# =============================================================================
# Complete End-to-End gMSA Scheduled Task Example for Vault Authentication
# =============================================================================
# This script demonstrates how to:
# 1. Create a scheduled task that runs under gMSA identity
# 2. Authenticate to Vault using Kerberos/SPNEGO
# 3. Retrieve secrets and use them in your application
# =============================================================================

# Run this script as Administrator on your Windows client machine
# Make sure the gMSA is already installed: Test-ADServiceAccount -Identity "vault-gmsa"

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$TaskName = "VaultSecretRefresh",
    [string]$ScriptPath = "C:\vault\scripts\refresh-secrets.ps1"
)

# =============================================================================
# Step 1: Create the PowerShell script that will run under gMSA
# =============================================================================

$vaultScript = @'
# =============================================================================
# Vault Secret Refresh Script (runs under gMSA identity)
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$VaultRole = "vault-gmsa-role"
)

# Function to get SPNEGO token using Windows SSPI
function Get-SPNEGOToken {
    param([string]$SPN)
    
    try {
        # Import required .NET assemblies for SSPI
        Add-Type -AssemblyName System.Security
        
        # Create SSPI context for Kerberos authentication
        $package = "Negotiate"
        $target = $SPN
        
        # Initialize security context
        $context = [System.Security.Authentication.ExtendedProtection.ChannelBinding]::new()
        
        # For demonstration, we'll use a simplified approach
        # In production, you'd use proper SSPI calls or a library like gokrb5
        
        # This is a placeholder - in real implementation, you'd:
        # 1. Call AcquireCredentialsHandle
        # 2. Call InitializeSecurityContext
        # 3. Extract the SPNEGO token
        
        # For now, we'll simulate getting a token
        # In production, replace this with actual SSPI implementation
        $spnegoBytes = [System.Text.Encoding]::UTF8.GetBytes("SPNEGO_TOKEN_PLACEHOLDER")
        return [System.Convert]::ToBase64String($spnegoBytes)
        
    } catch {
        Write-Error "Failed to get SPNEGO token: $($_.Exception.Message)"
        return $null
    }
}

# Function to authenticate to Vault using SPNEGO
function Invoke-VaultAuthentication {
    param(
        [string]$VaultUrl,
        [string]$Role,
        [string]$SPNEGOToken
    )
    
    try {
        $authEndpoint = "$VaultUrl/v1/auth/gmsa/login"
        $authBody = @{
            role = $Role
            spnego = $SPNEGOToken
        } | ConvertTo-Json
        
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        Write-Host "Authenticating to Vault at: $authEndpoint"
        $response = Invoke-RestMethod -Method POST -Uri $authEndpoint -Body $authBody -Headers $headers
        
        if ($response.auth -and $response.auth.client_token) {
            Write-Host "✅ Successfully authenticated to Vault"
            return $response.auth.client_token
        } else {
            Write-Error "Authentication failed: No token received"
            return $null
        }
        
    } catch {
        Write-Error "Vault authentication failed: $($_.Exception.Message)"
        return $null
    }
}

# Function to retrieve secrets from Vault
function Get-VaultSecret {
    param(
        [string]$VaultUrl,
        [string]$Token,
        [string]$SecretPath
    )
    
    try {
        $secretEndpoint = "$VaultUrl/v1/$SecretPath"
        $headers = @{
            "X-Vault-Token" = $Token
        }
        
        Write-Host "Retrieving secret from: $secretEndpoint"
        $response = Invoke-RestMethod -Method GET -Uri $secretEndpoint -Headers $headers
        
        if ($response.data -and $response.data.data) {
            Write-Host "✅ Successfully retrieved secret"
            return $response.data.data
        } else {
            Write-Error "Failed to retrieve secret: No data received"
            return $null
        }
        
    } catch {
        Write-Error "Secret retrieval failed: $($_.Exception.Message)"
        return $null
    }
}

