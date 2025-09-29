# =============================================================================
# gMSA Authentication Flow Validation Script
# =============================================================================
# This script validates the complete Windows Client → Linux Vault gMSA flow
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.example.com:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab",
    [switch]$Verbose = $false
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
        default { "White" }
    }
    
    Write-Host $logMessage -ForegroundColor $color
}

function Test-Environment {
    Write-ValidationLog "=== Environment Validation ===" -Level "INFO"
    
    # Test 1: Check if running under gMSA identity
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-ValidationLog "Current identity: $currentIdentity" -Level "INFO" -Test "ENV-001"
    
    if ($currentIdentity -like "*vault-gmsa$") {
        Write-ValidationLog "✓ Running under gMSA identity" -Level "SUCCESS" -Test "ENV-001"
    } else {
        Write-ValidationLog "✗ Not running under gMSA identity" -Level "ERROR" -Test "ENV-001"
        return $false
    }
    
    # Test 2: Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    Write-ValidationLog "PowerShell version: $psVersion" -Level "INFO" -Test "ENV-002"
    if ($psVersion.Major -ge 5) {
        Write-ValidationLog "✓ PowerShell version is compatible" -Level "SUCCESS" -Test "ENV-002"
    } else {
        Write-ValidationLog "✗ PowerShell version too old" -Level "ERROR" -Test "ENV-002"
        return $false
    }
    
    # Test 3: Check Active Directory module
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Write-ValidationLog "✓ Active Directory module available" -Level "SUCCESS" -Test "ENV-003"
    } else {
        Write-ValidationLog "✗ Active Directory module not available" -Level "WARNING" -Test "ENV-003"
    }
    
    return $true
}

function Test-SPNEGOTokenGeneration {
    Write-ValidationLog "=== SPNEGO Token Generation Validation ===" -Level "INFO"
    
    # Test 1: Check Kerberos tickets
    try {
        $klistOutput = klist 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-ValidationLog "✓ Kerberos tickets available" -Level "SUCCESS" -Test "SPNEGO-001"
            if ($Verbose) {
                Write-ValidationLog "Kerberos tickets: $klistOutput" -Level "INFO" -Test "SPNEGO-001"
            }
        } else {
            Write-ValidationLog "✗ No Kerberos tickets found" -Level "ERROR" -Test "SPNEGO-001"
            return $false
        }
    } catch {
        Write-ValidationLog "✗ Failed to check Kerberos tickets: $($_.Exception.Message)" -Level "ERROR" -Test "SPNEGO-001"
        return $false
    }
    
    # Test 2: Test SPNEGO token generation methods
    $spnegoMethods = @(
        @{ Name = "P/Invoke"; Function = "Get-SPNEGOTokenPInvoke" },
        @{ Name = "Windows Auth"; Function = "Get-SPNEGOTokenReal" },
        @{ Name = "SSPI"; Function = "Get-SPNEGOTokenSSPI" },
        @{ Name = "Kerberos"; Function = "Get-SPNEGOTokenKerberos" }
    )
    
    $successfulMethods = 0
    foreach ($method in $spnegoMethods) {
        try {
            Write-ValidationLog "Testing $($method.Name) method..." -Level "INFO" -Test "SPNEGO-002"
            
            # Check if function exists
            if (Get-Command $method.Function -ErrorAction SilentlyContinue) {
                Write-ValidationLog "✓ $($method.Name) function exists" -Level "SUCCESS" -Test "SPNEGO-002"
                $successfulMethods++
            } else {
                Write-ValidationLog "✗ $($method.Name) function not found" -Level "ERROR" -Test "SPNEGO-002"
            }
        } catch {
            Write-ValidationLog "✗ $($method.Name) method failed: $($_.Exception.Message)" -Level "ERROR" -Test "SPNEGO-002"
        }
    }
    
    if ($successfulMethods -gt 0) {
        Write-ValidationLog "✓ $successfulMethods SPNEGO methods available" -Level "SUCCESS" -Test "SPNEGO-002"
        return $true
    } else {
        Write-ValidationLog "✗ No SPNEGO methods available" -Level "ERROR" -Test "SPNEGO-002"
        return $false
    }
}

