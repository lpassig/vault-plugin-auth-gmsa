# Diagnostic script for Step 7 failure
# Run this to check all components

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Diagnosing gMSA Authentication Failure" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check current user identity
Write-Host "[1] Current User Identity:" -ForegroundColor Yellow
whoami
whoami /groups | Select-String "vault-gmsa" -Context 0,2
Write-Host ""

# 2. Check gMSA status
Write-Host "[2] gMSA Status:" -ForegroundColor Yellow
Test-ADServiceAccount -Identity vault-gmsa
Write-Host ""

# 3. Check SPN registration
Write-Host "[3] SPN Registration:" -ForegroundColor Yellow
setspn -L vault-gmsa
Write-Host ""

# 4. Check Kerberos tickets
Write-Host "[4] Kerberos Tickets:" -ForegroundColor Yellow
klist
Write-Host ""

# 5. Try to get service ticket
Write-Host "[5] Requesting Service Ticket:" -ForegroundColor Yellow
klist get HTTP/vault.local.lab
Start-Sleep -Seconds 2
klist | Select-String "HTTP/vault.local.lab" -Context 2,2
Write-Host ""

# 6. Check DNS resolution
Write-Host "[6] DNS Resolution:" -ForegroundColor Yellow
Resolve-DnsName vault.local.lab -ErrorAction SilentlyContinue
Write-Host ""

# 7. Check network connectivity
Write-Host "[7] Network Connectivity:" -ForegroundColor Yellow
Test-NetConnection -ComputerName vault.local.lab -Port 8200 -InformationLevel Detailed -WarningAction SilentlyContinue
Write-Host ""

# 8. Check if running as gMSA
Write-Host "[8] Running as gMSA Check:" -ForegroundColor Yellow
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
Write-Host "  Name: $($currentUser.Name)"
Write-Host "  Auth Type: $($currentUser.AuthenticationType)"
Write-Host "  Is System: $($currentUser.IsSystem)"
Write-Host "  Is Anonymous: $($currentUser.IsAnonymous)"
Write-Host ""

# 9. Check scheduled task configuration
Write-Host "[9] Scheduled Task Configuration:" -ForegroundColor Yellow
$task = Get-ScheduledTask -TaskName "VaultClientApp" -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "  User: $($task.Principal.UserId)"
    Write-Host "  LogonType: $($task.Principal.LogonType)"
    Write-Host "  RunLevel: $($task.Principal.RunLevel)"
} else {
    Write-Host "  Task not found!"
}
Write-Host ""

# 10. Test manual SPNEGO generation
Write-Host "[10] Testing Manual SPNEGO Generation:" -ForegroundColor Yellow
try {
    $request = [System.Net.WebRequest]::Create("https://vault.local.lab:8200/v1/sys/health")
    $request.UseDefaultCredentials = $true
    $request.PreAuthenticate = $true
    $request.ServerCertificateValidationCallback = {$true}
    
    try {
        $response = $request.GetResponse()
        Write-Host "  Response Status: $($response.StatusCode)"
        $response.Close()
    } catch {
        Write-Host "  Request failed (expected): $($_.Exception.Message)"
    }
    
    if ($request.Headers["Authorization"]) {
        Write-Host "  Authorization Header: Present"
        $authHeader = $request.Headers["Authorization"]
        if ($authHeader -match "Negotiate (.+)") {
            Write-Host "  Token Length: $($matches[1].Length) characters"
            Write-Host "  Token Preview: $($matches[1].Substring(0, [Math]::Min(50, $matches[1].Length)))..."
        }
    } else {
        Write-Host "  Authorization Header: NOT PRESENT"
    }
} catch {
    Write-Host "  Error: $($_.Exception.Message)"
}
Write-Host ""

# 11. Check logs
Write-Host "[11] Recent Log Entries:" -ForegroundColor Yellow
$logFile = "C:\vault-client\config\vault-client.log"
if (Test-Path $logFile) {
    Get-Content $logFile -Tail 30 | Select-String -Pattern "(ERROR|SUCCESS|Service ticket|SPNEGO)" | ForEach-Object {
        if ($_ -match "ERROR") {
            Write-Host "  $_" -ForegroundColor Red
        } elseif ($_ -match "SUCCESS") {
            Write-Host "  $_" -ForegroundColor Green
        } else {
            Write-Host "  $_" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "  Log file not found: $logFile"
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Diagnostics Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
