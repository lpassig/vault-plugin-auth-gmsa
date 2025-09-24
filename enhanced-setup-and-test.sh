#!/bin/bash

echo "=== Enhanced GMSA Auth Plugin Setup & Comprehensive Testing ==="
echo "Complete setup with comprehensive validation of all functions"
echo

# Set Vault environment
export VAULT_ADDR=http://127.0.0.1:8200

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test suite results
COMPREHENSIVE_TESTS_PASSED=0
COMPREHENSIVE_TESTS_FAILED=0
SECURITY_TESTS_PASSED=0
SECURITY_TESTS_FAILED=0
PERFORMANCE_TESTS_PASSED=0
PERFORMANCE_TESTS_FAILED=0

# Cleanup function
cleanup() {
    echo
    echo -e "${YELLOW}Cleaning up...${NC}"
    if [ ! -z "$VAULT_PID" ]; then
        echo "Stopping Vault (PID: $VAULT_PID)..."
        kill $VAULT_PID 2>/dev/null || true
    fi
    echo -e "${GREEN}Cleanup complete.${NC}"
}

# Set trap to cleanup on script exit
trap cleanup EXIT

# Function to run a test suite and capture results
run_test_suite() {
    local suite_name="$1"
    local suite_script="$2"
    local suite_description="$3"
    
    echo
    echo -e "${PURPLE}=== Running ${suite_name} ===${NC}"
    echo -e "${CYAN}${suite_description}${NC}"
    echo
    
    if [ -f "$suite_script" ]; then
        if bash "$suite_script"; then
            echo -e "${GREEN}✅ ${suite_name} PASSED${NC}"
            return 0
        else
            echo -e "${RED}❌ ${suite_name} FAILED${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Test suite script not found: ${suite_script}${NC}"
        return 1
    fi
}

