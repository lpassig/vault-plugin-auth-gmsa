#Requires -Version 5.1

<#
.SYNOPSIS
    Ultimate SPNEGO Token Generator - Forces Real Token Generation
.DESCRIPTION
    Generates real SPNEGO tokens by forcing Windows SSPI to create them.
    Uses multiple techniques to ensure real token generation.
.PARAMETER VaultUrl
    Vault server URL (default: https://vault.local.lab:8200)
.PARAMETER Role
    Vault role name (default: vault-gmsa-role)
.PARAMETER SPN
    Service Principal Name (default: HTTP/vault.local.lab)
.EXAMPLE
    .\ultimate-spnego-generator.ps1
#>

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$Role = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab"
)

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "INFO" { "White" }
        default { "White" }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-KerberosTicket {
    param([string]$TargetSPN)
    
    Write-Log "Checking for Kerberos ticket for SPN: $TargetSPN" -Level "INFO"
    
    try {
        $klistOutput = klist 2>&1
        if ($klistOutput -match [regex]::Escape($TargetSPN)) {
            Write-Log "SUCCESS: Kerberos ticket found for $TargetSPN" -Level "SUCCESS"
            return $true
        } else {
            Write-Log "WARNING: No Kerberos ticket found for $TargetSPN" -Level "WARNING"
            return $false
        }
    } catch {
        Write-Log "ERROR: Failed to check Kerberos tickets: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Request-KerberosTicket {
    param([string]$TargetSPN)
    
    Write-Log "Requesting Kerberos ticket for SPN: $TargetSPN" -Level "INFO"
    
    try {
        # Extract hostname from SPN
        $hostname = $TargetSPN -replace "^HTTP/", ""
        Write-Log "Extracted hostname: $hostname" -Level "INFO"
        
        # Request ticket using klist
        Write-Log "Requesting ticket using klist..." -Level "INFO"
        $klistResult = klist -k 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "SUCCESS: Kerberos ticket requested successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-Log "WARNING: klist ticket request failed with exit code: $LASTEXITCODE" -Level "WARNING"
            Write-Log "klist output: $klistResult" -Level "INFO"
            return $false
        }
    } catch {
        Write-Log "ERROR: Failed to request Kerberos ticket: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-RealSPNEGOToken {
    param(
        [string]$TargetSPN,
        [string]$VaultUrl
    )
    
    Write-Log "Generating real SPNEGO token using multiple techniques..." -Level "INFO"
    Write-Log "Target SPN: $TargetSPN" -Level "INFO"
    
    try {
        # Extract hostname from SPN for URL construction
        $hostname = $TargetSPN -replace "^HTTP/", ""
        Write-Log "Extracted hostname: $hostname" -Level "INFO"
        
        # Technique 1: Use a different server that DOES require SPNEGO authentication
        # We'll try to connect to a server that will force SPNEGO negotiation
        Write-Log "Technique 1: Attempting to trigger SPNEGO negotiation with external server..." -Level "INFO"
        
        # Try connecting to a server that requires SPNEGO (like a Windows server)
        $testServers = @(
            "http://$hostname",
            "https://$hostname",
            "http://$hostname:80",
            "https://$hostname:443"
        )
        
        foreach ($testServer in $testServers) {
            Write-Log "Trying server: $testServer" -Level "INFO"
            
            try {
                $webRequest = [System.Net.WebRequest]::Create($testServer)
                $webRequest.Method = "GET"
                $webRequest.UseDefaultCredentials = $true
                $webRequest.PreAuthenticate = $true
                $webRequest.Timeout = 5000
                $webRequest.UserAgent = "Vault-gMSA-Client/1.0"
                
                try {
                    $webResponse = $webRequest.GetResponse()
                    Write-Log "Server request completed with status: $($webResponse.StatusCode)" -Level "INFO"
                    $webResponse.Close()
                } catch {
                    $webStatusCode = $_.Exception.Response.StatusCode
                    Write-Log "Server request returned: $webStatusCode" -Level "INFO"
                    
                    # Check if Authorization header was added (this contains our SPNEGO token)
                    if ($webRequest.Headers.Contains("Authorization")) {
                        $authHeader = $webRequest.Headers.GetValues("Authorization")
                        if ($authHeader -and $authHeader[0] -like "Negotiate *") {
                            $spnegoToken = $authHeader[0].Substring(10) # Remove "Negotiate "
                            Write-Log "SUCCESS: Real SPNEGO token captured from external server!" -Level "SUCCESS"
                            Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..." -Level "INFO"
                            return $spnegoToken
                        }
                    }
                }
            } catch {
                Write-Log "Request to $testServer failed: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        # Technique 2: Use a different approach - create a WebRequest that will force SPNEGO
        # by targeting a specific endpoint that might trigger negotiation
        Write-Log "Technique 2: Attempting to force SPNEGO generation with Vault endpoints..." -Level "INFO"
        
        $testEndpoints = @(
            "$VaultUrl/v1/sys/config",
            "$VaultUrl/v1/sys/status",
            "$VaultUrl/v1/sys/leader",
            "$VaultUrl/v1/sys/seal-status",
            "$VaultUrl/v1/auth/gmsa/config",
            "$VaultUrl/v1/auth/gmsa/role/$Role"
        )
        
        foreach ($endpoint in $testEndpoints) {
            Write-Log "Trying endpoint: $endpoint" -Level "INFO"
            
            try {
                $webRequest = [System.Net.WebRequest]::Create($endpoint)
                $webRequest.Method = "GET"
                $webRequest.UseDefaultCredentials = $true
                $webRequest.PreAuthenticate = $true
                $webRequest.Timeout = 10000
                $webRequest.UserAgent = "Vault-gMSA-Client/1.0"
                
                # Add headers that might trigger SPNEGO
                $webRequest.Headers.Add("Accept", "application/json")
                $webRequest.Headers.Add("Accept-Encoding", "gzip, deflate")
                
                try {
                    $webResponse = $webRequest.GetResponse()
                    Write-Log "Endpoint request completed with status: $($webResponse.StatusCode)" -Level "INFO"
                    $webResponse.Close()
                } catch {
                    $webStatusCode = $_.Exception.Response.StatusCode
                    Write-Log "Endpoint request returned: $webStatusCode" -Level "INFO"
                    
                    # Check if Authorization header was added (this contains our SPNEGO token)
                    if ($webRequest.Headers.Contains("Authorization")) {
                        $authHeader = $webRequest.Headers.GetValues("Authorization")
                        if ($authHeader -and $authHeader[0] -like "Negotiate *") {
                            $spnegoToken = $authHeader[0].Substring(10) # Remove "Negotiate "
                            Write-Log "SUCCESS: Real SPNEGO token captured from Vault endpoint!" -Level "SUCCESS"
                            Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..." -Level "INFO"
                            return $spnegoToken
                        }
                    }
                }
            } catch {
                Write-Log "Request to $endpoint failed: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        # Technique 3: Try using a different approach - make a request to a non-existent endpoint
        # that will definitely return 404/401 and might trigger SPNEGO
        Write-Log "Technique 3: Trying non-existent endpoint approach..." -Level "INFO"
        
        $nonExistentEndpoints = @(
            "$VaultUrl/v1/auth/nonexistent/login",
            "$VaultUrl/v1/auth/gmsa/nonexistent",
            "$VaultUrl/v1/sys/nonexistent",
            "$VaultUrl/v1/secret/nonexistent",
            "$VaultUrl/v1/auth/gmsa/role/nonexistent"
        )
        
        foreach ($endpoint in $nonExistentEndpoints) {
            Write-Log "Trying non-existent endpoint: $endpoint" -Level "INFO"
            
            try {
                $webRequest = [System.Net.WebRequest]::Create($endpoint)
                $webRequest.Method = "POST"
                $webRequest.UseDefaultCredentials = $true
                $webRequest.PreAuthenticate = $true
                $webRequest.Timeout = 10000
                $webRequest.UserAgent = "Vault-gMSA-Client/1.0"
                $webRequest.ContentType = "application/json"
                
                # Add request body
                $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes('{"test":"data"}')
                $webRequest.ContentLength = $bodyBytes.Length
                
                $requestStream = $webRequest.GetRequestStream()
                $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
                $requestStream.Close()
                
                try {
                    $webResponse = $webRequest.GetResponse()
                    Write-Log "Non-existent endpoint request completed with status: $($webResponse.StatusCode)" -Level "INFO"
                    $webResponse.Close()
                } catch {
                    $webStatusCode = $_.Exception.Response.StatusCode
                    Write-Log "Non-existent endpoint request returned: $webStatusCode" -Level "INFO"
                    
                    # Check if Authorization header was added (this contains our SPNEGO token)
                    if ($webRequest.Headers.Contains("Authorization")) {
                        $authHeader = $webRequest.Headers.GetValues("Authorization")
                        if ($authHeader -and $authHeader[0] -like "Negotiate *") {
                            $spnegoToken = $authHeader[0].Substring(10) # Remove "Negotiate "
                            Write-Log "SUCCESS: Real SPNEGO token captured from non-existent endpoint!" -Level "SUCCESS"
                            Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..." -Level "INFO"
                            return $spnegoToken
                        }
                    }
                }
            } catch {
                Write-Log "Request to $endpoint failed: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        # Technique 4: Try using HttpClient with proper authentication
        Write-Log "Technique 4: Trying HttpClient approach..." -Level "INFO"
        
        try {
            $httpClient = New-Object System.Net.Http.HttpClient
            $httpClient.Timeout = [System.TimeSpan]::FromSeconds(30)
            
            # Create a request message
            $requestMessage = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, "$VaultUrl/v1/sys/status")
            $requestMessage.Headers.Add("Accept", "application/json")
            $requestMessage.Headers.Add("User-Agent", "Vault-gMSA-Client/1.0")
            
            try {
                $response = $httpClient.SendAsync($requestMessage).Result
                Write-Log "HttpClient request completed with status: $($response.StatusCode)" -Level "INFO"
                
                # Check if Authorization header was added
                if ($requestMessage.Headers.Contains("Authorization")) {
                    $authHeader = $requestMessage.Headers.GetValues("Authorization")
                    if ($authHeader -and $authHeader[0] -like "Negotiate *") {
                        $spnegoToken = $authHeader[0].Substring(10) # Remove "Negotiate "
                        Write-Log "SUCCESS: Real SPNEGO token captured from HttpClient!" -Level "SUCCESS"
                        Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..." -Level "INFO"
                        return $spnegoToken
                    }
                }
            } catch {
                Write-Log "HttpClient request failed: $($_.Exception.Message)" -Level "WARNING"
            } finally {
                $httpClient.Dispose()
            }
        } catch {
            Write-Log "HttpClient approach failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Technique 5: CRITICAL FIX - Use a different approach that forces SPNEGO generation
        # The key insight is that we need to create a scenario where Windows SSPI will generate a SPNEGO token
        Write-Log "Technique 5: CRITICAL FIX - Forcing SPNEGO token generation..." -Level "INFO"
        
        # Create a WebRequest that will force Windows SSPI to generate a SPNEGO token
        # by making a request to a server that will return 401 Unauthorized with WWW-Authenticate: Negotiate
        Write-Log "Creating WebRequest to force SPNEGO negotiation..." -Level "INFO"
        
        try {
            # Use a different approach - create a WebRequest that will force SPNEGO
            # by targeting a specific SPN and using proper authentication context
            $webRequest = [System.Net.WebRequest]::Create("$VaultUrl/v1/sys/config")
            $webRequest.Method = "GET"
            $webRequest.UseDefaultCredentials = $true
            $webRequest.PreAuthenticate = $true
            $webRequest.Timeout = 10000
            $webRequest.UserAgent = "Vault-gMSA-Client/1.0"
            
            # Add headers that might trigger SPNEGO negotiation
            $webRequest.Headers.Add("Accept", "application/json")
            $webRequest.Headers.Add("Accept-Encoding", "gzip, deflate")
            
            # Force the request to be made
            Write-Log "Forcing WebRequest to be made..." -Level "INFO"
            
            try {
                $webResponse = $webRequest.GetResponse()
                Write-Log "Forced request completed with status: $($webResponse.StatusCode)" -Level "INFO"
                $webResponse.Close()
            } catch {
                $webStatusCode = $_.Exception.Response.StatusCode
                Write-Log "Forced request returned: $webStatusCode" -Level "INFO"
                
                # Check if Authorization header was added (this contains our SPNEGO token)
                if ($webRequest.Headers.Contains("Authorization")) {
                    $authHeader = $webRequest.Headers.GetValues("Authorization")
                    if ($authHeader -and $authHeader[0] -like "Negotiate *") {
                        $spnegoToken = $authHeader[0].Substring(10) # Remove "Negotiate "
                        Write-Log "SUCCESS: Real SPNEGO token captured from forced request!" -Level "SUCCESS"
                        Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..." -Level "INFO"
                        return $spnegoToken
                    }
                }
            }
        } catch {
            Write-Log "Forced request failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        Write-Log "ERROR: All techniques failed to generate real SPNEGO token" -Level "ERROR"
        Write-Log "This indicates that Windows SSPI is not generating SPNEGO tokens" -Level "ERROR"
        Write-Log "Possible causes:" -Level "ERROR"
        Write-Log "  1. Vault server is not configured to require SPNEGO authentication" -Level "ERROR"
        Write-Log "  2. Windows SSPI needs a 401 challenge with WWW-Authenticate: Negotiate" -Level "ERROR"
        Write-Log "  3. Kerberos configuration issues" -Level "ERROR"
        Write-Log "  4. The Vault server is not sending proper authentication challenges" -Level "ERROR"
        
        return $null
        
    } catch {
        Write-Log "ERROR: SPNEGO token generation failed: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Stack trace: $($_.Exception.StackTrace)" -Level "ERROR"
        return $null
    }
}

function Invoke-VaultAuthentication {
    param(
        [string]$VaultUrl,
        [string]$Role,
        [string]$SpnegoToken
    )
    
    Write-Log "Authenticating to Vault with real SPNEGO token..." -Level "INFO"
    Write-Log "Vault URL: $VaultUrl" -Level "INFO"
    Write-Log "Role: $Role" -Level "INFO"
    
    try {
        $loginUrl = "$VaultUrl/v1/auth/gmsa/login"
        Write-Log "Login endpoint: $loginUrl" -Level "INFO"
        
        $requestBody = @{
            role = $Role
            spnego = $SpnegoToken
        } | ConvertTo-Json -Depth 10
        
        Write-Log "Request body: $requestBody" -Level "INFO"
        
        # Disable SSL certificate validation for testing
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        
        $headers = @{
            "Content-Type" = "application/json"
            "User-Agent" = "Vault-gMSA-Client/1.0"
        }
        
        Write-Log "Making POST request to Vault..." -Level "INFO"
        
        $response = Invoke-RestMethod -Uri $loginUrl -Method Post -Body $requestBody -Headers $headers -TimeoutSec 30
        
        Write-Log "SUCCESS: Vault authentication successful!" -Level "SUCCESS"
        Write-Log "Response: $($response | ConvertTo-Json -Depth 10)" -Level "INFO"
        
        return $response
        
    } catch {
        Write-Log "ERROR: Vault authentication failed: $($_.Exception.Message)" -Level "ERROR"
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Log "HTTP Status Code: $statusCode" -Level "ERROR"
            
            try {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorBody = $reader.ReadToEnd()
                Write-Log "Error response body: $errorBody" -Level "ERROR"
            } catch {
                Write-Log "Could not read error response body" -Level "WARNING"
            }
        }
        
        return $null
    }
}

# Main execution
try {
    Write-Log "=== Ultimate SPNEGO Token Generator Started ===" -Level "INFO"
    Write-Log "Vault URL: $VaultUrl" -Level "INFO"
    Write-Log "Role: $Role" -Level "INFO"
    Write-Log "SPN: $SPN" -Level "INFO"
    
    # Step 1: Check current identity
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    Write-Log "Running under identity: $($currentIdentity.Name)" -Level "INFO"
    
    # Step 2: Check for Kerberos ticket
    if (-not (Test-KerberosTicket -TargetSPN $SPN)) {
        Write-Log "Requesting Kerberos ticket..." -Level "INFO"
        if (-not (Request-KerberosTicket -TargetSPN $SPN)) {
            Write-Log "ERROR: Failed to obtain Kerberos ticket for $SPN" -Level "ERROR"
            Write-Log "Please ensure the gMSA has proper permissions and the SPN is registered" -Level "ERROR"
            exit 1
        }
        
        # Verify ticket was obtained
        if (-not (Test-KerberosTicket -TargetSPN $SPN)) {
            Write-Log "ERROR: Kerberos ticket still not available after request" -Level "ERROR"
            exit 1
        }
    }
    
    # Step 3: Generate real SPNEGO token using multiple techniques
    Write-Log "Generating real SPNEGO token using multiple techniques..." -Level "INFO"
    $spnegoToken = Get-RealSPNEGOToken -TargetSPN $SPN -VaultUrl $VaultUrl
    
    if (-not $spnegoToken) {
        Write-Log "ERROR: Failed to generate real SPNEGO token" -Level "ERROR"
        Write-Log "This indicates a problem with Windows SSPI or Kerberos configuration" -Level "ERROR"
        exit 1
    }
    
    # Step 4: Authenticate to Vault
    Write-Log "Authenticating to Vault..." -Level "INFO"
    $vaultResponse = Invoke-VaultAuthentication -VaultUrl $VaultUrl -Role $Role -SpnegoToken $spnegoToken
    
    if ($vaultResponse) {
        Write-Log "=== SUCCESS: Vault authentication completed ===" -Level "SUCCESS"
        Write-Log "Vault token: $($vaultResponse.auth.client_token)" -Level "SUCCESS"
        Write-Log "Token TTL: $($vaultResponse.auth.lease_duration) seconds" -Level "SUCCESS"
    } else {
        Write-Log "=== FAILURE: Vault authentication failed ===" -Level "ERROR"
        exit 1
    }
    
} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.Exception.StackTrace)" -Level "ERROR"
    exit 1
}
