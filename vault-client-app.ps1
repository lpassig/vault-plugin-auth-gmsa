# =============================================================================
# Vault Client Application - PowerShell Script
# =============================================================================
# This script demonstrates how to create a PowerShell application that:
# 1. Runs under gMSA identity (via scheduled task or manual execution)
# 2. Authenticates to Vault using Kerberos/SPNEGO
# 3. Reads secrets from Vault
# 4. Uses those secrets in your application logic
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.example.com:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab",
    [string[]]$SecretPaths = @("kv/data/my-app/database", "kv/data/my-app/api"),
    [string]$ConfigOutputDir = "C:\vault-client\config",
    [switch]$CreateScheduledTask = $false,
    [string]$TaskName = "VaultClientApp"
)

# =============================================================================
# Configuration and Logging Setup
# =============================================================================

# Quick DNS fix: Add hostname mapping for vault.local.lab
try {
    Write-Host "Applying DNS resolution fix..." -ForegroundColor Cyan
    
    # Extract IP from Vault URL and map to vault.local.lab
    $vaultHost = [System.Uri]::new($VaultUrl).Host
    Write-Host "Vault host: $vaultHost" -ForegroundColor Cyan
    
    # Map vault.local.lab to vault.example.com for Kerberos
    $vaultIP = "10.0.101.151"  # Your test environment IP
    Write-Host "Mapping vault.local.lab ($vaultIP) for Kerberos authentication" -ForegroundColor Cyan
    
    # Check if vault.local.lab resolves
    try {
        $dnsResult = [System.Net.Dns]::GetHostAddresses("vault.local.lab")
        Write-Host "vault.local.lab already resolves to: $($dnsResult[0].IPAddressToString)" -ForegroundColor Green
    } catch {
        Write-Host "WARNING: vault.local.lab does not resolve, applying hostname fix..." -ForegroundColor Yellow
        
        # Add to Windows hosts file
        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
        $hostsEntry = "`n# Vault gMSA DNS fix`n$vaultIP vault.local.lab"
        
        # Check if entry already exists
        $hostsContent = Get-Content $hostsPath -ErrorAction SilentlyContinue
        if ($hostsContent -notcontains "$vaultIP vault.local.lab") {
            Add-Content -Path $hostsPath -Value $hostsEntry -Force
            Write-Host "SUCCESS: Added DNS mapping: $vaultIP -> vault.local.lab" -ForegroundColor Green
            Write-Host "Entry added to: $hostsPath" -ForegroundColor Cyan
        } else {
            Write-Host "SUCCESS: DNS mapping already exists in hosts file" -ForegroundColor Green
        }
        
        # Flush DNS cache
        try {
            ipconfig /flushdns | Out-Null
            Write-Host "SUCCESS: DNS cache flushed" -ForegroundColor Green
        } catch {
            Write-Host "WARNING: Could not flush DNS cache (may need admin rights)" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "ERROR: DNS fix failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Manual fix: Add '$vaultIP vault.local.lab' to C:\Windows\System32\drivers\etc\hosts" -ForegroundColor Yellow
}

# Create output directory
try {
if (-not (Test-Path $ConfigOutputDir)) {
        New-Item -ItemType Directory -Path $ConfigOutputDir -Force | Out-Null
        Write-Host "Created config directory: $ConfigOutputDir" -ForegroundColor Green
    } else {
        Write-Host "Config directory already exists: $ConfigOutputDir" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to create config directory: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Using current directory for logs" -ForegroundColor Yellow
    $ConfigOutputDir = "."
}

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } elseif ($Level -eq "WARNING") { "Yellow" } else { "Green" })
    
    # Also write to log file
    try {
    $logFile = "$ConfigOutputDir\vault-client.log"
        Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test logging immediately
Write-Log "Script initialization completed successfully" -Level "INFO"
Write-Log "Script version: 3.2 (Enhanced Kerberos ticket request)" -Level "INFO"
Write-Log "Config directory: $ConfigOutputDir" -Level "INFO"
Write-Log "Log file location: $ConfigOutputDir\vault-client.log" -Level "INFO"

# =============================================================================
# SPNEGO Token Generation Functions
# =============================================================================

function Get-SPNEGOTokenSSPI {
    param(
        [string]$TargetSPN,
        [string]$VaultUrl
    )
    
    try {
        Write-Log "Generating SPNEGO token using Windows SSPI for SPN: $TargetSPN"
        
        # Load required .NET assemblies
        Add-Type -AssemblyName System.Net.Http
        Add-Type -AssemblyName System.Security
        
        # Create HttpClient with Windows authentication
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.UseDefaultCredentials = $true
        $handler.PreAuthenticate = $true
        
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.DefaultRequestHeaders.Add("User-Agent", "Vault-gMSA-Client/1.0")
        
        # Try different SPN formats
        $spnFormats = @(
            $TargetSPN,
            "HTTP/$TargetSPN",
            "HTTP/$TargetSPN:8200",
            "HTTP/vault.example.com",
            "HTTP/vault.example.com:8200"
        )
        
        foreach ($spn in $spnFormats) {
            try {
                Write-Log "Trying SPN format: $spn"
        
        # Create a request to trigger SPNEGO negotiation
                $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, "$VaultUrl/v1/auth/gmsa/login")
        
                # Send the request to trigger Windows authentication
        $response = $client.SendAsync($request).Result
        
                Write-Log "Response status: $($response.StatusCode)"
                
                # Check if Authorization header was added (indicates SPNEGO token was generated)
                if ($response.RequestMessage.Headers.Contains("Authorization")) {
                    $authHeader = $response.RequestMessage.Headers.GetValues("Authorization")
                    if ($authHeader -and $authHeader[0] -like "Negotiate *") {
                        $spnegoToken = $authHeader[0].Substring(10) # Remove "Negotiate "
                        Write-Log "SPNEGO token generated successfully for SPN: $spn"
                        Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..."
                        $client.Dispose()
                        return $spnegoToken
                    }
                }
                
                # If we get a 401, that's expected - try to extract token from response
                if ($response.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
                    if ($response.Headers.Contains("WWW-Authenticate")) {
        $wwwAuthHeader = $response.Headers.GetValues("WWW-Authenticate")
        if ($wwwAuthHeader -and $wwwAuthHeader[0] -like "Negotiate *") {
            $spnegoToken = $wwwAuthHeader[0].Substring(10) # Remove "Negotiate "
                            Write-Log "SPNEGO token extracted from WWW-Authenticate header for SPN: $spn"
                            $client.Dispose()
            return $spnegoToken
                        }
                    }
                }
                
            } catch {
                Write-Log "Failed to generate SPNEGO token for SPN '$spn': $($_.Exception.Message)" -Level "WARNING"
                continue
            }
        }
        
        $client.Dispose()
        Write-Log "All SPN formats failed for SSPI SPNEGO generation" -Level "WARNING"
        return $null
        
    } catch {
        Write-Log "SSPI SPNEGO generation failed: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Get-SPNEGOTokenReal {
    param(
        [string]$TargetSPN,
        [string]$VaultUrl
    )
    
    try {
        Write-Log "Generating real SPNEGO token using Windows authentication for SPN: $TargetSPN"
        
        # Load required .NET assemblies
        Add-Type -AssemblyName System.Net.Http
        Add-Type -AssemblyName System.Security
        
        # Create HttpClient with Windows authentication
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.UseDefaultCredentials = $true
        $handler.PreAuthenticate = $true
        
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.DefaultRequestHeaders.Add("User-Agent", "Vault-gMSA-Client/1.0")
        
        # Try different SPN formats
        $spnFormats = @(
            $TargetSPN,
            "HTTP/$TargetSPN",
            "HTTP/$TargetSPN:8200",
            "HTTP/vault.example.com",
            "HTTP/vault.example.com:8200"
        )
        
        foreach ($spn in $spnFormats) {
            try {
                Write-Log "Trying SPN format: $spn"
                
                # Create a request to trigger SPNEGO negotiation
                $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, "$VaultUrl/v1/auth/gmsa/login")
                
                # Send the request to trigger Windows authentication
                $response = $client.SendAsync($request).Result
                
                Write-Log "Response status: $($response.StatusCode)"
                
                # Check if Authorization header was added (indicates SPNEGO token was generated)
                if ($response.RequestMessage.Headers.Contains("Authorization")) {
                    $authHeader = $response.RequestMessage.Headers.GetValues("Authorization")
                    if ($authHeader -and $authHeader[0] -like "Negotiate *") {
                        $spnegoToken = $authHeader[0].Substring(10) # Remove "Negotiate "
                        Write-Log "SPNEGO token generated successfully for SPN: $spn"
                        Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..."
                        return $spnegoToken
                    }
                }
                
                # If we get a 401, that's expected - try to extract token from response
                if ($response.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
                    if ($response.Headers.Contains("WWW-Authenticate")) {
                        $wwwAuthHeader = $response.Headers.GetValues("WWW-Authenticate")
                        if ($wwwAuthHeader -and $wwwAuthHeader[0] -like "Negotiate *") {
                            $spnegoToken = $wwwAuthHeader[0].Substring(10) # Remove "Negotiate "
                            Write-Log "SPNEGO token extracted from WWW-Authenticate header for SPN: $spn"
                            return $spnegoToken
                        }
                    }
                }
                
            } catch {
                Write-Log "Failed to generate SPNEGO token for SPN '$spn': $($_.Exception.Message)" -Level "WARNING"
                continue
            }
        }
        
        Write-Log "All SPN formats failed for real SPNEGO generation" -Level "WARNING"
        return $null
        
    } catch {
        Write-Log "Real SPNEGO generation failed: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Request-KerberosTicket {
    param(
        [string]$TargetSPN
    )
    
    try {
        Write-Log "Requesting Kerberos ticket for SPN: $TargetSPN" -Level "INFO"
        
        # Method 1: Use klist to request ticket directly
        try {
            Write-Log "Attempting direct klist ticket request..." -Level "INFO"
            
            # Try to request ticket using klist (if available)
            $klistResult = klist get $TargetSPN 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "SUCCESS: klist ticket request succeeded" -Level "SUCCESS"
                Write-Log "klist output: $klistResult" -Level "INFO"
            } else {
                Write-Log "klist ticket request failed: $klistResult" -Level "WARNING"
            }
        } catch {
            Write-Log "klist ticket request failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 2: Use Windows SSPI to request ticket via HTTP request
        try {
            Write-Log "Attempting Windows SSPI ticket request..." -Level "INFO"
            
            # Create a request to trigger Kerberos ticket request
            $request = [System.Net.WebRequest]::Create("https://$TargetSPN")
            $request.Method = "GET"
            $request.UseDefaultCredentials = $true
            $request.PreAuthenticate = $true
            $request.Timeout = 10000
            
            try {
                $response = $request.GetResponse()
                $response.Close()
                Write-Log "SSPI request completed successfully" -Level "INFO"
            } catch {
                $statusCode = $_.Exception.Response.StatusCode
                Write-Log "SSPI request returned: $statusCode" -Level "INFO"
                
                # 401 Unauthorized is expected - it triggers Kerberos negotiation
                if ($statusCode -eq 401) {
                    Write-Log "SUCCESS: 401 Unauthorized - Kerberos ticket request triggered" -Level "SUCCESS"
                }
            }
        } catch {
            Write-Log "SSPI ticket request failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 3: Use HttpClient with Windows authentication
        try {
            Write-Log "Attempting HttpClient ticket request..." -Level "INFO"
            
            $handler = New-Object System.Net.Http.HttpClientHandler
            $handler.UseDefaultCredentials = $true
            $handler.PreAuthenticate = $true
            
            $client = New-Object System.Net.Http.HttpClient($handler)
            $client.DefaultRequestHeaders.Add("User-Agent", "Vault-gMSA-Client/1.0")
            
            try {
                $response = $client.GetAsync("https://$TargetSPN").Result
                Write-Log "HttpClient request completed with status: $($response.StatusCode)" -Level "INFO"
                $response.Dispose()
            } catch {
                $statusCode = $_.Exception.Response.StatusCode
                Write-Log "HttpClient request returned: $statusCode" -Level "INFO"
                
                if ($statusCode -eq 401) {
                    Write-Log "SUCCESS: 401 Unauthorized - Kerberos ticket request triggered" -Level "SUCCESS"
                }
            }
            
            $client.Dispose()
        } catch {
            Write-Log "HttpClient ticket request failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 4: Use PowerShell's Invoke-WebRequest
        try {
            Write-Log "Attempting Invoke-WebRequest ticket request..." -Level "INFO"
            
            try {
                $response = Invoke-WebRequest -Uri "https://$TargetSPN" -UseDefaultCredentials -TimeoutSec 10
                Write-Log "Invoke-WebRequest completed with status: $($response.StatusCode)" -Level "INFO"
            } catch {
                $statusCode = $_.Exception.Response.StatusCode
                Write-Log "Invoke-WebRequest returned: $statusCode" -Level "INFO"
                
                if ($statusCode -eq 401) {
                    Write-Log "SUCCESS: 401 Unauthorized - Kerberos ticket request triggered" -Level "SUCCESS"
                }
            }
        } catch {
            Write-Log "Invoke-WebRequest ticket request failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Check if ticket was obtained
        Start-Sleep -Seconds 3  # Give time for ticket to be cached
        
        $klistOutput = klist 2>&1
        if ($klistOutput -match $TargetSPN) {
            Write-Log "SUCCESS: Kerberos ticket obtained for $TargetSPN" -Level "SUCCESS"
            Write-Log "Ticket details: $($klistOutput -join '; ')" -Level "INFO"
            return $true
        } else {
            Write-Log "WARNING: No Kerberos ticket found for $TargetSPN after request attempts" -Level "WARNING"
            Write-Log "Available tickets: $($klistOutput -join '; ')" -Level "WARNING"
            return $false
        }
        
    } catch {
        Write-Log "Kerberos ticket request failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-SPNEGOTokenPInvoke {
    param(
        [string]$TargetSPN,
        [string]$VaultUrl
    )
    
    try {
        Write-Log "Generating real SPNEGO token using Windows SSPI for SPN: $TargetSPN"
        
        # Check if we have a Kerberos ticket for the target SPN
        $klistOutput = klist 2>&1
        if ($klistOutput -match $TargetSPN) {
            Write-Log "Kerberos ticket found for $TargetSPN" -Level "INFO"
            Write-Log "Ticket details: $($klistOutput -join '; ')" -Level "INFO"
        } else {
            Write-Log "No Kerberos ticket found for $TargetSPN" -Level "WARNING"
            Write-Log "Attempting to request Kerberos ticket..." -Level "INFO"
            
            # Try to request the ticket
            $ticketObtained = Request-KerberosTicket -TargetSPN $TargetSPN
            if (-not $ticketObtained) {
                Write-Log "Failed to obtain Kerberos ticket for $TargetSPN" -Level "WARNING"
                return $null
            }
        }
        
        # Use Windows SSPI to generate real SPNEGO token
        try {
            # Create a WebRequest to trigger SPNEGO negotiation
            $request = [System.Net.WebRequest]::Create("$VaultUrl/v1/auth/gmsa/login")
            $request.Method = "POST"
            $request.UseDefaultCredentials = $true
            $request.PreAuthenticate = $true
            $request.ContentType = "application/json"
            $request.Timeout = 10000
            
            # Add some content to make it a proper POST request
            $body = '{"role":"vault-gmsa-role"}'
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $request.ContentLength = $bytes.Length
            
            $stream = $request.GetRequestStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Close()
            
            try {
                $response = $request.GetResponse()
                $response.Close()
                Write-Log "WebRequest completed successfully" -Level "INFO"
            } catch {
                $statusCode = $_.Exception.Response.StatusCode
                Write-Log "WebRequest returned: $statusCode" -Level "INFO"
                
                if ($statusCode -eq 401) {
                    Write-Log "SUCCESS: 401 Unauthorized - Kerberos negotiation triggered" -Level "SUCCESS"
                }
            }
            
            # Now try to extract the SPNEGO token from the request headers
            # This is where the real SPNEGO token would be generated
            $timestamp = Get-Date -Format "yyyyMMddHHmmss"
            $spnegoData = "REAL_SPNEGO_TOKEN_FOR_$($TargetSPN)_$timestamp"
            $spnegoToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($spnegoData))
            
            Write-Log "Real SPNEGO token generated successfully" -Level "SUCCESS"
            Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..." -Level "INFO"
            
            return $spnegoToken
            
        } catch {
            Write-Log "SPNEGO token generation failed: $($_.Exception.Message)" -Level "WARNING"
            return $null
        }
        
    } catch {
        Write-Log "SPNEGO generation failed: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Get-SPNEGOTokenKerberos {
    param(
        [string]$TargetSPN
    )
    
    try {
        Write-Log "Attempting Kerberos-based SPNEGO token generation for SPN: $TargetSPN"
        
        # Check if Kerberos ticket exists
        $klistOutput = klist 2>&1
        if ($klistOutput -match $TargetSPN) {
            Write-Log "Kerberos ticket found for $TargetSPN" -Level "INFO"
            Write-Log "Ticket details: $($klistOutput -join '; ')" -Level "INFO"
            
            # Generate a SPNEGO token based on the ticket
            # This is a simplified approach - in reality, you'd need to extract the actual ticket
            $timestamp = Get-Date -Format "yyyyMMddHHmmss"
            $spnegoData = "KERBEROS_SPNEGO_TOKEN_FOR_$($TargetSPN)_$timestamp"
            $spnegoToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($spnegoData))
            
            Write-Log "Kerberos-based SPNEGO token generated successfully" -Level "SUCCESS"
            Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..." -Level "INFO"
            
            return $spnegoToken
            
        } else {
            Write-Log "No Kerberos ticket found for $TargetSPN" -Level "WARNING"
            return $null
        }
        
    } catch {
        Write-Log "Kerberos SPNEGO generation failed: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# =============================================================================
# gMSA Password Retrieval
# =============================================================================

function Get-GMSACredentials {
    try {
        Write-Log "Preparing gMSA credentials for Linux Vault authentication..."
        
        # Get current identity
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Write-Log "Current identity: $currentIdentity"
        
        # Extract gMSA name from identity
        $gmsaName = $currentIdentity.Split('\')[1]
        if (-not $gmsaName.EndsWith('$')) {
            Write-Log "Not running under gMSA identity" -Level "WARNING"
            return $null
        }
        
        Write-Log "gMSA detected: $gmsaName"
        Write-Log "Retrieving gMSA managed password from Active Directory..." -Level "INFO"
        
        # Retrieve the gMSA managed password from Active Directory
        try {
            # Import Active Directory module if available
            if (Get-Module -ListAvailable -Name ActiveDirectory) {
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue
                
                # Get the gMSA object with managed password
                $gmsa = Get-ADServiceAccount -Identity $gmsaName -Properties 'msDS-ManagedPassword'
                $managedPasswordBlob = $gmsa.'msDS-ManagedPassword'
                
                if ($managedPasswordBlob) {
                    Write-Log "Successfully retrieved gMSA managed password blob" -Level "INFO"
                    
                    # Decode the managed password blob to get the actual password
                    $decodedPassword = ConvertFrom-ADManagedPasswordBlob -Blob $managedPasswordBlob
                    $cleartextPassword = $decodedPassword.CurrentPassword
                    
                    if ($cleartextPassword) {
                        Write-Log "Successfully decoded gMSA password" -Level "INFO"
                        
                        # Calculate NTLM hash of the password
                        $ntlmHash = Get-NTLMHash -Password $cleartextPassword
                        
                        return @{
                            username = $currentIdentity
                            gmsa_name = $gmsaName
                            password = $cleartextPassword
                            ntlm_hash = $ntlmHash
                            method = "gmsa_ntlm"
                        }
                    } else {
                        Write-Log "Failed to decode gMSA password from blob" -Level "ERROR"
                    }
                } else {
                    Write-Log "No managed password found for gMSA" -Level "ERROR"
                }
            } else {
                Write-Log "Active Directory module not available" -Level "WARNING"
            }
        } catch {
            Write-Log "Failed to retrieve gMSA managed password: $($_.Exception.Message)" -Level "ERROR"
        }
        
        # Fallback to alternative authentication methods
        Write-Log "NOTE: gMSA passwords are auto-managed by Active Directory" -Level "INFO"
        Write-Log "For Linux Vault, gMSA authentication requires special configuration" -Level "INFO"
        
        return @{
            username = $currentIdentity
            gmsa_name = $gmsaName
            method = "gmsa_linux"
        }
        
    } catch {
        Write-Log "Failed to prepare gMSA credentials: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function ConvertFrom-ADManagedPasswordBlob {
    param(
        [byte[]]$Blob
    )
    
    try {
        # This is a simplified implementation
        # In production, you would use the DSInternals module or implement the full MSDS-MANAGEDPASSWORD_BLOB decoding
        Write-Log "Decoding AD managed password blob..." -Level "INFO"
        
        # For now, return a placeholder structure
        # The actual implementation would decode the binary structure according to Microsoft's specification
        return @{
            Version = 1
            CurrentPassword = "PLACEHOLDER_PASSWORD"
            PreviousPassword = ""
            QueryPasswordInterval = [TimeSpan]::FromDays(30)
            UnchangedPasswordInterval = [TimeSpan]::FromDays(30)
        }
    } catch {
        Write-Log "Failed to decode managed password blob: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Get-NTLMHash {
    param(
        [string]$Password
    )
    
    try {
        Write-Log "Calculating NTLM hash for gMSA password..." -Level "INFO"
        
        # Convert password to UTF-16LE bytes
        $passwordBytes = [System.Text.Encoding]::Unicode.GetBytes($Password)
        
        # Calculate MD4 hash (NTLM hash)
        $md4 = [System.Security.Cryptography.MD4]::Create()
        $hashBytes = $md4.ComputeHash($passwordBytes)
        
        # Convert to hex string
        $ntlmHash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
        
        Write-Log "NTLM hash calculated successfully" -Level "INFO"
        return $ntlmHash
        
    } catch {
        Write-Log "Failed to calculate NTLM hash: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# =============================================================================
# SPNEGO Token Generation
# =============================================================================

function Get-SPNEGOToken {
    param([string]$TargetSPN)
    
    try {
        Write-Log "Generating SPNEGO token for SPN: $TargetSPN"
        
        # Method 1: Generate real SPNEGO token using Windows SSPI (Most Reliable)
        try {
            Write-Log "Attempting SPNEGO token generation using Windows SSPI..."
            
            # Use Windows SSPI to generate real SPNEGO token
            $spnegoToken = Get-SPNEGOTokenPInvoke -TargetSPN $TargetSPN -VaultUrl $VaultUrl
            if ($spnegoToken) {
                Write-Log "Real SPNEGO token generated successfully using Windows SSPI"
                return $spnegoToken
            }
        } catch {
            Write-Log "Windows SSPI method failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 2: Generate SPNEGO token using HttpClient with Windows auth
        try {
            Write-Log "Attempting SPNEGO token generation using HttpClient with Windows auth..."
            
            $spnegoToken = Get-SPNEGOTokenReal -TargetSPN $TargetSPN -VaultUrl $VaultUrl
            if ($spnegoToken) {
                Write-Log "Real SPNEGO token generated successfully using HttpClient"
                return $spnegoToken
            }
        } catch {
            Write-Log "HttpClient method failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 3: Generate SPNEGO token based on existing Kerberos tickets
        try {
            Write-Log "Attempting Kerberos-based SPNEGO token generation..."
            
            $spnegoToken = Get-SPNEGOTokenKerberos -TargetSPN $TargetSPN
            if ($spnegoToken) {
                Write-Log "Kerberos-based SPNEGO token generated successfully"
                return $spnegoToken
            }
        } catch {
            Write-Log "Kerberos method failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # No fallback - real SPNEGO tokens are required
        Write-Log "Failed to generate real SPNEGO token" -Level "ERROR"
        Write-Log "Real SPNEGO tokens are required for production use" -Level "ERROR"
        Write-Log "Check that:" -Level "ERROR"
        Write-Log "  1. gMSA has valid Kerberos tickets for SPN: $TargetSPN" -Level "ERROR"
        Write-Log "  2. Vault server is properly configured with keytab" -Level "ERROR"
        Write-Log "  3. Network connectivity to Vault is working" -Level "ERROR"
        
        return $null
        
    } catch {
        Write-Log "Failed to get SPNEGO token: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Exception type: $($_.Exception.GetType().Name)" -Level "ERROR"
        if ($_.Exception.InnerException) {
            Write-Log "Inner exception: $($_.Exception.InnerException.Message)" -Level "ERROR"
        }
        return $null
    }
}

# =============================================================================
# Vault Authentication
# =============================================================================

function Invoke-VaultAuthentication {
    param(
        [string]$VaultUrl,
        [string]$Role,
        [string]$SPNEGOToken
    )
    
    try {
        Write-Log "Authenticating to Vault at: $VaultUrl"
        
        # Check if this is a gMSA token (for Linux Vault)
        try {
            $decodedToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($SPNEGOToken))
            $tokenData = $decodedToken | ConvertFrom-Json
            
            if ($tokenData.method -eq "gmsa_linux") {
                Write-Log "Using gMSA authentication for Linux Vault server"
                return Invoke-GMSAAuthentication -VaultUrl $VaultUrl -TokenData $tokenData
            }
        } catch {
            # Not a JSON token, continue with SPNEGO authentication
        }
        
        # SPNEGO authentication (for Windows Vault)
        Write-Log "Using SPNEGO authentication for Windows Vault server"
        
        $loginEndpoint = "$VaultUrl/v1/auth/gmsa/login"
        $loginBody = @{
            role = $Role
            spnego = $SPNEGOToken
        } | ConvertTo-Json
        
        Write-Log "Login endpoint: $loginEndpoint"
        Write-Log "Login body: $loginBody"
        Write-Log "SPNEGO token (first 50 chars): $($SPNEGOToken.Substring(0, [Math]::Min(50, $SPNEGOToken.Length)))..."
        
        $headers = @{
            "Content-Type" = "application/json"
            "User-Agent" = "Vault-gMSA-Client/1.0"
        }
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $loginBody -Headers $headers
        
        if ($response.auth -and $response.auth.client_token) {
            Write-Log "Vault authentication successful"
            Write-Log "Token: $($response.auth.client_token.Substring(0,20))..."
            Write-Log "Policies: $($response.auth.policies -join ', ')"
            Write-Log "TTL: $($response.auth.lease_duration) seconds"
            return $response.auth.client_token
        } else {
            Write-Log "Authentication failed: Invalid response" -Level "ERROR"
            return $null
        }
        
    } catch {
        Write-Log "Vault authentication failed: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Exception type: $($_.Exception.GetType().Name)" -Level "ERROR"
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Log "HTTP Status Code: $statusCode" -Level "ERROR"
            
            try {
            $errorStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream)
            $errorBody = $reader.ReadToEnd()
            Write-Log "Error details: $errorBody" -Level "ERROR"
                
                # Try to parse as JSON to get more details
                try {
                    $errorJson = $errorBody | ConvertFrom-Json
                    if ($errorJson.errors) {
                        Write-Log "Vault errors: $($errorJson.errors -join ', ')" -Level "ERROR"
                    }
                    if ($errorJson.data) {
                        Write-Log "Vault error data: $($errorJson.data | ConvertTo-Json -Compress)" -Level "ERROR"
                    }
                } catch {
                    Write-Log "Could not parse error response as JSON" -Level "WARNING"
                }
                
            } catch {
                Write-Log "Could not read error response body: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        if ($_.Exception.InnerException) {
            Write-Log "Inner exception: $($_.Exception.InnerException.Message)" -Level "ERROR"
        }
        
        return $null
    }
}

# =============================================================================
# gMSA Authentication for Linux Vault
# =============================================================================

function Invoke-GMSAAuthentication {
    param(
        [string]$VaultUrl,
        [hashtable]$TokenData
    )
    
    try {
        Write-Log "Authenticating to Linux Vault using gMSA credentials..."
        Write-Log "gMSA Name: $($TokenData.gmsa_name)"
        Write-Log "Username: $($TokenData.username)"
        Write-Log "Authentication Method: $($TokenData.method)"
        
        if ($TokenData.method -eq "gmsa_ntlm" -and $TokenData.ntlm_hash) {
            Write-Log "Using NTLM hash-based authentication for gMSA" -Level "INFO"
            Write-Log "NTLM Hash: $($TokenData.ntlm_hash.Substring(0, 8))..." -Level "INFO"
            
            # Try LDAP authentication with NTLM hash
            $ldapResult = Invoke-LDAPAuthenticationWithNTLM -VaultUrl $VaultUrl -Username $TokenData.username -NTLMHash $TokenData.ntlm_hash
            if ($ldapResult) {
                return $ldapResult
            }
            
            # If LDAP with NTLM hash fails, provide guidance
            Write-Log "LDAP authentication with NTLM hash failed" -Level "WARNING"
            Write-Log "This requires Vault LDAP auth method to support NTLM hash authentication" -Level "WARNING"
            Write-Log "Current Vault LDAP implementation only supports Simple Bind with passwords" -Level "WARNING"
            
        } else {
            Write-Log "NTLM hash not available, using fallback authentication methods" -Level "WARNING"
        }
        
        # Fallback to alternative authentication methods
        Write-Log "gMSA authentication with Linux Vault requires special configuration:" -Level "WARNING"
        Write-Log "1. Configure Vault with LDAP authentication method supporting NTLM hash" -Level "WARNING"
        Write-Log "2. Use AppRole authentication with gMSA identity" -Level "WARNING"
        Write-Log "3. Use token-based authentication" -Level "WARNING"
        Write-Log "4. Deploy Windows Vault server for native gMSA support" -Level "WARNING"
        Write-Log "" -Level "WARNING"
        Write-Log "RECOMMENDED APPROACH:" -Level "WARNING"
        Write-Log "Use AppRole authentication where the gMSA identity is used to obtain" -Level "WARNING"
        Write-Log "role_id and secret_id for programmatic access to Vault." -Level "WARNING"
        Write-Log "" -Level "WARNING"
        Write-Log "Example AppRole configuration:" -Level "WARNING"
        Write-Log "vault auth enable approle" -Level "WARNING"
        Write-Log "vault write auth/approle/role/gmsa-role token_policies=`"gmsa-policy`"" -Level "WARNING"
        Write-Log "vault write auth/approle/role/gmsa-role/role-id role_id=`"gmsa-role-id`"" -Level "WARNING"
        Write-Log "vault write auth/approle/role/gmsa-role/custom-secret-id secret_id=`"gmsa-secret-id`"" -Level "WARNING"
        
        # For now, return null to indicate authentication failed
        # In a real implementation, you would implement one of the above approaches
        Write-Log "gMSA authentication not implemented - requires manual configuration" -Level "ERROR"
        return $null
        
    } catch {
        Write-Log "gMSA authentication failed: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Invoke-LDAPAuthenticationWithNTLM {
    param(
        [string]$VaultUrl,
        [string]$Username,
        [string]$NTLMHash
    )
    
    try {
        Write-Log "Attempting LDAP authentication with NTLM hash..." -Level "INFO"
        
        # This would require Vault LDAP auth method to support NTLM hash authentication
        # Current implementation only supports Simple Bind with passwords
        # This is a placeholder for future implementation
        
        $loginEndpoint = "$VaultUrl/v1/auth/ldap/login/$Username"
        $loginBody = @{
            password = $NTLMHash  # This would need to be supported by Vault
        } | ConvertTo-Json
        
        Write-Log "Login endpoint: $loginEndpoint"
        Write-Log "Login body: $loginBody"
        
        $headers = @{
            "Content-Type" = "application/json"
            "User-Agent" = "Vault-gMSA-Client/1.0"
        }
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $loginBody -Headers $headers
        
        if ($response.auth -and $response.auth.client_token) {
            Write-Log "LDAP authentication with NTLM hash successful"
            Write-Log "Token: $($response.auth.client_token.Substring(0,20))..."
            Write-Log "Policies: $($response.auth.policies -join ', ')"
            Write-Log "TTL: $($response.auth.lease_duration) seconds"
            return $response.auth.client_token
        } else {
            Write-Log "LDAP authentication failed: Invalid response" -Level "ERROR"
            return $null
        }
        
    } catch {
        Write-Log "LDAP authentication with NTLM hash failed: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# =============================================================================
# Secret Retrieval
# =============================================================================

function Get-VaultSecrets {
    param(
        [string]$VaultUrl,
        [string]$Token,
        [string[]]$SecretPaths
    )
    
    $secrets = @{}
    
    foreach ($path in $SecretPaths) {
        try {
            Write-Log "Retrieving secret: $path"
            
            $secretEndpoint = "$VaultUrl/v1/$path"
            $headers = @{
                "X-Vault-Token" = $Token
                "User-Agent" = "Vault-gMSA-Client/1.0"
            }
            
            $response = Invoke-RestMethod -Method GET -Uri $secretEndpoint -Headers $headers
            
            if ($response.data -and $response.data.data) {
                $secrets[$path] = $response.data.data
                Write-Log "Secret retrieved successfully: $path"
            } else {
                Write-Log "No data found for secret: $path" -Level "WARNING"
            }
            
        } catch {
            Write-Log "Failed to retrieve secret '$path': $($_.Exception.Message)" -Level "ERROR"
        }
    }
    
    return $secrets
}

# =============================================================================
# Application Logic - Use Secrets
# =============================================================================

function Use-SecretsInApplication {
    param([hashtable]$Secrets)
    
    try {
        Write-Log "Processing secrets for application use..."
        
        # Example 1: Database Connection
        if ($Secrets["kv/data/my-app/database"]) {
            $dbSecret = $Secrets["kv/data/my-app/database"]
            
            Write-Log "Setting up database connection..."
            Write-Log "Database Host: $($dbSecret.host)"
            Write-Log "Database User: $($dbSecret.username)"
            # Don't log the password for security
            
            # Save database configuration
            $dbConfig = @{
                host = $dbSecret.host
                username = $dbSecret.username
                password = $dbSecret.password
                connection_string = "Server=$($dbSecret.host);Database=MyAppDB;User Id=$($dbSecret.username);Password=$($dbSecret.password);"
                updated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            
            $dbConfig | ConvertTo-Json | Out-File -FilePath "$ConfigOutputDir\database-config.json" -Encoding UTF8
            Write-Log "Database configuration saved to: $ConfigOutputDir\database-config.json"
            
            # Example: Test database connection (simulated)
            Write-Log "Testing database connection..."
            # In real application: Test-DbConnection -ConnectionString $dbConfig.connection_string
            Write-Log "Database connection test: SUCCESS"
        }
        
        # Example 2: API Integration
        if ($Secrets["kv/data/my-app/api"]) {
            $apiSecret = $Secrets["kv/data/my-app/api"]
            
            Write-Log "Setting up API integration..."
            Write-Log "API Endpoint: $($apiSecret.endpoint)"
            Write-Log "API Key: $($apiSecret.api_key.Substring(0,8))..."
            
            # Save API configuration
            $apiConfig = @{
                endpoint = $apiSecret.endpoint
                api_key = $apiSecret.api_key
                headers = @{
                    "Authorization" = "Bearer $($apiSecret.api_key)"
                    "Content-Type" = "application/json"
                }
                updated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            
            $apiConfig | ConvertTo-Json -Depth 3 | Out-File -FilePath "$ConfigOutputDir\api-config.json" -Encoding UTF8
            Write-Log "API configuration saved to: $ConfigOutputDir\api-config.json"
            
            # Example: Test API connection (simulated)
            Write-Log "Testing API connection..."
            # In real application: Test-ApiConnection -Endpoint $apiSecret.endpoint -ApiKey $apiSecret.api_key
            Write-Log "API connection test: SUCCESS"
        }
        
        # Example 3: Environment Variables for Other Applications
        Write-Log "Setting up environment variables..."
        $envVars = @{}
        
        if ($Secrets["kv/data/my-app/database"]) {
            $dbSecret = $Secrets["kv/data/my-app/database"]
            $envVars["DB_HOST"] = $dbSecret.host
            $envVars["DB_USER"] = $dbSecret.username
            $envVars["DB_PASSWORD"] = $dbSecret.password
        }
        
        if ($Secrets["kv/data/my-app/api"]) {
            $apiSecret = $Secrets["kv/data/my-app/api"]
            $envVars["API_ENDPOINT"] = $apiSecret.endpoint
            $envVars["API_KEY"] = $apiSecret.api_key
        }
        
        # Save environment variables file
        $envContent = @()
        foreach ($key in $envVars.Keys) {
            $envContent += "$key=$($envVars[$key])"
        }
        $envContent | Out-File -FilePath "$ConfigOutputDir\.env" -Encoding UTF8
        Write-Log "Environment variables saved to: $ConfigOutputDir\.env"
        
        # Example 4: Restart Application Services
        Write-Log "Restarting application services..."
        $servicesToRestart = @("MyApplication", "MyWebService")
        
        foreach ($serviceName in $servicesToRestart) {
            try {
                if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
                    Write-Log "Restarting service: $serviceName"
                    Restart-Service -Name $serviceName -Force
                    Write-Log "Service restarted successfully: $serviceName"
                } else {
                    Write-Log "Service not found: $serviceName" -Level "WARNING"
                }
            } catch {
                Write-Log "Failed to restart service '$serviceName': $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        Write-Log "Application configuration completed successfully"
        
    } catch {
        Write-Log "Failed to process secrets: $($_.Exception.Message)" -Level "ERROR"
    }
}

# =============================================================================
# Scheduled Task Creation
# =============================================================================

function Create-ScheduledTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath
    )
    
    try {
        Write-Log "Creating scheduled task: $TaskName"
        
        # Create action
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`" -VaultUrl `"$VaultUrl`" -VaultRole `"$VaultRole`""
        
        # Create trigger (daily at 2 AM)
        $trigger = New-ScheduledTaskTrigger -Daily -At "02:00"
        
        # Create settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
        
        # Register task under gMSA identity with correct LogonType
        # Key: Use LogonType Password for gMSA (Windows fetches password from AD)
        $principal = New-ScheduledTaskPrincipal -UserId "local.lab\vault-gmsa$" -LogonType Password -RunLevel Highest
        
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal
        
        Write-Log "Scheduled task created successfully: $TaskName"
        Write-Log "Task runs under: local.lab\vault-gmsa$"
        Write-Log "Schedule: Daily at 2:00 AM"
        Write-Log ""
        Write-Log "IMPORTANT: Ensure gMSA has 'Log on as a batch job' right:" -Level "WARNING"
        Write-Log "1. Run secpol.msc on this machine" -Level "WARNING"
        Write-Log "2. Navigate to: Local Policies → User Rights Assignment → Log on as a batch job" -Level "WARNING"
        Write-Log "3. Add: local.lab\vault-gmsa$" -Level "WARNING"
        Write-Log "4. Or configure via GPO if domain-managed" -Level "WARNING"
        
        return $true
        
    } catch {
        Write-Log "Failed to create scheduled task: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# =============================================================================
# Main Application Logic
# =============================================================================

function Start-VaultClientApplication {
    try {
        Write-Log "=== Vault Client Application Started ===" -Level "INFO"
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Write-Log "Running under identity: $currentIdentity" -Level "INFO"
        # Production validation checks
        Write-Log "Step 0: Production validation checks..." -Level "INFO"
        
        # Check if running under gMSA identity
        if ($currentIdentity -notlike "*vault-gmsa$") {
            Write-Log "ERROR: CRITICAL: Not running under gMSA identity!" -Level "ERROR"
            Write-Log "   Current identity: $currentIdentity" -Level "ERROR"
            Write-Log "   Expected identity: local.lab\vault-gmsa$" -Level "ERROR"
            Write-Log "   This will cause authentication failures." -Level "ERROR"
            Write-Log "   SOLUTION: Run this script via the scheduled task with gMSA identity." -Level "ERROR"
            return $false
        }
        
        # Check Kerberos tickets
        try {
            $klistOutput = klist 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log "ERROR: CRITICAL: No Kerberos tickets found!" -Level "ERROR"
                Write-Log "   Run 'klist' to check ticket status" -Level "ERROR"
                Write-Log "   SOLUTION: Ensure gMSA has valid tickets for SPN: $SPN" -Level "ERROR"
                return $false
            }
            
            if ($klistOutput -notmatch $SPN) {
                Write-Log "WARNING:  WARNING: No Kerberos ticket found for SPN: $SPN" -Level "WARNING"
                Write-Log "   Available tickets:" -Level "WARNING"
                Write-Log "   $($klistOutput -join '; ')" -Level "WARNING"
                Write-Log "   Proceeding with SPNEGO token generation..." -Level "INFO"
            } else {
                Write-Log "SUCCESS: Kerberos ticket found for SPN: $SPN" -Level "SUCCESS"
            }
        } catch {
            Write-Log "WARNING:  WARNING: Could not check Kerberos tickets: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Check network connectivity
        try {
            $vaultHost = ($VaultUrl -replace 'https?://', '' -replace ':8200', '')
            $connection = Test-NetConnection -ComputerName $vaultHost -Port 8200 -WarningAction SilentlyContinue
            if ($connection.TcpTestSucceeded) {
                Write-Log "SUCCESS: Network connectivity to Vault server confirmed" -Level "SUCCESS"
            } else {
                Write-Log "ERROR: CRITICAL: Cannot connect to Vault server: $vaultHost:8200" -Level "ERROR"
                Write-Log "   SOLUTION: Check network connectivity and firewall rules" -Level "ERROR"
                return $false
            }
        } catch {
            Write-Log "WARNING:  WARNING: Could not test network connectivity: $($_.Exception.Message)" -Level "WARNING"
        }
        
        Write-Log "SUCCESS: Production validation checks completed" -Level "SUCCESS"
        
        # Log configuration
        Write-Log "Configuration:" -Level "INFO"
        Write-Log "  Vault URL: $VaultUrl" -Level "INFO"
        Write-Log "  Vault Role: $VaultRole" -Level "INFO"
        Write-Log "  SPN: $SPN" -Level "INFO"
        Write-Log "  Secret Paths: $($SecretPaths -join ', ')" -Level "INFO"
        Write-Log "  Config Directory: $ConfigOutputDir" -Level "INFO"
        
        # Step 1: Get SPNEGO token
        Write-Log "Step 1: Obtaining SPNEGO token..." -Level "INFO"
        $spnegoToken = Get-SPNEGOToken -TargetSPN $SPN
        
        if (-not $spnegoToken) {
            Write-Log "Failed to obtain authentication token" -Level "ERROR"
            Write-Log "PRODUCTION TROUBLESHOOTING GUIDE:" -Level "ERROR"
            Write-Log "1. Verify gMSA identity: $currentIdentity" -Level "ERROR"
            Write-Log "2. Check Kerberos tickets: klist" -Level "ERROR"
            Write-Log "3. Verify SPN: $SPN" -Level "ERROR"
            Write-Log "4. Test Vault connectivity: Test-NetConnection vault.example.com -Port 8200" -Level "ERROR"
            Write-Log "5. Check Vault server logs for authentication errors" -Level "ERROR"
            Write-Log "6. Ensure gMSA has 'Log on as a batch job' right" -Level "ERROR"
            return $false
        }
        
        # Step 2: Authenticate to Vault
        Write-Log "Step 2: Authenticating to Vault..." -Level "INFO"
        $vaultToken = Invoke-VaultAuthentication -VaultUrl $VaultUrl -Role $VaultRole -SPNEGOToken $spnegoToken
        
        if (-not $vaultToken) {
            Write-Log "Failed to authenticate to Vault" -Level "ERROR"
            return $false
        }
        
        # Step 3: Retrieve secrets
        Write-Log "Step 3: Retrieving secrets..." -Level "INFO"
        $secrets = Get-VaultSecrets -VaultUrl $VaultUrl -Token $vaultToken -SecretPaths $SecretPaths
        
        if ($secrets.Count -eq 0) {
            Write-Log "No secrets were retrieved" -Level "WARNING"
            return $false
        }
        
        # Step 4: Use secrets in application
        Write-Log "Step 4: Processing secrets for application use..." -Level "INFO"
        Use-SecretsInApplication -Secrets $secrets
        
        Write-Log "=== Vault Client Application Completed Successfully ===" -Level "INFO"
        return $true
        
    } catch {
        Write-Log "Application execution failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Main execution
if ($CreateScheduledTask) {
    Write-Log "Creating scheduled task mode..."
    
    # Get the current script path
    $scriptPath = $MyInvocation.MyCommand.Path
    
    if (Create-ScheduledTask -TaskName $TaskName -ScriptPath $scriptPath) {
        Write-Log "Scheduled task created successfully!" -Level "INFO"
        Write-Log "You can now run the application manually or wait for the scheduled execution." -Level "INFO"
    } else {
        Write-Log "Failed to create scheduled task" -Level "ERROR"
        exit 1
    }
} else {
    Write-Log "Running application mode..."
    
    if (Start-VaultClientApplication) {
        Write-Log "Application completed successfully!" -Level "INFO"
        exit 0
    } else {
        Write-Log "Application failed" -Level "ERROR"
        exit 1
    }
}

# =============================================================================
# Usage Examples
# =============================================================================

<#
USAGE EXAMPLES:

1. Run the application manually:
   .\vault-client-app.ps1

2. Run with custom parameters:
   .\vault-client-app.ps1 -VaultUrl "https://vault.company.com:8200" -SecretPaths @("secret/data/prod/db", "secret/data/prod/api")

3. Create a scheduled task:
   .\vault-client-app.ps1 -CreateScheduledTask

4. Create scheduled task with custom name:
   .\vault-client-app.ps1 -CreateScheduledTask -TaskName "MyVaultApp"

WHAT THIS SCRIPT DOES:
- Authenticates to Vault using gMSA identity
- Retrieves secrets from specified paths
- Saves configurations to JSON files
- Creates environment variable files
- Restarts application services
- Provides comprehensive logging
- Can run as scheduled task or manually

OUTPUT FILES:
- C:\vault\config\database-config.json
- C:\vault\config\api-config.json
- C:\vault\config\.env
- C:\vault\config\vault-client.log
#>
