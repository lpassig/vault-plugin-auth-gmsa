# Vault Server gMSA Configuration Fix

## Overview

This document provides comprehensive scripts to fix the Vault server configuration for proper gMSA authentication. The scripts address the root cause of "400 Bad Request" errors by properly configuring the gMSA authentication method according to the Go implementation requirements.

## Problem Analysis

The PowerShell client was failing with "400 Bad Request" errors because:

1. **Vault server was not properly configured** for gMSA authentication
2. **Missing SPNEGO negotiation** - no `WWW-Authenticate: Negotiate` headers
3. **Incorrect gMSA auth method setup** - missing keytab, SPN, or realm configuration
4. **Missing roles and policies** for gMSA authentication

## Solution Scripts

### 1. PowerShell Configuration Script (Windows)

**File**: `fix-vault-server-config.ps1`

**Usage**:
```powershell
# Basic usage
.\fix-vault-server-config.ps1

# With custom parameters
.\fix-vault-server-config.ps1 -VaultUrl "https://vault.company.com:8200" -VaultToken "hvs.xxx" -KeytabPath "C:\vault-keytab.keytab"

# Dry run (show commands without executing)
.\fix-vault-server-config.ps1 -DryRun
```

**Features**:
- ✅ Tests Vault server connectivity
- ✅ Validates keytab file and converts to base64
- ✅ Enables gMSA authentication method
- ✅ Configures gMSA authentication with proper parameters
- ✅ Creates gMSA policy and role
- ✅ Enables KV secrets engine
- ✅ Creates test secrets
- ✅ Tests SPNEGO negotiation
- ✅ Provides detailed logging and error handling

### 2. Bash Configuration Script (Linux)

**File**: `fix-vault-server-config.sh`

**Usage**:
```bash
# Basic usage
./fix-vault-server-config.sh

# With environment variables
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="hvs.xxx"
export KEYTAB_PATH="/path/to/vault-keytab.keytab"
./fix-vault-server-config.sh
```

**Features**:
- ✅ Same functionality as PowerShell script
- ✅ Optimized for Linux Vault servers
- ✅ Uses Vault CLI commands directly
- ✅ Color-coded output for better readability
- ✅ Comprehensive error handling

## Configuration Details

### gMSA Authentication Method Configuration

The scripts configure the gMSA authentication method with these parameters:

```json
{
  "realm": "LOCAL.LAB",
  "kdcs": "ADDC.local.lab",
  "keytab": "<BASE64_KEYTAB>",
  "spn": "HTTP/vault.local.lab",
  "allow_channel_binding": false,
  "clock_skew_sec": 300,
  "realm_case_sensitive": false,
  "spn_case_sensitive": false
}
```

### gMSA Role Configuration

```json
{
  "allowed_realms": "LOCAL.LAB",
  "allowed_spns": "HTTP/vault.local.lab",
  "token_policies": "vault-gmsa-policy",
  "token_type": "default",
  "period": 0,
  "max_ttl": 3600
}
```

### gMSA Policy

```hcl
path "kv/data/my-app/*" {
  capabilities = ["read"]
}

path "kv/data/vault-gmsa/*" {
  capabilities = ["read"]
}

path "secret/data/my-app/*" {
  capabilities = ["read"]
}
```

## Prerequisites

### 1. Vault Server Access
- Vault server must be running and accessible
- Valid Vault token with admin privileges
- Vault CLI installed (for Linux script)

### 2. Keytab File
- Valid keytab file for the gMSA service account
- Keytab must contain the SPN: `HTTP/vault.local.lab`
- Keytab must be accessible from the script location

### 3. Network Connectivity
- Vault server must be reachable from the client
- DNS resolution for `vault.local.lab` must work
- Kerberos KDC (`ADDC.local.lab`) must be accessible

## Step-by-Step Execution

### Step 1: Prepare Environment

**Windows**:
```powershell
# Set Vault URL and token
$env:VAULT_ADDR = "https://vault.example.com:8200"
$env:VAULT_TOKEN = "hvs.your-token-here"

# Ensure keytab file exists
Test-Path "C:\vault-keytab.keytab"
```

**Linux**:
```bash
# Set environment variables
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="hvs.your-token-here"
export KEYTAB_PATH="/home/lennart/vault-keytab.keytab"
```

### Step 2: Run Configuration Script

**Windows**:
```powershell
.\fix-vault-server-config.ps1
```

**Linux**:
```bash
./fix-vault-server-config.sh
```

### Step 3: Verify Configuration

