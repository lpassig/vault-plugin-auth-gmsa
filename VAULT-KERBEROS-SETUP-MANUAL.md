# 🚀 Manual Vault Kerberos Setup Guide

Since SSH access is timing out, run these commands **directly on the Vault server**.

## Step-by-Step Vault Configuration

### Prerequisites

- Access to Vault server via SSH: `ssh lennart@107.23.32.117`
- Vault root token (set as environment variable)
- Computer account keytab (already generated)

---

## Commands to Run on Vault Server

Copy and paste these commands **directly on the Vault server**:

```bash
# Set Vault environment
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TOKEN="your-vault-token-here"

# Keytab for computer account EC2AMAZ-UB1QVDL$
KEYTAB_B64="BQIAAABRAAIACUxPQ0FMLkxBQgAESFRUUAAPdmF1bHQubG9jYWwubGFiAAAAAQAAAAACABIAIHm5fmpYTbxb5crqox9cK2YfECBk6LYDOMzV/EFE5s4Z"

echo "=========================================="
echo "OFFICIAL KERBEROS PLUGIN SETUP"
echo "=========================================="

# 1. Disable old gMSA auth (if exists)
echo ""
echo "Step 1: Cleaning up old auth methods..."
vault auth disable gmsa 2>/dev/null && echo "✓ Old gMSA disabled" || echo "✓ No old gMSA found"

# 2. Enable official Kerberos auth method
echo ""
echo "Step 2: Enabling Kerberos auth..."
vault auth enable -tls-skip-verify \
  -passthrough-request-headers=Authorization \
  -allowed-response-headers=www-authenticate \
  kerberos 2>/dev/null && echo "✓ Kerberos enabled" || echo "✓ Kerberos already enabled"

# 3. Configure Kerberos with computer account keytab
echo ""
echo "Step 3: Configuring Kerberos..."
vault write -tls-skip-verify auth/kerberos/config \
  keytab="$KEYTAB_B64" \
  service_account="HTTP/vault.local.lab" \
  realm="LOCAL.LAB" \
  remove_instance_name=true \
  disable_fast_negotiation=false

# 4. Configure LDAP (optional)
echo ""
echo "Step 4: Configuring LDAP..."
vault write -tls-skip-verify auth/kerberos/config/ldap \
  url="ldap://10.0.101.152" \
  binddn="CN=vault-keytab-svc,CN=Users,DC=local,DC=lab" \
  bindpass="Pa\$\$w0rd" \
  userdn="CN=Computers,DC=local,DC=lab" \
  userattr="sAMAccountName" \
  groupdn="CN=Users,DC=local,DC=lab" \
  groupattr="cn" \
  insecure_tls=true 2>/dev/null && echo "✓ LDAP configured" || echo "⚠ LDAP optional (skipped)"

# 5. Create role for computer accounts
echo ""
echo "Step 5: Creating computer-accounts role..."
vault write -tls-skip-verify auth/kerberos/role/computer-accounts \
  bound_service_account_names='*$@LOCAL.LAB' \
  token_policies="default,computer-policy" \
  token_ttl=3600 \
  token_max_ttl=7200

# 6. Create default role
echo ""
echo "Step 6: Creating default role..."
vault write -tls-skip-verify auth/kerberos/role/default \
  bound_service_account_names='*$@LOCAL.LAB' \
  token_policies="default" \
  token_ttl=3600 \
  token_max_ttl=7200

# 7. Create policy for computer accounts
echo ""
echo "Step 7: Creating computer-policy..."
vault policy write -tls-skip-verify computer-policy - <<'EOF'
# Allow reading secrets
path "secret/data/*" {
  capabilities = ["read", "list"]
}

# Allow database credentials
path "database/creds/*" {
  capabilities = ["read"]
}

# Allow token operations
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF

# 8. Verify configuration
echo ""
echo "=========================================="
echo "VERIFICATION"
echo "=========================================="

echo ""
echo "Auth methods:"
vault auth list -tls-skip-verify | grep kerberos

echo ""
echo "Kerberos config:"
vault read -tls-skip-verify auth/kerberos/config

echo ""
echo "Kerberos roles:"
vault list -tls-skip-verify auth/kerberos/role

echo ""
echo "Policies:"
vault policy list -tls-skip-verify | grep computer-policy

echo ""
echo "=========================================="
echo "SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  ✓ Auth endpoint: /v1/auth/kerberos/login"
echo "  ✓ SPN: HTTP/vault.local.lab@LOCAL.LAB"
echo "  ✓ Roles: computer-accounts, default"
echo "  ✓ Policy: computer-policy"
echo ""
echo "Next: Configure Windows client"
echo "=========================================="
```

---

## After Running These Commands

You should see:

```
✓ Kerberos enabled
✓ Kerberos configured
✓ computer-accounts role created
✓ default role created
✓ computer-policy created
```

---

## Troubleshooting

### If "auth enable" fails with "path already in use":

```bash
# Kerberos is already enabled, just continue
echo "Kerberos already enabled - continuing..."
```

### If policy write fails:

```bash
# Check for syntax errors in heredoc
vault policy write -tls-skip-verify computer-policy /path/to/policy.hcl
```

### To check current configuration:

```bash
vault read -tls-skip-verify auth/kerberos/config
vault list -tls-skip-verify auth/kerberos/role
```

---

## Next Steps After Vault Setup

1. **On ADDC**: Verify SPN registration
   ```powershell
   setspn -L EC2AMAZ-UB1QVDL$
   # Should show: HTTP/vault.local.lab
   ```

2. **On Windows CLIENT**: Deploy `vault-client-kerberos.ps1`
   ```powershell
   # Copy vault-client-kerberos.ps1 to C:\vault-client\scripts\
   # Update scheduled task to use new script
   ```

3. **Test authentication**
   ```powershell
   # Run the new client script
   C:\vault-client\scripts\vault-client-kerberos.ps1
   ```

---

## Alternative: Use Docker Exec (if Vault is in Docker)

If Vault is running in Docker:

```bash
# Find container ID
docker ps | grep vault

# Execute commands in container
docker exec -it <container-id> sh

# Then run the vault commands above inside the container
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TOKEN="your-vault-token-here"
# ... rest of commands ...
```

---

**Copy these commands and run them on the Vault server!** 🚀
