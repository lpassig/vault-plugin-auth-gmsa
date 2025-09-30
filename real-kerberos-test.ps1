Write-Host "Testing REAL Kerberos authentication..." -ForegroundColor Yellow

# Method 1: Use curl with --negotiate (most reliable)
Write-Host ""
Write-Host "Method 1: Using curl with --negotiate..." -ForegroundColor Cyan

$curlPath = "C:\Windows\System32\curl.exe"
if (Test-Path $curlPath) {
    $tempJsonFile = "$env:TEMP\kerberos-test.json"
    '{"role":"computer-accounts"}' | Out-File -FilePath $tempJsonFile -Encoding ASCII -NoNewline
    
    $curlArgs = @(
        "--negotiate",
        "--user", ":",
        "-X", "POST",
        "-H", "Content-Type: application/json",
        "--data-binary", "@$tempJsonFile",
        "-k",
        "-s",
        "http://vault.local.lab:8200/v1/auth/kerberos/login"
    )
    
    Write-Host "Running: curl.exe $($curlArgs -join ' ')" -ForegroundColor Gray
    $curlResult = & $curlPath $curlArgs 2>&1 | Out-String
    
    Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
    
    if ($curlResult -match '"client_token"') {
        Write-Host "✓ curl Kerberos authentication successful!" -ForegroundColor Green
        Write-Host "Response contains client_token" -ForegroundColor Green
    } else {
        Write-Host "❌ curl Kerberos authentication failed" -ForegroundColor Red
        Write-Host "Response: $curlResult" -ForegroundColor Red
    }
} else {
    Write-Host "❌ curl.exe not found" -ForegroundColor Red
}

# Method 2: Use WebRequest with UseDefaultCredentials
Write-Host ""
Write-Host "Method 2: Using WebRequest with UseDefaultCredentials..." -ForegroundColor Cyan

try {
    $request = [System.Net.WebRequest]::Create("http://vault.local.lab:8200/v1/auth/kerberos/login")
    $request.Method = "POST"
    $request.UseDefaultCredentials = $true
    $request.ContentType = "application/json"
    
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes('{"role":"computer-accounts"}')
    $request.ContentLength = $bodyBytes.Length
    
    $requestStream = $request.GetRequestStream()
    $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
    $requestStream.Close()
    
    $response = $request.GetResponse()
    $responseStream = $response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($responseStream)
    $responseContent = $reader.ReadToEnd()
    
    if ($responseContent -match '"client_token"') {
        Write-Host "✓ WebRequest Kerberos authentication successful!" -ForegroundColor Green
        Write-Host "Response contains client_token" -ForegroundColor Green
    } else {
        Write-Host "❌ WebRequest Kerberos authentication failed" -ForegroundColor Red
        Write-Host "Response: $responseContent" -ForegroundColor Red
    }
    
    $response.Close()
} catch {
    Write-Host "❌ WebRequest error: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Kerberos authentication test complete!" -ForegroundColor Cyan
