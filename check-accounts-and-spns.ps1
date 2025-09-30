# Check What Accounts and SPNs Actually Exist
Write-Host "Checking what accounts and SPNs actually exist..." -ForegroundColor Yellow

Write-Host ""
Write-Host "Step 1: Check if vault-keytab-svc account exists..." -ForegroundColor Cyan
try {
    $account = Get-ADUser -Identity "vault-keytab-svc" -ErrorAction Stop
    Write-Host "vault-keytab-svc account found" -ForegroundColor Green
} catch {
    Write-Host "vault-keytab-svc account not found or no permission to query" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Step 2: Check what SPNs exist for HTTP/vault.local.lab..." -ForegroundColor Cyan
try {
    $spnQuery = setspn -Q HTTP/vault.local.lab 2>&1 | Out-String
    Write-Host "SPN query result:" -ForegroundColor White
    Write-Host $spnQuery -ForegroundColor Gray
} catch {
    Write-Host "Could not query SPN: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Step 3: Check if EC2AMAZ-UB1QVDL$ account exists..." -ForegroundColor Cyan
try {
    $computerAccount = Get-ADComputer -Identity "EC2AMAZ-UB1QVDL" -ErrorAction Stop
    Write-Host "EC2AMAZ-UB1QVDL computer account found" -ForegroundColor Green
    Write-Host "DN: $($computerAccount.DistinguishedName)" -ForegroundColor Gray
} catch {
    Write-Host "EC2AMAZ-UB1QVDL computer account not found or no permission to query" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Step 4: Check what SPNs are registered to EC2AMAZ-UB1QVDL$..." -ForegroundColor Cyan
try {
    $computerSpnQuery = setspn -L EC2AMAZ-UB1QVDL$ 2>&1 | Out-String
    Write-Host "SPNs for EC2AMAZ-UB1QVDL$:" -ForegroundColor White
    Write-Host $computerSpnQuery -ForegroundColor Gray
} catch {
    Write-Host "Could not query SPNs for EC2AMAZ-UB1QVDL$: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Step 5: Try to get service ticket for HTTP/vault.local.lab..." -ForegroundColor Cyan
$ticketResult = klist get HTTP/vault.local.lab@LOCAL.LAB 2>&1 | Out-String
Write-Host "Ticket request result:" -ForegroundColor White
Write-Host $ticketResult -ForegroundColor Gray

Write-Host ""
Write-Host "Analysis complete!" -ForegroundColor Green
Write-Host "This will help us understand what accounts exist and what SPNs are registered" -ForegroundColor White
