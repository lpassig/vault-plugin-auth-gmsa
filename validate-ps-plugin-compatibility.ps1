# =============================================================================
# PowerShell Script and Go Plugin Compatibility Validation
# =============================================================================
# This script validates that the PowerShell client script will work correctly
# with the developed Go plugin implementation by testing:
# 1. API endpoint compatibility
# 2. Request/response format compatibility
# 3. Authentication flow compatibility
# 4. Error handling compatibility
# 5. Configuration compatibility
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.example.com:8200",
    [string]$TestRole = "vault-gmsa-role",
    [string]$TestSPN = "HTTP/vault.local.lab",
    [switch]$Verbose = $false
)

# =============================================================================
# Configuration and Logging Setup
# =============================================================================

$ConfigOutputDir = "C:\vault-client\config"
$LogFile = "$ConfigOutputDir\compatibility-test.log"

# Create output directory
try {
    if (-not (Test-Path $ConfigOutputDir)) {
        New-Item -ItemType Directory -Path $ConfigOutputDir -Force | Out-Null
        Write-Host "Created config directory: $ConfigOutputDir" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to create config directory: $($_.Exception.Message)" -ForegroundColor Red
    $ConfigOutputDir = "."
    $LogFile = "$ConfigOutputDir\compatibility-test.log"
}

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } elseif ($Level -eq "WARNING") { "Yellow" } elseif ($Level -eq "SUCCESS") { "Green" } else { "White" })
    
    # Also write to log file
    try {
        Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# =============================================================================
# Test Results Tracking
# =============================================================================

$TestResults = @{
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    Warnings = 0
    TestDetails = @()
}

function Add-TestResult {
    param(
        [string]$TestName,
        [string]$Status,
        [string]$Message,
        [string]$Details = ""
    )
    
    $TestResults.TotalTests++
    if ($Status -eq "PASS") {
        $TestResults.PassedTests++
        Write-Log "✅ $TestName: PASS - $Message" -Level "SUCCESS"
    } elseif ($Status -eq "FAIL") {
        $TestResults.FailedTests++
        Write-Log "❌ $TestName: FAIL - $Message" -Level "ERROR"
    } elseif ($Status -eq "WARN") {
        $TestResults.Warnings++
        Write-Log "⚠️  $TestName: WARN - $Message" -Level "WARNING"
    }
    
    $TestResults.TestDetails += @{
        Name = $TestName
        Status = $Status
        Message = $Message
        Details = $Details
        Timestamp = Get-Date
    }
}

# =============================================================================
# API Endpoint Compatibility Tests
# =============================================================================

function Test-APIEndpointCompatibility {
    Write-Log "=== Testing API Endpoint Compatibility ===" -Level "INFO"
    
    # Test 1: Login endpoint format
    $loginEndpoint = "$VaultUrl/v1/auth/gmsa/login"
    try {
        $request = [System.Net.WebRequest]::Create($loginEndpoint)
        $request.Method = "POST"
        $request.ContentType = "application/json"
        $request.UserAgent = "Vault-gMSA-Client/1.0"
        
        # Test with minimal valid payload
        $testPayload = @{
            role = $TestRole
            spnego = "dGVzdF90b2tlbg=="  # base64 encoded "test_token"
        } | ConvertTo-Json
        
        $requestBody = [System.Text.Encoding]::UTF8.GetBytes($testPayload)
        $request.ContentLength = $requestBody.Length
        
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($requestBody, 0, $requestBody.Length)
        $requestStream.Close()
        
        try {
            $response = $request.GetResponse()
            $response.Close()
            Add-TestResult -TestName "Login Endpoint Format" -Status "PASS" -Message "Endpoint accepts POST requests with JSON payload"
        } catch {
            $statusCode = $_.Exception.Response.StatusCode
            if ($statusCode -eq 400 -or $statusCode -eq 401 -or $statusCode -eq 403) {
                Add-TestResult -TestName "Login Endpoint Format" -Status "PASS" -Message "Endpoint accepts requests and returns expected error codes"
            } else {
                Add-TestResult -TestName "Login Endpoint Format" -Status "FAIL" -Message "Unexpected response: $statusCode"
            }
        }
    } catch {
        Add-TestResult -TestName "Login Endpoint Format" -Status "FAIL" -Message "Failed to connect to login endpoint: $($_.Exception.Message)"
    }
    
    # Test 2: Health endpoint
    $healthEndpoint = "$VaultUrl/v1/auth/gmsa/health"
    try {
        $request = [System.Net.WebRequest]::Create($healthEndpoint)
        $request.Method = "GET"
        $request.UserAgent = "Vault-gMSA-Client/1.0"
        
        try {
            $response = $request.GetResponse()
            $response.Close()
            Add-TestResult -TestName "Health Endpoint" -Status "PASS" -Message "Health endpoint is accessible"
        } catch {
            $statusCode = $_.Exception.Response.StatusCode
            if ($statusCode -eq 401 -or $statusCode -eq 403) {
                Add-TestResult -TestName "Health Endpoint" -Status "PASS" -Message "Health endpoint requires authentication (expected)"
            } else {
                Add-TestResult -TestName "Health Endpoint" -Status "WARN" -Message "Unexpected response: $statusCode"
            }
        }
    } catch {
        Add-TestResult -TestName "Health Endpoint" -Status "WARN" -Message "Health endpoint not accessible: $($_.Exception.Message)"
    }
}

# =============================================================================
# Request/Response Format Compatibility Tests
# =============================================================================

function Test-RequestResponseFormatCompatibility {
    Write-Log "=== Testing Request/Response Format Compatibility ===" -Level "INFO"
    
    # Test 1: Required fields validation
    $loginEndpoint = "$VaultUrl/v1/auth/gmsa/login"
    
    # Test missing role field
    try {
        $testPayload = @{
            spnego = "dGVzdF90b2tlbg=="
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $testPayload -ContentType "application/json" -ErrorAction Stop
        Add-TestResult -TestName "Missing Role Field" -Status "FAIL" -Message "Should reject requests without role field"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Add-TestResult -TestName "Missing Role Field" -Status "PASS" -Message "Correctly rejects requests without role field"
        } else {
            Add-TestResult -TestName "Missing Role Field" -Status "WARN" -Message "Unexpected error for missing role: $($_.Exception.Response.StatusCode)"
        }
    }
    
    # Test missing spnego field
    try {
        $testPayload = @{
            role = $TestRole
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $testPayload -ContentType "application/json" -ErrorAction Stop
        Add-TestResult -TestName "Missing SPNEGO Field" -Status "FAIL" -Message "Should reject requests without spnego field"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Add-TestResult -TestName "Missing SPNEGO Field" -Status "PASS" -Message "Correctly rejects requests without spnego field"
        } else {
            Add-TestResult -TestName "Missing SPNEGO Field" -Status "WARN" -Message "Unexpected error for missing spnego: $($_.Exception.Response.StatusCode)"
        }
    }
    
    # Test invalid base64 encoding
    try {
        $testPayload = @{
            role = $TestRole
            spnego = "invalid_base64_encoding"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $testPayload -ContentType "application/json" -ErrorAction Stop
        Add-TestResult -TestName "Invalid Base64 Encoding" -Status "FAIL" -Message "Should reject invalid base64 encoding"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Add-TestResult -TestName "Invalid Base64 Encoding" -Status "PASS" -Message "Correctly rejects invalid base64 encoding"
        } else {
            Add-TestResult -TestName "Invalid Base64 Encoding" -Status "WARN" -Message "Unexpected error for invalid base64: $($_.Exception.Response.StatusCode)"
        }
    }
    
    # Test channel binding field (optional)
    try {
        $testPayload = @{
            role = $TestRole
            spnego = "dGVzdF90b2tlbg=="
            cb_tlse = "test_channel_binding"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $testPayload -ContentType "application/json" -ErrorAction Stop
        Add-TestResult -TestName "Channel Binding Field" -Status "FAIL" -Message "Should reject invalid SPNEGO tokens"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400 -or $_.Exception.Response.StatusCode -eq 401) {
            Add-TestResult -TestName "Channel Binding Field" -Status "PASS" -Message "Accepts channel binding field and processes request"
        } else {
            Add-TestResult -TestName "Channel Binding Field" -Status "WARN" -Message "Unexpected error with channel binding: $($_.Exception.Response.StatusCode)"
        }
    }
}

# =============================================================================
# Authentication Flow Compatibility Tests
# =============================================================================

function Test-AuthenticationFlowCompatibility {
    Write-Log "=== Testing Authentication Flow Compatibility ===" -Level "INFO"
    
    # Test 1: Simulated SPNEGO token format
    $loginEndpoint = "$VaultUrl/v1/auth/gmsa/login"
    
    # Generate a simulated SPNEGO token (as the PowerShell script does)
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $tokenData = "KERBEROS_TOKEN_FOR_$TestSPN_$timestamp"
    $spnegoToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($tokenData))
    
    try {
        $testPayload = @{
            role = $TestRole
            spnego = $spnegoToken
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $testPayload -ContentType "application/json" -ErrorAction Stop
        Add-TestResult -TestName "Simulated SPNEGO Token" -Status "FAIL" -Message "Should reject simulated SPNEGO tokens"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Add-TestResult -TestName "Simulated SPNEGO Token" -Status "PASS" -Message "Correctly rejects simulated SPNEGO tokens"
        } else {
            Add-TestResult -TestName "Simulated SPNEGO Token" -Status "WARN" -Message "Unexpected error for simulated token: $($_.Exception.Response.StatusCode)"
        }
    }
    
    # Test 2: Empty SPNEGO token
    try {
        $testPayload = @{
            role = $TestRole
            spnego = ""
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $testPayload -ContentType "application/json" -ErrorAction Stop
        Add-TestResult -TestName "Empty SPNEGO Token" -Status "FAIL" -Message "Should reject empty SPNEGO tokens"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Add-TestResult -TestName "Empty SPNEGO Token" -Status "PASS" -Message "Correctly rejects empty SPNEGO tokens"
        } else {
            Add-TestResult -TestName "Empty SPNEGO Token" -Status "WARN" -Message "Unexpected error for empty token: $($_.Exception.Response.StatusCode)"
        }
    }
    
    # Test 3: Invalid role name
    try {
        $testPayload = @{
            role = "nonexistent-role"
            spnego = "dGVzdF90b2tlbg=="
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $testPayload -ContentType "application/json" -ErrorAction Stop
        Add-TestResult -TestName "Invalid Role Name" -Status "FAIL" -Message "Should reject invalid role names"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Add-TestResult -TestName "Invalid Role Name" -Status "PASS" -Message "Correctly rejects invalid role names"
        } else {
            Add-TestResult -TestName "Invalid Role Name" -Status "WARN" -Message "Unexpected error for invalid role: $($_.Exception.Response.StatusCode)"
        }
    }
}

