# Simplified vault-client-app.ps1 - Minimal version to test logging
param(
    [string]$VaultUrl = "https://vault.example.com:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab",
    [string[]]$SecretPaths = @("kv/data/my-app/database", "kv/data/my-app/api"),
    [string]$ConfigOutputDir = "C:\vault-client\config",
    [switch]$CreateScheduledTask = $false,
    [string]$TaskName = "VaultClientApp"
)

Write-Host "=== SIMPLIFIED VAULT CLIENT - TESTING LOGGING ===" -ForegroundColor Green

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
    
    # Check if vault.local.lab resolves
    try {
        $dnsResult = [System.Net.Dns]::GetHostAddresses("vault.local.lab")
        Write-Host "✅ vault.local.lab already resolves to: $($dnsResult[0].IPAddressToString)" -ForegroundColor Green
    } catch {
        Write-Host "⚠️ vault.local.lab does not resolve, applying hostname fix..." -ForegroundColor Yellow
        
        # Add to Windows hosts file
        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
        $hostsEntry = "`n# Vault gMSA DNS fix`n$vaultIP vault.local.lab"
        
        # Check if entry already exists
        $hostsContent = Get-Content $hostsPath -ErrorAction SilentlyContinue
        if ($hostsContent -notcontains "$vaultIP vault.local.lab") {
            Add-Content -Path $hostsPath -Value $hostsEntry -Force
            Write-Host "✅ Added DNS mapping: $vaultIP → vault.local.lab" -ForegroundColor Green
            Write-Host "📝 Entry added to: $hostsPath" -ForegroundColor Cyan
        } else {
            Write-Host "✅ DNS mapping already exists in hosts file" -ForegroundColor Green
        }
        
        # Flush DNS cache
        try {
            ipconfig /flushdns | Out-Null
            Write-Host "✅ DNS cache flushed" -ForegroundColor Green
        } catch {
            Write-Host "⚠️ Could not flush DNS cache (may need admin rights)" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "❌ DNS fix failed: $($_.Exception.Message)" -ForegroundColor Red
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
Write-Log "Script version: 2.0 (simplified for testing)" -Level "INFO"
Write-Log "Config directory: $ConfigOutputDir" -Level "INFO"
Write-Log "Log file location: $ConfigOutputDir\vault-client.log" -Level "INFO"

# Simple test function
function Test-SimpleFunction {
    Write-Log "Testing simple function call" -Level "INFO"
    return $true
}

# Test the function
Write-Log "Testing function call..." -Level "INFO"
if (Test-SimpleFunction) {
    Write-Log "Function test passed!" -Level "INFO"
} else {
    Write-Log "Function test failed!" -Level "ERROR"
}

# Check log file
Write-Host "`n=== CHECKING LOG FILE ===" -ForegroundColor Cyan
$logFile = "$ConfigOutputDir\vault-client.log"
if (Test-Path $logFile) {
    Write-Host "✅ Log file exists: $logFile" -ForegroundColor Green
    Write-Host "File size: $((Get-Item $logFile).Length) bytes" -ForegroundColor Cyan
    Write-Host "File contents:" -ForegroundColor Cyan
    Get-Content $logFile
} else {
    Write-Host "❌ Log file does not exist: $logFile" -ForegroundColor Red
}

Write-Host "`n=== SIMPLIFIED SCRIPT COMPLETED ===" -ForegroundColor Green
