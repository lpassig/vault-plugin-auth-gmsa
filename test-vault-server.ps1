# Quick Vault Server Test
# Simple script to test basic Vault server connectivity and configuration

param(
    [string]$VaultUrl = "https://vault.local.lab:8200"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Quick Vault Server Test" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# SSL Certificate bypass
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

Write-Host "Testing Vault Server: $VaultUrl" -ForegroundColor Yellow
Write-Host ""

# Test 1: Basic Health Check
Write-Host "1. Health Check:" -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/health" -Method Get
    Write-Host "SUCCESS: Vault is reachable" -ForegroundColor Green
    Write-Host "  Initialized: $($health.initialized)" -ForegroundColor Gray
    Write-Host "  Sealed: $($health.sealed)" -ForegroundColor Gray
    Write-Host "  Version: $($health.version)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Cannot reach Vault server" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 2: Check Auth Methods
Write-Host "2. Authentication Methods:" -ForegroundColor Yellow
try {
    $auth = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/auth" -Method Get
    Write-Host "Available auth methods:" -ForegroundColor White
    foreach ($method in $auth.data.Keys) {
        Write-Host "  - $method" -ForegroundColor Gray
        if ($method -eq "kerberos/") {
            Write-Host "    ✓ Kerberos auth method is enabled!" -ForegroundColor Green
        }
    }
} catch {
    Write-Host "ERROR: Cannot check auth methods" -ForegroundColor Red
}
Write-Host ""

# Test 3: Check Kerberos Login Endpoint
Write-Host "3. Kerberos Login Endpoint:" -ForegroundColor Yellow
try {
    $loginResponse = Invoke-WebRequest -Uri "$VaultUrl/v1/auth/kerberos/login" -Method Post -TimeoutSec 5
    Write-Host "SUCCESS: Kerberos login endpoint accessible" -ForegroundColor Green
    Write-Host "Status: $($loginResponse.StatusCode)" -ForegroundColor Green
} catch {
    $statusCode = $_.Exception.Response.StatusCode
    if ($statusCode -eq 400 -or $statusCode -eq 401) {
        Write-Host "SUCCESS: Kerberos login endpoint accessible (returns $statusCode without credentials)" -ForegroundColor Green
    } elseif ($statusCode -eq 404) {
        Write-Host "ERROR: Kerberos auth method not found (404)" -ForegroundColor Red
    } else {
        Write-Host "Response: $statusCode" -ForegroundColor Yellow
    }
}
Write-Host ""

# Test 4: Check Secrets Engines
Write-Host "4. Secrets Engines:" -ForegroundColor Yellow
try {
    $mounts = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/mounts" -Method Get
    Write-Host "Available secrets engines:" -ForegroundColor White
    foreach ($mount in $mounts.data.Keys) {
        Write-Host "  - $mount ($($mounts.data[$mount].type))" -ForegroundColor Gray
    }
} catch {
    Write-Host "ERROR: Cannot check secrets engines" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Test Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "If gMSA auth method is not enabled, run:" -ForegroundColor Yellow
Write-Host "  .\configure-vault-server.ps1 -VaultToken <root-token>" -ForegroundColor White
Write-Host ""

Write-Host "For detailed validation, run:" -ForegroundColor Yellow
Write-Host "  .\validate-vault-server-config.ps1" -ForegroundColor White
Write-Host ""
