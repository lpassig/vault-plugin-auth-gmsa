# Test Invoke-RestMethod with -UseDefaultCredentials for Kerberos Auth
# This tests the approach mentioned in the article

param(
    [string]$VaultAddr = "https://vault.local.lab:8200",
    [string]$Role = "computer-accounts"
)

$LogFile = "C:\vault-client\logs\test-invoke-restmethod.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    
    # Ensure log directory exists
    $logDir = Split-Path -Parent $LogFile
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logMessage
}

Write-Log "========================================" "INFO"
Write-Log "TEST: Invoke-RestMethod with -UseDefaultCredentials" "INFO"
Write-Log "========================================" "INFO"
Write-Log "" "INFO"

Write-Log "Environment Information:" "INFO"
Write-Log "  Current User: $env:USERNAME" "INFO"
Write-Log "  Computer: $env:COMPUTERNAME" "INFO"
Write-Log "  Domain: $env:USERDNSDOMAIN" "INFO"
Write-Log "  Vault URL: $VaultAddr" "INFO"
Write-Log "  Role: $Role" "INFO"
Write-Log "" "INFO"

# Check Kerberos tickets
Write-Log "Checking Kerberos tickets..." "INFO"
try {
    $tickets = klist 2>&1 | Out-String
    Write-Log $tickets "INFO"
} catch {
    Write-Log "Warning: Could not run klist: $($_.Exception.Message)" "WARNING"
}
Write-Log "" "INFO"

# Bypass SSL certificate validation for testing
Write-Log "Configuring SSL bypass for testing..." "INFO"
Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
Write-Log "✓ SSL validation bypassed" "INFO"
Write-Log "" "INFO"

# Test authentication using Invoke-RestMethod with -UseDefaultCredentials
Write-Log "Attempting authentication with Invoke-RestMethod..." "INFO"
Write-Log "Method: -UseDefaultCredentials + Authorization: Negotiate" "INFO"
Write-Log "" "INFO"

try {
    $requestBody = @{
        role = $Role
    } | ConvertTo-Json
    
    Write-Log "Request body: $requestBody" "INFO"
    Write-Log "Endpoint: $VaultAddr/v1/auth/kerberos/login" "INFO"
    Write-Log "" "INFO"
    
    Write-Log "Executing Invoke-RestMethod..." "INFO"
    
    $response = Invoke-RestMethod -Uri "$VaultAddr/v1/auth/kerberos/login" `
        -Method POST `
        -UseDefaultCredentials `
        -Headers @{
            "Authorization" = "Negotiate"
        } `
        -Body $requestBody `
        -ContentType "application/json" `
        -TimeoutSec 30 `
        -ErrorAction Stop
    
    Write-Log "" "SUCCESS"
    Write-Log "========================================" "SUCCESS"
    Write-Log "SUCCESS! Authentication succeeded!" "SUCCESS"
    Write-Log "========================================" "SUCCESS"
    Write-Log "" "SUCCESS"
    
    if ($response.auth -and $response.auth.client_token) {
        Write-Log "Token obtained: $($response.auth.client_token)" "INFO"
        Write-Log "Token TTL: $($response.auth.lease_duration) seconds" "INFO"
        Write-Log "Token policies: $($response.auth.policies -join ', ')" "INFO"
        Write-Log "" "INFO"
        
        # Test using the token to get a secret
        Write-Log "Testing token by retrieving a secret..." "INFO"
        $secretResponse = $null
        try {
            $secretResponse = Invoke-RestMethod -Uri "$VaultAddr/v1/secret/data/app/config" -Method GET -Headers @{"X-Vault-Token" = $response.auth.client_token} -TimeoutSec 10 -ErrorAction Stop
            Write-Log "✓ Token is valid - successfully retrieved secret" "SUCCESS"
            Write-Log "Secret keys: $($secretResponse.data.data.Keys -join ', ')" "INFO"
        } catch {
            if ($_.Exception.Message -match "404") {
                Write-Log "Note: Secret path doesn't exist (this is OK for testing)" "INFO"
            } else {
                Write-Log "Warning: Could not retrieve secret: $($_.Exception.Message)" "WARNING"
            }
        }
        
        Write-Log "" "SUCCESS"
        Write-Log "========================================" "SUCCESS"
        Write-Log "TEST COMPLETED SUCCESSFULLY!" "SUCCESS"
        Write-Log "========================================" "SUCCESS"
        Write-Log "" "SUCCESS"
        Write-Log "Conclusion: Invoke-RestMethod with -UseDefaultCredentials WORKS!" "SUCCESS"
        Write-Log "This approach automatically generates SPNEGO tokens via Windows SSPI" "SUCCESS"
        Write-Log "" "SUCCESS"
        
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        exit 0
        
    } else {
        Write-Log "Unexpected response format - no auth.client_token" "ERROR"
        Write-Log "Response: $($response | ConvertTo-Json -Depth 10)" "ERROR"
        
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        exit 1
    }
}
catch {
    Write-Log "" "ERROR"
    Write-Log "========================================" "ERROR"
    Write-Log "AUTHENTICATION FAILED!" "ERROR"
    Write-Log "========================================" "ERROR"
    Write-Log "" "ERROR"
    Write-Log "Error message: $($_.Exception.Message)" "ERROR"
    Write-Log "Error type: $($_.Exception.GetType().FullName)" "ERROR"
    
    if ($_.Exception.Response) {
        Write-Log "HTTP Status: $($_.Exception.Response.StatusCode)" "ERROR"
        Write-Log "Status description: $($_.Exception.Response.StatusDescription)" "ERROR"
        
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            $reader.Close()
            Write-Log "Response body: $responseBody" "ERROR"
        } catch {
            Write-Log "Could not read response body" "ERROR"
        }
    }
    
    Write-Log "" "ERROR"
    Write-Log "Troubleshooting:" "INFO"
    Write-Log "----------------" "INFO"
    Write-Log "1. Verify Vault Kerberos auth is enabled:" "INFO"
    Write-Log "   vault auth list | grep kerberos" "INFO"
    Write-Log "" "INFO"
    Write-Log "2. Verify SPN is registered to computer account (on ADDC):" "INFO"
    Write-Log "   setspn -L $env:COMPUTERNAME`$" "INFO"
    Write-Log "" "INFO"
    Write-Log "3. Verify Kerberos configuration on Vault:" "INFO"
    Write-Log "   vault read auth/kerberos/config" "INFO"
    Write-Log "" "INFO"
    Write-Log "4. Check if role exists:" "INFO"
    Write-Log "   vault read auth/kerberos/role/$Role" "INFO"
    Write-Log "" "INFO"
    
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
    exit 1
}

# This should not be reached
Write-Log "Unexpected script flow" "ERROR"

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

exit 1
