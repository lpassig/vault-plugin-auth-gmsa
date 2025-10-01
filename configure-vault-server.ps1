# Vault Server Configuration Script for gMSA Authentication
# This script helps configure the Vault server for gMSA authentication

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$VaultToken = "",  # Root token for configuration
    [string]$GMSARole = "vault-gmsa-role",
    [string]$PolicyName = "vault-gmsa-policy"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Vault Server Configuration for gMSA" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# SSL Certificate bypass for testing
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

if (-not $VaultToken) {
    Write-Host "ERROR: Vault token is required for configuration" -ForegroundColor Red
    Write-Host "Usage: .\configure-vault-server.ps1 -VaultToken <root-token>" -ForegroundColor Yellow
    exit 1
}

Write-Host "Vault Server Configuration:" -ForegroundColor Yellow
Write-Host "  URL: $VaultUrl" -ForegroundColor White
Write-Host "  Token: $($VaultToken.Substring(0, 8))..." -ForegroundColor White
Write-Host "  gMSA Role: $GMSARole" -ForegroundColor White
Write-Host "  Policy Name: $PolicyName" -ForegroundColor White
Write-Host ""

# Function to execute Vault commands
function Invoke-VaultCommand {
    param(
        [string]$Method,
        [string]$Path,
        [hashtable]$Body = @{},
        [string]$Description
    )
    
    try {
        Write-Host "Executing: $Description" -ForegroundColor Cyan
        
        $headers = @{
            "X-Vault-Token" = $VaultToken
            "Content-Type" = "application/json"
        }
        
        if ($Method -eq "GET") {
            $response = Invoke-RestMethod -Uri "$VaultUrl$Path" -Method Get -Headers $headers
        } else {
            $response = Invoke-RestMethod -Uri "$VaultUrl$Path" -Method $Method -Body ($Body | ConvertTo-Json) -Headers $headers
        }
        
        Write-Host "SUCCESS: $Description" -ForegroundColor Green
        return $response
    } catch {
        Write-Host "ERROR: $Description failed" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Step 1: Enable Kerberos Auth Method (Built-in)
Write-Host "Step 1: Enabling Kerberos Authentication Method (Built-in)" -ForegroundColor Yellow
$authResult = Invoke-VaultCommand -Method "POST" -Path "/v1/sys/auth/kerberos" -Body @{
    type = "kerberos"
    description = "Kerberos Authentication Method for gMSA"
} -Description "Enable Kerberos auth method"

if ($authResult) {
    Write-Host "SUCCESS: Kerberos auth method enabled" -ForegroundColor Green
} else {
    Write-Host "WARNING: Kerberos auth method may already be enabled" -ForegroundColor Yellow
}
Write-Host ""

# Step 2: Create Policy for gMSA
Write-Host "Step 2: Creating Policy for gMSA" -ForegroundColor Yellow
$policyContent = @"
path "kv/data/my-app/*" {
  capabilities = ["read"]
}

path "kv/data/my-app/database" {
  capabilities = ["read"]
}

path "kv/data/my-app/api" {
  capabilities = ["read"]
}

path "kv/metadata/my-app/*" {
  capabilities = ["read", "list"]
}
"@

$policyResult = Invoke-VaultCommand -Method "POST" -Path "/v1/sys/policy/$PolicyName" -Body @{
    policy = $policyContent
} -Description "Create gMSA policy"

if ($policyResult) {
    Write-Host "SUCCESS: Policy '$PolicyName' created" -ForegroundColor Green
} else {
    Write-Host "WARNING: Policy '$PolicyName' may already exist" -ForegroundColor Yellow
}
Write-Host ""

# Step 3: Configure Kerberos Auth Method
Write-Host "Step 3: Configuring Kerberos Auth Method" -ForegroundColor Yellow
$kerberosConfig = Invoke-VaultCommand -Method "POST" -Path "/v1/auth/kerberos/config" -Body @{
    keytab = "/etc/vault/vault.keytab"
    service_account = "HTTP/vault.local.lab"
    realm = "LOCAL.LAB"
    disable_fast_negotiation = $false
} -Description "Configure Kerberos auth method"

if ($kerberosConfig) {
    Write-Host "SUCCESS: Kerberos auth method configured" -ForegroundColor Green
} else {
    Write-Host "WARNING: Kerberos auth method may already be configured" -ForegroundColor Yellow
}
Write-Host ""

# Step 4: Create Kerberos Role
Write-Host "Step 4: Creating Kerberos Role" -ForegroundColor Yellow
$roleResult = Invoke-VaultCommand -Method "POST" -Path "/v1/auth/kerberos/role/$GMSARole" -Body @{
    policies = @($PolicyName)
    token_ttl = "1h"
    token_max_ttl = "24h"
    token_policies = @($PolicyName)
} -Description "Create Kerberos role"

if ($roleResult) {
    Write-Host "SUCCESS: Role '$GMSARole' created" -ForegroundColor Green
} else {
    Write-Host "WARNING: Role '$GMSARole' may already exist" -ForegroundColor Yellow
}
Write-Host ""

# Step 4: Enable KV Secrets Engine
Write-Host "Step 4: Enabling KV Secrets Engine" -ForegroundColor Yellow
$kvResult = Invoke-VaultCommand -Method "POST" -Path "/v1/sys/mounts/kv" -Body @{
    type = "kv"
    version = 2
    description = "Key-Value Secrets Engine"
} -Description "Enable KV secrets engine"

if ($kvResult) {
    Write-Host "SUCCESS: KV secrets engine enabled" -ForegroundColor Green
} else {
    Write-Host "WARNING: KV secrets engine may already be enabled" -ForegroundColor Yellow
}
Write-Host ""

# Step 5: Create Sample Secrets
Write-Host "Step 5: Creating Sample Secrets" -ForegroundColor Yellow
$secrets = @(
    @{
        path = "kv/data/my-app/database"
        data = @{
            username = "db_user"
            password = "db_password_123"
            host = "database.example.com"
            port = "5432"
        }
    },
    @{
        path = "kv/data/my-app/api"
        data = @{
            api_key = "api_key_456"
            endpoint = "https://api.example.com"
            timeout = "30"
        }
    }
)

foreach ($secret in $secrets) {
    $secretResult = Invoke-VaultCommand -Method "POST" -Path "/v1/$($secret.path)" -Body @{
        data = $secret.data
    } -Description "Create secret at $($secret.path)"
    
    if ($secretResult) {
        Write-Host "SUCCESS: Secret created at $($secret.path)" -ForegroundColor Green
    }
}
Write-Host ""

# Step 6: Verify Configuration
Write-Host "Step 6: Verifying Configuration" -ForegroundColor Yellow

# Check auth methods
$authMethods = Invoke-VaultCommand -Method "GET" -Path "/v1/sys/auth" -Description "Check auth methods"
if ($authMethods -and $authMethods.data.ContainsKey("gmsa/")) {
    Write-Host "SUCCESS: gMSA auth method is enabled" -ForegroundColor Green
} else {
    Write-Host "ERROR: gMSA auth method is not enabled" -ForegroundColor Red
}

# Check policies
$policies = Invoke-VaultCommand -Method "GET" -Path "/v1/sys/policy" -Description "Check policies"
if ($policies -and $policies.data.ContainsKey($PolicyName)) {
    Write-Host "SUCCESS: Policy '$PolicyName' exists" -ForegroundColor Green
} else {
    Write-Host "ERROR: Policy '$PolicyName' does not exist" -ForegroundColor Red
}

# Check roles
$roles = Invoke-VaultCommand -Method "GET" -Path "/v1/auth/gmsa/role" -Description "Check gMSA roles"
if ($roles -and $roles.data.ContainsKey($GMSARole)) {
    Write-Host "SUCCESS: Role '$GMSARole' exists" -ForegroundColor Green
} else {
    Write-Host "ERROR: Role '$GMSARole' does not exist" -ForegroundColor Red
}

# Check secrets engine
$mounts = Invoke-VaultCommand -Method "GET" -Path "/v1/sys/mounts" -Description "Check secrets engines"
if ($mounts -and $mounts.data.ContainsKey("kv/")) {
    Write-Host "SUCCESS: KV secrets engine is enabled" -ForegroundColor Green
} else {
    Write-Host "ERROR: KV secrets engine is not enabled" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Configuration Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Configure keytab on Vault server for Kerberos authentication" -ForegroundColor White
Write-Host "2. Ensure SPN 'HTTP/vault.local.lab' is registered in Active Directory" -ForegroundColor White
Write-Host "3. Test authentication with: .\test-real-issue.ps1" -ForegroundColor White
Write-Host "4. Run the client application as a scheduled task under gMSA identity" -ForegroundColor White
Write-Host ""

Write-Host "KEYTAB CONFIGURATION:" -ForegroundColor Yellow
Write-Host "The Vault server needs a keytab file with the SPN 'HTTP/vault.local.lab'" -ForegroundColor White
Write-Host "Place the keytab file on the Vault server and configure the gMSA plugin to use it" -ForegroundColor White
Write-Host ""

Write-Host "TESTING COMMANDS:" -ForegroundColor Yellow
Write-Host "1. Validate server: .\validate-vault-server-config.ps1" -ForegroundColor White
Write-Host "2. Test client: .\test-real-issue.ps1" -ForegroundColor White
Write-Host "3. Run application: .\vault-client-app.ps1" -ForegroundColor White
Write-Host ""