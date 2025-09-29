# =============================================================================
# Quick Fix for Logging Issues
# =============================================================================
# This script provides immediate fixes for common logging problems
# =============================================================================

param(
    [string]$ScriptPath = ".\vault-client-app.ps1",
    [string]$LogDir = ".\logs"
)

Write-Host "=== Quick Logging Fix ===" -ForegroundColor Cyan
Write-Host ""

# Create logs directory in current location
Write-Host "Creating logs directory: $LogDir" -ForegroundColor Yellow
try {
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Write-Host "✅ Logs directory created" -ForegroundColor Green
    } else {
        Write-Host "✅ Logs directory already exists" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Failed to create logs directory: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Using current directory for logs" -ForegroundColor Yellow
    $LogDir = "."
}

Write-Host ""
Write-Host "=== Running vault-client-app.ps1 with fixed logging ===" -ForegroundColor Cyan
Write-Host "Command: $ScriptPath -ConfigOutputDir '$LogDir'" -ForegroundColor White
Write-Host ""

# Run the script with the fixed log directory
try {
    & $ScriptPath -ConfigOutputDir $LogDir
} catch {
    Write-Host "❌ Script execution failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Check for log files ===" -ForegroundColor Cyan
$logFiles = Get-ChildItem -Path $LogDir -Filter "*.log" -ErrorAction SilentlyContinue
if ($logFiles) {
    Write-Host "✅ Found log files:" -ForegroundColor Green
    $logFiles | ForEach-Object { 
        Write-Host "   $($_.Name) ($($_.Length) bytes)" -ForegroundColor White
    }
} else {
    Write-Host "❌ No log files found in $LogDir" -ForegroundColor Red
    Write-Host "Check the script output above for errors" -ForegroundColor Yellow
}
