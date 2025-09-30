#Requires -Version 5.1

<#
.SYNOPSIS
    Real SPNEGO Token Generator using Windows SSPI
.DESCRIPTION
    Generates real SPNEGO tokens using Windows SSPI for Vault gMSA authentication.
    Uses InitializeSecurityContext Win32 API to establish proper security context.
.PARAMETER VaultUrl
    Vault server URL (default: https://vault.local.lab:8200)
.PARAMETER Role
    Vault role name (default: vault-gmsa-role)
.PARAMETER SPN
    Service Principal Name (default: HTTP/vault.local.lab)
.EXAMPLE
    .\real-spnego-generator.ps1
.EXAMPLE
    .\real-spnego-generator.ps1 -VaultUrl "https://vault.example.com:8200" -Role "my-role" -SPN "HTTP/vault.example.com"
#>

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$Role = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab"
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

    [StructLayout(LayoutKind.Sequential)]
    public struct SEC_BUFFER_DESC
    {
        public int ulVersion;
        public int cBuffers;
        public IntPtr pBuffers;
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

public class KerberosTicket
{
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
    public static extern bool LogonUser(
        string lpszUsername,
        string lpszDomain,
        string lpszPassword,
        int dwLogonType,
        int dwLogonProvider,
        ref IntPtr phToken
    );

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);

    public const int LOGON32_LOGON_NETWORK = 3;
    public const int LOGON32_PROVIDER_DEFAULT = 0;
}
"@

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

function New-SPNEGOToken {
    param(
        [string]$TargetSPN,
        [string]$VaultUrl
    )
    
    Write-Log "Generating real SPNEGO token using Windows SSPI..." -Level "INFO"
    Write-Log "Target SPN: $TargetSPN" -Level "INFO"
    
    try {
        # Step 1: Acquire credentials handle
        Write-Log "Step 1: Acquiring credentials handle..." -Level "INFO"
        
        $credHandle = New-Object SSPI+SECURITY_HANDLE
        $expiry = New-Object SSPI+SECURITY_INTEGER
        
        $result = [SSPI]::AcquireCredentialsHandle(
            $null,                                    # Principal
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
            Write-Log "ERROR: AcquireCredentialsHandle failed with result: 0x$($result.ToString('X8'))" -Level "ERROR"
            return $null
        }
        
        Write-Log "SUCCESS: Credentials handle acquired" -Level "SUCCESS"
        
        # Step 2: Initialize security context
        Write-Log "Step 2: Initializing security context..." -Level "INFO"
        
        $contextHandle = New-Object SSPI+SECURITY_HANDLE
        $outputBuffer = New-Object SSPI+SEC_BUFFER
        $contextAttr = 0
        
        $result = [SSPI]::InitializeSecurityContext(
            [ref]$credHandle,                       # Credential handle
            [IntPtr]::Zero,                         # Context handle (null for first call)
            $TargetSPN,                             # Target name (SPN)
            [SSPI]::ISC_REQ_CONFIDENTIALITY -bor [SSPI]::ISC_REQ_INTEGRITY -bor [SSPI]::ISC_REQ_MUTUAL_AUTH,  # Context requirements
            0,                                      # Reserved1
            [SSPI]::SECURITY_NETWORK_DREP,          # Target data representation
            [IntPtr]::Zero,                         # Input buffer
            0,                                      # Reserved2
            [ref]$contextHandle,                    # New context handle
            [ref]$outputBuffer,                     # Output buffer
            [ref]$contextAttr,                      # Context attributes
            [ref]$expiry                            # Expiry
        )
        
        if ($result -ne [SSPI]::SEC_E_OK -and $result -ne [SSPI]::SEC_I_CONTINUE_NEEDED) {
            Write-Log "ERROR: InitializeSecurityContext failed with result: 0x$($result.ToString('X8'))" -Level "ERROR"
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
    Write-Log "=== Real SPNEGO Token Generator Started ===" -Level "INFO"
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
    
    # Step 3: Generate real SPNEGO token
    Write-Log "Generating real SPNEGO token..." -Level "INFO"
    $spnegoToken = New-SPNEGOToken -TargetSPN $SPN -VaultUrl $VaultUrl
    
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