# =============================================================================
# Error Handling Compatibility Tests
# =============================================================================

function Test-ErrorHandlingCompatibility {
    Write-Log "=== Testing Error Handling Compatibility ===" -Level "INFO"
    
    # Test 1: Malformed JSON
    $loginEndpoint = "$VaultUrl/v1/auth/gmsa/login"
    
    try {
        $malformedJson = '{"role": "test-role", "spnego": "test-token"'  # Missing closing brace
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $malformedJson -ContentType "application/json" -ErrorAction Stop
        Add-TestResult -TestName "Malformed JSON" -Status "FAIL" -Message "Should reject malformed JSON"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Add-TestResult -TestName "Malformed JSON" -Status "PASS" -Message "Correctly rejects malformed JSON"
        } else {
            Add-TestResult -TestName "Malformed JSON" -Status "WARN" -Message "Unexpected error for malformed JSON: $($_.Exception.Response.StatusCode)"
        }
    }
    
    # Test 2: Wrong content type
    try {
        $testPayload = @{
            role = $TestRole
            spnego = "dGVzdF90b2tlbg=="
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $testPayload -ContentType "text/plain" -ErrorAction Stop
        Add-TestResult -TestName "Wrong Content Type" -Status "FAIL" -Message "Should reject wrong content type"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400 -or $_.Exception.Response.StatusCode -eq 415) {
            Add-TestResult -TestName "Wrong Content Type" -Status "PASS" -Message "Correctly rejects wrong content type"
        } else {
            Add-TestResult -TestName "Wrong Content Type" -Status "WARN" -Message "Unexpected error for wrong content type: $($_.Exception.Response.StatusCode)"
        }
    }
    
    # Test 3: Large payload
    try {
        $largeToken = "A" * 65536  # 64KB token
        $largeTokenB64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($largeToken))
        
        $testPayload = @{
            role = $TestRole
            spnego = $largeTokenB64
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $testPayload -ContentType "application/json" -ErrorAction Stop
        Add-TestResult -TestName "Large Payload" -Status "FAIL" -Message "Should reject large payloads"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400 -or $_.Exception.Response.StatusCode -eq 413) {
            Add-TestResult -TestName "Large Payload" -Status "PASS" -Message "Correctly rejects large payloads"
        } else {
            Add-TestResult -TestName "Large Payload" -Status "WARN" -Message "Unexpected error for large payload: $($_.Exception.Response.StatusCode)"
        }
    }
}

