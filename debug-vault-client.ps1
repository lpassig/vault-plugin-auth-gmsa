# Debug version of vault-client-app.ps1
# This will help identify where the script stops executing

param(
    [string]$VaultUrl = "https://vault.example.com:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab",
    [string[]]$SecretPaths = @("kv/data/my-app/database", "kv/data/my-app/api"),
    [string]$ConfigOutputDir = "C:\vault-client\config",
    [switch]$CreateScheduledTask = $false,
    [string]$TaskName = "VaultClientApp"
)

Write-Host "=== DEBUG: Script started ===" -ForegroundColor Green
Write-Host "Parameters:" -ForegroundColor Cyan
Write-Host "  VaultUrl: $VaultUrl" -ForegroundColor White
Write-Host "  VaultRole: $VaultRole" -ForegroundColor White
Write-Host "  SPN: $SPN" -ForegroundColor White
Write-Host "  ConfigOutputDir: $ConfigOutputDir" -ForegroundColor White
Write-Host "  CreateScheduledTask: $CreateScheduledTask" -ForegroundColor White

Write-Host "`n=== DEBUG: Starting DNS fix ===" -ForegroundColor Green

# Quick DNS fix: Add hostname mapping for vault.local.lab
try {
    Write-Host "🔧 Applying DNS resolution fix..." -ForegroundColor Cyan
    
    # Extract IP from Vault URL and map to vault.local.lab
    $vaultHost = [System.Uri]::new($VaultUrl).Host
    Write-Host "Vault host: $vaultHost" -ForegroundColor Cyan
    
    # Map vault.example.com to vault.local.lab for Kerberos
    if ($vaultHost -eq "vault.example.com") {
        $vaultIP = "10.0.101.151"  # Your test environment IP
        Write-Host "Mapping vault.example.com ($vaultIP) to vault.local.lab for Kerberos" -ForegroundColor Cyan
    } else {
        $vaultIP = $vaultHost
    }
    
    Write-Host "=== DEBUG: DNS fix completed ===" -ForegroundColor Green
} catch {
    Write-Host "❌ DNS fix failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== DEBUG: Creating output directory ===" -ForegroundColor Green

# Create output directory
try {
    if (-not (Test-Path $ConfigOutputDir)) {
        New-Item -ItemType Directory -Path $ConfigOutputDir -Force | Out-Null
        Write-Host "Created config directory: $ConfigOutputDir" -ForegroundColor Green
    } else {
        Write-Host "Config directory already exists: $ConfigOutputDir" -ForegroundColor Green
    }
    Write-Host "=== DEBUG: Directory creation completed ===" -ForegroundColor Green
} catch {
    Write-Host "Failed to create config directory: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Using current directory for logs" -ForegroundColor Yellow
    $ConfigOutputDir = "."
}

Write-Host "`n=== DEBUG: Defining logging function ===" -ForegroundColor Green

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

Write-Host "=== DEBUG: Logging function defined ===" -ForegroundColor Green

Write-Host "`n=== DEBUG: Testing logging function ===" -ForegroundColor Green

# Test logging immediately
Write-Log "Script initialization completed successfully" -Level "INFO"
Write-Log "Script version: 2.0 (with automatic ticket request)" -Level "INFO"
Write-Log "Config directory: $ConfigOutputDir" -Level "INFO"
Write-Log "Log file location: $ConfigOutputDir\vault-client.log" -Level "INFO"

Write-Host "=== DEBUG: Logging test completed ===" -ForegroundColor Green

Write-Host "`n=== DEBUG: Checking log file ===" -ForegroundColor Green
$logFile = "$ConfigOutputDir\vault-client.log"
if (Test-Path $logFile) {
    Write-Host "✅ Log file exists: $logFile" -ForegroundColor Green
    Write-Host "File size: $((Get-Item $logFile).Length) bytes" -ForegroundColor Cyan
    Write-Host "File contents:" -ForegroundColor Cyan
    Get-Content $logFile
} else {
    Write-Host "❌ Log file does not exist: $logFile" -ForegroundColor Red
}

Write-Host "`n=== DEBUG: Script completed successfully ===" -ForegroundColor Green
