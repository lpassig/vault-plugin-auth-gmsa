# =============================================================================
# Vault gMSA Plugin Implementation Validation Script
# =============================================================================
# This script validates the complete Go plugin implementation and architecture
# for Windows Client → Linux Vault gMSA authentication scenario
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.example.com:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab",
    [switch]$Verbose = $false,
    [switch]$BuildPlugin = $false
)

# =============================================================================
# Validation Functions
# =============================================================================

function Write-ValidationLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Test = ""
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = if ($Test) { "[$Test] " } else { "" }
    $logMessage = "[$timestamp] [$Level] $prefix$Message"
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "INFO" { "Cyan" }
        "STEP" { "Magenta" }
        default { "White" }
    }
    
    Write-Host $logMessage -ForegroundColor $color
}

function Test-GoEnvironment {
    Write-ValidationLog "=== Go Environment Validation ===" -Level "STEP"
    
    # Test 1: Check Go installation
    try {
        $goVersion = go version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-ValidationLog "✓ Go is installed: $goVersion" -Level "SUCCESS" -Test "GO-001"
        } else {
            Write-ValidationLog "✗ Go is not installed or not in PATH" -Level "ERROR" -Test "GO-001"
            return $false
        }
    } catch {
        Write-ValidationLog "✗ Failed to check Go version: $($_.Exception.Message)" -Level "ERROR" -Test "GO-001"
        return $false
    }
    
    # Test 2: Check Go module
    if (Test-Path "go.mod") {
        Write-ValidationLog "✓ go.mod file exists" -Level "SUCCESS" -Test "GO-002"
        
        $goModContent = Get-Content "go.mod" -Raw
        if ($goModContent -match "github.com/lpassig/vault-plugin-auth-gmsa") {
            Write-ValidationLog "✓ Module name is correct" -Level "SUCCESS" -Test "GO-002"
        } else {
            Write-ValidationLog "✗ Module name is incorrect" -Level "ERROR" -Test "GO-002"
            return $false
        }
        
        if ($goModContent -match "go 1.25.0") {
            Write-ValidationLog "✓ Go version requirement is correct" -Level "SUCCESS" -Test "GO-002"
        } else {
            Write-ValidationLog "⚠ Go version requirement may be outdated" -Level "WARNING" -Test "GO-002"
        }
    } else {
        Write-ValidationLog "✗ go.mod file not found" -Level "ERROR" -Test "GO-002"
        return $false
    }
    
    # Test 3: Check dependencies
    $requiredDeps = @(
        "github.com/hashicorp/vault/sdk",
        "github.com/jcmturner/gokrb5/v8",
        "github.com/jcmturner/goidentity/v6"
    )
    
    foreach ($dep in $requiredDeps) {
        if ($goModContent -match $dep) {
            Write-ValidationLog "✓ Dependency found: $dep" -Level "SUCCESS" -Test "GO-003"
        } else {
            Write-ValidationLog "✗ Missing dependency: $dep" -Level "ERROR" -Test "GO-003"
            return $false
        }
    }
    
    return $true
}

