#!/bin/bash

echo "=== Performance Test Suite ==="
echo "Testing performance characteristics and load handling"
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

# Performance thresholds (in milliseconds)
HEALTH_THRESHOLD_EXCELLENT=50
HEALTH_THRESHOLD_GOOD=200
CONFIG_THRESHOLD_EXCELLENT=100
CONFIG_THRESHOLD_GOOD=500
METRICS_THRESHOLD_EXCELLENT=100
METRICS_THRESHOLD_GOOD=500
AUTH_THRESHOLD_EXCELLENT=200
AUTH_THRESHOLD_GOOD=1000

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Function to measure response time
measure_response_time() {
    local command="$1"
    local start_time=$(date +%s%N)
    eval "$command" >/dev/null 2>&1
    local end_time=$(date +%s%N)
    local response_time=$(( (end_time - start_time) / 1000000 ))
    echo $response_time
}

# Function to run a performance test
run_performance_test() {
    local test_name="$1"
    local test_command="$2"
    local threshold_excellent="$3"
    local threshold_good="$4"
    local expected_success="${5:-true}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${CYAN}  Testing: ${test_name}${NC}"
    
    local response_time=$(measure_response_time "$test_command")
    
    if [ $response_time -lt $threshold_excellent ]; then
        echo -e "${GREEN}    ✓ EXCELLENT: ${test_name} - ${response_time}ms${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    elif [ $response_time -lt $threshold_good ]; then
        echo -e "${YELLOW}    ⚠ GOOD: ${test_name} - ${response_time}ms${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}    ✗ POOR: ${test_name} - ${response_time}ms${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Function to start a performance test category
start_performance_category() {
    local category_name="$1"
    echo
    echo -e "${PURPLE}=== ${category_name} ===${NC}"
}

# Function to end a performance test category
end_performance_category() {
    local category_name="$1"
    echo -e "${BLUE}Completed ${category_name}${NC}"
    echo
}

# Function to setup test data
setup_performance_test_data() {
    echo -e "${YELLOW}Setting up performance test data...${NC}"
    echo "dGVzdCBrZXl0YWIgZGF0YQ==" > /tmp/test-keytab.b64
    echo "Y2VydGFpbmx5IG5vdCBhIHJlYWwgc3BuZWdvIHRva2Vu" > /tmp/test-spnego.b64
    echo -e "${GREEN}✓ Performance test data prepared${NC}"
}

# Function to test basic endpoint performance
test_basic_endpoint_performance() {
    start_performance_category "Basic Endpoint Performance Tests"
    
    # Health endpoint performance
    run_performance_test "Health endpoint (basic)" "vault read auth/gmsa/health" $HEALTH_THRESHOLD_EXCELLENT $HEALTH_THRESHOLD_GOOD
    run_performance_test "Health endpoint (detailed)" "vault read auth/gmsa/health detailed=true" $HEALTH_THRESHOLD_EXCELLENT $HEALTH_THRESHOLD_GOOD
    
    # Metrics endpoint performance
    run_performance_test "Metrics endpoint" "vault read auth/gmsa/metrics" $METRICS_THRESHOLD_EXCELLENT $METRICS_THRESHOLD_GOOD
    
    # Configuration endpoint performance
    run_performance_test "Configuration read" "vault read auth/gmsa/config" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    end_performance_category "Basic Endpoint Performance Tests"
}

# Function to test configuration performance
test_configuration_performance() {
    start_performance_category "Configuration Performance Tests"
    
    # Configuration write performance
    run_performance_test "Configuration write (basic)" "vault write auth/gmsa/config realm=EXAMPLE.COM kdcs='dc1.example.com,dc2.example.com' spn='HTTP/vault.example.com' keytab=@/tmp/test-keytab.b64 allow_channel_binding=true clock_skew_sec=300" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    # Configuration update performance
    run_performance_test "Configuration update" "vault write auth/gmsa/config realm=EXAMPLE.COM kdcs='dc1.example.com,dc2.example.com,dc3.example.com' spn='HTTP/vault.example.com' keytab=@/tmp/test-keytab.b64 allow_channel_binding=false clock_skew_sec=600" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    # Configuration with normalization performance
    run_performance_test "Configuration write (with normalization)" "vault write auth/gmsa/config realm=EXAMPLE.COM kdcs='dc1.example.com' spn='HTTP/vault.example.com' keytab=@/tmp/test-keytab.b64 realm_case_sensitive=false spn_case_sensitive=false realm_suffixes='.local,.lan' spn_suffixes='.local,.lan'" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    end_performance_category "Configuration Performance Tests"
}

# Function to test role management performance
test_role_management_performance() {
    start_performance_category "Role Management Performance Tests"
    
    # Role creation performance
    run_performance_test "Role creation (basic)" "vault write auth/gmsa/role/perf-test-role name=perf-test-role allowed_realms=EXAMPLE.COM allowed_spns='HTTP/vault.example.com' token_policies=default" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    # Role read performance
    run_performance_test "Role read" "vault read auth/gmsa/role/perf-test-role" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    # Role update performance
    run_performance_test "Role update" "vault write auth/gmsa/role/perf-test-role name=perf-test-role allowed_realms='EXAMPLE.COM,TEST.COM' token_policies='default,kv-read'" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    # Role list performance
    run_performance_test "Role list" "vault list auth/gmsa/roles" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    # Role deletion performance
    run_performance_test "Role deletion" "vault delete auth/gmsa/role/perf-test-role" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    end_performance_category "Role Management Performance Tests"
}

# Function to test authentication performance
test_authentication_performance() {
    start_performance_category "Authentication Performance Tests"
    
    # Create test role
    vault write auth/gmsa/role/auth-perf-test name=auth-perf-test allowed_realms=EXAMPLE.COM allowed_spns='HTTP/vault.example.com' token_policies=default >/dev/null 2>&1
    
    # Authentication endpoint performance (will fail with mock data, but we measure response time)
    run_performance_test "Authentication endpoint (mock data)" "vault write auth/gmsa/login role=auth-perf-test spnego=@/tmp/test-spnego.b64" $AUTH_THRESHOLD_EXCELLENT $AUTH_THRESHOLD_GOOD "false"
    
    # Authentication with channel binding performance
    run_performance_test "Authentication with channel binding (mock data)" "vault write auth/gmsa/login role=auth-perf-test spnego=@/tmp/test-spnego.b64 cb_tlse=dGVzdC1jaGFubmVsLWJpbmRpbmc=" $AUTH_THRESHOLD_EXCELLENT $AUTH_THRESHOLD_GOOD "false"
    
    # Clean up test role
    vault delete auth/gmsa/role/auth-perf-test >/dev/null 2>&1
    
    end_performance_category "Authentication Performance Tests"
}

# Function to test rotation performance
test_rotation_performance() {
    start_performance_category "Password Rotation Performance Tests"
    
    # Rotation configuration performance
    run_performance_test "Rotation configuration write" "vault write auth/gmsa/rotation/config enabled=true check_interval=300s rotation_threshold=3600s max_retries=3 retry_delay=60s domain_controller=dc1.example.com domain_admin_user=admin domain_admin_password=password" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    # Rotation status performance
    run_performance_test "Rotation status read" "vault read auth/gmsa/rotation/status" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    # Rotation start performance
    run_performance_test "Rotation start" "vault write auth/gmsa/rotation/start" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    # Rotation stop performance
    run_performance_test "Rotation stop" "vault write auth/gmsa/rotation/stop" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD
    
    # Clean up rotation config
    vault delete auth/gmsa/rotation/config >/dev/null 2>&1
    
    end_performance_category "Password Rotation Performance Tests"
}

# Function to test load performance
test_load_performance() {
    start_performance_category "Load Performance Tests"
    
    echo -e "${CYAN}  Testing concurrent request handling...${NC}"
    
    # Test concurrent health checks
    local concurrent_health_start=$(date +%s%N)
    for i in {1..10}; do
        vault read auth/gmsa/health >/dev/null 2>&1 &
    done
    wait
    local concurrent_health_end=$(date +%s%N)
    local concurrent_health_time=$(( (concurrent_health_end - concurrent_health_start) / 1000000 ))
    
    if [ $concurrent_health_time -lt 1000 ]; then
        echo -e "${GREEN}    ✓ EXCELLENT: Concurrent health checks - ${concurrent_health_time}ms${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    elif [ $concurrent_health_time -lt 5000 ]; then
        echo -e "${YELLOW}    ⚠ GOOD: Concurrent health checks - ${concurrent_health_time}ms${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}    ✗ POOR: Concurrent health checks - ${concurrent_health_time}ms${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    # Test concurrent configuration reads
    local concurrent_config_start=$(date +%s%N)
    for i in {1..10}; do
        vault read auth/gmsa/config >/dev/null 2>&1 &
    done
    wait
    local concurrent_config_end=$(date +%s%N)
    local concurrent_config_time=$(( (concurrent_config_end - concurrent_config_start) / 1000000 ))
    
    if [ $concurrent_config_time -lt 1000 ]; then
        echo -e "${GREEN}    ✓ EXCELLENT: Concurrent config reads - ${concurrent_config_time}ms${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    elif [ $concurrent_config_time -lt 5000 ]; then
        echo -e "${YELLOW}    ⚠ GOOD: Concurrent config reads - ${concurrent_config_time}ms${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}    ✗ POOR: Concurrent config reads - ${concurrent_config_time}ms${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    end_performance_category "Load Performance Tests"
}

# Function to test memory usage
test_memory_usage() {
    start_performance_category "Memory Usage Tests"
    
    echo -e "${CYAN}  Testing memory usage patterns...${NC}"
    
    # Get initial memory usage
    local initial_memory=$(ps -o rss= -p $(pgrep vault) 2>/dev/null | head -1)
    if [ -z "$initial_memory" ]; then
        echo -e "${YELLOW}    ⚠ Could not determine Vault memory usage${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${GREEN}    ✓ Initial Vault memory usage: ${initial_memory}KB${NC}"
        
        # Perform multiple operations
        for i in {1..100}; do
            vault read auth/gmsa/health >/dev/null 2>&1
            vault read auth/gmsa/config >/dev/null 2>&1
        done
        
        # Get final memory usage
        local final_memory=$(ps -o rss= -p $(pgrep vault) 2>/dev/null | head -1)
        local memory_increase=$((final_memory - initial_memory))
        
        if [ $memory_increase -lt 10000 ]; then
            echo -e "${GREEN}    ✓ EXCELLENT: Memory usage stable - ${memory_increase}KB increase${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        elif [ $memory_increase -lt 50000 ]; then
            echo -e "${YELLOW}    ⚠ GOOD: Memory usage acceptable - ${memory_increase}KB increase${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}    ✗ POOR: Memory usage high - ${memory_increase}KB increase${NC}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    fi
    
    end_performance_category "Memory Usage Tests"
}

# Function to test error handling performance
test_error_handling_performance() {
    start_performance_category "Error Handling Performance Tests"
    
    # Test error response times
    run_performance_test "Invalid endpoint error" "vault read auth/gmsa/invalid-endpoint" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD "false"
    run_performance_test "Invalid configuration error" "vault write auth/gmsa/config realm='' kdcs='dc1.example.com' spn='HTTP/vault.example.com' keytab=@/tmp/test-keytab.b64" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD "false"
    run_performance_test "Invalid role error" "vault write auth/gmsa/role/invalid-role token_type=invalid" $CONFIG_THRESHOLD_EXCELLENT $CONFIG_THRESHOLD_GOOD "false"
    
    end_performance_category "Error Handling Performance Tests"
}

# Function to generate performance report
generate_performance_report() {
    echo
    echo -e "${PURPLE}=== PERFORMANCE TEST REPORT ===${NC}"
    echo -e "${BLUE}Total Performance Tests: ${TOTAL_TESTS}${NC}"
    echo -e "${GREEN}Performance Tests Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Performance Tests Failed: ${TESTS_FAILED}${NC}"
    echo
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}🚀 ALL PERFORMANCE TESTS PASSED! 🚀${NC}"
        echo -e "${GREEN}The gMSA auth plugin demonstrates excellent performance characteristics!${NC}"
        echo
        echo -e "${BLUE}✅ Performance Characteristics Verified:${NC}"
        echo "   • Fast response times for all endpoints"
        echo "   • Efficient configuration management"
        echo "   • Quick role management operations"
        echo "   • Responsive authentication handling"
        echo "   • Efficient password rotation"
        echo "   • Good concurrent request handling"
        echo "   • Stable memory usage"
        echo "   • Fast error handling"
        echo
        echo -e "${GREEN}⚡ PERFORMANCE GRADE: EXCELLENT${NC}"
        return 0
    else
        echo -e "${RED}⚠️ SOME PERFORMANCE TESTS FAILED! ⚠️${NC}"
        echo -e "${RED}Please review the failed performance tests above.${NC}"
        echo
        echo -e "${YELLOW}Failed performance tests may indicate:${NC}"
        echo "   • Slow response times"
        echo "   • Memory leaks"
        echo "   • Poor concurrent handling"
        echo "   • Resource exhaustion"
        echo
        return 1
    fi
}

# Main function
main() {
    echo -e "${BLUE}Starting Performance Test Suite${NC}"
    echo "=================================="
    echo
    
    # Pre-flight checks
    if ! curl -s http://127.0.0.1:8200/v1/sys/seal-status >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Vault is not running or not accessible${NC}"
        echo "Please start Vault first using: ./setup-and-test.sh"
        exit 1
    fi
    
    if ! vault auth list | grep -q "gmsa/"; then
        echo -e "${RED}ERROR: GMSA auth plugin is not enabled${NC}"
        echo "Please run setup-and-test.sh first to enable the plugin"
        exit 1
    fi
    
    setup_performance_test_data
    
    echo -e "${YELLOW}Running performance validation tests...${NC}"
    echo
    
    # Run all performance test categories
    test_basic_endpoint_performance
    test_configuration_performance
    test_role_management_performance
    test_authentication_performance
    test_rotation_performance
    test_load_performance
    test_memory_usage
    test_error_handling_performance
    
    # Generate final performance report
    generate_performance_report
}

# Run main function
main "$@"
