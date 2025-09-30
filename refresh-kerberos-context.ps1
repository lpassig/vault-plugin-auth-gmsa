# Refresh Kerberos Context and Test
Write-Host "Refreshing Kerberos context and testing..." -ForegroundColor Yellow

Write-Host ""
Write-Host "Step 1: Purge existing tickets..." -ForegroundColor Cyan
klist purge -li 0x62da7

Write-Host ""
Write-Host "Step 2: Wait a moment..." -ForegroundColor Cyan
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "Step 3: Try to get service ticket..." -ForegroundColor Cyan
$ticketResult = klist get HTTP/vault.local.lab@LOCAL.LAB 2>&1 | Out-String
Write-Host "Ticket result:" -ForegroundColor White
Write-Host $ticketResult -ForegroundColor Gray

Write-Host ""
Write-Host "Step 4: Check tickets..." -ForegroundColor Cyan
$tickets = klist 2>&1 | Out-String
Write-Host "Current tickets:" -ForegroundColor White
Write-Host $tickets -ForegroundColor Gray

Write-Host ""
Write-Host "Step 5: Test authentication if we have tickets..." -ForegroundColor Cyan
if ($tickets -match "HTTP/vault.local.lab") {
    Write-Host "Service ticket found, testing authentication..." -ForegroundColor Green
    
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
        
        $result = & $curlPath $curlArgs 2>&1 | Out-String
        Write-Host "Authentication result:" -ForegroundColor White
        Write-Host $result -ForegroundColor Gray
        
        Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "No service ticket found - still have credential issues" -ForegroundColor Red
}

Write-Host ""
Write-Host "Test complete!" -ForegroundColor Cyan
