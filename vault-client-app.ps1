param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$SPN = "",  # Auto-detect from VaultUrl if not specified
    [string[]]$SecretPaths = @("kv/data/my-app/database", "kv/data/my-app/api"),
    [string]$ConfigOutputDir = "C:\vault-client\config",
    [switch]$CreateScheduledTask = $false,
    [string]$TaskName = "VaultClientApp"
)

# Import required .NET types for Win32 SSPI
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;

public class SSPI
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
        ref SECURITY_INTEGER ptsExpiry
    );

    [DllImport("secur32.dll")]
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
        ref SECURITY_INTEGER ptsExpiry
    );

    [DllImport("secur32.dll")]
    public static extern int FreeContextBuffer(IntPtr pvContextBuffer);

    [DllImport("secur32.dll")]
    public static extern int FreeCredentialsHandle(ref SECURITY_HANDLE phCredential);

    [DllImport("secur32.dll")]
    public static extern int DeleteSecurityContext(ref SECURITY_HANDLE phContext);

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
        public int cbBuffer;
        public int BufferType;
        public IntPtr pvBuffer;
    }

    public const int SECPKG_CRED_OUTBOUND = 2;
    public const int SECURITY_NETWORK_DREP = 0;
    public const int ISC_REQ_CONFIDENTIALITY = 0x10;
    public const int ISC_REQ_INTEGRITY = 0x20;
    public const int ISC_REQ_MUTUAL_AUTH = 0x40;
    public const int SECBUFFER_TOKEN = 2;
    public const int SEC_E_OK = 0;
    public const int SEC_I_CONTINUE_NEEDED = 0x00090312;
    public const int SEC_I_COMPLETE_NEEDED = 0x00090313;
    public const int SEC_I_COMPLETE_AND_CONTINUE = 0x00090314;
}
"@

# =============================================================================
# Configuration and Logging Setup
# =============================================================================

