# Check gMSA Setup Status
# This script checks the current gMSA configuration

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$SPN = "HTTP/vault.local.lab"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "GMSA SETUP STATUS CHECK" -ForegroundColor Cyan
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
Write-Host "  SPN: $SPN" -ForegroundColor White
Write-Host "  Current User: $(whoami)" -ForegroundColor White
Write-Host ""

# Check gMSA account
Write-Host "Step 1: Checking gMSA account..." -ForegroundColor Yellow
Write-Host "--------------------------------" -ForegroundColor Yellow

try {
    $gmsa = Get-ADServiceAccount -Identity $GMSAAccount -ErrorAction SilentlyContinue
    
    if ($gmsa) {
        Write-Host "✓ gMSA account exists" -ForegroundColor Green
        Write-Host "  Name: $($gmsa.Name)" -ForegroundColor Gray
        Write-Host "  SID: $($gmsa.SID)" -ForegroundColor Gray
        Write-Host "  Enabled: $($gmsa.Enabled)" -ForegroundColor Gray
        
        # Check if installed on this machine
        try {
            $installed = Test-ADServiceAccount -Identity $GMSAAccount -ErrorAction SilentlyContinue
            if ($installed) {
                Write-Host "✓ gMSA is installed on this machine" -ForegroundColor Green
            } else {
                Write-Host "⚠ gMSA is NOT installed on this machine" -ForegroundColor Yellow
                Write-Host "  Run: Install-ADServiceAccount -Identity $GMSAAccount" -ForegroundColor Gray
            }
        } catch {
            Write-Host "⚠ Cannot check gMSA installation status" -ForegroundColor Yellow
        }
        
        $gmsaExists = $true
    } else {
        Write-Host "❌ gMSA account does not exist" -ForegroundColor Red
        Write-Host "  Run: New-ADServiceAccount -Name vault-gmsa -DNSHostName vault.local.lab" -ForegroundColor Gray
        $gmsaExists = $false
    }
} catch {
    Write-Host "❌ Error checking gMSA account: $($_.Exception.Message)" -ForegroundColor Red
    $gmsaExists = $false
}

# Check SPN registration
Write-Host ""
Write-Host "Step 2: Checking SPN registration..." -ForegroundColor Yellow
Write-Host "------------------------------------" -ForegroundColor Yellow

try {
    $spnResult = setspn -Q $SPN 2>&1
    Write-Host "SPN query result:" -ForegroundColor White
    Write-Host $spnResult -ForegroundColor Gray
    
    if ($spnResult -match $GMSAAccount) {
        Write-Host "✓ SPN is registered to gMSA account" -ForegroundColor Green
        $spnRegistered = $true
    } elseif ($spnResult -match "No such SPN found") {
        Write-Host "❌ SPN is not registered" -ForegroundColor Red
        Write-Host "  Run: setspn -A $SPN $GMSAAccount" -ForegroundColor Gray
        $spnRegistered = $false
    } else {
        Write-Host "⚠ SPN is registered to a different account" -ForegroundColor Yellow
        Write-Host "  Current registration: $spnResult" -ForegroundColor Gray
        $spnRegistered = $false
    }
} catch {
    Write-Host "❌ Error checking SPN registration: $($_.Exception.Message)" -ForegroundColor Red
    $spnRegistered = $false
}

# Check Kerberos tickets
Write-Host ""
Write-Host "Step 3: Checking Kerberos tickets..." -ForegroundColor Yellow
Write-Host "------------------------------------" -ForegroundColor Yellow

try {
    $tickets = klist 2>&1
    Write-Host "Kerberos tickets:" -ForegroundColor White
    Write-Host $tickets -ForegroundColor Gray
    
    if ($tickets -match "krbtgt") {
        Write-Host "✓ Kerberos TGT found" -ForegroundColor Green
        $kerberosTickets = $true
    } else {
        Write-Host "❌ No Kerberos TGT found" -ForegroundColor Red
        Write-Host "  Run: kinit -k $GMSAAccount" -ForegroundColor Gray
        $kerberosTickets = $false
    }
} catch {
    Write-Host "❌ Error checking Kerberos tickets: $($_.Exception.Message)" -ForegroundColor Red
    $kerberosTickets = $false
}

# Check scheduled task
Write-Host ""
Write-Host "Step 4: Checking scheduled task..." -ForegroundColor Yellow
Write-Host "-----------------------------------" -ForegroundColor Yellow

$taskName = "Vault-gMSA-Authentication"

try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if ($task) {
        Write-Host "✓ Scheduled task exists: $taskName" -ForegroundColor Green
        Write-Host "  State: $($task.State)" -ForegroundColor Gray
        Write-Host "  Principal: $($task.Principal.UserId)" -ForegroundColor Gray
        
        if ($task.Principal.UserId -eq $GMSAAccount) {
            Write-Host "✓ Task runs under correct gMSA account" -ForegroundColor Green
        } else {
            Write-Host "⚠ Task runs under different account: $($task.Principal.UserId)" -ForegroundColor Yellow
        }
        
        $taskExists = $true
    } else {
        Write-Host "❌ Scheduled task does not exist: $taskName" -ForegroundColor Red
        Write-Host "  Run: powershell -ExecutionPolicy Bypass -File .\create-gmsa-task-simple.ps1" -ForegroundColor Gray
        $taskExists = $false
    }
} catch {
    Write-Host "❌ Error checking scheduled task: $($_.Exception.Message)" -ForegroundColor Red
    $taskExists = $false
}

# Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "STATUS SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Results:" -ForegroundColor Yellow
Write-Host "  gMSA Account: $(if ($gmsaExists) { '✓ EXISTS' } else { '❌ MISSING' })" -ForegroundColor $(if ($gmsaExists) { 'Green' } else { 'Red' })
Write-Host "  SPN Registration: $(if ($spnRegistered) { '✓ CORRECT' } else { '❌ MISSING/WRONG' })" -ForegroundColor $(if ($spnRegistered) { 'Green' } else { 'Red' })
Write-Host "  Kerberos Tickets: $(if ($kerberosTickets) { '✓ PRESENT' } else { '❌ MISSING' })" -ForegroundColor $(if ($kerberosTickets) { 'Green' } else { 'Red' })
Write-Host "  Scheduled Task: $(if ($taskExists) { '✓ EXISTS' } else { '❌ MISSING' })" -ForegroundColor $(if ($taskExists) { 'Green' } else { 'Red' })

Write-Host ""
if ($gmsaExists -and $spnRegistered -and $kerberosTickets -and $taskExists) {
    Write-Host "🎉 SUCCESS: gMSA setup is complete!" -ForegroundColor Green
    Write-Host "Your gMSA authentication should be working." -ForegroundColor Green
} else {
    Write-Host "⚠ SETUP NEEDED: Some components are missing" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    
    if (-not $gmsaExists) {
        Write-Host "1. Create gMSA account" -ForegroundColor White
    }
    if (-not $spnRegistered) {
        Write-Host "2. Register SPN" -ForegroundColor White
    }
    if (-not $kerberosTickets) {
        Write-Host "3. Get Kerberos tickets" -ForegroundColor White
    }
    if (-not $taskExists) {
        Write-Host "4. Create scheduled task" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "STATUS CHECK COMPLETE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
