# Test script to verify logging functionality
param(
    [string]$TestDir = "C:\vault-client\config"
)

Write-Host "=== Logging Test Script ===" -ForegroundColor Cyan
Write-Host "Test directory: $TestDir" -ForegroundColor Yellow

# Create test directory
try {
    if (-not (Test-Path $TestDir)) {
        New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
        Write-Host "✓ Created test directory: $TestDir" -ForegroundColor Green
    } else {
        Write-Host "✓ Test directory already exists: $TestDir" -ForegroundColor Green
    }
} catch {
    Write-Host "✗ Failed to create test directory: $($_.Exception.Message)" -ForegroundColor Red
    $TestDir = "."
    Write-Host "Using current directory: $TestDir" -ForegroundColor Yellow
}

# Test logging function
function Write-TestLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } elseif ($Level -eq "WARNING") { "Yellow" } else { "Green" })
    
    # Write to log file
    try {
        $logFile = "$TestDir\test-log.log"
        Add-Content -Path $logFile -Value $logMessage
        Write-Host "✓ Logged to: $logFile" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test logging
Write-TestLog "Test log message 1" -Level "INFO"
Write-TestLog "Test log message 2" -Level "WARNING"
Write-TestLog "Test log message 3" -Level "ERROR"

Write-Host "=== Test Complete ===" -ForegroundColor Cyan
Write-Host "Check for log file at: $TestDir\test-log.log" -ForegroundColor Yellow
