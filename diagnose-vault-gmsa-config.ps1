# =============================================================================
# Vault gMSA Configuration Diagnostic Script
# =============================================================================
# This script diagnoses the Vault server configuration for gMSA authentication
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.example.com:8200",
    [string]$VaultRole = "vault-gmsa-role"
)

# Bypass SSL certificate validation for testing
try {
    Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint svcPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    Write-Host "SSL certificate validation bypassed for testing" -ForegroundColor Yellow
} catch {
    Write-Host "Could not bypass SSL certificate validation: $($_.Exception.Message)" -ForegroundColor Yellow
}

function Test-VaultConnectivity {
    param([string]$Url)
    
    try {
        Write-Host "Testing Vault connectivity to: $Url" -ForegroundColor Yellow
        
        # Test basic connectivity
        $response = Invoke-WebRequest -Uri "$Url/v1/sys/health" -UseBasicParsing -TimeoutSec 10
        Write-Host "✅ Vault server is reachable" -ForegroundColor Green
        Write-Host "   Status Code: $($response.StatusCode)" -ForegroundColor Cyan
        Write-Host "   Response: $($response.Content)" -ForegroundColor Cyan
        return $true
    } catch {
        Write-Host "❌ Cannot reach Vault server: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-GMSAAuthMethod {
    param([string]$Url)
    
    try {
        Write-Host "`nTesting gMSA authentication method..." -ForegroundColor Yellow
        
        # Check if gMSA auth method is enabled
        $authMethodsUrl = "$Url/v1/sys/auth"
        $response = Invoke-RestMethod -Uri $authMethodsUrl -Method GET
        
        if ($response.data -and $response.data.gmsa) {
            Write-Host "✅ gMSA authentication method is enabled" -ForegroundColor Green
            Write-Host "   Type: $($response.data.gmsa.type)" -ForegroundColor Cyan
            Write-Host "   Description: $($response.data.gmsa.description)" -ForegroundColor Cyan
        } else {
            Write-Host "❌ gMSA authentication method is NOT enabled" -ForegroundColor Red
            Write-Host "   Available auth methods:" -ForegroundColor Yellow
            if ($response.data) {
                $response.data.PSObject.Properties | ForEach-Object {
                    Write-Host "     - $($_.Name): $($_.Value.type)" -ForegroundColor Gray
                }
            }
            return $false
        }
        
        return $true
    } catch {
        Write-Host "❌ Failed to check auth methods: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-GMSAConfiguration {
    param([string]$Url)
    
    try {
        Write-Host "`nTesting gMSA configuration..." -ForegroundColor Yellow
        
        # Check gMSA configuration
        $configUrl = "$Url/v1/auth/gmsa/config"
        $response = Invoke-RestMethod -Uri $configUrl -Method GET
        
        Write-Host "✅ gMSA configuration found" -ForegroundColor Green
        Write-Host "   SPN: $($response.data.spn)" -ForegroundColor Cyan
        Write-Host "   Realm: $($response.data.realm)" -ForegroundColor Cyan
        Write-Host "   Require Channel Binding: $($response.data.require_cb)" -ForegroundColor Cyan
        
        return $true
    } catch {
        Write-Host "❌ Failed to get gMSA configuration: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Host "   HTTP Status: $statusCode" -ForegroundColor Yellow
        }
        return $false
    }
}

function Test-GMSARole {
    param([string]$Url, [string]$Role)
    
    try {
        Write-Host "`nTesting gMSA role configuration..." -ForegroundColor Yellow
        
        # Check gMSA role
        $roleUrl = "$Url/v1/auth/gmsa/role/$Role"
        $response = Invoke-RestMethod -Uri $roleUrl -Method GET
        
        Write-Host "✅ gMSA role '$Role' found" -ForegroundColor Green
        Write-Host "   Bound Service Account Names: $($response.data.bound_service_account_names -join ', ')" -ForegroundColor Cyan
        Write-Host "   Bound Service Account Namespaces: $($response.data.bound_service_account_namespaces -join ', ')" -ForegroundColor Cyan
        Write-Host "   Token Policies: $($response.data.token_policies -join ', ')" -ForegroundColor Cyan
        Write-Host "   Token TTL: $($response.data.token_ttl)" -ForegroundColor Cyan
        
        return $true
    } catch {
        Write-Host "❌ Failed to get gMSA role '$Role': $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Host "   HTTP Status: $statusCode" -ForegroundColor Yellow
        }
        return $false
    }
}

