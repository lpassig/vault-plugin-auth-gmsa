Write-Host "Testing HTTP vs HTTPS connectivity..." -ForegroundColor Yellow

# Disable SSL certificate validation for testing
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

Write-Host ""
Write-Host "Test 1: HTTP connectivity..." -ForegroundColor Cyan
$httpResponse = Invoke-WebRequest -Uri "http://vault.local.lab:8200/v1/sys/health" -Method GET -UseBasicParsing -ErrorAction SilentlyContinue

if ($httpResponse) {
    Write-Host "HTTP connectivity successful" -ForegroundColor Green
} else {
    Write-Host "HTTP connectivity failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "Test 2: HTTPS connectivity..." -ForegroundColor Cyan
$httpsResponse = Invoke-WebRequest -Uri "https://vault.local.lab:8200/v1/sys/health" -Method GET -UseBasicParsing -ErrorAction SilentlyContinue

if ($httpsResponse) {
    Write-Host "HTTPS connectivity successful" -ForegroundColor Green
} else {
    Write-Host "HTTPS connectivity failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "Test 3: HTTP Kerberos authentication..." -ForegroundColor Cyan
$body = '{"role":"computer-accounts"}'
$headers = @{"Content-Type" = "application/json"}

$httpAuth = Invoke-WebRequest -Uri "http://vault.local.lab:8200/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -UseBasicParsing -ErrorAction SilentlyContinue

if ($httpAuth -and $httpAuth.StatusCode -eq 200) {
    Write-Host "HTTP Kerberos authentication successful!" -ForegroundColor Green
} else {
    Write-Host "HTTP Kerberos authentication failed" -ForegroundColor Red
    Write-Host "Status: $($httpAuth.StatusCode)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Test 4: HTTPS Kerberos authentication..." -ForegroundColor Cyan
$httpsAuth = Invoke-WebRequest -Uri "https://vault.local.lab:8200/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -UseBasicParsing -ErrorAction SilentlyContinue

if ($httpsAuth -and $httpsAuth.StatusCode -eq 200) {
    Write-Host "HTTPS Kerberos authentication successful!" -ForegroundColor Green
} else {
    Write-Host "HTTPS Kerberos authentication failed" -ForegroundColor Red
    Write-Host "Status: $($httpsAuth.StatusCode)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Protocol test complete!" -ForegroundColor Cyan
