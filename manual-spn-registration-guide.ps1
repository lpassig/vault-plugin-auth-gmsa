# Manual SPN Registration Guide
# This script provides manual steps for SPN registration when automated methods fail

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$SPN = "HTTP/vault.local.lab"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Manual SPN Registration Guide" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "ISSUE DETECTED:" -ForegroundColor Red
Write-Host "LDAP Error 0x31 (Invalid Credentials) - Current user lacks permissions" -ForegroundColor Red
Write-Host ""

Write-Host "SOLUTION:" -ForegroundColor Yellow
Write-Host "You need to run SPN commands as a Domain Administrator" -ForegroundColor White
Write-Host ""

Write-Host "MANUAL STEPS:" -ForegroundColor Yellow
Write-Host ""

Write-Host "1. Open Command Prompt as Domain Administrator:" -ForegroundColor Cyan
Write-Host "   - Right-click Command Prompt" -ForegroundColor White
Write-Host "   - Select 'Run as Administrator'" -ForegroundColor White
Write-Host "   - Or use a Domain Admin account" -ForegroundColor White
Write-Host ""

Write-Host "2. Check current SPN registration:" -ForegroundColor Cyan
Write-Host "   setspn -Q $SPN" -ForegroundColor Gray
Write-Host ""

Write-Host "3. Remove any existing SPN registration:" -ForegroundColor Cyan
Write-Host "   setspn -D $SPN" -ForegroundColor Gray
Write-Host ""

Write-Host "4. Register SPN to gMSA account:" -ForegroundColor Cyan
Write-Host "   setspn -A $SPN $GMSAAccount" -ForegroundColor Gray
Write-Host ""

Write-Host "5. Verify SPN registration:" -ForegroundColor Cyan
Write-Host "   setspn -Q $SPN" -ForegroundColor Gray
Write-Host ""

Write-Host "6. List all SPNs for gMSA account:" -ForegroundColor Cyan
Write-Host "   setspn -L $GMSAAccount" -ForegroundColor Gray
Write-Host ""

Write-Host "ALTERNATIVE: Use Active Directory Users and Computers:" -ForegroundColor Yellow
Write-Host "1. Open 'Active Directory Users and Computers'" -ForegroundColor White
Write-Host "2. Navigate to 'Managed Service Accounts'" -ForegroundColor White
Write-Host "3. Find 'vault-gmsa$' account" -ForegroundColor White
Write-Host "4. Right-click → Properties → Attribute Editor" -ForegroundColor White
Write-Host "5. Find 'servicePrincipalName' attribute" -ForegroundColor White
Write-Host "6. Add value: $SPN" -ForegroundColor White
Write-Host ""

Write-Host "VERIFICATION:" -ForegroundColor Yellow
Write-Host "After manual registration, run this script again to verify:" -ForegroundColor White
Write-Host "   .\check-and-register-spn.ps1" -ForegroundColor Gray
Write-Host ""

Write-Host "EXPECTED RESULTS:" -ForegroundColor Yellow
Write-Host "You should see:" -ForegroundColor White
Write-Host "   - SUCCESS: SPN $SPN registered to $GMSAAccount" -ForegroundColor Green
Write-Host "   - SUCCESS: SPN registration verified!" -ForegroundColor Green
Write-Host ""

Write-Host "NEXT STEPS AFTER SPN REGISTRATION:" -ForegroundColor Yellow
Write-Host "1. Run: .\fix-gmsa-task-permissions.ps1" -ForegroundColor White
Write-Host "2. Test scheduled task: Start-ScheduledTask -TaskName 'Vault-gMSA-Authentication'" -ForegroundColor White
Write-Host "3. Check results: .\check-gmsa-task-status.ps1" -ForegroundColor White
Write-Host "4. Test authentication: .\test-gmsa-authentication.ps1" -ForegroundColor White
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Manual Registration Guide Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "IMPORTANT NOTES:" -ForegroundColor Red
Write-Host "- SPN registration requires Domain Administrator privileges" -ForegroundColor White
Write-Host "- The gMSA account must exist in Active Directory" -ForegroundColor White
Write-Host "- DNS resolution is working correctly (vault.local.lab → 10.0.101.8)" -ForegroundColor White
Write-Host "- Once SPN is registered, the scheduled task should work" -ForegroundColor White
Write-Host ""
