# Fix SPN Registration - Move from vault-keytab-svc to EC2AMAZ-UB1QVDL$
# Run this as Administrator on Windows

param(
    [string]$ComputerName = "EC2AMAZ-UB1QVDL",
    [string]$SPN = "HTTP/vault.local.lab"
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "FIX SPN REGISTRATION" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Current Issue:" -ForegroundColor Yellow
Write-Host "SPN '$SPN' is registered to 'vault-keytab-svc' but needs to be on '$ComputerName`$'" -ForegroundColor Yellow
Write-Host ""

# Step 1: Remove SPN from vault-keytab-svc
Write-Host "Step 1: Removing SPN from vault-keytab-svc..." -ForegroundColor Yellow
Write-Host "-----------------------------------------------" -ForegroundColor Yellow

try {
    setspn -D $SPN vault-keytab-svc
    Write-Host "✓ SPN removed from vault-keytab-svc" -ForegroundColor Green
} catch {
    Write-Host "⚠ Error removing SPN from vault-keytab-svc: $_" -ForegroundColor Yellow
    Write-Host "This might be OK if it wasn't registered there" -ForegroundColor Yellow
}

Write-Host ""

# Step 2: Add SPN to computer account
Write-Host "Step 2: Adding SPN to computer account..." -ForegroundColor Yellow
Write-Host "------------------------------------------" -ForegroundColor Yellow

$computerAccount = "$ComputerName`$"
Write-Host "Registering SPN: $SPN -> $computerAccount" -ForegroundColor White

try {
    setspn -A $SPN $computerAccount
    Write-Host "✓ SPN registered to $computerAccount" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to register SPN: $_" -ForegroundColor Red
    Write-Host "You may need domain admin privileges" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 3: Verify the registration
Write-Host "Step 3: Verifying SPN registration..." -ForegroundColor Yellow
Write-Host "--------------------------------------" -ForegroundColor Yellow

try {
    $spnQuery = setspn -Q $SPN 2>&1 | Out-String
    if ($spnQuery -match $ComputerName) {
        Write-Host "✓ SPN correctly registered to $ComputerName" -ForegroundColor Green
        Write-Host "Registration details:" -ForegroundColor White
        Write-Host $spnQuery.Trim() -ForegroundColor Gray
    } else {
        Write-Host "❌ SPN registration verification failed" -ForegroundColor Red
        Write-Host "Query result: $spnQuery" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error verifying SPN: $_" -ForegroundColor Red
}

Write-Host ""

# Step 4: Test authentication
Write-Host "Step 4: Testing authentication..." -ForegroundColor Yellow
Write-Host "----------------------------------" -ForegroundColor Yellow

Write-Host "Now test your scheduled task:" -ForegroundColor White
Write-Host "schtasks /Run /TN 'Test Curl Kerberos'" -ForegroundColor Gray
Write-Host "Get-Content C:\vault-client\logs\test-curl-system.log -Tail 30" -ForegroundColor Gray
Write-Host ""

Write-Host "=========================================" -ForegroundColor Green
Write-Host "SPN REGISTRATION FIX COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "The SPN should now be correctly registered to your computer account." -ForegroundColor White
Write-Host "This should resolve the 401 Unauthorized error." -ForegroundColor White
