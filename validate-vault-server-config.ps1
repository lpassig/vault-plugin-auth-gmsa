# Vault Server Configuration Validation Script
# This script validates that the Vault server is properly configured for gMSA authentication

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$VaultIP = "10.0.101.8",
    [string]$VaultPort = "8200"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Vault Server Configuration Validation" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# SSL Certificate bypass for testing
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

Write-Host "Vault Server Details:" -ForegroundColor Yellow
Write-Host "  URL: $VaultUrl" -ForegroundColor White
Write-Host "  IP: $VaultIP" -ForegroundColor White
Write-Host "  Port: $VaultPort" -ForegroundColor White
Write-Host ""

# Test 1: Basic Connectivity
Write-Host "1. Basic Connectivity Test:" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$VaultUrl/v1/sys/health" -TimeoutSec 10
    Write-Host "SUCCESS: Vault server is reachable" -ForegroundColor Green
    Write-Host "Status Code: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Response: $($response.Content)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Cannot reach Vault server" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 2: Check if Vault is initialized
Write-Host "2. Vault Initialization Status:" -ForegroundColor Yellow
try {
    $initStatus = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/init" -Method Get
    if ($initStatus.initialized) {
        Write-Host "SUCCESS: Vault is initialized" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Vault is not initialized" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Cannot check initialization status" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 3: Check Authentication Methods
Write-Host "3. Available Authentication Methods:" -ForegroundColor Yellow
try {
    $authMethods = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/auth" -Method Get
    Write-Host "Available auth methods:" -ForegroundColor White
    foreach ($method in $authMethods.data.Keys) {
        Write-Host "  - $method" -ForegroundColor Gray
        if ($method -eq "kerberos/") {
            Write-Host "    SUCCESS: Kerberos auth method is enabled!" -ForegroundColor Green
        }
    }
    
    if (-not $authMethods.data.ContainsKey("kerberos/")) {
        Write-Host "ERROR: Kerberos auth method is NOT enabled!" -ForegroundColor Red
        Write-Host "SOLUTION: Enable Kerberos auth method on Vault server" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Cannot check authentication methods" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 4: Check Kerberos Auth Configuration
Write-Host "4. Kerberos Auth Method Configuration:" -ForegroundColor Yellow
try {
    $kerberosConfig = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/auth/kerberos" -Method Get
    Write-Host "Kerberos auth method configuration:" -ForegroundColor White
    Write-Host "  Type: $($kerberosConfig.type)" -ForegroundColor Gray
    Write-Host "  Description: $($kerberosConfig.description)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Cannot access Kerberos auth method configuration" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 5: Check Kerberos Roles
Write-Host "5. Kerberos Roles Configuration:" -ForegroundColor Yellow
try {
    $roles = Invoke-RestMethod -Uri "$VaultUrl/v1/auth/kerberos/role" -Method Get
    Write-Host "Available Kerberos roles:" -ForegroundColor White
    foreach ($role in $roles.data.keys) {
        Write-Host "  - $role" -ForegroundColor Gray
    }
    
    if ($roles.data.keys.Count -eq 0) {
        Write-Host "WARNING: No Kerberos roles configured!" -ForegroundColor Yellow
        Write-Host "SOLUTION: Create Kerberos roles for authentication" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Cannot check Kerberos roles" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 6: Check Specific Role Configuration
Write-Host "6. Specific Role Configuration (vault-gmsa-role):" -ForegroundColor Yellow
try {
    $roleConfig = Invoke-RestMethod -Uri "$VaultUrl/v1/auth/kerberos/role/vault-gmsa-role" -Method Get
    Write-Host "Role 'vault-gmsa-role' configuration:" -ForegroundColor White
    Write-Host "  Policies: $($roleConfig.data.policies -join ', ')" -ForegroundColor Gray
    Write-Host "  Token TTL: $($roleConfig.data.token_ttl)" -ForegroundColor Gray
    Write-Host "  Token Max TTL: $($roleConfig.data.token_max_ttl)" -ForegroundColor Gray
} catch {
    Write-Host "WARNING: Role 'vault-gmsa-role' not found or not accessible" -ForegroundColor Yellow
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""

# Test 7: Check Policies
Write-Host "7. Available Policies:" -ForegroundColor Yellow
try {
    $policies = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/policy" -Method Get
    Write-Host "Available policies:" -ForegroundColor White
    foreach ($policy in $policies.data.keys) {
        Write-Host "  - $policy" -ForegroundColor Gray
    }
} catch {
    Write-Host "ERROR: Cannot check policies" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 8: Check Secrets Engines
Write-Host "8. Available Secrets Engines:" -ForegroundColor Yellow
try {
    $secrets = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/mounts" -Method Get
    Write-Host "Available secrets engines:" -ForegroundColor White
    foreach ($secret in $secrets.data.Keys) {
        Write-Host "  - $secret ($($secrets.data[$secret].type))" -ForegroundColor Gray
    }
} catch {
    Write-Host "ERROR: Cannot check secrets engines" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 9: Test Kerberos Authentication Endpoint
Write-Host "9. Kerberos Authentication Endpoint Test:" -ForegroundColor Yellow
try {
    # Try to access the Kerberos login endpoint
    $loginResponse = Invoke-WebRequest -Uri "$VaultUrl/v1/auth/kerberos/login" -Method Post -TimeoutSec 10
    Write-Host "SUCCESS: Kerberos login endpoint is accessible" -ForegroundColor Green
    Write-Host "Status Code: $($loginResponse.StatusCode)" -ForegroundColor Green
} catch {
    $statusCode = $_.Exception.Response.StatusCode
    Write-Host "Kerberos login endpoint response: $statusCode" -ForegroundColor Yellow
    
    if ($statusCode -eq 400) {
        Write-Host "SUCCESS: Endpoint accessible, returns 400 (expected without credentials)" -ForegroundColor Green
    } elseif ($statusCode -eq 401) {
        Write-Host "SUCCESS: Endpoint accessible, returns 401 (expected without credentials)" -ForegroundColor Green
    } elseif ($statusCode -eq 404) {
        Write-Host "ERROR: Kerberos auth method not found (404)" -ForegroundColor Red
    } else {
        Write-Host "Response: $statusCode" -ForegroundColor Yellow
    }
}
Write-Host ""

# Test 10: Check Vault Server Logs (if accessible)
Write-Host "10. Vault Server Status:" -ForegroundColor Yellow
try {
    $status = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/health" -Method Get
    Write-Host "Vault server status:" -ForegroundColor White
    Write-Host "  Initialized: $($status.initialized)" -ForegroundColor Gray
    Write-Host "  Sealed: $($status.sealed)" -ForegroundColor Gray
    Write-Host "  Standby: $($status.standby)" -ForegroundColor Gray
    Write-Host "  Performance Standby: $($status.performance_standby)" -ForegroundColor Gray
    Write-Host "  Replication Performance Mode: $($status.replication_performance_mode)" -ForegroundColor Gray
    Write-Host "  Replication DR Mode: $($status.replication_dr_mode)" -ForegroundColor Gray
    Write-Host "  Server Time UTC: $($status.server_time_utc)" -ForegroundColor Gray
    Write-Host "  Version: $($status.version)" -ForegroundColor Gray
    Write-Host "  Cluster Name: $($status.cluster_name)" -ForegroundColor Gray
    Write-Host "  Cluster ID: $($status.cluster_id)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: Cannot get Vault server status" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Validation Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "SUMMARY:" -ForegroundColor Yellow
Write-Host "1. Ensure Vault server is initialized and unsealed" -ForegroundColor White
Write-Host "2. Enable Kerberos auth method: vault auth enable kerberos" -ForegroundColor White
Write-Host "3. Configure Kerberos auth: vault write auth/kerberos/config keytab=/etc/vault/vault.keytab service_account=HTTP/vault.local.lab" -ForegroundColor White
Write-Host "4. Create Kerberos role: vault write auth/kerberos/role/vault-gmsa-role policies=vault-gmsa-policy" -ForegroundColor White
Write-Host "5. Create policy for gMSA: vault policy write vault-gmsa-policy - <<EOF" -ForegroundColor White
Write-Host "   path \"kv/data/my-app/*\" {" -ForegroundColor Gray
Write-Host "     capabilities = [\"read\"]" -ForegroundColor Gray
Write-Host "   }" -ForegroundColor Gray
Write-Host "   EOF" -ForegroundColor White
Write-Host "6. Ensure keytab is properly configured on Vault server" -ForegroundColor White
Write-Host "7. Verify SPN registration matches the hostname being used" -ForegroundColor White
Write-Host ""
