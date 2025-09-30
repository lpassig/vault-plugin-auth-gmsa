# Full gMSA Production Setup Script
# This script guides you through the complete passwordless gMSA setup with auto-rotation

<#
.SYNOPSIS
    Complete gMSA setup for passwordless Vault authentication with auto-rotation

.DESCRIPTION
    This script performs:
    1. gMSA creation on Domain Controller
    2. SPN migration from vault-keytab-svc to vault-gmsa
    3. Initial keytab generation
    4. gMSA installation on Windows client
    5. Scheduled task update
    6. Authentication testing

.PARAMETER Step
    Which step to execute (1-7, or 'all' for complete setup)

.PARAMETER GMSAName
    Name of the gMSA (default: vault-gmsa)

.PARAMETER SPN
    Service Principal Name (default: HTTP/vault.local.lab)

.PARAMETER Realm
    Kerberos realm (default: LOCAL.LAB)

.PARAMETER ClientGroup
    AD group for client computers (default: Vault-Clients)

.PARAMETER OldServiceAccount
    Current service account holding the SPN (default: vault-keytab-svc)

.EXAMPLE
    .\setup-gmsa-production.ps1 -Step all
    Run complete setup

.EXAMPLE
    .\setup-gmsa-production.ps1 -Step 1
    Run only step 1 (gMSA creation on DC)
#>

param(
    [ValidateSet('1', '2', '3', '4', '5', '6', '7', 'all')]
    [string]$Step = 'all',
    
    [string]$GMSAName = 'vault-gmsa',
    [string]$SPN = 'HTTP/vault.local.lab',
    [string]$Realm = 'LOCAL.LAB',
    [string]$ClientGroup = 'Vault-Clients',
    [string]$OldServiceAccount = 'vault-keytab-svc',
    [string]$VaultServer = 'vault.local.lab',
    [string]$VaultPort = '8200',
    [string]$TaskName = 'VaultClientApp'
)

# Color output functions
function Write-StepHeader {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Message" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Yellow
}

function Write-Command {
    param([string]$Message)
    Write-Host "  → $Message" -ForegroundColor Cyan
}

# Check if running with admin privileges
function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# STEP 1: Create gMSA on Domain Controller
function Step1-CreateGMSA {
    Write-StepHeader "STEP 1: Create gMSA on Domain Controller"
    
    Write-Info "This step must be run on a Domain Controller or a machine with AD tools"
    Write-Host ""
    
    # Check if AD module is available
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Error "ActiveDirectory module not found. Install RSAT or run on DC."
        Write-Host ""
        Write-Host "To install AD tools on Windows Server:" -ForegroundColor Yellow
        Write-Command "Install-WindowsFeature -Name RSAT-AD-PowerShell"
        Write-Host ""
        Write-Host "To install AD tools on Windows 10/11:" -ForegroundColor Yellow
        Write-Command "Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
        return $false
    }
    
    Import-Module ActiveDirectory -ErrorAction Stop
    
    # Check KDS root key
    Write-Info "Checking KDS root key..."
    $kdsKey = Get-KdsRootKey -ErrorAction SilentlyContinue
    
    if (-not $kdsKey) {
        Write-Info "Creating KDS root key (backdated for lab environments)..."
        Write-Command "Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))"
        
        try {
            Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) | Out-Null
            Write-Success "KDS root key created"
        } catch {
            Write-Error "Failed to create KDS root key: $_"
            return $false
        }
    } else {
        Write-Success "KDS root key already exists"
    }
    
    # Check if gMSA already exists
    $existingGMSA = Get-ADServiceAccount -Filter "Name -eq '$GMSAName'" -ErrorAction SilentlyContinue
    
    if ($existingGMSA) {
        Write-Success "gMSA '$GMSAName' already exists"
    } else {
        Write-Info "Creating gMSA '$GMSAName'..."
        Write-Command "New-ADServiceAccount -Name $GMSAName -DNSHostName $GMSAName.$Realm -ServicePrincipalNames '$SPN'"
        
        try {
            New-ADServiceAccount -Name $GMSAName `
                -DNSHostName "$GMSAName.$($Realm.ToLower())" `
                -ServicePrincipalNames $SPN `
                -PrincipalsAllowedToRetrieveManagedPassword $ClientGroup `
                -ErrorAction Stop
            
            Write-Success "gMSA '$GMSAName' created successfully"
        } catch {
            Write-Error "Failed to create gMSA: $_"
            return $false
        }
    }
    
    # Check if client group exists
    $existingGroup = Get-ADGroup -Filter "Name -eq '$ClientGroup'" -ErrorAction SilentlyContinue
    
    if ($existingGroup) {
        Write-Success "Client group '$ClientGroup' already exists"
    } else {
        Write-Info "Creating AD group '$ClientGroup'..."
        Write-Command "New-ADGroup -Name $ClientGroup -GroupCategory Security -GroupScope Global"
        
        try {
            New-ADGroup -Name $ClientGroup `
                -GroupCategory Security `
                -GroupScope Global `
                -Path "CN=Users,DC=$($Realm.Split('.')[0]),DC=$($Realm.Split('.')[1])" `
                -ErrorAction Stop
            
            Write-Success "Client group '$ClientGroup' created successfully"
        } catch {
            Write-Error "Failed to create group: $_"
            return $false
        }
    }
    
    # Add current computer to group
    Write-Info "Adding client computer to group..."
    $computerName = $env:COMPUTERNAME
    
    try {
        $groupMembers = Get-ADGroupMember -Identity $ClientGroup -ErrorAction SilentlyContinue
        $isMember = $groupMembers | Where-Object { $_.Name -eq "$computerName$" }
        
        if ($isMember) {
            Write-Success "Computer '$computerName' is already in group"
        } else {
            Add-ADGroupMember -Identity $ClientGroup -Members "$computerName$" -ErrorAction Stop
            Write-Success "Computer '$computerName' added to group '$ClientGroup'"
            Write-Info "⚠️  IMPORTANT: Reboot the computer for group membership to take effect!"
        }
    } catch {
        Write-Error "Failed to add computer to group: $_"
        return $false
    }
    
    Write-Host ""
    Write-Success "Step 1 completed successfully!"
    Write-Host ""
    
    return $true
}

