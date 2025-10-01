# Vault Server Configuration Check
# This script checks the Vault server configuration for gMSA authentication

param(
    [string]$VaultUrl = "http://10.0.101.8:8200"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Vault Server Configuration Check" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Vault URL: $VaultUrl" -ForegroundColor White
Write-Host ""

# Step 1: Check Vault server health
Write-Host "Step 1: Vault Server Health Check" -ForegroundColor Yellow
try {
    $healthResponse = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/health" -UseBasicParsing -TimeoutSec 10
    Write-Host "SUCCESS: Vault server is healthy" -ForegroundColor Green
    Write-Host "  Initialized: $($healthResponse.initialized)" -ForegroundColor Gray
    Write-Host "  Sealed: $($healthResponse.sealed)" -ForegroundColor Gray
    Write-Host "  Version: $($healthResponse.version)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Cannot reach Vault server" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 2: Check enabled auth methods
Write-Host "Step 2: Enabled Auth Methods" -ForegroundColor Yellow
try {
    $authMethods = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/auth" -UseBasicParsing
    Write-Host "Enabled auth methods:" -ForegroundColor White
    
    $kerberosFound = $false
    foreach ($method in $authMethods.PSObject.Properties) {
        $methodName = $method.Name
        $methodInfo = $method.Value
        Write-Host "  $methodName" -ForegroundColor Gray
        Write-Host "    Type: $($methodInfo.type)" -ForegroundColor Gray
        Write-Host "    Path: $($methodInfo.path)" -ForegroundColor Gray
        
        if ($methodName -eq "kerberos") {
            $kerberosFound = $true
            Write-Host "    SUCCESS: Kerberos auth method is enabled" -ForegroundColor Green
        }
    }
    
    if (-not $kerberosFound) {
        Write-Host "ERROR: Kerberos auth method is not enabled" -ForegroundColor Red
        Write-Host "Run: vault auth enable kerberos" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Cannot retrieve auth methods" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 3: Check Kerberos configuration
Write-Host "Step 3: Kerberos Configuration" -ForegroundColor Yellow
try {
    $kerberosConfig = Invoke-RestMethod -Uri "$VaultUrl/v1/auth/kerberos/config" -UseBasicParsing
    Write-Host "SUCCESS: Kerberos configuration found" -ForegroundColor Green
    Write-Host "  Service Account: $($kerberosConfig.service_account)" -ForegroundColor Gray
    Write-Host "  Keytab Path: $($kerberosConfig.keytab_path)" -ForegroundColor Gray
    Write-Host "  Add Group Aliases: $($kerberosConfig.add_group_aliases)" -ForegroundColor Gray
    Write-Host "  Remove Instance Name: $($kerberosConfig.remove_instance_name)" -ForegroundColor Gray
    
    # Check if service account matches expected SPN
    if ($kerberosConfig.service_account -eq "HTTP/vault.local.lab@LOCAL.LAB") {
        Write-Host "SUCCESS: Service account matches expected SPN" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Service account doesn't match expected SPN" -ForegroundColor Yellow
        Write-Host "  Expected: HTTP/vault.local.lab@LOCAL.LAB" -ForegroundColor White
        Write-Host "  Actual: $($kerberosConfig.service_account)" -ForegroundColor White
    }
    
} catch {
    Write-Host "ERROR: Cannot retrieve Kerberos configuration" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure Kerberos auth method is enabled and configured" -ForegroundColor Yellow
}
Write-Host ""

# Step 4: Check Kerberos groups
Write-Host "Step 4: Kerberos Groups" -ForegroundColor Yellow
try {
    $kerberosGroups = Invoke-RestMethod -Uri "$VaultUrl/v1/auth/kerberos/groups" -UseBasicParsing
    Write-Host "SUCCESS: Kerberos groups found" -ForegroundColor Green
    
    if ($kerberosGroups.groups) {
        foreach ($group in $kerberosGroups.groups.PSObject.Properties) {
            $groupName = $group.Name
            $groupInfo = $group.Value
            Write-Host "  Group: $groupName" -ForegroundColor Gray
            Write-Host "    Policies: $($groupInfo.policies -join ', ')" -ForegroundColor Gray
        }
    } else {
        Write-Host "WARNING: No Kerberos groups configured" -ForegroundColor Yellow
        Write-Host "Run: vault write auth/kerberos/groups/vault-gmsa-group policies=vault-gmsa-policy" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Cannot retrieve Kerberos groups" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 5: Check policies
Write-Host "Step 5: Policies" -ForegroundColor Yellow
try {
    $policies = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/policies/acl" -UseBasicParsing
    Write-Host "SUCCESS: Policies found" -ForegroundColor Green
    
    $gmsaPolicyFound = $false
    foreach ($policy in $policies.keys) {
        Write-Host "  Policy: $policy" -ForegroundColor Gray
        
        if ($policy -match "gmsa") {
            $gmsaPolicyFound = $true
            Write-Host "    SUCCESS: Found gMSA-related policy" -ForegroundColor Green
        }
    }
    
    if (-not $gmsaPolicyFound) {
        Write-Host "WARNING: No gMSA-related policies found" -ForegroundColor Yellow
        Write-Host "Consider creating a policy for gMSA authentication" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Cannot retrieve policies" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 6: Check secrets engines
Write-Host "Step 6: Secrets Engines" -ForegroundColor Yellow
try {
    $secretsEngines = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/mounts" -UseBasicParsing
    Write-Host "Enabled secrets engines:" -ForegroundColor White
    
    foreach ($engine in $secretsEngines.PSObject.Properties) {
        $engineName = $engine.Name
        $engineInfo = $engine.Value
        Write-Host "  $engineName" -ForegroundColor Gray
        Write-Host "    Type: $($engineInfo.type)" -ForegroundColor Gray
        Write-Host "    Path: $($engineInfo.path)" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "ERROR: Cannot retrieve secrets engines" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Step 7: Test Kerberos login endpoint
Write-Host "Step 7: Kerberos Login Endpoint Test" -ForegroundColor Yellow
try {
    Write-Host "Testing Kerberos login endpoint..." -ForegroundColor Cyan
    
    # Try a simple GET request to see if endpoint exists
    $loginResponse = Invoke-WebRequest -Uri "$VaultUrl/v1/auth/kerberos/login" -Method Get -UseBasicParsing -TimeoutSec 5
    
    Write-Host "SUCCESS: Kerberos login endpoint is accessible" -ForegroundColor Green
    Write-Host "  Status: $($loginResponse.StatusCode)" -ForegroundColor Gray
    
    if ($loginResponse.StatusCode -eq 405) {
        Write-Host "  INFO: 405 Method Not Allowed is expected for GET request" -ForegroundColor Cyan
        Write-Host "  The endpoint exists and is properly configured" -ForegroundColor Green
    }
    
} catch {
    Write-Host "ERROR: Kerberos login endpoint test failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Message -match "404") {
        Write-Host "  ANALYSIS: 404 Not Found - Kerberos auth method not enabled" -ForegroundColor Yellow
    } elseif ($_.Exception.Message -match "403") {
        Write-Host "  ANALYSIS: 403 Forbidden - Endpoint exists but access denied" -ForegroundColor Yellow
    }
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Vault Server Configuration Check Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "CONFIGURATION SUMMARY:" -ForegroundColor Yellow
Write-Host "1. Vault Server: Check if healthy and accessible" -ForegroundColor White
Write-Host "2. Kerberos Auth: Check if enabled and configured" -ForegroundColor White
Write-Host "3. Service Account: Check if matches HTTP/vault.local.lab@LOCAL.LAB" -ForegroundColor White
Write-Host "4. Keytab: Check if contains correct SPN" -ForegroundColor White
Write-Host "5. Groups: Check if gMSA group is configured" -ForegroundColor White
Write-Host "6. Policies: Check if gMSA policy exists" -ForegroundColor White
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. If Kerberos auth is not enabled: vault auth enable kerberos" -ForegroundColor White
Write-Host "2. If service account is wrong: vault write auth/kerberos/config service_account=HTTP/vault.local.lab@LOCAL.LAB" -ForegroundColor White
Write-Host "3. If keytab is missing: Copy keytab to Vault server" -ForegroundColor White
Write-Host "4. If groups are missing: vault write auth/kerberos/groups/vault-gmsa-group policies=vault-gmsa-policy" -ForegroundColor White
Write-Host "5. Run comprehensive diagnostic to test authentication" -ForegroundColor White
Write-Host ""

Write-Host "MANUAL COMMANDS:" -ForegroundColor Cyan
Write-Host "vault auth enable kerberos" -ForegroundColor Gray
Write-Host "vault write auth/kerberos/config service_account=HTTP/vault.local.lab@LOCAL.LAB keytab_path=/etc/vault/vault.keytab" -ForegroundColor Gray
Write-Host "vault write auth/kerberos/groups/vault-gmsa-group policies=vault-gmsa-policy" -ForegroundColor Gray
Write-Host ""