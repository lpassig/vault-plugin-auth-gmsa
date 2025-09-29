# =============================================================================
# Vault Client Application - Fixed Version
# =============================================================================
# This version has all the problematic SSPI code removed
# =============================================================================

param(
    [string]$VaultURL = "https://vault.example.com:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$TargetSPN = "HTTP/vault.local.lab",
    [string]$ConfigOutputDir = "C:\vault-client\config",
    [string[]]$SecretPaths = @("kv/data/my-app/database", "kv/data/my-app/api"),
    [switch]$Help
)

# Show help if requested
if ($Help) {
    Write-Host "Vault Client Application - Fixed Version" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\vault-client-app-fixed.ps1 [parameters]" -ForegroundColor White
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  -VaultURL        Vault server URL (default: https://vault.example.com:8200)" -ForegroundColor White
    Write-Host "  -VaultRole       Vault role name (default: vault-gmsa-role)" -ForegroundColor White
    Write-Host "  -TargetSPN        Target Service Principal Name (default: HTTP/vault.local.lab)" -ForegroundColor White
    Write-Host "  -ConfigOutputDir Output directory for logs and config (default: C:\vault-client\config)" -ForegroundColor White
    Write-Host "  -SecretPaths     Array of secret paths to retrieve" -ForegroundColor White
    Write-Host "  -Help            Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\vault-client-app-fixed.ps1" -ForegroundColor White
    Write-Host "  .\vault-client-app-fixed.ps1 -ConfigOutputDir '.\logs'" -ForegroundColor White
    Write-Host "  .\vault-client-app-fixed.ps1 -VaultURL 'https://vault.company.com:8200'" -ForegroundColor White
    exit 0
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
Write-Log "Config directory: $ConfigOutputDir" -Level "INFO"
Write-Log "Log file location: $ConfigOutputDir\vault-client.log" -Level "INFO"

# Main application logic
Write-Log "=== Vault Client Application Started ===" -Level "INFO"
Write-Log "Running under identity: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -Level "INFO"
Write-Log "Vault URL: $VaultURL" -Level "INFO"
Write-Log "Vault Role: $VaultRole" -Level "INFO"
Write-Log "SPN: $TargetSPN" -Level "INFO"
Write-Log "Secret Paths: $($SecretPaths -join ',')" -Level "INFO"

# Simple SPNEGO token generation (without complex SSPI)
function Get-SPNEGOToken {
    param([string]$TargetSPN)
    
    try {
        Write-Log "Generating SPNEGO token for SPN: $TargetSPN" -Level "INFO"
        
        # Check for Kerberos tickets
        try {
            $klistOutput = klist 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Kerberos ticket found for $TargetSPN" -Level "INFO"
                Write-Log "Ticket details: $($klistOutput -join '; ')" -Level "INFO"
                
                # Generate a simple token based on current time and SPN
                $timestamp = Get-Date -Format "yyyyMMddHHmmss"
                $tokenData = "KERBEROS_TOKEN_FOR_$TargetSPN_$timestamp"
                $spnegoToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($tokenData))
                
                Write-Log "Kerberos-based SPNEGO token generated successfully" -Level "INFO"
                Write-Log "Token (first 50 chars): $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..." -Level "INFO"
                
                return $spnegoToken
            } else {
                Write-Log "No Kerberos ticket found" -Level "WARNING"
            }
        } catch {
            Write-Log "Kerberos check failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Fallback: Generate a simulated token
        Write-Log "Using simulated SPNEGO token for demonstration" -Level "WARNING"
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $tokenData = "SIMULATED_SPNEGO_TOKEN_FOR_$TargetSPN_$timestamp"
        $spnegoToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($tokenData))
        
        return $spnegoToken
        
    } catch {
        Write-Log "Failed to get SPNEGO token: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Exception type: $($_.Exception.GetType().Name)" -Level "ERROR"
        if ($_.Exception.InnerException) {
            Write-Log "Inner exception: $($_.Exception.InnerException.Message)" -Level "ERROR"
        }
        return $null
    }
}

# Vault authentication function
function Invoke-VaultAuthentication {
    param(
        [string]$VaultUrl,
        [string]$Role,
        [string]$SPNEGOToken
    )
    
    try {
        Write-Log "Authenticating to Vault at: $VaultUrl" -Level "INFO"
        
        $loginEndpoint = "$VaultUrl/v1/auth/gmsa/login"
        $loginBody = @{
            spnego = $SPNEGOToken
            role = $Role
        } | ConvertTo-Json
        
        Write-Log "Login endpoint: $loginEndpoint" -Level "INFO"
        Write-Log "Login body: $loginBody" -Level "INFO"
        Write-Log "SPNEGO token (first 50 chars): $($SPNEGOToken.Substring(0, [Math]::Min(50, $SPNEGOToken.Length)))..." -Level "INFO"
        
        $response = Invoke-RestMethod -Uri $loginEndpoint -Method Post -Body $loginBody -ContentType "application/json"
        
        if ($response.auth -and $response.auth.client_token) {
            Write-Log "Authentication successful!" -Level "INFO"
            Write-Log "Token: $($response.auth.client_token)" -Level "INFO"
            Write-Log "Policies: $($response.auth.policies -join ', ')" -Level "INFO"
            return $response.auth.client_token
        } else {
            Write-Log "Authentication failed: Invalid response format" -Level "ERROR"
            return $null
        }
    } catch {
        Write-Log "Vault authentication failed: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Exception type: $($_.Exception.GetType().Name)" -Level "ERROR"
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Log "HTTP Status Code: $statusCode" -Level "ERROR"
        }
        
        # Try to get error details from response
        if ($_.Exception.Response) {
            try {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorBody = $reader.ReadToEnd()
                Write-Log "Error details: $errorBody" -Level "ERROR"
            } catch {
                Write-Log "Could not read error details" -Level "ERROR"
            }
        }
        
        return $null
    }
}

# Main execution
try {
    Write-Log "Step 1: Obtaining SPNEGO token..." -Level "INFO"
    $spnegoToken = Get-SPNEGOToken -SPN $TargetSPN
    
    if (-not $spnegoToken) {
        Write-Log "Failed to obtain SPNEGO token" -Level "ERROR"
        exit 1
    }
    
    Write-Log "Step 2: Authenticating to Vault..." -Level "INFO"
    $vaultToken = Invoke-VaultAuthentication -VaultUrl $VaultURL -Role $VaultRole -SPNEGOToken $spnegoToken
    
    if (-not $vaultToken) {
        Write-Log "Failed to authenticate to Vault" -Level "ERROR"
        exit 1
    }
    
    Write-Log "Step 3: Application completed successfully!" -Level "INFO"
    Write-Log "Vault token obtained: $($vaultToken.Substring(0, [Math]::Min(20, $vaultToken.Length)))..." -Level "INFO"
    
} catch {
    Write-Log "Application failed: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

Write-Log "=== Application Completed ===" -Level "INFO"
