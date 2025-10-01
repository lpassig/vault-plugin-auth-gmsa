# Simple gMSA Scheduled Task for Vault Authentication
# This script creates a minimal scheduled task for gMSA authentication

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$VaultUrl = "https://vault.local.lab:8200"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "GMSA SCHEDULED TASK SETUP" -ForegroundColor Cyan
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

# Create directories
$scriptDir = "C:\vault-client"
$logDir = "$scriptDir\logs"

if (-not (Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    Write-Host "✓ Created directory: $scriptDir" -ForegroundColor Green
}

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Write-Host "✓ Created directory: $logDir" -ForegroundColor Green
}

# Create the gMSA client script
$scriptPath = "$scriptDir\vault-gmsa-client.ps1"

$scriptContent = @'
# Vault gMSA Client for Scheduled Task
param([string]$VaultUrl = "https://vault.local.lab:8200")

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    $logFile = "C:\vault-client\logs\vault-gmsa-$(Get-Date -Format 'yyyy-MM-dd').log"
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}

Write-Log "Starting Vault gMSA authentication..." "INFO"
Write-Log "Current user: $(whoami)" "INFO"

# Bypass SSL for testing
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

try {
    Write-Log "Authenticating with Vault..." "INFO"
    
    $response = Invoke-RestMethod -Uri "$VaultUrl/v1/auth/kerberos/login" -Method Post -UseDefaultCredentials -UseBasicParsing -ErrorAction Stop
    
    if ($response.auth -and $response.auth.client_token) {
        Write-Log "SUCCESS: Authentication successful!" "SUCCESS"
        Write-Log "Token: $($response.auth.client_token)" "INFO"
        
        # Test token
        $headers = @{"X-Vault-Token" = $response.auth.client_token}
        $testResponse = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/health" -Headers $headers -UseBasicParsing
        Write-Log "SUCCESS: Token validation successful!" "SUCCESS"
        exit 0
    } else {
        Write-Log "ERROR: No token received" "ERROR"
        exit 1
    }
} catch {
    Write-Log "ERROR: Authentication failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
'@

Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8
Write-Host "✓ Created gMSA client script: $scriptPath" -ForegroundColor Green

# Create scheduled task
$taskName = "Vault-gMSA-Authentication"

try {
    # Remove existing task
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "✓ Removed existing task" -ForegroundColor Green
    }
    
    # Create new task
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 365)
    $principal = New-ScheduledTaskPrincipal -UserId $GMSAAccount -LogonType Password -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Vault gMSA Authentication"
    
    Write-Host "✓ Created scheduled task: $taskName" -ForegroundColor Green
    Write-Host "✓ Task runs under: $GMSAAccount" -ForegroundColor Green
    Write-Host "✓ Task runs every 5 minutes" -ForegroundColor Green
    
    # Test the task
    Write-Host ""
    Write-Host "Testing scheduled task..." -ForegroundColor Yellow
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 5
    
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
    Write-Host "Last Run Time: $($taskInfo.LastRunTime)" -ForegroundColor Gray
    Write-Host "Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
    
    if ($taskInfo.LastTaskResult -eq 0) {
        Write-Host "✓ Task executed successfully!" -ForegroundColor Green
    } else {
        Write-Host "⚠ Task execution had issues (Result: $($taskInfo.LastTaskResult))" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "SETUP COMPLETE!" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Manual commands:" -ForegroundColor Yellow
    Write-Host "  Start task: Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor White
    Write-Host "  View logs: Get-Content 'C:\vault-client\logs\vault-gmsa-*.log' -Tail 20" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host "❌ Error creating scheduled task: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}