# Force SPN Transfer from Computer to gMSA
# This script forcefully removes SPN from computer and registers to gMSA

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$ComputerAccount = "EC2AMAZ-UB1QVDL"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Force SPN Transfer from Computer to gMSA" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "ISSUE:" -ForegroundColor Red
Write-Host "SPN $SPN is stuck on $ComputerAccount and needs to be transferred to $GMSAAccount" -ForegroundColor Red
Write-Host "Vault server expects SPN to be owned by gMSA for valid SPNEGO tokens" -ForegroundColor Red
Write-Host ""

# Check if running as Administrator
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "SUCCESS: Running as Administrator" -ForegroundColor Green
Write-Host ""

# Step 1: Force remove SPN from computer account using -D with specific account
Write-Host "Step 1: Force removing SPN from computer account..." -ForegroundColor Yellow
try {
    Write-Host "Force removing $SPN from $ComputerAccount..." -ForegroundColor Cyan
    
    # Try different approaches to remove the SPN
    $removeCommands = @(
        "setspn -D $SPN $ComputerAccount",
        "setspn -D $SPN",
        "setspn -D $SPN $ComputerAccount$"
    )
    
    foreach ($cmd in $removeCommands) {
        Write-Host "Trying: $cmd" -ForegroundColor Gray
        $removeResult = Invoke-Expression $cmd 2>&1
        Write-Host "Result: $removeResult" -ForegroundColor Gray
        
        if ($removeResult -match "successfully" -or $removeResult -match "deleted" -or $removeResult -match "Updated object") {
            Write-Host "SUCCESS: SPN removed with command: $cmd" -ForegroundColor Green
            break
        }
    }
    
} catch {
    Write-Host "ERROR: Failed to remove SPN from computer account" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 2: Verify SPN is removed
Write-Host "Step 2: Verifying SPN removal..." -ForegroundColor Yellow
try {
    $verifyResult = setspn -Q $SPN 2>&1
    Write-Host "Verification result:" -ForegroundColor White
    Write-Host $verifyResult -ForegroundColor Gray
    
    if ($verifyResult -match "No such SPN found") {
        Write-Host "SUCCESS: SPN successfully removed" -ForegroundColor Green
    } elseif ($verifyResult -match $ComputerAccount) {
        Write-Host "WARNING: SPN still registered to computer account" -ForegroundColor Yellow
        Write-Host "Will try to register anyway..." -ForegroundColor Yellow
    } else {
        Write-Host "INFO: SPN status unclear, proceeding with registration" -ForegroundColor Gray
    }
} catch {
    Write-Host "ERROR: Cannot verify SPN removal" -ForegroundColor Red
}
Write-Host ""

# Step 3: Register SPN to gMSA account
Write-Host "Step 3: Registering SPN to gMSA account..." -ForegroundColor Yellow
try {
    Write-Host "Registering $SPN to $GMSAAccount..." -ForegroundColor Cyan
    
    # Try different approaches to register the SPN
    $addCommands = @(
        "setspn -A $SPN $GMSAAccount",
        "setspn -S $SPN $GMSAAccount"
    )
    
    foreach ($cmd in $addCommands) {
        Write-Host "Trying: $cmd" -ForegroundColor Gray
        $addResult = Invoke-Expression $cmd 2>&1
        Write-Host "Result: $addResult" -ForegroundColor Gray
        
        if ($addResult -match "successfully" -or $addResult -match "registered" -or $addResult -match "Updated object") {
            Write-Host "SUCCESS: SPN registered with command: $cmd" -ForegroundColor Green
            break
        } elseif ($addResult -match "Duplicate SPN found") {
            Write-Host "WARNING: Duplicate SPN still exists, trying next method..." -ForegroundColor Yellow
        }
    }
    
} catch {
    Write-Host "ERROR: Failed to register SPN to gMSA account" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 4: Verify final registration
Write-Host "Step 4: Verifying final SPN registration..." -ForegroundColor Yellow
try {
    $finalResult = setspn -Q $SPN 2>&1
    Write-Host "Final verification result:" -ForegroundColor White
    Write-Host $finalResult -ForegroundColor Gray
    
    if ($finalResult -match $GMSAAccount) {
        Write-Host "SUCCESS: SPN registration verified!" -ForegroundColor Green
        Write-Host "SPN $SPN is now registered to $GMSAAccount" -ForegroundColor Green
    } elseif ($finalResult -match $ComputerAccount) {
        Write-Host "ERROR: SPN still registered to computer account" -ForegroundColor Red
        Write-Host "Manual intervention may be required" -ForegroundColor Red
    } else {
        Write-Host "WARNING: SPN registration status unclear" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Cannot verify final SPN registration" -ForegroundColor Red
}
Write-Host ""

# Step 5: List all SPNs for gMSA account
Write-Host "Step 5: Listing all SPNs for gMSA account..." -ForegroundColor Yellow
try {
    $gmsaSpns = setspn -L $GMSAAccount 2>&1
    Write-Host "SPNs registered to $GMSAAccount:" -ForegroundColor White
    Write-Host $gmsaSpns -ForegroundColor Gray
    
    if ($gmsaSpns -match $SPN) {
        Write-Host "SUCCESS: $SPN found in gMSA SPN list" -ForegroundColor Green
    } else {
        Write-Host "WARNING: $SPN not found in gMSA SPN list" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Cannot list SPNs for gMSA account" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Force SPN Transfer Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "MANUAL COMMANDS (if automated fix failed):" -ForegroundColor Yellow
Write-Host "1. Open Command Prompt as Administrator" -ForegroundColor White
Write-Host "2. Run: setspn -D HTTP/vault.local.lab EC2AMAZ-UB1QVDL" -ForegroundColor Gray
Write-Host "3. Run: setspn -A HTTP/vault.local.lab LOCAL\vault-gmsa$" -ForegroundColor Gray
Write-Host "4. Verify: setspn -Q HTTP/vault.local.lab" -ForegroundColor Gray
Write-Host ""

Write-Host "ALTERNATIVE: Use Active Directory Users and Computers:" -ForegroundColor Yellow
Write-Host "1. Open ADUC as Domain Administrator" -ForegroundColor White
Write-Host "2. Find EC2AMAZ-UB1QVDL computer account" -ForegroundColor White
Write-Host "3. Remove HTTP/vault.local.lab from its SPN list" -ForegroundColor White
Write-Host "4. Find vault-gmsa$ in Managed Service Accounts" -ForegroundColor White
Write-Host "5. Add HTTP/vault.local.lab to its SPN list" -ForegroundColor White
Write-Host ""

Write-Host "NEXT STEPS AFTER SUCCESS:" -ForegroundColor Yellow
Write-Host "1. Test authentication: .\test-gmsa-authentication.ps1" -ForegroundColor White
Write-Host "2. Run scheduled task: Start-ScheduledTask -TaskName 'Vault-gMSA-Authentication'" -ForegroundColor White
Write-Host "3. Check Vault logs for successful authentication" -ForegroundColor White
Write-Host ""
