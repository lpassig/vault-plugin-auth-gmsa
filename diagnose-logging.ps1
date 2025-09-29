# =============================================================================
# Logging Diagnostic Script for Windows
# =============================================================================
# This script helps diagnose logging issues with vault-client-app.ps1
# =============================================================================

param(
    [string]$TestDir = "C:\vault-client\config",
    [string]$AltDir = ".\logs"
)

Write-Host "=== Logging Diagnostic Script ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check current directory
Write-Host "1. Current Directory:" -ForegroundColor Yellow
Write-Host "   $((Get-Location).Path)" -ForegroundColor White
Write-Host ""

# Test 2: Check if running as Administrator
Write-Host "2. Administrator Check:" -ForegroundColor Yellow
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if ($isAdmin) {
    Write-Host "   ✅ Running as Administrator" -ForegroundColor Green
} else {
    Write-Host "   ❌ NOT running as Administrator" -ForegroundColor Red
    Write-Host "   Note: This may prevent directory creation" -ForegroundColor Yellow
}
Write-Host ""

# Test 3: Test directory creation
Write-Host "3. Directory Creation Test:" -ForegroundColor Yellow
Write-Host "   Testing: $TestDir" -ForegroundColor White

try {
    if (-not (Test-Path $TestDir)) {
        Write-Host "   Directory does not exist, attempting to create..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
        Write-Host "   ✅ Directory created successfully" -ForegroundColor Green
    } else {
        Write-Host "   ✅ Directory already exists" -ForegroundColor Green
    }
    
    # Test write permissions
    $testFile = "$TestDir\test-write.tmp"
    "Test content" | Out-File -FilePath $testFile -Force
    if (Test-Path $testFile) {
        Write-Host "   ✅ Write permissions confirmed" -ForegroundColor Green
        Remove-Item $testFile -Force
    } else {
        Write-Host "   ❌ Write permissions failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "   ❌ Directory creation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Trying alternative directory: $AltDir" -ForegroundColor Yellow
    
    try {
        if (-not (Test-Path $AltDir)) {
            New-Item -ItemType Directory -Path $AltDir -Force | Out-Null
        }
        Write-Host "   ✅ Alternative directory created: $AltDir" -ForegroundColor Green
        $TestDir = $AltDir
    } catch {
        Write-Host "   ❌ Alternative directory creation also failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Using current directory for logs" -ForegroundColor Yellow
        $TestDir = "."
    }
}
Write-Host ""

# Test 4: Test logging function
Write-Host "4. Logging Function Test:" -ForegroundColor Yellow

function Test-WriteLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogDir
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } elseif ($Level -eq "WARNING") { "Yellow" } else { "Green" })
    
    # Also write to log file
    try {
        $logFile = "$LogDir\vault-client-test.log"
        Add-Content -Path $logFile -Value $logMessage -ErrorAction Stop
        Write-Host "   ✅ Log written to: $logFile" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "   ❌ Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Test the logging function
$logSuccess = Test-WriteLog -Message "Test log entry" -Level "INFO" -LogDir $TestDir
Write-Host ""

# Test 5: Check log file
Write-Host "5. Log File Verification:" -ForegroundColor Yellow
$logFile = "$TestDir\vault-client-test.log"
if (Test-Path $logFile) {
    Write-Host "   ✅ Log file exists: $logFile" -ForegroundColor Green
    Write-Host "   File size: $((Get-Item $logFile).Length) bytes" -ForegroundColor White
    Write-Host "   Content:" -ForegroundColor White
    Get-Content $logFile | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
} else {
    Write-Host "   ❌ Log file not found: $logFile" -ForegroundColor Red
}
Write-Host ""

# Test 6: Check PowerShell execution policy
Write-Host "6. PowerShell Execution Policy:" -ForegroundColor Yellow
$executionPolicy = Get-ExecutionPolicy
Write-Host "   Current policy: $executionPolicy" -ForegroundColor White
if ($executionPolicy -eq "Restricted") {
    Write-Host "   ⚠️  Execution policy is Restricted - this may prevent script execution" -ForegroundColor Yellow
} else {
    Write-Host "   ✅ Execution policy allows script execution" -ForegroundColor Green
}
Write-Host ""

# Test 7: Check gMSA availability
Write-Host "7. gMSA Availability Test:" -ForegroundColor Yellow
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $gmsaTest = Test-ADServiceAccount -Identity "vault-gmsa" -ErrorAction Stop
    if ($gmsaTest) {
        Write-Host "   ✅ gMSA 'vault-gmsa' is available" -ForegroundColor Green
    } else {
        Write-Host "   ❌ gMSA 'vault-gmsa' is not working" -ForegroundColor Red
    }
} catch {
    Write-Host "   ❌ Cannot test gMSA: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Make sure RSAT Active Directory PowerShell module is installed" -ForegroundColor Yellow
}
Write-Host ""

# Summary
Write-Host "=== DIAGNOSTIC SUMMARY ===" -ForegroundColor Cyan
Write-Host "Recommended log directory: $TestDir" -ForegroundColor White
Write-Host "Logging function test: $(if ($logSuccess) { 'PASSED' } else { 'FAILED' })" -ForegroundColor $(if ($logSuccess) { 'Green' } else { 'Red' })
Write-Host ""

if (-not $logSuccess) {
    Write-Host "=== TROUBLESHOOTING RECOMMENDATIONS ===" -ForegroundColor Red
    Write-Host "1. Run PowerShell as Administrator" -ForegroundColor Yellow
    Write-Host "2. Check disk space and permissions" -ForegroundColor Yellow
    Write-Host "3. Try using a different directory (e.g., .\logs)" -ForegroundColor Yellow
    Write-Host "4. Check antivirus software blocking file creation" -ForegroundColor Yellow
    Write-Host "5. Verify PowerShell execution policy" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To fix the vault-client-app.ps1 script:" -ForegroundColor Cyan
    Write-Host "1. Change ConfigOutputDir parameter to a writable location" -ForegroundColor White
    Write-Host "2. Or run: .\vault-client-app.ps1 -ConfigOutputDir '.\logs'" -ForegroundColor White
} else {
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "Logging is working correctly!" -ForegroundColor Green
    Write-Host "You can now run vault-client-app.ps1 with:" -ForegroundColor Cyan
    Write-Host ".\vault-client-app.ps1 -ConfigOutputDir '$TestDir'" -ForegroundColor White
}
