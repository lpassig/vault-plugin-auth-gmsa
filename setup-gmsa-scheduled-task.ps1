# Create Scheduled Task for gMSA Vault Authentication
# This script creates a scheduled task that runs under the gMSA identity

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$TaskName = "Vault-gMSA-Authentication",
    [string]$ScriptPath = "C:\vault-client\vault-client-gmsa.ps1",
    [string]$LogPath = "C:\vault-client\logs",
    [switch]$CreateTask = $false,
    [switch]$TestTask = $false,
    [switch]$RemoveTask = $false
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "GMSA SCHEDULED TASK MANAGEMENT" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "SUCCESS: Running as Administrator" -ForegroundColor Green
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  gMSA Account: $GMSAAccount" -ForegroundColor White
Write-Host "  Vault URL: $VaultUrl" -ForegroundColor White
Write-Host "  Task Name: $TaskName" -ForegroundColor White
Write-Host "  Script Path: $ScriptPath" -ForegroundColor White
Write-Host "  Log Path: $LogPath" -ForegroundColor White
Write-Host ""

# Function to create directories
function New-Directories {
    Write-Host "Creating directories..." -ForegroundColor Yellow
    
    $directories = @(
        "C:\vault-client",
        "C:\vault-client\config",
        "C:\vault-client\logs",
        "C:\vault-client\scripts"
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "✓ Created directory: $dir" -ForegroundColor Green
        } else {
            Write-Host "✓ Directory exists: $dir" -ForegroundColor Green
        }
    }
}

# Function to create the gMSA client script
function New-GMSAClientScript {
    Write-Host ""
    Write-Host "Creating gMSA client script..." -ForegroundColor Yellow
    
    $scriptContent = @'
# Vault gMSA Client for Scheduled Task Execution
# This script runs under gMSA identity in a scheduled task

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$LogPath = "C:\vault-client\logs"
)

# Create log directory if it doesn't exist
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "INFO" { Write-Host $logMessage -ForegroundColor Cyan }
        default { Write-Host $logMessage }
    }
    
    $logFile = "$LogPath\vault-gmsa-$(Get-Date -Format 'yyyy-MM-dd').log"
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}

Write-Log "Starting Vault gMSA authentication..." -Level "INFO"
Write-Log "Script version: 1.0 (Scheduled Task gMSA)" -Level "INFO"
Write-Log "Current user: $(whoami)" -Level "INFO"
Write-Log "Vault URL: $VaultUrl" -Level "INFO"

# Bypass SSL certificate validation for testing
Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint svcPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

