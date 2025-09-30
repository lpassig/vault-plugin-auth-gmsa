Write-Host "Testing HTTPS connectivity..." -ForegroundColor Yellow

$response = Invoke-WebRequest -Uri "https://vault.local.lab:8200/v1/sys/health" -Method GET -UseBasicParsing -SkipCertificateCheck -ErrorAction SilentlyContinue

if ($response) {
    Write-Host "HTTPS connectivity successful" -ForegroundColor Green
} else {
    Write-Host "HTTPS connectivity failed" -ForegroundColor Red
}

Write-Host "Testing Kerberos authentication..." -ForegroundColor Yellow

$body = '{"role":"computer-accounts"}'
$headers = @{"Content-Type" = "application/json"}

$authResponse = Invoke-WebRequest -Uri "https://vault.local.lab:8200/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -UseBasicParsing -SkipCertificateCheck -ErrorAction SilentlyContinue

if ($authResponse -and $authResponse.StatusCode -eq 200) {
    Write-Host "Authentication successful!" -ForegroundColor Green
} else {
    Write-Host "Authentication failed" -ForegroundColor Red
    Write-Host "Status: $($authResponse.StatusCode)" -ForegroundColor Red
}

Write-Host "Test complete!" -ForegroundColor Cyan