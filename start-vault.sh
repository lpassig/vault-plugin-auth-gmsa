#!/bin/bash

# Start Vault and keep it running for testing

echo "Starting Vault for testing..."

# Stop any existing Vault processes
pkill -f vault || true

# Build the plugin
echo "Building plugin..."
go build -trimpath -ldflags="-s -w -X main.version=916dc6c-dirty" -o bin/vault-plugin-auth-gmsa ./cmd/vault-plugin-auth-gmsa

# Setup plugin directory
mkdir -p /private/tmp/vault-plugins
cp bin/vault-plugin-auth-gmsa /private/tmp/vault-plugins/

# Start Vault
echo "Starting Vault..."
vault server -dev -dev-root-token-id="test-token" -dev-plugin-dir="/private/tmp/vault-plugins" &
VAULT_PID=$!

# Wait for Vault to start
echo "Waiting for Vault to start..."
sleep 5

# Set environment variables
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=test-token

# Initialize and unseal
echo "Initializing Vault..."
vault operator init -key-shares=1 -key-threshold=1 -format=json > /tmp/vault-keys.json
UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' /tmp/vault-keys.json)
vault operator unseal $UNSEAL_KEY

# Register and enable plugin
echo "Registering plugin..."
vault write sys/plugins/catalog/vault-plugin-auth-gmsa \
    sha256=$(shasum -a 256 /private/tmp/vault-plugins/vault-plugin-auth-gmsa | cut -d' ' -f1) \
    command="vault-plugin-auth-gmsa"

echo "Enabling plugin..."
vault auth enable -path=gmsa vault-plugin-auth-gmsa

# Create test keytab
echo "Creating test keytab..."
dd if=/dev/urandom bs=1024 count=1 | base64 > /tmp/test-keytab.b64

# Configure plugin
echo "Configuring plugin..."
vault write auth/gmsa/config \
    realm=EXAMPLE.COM \
    kdcs="dc1.example.com,dc2.example.com" \
    spn="HTTP/vault.example.com" \
    keytab=@/tmp/test-keytab.b64

echo "Vault is ready for testing!"
echo "PID: $VAULT_PID"
echo "VAULT_ADDR: $VAULT_ADDR"
echo "VAULT_TOKEN: $VAULT_TOKEN"

# Keep running
wait $VAULT_PID