function Test-SPNEGONegotiation {
    param([string]$Url, [string]$Role)
    
    try {
        Write-Host "`nTesting SPNEGO negotiation..." -ForegroundColor Yellow
        
        # Test SPNEGO negotiation by making a request to the login endpoint
        $loginUrl = "$Url/v1/auth/gmsa/login"
        
        # Create a request without credentials first
        $request = [System.Net.HttpWebRequest]::Create($loginUrl)
        $request.Method = "POST"
        $request.ContentType = "application/json"
        $request.Timeout = 10000
        $request.UserAgent = "Vault-gMSA-Diagnostic/1.0"
        
        # Add request body
        $body = @{
            role = $Role
        } | ConvertTo-Json
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $request.ContentLength = $bodyBytes.Length
        
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $requestStream.Close()
        
        try {
            $response = $request.GetResponse()
            Write-Host "❌ Unexpected: Got response without authentication challenge" -ForegroundColor Red
            Write-Host "   Status Code: $($response.StatusCode)" -ForegroundColor Yellow
            $response.Close()
            return $false
        } catch {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Host "✅ Got expected error response: $statusCode" -ForegroundColor Green
            
            # Check for WWW-Authenticate header
            $response = $_.Exception.Response
            if ($response.Headers["WWW-Authenticate"]) {
                $wwwAuth = $response.Headers["WWW-Authenticate"]
                Write-Host "✅ WWW-Authenticate header found: $wwwAuth" -ForegroundColor Green
                
                if ($wwwAuth -like "*Negotiate*") {
                    Write-Host "✅ SPNEGO negotiation is properly configured!" -ForegroundColor Green
                    return $true
                } else {
                    Write-Host "❌ WWW-Authenticate header does not contain 'Negotiate'" -ForegroundColor Red
                    Write-Host "   Expected: Contains 'Negotiate'" -ForegroundColor Yellow
                    Write-Host "   Actual: $wwwAuth" -ForegroundColor Yellow
                    return $false
                }
            } else {
                Write-Host "❌ No WWW-Authenticate header found" -ForegroundColor Red
                Write-Host "   This indicates the gMSA auth method is not properly configured for SPNEGO" -ForegroundColor Yellow
                return $false
            }
        }
    } catch {
        Write-Host "❌ SPNEGO negotiation test failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Show-VaultConfigurationCommands {
    Write-Host "`n=== Vault Server Configuration Commands ===" -ForegroundColor Green
    Write-Host "If the gMSA authentication is not properly configured, run these commands on your Vault server:" -ForegroundColor Yellow
    
    Write-Host "`n# 1. Enable gMSA authentication method" -ForegroundColor Cyan
    Write-Host "vault auth enable gmsa" -ForegroundColor White
    
    Write-Host "`n# 2. Configure gMSA authentication (replace <KEYTAB_BASE64> with your keytab)" -ForegroundColor Cyan
    Write-Host "vault write auth/gmsa/config \" -ForegroundColor White
    Write-Host "    keytab_b64='<KEYTAB_BASE64>' \" -ForegroundColor White
    Write-Host "    spn='HTTP/vault.local.lab' \" -ForegroundColor White
    Write-Host "    realm='LOCAL.LAB' \" -ForegroundColor White
    Write-Host "    require_cb=false" -ForegroundColor White
    
    Write-Host "`n# 3. Create gMSA role" -ForegroundColor Cyan
    Write-Host "vault write auth/gmsa/role/vault-gmsa-role \" -ForegroundColor White
    Write-Host "    bound_service_account_names='vault-gmsa' \" -ForegroundColor White
    Write-Host "    bound_service_account_namespaces='LOCAL.LAB' \" -ForegroundColor White
    Write-Host "    token_policies='vault-gmsa-policy' \" -ForegroundColor White
    Write-Host "    token_ttl=1h \" -ForegroundColor White
    Write-Host "    token_max_ttl=24h" -ForegroundColor White
    
    Write-Host "`n# 4. Create policy" -ForegroundColor Cyan
    Write-Host "vault policy write vault-gmsa-policy - <<EOF" -ForegroundColor White
    Write-Host "path `"kv/data/my-app/*`" {" -ForegroundColor White
    Write-Host "  capabilities = [`"read`"]" -ForegroundColor White
    Write-Host "}" -ForegroundColor White
    Write-Host "EOF" -ForegroundColor White
    
    Write-Host "`n# 5. Enable KV secrets engine" -ForegroundColor Cyan
    Write-Host "vault secrets enable -path=kv kv-v2" -ForegroundColor White
    
    Write-Host "`n# 6. Create test secrets" -ForegroundColor Cyan
    Write-Host "vault kv put kv/my-app/database username=dbuser password=dbpass123" -ForegroundColor White
    Write-Host "vault kv put kv/my-app/api api_key=abc123 secret=xyz789" -ForegroundColor White
}

# Main diagnostic process
Write-Host "=== Vault gMSA Configuration Diagnostic ===" -ForegroundColor Green
Write-Host "Vault URL: $VaultUrl" -ForegroundColor Cyan
Write-Host "Vault Role: $VaultRole" -ForegroundColor Cyan
Write-Host ""

$allTestsPassed = $true

# Test 1: Basic connectivity
if (-not (Test-VaultConnectivity -Url $VaultUrl)) {
    $allTestsPassed = $false
}

# Test 2: gMSA auth method
if (-not (Test-GMSAAuthMethod -Url $VaultUrl)) {
    $allTestsPassed = $false
}

# Test 3: gMSA configuration
if (-not (Test-GMSAConfiguration -Url $VaultUrl)) {
    $allTestsPassed = $false
}

# Test 4: gMSA role
if (-not (Test-GMSARole -Url $VaultUrl -Role $VaultRole)) {
    $allTestsPassed = $false
}

# Test 5: SPNEGO negotiation
if (-not (Test-SPNEGONegotiation -Url $VaultUrl -Role $VaultRole)) {
    $allTestsPassed = $false
}

# Summary
Write-Host "`n=== Diagnostic Summary ===" -ForegroundColor Green
if ($allTestsPassed) {
    Write-Host "✅ All tests passed! Vault gMSA configuration is correct." -ForegroundColor Green
    Write-Host "The issue may be with the SPNEGO token generation in the client script." -ForegroundColor Yellow
} else {
    Write-Host "❌ Some tests failed. Vault gMSA configuration needs attention." -ForegroundColor Red
    Show-VaultConfigurationCommands
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Yellow
Write-Host "1. If configuration tests failed, run the Vault configuration commands above" -ForegroundColor White
Write-Host "2. If all tests passed, the issue is in the client SPNEGO token generation" -ForegroundColor White
Write-Host "3. Check Vault server logs for authentication errors" -ForegroundColor White
Write-Host "4. Verify the keytab file is correct and contains the right SPN" -ForegroundColor White
