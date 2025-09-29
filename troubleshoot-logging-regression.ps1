# =============================================================================
# Logging Regression Troubleshooting
# =============================================================================
# This script helps identify what changed that broke logging
# =============================================================================

Write-Host "=== Logging Regression Analysis ===" -ForegroundColor Cyan
Write-Host ""

# Check 1: Recent changes to the script
Write-Host "1. Checking for recent script modifications:" -ForegroundColor Yellow
$scriptPath = ".\vault-client-app.ps1"
if (Test-Path $scriptPath) {
    $lastModified = (Get-Item $scriptPath).LastWriteTime
    Write-Host "   Script last modified: $lastModified" -ForegroundColor White
    
    # Check if script was modified recently (within last 24 hours)
    $recentChange = $lastModified -gt (Get-Date).AddDays(-1)
    if ($recentChange) {
        Write-Host "   ⚠️  Script was modified recently - this might be the cause" -ForegroundColor Yellow
    } else {
        Write-Host "   ✅ Script hasn't been modified recently" -ForegroundColor Green
    }
} else {
    Write-Host "   ❌ Script not found: $scriptPath" -ForegroundColor Red
}
Write-Host ""

# Check 2: Directory permissions
Write-Host "2. Checking directory permissions:" -ForegroundColor Yellow
$defaultDir = "C:\vault-client\config"
Write-Host "   Checking: $defaultDir" -ForegroundColor White

try {
    if (Test-Path $defaultDir) {
        $acl = Get-Acl $defaultDir
        Write-Host "   ✅ Directory exists" -ForegroundColor Green
        
        # Check if we can write to it
        $testFile = "$defaultDir\permission-test.tmp"
        "test" | Out-File -FilePath $testFile -Force -ErrorAction Stop
        if (Test-Path $testFile) {
            Write-Host "   ✅ Write permissions OK" -ForegroundColor Green
            Remove-Item $testFile -Force
        } else {
            Write-Host "   ❌ Write permissions failed" -ForegroundColor Red
        }
    } else {
        Write-Host "   ❌ Directory does not exist" -ForegroundColor Red
        Write-Host "   This is likely the cause of the logging issue" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Permission check failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Check 3: PowerShell execution context
Write-Host "3. Checking PowerShell execution context:" -ForegroundColor Yellow
Write-Host "   Current user: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor White
Write-Host "   Current location: $((Get-Location).Path)" -ForegroundColor White
Write-Host "   Execution policy: $(Get-ExecutionPolicy)" -ForegroundColor White

# Check if running as different user than before
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
if ($currentUser -like "*gmsa*" -or $currentUser -like "*vault-gmsa*") {
    Write-Host "   ✅ Running under gMSA identity" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Running under regular user identity" -ForegroundColor Yellow
    Write-Host "   This might explain why logging stopped working" -ForegroundColor Yellow
}
Write-Host ""

# Check 4: Recent Windows updates or policy changes
Write-Host "4. Checking for system changes:" -ForegroundColor Yellow
$lastBoot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
Write-Host "   Last system boot: $lastBoot" -ForegroundColor White

# Check if system was rebooted recently
$recentBoot = $lastBoot -gt (Get-Date).AddDays(-7)
if ($recentBoot) {
    Write-Host "   ⚠️  System was rebooted recently" -ForegroundColor Yellow
    Write-Host "   This might have reset permissions or policies" -ForegroundColor Yellow
} else {
    Write-Host "   ✅ System hasn't been rebooted recently" -ForegroundColor Green
}
Write-Host ""

# Check 5: Antivirus or security software
Write-Host "5. Checking for security software interference:" -ForegroundColor Yellow
$securityProducts = Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like "*antivirus*" -or $_.Name -like "*security*" -or $_.Name -like "*defender*" } | Select-Object Name
if ($securityProducts) {
    Write-Host "   ⚠️  Security software detected:" -ForegroundColor Yellow
    $securityProducts | ForEach-Object { Write-Host "     $($_.Name)" -ForegroundColor White }
    Write-Host "   This might be blocking file creation" -ForegroundColor Yellow
} else {
    Write-Host "   ✅ No obvious security software interference" -ForegroundColor Green
}
Write-Host ""

# Check 6: Disk space
Write-Host "6. Checking disk space:" -ForegroundColor Yellow
$drive = (Get-Location).Drive
$diskSpace = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $drive.Name }
if ($diskSpace) {
    $freeSpaceGB = [math]::Round($diskSpace.FreeSpace / 1GB, 2)
    Write-Host "   Free space on $($drive.Name): $freeSpaceGB GB" -ForegroundColor White
    if ($freeSpaceGB -lt 1) {
        Write-Host "   ⚠️  Low disk space might be causing issues" -ForegroundColor Yellow
    } else {
        Write-Host "   ✅ Sufficient disk space" -ForegroundColor Green
    }
}
Write-Host ""

# Check 7: Test the actual logging function
Write-Host "7. Testing logging function directly:" -ForegroundColor Yellow
$testDir = ".\test-logs"
try {
    if (-not (Test-Path $testDir)) {
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    }
    
    $testLogFile = "$testDir\test.log"
    $testMessage = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Test message"
    Add-Content -Path $testLogFile -Value $testMessage -ErrorAction Stop
    
    if (Test-Path $testLogFile) {
        Write-Host "   ✅ Logging function works in test directory" -ForegroundColor Green
        Write-Host "   Test log created: $testLogFile" -ForegroundColor White
    } else {
        Write-Host "   ❌ Logging function failed even in test directory" -ForegroundColor Red
    }
} catch {
    Write-Host "   ❌ Logging test failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Summary and recommendations
Write-Host "=== TROUBLESHOOTING SUMMARY ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "Most likely causes for logging regression:" -ForegroundColor Yellow
Write-Host "1. Directory permissions changed (most common)" -ForegroundColor White
Write-Host "2. Running under different user context" -ForegroundColor White
Write-Host "3. Recent system reboot reset policies" -ForegroundColor White
Write-Host "4. Antivirus software blocking file creation" -ForegroundColor White
Write-Host "5. Script modifications introduced bugs" -ForegroundColor White
Write-Host ""

Write-Host "Quick fixes to try:" -ForegroundColor Cyan
Write-Host "1. Run PowerShell as Administrator" -ForegroundColor White
Write-Host "2. Use a different directory: .\vault-client-app.ps1 -ConfigOutputDir '.\logs'" -ForegroundColor White
Write-Host "3. Check if gMSA permissions changed" -ForegroundColor White
Write-Host "4. Temporarily disable antivirus real-time protection" -ForegroundColor White
Write-Host "5. Recreate the C:\vault-client\config directory manually" -ForegroundColor White
Write-Host ""

Write-Host "To restore logging immediately:" -ForegroundColor Green
Write-Host ".\vault-client-app.ps1 -ConfigOutputDir '.\logs'" -ForegroundColor White
