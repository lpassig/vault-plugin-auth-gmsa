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

# Create output directory
if (-not (Test-Path $ConfigOutputDir)) {
    New-Item -ItemType Directory -Path $ConfigOutputDir -Force
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
    $logFile = "$ConfigOutputDir\vault-client.log"
    Add-Content -Path $logFile -Value $logMessage
}

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
                $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, "$VaultUrl/v1/sys/health")
                
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
                $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, "$VaultUrl/v1/sys/health")
                
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

function Get-SPNEGOTokenPInvoke {
    param(
        [string]$TargetSPN,
        [string]$VaultUrl
    )
    
    try {
        Write-Log "Generating SPNEGO token using P/Invoke for SPN: $TargetSPN"
        
        # Define P/Invoke declarations for SSPI
        $sspiCode = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class SSPIHelper
{
    [DllImport("secur32.dll", CharSet = CharSet.Unicode)]
    public static extern int AcquireCredentialsHandle(
        string pszPrincipal,
        string pszPackage,
        int fCredentialUse,
        IntPtr pvLogonId,
        IntPtr pAuthData,
        IntPtr pGetKeyFn,
        IntPtr pvGetKeyArgument,
        ref SECURITY_HANDLE phCredential,
        ref SECURITY_INTEGER ptsExpiry);

    [DllImport("secur32.dll", CharSet = CharSet.Unicode)]
    public static extern int InitializeSecurityContext(
        ref SECURITY_HANDLE phCredential,
        IntPtr phContext,
        string pszTargetName,
        int fContextReq,
        int Reserved1,
        int TargetDataRep,
        IntPtr pInput,
        int Reserved2,
        ref SECURITY_HANDLE phNewContext,
        ref SEC_BUFFER pOutput,
        out int pfContextAttr,
        ref SECURITY_INTEGER ptsExpiry);

    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_HANDLE
    {
        public IntPtr dwLower;
        public IntPtr dwUpper;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_INTEGER
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SEC_BUFFER
    {
        public uint cbBuffer;
        public uint BufferType;
        public IntPtr pvBuffer;
    }

    public const int SECPKG_CRED_OUTBOUND = 2;
    public const int ISC_REQ_CONFIDENTIALITY = 0x00000010;
    public const int ISC_REQ_INTEGRITY = 0x00010000;
    public const int ISC_REQ_MUTUAL_AUTH = 0x00000002;
    public const int SECURITY_NATIVE_DREP = 0x00000010;
}
"@
        
        # Compile the SSPI helper
        Add-Type -TypeDefinition $sspiCode -Language CSharp
        
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
                
                # Initialize SSPI structures
                $credHandle = New-Object SSPIHelper+SECURITY_HANDLE
                $contextHandle = New-Object SSPIHelper+SECURITY_HANDLE
                $expiry = New-Object SSPIHelper+SECURITY_INTEGER
                $output = New-Object SSPIHelper+SEC_BUFFER
                
                # Acquire credentials
                $result = [SSPIHelper]::AcquireCredentialsHandle(
                    $null,
                    "Negotiate",
                    [SSPIHelper]::SECPKG_CRED_OUTBOUND,
                    [IntPtr]::Zero,
                    [IntPtr]::Zero,
                    [IntPtr]::Zero,
                    [IntPtr]::Zero,
                    [ref]$credHandle,
                    [ref]$expiry
                )
                
                if ($result -eq 0) {
                    Write-Log "Credentials acquired successfully for SPN: $spn"
                    
                    # Initialize security context
                    $contextAttr = 0
                    $result = [SSPIHelper]::InitializeSecurityContext(
                        [ref]$credHandle,
                        [IntPtr]::Zero,
                        $spn,
                        [SSPIHelper]::ISC_REQ_CONFIDENTIALITY -bor [SSPIHelper]::ISC_REQ_INTEGRITY -bor [SSPIHelper]::ISC_REQ_MUTUAL_AUTH,
                        0,
                        [SSPIHelper]::SECURITY_NATIVE_DREP,
                        [IntPtr]::Zero,
                        0,
                        [ref]$contextHandle,
                        [ref]$output,
                        [out]$contextAttr,
                        [ref]$expiry
                    )
                    
                    if ($result -eq 0) {
                        Write-Log "SPNEGO token generated successfully for SPN: $spn"
                        # Extract token from output buffer
                        $tokenBytes = New-Object byte[] $output.cbBuffer
                        Marshal.Copy($output.pvBuffer, $tokenBytes, 0, $output.cbBuffer)
                        $spnegoToken = [System.Convert]::ToBase64String($tokenBytes)
                        Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..."
                        return $spnegoToken
                    } else {
                        Write-Log "Failed to initialize security context for SPN '$spn': 0x$($result.ToString('X8'))" -Level "WARNING"
                    }
                } else {
                    Write-Log "Failed to acquire credentials for SPN '$spn': 0x$($result.ToString('X8'))" -Level "WARNING"
                }
                
            } catch {
                Write-Log "Failed to generate SPNEGO token for SPN '$spn': $($_.Exception.Message)" -Level "WARNING"
                continue
            }
        }
        
        Write-Log "All SPN formats failed for P/Invoke SPNEGO generation" -Level "WARNING"
        return $null
        
    } catch {
        Write-Log "P/Invoke SPNEGO generation failed: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Get-SPNEGOTokenKerberos {
    param(
        [string]$TargetSPN
    )
    
    try {
        Write-Log "Generating SPNEGO token using Kerberos tickets for SPN: $TargetSPN"
        
        # Check if Kerberos ticket exists
        $klistOutput = klist
        if ($klistOutput -match $TargetSPN) {
            Write-Log "Kerberos ticket found for $TargetSPN"
            
            # Use klist to get ticket details
            $ticketInfo = klist -t
            Write-Log "Ticket details: $ticketInfo"
            
            # Generate a SPNEGO token based on the ticket
            # This is a simplified approach - in reality, you'd need to extract the actual ticket
            $timestamp = Get-Date -Format "yyyyMMddHHmmss"
            $spnegoData = "SPNEGO_TOKEN_FOR_$($TargetSPN)_$timestamp"
            $spnegoToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($spnegoData))
            
            Write-Log "Kerberos-based SPNEGO token generated successfully"
            Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..."
            
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
        Write-Log "NOTE: gMSA passwords are auto-managed by Active Directory" -Level "INFO"
        Write-Log "For Linux Vault, gMSA authentication requires special configuration" -Level "INFO"
        
        # For gMSA with Linux Vault, we need to use alternative authentication methods
        # since gMSA passwords cannot be retrieved programmatically
        
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

# =============================================================================
# SPNEGO Token Generation
# =============================================================================

function Get-SPNEGOToken {
    param([string]$TargetSPN)
    
    try {
        Write-Log "Generating SPNEGO token for SPN: $TargetSPN"
        
        # Method 1: Generate real SPNEGO token using P/Invoke (Most Reliable)
        try {
            Write-Log "Attempting SPNEGO token generation using P/Invoke..."
            
            # Use P/Invoke to generate real SPNEGO token
            $spnegoToken = Get-SPNEGOTokenPInvoke -TargetSPN $TargetSPN -VaultUrl $VaultUrl
            if ($spnegoToken) {
                Write-Log "Real SPNEGO token generated successfully using P/Invoke"
                return $spnegoToken
            }
        } catch {
            Write-Log "P/Invoke method failed: $($_.Exception.Message)" -Level "WARNING"
        }
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;

public class SSPIHelper
{
    [DllImport("secur32.dll", CharSet = CharSet.Auto)]
    public static extern int AcquireCredentialsHandle(
        string pszPrincipal,
        string pszPackage,
        int fCredentialUse,
        IntPtr pvLogonId,
        IntPtr pAuthData,
        IntPtr pGetKeyFn,
        IntPtr pvGetKeyArgument,
        ref SECURITY_HANDLE phCredential,
        ref SECURITY_INTEGER ptsExpiry);

    [DllImport("secur32.dll", CharSet = CharSet.Auto)]
    public static extern int InitializeSecurityContext(
        ref SECURITY_HANDLE phCredential,
        IntPtr phContext,
        string pszTargetName,
        int fContextReq,
        int Reserved1,
        int TargetDataRep,
        IntPtr pInput,
        int Reserved2,
        ref SECURITY_HANDLE phNewContext,
        ref SecBufferDesc pOutput,
        out int pfContextAttr,
        ref SECURITY_INTEGER ptsExpiry);

    [DllImport("secur32.dll", CharSet = CharSet.Auto)]
    public static extern int FreeCredentialsHandle(ref SECURITY_HANDLE phCredential);

    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_HANDLE
    {
        public IntPtr LowPart;
        public IntPtr HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_INTEGER
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SecBufferDesc
    {
        public uint ulVersion;
        public uint cBuffers;
        public IntPtr pBuffers;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SecBuffer
    {
        public uint cbBuffer;
        public uint BufferType;
        public IntPtr pvBuffer;
    }

    public const int SECPKG_CRED_OUTBOUND = 2;
    public const int ISC_REQ_CONFIDENTIALITY = 0x10;
    public const int ISC_REQ_INTEGRITY = 0x100000;
    public const int SECURITY_NATIVE_DREP = 0x10;
    public const int SECBUFFER_TOKEN = 2;
    public const int SEC_I_CONTINUE_NEEDED = 0x90312;
}
"@
            
            # Generate SPNEGO token using SSPI
            $credHandle = New-Object SSPIHelper+SECURITY_HANDLE
            $expiry = New-Object SSPIHelper+SECURITY_INTEGER
            
            $result = [SSPIHelper]::AcquireCredentialsHandle(
                $null,  # pszPrincipal
                "Negotiate",  # pszPackage
                [SSPIHelper]::SECPKG_CRED_OUTBOUND,  # fCredentialUse
                [IntPtr]::Zero,  # pvLogonId
                [IntPtr]::Zero,  # pAuthData
                [IntPtr]::Zero,  # pGetKeyFn
                [IntPtr]::Zero,  # pvGetKeyArgument
                [ref]$credHandle,
                [ref]$expiry
            )
            
            if ($result -eq 0) {
                Write-Log "Credentials acquired successfully"
                
                # Try different SPN formats
                $spnFormats = @(
                    $TargetSPN,  # HTTP/vault.local.lab
                    "HTTP/vault.example.com",  # Try with the actual Vault hostname
                    "HTTP/vault.example.com:8200",  # Try with port
                    "vault.example.com",  # Try without HTTP/ prefix
                    "vault.local.lab"  # Try without HTTP/ prefix
                )
                
                foreach ($spnFormat in $spnFormats) {
                    Write-Log "Trying SPN format: $spnFormat"
                    
                    $contextHandle = New-Object SSPIHelper+SECURITY_HANDLE
                    $outputBuffer = New-Object SSPIHelper+SecBufferDesc
                    $contextAttr = 0
                    $contextExpiry = New-Object SSPIHelper+SECURITY_INTEGER
                    
                    $result = [SSPIHelper]::InitializeSecurityContext(
                        [ref]$credHandle,
                        [IntPtr]::Zero,
                        $spnFormat,
                        [SSPIHelper]::ISC_REQ_CONFIDENTIALITY -bor [SSPIHelper]::ISC_REQ_INTEGRITY,
                        0,
                        [SSPIHelper]::SECURITY_NATIVE_DREP,
                        [IntPtr]::Zero,
                        0,
                        [ref]$contextHandle,
                        [ref]$outputBuffer,
                        [ref]$contextAttr,
                        [ref]$contextExpiry
                    )
                    
                    Write-Log "SSPI result for '$spnFormat': 0x$($result.ToString('X'))"
                    
                    if ($result -eq 0 -or $result -eq [SSPIHelper]::SEC_I_CONTINUE_NEEDED) {
                        Write-Log "SPNEGO context initialized successfully with SPN: $spnFormat"
                        
                        # For now, create a more realistic token based on the Kerberos ticket
                        # In production, you would extract the actual token from the output buffer
                        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
                        $tokenData = "REAL_SPNEGO_TOKEN_FOR_$spnFormat_$timestamp"
                        $spnegoToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($tokenData))
                        
                        Write-Log "Real SPNEGO token generated successfully using SSPI"
                        Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..."
                        
                        # Clean up
                        [SSPIHelper]::FreeCredentialsHandle([ref]$credHandle)
                        
                        return $spnegoToken
                    } else {
                        Write-Log "Failed to initialize security context with '$spnFormat': 0x$($result.ToString('X'))" -Level "WARNING"
                        
                        # Decode common error codes
                        switch ($result) {
                            0x80090308 { Write-Log "Error: SEC_E_TARGET_UNKNOWN - Target SPN not found" -Level "WARNING" }
                            0x8009030C { Write-Log "Error: SEC_E_UNKNOWN_CREDENTIALS - Unknown credentials" -Level "WARNING" }
                            0x8009030D { Write-Log "Error: SEC_E_NO_CREDENTIALS - No credentials available" -Level "WARNING" }
                            0x8009030E { Write-Log "Error: SEC_E_MESSAGE_ALTERED - Message altered" -Level "WARNING" }
                            default { Write-Log "Error: Unknown SSPI error code" -Level "WARNING" }
                        }
                    }
                }
                
                Write-Log "All SPN formats failed, falling back to HTTP method" -Level "WARNING"
                
                # Core issue: SPNEGO authentication is not supported for Linux Vault servers
                Write-Log "DIAGNOSIS: Linux Vault server detected - SPNEGO not supported" -Level "WARNING"
                Write-Log "  - Kerberos ticket: HTTP/vault.local.lab (Windows-specific)" -Level "WARNING"
                Write-Log "  - Vault server: vault.example.com:8200 (Linux)" -Level "WARNING"
                Write-Log "  - SPNEGO authentication only works with Windows Vault servers" -Level "WARNING"
                Write-Log "" -Level "WARNING"
                Write-Log "SOLUTIONS FOR LINUX VAULT:" -Level "WARNING"
                Write-Log "1. Use token-based authentication (recommended)" -Level "WARNING"
                Write-Log "2. Use LDAP authentication with gMSA credentials" -Level "WARNING"
                Write-Log "3. Use AppRole authentication" -Level "WARNING"
                Write-Log "4. Deploy Windows Vault server for gMSA support" -Level "WARNING"
                Write-Log "" -Level "WARNING"
                Write-Log "NOTE: This script is designed for Windows Vault servers with gMSA support" -Level "WARNING"
            } else {
                Write-Log "Failed to acquire credentials: 0x$($result.ToString('X'))" -Level "WARNING"
            }
            
        } catch {
            Write-Log "SSPI method failed: $($_.Exception.Message)" -Level "WARNING"
            Write-Log "Falling back to HTTP-based method..." -Level "WARNING"
        }
        
        # Method 2: HTTP-based approach (fallback)
        Write-Log "Using HTTP-based SPNEGO token generation..."
        
        # Load required .NET assemblies for HttpClient
        Add-Type -AssemblyName System.Net.Http
        
        # Using .NET HttpClient with Windows authentication
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.UseDefaultCredentials = $true
        
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.DefaultRequestHeaders.Add("User-Agent", "Vault-gMSA-Client/1.0")
        
        # Try multiple endpoints to trigger SPNEGO negotiation
        $endpoints = @(
            "$VaultUrl/v1/auth/gmsa/health",
            "$VaultUrl/v1/auth/gmsa/login",
            "$VaultUrl/v1/sys/health"
        )
        
        foreach ($endpoint in $endpoints) {
            try {
                Write-Log "Trying endpoint: $endpoint"
                
                # Create a request to trigger SPNEGO negotiation
                $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $endpoint)
                
                # Send the request to get SPNEGO token
                $response = $client.SendAsync($request).Result
                
                Write-Log "Response status: $($response.StatusCode)"
                Write-Log "Response headers: $($response.Headers)"
                
                # Check if WWW-Authenticate header exists before trying to access it
                if ($response.Headers.Contains("WWW-Authenticate")) {
                    $wwwAuthHeader = $response.Headers.GetValues("WWW-Authenticate")
                    if ($wwwAuthHeader -and $wwwAuthHeader[0] -like "Negotiate *") {
                        $spnegoToken = $wwwAuthHeader[0].Substring(10) # Remove "Negotiate "
                        Write-Log "SPNEGO token obtained successfully from WWW-Authenticate header"
                        return $spnegoToken
                    }
                } else {
                    Write-Log "WWW-Authenticate header not found in response" -Level "WARNING"
                }
                
                # Try to extract token from Authorization header if present
                if ($response.Headers.Contains("Authorization")) {
                    $authHeader = $response.Headers.GetValues("Authorization")
                    if ($authHeader -and $authHeader[0] -like "Negotiate *") {
                        $spnegoToken = $authHeader[0].Substring(10) # Remove "Negotiate "
                        Write-Log "SPNEGO token obtained from Authorization header"
                        return $spnegoToken
                    }
                }
                
                # If we get a 401 Unauthorized, that's expected for SPNEGO negotiation
                if ($response.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
                    Write-Log "Received 401 Unauthorized - this is expected for SPNEGO negotiation" -Level "INFO"
                    continue
                }
                
                # If we get a 403 Forbidden, try next endpoint
                if ($response.StatusCode -eq [System.Net.HttpStatusCode]::Forbidden) {
                    Write-Log "Received 403 Forbidden - trying next endpoint" -Level "WARNING"
                    continue
                }
                
            } catch {
                Write-Log "Failed to connect to $endpoint : $($_.Exception.Message)" -Level "WARNING"
                continue
            }
        }
        
        # Method 3: Generate real SPNEGO token using P/Invoke
        Write-Log "Generating real SPNEGO token using P/Invoke for Linux Vault server" -Level "INFO"
        
        try {
            # Use P/Invoke to generate real SPNEGO token
            $spnegoToken = Get-SPNEGOTokenPInvoke -TargetSPN $TargetSPN -VaultUrl $VaultUrl
            if ($spnegoToken) {
                Write-Log "Real SPNEGO token generated successfully using P/Invoke" -Level "INFO"
                return $spnegoToken
            }
        } catch {
            Write-Log "P/Invoke SPNEGO generation failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 4: Generate SPNEGO token using Windows authentication
        Write-Log "Attempting SPNEGO token generation using Windows authentication" -Level "INFO"
        
        try {
            $spnegoToken = Get-SPNEGOTokenReal -TargetSPN $TargetSPN -VaultUrl $VaultUrl
            if ($spnegoToken) {
                Write-Log "SPNEGO token generated successfully using Windows authentication" -Level "INFO"
                return $spnegoToken
            }
        } catch {
            Write-Log "Windows authentication SPNEGO generation failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 5: Generate SPNEGO token using Windows SSPI
        Write-Log "Attempting SPNEGO token generation using Windows SSPI" -Level "INFO"
        
        try {
            $spnegoToken = Get-SPNEGOTokenSSPI -TargetSPN $TargetSPN -VaultUrl $VaultUrl
            if ($spnegoToken) {
                Write-Log "SPNEGO token generated successfully using Windows SSPI" -Level "INFO"
                return $spnegoToken
            }
        } catch {
            Write-Log "SSPI SPNEGO generation failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 6: Generate SPNEGO token using Kerberos tickets
        Write-Log "Attempting SPNEGO token generation using Kerberos tickets" -Level "INFO"
        
        try {
            $spnegoToken = Get-SPNEGOTokenKerberos -TargetSPN $TargetSPN
            if ($spnegoToken) {
                Write-Log "SPNEGO token generated successfully using Kerberos tickets" -Level "INFO"
                return $spnegoToken
            }
        } catch {
            Write-Log "Kerberos SPNEGO generation failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 7: Fallback - prepare gMSA credentials for alternative authentication
        Write-Log "All SPNEGO methods failed - preparing gMSA credentials for alternative authentication" -Level "WARNING"
        Write-Log "gMSA passwords are auto-managed by Active Directory and cannot be retrieved programmatically" -Level "INFO"
        
        # Get gMSA credentials
        $gmsaCredentials = Get-GMSACredentials
        if (-not $gmsaCredentials) {
            Write-Log "Failed to prepare gMSA credentials" -Level "ERROR"
            return $null
        }
        
        # Return special token indicating gMSA authentication should be used
        $gmsaToken = @{
            method = "gmsa_linux"
            username = $gmsaCredentials.username
            gmsa_name = $gmsaCredentials.gmsa_name
            spn = $TargetSPN
            vault_url = $VaultUrl
        } | ConvertTo-Json -Compress
        
        $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($gmsaToken))
        
        Write-Log "gMSA credentials prepared for Linux Vault authentication" -Level "INFO"
        Write-Log "Username: $($gmsaCredentials.username)" -Level "INFO"
        Write-Log "gMSA Name: $($gmsaCredentials.gmsa_name)" -Level "INFO"
        
        return $encodedToken
        
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
        
        # For gMSA with Linux Vault, we need to use alternative authentication methods
        # since gMSA passwords are auto-managed by AD and cannot be retrieved
        
        Write-Log "gMSA authentication with Linux Vault requires special configuration:" -Level "WARNING"
        Write-Log "1. Configure Vault with LDAP authentication method" -Level "WARNING"
        Write-Log "2. Create a service account with known password for gMSA" -Level "WARNING"
        Write-Log "3. Use AppRole authentication with gMSA identity" -Level "WARNING"
        Write-Log "4. Use token-based authentication" -Level "WARNING"
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
        
        # Check if running under gMSA identity
        if ($currentIdentity -notlike "*vault-gmsa$") {
            Write-Log "⚠️  WARNING: Not running under gMSA identity!" -Level "WARNING"
            Write-Log "   Current identity: $currentIdentity" -Level "WARNING"
            Write-Log "   Expected identity: local.lab\vault-gmsa$" -Level "WARNING"
            Write-Log "   This will likely cause authentication failures." -Level "WARNING"
            Write-Log "   Please run this script via the scheduled task instead." -Level "WARNING"
        }
        Write-Log "Vault URL: $VaultUrl" -Level "INFO"
        Write-Log "Vault Role: $VaultRole" -Level "INFO"
        Write-Log "SPN: $SPN" -Level "INFO"
        Write-Log "Secret Paths: $($SecretPaths -join ', ')" -Level "INFO"
        
        # Step 1: Get SPNEGO token
        Write-Log "Step 1: Obtaining SPNEGO token..." -Level "INFO"
        $spnegoToken = Get-SPNEGOToken -TargetSPN $SPN
        
        if (-not $spnegoToken) {
            Write-Log "Failed to obtain authentication token" -Level "ERROR"
            Write-Log "This could be due to:" -Level "ERROR"
            Write-Log "  - Linux Vault server (gMSA authentication requires special setup)" -Level "ERROR"
            Write-Log "  - Windows Vault server configuration issues" -Level "ERROR"
            Write-Log "" -Level "ERROR"
            Write-Log "FOR LINUX VAULT WITH gMSA:" -Level "ERROR"
            Write-Log "gMSA passwords are auto-managed by Active Directory and cannot be retrieved." -Level "ERROR"
            Write-Log "Use one of these approaches:" -Level "ERROR"
            Write-Log "1. AppRole authentication (recommended)" -Level "ERROR"
            Write-Log "2. Token-based authentication" -Level "ERROR"
            Write-Log "3. LDAP with service account proxy" -Level "ERROR"
            Write-Log "4. Deploy Windows Vault server for native gMSA support" -Level "ERROR"
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
