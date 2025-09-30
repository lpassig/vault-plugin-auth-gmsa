param(
    [string]$VaultAddr = "https://vault.local.lab:8200",
    [string]$Role = "computer-accounts"
)

$LogFile = "C:\vault-client\logs\test-kerberos.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    
    $logDir = Split-Path -Parent $LogFile
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logMessage
}

Write-Log "========================================" "INFO"
Write-Log "KERBEROS AUTHENTICATION TEST" "INFO"
Write-Log "========================================" "INFO"
Write-Log "" "INFO"
Write-Log "Current User: $env:USERNAME" "INFO"
Write-Log "Computer: $env:COMPUTERNAME" "INFO"
Write-Log "Domain: $env:USERDNSDOMAIN" "INFO"
Write-Log "Vault URL: $VaultAddr" "INFO"
Write-Log "Role: $Role" "INFO"
Write-Log "" "INFO"

# Check Kerberos tickets
Write-Log "Checking Kerberos tickets..." "INFO"
$tickets = klist 2>&1 | Out-String
Write-Log $tickets "INFO"
Write-Log "" "INFO"

# Bypass SSL
Write-Log "Configuring SSL bypass..." "INFO"
Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
Write-Log "SSL validation bypassed" "INFO"
Write-Log "" "INFO"

# Authenticate
Write-Log "Attempting authentication..." "INFO"
$requestBody = @{ role = $Role } | ConvertTo-Json
Write-Log "Request body: $requestBody" "INFO"
Write-Log "Endpoint: $VaultAddr/v1/auth/kerberos/login" "INFO"
Write-Log "" "INFO"

try {
    $response = Invoke-RestMethod -Uri "$VaultAddr/v1/auth/kerberos/login" -Method POST -UseDefaultCredentials -Headers @{"Authorization" = "Negotiate"} -Body $requestBody -ContentType "application/json" -TimeoutSec 30 -ErrorAction Stop
    
    if ($response.auth -and $response.auth.client_token) {
        Write-Log "" "SUCCESS"
        Write-Log "========================================" "SUCCESS"
        Write-Log "SUCCESS! Authentication succeeded!" "SUCCESS"
        Write-Log "========================================" "SUCCESS"
        Write-Log "Token: $($response.auth.client_token)" "INFO"
        Write-Log "TTL: $($response.auth.lease_duration) seconds" "INFO"
        Write-Log "Policies: $($response.auth.policies -join ', ')" "INFO"
        Write-Log "" "SUCCESS"
        
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 0
    } else {
        Write-Log "No token in response" "ERROR"
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
} catch {
    Write-Log "" "ERROR"
    Write-Log "========================================" "ERROR"
    Write-Log "AUTHENTICATION FAILED!" "ERROR"
    Write-Log "========================================" "ERROR"
    Write-Log "Error: $($_.Exception.Message)" "ERROR"
    
    if ($_.Exception.Response) {
        Write-Log "HTTP Status: $($_.Exception.Response.StatusCode)" "ERROR"
    }
    
    Write-Log "" "ERROR"
    Write-Log "Troubleshooting:" "INFO"
    Write-Log "1. Verify SPN: setspn -L $env:COMPUTERNAME`$" "INFO"
    Write-Log "2. Check Vault: vault read auth/kerberos/config" "INFO"
    Write-Log "" "ERROR"
    
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}