The scripts automatically test the configuration, but you can also verify manually:

```bash
# Check gMSA auth method
vault auth list

# Check gMSA configuration
vault read auth/gmsa/config

# Check gMSA role
vault read auth/gmsa/role/vault-gmsa-role

# Test SPNEGO negotiation
curl -X POST -H "Content-Type: application/json" \
  -d '{"role":"vault-gmsa-role"}' \
  http://127.0.0.1:8200/v1/auth/gmsa/login
```

Expected response: `401 Unauthorized` with `WWW-Authenticate: Negotiate` header

## Troubleshooting

### Common Issues

#### 1. "gMSA auth method not enabled"
**Solution**: The script will enable it automatically. If it fails, run manually:
```bash
vault auth enable gmsa
```

#### 2. "Invalid keytab encoding"
**Solution**: Ensure the keytab file is valid and accessible:
```bash
# Check keytab file
file /path/to/vault-keytab.keytab
# Should show: data (binary file)

# Convert to base64
base64 -w 0 /path/to/vault-keytab.keytab
```

#### 3. "SPNEGO negotiation not configured"
**Solution**: Check that the gMSA configuration includes the correct SPN:
```bash
vault read auth/gmsa/config
# Verify spn = "HTTP/vault.local.lab"
```

#### 4. "Role not found"
**Solution**: The script creates the role automatically. If it fails, run manually:
```bash
vault write auth/gmsa/role/vault-gmsa-role \
  allowed_realms="LOCAL.LAB" \
  allowed_spns="HTTP/vault.local.lab" \
  token_policies="vault-gmsa-policy" \
  token_ttl=1h
```

### Debugging Commands

```bash
# Check Vault server status
vault status

# Check authentication methods
vault auth list

# Check gMSA configuration
vault read auth/gmsa/config -format=json

# Check gMSA role
vault read auth/gmsa/role/vault-gmsa-role -format=json

# Check policies
vault policy list
vault policy read vault-gmsa-policy

# Check secrets engines
vault secrets list

# Test secrets
vault kv get kv/my-app/database
vault kv get kv/my-app/api
```

## Expected Results

After running the configuration script, you should see:

### 1. Vault Server Configuration
- ✅ gMSA authentication method enabled
- ✅ gMSA configuration with correct SPN and realm
- ✅ gMSA role with proper constraints
- ✅ gMSA policy with read permissions
- ✅ KV secrets engine enabled
- ✅ Test secrets created

### 2. SPNEGO Negotiation
- ✅ `WWW-Authenticate: Negotiate` header in 401 responses
- ✅ Proper SPNEGO challenge/response flow
- ✅ Support for Windows SSPI integration

### 3. PowerShell Client Compatibility
- ✅ PowerShell client can now generate real SPNEGO tokens
- ✅ Vault server can validate SPNEGO tokens
- ✅ Successful authentication and secret retrieval

## Next Steps

After fixing the Vault server configuration:

1. **Test the PowerShell client**: Run `.\vault-client-app.ps1`
2. **Verify authentication**: Check that real SPNEGO tokens are generated
3. **Monitor Vault logs**: Watch for authentication success/failure
4. **Test secret retrieval**: Verify that secrets are properly accessed

## Manual Configuration (Fallback)

If the scripts fail, you can configure manually:

```bash
# 1. Enable gMSA auth method
vault auth enable gmsa

# 2. Configure gMSA authentication
vault write auth/gmsa/config \
  realm="LOCAL.LAB" \
  kdcs="ADDC.local.lab" \
  keytab="$(base64 -w 0 /path/to/vault-keytab.keytab)" \
  spn="HTTP/vault.local.lab" \
  allow_channel_binding=false

# 3. Create policy
vault policy write vault-gmsa-policy - <<EOF
path "kv/data/my-app/*" {
  capabilities = ["read"]
}
EOF

# 4. Create role
vault write auth/gmsa/role/vault-gmsa-role \
  allowed_realms="LOCAL.LAB" \
  allowed_spns="HTTP/vault.local.lab" \
  token_policies="vault-gmsa-policy" \
  token_ttl=1h

# 5. Enable KV secrets engine
vault secrets enable -path=kv kv-v2

# 6. Create test secrets
vault kv put kv/my-app/database host=db-server.local.lab username=app-user password=secure-password-123
vault kv put kv/my-app/api api_key=abc123def456ghi789 endpoint=https://api.local.lab
```

This configuration ensures that the Vault server properly supports gMSA authentication and can validate SPNEGO tokens from the PowerShell client.
