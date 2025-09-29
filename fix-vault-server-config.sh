#!/bin/bash
# =============================================================================
# Vault Server gMSA Configuration Script (Linux)
# =============================================================================
# This script configures the Vault server for gMSA authentication
# Run this script on the Linux Vault server
# =============================================================================

set -e

# Configuration
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}
VAULT_TOKEN=${VAULT_TOKEN:-""}
SPN=${SPN:-"HTTP/vault.local.lab"}
REALM=${REALM:-"LOCAL.LAB"}
ROLE_NAME=${ROLE_NAME:-"vault-gmsa-role"}
POLICY_NAME=${POLICY_NAME:-"vault-gmsa-policy"}
KEYTAB_PATH=${KEYTAB_PATH:-"/home/lennart/vault-keytab.keytab"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_command() {
    echo -e "${CYAN}[COMMAND]${NC} $1"
}

# Check if vault CLI is available
check_vault_cli() {
    if ! command -v vault &> /dev/null; then
        log_error "Vault CLI is not installed or not in PATH"
        log_info "Install Vault CLI: https://www.vaultproject.io/downloads"
        exit 1
    fi
    log_success "Vault CLI is available"
}

# Check Vault connectivity
check_vault_connectivity() {
    log_info "Testing Vault server connectivity..."
    
    if vault status -address="$VAULT_ADDR" &> /dev/null; then
        log_success "Vault server is reachable at $VAULT_ADDR"
        
        # Get Vault version
        VAULT_VERSION=$(vault version -address="$VAULT_ADDR" | head -n1)
        log_info "Vault version: $VAULT_VERSION"
    else
        log_error "Cannot reach Vault server at $VAULT_ADDR"
        log_info "Make sure Vault server is running and accessible"
        exit 1
    fi
}

# Check authentication
check_authentication() {
    if [ -z "$VAULT_TOKEN" ]; then
        log_warning "No Vault token provided"
        log_info "Set VAULT_TOKEN environment variable or authenticate manually"
        log_info "Example: export VAULT_TOKEN=\$(vault auth -method=userpass username=admin password=password -format=json | jq -r '.auth.client_token')"
        return 1
    else
        log_success "Using provided Vault token"
        export VAULT_TOKEN
        return 0
    fi
}

# Check keytab file
check_keytab() {
    if [ ! -f "$KEYTAB_PATH" ]; then
        log_error "Keytab file not found: $KEYTAB_PATH"
        log_info "Please provide the keytab file path"
        log_info "Example: export KEYTAB_PATH=/path/to/vault-keytab.keytab"
        exit 1
    fi
    
    log_success "Keytab file found: $KEYTAB_PATH"
    
    # Get file size
    KEYTAB_SIZE=$(stat -c%s "$KEYTAB_PATH")
    log_info "Keytab file size: $KEYTAB_SIZE bytes"
    
    # Convert to base64
    KEYTAB_BASE64=$(base64 -w 0 "$KEYTAB_PATH")
    log_success "Keytab converted to base64 (${#KEYTAB_BASE64} characters)"
}

# Enable gMSA authentication method
enable_gmsa_auth() {
    log_info "=== Step 1: Enabling gMSA Authentication Method ==="
    
    log_command "vault auth enable -path=gmsa gmsa"
    if vault auth enable -path=gmsa gmsa -address="$VAULT_ADDR" 2>/dev/null; then
        log_success "gMSA authentication method enabled"
    else
        log_warning "gMSA authentication method may already be enabled"
    fi
}

# Configure gMSA authentication
configure_gmsa_auth() {
    log_info "=== Step 2: Configuring gMSA Authentication ==="
    
    log_command "vault write auth/gmsa/config ..."
    
    vault write auth/gmsa/config \
        -address="$VAULT_ADDR" \
        realm="$REALM" \
        kdcs="ADDC.local.lab" \
        keytab="$KEYTAB_BASE64" \
        spn="$SPN" \
        allow_channel_binding=false \
        clock_skew_sec=300 \
        realm_case_sensitive=false \
        spn_case_sensitive=false
    
    log_success "gMSA authentication configured"
    log_info "  SPN: $SPN"
    log_info "  Realm: $REALM"
    log_info "  Channel Binding: false"
    log_info "  Clock Skew: 300 seconds"
}

# Create gMSA policy
create_gmsa_policy() {
    log_info "=== Step 3: Creating gMSA Policy ==="
    
    log_command "vault policy write $POLICY_NAME ..."
    
    vault policy write "$POLICY_NAME" \
        -address="$VAULT_ADDR" \
        - <<EOF
path "kv/data/my-app/*" {
  capabilities = ["read"]
}

path "kv/data/vault-gmsa/*" {
  capabilities = ["read"]
}

path "secret/data/my-app/*" {
  capabilities = ["read"]
}
EOF
    
    log_success "gMSA policy '$POLICY_NAME' created"
}

# Create gMSA role
create_gmsa_role() {
    log_info "=== Step 4: Creating gMSA Role ==="
    
    log_command "vault write auth/gmsa/role/$ROLE_NAME ..."
    
    vault write auth/gmsa/role/"$ROLE_NAME" \
        -address="$VAULT_ADDR" \
        allowed_realms="$REALM" \
        allowed_spns="$SPN" \
        token_policies="$POLICY_NAME" \
        token_type="default" \
        period=0 \
        max_ttl=3600
    
    log_success "gMSA role '$ROLE_NAME' created"
    log_info "  Allowed Realms: $REALM"
    log_info "  Allowed SPNs: $SPN"
    log_info "  Token Policies: $POLICY_NAME"
    log_info "  Max TTL: 3600 seconds"
}

# Enable KV secrets engine
enable_kv_secrets() {
    log_info "=== Step 5: Enabling KV Secrets Engine ==="
    
    log_command "vault secrets enable -path=kv kv-v2"
    
    if vault secrets enable -path=kv kv-v2 -address="$VAULT_ADDR" 2>/dev/null; then
        log_success "KV secrets engine enabled at path 'kv'"
    else
        log_warning "KV secrets engine may already be enabled"
    fi
}

# Create test secrets
create_test_secrets() {
    log_info "=== Step 6: Creating Test Secrets ==="
    
    # Create database secret
    log_command "vault kv put kv/my-app/database ..."
    vault kv put kv/my-app/database \
        -address="$VAULT_ADDR" \
        host="db-server.local.lab" \
        username="app-user" \
        password="secure-password-123" \
        port=1433
    
    log_success "Database secret created"
    
    # Create API secret
    log_command "vault kv put kv/my-app/api ..."
    vault kv put kv/my-app/api \
        -address="$VAULT_ADDR" \
        api_key="abc123def456ghi789" \
        endpoint="https://api.local.lab" \
        secret="xyz789uvw012rst345"
    
    log_success "API secret created"
}

# Test gMSA configuration
test_gmsa_config() {
    log_info "=== Step 7: Testing gMSA Configuration ==="
    
    # Test 1: Check if gMSA auth method is enabled
    log_info "Testing gMSA auth method..."
    if vault auth list -address="$VAULT_ADDR" | grep -q "gmsa/"; then
        log_success "gMSA auth method is enabled"
    else
        log_error "gMSA auth method is NOT enabled"
        return 1
    fi
    
    # Test 2: Check gMSA configuration
    log_info "Testing gMSA configuration..."
    if vault read auth/gmsa/config -address="$VAULT_ADDR" &>/dev/null; then
        log_success "gMSA configuration found"
        
        # Show configuration details
        CONFIG_OUTPUT=$(vault read auth/gmsa/config -address="$VAULT_ADDR" -format=json)
        CONFIG_SPN=$(echo "$CONFIG_OUTPUT" | jq -r '.data.spn')
        CONFIG_REALM=$(echo "$CONFIG_OUTPUT" | jq -r '.data.realm')
        
        log_info "  SPN: $CONFIG_SPN"
        log_info "  Realm: $CONFIG_REALM"
        
        if [ "$CONFIG_SPN" != "$SPN" ]; then
            log_warning "SPN mismatch: Expected '$SPN', Got '$CONFIG_SPN'"
        fi
        if [ "$CONFIG_REALM" != "$REALM" ]; then
            log_warning "Realm mismatch: Expected '$REALM', Got '$CONFIG_REALM'"
        fi
    else
        log_error "gMSA configuration not found"
        return 1
    fi
    
    # Test 3: Check gMSA role
    log_info "Testing gMSA role..."
    if vault read auth/gmsa/role/"$ROLE_NAME" -address="$VAULT_ADDR" &>/dev/null; then
        log_success "gMSA role '$ROLE_NAME' found"
        
        # Show role details
        ROLE_OUTPUT=$(vault read auth/gmsa/role/"$ROLE_NAME" -address="$VAULT_ADDR" -format=json)
        ROLE_POLICIES=$(echo "$ROLE_OUTPUT" | jq -r '.data.token_policies | join(", ")')
        log_info "  Token Policies: $ROLE_POLICIES"
    else
        log_error "gMSA role '$ROLE_NAME' not found"
        return 1
    fi
    
    # Test 4: Test SPNEGO negotiation (simplified)
    log_info "Testing SPNEGO negotiation..."
    log_info "Making test request to login endpoint..."
    
    # Create a test request to trigger SPNEGO negotiation
    RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"role":"'$ROLE_NAME'"}' \
        "$VAULT_ADDR/v1/auth/gmsa/login" 2>/dev/null || echo "000")
    
    if [ "$RESPONSE" = "401" ]; then
        log_success "Got expected 401 Unauthorized response"
        log_info "This indicates SPNEGO negotiation is properly configured"
    elif [ "$RESPONSE" = "400" ]; then
        log_warning "Got 400 Bad Request - this may indicate configuration issues"
        log_info "Check that the gMSA auth method is properly configured"
    else
        log_warning "Unexpected response code: $RESPONSE"
        log_info "Expected 401 Unauthorized for SPNEGO negotiation"
    fi
    
    return 0
}

