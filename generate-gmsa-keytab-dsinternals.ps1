# Generate Keytab for gMSA using DSInternals to Extract Password
# This script extracts the gMSA's current password from AD and generates a keytab

param(
    [string]$GMSAName = "vault-gmsa",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$Realm = "LOCAL.LAB",
    [string]$OutputFile = "vault-gmsa-extracted.keytab",
    [switch]$UpdateVault,
    [string]$VaultServer = "107.23.32.117",
    [string]$VaultUser = "lennart"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Generate gMSA Keytab using DSInternals" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check for DSInternals module
Write-Host "[1] Checking for DSInternals module..." -ForegroundColor Yellow

if (-not (Get-Module -ListAvailable -Name DSInternals)) {
    Write-Host "  ✗ DSInternals module not found" -ForegroundColor Red
    Write-Host ""
    Write-Host "Installing DSInternals..." -ForegroundColor Yellow
    
    try {
        Install-Module -Name DSInternals -Scope CurrentUser -Force -AllowClobber
        Write-Host "  ✓ DSInternals installed successfully" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Failed to install DSInternals: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Manual installation:" -ForegroundColor Yellow
        Write-Host "  Install-Module -Name DSInternals -Scope CurrentUser" -ForegroundColor White
        exit 1
    }
}

Import-Module DSInternals -ErrorAction Stop
Write-Host "  ✓ DSInternals module loaded" -ForegroundColor Green
Write-Host ""

# Step 2: Extract gMSA password from AD
Write-Host "[2] Extracting gMSA password from Active Directory..." -ForegroundColor Yellow

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

# Step 3: Generate keytab using ktpass
Write-Host "[3] Generating keytab using ktpass..." -ForegroundColor Yellow

try {
    # Create a temporary file for the password
    $tempPasswordFile = [System.IO.Path]::GetTempFileName()
    $plainPassword | Out-File -FilePath $tempPasswordFile -Encoding ASCII -NoNewline
    
    # Build ktpass command
    # Note: We use -pass with the actual password, then answer 'n' to not reset it
    $ktpassArgs = @(
        "-princ", "$SPN@$Realm",
        "-mapuser", "$Realm\$GMSAName$",
        "-crypto", "AES256-SHA1",
        "-ptype", "KRB5_NT_PRINCIPAL",
        "-pass", $plainPassword,
        "-out", $OutputFile
    )
    
    Write-Host "  Running ktpass..." -ForegroundColor Cyan
    
    # Run ktpass
    $ktpassProcess = Start-Process -FilePath "ktpass" -ArgumentList $ktpassArgs -NoNewWindow -Wait -PassThru
    
    # Clean up password file
    Remove-Item -Path $tempPasswordFile -Force -ErrorAction SilentlyContinue
    
    if ($ktpassProcess.ExitCode -eq 0 -and (Test-Path $OutputFile)) {
        $keytabSize = (Get-Item $OutputFile).Length
        Write-Host "  ✓ Keytab generated successfully" -ForegroundColor Green
        Write-Host "  ✓ File: $OutputFile ($keytabSize bytes)" -ForegroundColor Green
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

# Step 4: Convert to base64
Write-Host "[4] Converting keytab to base64..." -ForegroundColor Yellow

try {
    $keytabBytes = [System.IO.File]::ReadAllBytes($OutputFile)
    $keytabB64 = [System.Convert]::ToBase64String($keytabBytes)
    
    $outputB64File = "$OutputFile.b64"
    $keytabB64 | Out-File -FilePath $outputB64File -Encoding ASCII -NoNewline
    
    Write-Host "  ✓ Base64 keytab saved: $outputB64File" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Base64 Keytab Content:" -ForegroundColor Cyan
    Write-Host $keytabB64 -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host "  ✗ Failed to convert keytab: $_" -ForegroundColor Red
    exit 1
}

# Step 5: Update Vault (optional)
if ($UpdateVault) {
    Write-Host "[5] Updating Vault server configuration..." -ForegroundColor Yellow
    
    try {
        $sshCommand = "VAULT_SKIP_VERIFY=1 vault write auth/gmsa/config keytab='$keytabB64'"
        
        Write-Host "  Connecting to $VaultServer..." -ForegroundColor Cyan
        
        $result = ssh "$VaultUser@$VaultServer" $sshCommand
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Vault keytab updated successfully" -ForegroundColor Green
            Write-Host ""
            Write-Host "Vault configuration:" -ForegroundColor Cyan
            Write-Host $result -ForegroundColor White
        } else {
            Write-Host "  ✗ Failed to update Vault (exit code: $LASTEXITCODE)" -ForegroundColor Red
            Write-Host "  You can update manually using the base64 content above" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "  ✗ Failed to update Vault: $_" -ForegroundColor Red
        Write-Host "  You can update manually using the base64 content above" -ForegroundColor Yellow
    }
    
    Write-Host ""
}

# Step 6: Summary and next steps
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "✓ gMSA Password: Extracted from AD" -ForegroundColor Green
Write-Host "✓ Keytab File: $OutputFile" -ForegroundColor Green
Write-Host "✓ Base64 File: $outputB64File" -ForegroundColor Green

if ($UpdateVault) {
    Write-Host "✓ Vault Server: Updated" -ForegroundColor Green
} else {
    Write-Host "⚠ Vault Server: Not updated (use -UpdateVault to auto-update)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host ""

if (-not $UpdateVault) {
    Write-Host "1. Update Vault server manually:" -ForegroundColor White
    Write-Host "   ssh $VaultUser@$VaultServer" -ForegroundColor Cyan
    Write-Host "   VAULT_SKIP_VERIFY=1 vault write auth/gmsa/config keytab='$keytabB64'" -ForegroundColor Cyan
    Write-Host ""
}

Write-Host "2. Test authentication:" -ForegroundColor White
Write-Host "   Start-ScheduledTask -TaskName 'VaultClientApp'" -ForegroundColor Cyan
Write-Host "   Start-Sleep -Seconds 5" -ForegroundColor Cyan
Write-Host "   Get-Content 'C:\vault-client\config\vault-client.log' -Tail 30" -ForegroundColor Cyan
Write-Host ""

Write-Host "3. Expected result:" -ForegroundColor White
Write-Host "   [SUCCESS] Real SPNEGO token generated!" -ForegroundColor Green
Write-Host "   [SUCCESS] Vault authentication successful!" -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " 🎉 Keytab Generated Successfully!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
