# GMSA Auth Plugin Testing Guide

This document provides comprehensive information about testing the Vault GMSA authentication plugin.

## Overview

The plugin includes multiple test suites that validate different aspects of functionality:

- **Comprehensive Tests**: All plugin functions and features
- **Security Tests**: Security features and attack vector validation
- **Performance Tests**: Performance characteristics and load handling
- **Unit Tests**: Go unit tests for individual components
- **Integration Tests**: Plugin integration with Vault

## Test Suites

### 1. Comprehensive Test Suite (`comprehensive-test-suite.sh`)

Tests all plugin functions and features:

#### Health & Monitoring Tests
- Basic health check endpoint
- Detailed health check with system information
- Metrics endpoint
- Invalid parameter handling

#### Configuration Management Tests
- Basic configuration write/read
- Configuration with normalization settings
- Configuration updates
- Configuration deletion and restoration

#### Configuration Validation Tests
- Invalid realm validation (lowercase, empty, invalid characters)
- Invalid SPN validation (lowercase service, missing parts, invalid characters)
- Invalid KDC validation (empty, too many, invalid characters)
- Invalid keytab validation (empty, invalid base64)
- Invalid clock skew validation (negative, excessive)

#### Role Management Tests
- Basic role creation/read/update/delete
- Comprehensive role with all options
- Role validation (invalid token type, merge strategy, periods)
- Role list operations

#### Authentication Endpoint Tests
- Login endpoint structure validation
- Channel binding support
- Invalid parameter handling
- Mock authentication attempts

#### Password Rotation Tests
- Rotation configuration management
- Rotation start/stop operations
- Rotation status monitoring
- Configuration validation

#### Error Handling & Recovery Tests
- Graceful handling of missing configuration
- Invalid endpoint handling
- Invalid operation handling

#### Performance Tests
- Response time measurement
- Concurrent request handling
- Memory usage monitoring

#### Security Features Tests
- Input size limit validation
- Sensitive data redaction verification
- Error message safety

#### Cross-Platform Compatibility Tests
- Platform detection
- Platform-specific rotation manager behavior

#### Integration Scenario Tests
- Complete authentication workflow
- End-to-end functionality validation

### 2. Security Test Suite (`security-test-suite.sh`)

Tests security features and validates against attack vectors:

#### Input Validation Security Tests
- SQL injection attempts
- Script injection attempts
- Buffer overflow attempts
- Path traversal attempts
- Null byte injection
- Unicode attacks

#### Authentication Security Tests
- Empty/invalid SPNEGO token handling
- Oversized token handling
- Channel binding attacks
- Role enumeration attacks
- Timing attack resistance

#### Authorization Security Tests
- Malicious policy handling
- Group SID validation
- Policy injection attempts
- Deny policy functionality

#### Configuration Security Tests
- Configuration injection attempts
- Malicious keytab handling
- DNS poisoning attempts
- Clock skew manipulation
- Channel binding bypass attempts

#### Password Rotation Security Tests
- Rotation configuration injection
- Malicious notification endpoints
- Excessive retry attempts
- Malicious keytab commands

#### Error Handling Security Tests
- Information disclosure prevention
- Stack trace security
- Timing attack resistance

#### Logging Security Tests
- Sensitive data redaction
- Audit logging verification

### 3. Performance Test Suite (`performance-test-suite.sh`)

Tests performance characteristics and load handling:

#### Basic Endpoint Performance Tests
- Health endpoint response times
- Metrics endpoint response times
- Configuration read response times

#### Configuration Performance Tests
- Configuration write performance
- Configuration update performance
- Configuration with normalization performance

#### Role Management Performance Tests
- Role creation performance
- Role read performance
- Role update performance
- Role list performance
- Role deletion performance

#### Authentication Performance Tests
- Authentication endpoint response times
- Channel binding performance

#### Password Rotation Performance Tests
- Rotation configuration performance
- Rotation status performance
- Rotation start/stop performance

#### Load Performance Tests
- Concurrent request handling
- Concurrent configuration reads

#### Memory Usage Tests
- Memory usage patterns
- Memory leak detection

#### Error Handling Performance Tests
- Error response times
- Invalid request handling performance

## Running Tests

### Quick Start

```bash
# Run all tests with setup
./enhanced-setup-and-test.sh

# Run all tests (assuming Vault is running)
./run-tests.sh all

# Run specific test suite
./run-tests.sh comprehensive
./run-tests.sh security
./run-tests.sh performance
```

