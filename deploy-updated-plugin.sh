#!/bin/bash
# Deploy Updated Vault gMSA Plugin with HTTP Negotiate Protocol Support

set -e

echo "=========================================="
echo "Deploy Updated Vault gMSA Plugin"
echo "=========================================="
echo ""

# Configuration
VAULT_ADDR="${VAULT_ADDR:-https://vault.local.lab:8200}"
PLUGIN_NAME="vault-plugin-auth-gmsa"
PLUGIN_PATH="/vault/plugins/${PLUGIN_NAME}"
AUTH_PATH="gmsa"

echo "Configuration:"
echo "  Vault Address: $VAULT_ADDR"
echo "  Plugin Name: $PLUGIN_NAME"
echo "  Plugin Path: $PLUGIN_PATH"
echo "  Auth Path: $AUTH_PATH"
echo ""

# Step 1: Copy plugin to Vault server
echo "Step 1: Copying updated plugin to Vault server..."
echo "Command: scp bin/${PLUGIN_NAME} lennart@107.23.32.117:/tmp/"
scp bin/${PLUGIN_NAME} lennart@107.23.32.117:/tmp/
echo "✓ Plugin copied to /tmp/ on Vault server"
echo ""

# Step 2: Move plugin to Docker container
echo "Step 2: Moving plugin into Vault Docker container..."
CONTAINER_ID=$(ssh lennart@107.23.32.117 "sudo docker ps --filter 'name=vault' --format '{{.ID}}'")
echo "  Container ID: $CONTAINER_ID"

ssh lennart@107.23.32.117 "sudo docker cp /tmp/${PLUGIN_NAME} ${CONTAINER_ID}:${PLUGIN_PATH}"
echo "✓ Plugin moved to ${PLUGIN_PATH} in container"
echo ""

# Step 3: Set executable permissions
echo "Step 3: Setting executable permissions..."
ssh lennart@107.23.32.117 "sudo docker exec ${CONTAINER_ID} chmod +x ${PLUGIN_PATH}"
echo "✓ Plugin is now executable"
echo ""

# Step 4: Calculate SHA256
echo "Step 4: Calculating plugin SHA256..."
PLUGIN_SHA256=$(ssh lennart@107.23.32.117 "sudo docker exec ${CONTAINER_ID} sha256sum ${PLUGIN_PATH} | cut -d' ' -f1")
echo "  SHA256: $PLUGIN_SHA256"
echo ""

# Step 5: Disable existing auth method
echo "Step 5: Disabling existing auth method..."
export VAULT_SKIP_VERIFY=1
vault auth disable ${AUTH_PATH} 2>/dev/null || echo "  (Auth method not enabled, skipping)"
echo "✓ Existing auth method disabled"
echo ""

# Step 6: Deregister old plugin
echo "Step 6: Deregistering old plugin..."
vault plugin deregister auth ${PLUGIN_NAME} 2>/dev/null || echo "  (Plugin not registered, skipping)"
echo "✓ Old plugin deregistered"
echo ""

# Step 7: Register updated plugin
echo "Step 7: Registering updated plugin..."
vault plugin register \
    -sha256="${PLUGIN_SHA256}" \
    -command="${PLUGIN_NAME}" \
    auth ${PLUGIN_NAME}
echo "✓ Plugin registered successfully"
echo ""

# Step 8: Enable auth method with Authorization header passthrough
echo "Step 8: Enabling auth method with HTTP Negotiate support..."
vault auth enable \
    -path=${AUTH_PATH} \
    -passthrough-request-headers=Authorization \
    -allowed-response-headers=www-authenticate \
    ${PLUGIN_NAME}
echo "✓ Auth method enabled with Authorization header passthrough"
echo ""

# Step 9: Configure the auth method
echo "Step 9: Configuring auth method..."
KEYTAB_B64="BQIAAABVAAIACUxPQ0FMLkxBQgAESFRUUAAPdmF1bHQubG9jYWwubGFiAAAAAWjbrcYBABIAIP+YVCp3kvBhhHgkBHiiOLaKMxHHwo1hkIEa68AatEIDAAAAAQ=="

vault write auth/${AUTH_PATH}/config \
    keytab="${KEYTAB_B64}" \
    spn="HTTP/vault.local.lab" \
    realm="LOCAL.LAB" \
    kdcs="ADDC.local.lab:88"
echo "✓ Auth method configured"
echo ""

# Step 10: Create default role for HTTP Negotiate
echo "Step 10: Creating default role for HTTP Negotiate protocol..."
vault write auth/${AUTH_PATH}/role/default \
    token_policies="gmsa-policy" \
    allowed_realms="LOCAL.LAB" \
    allowed_spns="HTTP/vault.local.lab"
echo "✓ Default role created"
echo ""

# Step 11: Create vault-gmsa-role (for backward compatibility)
echo "Step 11: Creating vault-gmsa-role (backward compatibility)..."
vault write auth/${AUTH_PATH}/role/vault-gmsa-role \
    token_policies="gmsa-policy" \
    allowed_realms="LOCAL.LAB" \
    allowed_spns="HTTP/vault.local.lab"
echo "✓ vault-gmsa-role created"
echo ""

# Step 12: Verify configuration
echo "Step 12: Verifying configuration..."
echo ""
echo "Auth method config:"
vault read auth/${AUTH_PATH}/config
echo ""
echo "Default role:"
vault read auth/${AUTH_PATH}/role/default
echo ""
echo "vault-gmsa-role:"
vault read auth/${AUTH_PATH}/role/vault-gmsa-role
echo ""

# Step 13: Create gmsa-policy if it doesn't exist
echo "Step 13: Creating gmsa-policy (if not exists)..."
vault policy write gmsa-policy - <<EOF
# Allow reading secrets
path "kv/data/my-app/*" {
  capabilities = ["read", "list"]
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
echo "✓ gmsa-policy created"
echo ""

echo "=========================================="
echo "✅ DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
echo "📋 Summary:"
echo "  ✓ Plugin deployed: ${PLUGIN_PATH}"
echo "  ✓ Plugin SHA256: ${PLUGIN_SHA256}"
echo "  ✓ Auth method enabled: ${AUTH_PATH}"
echo "  ✓ Authorization header passthrough: ENABLED"
echo "  ✓ Default role created: default"
echo "  ✓ Legacy role created: vault-gmsa-role"
echo ""
echo "🧪 Testing Commands:"
echo ""
echo "1. Test with curl (HTTP Negotiate):"
echo "   curl --negotiate --user : -X POST ${VAULT_ADDR}/v1/auth/${AUTH_PATH}/login"
echo ""
echo "2. Test with PowerShell (UseDefaultCredentials):"
echo '   $r = Invoke-RestMethod -Uri "'${VAULT_ADDR}'/v1/auth/'${AUTH_PATH}'/login" -Method Post -UseDefaultCredentials'
echo '   Write-Host "Token: $($r.auth.client_token)"'
echo ""
echo "3. Test with old method (JSON body):"
echo '   $body = @{role="vault-gmsa-role"; spnego="<token>"} | ConvertTo-Json'
echo '   Invoke-RestMethod -Uri "'${VAULT_ADDR}'/v1/auth/'${AUTH_PATH}'/login" -Method Post -Body $body'
echo ""
echo "🚀 The plugin now supports both HTTP Negotiate and body-based authentication!"
echo ""
