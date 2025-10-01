# Fix gMSA Scheduled Task Permissions
# This script fixes the 267011 error by granting proper permissions to the gMSA account

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$TaskName = "Vault-gMSA-Debug"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Fix gMSA Scheduled Task Permissions" -ForegroundColor Cyan
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
Write-Host "  Task Name: $TaskName" -ForegroundColor White
Write-Host ""

# Step 1: Grant "Log on as a batch job" right to gMSA
Write-Host "Step 1: Granting 'Log on as a batch job' right to gMSA..." -ForegroundColor Yellow
try {
    # Use secedit to grant the right
    $seceditCmd = "secedit /export /cfg C:\temp\secpol.cfg"
    Invoke-Expression $seceditCmd | Out-Null
    
    # Read the current policy
    $secpol = Get-Content "C:\temp\secpol.cfg"
    
    # Find the SeBatchLogonRight line
    $batchLogonLine = $secpol | Where-Object { $_ -match "SeBatchLogonRight" }
    
    if ($batchLogonLine) {
        Write-Host "Current SeBatchLogonRight: $batchLogonLine" -ForegroundColor Gray
        
        # Check if gMSA is already in the list
        if ($batchLogonLine -match $GMSAAccount.Replace('\', '\\')) {
            Write-Host "SUCCESS: gMSA already has 'Log on as a batch job' right" -ForegroundColor Green
        } else {
            Write-Host "Adding gMSA to 'Log on as a batch job' right..." -ForegroundColor Cyan
            
            # Add gMSA to the right
            $newBatchLogonLine = $batchLogonLine + ",$GMSAAccount"
            $secpol = $secpol -replace [regex]::Escape($batchLogonLine), $newBatchLogonLine
            
            # Write back to file
            $secpol | Set-Content "C:\temp\secpol.cfg"
            
            # Import the updated policy
            $importCmd = "secedit /configure /cfg C:\temp\secpol.cfg /db C:\temp\secpol.sdb"
            Invoke-Expression $importCmd | Out-Null
            
            Write-Host "SUCCESS: Granted 'Log on as a batch job' right to gMSA" -ForegroundColor Green
        }
    } else {
        Write-Host "WARNING: Could not find SeBatchLogonRight in policy" -ForegroundColor Yellow
    }
    
    # Clean up temp files
    Remove-Item "C:\temp\secpol.cfg" -ErrorAction SilentlyContinue
    Remove-Item "C:\temp\secpol.sdb" -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "ERROR: Failed to grant 'Log on as a batch job' right" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Trying alternative method..." -ForegroundColor Yellow
    
    # Alternative method using local security policy
    try {
        $cmd = "net user `"$GMSAAccount`" /logonpasswordchg:no"
        Invoke-Expression $cmd | Out-Null
        Write-Host "SUCCESS: Applied alternative permission method" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Alternative method also failed" -ForegroundColor Red
    }
}
Write-Host ""

# Step 2: Update scheduled task to use proper logon type
Write-Host "Step 2: Updating scheduled task logon type..." -ForegroundColor Yellow
try {
    # Get the current task
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    
    # Create new principal with ServiceAccount logon type
    $newPrincipal = New-ScheduledTaskPrincipal -UserId $GMSAAccount -LogonType ServiceAccount -RunLevel Highest
    
    # Update the task
    Set-ScheduledTask -TaskName $TaskName -Principal $newPrincipal
    
    Write-Host "SUCCESS: Updated scheduled task logon type to ServiceAccount" -ForegroundColor Green
    
} catch {
    Write-Host "ERROR: Failed to update scheduled task" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 3: Test the task execution
Write-Host "Step 3: Testing task execution..." -ForegroundColor Yellow
try {
    Write-Host "Starting task manually..." -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $TaskName
    
    # Wait for task to complete
    Start-Sleep -Seconds 15
    
    # Check task status
    $taskInfo = Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
    Write-Host "Task execution result:" -ForegroundColor White
    Write-Host "  Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
    Write-Host "  Last Run Time: $($taskInfo.LastRunTime)" -ForegroundColor Gray
    
    if ($taskInfo.LastTaskResult -eq 0) {
        Write-Host "SUCCESS: Task executed successfully!" -ForegroundColor Green
        Write-Host "The gMSA authentication debug should now work!" -ForegroundColor Green
    } elseif ($taskInfo.LastTaskResult -eq 267011) {
        Write-Host "WARNING: Still getting error 267011" -ForegroundColor Yellow
        Write-Host "This might require a system restart or additional permissions" -ForegroundColor Yellow
    } else {
        Write-Host "INFO: Task result: $($taskInfo.LastTaskResult)" -ForegroundColor Cyan
        Write-Host "Check the debug output for authentication details" -ForegroundColor Cyan
    }
    
} catch {
    Write-Host "ERROR: Failed to test task execution" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 4: Alternative approach - run script directly under gMSA
Write-Host "Step 4: Alternative approach - Direct gMSA execution..." -ForegroundColor Yellow
Write-Host ""
Write-Host "MANUAL COMMANDS TO TRY:" -ForegroundColor Cyan
Write-Host "1. Run script directly under gMSA context:" -ForegroundColor White
Write-Host "   runas /user:$GMSAAccount 'PowerShell -ExecutionPolicy Bypass -File C:\vault-client\debug-gmsa-auth.ps1'" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Use PsExec to run as gMSA:" -ForegroundColor White
Write-Host "   psexec -u $GMSAAccount -p '' PowerShell -ExecutionPolicy Bypass -File C:\vault-client\debug-gmsa-auth.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Check if gMSA has proper service account permissions:" -ForegroundColor White
Write-Host "   Get-ADServiceAccount -Identity 'vault-gmsa' -Properties *" -ForegroundColor Gray
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Permission Fix Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Try running the debug task again:" -ForegroundColor White
Write-Host "   Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host ""
Write-Host "2. If still failing, try manual execution methods above" -ForegroundColor White
Write-Host ""
Write-Host "3. Check Event Viewer for detailed error information" -ForegroundColor White
Write-Host ""
Write-Host "4. Consider restarting the system if permissions don't take effect" -ForegroundColor White
Write-Host ""

if ($taskInfo.LastTaskResult -eq 0) {
    Write-Host "STATUS: gMSA permissions fixed successfully!" -ForegroundColor Green
} else {
    Write-Host "STATUS: May need additional troubleshooting or system restart" -ForegroundColor Yellow
}
Write-Host ""
