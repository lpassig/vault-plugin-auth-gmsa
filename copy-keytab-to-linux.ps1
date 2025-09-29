# =============================================================================
# Copy Keytab to Linux Vault Server
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$LinuxServer,
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "lennart",
    
    [Parameter(Mandatory=$false)]
    [string]$KeytabPath = "C:\vault-keytab.keytab",
    
    [Parameter(Mandatory=$false)]
    [string]$RemotePath = "/home/lennart/vault-keytab.keytab"
)

Write-Host "=== Copy Keytab to Linux Vault Server ===" -ForegroundColor Green

# Check if keytab exists
if (-not (Test-Path $KeytabPath)) {
    Write-Host "❌ Keytab file not found: $KeytabPath" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Keytab found: $KeytabPath" -ForegroundColor Green
Write-Host "📤 Copying to: $Username@$LinuxServer:$RemotePath" -ForegroundColor Cyan

# Copy keytab using SCP
try {
    scp $KeytabPath "${Username}@${LinuxServer}:${RemotePath}"
    Write-Host "✅ Keytab copied successfully!" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to copy keytab: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nAlternative methods:" -ForegroundColor Yellow
    Write-Host "1. Use WinSCP or similar GUI tool" -ForegroundColor White
    Write-Host "2. Use PowerShell with PSCP:" -ForegroundColor White
    Write-Host "   pscp $KeytabPath ${Username}@${LinuxServer}:${RemotePath}" -ForegroundColor White
    Write-Host "3. Manually copy via RDP/SSH" -ForegroundColor White
    exit 1
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Green
Write-Host "1. SSH to the Linux server:" -ForegroundColor Yellow
Write-Host "   ssh $Username@$LinuxServer" -ForegroundColor White
Write-Host "`n2. Convert keytab to base64:" -ForegroundColor Yellow
Write-Host "   base64 -w 0 $RemotePath" -ForegroundColor White
Write-Host "`n3. Use the base64 output in Vault configuration" -ForegroundColor Yellow
Write-Host "`n4. Run the configuration script:" -ForegroundColor Yellow
Write-Host "   .\configure-vault-server.ps1" -ForegroundColor White