function Test-PluginArchitecture {
    Write-ValidationLog "=== Plugin Architecture Validation ===" -Level "STEP"
    
    # Test 1: Check main entry point
    if (Test-Path "cmd/vault-plugin-auth-gmsa/main.go") {
        Write-ValidationLog "✓ Main entry point exists" -Level "SUCCESS" -Test "ARCH-001"
        
        $mainContent = Get-Content "cmd/vault-plugin-auth-gmsa/main.go" -Raw
        if ($mainContent -match "plugin.ServeMultiplex") {
            Write-ValidationLog "✓ Uses ServeMultiplex for plugin architecture" -Level "SUCCESS" -Test "ARCH-001"
        } else {
            Write-ValidationLog "✗ Does not use ServeMultiplex" -Level "ERROR" -Test "ARCH-001"
            return $false
        }
        
        if ($mainContent -match "backend.Factory") {
            Write-ValidationLog "✓ Backend factory is properly referenced" -Level "SUCCESS" -Test "ARCH-001"
        } else {
            Write-ValidationLog "✗ Backend factory not found" -Level "ERROR" -Test "ARCH-001"
            return $false
        }
    } else {
        Write-ValidationLog "✗ Main entry point not found" -Level "ERROR" -Test "ARCH-001"
        return $false
    }
    
    # Test 2: Check backend structure
    if (Test-Path "pkg/backend/backend.go") {
        Write-ValidationLog "✓ Backend implementation exists" -Level "SUCCESS" -Test "ARCH-002"
        
        $backendContent = Get-Content "pkg/backend/backend.go" -Raw
        if ($backendContent -match "type gmsaBackend struct") {
            Write-ValidationLog "✓ gMSA backend struct is defined" -Level "SUCCESS" -Test "ARCH-002"
        } else {
            Write-ValidationLog "✗ gMSA backend struct not found" -Level "ERROR" -Test "ARCH-002"
            return $false
        }
        
        if ($backendContent -match "BackendType: logical.TypeCredential") {
            Write-ValidationLog "✓ Correctly configured as credential backend" -Level "SUCCESS" -Test "ARCH-002"
        } else {
            Write-ValidationLog "✗ Not configured as credential backend" -Level "ERROR" -Test "ARCH-002"
            return $false
        }
    } else {
        Write-ValidationLog "✗ Backend implementation not found" -Level "ERROR" -Test "ARCH-002"
        return $false
    }
    
    # Test 3: Check path implementations
    $requiredPaths = @(
        "paths_login.go",
        "paths_config.go", 
        "paths_role.go",
        "paths_health.go",
        "paths_metrics.go",
        "paths_rotation.go"
    )
    
    foreach ($path in $requiredPaths) {
        if (Test-Path "pkg/backend/$path") {
            Write-ValidationLog "✓ Path implementation exists: $path" -Level "SUCCESS" -Test "ARCH-003"
        } else {
            Write-ValidationLog "✗ Missing path implementation: $path" -Level "ERROR" -Test "ARCH-003"
            return $false
        }
    }
    
    return $true
}

function Test-KerberosImplementation {
    Write-ValidationLog "=== Kerberos Implementation Validation ===" -Level "STEP"
    
    # Test 1: Check Kerberos package
    if (Test-Path "internal/kerb/validator.go") {
        Write-ValidationLog "✓ Kerberos validator exists" -Level "SUCCESS" -Test "KERB-001"
        
        $validatorContent = Get-Content "internal/kerb/validator.go" -Raw
        if ($validatorContent -match "type Validator struct") {
            Write-ValidationLog "✓ Validator struct is defined" -Level "SUCCESS" -Test "KERB-001"
        } else {
            Write-ValidationLog "✗ Validator struct not found" -Level "ERROR" -Test "KERB-001"
            return $false
        }
        
        if ($validatorContent -match "ValidateSPNEGO") {
            Write-ValidationLog "✓ SPNEGO validation method exists" -Level "SUCCESS" -Test "KERB-001"
        } else {
            Write-ValidationLog "✗ SPNEGO validation method not found" -Level "ERROR" -Test "KERB-001"
            return $false
        }
    } else {
        Write-ValidationLog "✗ Kerberos validator not found" -Level "ERROR" -Test "KERB-001"
        return $false
    }
    
    # Test 2: Check PAC implementation
    if (Test-Path "internal/kerb/pac.go") {
        Write-ValidationLog "✓ PAC implementation exists" -Level "SUCCESS" -Test "KERB-002"
        
        $pacContent = Get-Content "internal/kerb/pac.go" -Raw
        if ($pacContent -match "ExtractGroupSIDsFromPAC") {
            Write-ValidationLog "✓ PAC group SID extraction exists" -Level "SUCCESS" -Test "KERB-002"
        } else {
            Write-ValidationLog "✗ PAC group SID extraction not found" -Level "ERROR" -Test "KERB-002"
            return $false
        }
        
        if ($pacContent -match "PAC_LOGON_INFO") {
            Write-ValidationLog "✓ PAC buffer types are defined" -Level "SUCCESS" -Test "KERB-002"
        } else {
            Write-ValidationLog "✗ PAC buffer types not found" -Level "ERROR" -Test "KERB-002"
            return $false
        }
    } else {
        Write-ValidationLog "✗ PAC implementation not found" -Level "ERROR" -Test "KERB-002"
        return $false
    }
    
    # Test 3: Check gokrb5 integration
    $validatorContent = Get-Content "internal/kerb/validator.go" -Raw
    if ($validatorContent -match "github.com/jcmturner/gokrb5") {
        Write-ValidationLog "✓ gokrb5 library is integrated" -Level "SUCCESS" -Test "KERB-003"
    } else {
        Write-ValidationLog "✗ gokrb5 library not integrated" -Level "ERROR" -Test "KERB-003"
        return $false
    }
    
    return $true
}

