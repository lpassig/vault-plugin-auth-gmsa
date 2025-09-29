#!/bin/bash
# =============================================================================
# Vault Server Configuration Check Script (Linux)
# =============================================================================
# This script checks the current Vault server configuration and identifies issues
# =============================================================================

set -e

# Configuration
VAULT_ADDR=${VAULT_ADDR:-"https://vault.example.com:8200"}
VAULT_TOKEN=${VAULT_TOKEN:-""}
SPN=${SPN:-"HTTP/vault.local.lab"}
REALM=${REALM:-"LOCAL.LAB"}
ROLE_NAME=${ROLE_NAME:-"vault-gmsa-role"}
POLICY_NAME=${POLICY_NAME:-"vault-gmsa-policy"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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

log_fix() {
    echo -e "${MAGENTA}[FIX]${NC} $1"
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

# Check authentication methods
check_auth_methods() {
    log_info "=== Checking Authentication Methods ==="
    
    log_info "Available authentication methods:"
    vault auth list -address="$VAULT_ADDR" -format=json | jq -r '.data | to_entries[] | "   - \(.key): \(.value.type)"'
    
    # Check if gMSA is enabled
    if vault auth list -address="$VAULT_ADDR" | grep -q "gmsa/"; then
        log_success "gMSA authentication method is enabled"
        return 0
    else
        log_error "gMSA authentication method is NOT enabled"
        log_warning "This is required for gMSA authentication"
        return 1
    fi
}

# Check gMSA configuration
check_gmsa_config() {
    log_info "=== Checking gMSA Configuration ==="
    
    if vault read auth/gmsa/config -address="$VAULT_ADDR" &>/dev/null; then
        log_success "gMSA configuration found"
        
        # Get configuration details
        CONFIG_OUTPUT=$(vault read auth/gmsa/config -address="$VAULT_ADDR" -format=json)
        CONFIG_SPN=$(echo "$CONFIG_OUTPUT" | jq -r '.data.spn')
        CONFIG_REALM=$(echo "$CONFIG_OUTPUT" | jq -r '.data.realm')
        CONFIG_CB=$(echo "$CONFIG_OUTPUT" | jq -r '.data.allow_channel_binding')
        CONFIG_SKEW=$(echo "$CONFIG_OUTPUT" | jq -r '.data.clock_skew_sec')
        
        log_info "   SPN: $CONFIG_SPN"
        log_info "   Realm: $CONFIG_REALM"
        log_info "   Allow Channel Binding: $CONFIG_CB"
        log_info "   Clock Skew: $CONFIG_SKEW seconds"
        
        ISSUES=()
        
        # Check SPN
        if [ "$CONFIG_SPN" != "$SPN" ]; then
            ISSUES+=("SPN mismatch: Expected '$SPN', Got '$CONFIG_SPN'")
        fi
        
        # Check Realm
        if [ "$CONFIG_REALM" != "$REALM" ]; then
            ISSUES+=("Realm mismatch: Expected '$REALM', Got '$CONFIG_REALM'")
        fi
        
        # Check if keytab is configured
        KEYTAB_LENGTH=$(echo "$CONFIG_OUTPUT" | jq -r '.data.keytab | length')
        if [ "$KEYTAB_LENGTH" -eq 0 ]; then
            ISSUES+=("Keytab is not configured or empty")
        fi
        
        if [ ${#ISSUES[@]} -gt 0 ]; then
            log_warning "Configuration issues found:"
            for issue in "${ISSUES[@]}"; do
                log_warning "   - $issue"
            done
            return 1
        else
            log_success "gMSA configuration is correct"
            return 0
        fi
    else
        log_error "Failed to read gMSA configuration"
        log_warning "gMSA authentication method may not be properly configured"
        return 1
    fi
}

# Check gMSA role
check_gmsa_role() {
    log_info "=== Checking gMSA Role ==="
    
    if vault read auth/gmsa/role/"$ROLE_NAME" -address="$VAULT_ADDR" &>/dev/null; then
        log_success "gMSA role '$ROLE_NAME' found"
        
        # Get role details
        ROLE_OUTPUT=$(vault read auth/gmsa/role/"$ROLE_NAME" -address="$VAULT_ADDR" -format=json)
        ROLE_REALMS=$(echo "$ROLE_OUTPUT" | jq -r '.data.allowed_realms | join(", ")')
        ROLE_SPNS=$(echo "$ROLE_OUTPUT" | jq -r '.data.allowed_spns | join(", ")')
        ROLE_POLICIES=$(echo "$ROLE_OUTPUT" | jq -r '.data.token_policies | join(", ")')
        ROLE_TYPE=$(echo "$ROLE_OUTPUT" | jq -r '.data.token_type')
        ROLE_TTL=$(echo "$ROLE_OUTPUT" | jq -r '.data.max_ttl')
        
        log_info "   Allowed Realms: $ROLE_REALMS"
        log_info "   Allowed SPNs: $ROLE_SPNS"
        log_info "   Token Policies: $ROLE_POLICIES"
        log_info "   Token Type: $ROLE_TYPE"
        log_info "   Max TTL: $ROLE_TTL seconds"
        
        ISSUES=()
        
        # Check allowed realms
        if ! echo "$ROLE_REALMS" | grep -q "$REALM"; then
            ISSUES+=("Allowed realms does not include '$REALM'")
        fi
        
        # Check allowed SPNs
        if ! echo "$ROLE_SPNS" | grep -q "$SPN"; then
            ISSUES+=("Allowed SPNs does not include '$SPN'")
        fi
        
        # Check token policies
        if ! echo "$ROLE_POLICIES" | grep -q "$POLICY_NAME"; then
            ISSUES+=("Token policies does not include '$POLICY_NAME'")
        fi
        
        if [ ${#ISSUES[@]} -gt 0 ]; then
            log_warning "Role configuration issues found:"
            for issue in "${ISSUES[@]}"; do
                log_warning "   - $issue"
            done
            return 1
        else
            log_success "gMSA role configuration is correct"
            return 0
        fi
    else
        log_error "Failed to read gMSA role '$ROLE_NAME'"
        log_warning "gMSA role may not exist or be accessible"
        return 1
    fi
}

# Check gMSA policy
check_gmsa_policy() {
    log_info "=== Checking gMSA Policy ==="
    
    if vault policy read "$POLICY_NAME" -address="$VAULT_ADDR" &>/dev/null; then
        log_success "gMSA policy '$POLICY_NAME' found"
        
        # Get policy content
        POLICY_CONTENT=$(vault policy read "$POLICY_NAME" -address="$VAULT_ADDR")
        log_info "   Policy content:"
        echo "$POLICY_CONTENT" | sed 's/^/     /'
        
        # Check if policy has required permissions
        if echo "$POLICY_CONTENT" | grep -q "kv/data/my-app/\*"; then
            log_success "Policy has required KV permissions"
            return 0
        else
            log_warning "Policy may not have required KV permissions"
            return 1
        fi
    else
        log_error "Failed to read gMSA policy '$POLICY_NAME'"
        log_warning "gMSA policy may not exist or be accessible"
        return 1
    fi
}

# Check KV secrets engine
check_kv_secrets() {
    log_info "=== Checking KV Secrets Engine ==="
    
    # Check if KV secrets engine is enabled
    if vault secrets list -address="$VAULT_ADDR" | grep -q "kv/"; then
        log_success "KV secrets engine is enabled"
        
        # Get details about the KV mount
        MOUNT_INFO=$(vault secrets list -address="$VAULT_ADDR" -format=json | jq -r '.data."kv/"')
        MOUNT_TYPE=$(echo "$MOUNT_INFO" | jq -r '.type')
        MOUNT_DESC=$(echo "$MOUNT_INFO" | jq -r '.description')
        
        log_info "   Type: $MOUNT_TYPE"
        log_info "   Description: $MOUNT_DESC"
        
        if [ "$MOUNT_TYPE" = "kv-v2" ]; then
            log_success "KV v2 secrets engine is properly configured"
            return 0
        else
            log_warning "KV secrets engine is not v2"
            return 1
        fi
    else
        log_error "KV secrets engine is NOT enabled"
        log_warning "This is required for storing test secrets"
        return 1
    fi
}

# Check test secrets
check_test_secrets() {
    log_info "=== Checking Test Secrets ==="
    
    # Check database secret
    if vault kv get kv/my-app/database -address="$VAULT_ADDR" &>/dev/null; then
        log_success "Database secret found"
        
        # Get secret keys
        DB_KEYS=$(vault kv get kv/my-app/database -address="$VAULT_ADDR" -format=json | jq -r '.data.data | keys | join(", ")')
        log_info "   Keys: $DB_KEYS"
    else
        log_error "Database secret not found"
        return 1
    fi
    
    # Check API secret
    if vault kv get kv/my-app/api -address="$VAULT_ADDR" &>/dev/null; then
        log_success "API secret found"
        
        # Get secret keys
        API_KEYS=$(vault kv get kv/my-app/api -address="$VAULT_ADDR" -format=json | jq -r '.data.data | keys | join(", ")')
        log_info "   Keys: $API_KEYS"
    else
        log_error "API secret not found"
        return 1
    fi
    
    return 0
}

# Test SPNEGO negotiation
test_spnego_negotiation() {
    log_info "=== Testing SPNEGO Negotiation ==="
    
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
        
        # Check for WWW-Authenticate header
        WWW_AUTH=$(curl -s -w "%{http_code}" -o /dev/null \
            -X POST \
            -H "Content-Type: application/json" \
            -d '{"role":"'$ROLE_NAME'"}' \
            -D - \
            "$VAULT_ADDR/v1/auth/gmsa/login" 2>/dev/null | grep -i "www-authenticate" || echo "")
        
        if [ -n "$WWW_AUTH" ]; then
            log_success "WWW-Authenticate header found: $WWW_AUTH"
            if echo "$WWW_AUTH" | grep -qi "negotiate"; then
                log_success "SPNEGO negotiation is properly configured!"
                return 0
            else
                log_error "WWW-Authenticate header does not contain 'Negotiate'"
                return 1
            fi
        else
            log_error "No WWW-Authenticate header found"
            log_warning "This indicates the gMSA auth method is not properly configured for SPNEGO"
            return 1
        fi
    elif [ "$RESPONSE" = "400" ]; then
        log_warning "Got 400 Bad Request - this may indicate configuration issues"
        log_info "Check that the gMSA auth method is properly configured"
        return 1
    else
        log_warning "Unexpected response code: $RESPONSE"
        log_info "Expected 401 Unauthorized for SPNEGO negotiation"
        return 1
    fi
}

# Show fix commands
show_fix_commands() {
    log_fix "=== Fix Commands ==="
    log_fix "To fix the configuration issues, run:"
    log_fix ""
    log_fix "./fix-vault-server-config.sh"
    log_fix ""
    log_fix "Or run the individual commands manually:"
    log_fix ""
    log_fix "# Enable gMSA auth method"
    log_fix "vault auth enable gmsa"
    log_fix ""
    log_fix "# Configure gMSA authentication"
    log_fix "vault write auth/gmsa/config \\"
    log_fix "    realm='$REALM' \\"
    log_fix "    kdcs='ADDC.local.lab' \\"
    log_fix "    keytab='<BASE64_KEYTAB>' \\"
    log_fix "    spn='$SPN' \\"
    log_fix "    allow_channel_binding=false"
    log_fix ""
    log_fix "# Create gMSA role"
    log_fix "vault write auth/gmsa/role/$ROLE_NAME \\"
    log_fix "    allowed_realms='$REALM' \\"
    log_fix "    allowed_spns='$SPN' \\"
    log_fix "    token_policies='$POLICY_NAME' \\"
    log_fix "    token_ttl=1h"
    log_fix ""
    log_fix "# Create policy"
    log_fix "vault policy write $POLICY_NAME - <<EOF"
    log_fix "path \"kv/data/my-app/*\" {"
    log_fix "  capabilities = [\"read\"]"
    log_fix "}"
    log_fix "EOF"
    log_fix ""
    log_fix "# Enable KV secrets engine"
    log_fix "vault secrets enable -path=kv kv-v2"
    log_fix ""
    log_fix "# Create test secrets"
    log_fix "vault kv put kv/my-app/database host=db-server.local.lab username=app-user password=secure-password-123"
    log_fix "vault kv put kv/my-app/api api_key=abc123def456ghi789 endpoint=https://api.local.lab"
}

# Main execution
main() {
    echo "=== Vault Server Configuration Check ==="
    log_info "Vault Address: $VAULT_ADDR"
    log_info "SPN: $SPN"
    log_info "Realm: $REALM"
    log_info "Role Name: $ROLE_NAME"
    log_info "Policy Name: $POLICY_NAME"
    echo ""
    
    # Pre-flight checks
    check_vault_cli
    check_vault_connectivity
    
    if ! check_authentication; then
        log_warning "Proceeding without authentication - some checks may fail"
    fi
    
    # Execute configuration checks
    ALL_CHECKS_PASSED=true
    
    check_auth_methods || ALL_CHECKS_PASSED=false
    check_gmsa_config || ALL_CHECKS_PASSED=false
    check_gmsa_role || ALL_CHECKS_PASSED=false
    check_gmsa_policy || ALL_CHECKS_PASSED=false
    check_kv_secrets || ALL_CHECKS_PASSED=false
    check_test_secrets || ALL_CHECKS_PASSED=false
    test_spnego_negotiation || ALL_CHECKS_PASSED=false
    
    # Show results
    echo ""
    log_info "=== Configuration Check Summary ==="
    if [ "$ALL_CHECKS_PASSED" = true ]; then
        log_success "All configuration checks passed!"
        log_success "The Vault server is properly configured for gMSA authentication."
    else
        log_error "Some configuration checks failed."
        log_error "The Vault server needs configuration fixes."
        show_fix_commands
    fi
    
    echo ""
    log_info "Next steps:"
    if [ "$ALL_CHECKS_PASSED" = true ]; then
        log_info "1. Test the PowerShell client: .\vault-client-app.ps1"
        log_info "2. Verify gMSA has valid Kerberos tickets: klist"
        log_info "3. Check Vault logs for authentication events"
    else
        log_info "1. Fix the configuration issues using the commands above"
        log_info "2. Re-run this check script to verify fixes"
        log_info "3. Test the PowerShell client after fixes"
    fi
}

# Run main function
main "$@"
