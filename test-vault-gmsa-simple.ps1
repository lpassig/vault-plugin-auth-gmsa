# =============================================================================
# Simple Vault gMSA Test Script
# =============================================================================
# This script makes a simple test request to check if Vault gMSA is configured
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.example.com:8200"
)

# Bypass SSL certificate validation for testing
try {
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
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    Write-Host "SSL certificate validation bypassed for testing" -ForegroundColor Yellow
} catch {
    Write-Host "Could not bypass SSL certificate validation: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "=== Simple Vault gMSA Test ===" -ForegroundColor Green
Write-Host "Testing Vault server: $VaultUrl" -ForegroundColor Cyan

try {
    # Test 1: Basic health check
    Write-Host "`n1. Testing Vault health..." -ForegroundColor Yellow
    $healthUrl = "$VaultUrl/v1/sys/health"
    $healthResponse = Invoke-RestMethod -Uri $healthUrl -Method GET
    Write-Host "✅ Vault is healthy" -ForegroundColor Green
    Write-Host "   Version: $($healthResponse.version)" -ForegroundColor Cyan
    
    # Test 2: Check auth methods
    Write-Host "`n2. Checking authentication methods..." -ForegroundColor Yellow
    $authUrl = "$VaultUrl/v1/sys/auth"
    $authResponse = Invoke-RestMethod -Uri $authUrl -Method GET
    
    if ($authResponse.data.gmsa) {
        Write-Host "✅ gMSA auth method is enabled" -ForegroundColor Green
        Write-Host "   Type: $($authResponse.data.gmsa.type)" -ForegroundColor Cyan
    } else {
        Write-Host "❌ gMSA auth method is NOT enabled" -ForegroundColor Red
        Write-Host "   Available methods:" -ForegroundColor Yellow
        $authResponse.data.PSObject.Properties | ForEach-Object {
            Write-Host "     - $($_.Name): $($_.Value.type)" -ForegroundColor Gray
        }
    }
    
    # Test 3: Test gMSA login endpoint
    Write-Host "`n3. Testing gMSA login endpoint..." -ForegroundColor Yellow
    $loginUrl = "$VaultUrl/v1/auth/gmsa/login"
    
    try {
        # Make a request without credentials to see what happens
        $request = [System.Net.HttpWebRequest]::Create($loginUrl)
        $request.Method = "POST"
        $request.ContentType = "application/json"
        $request.Timeout = 10000
        
        $body = '{"role":"vault-gmsa-role"}'
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $request.ContentLength = $bodyBytes.Length
        
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $requestStream.Close()
        
        $response = $request.GetResponse()
        Write-Host "❌ Unexpected: Got response without authentication" -ForegroundColor Red
        Write-Host "   Status: $($response.StatusCode)" -ForegroundColor Yellow
        $response.Close()
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode
        Write-Host "✅ Got expected error: $statusCode" -ForegroundColor Green
        
        # Check headers
        $response = $_.Exception.Response
        Write-Host "   Response headers:" -ForegroundColor Cyan
        foreach ($headerName in $response.Headers.AllKeys) {
            Write-Host "     $headerName = $($response.Headers[$headerName])" -ForegroundColor Gray
        }
        
        # Check for WWW-Authenticate
        if ($response.Headers["WWW-Authenticate"]) {
            $wwwAuth = $response.Headers["WWW-Authenticate"]
            Write-Host "✅ WWW-Authenticate header: $wwwAuth" -ForegroundColor Green
            
            if ($wwwAuth -like "*Negotiate*") {
                Write-Host "✅ SPNEGO negotiation is configured!" -ForegroundColor Green
            } else {
                Write-Host "❌ WWW-Authenticate does not contain 'Negotiate'" -ForegroundColor Red
            }
        } else {
            Write-Host "❌ No WWW-Authenticate header found" -ForegroundColor Red
            Write-Host "   This means gMSA auth is not properly configured for SPNEGO" -ForegroundColor Yellow
        }
    }
    
} catch {
    Write-Host "❌ Test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Summary ===" -ForegroundColor Green
Write-Host "If you see 'WWW-Authenticate: Negotiate' above, gMSA is properly configured." -ForegroundColor Yellow
Write-Host "If not, you need to configure the Vault server with the gMSA keytab." -ForegroundColor Yellow
