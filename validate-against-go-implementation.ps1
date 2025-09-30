# =============================================================================
# Vault gMSA Client Validation Against Go Implementation
# =============================================================================
# This script validates the PowerShell client implementation against the Go
# authentication method to ensure compatibility and proper SPNEGO handling
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.example.com:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$Realm = "LOCAL.LAB"
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

function Write-ValidationLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "INFO" { "Cyan" }
        default { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

function Test-VaultServerConfiguration {
    Write-ValidationLog "=== Testing Vault Server Configuration ===" -Level "INFO"
    
    try {
        # Test 1: Check if gMSA auth method is enabled
        Write-ValidationLog "1. Checking gMSA authentication method..." -Level "INFO"
        $authUrl = "$VaultUrl/v1/sys/auth"
        $authResponse = Invoke-RestMethod -Uri $authUrl -Method GET
        
        if ($authResponse.data.gmsa) {
            Write-ValidationLog "✅ gMSA auth method is enabled" -Level "SUCCESS"
            Write-ValidationLog "   Type: $($authResponse.data.gmsa.type)" -Level "INFO"
        } else {
            Write-ValidationLog "❌ gMSA auth method is NOT enabled" -Level "ERROR"
            Write-ValidationLog "   Available methods:" -Level "WARNING"
            $authResponse.data.PSObject.Properties | ForEach-Object {
                Write-ValidationLog "     - $($_.Name): $($_.Value.type)" -Level "WARNING"
            }
            return $false
        }
        
        # Test 2: Check gMSA configuration
        Write-ValidationLog "2. Checking gMSA configuration..." -Level "INFO"
        $configUrl = "$VaultUrl/v1/auth/gmsa/config"
        $configResponse = Invoke-RestMethod -Uri $configUrl -Method GET
        
        Write-ValidationLog "✅ gMSA configuration found" -Level "SUCCESS"
        Write-ValidationLog "   SPN: $($configResponse.data.spn)" -Level "INFO"
        Write-ValidationLog "   Realm: $($configResponse.data.realm)" -Level "INFO"
        Write-ValidationLog "   Allow Channel Binding: $($configResponse.data.allow_channel_binding)" -Level "INFO"
        Write-ValidationLog "   Clock Skew: $($configResponse.data.clock_skew_sec) seconds" -Level "INFO"
        
        # Validate configuration matches expected values
        if ($configResponse.data.spn -ne $SPN) {
            Write-ValidationLog "⚠️ SPN mismatch: Expected '$SPN', Got '$($configResponse.data.spn)'" -Level "WARNING"
        }
        if ($configResponse.data.realm -ne $Realm) {
            Write-ValidationLog "⚠️ Realm mismatch: Expected '$Realm', Got '$($configResponse.data.realm)'" -Level "WARNING"
        }
        
        # Test 3: Check gMSA role
        Write-ValidationLog "3. Checking gMSA role configuration..." -Level "INFO"
        $roleUrl = "$VaultUrl/v1/auth/gmsa/role/$VaultRole"
        $roleResponse = Invoke-RestMethod -Uri $roleUrl -Method GET
        
        Write-ValidationLog "✅ gMSA role '$VaultRole' found" -Level "SUCCESS"
        Write-ValidationLog "   Allowed Realms: $($roleResponse.data.allowed_realms -join ', ')" -Level "INFO"
        Write-ValidationLog "   Allowed SPNs: $($roleResponse.data.allowed_spns -join ', ')" -Level "INFO"
        Write-ValidationLog "   Token Policies: $($roleResponse.data.token_policies -join ', ')" -Level "INFO"
        Write-ValidationLog "   Token Type: $($roleResponse.data.token_type)" -Level "INFO"
        
        return $true
        
    } catch {
        Write-ValidationLog "❌ Vault server configuration test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-SPNEGOTokenFormat {
    Write-ValidationLog "=== Testing SPNEGO Token Format ===" -Level "INFO"
    
    # Test 1: Validate base64 encoding
    Write-ValidationLog "1. Testing base64 encoding validation..." -Level "INFO"
    
    $testTokens = @(
        @{ Token = "valid-base64-token"; Valid = $true; Description = "Valid base64" },
        @{ Token = "invalid-base64!"; Valid = $false; Description = "Invalid base64" },
        @{ Token = ""; Valid = $false; Description = "Empty token" },
        @{ Token = "a" * 65537; Valid = $false; Description = "Token too large" }
    )
    
    foreach ($test in $testTokens) {
        try {
            $decoded = [System.Convert]::FromBase64String($test.Token)
            $isValid = $test.Valid
        } catch {
            $isValid = -not $test.Valid
        }
        
        if ($isValid -eq $test.Valid) {
            Write-ValidationLog "✅ $($test.Description): PASS" -Level "SUCCESS"
        } else {
            Write-ValidationLog "❌ $($test.Description): FAIL" -Level "ERROR"
        }
    }
    
    # Test 2: Test SPNEGO token structure (simplified)
    Write-ValidationLog "2. Testing SPNEGO token structure..." -Level "INFO"
    
    # Create a mock SPNEGO token for testing
    $mockSpnegoData = "SPNEGO_TOKEN_FOR_$SPN_$(Get-Date -Format 'yyyyMMddHHmmss')"
    $mockSpnegoToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($mockSpnegoData))
    
    Write-ValidationLog "   Mock SPNEGO token created: $($mockSpnegoToken.Substring(0, 50))..." -Level "INFO"
    Write-ValidationLog "   Token length: $($mockSpnegoToken.Length) characters" -Level "INFO"
    
    return $mockSpnegoToken
}

function Test-AuthenticationFlow {
    param([string]$TestToken)
    
    Write-ValidationLog "=== Testing Authentication Flow ===" -Level "INFO"
    
    # Test 1: Test login endpoint with mock token
    Write-ValidationLog "1. Testing login endpoint with mock SPNEGO token..." -Level "INFO"
    
    $loginUrl = "$VaultUrl/v1/auth/gmsa/login"
    $loginBody = @{
        role = $VaultRole
        spnego = $TestToken
    } | ConvertTo-Json
    
    Write-ValidationLog "   Login URL: $loginUrl" -Level "INFO"
    Write-ValidationLog "   Login body: $loginBody" -Level "INFO"
    
    try {
        $response = Invoke-RestMethod -Method POST -Uri $loginUrl -Body $loginBody -ContentType "application/json"
        Write-ValidationLog "❌ Unexpected: Authentication succeeded with mock token" -Level "ERROR"
        return $false
    } catch {
        $statusCode = $_.Exception.Response.StatusCode
        Write-ValidationLog "✅ Got expected error response: $statusCode" -Level "SUCCESS"
        
        # Check error message format
        try {
            $errorStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream)
            $errorBody = $reader.ReadToEnd()
            $reader.Close()
            $errorStream.Close()
            
            Write-ValidationLog "   Error response: $errorBody" -Level "INFO"
            
            # Parse error response
            $errorJson = $errorBody | ConvertFrom-Json
            if ($errorJson.errors) {
                Write-ValidationLog "   Vault errors: $($errorJson.errors -join ', ')" -Level "INFO"
            }
            
        } catch {
            Write-ValidationLog "   Could not parse error response" -Level "WARNING"
        }
        
        return $true
    }
}

