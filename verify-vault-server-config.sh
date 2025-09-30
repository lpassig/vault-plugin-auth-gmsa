#!/bin/bash
# =============================================================================
# Vault Server Configuration Verification for gMSA Authentication
# =============================================================================
# This script verifies the Vault server is correctly configured for gMSA auth
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
VAULT_ADDR="${VAULT_ADDR:-https://vault.local.lab:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
AUTH_PATH="gmsa"
ROLE_NAME="vault-gmsa-role"
EXPECTED_SPN="HTTP/vault.local.lab"
EXPECTED_REALM="LOCAL.LAB"

issues_found=0
checks_passed=0

# Helper functions
print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((checks_passed++))
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((issues_found++))
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# =============================================================================
# Check 1: Vault CLI Available
# =============================================================================
print_header "Vault Server Configuration Verification"

print_info "Checking Vault CLI..."
if command -v vault &> /dev/null; then
    vault_version=$(vault version | head -1)
    print_success "Vault CLI available: $vault_version"
else
    print_error "Vault CLI not found"
    echo ""
    echo -e "${YELLOW}SOLUTION: Install Vault CLI:${NC}"
    echo "  wget https://releases.hashicorp.com/vault/1.15.0/vault_1.15.0_linux_amd64.zip"
    echo "  unzip vault_1.15.0_linux_amd64.zip"
    echo "  sudo mv vault /usr/local/bin/"
    echo ""
    exit 1
fi

# =============================================================================
# Check 2: Vault Server Connectivity
# =============================================================================
print_info "Checking Vault server connectivity: $VAULT_ADDR..."

if vault status &> /dev/null || [ $? -eq 2 ]; then
    print_success "Vault server is reachable"
else
    print_error "Cannot connect to Vault server: $VAULT_ADDR"
    echo ""
    echo -e "${YELLOW}SOLUTION: Check Vault server status and network connectivity${NC}"
    echo "  export VAULT_ADDR='https://vault.local.lab:8200'"
    echo "  vault status"
    echo ""
    exit 1
fi

# =============================================================================
# Check 3: Vault Authentication
# =============================================================================
print_info "Checking Vault authentication..."

if [ -z "$VAULT_TOKEN" ]; then
    print_warning "VAULT_TOKEN not set, attempting to use existing token"
fi