# =============================================================================
# Configuration Compatibility Tests
# =============================================================================

function Test-ConfigurationCompatibility {
    Write-Log "=== Testing Configuration Compatibility ===" -Level "INFO"
    
    # Test 1: Check if gMSA auth method is enabled
    try {
        $authListEndpoint = "$VaultUrl/v1/sys/auth"
        $response = Invoke-RestMethod -Method GET -Uri $authListEndpoint -ErrorAction Stop
        
        if ($response.data -and $response.data.gmsa) {
            Add-TestResult -TestName "gMSA Auth Method Enabled" -Status "PASS" -Message "gMSA authentication method is enabled"
        } else {
            Add-TestResult -TestName "gMSA Auth Method Enabled" -Status "FAIL" -Message "gMSA authentication method is not enabled"
        }
    } catch {
        Add-TestResult -TestName "gMSA Auth Method Enabled" -Status "WARN" -Message "Could not check auth methods: $($_.Exception.Message)"
    }
    
    # Test 2: Check gMSA configuration
    try {
        $configEndpoint = "$VaultUrl/v1/auth/gmsa/config"
        $response = Invoke-RestMethod -Method GET -Uri $configEndpoint -ErrorAction Stop
        
        if ($response.data) {
            Add-TestResult -TestName "gMSA Configuration" -Status "PASS" -Message "gMSA configuration is accessible"
            
            # Check required configuration fields
            $requiredFields = @("realm", "spn", "keytab")
            $missingFields = @()
            
            foreach ($field in $requiredFields) {
                if (-not $response.data.$field) {
                    $missingFields += $field
                }
            }
            
            if ($missingFields.Count -eq 0) {
                Add-TestResult -TestName "Required Config Fields" -Status "PASS" -Message "All required configuration fields are present"
            } else {
                Add-TestResult -TestName "Required Config Fields" -Status "WARN" -Message "Missing required fields: $($missingFields -join ', ')"
            }
        } else {
            Add-TestResult -TestName "gMSA Configuration" -Status "FAIL" -Message "gMSA configuration is not accessible"
        }
    } catch {
        Add-TestResult -TestName "gMSA Configuration" -Status "WARN" -Message "Could not check gMSA configuration: $($_.Exception.Message)"
    }
    
    # Test 3: Check role configuration
    try {
        $roleEndpoint = "$VaultUrl/v1/auth/gmsa/role/$TestRole"
        $response = Invoke-RestMethod -Method GET -Uri $roleEndpoint -ErrorAction Stop
        
        if ($response.data) {
            Add-TestResult -TestName "Role Configuration" -Status "PASS" -Message "Role '$TestRole' is configured"
            
            # Check required role fields
            $requiredRoleFields = @("name", "token_policies")
            $missingRoleFields = @()
            
            foreach ($field in $requiredRoleFields) {
                if (-not $response.data.$field) {
                    $missingRoleFields += $field
                }
            }
            
            if ($missingRoleFields.Count -eq 0) {
                Add-TestResult -TestName "Required Role Fields" -Status "PASS" -Message "All required role fields are present"
            } else {
                Add-TestResult -TestName "Required Role Fields" -Status "WARN" -Message "Missing required role fields: $($missingRoleFields -join ', ')"
            }
        } else {
            Add-TestResult -TestName "Role Configuration" -Status "FAIL" -Message "Role '$TestRole' is not configured"
        }
    } catch {
        Add-TestResult -TestName "Role Configuration" -Status "WARN" -Message "Could not check role configuration: $($_.Exception.Message)"
    }
}

