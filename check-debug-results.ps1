# Check Debug Task Results
# This script checks the results of the gMSA debug scheduled task

param(
    [string]$TaskName = "Vault-gMSA-Debug"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Debug Task Results Check" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "WARNING: Not running as Administrator - some information may be limited" -ForegroundColor Yellow
} else {
    Write-Host "SUCCESS: Running as Administrator" -ForegroundColor Green
}
Write-Host ""

# Step 1: Check if debug task exists
Write-Host "Step 1: Checking if debug task exists..." -ForegroundColor Yellow
try {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host "SUCCESS: Debug task found" -ForegroundColor Green
    Write-Host "  Task Name: $($task.TaskName)" -ForegroundColor Gray
    Write-Host "  Task State: $($task.State)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Debug task not found: $TaskName" -ForegroundColor Red
    Write-Host "Run: .\create-debug-task.ps1 first" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Step 2: Get task execution info
Write-Host "Step 2: Getting task execution information..." -ForegroundColor Yellow
try {
    $taskInfo = Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
    Write-Host "SUCCESS: Task execution info retrieved" -ForegroundColor Green
    Write-Host ""
    Write-Host "EXECUTION DETAILS:" -ForegroundColor Cyan
    Write-Host "  Last Run Time: $($taskInfo.LastRunTime)" -ForegroundColor White
    Write-Host "  Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor White
    Write-Host "  Next Run Time: $($taskInfo.NextRunTime)" -ForegroundColor White
    Write-Host "  Number of Missed Runs: $($taskInfo.NumberOfMissedRuns)" -ForegroundColor White
    Write-Host ""
    
    # Interpret the result code
    switch ($taskInfo.LastTaskResult) {
        0 { Write-Host "RESULT: Task executed successfully!" -ForegroundColor Green }
        1 { Write-Host "RESULT: Task failed with error code 1" -ForegroundColor Red }
        267011 { Write-Host "RESULT: Account specified error (267011)" -ForegroundColor Red }
        2147942402 { Write-Host "RESULT: File not found error" -ForegroundColor Red }
        default { Write-Host "RESULT: Unknown error code: $($taskInfo.LastTaskResult)" -ForegroundColor Yellow }
    }
    
} catch {
    Write-Host "ERROR: Failed to get task execution info" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 3: Check Event Viewer for detailed logs
Write-Host "Step 3: Checking Event Viewer for detailed logs..." -ForegroundColor Yellow
try {
    # Get recent events from Task Scheduler
    $events = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational'; ID=200} -MaxEvents 5 -ErrorAction SilentlyContinue
    
    if ($events) {
        Write-Host "SUCCESS: Found recent Task Scheduler events" -ForegroundColor Green
        Write-Host ""
        Write-Host "RECENT TASK EVENTS:" -ForegroundColor Cyan
        foreach ($event in $events) {
            if ($event.Message -match $TaskName) {
                Write-Host "  Time: $($event.TimeCreated)" -ForegroundColor White
                Write-Host "  Event: $($event.Message)" -ForegroundColor Gray
                Write-Host ""
            }
        }
    } else {
        Write-Host "INFO: No recent Task Scheduler events found" -ForegroundColor Gray
    }
    
    # Get PowerShell execution events
    $psEvents = Get-WinEvent -FilterHashtable @{LogName='Windows PowerShell'; ID=400} -MaxEvents 3 -ErrorAction SilentlyContinue
    
    if ($psEvents) {
        Write-Host "SUCCESS: Found recent PowerShell execution events" -ForegroundColor Green
        Write-Host ""
        Write-Host "RECENT POWERSHELL EVENTS:" -ForegroundColor Cyan
        foreach ($event in $psEvents) {
            Write-Host "  Time: $($event.TimeCreated)" -ForegroundColor White
            Write-Host "  Event: $($event.Message)" -ForegroundColor Gray
            Write-Host ""
        }
    } else {
        Write-Host "INFO: No recent PowerShell execution events found" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "WARNING: Could not access Event Viewer logs" -ForegroundColor Yellow
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
}
Write-Host ""

# Step 4: Check if debug script output exists
Write-Host "Step 4: Checking for debug script output..." -ForegroundColor Yellow
$debugLogPath = "C:\vault-client\config\debug-gmsa.log"
if (Test-Path $debugLogPath) {
    Write-Host "SUCCESS: Debug log file found!" -ForegroundColor Green
    Write-Host "  Path: $debugLogPath" -ForegroundColor Gray
    
    # Show last 20 lines of the log
    Write-Host ""
    Write-Host "RECENT DEBUG LOG OUTPUT:" -ForegroundColor Cyan
    try {
        $logContent = Get-Content $debugLogPath -Tail 20
        foreach ($line in $logContent) {
            Write-Host "  $line" -ForegroundColor Gray
        }
    } catch {
        Write-Host "WARNING: Could not read debug log file" -ForegroundColor Yellow
    }
} else {
    Write-Host "INFO: Debug log file not found: $debugLogPath" -ForegroundColor Gray
    Write-Host "This might mean the debug script didn't run or failed early" -ForegroundColor Yellow
}
Write-Host ""

# Step 5: Manual execution suggestion
Write-Host "Step 5: Manual execution options..." -ForegroundColor Yellow
Write-Host ""
Write-Host "MANUAL COMMANDS:" -ForegroundColor Cyan
Write-Host "To run debug task again:" -ForegroundColor White
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host ""
Write-Host "To run debug script directly:" -ForegroundColor White
Write-Host "  PowerShell -ExecutionPolicy Bypass -File 'C:\vault-client\debug-gmsa-auth.ps1'" -ForegroundColor Gray
Write-Host ""
Write-Host "To check task status:" -ForegroundColor White
Write-Host "  Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo" -ForegroundColor Gray
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Debug Task Analysis Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

if ($taskInfo.LastTaskResult -eq 0) {
    Write-Host "STATUS: Debug task executed successfully!" -ForegroundColor Green
    Write-Host "Check the debug log output above for authentication details." -ForegroundColor Green
} else {
    Write-Host "STATUS: Debug task failed with error code $($taskInfo.LastTaskResult)" -ForegroundColor Red
    Write-Host "Check Event Viewer and try running the task manually." -ForegroundColor Yellow
}
Write-Host ""
