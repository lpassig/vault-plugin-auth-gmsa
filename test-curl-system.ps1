param(
    [string]$VaultAddr = "https://vault.local.lab:8200",
    [string]$Role = "computer-accounts"
)

$LogFile = "C:\vault-client\logs\test-curl-system.log"

# Ensure log directory exists
$logDir = "C:\vault-client\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Output $logMessage
    Add-Content -Path $LogFile -Value $logMessage -Force
}

try {
    Write-Log "========================================" "INFO"
    Write-Log "CURL KERBEROS AUTH TEST (RUNNING AS SYSTEM)" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "" "INFO"
    Write-Log "Current User: $env:USERNAME" "INFO"
    Write-Log "Computer: $env:COMPUTERNAME" "INFO"
    Write-Log "Vault URL: $VaultAddr" "INFO"
    Write-Log "Role: $Role" "INFO"
    Write-Log "" "INFO"

    # Check Kerberos tickets (don't purge - computer accounts need existing tickets)
    Write-Log "Checking Kerberos tickets..." "INFO"
    $tickets = klist 2>&1 | Out-String
    Write-Log $tickets "INFO"
    Write-Log "" "INFO"

    # Use curl.exe with --negotiate
    Write-Log "Authenticating with curl.exe --negotiate..." "INFO"
    
    $curlPath = "C:\Windows\System32\curl.exe"
    if (-not (Test-Path $curlPath)) {
        Write-Log "ERROR: curl.exe not found at $curlPath" "ERROR"
        exit 1
    }

    # Create request body
    $bodyJson = @{role = $Role} | ConvertTo-Json -Compress
    $tempJsonFile = "$env:TEMP\vault-auth-body.json"
    $bodyJson | Out-File -FilePath $tempJsonFile -Encoding ASCII -NoNewline -Force
    
    Write-Log "Request body: $bodyJson" "INFO"
    Write-Log "Endpoint: $VaultAddr/v1/auth/kerberos/login" "INFO"
    Write-Log "" "INFO"

    # Use curl with --negotiate
    $curlArgs = @(
        "--negotiate",
        "--user", ":",
        "-X", "POST",
        "-H", "Content-Type: application/json",
        "--data-binary", "@$tempJsonFile",
        "-k",
        "-v",
        "$VaultAddr/v1/auth/kerberos/login"
    )
    
    Write-Log "Executing: curl.exe $($curlArgs -join ' ')" "INFO"
    $curlOutput = & $curlPath $curlArgs 2>&1 | Out-String
    
    # Clean up temp file
    Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
    
    Write-Log "curl output:" "INFO"
    Write-Log $curlOutput "INFO"
    
    # Try to parse JSON response
    try {
        # Extract JSON from curl output (it includes debug info)
        $jsonMatch = $curlOutput | Select-String -Pattern '\{.*"auth".*\}' -AllMatches
        if ($jsonMatch) {
            $jsonResponse = $jsonMatch.Matches[0].Value
            $authResponse = $jsonResponse | ConvertFrom-Json
            
            if ($authResponse.auth -and $authResponse.auth.client_token) {
                Write-Log "" "SUCCESS"
                Write-Log "========================================" "SUCCESS"
                Write-Log "SUCCESS! Authentication succeeded!" "SUCCESS"
                Write-Log "========================================" "SUCCESS"
                Write-Log "Token: $($authResponse.auth.client_token)" "INFO"
                Write-Log "TTL: $($authResponse.auth.lease_duration) seconds" "INFO"
                Write-Log "Policies: $($authResponse.auth.policies -join ', ')" "INFO"
                Write-Log "" "SUCCESS"
                Write-Log "AUTHENTICATION SUCCESSFUL!" "SUCCESS"
                exit 0
            }
        }
        
        Write-Log "No valid token in response" "ERROR"
        exit 1
        
    } catch {
        Write-Log "Failed to parse response: $($_.Exception.Message)" "ERROR"
        exit 1
    }
    
} catch {
    Write-Log "" "ERROR"
    Write-Log "========================================" "ERROR"
    Write-Log "AUTHENTICATION FAILED!" "ERROR"
    Write-Log "========================================" "ERROR"
    Write-Log "Error: $($_.Exception.Message)" "ERROR"
    Write-Log "" "ERROR"
    exit 1
}