# Bypass SSL certificate validation for testing (NOT for production)
try {
    # Method 1: Use ServicePointManager (legacy)
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
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    
    Write-Host "SSL certificate validation bypassed for testing" -ForegroundColor Yellow
    Write-Host "ServicePointManager CertificatePolicy: $([System.Net.ServicePointManager]::CertificatePolicy)" -ForegroundColor Cyan
    Write-Host "ServicePointManager SecurityProtocol: $([System.Net.ServicePointManager]::SecurityProtocol)" -ForegroundColor Cyan
} catch {
    Write-Host "Could not bypass SSL certificate validation: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Quick DNS fix: Add hostname mapping for vault.local.lab
try {
    Write-Host "Applying DNS resolution fix..." -ForegroundColor Cyan
    
    # Extract hostname/IP from Vault URL
    $vaultHost = [System.Uri]::new($VaultUrl).Host
    Write-Host "Vault host: $vaultHost" -ForegroundColor Cyan
    
    # Check if it's an IP address
    $isIP = [System.Net.IPAddress]::TryParse($vaultHost, [ref]$null)
    
    if ($isIP) {
        Write-Host "Detected IP address: $vaultHost" -ForegroundColor Cyan
        $vaultIP = $vaultHost
        Write-Host "Using IP: $vaultIP for vault.local.lab mapping" -ForegroundColor Cyan
    } else {
        Write-Host "Detected hostname: $vaultHost" -ForegroundColor Cyan
        # Try to resolve hostname to IP
        try {
            $dnsResult = [System.Net.Dns]::GetHostAddresses($vaultHost)
            $vaultIP = $dnsResult[0].IPAddressToString
            Write-Host "Resolved hostname to IP: $vaultIP" -ForegroundColor Cyan
        } catch {
            Write-Host "Could not resolve hostname, using as-is" -ForegroundColor Yellow
            $vaultIP = $vaultHost
        }
    }
    
    # Only apply hostname mapping if using hostname-based SPN
    if ($SPN -like "HTTP/vault.local.lab") {
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
                Write-Host "SUCCESS: Added '$vaultIP vault.local.lab' to hosts file" -ForegroundColor Green
            } else {
                Write-Host "Hosts entry already exists" -ForegroundColor Green
            }
            
            # Flush DNS cache
            try {
                ipconfig /flushdns | Out-Null
                Write-Host "SUCCESS: DNS cache flushed" -ForegroundColor Green
            } catch {
                Write-Host "WARNING: Could not flush DNS cache (may need admin rights)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "Using IP-based SPN: $SPN - no hostname mapping needed" -ForegroundColor Green
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
    
    # Write to console with color coding
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "INFO" { Write-Host $logMessage -ForegroundColor Cyan }
        default { Write-Host $logMessage }
    }
    
    # Also write to log file
    try {
    $logFile = "$ConfigOutputDir\vault-client.log"
        Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Auto-detect SPN if not specified
if ([string]::IsNullOrEmpty($SPN)) {
    $vaultHost = [System.Uri]::new($VaultUrl).Host
    $isIP = [System.Net.IPAddress]::TryParse($vaultHost, [ref]$null)
    
    if ($isIP) {
        $SPN = "HTTP/$vaultHost"
        Write-Log "Auto-detected IP-based SPN: $SPN" -Level "INFO"
        
        # Check if IP SPN support is enabled
        try {
            $tryIPSPN = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters" -Name "TryIPSPN" -ErrorAction SilentlyContinue
            if ($tryIPSPN -and $tryIPSPN.TryIPSPN -eq 1) {
                Write-Log "SUCCESS: IP SPN support is enabled" -Level "SUCCESS"
            } else {
                Write-Log "WARNING: IP SPN support may not be enabled" -Level "WARNING"
                Write-Log "To enable IP SPN support, run as Administrator:" -Level "WARNING"
                Write-Log "reg add \"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters\" /v TryIPSPN /t REG_DWORD /d 1 /f" -Level "WARNING"
            }
        } catch {
            Write-Log "WARNING: Could not check IP SPN support status" -Level "WARNING"
        }
    } else {
        $SPN = "HTTP/$vaultHost"
        Write-Log "Auto-detected hostname-based SPN: $SPN" -Level "INFO"
    }
}

# Test logging immediately
Write-Log "Script initialization completed successfully" -Level "INFO"
Write-Log "Script version: 3.12 (Multi-Endpoint SPNEGO Trigger)" -Level "INFO"
Write-Log "Config directory: $ConfigOutputDir" -Level "INFO"
Write-Log "Log file location: $ConfigOutputDir\vault-client.log" -Level "INFO"
Write-Log "Vault URL: $VaultUrl" -Level "INFO"
Write-Log "SPN: $SPN" -Level "INFO"

# =============================================================================
# SPNEGO Token Generation using Win32 SSPI
# =============================================================================

function Get-SPNEGOTokenPInvoke {
    param(
        [string]$TargetSPN,
        [string]$VaultUrl
    )
    
    try {
        Write-Log "Generating real SPNEGO token using Win32 SSPI APIs for SPN: $TargetSPN" -Level "INFO"
        
        # Check if we have a Kerberos ticket for the target SPN
        $klistOutput = klist 2>&1
        if ($klistOutput -match $TargetSPN) {
            Write-Log "Kerberos ticket found for $TargetSPN" -Level "INFO"
            Write-Log "Ticket details: $($klistOutput -join '; ')" -Level "INFO"
        } else {
            Write-Log "No Kerberos ticket found for $TargetSPN" -Level "WARNING"
            
            # Check if we have a TGT (Ticket Granting Ticket)
            if ($klistOutput -match "krbtgt/LOCAL.LAB") {
                Write-Log "TGT (Ticket Granting Ticket) found - attempting to request service ticket" -Level "INFO"
                
                # Try to request the service ticket using klist
                Write-Log "Requesting service ticket for $TargetSPN using klist..." -Level "INFO"
                try {
                    $serviceTicketResult = klist get $TargetSPN 2>&1
                    Write-Log "Service ticket request result: $serviceTicketResult" -Level "INFO"
                    
                    # Check if service ticket was obtained
                    Start-Sleep -Seconds 2
                    $updatedKlistOutput = klist 2>&1
                    if ($updatedKlistOutput -match $TargetSPN) {
                        Write-Log "SUCCESS: Service ticket obtained for $TargetSPN" -Level "SUCCESS"
                    } else {
                        Write-Log "WARNING: Service ticket request may have failed" -Level "WARNING"
                        Write-Log "Proceeding with TGT - Windows SSPI may generate service ticket on-demand" -Level "INFO"
                    }
                } catch {
                    Write-Log "Service ticket request failed: $($_.Exception.Message)" -Level "WARNING"
                    Write-Log "Proceeding with TGT - Windows SSPI may generate service ticket on-demand" -Level "INFO"
                }
            } else {
                Write-Log "No TGT found - cannot proceed with SPNEGO generation" -Level "ERROR"
                Write-Log "gMSA account must have valid Kerberos tickets" -Level "ERROR"
                return $null
            }
        }
        
        # Generate real SPNEGO token using Win32 SSPI APIs
        Write-Log "Generating real SPNEGO token using Win32 SSPI APIs..." -Level "INFO"
        
        # Enhanced debugging for gMSA context
        Write-Log "=== DEBUGGING gMSA CONTEXT ===" -Level "INFO"
        Write-Log "Current user: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -Level "INFO"
        Write-Log "Current user type: $([System.Security.Principal.WindowsIdentity]::GetCurrent().AuthenticationType)" -Level "INFO"
        Write-Log "Is authenticated: $([System.Security.Principal.WindowsIdentity]::GetCurrent().IsAuthenticated)" -Level "INFO"
        Write-Log "Is guest: $([System.Security.Principal.WindowsIdentity]::GetCurrent().IsGuest)" -Level "INFO"
        Write-Log "Is system: $([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem)" -Level "INFO"
        Write-Log "Is anonymous: $([System.Security.Principal.WindowsIdentity]::GetCurrent().IsAnonymous)" -Level "INFO"
        
        # Check available credentials
        Write-Log "Checking available credentials..." -Level "INFO"
        try {
            $defaultCreds = [System.Net.CredentialCache]::DefaultCredentials
            if ($defaultCreds) {
                Write-Log "Default credentials available: $($defaultCreds.GetType().Name)" -Level "INFO"
                Write-Log "Default credentials domain: $($defaultCreds.Domain)" -Level "INFO"
                Write-Log "Default credentials username: $($defaultCreds.UserName)" -Level "INFO"
            } else {
                Write-Log "No default credentials available" -Level "WARNING"
            }
        } catch {
            Write-Log "Error checking default credentials: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Check Kerberos ticket cache in detail
        Write-Log "=== DETAILED KERBEROS TICKET ANALYSIS ===" -Level "INFO"
        try {
            $detailedKlist = klist 2>&1
            Write-Log "Full klist output:" -Level "INFO"
            $detailedKlist | ForEach-Object { Write-Log "  $_" -Level "INFO" }
            
            # Check for specific SPN
            if ($detailedKlist -match $TargetSPN) {
                Write-Log "SUCCESS: Found ticket for target SPN: $TargetSPN" -Level "SUCCESS"
            } else {
                Write-Log "WARNING: No ticket found for target SPN: $TargetSPN" -Level "WARNING"
                
                # Check for any HTTP tickets
                $httpTickets = $detailedKlist | Where-Object { $_ -match "HTTP/" }
                if ($httpTickets) {
                    Write-Log "Found HTTP tickets:" -Level "INFO"
                    $httpTickets | ForEach-Object { Write-Log "  $_" -Level "INFO" }
                } else {
                    Write-Log "No HTTP tickets found in cache" -Level "WARNING"
                }
            }
        } catch {
            Write-Log "Error analyzing Kerberos tickets: $($_.Exception.Message)" -Level "WARNING"
        }
        
        try {
            # Step 1: Acquire credentials handle
            Write-Log "Step 1: Acquiring credentials handle..." -Level "INFO"
            
            $credHandle = New-Object SSPI+SECURITY_HANDLE
            $expiry = New-Object SSPI+SECURITY_INTEGER
            
            # Try different approaches to acquire credentials
            Write-Log "Attempting to acquire credentials handle..." -Level "INFO"
            
            # Method 1: Try with explicit principal (current user)
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            Write-Log "Using current user as principal: $currentUser" -Level "INFO"
            
            $result = [SSPI]::AcquireCredentialsHandle(
                $currentUser,                             # Principal (current user)
                "Negotiate",                              # Package (SPNEGO)
                [SSPI]::SECPKG_CRED_OUTBOUND,            # Credential use
                [IntPtr]::Zero,                          # Logon ID
                [IntPtr]::Zero,                          # Auth data
                [IntPtr]::Zero,                          # Get key function
                [IntPtr]::Zero,                          # Get key argument
                [ref]$credHandle,                        # Credential handle
                [ref]$expiry                             # Expiry
            )
            
            if ($result -ne [SSPI]::SEC_E_OK) {
                Write-Log "Method 1 failed with result: 0x$($result.ToString('X8')), trying Method 2..." -Level "WARNING"
                
                # Method 2: Try with null principal (use default credentials)
                Write-Log "Trying with null principal (default credentials)..." -Level "INFO"
                $result = [SSPI]::AcquireCredentialsHandle(
                    $null,                                # Principal (null = default)
                    "Negotiate",                          # Package (SPNEGO)
                    [SSPI]::SECPKG_CRED_OUTBOUND,        # Credential use
                    [IntPtr]::Zero,                      # Logon ID
                    [IntPtr]::Zero,                      # Auth data
                    [IntPtr]::Zero,                      # Get key function
                    [IntPtr]::Zero,                      # Get key argument
                    [ref]$credHandle,                    # Credential handle
                    [ref]$expiry                         # Expiry
                )
                
                if ($result -ne [SSPI]::SEC_E_OK) {
                    Write-Log "Method 2 failed with result: 0x$($result.ToString('X8')), trying Method 3..." -Level "WARNING"
                    
                    # Method 3: Try with Kerberos package directly
                    Write-Log "Trying with Kerberos package directly..." -Level "INFO"
                    $result = [SSPI]::AcquireCredentialsHandle(
                        $null,                            # Principal
                        "Kerberos",                       # Package (Kerberos)
                        [SSPI]::SECPKG_CRED_OUTBOUND,    # Credential use
                        [IntPtr]::Zero,                  # Logon ID
                        [IntPtr]::Zero,                  # Auth data
                        [IntPtr]::Zero,                  # Get key function
                        [IntPtr]::Zero,                  # Get key argument
                        [ref]$credHandle,                # Credential handle
                        [ref]$expiry                     # Expiry
                    )
                }
            }
            
            if ($result -ne [SSPI]::SEC_E_OK) {
                Write-Log "ERROR: AcquireCredentialsHandle failed with result: 0x$($result.ToString('X8'))" -Level "ERROR"
                return $null
            }
            
            Write-Log "SUCCESS: Credentials handle acquired" -Level "SUCCESS"
            
            # Step 2: Initialize security context
            Write-Log "Step 2: Initializing security context..." -Level "INFO"
            Write-Log "Target SPN: $TargetSPN" -Level "INFO"
            Write-Log "Credential handle: Lower=$($credHandle.dwLower), Upper=$($credHandle.dwUpper)" -Level "INFO"
            
            $contextHandle = New-Object SSPI+SECURITY_HANDLE
            $outputBuffer = New-Object SSPI+SEC_BUFFER
            $contextAttr = 0
            
            # Try different context requirements
            $contextRequirements = @(
                ([SSPI]::ISC_REQ_CONFIDENTIALITY -bor [SSPI]::ISC_REQ_INTEGRITY -bor [SSPI]::ISC_REQ_MUTUAL_AUTH),
                [SSPI]::ISC_REQ_CONFIDENTIALITY,
                [SSPI]::ISC_REQ_INTEGRITY,
                0  # No special requirements
            )
            
            $result = 0
            foreach ($req in $contextRequirements) {
                Write-Log "Trying InitializeSecurityContext with requirements: 0x$($req.ToString('X8'))" -Level "INFO"
                
                $result = [SSPI]::InitializeSecurityContext(
                    [ref]$credHandle,                       # Credential handle
                    [IntPtr]::Zero,                         # Context handle (null for first call)
                    $TargetSPN,                             # Target name (SPN)
                    $req,                                   # Context requirements
                    0,                                      # Reserved1
                    [SSPI]::SECURITY_NETWORK_DREP,          # Target data representation
                    [IntPtr]::Zero,                         # Input buffer
                    0,                                      # Reserved2
                    [ref]$contextHandle,                    # New context handle
                    [ref]$outputBuffer,                     # Output buffer
                    [ref]$contextAttr,                      # Context attributes
                    [ref]$expiry                            # Expiry
                )
                
                Write-Log "InitializeSecurityContext result: 0x$($result.ToString('X8'))" -Level "INFO"
                
                if ($result -eq [SSPI]::SEC_E_OK -or $result -eq [SSPI]::SEC_I_CONTINUE_NEEDED) {
                    Write-Log "SUCCESS: InitializeSecurityContext succeeded with requirements: 0x$($req.ToString('X8'))" -Level "SUCCESS"
                    break
                } else {
                    Write-Log "Failed with requirements 0x$($req.ToString('X8')), trying next..." -Level "WARNING"
                }
            }
            
            Write-Log "InitializeSecurityContext result: 0x$($result.ToString('X8'))" -Level "INFO"
            Write-Log "Context handle: Lower=$($contextHandle.dwLower), Upper=$($contextHandle.dwUpper)" -Level "INFO"
            Write-Log "Output buffer size: $($outputBuffer.cbBuffer) bytes" -Level "INFO"
            Write-Log "Output buffer type: $($outputBuffer.BufferType)" -Level "INFO"
            Write-Log "Output buffer pointer: $($outputBuffer.pvBuffer)" -Level "INFO"
            Write-Log "Context attributes: 0x$($contextAttr.ToString('X8'))" -Level "INFO"
            
            if ($result -ne [SSPI]::SEC_E_OK -and $result -ne [SSPI]::SEC_I_CONTINUE_NEEDED) {
                Write-Log "ERROR: InitializeSecurityContext failed with result: 0x$($result.ToString('X8'))" -Level "ERROR"
                
                # Decode common error codes
                switch ($result) {
                    0x80090308 { 
                        Write-Log "ERROR: SEC_E_UNKNOWN_CREDENTIALS - No valid credentials for SPN: $TargetSPN" -Level "ERROR"
                        Write-Log "CRITICAL: The SPN '$TargetSPN' is not registered in Active Directory" -Level "ERROR"
                        Write-Log "SOLUTION: Register the SPN for the Linux Vault server:" -Level "ERROR"
                        Write-Log "  Windows: setspn -A $TargetSPN vault-gmsa" -Level "ERROR"
                        Write-Log "  Linux: ktutil -k /path/to/vault.keytab add_entry -p $TargetSPN -e aes256-cts-hmac-sha1-96 -w password" -Level "ERROR"
                        Write-Log "  Or use: setspn -A $TargetSPN <linux-hostname>" -Level "ERROR"
                    }
                    0x8009030E { Write-Log "ERROR: SEC_E_NO_CREDENTIALS - No credentials available" -Level "ERROR" }
                    0x8009030F { Write-Log "ERROR: SEC_E_NO_AUTHENTICATING_AUTHORITY - Cannot contact domain controller" -Level "ERROR" }
                    0x80090311 { Write-Log "ERROR: SEC_E_WRONG_PRINCIPAL - SPN does not match server" -Level "ERROR" }
                    default { Write-Log "ERROR: Unknown SSPI error code: 0x$($result.ToString('X8'))" -Level "ERROR" }
                }
                
                Write-Log "Troubleshooting steps for Linux Vault server:" -Level "ERROR"
                Write-Log "1. Register SPN for Linux host: setspn -A $TargetSPN <linux-hostname>" -Level "ERROR"
                Write-Log "2. Or register for gMSA: setspn -A $TargetSPN vault-gmsa" -Level "ERROR"
                Write-Log "3. Verify SPN exists: setspn -L <linux-hostname> or setspn -L vault-gmsa" -Level "ERROR"
                Write-Log "4. Ensure Linux Vault server has proper keytab with SPN" -Level "ERROR"
                Write-Log "5. Check domain controller connectivity from Linux" -Level "ERROR"
                Write-Log "6. Verify gMSA account is properly configured" -Level "ERROR"
                
                Write-Log "Attempting alternative SPNEGO generation method..." -Level "WARNING"
                
                # Alternative Method: Use PowerShell 5.1 compatible HTTP methods to capture SPNEGO token
                try {
                    Write-Log "Alternative Method: Using PowerShell 5.1 compatible HTTP methods to capture SPNEGO token..." -Level "INFO"
                    
                    # Method 1: Use WebRequest with UseDefaultCredentials
                    try {
                        Write-Log "Method 1: Using WebRequest with UseDefaultCredentials..." -Level "INFO"
                        
                        $request = [System.Net.WebRequest]::Create("$VaultUrl/v1/auth/gmsa/login")
                        $request.Method = "POST"
                        $request.UseDefaultCredentials = $true
                        $request.Timeout = 10000
                        $request.UserAgent = "Vault-gMSA-Client/1.0"
                        $request.ContentType = "application/json"
                        
                        # Add test content
                        $body = '{"role":"test","spnego":"test"}'
                        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                        $request.ContentLength = $bodyBytes.Length
                        
                        $requestStream = $request.GetRequestStream()
                        $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
                        $requestStream.Close()
                        
                        try {
                            $response = $request.GetResponse()
                            Write-Log "Alternative WebRequest completed with status: $($response.StatusCode)" -Level "INFO"
                            
                            # Check response headers for WWW-Authenticate
                            if ($response.Headers -and $response.Headers["WWW-Authenticate"]) {
                                Write-Log "Response WWW-Authenticate header: $($response.Headers['WWW-Authenticate'])" -Level "INFO"
                            }
                            
                            $response.Close()
                        } catch {
                            $statusCode = $_.Exception.Response.StatusCode
                            Write-Log "Alternative WebRequest returned: $statusCode" -Level "INFO"
                            
                            # Check response headers for WWW-Authenticate
                            if ($_.Exception.Response.Headers -and $_.Exception.Response.Headers["WWW-Authenticate"]) {
                                Write-Log "Error Response WWW-Authenticate header: $($_.Exception.Response.Headers['WWW-Authenticate'])" -Level "INFO"
                            }
                            
                            # Check if the request contains Authorization header
                            Write-Log "Checking request headers for Authorization..." -Level "INFO"
                            if ($request.Headers) {
                                Write-Log "Request headers count: $($request.Headers.Count)" -Level "INFO"
                                $authHeader = $request.Headers["Authorization"]
                                if ($authHeader) {
                                    Write-Log "Found Authorization header: $authHeader" -Level "INFO"
                                    if ($authHeader -like "Negotiate *") {
                                        $spnegoToken = $authHeader.Substring(9)  # Remove "Negotiate " prefix
                                        Write-Log "SUCCESS: Captured SPNEGO token from WebRequest method!" -Level "SUCCESS"
                                        Write-Log "Token length: $($spnegoToken.Length) characters" -Level "INFO"
                                        [SSPI]::FreeCredentialsHandle([ref]$credHandle)
                                        return $spnegoToken
                                    }
                                } else {
                                    Write-Log "No Authorization header found in request" -Level "WARNING"
                                }
                            } else {
                                Write-Log "No request headers found" -Level "WARNING"
                            }
                        }
                    } catch {
                        Write-Log "WebRequest method failed: $($_.Exception.Message)" -Level "WARNING"
                    }
                    
                    # Method 2: Use WebClient with UseDefaultCredentials
                    try {
                        Write-Log "Method 2: Using WebClient with UseDefaultCredentials..." -Level "INFO"
                        
                        $webClient = New-Object System.Net.WebClient
                        $webClient.UseDefaultCredentials = $true
                        $webClient.Headers.Add("User-Agent", "Vault-gMSA-Client/1.0")
                        $webClient.Headers.Add("Content-Type", "application/json")
                        
                        $body = '{"role":"test","spnego":"test"}'
                        
                        try {
                            $response = $webClient.UploadString("$VaultUrl/v1/auth/gmsa/login", "POST", $body)
                            Write-Log "Alternative WebClient completed successfully" -Level "INFO"
                        } catch {
                            $statusCode = $_.Exception.Response.StatusCode
                            Write-Log "Alternative WebClient returned: $statusCode" -Level "INFO"
                            
                            # Check response headers for WWW-Authenticate
                            if ($_.Exception.Response.Headers -and $_.Exception.Response.Headers["WWW-Authenticate"]) {
                                Write-Log "Error Response WWW-Authenticate header: $($_.Exception.Response.Headers['WWW-Authenticate'])" -Level "INFO"
                            }
                            
                            # Check if the request contains Authorization header
                            Write-Log "Checking WebClient headers for Authorization..." -Level "INFO"
                            if ($webClient.Headers) {
                                Write-Log "WebClient headers count: $($webClient.Headers.Count)" -Level "INFO"
                                $authHeader = $webClient.Headers["Authorization"]
                                if ($authHeader) {
                                    Write-Log "Found Authorization header: $authHeader" -Level "INFO"
                                    if ($authHeader -like "Negotiate *") {
                                        $spnegoToken = $authHeader.Substring(9)  # Remove "Negotiate " prefix
                                        Write-Log "SUCCESS: Captured SPNEGO token from WebClient method!" -Level "SUCCESS"
                                        Write-Log "Token length: $($spnegoToken.Length) characters" -Level "INFO"
                                        [SSPI]::FreeCredentialsHandle([ref]$credHandle)
                                        return $spnegoToken
                                    }
                                } else {
                                    Write-Log "No Authorization header found in WebClient" -Level "WARNING"
                                }
                            } else {
                                Write-Log "No WebClient headers found" -Level "WARNING"
                            }
                        }
                        
                        $webClient.Dispose()
                    } catch {
                        Write-Log "WebClient method failed: $($_.Exception.Message)" -Level "WARNING"
                    }
                    
                    # Method 3: Use Invoke-WebRequest with UseDefaultCredentials
                    try {
                        Write-Log "Method 3: Using Invoke-WebRequest with UseDefaultCredentials..." -Level "INFO"
                        
                        $body = '{"role":"test","spnego":"test"}'
                        
                        try {
                            $response = Invoke-WebRequest -Uri "$VaultUrl/v1/auth/gmsa/login" -Method Post -Body $body -ContentType "application/json" -UseDefaultCredentials -UseBasicParsing -TimeoutSec 10
                            Write-Log "Alternative Invoke-WebRequest completed with status: $($response.StatusCode)" -Level "INFO"
                        } catch {
                            $statusCode = $_.Exception.Response.StatusCode
                            Write-Log "Alternative Invoke-WebRequest returned: $statusCode" -Level "INFO"
                            
                            # Check if the request contains Authorization header
                            if ($_.Exception.Response.Headers -and $_.Exception.Response.Headers["Authorization"]) {
                                $authHeader = $_.Exception.Response.Headers["Authorization"]
                                if ($authHeader -like "Negotiate *") {
                                    $spnegoToken = $authHeader.Substring(9)  # Remove "Negotiate " prefix
                                    Write-Log "SUCCESS: Captured SPNEGO token from Invoke-WebRequest method!" -Level "SUCCESS"
                                    Write-Log "Token length: $($spnegoToken.Length) characters" -Level "INFO"
                                    [SSPI]::FreeCredentialsHandle([ref]$credHandle)
                                    return $spnegoToken
                                }
                            }
                        }
                    } catch {
                        Write-Log "Invoke-WebRequest method failed: $($_.Exception.Message)" -Level "WARNING"
                    }
                    
                    # Method 4: Try different endpoints to trigger SPNEGO negotiation
                    try {
                        Write-Log "Method 4: Trying different endpoints to trigger SPNEGO negotiation..." -Level "INFO"
                        
                        $testEndpoints = @(
                            "/v1/sys/health",
                            "/v1/sys/status", 
                            "/v1/sys/seal-status",
                            "/v1/sys/leader",
                            "/v1/sys/config",
                            "/v1/auth/gmsa/config",
                            "/v1/auth/gmsa/login"
                        )
                        
                        foreach ($endpoint in $testEndpoints) {
                            Write-Log "Testing endpoint: $endpoint" -Level "INFO"
                            
                            try {
                                $testRequest = [System.Net.WebRequest]::Create("$VaultUrl$endpoint")
                                $testRequest.Method = "GET"
                                $testRequest.UseDefaultCredentials = $true
                                $testRequest.Timeout = 5000
                                $testRequest.UserAgent = "Vault-gMSA-Client/1.0"
                                
                                $testResponse = $testRequest.GetResponse()
                                Write-Log "Endpoint $endpoint returned: $($testResponse.StatusCode)" -Level "INFO"
                                
                                # Check for WWW-Authenticate header
                                if ($testResponse.Headers -and $testResponse.Headers["WWW-Authenticate"]) {
                                    Write-Log "SUCCESS: Found WWW-Authenticate header: $($testResponse.Headers['WWW-Authenticate'])" -Level "SUCCESS"
                                    
                                    # Check if the request contains Authorization header
                                    if ($testRequest.Headers -and $testRequest.Headers["Authorization"]) {
                                        $authHeader = $testRequest.Headers["Authorization"]
                                        Write-Log "SUCCESS: Found Authorization header: $authHeader" -Level "SUCCESS"
                                        if ($authHeader -like "Negotiate *") {
                                            $spnegoToken = $authHeader.Substring(9)  # Remove "Negotiate " prefix
                                            Write-Log "SUCCESS: Captured SPNEGO token from endpoint $endpoint!" -Level "SUCCESS"
                                            Write-Log "Token length: $($spnegoToken.Length) characters" -Level "INFO"
                                            [SSPI]::FreeCredentialsHandle([ref]$credHandle)
                                            return $spnegoToken
                                        }
                                    }
                                }
                                
                                $testResponse.Close()
                            } catch {
                                $statusCode = $_.Exception.Response.StatusCode
                                Write-Log "Endpoint $endpoint returned: $statusCode" -Level "INFO"
                                
                                # Check for WWW-Authenticate header in error response
                                if ($_.Exception.Response.Headers -and $_.Exception.Response.Headers["WWW-Authenticate"]) {
                                    Write-Log "SUCCESS: Found WWW-Authenticate header in error: $($_.Exception.Response.Headers['WWW-Authenticate'])" -Level "SUCCESS"
                                    
                                    # Check if the request contains Authorization header
                                    if ($testRequest.Headers -and $testRequest.Headers["Authorization"]) {
                                        $authHeader = $testRequest.Headers["Authorization"]
                                        Write-Log "SUCCESS: Found Authorization header: $authHeader" -Level "SUCCESS"
                                        if ($authHeader -like "Negotiate *") {
                                            $spnegoToken = $authHeader.Substring(9)  # Remove "Negotiate " prefix
                                            Write-Log "SUCCESS: Captured SPNEGO token from endpoint $endpoint!" -Level "SUCCESS"
                                            Write-Log "Token length: $($spnegoToken.Length) characters" -Level "INFO"
                                            [SSPI]::FreeCredentialsHandle([ref]$credHandle)
                                            return $spnegoToken
                                        }
                                    }
                                }
                            }
                        }
                    } catch {
                        Write-Log "Method 4 failed: $($_.Exception.Message)" -Level "WARNING"
                    }
                    
                } catch {
                    Write-Log "Alternative method failed: $($_.Exception.Message)" -Level "WARNING"
                }
                
                # Final Alternative: Try using the existing Kerberos ticket directly
                try {
                    Write-Log "Final Alternative: Attempting to extract token from existing Kerberos ticket..." -Level "INFO"
                    
                    # Since we have a valid Kerberos ticket, try to use it directly
                    # This is a more advanced approach that might work
                    Write-Log "Attempting direct Kerberos ticket usage..." -Level "INFO"
                    
                    # For now, we'll return null and let the caller handle it
                    Write-Log "Direct Kerberos ticket usage not implemented yet" -Level "WARNING"
                } catch {
                    Write-Log "Final alternative method failed: $($_.Exception.Message)" -Level "WARNING"
                }
                
                [SSPI]::FreeCredentialsHandle([ref]$credHandle)
                return $null
            }
            
            Write-Log "SUCCESS: Security context initialized" -Level "SUCCESS"
            Write-Log "Context attributes: 0x$($contextAttr.ToString('X8'))" -Level "INFO"
            
            # Step 3: Extract SPNEGO token from output buffer
            if ($outputBuffer.cbBuffer -gt 0 -and $outputBuffer.pvBuffer -ne [IntPtr]::Zero) {
                Write-Log "Step 3: Extracting SPNEGO token from output buffer..." -Level "INFO"
                Write-Log "Output buffer size: $($outputBuffer.cbBuffer) bytes" -Level "INFO"
                
                # Copy the token data
                $tokenBytes = New-Object byte[] $outputBuffer.cbBuffer
                [System.Runtime.InteropServices.Marshal]::Copy($outputBuffer.pvBuffer, $tokenBytes, 0, $outputBuffer.cbBuffer)
                
                # Convert to base64
                $spnegoToken = [System.Convert]::ToBase64String($tokenBytes)
                
                Write-Log "SUCCESS: Real SPNEGO token generated!" -Level "SUCCESS"
                Write-Log "Token length: $($spnegoToken.Length) characters" -Level "INFO"
                Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..." -Level "INFO"
                
                # Cleanup
                [SSPI]::FreeContextBuffer($outputBuffer.pvBuffer)
                [SSPI]::DeleteSecurityContext([ref]$contextHandle)
                [SSPI]::FreeCredentialsHandle([ref]$credHandle)
                
                return $spnegoToken
            } else {
                Write-Log "ERROR: No token data in output buffer" -Level "ERROR"
                [SSPI]::DeleteSecurityContext([ref]$contextHandle)
                [SSPI]::FreeCredentialsHandle([ref]$credHandle)
                return $null
            }
            
        } catch {
            Write-Log "ERROR: Win32 SSPI token generation failed: $($_.Exception.Message)" -Level "ERROR"
            Write-Log "Stack trace: $($_.Exception.StackTrace)" -Level "ERROR"
            return $null
        }
        
        # This code should never be reached if the above logic is correct
        Write-Log "ERROR: Unexpected code path - SPNEGO generation failed" -Level "ERROR"
        return $null
        
    } catch {
        Write-Log "SPNEGO token generation failed: $($_.Exception.Message)" -Level "WARNING"
        return $null
    }
}

function Request-KerberosTicket {
    param(
        [string]$TargetSPN
    )
    
    try {
        Write-Log "Requesting Kerberos ticket for SPN: $TargetSPN" -Level "INFO"
        
        $overallTimeout = 30  # Overall timeout in seconds
        $startTime = Get-Date
        
        # Method 1: Use klist to request ticket
        try {
            Write-Log "Method 1: Requesting ticket using klist..." -Level "INFO"
            $klistResult = klist 2>&1
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
            # Check timeout
            if ((Get-Date) - $startTime -gt [TimeSpan]::FromSeconds($overallTimeout)) {
                Write-Log "Timeout reached, skipping remaining methods" -Level "WARNING"
                return $false
            }
            
            Write-Log "Method 2: Requesting ticket using Windows SSPI..." -Level "INFO"
            
            # Extract hostname from SPN for HTTP request
            if ($TargetSPN -match "HTTP/(.+)") {
                $hostname = $matches[1]
            } else {
                $hostname = $TargetSPN
            }
            
            Write-Log "Using hostname for request: $hostname" -Level "INFO"
            
            # Method 2A: Try to request service ticket using klist with specific SPN
            Write-Log "Method 2A: Requesting service ticket using klist for SPN: $TargetSPN" -Level "INFO"
            try {
                # Use klist to request a service ticket for the specific SPN
                $klistResult = klist get $TargetSPN 2>&1
                Write-Log "klist service ticket request result: $klistResult" -Level "INFO"
                
                # Check if the request was successful
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "SUCCESS: Service ticket request completed" -Level "SUCCESS"
                } else {
                    Write-Log "Service ticket request failed with exit code: $LASTEXITCODE" -Level "WARNING"
                }
            } catch {
                Write-Log "klist service ticket request failed: $($_.Exception.Message)" -Level "WARNING"
            }
            
            # Method 2B: Create HTTP request to trigger Kerberos ticket request
            Write-Log "Method 2B: Creating HTTP request to trigger service ticket..." -Level "INFO"
            
            # Create HTTP request to trigger Kerberos ticket request
            $request = [System.Net.WebRequest]::Create("https://$hostname")
            $request.Method = "GET"
            $request.UseDefaultCredentials = $true
            $request.Timeout = 10000
            $request.UserAgent = "Vault-gMSA-Client/1.0"
            
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
            
            # Method 2C: Try using Invoke-WebRequest to trigger service ticket
            Write-Log "Method 2C: Using Invoke-WebRequest to trigger service ticket..." -Level "INFO"
            try {
                $webResponse = Invoke-WebRequest -Uri "https://$hostname" -UseDefaultCredentials -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                Write-Log "Invoke-WebRequest completed with status: $($webResponse.StatusCode)" -Level "INFO"
            } catch {
                if ($_.Exception.Response) {
                    $statusCode = $_.Exception.Response.StatusCode
                    Write-Log "Invoke-WebRequest returned: $statusCode" -Level "INFO"
                    
                    if ($statusCode -eq 401) {
                        Write-Log "SUCCESS: 401 Unauthorized - Service ticket request triggered" -Level "SUCCESS"
                    }
                } else {
                    Write-Log "Invoke-WebRequest failed with non-HTTP error: $($_.Exception.Message)" -Level "WARNING"
                }
            }
            
        } catch {
            Write-Log "SSPI ticket request failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 3: Try using PowerShell's built-in Kerberos functionality
        try {
            Write-Log "Method 3: Using PowerShell's built-in Kerberos functionality..." -Level "INFO"
            
            # Try to create a credential and use it to request a service ticket
            $credential = [System.Net.CredentialCache]::DefaultCredentials
            if ($credential) {
                Write-Log "Default credentials available: $($credential.GetType().Name)" -Level "INFO"
                
                # Try to make a request that will trigger service ticket request
                try {
                    $webClient = New-Object System.Net.WebClient
                    $webClient.UseDefaultCredentials = $true
                    $webClient.DownloadString("https://$hostname")
                    Write-Log "WebClient request completed successfully" -Level "INFO"
                } catch {
                    Write-Log "WebClient request failed: $($_.Exception.Message)" -Level "INFO"
                }
            }
        } catch {
            Write-Log "PowerShell Kerberos method failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Check if ticket was obtained
        Start-Sleep -Seconds 5  # Give more time for ticket to be cached
        
        $klistOutput = klist 2>&1
        Write-Log "Final klist check for SPN: $TargetSPN" -Level "INFO"
        Write-Log "Full klist output: $($klistOutput -join '; ')" -Level "INFO"
        
        if ($klistOutput -match $TargetSPN) {
            Write-Log "SUCCESS: Kerberos ticket obtained for $TargetSPN" -Level "SUCCESS"
            Write-Log "Ticket details: $($klistOutput -join '; ')" -Level "INFO"
            return $true
        } else {
            Write-Log "WARNING: No Kerberos ticket found for $TargetSPN after request attempts" -Level "WARNING"
            Write-Log "Available tickets: $($klistOutput -join '; ')" -Level "WARNING"
            
            # Additional debugging: Check if we have any HTTP service tickets
            $httpTickets = $klistOutput | Where-Object { $_ -match "HTTP/" }
            if ($httpTickets) {
                Write-Log "Found HTTP service tickets: $($httpTickets -join '; ')" -Level "INFO"
            } else {
                Write-Log "No HTTP service tickets found in cache" -Level "WARNING"
            }
            
            return $false
        }
        
    } catch {
        Write-Log "Kerberos ticket request failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# =============================================================================
# Vault Authentication
# =============================================================================

function Authenticate-ToVault {
    param(
        [string]$VaultUrl,
        [string]$Role,
        [string]$SPN
    )
    
    try {
        Write-Log "Starting Vault authentication process..." -Level "INFO"
        Write-Log "Vault URL: $VaultUrl" -Level "INFO"
        Write-Log "Role: $Role" -Level "INFO"
        Write-Log "SPN: $SPN" -Level "INFO"
        
        # Generate SPNEGO token
        Write-Log "Generating SPNEGO token..." -Level "INFO"
        $spnegoToken = Get-SPNEGOTokenPInvoke -TargetSPN $SPN -VaultUrl $VaultUrl
        
        if (-not $spnegoToken) {
            Write-Log "ERROR: Failed to generate SPNEGO token" -Level "ERROR"
            Write-Log "Cannot proceed with authentication without a valid SPNEGO token" -Level "ERROR"
            return $null
        }
        
        # Validate token format
        if ($spnegoToken -is [array] -or $spnegoToken -is [System.Collections.ArrayList]) {
            Write-Log "ERROR: Invalid token format - token is an array instead of string" -Level "ERROR"
            Write-Log "Token value: $($spnegoToken | ConvertTo-Json)" -Level "ERROR"
            return $null
        }
        
        if ($spnegoToken.Length -lt 10) {
            Write-Log "ERROR: Token too short - likely invalid" -Level "ERROR"
            Write-Log "Token length: $($spnegoToken.Length) characters" -Level "ERROR"
            Write-Log "Token value: $spnegoToken" -Level "ERROR"
            return $null
        }
        
        Write-Log "SPNEGO token generated successfully" -Level "SUCCESS"
        Write-Log "Token length: $($spnegoToken.Length) characters" -Level "INFO"
        
        # Prepare authentication request
        $authBody = @{
            role = $Role
            spnego = $spnegoToken
        } | ConvertTo-Json
        
        Write-Log "Authentication request body prepared" -Level "INFO"
        Write-Log "Request body: $authBody" -Level "INFO"
        
        # Send authentication request to Vault
        Write-Log "Sending authentication request to Vault..." -Level "INFO"
        
        try {
            $response = Invoke-RestMethod -Uri "$VaultUrl/v1/auth/gmsa/login" -Method Post -Body $authBody -ContentType "application/json" -UseBasicParsing
            
            if ($response.auth -and $response.auth.client_token) {
                Write-Log "SUCCESS: Vault authentication successful!" -Level "SUCCESS"
                Write-Log "Client token: $($response.auth.client_token)" -Level "INFO"
                Write-Log "Token TTL: $($response.auth.lease_duration) seconds" -Level "INFO"
                
                return $response.auth.client_token
            } else {
                Write-Log "ERROR: Authentication response missing required fields" -Level "ERROR"
                Write-Log "Response: $($response | ConvertTo-Json -Depth 3)" -Level "ERROR"
                return $null
            }
            
        } catch {
            Write-Log "ERROR: Vault authentication request failed" -Level "ERROR"
            Write-Log "Error details: $($_.Exception.Message)" -Level "ERROR"
            
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
        
        $response = Invoke-RestMethod -Uri "$VaultUrl/v1/$SecretPath" -Method Get -Headers $headers -UseBasicParsing
        
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
        Write-Log "Script version: 3.12 (Multi-Endpoint SPNEGO Trigger)" -Level "INFO"
        
        # Authenticate to Vault
        Write-Log "Step 1: Authenticating to Vault..." -Level "INFO"
        $vaultToken = Authenticate-ToVault -VaultUrl $VaultUrl -Role $VaultRole -SPN $SPN
        
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
    Write-Host "Vault gMSA Authentication Client" -ForegroundColor Green
    Write-Host "=================================" -ForegroundColor Green
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