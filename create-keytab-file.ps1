# Quick script to create the keytab file for Step 6

# The keytab you provided earlier (this is the vault-keytab-svc keytab)
$keytabB64 = "BQIAAABRAAIACUxPQ0FMLkxBQgAESFRUUAAPdmF1bHQubG9jYWwubGFiAAAAAQAAAAAFABIAILBYBG52/nfd2vUaZ1VDMhXQYJTe/rtdnuknqsm8vbhj"

# Save it to the file the script is looking for
$keytabB64 | Out-File "vault-gmsa.keytab.b64" -Encoding ASCII -NoNewline

Write-Host "✓ Created vault-gmsa.keytab.b64" -ForegroundColor Green
Write-Host ""
Write-Host "Note: This is a temporary keytab from vault-keytab-svc" -ForegroundColor Yellow
Write-Host "Vault's auto-rotation will replace it with a proper gMSA keytab automatically" -ForegroundColor Yellow
Write-Host ""
Write-Host "Now you can continue with Step 6:" -ForegroundColor Cyan
Write-Host "  .\setup-gmsa-production.ps1 -Step 6" -ForegroundColor White