# =============================================================================
# PowerShell Script Integration Tests
# =============================================================================

function Test-PowerShellScriptIntegration {
    Write-Log "=== Testing PowerShell Script Integration ===" -Level "INFO"
    
    # Test 1: Check if PowerShell script functions are available
    $scriptPath = "vault-client-app.ps1"
    if (Test-Path $scriptPath) {
        Add-TestResult -TestName "PowerShell Script Exists" -Status "PASS" -Message "PowerShell script file exists"
        
        # Test 2: Check script syntax
        try {
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $scriptPath -Raw), [ref]$null)
            Add-TestResult -TestName "PowerShell Script Syntax" -Status "PASS" -Message "PowerShell script has valid syntax"
        } catch {
            Add-TestResult -TestName "PowerShell Script Syntax" -Status "FAIL" -Message "PowerShell script has syntax errors: $($_.Exception.Message)"
        }
        
        # Test 3: Check required functions exist
        $requiredFunctions = @(
            "Get-SPNEGOToken",
            "Invoke-VaultAuthentication",
            "Get-VaultSecrets",
            "Write-Log"
        )
        
        $scriptContent = Get-Content $scriptPath -Raw
        $missingFunctions = @()
        
        foreach ($function in $requiredFunctions) {
            if ($scriptContent -notmatch "function $function") {
                $missingFunctions += $function
            }
        }
        
        if ($missingFunctions.Count -eq 0) {
            Add-TestResult -TestName "Required Functions" -Status "PASS" -Message "All required functions are present"
        } else {
            Add-TestResult -TestName "Required Functions" -Status "FAIL" -Message "Missing required functions: $($missingFunctions -join ', ')"
        }
        
    } else {
        Add-TestResult -TestName "PowerShell Script Exists" -Status "FAIL" -Message "PowerShell script file not found"
    }
}

