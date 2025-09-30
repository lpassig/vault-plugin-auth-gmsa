# Verify if gMSA password has rotated
# Run this as SYSTEM on ADDC: PsExec64.exe -s -i powershell.exe

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Verify gMSA Password Rotation" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check current user
$currentUser = whoami
Write-Host "Current User: $currentUser" -ForegroundColor Yellow

if ($currentUser -ne "nt authority\system") {
    Write-Host "ERROR: Must run as SYSTEM" -ForegroundColor Red
    Write-Host "Use: PsExec64.exe -s -i powershell.exe" -ForegroundColor Yellow
    exit 1
}

# Get the gMSA account
Write-Host "Retrieving gMSA account: vault-gmsa..." -ForegroundColor Cyan
$gmsa = Get-ADServiceAccount -Identity vault-gmsa -Properties 'msDS-ManagedPassword', 'msDS-ManagedPasswordId'

# Get the password blob
$passwordBlob = $gmsa.'msDS-ManagedPassword'

if ($passwordBlob -eq $null) {
    Write-Host "ERROR: No password blob retrieved" -ForegroundColor Red
    exit 1
}

Write-Host "SUCCESS: Got password blob ($($passwordBlob.Length) bytes)" -ForegroundColor Green
Write-Host ""

# Extract the current password (bytes 16-271)
$currentPasswordBytes = $passwordBlob[16..271]

# For AES256, we need the first 32 bytes of the password
$aes256KeyBytes = $currentPasswordBytes[0..31]

# Convert to hex for comparison
$currentKeyHex = -join ($aes256KeyBytes | ForEach-Object { '{0:X2}' -f $_ })

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Current AES256 Key:" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host $currentKeyHex -ForegroundColor White
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Previous AES256 Key (from keytab):" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan
$previousKeyHex = "B5B19043ACDEC75EB1302B8BE1111E5CD3B3E6CEA147AA9C947542991CBEB7DC"
Write-Host $previousKeyHex -ForegroundColor White
Write-Host ""

if ($currentKeyHex -eq $previousKeyHex) {
    Write-Host "✓ MATCH: Keys are identical - password has NOT rotated" -ForegroundColor Green
} else {
    Write-Host "✗ MISMATCH: Keys are different - PASSWORD HAS ROTATED!" -ForegroundColor Red
    Write-Host ""
    Write-Host "ACTION REQUIRED:" -ForegroundColor Yellow
    Write-Host "The gMSA password has rotated since the keytab was generated." -ForegroundColor Yellow
    Write-Host "You need to update the Vault keytab with the new key." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Run: .\extract-aes-key.ps1" -ForegroundColor Cyan
    Write-Host "Then update Vault with the new keytab" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Additional Information:" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "gMSA Password ID: $($gmsa.'msDS-ManagedPasswordId')" -ForegroundColor Gray
Write-Host "Password Blob Length: $($passwordBlob.Length) bytes" -ForegroundColor Gray
Write-Host ""