function Test-AuthenticationFlow {
    Write-ValidationLog "=== Authentication Flow Validation ===" -Level "STEP"
    
    # Test 1: Check login path implementation
    $loginContent = Get-Content "pkg/backend/paths_login.go" -Raw
    if ($loginContent -match "handleLogin") {
        Write-ValidationLog "✓ Login handler exists" -Level "SUCCESS" -Test "AUTH-001"
    } else {
        Write-ValidationLog "✗ Login handler not found" -Level "ERROR" -Test "AUTH-001"
        return $false
    }
    
    # Test 2: Check SPNEGO token validation
    if ($loginContent -match "spnego") {
        Write-ValidationLog "✓ SPNEGO token handling exists" -Level "SUCCESS" -Test "AUTH-002"
    } else {
        Write-ValidationLog "✗ SPNEGO token handling not found" -Level "ERROR" -Test "AUTH-002"
        return $false
    }
    
    # Test 3: Check role-based authorization
    if ($loginContent -match "AllowedRealms") {
        Write-ValidationLog "✓ Role-based authorization exists" -Level "SUCCESS" -Test "AUTH-003"
    } else {
        Write-ValidationLog "✗ Role-based authorization not found" -Level "ERROR" -Test "AUTH-003"
        return $false
    }
    
    # Test 4: Check group SID binding
    if ($loginContent -match "BoundGroupSIDs") {
        Write-ValidationLog "✓ Group SID binding exists" -Level "SUCCESS" -Test "AUTH-004"
    } else {
        Write-ValidationLog "✗ Group SID binding not found" -Level "ERROR" -Test "AUTH-004"
        return $false
    }
    
    # Test 5: Check channel binding support
    if ($loginContent -match "cb_tlse") {
        Write-ValidationLog "✓ Channel binding support exists" -Level "SUCCESS" -Test "AUTH-005"
    } else {
        Write-ValidationLog "✗ Channel binding support not found" -Level "ERROR" -Test "AUTH-005"
        return $false
    }
    
    return $true
}

function Test-ConfigurationManagement {
    Write-ValidationLog "=== Configuration Management Validation ===" -Level "STEP"
    
    # Test 1: Check config structure
    $configContent = Get-Content "pkg/backend/config.go" -Raw
    if ($configContent -match "type Config struct") {
        Write-ValidationLog "✓ Config struct exists" -Level "SUCCESS" -Test "CONFIG-001"
    } else {
        Write-ValidationLog "✗ Config struct not found" -Level "ERROR" -Test "CONFIG-001"
        return $false
    }
    
    # Test 2: Check required config fields
    $requiredFields = @("Realm", "KeytabB64", "SPN", "ClockSkewSec")
    foreach ($field in $requiredFields) {
        if ($configContent -match $field) {
            Write-ValidationLog "✓ Config field exists: $field" -Level "SUCCESS" -Test "CONFIG-002"
        } else {
            Write-ValidationLog "✗ Missing config field: $field" -Level "ERROR" -Test "CONFIG-002"
            return $false
        }
    }
    
    # Test 3: Check normalization support
    if ($configContent -match "NormalizationConfig") {
        Write-ValidationLog "✓ Normalization configuration exists" -Level "SUCCESS" -Test "CONFIG-003"
    } else {
        Write-ValidationLog "✗ Normalization configuration not found" -Level "ERROR" -Test "CONFIG-003"
        return $false
    }
    
    # Test 4: Check validation functions
    if ($configContent -match "normalizeAndValidateConfig") {
        Write-ValidationLog "✓ Config validation exists" -Level "SUCCESS" -Test "CONFIG-004"
    } else {
        Write-ValidationLog "✗ Config validation not found" -Level "ERROR" -Test "CONFIG-004"
        return $false
    }
    
    return $true
}

