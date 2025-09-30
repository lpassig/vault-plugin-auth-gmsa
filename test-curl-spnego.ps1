# Test SPNEGO token generation using curl (Windows SSPI)
# This bypasses PowerShell's limitations with gMSA credentials

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Test SPNEGO Generation with curl" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check current user
$currentUser = whoami
Write-Host "Current User: $currentUser" -ForegroundColor Yellow
Write-Host ""

# Check if curl is available
try {
    $curlVersion = curl --version 2>&1 | Select-Object -First 1
    Write-Host "curl version: $curlVersion" -ForegroundColor Green
} catch {
    Write-Host "ERROR: curl not found" -ForegroundColor Red
    exit 1
}

# Check Kerberos tickets
Write-Host "Checking Kerberos tickets..." -ForegroundColor Cyan
$klistOutput = klist 2>&1
Write-Host $klistOutput -ForegroundColor Gray
Write-Host ""

# Test 1: Use curl with --negotiate to generate SPNEGO
Write-Host "Test 1: curl with --negotiate flag" -ForegroundColor Cyan
Write-Host "Command: curl --negotiate --user : -v https://vault.local.lab:8200/v1/sys/health" -ForegroundColor Gray
Write-Host ""

try {
    $curlOutput = curl --negotiate --user : -v https://vault.local.lab:8200/v1/sys/health 2>&1
    Write-Host "curl output:" -ForegroundColor Yellow
    Write-Host $curlOutput -ForegroundColor Gray
    
    # Check if Authorization header was sent
    if ($curlOutput -match "Authorization: Negotiate (.+)") {
        $spnegoToken = $matches[1]
        Write-Host ""
        Write-Host "SUCCESS: SPNEGO token generated!" -ForegroundColor Green
        Write-Host "Token (first 100 chars): $($spnegoToken.Substring(0, [Math]::Min(100, $spnegoToken.Length)))..." -ForegroundColor White
        Write-Host "Token length: $($spnegoToken.Length) characters" -ForegroundColor White
    } else {
        Write-Host ""
        Write-Host "WARNING: No Authorization header found in curl output" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: curl failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Test 2: curl with --negotiate and dump headers" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Test 2: Use curl with --negotiate and save headers
try {
    $headerFile = "$env:TEMP\curl-headers.txt"
    $curlCmd = "curl --negotiate --user : -D `"$headerFile`" https://vault.local.lab:8200/v1/sys/health 2>&1"
    Write-Host "Command: $curlCmd" -ForegroundColor Gray
    Write-Host ""
    
    $curlOutput = Invoke-Expression $curlCmd
    Write-Host "curl output:" -ForegroundColor Yellow
    Write-Host $curlOutput -ForegroundColor Gray
    
    if (Test-Path $headerFile) {
        Write-Host ""
        Write-Host "Headers saved to: $headerFile" -ForegroundColor Green
        $headers = Get-Content $headerFile
        Write-Host "Headers:" -ForegroundColor Yellow
        Write-Host $headers -ForegroundColor Gray
        
        # Check for Authorization header in headers file
        $authHeader = $headers | Where-Object { $_ -like "Authorization: Negotiate *" }
        if ($authHeader) {
            Write-Host ""
            Write-Host "SUCCESS: Found Authorization header!" -ForegroundColor Green
            Write-Host $authHeader -ForegroundColor White
        }
    }
} catch {
    Write-Host "ERROR: curl with headers failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Conclusion:" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "If curl successfully generated a SPNEGO token, we can use curl as a workaround." -ForegroundColor White
Write-Host "If curl also failed, the issue is deeper in Windows SSPI configuration." -ForegroundColor White
Write-Host ""