# Function to authenticate with Vault using Kerberos
function Invoke-VaultAuthentication {
    param(
        [string]$VaultUrl
    )
    
    try {
        Write-Log "Authenticating with Vault using Kerberos..." -Level "INFO"
        
        # Method 1: Try Invoke-RestMethod with UseDefaultCredentials
        try {
            Write-Log "Method 1: Using Invoke-RestMethod with UseDefaultCredentials..." -Level "INFO"
            
            $response = Invoke-RestMethod `
                -Uri "$VaultUrl/v1/auth/kerberos/login" `
                -Method Post `
                -UseDefaultCredentials `
                -UseBasicParsing `
                -ErrorAction Stop
            
            if ($response.auth -and $response.auth.client_token) {
                Write-Log "SUCCESS: Vault authentication successful!" -Level "SUCCESS"
                Write-Log "Client token: $($response.auth.client_token)" -Level "INFO"
                Write-Log "Token TTL: $($response.auth.lease_duration) seconds" -Level "INFO"
                return $response.auth.client_token
            }
        } catch {
            Write-Log "Method 1 failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 2: Try WebRequest with UseDefaultCredentials
        try {
            Write-Log "Method 2: Using WebRequest with UseDefaultCredentials..." -Level "INFO"
            
            $request = [System.Net.WebRequest]::Create("$VaultUrl/v1/auth/kerberos/login")
            $request.Method = "POST"
            $request.UseDefaultCredentials = $true
            $request.PreAuthenticate = $true
            $request.UserAgent = "Vault-gMSA-Client/1.0"
            
            $response = $request.GetResponse()
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            $response.Close()
            
            $authResponse = $responseBody | ConvertFrom-Json
            if ($authResponse.auth -and $authResponse.auth.client_token) {
                Write-Log "SUCCESS: Vault authentication successful with WebRequest!" -Level "SUCCESS"
                Write-Log "Client token: $($authResponse.auth.client_token)" -Level "INFO"
                return $authResponse.auth.client_token
            }
        } catch {
            Write-Log "Method 2 failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 3: Try with curl if available
        try {
            Write-Log "Method 3: Using curl for SPNEGO authentication..." -Level "INFO"
            
            if (Get-Command curl -ErrorAction SilentlyContinue) {
                $curlOutput = curl --negotiate --user : -v "$VaultUrl/v1/sys/health" 2>&1 | Out-String
                
                if ($curlOutput -match "Authorization: Negotiate ([A-Za-z0-9+/=]+)") {
                    $spnegoToken = $matches[1]
                    Write-Log "SUCCESS: SPNEGO token generated via curl!" -Level "SUCCESS"
                    
                    $body = @{
                        spnego = $spnegoToken
                    } | ConvertTo-Json
                    
                    $response = Invoke-RestMethod `
                        -Uri "$VaultUrl/v1/auth/kerberos/login" `
                        -Method Post `
                        -Body $body `
                        -ContentType "application/json" `
                        -UseBasicParsing
                    
                    if ($response.auth -and $response.auth.client_token) {
                        Write-Log "SUCCESS: Vault authentication successful via curl!" -Level "SUCCESS"
                        Write-Log "Client token: $($response.auth.client_token)" -Level "INFO"
                        return $response.auth.client_token
                    }
                }
            }
        } catch {
            Write-Log "Method 3 failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        Write-Log "ERROR: All authentication methods failed" -Level "ERROR"
        return $null
        
    } catch {
        Write-Log "ERROR: Authentication process failed: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# Function to test token usage
function Test-TokenUsage {
    param(
        [string]$VaultUrl,
        [string]$Token
    )
    
    try {
        Write-Log "Testing token usage..." -Level "INFO"
        
        $headers = @{
            "X-Vault-Token" = $Token
        }
        
        $response = Invoke-RestMethod `
            -Uri "$VaultUrl/v1/sys/health" `
            -Method Get `
            -Headers $headers `
            -UseBasicParsing
        
        Write-Log "SUCCESS: Token is valid and working!" -Level "SUCCESS"
        Write-Log "Vault Status: $($response.status)" -Level "INFO"
        return $true
    } catch {
        Write-Log "ERROR: Token validation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Main execution
try {
    Write-Log "Starting Vault gMSA Client Application..." -Level "INFO"
    
    # Authenticate to Vault
    Write-Log "Step 1: Authenticating to Vault..." -Level "INFO"
    $vaultToken = Invoke-VaultAuthentication -VaultUrl $VaultUrl
    
    if (-not $vaultToken) {
        Write-Log "ERROR: Failed to authenticate to Vault" -Level "ERROR"
        Write-Log "Application cannot continue without valid authentication" -Level "ERROR"
        exit 1
    }
    
    Write-Log "SUCCESS: Vault authentication completed" -Level "SUCCESS"
    
    # Test token usage
    Write-Log "Step 2: Testing token usage..." -Level "INFO"
    $tokenValid = Test-TokenUsage -VaultUrl $VaultUrl -Token $vaultToken
    
    if ($tokenValid) {
        Write-Log "SUCCESS: Vault gMSA Client Application completed successfully!" -Level "SUCCESS"
        Write-Log "Authentication is working properly under gMSA identity" -Level "SUCCESS"
        exit 0
    } else {
        Write-Log "ERROR: Token validation failed" -Level "ERROR"
        exit 1
    }
    
} catch {
    Write-Log "ERROR: Application failed: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}
'@

    Set-Content -Path $ScriptPath -Value $scriptContent -Encoding UTF8
    Write-Host "✓ Created gMSA client script: $ScriptPath" -ForegroundColor Green
}

# Function to create the scheduled task
function New-ScheduledTask {
    Write-Host ""
    Write-Host "Creating scheduled task..." -ForegroundColor Yellow
    
    try {
        # Remove existing task if it exists
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "✓ Removed existing task: $TaskName" -ForegroundColor Green
        }
        
        # Create action
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
        
        # Create trigger (run every 5 minutes)
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 365)
        
        # Create principal for gMSA
        $principal = New-ScheduledTaskPrincipal -UserId $GMSAAccount -LogonType Password -RunLevel Highest
        
        # Create settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        
        # Register the task
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Vault gMSA Authentication Task"
        
        Write-Host "✓ Created scheduled task: $TaskName" -ForegroundColor Green
        Write-Host "✓ Task runs under gMSA account: $GMSAAccount" -ForegroundColor Green
        Write-Host "✓ Task runs every 5 minutes" -ForegroundColor Green
        
        return $true
    } catch {
        Write-Host "❌ Error creating scheduled task: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to test the scheduled task
function Test-ScheduledTask {
    Write-Host ""
    Write-Host "Testing scheduled task..." -ForegroundColor Yellow
    
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Host "❌ Scheduled task not found: $TaskName" -ForegroundColor Red
            return $false
        }
        
        Write-Host "✓ Scheduled task found: $TaskName" -ForegroundColor Green
        Write-Host "  State: $($task.State)" -ForegroundColor Gray
        Write-Host "  Principal: $($task.Principal.UserId)" -ForegroundColor Gray
        
        # Start the task manually
        Write-Host "Starting task manually for testing..." -ForegroundColor Cyan
        Start-ScheduledTask -TaskName $TaskName
        
        # Wait a moment for execution
        Start-Sleep -Seconds 5
        
        # Check task history
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
        Write-Host "  Last Run Time: $($taskInfo.LastRunTime)" -ForegroundColor Gray
        Write-Host "  Last Task Result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
        
        if ($taskInfo.LastTaskResult -eq 0) {
            Write-Host "✓ Task executed successfully!" -ForegroundColor Green
        } else {
            Write-Host "⚠ Task execution had issues (Result: $($taskInfo.LastTaskResult))" -ForegroundColor Yellow
        }
        
        return $true
    } catch {
        Write-Host "❌ Error testing scheduled task: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to remove the scheduled task
function Remove-ScheduledTask {
    Write-Host ""
    Write-Host "Removing scheduled task..." -ForegroundColor Yellow
    
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "✓ Removed scheduled task: $TaskName" -ForegroundColor Green
        } else {
            Write-Host "⚠ Scheduled task not found: $TaskName" -ForegroundColor Yellow
        }
        return $true
    } catch {
        Write-Host "❌ Error removing scheduled task: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main execution
function Main {
    if ($RemoveTask) {
        Remove-ScheduledTask
        return
    }
    
    if ($CreateTask) {
        New-Directories
        New-GMSAClientScript
        New-ScheduledTask
    }
    
    if ($TestTask) {
        Test-ScheduledTask
    }
    
    if (-not $CreateTask -and -not $TestTask -and -not $RemoveTask) {
        # Default: Create and test
        New-Directories
        New-GMSAClientScript
        $taskCreated = New-ScheduledTask
        
        if ($taskCreated) {
            Start-Sleep -Seconds 2
            Test-ScheduledTask
        }
    }
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "SCHEDULED TASK MANAGEMENT COMPLETE" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Manual commands:" -ForegroundColor Yellow
    Write-Host "  Start task: Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
    Write-Host "  Stop task: Stop-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
    Write-Host "  View logs: Get-Content '$LogPath\vault-gmsa-*.log' -Tail 50" -ForegroundColor White
    Write-Host ""
}

# Run main function
Main