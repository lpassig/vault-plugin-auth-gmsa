# Extract AES256 Kerberos Key from gMSA Managed Password Blob
# Run this as SYSTEM on ADDC using: PsExec64.exe -s -i powershell.exe

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Extract AES256 Key from gMSA" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Verify running as SYSTEM
$currentUser = whoami
Write-Host "Current User: $currentUser" -ForegroundColor Yellow
if ($currentUser -ne "nt authority\system") {
    Write-Host "ERROR: Must run as SYSTEM" -ForegroundColor Red
    Write-Host "Use: PsExec64.exe -s -i powershell.exe" -ForegroundColor Yellow
    exit 1
}

# Get the gMSA account
Write-Host "Retrieving gMSA account: vault-gmsa..." -ForegroundColor Cyan
$gmsa = Get-ADServiceAccount -Identity vault-gmsa -Properties 'msDS-ManagedPassword'

# Get the password blob
$passwordBlob = $gmsa.'msDS-ManagedPassword'

if ($passwordBlob -eq $null) {
    Write-Host "ERROR: No password blob retrieved" -ForegroundColor Red
    exit 1
}

Write-Host "SUCCESS: Got password blob ($($passwordBlob.Length) bytes)" -ForegroundColor Green
Write-Host ""

# Extract the current password (bytes 16-271)
# This is the 256-byte current password field
$currentPasswordBytes = $passwordBlob[16..271]

# For AES256, we need the first 32 bytes of the password
$aes256KeyBytes = $currentPasswordBytes[0..31]

# Convert to hex for ktutil
$aes256KeyHex = -join ($aes256KeyBytes | ForEach-Object { '{0:X2}' -f $_ })

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "AES256 Kerberos Key Extracted" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Key Length: 32 bytes (256 bits)" -ForegroundColor Yellow
Write-Host "Hex Key:" -ForegroundColor Yellow
Write-Host $aes256KeyHex -ForegroundColor White
Write-Host ""

# Also output for easy copy-paste
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Copy this hex key for ktutil on Linux:" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
$aes256KeyHex | Set-Clipboard
Write-Host $aes256KeyHex -ForegroundColor White
Write-Host ""
Write-Host "✓ Hex key copied to clipboard!" -ForegroundColor Green
Write-Host ""

# Save to file
$keyFile = "C:\vault-gmsa-aes256-key.txt"
$aes256KeyHex | Out-File -FilePath $keyFile -Encoding ASCII -NoNewline
Write-Host "✓ Key saved to: $keyFile" -ForegroundColor Green
Write-Host ""

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Next Steps on Vault Server (Linux):" -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Create keytab using ktutil:" -ForegroundColor White
Write-Host "   ktutil" -ForegroundColor Gray
Write-Host "   add_entry -password -p HTTP/vault.local.lab@LOCAL.LAB -k 1 -e aes256-cts-hmac-sha1-96" -ForegroundColor Gray
Write-Host "   <paste hex key: $aes256KeyHex>" -ForegroundColor Gray
Write-Host "   write_kt /tmp/vault-gmsa-linux.keytab" -ForegroundColor Gray
Write-Host "   quit" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Base64 encode and update Vault:" -ForegroundColor White
Write-Host "   base64 -w 0 /tmp/vault-gmsa-linux.keytab > /tmp/vault-gmsa.keytab.b64" -ForegroundColor Gray
Write-Host "   export VAULT_SKIP_VERIFY=1" -ForegroundColor Gray
Write-Host "   vault write auth/gmsa/config keytab=`"`$(cat /tmp/vault-gmsa.keytab.b64)`" spn='HTTP/vault.local.lab' realm='LOCAL.LAB' kdcs='ADDC.local.lab:88'" -ForegroundColor Gray
Write-Host ""