### Test Runner Options

The `run-tests.sh` script provides flexible options:

```bash
# Run with setup
./run-tests.sh comprehensive --setup

# Run with cleanup
./run-tests.sh security --cleanup

# Run with verbose output
./run-tests.sh performance --verbose

# Run unit tests only
./run-tests.sh unit

# Run integration tests only
./run-tests.sh integration
```

### Individual Test Suites

```bash
# Run comprehensive tests
./comprehensive-test-suite.sh

# Run security tests
./security-test-suite.sh

# Run performance tests
./performance-test-suite.sh

# Run Go unit tests
go test ./... -v
```

## Test Data

The test suites use mock data for testing:

- **Test Keytab**: Base64-encoded test keytab data
- **Test SPNEGO**: Base64-encoded mock SPNEGO token
- **Test Channel Binding**: Base64-encoded test channel binding

**Note**: These are mock data for testing endpoint structure and validation. Real authentication requires valid gMSA keytab and Kerberos infrastructure.

## Test Results

### Success Criteria

- **Comprehensive Tests**: All functionality working correctly
- **Security Tests**: All security controls functioning properly
- **Performance Tests**: Response times within acceptable thresholds
- **Unit Tests**: All Go unit tests passing
- **Integration Tests**: Plugin properly integrated with Vault

### Performance Thresholds

- **Health Endpoint**: < 50ms (excellent), < 200ms (good)
- **Configuration Operations**: < 100ms (excellent), < 500ms (good)
- **Metrics Endpoint**: < 100ms (excellent), < 500ms (good)
- **Authentication**: < 200ms (excellent), < 1000ms (good)

### Security Validation

- **Input Validation**: All malicious inputs properly rejected
- **Authentication Security**: All attack vectors properly handled
- **Authorization Security**: All authorization controls functioning
- **Error Handling**: No information disclosure in error messages
- **Logging Security**: Sensitive data properly redacted

## Troubleshooting

### Common Issues

1. **Vault Not Running**
   ```bash
   # Start Vault first
   ./enhanced-setup-and-test.sh --setup-only
   ```

2. **Plugin Not Enabled**
   ```bash
   # Enable the plugin
   vault auth enable -path=gmsa vault-plugin-auth-gmsa
   ```

3. **Permission Issues**
   ```bash
   # Make scripts executable
   chmod +x *.sh
   ```

4. **Test Failures**
   - Check Vault logs for errors
   - Verify plugin is properly registered
   - Ensure test data is available

### Debug Mode

Run tests with verbose output:

```bash
./run-tests.sh all --verbose
```

### Manual Testing

For manual testing of specific features:

```bash
# Test health endpoint
vault read auth/gmsa/health

# Test configuration
vault read auth/gmsa/config

# Test role management
vault list auth/gmsa/roles

# Test metrics
vault read auth/gmsa/metrics
```

## Continuous Integration

The test suites are designed to run in CI/CD pipelines:

```bash
# CI pipeline example
./enhanced-setup-and-test.sh
```

This will:
1. Set up Vault and plugin
2. Run all test suites
3. Generate comprehensive report
4. Clean up resources

## Production Validation

Before production deployment:

1. **Run Complete Test Suite**
   ```bash
   ./enhanced-setup-and-test.sh
   ```

2. **Verify All Tests Pass**
   - Comprehensive tests: ✅ PASSED
   - Security tests: ✅ PASSED
   - Performance tests: ✅ PASSED

3. **Check Performance Metrics**
   - Response times within thresholds
   - Memory usage stable
   - Concurrent handling working

4. **Validate Security Controls**
   - Input validation working
   - Authentication secure
   - Authorization functioning
   - Error handling safe

## Test Coverage

The test suites provide comprehensive coverage:

- **Functionality**: 100% of plugin features tested
- **Security**: All security controls validated
- **Performance**: Response times and load handling tested
- **Error Handling**: Error scenarios and recovery tested
- **Integration**: Plugin-Vault integration validated

## Contributing

When adding new features:

1. **Add Unit Tests**: Test individual components
2. **Add Integration Tests**: Test feature integration
3. **Add Security Tests**: Validate security controls
4. **Add Performance Tests**: Measure performance impact
5. **Update Documentation**: Update this testing guide

## Support

For testing issues:

1. Check this documentation
2. Review test output and logs
3. Verify Vault and plugin status
4. Check test data availability
5. Contact the development team