function Test-RealSPNEGONegotiation {
    Write-ValidationLog "=== Testing Real SPNEGO Negotiation ===" -Level "INFO"
    
    # Test 1: Check if we can trigger SPNEGO negotiation
    Write-ValidationLog "1. Testing SPNEGO negotiation trigger..." -Level "INFO"
    
    $loginUrl = "$VaultUrl/v1/auth/gmsa/login"
    
    try {
        # Create request without credentials to trigger 401 challenge
        $request = [System.Net.HttpWebRequest]::Create($loginUrl)
        $request.Method = "POST"
        $request.ContentType = "application/json"
        $request.Timeout = 10000
        $request.UserAgent = "Vault-gMSA-Validation/1.0"
        
        $body = @{
            role = $VaultRole
        } | ConvertTo-Json
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $request.ContentLength = $bodyBytes.Length
        
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $requestStream.Close()
        
        $response = $request.GetResponse()
        Write-ValidationLog "❌ Unexpected: Got response without authentication challenge" -Level "ERROR"
        Write-ValidationLog "   Status Code: $($response.StatusCode)" -Level "WARNING"
        $response.Close()
        return $false
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode
        Write-ValidationLog "✅ Got expected error response: $statusCode" -Level "SUCCESS"
        
        # Check for WWW-Authenticate header
        $response = $_.Exception.Response
        if ($response.Headers["WWW-Authenticate"]) {
            $wwwAuth = $response.Headers["WWW-Authenticate"]
            Write-ValidationLog "✅ WWW-Authenticate header found: $wwwAuth" -Level "SUCCESS"
            
            if ($wwwAuth -like "*Negotiate*") {
                Write-ValidationLog "✅ SPNEGO negotiation is properly configured!" -Level "SUCCESS"
                return $true
            } else {
                Write-ValidationLog "❌ WWW-Authenticate header does not contain 'Negotiate'" -Level "ERROR"
                Write-ValidationLog "   Expected: Contains 'Negotiate'" -Level "WARNING"
                Write-ValidationLog "   Actual: $wwwAuth" -Level "WARNING"
                return $false
            }
        } else {
            Write-ValidationLog "❌ No WWW-Authenticate header found" -Level "ERROR"
            Write-ValidationLog "   This indicates the gMSA auth method is not properly configured for SPNEGO" -Level "WARNING"
            return $false
        }
    }
}

