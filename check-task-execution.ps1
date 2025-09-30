# Check how the scheduled task is actually executing

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Checking Scheduled Task Execution" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check last task run result
Write-Host "[1] Last Task Run Result:" -ForegroundColor Yellow
$taskInfo = Get-ScheduledTaskInfo -TaskName "VaultClientApp"
Write-Host "  Last Run Time: $($taskInfo.LastRunTime)"
Write-Host "  Last Result: $($taskInfo.LastTaskResult) (0x$($taskInfo.LastTaskResult.ToString('X8')))"
Write-Host "  Next Run Time: $($taskInfo.NextRunTime)"
Write-Host ""

# 2. Check task principal
Write-Host "[2] Task Principal Configuration:" -ForegroundColor Yellow
$task = Get-ScheduledTask -TaskName "VaultClientApp"
Write-Host "  User ID: $($task.Principal.UserId)"
Write-Host "  Logon Type: $($task.Principal.LogonType)"
Write-Host "  Run Level: $($task.Principal.RunLevel)"
Write-Host "  Required Privileges: $($task.Principal.RequiredPrivilege -join ', ')"
Write-Host ""

# 3. Get FULL log with timestamp filter
Write-Host "[3] Recent Log Entries (last 2 runs):" -ForegroundColor Yellow
$logFile = "C:\vault-client\config\vault-client.log"
if (Test-Path $logFile) {
    # Get last 50 lines to capture both runs
    $logs = Get-Content $logFile -Tail 50
    
    # Look for "Running under" entries
    $runningUnder = $logs | Select-String "Running under"
    if ($runningUnder) {
        Write-Host "  Found 'Running under' entries:" -ForegroundColor Green
        $runningUnder | ForEach-Object { Write-Host "    $_" -ForegroundColor White }
    } else {
        Write-Host "  No 'Running under' entries found!" -ForegroundColor Red
        Write-Host "  Script may not be logging user identity correctly" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Show all recent entries
    Write-Host "  All recent entries:" -ForegroundColor Cyan
    $logs | ForEach-Object {
        if ($_ -match "ERROR") {
            Write-Host "    $_" -ForegroundColor Red
        } elseif ($_ -match "SUCCESS") {
            Write-Host "    $_" -ForegroundColor Green
        } elseif ($_ -match "INFO.*Script version") {
            Write-Host "    $_" -ForegroundColor Cyan
        } else {
            Write-Host "    $_" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "  Log file not found: $logFile" -ForegroundColor Red
}
Write-Host ""

# 4. Check if gMSA can authenticate interactively
Write-Host "[4] Testing gMSA Authentication Capability:" -ForegroundColor Yellow
$gmsaTest = Test-ADServiceAccount -Identity vault-gmsa
Write-Host "  Test-ADServiceAccount: $gmsaTest"
if ($gmsaTest) {
    Write-Host "  gMSA can retrieve password from AD ✓" -ForegroundColor Green
} else {
    Write-Host "  gMSA CANNOT retrieve password from AD ✗" -ForegroundColor Red
}
Write-Host ""

# 5. Check if vault-gmsa can get tickets
Write-Host "[5] Checking if gMSA has Kerberos tickets:" -ForegroundColor Yellow
Write-Host "  Note: gMSA tickets are stored separately, not visible in current session" -ForegroundColor Yellow
Write-Host ""

# 6. Verify script file location and permissions
Write-Host "[6] Script File Check:" -ForegroundColor Yellow
$scriptPath = "C:\vault-client\scripts\vault-client-app.ps1"
if (Test-Path $scriptPath) {
    $scriptFile = Get-Item $scriptPath
    Write-Host "  Path: $scriptPath ✓" -ForegroundColor Green
    Write-Host "  Size: $($scriptFile.Length) bytes"
    Write-Host "  Last Modified: $($scriptFile.LastWriteTime)"
    
    # Check for the user identity logging
    $scriptContent = Get-Content $scriptPath -Raw
    if ($scriptContent -match "Running under") {
        Write-Host "  Contains 'Running under' logging: ✓" -ForegroundColor Green
    } else {
        Write-Host "  Missing 'Running under' logging: ✗" -ForegroundColor Red
        Write-Host "  Script may need to be updated" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Script not found: $scriptPath ✗" -ForegroundColor Red
}
Write-Host ""

# 7. Check Event Log for scheduled task execution
Write-Host "[7] Checking Event Log for Task Execution:" -ForegroundColor Yellow
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-TaskScheduler/Operational'
        Id = 200,201  # Task executed, Task completed
    } -MaxEvents 10 -ErrorAction SilentlyContinue | Where-Object { $_.Message -match "VaultClientApp" }
    
    if ($events) {
        foreach ($event in $events) {
            Write-Host "  [$($event.TimeCreated)] ID $($event.Id): $($event.Message.Split("`n")[0])" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  No recent task execution events found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Could not read event log: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Recommendation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "If 'Running under' is not showing vault-gmsa$:" -ForegroundColor Yellow
Write-Host "1. The script needs to log the current user identity" -ForegroundColor White
Write-Host "2. Check if script version has this logging" -ForegroundColor White
Write-Host "3. Re-deploy latest script version" -ForegroundColor White
Write-Host ""
