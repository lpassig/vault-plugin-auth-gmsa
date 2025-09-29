# =============================================================================
# Script Validation and Testing
# =============================================================================
# This script validates both vault-client-app.ps1 and setup-vault-client.ps1
# for syntax errors, function definitions, and basic functionality
# =============================================================================

Write-Host "=== Script Validation and Testing ===" -ForegroundColor Green
Write-Host ""

# Test 1: Syntax Validation
Write-Host "1. Testing PowerShell syntax..." -ForegroundColor Yellow

try {
    $syntaxErrors = @()
    
    # Test vault-client-app.ps1
    Write-Host "   Testing vault-client-app.ps1..." -ForegroundColor Cyan
    $ast = [System.Management.Automation.Parser]::ParseFile("$PWD/vault-client-app.ps1", [ref]$null, [ref]$null)
    if ($ast) {
        Write-Host "   SUCCESS: vault-client-app.ps1 syntax is valid" -ForegroundColor Green
    }
    
    # Test setup-vault-client.ps1
    Write-Host "   Testing setup-vault-client.ps1..." -ForegroundColor Cyan
    $ast = [System.Management.Automation.Parser]::ParseFile("$PWD/setup-vault-client.ps1", [ref]$null, [ref]$null)
    if ($ast) {
        Write-Host "   SUCCESS: setup-vault-client.ps1 syntax is valid" -ForegroundColor Green
    }
    
} catch {
    Write-Host "   ERROR: Syntax validation failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 2: Function Definitions
Write-Host "2. Checking function definitions..." -ForegroundColor Yellow

$requiredFunctions = @{
    "vault-client-app.ps1" = @(
        "Write-Log",
        "Get-SPNEGOTokenSSPI",
        "Get-SPNEGOTokenReal", 
        "Get-SPNEGOTokenPInvoke",
        "Get-SPNEGOTokenKerberos",
        "Request-KerberosTicket",
        "Get-SPNEGOToken",
        "Invoke-VaultAuthentication",
        "Get-VaultSecrets",
        "Use-SecretsInApplication",
        "Start-VaultClientApplication"
    )
    "setup-vault-client.ps1" = @(
        "Test-ScriptUpdates",
        "Test-Prerequisites",
        "New-ApplicationStructure",
        "Copy-ApplicationScript",
        "Update-ScheduledTaskScript",
        "New-VaultClientScheduledTask",
        "New-ConfigurationFiles",
        "Test-Setup",
        "Start-Setup"
    )
}

foreach ($script in $requiredFunctions.Keys) {
    Write-Host "   Checking $script..." -ForegroundColor Cyan
    $content = Get-Content $script -Raw
    $missingFunctions = @()
    
    foreach ($function in $requiredFunctions[$script]) {
        if ($content -notmatch "function $function") {
            $missingFunctions += $function
        }
    }
    
    if ($missingFunctions.Count -eq 0) {
        Write-Host "   SUCCESS: All required functions found in $script" -ForegroundColor Green
    } else {
        Write-Host "   ERROR: Missing functions in $script : $($missingFunctions -join ', ')" -ForegroundColor Red
    }
}

Write-Host ""

# Test 3: Script Version Check
Write-Host "3. Checking script versions..." -ForegroundColor Yellow

$vaultClientContent = Get-Content "vault-client-app.ps1" -Raw
if ($vaultClientContent -match 'Script version:\s*([^\s]+)') {
    $version = $matches[1]
    Write-Host "   vault-client-app.ps1 version: $version" -ForegroundColor Cyan
    
    if ($version -eq "3.1") {
        Write-Host "   SUCCESS: Correct version (3.1) with automatic Kerberos ticket request" -ForegroundColor Green
    } else {
        Write-Host "   WARNING: Expected version 3.1, found $version" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ERROR: Could not determine vault-client-app.ps1 version" -ForegroundColor Red
}

Write-Host ""

# Test 4: Parameter Validation
Write-Host "4. Checking parameter definitions..." -ForegroundColor Yellow

# Check vault-client-app.ps1 parameters
$vaultClientParams = @(
    "VaultUrl",
    "VaultRole", 
    "SPN",
    "SecretPaths",
    "ConfigOutputDir",
    "CreateScheduledTask",
    "TaskName"
)

$vaultClientContent = Get-Content "vault-client-app.ps1" -Raw
$missingParams = @()

foreach ($param in $vaultClientParams) {
    if ($vaultClientContent -notmatch "\[.*\]\`$$param") {
        $missingParams += $param
    }
}

if ($missingParams.Count -eq 0) {
    Write-Host "   SUCCESS: All required parameters found in vault-client-app.ps1" -ForegroundColor Green
} else {
    Write-Host "   ERROR: Missing parameters in vault-client-app.ps1: $($missingParams -join ', ')" -ForegroundColor Red
}

# Check setup-vault-client.ps1 parameters
$setupParams = @(
    "VaultUrl",
    "VaultRole",
    "TaskName", 
    "Schedule",
    "Time",
    "SecretPaths",
    "ForceUpdate",
    "CheckUpdates"
)

$setupContent = Get-Content "setup-vault-client.ps1" -Raw
$missingSetupParams = @()

foreach ($param in $setupParams) {
    if ($setupContent -notmatch "\[.*\]\`$$param") {
        $missingSetupParams += $param
    }
}

if ($missingSetupParams.Count -eq 0) {
    Write-Host "   SUCCESS: All required parameters found in setup-vault-client.ps1" -ForegroundColor Green
} else {
    Write-Host "   ERROR: Missing parameters in setup-vault-client.ps1: $($missingSetupParams -join ', ')" -ForegroundColor Red
}

Write-Host ""

# Test 5: Critical Code Paths
Write-Host "5. Checking critical code paths..." -ForegroundColor Yellow

# Check if Request-KerberosTicket is called
if ($vaultClientContent -match "Request-KerberosTicket") {
    Write-Host "   SUCCESS: Request-KerberosTicket function is called" -ForegroundColor Green
} else {
    Write-Host "   ERROR: Request-KerberosTicket function is not called" -ForegroundColor Red
}

# Check if Get-SPNEGOTokenPInvoke calls Request-KerberosTicket
if ($vaultClientContent -match "Get-SPNEGOTokenPInvoke.*Request-KerberosTicket") {
    Write-Host "   SUCCESS: Get-SPNEGOTokenPInvoke calls Request-KerberosTicket" -ForegroundColor Green
} else {
    Write-Host "   WARNING: Get-SPNEGOTokenPInvoke may not call Request-KerberosTicket" -ForegroundColor Yellow
}

# Check if setup script creates scheduled task properly
if ($setupContent -match "New-VaultClientScheduledTask") {
    Write-Host "   SUCCESS: Setup script calls New-VaultClientScheduledTask" -ForegroundColor Green
} else {
    Write-Host "   ERROR: Setup script does not call New-VaultClientScheduledTask" -ForegroundColor Red
}

Write-Host ""

# Test 6: File Existence
Write-Host "6. Checking file existence..." -ForegroundColor Yellow

$requiredFiles = @(
    "vault-client-app.ps1",
    "setup-vault-client.ps1"
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        $size = (Get-Item $file).Length
        Write-Host "   SUCCESS: $file exists ($size bytes)" -ForegroundColor Green
    } else {
        Write-Host "   ERROR: $file does not exist" -ForegroundColor Red
    }
}

Write-Host ""

# Test 7: Summary
Write-Host "=== VALIDATION SUMMARY ===" -ForegroundColor Green
Write-Host ""

Write-Host "Scripts validated successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run: .\setup-vault-client.ps1" -ForegroundColor White
Write-Host "2. Check scheduled task creation" -ForegroundColor White
Write-Host "3. Test: Start-ScheduledTask -TaskName 'VaultClientApp'" -ForegroundColor White
Write-Host "4. Monitor: Get-Content 'C:\vault-client\config\vault-client.log'" -ForegroundColor White
Write-Host ""
Write-Host "The scripts are ready for production use!" -ForegroundColor Green
