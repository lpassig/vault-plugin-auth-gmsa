# Vault gMSA Client using HTTP Negotiate Protocol
# This script uses Windows HTTP stack for automatic SPNEGO generation

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$VaultRole = "default",  # Use "default" for HTTP Negotiate, or specify custom role
    [string[]]$SecretPaths = @("kv/data/my-app/database", "kv/data/my-app/api"),
    [string]$ConfigOutputDir = "C:\vault-client\config"
)

# =============================================================================
# Configuration and Logging Setup
# =============================================================================

# Bypass SSL certificate validation for testing (PowerShell 5.1 compatible)
if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
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
}
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls

# Create output directory
if (-not (Test-Path $ConfigOutputDir)) {
    New-Item -ItemType Directory -Path $ConfigOutputDir -Force | Out-Null
}

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "INFO" { Write-Host $logMessage -ForegroundColor Cyan }
        default { Write-Host $logMessage }
    }
    
    $logFile = "$ConfigOutputDir\vault-client.log"
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}

Write-Log "Script initialization completed successfully" -Level "INFO"
Write-Log "Script version: 4.1 (HTTP Negotiate Protocol - Enhanced SSL & Error Handling)" -Level "INFO"
Write-Log "Config directory: $ConfigOutputDir" -Level "INFO"
Write-Log "Vault URL: $VaultUrl" -Level "INFO"
Write-Log "Current user: $(whoami)" -Level "INFO"

# =============================================================================
# Vault Authentication using HTTP Negotiate
# =============================================================================

