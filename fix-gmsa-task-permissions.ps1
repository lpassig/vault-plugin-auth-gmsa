# Fix gMSA Scheduled Task Permissions
# This script fixes common permission issues with gMSA scheduled tasks

param(
    [string]$TaskName = "Vault-gMSA-Authentication",
    [string]$GMSAAccount = "LOCAL\vault-gmsa$"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Fixing gMSA Scheduled Task Permissions" -ForegroundColor Cyan
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

# Step 1: Check current task configuration
Write-Host "Step 1: Checking current task configuration..." -ForegroundColor Yellow
try {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host "Current task configuration:" -ForegroundColor White
    Write-Host "  User: $($task.Principal.UserId)" -ForegroundColor Gray
    Write-Host "  Logon Type: $($task.Principal.LogonType)" -ForegroundColor Gray
    Write-Host "  Run Level: $($task.Principal.RunLevel)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Task '$TaskName' not found" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 2: Grant "Log on as a batch job" right to gMSA
Write-Host "Step 2: Granting 'Log on as a batch job' right to gMSA..." -ForegroundColor Yellow
try {
    # Use secedit to grant the right
    $seceditCmd = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeBatchLogonRight = $GMSAAccount
"@
    
    $seceditFile = "$env:TEMP\gmsa_batch_logon.inf"
    $seceditCmd | Out-File -FilePath $seceditFile -Encoding ASCII
    
    $result = secedit /configure /db "$env:TEMP\gmsa_batch_logon.sdb" /cfg $seceditFile /areas USER_RIGHTS
    Write-Host "SUCCESS: Granted 'Log on as a batch job' right to $GMSAAccount" -ForegroundColor Green
    
    # Clean up temp files
    Remove-Item $seceditFile -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\gmsa_batch_logon.sdb" -Force -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "WARNING: Could not grant batch logon right via secedit" -ForegroundColor Yellow
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "MANUAL STEP: Grant 'Log on as a batch job' right manually:" -ForegroundColor Yellow
    Write-Host "  1. Run 'secpol.msc'" -ForegroundColor Gray
    Write-Host "  2. Go to Local Policies > User Rights Assignment" -ForegroundColor Gray
    Write-Host "  3. Find 'Log on as a batch job'" -ForegroundColor Gray
    Write-Host "  4. Add $GMSAAccount" -ForegroundColor Gray
}
Write-Host ""

# Step 3: Update task configuration to use Service Account logon type
Write-Host "Step 3: Updating task configuration..." -ForegroundColor Yellow
try {
    # Remove existing task
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    
    # Get the script path
    $scriptPath = "C:\vault-client\vault-client-app.ps1"
    
    # Create new task with Service Account logon type
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
    $principal = New-ScheduledTaskPrincipal -UserId $GMSAAccount -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Vault gMSA Authentication Task"
    
    Write-Host "SUCCESS: Task updated with ServiceAccount logon type" -ForegroundColor Green
    
} catch {
    Write-Host "ERROR: Failed to update task configuration" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 4: Verify the updated task
Write-Host "Step 4: Verifying updated task..." -ForegroundColor Yellow
try {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host "Updated task configuration:" -ForegroundColor White
    Write-Host "  User: $($task.Principal.UserId)" -ForegroundColor Gray
    Write-Host "  Logon Type: $($task.Principal.LogonType)" -ForegroundColor Gray
    Write-Host "  Run Level: $($task.Principal.RunLevel)" -ForegroundColor Gray
    Write-Host "  State: $($task.State)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Cannot verify updated task" -ForegroundColor Red
}
Write-Host ""

# Step 5: Test the task immediately
Write-Host "Step 5: Testing task execution..." -ForegroundColor Yellow
try {
    Write-Host "Starting task manually..." -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $TaskName
    
    # Wait a moment for the task to start
    Start-Sleep -Seconds 5
    
    # Check task status
    $taskInfo = Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
    Write-Host "Task execution result:" -ForegroundColor White
    Write-Host "  Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
    Write-Host "  Last Run Time: $($taskInfo.LastRunTime)" -ForegroundColor Gray
    
    if ($taskInfo.LastTaskResult -eq 0) {
        Write-Host "SUCCESS: Task executed successfully!" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Task result: $($taskInfo.LastTaskResult)" -ForegroundColor Yellow
        Write-Host "Check the log file for details: C:\vault-client\config\vault-client.log" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Failed to test task execution" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Permission Fix Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Check the log file: C:\vault-client\config\vault-client.log" -ForegroundColor White
Write-Host "2. Run: .\check-gmsa-task-status.ps1" -ForegroundColor White
Write-Host "3. If still failing, check Event Viewer for detailed errors" -ForegroundColor White
Write-Host ""

Write-Host "COMMON ERROR CODES:" -ForegroundColor Yellow
Write-Host "  0 = Success" -ForegroundColor White
Write-Host "  267011 = Account/service mismatch (fixed by ServiceAccount logon type)" -ForegroundColor White
Write-Host "  267014 = Task failed to start (check batch logon right)" -ForegroundColor White
Write-Host "  2147942402 = Access denied (check permissions)" -ForegroundColor White
Write-Host ""
