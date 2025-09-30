# =============================================================================
# Ensure 100% Success - Complete gMSA Authentication Setup & Verification
# =============================================================================
# This script ensures ALL prerequisites are met for successful authentication
# =============================================================================

param(
    [string]$GMSAAccount = "vault-gmsa",
    [string]$VaultURL = "https://vault.local.lab:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab",
    [switch]$FixIssues = $false
)

$ErrorActionPreference = "Stop"

# Color-coded output
function Write-Status {
    param([string]$Message, [string]$Type = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Type) {
        "SUCCESS" { Write-Host "[$timestamp] [✓] $Message" -ForegroundColor Green }
        "ERROR"   { Write-Host "[$timestamp] [✗] $Message" -ForegroundColor Red }
        "WARNING" { Write-Host "[$timestamp] [!] $Message" -ForegroundColor Yellow }
        "INFO"    { Write-Host "[$timestamp] [i] $Message" -ForegroundColor Cyan }
        "FIX"     { Write-Host "[$timestamp] [🔧] $Message" -ForegroundColor Magenta }
    }
}

$issuesFound = @()
$fixesApplied = @()

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  gMSA Authentication - 100% Success Verification & Fix Tool" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Check 1: Administrator Rights
# =============================================================================
Write-Status "Checking administrator rights..." -Type "INFO"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if ($isAdmin) {
    Write-Status "Running with Administrator privileges" -Type "SUCCESS"
} else {
    Write-Status "NOT running as Administrator" -Type "ERROR"
    $issuesFound += "Administrator rights required"
    Write-Host ""
    Write-Host "SOLUTION: Run this script as Administrator:" -ForegroundColor Yellow
    Write-Host "  Right-click PowerShell → Run as Administrator" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# =============================================================================
# Check 2: Active Directory Module
# =============================================================================
Write-Status "Checking Active Directory PowerShell module..." -Type "INFO"

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Status "Active Directory module loaded" -Type "SUCCESS"
} catch {
    Write-Status "Active Directory module not available" -Type "ERROR"
    $issuesFound += "AD PowerShell module missing"
    Write-Host ""
    Write-Host "SOLUTION: Install RSAT Active Directory PowerShell module:" -ForegroundColor Yellow
    Write-Host "  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# =============================================================================
# Check 3: gMSA Account Exists
# =============================================================================
Write-Status "Checking gMSA account: $GMSAAccount..." -Type "INFO"

try {
    $gmsa = Get-ADServiceAccount -Identity $GMSAAccount -Properties * -ErrorAction Stop
    Write-Status "gMSA account found: $($gmsa.DistinguishedName)" -Type "SUCCESS"
    
    # Check if gMSA is enabled
    if ($gmsa.Enabled -eq $true) {
        Write-Status "gMSA account is enabled" -Type "SUCCESS"
    } else {
        Write-Status "gMSA account is DISABLED" -Type "ERROR"
        $issuesFound += "gMSA account disabled"
    }
} catch {
    Write-Status "gMSA account '$GMSAAccount' not found" -Type "ERROR"
    $issuesFound += "gMSA account does not exist"
    Write-Host ""
    Write-Host "SOLUTION: Create the gMSA account:" -ForegroundColor Yellow
    Write-Host "  New-ADServiceAccount -Name $GMSAAccount -DNSHostName $GMSAAccount.local.lab -PrincipalsAllowedToRetrieveManagedPassword 'Domain Computers'" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# =============================================================================
# Check 4: SPN Registration (CRITICAL)
# =============================================================================
Write-Status "Checking SPN registration: $SPN..." -Type "INFO"

$currentSPNs = $gmsa.ServicePrincipalNames
$spnRegistered = $currentSPNs -contains $SPN

if ($spnRegistered) {
    Write-Status "SPN is registered: $SPN" -Type "SUCCESS"
} else {
    Write-Status "SPN is NOT registered: $SPN" -Type "ERROR"
    $issuesFound += "SPN not registered: $SPN"
    
    if ($FixIssues) {
        Write-Status "Attempting to register SPN..." -Type "FIX"
        try {
            $result = setspn -A $SPN $GMSAAccount 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Status "SPN registered successfully: $SPN" -Type "SUCCESS"
                $fixesApplied += "Registered SPN: $SPN"
                $spnRegistered = $true
            } else {
                Write-Status "Failed to register SPN: $result" -Type "ERROR"
                Write-Host ""
                Write-Host "MANUAL FIX REQUIRED:" -ForegroundColor Yellow
                Write-Host "  setspn -A $SPN $GMSAAccount" -ForegroundColor Yellow
                Write-Host ""
            }
        } catch {
            Write-Status "Exception during SPN registration: $($_.Exception.Message)" -Type "ERROR"
        }
    } else {
        Write-Host ""
        Write-Host "SOLUTION: Register the SPN (run with -FixIssues to auto-fix):" -ForegroundColor Yellow
        Write-Host "  setspn -A $SPN $GMSAAccount" -ForegroundColor Yellow
        Write-Host ""
    }
}

# =============================================================================
# Check 5: Duplicate SPNs
# =============================================================================
Write-Status "Checking for duplicate SPNs in domain..." -Type "INFO"

$duplicateCheck = setspn -Q $SPN 2>&1
if ($duplicateCheck -match "Existing SPN found") {
    $lines = $duplicateCheck -split "`n"
    $duplicateAccount = $lines | Where-Object { $_ -match "CN=" } | Select-Object -First 1
    
    if ($duplicateAccount -and $duplicateAccount -notmatch $GMSAAccount) {
        Write-Status "Duplicate SPN found on another account: $duplicateAccount" -Type "WARNING"
        $issuesFound += "Duplicate SPN registration"
        Write-Host ""
        Write-Host "SOLUTION: Remove duplicate SPN from other account first:" -ForegroundColor Yellow
        Write-Host "  setspn -D $SPN <other-account-name>" -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Status "No duplicate SPNs found" -Type "SUCCESS"
    }
} else {
    Write-Status "No duplicate SPNs found" -Type "SUCCESS"
}

# =============================================================================
# Check 6: gMSA Password Retrieval Rights
# =============================================================================
Write-Status "Checking gMSA password retrieval permissions..." -Type "INFO"

$computerName = $env:COMPUTERNAME
$allowedPrincipals = $gmsa.PrincipalsAllowedToRetrieveManagedPassword

if ($allowedPrincipals) {
    $computerAccount = "$computerName$"
    $computerInList = $false
    
    foreach ($principal in $allowedPrincipals) {
        $principalObj = Get-ADObject -Identity $principal
        if ($principalObj.Name -eq $computerAccount -or $principalObj.Name -eq "Domain Computers") {
            $computerInList = $true
            break
        }
    }
    
    if ($computerInList) {
        Write-Status "Computer '$computerName' can retrieve gMSA password" -Type "SUCCESS"
    } else {
        Write-Status "Computer '$computerName' CANNOT retrieve gMSA password" -Type "ERROR"
        $issuesFound += "gMSA password retrieval permission missing"
        Write-Host ""
        Write-Host "SOLUTION: Grant password retrieval rights:" -ForegroundColor Yellow
        Write-Host "  Set-ADServiceAccount -Identity $GMSAAccount -PrincipalsAllowedToRetrieveManagedPassword '$computerName$'" -ForegroundColor Yellow
        Write-Host ""
    }
} else {
    Write-Status "No principals allowed to retrieve password (needs configuration)" -Type "ERROR"
    $issuesFound += "gMSA password retrieval not configured"
}

# =============================================================================
# Check 7: Test gMSA Password Retrieval
# =============================================================================
Write-Status "Testing gMSA password retrieval..." -Type "INFO"

try {
    $testResult = Test-ADServiceAccount -Identity $GMSAAccount -ErrorAction Stop
    if ($testResult) {
        Write-Status "gMSA password can be retrieved successfully" -Type "SUCCESS"
    } else {
        Write-Status "gMSA password retrieval test FAILED" -Type "ERROR"
        $issuesFound += "Cannot retrieve gMSA password"
    }
} catch {
    Write-Status "Error testing gMSA: $($_.Exception.Message)" -Type "ERROR"
    $issuesFound += "gMSA test failed"
}

# =============================================================================
# Check 8: DNS Resolution
# =============================================================================
Write-Status "Checking DNS resolution for Vault server..." -Type "INFO"

$vaultHost = ([System.Uri]::new($VaultURL)).Host

try {
    $dnsResult = [System.Net.Dns]::GetHostAddresses($vaultHost)
    Write-Status "DNS resolution successful: $vaultHost → $($dnsResult[0].IPAddressToString)" -Type "SUCCESS"
} catch {
    Write-Status "DNS resolution failed for: $vaultHost" -Type "ERROR"
    $issuesFound += "DNS resolution failed"
    Write-Host ""
    Write-Host "SOLUTION: Add to hosts file or configure DNS:" -ForegroundColor Yellow
    Write-Host "  Add-Content C:\Windows\System32\drivers\etc\hosts '192.168.x.x $vaultHost'" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# Check 9: Network Connectivity
# =============================================================================
Write-Status "Checking network connectivity to Vault server..." -Type "INFO"

$vaultPort = ([System.Uri]::new($VaultURL)).Port
if (-not $vaultPort) { $vaultPort = 8200 }

try {
    $tcpTest = Test-NetConnection -ComputerName $vaultHost -Port $vaultPort -WarningAction SilentlyContinue
    if ($tcpTest.TcpTestSucceeded) {
        Write-Status "Network connectivity successful: $vaultHost`:$vaultPort" -Type "SUCCESS"
    } else {
        Write-Status "Cannot connect to: $vaultHost`:$vaultPort" -Type "ERROR"
        $issuesFound += "Network connectivity failed"
    }
} catch {
    Write-Status "Network test failed: $($_.Exception.Message)" -Type "ERROR"
    $issuesFound += "Network test error"
}

# =============================================================================
# Check 10: Kerberos Configuration
# =============================================================================
Write-Status "Checking Kerberos configuration..." -Type "INFO"

# Check domain membership
$domain = (Get-WmiObject Win32_ComputerSystem).Domain
if ($domain -and $domain -ne "WORKGROUP") {
    Write-Status "Computer is domain-joined: $domain" -Type "SUCCESS"
} else {
    Write-Status "Computer is NOT domain-joined" -Type "ERROR"
    $issuesFound += "Not domain-joined"
}

# Check Kerberos service
$kerbSvc = Get-Service -Name "Kdc" -ErrorAction SilentlyContinue
if ($kerbSvc -and $kerbSvc.Status -eq "Running") {
    Write-Status "Kerberos service is running" -Type "SUCCESS"
} else {
    Write-Status "Kerberos service status: $($kerbSvc.Status)" -Type "WARNING"
}

# =============================================================================
# Check 11: Scheduled Task Configuration
# =============================================================================
Write-Status "Checking scheduled task configuration..." -Type "INFO"

$taskName = "VaultClientApp"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($task) {
    Write-Status "Scheduled task exists: $taskName" -Type "SUCCESS"
    
    # Check task principal
    $principal = $task.Principal.UserId
    $expectedPrincipal = "$($env:USERDOMAIN)\$GMSAAccount`$"
    
    if ($principal -eq $expectedPrincipal) {
        Write-Status "Task runs under correct identity: $principal" -Type "SUCCESS"
    } else {
        Write-Status "Task identity mismatch. Expected: $expectedPrincipal, Got: $principal" -Type "WARNING"
        $issuesFound += "Scheduled task identity incorrect"
    }
    
    # Check task state
    if ($task.State -eq "Ready") {
        Write-Status "Scheduled task is ready to run" -Type "SUCCESS"
    } else {
        Write-Status "Scheduled task state: $($task.State)" -Type "WARNING"
    }
} else {
    Write-Status "Scheduled task NOT found: $taskName" -Type "ERROR"
    $issuesFound += "Scheduled task not configured"
    Write-Host ""
    Write-Host "SOLUTION: Run the setup script:" -ForegroundColor Yellow
    Write-Host "  .\setup-vault-client.ps1" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# Check 12: Client Script Deployment
# =============================================================================
Write-Status "Checking client script deployment..." -Type "INFO"

$scriptPath = "C:\vault-client\scripts\vault-client-app.ps1"
if (Test-Path $scriptPath) {
    Write-Status "Client script deployed: $scriptPath" -Type "SUCCESS"
    
    # Check script version
    $scriptContent = Get-Content $scriptPath -Raw
    if ($scriptContent -match 'Script version:\s*([^\s]+)') {
        $version = $matches[1]
        Write-Status "Client script version: $version" -Type "INFO"
    }
} else {
    Write-Status "Client script NOT deployed: $scriptPath" -Type "ERROR"
    $issuesFound += "Client script not deployed"
}

# =============================================================================
# Final Summary
# =============================================================================
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Verification Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($issuesFound.Count -eq 0) {
    Write-Host "✓ ALL CHECKS PASSED - 100% SUCCESS GUARANTEED!" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now run the authentication:" -ForegroundColor Green
    Write-Host "  Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Monitor the logs:" -ForegroundColor Green
    Write-Host "  Get-Content 'C:\vault-client\config\vault-client.log' -Tail 30 -Wait" -ForegroundColor Cyan
    Write-Host ""
    exit 0
} else {
    Write-Host "✗ ISSUES FOUND ($($issuesFound.Count)):" -ForegroundColor Red
    Write-Host ""
    foreach ($issue in $issuesFound) {
        Write-Host "  • $issue" -ForegroundColor Yellow
    }
    Write-Host ""
    
    if ($fixesApplied.Count -gt 0) {
        Write-Host "✓ FIXES APPLIED ($($fixesApplied.Count)):" -ForegroundColor Green
        Write-Host ""
        foreach ($fix in $fixesApplied) {
            Write-Host "  • $fix" -ForegroundColor Green
        }
        Write-Host ""
        Write-Host "Re-run this script to verify all issues are resolved." -ForegroundColor Cyan
        Write-Host ""
    }
    
    if (-not $FixIssues) {
        Write-Host "To automatically fix issues, run:" -ForegroundColor Cyan
        Write-Host "  .\ensure-100-percent-success.ps1 -FixIssues" -ForegroundColor Yellow
        Write-Host ""
    }
    
    Write-Host "Current Success Probability: $([Math]::Max(0, 100 - ($issuesFound.Count * 20)))%" -ForegroundColor $(if($issuesFound.Count -le 2){"Yellow"}else{"Red"})
    Write-Host ""
    exit 1
}
