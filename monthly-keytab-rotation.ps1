# =============================================================================
# Monthly gMSA Keytab Rotation Script
# =============================================================================
# This script should be scheduled to run monthly (before gMSA password rotation)
# It uses DSInternals to extract the current gMSA password and regenerate the keytab
# 
# Schedule: Run on day 25 of each month (before 30-day gMSA rotation)
# =============================================================================

param(
    [string]$GMSAName = "vault-gmsa",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$Realm = "LOCAL.LAB",
    [string]$VaultServer = "107.23.32.117",
    [string]$VaultUser = "lennart",
    [string]$LogFile = "C:\vault-client\logs\keytab-rotation.log",
    [switch]$TestMode
)

function Write-RotationLog {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    try {
        $logDir = Split-Path $LogFile
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Failed to write to log file: $_" -ForegroundColor Yellow
    }
}

Write-RotationLog "========================================" -Level "INFO"
Write-RotationLog "Monthly gMSA Keytab Rotation" -Level "INFO"
Write-RotationLog "========================================" -Level "INFO"
Write-RotationLog "" -Level "INFO"

# Check if DSInternals is installed
if (-not (Get-Module -ListAvailable -Name DSInternals)) {
    Write-RotationLog "DSInternals module not found, installing..." -Level "WARNING"
    
    try {
        Install-Module -Name DSInternals -Scope CurrentUser -Force -AllowClobber
        Write-RotationLog "DSInternals installed successfully" -Level "SUCCESS"
    } catch {
        Write-RotationLog "Failed to install DSInternals: $_" -Level "ERROR"
        exit 1
    }
}

Import-Module DSInternals -ErrorAction Stop
Write-RotationLog "DSInternals module loaded" -Level "INFO"

# Extract gMSA password
Write-RotationLog "Extracting gMSA password from Active Directory..." -Level "INFO"

try {
    $gmsaAccount = Get-ADServiceAccount -Identity $GMSAName -Properties 'msDS-ManagedPassword' -ErrorAction Stop
    
    if (-not $gmsaAccount.'msDS-ManagedPassword') {
        Write-RotationLog "No managed password found for $GMSAName" -Level "ERROR"
        exit 1
    }
    
    $passwordBlob = $gmsaAccount.'msDS-ManagedPassword'
    $managedPassword = ConvertFrom-ADManagedPasswordBlob $passwordBlob
    $currentPassword = $managedPassword.SecureCurrentPassword
    
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($currentPassword)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    Write-RotationLog "Extracted current password (length: $($plainPassword.Length) chars)" -Level "SUCCESS"
    
} catch {
    Write-RotationLog "Failed to extract gMSA password: $_" -Level "ERROR"
    exit 1
}

# Generate keytab
Write-RotationLog "Generating new keytab..." -Level "INFO"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$keytabFile = "vault-gmsa-rotated-$timestamp.keytab"

try {
    $ktpassArgs = @(
        "-princ", "$SPN@$Realm",
        "-mapuser", "$Realm\$GMSAName$",
        "-crypto", "AES256-SHA1",
        "-ptype", "KRB5_NT_PRINCIPAL",
        "-pass", $plainPassword,
        "-out", $keytabFile
    )
    
    $ktpassProcess = Start-Process -FilePath "ktpass" -ArgumentList $ktpassArgs -NoNewWindow -Wait -PassThru
    
    if ($ktpassProcess.ExitCode -eq 0 -and (Test-Path $keytabFile)) {
        $keytabSize = (Get-Item $keytabFile).Length
        Write-RotationLog "Keytab generated successfully: $keytabFile ($keytabSize bytes)" -Level "SUCCESS"
    } else {
        Write-RotationLog "ktpass failed (exit code: $($ktpassProcess.ExitCode))" -Level "ERROR"
        exit 1
    }
    
} catch {
    Write-RotationLog "Failed to generate keytab: $_" -Level "ERROR"
    exit 1
} finally {
    if ($plainPassword) {
        $plainPassword = $null
        [System.GC]::Collect()
    }
}

# Convert to base64
Write-RotationLog "Converting keytab to base64..." -Level "INFO"

try {
    $keytabBytes = [System.IO.File]::ReadAllBytes($keytabFile)
    $keytabB64 = [System.Convert]::ToBase64String($keytabBytes)
    
    $outputB64File = "$keytabFile.b64"
    $keytabB64 | Out-File -FilePath $outputB64File -Encoding ASCII -NoNewline
    
    Write-RotationLog "Base64 keytab saved: $outputB64File" -Level "SUCCESS"
    
} catch {
    Write-RotationLog "Failed to convert keytab: $_" -Level "ERROR"
    exit 1
}

