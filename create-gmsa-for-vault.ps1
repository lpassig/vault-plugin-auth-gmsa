# Create gMSA for Vault Authentication with Automated Password Rotation
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "CREATE GMSA FOR VAULT AUTHENTICATION" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Benefits of gMSA:" -ForegroundColor Yellow
Write-Host "- Automated password rotation (every 30 days)" -ForegroundColor White
Write-Host "- No password management needed" -ForegroundColor White
Write-Host "- Better Kerberos support than computer accounts" -ForegroundColor White
Write-Host "- Designed for service authentication" -ForegroundColor White
Write-Host ""

Write-Host "Step 1: Create gMSA account..." -ForegroundColor Cyan
Write-Host "Run as Domain Administrator:" -ForegroundColor White
Write-Host ""
Write-Host "# Create gMSA" -ForegroundColor Gray
Write-Host "New-ADServiceAccount -Name 'vault-gmsa' -SamAccountName 'vault-gmsa' -DNSHostName 'vault.local.lab' -ServicePrincipalNames 'HTTP/vault.local.lab' -PrincipalsAllowedToRetrieveManagedPassword 'EC2AMAZ-UB1QVDL$'" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 2: Install gMSA on Windows client..." -ForegroundColor Cyan
Write-Host "Run on EC2AMAZ-UB1QVDL:" -ForegroundColor White
Write-Host ""
Write-Host "# Install gMSA" -ForegroundColor Gray
Write-Host "Install-ADServiceAccount -Identity 'vault-gmsa'" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 3: Test gMSA authentication..." -ForegroundColor Cyan
Write-Host "Run this PowerShell script:" -ForegroundColor White
Write-Host ""
Write-Host "# Test gMSA" -ForegroundColor Gray
Write-Host "Test-ADServiceAccount -Identity 'vault-gmsa'" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 4: Generate keytab for gMSA..." -ForegroundColor Cyan
Write-Host "Run as Domain Administrator:" -ForegroundColor White
Write-Host ""
Write-Host "# Generate keytab" -ForegroundColor Gray
Write-Host "ktpass -out vault-gmsa.keytab \" -ForegroundColor Gray
Write-Host "  -princ HTTP/vault.local.lab@LOCAL.LAB \" -ForegroundColor Gray
Write-Host "  -mapUser vault-gmsa$ \" -ForegroundColor Gray
Write-Host "  -pass * \" -ForegroundColor Gray
Write-Host "  -crypto AES256-SHA1 \" -ForegroundColor Gray
Write-Host "  -ptype KRB5_NT_PRINCIPAL \" -ForegroundColor Gray
Write-Host "  +rndpass \" -ForegroundColor Gray
Write-Host "  -setupn \" -ForegroundColor Gray
Write-Host "  -setpass" -ForegroundColor Gray
Write-Host ""

Write-Host "Step 5: Update Vault configuration..." -ForegroundColor Cyan
Write-Host "Copy keytab to Vault server and update config" -ForegroundColor White
Write-Host ""

Write-Host "Step 6: Create scheduled task with gMSA..." -ForegroundColor Cyan
Write-Host "Run this to create scheduled task:" -ForegroundColor White
Write-Host ""
Write-Host "# Create scheduled task" -ForegroundColor Gray
Write-Host "`$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-File C:\vault-client\vault-client-app.ps1'" -ForegroundColor Gray
Write-Host "`$principal = New-ScheduledTaskPrincipal -UserId 'LOCAL.LAB\vault-gmsa$' -LogonType Password" -ForegroundColor Gray
Write-Host "Register-ScheduledTask -TaskName 'VaultGMSAAuth' -Action `$action -Principal `$principal" -ForegroundColor Gray
Write-Host ""

Write-Host "=========================================" -ForegroundColor Green
Write-Host "GMSA SETUP COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Benefits:" -ForegroundColor White
Write-Host "✓ Automated password rotation" -ForegroundColor Green
Write-Host "✓ Better Kerberos support" -ForegroundColor Green
Write-Host "✓ No manual password management" -ForegroundColor Green
Write-Host "✓ Designed for service authentication" -ForegroundColor Green
Write-Host "✓ More secure than computer accounts" -ForegroundColor Green
