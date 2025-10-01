# Ultra Simple Protocol Test
Write-Host "Testing HTTPS connectivity to Vault..." -ForegroundColor Yellow

# Test 1: Basic HTTPS connectivity
$response = Invoke-WebRequest -Uri "https://vault.local.lab:8200/v1/sys/health" -Method GET -UseBasicParsing -SkipCertificateCheck -ErrorAction SilentlyContinue

if ($response) {
    Write-Host "✓ HTTPS connectivity successful" -ForegroundColor Green
} else {
    Write-Host "❌ HTTPS connectivity failed" -ForegroundColor Red
}

Write-Host ""

# Test 2: Kerberos authentication
Write-Host "Testing Kerberos authentication..." -ForegroundColor Yellow

$body = @{role = "computer-accounts"} | ConvertTo-Json -Compress
$headers = @{
    "Content-Type" = "application/json"
}

$authResponse = Invoke-WebRequest -Uri "https://vault.local.lab:8200/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -UseBasicParsing -SkipCertificateCheck -ErrorAction SilentlyContinue

if ($authResponse -and $authResponse.StatusCode -eq 200) {
    Write-Host "✓ Authentication successful!" -ForegroundColor Green
    $responseData = $authResponse.Content | ConvertFrom-Json
    if ($responseData.auth.client_token) {
        Write-Host "✓ Token received!" -ForegroundColor Green
    }
} else {
    Write-Host "❌ Authentication failed" -ForegroundColor Red
    Write-Host "Status: $($authResponse.StatusCode)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Test complete!" -ForegroundColor Cyan


