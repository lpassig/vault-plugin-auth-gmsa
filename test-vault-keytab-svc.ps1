# Test Authentication with vault-keytab-svc Account
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "TEST WITH VAULT-KEYTAB-SVC ACCOUNT" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Issue: SPN is registered to vault-keytab-svc, not EC2AMAZ-UB1QVDL$" -ForegroundColor Yellow
Write-Host "Solution: Test authentication using vault-keytab-svc account" -ForegroundColor Yellow
Write-Host ""

Write-Host "Step 1: Check if vault-keytab-svc account exists..." -ForegroundColor Cyan
try {
    $account = Get-ADUser -Identity "vault-keytab-svc" -ErrorAction Stop
    Write-Host "✓ vault-keytab-svc account found" -ForegroundColor Green
    Write-Host "DN: $($account.DistinguishedName)" -ForegroundColor Gray
} catch {
    Write-Host "❌ vault-keytab-svc account not found: $_" -ForegroundColor Red
    Write-Host "This means the SPN registration is invalid" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 2: Check SPN registration..." -ForegroundColor Cyan
try {
    $spnQuery = setspn -L vault-keytab-svc 2>&1 | Out-String
    Write-Host "SPNs registered to vault-keytab-svc:" -ForegroundColor White
    Write-Host $spnQuery -ForegroundColor Gray
    
    if ($spnQuery -match "HTTP/vault.local.lab") {
        Write-Host "✓ HTTP/vault.local.lab is registered to vault-keytab-svc" -ForegroundColor Green
    } else {
        Write-Host "❌ HTTP/vault.local.lab not found in vault-keytab-svc SPNs" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Could not check SPN registration: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Step 3: Test authentication as vault-keytab-svc..." -ForegroundColor Cyan
Write-Host "Note: This requires knowing the vault-keytab-svc password" -ForegroundColor Yellow

# Try to run as vault-keytab-svc (this will prompt for password)
Write-Host "Attempting to run PowerShell as vault-keytab-svc..." -ForegroundColor White
Write-Host "You will be prompted for the vault-keytab-svc password" -ForegroundColor Yellow

try {
    # This will prompt for password
    $credential = Get-Credential -UserName "LOCAL.LAB\vault-keytab-svc" -Message "Enter vault-keytab-svc password"
    
    if ($credential) {
        Write-Host "✓ Credentials obtained" -ForegroundColor Green
        
        # Test authentication with these credentials
        $body = '{"role":"computer-accounts"}'
        $headers = @{"Content-Type" = "application/json"}
        
        # Use Invoke-WebRequest with credentials
        $response = Invoke-WebRequest -Uri "http://vault.local.lab:8200/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -Credential $credential -UseBasicParsing -ErrorAction SilentlyContinue
        
        if ($response -and $response.StatusCode -eq 200) {
            Write-Host "✓ Authentication successful with vault-keytab-svc!" -ForegroundColor Green
            $responseData = $response.Content | ConvertFrom-Json
            if ($responseData.auth.client_token) {
                Write-Host "✓ Token received!" -ForegroundColor Green
            }
        } else {
            Write-Host "❌ Authentication failed with vault-keytab-svc" -ForegroundColor Red
            Write-Host "Status: $($response.StatusCode)" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "❌ Could not test with vault-keytab-svc: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "VAULT-KEYTAB-SVC TEST COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "If this works, the solution is to:" -ForegroundColor White
Write-Host "1. Use vault-keytab-svc account for authentication" -ForegroundColor Gray
Write-Host "2. Or get domain admin to move SPN to EC2AMAZ-UB1QVDL$" -ForegroundColor Gray
Write-Host "3. Or regenerate keytab for EC2AMAZ-UB1QVDL$" -ForegroundColor Gray


