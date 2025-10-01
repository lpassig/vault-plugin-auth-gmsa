# Minimal test to isolate the logging issue
Write-Host "Starting minimal test..." -ForegroundColor Green

# Test 1: Basic Write-Host
Write-Host "Test 1: Basic Write-Host works" -ForegroundColor Green

# Test 2: Directory creation
$ConfigOutputDir = "C:\vault-client\config"
Write-Host "Test 2: Testing directory creation..." -ForegroundColor Cyan

try {
    if (-not (Test-Path $ConfigOutputDir)) {
        New-Item -ItemType Directory -Path $ConfigOutputDir -Force | Out-Null
        Write-Host "✅ Directory created: $ConfigOutputDir" -ForegroundColor Green
    } else {
        Write-Host "✅ Directory already exists: $ConfigOutputDir" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Directory creation failed: $($_.Exception.Message)" -ForegroundColor Red
    $ConfigOutputDir = "."
    Write-Host "Using current directory: $ConfigOutputDir" -ForegroundColor Yellow
}

# Test 3: Simple logging function
function Write-Log-Simple {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [INFO] $Message"
    Write-Host $logMessage -ForegroundColor Green
    
    # Try to write to file
    try {
        $logFile = "$ConfigOutputDir\test.log"
        Add-Content -Path $logFile -Value $logMessage
        Write-Host "✅ Log written to: $logFile" -ForegroundColor Green
    } catch {
        Write-Host "❌ Log file write failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test 4: Call logging function
Write-Host "Test 3: Testing logging function..." -ForegroundColor Cyan
Write-Log-Simple "This is a test log message"

# Test 5: Check if file was created
Write-Host "Test 4: Checking log file..." -ForegroundColor Cyan
$logFile = "$ConfigOutputDir\test.log"
if (Test-Path $logFile) {
    Write-Host "✅ Log file exists: $logFile" -ForegroundColor Green
    Write-Host "File contents:" -ForegroundColor Cyan
    Get-Content $logFile
} else {
    Write-Host "❌ Log file does not exist: $logFile" -ForegroundColor Red
}

Write-Host "Minimal test completed." -ForegroundColor Green
