# PowerShell Environment Diagnostic Script
Write-Host "=== PowerShell Environment Diagnostic ===" -ForegroundColor Green

# Check PowerShell version
Write-Host "`nPowerShell Version:" -ForegroundColor Cyan
$PSVersionTable.PSVersion

# Check execution policy
Write-Host "`nExecution Policy:" -ForegroundColor Cyan
Get-ExecutionPolicy -List

# Check if running as administrator
Write-Host "`nAdministrator Check:" -ForegroundColor Cyan
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
Write-Host "Running as Administrator: $isAdmin" -ForegroundColor $(if ($isAdmin) { "Green" } else { "Yellow" })

# Check current directory
Write-Host "`nCurrent Directory:" -ForegroundColor Cyan
Get-Location

# Check if script files exist
Write-Host "`nScript Files Check:" -ForegroundColor Cyan
$scripts = @("vault-client-app.ps1", "minimal-test.ps1", "debug-vault-client.ps1")
foreach ($script in $scripts) {
    if (Test-Path $script) {
        Write-Host "✅ $script exists" -ForegroundColor Green
    } else {
        Write-Host "❌ $script missing" -ForegroundColor Red
    }
}

# Test basic file operations
Write-Host "`nFile Operations Test:" -ForegroundColor Cyan
$testDir = "C:\vault-client\config"
try {
    if (-not (Test-Path $testDir)) {
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Write-Host "✅ Directory created: $testDir" -ForegroundColor Green
    } else {
        Write-Host "✅ Directory exists: $testDir" -ForegroundColor Green
    }
    
    # Test file writing
    $testFile = "$testDir\test.txt"
    "Test content" | Out-File -FilePath $testFile -Force
    if (Test-Path $testFile) {
        Write-Host "✅ File write test passed" -ForegroundColor Green
        Remove-Item $testFile -Force
    } else {
        Write-Host "❌ File write test failed" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ File operations failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test Add-Type
Write-Host "`nAdd-Type Test:" -ForegroundColor Cyan
try {
    Add-Type -AssemblyName System.Net.Http
    Write-Host "✅ Add-Type System.Net.Http succeeded" -ForegroundColor Green
} catch {
    Write-Host "❌ Add-Type System.Net.Http failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test .NET classes
Write-Host "`n.NET Classes Test:" -ForegroundColor Cyan
try {
    $uri = [System.Uri]::new("https://vault.example.com:8200")
    Write-Host "✅ System.Uri test passed: $($uri.Host)" -ForegroundColor Green
} catch {
    Write-Host "❌ System.Uri test failed: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    $dns = [System.Net.Dns]::GetHostAddresses("localhost")
    Write-Host "✅ System.Net.Dns test passed" -ForegroundColor Green
} catch {
    Write-Host "❌ System.Net.Dns test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Diagnostic Complete ===" -ForegroundColor Green
