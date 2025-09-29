# =============================================================================
# Quick DNS Fix for Vault gMSA Authentication
# =============================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$VaultIP = "10.0.101.151",
    
    [Parameter(Mandatory=$false)]
    [string]$VaultHostname = "vault.local.lab"
)

Write-Host "=== Quick DNS Fix for Vault gMSA ===" -ForegroundColor Green
Write-Host "This script adds DNS mapping for Kerberos authentication" -ForegroundColor Yellow

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Host "⚠️ WARNING: Not running as Administrator" -ForegroundColor Yellow
    Write-Host "DNS cache flush may not work, but hosts file can still be updated" -ForegroundColor Yellow
}

# Check current DNS resolution
Write-Host "`n🔍 Checking current DNS resolution..." -ForegroundColor Cyan
try {
    $dnsResult = [System.Net.Dns]::GetHostAddresses($VaultHostname)
    Write-Host "✅ $VaultHostname already resolves to: $($dnsResult[0].IPAddressToString)" -ForegroundColor Green
    
    if ($dnsResult[0].IPAddressToString -eq $VaultIP) {
        Write-Host "✅ DNS resolution is correct!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "⚠️ DNS resolves to different IP: $($dnsResult[0].IPAddressToString)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ $VaultHostname does not resolve" -ForegroundColor Red
}

# Add to hosts file
Write-Host "`n🔧 Adding DNS mapping to hosts file..." -ForegroundColor Cyan
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostsEntry = "`n# Vault gMSA DNS fix - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n$VaultIP $VaultHostname"

try {
    # Check if entry already exists
    $hostsContent = Get-Content $hostsPath -ErrorAction SilentlyContinue
    $existingEntry = $hostsContent | Where-Object { $_ -like "*$VaultHostname*" }
    
    if ($existingEntry) {
        Write-Host "⚠️ Entry already exists: $existingEntry" -ForegroundColor Yellow
        
        # Check if it's correct
        if ($existingEntry -like "*$VaultIP*") {
            Write-Host "✅ Existing entry is correct" -ForegroundColor Green
        } else {
            Write-Host "❌ Existing entry has wrong IP, updating..." -ForegroundColor Red
            # Remove old entry and add new one
            $newContent = $hostsContent | Where-Object { $_ -notlike "*$VaultHostname*" }
            $newContent += $hostsEntry
            $newContent | Set-Content $hostsPath -Force
            Write-Host "✅ Updated hosts file with correct IP" -ForegroundColor Green
        }
    } else {
        # Add new entry
        Add-Content -Path $hostsPath -Value $hostsEntry -Force
        Write-Host "✅ Added DNS mapping: $VaultIP → $VaultHostname" -ForegroundColor Green
        Write-Host "📝 Entry added to: $hostsPath" -ForegroundColor Cyan
    }
} catch {
    Write-Host "❌ Failed to update hosts file: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Manual fix: Add '$VaultIP $VaultHostname' to $hostsPath" -ForegroundColor Yellow
    exit 1
}

# Flush DNS cache
Write-Host "`n🔄 Flushing DNS cache..." -ForegroundColor Cyan
try {
    if ($isAdmin) {
        ipconfig /flushdns | Out-Null
        Write-Host "✅ DNS cache flushed successfully" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Cannot flush DNS cache (need admin rights)" -ForegroundColor Yellow
        Write-Host "Run as Administrator or restart the computer" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Failed to flush DNS cache: $($_.Exception.Message)" -ForegroundColor Red
}

# Test DNS resolution
Write-Host "`n🧪 Testing DNS resolution..." -ForegroundColor Cyan
try {
    $testResult = [System.Net.Dns]::GetHostAddresses($VaultHostname)
    Write-Host "✅ $VaultHostname now resolves to: $($testResult[0].IPAddressToString)" -ForegroundColor Green
    
    if ($testResult[0].IPAddressToString -eq $VaultIP) {
        Write-Host "🎉 SUCCESS: DNS resolution is working correctly!" -ForegroundColor Green
    } else {
        Write-Host "❌ DNS still resolves to wrong IP" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ DNS resolution still failing" -ForegroundColor Red
}

# Test connectivity
Write-Host "`n🌐 Testing connectivity..." -ForegroundColor Cyan
try {
    $pingResult = Test-NetConnection -ComputerName $VaultHostname -Port 8200 -WarningAction SilentlyContinue
    if ($pingResult.TcpTestSucceeded) {
        Write-Host "✅ Can connect to $VaultHostname:8200" -ForegroundColor Green
    } else {
        Write-Host "❌ Cannot connect to $VaultHostname:8200" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Connectivity test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== DNS Fix Complete ===" -ForegroundColor Green
Write-Host "You can now run the Vault client script:" -ForegroundColor Yellow
Write-Host ".\vault-client-app.ps1" -ForegroundColor White

Write-Host "`n=== Troubleshooting ===" -ForegroundColor Cyan
Write-Host "If issues persist:" -ForegroundColor Yellow
Write-Host "1. Run as Administrator: Start-Process PowerShell -Verb RunAs" -ForegroundColor White
Write-Host "2. Check hosts file: Get-Content $hostsPath" -ForegroundColor White
Write-Host "3. Test DNS: nslookup $VaultHostname" -ForegroundColor White
Write-Host "4. Test connectivity: Test-NetConnection $VaultHostname -Port 8200" -ForegroundColor White
