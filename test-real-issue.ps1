# Test to identify the real issue with gMSA authentication
# Based on user feedback that gMSA + scheduled task + Kerberos should work

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Real Issue Diagnosis for gMSA Authentication" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check current user and Kerberos tickets
Write-Host "1. Current User and Kerberos Status:" -ForegroundColor Yellow
$currentUser = whoami
Write-Host "Current User: $currentUser" -ForegroundColor White

$klistOutput = klist 2>&1
Write-Host "Kerberos Tickets:" -ForegroundColor White
Write-Host $klistOutput -ForegroundColor Gray
Write-Host ""

# Test 2: DNS Resolution Test
Write-Host "2. DNS Resolution Test:" -ForegroundColor Yellow
try {
    $dnsResult = [System.Net.Dns]::GetHostAddresses("vault.local.lab")
    Write-Host "vault.local.lab resolves to: $($dnsResult[0].IPAddressToString)" -ForegroundColor Green
} catch {
    Write-Host "vault.local.lab DNS resolution failed: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    $dnsResult = [System.Net.Dns]::GetHostAddresses("vault.example.com")
    Write-Host "vault.example.com resolves to: $($dnsResult[0].IPAddressToString)" -ForegroundColor Green
} catch {
    Write-Host "vault.example.com DNS resolution failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 3: SSL Certificate Test
Write-Host "3. SSL Certificate Test:" -ForegroundColor Yellow
$testUrls = @(
    "https://vault.local.lab:8200/v1/sys/health",
    "https://vault.example.com:8200/v1/sys/health"
)

foreach ($url in $testUrls) {
    Write-Host "Testing: $url" -ForegroundColor Cyan
    try {
        # Use older PowerShell compatible method for SSL bypass
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        $response = Invoke-WebRequest -Uri $url -UseDefaultCredentials -TimeoutSec 10
        Write-Host "SUCCESS: SSL connection works" -ForegroundColor Green
        Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.InnerException) {
            Write-Host "Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""
}

# Test 4: curl with Windows-compatible syntax
Write-Host "4. curl Tests:" -ForegroundColor Yellow
if (Get-Command curl -ErrorAction SilentlyContinue) {
    $curlTests = @(
        "curl.exe --insecure --verbose https://vault.local.lab:8200/v1/sys/health",
        "curl.exe --negotiate --user : --insecure --verbose https://vault.local.lab:8200/v1/sys/health"
    )
    
    foreach ($curlTest in $curlTests) {
        Write-Host "Testing: $curlTest" -ForegroundColor Cyan
        try {
            $curlOutput = Invoke-Expression $curlTest 2>&1
            Write-Host "curl output:" -ForegroundColor White
            Write-Host $curlOutput -ForegroundColor Gray
        } catch {
            Write-Host "curl failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host ""
    }
} else {
    Write-Host "curl not available" -ForegroundColor Yellow
}

# Test 5: PowerShell HTTP Negotiate Test
Write-Host "5. PowerShell HTTP Negotiate Test:" -ForegroundColor Yellow
$testUrls = @(
    "https://vault.local.lab:8200/v1/auth/kerberos/login"
)

foreach ($url in $testUrls) {
    Write-Host "Testing HTTP Negotiate: $url" -ForegroundColor Cyan
    try {
        # Use older PowerShell compatible method for SSL bypass
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        $response = Invoke-RestMethod -Uri $url -Method Post -UseDefaultCredentials -UseBasicParsing
        Write-Host "SUCCESS: HTTP Negotiate works" -ForegroundColor Green
        Write-Host "Response: $($response | ConvertTo-Json)" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Host "HTTP Status: $statusCode" -ForegroundColor Red
            
            if ($_.Exception.Response.GetResponseStream()) {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                Write-Host "Error Body: $errorBody" -ForegroundColor Red
            }
        }
    }
    Write-Host ""
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Diagnosis Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Check if DNS resolution matches SSL certificate" -ForegroundColor White
Write-Host "2. Verify Vault server is configured for HTTP Negotiate" -ForegroundColor White
Write-Host "3. Check if SPN matches the hostname being used" -ForegroundColor White
Write-Host "4. Verify keytab is up-to-date on Vault server" -ForegroundColor White
