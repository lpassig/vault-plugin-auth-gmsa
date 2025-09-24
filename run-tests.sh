#!/bin/bash

echo "=== GMSA Auth Plugin Test Runner ==="
echo "Run specific test suites or all tests"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    echo -e "${BLUE}Usage: $0 [TEST_SUITE] [OPTIONS]${NC}"
    echo
    echo -e "${CYAN}Test Suites:${NC}"
    echo "  all            Run all test suites (default)"
    echo "  comprehensive  Run comprehensive function tests"
    echo "  security       Run security-focused tests"
    echo "  performance    Run performance tests"
    echo "  unit           Run Go unit tests"
    echo "  integration    Run integration tests"
    echo
    echo -e "${CYAN}Options:${NC}"
    echo "  --setup        Run setup first (start Vault, enable plugin)"
    echo "  --cleanup      Clean up after tests"
    echo "  --verbose      Show detailed output"
    echo "  --help         Show this help message"
    echo
    echo -e "${CYAN}Examples:${NC}"
    echo "  $0                                    # Run all tests"
    echo "  $0 comprehensive --setup             # Run comprehensive tests with setup"
    echo "  $0 security --verbose                # Run security tests with verbose output"
    echo "  $0 performance --setup --cleanup     # Run performance tests with setup and cleanup"
    echo "  $0 unit                              # Run Go unit tests only"
    echo
}

