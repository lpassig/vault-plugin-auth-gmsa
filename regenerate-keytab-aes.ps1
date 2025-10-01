# Regenerate Vault Keytab with AES Encryption
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "REGENERATE VAULT KEYTAB WITH AES" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Issue: Vault keytab uses arcfour-hmac, Windows uses AES" -ForegroundColor Yellow
Write-Host "Solution: Generate new keytab with AES encryption" -ForegroundColor Yellow
Write-Host ""

Write-Host "Step 1: Generate new keytab with AES encryption..." -ForegroundColor Cyan
Write-Host "Run this command as Administrator on Windows:" -ForegroundColor White
Write-Host ""
Write-Host "ktpass -out vault-aes.keytab \" -ForegroundColor Gray
Write-Host "  -princ HTTP/vault.local.lab@LOCAL.LAB \" -ForegroundColor Gray
Write-Host "  -mapUser EC2AMAZ-UB1QVDL$ \" -ForegroundColor Gray
Write-Host "  -pass * \" -ForegroundColor Gray
Write-Host "  -crypto AES256-SHA1 \" -ForegroundColor Gray
Write-Host "  -ptype KRB5_NT_PRINCIPAL \" -ForegroundColor Gray
Write-Host "  +rndpass \" -ForegroundColor Gray
Write-Host "  -setupn \" -ForegroundColor Gray
Write-Host "  -setpass" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 2: Copy keytab to Vault server..." -ForegroundColor Cyan
Write-Host "scp vault-aes.keytab lennart@107.23.32.117:/tmp/" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 3: Update Vault configuration..." -ForegroundColor Cyan
Write-Host "On Vault server, run:" -ForegroundColor White
Write-Host ""
Write-Host "# Convert to base64" -ForegroundColor Gray
Write-Host "KEYTAB_B64=\$(base64 -w 0 /tmp/vault-aes.keytab)" -ForegroundColor Gray
Write-Host ""
Write-Host "# Update Vault config" -ForegroundColor Gray
Write-Host "vault write auth/kerberos/config \" -ForegroundColor Gray
Write-Host "  keytab=\"\$KEYTAB_B64\" \" -ForegroundColor Gray
Write-Host "  service_account=\"HTTP/vault.local.lab\" \" -ForegroundColor Gray
Write-Host "  realm=\"LOCAL.LAB\"" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 4: Test authentication..." -ForegroundColor Cyan
Write-Host ".\simple-kerberos-test.ps1" -ForegroundColor Gray
Write-Host ""

Write-Host "=========================================" -ForegroundColor Green
Write-Host "KEYTAB REGENERATION GUIDE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green


