# Test Kerberos Authentication with Vault Server
# This script tests authentication using the built-in Kerberos auth method

param(
    [string]$VaultUrl = "https://vault.local.lab:8200"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "TESTING KERBEROS AUTHENTICATION" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Bypass SSL certificate validation for testing
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

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Vault URL: $VaultUrl" -ForegroundColor White
Write-Host "  Current User: $(whoami)" -ForegroundColor White
Write-Host ""

# Function to test Kerberos tickets
function Test-KerberosTickets {
    Write-Host "Step 1: Checking Kerberos tickets..." -ForegroundColor Yellow
    Write-Host "------------------------------------" -ForegroundColor Yellow
    
    try {
        $tickets = klist 2>&1
        Write-Host "Kerberos tickets:" -ForegroundColor White
        Write-Host $tickets -ForegroundColor Gray
        
        if ($tickets -match "krbtgt") {
            Write-Host "✓ Kerberos TGT found" -ForegroundColor Green
            return $true
        } else {
            Write-Host "❌ No Kerberos TGT found" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Error checking Kerberos tickets: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to test SPNEGO token generation with curl
function Test-SPNEGOWithCurl {
    Write-Host ""
    Write-Host "Step 2: Testing SPNEGO token generation with curl..." -ForegroundColor Yellow
    Write-Host "----------------------------------------------------" -ForegroundColor Yellow
    
    try {
        if (Get-Command curl -ErrorAction SilentlyContinue) {
            Write-Host "Using curl to generate SPNEGO token..." -ForegroundColor Cyan
            
            $curlOutput = curl --negotiate --user : -v "$VaultUrl/v1/sys/health" 2>&1 | Out-String
            
            if ($curlOutput -match "Authorization: Negotiate ([A-Za-z0-9+/=]+)") {
                $spnegoToken = $matches[1]
                Write-Host "✓ SPNEGO token generated successfully" -ForegroundColor Green
                Write-Host "  Token length: $($spnegoToken.Length) characters" -ForegroundColor Gray
                return $spnegoToken
            } else {
                Write-Host "❌ SPNEGO token generation failed" -ForegroundColor Red
                Write-Host "Curl output:" -ForegroundColor Gray
                Write-Host $curlOutput -ForegroundColor Gray
                return $null
            }
        } else {
            Write-Host "❌ curl command not available" -ForegroundColor Red
            return $null
        }
    } catch {
        Write-Host "❌ Error testing SPNEGO token generation: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Function to test Kerberos authentication
function Test-KerberosAuthentication {
    param([string]$SPNEGOToken)
    
    Write-Host ""
    Write-Host "Step 3: Testing Kerberos authentication..." -ForegroundColor Yellow
    Write-Host "------------------------------------------" -ForegroundColor Yellow
    
    try {
        # Method 1: Try HTTP Negotiate with Invoke-RestMethod
        Write-Host "Method 1: Using Invoke-RestMethod with UseDefaultCredentials..." -ForegroundColor Cyan
        
        $response = Invoke-RestMethod `
            -Uri "$VaultUrl/v1/auth/kerberos/login" `
            -Method Post `
            -UseDefaultCredentials `
            -UseBasicParsing `
            -ErrorAction Stop
        
        if ($response.auth -and $response.auth.client_token) {
            Write-Host "✓ Authentication successful!" -ForegroundColor Green
            Write-Host "  Client Token: $($response.auth.client_token)" -ForegroundColor Gray
            Write-Host "  Token TTL: $($response.auth.lease_duration) seconds" -ForegroundColor Gray
            return $response.auth.client_token
        } else {
            Write-Host "❌ Authentication failed - no token received" -ForegroundColor Red
        }
    } catch {
        Write-Host "Method 1 failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Method 2: Try WebRequest with UseDefaultCredentials
    try {
        Write-Host ""
        Write-Host "Method 2: Using WebRequest with UseDefaultCredentials..." -ForegroundColor Cyan
        
        $request = [System.Net.WebRequest]::Create("$VaultUrl/v1/auth/kerberos/login")
        $request.Method = "POST"
        $request.UseDefaultCredentials = $true
        $request.PreAuthenticate = $true
        $request.UserAgent = "Vault-Kerberos-Client/1.0"
        
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        $response.Close()
        
        $authResponse = $responseBody | ConvertFrom-Json
        if ($authResponse.auth -and $authResponse.auth.client_token) {
            Write-Host "✓ Authentication successful with WebRequest!" -ForegroundColor Green
            Write-Host "  Client Token: $($authResponse.auth.client_token)" -ForegroundColor Gray
            return $authResponse.auth.client_token
        } else {
            Write-Host "❌ Authentication failed - no token received" -ForegroundColor Red
        }
    } catch {
        Write-Host "Method 2 failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Method 3: Try with manual SPNEGO token
    if ($SPNEGOToken) {
        try {
            Write-Host ""
            Write-Host "Method 3: Using manual SPNEGO token..." -ForegroundColor Cyan
            
            $body = @{
                spnego = $SPNEGOToken
            } | ConvertTo-Json
            
            $response = Invoke-RestMethod `
                -Uri "$VaultUrl/v1/auth/kerberos/login" `
                -Method Post `
                -Body $body `
                -ContentType "application/json" `
                -UseBasicParsing
            
            if ($response.auth -and $response.auth.client_token) {
                Write-Host "✓ Authentication successful with manual SPNEGO!" -ForegroundColor Green
                Write-Host "  Client Token: $($response.auth.client_token)" -ForegroundColor Gray
                return $response.auth.client_token
            } else {
                Write-Host "❌ Authentication failed - no token received" -ForegroundColor Red
            }
        } catch {
            Write-Host "Method 3 failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    return $null
}

# Function to test token usage
function Test-TokenUsage {
    param([string]$Token)
    
    Write-Host ""
    Write-Host "Step 4: Testing token usage..." -ForegroundColor Yellow
    Write-Host "-----------------------------" -ForegroundColor Yellow
    
    if (-not $Token) {
        Write-Host "❌ No token available for testing" -ForegroundColor Red
        return $false
    }
    
    try {
        $headers = @{
            "X-Vault-Token" = $Token
        }
        
        $response = Invoke-RestMethod `
            -Uri "$VaultUrl/v1/sys/health" `
            -Method Get `
            -Headers $headers `
            -UseBasicParsing
        
        Write-Host "✓ Token is valid and working!" -ForegroundColor Green
        Write-Host "  Vault Status: $($response.status)" -ForegroundColor Gray
        return $true
    } catch {
        Write-Host "❌ Token validation failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main execution
function Main {
    Write-Host "Starting Kerberos authentication test..." -ForegroundColor Green
    Write-Host ""
    
    # Test Kerberos tickets
    $kerberosTickets = Test-KerberosTickets
    
    # Test SPNEGO token generation
    $spnegoToken = Test-SPNEGOWithCurl
    
    # Test authentication
    $authToken = Test-KerberosAuthentication -SPNEGOToken $spnegoToken
    
    # Test token usage
    $tokenValid = Test-TokenUsage -Token $authToken
    
    # Summary
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "TEST SUMMARY" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Results:" -ForegroundColor Yellow
    Write-Host "  Kerberos Tickets: $(if ($kerberosTickets) { '✓ PASS' } else { '❌ FAIL' })" -ForegroundColor $(if ($kerberosTickets) { 'Green' } else { 'Red' })
    Write-Host "  SPNEGO Generation: $(if ($spnegoToken) { '✓ PASS' } else { '❌ FAIL' })" -ForegroundColor $(if ($spnegoToken) { 'Green' } else { 'Red' })
    Write-Host "  Authentication: $(if ($authToken) { '✓ PASS' } else { '❌ FAIL' })" -ForegroundColor $(if ($authToken) { 'Green' } else { 'Red' })
    Write-Host "  Token Usage: $(if ($tokenValid) { '✓ PASS' } else { '❌ FAIL' })" -ForegroundColor $(if ($tokenValid) { 'Green' } else { 'Red' })
    
    Write-Host ""
    if ($authToken) {
        Write-Host "🎉 SUCCESS: Kerberos authentication is working!" -ForegroundColor Green
        Write-Host "You can now use this authentication method in your applications." -ForegroundColor Green
    } else {
        Write-Host "❌ FAILURE: Kerberos authentication is not working" -ForegroundColor Red
        Write-Host ""
        Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
        Write-Host "1. Verify SPN registration: setspn -Q HTTP/vault.local.lab" -ForegroundColor White
        Write-Host "2. Check Kerberos tickets: klist" -ForegroundColor White
        Write-Host "3. Verify Vault server configuration" -ForegroundColor White
        Write-Host "4. Check Vault server logs" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "TEST COMPLETE" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
}

# Run main function
Main
