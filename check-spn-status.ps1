# Check Current SPN Registration Status
# This script verifies the current SPN registration for gMSA authentication

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$SPN = "HTTP/vault.local.lab"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SPN Registration Status Check" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "CONFIGURATION:" -ForegroundColor Yellow
Write-Host "  gMSA Account: $GMSAAccount" -ForegroundColor White
Write-Host "  Required SPN: $SPN" -ForegroundColor White
Write-Host "  Vault Server: Expects SPN HTTP/vault.local.lab@LOCAL.LAB" -ForegroundColor White
Write-Host ""

# Check if running as Administrator
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "WARNING: Not running as Administrator - some checks may fail" -ForegroundColor Yellow
} else {
    Write-Host "SUCCESS: Running as Administrator" -ForegroundColor Green
}
Write-Host ""

# Step 1: Check current SPN registration
Write-Host "Step 1: Current SPN Registration:" -ForegroundColor Yellow
try {
    $spnResult = setspn -Q $SPN 2>&1
    Write-Host "SPN query result:" -ForegroundColor White
    Write-Host $spnResult -ForegroundColor Gray
    
    if ($spnResult -match $GMSAAccount) {
        Write-Host "SUCCESS: SPN $SPN is registered to $GMSAAccount" -ForegroundColor Green
    } elseif ($spnResult -match "No such SPN found") {
        Write-Host "ERROR: SPN $SPN is not registered anywhere" -ForegroundColor Red
    } else {
        Write-Host "WARNING: SPN $SPN is registered to a different account" -ForegroundColor Yellow
        Write-Host "Current registration: $spnResult" -ForegroundColor Gray
    }
} catch {
    Write-Host "ERROR: Cannot query SPN registration" -ForegroundColor Red
}
Write-Host ""

# Step 2: List all SPNs for gMSA account
Write-Host "Step 2: All SPNs for gMSA Account:" -ForegroundColor Yellow
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

# Step 3: Check DNS resolution
Write-Host "Step 3: DNS Resolution Check:" -ForegroundColor Yellow
try {
    $dnsResult = [System.Net.Dns]::GetHostAddresses("vault.local.lab")
    Write-Host "SUCCESS: vault.local.lab resolves to: $($dnsResult[0].IPAddressToString)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: vault.local.lab DNS resolution failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SPN Registration Analysis" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "REQUIRED CONFIGURATION:" -ForegroundColor Yellow
Write-Host "1. SPN: HTTP/vault.local.lab" -ForegroundColor White
Write-Host "2. Owner: LOCAL\vault-gmsa$ (gMSA account)" -ForegroundColor White
Write-Host "3. Vault Server: Configured with same SPN in keytab" -ForegroundColor White
Write-Host "4. DNS: vault.local.lab resolves to Vault server IP" -ForegroundColor White
Write-Host ""

Write-Host "AUTHENTICATION FLOW:" -ForegroundColor Yellow
Write-Host "1. Scheduled task runs under LOCAL\vault-gmsa$" -ForegroundColor White
Write-Host "2. Windows requests Kerberos ticket for HTTP/vault.local.lab" -ForegroundColor White
Write-Host "3. Ticket is signed with gMSA's credentials" -ForegroundColor White
Write-Host "4. Vault server validates ticket using keytab with same SPN" -ForegroundColor White
Write-Host "5. Authentication succeeds" -ForegroundColor White
Write-Host ""

Write-Host "DO YOU NEED 2 SPNs?" -ForegroundColor Yellow
Write-Host "NO - You only need ONE SPN:" -ForegroundColor White
Write-Host "  HTTP/vault.local.lab registered to LOCAL\vault-gmsa$" -ForegroundColor Green
Write-Host ""
Write-Host "The gMSA account and Vault server share the same SPN." -ForegroundColor White
Write-Host "This allows mutual authentication between them." -ForegroundColor White
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Ensure SPN HTTP/vault.local.lab is registered to LOCAL\vault-gmsa$" -ForegroundColor White
Write-Host "2. Verify Vault server keytab contains the same SPN" -ForegroundColor White
Write-Host "3. Test authentication with scheduled task" -ForegroundColor White
Write-Host ""

if ($spnResult -match $GMSAAccount) {
    Write-Host "STATUS: SPN registration looks correct!" -ForegroundColor Green
    Write-Host "If authentication is still failing, check Vault server keytab." -ForegroundColor White
} else {
    Write-Host "STATUS: SPN registration needs to be fixed." -ForegroundColor Red
    Write-Host "Run: .\force-spn-transfer.ps1" -ForegroundColor White
}
Write-Host ""
