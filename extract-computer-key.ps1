# Extract AES256 Kerberos Key from Computer Account
# Run this on Domain Controller as Administrator

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Extract AES256 Key from Computer Account" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Get the computer account
Write-Host "Retrieving computer account: $ComputerName..." -ForegroundColor Cyan
$computer = Get-ADComputer -Identity $ComputerName -Properties 'msDS-KeyVersionNumber'

if ($computer -eq $null) {
    Write-Host "ERROR: Computer account not found" -ForegroundColor Red
    exit 1
}

Write-Host "SUCCESS: Found computer account" -ForegroundColor Green
Write-Host "DN: $($computer.DistinguishedName)" -ForegroundColor Yellow
Write-Host "Key Version Number: $($computer.'msDS-KeyVersionNumber')" -ForegroundColor Yellow
Write-Host ""

# Use DSInternals to get the computer account's current Kerberos key
try {
    Import-Module DSInternals -ErrorAction Stop
    
    # Get the computer account's supplemental credentials
    Write-Host "Attempting to retrieve Kerberos keys using DSInternals..." -ForegroundColor Cyan
    
    # This requires domain admin privileges
    $key = Get-ADReplAccount -SamAccountName "$ComputerName$" -Server localhost | 
           Select-Object -ExpandProperty KerberosKeys |
           Where-Object { $_.KeyType -eq 'AES256_CTS_HMAC_SHA1_96' } |
           Select-Object -First 1
    
    if ($key -ne $null) {
        $aes256KeyHex = -join ($key.Key | ForEach-Object { '{0:X2}' -f $_ })
        
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host "AES256 Kerberos Key Extracted" -ForegroundColor Green
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Key Length: 32 bytes (256 bits)" -ForegroundColor Yellow
        Write-Host "Hex Key:" -ForegroundColor Yellow
        Write-Host $aes256KeyHex -ForegroundColor White
        Write-Host ""
        
        # Copy to clipboard
        $aes256KeyHex | Set-Clipboard
        Write-Host "✓ Hex key copied to clipboard!" -ForegroundColor Green
        Write-Host ""
        
        # Save to file
        $keyFile = "C:\$ComputerName-aes256-key.txt"
        $aes256KeyHex | Out-File -FilePath $keyFile -Encoding ASCII -NoNewline
        Write-Host "✓ Key saved to: $keyFile" -ForegroundColor Green
        Write-Host ""
        
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host "Next Steps on Vault Server (Linux):" -ForegroundColor Yellow
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Run this command to create and upload the keytab:" -ForegroundColor White
        Write-Host ""
        Write-Host "echo '$aes256KeyHex' | ssh lennart@107.23.32.117" -ForegroundColor Gray
        Write-Host ""
    } else {
        Write-Host "ERROR: No AES256 key found for $ComputerName" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "ERROR: DSInternals method failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host "ALTERNATIVE: Reset Computer Password" -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Since we can't extract the existing key, we need to reset the computer password:" -ForegroundColor White
    Write-Host ""
    Write-Host "1. Generate a new random password and keytab:" -ForegroundColor White
    Write-Host ""
    Write-Host "ktpass -out C:\$ComputerName-http.keytab ``" -ForegroundColor Gray
    Write-Host "  -princ HTTP/vault.local.lab@LOCAL.LAB ``" -ForegroundColor Gray
    Write-Host "  -mapuser CN=$ComputerName,CN=Computers,DC=local,DC=lab ``" -ForegroundColor Gray
    Write-Host "  -crypto AES256-SHA1 ``" -ForegroundColor Gray
    Write-Host "  -ptype KRB5_NT_PRINCIPAL ``" -ForegroundColor Gray
    Write-Host "  +rndpass ``" -ForegroundColor Gray
    Write-Host "  -setupn ``" -ForegroundColor Gray
    Write-Host "  -setpass" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. This WILL reset the computer password!" -ForegroundColor Red
    Write-Host "3. You'll need to rejoin the domain on the Linux server after this." -ForegroundColor Red
    Write-Host ""
}