if vault token lookup &> /dev/null; then
    token_info=$(vault token lookup -format=json 2>/dev/null)
    policies=$(echo "$token_info" | jq -r '.data.policies[]' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    print_success "Authenticated to Vault (policies: $policies)"
else
    print_error "Not authenticated to Vault"
    echo ""
    echo -e "${YELLOW}SOLUTION: Authenticate to Vault:${NC}"
    echo "  export VAULT_TOKEN='<your-root-token>'"
    echo "  # Or: vault login"
    echo ""
    exit 1
fi

# =============================================================================
# Check 4: gMSA Auth Method Enabled
# =============================================================================
print_info "Checking if gMSA auth method is enabled..."

auth_methods=$(vault auth list -format=json 2>/dev/null)
if echo "$auth_methods" | jq -e ".\"${AUTH_PATH}/\"" &> /dev/null; then
    auth_type=$(echo "$auth_methods" | jq -r ".\"${AUTH_PATH}/\".type")
    print_success "gMSA auth method enabled at path: ${AUTH_PATH}/ (type: $auth_type)"
else
    print_error "gMSA auth method NOT enabled at path: ${AUTH_PATH}/"
    echo ""
    echo -e "${YELLOW}SOLUTION: Enable gMSA auth method:${NC}"
    echo "  vault auth enable -path=${AUTH_PATH} vault-plugin-auth-gmsa"
    echo ""
fi

# =============================================================================
# Check 5: gMSA Auth Configuration
# =============================================================================
print_info "Checking gMSA auth configuration..."

if config=$(vault read -format=json "auth/${AUTH_PATH}/config" 2>/dev/null); then
    print_success "gMSA auth configuration exists"
    
    # Check SPN
    spn=$(echo "$config" | jq -r '.data.spn // empty')
    if [ "$spn" = "$EXPECTED_SPN" ]; then
        print_success "SPN configured correctly: $spn"
    elif [ -z "$spn" ]; then
        print_error "SPN not configured"
    else
        print_warning "SPN configured but different: $spn (expected: $EXPECTED_SPN)"
    fi
    
    # Check Realm
    realm=$(echo "$config" | jq -r '.data.realm // empty')
    if [ "$realm" = "$EXPECTED_REALM" ]; then
        print_success "Realm configured correctly: $realm"
    elif [ -z "$realm" ]; then
        print_error "Realm not configured"
    else
        print_warning "Realm configured but different: $realm (expected: $EXPECTED_REALM)"
    fi
    
    # Check Keytab (we can't see the actual keytab, just verify it's set)
    keytab=$(echo "$config" | jq -r '.data.keytab_b64 // empty')
    if [ -n "$keytab" ] || echo "$config" | jq -e '.data' | grep -q "keytab"; then
        print_success "Keytab is configured (hidden for security)"
    else
        print_error "Keytab not configured"
        echo ""
        echo -e "${YELLOW}SOLUTION: Configure keytab:${NC}"
        echo "  vault write auth/${AUTH_PATH}/config \\"
        echo "    realm=$EXPECTED_REALM \\"
        echo "    spn=$EXPECTED_SPN \\"
        echo "    keytab_b64=\$(base64 -w 0 /path/to/vault.keytab)"
        echo ""
    fi
    
    # Check clock skew
    clock_skew=$(echo "$config" | jq -r '.data.clock_skew_sec // 300')
    print_info "Clock skew tolerance: ${clock_skew}s"
    
else
    print_error "gMSA auth method not configured"
    echo ""
    echo -e "${YELLOW}SOLUTION: Configure gMSA auth method:${NC}"
    echo "  vault write auth/${AUTH_PATH}/config \\"
    echo "    realm=$EXPECTED_REALM \\"
    echo "    spn=$EXPECTED_SPN \\"
    echo "    keytab_b64=\$(base64 -w 0 /path/to/vault.keytab)"
    echo ""
fi

# =============================================================================
# Check 6: gMSA Role Configuration
# =============================================================================
print_info "Checking gMSA role: $ROLE_NAME..."

if role=$(vault read -format=json "auth/${AUTH_PATH}/role/${ROLE_NAME}" 2>/dev/null); then
    print_success "Role exists: $ROLE_NAME"
    
    # Check policies
    policies=$(echo "$role" | jq -r '.data.token_policies[]? // empty' | tr '\n' ', ' | sed 's/,$//')
    if [ -n "$policies" ]; then
        print_success "Role policies: $policies"
    else
        print_warning "No policies assigned to role"
    fi
    
    # Check allowed realms
    allowed_realms=$(echo "$role" | jq -r '.data.allowed_realms[]? // empty' | tr '\n' ', ' | sed 's/,$//')
    if [ -n "$allowed_realms" ]; then
        if echo "$allowed_realms" | grep -q "$EXPECTED_REALM"; then
            print_success "Allowed realms include: $EXPECTED_REALM"
        else
            print_warning "Allowed realms ($allowed_realms) don't include expected realm: $EXPECTED_REALM"
        fi
    else
        print_info "No realm restrictions (allows all realms)"
    fi
    
    # Check TTL
    max_ttl=$(echo "$role" | jq -r '.data.max_ttl // 0')
    print_info "Token max TTL: ${max_ttl}s"
    
else
    print_error "Role NOT found: $ROLE_NAME"
    echo ""
    echo -e "${YELLOW}SOLUTION: Create role:${NC}"
    echo "  vault write auth/${AUTH_PATH}/role/${ROLE_NAME} \\"
    echo "    token_policies=default \\"
    echo "    allowed_realms=${EXPECTED_REALM}"
    echo ""
fi

# =============================================================================
# Check 7: Vault Policies
# =============================================================================
print_info "Checking Vault policies..."

if policies=$(vault policy list 2>/dev/null); then
    policy_count=$(echo "$policies" | wc -l)
    print_success "Found $policy_count policies"
    
    # Check for common policies
    if echo "$policies" | grep -q "^default$"; then
        print_info "Default policy exists"
    fi
else
    print_warning "Could not list policies"
fi

# =============================================================================
# Check 8: Plugin Binary
# =============================================================================
print_info "Checking plugin binary..."

if vault plugin list -format=json 2>/dev/null | jq -e '.auth[] | select(.name=="vault-plugin-auth-gmsa")' &> /dev/null; then
    plugin_info=$(vault plugin list -format=json | jq '.auth[] | select(.name=="vault-plugin-auth-gmsa")')
    plugin_version=$(echo "$plugin_info" | jq -r '.version // "unknown"')
    print_success "Plugin registered: vault-plugin-auth-gmsa (version: $plugin_version)"
else
    print_warning "Plugin may not be registered in catalog"
    print_info "This is okay if auth method is working"
fi

# =============================================================================
# Check 9: Vault Server Logs (if accessible)
# =============================================================================
print_info "Checking for recent authentication attempts..."

# This is informational only
print_info "Check Vault server logs for authentication details"
print_info "  journalctl -u vault -n 50 | grep gmsa"

# =============================================================================
# Final Summary
# =============================================================================
print_header "Verification Summary"

total_checks=$((checks_passed + issues_found))
success_rate=$((checks_passed * 100 / total_checks))

echo -e "Checks passed: ${GREEN}$checks_passed${NC} / $total_checks"
echo -e "Issues found:  ${RED}$issues_found${NC}"
echo ""

if [ $issues_found -eq 0 ]; then
    echo -e "${GREEN}✓ ALL CHECKS PASSED - Vault server is correctly configured!${NC}"
    echo ""
    echo -e "${GREEN}Success Rate: 100%${NC}"
    echo ""
    echo "The Vault server is ready for gMSA authentication."
    echo ""
    echo "Test authentication from Windows client:"
    echo "  Start-ScheduledTask -TaskName 'VaultClientApp'"
    echo ""
    exit 0
else
    echo -e "${RED}✗ ISSUES FOUND - Configuration incomplete${NC}"
    echo ""
    echo -e "${YELLOW}Success Rate: ${success_rate}%${NC}"
    echo ""
    echo "Review the errors above and apply the suggested solutions."
    echo ""
    
    if [ $issues_found -le 2 ]; then
        echo -e "${YELLOW}You're close! Just fix the highlighted issues.${NC}"
    else
        echo -e "${RED}Multiple issues detected. Review the configuration guide.${NC}"
    fi
    echo ""
    exit 1
fi
