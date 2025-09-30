# Quick Test Script for HTTP Negotiate Authentication
# Run this to test if the new authentication method works

param(
    [string]$VaultUrl = "https://vault.local.lab:8200"
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Test HTTP Negotiate Authentication" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Bypass SSL certificate validation
Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint svcPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

# Display current identity
Write-Host "Current Identity: $(whoami)" -ForegroundColor Yellow
Write-Host "Vault URL: $VaultUrl" -ForegroundColor Yellow
Write-Host ""

# Check Kerberos tickets
Write-Host "Checking Kerberos tickets..." -ForegroundColor Cyan
$klistOutput = klist 2>&1
if ($klistOutput -match "HTTP/vault.local.lab") {
    Write-Host "✓ Service ticket found for HTTP/vault.local.lab" -ForegroundColor Green
} else {
    Write-Host "✗ No service ticket for HTTP/vault.local.lab" -ForegroundColor Yellow
    Write-Host "  Attempting to obtain ticket..." -ForegroundColor Cyan
    try {
        klist get HTTP/vault.local.lab 2>&1 | Out-Null
        Write-Host "✓ Service ticket obtained" -ForegroundColor Green
    } catch {
        Write-Host "✗ Could not obtain ticket: $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host ""

# Test 1: Invoke-RestMethod with UseDefaultCredentials
Write-Host "Test 1: Invoke-RestMethod with UseDefaultCredentials" -ForegroundColor Cyan
Write-Host "-----------------------------------------------" -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod `
        -Uri "$VaultUrl/v1/auth/gmsa/login" `
        -Method Post `
        -UseDefaultCredentials `
        -UseBasicParsing `
        -ErrorAction Stop
    
    if ($response.auth -and $response.auth.client_token) {
        Write-Host "✓ SUCCESS!" -ForegroundColor Green
        Write-Host "  Token: $($response.auth.client_token)" -ForegroundColor White
        Write-Host "  TTL: $($response.auth.lease_duration) seconds" -ForegroundColor White
        Write-Host "  Policies: $($response.auth.policies -join ', ')" -ForegroundColor White
        $global:VaultToken = $response.auth.client_token
    } else {
        Write-Host "✗ FAILED: No token in response" -ForegroundColor Red
        Write-Host "  Response: $($response | ConvertTo-Json -Depth 3)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode
        Write-Host "  Status Code: $statusCode" -ForegroundColor Yellow
    }
}
Write-Host ""

# Test 2: WebRequest with UseDefaultCredentials
if (-not $global:VaultToken) {
    Write-Host "Test 2: WebRequest with UseDefaultCredentials" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------" -ForegroundColor Cyan
    try {
        $request = [System.Net.WebRequest]::Create("$VaultUrl/v1/auth/gmsa/login")
        $request.Method = "POST"
        $request.UseDefaultCredentials = $true
        $request.PreAuthenticate = $true
        $request.UserAgent = "Vault-Test-Client/1.0"
        
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        $response.Close()
        
        $authResponse = $responseBody | ConvertFrom-Json
        if ($authResponse.auth -and $authResponse.auth.client_token) {
            Write-Host "✓ SUCCESS!" -ForegroundColor Green
            Write-Host "  Token: $($authResponse.auth.client_token)" -ForegroundColor White
            Write-Host "  TTL: $($authResponse.auth.lease_duration) seconds" -ForegroundColor White
            $global:VaultToken = $authResponse.auth.client_token
        } else {
            Write-Host "✗ FAILED: No token in response" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

# Test 3: Try to retrieve a secret
if ($global:VaultToken) {
    Write-Host "Test 3: Retrieve Secret (Optional)" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------" -ForegroundColor Cyan
    try {
        $secretResponse = Invoke-RestMethod `
            -Uri "$VaultUrl/v1/kv/data/my-app/database" `
            -Method Get `
            -Headers @{"X-Vault-Token" = $global:VaultToken} `
            -UseBasicParsing `
            -ErrorAction Stop
        
        if ($secretResponse.data -and $secretResponse.data.data) {
            Write-Host "✓ SUCCESS: Secret retrieved!" -ForegroundColor Green
            Write-Host "  Keys: $($secretResponse.data.data.Keys -join ', ')" -ForegroundColor White
        } else {
            Write-Host "✗ FAILED: No data in secret response" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  (This is normal if the secret doesn't exist yet)" -ForegroundColor Yellow
    }
    Write-Host ""
}

# Summary
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
if ($global:VaultToken) {
    Write-Host "✅ HTTP Negotiate authentication WORKS!" -ForegroundColor Green
    Write-Host "" 
    Write-Host "Your Vault token: $global:VaultToken" -ForegroundColor White
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Run: .\setup-vault-client.ps1" -ForegroundColor White
    Write-Host "2. This will deploy the new script and create the scheduled task" -ForegroundColor White
    Write-Host "3. Test the task: Start-ScheduledTask -TaskName 'VaultClientApp'" -ForegroundColor White
} else {
    Write-Host "❌ Authentication failed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Verify SPN is registered: setspn -L vault-gmsa" -ForegroundColor White
    Write-Host "2. Check Vault config: vault read auth/gmsa/config" -ForegroundColor White
    Write-Host "3. Verify running as gMSA: whoami" -ForegroundColor White
    Write-Host "4. Check Vault logs for errors" -ForegroundColor White
}
Write-Host ""
