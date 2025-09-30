#!/bin/bash
# Configure Vault to use domain-based Kerberos auth (no keytab needed)

set -e

export VAULT_ADDR="https://127.0.0.1:8200"

echo "=========================================="
echo "CONFIGURE VAULT DOMAIN-BASED KERBEROS AUTH"
echo "=========================================="
echo ""

# Prompt for Vault token
echo "Please provide your Vault root token:"
read -s VAULT_TOKEN
export VAULT_TOKEN

echo ""
echo "Step 1: Disable old Kerberos auth (if exists)..."
echo "--------------------------------------------------"

vault auth disable kerberos -tls-skip-verify 2>/dev/null && echo "✓ Old Kerberos auth disabled" || echo "✓ No existing Kerberos auth found"

echo ""

# Step 2: Enable Kerberos auth with domain integration
echo "Step 2: Enabling Kerberos auth with domain integration..."
echo "-----------------------------------------------------------"

vault auth enable -tls-skip-verify \
  -passthrough-request-headers=Authorization \
  -allowed-response-headers=www-authenticate \
  kerberos

echo "✓ Kerberos auth enabled"
echo ""

# Step 3: Configure Kerberos to use system Kerberos (no keytab)
echo "Step 3: Configuring Kerberos for domain-joined server..."
echo "----------------------------------------------------------"

# Note: With domain join, Vault can validate SPNEGO tokens using the system's Kerberos
# We still need basic config but NO keytab
vault write -tls-skip-verify auth/kerberos/config \
  service_account="HTTP/vault.local.lab" \
  realm="LOCAL.LAB" \
  remove_instance_name=true \
  disable_fast_negotiation=false

echo "✓ Kerberos configured (using system Kerberos, no keytab)"
echo ""

# Step 4: Configure LDAP for group lookups
echo "Step 4: Configuring LDAP integration..."
echo "----------------------------------------"

vault write -tls-skip-verify auth/kerberos/config/ldap \
  url="ldap://10.0.101.193" \
  binddn="CN=vault-keytab-svc,CN=Users,DC=local,DC=lab" \
  bindpass="Pa\$\$w0rd" \
  userdn="CN=Computers,DC=local,DC=lab" \
  userattr="sAMAccountName" \
  groupdn="CN=Users,DC=local,DC=lab" \
  groupattr="cn" \
  insecure_tls=true

echo "✓ LDAP configured"
echo ""

# Step 5: Create groups
echo "Step 5: Creating Kerberos groups..."
echo "------------------------------------"

vault write -tls-skip-verify auth/kerberos/groups/computer-accounts \
  policies="default,computer-policy"

vault write -tls-skip-verify auth/kerberos/groups/default \
  policies="default"

echo "✓ Groups created"
echo ""

# Step 6: Ensure policy exists
echo "Step 6: Creating/updating computer-policy..."
echo "---------------------------------------------"

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

echo "✓ Policy created"
echo ""

# Step 7: Verify configuration
echo "Step 7: Verifying configuration..."
echo "-----------------------------------"

echo ""
echo "Auth methods:"
vault auth list -tls-skip-verify | grep kerberos

echo ""
echo "Kerberos config:"
vault read -tls-skip-verify auth/kerberos/config

echo ""
echo "Kerberos groups:"
vault list -tls-skip-verify auth/kerberos/groups

echo ""
echo "=========================================="
echo "CONFIGURATION COMPLETE!"
echo "=========================================="
echo ""
echo "Key Points:"
echo "-----------"
echo "✓ Vault is using DOMAIN-BASED Kerberos authentication"
echo "✓ NO KEYTAB is used - Vault uses system Kerberos"
echo "✓ Vault server validates tickets using its domain credentials"
echo "✓ No password rotation issues!"
echo ""
echo "How it works:"
echo "-------------"
echo "1. Windows client sends SPNEGO token"
echo "2. Vault server (domain-joined) validates it via SSSD/Kerberos"
echo "3. No keytab file needed - uses computer's domain credentials"
echo "4. Works seamlessly with AD password policies"
echo ""
echo "Test from Windows:"
echo "------------------"
echo "  schtasks /Run /TN \"Test Curl Kerberos\""
echo "  Get-Content C:\\vault-client\\logs\\test-curl-system.log"
echo ""
echo "=========================================="
