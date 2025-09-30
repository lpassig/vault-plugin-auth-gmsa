#!/bin/bash
# Deploy Updated Vault gMSA Plugin with HTTP Negotiate Support

set -e

VAULT_SERVER="107.23.32.117"
VAULT_USER="lennart"
PLUGIN_NAME="vault-plugin-auth-gmsa"
PLUGIN_BINARY="vault-plugin-auth-gmsa-linux"
VAULT_ADDR="https://127.0.0.1:8200"

echo "🚀 Deploying Updated Vault gMSA Plugin with HTTP Negotiate Support"
echo "=================================================================="
echo ""

# Step 1: Upload plugin to server
echo "📤 Step 1: Uploading plugin binary to Vault server..."
scp ${PLUGIN_BINARY} ${VAULT_USER}@${VAULT_SERVER}:/tmp/${PLUGIN_NAME}
echo "✅ Plugin uploaded"
echo ""

# Step 2: Get Docker container ID and deploy plugin
echo "🐳 Step 2: Deploying plugin to Vault Docker container..."
ssh ${VAULT_USER}@${VAULT_SERVER} << 'ENDSSH'
    # Get Docker container ID
    CONTAINER_ID=$(sudo docker ps --filter ancestor=hashicorp/vault --format '{{.ID}}')
    echo "   Container ID: $CONTAINER_ID"
    
    # Copy plugin to container
    sudo docker cp /tmp/vault-plugin-auth-gmsa ${CONTAINER_ID}:/vault/plugins/vault-plugin-auth-gmsa
    
    # Set permissions
    sudo docker exec ${CONTAINER_ID} chmod +x /vault/plugins/vault-plugin-auth-gmsa
    
    # Get SHA256
    PLUGIN_SHA=$(sudo docker exec ${CONTAINER_ID} sha256sum /vault/plugins/vault-plugin-auth-gmsa | cut -d' ' -f1)
    echo "   Plugin SHA256: $PLUGIN_SHA"
    
    # Export for Vault commands
    export VAULT_ADDR='https://127.0.0.1:8200'
    export VAULT_SKIP_VERIFY=1
    
    # Disable old auth method
    echo ""
    echo "   🔄 Disabling old auth method..."
    vault auth disable gmsa || true
    
    # Deregister old plugin
    echo "   🔄 Deregistering old plugin..."
    vault plugin deregister auth vault-plugin-auth-gmsa || true
    
    # Register new plugin
    echo "   ✅ Registering new plugin with HTTP Negotiate support..."
    vault plugin register \
        -sha256="${PLUGIN_SHA}" \
        -command="vault-plugin-auth-gmsa" \
        auth vault-plugin-auth-gmsa
    
    # Enable auth method with header passthrough
    echo "   ✅ Enabling auth method with Authorization header passthrough..."
    vault auth enable \
        -path=gmsa \
        -passthrough-request-headers="Authorization" \
        -allowed-response-headers="WWW-Authenticate" \
        vault-plugin-auth-gmsa
    
    # Reconfigure auth method
    echo "   ✅ Configuring auth method..."
    KEYTAB_B64=$(cat /tmp/vault-gmsa.keytab.b64 2>/dev/null || cat /tmp/vault.keytab.b64 2>/dev/null || echo "")
    
    if [ -n "$KEYTAB_B64" ]; then
        vault write auth/gmsa/config \
            realm="LOCAL.LAB" \
            kdcs="ADDC.local.lab:88" \
            spn="HTTP/vault.local.lab" \
            keytab="$KEYTAB_B64" \
            clock_skew_sec=300
    else
        echo "   ⚠️  No keytab found - you'll need to configure it manually"
    fi
    
    # Create default role and policy
    echo "   ✅ Creating default role and policy..."
    
    # Create policy
    vault policy write vault-gmsa-policy - <<EOF
# Read KV secrets
path "kv/data/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/*" {
  capabilities = ["read", "list"]
}
EOF
    
    # Create role
    vault write auth/gmsa/role/vault-gmsa-role \
        policies="vault-gmsa-policy" \
        spns="HTTP/vault.local.lab" \
        max_ttl="1h" \
        ttl="1h"
    
    # Also create a default role for HTTP Negotiate (no role name in request)
    vault write auth/gmsa/role/default \
        policies="vault-gmsa-policy" \
        spns="HTTP/vault.local.lab" \
        max_ttl="1h" \
        ttl="1h"
    
    echo ""
    echo "✅ Plugin deployment complete!"
    echo ""
    echo "📋 Verification:"
    vault auth list | grep gmsa
    vault read auth/gmsa/config
    vault read auth/gmsa/role/vault-gmsa-role
    vault read auth/gmsa/role/default
ENDSSH

echo ""
echo "🎉 Deployment Complete!"
echo ""
echo "The updated plugin now supports:"
echo "✅ HTTP Negotiate protocol (Authorization header)"
echo "✅ Legacy method (SPNEGO in request body)"
echo "✅ Automatic SPNEGO token generation via UseDefaultCredentials"
echo ""
echo "Your Windows client should now authenticate successfully!"
echo ""
echo "Next steps:"
echo "1. Re-run the Windows client: Start-ScheduledTask -TaskName 'VaultClientApp'"
echo "2. Check logs: Get-Content C:\vault-client\config\vault-client.log -Tail 50"
echo "3. Look for: [SUCCESS] SUCCESS: Vault authentication successful"
