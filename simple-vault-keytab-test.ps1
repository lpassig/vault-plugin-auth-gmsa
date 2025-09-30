# Simple Test with vault-keytab-svc Account
Write-Host "Testing authentication with vault-keytab-svc account..." -ForegroundColor Yellow

# Check if vault-keytab-svc account exists
Write-Host "Checking if vault-keytab-svc account exists..." -ForegroundColor Cyan
$account = Get-ADUser -Identity "vault-keytab-svc" -ErrorAction SilentlyContinue

if ($account) {
    Write-Host "vault-keytab-svc account found" -ForegroundColor Green
} else {
    Write-Host "vault-keytab-svc account not found" -ForegroundColor Red
    Write-Host "This means the SPN registration is invalid" -ForegroundColor Red
    exit 1
}

# Check SPN registration
Write-Host "Checking SPN registration..." -ForegroundColor Cyan
$spnQuery = setspn -L vault-keytab-svc 2>&1 | Out-String
Write-Host "SPNs for vault-keytab-svc:" -ForegroundColor White
Write-Host $spnQuery -ForegroundColor Gray

if ($spnQuery -match "HTTP/vault.local.lab") {
    Write-Host "HTTP/vault.local.lab is registered to vault-keytab-svc" -ForegroundColor Green
} else {
    Write-Host "HTTP/vault.local.lab not found in vault-keytab-svc SPNs" -ForegroundColor Red
}

# Test authentication
Write-Host "Testing authentication..." -ForegroundColor Cyan
Write-Host "You will be prompted for vault-keytab-svc password" -ForegroundColor Yellow

$credential = Get-Credential -UserName "LOCAL.LAB\vault-keytab-svc" -Message "Enter vault-keytab-svc password"

if ($credential) {
    Write-Host "Testing authentication with vault-keytab-svc..." -ForegroundColor White
    
    $body = '{"role":"computer-accounts"}'
    $headers = @{"Content-Type" = "application/json"}
    
    $response = Invoke-WebRequest -Uri "http://vault.local.lab:8200/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -Credential $credential -UseBasicParsing -ErrorAction SilentlyContinue
    
    if ($response -and $response.StatusCode -eq 200) {
        Write-Host "Authentication successful with vault-keytab-svc!" -ForegroundColor Green
        $responseData = $response.Content | ConvertFrom-Json
        if ($responseData.auth.client_token) {
            Write-Host "Token received!" -ForegroundColor Green
        }
    } else {
        Write-Host "Authentication failed with vault-keytab-svc" -ForegroundColor Red
        Write-Host "Status: $($response.StatusCode)" -ForegroundColor Red
    }
} else {
    Write-Host "No credentials provided" -ForegroundColor Red
}

Write-Host "Test complete!" -ForegroundColor Cyan