function Authenticate-ToVault {
    param(
        [string]$VaultUrl,
        [string]$Role = "default"
    )
    
    try {
        Write-Log "Starting Vault authentication using HTTP Negotiate protocol..." -Level "INFO"
        Write-Log "Vault URL: $VaultUrl" -Level "INFO"
        Write-Log "Role: $Role" -Level "INFO"
        
        # Method 1: Try Invoke-RestMethod with UseDefaultCredentials (with role in body)
        try {
            Write-Log "Method 1: Using Invoke-RestMethod with UseDefaultCredentials..." -Level "INFO"
            
            # Build request body with role
            $body = @{ role = $Role } | ConvertTo-Json
            
            $response = Invoke-RestMethod `
                -Uri "$VaultUrl/v1/auth/gmsa/login" `
                -Method Post `
                -Body $body `
                -ContentType "application/json" `
                -UseDefaultCredentials `
                -UseBasicParsing `
                -ErrorAction Stop
            
            if ($response.auth -and $response.auth.client_token) {
                Write-Log "SUCCESS: Vault authentication successful via HTTP Negotiate!" -Level "SUCCESS"
                Write-Log "Client token: $($response.auth.client_token)" -Level "INFO"
                Write-Log "Token TTL: $($response.auth.lease_duration) seconds" -Level "INFO"
                return $response.auth.client_token
            }
        } catch {
            Write-Log "Method 1 failed: $($_.Exception.Message)" -Level "WARNING"
            Write-Log "Method 1 error details: $($_.Exception.InnerException.Message)" -Level "WARNING"
        }
        
        # Method 2: Try WebRequest with UseDefaultCredentials (with role in body)
        try {
            Write-Log "Method 2: Using WebRequest with UseDefaultCredentials..." -Level "INFO"
            
            $request = [System.Net.HttpWebRequest]::Create("$VaultUrl/v1/auth/gmsa/login")
            $request.Method = "POST"
            $request.UseDefaultCredentials = $true
            $request.PreAuthenticate = $true
            $request.UserAgent = "Vault-gMSA-Client/4.0"
            $request.ContentType = "application/json"
            
            # Add role in request body
            $bodyJson = @{ role = $Role } | ConvertTo-Json
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
            $request.ContentLength = $bodyBytes.Length
            
            $requestStream = $request.GetRequestStream()
            $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
            $requestStream.Close()
            
            $response = $request.GetResponse()
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            $reader.Close()
            $response.Close()
            
            $authResponse = $responseBody | ConvertFrom-Json
            if ($authResponse.auth -and $authResponse.auth.client_token) {
                Write-Log "SUCCESS: Vault authentication successful via WebRequest!" -Level "SUCCESS"
                Write-Log "Client token: $($authResponse.auth.client_token)" -Level "INFO"
                return $authResponse.auth.client_token
            }
        } catch [System.Net.WebException] {
            # Enhanced error handling for web exceptions
            $errorResponse = $_.Exception.Response
            if ($errorResponse) {
                $reader = New-Object System.IO.StreamReader($errorResponse.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                $reader.Close()
                Write-Log "Method 2 failed with status: $($errorResponse.StatusCode)" -Level "WARNING"
                Write-Log "Method 2 error body: $errorBody" -Level "WARNING"
            } else {
                Write-Log "Method 2 failed: $($_.Exception.Message)" -Level "WARNING"
            }
        } catch {
            Write-Log "Method 2 failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 3: Try with explicit curl.exe if available (not PowerShell alias)
        try {
            Write-Log "Method 3: Trying with curl.exe for SPNEGO token generation..." -Level "INFO"
            
            # Use full path to curl.exe to avoid PowerShell alias
            $curlPath = "C:\Windows\System32\curl.exe"
            if (Test-Path $curlPath) {
                Write-Log "Using curl.exe to generate SPNEGO token..." -Level "INFO"
                
                # Run curl with --negotiate to generate SPNEGO token
                $curlOutput = & $curlPath --negotiate --user : -v "$VaultUrl/v1/sys/health" 2>&1 | Out-String
                
                if ($curlOutput -match "Authorization: Negotiate ([A-Za-z0-9+/=]+)") {
                    $spnegoToken = $matches[1]
                    Write-Log "SUCCESS: SPNEGO token generated via curl.exe!" -Level "SUCCESS"
                    Write-Log "Token length: $($spnegoToken.Length) characters" -Level "INFO"
                    
                    # Send token in body
                    $body = @{
                        role = $Role
                        spnego = $spnegoToken
                    } | ConvertTo-Json
                    
                    $response = Invoke-RestMethod `
                        -Uri "$VaultUrl/v1/auth/gmsa/login" `
                        -Method Post `
                        -Body $body `
                        -ContentType "application/json" `
                        -UseBasicParsing
                    
                    if ($response.auth -and $response.auth.client_token) {
                        Write-Log "SUCCESS: Vault authentication successful via curl.exe method!" -Level "SUCCESS"
                        Write-Log "Client token: $($response.auth.client_token)" -Level "INFO"
                        return $response.auth.client_token
                    }
                } else {
                    Write-Log "No SPNEGO token found in curl output" -Level "WARNING"
                }
            } else {
                Write-Log "curl.exe not found at $curlPath" -Level "WARNING"
            }
        } catch {
            Write-Log "Method 3 failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        Write-Log "ERROR: All authentication methods failed" -Level "ERROR"
        Write-Log "" -Level "ERROR"
        Write-Log "TROUBLESHOOTING DIAGNOSTICS:" -Level "ERROR"
        Write-Log "1. Current User: $(whoami)" -Level "ERROR"
        Write-Log "2. Vault URL: $VaultUrl" -Level "ERROR"
        Write-Log "3. Target Endpoint: $VaultUrl/v1/auth/gmsa/login" -Level "ERROR"
        Write-Log "4. SSL Certificate Policy: Bypassed (TrustAllCertsPolicy active)" -Level "ERROR"
        
        # Check Kerberos tickets
        try {
            $ticketsOutput = klist | Out-String
            if ($ticketsOutput -match "krbtgt") {
                Write-Log "5. Kerberos TGT: PRESENT" -Level "INFO"
            } else {
                Write-Log "5. Kerberos TGT: MISSING (Run 'kinit' or re-login)" -Level "ERROR"
            }
        } catch {
            Write-Log "5. Kerberos ticket check failed" -Level "ERROR"
        }
        
        Write-Log "" -Level "ERROR"
        Write-Log "COMMON CAUSES:" -Level "ERROR"
        Write-Log "- Vault server configuration issues (check if HTTP Negotiate is enabled)" -Level "ERROR"
        Write-Log "- Network connectivity (verify $VaultUrl is reachable)" -Level "ERROR"
        Write-Log "- gMSA account permissions (verify SPN registration)" -Level "ERROR"
        Write-Log "- Vault server logs may show more details" -Level "ERROR"
        
        return $null
        
    } catch {
        Write-Log "ERROR: Authentication process failed: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# =============================================================================
# Secret Retrieval
# =============================================================================

function Get-VaultSecret {
    param(
        [string]$VaultUrl,
        [string]$Token,
        [string]$SecretPath
    )
    
    try {
        Write-Log "Retrieving secret from path: $SecretPath" -Level "INFO"
        
        $headers = @{
            "X-Vault-Token" = $Token
        }
        
        $response = Invoke-RestMethod `
            -Uri "$VaultUrl/v1/$SecretPath" `
            -Method Get `
            -Headers $headers `
            -UseBasicParsing
        
        if ($response.data -and $response.data.data) {
            Write-Log "SUCCESS: Secret retrieved successfully" -Level "SUCCESS"
            return $response.data.data
        } else {
            Write-Log "ERROR: Secret response missing data field" -Level "ERROR"
            return $null
        }
        
    } catch {
        Write-Log "ERROR: Failed to retrieve secret from $SecretPath" -Level "ERROR"
        Write-Log "Error details: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# =============================================================================
# Main Application Logic
# =============================================================================

function Start-VaultClientApplication {
    try {
        Write-Log "Starting Vault Client Application..." -Level "INFO"
        Write-Log "Script version: 4.0 (HTTP Negotiate Protocol)" -Level "INFO"
        
        # Authenticate to Vault
        Write-Log "Step 1: Authenticating to Vault using HTTP Negotiate..." -Level "INFO"
        $vaultToken = Authenticate-ToVault -VaultUrl $VaultUrl -Role $VaultRole
        
        if (-not $vaultToken) {
            Write-Log "ERROR: Failed to authenticate to Vault" -Level "ERROR"
            Write-Log "Application cannot continue without valid authentication" -Level "ERROR"
            return $false
        }
        
        Write-Log "SUCCESS: Vault authentication completed" -Level "SUCCESS"
        
        # Retrieve secrets
        Write-Log "Step 2: Retrieving secrets..." -Level "INFO"
        $secrets = @{}
        
        foreach ($secretPath in $SecretPaths) {
            Write-Log "Retrieving secret from: $secretPath" -Level "INFO"
            $secret = Get-VaultSecret -VaultUrl $VaultUrl -Token $vaultToken -SecretPath $secretPath
            
            if ($secret) {
                $secrets[$secretPath] = $secret
                Write-Log "SUCCESS: Secret retrieved from $secretPath" -Level "SUCCESS"
            } else {
                Write-Log "WARNING: Failed to retrieve secret from $secretPath" -Level "WARNING"
            }
        }
        
        # Display retrieved secrets
        if ($secrets.Count -gt 0) {
            Write-Log "SUCCESS: Retrieved $($secrets.Count) secrets" -Level "SUCCESS"
            Write-Log "Secret summary:" -Level "INFO"
            
            foreach ($path in $secrets.Keys) {
                Write-Log "  - $path : $($secrets[$path].Keys -join ', ')" -Level "INFO"
            }
        } else {
            Write-Log "WARNING: No secrets were retrieved" -Level "WARNING"
        }
        
        Write-Log "Vault Client Application completed successfully" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-Log "ERROR: Application failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# =============================================================================
# Script Entry Point
# =============================================================================

try {
    Write-Host ""
    Write-Host "Vault gMSA Authentication Client (HTTP Negotiate Protocol)" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    
    # Start the application
    $success = Start-VaultClientApplication
    
    if ($success) {
        Write-Host ""
        Write-Host "Application completed successfully!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host ""
        Write-Host "Application failed!" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.Exception.StackTrace)" -ForegroundColor Red
    exit 1
}
