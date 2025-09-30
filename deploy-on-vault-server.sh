#!/bin/bash
# Deploy Updated Plugin - Run this ON the Vault server

set -e

echo "=========================================="
echo "Deploy Updated Vault gMSA Plugin"
echo "=========================================="
echo ""

# Configuration
PLUGIN_NAME="vault-plugin-auth-gmsa"
CONTAINER_NAME="vault"
PLUGIN_PATH="/vault/plugins/${PLUGIN_NAME}"
AUTH_PATH="gmsa"
VAULT_TOKEN="${VAULT_TOKEN:-hvs.CAESIJ3OhFlnPCzJqRq7dDgBEWtMZRtzI3UGTXcDBV9RRWlmGh4KHGh2cy5GTzVYUTFGOXA2cHhmV1ZtZ3lBbnFYeWI}"

# Get container ID
CONTAINER_ID=$(sudo docker ps --filter "name=${CONTAINER_NAME}" --format '{{.ID}}')
echo "Container ID: $CONTAINER_ID"
echo ""

# Step 1: Copy plugin to container
echo "Step 1: Copying plugin to container..."
sudo docker cp /tmp/${PLUGIN_NAME} ${CONTAINER_ID}:${PLUGIN_PATH}
echo "✓ Plugin copied"
echo ""

# Step 2: Set permissions
echo "Step 2: Setting permissions..."
sudo docker exec ${CONTAINER_ID} chmod +x ${PLUGIN_PATH}
echo "✓ Permissions set"
echo ""

# Step 3: Calculate SHA256
echo "Step 3: Calculating SHA256..."
PLUGIN_SHA256=$(sudo docker exec ${CONTAINER_ID} sha256sum ${PLUGIN_PATH} | cut -d' ' -f1)
echo "SHA256: $PLUGIN_SHA256"
echo ""

# Step 4: Disable existing auth
echo "Step 4: Disabling existing auth method..."
export VAULT_SKIP_VERIFY=1
vault auth disable ${AUTH_PATH} 2>/dev/null || echo "(Not enabled, skipping)"
echo ""

# Step 5: Deregister old plugin
echo "Step 5: Deregistering old plugin..."
vault plugin deregister auth ${PLUGIN_NAME} 2>/dev/null || echo "(Not registered, skipping)"
echo ""

# Step 6: Register plugin
echo "Step 6: Registering plugin..."
vault plugin register \
    -sha256="${PLUGIN_SHA256}" \
    -command="${PLUGIN_NAME}" \
    auth ${PLUGIN_NAME}
echo "✓ Plugin registered"
echo ""

# Step 7: Enable auth with Authorization header
echo "Step 7: Enabling auth method..."
vault auth enable \
    -path=${AUTH_PATH} \
    -passthrough-request-headers=Authorization \
    -allowed-response-headers=www-authenticate \
    ${PLUGIN_NAME}
echo "✓ Auth enabled"
echo ""

# Step 8: Configure
echo "Step 8: Configuring..."
vault write auth/${AUTH_PATH}/config \
    keytab="BQIAAABVAAIACUxPQ0FMLkxBQgAESFRUUAAPdmF1bHQubG9jYWwubGFiAAAAAWjbrcYBABIAIP+YVCp3kvBhhHgkBHiiOLaKMxHHwo1hkIEa68AatEIDAAAAAQ==" \
    spn="HTTP/vault.local.lab" \
    realm="LOCAL.LAB" \
    kdcs="ADDC.local.lab:88"
echo "✓ Configured"
echo ""

# Step 9: Create default role
echo "Step 9: Creating default role..."
vault write auth/${AUTH_PATH}/role/default \
    token_policies="gmsa-policy" \
    allowed_realms="LOCAL.LAB" \
    allowed_spns="HTTP/vault.local.lab"
echo "✓ Default role created"
echo ""

# Step 10: Create vault-gmsa-role
echo "Step 10: Creating vault-gmsa-role..."
vault write auth/${AUTH_PATH}/role/vault-gmsa-role \
    token_policies="gmsa-policy" \
    allowed_realms="LOCAL.LAB" \
    allowed_spns="HTTP/vault.local.lab"
echo "✓ vault-gmsa-role created"
echo ""

# Step 11: Create policy
echo "Step 11: Creating gmsa-policy..."
vault policy write gmsa-policy - <<EOF
path "kv/data/my-app/*" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF
echo "✓ Policy created"
echo ""

echo "=========================================="
echo "✅ DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
vault read auth/${AUTH_PATH}/config
echo ""
