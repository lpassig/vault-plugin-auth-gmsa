# Direct gMSA Authentication Test
# This script tests gMSA authentication without scheduled tasks

param(
    [string]$VaultUrl = "http://10.0.101.8:8200",
    [string]$Role = "vault-gmsa-role"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Direct gMSA Authentication Test" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Vault URL: $VaultUrl" -ForegroundColor White
Write-Host "  Role: $Role" -ForegroundColor White
Write-Host ""

# Step 1: Check current identity
Write-Host "Step 1: Current Identity Check..." -ForegroundColor Yellow
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Current identity: $currentIdentity" -ForegroundColor White

if ($currentIdentity.EndsWith("$")) {
    Write-Host "SUCCESS: Running under service account identity" -ForegroundColor Green
} else {
    Write-Host "WARNING: Not running under service account identity" -ForegroundColor Yellow
    Write-Host "This test will show what happens under regular user context" -ForegroundColor Yellow
}
Write-Host ""

# Step 2: Check Kerberos tickets
Write-Host "Step 2: Kerberos Tickets Check..." -ForegroundColor Yellow
try {
    $klistOutput = klist 2>&1
    Write-Host "Kerberos tickets:" -ForegroundColor White
    Write-Host $klistOutput -ForegroundColor Gray
    
    if ($klistOutput -match "HTTP/vault.local.lab") {
        Write-Host "SUCCESS: Found ticket for HTTP/vault.local.lab" -ForegroundColor Green
    } else {
        Write-Host "WARNING: No ticket found for HTTP/vault.local.lab" -ForegroundColor Yellow
        Write-Host "This is expected if not running under gMSA identity" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Could not check Kerberos tickets" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 3: Test Vault connectivity
Write-Host "Step 3: Vault Server Connectivity..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$VaultUrl/v1/sys/health" -Method Get -UseBasicParsing -TimeoutSec 10
    Write-Host "SUCCESS: Vault server is reachable" -ForegroundColor Green
    Write-Host "  Status Code: $($response.StatusCode)" -ForegroundColor Gray
    Write-Host "  Response: $($response.Content)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Cannot reach Vault server" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check network connectivity and Vault server status" -ForegroundColor Yellow
}
Write-Host ""

# Step 4: Test Kerberos authentication
Write-Host "Step 4: Kerberos Authentication Test..." -ForegroundColor Yellow
try {
    Write-Host "Attempting Kerberos authentication..." -ForegroundColor Cyan
    
    # Method 1: Invoke-RestMethod with UseDefaultCredentials
    try {
        Write-Host "Method 1: Invoke-RestMethod with UseDefaultCredentials..." -ForegroundColor White
        $authResponse = Invoke-RestMethod `
            -Uri "$VaultUrl/v1/auth/kerberos/login" `
            -Method Post `
            -UseDefaultCredentials `
            -UseBasicParsing `
            -ErrorAction Stop
        
        if ($authResponse.auth -and $authResponse.auth.client_token) {
            Write-Host "SUCCESS: Kerberos authentication successful!" -ForegroundColor Green
            Write-Host "  Client Token: $($authResponse.auth.client_token)" -ForegroundColor Gray
            Write-Host "  Token TTL: $($authResponse.auth.lease_duration) seconds" -ForegroundColor Gray
            
            # Test secret retrieval
            Write-Host "Testing secret retrieval..." -ForegroundColor Cyan
            try {
                $secretResponse = Invoke-RestMethod `
                    -Uri "$VaultUrl/v1/secret/data/gmsa-test" `
                    -Method Get `
                    -Headers @{ "X-Vault-Token" = $authResponse.auth.client_token } `
                    -UseBasicParsing
                
                Write-Host "SUCCESS: Secret retrieved successfully!" -ForegroundColor Green
                Write-Host "  Secret Data: $($secretResponse.data.data | ConvertTo-Json)" -ForegroundColor Gray
            } catch {
                Write-Host "WARNING: Secret retrieval failed" -ForegroundColor Yellow
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
            }
            
        } else {
            Write-Host "WARNING: Authentication response missing auth data" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "Method 1 failed: $($_.Exception.Message)" -ForegroundColor Red
        
        # Method 2: WebRequest with UseDefaultCredentials
        try {
            Write-Host "Method 2: WebRequest with UseDefaultCredentials..." -ForegroundColor White
            $request = [System.Net.WebRequest]::Create("$VaultUrl/v1/auth/kerberos/login")
            $request.Method = "POST"
            $request.UseDefaultCredentials = $true
            $request.PreAuthenticate = $true
            
            $response = $request.GetResponse()
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            $response.Close()
            
            $authResponse = $responseBody | ConvertFrom-Json
            if ($authResponse.auth -and $authResponse.auth.client_token) {
                Write-Host "SUCCESS: WebRequest authentication successful!" -ForegroundColor Green
                Write-Host "  Client Token: $($authResponse.auth.client_token)" -ForegroundColor Gray
            } else {
                Write-Host "WARNING: WebRequest response missing auth data" -ForegroundColor Yellow
            }
            
        } catch {
            Write-Host "Method 2 failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
} catch {
    Write-Host "ERROR: Kerberos authentication test failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 5: Test with explicit role
Write-Host "Step 5: Testing with explicit role..." -ForegroundColor Yellow
try {
    $body = @{
        role = $Role
    } | ConvertTo-Json
    
    $authResponse = Invoke-RestMethod `
        -Uri "$VaultUrl/v1/auth/kerberos/login" `
        -Method Post `
        -Body $body `
        -ContentType "application/json" `
        -UseDefaultCredentials `
        -UseBasicParsing
    
    if ($authResponse.auth -and $authResponse.auth.client_token) {
        Write-Host "SUCCESS: Authentication with explicit role successful!" -ForegroundColor Green
        Write-Host "  Client Token: $($authResponse.auth.client_token)" -ForegroundColor Gray
    } else {
        Write-Host "WARNING: Authentication with role failed" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "Authentication with role failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Direct Authentication Test Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "ANALYSIS:" -ForegroundColor Yellow
if ($currentIdentity.EndsWith("$")) {
    Write-Host "Running under service account - results show gMSA authentication capability" -ForegroundColor Green
} else {
    Write-Host "Running under regular user - results show what happens without gMSA" -ForegroundColor Yellow
    Write-Host "To test gMSA authentication, run this script under gMSA identity" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. If authentication succeeded: gMSA setup is working!" -ForegroundColor White
Write-Host "2. If authentication failed: check Vault server configuration" -ForegroundColor White
Write-Host "3. To test under gMSA: use manual execution methods from advanced-gmsa-fix.ps1" -ForegroundColor White
Write-Host ""

Write-Host "MANUAL GMSA TEST COMMANDS:" -ForegroundColor Cyan
Write-Host "runas /user:LOCAL\vault-gmsa$ 'PowerShell -ExecutionPolicy Bypass -File .\test-direct-auth.ps1'" -ForegroundColor Gray
Write-Host ""