# Show configuration summary
show_summary() {
    log_info "=== Configuration Summary ==="
    log_info "Vault Address: $VAULT_ADDR"
    log_info "SPN: $SPN"
    log_info "Realm: $REALM"
    log_info "Role Name: $ROLE_NAME"
    log_info "Policy Name: $POLICY_NAME"
    log_info "Keytab Path: $KEYTAB_PATH"
    log_info ""
    
    log_info "=== Manual Commands (if needed) ==="
    log_command "vault auth enable gmsa"
    log_command "vault write auth/gmsa/config realm='$REALM' kdcs='ADDC.local.lab' keytab='<BASE64>' spn='$SPN' allow_channel_binding=false"
    log_command "vault write auth/gmsa/role/$ROLE_NAME allowed_realms='$REALM' allowed_spns='$SPN' token_policies='$POLICY_NAME' token_ttl=1h"
    log_command "vault policy write $POLICY_NAME - <<EOF"
    log_command "path \"kv/data/my-app/*\" { capabilities = [\"read\"] }"
    log_command "EOF"
    log_command "vault secrets enable -path=kv kv-v2"
    log_command "vault kv put kv/my-app/database host=db-server.local.lab username=app-user password=secure-password-123"
    log_command "vault kv put kv/my-app/api api_key=abc123def456ghi789 endpoint=https://api.local.lab"
}

# Main execution
main() {
    echo "=== Vault Server gMSA Configuration Script ==="
    echo "This script will configure Vault server for proper gMSA authentication"
    echo ""
    
    # Pre-flight checks
    check_vault_cli
    check_vault_connectivity
    
    if ! check_authentication; then
        log_warning "Proceeding without authentication - some operations may fail"
    fi
    
    check_keytab
    
    # Execute configuration steps
    enable_gmsa_auth
    configure_gmsa_auth
    create_gmsa_policy
    create_gmsa_role
    enable_kv_secrets
    create_test_secrets
    
    # Test the configuration
    if test_gmsa_config; then
        log_success "All tests passed!"
    else
        log_warning "Some tests failed - check the configuration"
    fi
    
    # Show summary
    show_summary
    
    # Final result
    echo ""
    log_info "=== Final Result ==="
    log_success "Vault server gMSA configuration completed!"
    log_info "The PowerShell client should now be able to authenticate properly."
    echo ""
    log_info "Next steps:"
    log_info "1. Test the PowerShell client: .\vault-client-app.ps1"
    log_info "2. Check Vault logs for any authentication errors"
    log_info "3. Verify gMSA has valid Kerberos tickets: klist"
}

# Run main function
main "$@"
