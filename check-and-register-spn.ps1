# Check and Register SPN for gMSA
# This script verifies and registers the required SPN for Kerberos authentication

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$SPN = "HTTP/vault.local.lab"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SPN Registration Check and Fix" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  gMSA Account: $GMSAAccount" -ForegroundColor White
Write-Host "  SPN: $SPN" -ForegroundColor White
Write-Host ""

# Check if running as Administrator
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "WARNING: Not running as Administrator - some operations may fail" -ForegroundColor Yellow
} else {
    Write-Host "SUCCESS: Running as Administrator" -ForegroundColor Green
}
Write-Host ""

# Step 1: Check current SPN registration
Write-Host "Step 1: Checking current SPN registration..." -ForegroundColor Yellow
try {
    $spnResult = setspn -Q $SPN 2>&1
    Write-Host "SPN query result:" -ForegroundColor White
    Write-Host $spnResult -ForegroundColor Gray
    
    if ($spnResult -match $GMSAAccount) {
        Write-Host "SUCCESS: SPN $SPN is registered to $GMSAAccount" -ForegroundColor Green
    } elseif ($spnResult -match "No such SPN found") {
        Write-Host "WARNING: SPN $SPN is not registered" -ForegroundColor Yellow
    } else {
        Write-Host "WARNING: SPN $SPN is registered to a different account" -ForegroundColor Yellow
        Write-Host "Current registration: $spnResult" -ForegroundColor Gray
    }
} catch {
    Write-Host "ERROR: Cannot query SPN registration" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 2: Check all SPNs for the gMSA account
Write-Host "Step 2: Checking all SPNs for gMSA account..." -ForegroundColor Yellow
try {
    $gmsaSpns = setspn -L $GMSAAccount 2>&1
    Write-Host "SPNs registered to ${GMSAAccount}:" -ForegroundColor White
    Write-Host $gmsaSpns -ForegroundColor Gray
    
    if ($gmsaSpns -match $SPN) {
        Write-Host "SUCCESS: $SPN is registered to ${GMSAAccount}" -ForegroundColor Green
    } else {
        Write-Host "WARNING: $SPN is not registered to ${GMSAAccount}" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Cannot list SPNs for gMSA account" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 3: Register the SPN if needed
Write-Host "Step 3: Registering SPN if needed..." -ForegroundColor Yellow
try {
    # First, try to remove any existing registration of this SPN
    Write-Host "Removing any existing SPN registration..." -ForegroundColor Cyan
    $removeResult = setspn -D $SPN 2>&1
    Write-Host "Remove result: $removeResult" -ForegroundColor Gray
    
    # Now register the SPN to the gMSA account
    Write-Host "Registering SPN to gMSA account..." -ForegroundColor Cyan
    $addResult = setspn -A $SPN $GMSAAccount 2>&1
    Write-Host "Add result: $addResult" -ForegroundColor Gray
    
    if ($addResult -match "successfully") {
        Write-Host "SUCCESS: SPN $SPN registered to ${GMSAAccount}" -ForegroundColor Green
    } else {
        Write-Host "WARNING: SPN registration may have failed" -ForegroundColor Yellow
        Write-Host "Result: $addResult" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Failed to register SPN" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 4: Verify the registration
Write-Host "Step 4: Verifying SPN registration..." -ForegroundColor Yellow
try {
    $verifyResult = setspn -Q $SPN 2>&1
    Write-Host "Verification result:" -ForegroundColor White
    Write-Host $verifyResult -ForegroundColor Gray
    
    if ($verifyResult -match ${GMSAAccount}) {
        Write-Host "SUCCESS: SPN registration verified!" -ForegroundColor Green
    } else {
        Write-Host "ERROR: SPN registration verification failed" -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR: Cannot verify SPN registration" -ForegroundColor Red
}
Write-Host ""

# Step 5: Test DNS resolution
Write-Host "Step 5: Testing DNS resolution..." -ForegroundColor Yellow
try {
    $dnsResult = [System.Net.Dns]::GetHostAddresses("vault.local.lab")
    Write-Host "SUCCESS: vault.local.lab resolves to: $($dnsResult[0].IPAddressToString)" -ForegroundColor Green
} catch {
    Write-Host "WARNING: vault.local.lab DNS resolution failed" -ForegroundColor Yellow
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "SOLUTION: Add entry to hosts file or configure DNS" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SPN Check Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Run: .\fix-gmsa-task-permissions.ps1" -ForegroundColor White
Write-Host "2. Test the scheduled task: Start-ScheduledTask -TaskName 'Vault-gMSA-Authentication'" -ForegroundColor White
Write-Host "3. Check results: .\check-gmsa-task-status.ps1" -ForegroundColor White
Write-Host ""

Write-Host "MANUAL COMMANDS:" -ForegroundColor Yellow
Write-Host "Check SPN: setspn -Q HTTP/vault.local.lab" -ForegroundColor White
Write-Host "List gMSA SPNs: setspn -L LOCAL\vault-gmsa$" -ForegroundColor White
Write-Host "Register SPN: setspn -A HTTP/vault.local.lab LOCAL\vault-gmsa$" -ForegroundColor White
Write-Host "Remove SPN: setspn -D HTTP/vault.local.lab" -ForegroundColor White
Write-Host ""
