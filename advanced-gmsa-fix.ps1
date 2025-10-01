# Advanced gMSA Permission Fix
# This script uses multiple methods to fix gMSA scheduled task permissions

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$TaskName = "Vault-gMSA-Debug"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Advanced gMSA Permission Fix" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

Write-Host "SUCCESS: Running as Administrator" -ForegroundColor Green
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  gMSA Account: $GMSAAccount" -ForegroundColor White
Write-Host "  Task Name: $TaskName" -ForegroundColor White
Write-Host ""

# Step 1: Check current gMSA permissions
Write-Host "Step 1: Checking current gMSA permissions..." -ForegroundColor Yellow
try {
    # Check if gMSA exists in AD
    $gmsa = Get-ADServiceAccount -Identity "vault-gmsa" -ErrorAction Stop
    Write-Host "SUCCESS: gMSA account found in Active Directory" -ForegroundColor Green
    Write-Host "  Name: $($gmsa.Name)" -ForegroundColor Gray
    Write-Host "  Distinguished Name: $($gmsa.DistinguishedName)" -ForegroundColor Gray
    Write-Host "  Service Principal Names: $($gmsa.ServicePrincipalNames -join ', ')" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: gMSA account not found in Active Directory" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure the gMSA account exists and you have AD permissions" -ForegroundColor Yellow
}
Write-Host ""

# Step 2: Grant multiple service account rights
Write-Host "Step 2: Granting comprehensive service account rights..." -ForegroundColor Yellow

# List of rights to grant
$rights = @(
    "SeBatchLogonRight",
    "SeServiceLogonRight", 
    "SeInteractiveLogonRight",
    "SeNetworkLogonRight"
)

foreach ($right in $rights) {
    try {
        Write-Host "Granting $right to $GMSAAccount..." -ForegroundColor Cyan
        
        # Use ntrights.exe if available
        $ntrightsCmd = "ntrights +r $right -u $GMSAAccount"
        $result = Invoke-Expression $ntrightsCmd 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SUCCESS: Granted $right" -ForegroundColor Green
        } else {
            Write-Host "WARNING: ntrights failed for $right" -ForegroundColor Yellow
            Write-Host "Result: $result" -ForegroundColor Gray
        }
    } catch {
        Write-Host "WARNING: Could not grant $right" -ForegroundColor Yellow
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
}
Write-Host ""

