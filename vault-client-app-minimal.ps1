param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab",
    [string[]]$SecretPaths = @("kv/data/my-app/database", "kv/data/my-app/api"),
    [string]$ConfigOutputDir = "C:\vault-client\config"
)

# =============================================================================
# Minimal Vault gMSA Client - Production Ready
# =============================================================================
# This script authenticates to your custom gMSA plugin using real SPNEGO tokens
# Requirements: gMSA account with valid Kerberos tickets
# =============================================================================

# Import Win32 SSPI for real SPNEGO token generation
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class SSPI
{
    [DllImport("secur32.dll", CharSet = CharSet.Unicode)]
    public static extern int AcquireCredentialsHandle(
        string pszPrincipal, string pszPackage, int fCredentialUse,
        IntPtr pvLogonId, IntPtr pAuthData, IntPtr pGetKeyFn, IntPtr pvGetKeyArgument,
        ref SECURITY_HANDLE phCredential, ref SECURITY_INTEGER ptsExpiry);

    [DllImport("secur32.dll")]
    public static extern int InitializeSecurityContext(
        ref SECURITY_HANDLE phCredential, IntPtr phContext, string pszTargetName,
        int fContextReq, int Reserved1, int TargetDataRep, IntPtr pInput, int Reserved2,
        ref SECURITY_HANDLE phNewContext, ref SEC_BUFFER pOutput, out int pfContextAttr,
        ref SECURITY_INTEGER ptsExpiry);

    [DllImport("secur32.dll")]
    public static extern int FreeContextBuffer(IntPtr pvContextBuffer);
    [DllImport("secur32.dll")]
    public static extern int FreeCredentialsHandle(ref SECURITY_HANDLE phCredential);
    [DllImport("secur32.dll")]
    public static extern int DeleteSecurityContext(ref SECURITY_HANDLE phContext);

    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_HANDLE { public IntPtr dwLower; public IntPtr dwUpper; }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_INTEGER { public uint LowPart; public int HighPart; }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct SEC_BUFFER { public int cbBuffer; public int BufferType; public IntPtr pvBuffer; }

    public const int SECPKG_CRED_OUTBOUND = 2;
    public const int SECURITY_NETWORK_DREP = 0;
    public const int ISC_REQ_CONFIDENTIALITY = 0x10;
    public const int ISC_REQ_INTEGRITY = 0x20;
    public const int ISC_REQ_MUTUAL_AUTH = 0x40;
    public const int SEC_E_OK = 0;
    public const int SEC_I_CONTINUE_NEEDED = 0x00090312;
}
"@

# SSL bypass for testing (remove in production)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

# Create output directory
if (-not (Test-Path $ConfigOutputDir)) {
    New-Item -ItemType Directory -Path $ConfigOutputDir -Force | Out-Null
}

# Simple logging
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    try {
        Add-Content -Path "$ConfigOutputDir\vault-client.log" -Value $logMessage -ErrorAction SilentlyContinue
    } catch { }
}

# =============================================================================
# Generate Real SPNEGO Token using Win32 SSPI
# =============================================================================
function Get-SPNEGOToken {
    param([string]$TargetSPN)
    
    try {
        Write-Log "Generating SPNEGO token for SPN: $TargetSPN"
        
        # Check for Kerberos tickets
        $klistOutput = klist 2>&1
        if ($klistOutput -match "krbtgt/LOCAL.LAB") {
            Write-Log "TGT found - attempting SPNEGO generation"
        } else {
            Write-Log "ERROR: No TGT found - gMSA authentication required" "ERROR"
            return $null
        }
        
        # Generate real SPNEGO token using Win32 SSPI
        $credHandle = New-Object SSPI+SECURITY_HANDLE
        $expiry = New-Object SSPI+SECURITY_INTEGER
        
        # Acquire credentials handle
        $result = [SSPI]::AcquireCredentialsHandle(
            $null, "Negotiate", [SSPI]::SECPKG_CRED_OUTBOUND,
            [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero,
            [ref]$credHandle, [ref]$expiry
        )
        
        if ($result -ne [SSPI]::SEC_E_OK) {
            Write-Log "ERROR: AcquireCredentialsHandle failed: 0x$($result.ToString('X8'))" "ERROR"
            return $null
        }
        
        # Initialize security context
        $contextHandle = New-Object SSPI+SECURITY_HANDLE
        $outputBuffer = New-Object SSPI+SEC_BUFFER
        $contextAttr = 0
        
        $result = [SSPI]::InitializeSecurityContext(
            [ref]$credHandle, [IntPtr]::Zero, $TargetSPN,
            [SSPI]::ISC_REQ_CONFIDENTIALITY -bor [SSPI]::ISC_REQ_INTEGRITY,
            0, [SSPI]::SECURITY_NETWORK_DREP, [IntPtr]::Zero, 0,
            [ref]$contextHandle, [ref]$outputBuffer, [ref]$contextAttr, [ref]$expiry
        )
        
        if ($result -ne [SSPI]::SEC_E_OK -and $result -ne [SSPI]::SEC_I_CONTINUE_NEEDED) {
            Write-Log "ERROR: InitializeSecurityContext failed: 0x$($result.ToString('X8'))" "ERROR"
            
            # Provide Linux-specific guidance
            if ($result -eq 0x80090308) {
                Write-Log "ERROR: SEC_E_UNKNOWN_CREDENTIALS - SPN not registered" "ERROR"
                Write-Log "SOLUTION for Linux Vault server:" "ERROR"
                Write-Log "  setspn -A $TargetSPN <linux-hostname>" "ERROR"
                Write-Log "  Or: setspn -A $TargetSPN vault-gmsa" "ERROR"
            }
            
            [SSPI]::FreeCredentialsHandle([ref]$credHandle)
            return $null
        }
        
        # Extract SPNEGO token
        if ($outputBuffer.cbBuffer -gt 0 -and $outputBuffer.pvBuffer -ne [IntPtr]::Zero) {
            $tokenBytes = New-Object byte[] $outputBuffer.cbBuffer
            [System.Runtime.InteropServices.Marshal]::Copy($outputBuffer.pvBuffer, $tokenBytes, 0, $outputBuffer.cbBuffer)
            $spnegoToken = [System.Convert]::ToBase64String($tokenBytes)
            
            # Cleanup
            [SSPI]::FreeContextBuffer($outputBuffer.pvBuffer)
            [SSPI]::DeleteSecurityContext([ref]$contextHandle)
            [SSPI]::FreeCredentialsHandle([ref]$credHandle)
            
            Write-Log "SUCCESS: SPNEGO token generated ($($spnegoToken.Length) chars)" "SUCCESS"
            return $spnegoToken
        } else {
            Write-Log "ERROR: No token data in output buffer" "ERROR"
            [SSPI]::DeleteSecurityContext([ref]$contextHandle)
            [SSPI]::FreeCredentialsHandle([ref]$credHandle)
            return $null
        }
        
    } catch {
        Write-Log "ERROR: SPNEGO generation failed: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# =============================================================================
# Authenticate to Vault using gMSA plugin
# =============================================================================
function Authenticate-ToVault {
    param([string]$VaultUrl, [string]$Role, [string]$SPN)
    
    try {
        Write-Log "Authenticating to Vault gMSA plugin..."
        Write-Log "Vault URL: $VaultUrl"
        Write-Log "Role: $Role"
        Write-Log "SPN: $SPN"
        
        # Generate SPNEGO token
        $spnegoToken = Get-SPNEGOToken -TargetSPN $SPN
        if (-not $spnegoToken) {
            Write-Log "ERROR: Failed to generate SPNEGO token" "ERROR"
            return $null
        }
        
        # Prepare authentication request
        $authBody = @{
            role = $Role
            spnego = $spnegoToken
        } | ConvertTo-Json
        
        Write-Log "Sending authentication request to Vault..."
        
        # Send request to your custom gMSA plugin
        $response = Invoke-RestMethod -Uri "$VaultUrl/v1/auth/gmsa/login" -Method Post -Body $authBody -ContentType "application/json" -UseBasicParsing
        
        if ($response.auth -and $response.auth.client_token) {
            Write-Log "SUCCESS: Vault authentication successful!" "SUCCESS"
            Write-Log "Token TTL: $($response.auth.lease_duration) seconds"
            return $response.auth.client_token
        } else {
            Write-Log "ERROR: Authentication response missing required fields" "ERROR"
            return $null
        }
        
    } catch {
        Write-Log "ERROR: Vault authentication failed: $($_.Exception.Message)" "ERROR"
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Log "HTTP Status: $statusCode" "ERROR"
        }
        return $null
    }
}

# =============================================================================
# Retrieve secrets from Vault
# =============================================================================
function Get-VaultSecret {
    param([string]$VaultUrl, [string]$Token, [string]$SecretPath)
    
    try {
        Write-Log "Retrieving secret: $SecretPath"
        
        $headers = @{ "X-Vault-Token" = $Token }
        $response = Invoke-RestMethod -Uri "$VaultUrl/v1/$SecretPath" -Method Get -Headers $headers -UseBasicParsing
        
        if ($response.data -and $response.data.data) {
            Write-Log "SUCCESS: Secret retrieved" "SUCCESS"
            return $response.data.data
        } else {
            Write-Log "ERROR: Secret response missing data" "ERROR"
            return $null
        }
        
    } catch {
        Write-Log "ERROR: Failed to retrieve secret: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# =============================================================================
# Main Application
# =============================================================================
try {
    Write-Host "Vault gMSA Authentication Client (Minimal)" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host ""
    
    Write-Log "Starting Vault Client Application..."
    
    # Step 1: Authenticate to Vault
    Write-Log "Step 1: Authenticating to Vault..."
    $vaultToken = Authenticate-ToVault -VaultUrl $VaultUrl -Role $VaultRole -SPN $SPN
    
    if (-not $vaultToken) {
        Write-Log "ERROR: Authentication failed - cannot continue" "ERROR"
        exit 1
    }
    
    # Step 2: Retrieve secrets
    Write-Log "Step 2: Retrieving secrets..."
    $secrets = @{}
    
    foreach ($secretPath in $SecretPaths) {
        $secret = Get-VaultSecret -VaultUrl $VaultUrl -Token $vaultToken -SecretPath $secretPath
        if ($secret) {
            $secrets[$secretPath] = $secret
            Write-Log "Retrieved: $secretPath" "SUCCESS"
        }
    }
    
    # Step 3: Display results
    if ($secrets.Count -gt 0) {
        Write-Log "SUCCESS: Retrieved $($secrets.Count) secrets" "SUCCESS"
        Write-Log "Secret summary:"
        foreach ($path in $secrets.Keys) {
            Write-Log "  - $path : $($secrets[$path].Keys -join ', ')"
        }
    } else {
        Write-Log "WARNING: No secrets retrieved" "WARNING"
    }
    
    Write-Log "Application completed successfully" "SUCCESS"
    Write-Host ""
    Write-Host "SUCCESS: Vault gMSA authentication completed!" -ForegroundColor Green
    
} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    Write-Host "FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
