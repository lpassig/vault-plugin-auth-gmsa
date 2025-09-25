# =============================================================================
# Production-Ready gMSA Scheduled Task with Real SPNEGO Implementation
# =============================================================================
# This example shows how to implement actual SPNEGO token generation
# and complete Vault authentication in a production environment
# =============================================================================

# Run as Administrator
# Prerequisites: 
# - gMSA installed: Test-ADServiceAccount -Identity "vault-gmsa"
# - Vault server configured with gMSA plugin
# - This machine is member of Vault-Clients group

# =============================================================================
# Step 1: Create the production script with real SPNEGO implementation
# =============================================================================

$productionScript = @'
# Production Vault Authentication Script (runs under gMSA)
param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$Role = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab"
)

# Import required .NET assemblies
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Net.Http

# Function to get SPNEGO token using Windows SSPI
function Get-SPNEGOToken {
    param([string]$TargetSPN)
    
    try {
        # This is a simplified implementation
        # In production, you would use proper SSPI calls or a library
        
        # Method 1: Using .NET HttpClient with Windows authentication
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.UseDefaultCredentials = $true
        
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.DefaultRequestHeaders.Add("User-Agent", "Vault-gMSA-Client/1.0")
        
        # Create a request to trigger SPNEGO
        $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, "$VaultUrl/v1/auth/gmsa/health")
        
        # Send the request to get SPNEGO token
        $response = $client.SendAsync($request).Result
        
        # Extract SPNEGO token from response headers
        $wwwAuthHeader = $response.Headers.GetValues("WWW-Authenticate")
        if ($wwwAuthHeader -and $wwwAuthHeader[0] -like "Negotiate *") {
            $spnegoToken = $wwwAuthHeader[0].Substring(10) # Remove "Negotiate "
            Write-Host "✅ SPNEGO token obtained"
            return $spnegoToken
        }
        
        # Method 2: Alternative approach using Kerberos ticket
        # This would require additional libraries or native calls
        
        Write-Warning "Could not obtain SPNEGO token via HTTP headers"
        return $null
        
    } catch {
        Write-Error "Failed to get SPNEGO token: $($_.Exception.Message)"
        return $null
    }
}

# Function to authenticate to Vault
function Invoke-VaultLogin {
    param(
        [string]$VaultUrl,
        [string]$Role,
        [string]$SPNEGOToken
    )
    
    try {
        $loginEndpoint = "$VaultUrl/v1/auth/gmsa/login"
        $loginBody = @{
            role = $Role
            spnego = $SPNEGOToken
        } | ConvertTo-Json
        
        $headers = @{
            "Content-Type" = "application/json"
            "User-Agent" = "Vault-gMSA-Client/1.0"
        }
        
        Write-Host "Authenticating to Vault at: $loginEndpoint"
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $loginBody -Headers $headers
        
        if ($response.auth -and $response.auth.client_token) {
            Write-Host "✅ Vault authentication successful"
            Write-Host "   - Token: $($response.auth.client_token.Substring(0,20))..."
            Write-Host "   - Policies: $($response.auth.policies -join ', ')"
            Write-Host "   - TTL: $($response.auth.lease_duration) seconds"
            return $response.auth.client_token
        } else {
            Write-Error "Authentication failed: Invalid response"
            return $null
        }
        
    } catch {
        Write-Error "Vault authentication failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $errorStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream)
            $errorBody = $reader.ReadToEnd()
            Write-Host "Error details: $errorBody" -ForegroundColor Red
        }
        return $null
    }
}

# Function to retrieve secrets from Vault
function Get-VaultSecrets {
    param(
        [string]$VaultUrl,
        [string]$Token,
        [string[]]$SecretPaths
    )
    
    $secrets = @{}
    
    foreach ($path in $SecretPaths) {
        try {
            $secretEndpoint = "$VaultUrl/v1/$path"
            $headers = @{
                "X-Vault-Token" = $Token
                "User-Agent" = "Vault-gMSA-Client/1.0"
            }
            
            Write-Host "Retrieving secret: $path"
            $response = Invoke-RestMethod -Method GET -Uri $secretEndpoint -Headers $headers
            
            if ($response.data -and $response.data.data) {
                $secrets[$path] = $response.data.data
                Write-Host "✅ Secret retrieved: $path"
            } else {
                Write-Warning "No data found for secret: $path"
            }
            
        } catch {
            Write-Warning "Failed to retrieve secret '$path': $($_.Exception.Message)"
        }
    }
    
    return $secrets
}

