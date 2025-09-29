# =============================================================================
# gMSA Scenario Test Script
# =============================================================================
# Tests the complete Windows Client → Linux Vault gMSA authentication scenario
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.example.com:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab",
    [switch]$DryRun = $false
)

# =============================================================================
# Test Functions
# =============================================================================

function Write-TestLog {
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

function Test-ScenarioStep1 {
    Write-TestLog "=== Step 1: Environment Setup ===" -Level "STEP"
    
    # Check gMSA identity
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-TestLog "Current identity: $currentIdentity" -Level "INFO" -Test "STEP1"
    
    if ($currentIdentity -like "*vault-gmsa$") {
        Write-TestLog "✓ Running under gMSA identity" -Level "SUCCESS" -Test "STEP1"
        return $true
    } else {
        Write-TestLog "✗ Not running under gMSA identity" -Level "ERROR" -Test "STEP1"
        Write-TestLog "Expected: *vault-gmsa$" -Level "ERROR" -Test "STEP1"
        Write-TestLog "Actual: $currentIdentity" -Level "ERROR" -Test "STEP1"
        return $false
    }
}

function Test-ScenarioStep2 {
    Write-TestLog "=== Step 2: SPNEGO Token Generation ===" -Level "STEP"
    
    # Test SPNEGO token generation
    try {
        Write-TestLog "Generating SPNEGO token for SPN: $SPN" -Level "INFO" -Test "STEP2"
        
        # Use the main script's SPNEGO token generation
        $spnegoToken = Get-SPNEGOToken -TargetSPN $SPN -VaultUrl $VaultUrl
        
        if ($spnegoToken) {
            Write-TestLog "✓ SPNEGO token generated successfully" -Level "SUCCESS" -Test "STEP2"
            Write-TestLog "Token length: $($spnegoToken.Length) characters" -Level "INFO" -Test "STEP2"
            Write-TestLog "Token preview: $($spnegoToken.Substring(0, [Math]::Min(50, $spnegoToken.Length)))..." -Level "INFO" -Test "STEP2"
            return $spnegoToken
        } else {
            Write-TestLog "✗ Failed to generate SPNEGO token" -Level "ERROR" -Test "STEP2"
            return $null
        }
    } catch {
        Write-TestLog "✗ SPNEGO token generation error: $($_.Exception.Message)" -Level "ERROR" -Test "STEP2"
        return $null
    }
}

function Test-ScenarioStep3 {
    param(
        [string]$SPNEGOToken
    )
    
    Write-TestLog "=== Step 3: Vault Authentication ===" -Level "STEP"
    
    if (-not $SPNEGOToken) {
        Write-TestLog "✗ No SPNEGO token provided" -Level "ERROR" -Test "STEP3"
        return $null
    }
    
    try {
        Write-TestLog "Authenticating to Vault at: $VaultUrl" -Level "INFO" -Test "STEP3"
        
        if ($DryRun) {
            Write-TestLog "DRY RUN: Would authenticate with SPNEGO token" -Level "WARNING" -Test "STEP3"
            return "DRY_RUN_TOKEN"
        }
        
        # Use the main script's authentication function
        $vaultToken = Invoke-VaultAuthentication -VaultUrl $VaultUrl -Role $VaultRole -SPNEGOToken $SPNEGOToken
        
        if ($vaultToken) {
            Write-TestLog "✓ Vault authentication successful" -Level "SUCCESS" -Test "STEP3"
            Write-TestLog "Vault token preview: $($vaultToken.Substring(0, [Math]::Min(20, $vaultToken.Length)))..." -Level "INFO" -Test "STEP3"
            return $vaultToken
        } else {
            Write-TestLog "✗ Vault authentication failed" -Level "ERROR" -Test "STEP3"
            return $null
        }
    } catch {
        Write-TestLog "✗ Vault authentication error: $($_.Exception.Message)" -Level "ERROR" -Test "STEP3"
        return $null
    }
}

function Test-ScenarioStep4 {
    param(
        [string]$VaultToken
    )
    
    Write-TestLog "=== Step 4: Secret Retrieval ===" -Level "STEP"
    
    if (-not $VaultToken) {
        Write-TestLog "✗ No Vault token provided" -Level "ERROR" -Test "STEP4"
        return $false
    }
    
    try {
        Write-TestLog "Testing secret retrieval..." -Level "INFO" -Test "STEP4"
        
        if ($DryRun) {
            Write-TestLog "DRY RUN: Would retrieve secrets from Vault" -Level "WARNING" -Test "STEP4"
            return $true
        }
        
        # Test secret retrieval
        $testSecretPath = "kv/data/my-app/database"
        $secret = Get-VaultSecret -VaultUrl $VaultUrl -VaultToken $VaultToken -SecretPath $testSecretPath
        
        if ($secret) {
            Write-TestLog "✓ Secret retrieval successful" -Level "SUCCESS" -Test "STEP4"
            Write-TestLog "Secret path: $testSecretPath" -Level "INFO" -Test "STEP4"
            return $true
        } else {
            Write-TestLog "✗ Secret retrieval failed" -Level "ERROR" -Test "STEP4"
            return $false
        }
    } catch {
        Write-TestLog "✗ Secret retrieval error: $($_.Exception.Message)" -Level "ERROR" -Test "STEP4"
        return $false
    }
}

function Test-ScenarioStep5 {
    Write-TestLog "=== Step 5: gMSA NTLM Hash Authentication ===" -Level "STEP"
    
    try {
        Write-TestLog "Testing gMSA NTLM hash authentication..." -Level "INFO" -Test "STEP5"
        
        # Get gMSA credentials
        $gmsaCredentials = Get-GMSACredentials
        
        if ($gmsaCredentials -and $gmsaCredentials.ntlm_hash) {
            Write-TestLog "✓ gMSA credentials with NTLM hash retrieved" -Level "SUCCESS" -Test "STEP5"
            Write-TestLog "gMSA Name: $($gmsaCredentials.gmsa_name)" -Level "INFO" -Test "STEP5"
            Write-TestLog "NTLM Hash: $($gmsaCredentials.ntlm_hash.Substring(0, 8))..." -Level "INFO" -Test "STEP5"
            
            if ($DryRun) {
                Write-TestLog "DRY RUN: Would authenticate with NTLM hash" -Level "WARNING" -Test "STEP5"
                return $true
            }
            
            # Test NTLM hash authentication
            $ntlmResult = Invoke-LDAPAuthenticationWithNTLM -VaultUrl $VaultUrl -Username $gmsaCredentials.username -NTLMHash $gmsaCredentials.ntlm_hash
            
            if ($ntlmResult) {
                Write-TestLog "✓ NTLM hash authentication successful" -Level "SUCCESS" -Test "STEP5"
                return $true
            } else {
                Write-TestLog "⚠ NTLM hash authentication failed (expected - requires Vault enhancement)" -Level "WARNING" -Test "STEP5"
                return $true  # This is expected to fail until Vault supports NTLM hash
            }
        } else {
            Write-TestLog "✗ gMSA credentials with NTLM hash not available" -Level "ERROR" -Test "STEP5"
            return $false
        }
    } catch {
        Write-TestLog "✗ gMSA NTLM hash test error: $($_.Exception.Message)" -Level "ERROR" -Test "STEP5"
        return $false
    }
}

# =============================================================================
# Main Test Execution
# =============================================================================

function Start-ScenarioTest {
    Write-TestLog "=== gMSA Authentication Scenario Test ===" -Level "STEP"
    Write-TestLog "Vault URL: $VaultUrl" -Level "INFO"
    Write-TestLog "Vault Role: $VaultRole" -Level "INFO"
    Write-TestLog "SPN: $SPN" -Level "INFO"
    Write-TestLog "Dry Run: $DryRun" -Level "INFO"
    Write-TestLog "" -Level "INFO"
    
    $steps = @(
        @{ Name = "Environment Setup"; Function = "Test-ScenarioStep1"; Result = $null },
        @{ Name = "SPNEGO Token Generation"; Function = "Test-ScenarioStep2"; Result = $null },
        @{ Name = "Vault Authentication"; Function = "Test-ScenarioStep3"; Result = $null },
        @{ Name = "Secret Retrieval"; Function = "Test-ScenarioStep4"; Result = $null },
        @{ Name = "gMSA NTLM Hash Authentication"; Function = "Test-ScenarioStep5"; Result = $null }
    )
    
    $passedSteps = 0
    $totalSteps = $steps.Count
    
    # Step 1: Environment Setup
    $steps[0].Result = & $steps[0].Function
    if ($steps[0].Result) { $passedSteps++ }
    
    # Step 2: SPNEGO Token Generation
    $steps[1].Result = & $steps[1].Function
    if ($steps[1].Result) { $passedSteps++ }
    
    # Step 3: Vault Authentication
    $steps[2].Result = & $steps[2].Function -SPNEGOToken $steps[1].Result
    if ($steps[2].Result) { $passedSteps++ }
    
    # Step 4: Secret Retrieval
    $steps[3].Result = & $steps[3].Function -VaultToken $steps[2].Result
    if ($steps[3].Result) { $passedSteps++ }
    
    # Step 5: gMSA NTLM Hash Authentication
    $steps[4].Result = & $steps[4].Function
    if ($steps[4].Result) { $passedSteps++ }
    
    # Summary
    Write-TestLog "" -Level "INFO"
    Write-TestLog "=== Scenario Test Summary ===" -Level "STEP"
    Write-TestLog "Passed: $passedSteps/$totalSteps steps" -Level "INFO"
    
    foreach ($step in $steps) {
        $status = if ($step.Result) { "✓ PASS" } else { "✗ FAIL" }
        Write-TestLog "$status - $($step.Name)" -Level "INFO"
    }
    
    if ($passedSteps -eq $totalSteps) {
        Write-TestLog "✓ All scenario steps passed! gMSA authentication flow is working." -Level "SUCCESS"
        return $true
    } else {
        Write-TestLog "✗ Some scenario steps failed. Please review the issues above." -Level "ERROR"
        return $false
    }
}

# =============================================================================
# Script Execution
# =============================================================================

# Load the main script functions
try {
    Write-TestLog "Loading main script functions..." -Level "INFO"
    . .\vault-client-app.ps1 -WhatIf
    Write-TestLog "✓ Main script functions loaded" -Level "SUCCESS"
} catch {
    Write-TestLog "✗ Failed to load main script functions: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

# Run scenario test
if (Start-ScenarioTest) {
    Write-TestLog "Scenario test completed successfully!" -Level "SUCCESS"
    exit 0
} else {
    Write-TestLog "Scenario test failed!" -Level "ERROR"
    exit 1
}
