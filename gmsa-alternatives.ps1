# gMSA Scheduled Task Alternative Solutions
# This script provides alternative approaches when scheduled tasks fail with error 267011

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$ScriptPath = "C:\vault-client\debug-gmsa-auth.ps1"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "gMSA Alternative Solutions" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

Write-Host "SUCCESS: Running as Administrator" -ForegroundColor Green
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  gMSA Account: $GMSAAccount" -ForegroundColor White
Write-Host "  Script Path: $ScriptPath" -ForegroundColor White
Write-Host ""

# Step 1: Create Windows Service instead of scheduled task
Write-Host "Step 1: Creating Windows Service..." -ForegroundColor Yellow
try {
    # Remove existing service if it exists
    $serviceName = "VaultGMSADebug"
    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $serviceName | Out-Null
        Write-Host "Removed existing service" -ForegroundColor Gray
    }
    
    # Create new service
    $binPath = "PowerShell -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $createCmd = "sc create $serviceName binPath= `"$binPath`" start= demand obj= `"$GMSAAccount`""
    
    Write-Host "Creating service with command:" -ForegroundColor Cyan
    Write-Host "  $createCmd" -ForegroundColor Gray
    
    Invoke-Expression $createCmd | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: Windows Service created successfully!" -ForegroundColor Green
        Write-Host "  Service Name: $serviceName" -ForegroundColor Gray
        Write-Host "  Account: $GMSAAccount" -ForegroundColor Gray
        Write-Host "  Script: $ScriptPath" -ForegroundColor Gray
        
        # Test the service
        Write-Host "Testing service execution..." -ForegroundColor Cyan
        Start-Service -Name $serviceName
        Start-Sleep -Seconds 10
        
        $serviceStatus = Get-Service -Name $serviceName
        Write-Host "Service Status: $($serviceStatus.Status)" -ForegroundColor White
        
        if ($serviceStatus.Status -eq "Running") {
            Write-Host "SUCCESS: Service started successfully!" -ForegroundColor Green
        } else {
            Write-Host "WARNING: Service status: $($serviceStatus.Status)" -ForegroundColor Yellow
        }
        
        # Stop the service
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        Write-Host "Service stopped for testing" -ForegroundColor Gray
        
    } else {
        Write-Host "ERROR: Failed to create Windows Service" -ForegroundColor Red
    }
    
} catch {
    Write-Host "ERROR: Windows Service creation failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 2: Create a batch file wrapper
Write-Host "Step 2: Creating batch file wrapper..." -ForegroundColor Yellow
try {
    $batchPath = "C:\vault-client\run-gmsa-debug.bat"
    $batchContent = @"
@echo off
echo Starting gMSA debug script...
PowerShell -ExecutionPolicy Bypass -File "$ScriptPath"
echo Debug script completed.
pause
"@
    
    $batchContent | Out-File -FilePath $batchPath -Encoding ASCII
    Write-Host "SUCCESS: Batch file created: $batchPath" -ForegroundColor Green
    
    # Test the batch file
    Write-Host "Testing batch file execution..." -ForegroundColor Cyan
    $batchResult = Start-Process -FilePath $batchPath -Wait -PassThru -WindowStyle Hidden
    Write-Host "Batch file exit code: $($batchResult.ExitCode)" -ForegroundColor White
    
} catch {
    Write-Host "ERROR: Batch file creation failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 3: Create a PowerShell wrapper with different execution context
Write-Host "Step 3: Creating PowerShell wrapper..." -ForegroundColor Yellow
try {
    $wrapperPath = "C:\vault-client\gmsa-wrapper.ps1"
    $wrapperContent = @"
# gMSA Wrapper Script
# This script runs the debug script in a different execution context

Write-Host "gMSA Wrapper Starting..." -ForegroundColor Cyan
Write-Host "Current Identity: `$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor White

# Try to run the debug script
try {
    Write-Host "Executing debug script..." -ForegroundColor Yellow
    & "$ScriptPath"
    Write-Host "Debug script completed successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Debug script failed" -ForegroundColor Red
    Write-Host "Error: `$(`$_.Exception.Message)" -ForegroundColor Red
}

