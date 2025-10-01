# Check gMSA Scheduled Task Status and Logs
# This script helps troubleshoot the gMSA scheduled task

param(
    [string]$TaskName = "Vault-gMSA-Authentication",
    [string]$LogPath = "C:\vault-client\config\vault-client.log"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "gMSA Scheduled Task Status Check" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "WARNING: Not running as Administrator - some checks may fail" -ForegroundColor Yellow
} else {
    Write-Host "SUCCESS: Running as Administrator" -ForegroundColor Green
}
Write-Host ""

# Step 1: Check if task exists
Write-Host "1. Scheduled Task Status:" -ForegroundColor Yellow
try {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host "SUCCESS: Task '$TaskName' exists" -ForegroundColor Green
    Write-Host "  State: $($task.State)" -ForegroundColor Gray
    Write-Host "  Enabled: $($task.Settings.Enabled)" -ForegroundColor Gray
    Write-Host "  Run Level: $($task.Principal.RunLevel)" -ForegroundColor Gray
    Write-Host "  User: $($task.Principal.UserId)" -ForegroundColor Gray
    Write-Host "  Logon Type: $($task.Principal.LogonType)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Task '$TaskName' not found" -ForegroundColor Red
    Write-Host "Run setup-gmsa-scheduled-task.ps1 first" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Step 2: Get task execution info
Write-Host "2. Task Execution History:" -ForegroundColor Yellow
try {
    $taskInfo = Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
    Write-Host "  Last Run Time: $($taskInfo.LastRunTime)" -ForegroundColor Gray
    Write-Host "  Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
    Write-Host "  Next Run Time: $($taskInfo.NextRunTime)" -ForegroundColor Gray
    Write-Host "  Number of Missed Runs: $($taskInfo.NumberOfMissedRuns)" -ForegroundColor Gray
    
    if ($taskInfo.LastTaskResult -eq 0) {
        Write-Host "SUCCESS: Last run completed successfully" -ForegroundColor Green
    } elseif ($taskInfo.LastTaskResult -eq 267014) {
        Write-Host "ERROR: Task failed to start (267014)" -ForegroundColor Red
        Write-Host "SOLUTION: Check gMSA account permissions" -ForegroundColor Yellow
    } else {
        Write-Host "WARNING: Last run result: $($taskInfo.LastTaskResult)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Cannot get task execution info" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 3: Check log file
Write-Host "3. Log File Check:" -ForegroundColor Yellow
if (Test-Path $LogPath) {
    Write-Host "SUCCESS: Log file exists at $LogPath" -ForegroundColor Green
    
    # Get last 10 lines of log
    try {
        $logContent = Get-Content $LogPath -Tail 10
        Write-Host "Last 10 log entries:" -ForegroundColor White
        foreach ($line in $logContent) {
            Write-Host "  $line" -ForegroundColor Gray
        }
    } catch {
        Write-Host "ERROR: Cannot read log file" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "WARNING: Log file not found at $LogPath" -ForegroundColor Yellow
    Write-Host "This may indicate the task hasn't run yet or failed to start" -ForegroundColor Yellow
}
Write-Host ""

# Step 4: Check Event Viewer for errors
Write-Host "4. Event Viewer Check:" -ForegroundColor Yellow
if ($isAdmin) {
    try {
        $events = Get-WinEvent -FilterHashtable @{LogName='System'; ID=1074,1076,7034,7035,7036} -MaxEvents 5 -ErrorAction SilentlyContinue
        $taskEvents = $events | Where-Object { $_.Message -like "*$TaskName*" }
        
        if ($taskEvents) {
            Write-Host "Recent task-related events:" -ForegroundColor White
            foreach ($event in $taskEvents) {
                Write-Host "  $($event.TimeCreated): $($event.LevelDisplayName) - $($event.Id)" -ForegroundColor Gray
            }
        } else {
            Write-Host "INFO: No recent task-related events found" -ForegroundColor Gray
        }
    } catch {
        Write-Host "WARNING: Cannot access Event Viewer" -ForegroundColor Yellow
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "INFO: Run as Administrator to check Event Viewer" -ForegroundColor Gray
}
Write-Host ""

# Step 5: Test manual execution
Write-Host "5. Manual Test:" -ForegroundColor Yellow
Write-Host "To test the task manually, run:" -ForegroundColor White
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host ""
Write-Host "To check results after manual run:" -ForegroundColor White
Write-Host "  Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo" -ForegroundColor Gray
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Status Check Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "COMMON ISSUES:" -ForegroundColor Yellow
Write-Host "1. gMSA account needs 'Log on as a batch job' right" -ForegroundColor White
Write-Host "2. SPN 'HTTP/vault.local.lab' must be registered in AD" -ForegroundColor White
Write-Host "3. Keytab must be configured on Vault server" -ForegroundColor White
Write-Host "4. DNS resolution for vault.local.lab must work" -ForegroundColor White
Write-Host ""

Write-Host "QUICK FIXES:" -ForegroundColor Yellow
Write-Host "1. Grant batch logon right: secpol.msc > Local Policies > User Rights Assignment" -ForegroundColor White
Write-Host "2. Register SPN: setspn -A HTTP/vault.local.lab LOCAL\vault-gmsa$" -ForegroundColor White
Write-Host "3. Test DNS: nslookup vault.local.lab" -ForegroundColor White
Write-Host ""
