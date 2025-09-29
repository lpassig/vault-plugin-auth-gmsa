# =============================================================================
# Vault Server Configuration Check and Fix Script
# =============================================================================
# This script checks the current Vault server configuration and fixes any issues
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.example.com:8200",
    [string]$VaultToken = "",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$Realm = "LOCAL.LAB",
    [string]$RoleName = "vault-gmsa-role",
    [string]$PolicyName = "vault-gmsa-policy",
    [switch]$SkipSSLVerification = $true,
    [switch]$AutoFix = $false
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

function Write-CheckLog {
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
        "FIX" { "Magenta" }
        default { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

function Test-VaultConnectivity {
    Write-CheckLog "Testing Vault server connectivity..." -Level "INFO"
    
    try {
        $healthUrl = "$VaultUrl/v1/sys/health"
        $response = Invoke-RestMethod -Uri $healthUrl -Method GET
        Write-CheckLog "✅ Vault server is reachable" -Level "SUCCESS"
        Write-CheckLog "   Version: $($response.version)" -Level "INFO"
        Write-CheckLog "   Cluster Name: $($response.cluster_name)" -Level "INFO"
        return $true
    } catch {
        Write-CheckLog "❌ Cannot reach Vault server: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-VaultToken {
    if ($VaultToken) {
        Write-CheckLog "Using provided Vault token" -Level "INFO"
        return $VaultToken
    }
    
    $envToken = $env:VAULT_TOKEN
    if ($envToken) {
        Write-CheckLog "Using Vault token from environment" -Level "INFO"
        return $envToken
    }
    
    Write-CheckLog "No Vault token provided. Some checks may fail." -Level "WARNING"
    return $null
}

function Check-AuthMethods {
    Write-CheckLog "=== Checking Authentication Methods ===" -Level "INFO"
    
    try {
        $headers = @{}
        if ($VaultToken) { $headers["X-Vault-Token"] = $VaultToken }
        
        $authUrl = "$VaultUrl/v1/sys/auth"
        $response = Invoke-RestMethod -Uri $authUrl -Method GET -Headers $headers
        
        Write-CheckLog "Available authentication methods:" -Level "INFO"
        $gmsaFound = $false
        
        if ($response.data) {
            foreach ($method in $response.data.PSObject.Properties) {
                $methodName = $method.Name
                $methodType = $method.Value.type
                $methodDesc = $method.Value.description
                
                Write-CheckLog "   - $methodName`: $methodType" -Level "INFO"
                if ($methodDesc) {
                    Write-CheckLog "     Description: $methodDesc" -Level "INFO"
                }
                
                if ($methodName -eq "gmsa" -or $methodName -eq "gmsa/") {
                    $gmsaFound = $true
                    Write-CheckLog "✅ gMSA authentication method is enabled" -Level "SUCCESS"
                }
            }
        }
        
        if (-not $gmsaFound) {
            Write-CheckLog "❌ gMSA authentication method is NOT enabled" -Level "ERROR"
            Write-CheckLog "   This is required for gMSA authentication" -Level "WARNING"
            return $false
        }
        
        return $true
        
    } catch {
        Write-CheckLog "❌ Failed to check authentication methods: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Check-GMSAConfiguration {
    Write-CheckLog "=== Checking gMSA Configuration ===" -Level "INFO"
    
    try {
        $headers = @{}
        if ($VaultToken) { $headers["X-Vault-Token"] = $VaultToken }
        
        $configUrl = "$VaultUrl/v1/auth/gmsa/config"
        $response = Invoke-RestMethod -Uri $configUrl -Method GET -Headers $headers
        
        Write-CheckLog "✅ gMSA configuration found" -Level "SUCCESS"
        Write-CheckLog "   SPN: $($response.data.spn)" -Level "INFO"
        Write-CheckLog "   Realm: $($response.data.realm)" -Level "INFO"
        Write-CheckLog "   Allow Channel Binding: $($response.data.allow_channel_binding)" -Level "INFO"
        Write-CheckLog "   Clock Skew: $($response.data.clock_skew_sec) seconds" -Level "INFO"
        
        $issues = @()
        
        # Check SPN
        if ($response.data.spn -ne $SPN) {
            $issues += "SPN mismatch: Expected '$SPN', Got '$($response.data.spn)'"
        }
        
        # Check Realm
        if ($response.data.realm -ne $Realm) {
            $issues += "Realm mismatch: Expected '$Realm', Got '$($response.data.realm)'"
        }
        
        # Check if keytab is configured
        if (-not $response.data.keytab -or $response.data.keytab.Length -eq 0) {
            $issues += "Keytab is not configured or empty"
        }
        
        if ($issues.Count -gt 0) {
            Write-CheckLog "⚠️ Configuration issues found:" -Level "WARNING"
            foreach ($issue in $issues) {
                Write-CheckLog "   - $issue" -Level "WARNING"
            }
            return $false
        } else {
            Write-CheckLog "✅ gMSA configuration is correct" -Level "SUCCESS"
            return $true
        }
        
    } catch {
        Write-CheckLog "❌ Failed to check gMSA configuration: $($_.Exception.Message)" -Level "ERROR"
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-CheckLog "   HTTP Status: $statusCode" -Level "ERROR"
        }
        return $false
    }
}

function Check-GMSARole {
    Write-CheckLog "=== Checking gMSA Role ===" -Level "INFO"
    
    try {
        $headers = @{}
        if ($VaultToken) { $headers["X-Vault-Token"] = $VaultToken }
        
        $roleUrl = "$VaultUrl/v1/auth/gmsa/role/$RoleName"
        $response = Invoke-RestMethod -Uri $roleUrl -Method GET -Headers $headers
        
        Write-CheckLog "✅ gMSA role '$RoleName' found" -Level "SUCCESS"
        Write-CheckLog "   Allowed Realms: $($response.data.allowed_realms -join ', ')" -Level "INFO"
        Write-CheckLog "   Allowed SPNs: $($response.data.allowed_spns -join ', ')" -Level "INFO"
        Write-CheckLog "   Token Policies: $($response.data.token_policies -join ', ')" -Level "INFO"
        Write-CheckLog "   Token Type: $($response.data.token_type)" -Level "INFO"
        Write-CheckLog "   Max TTL: $($response.data.max_ttl) seconds" -Level "INFO"
        
        $issues = @()
        
        # Check allowed realms
        if (-not $response.data.allowed_realms -or $response.data.allowed_realms -notcontains $Realm) {
            $issues += "Allowed realms does not include '$Realm'"
        }
        
        # Check allowed SPNs
        if (-not $response.data.allowed_spns -or $response.data.allowed_spns -notcontains $SPN) {
            $issues += "Allowed SPNs does not include '$SPN'"
        }
        
        # Check token policies
        if (-not $response.data.token_policies -or $response.data.token_policies -notcontains $PolicyName) {
            $issues += "Token policies does not include '$PolicyName'"
        }
        
        if ($issues.Count -gt 0) {
            Write-CheckLog "⚠️ Role configuration issues found:" -Level "WARNING"
            foreach ($issue in $issues) {
                Write-CheckLog "   - $issue" -Level "WARNING"
            }
            return $false
        } else {
            Write-CheckLog "✅ gMSA role configuration is correct" -Level "SUCCESS"
            return $true
        }
        
    } catch {
        Write-CheckLog "❌ Failed to check gMSA role: $($_.Exception.Message)" -Level "ERROR"
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-CheckLog "   HTTP Status: $statusCode" -Level "ERROR"
        }
        return $false
    }
}

function Check-GMSAPolicy {
    Write-CheckLog "=== Checking gMSA Policy ===" -Level "INFO"
    
    try {
        $headers = @{}
        if ($VaultToken) { $headers["X-Vault-Token"] = $VaultToken }
        
        $policyUrl = "$VaultUrl/v1/sys/policies/acl/$PolicyName"
        $response = Invoke-RestMethod -Uri $policyUrl -Method GET -Headers $headers
        
        Write-CheckLog "✅ gMSA policy '$PolicyName' found" -Level "SUCCESS"
        Write-CheckLog "   Policy content:" -Level "INFO"
        Write-CheckLog "   $($response.data.policy)" -Level "INFO"
        
        # Check if policy has required permissions
        $policyContent = $response.data.policy
        if ($policyContent -notmatch 'kv/data/my-app/\*') {
            Write-CheckLog "⚠️ Policy may not have required KV permissions" -Level "WARNING"
            return $false
        }
        
        Write-CheckLog "✅ gMSA policy configuration is correct" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-CheckLog "❌ Failed to check gMSA policy: $($_.Exception.Message)" -Level "ERROR"
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-CheckLog "   HTTP Status: $statusCode" -Level "ERROR"
        }
        return $false
    }
}

function Check-KVSecretsEngine {
    Write-CheckLog "=== Checking KV Secrets Engine ===" -Level "INFO"
    
    try {
        $headers = @{}
        if ($VaultToken) { $headers["X-Vault-Token"] = $VaultToken }
        
        $secretsUrl = "$VaultUrl/v1/sys/mounts"
        $response = Invoke-RestMethod -Uri $secretsUrl -Method GET -Headers $headers
        
        $kvFound = $false
        
        if ($response.data) {
            foreach ($mount in $response.data.PSObject.Properties) {
                $mountName = $mount.Name
                $mountType = $mount.Value.type
                
                if ($mountName -eq "kv/" -and $mountType -eq "kv-v2") {
                    $kvFound = $true
                    Write-CheckLog "✅ KV secrets engine is enabled at path 'kv'" -Level "SUCCESS"
                    Write-CheckLog "   Type: $mountType" -Level "INFO"
                    Write-CheckLog "   Description: $($mount.Value.description)" -Level "INFO"
                }
            }
        }
        
        if (-not $kvFound) {
            Write-CheckLog "❌ KV secrets engine is NOT enabled" -Level "ERROR"
            Write-CheckLog "   This is required for storing test secrets" -Level "WARNING"
            return $false
        }
        
        return $true
        
    } catch {
        Write-CheckLog "❌ Failed to check secrets engines: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Check-TestSecrets {
    Write-CheckLog "=== Checking Test Secrets ===" -Level "INFO"
    
    try {
        $headers = @{}
        if ($VaultToken) { $headers["X-Vault-Token"] = $VaultToken }
        
        # Check database secret
        $dbSecretUrl = "$VaultUrl/v1/kv/data/my-app/database"
        try {
            $dbResponse = Invoke-RestMethod -Uri $dbSecretUrl -Method GET -Headers $headers
            Write-CheckLog "✅ Database secret found" -Level "SUCCESS"
            Write-CheckLog "   Keys: $($dbResponse.data.data.PSObject.Properties.Name -join ', ')" -Level "INFO"
        } catch {
            Write-CheckLog "❌ Database secret not found" -Level "ERROR"
            return $false
        }
        
        # Check API secret
        $apiSecretUrl = "$VaultUrl/v1/kv/data/my-app/api"
        try {
            $apiResponse = Invoke-RestMethod -Uri $apiSecretUrl -Method GET -Headers $headers
            Write-CheckLog "✅ API secret found" -Level "SUCCESS"
            Write-CheckLog "   Keys: $($apiResponse.data.data.PSObject.Properties.Name -join ', ')" -Level "INFO"
        } catch {
            Write-CheckLog "❌ API secret not found" -Level "ERROR"
            return $false
        }
        
        return $true
        
    } catch {
        Write-CheckLog "❌ Failed to check test secrets: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-SPNEGONegotiation {
    Write-CheckLog "=== Testing SPNEGO Negotiation ===" -Level "INFO"
    
    try {
        $loginUrl = "$VaultUrl/v1/auth/gmsa/login"
        
        # Create request without credentials to trigger 401 challenge
        $request = [System.Net.HttpWebRequest]::Create($loginUrl)
        $request.Method = "POST"
        $request.ContentType = "application/json"
        $request.Timeout = 10000
        $request.UserAgent = "Vault-gMSA-Check/1.0"
        
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
            Write-CheckLog "❌ Unexpected: Got response without authentication challenge" -Level "ERROR"
            Write-CheckLog "   Status Code: $($response.StatusCode)" -Level "WARNING"
            $response.Close()
            return $false
        } catch {
            $statusCode = $_.Exception.Response.StatusCode
            Write-CheckLog "✅ Got expected error response: $statusCode" -Level "SUCCESS"
            
            # Check for WWW-Authenticate header
            $response = $_.Exception.Response
            if ($response.Headers["WWW-Authenticate"]) {
                $wwwAuth = $response.Headers["WWW-Authenticate"]
                Write-CheckLog "✅ WWW-Authenticate header found: $wwwAuth" -Level "SUCCESS"
                
                if ($wwwAuth -like "*Negotiate*") {
                    Write-CheckLog "✅ SPNEGO negotiation is properly configured!" -Level "SUCCESS"
                    return $true
                } else {
                    Write-CheckLog "❌ WWW-Authenticate header does not contain 'Negotiate'" -Level "ERROR"
                    Write-CheckLog "   Expected: Contains 'Negotiate'" -Level "WARNING"
                    Write-CheckLog "   Actual: $wwwAuth" -Level "WARNING"
                    return $false
                }
            } else {
                Write-CheckLog "❌ No WWW-Authenticate header found" -Level "ERROR"
                Write-CheckLog "   This indicates the gMSA auth method is not properly configured for SPNEGO" -Level "WARNING"
                return $false
            }
        }
    } catch {
        Write-CheckLog "❌ SPNEGO negotiation test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Show-FixCommands {
    Write-CheckLog "=== Fix Commands ===" -Level "FIX"
    Write-CheckLog "To fix the configuration issues, run:" -Level "FIX"
    Write-CheckLog "" -Level "FIX"
    Write-CheckLog ".\fix-vault-server-config.ps1 -VaultUrl `"$VaultUrl`" -VaultToken `"$VaultToken`"" -Level "FIX"
    Write-CheckLog "" -Level "FIX"
    Write-CheckLog "Or run the individual commands manually:" -Level "FIX"
    Write-CheckLog "" -Level "FIX"
    Write-CheckLog "# Enable gMSA auth method" -Level "FIX"
    Write-CheckLog "vault auth enable gmsa" -Level "FIX"
    Write-CheckLog "" -Level "FIX"
    Write-CheckLog "# Configure gMSA authentication" -Level "FIX"
    Write-CheckLog "vault write auth/gmsa/config \" -Level "FIX"
    Write-CheckLog "    realm='$Realm' \" -Level "FIX"
    Write-CheckLog "    kdcs='ADDC.local.lab' \" -Level "FIX"
    Write-CheckLog "    keytab='<BASE64_KEYTAB>' \" -Level "FIX"
    Write-CheckLog "    spn='$SPN' \" -Level "FIX"
    Write-CheckLog "    allow_channel_binding=false" -Level "FIX"
    Write-CheckLog "" -Level "FIX"
    Write-CheckLog "# Create gMSA role" -Level "FIX"
    Write-CheckLog "vault write auth/gmsa/role/$RoleName \" -Level "FIX"
    Write-CheckLog "    allowed_realms='$Realm' \" -Level "FIX"
    Write-CheckLog "    allowed_spns='$SPN' \" -Level "FIX"
    Write-CheckLog "    token_policies='$PolicyName' \" -Level "FIX"
    Write-CheckLog "    token_ttl=1h" -Level "FIX"
    Write-CheckLog "" -Level "FIX"
}

function Invoke-AutoFix {
    Write-CheckLog "=== Auto-Fix Mode ===" -Level "FIX"
    Write-CheckLog "Running automatic configuration fix..." -Level "FIX"
    
    try {
        # Run the fix script
        $fixScript = ".\fix-vault-server-config.ps1"
        if (Test-Path $fixScript) {
            Write-CheckLog "Executing fix script: $fixScript" -Level "FIX"
            & $fixScript -VaultUrl $VaultUrl -VaultToken $VaultToken -SkipSSLVerification:$SkipSSLVerification
        } else {
            Write-CheckLog "Fix script not found: $fixScript" -Level "ERROR"
            Show-FixCommands
        }
    } catch {
        Write-CheckLog "Auto-fix failed: $($_.Exception.Message)" -Level "ERROR"
        Show-FixCommands
    }
}

# Main execution
Write-CheckLog "=== Vault Server Configuration Check ===" -Level "INFO"
Write-CheckLog "Vault URL: $VaultUrl" -Level "INFO"
Write-CheckLog "SPN: $SPN" -Level "INFO"
Write-CheckLog "Realm: $Realm" -Level "INFO"
Write-CheckLog "Role Name: $RoleName" -Level "INFO"
Write-CheckLog "Policy Name: $PolicyName" -Level "INFO"
Write-CheckLog "" -Level "INFO"

# Step 0: Validate inputs and connectivity
if (-not (Test-VaultConnectivity)) {
    Write-CheckLog "Cannot proceed without Vault server connectivity" -Level "ERROR"
    exit 1
}

$VaultToken = Get-VaultToken
if (-not $VaultToken) {
    Write-CheckLog "No Vault token available. Some checks may fail." -Level "WARNING"
}

# Execute configuration checks
$allChecksPassed = $true

$allChecksPassed = $allChecksPassed -and (Check-AuthMethods)
$allChecksPassed = $allChecksPassed -and (Check-GMSAConfiguration)
$allChecksPassed = $allChecksPassed -and (Check-GMSARole)
$allChecksPassed = $allChecksPassed -and (Check-GMSAPolicy)
$allChecksPassed = $allChecksPassed -and (Check-KVSecretsEngine)
$allChecksPassed = $allChecksPassed -and (Check-TestSecrets)
$allChecksPassed = $allChecksPassed -and (Test-SPNEGONegotiation)

# Show results
Write-CheckLog "=== Configuration Check Summary ===" -Level "INFO"
if ($allChecksPassed) {
    Write-CheckLog "✅ All configuration checks passed!" -Level "SUCCESS"
    Write-CheckLog "The Vault server is properly configured for gMSA authentication." -Level "SUCCESS"
} else {
    Write-CheckLog "❌ Some configuration checks failed." -Level "ERROR"
    Write-CheckLog "The Vault server needs configuration fixes." -Level "ERROR"
    
    if ($AutoFix) {
        Invoke-AutoFix
    } else {
        Show-FixCommands
    }
}

Write-CheckLog "" -Level "INFO"
Write-CheckLog "Next steps:" -Level "INFO"
if ($allChecksPassed) {
    Write-CheckLog "1. Test the PowerShell client: .\vault-client-app.ps1" -Level "INFO"
    Write-CheckLog "2. Verify gMSA has valid Kerberos tickets: klist" -Level "INFO"
    Write-CheckLog "3. Check Vault logs for authentication events" -Level "INFO"
} else {
    Write-CheckLog "1. Fix the configuration issues using the commands above" -Level "INFO"
    Write-CheckLog "2. Re-run this check script to verify fixes" -Level "INFO"
    Write-CheckLog "3. Test the PowerShell client after fixes" -Level "INFO"
}
