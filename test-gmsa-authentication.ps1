# Test gMSA Authentication with Vault Server
# This script tests the complete gMSA authentication flow

param(
    [string]$VaultUrl = "http://10.0.101.8:8200"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Testing gMSA Authentication with Vault" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
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

# Test 4: Test Kerberos authentication
Write-Host "4. Kerberos Authentication Test:" -ForegroundColor Yellow
try {
    Write-Host "Attempting Kerberos authentication..." -ForegroundColor Cyan
    
    # Method 1: Try HTTP Negotiate with UseDefaultCredentials
    try {
        $response = Invoke-RestMethod `
            -Uri "$VaultUrl/v1/auth/kerberos/login" `
            -Method Post `
            -UseDefaultCredentials `
            -UseBasicParsing
        
        if ($response.auth -and $response.auth.client_token) {
            Write-Host "SUCCESS: Kerberos authentication successful!" -ForegroundColor Green
            Write-Host "Client token: $($response.auth.client_token)" -ForegroundColor Green
            Write-Host "Token TTL: $($response.auth.lease_duration) seconds" -ForegroundColor Green
            Write-Host "Policies: $($response.auth.policies -join ', ')" -ForegroundColor Green
            
            # Test 5: Retrieve secrets
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
            
        } else {
            Write-Host "ERROR: Authentication failed - no token received" -ForegroundColor Red
        }
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode
        Write-Host "Authentication failed with status: $statusCode" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $errorBody = $reader.ReadToEnd()
            Write-Host "Error details: $errorBody" -ForegroundColor Red
        }
    }
    
} catch {
    Write-Host "ERROR: Kerberos authentication test failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Test Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. If authentication failed, ensure you're running under gMSA identity" -ForegroundColor White
Write-Host "2. Check that SPN 'HTTP/vault.local.lab' is registered in AD" -ForegroundColor White
Write-Host "3. Verify keytab is configured on Vault server" -ForegroundColor White
Write-Host "4. Run as scheduled task under gMSA account for production use" -ForegroundColor White
Write-Host ""