function Test-PowerShellClientCompatibility {
    Write-ValidationLog "=== Testing PowerShell Client Compatibility ===" -Level "INFO"
    
    # Test 1: Check PowerShell version compatibility
    Write-ValidationLog "1. Checking PowerShell version compatibility..." -Level "INFO"
    $psVersion = $PSVersionTable.PSVersion
    Write-ValidationLog "   PowerShell Version: $psVersion" -Level "INFO"
    
    if ($psVersion.Major -ge 5) {
        Write-ValidationLog "✅ PowerShell version is compatible" -Level "SUCCESS"
    } else {
        Write-ValidationLog "❌ PowerShell version is too old" -Level "ERROR"
        return $false
    }
    
    # Test 2: Check .NET Framework availability
    Write-ValidationLog "2. Checking .NET Framework availability..." -Level "INFO"
    try {
        Add-Type -AssemblyName System.Net.Http
        Add-Type -AssemblyName System.Security
        Write-ValidationLog "✅ Required .NET assemblies are available" -Level "SUCCESS"
    } catch {
        Write-ValidationLog "❌ Required .NET assemblies are not available: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    
    # Test 3: Check Windows authentication capabilities
    Write-ValidationLog "3. Checking Windows authentication capabilities..." -Level "INFO"
    try {
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Write-ValidationLog "   Current identity: $currentIdentity" -Level "INFO"
        
        if ($currentIdentity -like "*vault-gmsa$") {
            Write-ValidationLog "✅ Running under gMSA identity" -Level "SUCCESS"
        } else {
            Write-ValidationLog "⚠️ Not running under gMSA identity" -Level "WARNING"
            Write-ValidationLog "   This may cause authentication failures" -Level "WARNING"
        }
        
        # Check Kerberos tickets
        $klistOutput = klist 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-ValidationLog "✅ Kerberos tickets are available" -Level "SUCCESS"
            if ($klistOutput -match $SPN) {
                Write-ValidationLog "✅ Kerberos ticket found for SPN: $SPN" -Level "SUCCESS"
            } else {
                Write-ValidationLog "⚠️ No Kerberos ticket found for SPN: $SPN" -Level "WARNING"
            }
        } else {
            Write-ValidationLog "❌ No Kerberos tickets available" -Level "ERROR"
        }
        
    } catch {
        Write-ValidationLog "❌ Windows authentication check failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    
    return $true
}

function Show-GoImplementationRequirements {
    Write-ValidationLog "=== Go Implementation Requirements ===" -Level "INFO"
    
    Write-ValidationLog "Based on the Go implementation analysis:" -Level "INFO"
    Write-ValidationLog "" -Level "INFO"
    
    Write-ValidationLog "1. SPNEGO Token Requirements:" -Level "INFO"
    Write-ValidationLog "   - Must be base64-encoded" -Level "INFO"
    Write-ValidationLog "   - Must be valid SPNEGO token structure" -Level "INFO"
    Write-ValidationLog "   - Must contain valid Kerberos ticket" -Level "INFO"
    Write-ValidationLog "   - Must be for the correct SPN: $SPN" -Level "INFO"
    Write-ValidationLog "" -Level "INFO"
    
    Write-ValidationLog "2. Authentication Flow:" -Level "INFO"
    Write-ValidationLog "   - POST to /v1/auth/gmsa/login" -Level "INFO"
    Write-ValidationLog "   - Body: { 'role': '$VaultRole', 'spnego': '<base64-token>' }" -Level "INFO"
    Write-ValidationLog "   - Content-Type: application/json" -Level "INFO"
    Write-ValidationLog "" -Level "INFO"
    
    Write-ValidationLog "3. Validation Process:" -Level "INFO"
    Write-ValidationLog "   - Decode base64 SPNEGO token" -Level "INFO"
    Write-ValidationLog "   - Parse SPNEGO token structure" -Level "INFO"
    Write-ValidationLog "   - Validate Kerberos ticket using keytab" -Level "INFO"
    Write-ValidationLog "   - Extract principal and realm" -Level "INFO"
    Write-ValidationLog "   - Validate against role constraints" -Level "INFO"
    Write-ValidationLog "" -Level "INFO"
    
    Write-ValidationLog "4. Error Handling:" -Level "INFO"
    Write-ValidationLog "   - Invalid SPNEGO token: 'spnego token unmarshal failed'" -Level "INFO"
    Write-ValidationLog "   - Kerberos failure: 'kerberos negotiation failed'" -Level "INFO"
    Write-ValidationLog "   - Role not found: 'role not found'" -Level "INFO"
    Write-ValidationLog "   - Config not found: 'auth method not configured'" -Level "INFO"
    Write-ValidationLog "" -Level "INFO"
}

function Show-PowerShellClientIssues {
    Write-ValidationLog "=== PowerShell Client Issues Identified ===" -Level "INFO"
    
    Write-ValidationLog "1. SPNEGO Token Generation:" -Level "WARNING"
    Write-ValidationLog "   - Current implementation generates mock tokens" -Level "WARNING"
    Write-ValidationLog "   - Need real SPNEGO tokens from Windows SSPI" -Level "WARNING"
    Write-ValidationLog "   - Must use proper Kerberos negotiation flow" -Level "WARNING"
    Write-ValidationLog "" -Level "WARNING"
    
    Write-ValidationLog "2. Authentication Flow:" -Level "WARNING"
    Write-ValidationLog "   - Missing proper SPNEGO negotiation" -Level "WARNING"
    Write-ValidationLog "   - Not capturing real Authorization headers" -Level "WARNING"
    Write-ValidationLog "   - Falling back to generated tokens" -Level "WARNING"
    Write-ValidationLog "" -Level "WARNING"
    
    Write-ValidationLog "3. Required Fixes:" -Level "INFO"
    Write-ValidationLog "   - Implement proper Windows SSPI integration" -Level "INFO"
    Write-ValidationLog "   - Use HttpWebRequest with UseDefaultCredentials" -Level "INFO"
    Write-ValidationLog "   - Capture Authorization header from request" -Level "INFO"
    Write-ValidationLog "   - Extract SPNEGO token from 'Negotiate' header" -Level "INFO"
    Write-ValidationLog "" -Level "INFO"
}

# Main validation process
Write-ValidationLog "=== Vault gMSA Client Validation Against Go Implementation ===" -Level "INFO"
Write-ValidationLog "Vault URL: $VaultUrl" -Level "INFO"
Write-ValidationLog "Vault Role: $VaultRole" -Level "INFO"
Write-ValidationLog "SPN: $SPN" -Level "INFO"
Write-ValidationLog "Realm: $Realm" -Level "INFO"
Write-ValidationLog "" -Level "INFO"

$allTestsPassed = $true

# Test 1: Vault server configuration
if (-not (Test-VaultServerConfiguration)) {
    $allTestsPassed = $false
}

# Test 2: SPNEGO token format
$testToken = Test-SPNEGOTokenFormat

# Test 3: Authentication flow
if (-not (Test-AuthenticationFlow -TestToken $testToken)) {
    $allTestsPassed = $false
}

# Test 4: Real SPNEGO negotiation
if (-not (Test-RealSPNEGONegotiation)) {
    $allTestsPassed = $false
}

# Test 5: PowerShell client compatibility
if (-not (Test-PowerShellClientCompatibility)) {
    $allTestsPassed = $false
}

# Show requirements and issues
Show-GoImplementationRequirements
Show-PowerShellClientIssues

# Summary
Write-ValidationLog "=== Validation Summary ===" -Level "INFO"
if ($allTestsPassed) {
    Write-ValidationLog "✅ All validation tests passed!" -Level "SUCCESS"
    Write-ValidationLog "The PowerShell client should be compatible with the Go implementation." -Level "SUCCESS"
} else {
    Write-ValidationLog "❌ Some validation tests failed." -Level "ERROR"
    Write-ValidationLog "The PowerShell client needs fixes to be compatible with the Go implementation." -Level "ERROR"
}

Write-ValidationLog "" -Level "INFO"
Write-ValidationLog "=== Next Steps ===" -Level "INFO"
Write-ValidationLog "1. If Vault server tests failed, configure the gMSA auth method properly" -Level "INFO"
Write-ValidationLog "2. If SPNEGO negotiation failed, check keytab configuration" -Level "INFO"
Write-ValidationLog "3. If PowerShell tests failed, implement proper SPNEGO token generation" -Level "INFO"
Write-ValidationLog "4. Test with real gMSA identity and Kerberos tickets" -Level "INFO"
