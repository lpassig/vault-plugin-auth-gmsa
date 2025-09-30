# Fix Protocol Mismatch - Update Windows Client to Use HTTPS
# The issue: Windows client uses HTTP but Vault Docker container expects HTTPS

param(
    [string]$VaultAddr = "https://vault.local.lab:8200",
    [string]$Role = "computer-accounts"
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "FIX PROTOCOL MISMATCH" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Issue Identified:" -ForegroundColor Yellow
Write-Host "Windows client is using HTTP but Vault Docker container expects HTTPS" -ForegroundColor Yellow
Write-Host ""

Write-Host "Current Windows client URL: http://vault.local.lab:8200" -ForegroundColor Red
Write-Host "Required URL: https://vault.local.lab:8200" -ForegroundColor Green
Write-Host ""

# Update the test script to use HTTPS
Write-Host "Step 1: Updating test script to use HTTPS..." -ForegroundColor Yellow
Write-Host "------------------------------------------------" -ForegroundColor Yellow

$testScriptPath = "C:\vault-client\test-curl-system.ps1"
if (Test-Path $testScriptPath) {
    $content = Get-Content $testScriptPath -Raw
    $updatedContent = $content -replace 'http://vault\.local\.lab:8200', 'https://vault.local.lab:8200'
    
    if ($content -ne $updatedContent) {
        $updatedContent | Set-Content $testScriptPath -Force
        Write-Host "✓ Updated test script to use HTTPS" -ForegroundColor Green
    } else {
        Write-Host "✓ Test script already uses HTTPS" -ForegroundColor Green
    }
} else {
    Write-Host "⚠ Test script not found at $testScriptPath" -ForegroundColor Yellow
}

Write-Host ""

# Update the scheduled task script
Write-Host "Step 2: Updating scheduled task script..." -ForegroundColor Yellow
Write-Host "------------------------------------------" -ForegroundColor Yellow

$scheduledTaskScript = "C:\vault-client\vault-client-app.ps1"
if (Test-Path $scheduledTaskScript) {
    $content = Get-Content $scheduledTaskScript -Raw
    $updatedContent = $content -replace 'http://vault\.local\.lab:8200', 'https://vault.local.lab:8200'
    
    if ($content -ne $updatedContent) {
        $updatedContent | Set-Content $scheduledTaskScript -Force
        Write-Host "✓ Updated scheduled task script to use HTTPS" -ForegroundColor Green
    } else {
        Write-Host "✓ Scheduled task script already uses HTTPS" -ForegroundColor Green
    }
} else {
    Write-Host "⚠ Scheduled task script not found at $scheduledTaskScript" -ForegroundColor Yellow
}

Write-Host ""

# Test HTTPS connectivity
Write-Host "Step 3: Testing HTTPS connectivity..." -ForegroundColor Yellow
Write-Host "---------------------------------------" -ForegroundColor Yellow

try {
    $response = Invoke-WebRequest -Uri "https://vault.local.lab:8200/v1/sys/health" -Method GET -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    Write-Host "✓ HTTPS connectivity successful" -ForegroundColor Green
    Write-Host "Status Code: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "❌ HTTPS connectivity failed: $_" -ForegroundColor Red
    Write-Host "This might be due to SSL certificate issues" -ForegroundColor Yellow
}

Write-Host ""

# Test Kerberos authentication with HTTPS
Write-Host "Step 4: Testing Kerberos authentication with HTTPS..." -ForegroundColor Yellow
Write-Host "------------------------------------------------------" -ForegroundColor Yellow

try {
    $body = @{role = $Role} | ConvertTo-Json -Compress
    $headers = @{
        "Content-Type" = "application/json"
    }
    
    Write-Host "Testing authentication to: $VaultAddr/v1/auth/kerberos/login" -ForegroundColor White
    
    $response = Invoke-WebRequest -Uri "$VaultAddr/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    
    if ($response.StatusCode -eq 200) {
        Write-Host "✓ Authentication successful with HTTPS!" -ForegroundColor Green
        $responseData = $response.Content | ConvertFrom-Json
        if ($responseData.auth.client_token) {
            Write-Host "✓ Token received: $($responseData.auth.client_token.Substring(0,20))..." -ForegroundColor Green
        }
    }
} catch {
    $errorResponse = $_.Exception.Response
    if ($errorResponse) {
        $statusCode = $errorResponse.StatusCode
        Write-Host "❌ Authentication failed with status: $statusCode" -ForegroundColor Red
        
        if ($statusCode -eq 401) {
            Write-Host "Still getting 401 - this might be the SPN registration issue" -ForegroundColor Yellow
            Write-Host "Run: .\fix-spn-registration.ps1" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ Network error: $_" -ForegroundColor Red
    }
}

Write-Host ""

# Provide next steps
Write-Host "Step 5: Next Steps..." -ForegroundColor Yellow
Write-Host "--------------------" -ForegroundColor Yellow

Write-Host ""
Write-Host "1. If you still get 401 errors, fix the SPN registration:" -ForegroundColor White
Write-Host "   .\fix-spn-registration.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Test your scheduled task:" -ForegroundColor White
Write-Host "   schtasks /Run /TN 'Test Curl Kerberos'" -ForegroundColor Gray
Write-Host "   Get-Content C:\vault-client\logs\test-curl-system.log -Tail 30" -ForegroundColor Gray
Write-Host ""
Write-Host "3. If SSL certificate issues persist, you may need to:" -ForegroundColor White
Write-Host "   - Add the Vault certificate to Windows trusted store" -ForegroundColor Gray
Write-Host "   - Or configure Vault to use HTTP (not recommended for production)" -ForegroundColor Gray
Write-Host ""

Write-Host "=========================================" -ForegroundColor Green
Write-Host "PROTOCOL MISMATCH FIX COMPLETE" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Your Windows client should now use HTTPS to connect to Vault." -ForegroundColor White
Write-Host "This should resolve the protocol mismatch issue." -ForegroundColor White