Write-Host "gMSA Wrapper Completed" -ForegroundColor Cyan
"@
    
    $wrapperContent | Out-File -FilePath $wrapperPath -Encoding UTF8
    Write-Host "SUCCESS: PowerShell wrapper created: $wrapperPath" -ForegroundColor Green
    
    # Test the wrapper
    Write-Host "Testing PowerShell wrapper..." -ForegroundColor Cyan
    $wrapperResult = Start-Process -FilePath "PowerShell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$wrapperPath`"" -Wait -PassThru -WindowStyle Hidden
    Write-Host "Wrapper exit code: $($wrapperResult.ExitCode)" -ForegroundColor White
    
} catch {
    Write-Host "ERROR: PowerShell wrapper creation failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 4: Test direct script execution
Write-Host "Step 4: Testing direct script execution..." -ForegroundColor Yellow
try {
    Write-Host "Running debug script directly..." -ForegroundColor Cyan
    $directResult = Start-Process -FilePath "PowerShell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$ScriptPath`"" -Wait -PassThru -WindowStyle Hidden
    Write-Host "Direct execution exit code: $($directResult.ExitCode)" -ForegroundColor White
    
    if ($directResult.ExitCode -eq 0) {
        Write-Host "SUCCESS: Direct execution worked!" -ForegroundColor Green
        Write-Host "The script itself is working - issue is with scheduled task permissions" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Direct execution failed with code: $($directResult.ExitCode)" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Direct execution failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 5: Create a simple test script
Write-Host "Step 5: Creating simple test script..." -ForegroundColor Yellow
try {
    $testPath = "C:\vault-client\simple-test.ps1"
    $testContent = @"
# Simple gMSA Test Script
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Simple gMSA Test" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Current Identity: `$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor White
Write-Host "Current User: `$env:USERNAME" -ForegroundColor White
Write-Host "Current Domain: `$env:USERDOMAIN" -ForegroundColor White
Write-Host ""

Write-Host "Kerberos Tickets:" -ForegroundColor Yellow
try {
    klist
} catch {
    Write-Host "Could not run klist: `$(`$_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "Vault Connectivity Test:" -ForegroundColor Yellow
try {
    `$response = Invoke-WebRequest -Uri "http://10.0.101.8:8200/v1/sys/health" -UseBasicParsing -TimeoutSec 5
    Write-Host "SUCCESS: Vault server reachable (Status: `$(`$response.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Vault server not reachable: `$(`$_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "Test completed at: `$(Get-Date)" -ForegroundColor Cyan
"@
    
    $testContent | Out-File -FilePath $testPath -Encoding UTF8
    Write-Host "SUCCESS: Simple test script created: $testPath" -ForegroundColor Green
    
    # Test the simple script
    Write-Host "Testing simple script..." -ForegroundColor Cyan
    $testResult = Start-Process -FilePath "PowerShell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$testPath`"" -Wait -PassThru -WindowStyle Hidden
    Write-Host "Simple test exit code: $($testResult.ExitCode)" -ForegroundColor White
    
} catch {
    Write-Host "ERROR: Simple test script creation failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Alternative Solutions Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "CREATED FILES:" -ForegroundColor Yellow
Write-Host "1. Windows Service: VaultGMSADebug" -ForegroundColor White
Write-Host "2. Batch Wrapper: C:\vault-client\run-gmsa-debug.bat" -ForegroundColor White
Write-Host "3. PowerShell Wrapper: C:\vault-client\gmsa-wrapper.ps1" -ForegroundColor White
Write-Host "4. Simple Test: C:\vault-client\simple-test.ps1" -ForegroundColor White
Write-Host ""

Write-Host "MANUAL TESTING COMMANDS:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Test Windows Service:" -ForegroundColor White
Write-Host "   Start-Service -Name VaultGMSADebug" -ForegroundColor Gray
Write-Host "   Get-Service -Name VaultGMSADebug" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Test Batch Wrapper:" -ForegroundColor White
Write-Host "   C:\vault-client\run-gmsa-debug.bat" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Test PowerShell Wrapper:" -ForegroundColor White
Write-Host "   PowerShell -ExecutionPolicy Bypass -File C:\vault-client\gmsa-wrapper.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Test Simple Script:" -ForegroundColor White
Write-Host "   PowerShell -ExecutionPolicy Bypass -File C:\vault-client\simple-test.ps1" -ForegroundColor Gray
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Try the Windows Service approach (most likely to work)" -ForegroundColor White
Write-Host "2. Test the simple script to verify basic functionality" -ForegroundColor White
Write-Host "3. If service works, configure it to start automatically" -ForegroundColor White
Write-Host "4. Use the service instead of scheduled tasks for gMSA execution" -ForegroundColor White
Write-Host ""

Write-Host "SERVICE CONFIGURATION:" -ForegroundColor Cyan
Write-Host "To make the service start automatically:" -ForegroundColor White
Write-Host "   sc config VaultGMSADebug start= auto" -ForegroundColor Gray
Write-Host ""
Write-Host "To start the service:" -ForegroundColor White
Write-Host "   Start-Service -Name VaultGMSADebug" -ForegroundColor Gray
Write-Host ""
Write-Host "To check service status:" -ForegroundColor White
Write-Host "   Get-Service -Name VaultGMSADebug" -ForegroundColor Gray
Write-Host ""