# Step 3: Use secedit method with proper SID resolution
Write-Host "Step 3: Using secedit with SID resolution..." -ForegroundColor Yellow
try {
    # Get the SID of the gMSA account
    $gmsaSid = (New-Object System.Security.Principal.NTAccount($GMSAAccount)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    Write-Host "gMSA SID: $gmsaSid" -ForegroundColor Gray
    
    # Export current policy
    $seceditCmd = "secedit /export /cfg C:\temp\secpol.cfg"
    Invoke-Expression $seceditCmd | Out-Null
    
    # Read and modify policy
    $secpol = Get-Content "C:\temp\secpol.cfg"
    
    # Update SeBatchLogonRight
    $batchLogonLine = $secpol | Where-Object { $_ -match "SeBatchLogonRight" }
    if ($batchLogonLine -and $batchLogonLine -notmatch $gmsaSid) {
        Write-Host "Adding gMSA SID to SeBatchLogonRight..." -ForegroundColor Cyan
        $newBatchLogonLine = $batchLogonLine + ",$gmsaSid"
        $secpol = $secpol -replace [regex]::Escape($batchLogonLine), $newBatchLogonLine
        $secpol | Set-Content "C:\temp\secpol.cfg"
        
        # Import updated policy
        $importCmd = "secedit /configure /cfg C:\temp\secpol.cfg /db C:\temp\secpol.sdb"
        Invoke-Expression $importCmd | Out-Null
        Write-Host "SUCCESS: Updated policy with gMSA SID" -ForegroundColor Green
    } else {
        Write-Host "SUCCESS: gMSA SID already in SeBatchLogonRight" -ForegroundColor Green
    }
    
    # Clean up
    Remove-Item "C:\temp\secpol.cfg" -ErrorAction SilentlyContinue
    Remove-Item "C:\temp\secpol.sdb" -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "ERROR: secedit method failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 4: Create a new scheduled task with different approach
Write-Host "Step 4: Creating alternative scheduled task..." -ForegroundColor Yellow
try {
    # Remove existing task
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    
    # Create new task with different settings
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"C:\vault-client\debug-gmsa-auth.ps1`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
    
    # Try different principal settings
    $principal = New-ScheduledTaskPrincipal -UserId $GMSAAccount -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
    
    # Register the task
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Vault gMSA Debug Task"
    
    Write-Host "SUCCESS: Created new scheduled task with enhanced settings" -ForegroundColor Green
    
} catch {
    Write-Host "ERROR: Failed to create new scheduled task" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 5: Test the new task
Write-Host "Step 5: Testing new scheduled task..." -ForegroundColor Yellow
try {
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 10
    
    $taskInfo = Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
    Write-Host "Task execution result:" -ForegroundColor White
    Write-Host "  Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
    Write-Host "  Last Run Time: $($taskInfo.LastRunTime)" -ForegroundColor Gray
    
    if ($taskInfo.LastTaskResult -eq 0) {
        Write-Host "SUCCESS: Task executed successfully!" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Task still failing with code: $($taskInfo.LastTaskResult)" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Failed to test task" -ForegroundColor Red
}
Write-Host ""

# Step 6: Alternative execution methods
Write-Host "Step 6: Alternative execution methods..." -ForegroundColor Yellow
Write-Host ""
Write-Host "MANUAL EXECUTION OPTIONS:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Run as different user (requires password):" -ForegroundColor White
Write-Host "   runas /user:$GMSAAccount 'PowerShell -ExecutionPolicy Bypass -File C:\vault-client\debug-gmsa-auth.ps1'" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Use PsExec (if available):" -ForegroundColor White
Write-Host "   psexec -u $GMSAAccount -p '' PowerShell -ExecutionPolicy Bypass -File C:\vault-client\debug-gmsa-auth.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Create a Windows Service instead of scheduled task:" -ForegroundColor White
Write-Host "   sc create VaultGMSADebug binPath= 'PowerShell -ExecutionPolicy Bypass -File C:\vault-client\debug-gmsa-auth.ps1' start= auto obj= $GMSAAccount" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Use Task Scheduler GUI:" -ForegroundColor White
Write-Host "   - Open Task Scheduler" -ForegroundColor Gray
Write-Host "   - Create Basic Task" -ForegroundColor Gray
Write-Host "   - Set user account to $GMSAAccount" -ForegroundColor Gray
Write-Host "   - Set logon type to 'Service Account'" -ForegroundColor Gray
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Advanced Permission Fix Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "DIAGNOSIS:" -ForegroundColor Yellow
Write-Host "Error 267011 typically means:" -ForegroundColor White
Write-Host "1. gMSA account lacks service account permissions" -ForegroundColor Gray
Write-Host "2. Domain policy restricts gMSA logon rights" -ForegroundColor Gray
Write-Host "3. gMSA account is not properly configured in AD" -ForegroundColor Gray
Write-Host "4. System needs restart for policy changes to take effect" -ForegroundColor Gray
Write-Host ""

Write-Host "RECOMMENDATIONS:" -ForegroundColor Yellow
Write-Host "1. Try the manual execution methods above" -ForegroundColor White
Write-Host "2. Check with Domain Administrator about gMSA policies" -ForegroundColor White
Write-Host "3. Consider creating a Windows Service instead of scheduled task" -ForegroundColor White
Write-Host "4. Restart the system to apply policy changes" -ForegroundColor White
Write-Host ""

if ($taskInfo.LastTaskResult -eq 0) {
    Write-Host "STATUS: gMSA permissions fixed successfully!" -ForegroundColor Green
} else {
    Write-Host "STATUS: May need domain administrator intervention or system restart" -ForegroundColor Yellow
}
Write-Host ""
