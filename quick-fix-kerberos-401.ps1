# Quick Fix for Kerberos 401 Unauthorized Error
# This script addresses the most common causes of authentication failure

param(
    [string]$ComputerName = "EC2AMAZ-UB1QVDL",
    [string]$VaultAddr = "http://vault.local.lab:8200"
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "QUICK FIX FOR KERBEROS 401 ERROR" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Fix 1: Register SPN (Most Common Issue)
Write-Host "Fix 1: Registering SPN..." -ForegroundColor Yellow
Write-Host "---------------------------" -ForegroundColor Yellow

$spn = "HTTP/vault.local.lab"
$computerAccount = "$ComputerName`$"

try {
    # Check if SPN already exists
    $existingSpn = setspn -Q $spn 2>&1 | Out-String
    
    if ($existingSpn -match "CN=") {
        Write-Host "SPN already exists: $($existingSpn.Trim())" -ForegroundColor Yellow
        
        # Check if it's registered to the correct account
        if ($existingSpn -match $ComputerName) {
            Write-Host "✓ SPN correctly registered to $ComputerName" -ForegroundColor Green
        } else {
            Write-Host "⚠ SPN registered to different account, removing and re-adding..." -ForegroundColor Yellow
            setspn -D $spn $computerAccount 2>$null
            setspn -A $spn $computerAccount
            Write-Host "✓ SPN re-registered to $ComputerName" -ForegroundColor Green
        }
    } else {
        # SPN doesn't exist, register it
        Write-Host "Registering SPN: $spn -> $computerAccount" -ForegroundColor White
        setspn -A $spn $computerAccount
        Write-Host "✓ SPN registered successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Failed to register SPN: $_" -ForegroundColor Red
    Write-Host "You may need domain admin privileges" -ForegroundColor Red
}

Write-Host ""

# Fix 2: Purge and Renew Kerberos Tickets
Write-Host "Fix 2: Renewing Kerberos Tickets..." -ForegroundColor Yellow
Write-Host "------------------------------------" -ForegroundColor Yellow

try {
    # Purge existing tickets
    Write-Host "Purging existing tickets..." -ForegroundColor White
    klist purge -li 0x3e7 2>$null
    
    # Wait a moment
    Start-Sleep -Seconds 2
    
    # Check if we can get new tickets
    Write-Host "Checking for new tickets..." -ForegroundColor White
    $tickets = klist 2>&1 | Out-String
    
    if ($tickets -match "HTTP/vault.local.lab") {
        Write-Host "✓ Service ticket for HTTP/vault.local.lab obtained" -ForegroundColor Green
    } else {
        Write-Host "⚠ No service ticket found, this may cause issues" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Error with ticket renewal: $_" -ForegroundColor Red
}

Write-Host ""

# Fix 3: Test Authentication
Write-Host "Fix 3: Testing Authentication..." -ForegroundColor Yellow
Write-Host "----------------------------------" -ForegroundColor Yellow

try {
    # Test with curl (most reliable method)
    $curlPath = "C:\Windows\System32\curl.exe"
    if (Test-Path $curlPath) {
        Write-Host "Testing with curl.exe..." -ForegroundColor White
        
        $tempJsonFile = "$env:TEMP\test-auth.json"
        '{"role":"computer-accounts"}' | Out-File -FilePath $tempJsonFile -Encoding ASCII -NoNewline
        
        $curlArgs = @(
            "--negotiate",
            "--user", ":",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "--data-binary", "@$tempJsonFile",
            "-k",
            "-s",
            "$VaultAddr/v1/auth/kerberos/login"
        )
        
        $curlResult = & $curlPath $curlArgs 2>&1 | Out-String
        
        # Clean up temp file
        Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
        
        if ($curlResult -match '"client_token"') {
            Write-Host "✓ Authentication successful with curl!" -ForegroundColor Green
            Write-Host "Response contains client_token" -ForegroundColor Green
        } else {
            Write-Host "❌ Authentication still failing" -ForegroundColor Red
            Write-Host "Response: $curlResult" -ForegroundColor Red
        }
    } else {
        Write-Host "⚠ curl.exe not found, testing with PowerShell..." -ForegroundColor Yellow
        
        # Test with PowerShell WebRequest
        $body = @{role = "computer-accounts"} | ConvertTo-Json -Compress
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        try {
            $response = Invoke-WebRequest -Uri "$VaultAddr/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -UseBasicParsing -ErrorAction Stop
            
            if ($response.StatusCode -eq 200) {
                Write-Host "✓ Authentication successful with PowerShell!" -ForegroundColor Green
            }
        } catch {
            Write-Host "❌ PowerShell authentication failed: $_" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "❌ Error during authentication test: $_" -ForegroundColor Red
}

Write-Host ""

# Fix 4: Provide Next Steps
Write-Host "Fix 4: Next Steps..." -ForegroundColor Yellow
Write-Host "--------------------" -ForegroundColor Yellow

Write-Host ""
Write-Host "If authentication is still failing, check these on the Vault server:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Verify Kerberos auth is enabled:" -ForegroundColor White
Write-Host "   vault auth list | grep kerberos" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Check Kerberos configuration:" -ForegroundColor White
Write-Host "   vault read auth/kerberos/config" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Verify role exists:" -ForegroundColor White
Write-Host "   vault read auth/kerberos/role/computer-accounts" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Check Vault server logs:" -ForegroundColor White
Write-Host "   journalctl -u vault -f" -ForegroundColor Gray
Write-Host ""

Write-Host "=========================================" -ForegroundColor Green
Write-Host "QUICK FIX COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Now test your scheduled task:" -ForegroundColor White
Write-Host "schtasks /Run /TN 'Test Curl Kerberos'" -ForegroundColor Gray
Write-Host "Get-Content C:\vault-client\logs\test-curl-system.log -Tail 30" -ForegroundColor Gray