# Function to check if Vault is running
check_vault() {
    if curl -s http://127.0.0.1:8200/v1/sys/seal-status >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to check if plugin is enabled
check_plugin() {
    if vault auth list | grep -q "gmsa/"; then
        return 0
    else
        return 1
    fi
}

# Function to run setup
run_setup() {
    echo -e "${YELLOW}Running setup...${NC}"
    if [ -f "./enhanced-setup-and-test.sh" ]; then
        ./enhanced-setup-and-test.sh --setup-only
    else
        echo -e "${RED}Setup script not found: enhanced-setup-and-test.sh${NC}"
        return 1
    fi
}

# Function to run comprehensive tests
run_comprehensive_tests() {
    echo -e "${BLUE}=== Running Comprehensive Tests ===${NC}"
    if [ -f "./comprehensive-test-suite.sh" ]; then
        ./comprehensive-test-suite.sh
    else
        echo -e "${RED}Comprehensive test suite not found${NC}"
        return 1
    fi
}

# Function to run security tests
run_security_tests() {
    echo -e "${BLUE}=== Running Security Tests ===${NC}"
    if [ -f "./security-test-suite.sh" ]; then
        ./security-test-suite.sh
    else
        echo -e "${RED}Security test suite not found${NC}"
        return 1
    fi
}

# Function to run performance tests
run_performance_tests() {
    echo -e "${BLUE}=== Running Performance Tests ===${NC}"
    if [ -f "./performance-test-suite.sh" ]; then
        ./performance-test-suite.sh
    else
        echo -e "${RED}Performance test suite not found${NC}"
        return 1
    fi
}

# Function to run unit tests
run_unit_tests() {
    echo -e "${BLUE}=== Running Unit Tests ===${NC}"
    echo "Running Go unit tests..."
    if go test ./... -v; then
        echo -e "${GREEN}✅ Unit tests passed${NC}"
        return 0
    else
        echo -e "${RED}❌ Unit tests failed${NC}"
        return 1
    fi
}

# Function to run integration tests
run_integration_tests() {
    echo -e "${BLUE}=== Running Integration Tests ===${NC}"
    echo "Running integration tests..."
    
    # Check if Vault is running
    if ! check_vault; then
        echo -e "${RED}Vault is not running. Please start Vault first.${NC}"
        return 1
    fi
    
    # Check if plugin is enabled
    if ! check_plugin; then
        echo -e "${RED}GMSA plugin is not enabled. Please enable it first.${NC}"
        return 1
    fi
    
    # Run integration tests
    echo "Testing plugin integration with Vault..."
    
    # Test basic functionality
    echo "Testing basic plugin functionality..."
    if vault read auth/gmsa/health >/dev/null 2>&1; then
        echo -e "${GREEN}  ✅ Health endpoint working${NC}"
    else
        echo -e "${RED}  ❌ Health endpoint failed${NC}"
        return 1
    fi
    
    if vault read auth/gmsa/config >/dev/null 2>&1; then
        echo -e "${GREEN}  ✅ Configuration endpoint working${NC}"
    else
        echo -e "${RED}  ❌ Configuration endpoint failed${NC}"
        return 1
    fi
    
    if vault list auth/gmsa/roles >/dev/null 2>&1; then
        echo -e "${GREEN}  ✅ Role management working${NC}"
    else
        echo -e "${RED}  ❌ Role management failed${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Integration tests passed${NC}"
    return 0
}

# Function to run cleanup
run_cleanup() {
    echo -e "${YELLOW}Running cleanup...${NC}"
    echo "Stopping Vault processes..."
    pkill vault 2>/dev/null || true
    echo "Cleaning up test files..."
    rm -f /tmp/test-keytab.b64 /tmp/test-spnego.b64 /tmp/test-channel-binding.b64
    echo -e "${GREEN}Cleanup completed${NC}"
}

# Function to run all tests
run_all_tests() {
    echo -e "${BLUE}=== Running All Test Suites ===${NC}"
    
    local all_passed=0
    
    # Run unit tests
    if run_unit_tests; then
        echo -e "${GREEN}✅ Unit tests passed${NC}"
    else
        echo -e "${RED}❌ Unit tests failed${NC}"
        all_passed=1
    fi
    
    # Run integration tests
    if run_integration_tests; then
        echo -e "${GREEN}✅ Integration tests passed${NC}"
    else
        echo -e "${RED}❌ Integration tests failed${NC}"
        all_passed=1
    fi
    
    # Run comprehensive tests
    if run_comprehensive_tests; then
        echo -e "${GREEN}✅ Comprehensive tests passed${NC}"
    else
        echo -e "${RED}❌ Comprehensive tests failed${NC}"
        all_passed=1
    fi
    
    # Run security tests
    if run_security_tests; then
        echo -e "${GREEN}✅ Security tests passed${NC}"
    else
        echo -e "${RED}❌ Security tests failed${NC}"
        all_passed=1
    fi
    
    # Run performance tests
    if run_performance_tests; then
        echo -e "${GREEN}✅ Performance tests passed${NC}"
    else
        echo -e "${RED}❌ Performance tests failed${NC}"
        all_passed=1
    fi
    
    return $all_passed
}

# Main function
main() {
    local test_suite="all"
    local run_setup_flag=false
    local run_cleanup_flag=false
    local verbose_flag=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            all|comprehensive|security|performance|unit|integration)
                test_suite="$1"
                shift
                ;;
            --setup)
                run_setup_flag=true
                shift
                ;;
            --cleanup)
                run_cleanup_flag=true
                shift
                ;;
            --verbose)
                verbose_flag=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set verbose mode if requested
    if [ "$verbose_flag" = true ]; then
        set -x
    fi
    
    echo -e "${CYAN}Running test suite: ${test_suite}${NC}"
    echo
    
    # Run setup if requested
    if [ "$run_setup_flag" = true ]; then
        if ! run_setup; then
            echo -e "${RED}Setup failed${NC}"
            exit 1
        fi
    fi
    
    # Run the requested test suite
    local test_result=0
    case $test_suite in
        all)
            if ! run_all_tests; then
                test_result=1
            fi
            ;;
        comprehensive)
            if ! run_comprehensive_tests; then
                test_result=1
            fi
            ;;
        security)
            if ! run_security_tests; then
                test_result=1
            fi
            ;;
        performance)
            if ! run_performance_tests; then
                test_result=1
            fi
            ;;
        unit)
            if ! run_unit_tests; then
                test_result=1
            fi
            ;;
        integration)
            if ! run_integration_tests; then
                test_result=1
            fi
            ;;
    esac
    
    # Run cleanup if requested
    if [ "$run_cleanup_flag" = true ]; then
        run_cleanup
    fi
    
    # Final result
    if [ $test_result -eq 0 ]; then
        echo
        echo -e "${GREEN}🎉 All tests completed successfully! 🎉${NC}"
        exit 0
    else
        echo
        echo -e "${RED}❌ Some tests failed! ❌${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