# =============================================================================
# Main Execution
# =============================================================================

function Start-CompatibilityValidation {
    Write-Log "=== PowerShell Script and Go Plugin Compatibility Validation ===" -Level "INFO"
    Write-Log "Vault URL: $VaultUrl" -Level "INFO"
    Write-Log "Test Role: $TestRole" -Level "INFO"
    Write-Log "Test SPN: $TestSPN" -Level "INFO"
    Write-Log "Log File: $LogFile" -Level "INFO"
    Write-Log "" -Level "INFO"
    
    # Run all compatibility tests
    Test-APIEndpointCompatibility
    Test-RequestResponseFormatCompatibility
    Test-AuthenticationFlowCompatibility
    Test-ErrorHandlingCompatibility
    Test-ConfigurationCompatibility
    Test-PowerShellScriptIntegration
    
    # Generate summary report
    Write-Log "" -Level "INFO"
    Write-Log "=== Compatibility Validation Summary ===" -Level "INFO"
    Write-Log "Total Tests: $($TestResults.TotalTests)" -Level "INFO"
    Write-Log "Passed: $($TestResults.PassedTests)" -Level "SUCCESS"
    Write-Log "Failed: $($TestResults.FailedTests)" -Level "ERROR"
    Write-Log "Warnings: $($TestResults.Warnings)" -Level "WARNING"
    Write-Log "" -Level "INFO"
    
    # Calculate compatibility score
    $compatibilityScore = [Math]::Round(($TestResults.PassedTests / $TestResults.TotalTests) * 100, 2)
    Write-Log "Compatibility Score: $compatibilityScore%" -Level "INFO"
    
    if ($compatibilityScore -ge 90) {
        Write-Log "✅ EXCELLENT: PowerShell script and Go plugin are highly compatible" -Level "SUCCESS"
    } elseif ($compatibilityScore -ge 75) {
        Write-Log "✅ GOOD: PowerShell script and Go plugin are mostly compatible" -Level "SUCCESS"
    } elseif ($compatibilityScore -ge 50) {
        Write-Log "⚠️  FAIR: PowerShell script and Go plugin have some compatibility issues" -Level "WARNING"
    } else {
        Write-Log "❌ POOR: PowerShell script and Go plugin have significant compatibility issues" -Level "ERROR"
    }
    
    # Save detailed results
    $resultsFile = "$ConfigOutputDir\compatibility-results.json"
    $TestResults | ConvertTo-Json -Depth 3 | Out-File -FilePath $resultsFile -Encoding UTF8
    Write-Log "Detailed results saved to: $resultsFile" -Level "INFO"
    
    return $compatibilityScore
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Main execution
try {
    $score = Start-CompatibilityValidation
    
    if ($score -ge 75) {
        Write-Log "Compatibility validation completed successfully!" -Level "SUCCESS"
        exit 0
    } else {
        Write-Log "Compatibility validation found issues that need attention." -Level "WARNING"
        exit 1
    }
} catch {
    Write-Log "Compatibility validation failed: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}