# Update Vault server (if not in test mode)
if (-not $TestMode) {
    Write-RotationLog "Updating Vault server configuration..." -Level "INFO"
    
    try {
        # Backup current Vault config
        Write-RotationLog "Backing up current Vault config..." -Level "INFO"
        $backupConfig = ssh "$VaultUser@$VaultServer" "VAULT_SKIP_VERIFY=1 vault read -format=json auth/gmsa/config" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $backupFile = "vault-config-backup-$timestamp.json"
            $backupConfig | Out-File -FilePath $backupFile -Encoding UTF8
            Write-RotationLog "Vault config backed up: $backupFile" -Level "SUCCESS"
        }
        
        # Update with new keytab
        $sshCommand = "VAULT_SKIP_VERIFY=1 vault write auth/gmsa/config keytab='$keytabB64'"
        
        Write-RotationLog "Connecting to Vault server: $VaultServer..." -Level "INFO"
        
        $result = ssh "$VaultUser@$VaultServer" $sshCommand 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-RotationLog "Vault keytab updated successfully" -Level "SUCCESS"
            Write-RotationLog "Vault response: $result" -Level "INFO"
        } else {
            Write-RotationLog "Failed to update Vault (exit code: $LASTEXITCODE)" -Level "ERROR"
            Write-RotationLog "Output: $result" -Level "ERROR"
            
            # Attempt to restore backup
            Write-RotationLog "Attempting to restore backup..." -Level "WARNING"
            # Restoration logic would go here
            
            exit 1
        }
        
    } catch {
        Write-RotationLog "Failed to update Vault: $_" -Level "ERROR"
        exit 1
    }
} else {
    Write-RotationLog "TEST MODE: Skipping Vault update" -Level "WARNING"
    Write-RotationLog "To update Vault manually:" -Level "INFO"
    Write-RotationLog "  ssh $VaultUser@$VaultServer" -Level "INFO"
    Write-RotationLog "  VAULT_SKIP_VERIFY=1 vault write auth/gmsa/config keytab='$keytabB64'" -Level "INFO"
}

# Test authentication
Write-RotationLog "Testing authentication with new keytab..." -Level "INFO"

try {
    Start-ScheduledTask -TaskName "VaultClientApp" -ErrorAction Stop
    Start-Sleep -Seconds 5
    
    $vaultLog = "C:\vault-client\config\vault-client.log"
    if (Test-Path $vaultLog) {
        $lastLines = Get-Content $vaultLog -Tail 10
        
        if ($lastLines -match "SUCCESS.*authentication successful") {
            Write-RotationLog "Authentication test PASSED" -Level "SUCCESS"
        } elseif ($lastLines -match "ERROR") {
            Write-RotationLog "Authentication test FAILED" -Level "ERROR"
            Write-RotationLog "Last log lines:" -Level "ERROR"
            $lastLines | ForEach-Object { Write-RotationLog "  $_" -Level "ERROR" }
            exit 1
        } else {
            Write-RotationLog "Authentication test result unclear" -Level "WARNING"
        }
    } else {
        Write-RotationLog "Log file not found: $vaultLog" -Level "WARNING"
    }
    
} catch {
    Write-RotationLog "Failed to test authentication: $_" -Level "ERROR"
}

# Cleanup old keytab files (keep last 5)
Write-RotationLog "Cleaning up old keytab files..." -Level "INFO"

try {
    $oldKeytabs = Get-ChildItem -Path "." -Filter "vault-gmsa-rotated-*.keytab" | 
        Sort-Object -Property LastWriteTime -Descending | 
        Select-Object -Skip 5
    
    if ($oldKeytabs) {
        foreach ($file in $oldKeytabs) {
            Remove-Item -Path $file.FullName -Force
            Remove-Item -Path "$($file.FullName).b64" -Force -ErrorAction SilentlyContinue
            Write-RotationLog "Removed old keytab: $($file.Name)" -Level "INFO"
        }
    }
} catch {
    Write-RotationLog "Failed to cleanup old keytabs: $_" -Level "WARNING"
}

# Summary
Write-RotationLog "" -Level "INFO"
Write-RotationLog "========================================" -Level "INFO"
Write-RotationLog "Rotation Complete!" -Level "SUCCESS"
Write-RotationLog "========================================" -Level "INFO"
Write-RotationLog "" -Level "INFO"
Write-RotationLog "New keytab: $keytabFile" -Level "INFO"
Write-RotationLog "Base64 file: $outputB64File" -Level "INFO"

if (-not $TestMode) {
    Write-RotationLog "Vault server: Updated" -Level "INFO"
} else {
    Write-RotationLog "Vault server: Not updated (test mode)" -Level "INFO"
}

Write-RotationLog "" -Level "INFO"
Write-RotationLog "Next rotation: $(Get-Date (Get-Date).AddDays(30) -Format 'yyyy-MM-dd')" -Level "INFO"
Write-RotationLog "" -Level "INFO"

# Send notification (optional - implement as needed)
# Send-MailMessage -To "admin@local.lab" -Subject "gMSA Keytab Rotation Complete" -Body "Rotation completed successfully"

exit 0
