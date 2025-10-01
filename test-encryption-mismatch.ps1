# Test Different Kerberos Approaches
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "TESTING DIFFERENT KERBEROS APPROACHES" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Issue: Vault keytab uses arcfour-hmac encryption" -ForegroundColor Yellow
Write-Host "Windows client might be using AES encryption" -ForegroundColor Yellow
Write-Host "This mismatch causes ASN.1 parsing errors" -ForegroundColor Yellow
Write-Host ""

# Test 1: Try with different curl options
Write-Host "Test 1: curl with different encryption options..." -ForegroundColor Cyan

$curlPath = "C:\Windows\System32\curl.exe"
if (Test-Path $curlPath) {
    $tempJsonFile = "test.json"
    '{"role":"computer-accounts"}' | Out-File -FilePath $tempJsonFile -Encoding ASCII -NoNewline
    
    # Try with --negotiate and --delegation
    $curlArgs1 = @(
        "--negotiate",
        "--delegation", "always",
        "--user", ":",
        "-X", "POST",
        "-H", "Content-Type: application/json",
        "--data-binary", "@$tempJsonFile",
        "-k",
        "-s",
        "http://vault.local.lab:8200/v1/auth/kerberos/login"
    )
    
    Write-Host "Trying curl with delegation..." -ForegroundColor White
    $result1 = & $curlPath $curlArgs1 2>&1 | Out-String
    Write-Host "Result: $result1" -ForegroundColor Gray
    
    # Try with different user agent
    $curlArgs2 = @(
        "--negotiate",
        "--user", ":",
        "-X", "POST",
        "-H", "Content-Type: application/json",
        "-H", "User-Agent: curl/7.68.0",
        "--data-binary", "@$tempJsonFile",
        "-k",
        "-s",
        "http://vault.local.lab:8200/v1/auth/kerberos/login"
    )
    
    Write-Host "Trying curl with different user agent..." -ForegroundColor White
    $result2 = & $curlPath $curlArgs2 2>&1 | Out-String
    Write-Host "Result: $result2" -ForegroundColor Gray
    
    Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Test 2: Check what encryption types Windows is using..." -ForegroundColor Cyan

# Check Kerberos tickets
$tickets = klist 2>&1 | Out-String
Write-Host "Current Kerberos tickets:" -ForegroundColor White
Write-Host $tickets -ForegroundColor Gray

Write-Host ""
Write-Host "Test 3: Try to force AES encryption..." -ForegroundColor Cyan

# Try to get a new ticket with specific encryption
try {
    $spn = "HTTP/vault.local.lab@LOCAL.LAB"
    Write-Host "Attempting to get service ticket for: $spn" -ForegroundColor White
    
    # This might work if we can specify encryption type
    $ticketResult = klist -s $spn 2>&1 | Out-String
    Write-Host "Ticket result: $ticketResult" -ForegroundColor Gray
} catch {
    Write-Host "Could not get service ticket: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "TESTING COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "1. If encryption mismatch is the issue, we need to regenerate the keytab" -ForegroundColor Gray
Write-Host "2. Or configure Windows to use arcfour-hmac encryption" -ForegroundColor Gray
Write-Host "3. Or configure Vault to accept AES encryption" -ForegroundColor Gray