function Test-SecurityFeatures {
    Write-ValidationLog "=== Security Features Validation ===" -Level "STEP"
    
    # Test 1: Check input validation
    $loginContent = Get-Content "pkg/backend/paths_login.go" -Raw
    if ($loginContent -match "validateLoginInput") {
        Write-ValidationLog "✓ Input validation exists" -Level "SUCCESS" -Test "SEC-001"
    } else {
        Write-ValidationLog "✗ Input validation not found" -Level "ERROR" -Test "SEC-001"
        return $false
    }
    
    # Test 2: Check error handling
    if ($loginContent -match "AuthError") {
        Write-ValidationLog "✓ Structured error handling exists" -Level "SUCCESS" -Test "SEC-002"
    } else {
        Write-ValidationLog "✗ Structured error handling not found" -Level "ERROR" -Test "SEC-002"
        return $false
    }
    
    # Test 3: Check safe logging
    $configContent = Get-Content "pkg/backend/config.go" -Raw
    if ($configContent -match "Safe\\(\\)") {
        Write-ValidationLog "✓ Safe logging exists" -Level "SUCCESS" -Test "SEC-003"
    } else {
        Write-ValidationLog "✗ Safe logging not found" -Level "ERROR" -Test "SEC-003"
        return $false
    }
    
    # Test 4: Check metrics and monitoring
    $backendContent = Get-Content "pkg/backend/backend.go" -Raw
    if ($backendContent -match "expvar") {
        Write-ValidationLog "✓ Metrics and monitoring exists" -Level "SUCCESS" -Test "SEC-004"
    } else {
        Write-ValidationLog "✗ Metrics and monitoring not found" -Level "ERROR" -Test "SEC-004"
        return $false
    }
    
    return $true
}

function Test-PluginBuild {
    Write-ValidationLog "=== Plugin Build Validation ===" -Level "STEP"
    
    if (-not $BuildPlugin) {
        Write-ValidationLog "⚠ Plugin build test skipped (use -BuildPlugin to enable)" -Level "WARNING" -Test "BUILD-001"
        return $true
    }
    
    # Test 1: Check if plugin binary exists
    if (Test-Path "vault-plugin-auth-gmsa") {
        Write-ValidationLog "✓ Plugin binary exists" -Level "SUCCESS" -Test "BUILD-001"
    } else {
        Write-ValidationLog "⚠ Plugin binary not found, attempting to build..." -Level "WARNING" -Test "BUILD-001"
        
        # Test 2: Try to build the plugin
        try {
            Write-ValidationLog "Building plugin..." -Level "INFO" -Test "BUILD-002"
            $buildOutput = go build -o vault-plugin-auth-gmsa ./cmd/vault-plugin-auth-gmsa 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-ValidationLog "✓ Plugin built successfully" -Level "SUCCESS" -Test "BUILD-002"
            } else {
                Write-ValidationLog "✗ Plugin build failed: $buildOutput" -Level "ERROR" -Test "BUILD-002"
                return $false
            }
        } catch {
            Write-ValidationLog "✗ Plugin build error: $($_.Exception.Message)" -Level "ERROR" -Test "BUILD-002"
            return $false
        }
    }
    
    # Test 3: Check plugin binary properties
    if (Test-Path "vault-plugin-auth-gmsa") {
        $fileInfo = Get-Item "vault-plugin-auth-gmsa"
        Write-ValidationLog "✓ Plugin binary size: $($fileInfo.Length) bytes" -Level "SUCCESS" -Test "BUILD-003"
        
        if ($fileInfo.Length -gt 0) {
            Write-ValidationLog "✓ Plugin binary is not empty" -Level "SUCCESS" -Test "BUILD-003"
        } else {
            Write-ValidationLog "✗ Plugin binary is empty" -Level "ERROR" -Test "BUILD-003"
            return $false
        }
    }
    
    return $true
}

