#!/bin/bash
# Setup Official HashiCorp Kerberos Plugin on Vault
# Run this on the Vault server or via SSH

set -e

export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TOKEN="${VAULT_TOKEN:-hvs.BfUGPRV0r01gHb5eTAz9sxeI}"

KEYTAB_B64="BQIAAABRAAIACUxPQ0FMLkxBQgAESFRUUAAPdmF1bHQubG9jYWwubGFiAAAAAQAAAAACABIAIHm5fmpYTbxb5crqox9cK2YfECBk6LYDOMzV/EFE5s4Z"

echo "=========================================="
echo "OFFICIAL KERBEROS PLUGIN SETUP"
echo "=========================================="
echo ""

# Step 1: Check Vault version
echo "Step 1: Checking Vault version..."
echo "-----------------------------------"
VAULT_VERSION=$(vault version | grep -oP 'Vault v\K[0-9.]+' || echo "unknown")
echo "Vault Version: $VAULT_VERSION"
echo ""

# Step 2: Disable old gMSA auth if it exists
echo "Step 2: Cleaning up old auth methods..."
echo "----------------------------------------"
vault auth disable gmsa 2>/dev/null && echo "✓ Disabled old gMSA auth method" || echo "✓ No old gMSA auth method found"
echo ""

# Step 3: Enable official Kerberos auth method
echo "Step 3: Enabling official Kerberos auth method..."
echo "--------------------------------------------------"
vault auth enable -tls-skip-verify \
  -passthrough-request-headers=Authorization \
  -allowed-response-headers=www-authenticate \
  kerberos

if [ $? -eq 0 ]; then
    echo "✓ Kerberos auth method enabled successfully"
else
    echo "Note: Kerberos auth may already be enabled (this is OK)"
fi
echo ""

# Step 4: Configure Kerberos auth with computer account keytab
echo "Step 4: Configuring Kerberos authentication..."
echo "-----------------------------------------------"
vault write -tls-skip-verify auth/kerberos/config \
  keytab="$KEYTAB_B64" \
  service_account="HTTP/vault.local.lab" \
  realm="LOCAL.LAB" \
  remove_instance_name=true \
  disable_fast_negotiation=false

if [ $? -eq 0 ]; then
    echo "✓ Kerberos configuration successful"
else
    echo "✗ Failed to configure Kerberos"
    exit 1
fi
echo ""

# Step 5: Configure LDAP for group lookups (optional but recommended)
echo "Step 5: Configuring LDAP integration..."
echo "----------------------------------------"
vault write -tls-skip-verify auth/kerberos/config/ldap \
  url="ldap://10.0.101.152" \
  binddn="CN=vault-keytab-svc,CN=Users,DC=local,DC=lab" \
  bindpass="Pa\$\$w0rd" \
  userdn="CN=Computers,DC=local,DC=lab" \
  userattr="sAMAccountName" \
  groupdn="CN=Users,DC=local,DC=lab" \
  groupattr="cn" \
  insecure_tls=true

if [ $? -eq 0 ]; then
    echo "✓ LDAP integration configured"
else
    echo "⚠ LDAP configuration failed (optional feature, continuing...)"
fi
echo ""

# Step 6: Create role for computer accounts
echo "Step 6: Creating role for computer accounts..."
echo "-----------------------------------------------"
vault write -tls-skip-verify auth/kerberos/role/computer-accounts \
  bound_service_account_names='*$@LOCAL.LAB' \
  token_policies="default,computer-policy" \
  token_ttl=3600 \
  token_max_ttl=7200

if [ $? -eq 0 ]; then
    echo "✓ Computer accounts role created"
else
    echo "✗ Failed to create role"
    exit 1
fi
echo ""

# Step 7: Create default role (for clients that don't specify a role)
echo "Step 7: Creating default role..."
echo "---------------------------------"
vault write -tls-skip-verify auth/kerberos/role/default \
  bound_service_account_names='*$@LOCAL.LAB' \
  token_policies="default" \
  token_ttl=3600 \
  token_max_ttl=7200

if [ $? -eq 0 ]; then
    echo "✓ Default role created"
else
    echo "⚠ Default role creation failed (optional)"
fi
echo ""

# Step 8: Create policy for computer accounts
echo "Step 8: Creating policy for computer accounts..."
echo "-------------------------------------------------"
vault policy write -tls-skip-verify computer-policy - <<EOF
# Allow reading secrets in secret/data/*
path "secret/data/*" {
  capabilities = ["read", "list"]
}

# Allow reading database credentials
path "database/creds/*" {
  capabilities = ["read"]
}

# Allow token renewal
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow token lookup
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF

if [ $? -eq 0 ]; then
    echo "✓ Computer policy created"
else
    echo "✗ Failed to create policy"
    exit 1
fi
echo ""

# Step 9: Verify configuration
echo "Step 9: Verifying configuration..."
echo "-----------------------------------"
echo ""
echo "Auth Methods:"
vault auth list -tls-skip-verify | grep kerberos && echo "✓ Kerberos auth enabled" || echo "✗ Kerberos auth not found"
echo ""

echo "Kerberos Configuration:"
vault read -tls-skip-verify auth/kerberos/config
echo ""

echo "Kerberos Roles:"
vault list -tls-skip-verify auth/kerberos/role 2>/dev/null || echo "No roles found"
echo ""

echo "Policies:"
vault policy list -tls-skip-verify | grep computer-policy && echo "✓ computer-policy exists" || echo "✗ computer-policy not found"
echo ""

echo "=========================================="
echo "SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "Configuration Summary:"
echo "----------------------"
echo "✓ Auth Method: kerberos (official HashiCorp plugin)"
echo "✓ Endpoint: /v1/auth/kerberos/login"
echo "✓ SPN: HTTP/vault.local.lab@LOCAL.LAB"
echo "✓ Realm: LOCAL.LAB"
echo "✓ Roles: computer-accounts, default"
echo "✓ Policy: computer-policy"
echo ""
echo "Client Configuration:"
echo "---------------------"
echo "Computer Account: EC2AMAZ-UB1QVDL\$@LOCAL.LAB"
echo "SPN Registration: HTTP/vault.local.lab on EC2AMAZ-UB1QVDL\$"
echo "Auth URL: https://vault.local.lab:8200/v1/auth/kerberos/login"
echo ""
echo "Next Steps:"
echo "-----------"
echo "1. On ADDC: Verify SPN is on computer account"
echo "   setspn -L EC2AMAZ-UB1QVDL\$"
echo ""
echo "2. On Windows CLIENT: Deploy vault-client-kerberos.ps1"
echo ""
echo "3. On Windows CLIENT: Run authentication test"
echo "   schtasks /Run /TN \"Vault Kerberos Auth\""
echo ""
echo "=========================================="