function Test-GMSACredentials {
    Write-ValidationLog "=== gMSA Credentials Validation ===" -Level "INFO"
    
    # Test 1: Check gMSA credential retrieval
    try {
        Write-ValidationLog "Testing gMSA credential retrieval..." -Level "INFO" -Test "GMSA-001"
        
        # Check if Get-GMSACredentials function exists
        if (Get-Command Get-GMSACredentials -ErrorAction SilentlyContinue) {
            Write-ValidationLog "✓ Get-GMSACredentials function exists" -Level "SUCCESS" -Test "GMSA-001"
            
            # Test the function
            $gmsaCredentials = Get-GMSACredentials
            if ($gmsaCredentials) {
                Write-ValidationLog "✓ gMSA credentials retrieved successfully" -Level "SUCCESS" -Test "GMSA-001"
                Write-ValidationLog "gMSA Name: $($gmsaCredentials.gmsa_name)" -Level "INFO" -Test "GMSA-001"
                Write-ValidationLog "Method: $($gmsaCredentials.method)" -Level "INFO" -Test "GMSA-001"
                
                if ($gmsaCredentials.ntlm_hash) {
                    Write-ValidationLog "✓ NTLM hash available" -Level "SUCCESS" -Test "GMSA-001"
                    if ($Verbose) {
                        Write-ValidationLog "NTLM Hash: $($gmsaCredentials.ntlm_hash.Substring(0, 8))..." -Level "INFO" -Test "GMSA-001"
                    }
                } else {
                    Write-ValidationLog "⚠ NTLM hash not available" -Level "WARNING" -Test "GMSA-001"
                }
            } else {
                Write-ValidationLog "✗ Failed to retrieve gMSA credentials" -Level "ERROR" -Test "GMSA-001"
                return $false
            }
        } else {
            Write-ValidationLog "✗ Get-GMSACredentials function not found" -Level "ERROR" -Test "GMSA-001"
            return $false
        }
    } catch {
        Write-ValidationLog "✗ gMSA credential test failed: $($_.Exception.Message)" -Level "ERROR" -Test "GMSA-001"
        return $false
    }
    
    return $true
}

function Test-VaultConnectivity {
    Write-ValidationLog "=== Vault Connectivity Validation ===" -Level "INFO"
    
    # Test 1: Check Vault URL format
    if ($VaultUrl -match "^https?://") {
        Write-ValidationLog "✓ Vault URL format is valid" -Level "SUCCESS" -Test "VAULT-001"
    } else {
        Write-ValidationLog "✗ Vault URL format is invalid" -Level "ERROR" -Test "VAULT-001"
        return $false
    }
    
    # Test 2: Test Vault health endpoint
    try {
        Write-ValidationLog "Testing Vault health endpoint..." -Level "INFO" -Test "VAULT-002"
        
        $healthUrl = "$VaultUrl/v1/sys/health"
        $response = Invoke-RestMethod -Uri $healthUrl -Method GET -TimeoutSec 10
        
        Write-ValidationLog "✓ Vault health endpoint accessible" -Level "SUCCESS" -Test "VAULT-002"
        if ($Verbose) {
            Write-ValidationLog "Vault health response: $($response | ConvertTo-Json -Compress)" -Level "INFO" -Test "VAULT-002"
        }
    } catch {
        Write-ValidationLog "✗ Vault health endpoint not accessible: $($_.Exception.Message)" -Level "ERROR" -Test "VAULT-002"
        return $false
    }
    
    # Test 3: Test gMSA auth endpoint
    try {
        Write-ValidationLog "Testing gMSA auth endpoint..." -Level "INFO" -Test "VAULT-003"
        
        $authUrl = "$VaultUrl/v1/auth/gmsa/health"
        $response = Invoke-RestMethod -Uri $authUrl -Method GET -TimeoutSec 10
        
        Write-ValidationLog "✓ gMSA auth endpoint accessible" -Level "SUCCESS" -Test "VAULT-003"
    } catch {
        Write-ValidationLog "⚠ gMSA auth endpoint not accessible: $($_.Exception.Message)" -Level "WARNING" -Test "VAULT-003"
        # This is expected if the gMSA auth method is not enabled
    }
    
    return $true
}

