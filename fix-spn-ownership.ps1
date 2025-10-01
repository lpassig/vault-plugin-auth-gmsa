# Fix SPN Ownership - Move SPN from Computer to gMSA
# This script removes SPN from computer account and registers it to gMSA

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$ComputerAccount = "EC2AMAZ-UB1QVDL"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Fix SPN Ownership" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "ISSUE DETECTED:" -ForegroundColor Red
Write-Host "SPN $SPN is registered to $ComputerAccount instead of $GMSAAccount" -ForegroundColor Red
Write-Host ""

Write-Host "SOLUTION:" -ForegroundColor Yellow
Write-Host "Remove SPN from computer account and register it to gMSA account" -ForegroundColor White
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

# Step 1: Remove SPN from computer account
Write-Host "Step 1: Removing SPN from computer account..." -ForegroundColor Yellow
try {
    Write-Host "Removing $SPN from $ComputerAccount..." -ForegroundColor Cyan
    $removeResult = setspn -D $SPN $ComputerAccount 2>&1
    Write-Host "Remove result: $removeResult" -ForegroundColor Gray
    
    if ($removeResult -match "successfully" -or $removeResult -match "deleted") {
        Write-Host "SUCCESS: SPN removed from computer account" -ForegroundColor Green
    } else {
        Write-Host "WARNING: SPN removal may have failed" -ForegroundColor Yellow
        Write-Host "Result: $removeResult" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Failed to remove SPN from computer account" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 2: Verify SPN is removed
Write-Host "Step 2: Verifying SPN removal..." -ForegroundColor Yellow
try {
    $verifyResult = setspn -Q $SPN 2>&1
    Write-Host "Verification result:" -ForegroundColor White
    Write-Host $verifyResult -ForegroundColor Gray
    
    if ($verifyResult -match "No such SPN found") {
        Write-Host "SUCCESS: SPN successfully removed" -ForegroundColor Green
    } elseif ($verifyResult -match $ComputerAccount) {
        Write-Host "WARNING: SPN still registered to computer account" -ForegroundColor Yellow
        Write-Host "Manual removal may be required" -ForegroundColor Yellow
    } else {
        Write-Host "INFO: SPN status unclear, proceeding with registration" -ForegroundColor Gray
    }
} catch {
    Write-Host "ERROR: Cannot verify SPN removal" -ForegroundColor Red
}
Write-Host ""

# Step 3: Register SPN to gMSA account
Write-Host "Step 3: Registering SPN to gMSA account..." -ForegroundColor Yellow
try {
    Write-Host "Registering $SPN to $GMSAAccount..." -ForegroundColor Cyan
    $addResult = setspn -A $SPN $GMSAAccount 2>&1
    Write-Host "Add result: $addResult" -ForegroundColor Gray
    
    if ($addResult -match "successfully" -or $addResult -match "registered") {
        Write-Host "SUCCESS: SPN registered to gMSA account" -ForegroundColor Green
    } else {
        Write-Host "WARNING: SPN registration may have failed" -ForegroundColor Yellow
        Write-Host "Result: $addResult" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Failed to register SPN to gMSA account" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 4: Verify final registration
Write-Host "Step 4: Verifying final SPN registration..." -ForegroundColor Yellow
try {
    $finalResult = setspn -Q $SPN 2>&1
    Write-Host "Final verification result:" -ForegroundColor White
    Write-Host $finalResult -ForegroundColor Gray
    
    if ($finalResult -match $GMSAAccount) {
        Write-Host "SUCCESS: SPN registration verified!" -ForegroundColor Green
        Write-Host "SPN $SPN is now registered to $GMSAAccount" -ForegroundColor Green
    } else {
        Write-Host "ERROR: SPN registration verification failed" -ForegroundColor Red
        Write-Host "SPN may still be registered to wrong account" -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR: Cannot verify final SPN registration" -ForegroundColor Red
}
Write-Host ""

# Step 5: List all SPNs for gMSA account
Write-Host "Step 5: Listing all SPNs for gMSA account..." -ForegroundColor Yellow
try {
    $gmsaSpns = setspn -L $GMSAAccount 2>&1
    Write-Host "SPNs registered to $GMSAAccount:" -ForegroundColor White
    Write-Host $gmsaSpns -ForegroundColor Gray
    
    if ($gmsaSpns -match $SPN) {
        Write-Host "SUCCESS: $SPN found in gMSA SPN list" -ForegroundColor Green
    } else {
        Write-Host "WARNING: $SPN not found in gMSA SPN list" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Cannot list SPNs for gMSA account" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SPN Ownership Fix Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Run: .\fix-gmsa-task-permissions.ps1" -ForegroundColor White
Write-Host "2. Test scheduled task: Start-ScheduledTask -TaskName 'Vault-gMSA-Authentication'" -ForegroundColor White
Write-Host "3. Check results: .\check-gmsa-task-status.ps1" -ForegroundColor White
Write-Host "4. Test authentication: .\test-gmsa-authentication.ps1" -ForegroundColor White
Write-Host ""

Write-Host "MANUAL VERIFICATION:" -ForegroundColor Yellow
Write-Host "Check SPN: setspn -Q HTTP/vault.local.lab" -ForegroundColor White
Write-Host "List gMSA SPNs: setspn -L LOCAL\vault-gmsa$" -ForegroundColor White
Write-Host ""

Write-Host "EXPECTED RESULTS:" -ForegroundColor Yellow
Write-Host "After successful fix, you should see:" -ForegroundColor White
Write-Host "  - SUCCESS: SPN registered to gMSA account" -ForegroundColor Green
Write-Host "  - SUCCESS: SPN registration verified!" -ForegroundColor Green
Write-Host "  - HTTP/vault.local.lab in gMSA SPN list" -ForegroundColor Green
Write-Host ""
