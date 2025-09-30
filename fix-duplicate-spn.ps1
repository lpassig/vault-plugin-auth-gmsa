# =============================================================================
# Fix Duplicate SPN Issue
# =============================================================================
# This script identifies and resolves duplicate SPN registrations
# =============================================================================

param(
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$CorrectAccount = "vault-gmsa"
)

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Duplicate SPN Resolution Tool" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Step 1: Find where the SPN is currently registered
Write-Host "[1] Searching for existing SPN registration..." -ForegroundColor Yellow
Write-Host "    SPN: $SPN" -ForegroundColor Cyan
Write-Host ""

$searchResult = setspn -Q $SPN 2>&1

if ($searchResult -match "Existing SPN found") {
    Write-Host "✓ Found existing SPN registration:" -ForegroundColor Green
    Write-Host ""
    $searchResult | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    Write-Host ""
    
    # Extract the account name from the output
    $accountLines = $searchResult | Where-Object { $_ -match "CN=" }
    
    if ($accountLines) {
        Write-Host "[2] SPN is currently registered to:" -ForegroundColor Yellow
        $accountLines | ForEach-Object { 
            Write-Host "    $_" -ForegroundColor Cyan
            
            # Try to extract just the account name
            if ($_ -match "CN=([^,]+)") {
                $currentAccount = $matches[1]
                Write-Host "    Account: $currentAccount" -ForegroundColor White
            }
        }
        Write-Host ""
        
        # Step 2: Determine action
        if ($accountLines -match $CorrectAccount) {
            Write-Host "✓ SPN is already registered to the correct account: $CorrectAccount" -ForegroundColor Green
            Write-Host ""
            Write-Host "No action needed! The SPN is correctly configured." -ForegroundColor Green
            Write-Host ""
            Write-Host "Your authentication should work now. Test with:" -ForegroundColor Cyan
            Write-Host "  Start-ScheduledTask -TaskName 'VaultClientApp'" -ForegroundColor White
            Write-Host ""
            exit 0
        } else {
            Write-Host "✗ SPN is registered to a DIFFERENT account (not $CorrectAccount)" -ForegroundColor Red
            Write-Host ""
            Write-Host "This is the cause of your 0x80090308 error!" -ForegroundColor Yellow
            Write-Host ""
            
            # Step 3: Provide fix options
            Write-Host "[3] Fix Options:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Option 1: Remove SPN from wrong account and add to correct account" -ForegroundColor Cyan
            Write-Host "-------------------------------------------------------------------" -ForegroundColor Gray
            
            foreach ($line in $accountLines) {
                if ($line -match "CN=([^,]+)") {
                    $wrongAccount = $matches[1]
                    if ($wrongAccount -ne $CorrectAccount) {
                        Write-Host ""
                        Write-Host "Step A: Remove from wrong account ($wrongAccount):" -ForegroundColor White
                        Write-Host "  setspn -D $SPN $wrongAccount" -ForegroundColor Yellow
                        Write-Host ""
                        Write-Host "Step B: Add to correct account ($CorrectAccount):" -ForegroundColor White
                        Write-Host "  setspn -A $SPN $CorrectAccount" -ForegroundColor Yellow
                        Write-Host ""
                        
                        # Offer to do it automatically
                        Write-Host "Do you want to fix this automatically? (Y/N): " -ForegroundColor Cyan -NoNewline
                        $response = Read-Host
                        
                        if ($response -eq 'Y' -or $response -eq 'y') {
                            Write-Host ""
                            Write-Host "Executing fix..." -ForegroundColor Cyan
                            
                            # Remove from wrong account
                            Write-Host "  Removing SPN from $wrongAccount..." -ForegroundColor Yellow
                            $removeResult = setspn -D $SPN $wrongAccount 2>&1
                            
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "  ✓ Successfully removed SPN from $wrongAccount" -ForegroundColor Green
                                
                                # Add to correct account
                                Write-Host "  Adding SPN to $CorrectAccount..." -ForegroundColor Yellow
                                $addResult = setspn -A $SPN $CorrectAccount 2>&1
                                
                                if ($LASTEXITCODE -eq 0) {
                                    Write-Host "  ✓ Successfully added SPN to $CorrectAccount" -ForegroundColor Green
                                    Write-Host ""
                                    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
                                    Write-Host "  ✓ FIX COMPLETE - SPN is now correctly registered!" -ForegroundColor Green
                                    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
                                    Write-Host ""
                                    
                                    # Verify
                                    Write-Host "Verification:" -ForegroundColor Cyan
                                    $verifyResult = setspn -L $CorrectAccount
                                    $verifyResult | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
                                    Write-Host ""
                                    
                                    Write-Host "Next Steps:" -ForegroundColor Cyan
                                    Write-Host "  1. Wait 30 seconds for AD replication" -ForegroundColor White
                                    Write-Host "  2. Test authentication:" -ForegroundColor White
                                    Write-Host "     Start-ScheduledTask -TaskName 'VaultClientApp'" -ForegroundColor Yellow
                                    Write-Host "  3. Check logs:" -ForegroundColor White
                                    Write-Host "     Get-Content 'C:\vault-client\config\vault-client.log' -Tail 30" -ForegroundColor Yellow
                                    Write-Host ""
                                    Write-Host "Expected result: [SUCCESS] Vault authentication successful!" -ForegroundColor Green
                                    Write-Host ""
                                    exit 0
                                } else {
                                    Write-Host "  ✗ Failed to add SPN to $CorrectAccount" -ForegroundColor Red
                                    Write-Host "  Error: $addResult" -ForegroundColor Red
                                    exit 1
                                }
                            } else {
                                Write-Host "  ✗ Failed to remove SPN from $wrongAccount" -ForegroundColor Red
                                Write-Host "  Error: $removeResult" -ForegroundColor Red
                                exit 1
                            }
                        } else {
                            Write-Host ""
                            Write-Host "Fix cancelled. Please run the commands manually when ready." -ForegroundColor Yellow
                            Write-Host ""
                            exit 0
                        }
                    }
                }
            }
            
            Write-Host ""
            Write-Host "Option 2: Use the wrong account's keytab in Vault" -ForegroundColor Cyan
            Write-Host "---------------------------------------------------" -ForegroundColor Gray
            Write-Host "If the SPN is registered to a different service account," -ForegroundColor White
            Write-Host "you can generate a keytab for THAT account instead:" -ForegroundColor White
            Write-Host ""
            Write-Host "  ktpass -out vault.keytab \\" -ForegroundColor Yellow
            Write-Host "    -princ $SPN@LOCAL.LAB \\" -ForegroundColor Yellow
            Write-Host "    -mapUser <current-account-name> \\" -ForegroundColor Yellow
            Write-Host "    -pass * \\" -ForegroundColor Yellow
            Write-Host "    -crypto AES256-SHA1" -ForegroundColor Yellow
            Write-Host ""
        }
    }
} else {
    Write-Host "✗ No existing SPN found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "This is unexpected. The error said 'Duplicate SPN found' but we can't locate it." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Try these diagnostic commands:" -ForegroundColor Cyan
    Write-Host "  setspn -Q $SPN" -ForegroundColor Yellow
    Write-Host "  setspn -L $CorrectAccount" -ForegroundColor Yellow
    Write-Host "  setspn -T local.lab -Q */*" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
