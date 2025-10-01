# Setup gMSA Scheduled Task for Vault Authentication
# This script creates a scheduled task that runs under the gMSA identity

param(
    [string]$TaskName = "Vault-gMSA-Authentication",
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$ScriptPath = "C:\vault-client\vault-client-app.ps1"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Setting up gMSA Scheduled Task" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Task Name: $TaskName" -ForegroundColor White
Write-Host "  gMSA Account: $GMSAAccount" -ForegroundColor White
Write-Host "  Script Path: $ScriptPath" -ForegroundColor White
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

# Step 1: Create the script directory
Write-Host "Step 1: Creating script directory..." -ForegroundColor Yellow
$scriptDir = Split-Path $ScriptPath -Parent
if (-not (Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    Write-Host "SUCCESS: Created directory $scriptDir" -ForegroundColor Green
} else {
    Write-Host "SUCCESS: Directory $scriptDir already exists" -ForegroundColor Green
}
Write-Host ""

# Step 2: Copy the script to the target location
Write-Host "Step 2: Copying script to target location..." -ForegroundColor Yellow
$currentScript = $MyInvocation.MyCommand.Path
$currentDir = Split-Path $currentScript -Parent
$sourceScript = Join-Path $currentDir "vault-client-app.ps1"

if (Test-Path $sourceScript) {
    Copy-Item $sourceScript $ScriptPath -Force
    Write-Host "SUCCESS: Script copied to $ScriptPath" -ForegroundColor Green
} else {
    Write-Host "ERROR: Source script not found: $sourceScript" -ForegroundColor Red
    Write-Host "Make sure vault-client-app.ps1 is in the same directory as this script" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Step 3: Remove existing task if it exists
Write-Host "Step 3: Removing existing task if it exists..." -ForegroundColor Yellow
try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "SUCCESS: Existing task removed" -ForegroundColor Green
} catch {
    Write-Host "INFO: No existing task to remove" -ForegroundColor Gray
}
Write-Host ""

# Step 4: Create the scheduled task
Write-Host "Step 4: Creating scheduled task..." -ForegroundColor Yellow
try {
    # Create task action
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    
    # Create task trigger (run once immediately for testing)
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
    
    # Create task principal (run under gMSA account)
    $principal = New-ScheduledTaskPrincipal -UserId $GMSAAccount -LogonType Password -RunLevel Highest
    
    # Create task settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    # Register the task
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Vault gMSA Authentication Task"
    
    Write-Host "SUCCESS: Scheduled task created successfully!" -ForegroundColor Green
    Write-Host "  Task Name: $TaskName" -ForegroundColor Gray
    Write-Host "  Account: $GMSAAccount" -ForegroundColor Gray
    Write-Host "  Script: $ScriptPath" -ForegroundColor Gray
    Write-Host "  Trigger: Run once in 1 minute" -ForegroundColor Gray
    
} catch {
    Write-Host "ERROR: Failed to create scheduled task" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 5: Verify the task was created
Write-Host "Step 5: Verifying task creation..." -ForegroundColor Yellow
try {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host "SUCCESS: Task verification complete" -ForegroundColor Green
    Write-Host "  Task State: $($task.State)" -ForegroundColor Gray
    Write-Host "  Last Run: $($task.LastRunTime)" -ForegroundColor Gray
    Write-Host "  Next Run: $($task.NextRunTime)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Task verification failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Wait 1 minute for the task to run automatically" -ForegroundColor White
Write-Host "2. Check the task history: Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo" -ForegroundColor White
Write-Host "3. Check the log file: C:\vault-client\config\vault-client.log" -ForegroundColor White
Write-Host "4. To run manually: Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host ""

Write-Host "TROUBLESHOOTING:" -ForegroundColor Yellow
Write-Host "1. If task fails, check Event Viewer > Windows Logs > System" -ForegroundColor White
Write-Host "2. Ensure gMSA account has 'Log on as a batch job' right" -ForegroundColor White
Write-Host "3. Verify SPN 'HTTP/vault.local.lab' is registered in AD" -ForegroundColor White
Write-Host "4. Check that keytab is configured on Vault server" -ForegroundColor White
Write-Host ""

Write-Host "MANUAL TEST:" -ForegroundColor Yellow
Write-Host "To test immediately, run:" -ForegroundColor White
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host ""
