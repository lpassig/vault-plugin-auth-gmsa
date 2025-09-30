# Quick script to add user identity logging to vault-client-app.ps1

$scriptPath = "C:\vault-client\scripts\vault-client-app.ps1"

# Read the current script
$content = Get-Content $scriptPath -Raw

# Find the Start-VaultClientApplication function start
$insertPoint = $content.IndexOf("function Start-VaultClientApplication")

if ($insertPoint -gt 0) {
    # Find the first Write-Log after function declaration
    $logInsertPoint = $content.IndexOf("Write-Log", $insertPoint)
    
    if ($logInsertPoint -gt 0) {
        # Add user identity logging right before the first log
        $userLogging = @"
    
    # Log current user identity for troubleshooting
    try {
        `$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        Write-Log "Running under: `$(`$currentUser.Name)" -Level "INFO"
        Write-Log "Authentication Type: `$(`$currentUser.AuthenticationType)" -Level "INFO"
        
        # Check if running as gMSA
        if (`$currentUser.Name -like "*vault-gmsa*") {
            Write-Log "SUCCESS: Running as gMSA account" -Level "SUCCESS"
        } else {
            Write-Log "WARNING: NOT running as gMSA account - authentication may fail" -Level "WARNING"
            Write-Log "Expected: vault-gmsa$", Actual: `$(`$currentUser.Name)" -Level "WARNING"
        }
    } catch {
        Write-Log "Could not determine current user: `$(`$_.Exception.Message)" -Level "WARNING"
    }
    
"@
        
        $newContent = $content.Insert($logInsertPoint, $userLogging)
        
        # Backup original
        Copy-Item $scriptPath "$scriptPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        # Write updated content
        $newContent | Out-File $scriptPath -Encoding UTF8 -Force
        
        Write-Host "✓ Added user identity logging to $scriptPath" -ForegroundColor Green
        Write-Host "✓ Backup created" -ForegroundColor Green
        Write-Host ""
        Write-Host "Now run the scheduled task again:" -ForegroundColor Yellow
        Write-Host "  Start-ScheduledTask -TaskName 'VaultClientApp'" -ForegroundColor White
        Write-Host "  Start-Sleep -Seconds 5" -ForegroundColor White
        Write-Host "  Get-Content 'C:\vault-client\config\vault-client.log' -Tail 50 | Select-String 'Running under|gMSA'" -ForegroundColor White
    } else {
        Write-Host "✗ Could not find insertion point" -ForegroundColor Red
    }
} else {
    Write-Host "✗ Could not find Start-VaultClientApplication function" -ForegroundColor Red
}
