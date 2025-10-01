# Test gMSA Authentication Without SPN Registration
# This script tests if authentication works even without proper SPN registration

param(
    [string]$VaultUrl = "http://10.0.101.8:8200"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Testing gMSA Authentication (Bypass SPN Check)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "NOTE: SPN registration failed due to insufficient permissions" -ForegroundColor Yellow
Write-Host "This test will try authentication anyway to see if it works" -ForegroundColor Yellow
Write-Host ""

# SSL Certificate bypass for testing
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

Write-Host "Vault Server: $VaultUrl" -ForegroundColor Yellow
Write-Host ""

# Test 1: Check current identity
Write-Host "1. Current Identity Check:" -ForegroundColor Yellow
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Current user: $currentIdentity" -ForegroundColor White

if ($currentIdentity.EndsWith("$")) {
    Write-Host "SUCCESS: Running under gMSA identity!" -ForegroundColor Green
} else {
    Write-Host "WARNING: Not running under gMSA identity" -ForegroundColor Yellow
    Write-Host "SOLUTION: Run this script as a scheduled task under the gMSA account" -ForegroundColor Yellow
}
Write-Host ""

# Test 2: Check Kerberos tickets
Write-Host "2. Kerberos Tickets Check:" -ForegroundColor Yellow
try {
    $klistOutput = klist 2>&1
    Write-Host "Kerberos tickets:" -ForegroundColor White
    Write-Host $klistOutput -ForegroundColor Gray
    
    if ($klistOutput -match "HTTP/vault.local.lab") {
        Write-Host "SUCCESS: Kerberos ticket found for HTTP/vault.local.lab" -ForegroundColor Green
    } else {
        Write-Host "WARNING: No Kerberos ticket found for HTTP/vault.local.lab" -ForegroundColor Yellow
        Write-Host "This is expected if SPN is not registered" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Cannot check Kerberos tickets" -ForegroundColor Red
}
Write-Host ""

# Test 3: Test Vault connectivity
Write-Host "3. Vault Server Connectivity:" -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/health" -Method Get
    Write-Host "SUCCESS: Vault server is reachable" -ForegroundColor Green
    Write-Host "  Initialized: $($health.initialized)" -ForegroundColor Gray
    Write-Host "  Sealed: $($health.sealed)" -ForegroundColor Gray
    Write-Host "  Version: $($health.version)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Cannot reach Vault server" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 4: Test Kerberos authentication with different approaches
Write-Host "4. Kerberos Authentication Test (Multiple Methods):" -ForegroundColor Yellow

# Method 1: Try with vault.local.lab hostname
Write-Host "Method 1: Using vault.local.lab hostname..." -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod `
        -Uri "http://vault.local.lab:8200/v1/auth/kerberos/login" `
        -Method Post `
        -UseDefaultCredentials `
        -UseBasicParsing
    
    if ($response.auth -and $response.auth.client_token) {
        Write-Host "SUCCESS: Authentication successful with vault.local.lab!" -ForegroundColor Green
        Write-Host "Client token: $($response.auth.client_token)" -ForegroundColor Green
        Write-Host "Token TTL: $($response.auth.lease_duration) seconds" -ForegroundColor Green
        Write-Host "Policies: $($response.auth.policies -join ', ')" -ForegroundColor Green
        
        # Test secret retrieval
        Write-Host ""
        Write-Host "5. Secret Retrieval Test:" -ForegroundColor Yellow
        try {
            $headers = @{
                "X-Vault-Token" = $response.auth.client_token
            }
            
            $secrets = Invoke-RestMethod `
                -Uri "$VaultUrl/v1/secret/my-app/database" `
                -Method Get `
                -Headers $headers
            
            Write-Host "SUCCESS: Secrets retrieved!" -ForegroundColor Green
            Write-Host "Database secrets:" -ForegroundColor White
            Write-Host "  Username: $($secrets.data.data.username)" -ForegroundColor Gray
            Write-Host "  Password: $($secrets.data.data.password)" -ForegroundColor Gray
            Write-Host "  Host: $($secrets.data.data.host)" -ForegroundColor Gray
            Write-Host "  Port: $($secrets.data.data.port)" -ForegroundColor Gray
            
        } catch {
            Write-Host "ERROR: Failed to retrieve secrets" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host ""
        Write-Host "🎉 SUCCESS: Complete authentication flow working!" -ForegroundColor Green
        Write-Host "The SPN registration issue doesn't prevent authentication!" -ForegroundColor Green
        exit 0
        
    } else {
        Write-Host "Method 1 failed: No token received" -ForegroundColor Yellow
    }
    
} catch {
    $statusCode = $_.Exception.Response.StatusCode
    Write-Host "Method 1 failed with status: $statusCode" -ForegroundColor Yellow
}

# Method 2: Try with IP address
Write-Host "Method 2: Using IP address..." -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod `
        -Uri "$VaultUrl/v1/auth/kerberos/login" `
        -Method Post `
        -UseDefaultCredentials `
        -UseBasicParsing
    
    if ($response.auth -and $response.auth.client_token) {
        Write-Host "SUCCESS: Authentication successful with IP address!" -ForegroundColor Green
        Write-Host "Client token: $($response.auth.client_token)" -ForegroundColor Green
        Write-Host "Token TTL: $($response.auth.lease_duration) seconds" -ForegroundColor Green
        Write-Host "Policies: $($response.auth.policies -join ', ')" -ForegroundColor Green
        
        Write-Host ""
        Write-Host "🎉 SUCCESS: Authentication working with IP address!" -ForegroundColor Green
        Write-Host "The Vault server is configured to work without strict SPN matching!" -ForegroundColor Green
        exit 0
        
    } else {
        Write-Host "Method 2 failed: No token received" -ForegroundColor Yellow
    }
    
} catch {
    $statusCode = $_.Exception.Response.StatusCode
    Write-Host "Method 2 failed with status: $statusCode" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "❌ Both authentication methods failed" -ForegroundColor Red
Write-Host "This confirms that SPN registration is required" -ForegroundColor Red
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Test Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "CONCLUSION:" -ForegroundColor Yellow
Write-Host "SPN registration is required for authentication to work" -ForegroundColor White
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Run: .\manual-spn-registration-guide.ps1" -ForegroundColor White
Write-Host "2. Follow manual SPN registration steps as Domain Administrator" -ForegroundColor White
Write-Host "3. After SPN registration, test again with this script" -ForegroundColor White
Write-Host ""
