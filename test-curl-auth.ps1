# Quick Test: curl.exe Authentication with --negotiate
# Run this directly to test if curl.exe can authenticate

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$Role = "vault-gmsa-role"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing curl.exe Authentication" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check current user
Write-Host "Current User: $(whoami)" -ForegroundColor Yellow
Write-Host ""

# Check if curl.exe exists
$curlPath = "C:\Windows\System32\curl.exe"
if (-not (Test-Path $curlPath)) {
    Write-Host "ERROR: curl.exe not found at $curlPath" -ForegroundColor Red
    exit 1
}
Write-Host "✓ curl.exe found at $curlPath" -ForegroundColor Green
Write-Host ""

# Check Kerberos tickets
Write-Host "Checking Kerberos tickets..." -ForegroundColor Yellow
try {
    $ticketsOutput = klist 2>&1 | Out-String
    if ($ticketsOutput -match "krbtgt") {
        Write-Host "✓ Kerberos TGT present" -ForegroundColor Green
    } else {
        Write-Host "⚠ Warning: No Kerberos TGT found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ Warning: Could not check Kerberos tickets" -ForegroundColor Yellow
}
Write-Host ""

# Prepare request body
$bodyJson = @{ role = $Role } | ConvertTo-Json
Write-Host "Request Body: $bodyJson" -ForegroundColor Yellow
Write-Host ""

# Build curl command
$curlArgs = @(
    "--negotiate",
    "--user", ":",
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", $bodyJson,
    "-k",  # Skip SSL verification
    "-s",  # Silent mode
    "-w", "`nHTTP_CODE:%{http_code}",  # Show HTTP status code
    "$VaultUrl/v1/auth/gmsa/login"
)

Write-Host "Executing curl.exe command:" -ForegroundColor Cyan
Write-Host "  curl.exe $($curlArgs -join ' ')" -ForegroundColor Gray
Write-Host ""

# Execute curl
Write-Host "Sending authentication request..." -ForegroundColor Yellow
$curlOutput = & $curlPath $curlArgs 2>&1 | Out-String

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "curl.exe Output:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host $curlOutput
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Parse response
try {
    # Extract HTTP code
    if ($curlOutput -match "HTTP_CODE:(\d+)") {
        $httpCode = $matches[1]
        $responseBody = $curlOutput -replace "HTTP_CODE:\d+", ""
        
        Write-Host "HTTP Status Code: $httpCode" -ForegroundColor $(if ($httpCode -eq "200") { "Green" } else { "Red" })
        Write-Host ""
        
        # Try to parse JSON
        $authResponse = $responseBody | ConvertFrom-Json
        
        if ($authResponse.auth -and $authResponse.auth.client_token) {
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "✓ SUCCESS: Authentication Successful!" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "Client Token: $($authResponse.auth.client_token)" -ForegroundColor Green
            Write-Host "Token TTL: $($authResponse.auth.lease_duration) seconds" -ForegroundColor Green
            Write-Host "Renewable: $($authResponse.auth.renewable)" -ForegroundColor Green
            Write-Host ""
            Write-Host "✓ curl.exe with --negotiate WORKS!" -ForegroundColor Green
            exit 0
        } elseif ($authResponse.errors) {
            Write-Host "========================================" -ForegroundColor Red
            Write-Host "✗ Authentication Failed" -ForegroundColor Red
            Write-Host "========================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "Vault Error: $($authResponse.errors -join ', ')" -ForegroundColor Red
            Write-Host ""
            Write-Host "Possible causes:" -ForegroundColor Yellow
            Write-Host "  - SPNEGO token not generated (gMSA issue)" -ForegroundColor Yellow
            Write-Host "  - Keytab mismatch on Vault server" -ForegroundColor Yellow
            Write-Host "  - Role not configured correctly" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "Could not extract HTTP status code from output" -ForegroundColor Yellow
    }
} catch {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "✗ Failed to Parse Response" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "This might mean:" -ForegroundColor Yellow
    Write-Host "  - curl.exe returned an error" -ForegroundColor Yellow
    Write-Host "  - Network connectivity issue" -ForegroundColor Yellow
    Write-Host "  - Vault server not responding" -ForegroundColor Yellow
    exit 1
}

Write-Host "Test completed" -ForegroundColor Cyan
