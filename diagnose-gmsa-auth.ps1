# =============================================================================
# gMSA Authentication Diagnostic Script
# =============================================================================
# This script diagnoses gMSA authentication issues step by step
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$GMSAName = "vault-gmsa"
)

Write-Host "=== gMSA Authentication Diagnostic ===" -ForegroundColor Green
Write-Host "Vault URL: $VaultUrl" -ForegroundColor Cyan
Write-Host "SPN: $SPN" -ForegroundColor Cyan
Write-Host "gMSA: $GMSAName" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Step 1: Check gMSA Account Status
# =============================================================================

Write-Host "Step 1: Checking gMSA Account Status..." -ForegroundColor Yellow

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $gmsa = Get-ADServiceAccount -Identity $GMSAName -ErrorAction Stop
    
    Write-Host "✅ gMSA Account Found:" -ForegroundColor Green
    Write-Host "   Name: $($gmsa.Name)" -ForegroundColor White
    Write-Host "   Enabled: $($gmsa.Enabled)" -ForegroundColor White
    Write-Host "   PasswordLastSet: $($gmsa.PasswordLastSet)" -ForegroundColor White
    
    # Test gMSA functionality
    $gmsaTest = Test-ADServiceAccount -Identity $GMSAName -ErrorAction Stop
    if ($gmsaTest) {
        Write-Host "✅ gMSA Account is working properly" -ForegroundColor Green
    } else {
        Write-Host "❌ gMSA Account is not working properly" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error checking gMSA account: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# =============================================================================
# Step 2: Check SPN Registration
# =============================================================================

Write-Host "Step 2: Checking SPN Registration..." -ForegroundColor Yellow

try {
    $spnList = setspn -L $GMSAName 2>&1
    if ($spnList -match $SPN) {
        Write-Host "✅ SPN '$SPN' is registered for $GMSAName" -ForegroundColor Green
        Write-Host "   Registered SPNs:" -ForegroundColor White
        $spnList | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
    } else {
        Write-Host "❌ SPN '$SPN' is NOT registered for $GMSAName" -ForegroundColor Red
        Write-Host "   Available SPNs:" -ForegroundColor White
        $spnList | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
        Write-Host ""
        Write-Host "🔧 Fix: Register the SPN:" -ForegroundColor Yellow
        Write-Host "   setspn -A $SPN $GMSAName" -ForegroundColor Cyan
    }
} catch {
    Write-Host "❌ Error checking SPN registration: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# =============================================================================
# Step 3: Check DNS Resolution
# =============================================================================

Write-Host "Step 3: Checking DNS Resolution..." -ForegroundColor Yellow

try {
    $vaultHost = [System.Uri]::new($VaultUrl).Host
    Write-Host "   Vault Host: $vaultHost" -ForegroundColor White
    
    $dnsResult = [System.Net.Dns]::GetHostAddresses($vaultHost)
    Write-Host "✅ DNS Resolution successful:" -ForegroundColor Green
    $dnsResult | ForEach-Object { Write-Host "     $($_.IPAddressToString)" -ForegroundColor Gray }
    
    # Check hosts file
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hostsContent = Get-Content $hostsPath -ErrorAction SilentlyContinue
    $vaultEntry = $hostsContent | Where-Object { $_ -match "vault.local.lab" }
    
    if ($vaultEntry) {
        Write-Host "✅ Hosts file entry found:" -ForegroundColor Green
        Write-Host "     $vaultEntry" -ForegroundColor Gray
    } else {
        Write-Host "⚠️ No hosts file entry for vault.local.lab" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ DNS Resolution failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "🔧 Fix: Add hosts file entry:" -ForegroundColor Yellow
    Write-Host "   echo <VAULT_IP> vault.local.lab >> C:\Windows\System32\drivers\etc\hosts" -ForegroundColor Cyan
}

Write-Host ""

# =============================================================================
# Step 4: Check Network Connectivity
# =============================================================================

Write-Host "Step 4: Checking Network Connectivity..." -ForegroundColor Yellow

try {
    $vaultHost = [System.Uri]::new($VaultUrl).Host
    $vaultPort = [System.Uri]::new($VaultUrl).Port
    
    $connection = Test-NetConnection -ComputerName $vaultHost -Port $vaultPort -WarningAction SilentlyContinue
    
    if ($connection.TcpTestSucceeded) {
        Write-Host "✅ Network connectivity successful:" -ForegroundColor Green
        Write-Host "   Host: $vaultHost" -ForegroundColor White
        Write-Host "   Port: $vaultPort" -ForegroundColor White
        Write-Host "   Response Time: $($connection.PingReplyDetails.RoundtripTime)ms" -ForegroundColor White
    } else {
        Write-Host "❌ Network connectivity failed:" -ForegroundColor Red
        Write-Host "   Host: $vaultHost" -ForegroundColor White
        Write-Host "   Port: $vaultPort" -ForegroundColor White
    }
} catch {
    Write-Host "❌ Network connectivity test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# =============================================================================
# Step 5: Check Kerberos Tickets
# =============================================================================

Write-Host "Step 5: Checking Kerberos Tickets..." -ForegroundColor Yellow

try {
    $klistOutput = klist 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Kerberos ticket cache accessible" -ForegroundColor Green
        
        # Check for TGT
        if ($klistOutput -match "krbtgt/LOCAL.LAB") {
            Write-Host "✅ TGT (Ticket Granting Ticket) found" -ForegroundColor Green
        } else {
            Write-Host "❌ No TGT found" -ForegroundColor Red
        }
        
        # Check for service ticket
        if ($klistOutput -match $SPN) {
            Write-Host "✅ Service ticket found for $SPN" -ForegroundColor Green
        } else {
            Write-Host "⚠️ No service ticket found for $SPN" -ForegroundColor Yellow
            Write-Host "🔧 Try requesting service ticket:" -ForegroundColor Yellow
            Write-Host "   klist get $SPN" -ForegroundColor Cyan
        }
        
        Write-Host "   Current tickets:" -ForegroundColor White
        $klistOutput | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
    } else {
        Write-Host "❌ Error accessing Kerberos ticket cache: $klistOutput" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error checking Kerberos tickets: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# =============================================================================
# Step 6: Test Service Ticket Request
# =============================================================================

Write-Host "Step 6: Testing Service Ticket Request..." -ForegroundColor Yellow

try {
    Write-Host "   Requesting service ticket for $SPN..." -ForegroundColor White
    $serviceTicketResult = klist get $SPN 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Service ticket request successful" -ForegroundColor Green
        Write-Host "   Result: $serviceTicketResult" -ForegroundColor Gray
    } else {
        Write-Host "❌ Service ticket request failed:" -ForegroundColor Red
        Write-Host "   Error: $serviceTicketResult" -ForegroundColor Red
        
        # Check if it's a DNS issue
        if ($serviceTicketResult -match "DNS") {
            Write-Host "🔧 DNS issue detected - check hosts file" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "❌ Error requesting service ticket: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# =============================================================================
# Step 7: Check IP SPN Support (if using IP)
# =============================================================================

$vaultHost = [System.Uri]::new($VaultUrl).Host
$isIP = [System.Net.IPAddress]::TryParse($vaultHost, [ref]$null)

if ($isIP) {
    Write-Host "Step 7: Checking IP SPN Support..." -ForegroundColor Yellow
    
    try {
        $tryIPSPN = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters" -Name "TryIPSPN" -ErrorAction SilentlyContinue
        
        if ($tryIPSPN -and $tryIPSPN.TryIPSPN -eq 1) {
            Write-Host "✅ IP SPN support is enabled" -ForegroundColor Green
        } else {
            Write-Host "❌ IP SPN support is NOT enabled" -ForegroundColor Red
            Write-Host "🔧 Fix: Enable IP SPN support:" -ForegroundColor Yellow
            Write-Host "   .\enable-ip-spn-support.ps1" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "❌ Error checking IP SPN support: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
}

# =============================================================================
# Step 8: Test Vault Connectivity
# =============================================================================

Write-Host "Step 8: Testing Vault Connectivity..." -ForegroundColor Yellow

try {
    # Test basic HTTP connectivity
    $response = Invoke-WebRequest -Uri "$VaultUrl/v1/sys/health" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    
    Write-Host "✅ Vault server is reachable" -ForegroundColor Green
    Write-Host "   Status Code: $($response.StatusCode)" -ForegroundColor White
    Write-Host "   Response Time: $($response.Headers.'X-Response-Time')" -ForegroundColor White
} catch {
    Write-Host "❌ Vault server connectivity failed: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode
        Write-Host "   HTTP Status: $statusCode" -ForegroundColor White
    }
}

Write-Host ""

# =============================================================================
# Summary and Recommendations
# =============================================================================

Write-Host "=== DIAGNOSTIC SUMMARY ===" -ForegroundColor Green
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Fix any issues identified above" -ForegroundColor White
Write-Host "2. Run the diagnostic again to verify fixes" -ForegroundColor White
Write-Host "3. Test authentication with: .\vault-client-app.ps1 -VaultUrl `"$VaultUrl`"" -ForegroundColor White
Write-Host ""

Write-Host "Common Fixes:" -ForegroundColor Yellow
Write-Host "• Register SPN: setspn -A $SPN $GMSAName" -ForegroundColor Cyan
Write-Host "• Add hosts entry: echo <VAULT_IP> vault.local.lab >> C:\Windows\System32\drivers\etc\hosts" -ForegroundColor Cyan
Write-Host "• Enable IP SPN: .\enable-ip-spn-support.ps1" -ForegroundColor Cyan
Write-Host "• Request ticket: klist get $SPN" -ForegroundColor Cyan
Write-Host "• Flush DNS: ipconfig /flushdns" -ForegroundColor Cyan
