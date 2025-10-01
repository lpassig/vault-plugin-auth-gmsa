# Simple Protocol Fix - Update Windows Client to Use HTTPS
param(
    [string]$VaultAddr = "https://vault.local.lab:8200"
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "SIMPLE PROTOCOL FIX" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Issue: Windows client uses HTTP but Vault Docker expects HTTPS" -ForegroundColor Yellow
Write-Host ""

# Test HTTPS connectivity
Write-Host "Testing HTTPS connectivity..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://vault.local.lab:8200/v1/sys/health" -Method GET -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    Write-Host "✓ HTTPS connectivity successful" -ForegroundColor Green
} catch {
    Write-Host "❌ HTTPS connectivity failed: $_" -ForegroundColor Red
}

Write-Host ""

# Test authentication with HTTPS
Write-Host "Testing Kerberos authentication with HTTPS..." -ForegroundColor Yellow
try {
    $body = @{role = "computer-accounts"} | ConvertTo-Json -Compress
    $headers = @{
        "Content-Type" = "application/json"
    }
    
    $response = Invoke-WebRequest -Uri "https://vault.local.lab:8200/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    
    if ($response.StatusCode -eq 200) {
        Write-Host "✓ Authentication successful with HTTPS!" -ForegroundColor Green
        $responseData = $response.Content | ConvertFrom-Json
        if ($responseData.auth.client_token) {
            Write-Host "✓ Token received!" -ForegroundColor Green
        }
    }
} catch {
    $errorResponse = $_.Exception.Response
    if ($errorResponse) {
        $statusCode = $errorResponse.StatusCode
        Write-Host "❌ Authentication failed with status: $statusCode" -ForegroundColor Red
        
        if ($statusCode -eq 401) {
            Write-Host "Still getting 401 - run: .\fix-spn-registration.ps1" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ Network error: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "PROTOCOL TEST COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green