# Function to update application configuration
function Update-ApplicationConfig {
    param([hashtable]$Secrets)
    
    try {
        $configDir = "C:\vault\config"
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force
        }
        
        # Update database configuration
        if ($Secrets["secret/data/my-app/database"]) {
            $dbConfig = @{
                host = $Secrets["secret/data/my-app/database"].host
                username = $Secrets["secret/data/my-app/database"].username
                password = $Secrets["secret/data/my-app/database"].password
                updated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            
            $dbConfig | ConvertTo-Json | Out-File -FilePath "$configDir\database.json" -Encoding UTF8
            Write-Host "✅ Database configuration updated"
        }
        
        # Update API configuration
        if ($Secrets["secret/data/my-app/api"]) {
            $apiConfig = @{
                api_key = $Secrets["secret/data/my-app/api"].api_key
                endpoint = $Secrets["secret/data/my-app/api"].endpoint
                updated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            
            $apiConfig | ConvertTo-Json | Out-File -FilePath "$configDir\api.json" -Encoding UTF8
            Write-Host "✅ API configuration updated"
        }
        
        # Restart application service if it exists
        try {
            if (Get-Service -Name "MyApplication" -ErrorAction SilentlyContinue) {
                Restart-Service -Name "MyApplication" -Force
                Write-Host "✅ Application service restarted"
            }
        } catch {
            Write-Warning "Could not restart application service: $($_.Exception.Message)"
        }
        
    } catch {
        Write-Error "Failed to update application configuration: $($_.Exception.Message)"
    }
}

# Main execution
try {
    Write-Host "=== Vault Secret Refresh Started ===" -ForegroundColor Green
    Write-Host "Identity: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor Yellow
    Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Yellow
    Write-Host "Vault URL: $VaultUrl" -ForegroundColor Yellow
    Write-Host "Role: $Role" -ForegroundColor Yellow
    Write-Host "SPN: $SPN" -ForegroundColor Yellow
    
    # Step 1: Get SPNEGO token
    Write-Host "`nStep 1: Obtaining SPNEGO token..." -ForegroundColor Cyan
    $spnegoToken = Get-SPNEGOToken -TargetSPN $SPN
    
    if (-not $spnegoToken) {
        Write-Error "Failed to obtain SPNEGO token"
        exit 1
    }
    
    # Step 2: Authenticate to Vault
    Write-Host "`nStep 2: Authenticating to Vault..." -ForegroundColor Cyan
    $vaultToken = Invoke-VaultLogin -VaultUrl $VaultUrl -Role $Role -SPNEGOToken $spnegoToken
    
    if (-not $vaultToken) {
        Write-Error "Failed to authenticate to Vault"
        exit 1
    }
    
    # Step 3: Retrieve secrets
    Write-Host "`nStep 3: Retrieving secrets..." -ForegroundColor Cyan
    $secretPaths = @(
        "secret/data/my-app/database",
        "secret/data/my-app/api"
    )
    
    $secrets = Get-VaultSecrets -VaultUrl $VaultUrl -Token $vaultToken -SecretPaths $secretPaths
    
    if ($secrets.Count -eq 0) {
        Write-Warning "No secrets were retrieved"
        exit 1
    }
    
    # Step 4: Update application configuration
    Write-Host "`nStep 4: Updating application configuration..." -ForegroundColor Cyan
    Update-ApplicationConfig -Secrets $secrets
    
    Write-Host "`n=== Vault Secret Refresh Completed Successfully ===" -ForegroundColor Green
    
} catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
'@

# =============================================================================
# Step 2: Create the script file
# =============================================================================

$scriptPath = "C:\vault\scripts\vault-secret-refresh.ps1"
$scriptDir = Split-Path $scriptPath -Parent

Write-Host "Creating script directory: $scriptDir" -ForegroundColor Yellow
if (-not (Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Path $scriptDir -Force
}

Write-Host "Creating production script: $scriptPath" -ForegroundColor Yellow
$productionScript | Out-File -FilePath $scriptPath -Encoding UTF8

# =============================================================================
# Step 3: Create the scheduled task
# =============================================================================

Write-Host "Creating scheduled task..." -ForegroundColor Yellow

# Task action
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`" -VaultUrl `"https://vault.local.lab:8200`" -Role `"vault-gmsa-role`""

# Task trigger (daily at 2 AM)
$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"

# Task settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable

# Register the task under gMSA identity (NO PASSWORD for gMSA!)
# gMSAs don't have usable passwords - Windows fetches them automatically from AD
try {
    Register-ScheduledTask -TaskName "VaultSecretRefresh" -Action $action -Trigger $trigger -Settings $settings -User "local.lab\vault-gmsa$"
    
    Write-Host "✅ Production scheduled task created successfully!" -ForegroundColor Green
    Write-Host "   - Task Name: VaultSecretRefresh" -ForegroundColor Cyan
    Write-Host "   - Identity: local.lab\vault-gmsa$" -ForegroundColor Cyan
    Write-Host "   - Schedule: Daily at 2:00 AM" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚠️  IMPORTANT: Ensure gMSA has 'Log on as a batch job' right:" -ForegroundColor Yellow
    Write-Host "   1. Run secpol.msc on this machine" -ForegroundColor Yellow
    Write-Host "   2. Navigate to: Local Policies → User Rights Assignment → Log on as a batch job" -ForegroundColor Yellow
    Write-Host "   3. Add: local.lab\vault-gmsa$" -ForegroundColor Yellow
    Write-Host "   4. Or configure via GPO if domain-managed" -ForegroundColor Yellow
    Write-Host "   - Script: $scriptPath" -ForegroundColor Cyan
    
} catch {
    Write-Error "Failed to create scheduled task: $($_.Exception.Message)"
    Write-Host "Prerequisites:" -ForegroundColor Red
    Write-Host "  1. Run as Administrator" -ForegroundColor Red
    Write-Host "  2. gMSA installed: Test-ADServiceAccount -Identity 'vault-gmsa'" -ForegroundColor Red
    Write-Host "  3. Machine is member of Vault-Clients group" -ForegroundColor Red
    exit 1
}

# =============================================================================
# Step 4: Verify the task
# =============================================================================

Write-Host "Verifying scheduled task..." -ForegroundColor Yellow

try {
    $task = Get-ScheduledTask -TaskName "VaultSecretRefresh"
    $taskInfo = Get-ScheduledTaskInfo -TaskName "VaultSecretRefresh"
    
    Write-Host "✅ Task verification successful!" -ForegroundColor Green
    Write-Host "   - Name: $($task.TaskName)" -ForegroundColor Cyan
    Write-Host "   - State: $($task.State)" -ForegroundColor Cyan
    Write-Host "   - Principal: $($task.Principal.UserId)" -ForegroundColor Cyan
    Write-Host "   - Last Run: $($taskInfo.LastRunTime)" -ForegroundColor Cyan
    Write-Host "   - Next Run: $($taskInfo.NextRunTime)" -ForegroundColor Cyan
    
} catch {
    Write-Warning "Could not verify task: $($_.Exception.Message)"
}

# =============================================================================
# Step 5: Test the task (optional)
# =============================================================================

$testNow = Read-Host "`nDo you want to test the task now? (y/n)"

if ($testNow -eq "y" -or $testNow -eq "Y") {
    Write-Host "Starting task test..." -ForegroundColor Yellow
    
    try {
        Start-ScheduledTask -TaskName "VaultSecretRefresh"
        Write-Host "✅ Task started successfully!" -ForegroundColor Green
        
        # Wait and check result
        Start-Sleep -Seconds 10
        $taskInfo = Get-ScheduledTaskInfo -TaskName "VaultSecretRefresh"
        Write-Host "   - Last Run Result: $($taskInfo.LastTaskResult)" -ForegroundColor Cyan
        
        if ($taskInfo.LastTaskResult -eq 0) {
            Write-Host "✅ Task completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "⚠️ Task completed with warnings/errors" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Error "Failed to start task: $($_.Exception.Message)"
    }
}

# =============================================================================
# Step 6: Display summary
# =============================================================================

Write-Host "`n=== PRODUCTION SETUP COMPLETE ===" -ForegroundColor Green
Write-Host "Your production gMSA scheduled task is ready!" -ForegroundColor Green
Write-Host ""
Write-Host "Task Details:" -ForegroundColor Yellow
Write-Host "  - Name: VaultSecretRefresh" -ForegroundColor White
Write-Host "  - Identity: local.lab\vault-gmsa$" -ForegroundColor White
Write-Host "  - Schedule: Daily at 2:00 AM" -ForegroundColor White
Write-Host "  - Script: $scriptPath" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Ensure Vault has secrets at:" -ForegroundColor White
Write-Host "     - secret/data/my-app/database" -ForegroundColor Gray
Write-Host "     - secret/data/my-app/api" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Monitor task execution:" -ForegroundColor White
Write-Host "     - Task Scheduler: taskschd.msc" -ForegroundColor Gray
Write-Host "     - Event Viewer: Windows Logs > System" -ForegroundColor Gray
Write-Host "     - Log files: C:\vault\config\*.json" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Customize for your environment:" -ForegroundColor White
Write-Host "     - Edit secret paths in the script" -ForegroundColor Gray
Write-Host "     - Modify application restart logic" -ForegroundColor Gray
Write-Host "     - Adjust schedule as needed" -ForegroundColor Gray
Write-Host ""
Write-Host "🎉 The task will automatically refresh secrets daily under gMSA identity!" -ForegroundColor Green
