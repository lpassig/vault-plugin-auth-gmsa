# 🚀 Setup Vault for Official Kerberos Plugin - Quick Guide

## Summary

You have everything ready! Just need to run commands on the Vault server with a valid token.

---

## Step 1: SSH to Vault Server

```bash
ssh lennart@107.23.32.117
```

---

## Step 2: Set Vault Environment

```bash
# Set Vault address and token
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TOKEN="<your-valid-vault-token>"

# Verify token is valid
vault token lookup
```

---

## Step 3: Run Setup Commands

```bash
# Keytab for computer account EC2AMAZ-UB1QVDL$
KEYTAB_B64="BQIAAABRAAIACUxPQ0FMLkxBQgAESFRUUAAPdmF1bHQubG9jYWwubGFiAAAAAQAAAAACABIAIHm5fmpYTbxb5crqox9cK2YfECBk6LYDOMzV/EFE5s4Z"

# 1. Disable old gMSA auth (if exists)
vault auth disable gmsa 2>/dev/null || echo "No old gMSA found"

# 2. Enable Kerberos auth
vault auth enable -tls-skip-verify \
  -passthrough-request-headers=Authorization \
  -allowed-response-headers=www-authenticate \
  kerberos

# 3. Configure Kerberos
vault write -tls-skip-verify auth/kerberos/config \
  keytab="$KEYTAB_B64" \
  service_account="HTTP/vault.local.lab" \
  realm="LOCAL.LAB" \
  remove_instance_name=true \
  disable_fast_negotiation=false

# 4. Create role for computer accounts
vault write -tls-skip-verify auth/kerberos/role/computer-accounts \
  bound_service_account_names='*$@LOCAL.LAB' \
  token_policies="default,computer-policy" \
  token_ttl=3600 \
  token_max_ttl=7200

# 5. Create default role
vault write -tls-skip-verify auth/kerberos/role/default \
  bound_service_account_names='*$@LOCAL.LAB' \
  token_policies="default" \
  token_ttl=3600 \
  token_max_ttl=7200

# 6. Create policy
vault policy write -tls-skip-verify computer-policy - <<'EOF'
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "database/creds/*" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF

# 7. Verify
vault auth list -tls-skip-verify | grep kerberos
vault read -tls-skip-verify auth/kerberos/config
vault list -tls-skip-verify auth/kerberos/role
```

---

## Step 4: Verify Configuration

Expected output:

```
✓ kerberos/ listed in auth methods
✓ Config shows: service_account="HTTP/vault.local.lab"
✓ Roles: computer-accounts, default
✓ Policy: computer-policy
```

---

## Step 5: Test from Windows Client

**Option A: Using test-invoke-restmethod.ps1 (Pure PowerShell)**

```powershell
# On Windows CLIENT
.\test-invoke-restmethod.ps1 -VaultAddr "https://vault.local.lab:8200" -Role "computer-accounts"

# Check logs
Get-Content C:\vault-client\logs\test-invoke-restmethod.log -Tail 50
```

**Option B: Using vault-client-kerberos.ps1 (curl.exe)**

```powershell
# Deploy script
Copy-Item .\vault-client-kerberos.ps1 C:\vault-client\scripts\

# Run directly
C:\vault-client\scripts\vault-client-kerberos.ps1

# Or via scheduled task
schtasks /Create /TN "Vault Kerberos Auth" `
  /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\vault-client\scripts\vault-client-kerberos.ps1" `
  /SC HOURLY /RU "NT AUTHORITY\SYSTEM" /RL HIGHEST /F

schtasks /Run /TN "Vault Kerberos Auth"
```

---

## Troubleshooting

### If "permission denied" or "invalid token":

```bash
# Get a new root token or use your existing valid token
vault token lookup
```

### If Kerberos auth enable fails with "path already in use":

```bash
# It's already enabled, just continue with step 3
vault read -tls-skip-verify auth/kerberos/config
```

### To check if setup is complete:

```bash
# Should show kerberos auth
vault auth list -tls-skip-verify

# Should show configuration
vault read -tls-skip-verify auth/kerberos/config

# Should list roles
vault list -tls-skip-verify auth/kerberos/role
```

---

## Expected Test Result from Windows

```
[2025-09-30 12:00:00] [INFO] === VAULT KERBEROS AUTHENTICATION (OFFICIAL PLUGIN) ===
[2025-09-30 12:00:00] [INFO] Current User: EC2AMAZ-UB1QVDL$
[2025-09-30 12:00:01] [SUCCESS] SUCCESS! Vault token obtained
[2025-09-30 12:00:01] [INFO] Token: hvs.XXXXX...
[2025-09-30 12:00:01] [INFO] TTL: 3600 seconds
```

---

## Quick Reference

**Vault Setup:** `ssh lennart@107.23.32.117` → Run commands from Step 3  
**Windows Test:** Run `test-invoke-restmethod.ps1` or `vault-client-kerberos.ps1`  
**SPN Check (ADDC):** `setspn -L EC2AMAZ-UB1QVDL$` (should show HTTP/vault.local.lab)

---

**All files are ready - just need to execute on Vault server!** 🚀
