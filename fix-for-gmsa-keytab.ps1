# =============================================================================
# Fix: Regenerate Keytab for gMSA and Restore SPN
# =============================================================================
# This script reverses the SPN move and creates a proper keytab for gMSA
# =============================================================================

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  gMSA Keytab Fix - Restore and Regenerate" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Step 1: Restore SPN to gMSA
Write-Host "[1] Restoring SPN to gMSA account..." -ForegroundColor Yellow
Write-Host ""

Write-Host "Removing SPN from vault-keytab-svc..." -ForegroundColor Cyan
setspn -D HTTP/vault.local.lab vault-keytab-svc

Write-Host ""
Write-Host "Adding SPN back to vault-gmsa..." -ForegroundColor Cyan
setspn -A HTTP/vault.local.lab vault-gmsa

Write-Host ""
Write-Host "✓ SPN restored to gMSA" -ForegroundColor Green
Write-Host ""

# Step 2: Verify SPN registration
Write-Host "[2] Verifying SPN registration..." -ForegroundColor Yellow
Write-Host ""

$spnCheck = setspn -L vault-gmsa
Write-Host $spnCheck
Write-Host ""

if ($spnCheck -match "HTTP/vault.local.lab") {
    Write-Host "✓ SPN correctly registered to vault-gmsa" -ForegroundColor Green
} else {
    Write-Host "✗ SPN verification failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 3: Generate keytab for gMSA
Write-Host "[3] Generating keytab for gMSA..." -ForegroundColor Yellow
Write-Host ""

Write-Host "⚠️  CRITICAL INSTRUCTIONS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "The ktpass command will ask: 'Do you want to change the password? (y/n)'" -ForegroundColor White
Write-Host "YOU MUST ANSWER: n (NO)" -ForegroundColor Red
Write-Host ""
Write-Host "If you answer 'y' (yes), it will RESET the gMSA managed password and BREAK the account!" -ForegroundColor Red
Write-Host ""
Write-Host "Press Enter to continue or Ctrl+C to abort..." -ForegroundColor Yellow
Read-Host

Write-Host ""
Write-Host "Running ktpass for gMSA (answer 'n' when prompted)..." -ForegroundColor Cyan
Write-Host ""

# IMPORTANT: This will prompt for password change - user must answer 'n' (no)
ktpass -princ HTTP/vault.local.lab@LOCAL.LAB `
    -mapuser LOCAL\vault-gmsa$ `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -pass * `
    -out vault-gmsa.keytab

Write-Host ""

if (Test-Path "vault-gmsa.keytab") {
    Write-Host "✓ Keytab file created: vault-gmsa.keytab" -ForegroundColor Green
    
    # Get file size
    $fileSize = (Get-Item "vault-gmsa.keytab").Length
    Write-Host "  File size: $fileSize bytes" -ForegroundColor Cyan
    
    # Step 4: Convert to base64
    Write-Host ""
    Write-Host "[4] Converting keytab to base64..." -ForegroundColor Yellow
    Write-Host ""
    
    $keytabBytes = [System.IO.File]::ReadAllBytes((Resolve-Path "vault-gmsa.keytab").Path)
    $keytabBase64 = [System.Convert]::ToBase64String($keytabBytes)
    
    # Save base64 to file
    $keytabBase64 | Out-File "vault-gmsa.keytab.b64" -Encoding ASCII
    
    Write-Host "✓ Base64 keytab saved to: vault-gmsa.keytab.b64" -ForegroundColor Green
    Write-Host ""
    
    # Step 5: Display next steps
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ KEYTAB GENERATION COMPLETE" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Copy the keytab to your Vault server:" -ForegroundColor White
    Write-Host "   scp vault-gmsa.keytab.b64 user@vault-server:/tmp/" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "2. On the Vault server, update the configuration:" -ForegroundColor White
    Write-Host "   vault write auth/gmsa/config \\" -ForegroundColor Yellow
    Write-Host "     realm='LOCAL.LAB' \\" -ForegroundColor Yellow
    Write-Host "     kdcs='addc.local.lab' \\" -ForegroundColor Yellow
    Write-Host "     spn='HTTP/vault.local.lab' \\" -ForegroundColor Yellow
    Write-Host "     keytab=`"`$(cat /tmp/vault-gmsa.keytab.b64)`" \\" -ForegroundColor Yellow
    Write-Host "     clock_skew_sec=300 \\" -ForegroundColor Yellow
    Write-Host "     allow_channel_binding=true" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "3. Test the authentication:" -ForegroundColor White
    Write-Host "   Start-ScheduledTask -TaskName 'VaultClientApp'" -ForegroundColor Yellow
    Write-Host "   Get-Content 'C:\vault-client\config\vault-client.log' -Tail 30" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "Expected Result:" -ForegroundColor Cyan
    Write-Host "  [SUCCESS] Real SPNEGO token generated!" -ForegroundColor Green
    Write-Host "  [SUCCESS] Vault authentication successful!" -ForegroundColor Green
    Write-Host ""
    
} else {
    Write-Host "✗ Keytab file was not created!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possible reasons:" -ForegroundColor Yellow
    Write-Host "  1. You answered 'y' to the password change prompt (should be 'n')" -ForegroundColor White
    Write-Host "  2. Insufficient permissions to run ktpass" -ForegroundColor White
    Write-Host "  3. gMSA account issue" -ForegroundColor White
    Write-Host ""
    Write-Host "Try again and make sure to answer 'n' (NO) when asked about password change!" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