# STEP 2: Move SPN from old account to gMSA
function Step2-MoveSPN {
    Write-StepHeader "STEP 2: Move SPN from $OldServiceAccount to $GMSAName"
    
    # Check current SPN registration
    Write-Info "Checking current SPN registration..."
    
    try {
        $currentSPNs = setspn -L $OldServiceAccount 2>&1
        
        if ($currentSPNs -match $SPN) {
            Write-Info "SPN '$SPN' is currently on '$OldServiceAccount'"
            Write-Info "Removing SPN from '$OldServiceAccount'..."
            Write-Command "setspn -D $SPN $OldServiceAccount"
            
            $result = setspn -D $SPN $OldServiceAccount 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Success "SPN removed from '$OldServiceAccount'"
            } else {
                Write-Error "Failed to remove SPN: $result"
                return $false
            }
        } else {
            Write-Info "SPN '$SPN' is not on '$OldServiceAccount'"
        }
    } catch {
        Write-Info "Could not check '$OldServiceAccount' (may not exist)"
    }
    
    # Add SPN to gMSA
    Write-Info "Adding SPN to '$GMSAName'..."
    Write-Command "setspn -A $SPN $GMSAName"
    
    $result = setspn -A $SPN $GMSAName 2>&1
    
    if ($result -match "Duplicate SPN found") {
        Write-Info "SPN already exists, ensuring it's on $GMSAName..."
        
        # Check if it's already on gMSA
        $gmsaSPNs = setspn -L $GMSAName 2>&1
        
        if ($gmsaSPNs -match $SPN) {
            Write-Success "SPN '$SPN' is already on '$GMSAName'"
        } else {
            Write-Error "SPN is registered elsewhere. Use: setspn -Q $SPN to find it"
            return $false
        }
    } elseif ($LASTEXITCODE -eq 0) {
        Write-Success "SPN '$SPN' added to '$GMSAName'"
    } else {
        Write-Error "Failed to add SPN: $result"
        return $false
    }
    
    # Verify
    Write-Info "Verifying SPN registration..."
    $gmsaSPNs = setspn -L $GMSAName 2>&1
    
    if ($gmsaSPNs -match $SPN) {
        Write-Success "Verified: SPN '$SPN' is on '$GMSAName'"
        Write-Host ""
        Write-Host "Registered SPNs for ${GMSAName}:" -ForegroundColor Cyan
        $gmsaSPNs | Where-Object { $_ -match "^\s+HTTP" } | ForEach-Object {
            Write-Host "  $_" -ForegroundColor White
        }
    } else {
        Write-Error "SPN verification failed"
        return $false
    }
    
    Write-Host ""
    Write-Success "Step 2 completed successfully!"
    Write-Host ""
    
    return $true
}

# STEP 3: Generate initial keytab
function Step3-GenerateKeytab {
    Write-StepHeader "STEP 3: Generate Initial Keytab for gMSA"
    
    Write-Info "This step generates a keytab for the gMSA"
    Write-Host ""
    
    $keytabFile = "vault-gmsa.keytab"
    $keytabB64File = "vault-gmsa.keytab.b64"
    
    Write-Info "Generating keytab using ktpass..."
    Write-Command "ktpass -princ $SPN@$Realm -mapuser $Realm\$GMSAName$ -crypto AES256-SHA1 -ptype KRB5_NT_PRINCIPAL -pass * -out $keytabFile"
    Write-Host ""
    
    Write-Host "CRITICAL: When prompted 'Do you want to change the password? (y/n)'" -ForegroundColor Yellow
    Write-Host "          Answer: n (NO) to preserve gMSA managed password" -ForegroundColor Yellow
    Write-Host ""
    
    $ktpassCmd = "ktpass -princ $SPN@$Realm -mapuser $Realm\$GMSAName$ -crypto AES256-SHA1 -ptype KRB5_NT_PRINCIPAL -pass * -out $keytabFile"
    
    try {
        # Run ktpass interactively
        Start-Process "ktpass" -ArgumentList "-princ","$SPN@$Realm","-mapuser","$Realm\$GMSAName$","-crypto","AES256-SHA1","-ptype","KRB5_NT_PRINCIPAL","-pass","*","-out","$keytabFile" -NoNewWindow -Wait
        
        if (Test-Path $keytabFile) {
            Write-Success "Keytab file created: $keytabFile"
            
            # Convert to base64
            Write-Info "Converting keytab to base64..."
            $keytabBytes = [System.IO.File]::ReadAllBytes($keytabFile)
            $keytabB64 = [Convert]::ToBase64String($keytabBytes)
            $keytabB64 | Out-File $keytabB64File -Encoding ASCII -NoNewline
            
            Write-Success "Base64 keytab saved: $keytabB64File"
            Write-Host ""
            Write-Host "Base64 keytab content:" -ForegroundColor Cyan
            Write-Host $keytabB64 -ForegroundColor White
            
        } else {
            Write-Info "Keytab file not created (expected if you answered 'n' to password change)"
            Write-Info "This is normal for gMSA - the plugin's auto-rotation will generate keytabs"
            Write-Info "You can use the existing vault-keytab-svc keytab temporarily"
        }
    } catch {
        Write-Error "Failed to generate keytab: $_"
        Write-Info "You can use the existing vault-keytab-svc keytab temporarily"
        return $false
    }
    
    Write-Host ""
    Write-Success "Step 3 completed!"
    Write-Host ""
    
    return $true
}

# STEP 4: Install gMSA on Windows Client
function Step4-InstallGMSA {
    Write-StepHeader "STEP 4: Install gMSA on Windows Client"
    
    Write-Info "Installing gMSA '$GMSAName' on this computer..."
    Write-Command "Install-ADServiceAccount -Identity $GMSAName"
    
    try {
        Install-ADServiceAccount -Identity $GMSAName -ErrorAction Stop
        Write-Success "gMSA installed successfully"
    } catch {
        if ($_.Exception.Message -match "already installed") {
            Write-Success "gMSA is already installed"
        } else {
            Write-Error "Failed to install gMSA: $_"
            Write-Info "Ensure this computer is in the '$ClientGroup' group and has been rebooted"
            return $false
        }
    }
    
    # Test gMSA
    Write-Info "Testing gMSA installation..."
    Write-Command "Test-ADServiceAccount -Identity $GMSAName"
    
    $testResult = Test-ADServiceAccount -Identity $GMSAName
    
    if ($testResult) {
        Write-Success "gMSA test PASSED! Passwordless authentication is working!"
    } else {
        Write-Error "gMSA test FAILED!"
        Write-Host ""
        Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
        Write-Host "1. Verify computer is in '$ClientGroup' group:" -ForegroundColor Yellow
        Write-Command "Get-ADGroupMember -Identity $ClientGroup | Where-Object { `$_.Name -eq '$env:COMPUTERNAME' }"
        Write-Host ""
        Write-Host "2. If not in group, add it and REBOOT:" -ForegroundColor Yellow
        Write-Command "Add-ADGroupMember -Identity $ClientGroup -Members '$env:COMPUTERNAME$'"
        Write-Command "Restart-Computer"
        Write-Host ""
        return $false
    }
    
    Write-Host ""
    Write-Success "Step 4 completed successfully!"
    Write-Host ""
    
    return $true
}

