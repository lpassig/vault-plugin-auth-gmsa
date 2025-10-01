# Alternative Authentication Method for Vault
# This script tries different authentication approaches when SPN registration is not possible

param(
    [string]$VaultAddr = "http://vault.local.lab:8200",
    [string]$Role = "computer-accounts"
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "ALTERNATIVE VAULT AUTHENTICATION" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$LogFile = "C:\vault-client\logs\alternative-auth.log"

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
    Write-Log "ALTERNATIVE AUTHENTICATION METHODS" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "" "INFO"
    Write-Log "Current User: $env:USERNAME" "INFO"
    Write-Log "Computer: $env:COMPUTERNAME" "INFO"
    Write-Log "Vault URL: $VaultAddr" "INFO"
    Write-Log "Role: $Role" "INFO"
    Write-Log "" "INFO"

    # Method 1: Try with different SPN formats
    Write-Log "Method 1: Trying different SPN formats..." "INFO"
    
    $spnVariations = @(
        "HTTP/vault.local.lab",
        "HTTP/vault.local.lab@LOCAL.LAB",
        "HTTP/VAULT.LOCAL.LAB",
        "http/vault.local.lab"
    )
    
    foreach ($spn in $spnVariations) {
        Write-Log "Trying SPN: $spn" "INFO"
        
        # Try to get a service ticket for this SPN
        try {
            $ticketResult = klist -s $spn 2>&1 | Out-String
            if ($ticketResult -match "Ticket cache") {
                Write-Log "✓ Service ticket exists for: $spn" "SUCCESS"
                
                # Try authentication with this SPN
                $body = @{role = $Role} | ConvertTo-Json -Compress
                $headers = @{
                    "Content-Type" = "application/json"
                }
                
                try {
                    $response = Invoke-WebRequest -Uri "$VaultAddr/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -UseBasicParsing -ErrorAction Stop
                    
                    if ($response.StatusCode -eq 200) {
                        Write-Log "✓ Authentication successful with SPN: $spn" "SUCCESS"
                        $responseData = $response.Content | ConvertFrom-Json
                        if ($responseData.auth.client_token) {
                            Write-Log "Token: $($responseData.auth.client_token)" "SUCCESS"
                            Write-Log "AUTHENTICATION SUCCESSFUL!" "SUCCESS"
                            exit 0
                        }
                    }
                } catch {
                    Write-Log "Authentication failed with SPN: $spn - $($_.Exception.Message)" "WARNING"
                }
            }
        } catch {
            Write-Log "No ticket for SPN: $spn" "INFO"
        }
    }
    
    # Method 2: Try with computer account name variations
    Write-Log "" "INFO"
    Write-Log "Method 2: Trying computer account variations..." "INFO"
    
    $computerVariations = @(
        "EC2AMAZ-UB1QVDL$",
        "EC2AMAZ-UB1QVDL",
        "EC2AMAZ-UB1QVDL$@LOCAL.LAB",
        "EC2AMAZ-UB1QVDL@LOCAL.LAB"
    )
    
    foreach ($computer in $computerVariations) {
        Write-Log "Trying computer account: $computer" "INFO"
        
        # Try to register SPN with this computer account
        try {
            $spnResult = setspn -A HTTP/vault.local.lab $computer 2>&1 | Out-String
            if ($spnResult -match "Duplicate SPN") {
                Write-Log "SPN already exists for: $computer" "INFO"
            } elseif ($spnResult -match "Updated object") {
                Write-Log "✓ SPN registered for: $computer" "SUCCESS"
                
                # Test authentication
                Start-Sleep -Seconds 2
                $body = @{role = $Role} | ConvertTo-Json -Compress
                $headers = @{
                    "Content-Type" = "application/json"
                }
                
                try {
                    $response = Invoke-WebRequest -Uri "$VaultAddr/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -UseBasicParsing -ErrorAction Stop
                    
                    if ($response.StatusCode -eq 200) {
                        Write-Log "✓ Authentication successful with computer: $computer" "SUCCESS"
                        $responseData = $response.Content | ConvertFrom-Json
                        if ($responseData.auth.client_token) {
                            Write-Log "Token: $($responseData.auth.client_token)" "SUCCESS"
                            Write-Log "AUTHENTICATION SUCCESSFUL!" "SUCCESS"
                            exit 0
                        }
                    }
                } catch {
                    Write-Log "Authentication failed with computer: $computer - $($_.Exception.Message)" "WARNING"
                }
            }
        } catch {
            Write-Log "Failed to register SPN for: $computer - $($_.Exception.Message)" "WARNING"
        }
    }
    
    # Method 3: Try with different authentication endpoints
    Write-Log "" "INFO"
    Write-Log "Method 3: Trying different authentication endpoints..." "INFO"
    
    $endpoints = @(
        "/v1/auth/kerberos/login",
        "/v1/auth/gmsa/login",
        "/v1/auth/ldap/login"
    )
    
    foreach ($endpoint in $endpoints) {
        Write-Log "Trying endpoint: $endpoint" "INFO"
        
        $body = @{role = $Role} | ConvertTo-Json -Compress
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        try {
            $response = Invoke-WebRequest -Uri "$VaultAddr$endpoint" -Method POST -Body $body -Headers $headers -UseBasicParsing -ErrorAction Stop
            
            if ($response.StatusCode -eq 200) {
                Write-Log "✓ Authentication successful with endpoint: $endpoint" "SUCCESS"
                $responseData = $response.Content | ConvertFrom-Json
                if ($responseData.auth.client_token) {
                    Write-Log "Token: $($responseData.auth.client_token)" "SUCCESS"
                    Write-Log "AUTHENTICATION SUCCESSFUL!" "SUCCESS"
                    exit 0
                }
            }
        } catch {
            Write-Log "Authentication failed with endpoint: $endpoint - $($_.Exception.Message)" "WARNING"
        }
    }
    
    # Method 4: Try with curl and different options
    Write-Log "" "INFO"
    Write-Log "Method 4: Trying curl with different options..." "INFO"
    
    $curlPath = "C:\Windows\System32\curl.exe"
    if (Test-Path $curlPath) {
        $tempJsonFile = "$env:TEMP\vault-auth-body.json"
        $bodyJson = @{role = $Role} | ConvertTo-Json -Compress
        $bodyJson | Out-File -FilePath $tempJsonFile -Encoding ASCII -NoNewline -Force
        
        $curlOptions = @(
            @("--negotiate", "--user", ":", "-X", "POST", "-H", "Content-Type: application/json", "--data-binary", "@$tempJsonFile", "-k", "-v"),
            @("--negotiate", "--user", ":", "-X", "POST", "-H", "Content-Type: application/json", "--data-binary", "@$tempJsonFile", "-k", "-s"),
            @("--negotiate", "-X", "POST", "-H", "Content-Type: application/json", "--data-binary", "@$tempJsonFile", "-k", "-v"),
            @("--negotiate", "-X", "POST", "-H", "Content-Type: application/json", "--data-binary", "@$tempJsonFile", "-k", "-s", "--insecure")
        )
        
        foreach ($options in $curlOptions) {
            Write-Log "Trying curl with options: $($options -join ' ')" "INFO"
            
            try {
                $curlOutput = & $curlPath $options "$VaultAddr/v1/auth/kerberos/login" 2>&1 | Out-String
                
                if ($curlOutput -match '"client_token"') {
                    Write-Log "✓ Authentication successful with curl!" "SUCCESS"
                    Write-Log "Response: $curlOutput" "SUCCESS"
                    Write-Log "AUTHENTICATION SUCCESSFUL!" "SUCCESS"
                    exit 0
                } else {
                    Write-Log "Curl failed: $curlOutput" "WARNING"
                }
            } catch {
                Write-Log "Curl error: $($_.Exception.Message)" "WARNING"
            }
        }
        
        # Clean up temp file
        Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
    }
    
    Write-Log "All alternative methods failed" "ERROR"
    Write-Log "========================================" "ERROR"
    Write-Log "AUTHENTICATION FAILED!" "ERROR"
    Write-Log "========================================" "ERROR"
    Write-Log "" "ERROR"
    Write-Log "RECOMMENDED NEXT STEPS:" "ERROR"
    Write-Log "1. Get domain admin access to register SPN" "ERROR"
    Write-Log "2. Contact domain administrator to run:" "ERROR"
    Write-Log "   setspn -A HTTP/vault.local.lab EC2AMAZ-UB1QVDL$" "ERROR"
    Write-Log "3. Verify Vault server configuration" "ERROR"
    Write-Log "4. Check if different auth method is configured" "ERROR"
    
    exit 1
    
} catch {
    Write-Log "Script error: $($_.Exception.Message)" "ERROR"
    exit 1
}


