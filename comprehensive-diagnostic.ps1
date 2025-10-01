# Comprehensive gMSA Authentication Diagnostic
# This script performs detailed diagnostics to identify authentication issues

param(
    [string]$VaultUrl = "http://10.0.101.8:8200",
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$SPN = "HTTP/vault.local.lab"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Comprehensive gMSA Authentication Diagnostic" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Vault URL: $VaultUrl" -ForegroundColor White
Write-Host "  gMSA Account: $GMSAAccount" -ForegroundColor White
Write-Host "  SPN: $SPN" -ForegroundColor White
Write-Host ""

# Step 1: Current Identity Analysis
Write-Host "Step 1: Current Identity Analysis" -ForegroundColor Yellow
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$currentUser = $env:USERNAME
$currentDomain = $env:USERDOMAIN

Write-Host "Current Identity: $currentIdentity" -ForegroundColor White
Write-Host "Current User: $currentUser" -ForegroundColor White
Write-Host "Current Domain: $currentDomain" -ForegroundColor White

if ($currentIdentity.EndsWith("$")) {
    Write-Host "SUCCESS: Running under service account identity" -ForegroundColor Green
} else {
    Write-Host "WARNING: Not running under service account identity" -ForegroundColor Yellow
    Write-Host "This test will show what happens under regular user context" -ForegroundColor Yellow
}
Write-Host ""

# Step 2: DNS Resolution Test
Write-Host "Step 2: DNS Resolution Test" -ForegroundColor Yellow
try {
    $dnsResult = [System.Net.Dns]::GetHostAddresses("vault.local.lab")
    Write-Host "SUCCESS: vault.local.lab resolves to: $($dnsResult[0].IPAddressToString)" -ForegroundColor Green
    
    if ($dnsResult[0].IPAddressToString -eq "10.0.101.8") {
        Write-Host "SUCCESS: DNS resolution matches expected IP" -ForegroundColor Green
    } else {
        Write-Host "WARNING: DNS resolution doesn't match expected IP (10.0.101.8)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: DNS resolution failed for vault.local.lab" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 3: Vault Server Connectivity
Write-Host "Step 3: Vault Server Connectivity" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$VaultUrl/v1/sys/health" -UseBasicParsing -TimeoutSec 10
    Write-Host "SUCCESS: Vault server is reachable" -ForegroundColor Green
    Write-Host "  Status Code: $($response.StatusCode)" -ForegroundColor Gray
    Write-Host "  Response: $($response.Content)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Cannot reach Vault server" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check network connectivity and Vault server status" -ForegroundColor Yellow
}
Write-Host ""

# Step 4: Kerberos Tickets Analysis
Write-Host "Step 4: Kerberos Tickets Analysis" -ForegroundColor Yellow
try {
    $klistOutput = klist 2>&1
    Write-Host "Kerberos tickets:" -ForegroundColor White
    Write-Host $klistOutput -ForegroundColor Gray
    
    if ($klistOutput -match $SPN) {
        Write-Host "SUCCESS: Found ticket for $SPN" -ForegroundColor Green
    } else {
        Write-Host "WARNING: No ticket found for $SPN" -ForegroundColor Yellow
        Write-Host "This is likely the root cause of authentication failure" -ForegroundColor Yellow
    }
    
    # Check for any HTTP tickets
    if ($klistOutput -match "HTTP/") {
        Write-Host "INFO: Found other HTTP tickets:" -ForegroundColor Cyan
        $httpTickets = $klistOutput | Select-String "HTTP/"
        foreach ($ticket in $httpTickets) {
            Write-Host "  $ticket" -ForegroundColor Gray
        }
    } else {
        Write-Host "WARNING: No HTTP tickets found at all" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Could not check Kerberos tickets" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 5: SPN Registration Verification
Write-Host "Step 5: SPN Registration Verification" -ForegroundColor Yellow
try {
    # Check if running as Administrator
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        Write-Host "SUCCESS: Running as Administrator - can check SPN registration" -ForegroundColor Green
        
        # Query SPN
        $spnResult = setspn -Q $SPN 2>&1
        Write-Host "SPN query result:" -ForegroundColor White
        Write-Host $spnResult -ForegroundColor Gray
        
        if ($spnResult -match $GMSAAccount) {
            Write-Host "SUCCESS: SPN $SPN is registered to $GMSAAccount" -ForegroundColor Green
        } elseif ($spnResult -match "No such SPN found") {
            Write-Host "ERROR: SPN $SPN is not registered anywhere" -ForegroundColor Red
        } else {
            Write-Host "WARNING: SPN $SPN is registered to a different account" -ForegroundColor Yellow
        }
        
        # List all SPNs for gMSA
        $gmsaSpns = setspn -L $GMSAAccount 2>&1
        Write-Host "All SPNs for $GMSAAccount:" -ForegroundColor White
        Write-Host $gmsaSpns -ForegroundColor Gray
        
    } else {
        Write-Host "WARNING: Not running as Administrator - cannot check SPN registration" -ForegroundColor Yellow
        Write-Host "Run this script as Administrator to check SPN registration" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: SPN verification failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 6: Vault Server Configuration Check
Write-Host "Step 6: Vault Server Configuration Check" -ForegroundColor Yellow
try {
    # Check if Kerberos auth method is enabled
    $authMethods = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/auth" -UseBasicParsing
    if ($authMethods.kerberos) {
        Write-Host "SUCCESS: Kerberos auth method is enabled" -ForegroundColor Green
        Write-Host "  Path: $($authMethods.kerberos.path)" -ForegroundColor Gray
        Write-Host "  Type: $($authMethods.kerberos.type)" -ForegroundColor Gray
    } else {
        Write-Host "ERROR: Kerberos auth method is not enabled" -ForegroundColor Red
    }
    
    # Check Kerberos configuration
    try {
        $kerberosConfig = Invoke-RestMethod -Uri "$VaultUrl/v1/auth/kerberos/config" -UseBasicParsing
        Write-Host "SUCCESS: Kerberos configuration found" -ForegroundColor Green
        Write-Host "  Service Account: $($kerberosConfig.service_account)" -ForegroundColor Gray
        Write-Host "  Keytab Path: $($kerberosConfig.keytab_path)" -ForegroundColor Gray
    } catch {
        Write-Host "ERROR: Cannot retrieve Kerberos configuration" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
} catch {
    Write-Host "ERROR: Cannot check Vault server configuration" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 7: Authentication Test with Detailed Error Analysis
Write-Host "Step 7: Authentication Test with Detailed Error Analysis" -ForegroundColor Yellow
try {
    Write-Host "Attempting Kerberos authentication..." -ForegroundColor Cyan
    
    $authResponse = Invoke-RestMethod `
        -Uri "$VaultUrl/v1/auth/kerberos/login" `
        -Method Post `
        -UseDefaultCredentials `
        -UseBasicParsing `
        -ErrorAction Stop
    
    if ($authResponse.auth -and $authResponse.auth.client_token) {
        Write-Host "SUCCESS: Kerberos authentication successful!" -ForegroundColor Green
        Write-Host "  Token: $($authResponse.auth.client_token.Substring(0,20))..." -ForegroundColor Gray
        Write-Host "  TTL: $($authResponse.auth.lease_duration) seconds" -ForegroundColor Gray
    } else {
        Write-Host "WARNING: Authentication response missing auth data" -ForegroundColor Yellow
        Write-Host "  Response: $($authResponse | ConvertTo-Json -Compress)" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "ERROR: Kerberos authentication failed" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    
    # Detailed error analysis
    if ($_.Exception.Message -match "401") {
        Write-Host "  ANALYSIS: 401 Unauthorized - authentication failed" -ForegroundColor Yellow
        Write-Host "  POSSIBLE CAUSES:" -ForegroundColor Yellow
        Write-Host "    - No valid Kerberos ticket for $SPN" -ForegroundColor White
        Write-Host "    - SPN not registered to gMSA account" -ForegroundColor White
        Write-Host "    - Vault server keytab doesn't match SPN" -ForegroundColor White
    } elseif ($_.Exception.Message -match "403") {
        Write-Host "  ANALYSIS: 403 Forbidden - access denied" -ForegroundColor Yellow
        Write-Host "  POSSIBLE CAUSES:" -ForegroundColor Yellow
        Write-Host "    - gMSA account not authorized for Kerberos auth" -ForegroundColor White
        Write-Host "    - Vault server policy restrictions" -ForegroundColor White
    } elseif ($_.Exception.Message -match "404") {
        Write-Host "  ANALYSIS: 404 Not Found - endpoint doesn't exist" -ForegroundColor Yellow
        Write-Host "  POSSIBLE CAUSES:" -ForegroundColor Yellow
        Write-Host "    - Kerberos auth method not enabled" -ForegroundColor White
        Write-Host "    - Wrong Vault URL or path" -ForegroundColor White
    } elseif ($_.Exception.Message -match "SEC_E_INVALID_TOKEN") {
        Write-Host "  ANALYSIS: SEC_E_INVALID_TOKEN - Kerberos token validation failed" -ForegroundColor Yellow
        Write-Host "  POSSIBLE CAUSES:" -ForegroundColor Yellow
        Write-Host "    - SPN/keytab mismatch" -ForegroundColor White
        Write-Host "    - Hostname mismatch in certificate" -ForegroundColor White
        Write-Host "    - Kerberos ticket expired or invalid" -ForegroundColor White
    }
}
Write-Host ""

# Step 8: Manual Kerberos Ticket Request Test
Write-Host "Step 8: Manual Kerberos Ticket Request Test" -ForegroundColor Yellow
try {
    Write-Host "Attempting to request Kerberos ticket for $SPN..." -ForegroundColor Cyan
    
    # Try to trigger Kerberos ticket request
    $testUrl = "http://vault.local.lab:8200/v1/auth/kerberos/login"
    $response = Invoke-WebRequest -Uri $testUrl -UseDefaultCredentials -UseBasicParsing -TimeoutSec 10
    
    Write-Host "SUCCESS: HTTP request completed" -ForegroundColor Green
    Write-Host "  Status: $($response.StatusCode)" -ForegroundColor Gray
    
    # Check if ticket was requested
    $klistAfter = klist 2>&1
    if ($klistAfter -match $SPN) {
        Write-Host "SUCCESS: Kerberos ticket was requested for $SPN" -ForegroundColor Green
    } else {
        Write-Host "WARNING: No ticket was requested for $SPN" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Manual ticket request failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Diagnostic Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "SUMMARY:" -ForegroundColor Yellow
Write-Host "1. DNS Resolution: Check if vault.local.lab resolves to 10.0.101.8" -ForegroundColor White
Write-Host "2. SPN Registration: Check if HTTP/vault.local.lab is registered to LOCAL\vault-gmsa$" -ForegroundColor White
Write-Host "3. Kerberos Tickets: Check if ticket exists for HTTP/vault.local.lab" -ForegroundColor White
Write-Host "4. Vault Configuration: Check if Kerberos auth method is enabled and configured" -ForegroundColor White
Write-Host "5. Keytab: Check if Vault server keytab contains HTTP/vault.local.lab@LOCAL.LAB" -ForegroundColor White
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Run this script as Administrator to check SPN registration" -ForegroundColor White
Write-Host "2. Run this script under gMSA identity to test properly" -ForegroundColor White
Write-Host "3. Check Vault server keytab configuration" -ForegroundColor White
Write-Host "4. Verify gMSA account has proper permissions" -ForegroundColor White
Write-Host ""

Write-Host "MANUAL GMSA TEST:" -ForegroundColor Cyan
Write-Host "runas /user:LOCAL\vault-gmsa$ 'PowerShell -ExecutionPolicy Bypass -File .\comprehensive-diagnostic.ps1'" -ForegroundColor Gray
Write-Host ""
