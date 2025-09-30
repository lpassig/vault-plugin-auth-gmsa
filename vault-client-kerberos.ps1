# vault-client-kerberos.ps1
# Windows Client for Official HashiCorp Vault Kerberos Plugin
# Runs as NT AUTHORITY\SYSTEM, uses computer account for authentication

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$Role = "computer-accounts"
)

$LogFile = "C:\vault-client\logs\vault-kerberos.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    
    # Ensure log directory exists
    $logDir = Split-Path -Parent $LogFile
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logMessage
}

function Test-KerberosAuth {
    Write-Log "========================================" "INFO"
    Write-Log "VAULT KERBEROS AUTHENTICATION (OFFICIAL PLUGIN)" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "Current User: $env:USERNAME" "INFO"
    Write-Log "Computer: $env:COMPUTERNAME" "INFO"
    Write-Log "Domain: $env:USERDNSDOMAIN" "INFO"
    Write-Log "Vault URL: $VaultUrl" "INFO"
    Write-Log "Role: $Role" "INFO"
    Write-Log "Auth Endpoint: /v1/auth/kerberos/login" "INFO"
    Write-Log "" "INFO"
    
    # Check Kerberos tickets
    Write-Log "Checking Kerberos tickets..." "INFO"
    try {
        $tickets = klist 2>&1 | Out-String
        Write-Log $tickets "INFO"
    } catch {
        Write-Log "Warning: Could not run klist: $($_.Exception.Message)" "WARNING"
    }
    Write-Log "" "INFO"
    
    # Authenticate using curl.exe with --negotiate
    Write-Log "Authenticating to Vault using curl.exe --negotiate..." "INFO"
    
    $curlPath = "C:\Windows\System32\curl.exe"
    if (-not (Test-Path $curlPath)) {
        Write-Log "ERROR: curl.exe not found at $curlPath" "ERROR"
        return $null
    }
    
    # Create request body
    $bodyObj = @{role = $Role}
    $body = $bodyObj | ConvertTo-Json -Compress
    $tempFile = "$env:TEMP\vault-kerberos-body.json"
    $body | Out-File -FilePath $tempFile -Encoding ASCII -NoNewline -Force
    
    Write-Log "Request body: $body" "INFO"
    
    # Use curl.exe with --negotiate for automatic SPNEGO
    $curlArgs = @(
        "--negotiate",
        "--user", ":",
        "-X", "POST",
        "-H", "Content-Type: application/json",
        "--data-binary", "@$tempFile",
        "-k",
        "-s",
        "$VaultUrl/v1/auth/kerberos/login"
    )
    
    Write-Log "Executing: curl.exe $($curlArgs -join ' ')" "INFO"
    
    try {
        $response = & $curlPath $curlArgs 2>&1 | Out-String
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        
        Write-Log "Response received (length: $($response.Length) chars)" "INFO"
        
        # Check if response looks like JSON
        if ($response -match '^\s*\{') {
            # Parse JSON response
            $authResponse = $response | ConvertFrom-Json -ErrorAction Stop
            
            if ($authResponse.auth -and $authResponse.auth.client_token) {
                Write-Log "========================================" "SUCCESS"
                Write-Log "SUCCESS! Vault token obtained" "SUCCESS"
                Write-Log "========================================" "SUCCESS"
                Write-Log "Token: $($authResponse.auth.client_token)" "INFO"
                Write-Log "TTL: $($authResponse.auth.lease_duration) seconds" "INFO"
                Write-Log "Policies: $($authResponse.auth.policies -join ', ')" "INFO"
                Write-Log "" "INFO"
                
                return $authResponse.auth.client_token
            } elseif ($authResponse.errors) {
                Write-Log "Authentication failed with errors:" "ERROR"
                $authResponse.errors | ForEach-Object { Write-Log "  - $_" "ERROR" }
                Write-Log "Full response: $response" "ERROR"
                return $null
            } else {
                Write-Log "Unexpected response format - no token in response" "ERROR"
                Write-Log "Response: $response" "ERROR"
                return $null
            }
        } else {
            Write-Log "Response is not valid JSON" "ERROR"
            Write-Log "Response: $response" "ERROR"
            return $null
        }
        
    } catch {
        Write-Log "Authentication failed: $($_.Exception.Message)" "ERROR"
        Write-Log "Response: $response" "ERROR"
        return $null
    }
}

function Get-VaultSecret {
    param(
        [string]$Token,
        [string]$SecretPath = "secret/data/app/config"
    )
    
    Write-Log "Retrieving secret from: $SecretPath" "INFO"
    
    $curlArgs = @(
        "-H", "X-Vault-Token: $Token",
        "-k",
        "-s",
        "$VaultUrl/v1/$SecretPath"
    )
    
    try {
        $response = & "C:\Windows\System32\curl.exe" $curlArgs 2>&1 | Out-String
        
        if ($response -match '^\s*\{') {
            $secret = $response | ConvertFrom-Json -ErrorAction Stop
            
            if ($secret.data) {
                Write-Log "Secret retrieved successfully" "SUCCESS"
                Write-Log "Secret keys: $($secret.data.data.Keys -join ', ')" "INFO"
                return $secret
            } else {
                Write-Log "Secret path exists but no data found" "WARNING"
                return $null
            }
        } else {
            Write-Log "Secret not found or invalid response" "WARNING"
            Write-Log "Response: $response" "WARNING"
            return $null
        }
        
    } catch {
        Write-Log "Failed to retrieve secret: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Main execution
try {
    Write-Log "========================================" "INFO"
    Write-Log "STARTING VAULT AUTHENTICATION" "INFO"
    Write-Log "Script Version: 1.0 (Official Kerberos Plugin)" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "" "INFO"
    
    # Authenticate
    $token = Test-KerberosAuth
    
    if ($token) {
        Write-Log "" "INFO"
        Write-Log "Attempting to retrieve test secret..." "INFO"
        
        # Try to get a sample secret
        $secret = Get-VaultSecret -Token $token -SecretPath "secret/data/app/config"
        
        if ($secret) {
            Write-Log "" "SUCCESS"
            Write-Log "========================================" "SUCCESS"
            Write-Log "APPLICATION CONFIGURED SUCCESSFULLY!" "SUCCESS"
            Write-Log "========================================" "SUCCESS"
        } else {
            Write-Log "" "INFO"
            Write-Log "Note: No test secret found (this is OK for initial setup)" "INFO"
        }
        
        Write-Log "" "INFO"
        Write-Log "Authentication completed successfully!" "SUCCESS"
        exit 0
        
    } else {
        Write-Log "" "ERROR"
        Write-Log "========================================" "ERROR"
        Write-Log "AUTHENTICATION FAILED!" "ERROR"
        Write-Log "========================================" "ERROR"
        Write-Log "" "ERROR"
        Write-Log "Troubleshooting:" "INFO"
        Write-Log "1. Verify SPN is registered to computer account (on ADDC):" "INFO"
        Write-Log "   setspn -L $env:COMPUTERNAME`$" "INFO"
        Write-Log "" "INFO"
        Write-Log "2. Verify Vault Kerberos configuration (on Vault server):" "INFO"
        Write-Log "   vault read auth/kerberos/config" "INFO"
        Write-Log "" "INFO"
        Write-Log "3. Check Kerberos tickets (as SYSTEM):" "INFO"
        Write-Log "   PsExec64.exe -s -i cmd" "INFO"
        Write-Log "   klist" "INFO"
        Write-Log "" "ERROR"
        exit 1
    }
    
} catch {
    Write-Log "" "ERROR"
    Write-Log "Script failed with exception: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