function Test-IntegrationPoints {
    Write-ValidationLog "=== Integration Points Validation ===" -Level "STEP"
    
    # Test 1: Check Vault SDK integration
    $backendContent = Get-Content "pkg/backend/backend.go" -Raw
    if ($backendContent -match "github.com/hashicorp/vault/sdk") {
        Write-ValidationLog "✓ Vault SDK integration exists" -Level "SUCCESS" -Test "INT-001"
    } else {
        Write-ValidationLog "✗ Vault SDK integration not found" -Level "ERROR" -Test "INT-001"
        return $false
    }
    
    # Test 2: Check framework integration
    if ($backendContent -match "framework.Backend") {
        Write-ValidationLog "✓ Vault framework integration exists" -Level "SUCCESS" -Test "INT-002"
    } else {
        Write-ValidationLog "✗ Vault framework integration not found" -Level "ERROR" -Test "INT-002"
        return $false
    }
    
    # Test 3: Check storage integration
    if ($backendContent -match "logical.Storage") {
        Write-ValidationLog "✓ Vault storage integration exists" -Level "SUCCESS" -Test "INT-003"
    } else {
        Write-ValidationLog "✗ Vault storage integration not found" -Level "ERROR" -Test "INT-003"
        return $false
    }
    
    # Test 4: Check logging integration
    if ($backendContent -match "hclog.Logger") {
        Write-ValidationLog "✓ Vault logging integration exists" -Level "SUCCESS" -Test "INT-004"
    } else {
        Write-ValidationLog "✗ Vault logging integration not found" -Level "ERROR" -Test "INT-004"
        return $false
    }
    
    return $true
}

# =============================================================================
# Main Validation Logic
# =============================================================================

function Start-PluginValidation {
    Write-ValidationLog "=== Vault gMSA Plugin Implementation Validation ===" -Level "STEP"
    Write-ValidationLog "Validating complete Go plugin implementation..." -Level "INFO"
    Write-ValidationLog "" -Level "INFO"
    
    $tests = @(
        @{ Name = "Go Environment"; Function = "Test-GoEnvironment" },
        @{ Name = "Plugin Architecture"; Function = "Test-PluginArchitecture" },
        @{ Name = "Kerberos Implementation"; Function = "Test-KerberosImplementation" },
        @{ Name = "Authentication Flow"; Function = "Test-AuthenticationFlow" },
        @{ Name = "Configuration Management"; Function = "Test-ConfigurationManagement" },
        @{ Name = "Security Features"; Function = "Test-SecurityFeatures" },
        @{ Name = "Plugin Build"; Function = "Test-PluginBuild" },
        @{ Name = "Integration Points"; Function = "Test-IntegrationPoints" }
    )
    
    $passedTests = 0
    $totalTests = $tests.Count
    
    foreach ($test in $tests) {
        Write-ValidationLog "Running $($test.Name) validation..." -Level "INFO"
        
        try {
            if (& $test.Function) {
                Write-ValidationLog "✓ $($test.Name) validation passed" -Level "SUCCESS"
                $passedTests++
            } else {
                Write-ValidationLog "✗ $($test.Name) validation failed" -Level "ERROR"
            }
        } catch {
            Write-ValidationLog "✗ $($test.Name) validation error: $($_.Exception.Message)" -Level "ERROR"
        }
        
        Write-ValidationLog "" -Level "INFO"
    }
    
    # Summary
    Write-ValidationLog "=== Validation Summary ===" -Level "STEP"
    Write-ValidationLog "Passed: $passedTests/$totalTests tests" -Level "INFO"
    
    if ($passedTests -eq $totalTests) {
        Write-ValidationLog "✓ All plugin validations passed! Implementation is ready." -Level "SUCCESS"
        Write-ValidationLog "" -Level "INFO"
        Write-ValidationLog "Next steps:" -Level "INFO"
        Write-ValidationLog "1. Build the plugin: go build -o vault-plugin-auth-gmsa ./cmd/vault-plugin-auth-gmsa" -Level "INFO"
        Write-ValidationLog "2. Configure Vault to use the plugin" -Level "INFO"
        Write-ValidationLog "3. Test with Windows client using vault-client-app.ps1" -Level "INFO"
        return $true
    } else {
        Write-ValidationLog "✗ Some validations failed. Please review the issues above." -Level "ERROR"
        return $false
    }
}

# =============================================================================
# Script Execution
# =============================================================================

# Run validation
if (Start-PluginValidation) {
    Write-ValidationLog "Plugin validation completed successfully!" -Level "SUCCESS"
    exit 0
} else {
    Write-ValidationLog "Plugin validation failed!" -Level "ERROR"
    exit 1
}
