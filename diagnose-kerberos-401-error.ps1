# Diagnose 401 Unauthorized Error in Kerberos Authentication
# Run this script to identify and fix the authentication issue

param(
    [string]$VaultAddr = "http://vault.local.lab:8200",
    [string]$ComputerName = "EC2AMAZ-UB1QVDL",
    [switch]$FixIssues
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "KERBEROS 401 ERROR DIAGNOSTIC TOOL" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check SPN Registration
Write-Host "Step 1: Checking SPN Registration..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

$spn = "HTTP/vault.local.lab"
Write-Host "Looking for SPN: $spn" -ForegroundColor White

try {
    # Check if SPN exists
    $spnQuery = setspn -Q $spn 2>&1 | Out-String
    if ($spnQuery -match "CN=") {
        Write-Host "✓ SPN found: $spn" -ForegroundColor Green
        Write-Host "Registered to: $($spnQuery.Trim())" -ForegroundColor Green
        
        # Check if it's registered to the correct computer account
        if ($spnQuery -match $ComputerName) {
            Write-Host "✓ SPN correctly registered to computer account: $ComputerName" -ForegroundColor Green
        } else {
            Write-Host "⚠ SPN registered to different account" -ForegroundColor Yellow
            Write-Host "Current registration: $($spnQuery.Trim())" -ForegroundColor Yellow
            Write-Host "Expected: $ComputerName" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ SPN NOT FOUND: $spn" -ForegroundColor Red
        Write-Host "This is likely the cause of the 401 error!" -ForegroundColor Red
        
        if ($FixIssues) {
            Write-Host ""
            Write-Host "Fixing SPN registration..." -ForegroundColor Cyan
            try {
                setspn -A $spn "$ComputerName`$"
                Write-Host "✓ SPN registered successfully" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to register SPN: $_" -ForegroundColor Red
            }
        }
    }
} catch {
    Write-Host "❌ Error checking SPN: $_" -ForegroundColor Red
}

Write-Host ""

# Step 2: Check Kerberos Tickets
Write-Host "Step 2: Checking Kerberos Tickets..." -ForegroundColor Yellow
Write-Host "--------------------------------------" -ForegroundColor Yellow

try {
    $tickets = klist 2>&1 | Out-String
    Write-Host "Current Kerberos tickets:" -ForegroundColor White
    Write-Host $tickets -ForegroundColor Gray
    
    if ($tickets -match "HTTP/vault.local.lab") {
        Write-Host "✓ Service ticket for HTTP/vault.local.lab found" -ForegroundColor Green
    } else {
        Write-Host "❌ No service ticket for HTTP/vault.local.lab" -ForegroundColor Red
        Write-Host "This could cause authentication failure" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error checking tickets: $_" -ForegroundColor Red
}

Write-Host ""

# Step 3: Check Vault Server Configuration
Write-Host "Step 3: Checking Vault Server Configuration..." -ForegroundColor Yellow
Write-Host "-----------------------------------------------" -ForegroundColor Yellow

try {
    # Test basic connectivity
    $response = Invoke-WebRequest -Uri "$VaultAddr/v1/sys/health" -Method GET -UseBasicParsing -ErrorAction Stop
    Write-Host "✓ Vault server is reachable" -ForegroundColor Green
    
    # Check if Kerberos auth is enabled
    try {
        $authResponse = Invoke-WebRequest -Uri "$VaultAddr/v1/sys/auth" -Method GET -UseBasicParsing -ErrorAction Stop
        $authContent = $authResponse.Content | ConvertFrom-Json
        
        if ($authContent.data.kerberos) {
            Write-Host "✓ Kerberos auth method is enabled" -ForegroundColor Green
        } else {
            Write-Host "❌ Kerberos auth method not found" -ForegroundColor Red
            Write-Host "This could be the issue!" -ForegroundColor Red
        }
    } catch {
        Write-Host "⚠ Could not check auth methods (may need token)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Cannot reach Vault server: $_" -ForegroundColor Red
}

Write-Host ""

# Step 4: Test Authentication with Detailed Logging
Write-Host "Step 4: Testing Authentication..." -ForegroundColor Yellow
Write-Host "-----------------------------------" -ForegroundColor Yellow

try {
    # Create test request
    $body = @{role = "computer-accounts"} | ConvertTo-Json -Compress
    $headers = @{
        "Content-Type" = "application/json"
    }
    
    Write-Host "Testing authentication to: $VaultAddr/v1/auth/kerberos/login" -ForegroundColor White
    Write-Host "Request body: $body" -ForegroundColor White
    
    $authTest = Invoke-WebRequest -Uri "$VaultAddr/v1/auth/kerberos/login" -Method POST -Body $body -Headers $headers -UseBasicParsing -ErrorAction Stop
    
    if ($authTest.StatusCode -eq 200) {
        Write-Host "✓ Authentication successful!" -ForegroundColor Green
        $responseData = $authTest.Content | ConvertFrom-Json
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
            Write-Host "This confirms the 401 Unauthorized error" -ForegroundColor Red
            
            # Try to get error details
            try {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorContent = $reader.ReadToEnd()
                Write-Host "Error details: $errorContent" -ForegroundColor Red
            } catch {
                Write-Host "Could not read error details" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "❌ Network error: $_" -ForegroundColor Red
    }
}

Write-Host ""

# Step 5: Provide Recommendations
Write-Host "Step 5: Recommendations..." -ForegroundColor Yellow
Write-Host "---------------------------" -ForegroundColor Yellow

Write-Host ""
Write-Host "Based on the diagnosis above, here are the most likely fixes:" -ForegroundColor Cyan
Write-Host ""

Write-Host "1. SPN Registration (Most Common Fix):" -ForegroundColor White
Write-Host "   setspn -A HTTP/vault.local.lab $ComputerName`$" -ForegroundColor Gray
Write-Host ""

Write-Host "2. Verify Vault Server Configuration:" -ForegroundColor White
Write-Host "   # On Vault server, check:" -ForegroundColor Gray
Write-Host "   vault auth list" -ForegroundColor Gray
Write-Host "   vault read auth/kerberos/config" -ForegroundColor Gray
Write-Host ""

Write-Host "3. Check Keytab on Vault Server:" -ForegroundColor White
Write-Host "   # Verify keytab contains correct principal:" -ForegroundColor Gray
Write-Host "   klist -kte /path/to/keytab" -ForegroundColor Gray
Write-Host ""

Write-Host "4. Test with curl (Alternative Method):" -ForegroundColor White
Write-Host "   curl --negotiate -u : -X POST -H 'Content-Type: application/json' -d '{\"role\":\"computer-accounts\"}' $VaultAddr/v1/auth/kerberos/login" -ForegroundColor Gray
Write-Host ""

if ($FixIssues) {
    Write-Host "=========================================" -ForegroundColor Green
    Write-Host "AUTOMATIC FIXES APPLIED" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Please run the test again to verify the fix:" -ForegroundColor White
    Write-Host "schtasks /Run /TN 'Test Curl Kerberos'" -ForegroundColor Gray
} else {
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "TO APPLY AUTOMATIC FIXES:" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Run this script with -FixIssues parameter:" -ForegroundColor White
    Write-Host ".\diagnose-kerberos-401-error.ps1 -FixIssues" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "DIAGNOSIS COMPLETE" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan