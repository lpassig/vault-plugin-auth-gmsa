# Create Debug Scheduled Task for gMSA Authentication
# This script creates a scheduled task to run debug-gmsa-auth.ps1 under gMSA identity

param(
    [string]$TaskName = "Vault-gMSA-Debug",
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$ScriptPath = "C:\vault-client\debug-gmsa-auth.ps1"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Creating Debug Scheduled Task for gMSA" -ForegroundColor Cyan
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
Write-Host "  Task Name: $TaskName" -ForegroundColor White
Write-Host "  gMSA Account: $GMSAAccount" -ForegroundColor White
Write-Host "  Script Path: $ScriptPath" -ForegroundColor White
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

# Step 2: Copy the debug script to the target location
Write-Host "Step 2: Copying debug script to target location..." -ForegroundColor Yellow
$currentScript = $MyInvocation.MyCommand.Path
$currentDir = Split-Path $currentScript -Parent
$sourceScript = Join-Path $currentDir "debug-gmsa-auth.ps1"

if (Test-Path $sourceScript) {
    Copy-Item $sourceScript $ScriptPath -Force
    Write-Host "SUCCESS: Debug script copied to $ScriptPath" -ForegroundColor Green
} else {
    Write-Host "ERROR: Source script not found: $sourceScript" -ForegroundColor Red
    Write-Host "Make sure debug-gmsa-auth.ps1 is in the same directory as this script" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Step 3: Remove existing debug task if it exists
Write-Host "Step 3: Removing existing debug task if it exists..." -ForegroundColor Yellow
try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "SUCCESS: Existing debug task removed" -ForegroundColor Green
} catch {
    Write-Host "INFO: No existing debug task to remove" -ForegroundColor Gray
}
Write-Host ""

# Step 4: Create the debug scheduled task
Write-Host "Step 4: Creating debug scheduled task..." -ForegroundColor Yellow
try {
    # Create task action
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    
    # Create task trigger (run once immediately for testing)
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
    
    # Create task principal (run under gMSA account)
    $principal = New-ScheduledTaskPrincipal -UserId $GMSAAccount -LogonType ServiceAccount -RunLevel Highest
    
    # Create task settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    # Register the task
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Vault gMSA Debug Task"
    
    Write-Host "SUCCESS: Debug scheduled task created successfully!" -ForegroundColor Green
    Write-Host "  Task Name: $TaskName" -ForegroundColor Gray
    Write-Host "  Account: $GMSAAccount" -ForegroundColor Gray
    Write-Host "  Script: $ScriptPath" -ForegroundColor Gray
    Write-Host "  Trigger: Run once in 1 minute" -ForegroundColor Gray
    
} catch {
    Write-Host "ERROR: Failed to create debug scheduled task" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 5: Verify the task was created
Write-Host "Step 5: Verifying debug task creation..." -ForegroundColor Yellow
try {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host "SUCCESS: Debug task verification complete" -ForegroundColor Green
    Write-Host "  Task State: $($task.State)" -ForegroundColor Gray
    Write-Host "  Last Run: $($task.LastRunTime)" -ForegroundColor Gray
    Write-Host "  Next Run: $($task.NextRunTime)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Debug task verification failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 6: Test the debug task immediately
Write-Host "Step 6: Testing debug task execution..." -ForegroundColor Yellow
try {
    Write-Host "Starting debug task manually..." -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $TaskName
    
    # Wait a moment for the task to start
    Start-Sleep -Seconds 10
    
    # Check task status
    $taskInfo = Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
    Write-Host "Debug task execution result:" -ForegroundColor White
    Write-Host "  Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
    Write-Host "  Last Run Time: $($taskInfo.LastRunTime)" -ForegroundColor Gray
    
    if ($taskInfo.LastTaskResult -eq 0) {
        Write-Host "SUCCESS: Debug task executed successfully!" -ForegroundColor Green
        Write-Host "Check the output above for authentication details" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Debug task result: $($taskInfo.LastTaskResult)" -ForegroundColor Yellow
        Write-Host "Check Event Viewer for detailed error information" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Failed to test debug task execution" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Debug Task Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "WHAT HAPPENS NEXT:" -ForegroundColor Yellow
Write-Host "1. The debug task will run under LOCAL\vault-gmsa$ identity" -ForegroundColor White
Write-Host "2. It will show detailed authentication diagnostics" -ForegroundColor White
Write-Host "3. You'll see exactly what's failing in the authentication process" -ForegroundColor White
Write-Host ""

Write-Host "MANUAL COMMANDS:" -ForegroundColor Yellow
Write-Host "To run debug task manually:" -ForegroundColor White
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host ""
Write-Host "To check debug task status:" -ForegroundColor White
Write-Host "  Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo" -ForegroundColor Gray
Write-Host ""
Write-Host "To remove debug task when done:" -ForegroundColor White
Write-Host "  Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" -ForegroundColor Gray
Write-Host ""

Write-Host "EXPECTED OUTPUT:" -ForegroundColor Yellow
Write-Host "The debug task will show:" -ForegroundColor White
Write-Host "  - Current identity (should be LOCAL\vault-gmsa$)" -ForegroundColor Gray
Write-Host "  - Kerberos tickets available" -ForegroundColor Gray
Write-Host "  - Vault connectivity status" -ForegroundColor Gray
Write-Host "  - Authentication test results" -ForegroundColor Gray
Write-Host "  - Secret retrieval test" -ForegroundColor Gray
Write-Host ""
