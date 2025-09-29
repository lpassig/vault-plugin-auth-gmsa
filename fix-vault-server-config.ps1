# =============================================================================
# Vault Server gMSA Configuration Fix Script
# =============================================================================
# This script fixes the Vault server configuration to properly support gMSA
# authentication according to the Go implementation requirements
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.example.com:8200",
    [string]$VaultToken = "",
    [string]$KeytabPath = "C:\vault-keytab.keytab",
    [string]$KeytabBase64 = "",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$Realm = "LOCAL.LAB",
    [string]$RoleName = "vault-gmsa-role",
    [string]$PolicyName = "vault-gmsa-policy",
    [switch]$SkipSSLVerification = $true,
    [switch]$DryRun = $false
)

# Bypass SSL certificate validation if requested
if ($SkipSSLVerification) {
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
        Write-Host "SSL certificate validation bypassed" -ForegroundColor Yellow
    } catch {
        Write-Host "Could not bypass SSL certificate validation: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Write-ConfigLog {
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
        "COMMAND" { "White" }
        default { "Gray" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

function Test-VaultConnectivity {
    Write-ConfigLog "Testing Vault server connectivity..." -Level "INFO"
    
    try {
        $healthUrl = "$VaultUrl/v1/sys/health"
        $response = Invoke-RestMethod -Uri $healthUrl -Method GET
        Write-ConfigLog "✅ Vault server is reachable" -Level "SUCCESS"
        Write-ConfigLog "   Version: $($response.version)" -Level "INFO"
        Write-ConfigLog "   Cluster Name: $($response.cluster_name)" -Level "INFO"
        return $true
    } catch {
        Write-ConfigLog "❌ Cannot reach Vault server: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-VaultToken {
    if ($VaultToken) {
        Write-ConfigLog "Using provided Vault token" -Level "INFO"
        return $VaultToken
    }
    
    # Try to get token from environment or prompt
    $envToken = $env:VAULT_TOKEN
    if ($envToken) {
        Write-ConfigLog "Using Vault token from environment" -Level "INFO"
        return $envToken
    }
    
    Write-ConfigLog "No Vault token provided. You may need to authenticate manually." -Level "WARNING"
    Write-ConfigLog "Set VAULT_TOKEN environment variable or use -VaultToken parameter" -Level "WARNING"
    return $null
}

function Get-KeytabBase64 {
    if ($KeytabBase64) {
        Write-ConfigLog "Using provided keytab base64" -Level "INFO"
        return $KeytabBase64
    }
    
    if (Test-Path $KeytabPath) {
        Write-ConfigLog "Reading keytab file: $KeytabPath" -Level "INFO"
        try {
            $keytabBytes = [System.IO.File]::ReadAllBytes($KeytabPath)
            $keytabBase64 = [System.Convert]::ToBase64String($keytabBytes)
            Write-ConfigLog "✅ Keytab file read successfully" -Level "SUCCESS"
            Write-ConfigLog "   File size: $($keytabBytes.Length) bytes" -Level "INFO"
            Write-ConfigLog "   Base64 length: $($keytabBase64.Length) characters" -Level "INFO"
            return $keytabBase64
        } catch {
            Write-ConfigLog "❌ Failed to read keytab file: $($_.Exception.Message)" -Level "ERROR"
            return $null
        }
    } else {
        Write-ConfigLog "❌ Keytab file not found: $KeytabPath" -Level "ERROR"
        Write-ConfigLog "Please provide keytab file path or base64 content" -Level "WARNING"
        return $null
    }
}

function Invoke-VaultCommand {
    param(
        [string]$Command,
        [string]$Description,
        [hashtable]$Headers = @{}
    )
    
    Write-ConfigLog "Executing: $Description" -Level "INFO"
    Write-ConfigLog "Command: $Command" -Level "COMMAND"
    
    if ($DryRun) {
        Write-ConfigLog "DRY RUN: Command would be executed" -Level "WARNING"
        return $true
    }
    
    try {
        # Parse the command to extract method, URL, and body
        $parts = $Command -split ' ', 3
        $method = $parts[0].ToUpper()
        $url = $parts[1]
        $body = if ($parts.Count -gt 2) { $parts[2] } else { $null }
        
        # Add Vault token to headers if available
        if ($VaultToken) {
            $Headers["X-Vault-Token"] = $VaultToken
        }
        
        $Headers["Content-Type"] = "application/json"
        
        if ($method -eq "GET") {
            $response = Invoke-RestMethod -Uri $url -Method GET -Headers $Headers
        } elseif ($method -eq "POST" -or $method -eq "PUT") {
            $response = Invoke-RestMethod -Uri $url -Method $method -Body $body -Headers $Headers
        } else {
            Write-ConfigLog "❌ Unsupported HTTP method: $method" -Level "ERROR"
            return $false
        }
        
        Write-ConfigLog "✅ Command executed successfully" -Level "SUCCESS"
        if ($response) {
            Write-ConfigLog "Response: $($response | ConvertTo-Json -Compress)" -Level "INFO"
        }
        return $true
        
    } catch {
        Write-ConfigLog "❌ Command failed: $($_.Exception.Message)" -Level "ERROR"
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-ConfigLog "   HTTP Status: $statusCode" -Level "ERROR"
            
            try {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorBody = $reader.ReadToEnd()
                $reader.Close()
                $errorStream.Close()
                Write-ConfigLog "   Error details: $errorBody" -Level "ERROR"
            } catch {
                Write-ConfigLog "   Could not read error details" -Level "WARNING"
            }
        }
        return $false
    }
}

function Enable-GMSAAuthMethod {
    Write-ConfigLog "=== Step 1: Enabling gMSA Authentication Method ===" -Level "INFO"
    
    $command = "POST $VaultUrl/v1/sys/auth/gmsa"
    $body = @{
        type = "gmsa"
        description = "gMSA authentication method"
    } | ConvertTo-Json
    
    $fullCommand = "$command '$body'"
    
    return Invoke-VaultCommand -Command $fullCommand -Description "Enable gMSA authentication method"
}

function Configure-GMSAAuth {
    param([string]$KeytabBase64)
    
    Write-ConfigLog "=== Step 2: Configuring gMSA Authentication ===" -Level "INFO"
    
    $configBody = @{
        realm = $Realm
        kdcs = "ADDC.local.lab"
        keytab = $KeytabBase64
        spn = $SPN
        allow_channel_binding = $false
        clock_skew_sec = 300
        realm_case_sensitive = $false
        spn_case_sensitive = $false
    } | ConvertTo-Json
    
    $command = "POST $VaultUrl/v1/auth/gmsa/config"
    $fullCommand = "$command '$configBody'"
    
    return Invoke-VaultCommand -Command $fullCommand -Description "Configure gMSA authentication"
}

function Create-GMSAPolicy {
    Write-ConfigLog "=== Step 3: Creating gMSA Policy ===" -Level "INFO"
    
    $policyBody = @"
path "kv/data/my-app/*" {
  capabilities = ["read"]
}

path "kv/data/vault-gmsa/*" {
  capabilities = ["read"]
}

path "secret/data/my-app/*" {
  capabilities = ["read"]
}
"@
    
    $command = "POST $VaultUrl/v1/sys/policies/acl/$PolicyName"
    $body = @{
        policy = $policyBody
    } | ConvertTo-Json
    
    $fullCommand = "$command '$body'"
    
    return Invoke-VaultCommand -Command $fullCommand -Description "Create gMSA policy"
}

function Create-GMSARole {
    Write-ConfigLog "=== Step 4: Creating gMSA Role ===" -Level "INFO"
    
    $roleBody = @{
        allowed_realms = $Realm
        allowed_spns = $SPN
        token_policies = $PolicyName
        token_type = "default"
        period = 0
        max_ttl = 3600
    } | ConvertTo-Json
    
    $command = "POST $VaultUrl/v1/auth/gmsa/role/$RoleName"
    $fullCommand = "$command '$roleBody'"
    
    return Invoke-VaultCommand -Command $fullCommand -Description "Create gMSA role"
}

function Enable-KVSecretsEngine {
    Write-ConfigLog "=== Step 5: Enabling KV Secrets Engine ===" -Level "INFO"
    
    $command = "POST $VaultUrl/v1/sys/mounts/kv"
    $body = @{
        type = "kv-v2"
        description = "KV secrets engine for gMSA testing"
    } | ConvertTo-Json
    
    $fullCommand = "$command '$body'"
    
    return Invoke-VaultCommand -Command $fullCommand -Description "Enable KV secrets engine"
}

function Create-TestSecrets {
    Write-ConfigLog "=== Step 6: Creating Test Secrets ===" -Level "INFO"
    
    # Create database secret
    $dbSecretBody = @{
        data = @{
            host = "db-server.local.lab"
            username = "app-user"
            password = "secure-password-123"
            port = 1433
        }
    } | ConvertTo-Json
    
    $dbCommand = "POST $VaultUrl/v1/kv/data/my-app/database"
    $dbFullCommand = "$dbCommand '$dbSecretBody'"
    
    $dbResult = Invoke-VaultCommand -Command $dbFullCommand -Description "Create database secret"
    
    # Create API secret
    $apiSecretBody = @{
        data = @{
            api_key = "abc123def456ghi789"
            endpoint = "https://api.local.lab"
            secret = "xyz789uvw012rst345"
        }
    } | ConvertTo-Json
    
    $apiCommand = "POST $VaultUrl/v1/kv/data/my-app/api"
    $apiFullCommand = "$apiCommand '$apiSecretBody'"
    
    $apiResult = Invoke-VaultCommand -Command $apiFullCommand -Description "Create API secret"
    
    return ($dbResult -and $apiResult)
}

function Test-GMSAConfiguration {
    Write-ConfigLog "=== Step 7: Testing gMSA Configuration ===" -Level "INFO"
    
    # Test 1: Check if gMSA auth method is enabled
    Write-ConfigLog "Testing gMSA auth method..." -Level "INFO"
    $authCommand = "GET $VaultUrl/v1/sys/auth"
    
    try {
        $headers = @{}
        if ($VaultToken) { $headers["X-Vault-Token"] = $VaultToken }
        
        $authResponse = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/auth" -Method GET -Headers $headers
        
        if ($authResponse.data.gmsa) {
            Write-ConfigLog "✅ gMSA auth method is enabled" -Level "SUCCESS"
        } else {
            Write-ConfigLog "❌ gMSA auth method is NOT enabled" -Level "ERROR"
            return $false
        }
    } catch {
        Write-ConfigLog "❌ Failed to check auth methods: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    
    # Test 2: Check gMSA configuration
    Write-ConfigLog "Testing gMSA configuration..." -Level "INFO"
    try {
        $headers = @{}
        if ($VaultToken) { $headers["X-Vault-Token"] = $VaultToken }
        
        $configResponse = Invoke-RestMethod -Uri "$VaultUrl/v1/auth/gmsa/config" -Method GET -Headers $headers
        
        Write-ConfigLog "✅ gMSA configuration found" -Level "SUCCESS"
        Write-ConfigLog "   SPN: $($configResponse.data.spn)" -Level "INFO"
        Write-ConfigLog "   Realm: $($configResponse.data.realm)" -Level "INFO"
        
        if ($configResponse.data.spn -ne $SPN) {
            Write-ConfigLog "⚠️ SPN mismatch: Expected '$SPN', Got '$($configResponse.data.spn)'" -Level "WARNING"
        }
        if ($configResponse.data.realm -ne $Realm) {
            Write-ConfigLog "⚠️ Realm mismatch: Expected '$Realm', Got '$($configResponse.data.realm)'" -Level "WARNING"
        }
        
    } catch {
        Write-ConfigLog "❌ Failed to check gMSA configuration: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    
    # Test 3: Check gMSA role
    Write-ConfigLog "Testing gMSA role..." -Level "INFO"
    try {
        $headers = @{}
        if ($VaultToken) { $headers["X-Vault-Token"] = $VaultToken }
        
        $roleResponse = Invoke-RestMethod -Uri "$VaultUrl/v1/auth/gmsa/role/$RoleName" -Method GET -Headers $headers
        
        Write-ConfigLog "✅ gMSA role '$RoleName' found" -Level "SUCCESS"
        Write-ConfigLog "   Token Policies: $($roleResponse.data.token_policies -join ', ')" -Level "INFO"
        
    } catch {
        Write-ConfigLog "❌ Failed to check gMSA role: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    
    # Test 4: Test SPNEGO negotiation
    Write-ConfigLog "Testing SPNEGO negotiation..." -Level "INFO"
    try {
        $loginUrl = "$VaultUrl/v1/auth/gmsa/login"
        
        # Create request without credentials to trigger 401 challenge
        $request = [System.Net.HttpWebRequest]::Create($loginUrl)
        $request.Method = "POST"
        $request.ContentType = "application/json"
        $request.Timeout = 10000
        
        $body = @{
            role = $RoleName
        } | ConvertTo-Json
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $request.ContentLength = $bodyBytes.Length
        
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $requestStream.Close()
        
        try {
            $response = $request.GetResponse()
            Write-ConfigLog "❌ Unexpected: Got response without authentication challenge" -Level "ERROR"
            $response.Close()
            return $false
        } catch {
            $statusCode = $_.Exception.Response.StatusCode
            Write-ConfigLog "✅ Got expected error response: $statusCode" -Level "SUCCESS"
            
            # Check for WWW-Authenticate header
            $response = $_.Exception.Response
            if ($response.Headers["WWW-Authenticate"]) {
                $wwwAuth = $response.Headers["WWW-Authenticate"]
                Write-ConfigLog "✅ WWW-Authenticate header found: $wwwAuth" -Level "SUCCESS"
                
                if ($wwwAuth -like "*Negotiate*") {
                    Write-ConfigLog "✅ SPNEGO negotiation is properly configured!" -Level "SUCCESS"
                    return $true
                } else {
                    Write-ConfigLog "❌ WWW-Authenticate header does not contain 'Negotiate'" -Level "ERROR"
                    return $false
                }
            } else {
                Write-ConfigLog "❌ No WWW-Authenticate header found" -Level "ERROR"
                Write-ConfigLog "   This indicates the gMSA auth method is not properly configured for SPNEGO" -Level "WARNING"
                return $false
            }
        }
    } catch {
        Write-ConfigLog "❌ SPNEGO negotiation test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Show-ConfigurationSummary {
    Write-ConfigLog "=== Configuration Summary ===" -Level "INFO"
    Write-ConfigLog "Vault URL: $VaultUrl" -Level "INFO"
    Write-ConfigLog "SPN: $SPN" -Level "INFO"
    Write-ConfigLog "Realm: $Realm" -Level "INFO"
    Write-ConfigLog "Role Name: $RoleName" -Level "INFO"
    Write-ConfigLog "Policy Name: $PolicyName" -Level "INFO"
    Write-ConfigLog "Keytab Path: $KeytabPath" -Level "INFO"
    Write-ConfigLog "" -Level "INFO"
    
    Write-ConfigLog "=== Manual Commands (if needed) ===" -Level "INFO"
    Write-ConfigLog "1. Enable gMSA auth method:" -Level "COMMAND"
    Write-ConfigLog "   vault auth enable gmsa" -Level "COMMAND"
    Write-ConfigLog "" -Level "COMMAND"
    
    Write-ConfigLog "2. Configure gMSA authentication:" -Level "COMMAND"
    Write-ConfigLog "   vault write auth/gmsa/config \" -Level "COMMAND"
    Write-ConfigLog "       realm='$Realm' \" -Level "COMMAND"
    Write-ConfigLog "       kdcs='ADDC.local.lab' \" -Level "COMMAND"
    Write-ConfigLog "       keytab='<BASE64_KEYTAB>' \" -Level "COMMAND"
    Write-ConfigLog "       spn='$SPN' \" -Level "COMMAND"
    Write-ConfigLog "       allow_channel_binding=false" -Level "COMMAND"
    Write-ConfigLog "" -Level "COMMAND"
    
    Write-ConfigLog "3. Create gMSA role:" -Level "COMMAND"
    Write-ConfigLog "   vault write auth/gmsa/role/$RoleName \" -Level "COMMAND"
    Write-ConfigLog "       allowed_realms='$Realm' \" -Level "COMMAND"
    Write-ConfigLog "       allowed_spns='$SPN' \" -Level "COMMAND"
    Write-ConfigLog "       token_policies='$PolicyName' \" -Level "COMMAND"
    Write-ConfigLog "       token_ttl=1h" -Level "COMMAND"
    Write-ConfigLog "" -Level "COMMAND"
    
    Write-ConfigLog "4. Create policy:" -Level "COMMAND"
    Write-ConfigLog "   vault policy write $PolicyName - <<EOF" -Level "COMMAND"
    Write-ConfigLog "   path `"kv/data/my-app/*`" {" -Level "COMMAND"
    Write-ConfigLog "     capabilities = [`"read`"]" -Level "COMMAND"
    Write-ConfigLog "   }" -Level "COMMAND"
    Write-ConfigLog "   EOF" -Level "COMMAND"
    Write-ConfigLog "" -Level "COMMAND"
    
    Write-ConfigLog "5. Enable KV secrets engine:" -Level "COMMAND"
    Write-ConfigLog "   vault secrets enable -path=kv kv-v2" -Level "COMMAND"
    Write-ConfigLog "" -Level "COMMAND"
    
    Write-ConfigLog "6. Create test secrets:" -Level "COMMAND"
    Write-ConfigLog "   vault kv put kv/my-app/database host=db-server.local.lab username=app-user password=secure-password-123" -Level "COMMAND"
    Write-ConfigLog "   vault kv put kv/my-app/api api_key=abc123def456ghi789 endpoint=https://api.local.lab" -Level "COMMAND"
    Write-ConfigLog "" -Level "COMMAND"
}

# Main execution
Write-ConfigLog "=== Vault Server gMSA Configuration Fix ===" -Level "INFO"
Write-ConfigLog "This script will configure Vault server for proper gMSA authentication" -Level "INFO"
Write-ConfigLog "" -Level "INFO"

# Step 0: Validate inputs and connectivity
if (-not (Test-VaultConnectivity)) {
    Write-ConfigLog "Cannot proceed without Vault server connectivity" -Level "ERROR"
    exit 1
}

$VaultToken = Get-VaultToken
if (-not $VaultToken) {
    Write-ConfigLog "No Vault token available. Some operations may fail." -Level "WARNING"
}

$KeytabBase64 = Get-KeytabBase64
if (-not $KeytabBase64) {
    Write-ConfigLog "Cannot proceed without keytab data" -Level "ERROR"
    exit 1
}

# Execute configuration steps
$allStepsPassed = $true

$allStepsPassed = $allStepsPassed -and (Enable-GMSAAuthMethod)
$allStepsPassed = $allStepsPassed -and (Configure-GMSAAuth -KeytabBase64 $KeytabBase64)
$allStepsPassed = $allStepsPassed -and (Create-GMSAPolicy)
$allStepsPassed = $allStepsPassed -and (Create-GMSARole)
$allStepsPassed = $allStepsPassed -and (Enable-KVSecretsEngine)
$allStepsPassed = $allStepsPassed -and (Create-TestSecrets)

# Test the configuration
$testPassed = Test-GMSAConfiguration

# Show summary
Show-ConfigurationSummary

# Final result
Write-ConfigLog "=== Final Result ===" -Level "INFO"
if ($allStepsPassed -and $testPassed) {
    Write-ConfigLog "✅ Vault server gMSA configuration completed successfully!" -Level "SUCCESS"
    Write-ConfigLog "The PowerShell client should now be able to authenticate properly." -Level "SUCCESS"
} else {
    Write-ConfigLog "❌ Vault server gMSA configuration failed or incomplete." -Level "ERROR"
    Write-ConfigLog "Check the error messages above and fix the issues manually." -Level "ERROR"
}

Write-ConfigLog "" -Level "INFO"
Write-ConfigLog "Next steps:" -Level "INFO"
Write-ConfigLog "1. Test the PowerShell client: .\vault-client-app.ps1" -Level "INFO"
Write-ConfigLog "2. Check Vault logs for any authentication errors" -Level "INFO"
Write-ConfigLog "3. Verify gMSA has valid Kerberos tickets: klist" -Level "INFO"
