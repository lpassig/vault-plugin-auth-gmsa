# Quick gMSA Authentication Test
# This script quickly tests gMSA authentication without complex setup

param(
    [string]$VaultUrl = "http://10.0.101.8:8200"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Quick gMSA Authentication Test" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Current Identity: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor White
Write-Host "Vault URL: $VaultUrl" -ForegroundColor White
Write-Host ""

# Test 1: Basic connectivity
Write-Host "Test 1: Vault Server Connectivity" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$VaultUrl/v1/sys/health" -UseBasicParsing -TimeoutSec 5
    Write-Host "SUCCESS: Vault server is reachable" -ForegroundColor Green
    Write-Host "  Status: $($response.StatusCode)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Cannot reach Vault server" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 2: Kerberos authentication
Write-Host "Test 2: Kerberos Authentication" -ForegroundColor Yellow
try {
    Write-Host "Attempting Kerberos authentication..." -ForegroundColor Cyan
    
    $authResponse = Invoke-RestMethod `
        -Uri "$VaultUrl/v1/auth/kerberos/login" `
        -Method Post `
        -UseDefaultCredentials `
        -UseBasicParsing `
        -ErrorAction Stop
    
    if ($authResponse.auth -and $authResponse.auth.client_token) {
        Write-Host "SUCCESS: Kerberos authentication successful!" -ForegroundColor Green
        Write-Host "  Token: $($authResponse.auth.client_token.Substring(0,20))..." -ForegroundColor Gray
        Write-Host "  TTL: $($authResponse.auth.lease_duration) seconds" -ForegroundColor Gray
        
        # Test 3: Secret retrieval
        Write-Host ""
        Write-Host "Test 3: Secret Retrieval" -ForegroundColor Yellow
        try {
            $secretResponse = Invoke-RestMethod `
                -Uri "$VaultUrl/v1/secret/data/gmsa-test" `
                -Method Get `
                -Headers @{ "X-Vault-Token" = $authResponse.auth.client_token } `
                -UseBasicParsing
            
            Write-Host "SUCCESS: Secret retrieved successfully!" -ForegroundColor Green
            Write-Host "  Data: $($secretResponse.data.data | ConvertTo-Json -Compress)" -ForegroundColor Gray
            
        } catch {
            Write-Host "WARNING: Secret retrieval failed" -ForegroundColor Yellow
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
            Write-Host "  This might be expected if the secret doesn't exist" -ForegroundColor Gray
        }
        
    } else {
        Write-Host "WARNING: Authentication response missing auth data" -ForegroundColor Yellow
        Write-Host "  Response: $($authResponse | ConvertTo-Json -Compress)" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "ERROR: Kerberos authentication failed" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    
    # Check if it's a specific error
    if ($_.Exception.Message -match "401") {
        Write-Host "  This is a 401 Unauthorized - authentication failed" -ForegroundColor Yellow
    } elseif ($_.Exception.Message -match "403") {
        Write-Host "  This is a 403 Forbidden - access denied" -ForegroundColor Yellow
    } elseif ($_.Exception.Message -match "404") {
        Write-Host "  This is a 404 Not Found - endpoint doesn't exist" -ForegroundColor Yellow
    }
}
Write-Host ""

# Test 4: Check Kerberos tickets
Write-Host "Test 4: Kerberos Tickets" -ForegroundColor Yellow
try {
    $klistOutput = klist 2>&1
    Write-Host "Kerberos tickets:" -ForegroundColor White
    Write-Host $klistOutput -ForegroundColor Gray
    
    if ($klistOutput -match "HTTP/vault.local.lab") {
        Write-Host "SUCCESS: Found ticket for HTTP/vault.local.lab" -ForegroundColor Green
    } else {
        Write-Host "WARNING: No ticket found for HTTP/vault.local.lab" -ForegroundColor Yellow
        Write-Host "  This might be why authentication is failing" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Could not check Kerberos tickets" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Quick Test Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "ANALYSIS:" -ForegroundColor Yellow
if ($authResponse.auth -and $authResponse.auth.client_token) {
    Write-Host "SUCCESS: gMSA authentication is working!" -ForegroundColor Green
    Write-Host "The issue is with scheduled task permissions, not authentication itself." -ForegroundColor Green
    Write-Host "Use Windows Service or manual execution instead of scheduled tasks." -ForegroundColor Green
} else {
    Write-Host "ISSUE: gMSA authentication is not working" -ForegroundColor Red
    Write-Host "Check:" -ForegroundColor Yellow
    Write-Host "  1. SPN registration (HTTP/vault.local.lab -> LOCAL\vault-gmsa$)" -ForegroundColor White
    Write-Host "  2. Vault server keytab configuration" -ForegroundColor White
    Write-Host "  3. DNS resolution (vault.local.lab -> 10.0.101.8)" -ForegroundColor White
    Write-Host "  4. Kerberos ticket availability" -ForegroundColor White
}
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. If authentication worked: Use Windows Service approach" -ForegroundColor White
Write-Host "2. If authentication failed: Check Vault server configuration" -ForegroundColor White
Write-Host "3. Run this script under gMSA identity to test properly" -ForegroundColor White
Write-Host ""

Write-Host "MANUAL GMSA TEST:" -ForegroundColor Cyan
Write-Host "runas /user:LOCAL\vault-gmsa$ 'PowerShell -ExecutionPolicy Bypass -File .\quick-auth-test.ps1'" -ForegroundColor Gray
Write-Host ""