# Function to check if Vault is running
check_vault_running() {
    if curl -s http://127.0.0.1:8200/v1/sys/seal-status >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to setup Vault and plugin
setup_vault_and_plugin() {
    echo -e "${BLUE}=== Phase 1: Vault Setup & Plugin Installation ===${NC}"
    
    echo "1. Stopping any existing Vault processes..."
    pkill vault 2>/dev/null || true
    sleep 3
    
    # Clean up any existing plugin registrations (only if Vault is running)
    echo "Cleaning up existing plugin registrations..."
    if check_vault_running; then
        vault plugin deregister auth vault-plugin-auth-gmsa 2>/dev/null || true
    else
        echo "Vault not running, skipping plugin cleanup"
    fi
    
    echo "2. Building the plugin..."
    if ! make build; then
        echo -e "${RED}❌ Plugin build failed${NC}"
        exit 1
    fi
    
    echo "3. Setting up plugin directory..."
    mkdir -p /private/tmp/vault-plugins
    cp bin/vault-plugin-auth-gmsa /private/tmp/vault-plugins/
    
    echo "4. Starting Vault with configuration..."
    vault server -config=vault-dev.hcl &
    VAULT_PID=$!
    echo "Vault started with PID: $VAULT_PID"
    
    echo "Waiting for Vault to start..."
    for i in {1..30}; do
        if check_vault_running; then
            echo -e "${GREEN}Vault is ready!${NC}"
            break
        fi
        echo "Waiting for Vault... ($i/30)"
        sleep 1
    done
    
    if ! check_vault_running; then
        echo -e "${RED}ERROR: Vault failed to start${NC}"
        exit 1
    fi
    
    echo "5. Initializing Vault..."
    if vault status | grep -q "Initialized.*false"; then
        echo "Vault not initialized, initializing..."
        INIT_OUTPUT=$(vault operator init -key-shares=1 -key-threshold=1)
        UNSEAL_KEY=$(echo "$INIT_OUTPUT" | grep "Unseal Key 1:" | awk '{print $4}')
        ROOT_TOKEN=$(echo "$INIT_OUTPUT" | grep "Initial Root Token:" | awk '{print $4}')
        export VAULT_TOKEN=$ROOT_TOKEN
        
        echo "6. Unsealing Vault..."
        vault operator unseal $UNSEAL_KEY
    else
        echo "Vault already initialized, checking if unsealed..."
        if vault status | grep -q "Sealed.*true"; then
            echo -e "${RED}Vault is sealed, please unseal manually or restart with fresh data${NC}"
            echo "You can unseal with: vault operator unseal <unseal-key>"
            exit 1
        else
            echo "Vault is already unsealed, using existing token..."
            if [ -z "$VAULT_TOKEN" ]; then
                echo -e "${RED}Please set VAULT_TOKEN environment variable or authenticate manually${NC}"
                echo "Example: export VAULT_TOKEN=<your-root-token>"
                exit 1
            fi
        fi
    fi
    
    echo "7. Checking Vault status..."
    vault status
    
    echo "8. Registering the GMSA auth plugin..."
    PLUGIN_SHA256=$(sha256sum /private/tmp/vault-plugins/vault-plugin-auth-gmsa | awk '{print $1}')
    echo "Plugin SHA256: $PLUGIN_SHA256"
    vault plugin register -sha256="$PLUGIN_SHA256" -version="v0.1.0" auth vault-plugin-auth-gmsa
    
    echo "9. Enabling the GMSA auth method..."
    vault auth enable -path=gmsa vault-plugin-auth-gmsa
    
    echo "10. Verifying the auth method is enabled..."
    vault auth list
    
    echo "11. Setting up basic configuration for testing..."
    echo "dGVzdCBrZXl0YWIgZGF0YQ==" > /tmp/test-keytab.b64
    vault write auth/gmsa/config \
      realm=EXAMPLE.COM \
      kdcs="dc1.example.com,dc2.example.com" \
      spn="HTTP/vault.example.com" \
      keytab=@/tmp/test-keytab.b64 \
      allow_channel_binding=true \
      clock_skew_sec=300
    
    echo "12. Verifying basic configuration..."
    vault read auth/gmsa/config
    
    echo -e "${GREEN}✅ Vault setup and plugin installation completed successfully!${NC}"
}

# Function to run comprehensive tests
run_comprehensive_tests() {
    echo -e "${BLUE}=== Phase 2: Comprehensive Function Testing ===${NC}"
    
    if run_test_suite "Comprehensive Test Suite" "./comprehensive-test-suite.sh" "Testing all plugin functions and features"; then
        COMPREHENSIVE_TESTS_PASSED=1
    else
        COMPREHENSIVE_TESTS_FAILED=1
    fi
}

# Function to run security tests
run_security_tests() {
    echo -e "${BLUE}=== Phase 3: Security Validation ===${NC}"
    
    if run_test_suite "Security Test Suite" "./security-test-suite.sh" "Testing security features and attack vectors"; then
        SECURITY_TESTS_PASSED=1
    else
        SECURITY_TESTS_FAILED=1
    fi
}

# Function to run performance tests
run_performance_tests() {
    echo -e "${BLUE}=== Phase 4: Performance Validation ===${NC}"
    
    if run_test_suite "Performance Test Suite" "./performance-test-suite.sh" "Testing performance characteristics and load handling"; then
        PERFORMANCE_TESTS_PASSED=1
    else
        PERFORMANCE_TESTS_FAILED=1
    fi
}

# Function to generate final report
generate_final_report() {
    echo
    echo -e "${PURPLE}=== FINAL COMPREHENSIVE VALIDATION REPORT ===${NC}"
    echo "=================================================="
    echo
    
    # Test suite results
    echo -e "${BLUE}Test Suite Results:${NC}"
    if [ $COMPREHENSIVE_TESTS_PASSED -eq 1 ]; then
        echo -e "${GREEN}  ✅ Comprehensive Test Suite: PASSED${NC}"
    else
        echo -e "${RED}  ❌ Comprehensive Test Suite: FAILED${NC}"
    fi
    
    if [ $SECURITY_TESTS_PASSED -eq 1 ]; then
        echo -e "${GREEN}  ✅ Security Test Suite: PASSED${NC}"
    else
        echo -e "${RED}  ❌ Security Test Suite: FAILED${NC}"
    fi
    
    if [ $PERFORMANCE_TESTS_PASSED -eq 1 ]; then
        echo -e "${GREEN}  ✅ Performance Test Suite: PASSED${NC}"
    else
        echo -e "${RED}  ❌ Performance Test Suite: FAILED${NC}"
    fi
    
    echo
    
    # Overall assessment
    local total_passed=$((COMPREHENSIVE_TESTS_PASSED + SECURITY_TESTS_PASSED + PERFORMANCE_TESTS_PASSED))
    local total_failed=$((COMPREHENSIVE_TESTS_FAILED + SECURITY_TESTS_FAILED + PERFORMANCE_TESTS_FAILED))
    
    if [ $total_failed -eq 0 ]; then
        echo -e "${GREEN}🎉 ALL TEST SUITES PASSED! 🎉${NC}"
        echo -e "${GREEN}The gMSA auth plugin is fully validated and production-ready!${NC}"
        echo
        echo -e "${BLUE}✅ Validation Summary:${NC}"
        echo "   • All plugin functions tested and working"
        echo "   • Security features validated and secure"
        echo "   • Performance characteristics excellent"
        echo "   • Production readiness confirmed"
        echo
        echo -e "${GREEN}🚀 PRODUCTION DEPLOYMENT: APPROVED${NC}"
        echo
        echo -e "${YELLOW}📋 Next Steps:${NC}"
        echo "   1. Deploy to production environment"
        echo "   2. Configure with real gMSA keytab"
        echo "   3. Set up monitoring and alerting"
        echo "   4. Train operations team"
        echo "   5. Document operational procedures"
        echo
        echo -e "${CYAN}🎯 Your plugin is ready for enterprise use!${NC}"
        return 0
    else
        echo -e "${RED}⚠️ SOME TEST SUITES FAILED! ⚠️${NC}"
        echo -e "${RED}Please review the failed test suites above.${NC}"
        echo
        echo -e "${YELLOW}Failed test suites may indicate:${NC}"
        echo "   • Functionality issues"
        echo "   • Security vulnerabilities"
        echo "   • Performance problems"
        echo "   • Configuration errors"
        echo
        echo -e "${RED}🚫 PRODUCTION DEPLOYMENT: NOT RECOMMENDED${NC}"
        echo -e "${YELLOW}Please fix the issues before deploying to production.${NC}"
        return 1
    fi
}

# Function to show usage information
show_usage() {
    echo -e "${BLUE}Usage: $0 [OPTIONS]${NC}"
    echo
    echo -e "${CYAN}Options:${NC}"
    echo "  --setup-only     Run only the setup phase (skip tests)"
    echo "  --tests-only     Run only the test suites (assume Vault is running)"
    echo "  --comprehensive  Run comprehensive tests only"
    echo "  --security       Run security tests only"
    echo "  --performance    Run performance tests only"
    echo "  --help           Show this help message"
    echo
    echo -e "${CYAN}Examples:${NC}"
    echo "  $0                    # Run complete setup and all tests"
    echo "  $0 --setup-only       # Run only setup (skip tests)"
    echo "  $0 --tests-only       # Run only tests (assume setup done)"
    echo "  $0 --security         # Run only security tests"
    echo
}

# Main function
main() {
    # Parse command line arguments
    case "${1:-}" in
        --setup-only)
            echo -e "${YELLOW}Running setup only (skipping tests)...${NC}"
            setup_vault_and_plugin
            echo -e "${GREEN}✅ Setup completed successfully!${NC}"
            echo -e "${YELLOW}To run tests, use: $0 --tests-only${NC}"
            exit 0
            ;;
        --tests-only)
            echo -e "${YELLOW}Running tests only (assuming Vault is running)...${NC}"
            if ! check_vault_running; then
                echo -e "${RED}ERROR: Vault is not running${NC}"
                echo "Please start Vault first using: $0 --setup-only"
                exit 1
            fi
            run_comprehensive_tests
            run_security_tests
            run_performance_tests
            generate_final_report
            ;;
        --comprehensive)
            echo -e "${YELLOW}Running comprehensive tests only...${NC}"
            if ! check_vault_running; then
                echo -e "${RED}ERROR: Vault is not running${NC}"
                echo "Please start Vault first using: $0 --setup-only"
                exit 1
            fi
            run_comprehensive_tests
            ;;
        --security)
            echo -e "${YELLOW}Running security tests only...${NC}"
            if ! check_vault_running; then
                echo -e "${RED}ERROR: Vault is not running${NC}"
                echo "Please start Vault first using: $0 --setup-only"
                exit 1
            fi
            run_security_tests
            ;;
        --performance)
            echo -e "${YELLOW}Running performance tests only...${NC}"
            if ! check_vault_running; then
                echo -e "${RED}ERROR: Vault is not running${NC}"
                echo "Please start Vault first using: $0 --setup-only"
                exit 1
            fi
            run_performance_tests
            ;;
        --help)
            show_usage
            exit 0
            ;;
        "")
            # Default: run everything
            echo -e "${YELLOW}Running complete setup and comprehensive testing...${NC}"
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
    
    # Run complete validation
    setup_vault_and_plugin
    run_comprehensive_tests
    run_security_tests
    run_performance_tests
    generate_final_report
}

# Run main function
main "$@"
