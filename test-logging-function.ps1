# Test logging function
param(
    [string]$ConfigOutputDir = "C:\vault-client\config"
)

Write-Host "Testing logging function..." -ForegroundColor Cyan

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

# Test logging
Write-Log "Test message 1" -Level "INFO"
Write-Log "Test warning message" -Level "WARNING"
Write-Log "Test error message" -Level "ERROR"

Write-Host "`nLog file location: $ConfigOutputDir\vault-client.log" -ForegroundColor Cyan
if (Test-Path "$ConfigOutputDir\vault-client.log") {
    Write-Host "✅ Log file created successfully!" -ForegroundColor Green
    Write-Host "Log file contents:" -ForegroundColor Cyan
    Get-Content "$ConfigOutputDir\vault-client.log"
} else {
    Write-Host "❌ Log file not created" -ForegroundColor Red
}
