# Debug gMSA Authentication Issues
# This script runs detailed diagnostics under gMSA identity

param(
    [string]$VaultUrl = "http://10.0.101.8:8200"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Debug gMSA Authentication Issues" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# SSL Certificate bypass
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

Write-Host "Vault Server: $VaultUrl" -ForegroundColor Yellow
Write-Host ""

# Test 1: Current identity
Write-Host "1. Current Identity:" -ForegroundColor Yellow
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Current user: $currentIdentity" -ForegroundColor White

if ($currentIdentity.EndsWith("$")) {
    Write-Host "SUCCESS: Running under gMSA identity!" -ForegroundColor Green
} else {
    Write-Host "ERROR: Not running under gMSA identity" -ForegroundColor Red
    Write-Host "This script should be run as a scheduled task under gMSA" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 2: Kerberos tickets
Write-Host "2. Kerberos Tickets:" -ForegroundColor Yellow
try {
    $klistOutput = klist 2>&1
    Write-Host "Kerberos tickets:" -ForegroundColor White
    Write-Host $klistOutput -ForegroundColor Gray
    
    if ($klistOutput -match "HTTP/vault.local.lab") {
        Write-Host "SUCCESS: Kerberos ticket found for HTTP/vault.local.lab" -ForegroundColor Green
    } else {
        Write-Host "WARNING: No Kerberos ticket found for HTTP/vault.local.lab" -ForegroundColor Yellow
        Write-Host "This might be the issue - gMSA needs to request a ticket" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Cannot check Kerberos tickets" -ForegroundColor Red
}
Write-Host ""

# Test 3: Vault connectivity
Write-Host "3. Vault Server Connectivity:" -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/health" -Method Get
    Write-Host "SUCCESS: Vault server is reachable" -ForegroundColor Green
    Write-Host "  Initialized: $($health.initialized)" -ForegroundColor Gray
    Write-Host "  Sealed: $($health.sealed)" -ForegroundColor Gray
    Write-Host "  Version: $($health.version)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Cannot reach Vault server" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 4: Try to request Kerberos ticket
Write-Host "4. Attempting to Request Kerberos Ticket:" -ForegroundColor Yellow
try {
    Write-Host "Trying to request Kerberos ticket for HTTP/vault.local.lab..." -ForegroundColor Cyan
    
    # Method 1: Try HTTP request to trigger ticket request
    try {
        $response = Invoke-WebRequest -Uri "http://vault.local.lab:8200/v1/sys/health" -UseDefaultCredentials -TimeoutSec 10
        Write-Host "SUCCESS: HTTP request completed, ticket may have been requested" -ForegroundColor Green
        Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "HTTP request failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Check tickets again
    $klistOutput2 = klist 2>&1
    if ($klistOutput2 -match "HTTP/vault.local.lab") {
        Write-Host "SUCCESS: Kerberos ticket now available!" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Still no Kerberos ticket after request attempt" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Failed to request Kerberos ticket" -ForegroundColor Red
}
Write-Host ""

# Test 5: Test Kerberos authentication
Write-Host "5. Kerberos Authentication Test:" -ForegroundColor Yellow
try {
    Write-Host "Attempting Kerberos authentication..." -ForegroundColor Cyan
    
    $response = Invoke-RestMethod `
        -Uri "$VaultUrl/v1/auth/kerberos/login" `
        -Method Post `
        -UseDefaultCredentials `
        -UseBasicParsing
    
    if ($response.auth -and $response.auth.client_token) {
        Write-Host "SUCCESS: Kerberos authentication successful!" -ForegroundColor Green
        Write-Host "Client token: $($response.auth.client_token)" -ForegroundColor Green
        Write-Host "Token TTL: $($response.auth.lease_duration) seconds" -ForegroundColor Green
        Write-Host "Policies: $($response.auth.policies -join ', ')" -ForegroundColor Green
        
        # Test secret retrieval
        Write-Host ""
        Write-Host "6. Secret Retrieval Test:" -ForegroundColor Yellow
        try {
            $headers = @{
                "X-Vault-Token" = $response.auth.client_token
            }
            
            $secrets = Invoke-RestMethod `
                -Uri "$VaultUrl/v1/secret/my-app/database" `
                -Method Get `
                -Headers $headers
            
            Write-Host "SUCCESS: Secrets retrieved!" -ForegroundColor Green
            Write-Host "Database secrets:" -ForegroundColor White
            Write-Host "  Username: $($secrets.data.data.username)" -ForegroundColor Gray
            Write-Host "  Password: $($secrets.data.data.password)" -ForegroundColor Gray
            Write-Host "  Host: $($secrets.data.data.host)" -ForegroundColor Gray
            Write-Host "  Port: $($secrets.data.data.port)" -ForegroundColor Gray
            
            Write-Host ""
            Write-Host "🎉 COMPLETE SUCCESS: gMSA authentication is working!" -ForegroundColor Green
            Write-Host "The SPN fix resolved the authentication issue!" -ForegroundColor Green
            
        } catch {
            Write-Host "ERROR: Failed to retrieve secrets" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        
    } else {
        Write-Host "ERROR: Authentication failed - no token received" -ForegroundColor Red
    }
    
} catch {
    $statusCode = $_.Exception.Response.StatusCode
    Write-Host "Authentication failed with status: $statusCode" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errorBody = $reader.ReadToEnd()
        Write-Host "Error details: $errorBody" -ForegroundColor Red
    }
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Debug Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
if ($currentIdentity.EndsWith("$")) {
    Write-Host "1. If authentication succeeded: Update the main script" -ForegroundColor White
    Write-Host "2. If authentication failed: Check Vault server logs" -ForegroundColor White
    Write-Host "3. Verify keytab configuration on Vault server" -ForegroundColor White
} else {
    Write-Host "1. Run this script as a scheduled task under gMSA identity" -ForegroundColor White
    Write-Host "2. Use: Start-ScheduledTask -TaskName 'Vault-gMSA-Authentication'" -ForegroundColor White
}
Write-Host ""