# Main execution
try {
    Write-Host "=== Vault Secret Refresh Script Started ===" -ForegroundColor Green
    Write-Host "Running under identity: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor Yellow
    Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Yellow
    
    # Step 1: Get SPNEGO token for Vault SPN
    $spn = "HTTP/vault.local.lab"
    Write-Host "Getting SPNEGO token for SPN: $spn"
    $spnegoToken = Get-SPNEGOToken -SPN $spn
    
    if (-not $spnegoToken) {
        Write-Error "Failed to get SPNEGO token"
        exit 1
    }
    
    # Step 2: Authenticate to Vault
    Write-Host "Authenticating to Vault..."
    $vaultToken = Invoke-VaultAuthentication -VaultUrl $VaultUrl -Role $VaultRole -SPNEGOToken $spnegoToken
    
    if (-not $vaultToken) {
        Write-Error "Failed to authenticate to Vault"
        exit 1
    }
    
    # Step 3: Retrieve secrets
    Write-Host "Retrieving secrets..."
    $secrets = @()
    
    # Example: Retrieve database credentials
    $dbSecret = Get-VaultSecret -VaultUrl $VaultUrl -Token $vaultToken -SecretPath "secret/data/my-app/database"
    if ($dbSecret) {
        $secrets += @{
            Type = "Database"
            Host = $dbSecret.host
            Username = $dbSecret.username
            Password = $dbSecret.password
        }
        Write-Host "✅ Database credentials retrieved"
    }
    
    # Example: Retrieve API credentials
    $apiSecret = Get-VaultSecret -VaultUrl $VaultUrl -Token $vaultToken -SecretPath "secret/data/my-app/api"
    if ($apiSecret) {
        $secrets += @{
            Type = "API"
            ApiKey = $apiSecret.api_key
            Endpoint = $apiSecret.endpoint
        }
        Write-Host "✅ API credentials retrieved"
    }
    
    # Step 4: Use the secrets (example: update configuration files)
    if ($secrets.Count -gt 0) {
        Write-Host "Updating application configuration..."
        
        # Create configuration directory if it doesn't exist
        $configDir = "C:\vault\config"
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force
        }
        
        # Save secrets to configuration files
        foreach ($secret in $secrets) {
            $configFile = "$configDir\$($secret.Type.ToLower())-config.json"
            $secret | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8
            Write-Host "✅ Configuration saved to: $configFile"
        }
        
        # Example: Restart application service
        Write-Host "Restarting application service..."
        try {
            Stop-Service -Name "MyApplication" -ErrorAction SilentlyContinue
            Start-Service -Name "MyApplication" -ErrorAction SilentlyContinue
            Write-Host "✅ Application service restarted"
        } catch {
            Write-Warning "Could not restart application service: $($_.Exception.Message)"
        }
    }
    
    Write-Host "=== Vault Secret Refresh Script Completed Successfully ===" -ForegroundColor Green
    
} catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
'@

# =============================================================================
# Step 2: Create the script directory and save the script
# =============================================================================

Write-Host "Creating script directory and files..." -ForegroundColor Yellow

