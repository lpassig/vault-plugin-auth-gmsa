# Fix SPN Registration - This is the most likely cause
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "FIX SPN REGISTRATION" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Issue: Vault logs show 'not a valid SPNEGO token: asn1: structure error'" -ForegroundColor Yellow
Write-Host "This usually means the SPN is not registered correctly" -ForegroundColor Yellow
Write-Host ""

# Check current SPN registration
Write-Host "Step 1: Checking current SPN registration..." -ForegroundColor Yellow
$spnQuery = setspn -Q HTTP/vault.local.lab 2>&1 | Out-String
Write-Host "Current SPN registration:" -ForegroundColor White
Write-Host $spnQuery -ForegroundColor Gray

Write-Host ""
Write-Host "Step 2: Fixing SPN registration..." -ForegroundColor Yellow

# Remove SPN from vault-keytab-svc if it exists
Write-Host "Removing SPN from vault-keytab-svc..." -ForegroundColor White
setspn -D HTTP/vault.local.lab vault-keytab-svc 2>$null

# Add SPN to computer account
Write-Host "Adding SPN to EC2AMAZ-UB1QVDL$..." -ForegroundColor White
setspn -A HTTP/vault.local.lab EC2AMAZ-UB1QVDL$

Write-Host ""
Write-Host "Step 3: Verifying SPN registration..." -ForegroundColor Yellow
$newSpnQuery = setspn -Q HTTP/vault.local.lab 2>&1 | Out-String
Write-Host "Updated SPN registration:" -ForegroundColor White
Write-Host $newSpnQuery -ForegroundColor Gray

Write-Host ""
Write-Host "Step 4: Testing authentication again..." -ForegroundColor Yellow
Write-Host "Run: .\simple-kerberos-test.ps1" -ForegroundColor White

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "SPN REGISTRATION FIX COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