# STEP 5: Update Scheduled Task to use gMSA
function Step5-UpdateScheduledTask {
    Write-StepHeader "STEP 5: Update Scheduled Task to use gMSA (Passwordless!)"
    
    # Check if task exists
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    
    if (-not $task) {
        Write-Error "Scheduled task '$TaskName' not found"
        Write-Info "Create the task first using setup-vault-client.ps1"
        return $false
    }
    
    Write-Success "Found scheduled task: $TaskName"
    Write-Info "Current configuration:"
    Write-Host "  User: $($task.Principal.UserId)" -ForegroundColor Cyan
    Write-Host "  LogonType: $($task.Principal.LogonType)" -ForegroundColor Cyan
    Write-Host ""
    
    # Update task to use gMSA
    Write-Info "Updating task to use gMSA '$GMSAName' (passwordless!)..."
    Write-Command "Set-ScheduledTask -TaskName $TaskName -Principal (New-ScheduledTaskPrincipal -UserId '$Realm\$GMSAName$' -LogonType Password -RunLevel Highest)"
    
    try {
        $principal = New-ScheduledTaskPrincipal `
            -UserId "$Realm\$GMSAName$" `
            -LogonType Password `
            -RunLevel Highest
        
        Set-ScheduledTask -TaskName $TaskName -Principal $principal -ErrorAction Stop
        
        Write-Success "Scheduled task updated to use gMSA!"
        Write-Success "NO PASSWORD REQUIRED - gMSA provides passwordless authentication!"
        
        # Verify
        $updatedTask = Get-ScheduledTask -TaskName $TaskName
        Write-Host ""
        Write-Host "Updated configuration:" -ForegroundColor Green
        Write-Host "  User: $($updatedTask.Principal.UserId)" -ForegroundColor White
        Write-Host "  LogonType: $($updatedTask.Principal.LogonType)" -ForegroundColor White
        
    } catch {
        Write-Error "Failed to update scheduled task: $_"
        return $false
    }
    
    Write-Host ""
    Write-Success "Step 5 completed successfully!"
    Write-Host ""
    
    return $true
}

# STEP 6: Configure Vault with Auto-Rotation
function Step6-ConfigureVault {
    Write-StepHeader "STEP 6: Configure Vault with Auto-Rotation"
    
    Write-Info "This step configures Vault on the server side"
    Write-Host ""
    
    $keytabB64File = "vault-gmsa.keytab.b64"
    
    if (Test-Path $keytabB64File) {
        $keytabB64 = Get-Content $keytabB64File -Raw
    } else {
        Write-Error "Keytab file not found: $keytabB64File"
        Write-Info "Generate the keytab first (Step 3) or use existing vault-keytab-svc keytab"
        return $false
    }
    
    Write-Host "Run these commands on your Vault server:" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "# Copy keytab to Vault server" -ForegroundColor Cyan
    Write-Command "scp $keytabB64File user@${VaultServer}:/tmp/"
    Write-Host ""
    
    Write-Host "# Configure Vault auth method with AUTO-ROTATION" -ForegroundColor Cyan
    Write-Host @"
vault write auth/gmsa/config \
  realm="$Realm" \
  kdcs="addc.$($Realm.ToLower())" \
  spn="$SPN" \
  keytab="`$(cat /tmp/$keytabB64File)" \
  clock_skew_sec=300 \
  allow_channel_binding=true \
  enable_rotation=true \
  rotation_threshold=5d \
  backup_keytabs=true
"@ -ForegroundColor White
    
    Write-Host ""
    Write-Host "# Verify configuration" -ForegroundColor Cyan
    Write-Command "vault read auth/gmsa/config"
    Write-Host ""
    
    Write-Host "# Check rotation status" -ForegroundColor Cyan
    Write-Command "vault read auth/gmsa/rotation/status"
    Write-Host ""
    
    Write-Info "After running these commands, press Enter to continue..."
    Read-Host
    
    Write-Success "Step 6 configuration provided!"
    Write-Host ""
    
    return $true
}

# STEP 7: Test Authentication
function Step7-TestAuthentication {
    Write-StepHeader "STEP 7: Test gMSA Authentication"
    
    Write-Info "Running scheduled task to test authentication..."
    Write-Command "Start-ScheduledTask -TaskName $TaskName"
    
    try {
        Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        Write-Success "Scheduled task started"
        
        Write-Info "Waiting for task to complete..."
        Start-Sleep -Seconds 5
        
        # Check task result
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
        
        if ($taskInfo.LastTaskResult -eq 0) {
            Write-Success "Task completed successfully! (Exit code: 0)"
        } else {
            Write-Error "Task failed with exit code: $($taskInfo.LastTaskResult)"
        }
        
    } catch {
        Write-Error "Failed to start task: $_"
        return $false
    }
    
    # Check logs
    $logFile = "C:\vault-client\config\vault-client.log"
    
    if (Test-Path $logFile) {
        Write-Info "Checking authentication logs..."
        Write-Host ""
        
        $recentLogs = Get-Content $logFile -Tail 20
        
        # Check for success indicators
        $hasSuccess = $recentLogs | Where-Object { $_ -match "SUCCESS.*authentication" -or $_ -match "SUCCESS.*token generated" }
        $hasError = $recentLogs | Where-Object { $_ -match "ERROR" }
        
        if ($hasSuccess) {
            Write-Host "Recent logs (SUCCESS):" -ForegroundColor Green
            $recentLogs | ForEach-Object {
                if ($_ -match "SUCCESS") {
                    Write-Host $_ -ForegroundColor Green
                } elseif ($_ -match "ERROR") {
                    Write-Host $_ -ForegroundColor Red
                } else {
                    Write-Host $_ -ForegroundColor Gray
                }
            }
            
            Write-Host ""
            Write-Success "🎉 PASSWORDLESS gMSA AUTHENTICATION IS WORKING!"
            Write-Success "Auto-rotation is enabled on Vault server!"
            
        } elseif ($hasError) {
            Write-Host "Recent logs (ERRORS FOUND):" -ForegroundColor Red
            $recentLogs | ForEach-Object {
                if ($_ -match "ERROR") {
                    Write-Host $_ -ForegroundColor Red
                } else {
                    Write-Host $_ -ForegroundColor Gray
                }
            }
            
            Write-Host ""
            Write-Error "Authentication failed - check errors above"
            
        } else {
            Write-Host "Recent logs:" -ForegroundColor Yellow
            $recentLogs | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        }
        
    } else {
        Write-Error "Log file not found: $logFile"
        return $false
    }
    
    Write-Host ""
    Write-Success "Step 7 completed!"
    Write-Host ""
    
    return $true
}

# Main execution
Write-Host @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Full gMSA Production Setup with Auto-Rotation          ║
║   Passwordless Vault Authentication                      ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

if (-not (Test-Admin)) {
    Write-Error "This script requires Administrator privileges"
    Write-Info "Right-click PowerShell and select 'Run as Administrator'"
    exit 1
}

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  gMSA Name: $GMSAName" -ForegroundColor White
Write-Host "  SPN: $SPN" -ForegroundColor White
Write-Host "  Realm: $Realm" -ForegroundColor White
Write-Host "  Client Group: $ClientGroup" -ForegroundColor White
Write-Host "  Old Account: $OldServiceAccount" -ForegroundColor White
Write-Host "  Vault Server: $VaultServer" -ForegroundColor White
Write-Host ""

if ($Step -eq 'all') {
    Write-Info "Running ALL steps (1-7)..."
    Write-Host ""
    
    $stepList = @(
        @{ Name = "Create gMSA"; Function = ${function:Step1-CreateGMSA} },
        @{ Name = "Move SPN"; Function = ${function:Step2-MoveSPN} },
        @{ Name = "Generate Keytab"; Function = ${function:Step3-GenerateKeytab} },
        @{ Name = "Install gMSA"; Function = ${function:Step4-InstallGMSA} },
        @{ Name = "Update Task"; Function = ${function:Step5-UpdateScheduledTask} },
        @{ Name = "Configure Vault"; Function = ${function:Step6-ConfigureVault} },
        @{ Name = "Test Auth"; Function = ${function:Step7-TestAuthentication} }
    )
    
    $success = $true
    
    foreach ($stepItem in $stepList) {
        $result = & $stepItem.Function
        
        if (-not $result) {
            Write-Error "Step failed: $($stepItem.Name)"
            $success = $false
            break
        }
    }
    
    if ($success) {
        Write-Host @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   ✓ SUCCESS! Full gMSA Setup Complete!                   ║
║                                                           ║
║   ✓ Passwordless authentication configured               ║
║   ✓ Auto-rotation enabled                                ║
║   ✓ Production ready!                                    ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green
    }
    
} else {
    # Run specific step
    switch ($Step) {
        '1' { Step1-CreateGMSA }
        '2' { Step2-MoveSPN }
        '3' { Step3-GenerateKeytab }
        '4' { Step4-InstallGMSA }
        '5' { Step5-UpdateScheduledTask }
        '6' { Step6-ConfigureVault }
        '7' { Step7-TestAuthentication }
    }
}