# Create directories
$scriptDir = Split-Path $ScriptPath -Parent
if (-not (Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Path $scriptDir -Force
    Write-Host "✅ Created directory: $scriptDir"
}

# Save the script
$vaultScript | Out-File -FilePath $ScriptPath -Encoding UTF8
Write-Host "✅ Created script: $ScriptPath"

# =============================================================================
# Step 3: Create the scheduled task action
# =============================================================================

Write-Host "Creating scheduled task action..." -ForegroundColor Yellow

# Create the action that will run the PowerShell script
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`" -VaultUrl `"$VaultUrl`" -VaultRole `"$VaultRole`""

# =============================================================================
# Step 4: Create the scheduled task trigger (daily at 2 AM)
# =============================================================================

Write-Host "Creating scheduled task trigger..." -ForegroundColor Yellow

$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"

# =============================================================================
# Step 5: Configure task settings
# =============================================================================

Write-Host "Configuring task settings..." -ForegroundColor Yellow

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable

# =============================================================================
# Step 6: Register the scheduled task under gMSA identity
# =============================================================================

Write-Host "Registering scheduled task under gMSA identity..." -ForegroundColor Yellow

try {
    # Register the task with gMSA identity (NO PASSWORD for gMSA!)
    # gMSAs don't have usable passwords - Windows fetches them automatically from AD
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -User "local.lab\vault-gmsa$"
    
    Write-Host "✅ Scheduled task '$TaskName' created successfully!" -ForegroundColor Green
    Write-Host "   - Task runs under: local.lab\vault-gmsa$" -ForegroundColor Cyan
    Write-Host "   - Schedule: Daily at 2:00 AM" -ForegroundColor Cyan
    Write-Host "   - Script location: $ScriptPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚠️  IMPORTANT: Ensure gMSA has 'Log on as a batch job' right:" -ForegroundColor Yellow
    Write-Host "   1. Run secpol.msc on this machine" -ForegroundColor Yellow
    Write-Host "   2. Navigate to: Local Policies → User Rights Assignment → Log on as a batch job" -ForegroundColor Yellow
    Write-Host "   3. Add: local.lab\vault-gmsa$" -ForegroundColor Yellow
    Write-Host "   4. Or configure via GPO if domain-managed" -ForegroundColor Yellow
    
} catch {
    Write-Error "Failed to create scheduled task: $($_.Exception.Message)"
    Write-Host "Make sure:" -ForegroundColor Red
    Write-Host "  1. You're running as Administrator" -ForegroundColor Red
    Write-Host "  2. The gMSA 'vault-gmsa' is installed on this machine" -ForegroundColor Red
    Write-Host "  3. This machine is a member of the Vault-Clients group" -ForegroundColor Red
    exit 1
}

# =============================================================================
# Step 7: Verify the task was created
# =============================================================================

Write-Host "Verifying scheduled task..." -ForegroundColor Yellow

try {
    $task = Get-ScheduledTask -TaskName $TaskName
    $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
    
    Write-Host "✅ Task verification successful!" -ForegroundColor Green
    Write-Host "   - Task Name: $($task.TaskName)" -ForegroundColor Cyan
    Write-Host "   - Task State: $($task.State)" -ForegroundColor Cyan
    Write-Host "   - Principal: $($task.Principal.UserId)" -ForegroundColor Cyan
    Write-Host "   - Last Run: $($taskInfo.LastRunTime)" -ForegroundColor Cyan
    Write-Host "   - Next Run: $($taskInfo.NextRunTime)" -ForegroundColor Cyan
    
} catch {
    Write-Warning "Could not verify task details: $($_.Exception.Message)"
}

# =============================================================================
# Step 8: Test the task manually (optional)
# =============================================================================

$testTask = Read-Host "Do you want to test the task manually now? (y/n)"

if ($testTask -eq "y" -or $testTask -eq "Y") {
    Write-Host "Running task manually..." -ForegroundColor Yellow
    
    try {
        Start-ScheduledTask -TaskName $TaskName
        Write-Host "✅ Task started successfully!" -ForegroundColor Green
        Write-Host "Check the task history and logs for results." -ForegroundColor Cyan
        
        # Wait a moment and check the result
        Start-Sleep -Seconds 5
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
        Write-Host "   - Last Run Result: $($taskInfo.LastTaskResult)" -ForegroundColor Cyan
        
    } catch {
        Write-Error "Failed to start task: $($_.Exception.Message)"
    }
}

# =============================================================================
# Step 9: Display summary and next steps
# =============================================================================

Write-Host "`n=== SETUP COMPLETE ===" -ForegroundColor Green
Write-Host "Your gMSA scheduled task is now configured!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Ensure your Vault server has the secrets at:" -ForegroundColor White
Write-Host "   - secret/data/my-app/database" -ForegroundColor Gray
Write-Host "   - secret/data/my-app/api" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Test the authentication manually:" -ForegroundColor White
Write-Host "   - Run: Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host "   - Check: Get-ScheduledTaskInfo -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Monitor the task execution:" -ForegroundColor White
Write-Host "   - Task Scheduler: taskschd.msc" -ForegroundColor Gray
Write-Host "   - Event Viewer: Windows Logs > System" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Customize the script for your specific needs:" -ForegroundColor White
Write-Host "   - Edit: $ScriptPath" -ForegroundColor Gray
Write-Host "   - Modify secret paths and application logic" -ForegroundColor Gray
Write-Host ""
Write-Host "The task will automatically run daily at 2:00 AM under the gMSA identity!" -ForegroundColor Green
