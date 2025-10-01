# Get Service Ticket and Test Authentication
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "GET SERVICE TICKET AND TEST" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Issue: No Kerberos tickets cached" -ForegroundColor Yellow
Write-Host "This means Windows can't get tickets for HTTP/vault.local.lab" -ForegroundColor Yellow
Write-Host ""

# Step 1: Try to get a service ticket
Write-Host "Step 1: Attempting to get service ticket..." -ForegroundColor Cyan

$spn = "HTTP/vault.local.lab@LOCAL.LAB"
Write-Host "Requesting ticket for: $spn" -ForegroundColor White

# Use klist get command (correct syntax)
$ticketResult = klist get $spn 2>&1 | Out-String
Write-Host "Ticket request result:" -ForegroundColor White
Write-Host $ticketResult -ForegroundColor Gray

Write-Host ""

# Step 2: Check if we now have tickets
Write-Host "Step 2: Checking for tickets after request..." -ForegroundColor Cyan
$tickets = klist 2>&1 | Out-String
Write-Host "Current tickets:" -ForegroundColor White
Write-Host $tickets -ForegroundColor Gray

Write-Host ""

# Step 3: Test authentication if we got tickets
if ($tickets -match "HTTP/vault.local.lab") {
    Write-Host "Step 3: Testing authentication with new ticket..." -ForegroundColor Cyan
    
    $curlPath = "C:\Windows\System32\curl.exe"
    if (Test-Path $curlPath) {
        $tempJsonFile = "test.json"
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
        
        Write-Host "Testing with curl..." -ForegroundColor White
        $result = & $curlPath $curlArgs 2>&1 | Out-String
        Write-Host "Result: $result" -ForegroundColor Gray
        
        Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "Step 3: No service ticket obtained - skipping authentication test" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "SERVICE TICKET TEST COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "If no ticket was obtained, the issue is SPN registration" -ForegroundColor White
Write-Host "If ticket was obtained but auth still fails, it's encryption mismatch" -ForegroundColor White