function Test-AuthenticationFlow {
    Write-ValidationLog "=== Authentication Flow Validation ===" -Level "INFO"
    
    # Test 1: Check authentication functions
    $authFunctions = @(
        @{ Name = "Invoke-VaultAuthentication"; Description = "Main Vault authentication" },
        @{ Name = "Invoke-GMSAAuthentication"; Description = "gMSA authentication" },
        @{ Name = "Invoke-LDAPAuthenticationWithNTLM"; Description = "LDAP with NTLM hash" }
    )
    
    $availableFunctions = 0
    foreach ($func in $authFunctions) {
        if (Get-Command $func.Name -ErrorAction SilentlyContinue) {
            Write-ValidationLog "✓ $($func.Description) function available" -Level "SUCCESS" -Test "AUTH-001"
            $availableFunctions++
        } else {
            Write-ValidationLog "✗ $($func.Description) function not found" -Level "ERROR" -Test "AUTH-001"
        }
    }
    
    if ($availableFunctions -eq $authFunctions.Count) {
        Write-ValidationLog "✓ All authentication functions available" -Level "SUCCESS" -Test "AUTH-001"
        return $true
    } else {
        Write-ValidationLog "✗ Some authentication functions missing" -Level "ERROR" -Test "AUTH-001"
        return $false
    }
}

function Test-SecretRetrieval {
    Write-ValidationLog "=== Secret Retrieval Validation ===" -Level "INFO"
    
    # Test 1: Check secret retrieval functions
    $secretFunctions = @(
        @{ Name = "Get-VaultSecret"; Description = "Vault secret retrieval" },
        @{ Name = "Save-ApplicationConfig"; Description = "Application configuration" }
    )
    
    $availableFunctions = 0
    foreach ($func in $secretFunctions) {
        if (Get-Command $func.Name -ErrorAction SilentlyContinue) {
            Write-ValidationLog "✓ $($func.Description) function available" -Level "SUCCESS" -Test "SECRET-001"
            $availableFunctions++
        } else {
            Write-ValidationLog "✗ $($func.Description) function not found" -Level "ERROR" -Test "SECRET-001"
        }
    }
    
    if ($availableFunctions -eq $secretFunctions.Count) {
        Write-ValidationLog "✓ All secret retrieval functions available" -Level "SUCCESS" -Test "SECRET-001"
        return $true
    } else {
        Write-ValidationLog "✗ Some secret retrieval functions missing" -Level "ERROR" -Test "SECRET-001"
        return $false
    }
}

# =============================================================================
# Main Validation Logic
# =============================================================================

function Start-Validation {
    Write-ValidationLog "=== gMSA Authentication Flow Validation ===" -Level "INFO"
    Write-ValidationLog "Vault URL: $VaultUrl" -Level "INFO"
    Write-ValidationLog "Vault Role: $VaultRole" -Level "INFO"
    Write-ValidationLog "SPN: $SPN" -Level "INFO"
    Write-ValidationLog "" -Level "INFO"
    
    $tests = @(
        @{ Name = "Environment"; Function = "Test-Environment" },
        @{ Name = "SPNEGO Token Generation"; Function = "Test-SPNEGOTokenGeneration" },
        @{ Name = "gMSA Credentials"; Function = "Test-GMSACredentials" },
        @{ Name = "Vault Connectivity"; Function = "Test-VaultConnectivity" },
        @{ Name = "Authentication Flow"; Function = "Test-AuthenticationFlow" },
        @{ Name = "Secret Retrieval"; Function = "Test-SecretRetrieval" }
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
    Write-ValidationLog "=== Validation Summary ===" -Level "INFO"
    Write-ValidationLog "Passed: $passedTests/$totalTests tests" -Level "INFO"
    
    if ($passedTests -eq $totalTests) {
        Write-ValidationLog "✓ All validations passed! gMSA authentication flow is ready." -Level "SUCCESS"
        return $true
    } else {
        Write-ValidationLog "✗ Some validations failed. Please review the issues above." -Level "ERROR"
        return $false
    }
}

# =============================================================================
# Script Execution
# =============================================================================

# Load the main script functions
try {
    Write-ValidationLog "Loading main script functions..." -Level "INFO"
    . .\vault-client-app.ps1 -WhatIf
    Write-ValidationLog "✓ Main script functions loaded" -Level "SUCCESS"
} catch {
    Write-ValidationLog "✗ Failed to load main script functions: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Run validation
if (Start-Validation) {
    Write-ValidationLog "Validation completed successfully!" -Level "SUCCESS"
    exit 0
} else {
    Write-ValidationLog "Validation failed!" -Level "ERROR"
    exit 1
}
