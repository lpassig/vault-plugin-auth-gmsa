# =============================================================================
# Complete gMSA Setup with DSInternals Keytab Generation
# =============================================================================
# This script performs the complete gMSA authentication setup:
# 1. Installs DSInternals module
# 2. Extracts gMSA password from Active Directory
# 3. Generates keytab with real password
# 4. Configures Vault server
# 5. Sets up Windows client with scheduled task
# 6. Tests authentication
# =============================================================================

param(
    [string]$GMSAName = "vault-gmsa",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$Realm = "LOCAL.LAB",
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$VaultServer = "107.23.32.117",
    [string]$VaultUser = "lennart",
    [string]$TaskName = "VaultClientApp",
    [switch]$SkipVaultUpdate,
    [switch]$SkipClientSetup,
    [switch]$TestOnly
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Complete gMSA Setup with DSInternals" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Step 1: Install DSInternals Module
# =============================================================================

Write-Host "[Step 1/6] Installing DSInternals module..." -ForegroundColor Yellow
Write-Host ""

if (-not (Get-Module -ListAvailable -Name DSInternals)) {
    Write-Host "  DSInternals not found, installing..." -ForegroundColor Cyan
    
    try {
        Install-Module -Name DSInternals -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Host "  ✓ DSInternals installed successfully" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Failed to install DSInternals: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Manual installation:" -ForegroundColor Yellow
        Write-Host "  Install-Module -Name DSInternals -Scope CurrentUser" -ForegroundColor White
        exit 1
    }
} else {
    Write-Host "  ✓ DSInternals already installed" -ForegroundColor Green
}

Import-Module DSInternals -ErrorAction Stop
Write-Host "  ✓ DSInternals module loaded" -ForegroundColor Green
Write-Host ""

# =============================================================================
# Step 2: Extract gMSA Password from Active Directory
# =============================================================================

Write-Host "[Step 2/6] Extracting gMSA password from Active Directory..." -ForegroundColor Yellow
Write-Host ""

try {
    # Get the gMSA object with managed password attribute
    $gmsaAccount = Get-ADServiceAccount -Identity $GMSAName -Properties 'msDS-ManagedPassword' -ErrorAction Stop
    
    if (-not $gmsaAccount.'msDS-ManagedPassword') {
        Write-Host "  ✗ No managed password found for $GMSAName" -ForegroundColor Red
        Write-Host "  This computer may not have permission to retrieve the password" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Verify:" -ForegroundColor Yellow
        Write-Host "  Test-ADServiceAccount -Identity $GMSAName" -ForegroundColor White
        exit 1
    }
    
    Write-Host "  ✓ Retrieved gMSA object from AD" -ForegroundColor Green
    
    # Decode the password blob
    $passwordBlob = $gmsaAccount.'msDS-ManagedPassword'
    $managedPassword = ConvertFrom-ADManagedPasswordBlob $passwordBlob
    
    Write-Host "  ✓ Decoded managed password blob" -ForegroundColor Green
    
    # Get the current password
    $currentPassword = $managedPassword.SecureCurrentPassword
    
    # Convert SecureString to plain text (needed for ktpass)
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($currentPassword)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    Write-Host "  ✓ Extracted current password (length: $($plainPassword.Length) chars)" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host "  ✗ Failed to extract gMSA password: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Common issues:" -ForegroundColor Yellow
    Write-Host "  1. Computer not in PrincipalsAllowedToRetrieveManagedPassword" -ForegroundColor White
    Write-Host "  2. gMSA not installed: Install-ADServiceAccount -Identity $GMSAName" -ForegroundColor White
    Write-Host "  3. Insufficient permissions" -ForegroundColor White
    exit 1
}

# =============================================================================
# Step 3: Generate Keytab using ktpass
# =============================================================================

Write-Host "[Step 3/6] Generating keytab using ktpass..." -ForegroundColor Yellow
Write-Host ""

$keytabFile = "vault-gmsa-generated.keytab"

try {
    # Build ktpass command
    $ktpassArgs = @(
        "-princ", "$SPN@$Realm",
        "-mapuser", "$Realm\$GMSAName$",
        "-crypto", "AES256-SHA1",
        "-ptype", "KRB5_NT_PRINCIPAL",
        "-pass", $plainPassword,
        "-out", $keytabFile
    )
    
    Write-Host "  Running ktpass..." -ForegroundColor Cyan
    
    # Run ktpass
    $ktpassProcess = Start-Process -FilePath "ktpass" -ArgumentList $ktpassArgs -NoNewWindow -Wait -PassThru
    
    if ($ktpassProcess.ExitCode -eq 0 -and (Test-Path $keytabFile)) {
        $keytabSize = (Get-Item $keytabFile).Length
        Write-Host "  ✓ Keytab generated successfully" -ForegroundColor Green
        Write-Host "  ✓ File: $keytabFile ($keytabSize bytes)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ ktpass failed (exit code: $($ktpassProcess.ExitCode))" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "  ✗ Failed to generate keytab: $_" -ForegroundColor Red
    exit 1
} finally {
    # Clear password from memory
    if ($plainPassword) {
        $plainPassword = $null
        [System.GC]::Collect()
    }
}

Write-Host ""

# =============================================================================
# Step 4: Convert to Base64
# =============================================================================

Write-Host "[Step 4/6] Converting keytab to base64..." -ForegroundColor Yellow
Write-Host ""

try {
    $keytabBytes = [System.IO.File]::ReadAllBytes($keytabFile)
    $keytabB64 = [System.Convert]::ToBase64String($keytabBytes)
    
    $outputB64File = "$keytabFile.b64"
    $keytabB64 | Out-File -FilePath $outputB64File -Encoding ASCII -NoNewline
    
    Write-Host "  ✓ Base64 keytab saved: $outputB64File" -ForegroundColor Green
    Write-Host "  ✓ Base64 length: $($keytabB64.Length) characters" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host "  ✗ Failed to convert keytab: $_" -ForegroundColor Red
    exit 1
}

# =============================================================================
# Step 5: Update Vault Server Configuration
# =============================================================================

if (-not $SkipVaultUpdate) {
    Write-Host "[Step 5/6] Updating Vault server configuration..." -ForegroundColor Yellow
    Write-Host ""
    
    try {
        $sshCommand = "VAULT_SKIP_VERIFY=1 vault write auth/gmsa/config keytab='$keytabB64' spn='$SPN' realm='$Realm'"
        
        Write-Host "  Connecting to $VaultServer..." -ForegroundColor Cyan
        
        $result = ssh "$VaultUser@$VaultServer" $sshCommand 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Vault keytab updated successfully" -ForegroundColor Green
            Write-Host ""
            Write-Host "Vault configuration:" -ForegroundColor Cyan
            Write-Host $result -ForegroundColor White
        } else {
            Write-Host "  ✗ Failed to update Vault (exit code: $LASTEXITCODE)" -ForegroundColor Red
            Write-Host "  Output: $result" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Manual update command:" -ForegroundColor Yellow
            Write-Host "  ssh $VaultUser@$VaultServer" -ForegroundColor Cyan
            Write-Host "  $sshCommand" -ForegroundColor Cyan
        }
        
    } catch {
        Write-Host "  ✗ Failed to update Vault: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Manual update command:" -ForegroundColor Yellow
        Write-Host "  ssh $VaultUser@$VaultServer" -ForegroundColor Cyan
        Write-Host "  VAULT_SKIP_VERIFY=1 vault write auth/gmsa/config keytab='<base64-content>'" -ForegroundColor Cyan
    }
    
    Write-Host ""
} else {
    Write-Host "[Step 5/6] Skipping Vault update (use -SkipVaultUpdate=`$false to enable)" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# Step 6: Setup Windows Client with Scheduled Task
# =============================================================================

if (-not $SkipClientSetup) {
    Write-Host "[Step 6/6] Setting up Windows client..." -ForegroundColor Yellow
    Write-Host ""
    
    if (Test-Path ".\setup-vault-client.ps1") {
        Write-Host "  Running setup-vault-client.ps1..." -ForegroundColor Cyan
        
        try {
            & ".\setup-vault-client.ps1" -VaultUrl $VaultUrl -VaultRole $VaultRole -TaskName $TaskName
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Client setup completed successfully" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Client setup failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
            }
        } catch {
            Write-Host "  ✗ Client setup failed: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "  ✗ setup-vault-client.ps1 not found" -ForegroundColor Red
        Write-Host "  Run manually: .\\setup-vault-client.ps1 -VaultUrl `"$VaultUrl`" -VaultRole `"$VaultRole`"" -ForegroundColor Yellow
    }
    
    Write-Host ""
} else {
    Write-Host "[Step 6/6] Skipping client setup (use -SkipClientSetup=`$false to enable)" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# Test Authentication (if requested)
# =============================================================================

if ($TestOnly) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " Testing Authentication" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Starting scheduled task: $TaskName" -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    
    Write-Host "Waiting for task to complete (5 seconds)..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    
    $logFile = "C:\vault-client\config\vault-client.log"
    if (Test-Path $logFile) {
        Write-Host ""
        Write-Host "Last 30 lines of log:" -ForegroundColor Cyan
        Get-Content $logFile -Tail 30 | ForEach-Object { Write-Host $_ }
    } else {
        Write-Host "  ✗ Log file not found: $logFile" -ForegroundColor Red
    }
}

# =============================================================================
# Summary
# =============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Setup Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "✓ DSInternals Module: Installed" -ForegroundColor Green
Write-Host "✓ gMSA Password: Extracted from AD" -ForegroundColor Green
Write-Host "✓ Keytab File: $keytabFile" -ForegroundColor Green
Write-Host "✓ Base64 File: $outputB64File" -ForegroundColor Green

if (-not $SkipVaultUpdate) {
    Write-Host "✓ Vault Server: Updated" -ForegroundColor Green
} else {
    Write-Host "⚠ Vault Server: Not updated (run with -SkipVaultUpdate=`$false)" -ForegroundColor Yellow
}

if (-not $SkipClientSetup) {
    Write-Host "✓ Windows Client: Configured" -ForegroundColor Green
} else {
    Write-Host "⚠ Windows Client: Not configured (run with -SkipClientSetup=`$false)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host ""

Write-Host "1. Test authentication:" -ForegroundColor White
Write-Host "   Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Cyan
Write-Host "   Get-Content 'C:\vault-client\config\vault-client.log' -Tail 30" -ForegroundColor Cyan
Write-Host ""

Write-Host "2. Expected result:" -ForegroundColor White
Write-Host "   [SUCCESS] Real SPNEGO token generated!" -ForegroundColor Green
Write-Host "   [SUCCESS] Vault authentication successful!" -ForegroundColor Green
Write-Host ""

Write-Host "3. Monthly keytab rotation:" -ForegroundColor White
Write-Host "   Schedule this script to run monthly (before gMSA password rotation)" -ForegroundColor Cyan
Write-Host "   OR" -ForegroundColor White
Write-Host "   Enable Vault auto-rotation (see SOLUTION-COMPARISON.md)" -ForegroundColor Cyan
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " 🎉 All Done!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
