# Simple test script to verify logging works
param(
    [string]$TestMessage = "Hello from PowerShell!"
)

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } elseif ($Level -eq "WARNING") { "Yellow" } else { "Green" })
}

# Test logging
Write-Log "=== Test Script Started ===" -Level "INFO"
Write-Log "Test message: $TestMessage" -Level "INFO"
Write-Log "Current user: $env:USERNAME" -Level "INFO"
Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" -Level "INFO"
Write-Log "=== Test Script Completed ===" -Level "INFO"
