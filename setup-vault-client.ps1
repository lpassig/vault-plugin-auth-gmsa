# =============================================================================
# Vault Client Application Setup Script
# =============================================================================
# This script sets up the Vault client application as a scheduled task
# that runs under gMSA identity and reads secrets from Vault
# =============================================================================

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$TaskName = "VaultClientApp",
    [string]$Schedule = "Daily",
    [string]$Time = "02:00",
    [string[]]$SecretPaths = @("kv/data/my-app/database", "kv/data/my-app/api"),
    [switch]$ForceUpdate,
    [switch]$CheckUpdates
)

# =============================================================================
# Check for Updates
# =============================================================================

function Test-ScriptUpdates {
    param([string]$ScriptsDir)
    
    Write-Host "Checking for script updates..." -ForegroundColor Yellow
    
    $sourceScript = "vault-client-app.ps1"
    $targetScript = "$ScriptsDir\vault-client-app.ps1"
    
    if (-not (Test-Path $sourceScript)) {
        Write-Host "ERROR: Source script not found: $sourceScript" -ForegroundColor Red
        return $false
    }
    
    if (-not (Test-Path $targetScript)) {
        Write-Host "⚠️ Target script not found: $targetScript" -ForegroundColor Yellow
        Write-Host "Run setup without -CheckUpdates to create the initial installation" -ForegroundColor Cyan
        return $false
    }
    
    # Extract version from source script
    $sourceContent = Get-Content $sourceScript -Raw
    $sourceVersion = if ($sourceContent -match 'Script version:\s*([^\s]+)') { $matches[1] } else { "unknown" }
    
    # Extract version from target script
    $targetContent = Get-Content $targetScript -Raw
    $targetVersion = if ($targetContent -match 'Script version:\s*([^\s]+)') { $matches[1] } else { "unknown" }
    
    Write-Host "Source script version: $sourceVersion" -ForegroundColor Cyan
    Write-Host "Target script version: $targetVersion" -ForegroundColor Cyan
    
    if ($sourceVersion -eq $targetVersion -and $sourceVersion -ne "unknown") {
        Write-Host "SUCCESS: Script versions match, no update needed" -ForegroundColor Green
        Write-Host "Note: Run setup again to force overwrite with current directory version" -ForegroundColor Cyan
        return $false
    } else {
        Write-Host "WARNING: Script versions differ, update available!" -ForegroundColor Yellow
        Write-Host "Run: .\setup-vault-client.ps1" -ForegroundColor Cyan
        Write-Host "The setup script will always overwrite with the current directory version" -ForegroundColor Cyan
        return $true
    }
}

# =============================================================================
# Prerequisites Check
# =============================================================================

function Test-Prerequisites {
    Write-Host "Checking prerequisites..." -ForegroundColor Yellow
    
    # Check if running as Administrator
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
        return $false
    }
    Write-Host "SUCCESS: Running as Administrator" -ForegroundColor Green
    
    # Check if gMSA is installed
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $gmsaTest = Test-ADServiceAccount -Identity "vault-gmsa" -ErrorAction Stop
        if ($gmsaTest) {
            Write-Host "SUCCESS: gMSA 'vault-gmsa' is installed and working" -ForegroundColor Green
        } else {
            Write-Host "ERROR: gMSA 'vault-gmsa' is not working properly" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "ERROR: Cannot test gMSA: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Make sure RSAT Active Directory PowerShell module is installed" -ForegroundColor Yellow
        return $false
    }
    
    # Check Vault connectivity
    try {
        $vaultHost = ($VaultUrl -replace "https://", "" -replace "http://", "" -replace ":8200", "")
        $connection = Test-NetConnection -ComputerName $vaultHost -Port 8200 -WarningAction SilentlyContinue
        if ($connection.TcpTestSucceeded) {
            Write-Host "SUCCESS: Vault server is reachable: $vaultHost:8200" -ForegroundColor Green
        } else {
            Write-Host "ERROR: Cannot reach Vault server: $vaultHost:8200" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "ERROR: Network connectivity test failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    
    return $true
}

# =============================================================================
# Create Application Directory Structure
# =============================================================================

function New-ApplicationStructure {
    Write-Host "Creating application directory structure..." -ForegroundColor Yellow
    
    $appDir = "C:\vault-client"
    $configDir = "$appDir\config"
    $logsDir = "$appDir\logs"
    $scriptsDir = "$appDir\scripts"
    
    # Create directories
    @($appDir, $configDir, $logsDir, $scriptsDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
            Write-Host "SUCCESS: Created directory: $_" -ForegroundColor Green
        } else {
            Write-Host "SUCCESS: Directory exists: $_" -ForegroundColor Green
        }
    }
    
    return @{
        AppDir = $appDir
        ConfigDir = $configDir
        LogsDir = $logsDir
        ScriptsDir = $scriptsDir
    }
}

# =============================================================================
# Copy Application Script
# =============================================================================

function Copy-ApplicationScript {
    param([string]$ScriptsDir)
    
    Write-Host "Setting up application script..." -ForegroundColor Yellow
    
    $sourceScript = "vault-client-app.ps1"
    $targetScript = "$ScriptsDir\vault-client-app.ps1"
    
    if (Test-Path $sourceScript) {
        Write-Host "Source script found: $sourceScript" -ForegroundColor Green
        
        # Extract version from source script
        $sourceContent = Get-Content $sourceScript -Raw
        $sourceVersion = if ($sourceContent -match 'Script version:\s*([^\s]+)') { $matches[1] } else { "unknown" }
        Write-Host "Source script version: $sourceVersion" -ForegroundColor Cyan
        
        # Always create backup of existing script if it exists
        if (Test-Path $targetScript) {
            $backupScript = "$targetScript.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item $targetScript $backupScript -Force
            Write-Host "SUCCESS: Created backup: $backupScript" -ForegroundColor Green
            
            # Show target version for comparison
            $targetContent = Get-Content $targetScript -Raw
            $targetVersion = if ($targetContent -match 'Script version:\s*([^\s]+)') { $matches[1] } else { "unknown" }
            Write-Host "Previous target script version: $targetVersion" -ForegroundColor Cyan
        }
        
        # Always overwrite with current directory script
        Write-Host "UPDATING: Overwriting scheduled task script with current directory version..." -ForegroundColor Yellow
        
        try {
            Copy-Item $sourceScript $targetScript -Force -ErrorAction Stop
            Write-Host "SUCCESS: Copy operation completed" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Copy operation failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Source: $sourceScript" -ForegroundColor Yellow
            Write-Host "Target: $targetScript" -ForegroundColor Yellow
            Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
            return $null
        }
        
        # Verify the copy worked
        if (Test-Path $targetScript) {
            $copiedContent = Get-Content $targetScript -Raw
            $copiedVersion = if ($copiedContent -match 'Script version:\s*([^\s]+)') { $matches[1] } else { "unknown" }
            Write-Host "SUCCESS: Application script updated: $targetScript" -ForegroundColor Green
            Write-Host "SUCCESS: Copied script version: $copiedVersion" -ForegroundColor Green
            
            # Verify file size
            $fileSize = (Get-Item $targetScript).Length
            Write-Host "SUCCESS: File size: $fileSize bytes" -ForegroundColor Green
            
            # Note: Scheduled task will be created/updated in the main setup process
            
            Write-Host "DEBUG: About to return targetScript: $targetScript" -ForegroundColor Magenta
            Write-Host "DEBUG: targetScript type: $($targetScript.GetType().Name)" -ForegroundColor Magenta
            return $targetScript
        } else {
            Write-Host "ERROR: Failed to copy script to: $targetScript" -ForegroundColor Red
            Write-Host "Source script exists: $(Test-Path $sourceScript)" -ForegroundColor Yellow
            Write-Host "Target directory exists: $(Test-Path (Split-Path $targetScript))" -ForegroundColor Yellow
            return $null
        }
    } else {
        Write-Host "ERROR: Source script not found: $sourceScript" -ForegroundColor Red
        Write-Host "Make sure vault-client-app.ps1 is in the current directory" -ForegroundColor Yellow
        return $null
    }
}

# =============================================================================
# Update Scheduled Task Script
# =============================================================================

function Update-ScheduledTaskScript {
    param(
        [string]$TaskName,
        [string]$ScriptPath
    )
    
    try {
        # Verify the script path exists before updating the task
        if (-not (Test-Path $ScriptPath)) {
            Write-Host "ERROR: Script path does not exist: $ScriptPath" -ForegroundColor Red
            return $false
        }
        
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            # Get current task settings
            $currentAction = $existingTask.Actions[0]
            $currentTrigger = $existingTask.Triggers[0]
            $currentSettings = $existingTask.Settings
            $currentPrincipal = $existingTask.Principal
            
            # Create new action with updated script path
            $absoluteScriptPath = (Resolve-Path $ScriptPath).Path
            $actionArgs = "-ExecutionPolicy Bypass -File `"$absoluteScriptPath`""
            $newAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $actionArgs
            
            Write-Host "Updating scheduled task with absolute script path: $absoluteScriptPath" -ForegroundColor Cyan
            Write-Host "Task arguments: $actionArgs" -ForegroundColor Cyan
            
            # Update the task
            Set-ScheduledTask -TaskName $TaskName -Action $newAction -Trigger $currentTrigger -Settings $currentSettings -Principal $currentPrincipal
            
            Write-Host "SUCCESS: Scheduled task updated with new script path" -ForegroundColor Green
            Write-Host "   Script path: $ScriptPath" -ForegroundColor Cyan
            
            # Verify the update worked
            $updatedTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($updatedTask) {
                $updatedAction = $updatedTask.Actions[0]
                Write-Host "SUCCESS: Verified scheduled task update successful" -ForegroundColor Green
                Write-Host "   Task arguments: $($updatedAction.Arguments)" -ForegroundColor Cyan
                
                # Verify the script path in the arguments
                if ($updatedAction.Arguments -like "*`"$absoluteScriptPath`"*") {
                    Write-Host "SUCCESS: Script path correctly set in task arguments" -ForegroundColor Green
                } else {
                    Write-Host "WARNING: Script path may not be correctly set in task arguments" -ForegroundColor Yellow
                    Write-Host "   Expected: *`"$absoluteScriptPath`"*" -ForegroundColor Cyan
                    Write-Host "   Actual: $($updatedAction.Arguments)" -ForegroundColor Cyan
                }
            }
            
            return $true
        } else {
            Write-Host "WARNING: Scheduled task not found, will be created during setup" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "ERROR: Failed to update scheduled task: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# =============================================================================
# Create Scheduled Task
# =============================================================================

function New-VaultClientScheduledTask {
    param(
        [string]$ScriptPath,
        [string]$TaskName,
        [string]$Schedule,
        [string]$Time,
        [string]$VaultUrl,
        [string]$VaultRole,
        [string[]]$SecretPaths
    )
    
    Write-Host "Creating scheduled task..." -ForegroundColor Yellow
    
    try {
        # Remove existing task if it exists
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "SUCCESS: Removed existing task: $TaskName" -ForegroundColor Green
        }
        
        # Create action with proper script path handling
        $secretPathsParam = $SecretPaths -join '","'
        
        # Verify the script path exists before creating the task
        Write-Host "Verifying script path: $ScriptPath" -ForegroundColor Cyan
        Write-Host "Script path type: $($ScriptPath.GetType().Name)" -ForegroundColor Cyan
        
        if (-not (Test-Path $ScriptPath)) {
            Write-Host "ERROR: Script path does not exist: $ScriptPath" -ForegroundColor Red
            Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
            Write-Host "Available files:" -ForegroundColor Yellow
            Get-ChildItem -Path (Split-Path $ScriptPath) -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor Gray }
            return $false
        }
        
        # Use absolute path and ensure proper escaping
        $absoluteScriptPath = (Resolve-Path $ScriptPath).Path
        Write-Host "Creating scheduled task action with absolute script path: $absoluteScriptPath" -ForegroundColor Cyan
        
        # Create arguments with proper escaping
        $actionArgs = "-ExecutionPolicy Bypass -File `"$absoluteScriptPath`" -VaultUrl `"$VaultUrl`" -VaultRole `"$VaultRole`" -SecretPaths @(`"$secretPathsParam`")"
        
        Write-Host "Task arguments: $actionArgs" -ForegroundColor Cyan
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $actionArgs
        
        # Create trigger based on schedule
        switch ($Schedule.ToLower()) {
            "daily" {
                $trigger = New-ScheduledTaskTrigger -Daily -At $Time
            }
            "weekly" {
                $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $Time
            }
            "hourly" {
                $trigger = New-ScheduledTaskTrigger -Once -At $Time -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 365)
            }
            default {
                $trigger = New-ScheduledTaskTrigger -Daily -At $Time
            }
        }
        
        # Create settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
        
        # Register task under gMSA identity with correct LogonType
        # Key: Use LogonType Password for gMSA (Windows fetches password from AD)
        $principal = New-ScheduledTaskPrincipal -UserId "local.lab\vault-gmsa$" -LogonType Password -RunLevel Highest
        
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal
        
        Write-Host "SUCCESS: Scheduled task created successfully: $TaskName" -ForegroundColor Green
        Write-Host "   - Identity: local.lab\vault-gmsa$" -ForegroundColor Cyan
        Write-Host "   - Schedule: $Schedule at $Time" -ForegroundColor Cyan
        Write-Host "   - Script: $ScriptPath" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "IMPORTANT: Ensure gMSA has 'Log on as a batch job' right:" -ForegroundColor Yellow
        Write-Host "   1. Run secpol.msc on this machine" -ForegroundColor Yellow
        Write-Host "   2. Navigate to: Local Policies → User Rights Assignment → Log on as a batch job" -ForegroundColor Yellow
        Write-Host "   3. Add: local.lab\vault-gmsa$" -ForegroundColor Yellow
        Write-Host "   4. Or configure via GPO if domain-managed" -ForegroundColor Yellow
        
        return $true
        
    } catch {
        Write-Host "ERROR: Failed to create scheduled task: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# =============================================================================
# Create Configuration Files
# =============================================================================

function New-ConfigurationFiles {
    param([string]$ConfigDir, [string]$VaultUrl, [string]$VaultRole, [string[]]$SecretPaths)
    
    Write-Host "Creating configuration files..." -ForegroundColor Yellow
    
    # Create main configuration file
    $config = @{
        vault_url = $VaultUrl
        vault_role = $VaultRole
        secret_paths = $SecretPaths
        config_output_dir = $ConfigDir
        created_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        created_by = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
    
    $config | ConvertTo-Json -Depth 3 | Out-File -FilePath "$ConfigDir\vault-client-config.json" -Encoding UTF8
    Write-Host "SUCCESS: Configuration file created: $ConfigDir\vault-client-config.json" -ForegroundColor Green
    
    # Create example secrets in Vault (instructions)
    $vaultInstructions = @"
# Vault Secrets Setup Instructions
# ================================

Before running the client application, ensure these secrets exist in Vault:

1. Database Secret:
   vault kv put kv/my-app/database host="db-server.local.lab" username="app-user" password="secure-password"

2. API Secret:
   vault kv put kv/my-app/api api_key="your-api-key" endpoint="https://api.local.lab"

3. Verify secrets:
   vault kv get kv/my-app/database
   vault kv get kv/my-app/api

4. Check Vault auth method configuration:
   vault read auth/gmsa/config
   vault read auth/gmsa/role/vault-gmsa-role

# Application Configuration
# ========================
Vault URL: $VaultUrl
Vault Role: $VaultRole
Secret Paths: $($SecretPaths -join ', ')
Config Directory: $ConfigDir

# Scheduled Task
# ==============
Task Name: $TaskName
Schedule: $Schedule at $Time
Identity: local.lab\vault-gmsa$
"@
    
    $vaultInstructions | Out-File -FilePath "$ConfigDir\VAULT_SETUP_INSTRUCTIONS.txt" -Encoding UTF8
    Write-Host "SUCCESS: Setup instructions created: $ConfigDir\VAULT_SETUP_INSTRUCTIONS.txt" -ForegroundColor Green
}

# =============================================================================
# Test the Setup
# =============================================================================

function Test-Setup {
    param([string]$TaskName, [string]$ScriptPath)
    
    Write-Host "Testing the setup..." -ForegroundColor Yellow
    
    try {
        # Check if task exists
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        Write-Host "SUCCESS: Scheduled task exists: $($task.TaskName)" -ForegroundColor Green
        Write-Host "   - State: $($task.State)" -ForegroundColor Cyan
        Write-Host "   - Principal: $($task.Principal.UserId)" -ForegroundColor Cyan
        
        # Check if script exists
        if (Test-Path $ScriptPath) {
            $absoluteScriptPath = (Resolve-Path $ScriptPath).Path
            Write-Host "SUCCESS: Application script exists: $absoluteScriptPath" -ForegroundColor Green
            
            # Verify script version
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptVersion = if ($scriptContent -match 'Script version:\s*([^\s]+)') { $matches[1] } else { "unknown" }
            Write-Host "   - Script version: $scriptVersion" -ForegroundColor Cyan
            
            # Check script size
            $scriptSize = (Get-Item $ScriptPath).Length
            Write-Host "   - Script size: $scriptSize bytes" -ForegroundColor Cyan
            
            # Verify the scheduled task is pointing to the correct script
            $taskAction = $task.Actions[0]
            if ($taskAction.Arguments -like "*`"$absoluteScriptPath`"*") {
                Write-Host "SUCCESS: Scheduled task points to correct script path" -ForegroundColor Green
            } else {
                Write-Host "WARNING: Scheduled task may not point to correct script path" -ForegroundColor Yellow
                Write-Host "   Expected: *`"$absoluteScriptPath`"*" -ForegroundColor Cyan
                Write-Host "   Actual: $($taskAction.Arguments)" -ForegroundColor Cyan
            }
        } else {
            Write-Host "ERROR: Application script not found: $ScriptPath" -ForegroundColor Red
            return $false
        }
        
        # Test run the script manually
        Write-Host "Running application test..." -ForegroundColor Yellow
        
        # Test by running the scheduled task (which runs under gMSA identity)
        Write-Host "Starting scheduled task to test gMSA authentication..." -ForegroundColor Cyan
        Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        
        # Wait a moment for the task to start
        Start-Sleep -Seconds 3
        
        # Check if the task is running
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($taskInfo) {
            Write-Host "SUCCESS: Scheduled task test initiated successfully" -ForegroundColor Green
            Write-Host "   - Task State: $($taskInfo.State)" -ForegroundColor Cyan
            Write-Host "   - Last Run: $($taskInfo.LastRunTime)" -ForegroundColor Cyan
            Write-Host "   - Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Cyan
            Write-Host "   - Check logs at: C:\vault-client\config\vault-client.log" -ForegroundColor Cyan
            
            # Check if log file was created
            $logFile = "C:\vault-client\config\vault-client.log"
            if (Test-Path $logFile) {
                Write-Host "SUCCESS: Log file exists: $logFile" -ForegroundColor Green
                $logSize = (Get-Item $logFile).Length
                Write-Host "   - Log file size: $logSize bytes" -ForegroundColor Cyan
                
                # Show last few lines of log
                try {
                    $lastLines = Get-Content $logFile -Tail 5 -ErrorAction SilentlyContinue
                    if ($lastLines) {
                        Write-Host "   - Recent log entries:" -ForegroundColor Cyan
                        $lastLines | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
                    }
                } catch {
                    Write-Host "   - Could not read log file" -ForegroundColor Yellow
                }
            } else {
                Write-Host "WARNING: Log file not found: $logFile" -ForegroundColor Yellow
            }
        } else {
            Write-Host "WARNING: Could not verify scheduled task execution" -ForegroundColor Yellow
        }
        
        return $true
        
    } catch {
        Write-Host "ERROR: Setup test failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# =============================================================================
# Main Setup Process
# =============================================================================

function Start-Setup {
    Write-Host "=== Vault Client Application Setup ===" -ForegroundColor Green
    Write-Host "Vault URL: $VaultUrl" -ForegroundColor Cyan
    Write-Host "Vault Role: $VaultRole" -ForegroundColor Cyan
    Write-Host "Task Name: $TaskName" -ForegroundColor Cyan
    Write-Host "Schedule: $Schedule at $Time" -ForegroundColor Cyan
    Write-Host "Secret Paths: $($SecretPaths -join ', ')" -ForegroundColor Cyan
    Write-Host ""
    
    # Handle CheckUpdates parameter
    if ($CheckUpdates) {
        Write-Host "=== Checking for Updates ===" -ForegroundColor Yellow
        $dirs = New-ApplicationStructure
        $hasUpdates = Test-ScriptUpdates -ScriptsDir $dirs.ScriptsDir
        if ($hasUpdates) {
            Write-Host ""
            Write-Host "To apply updates, run:" -ForegroundColor Yellow
            Write-Host ".\setup-vault-client.ps1 -ForceUpdate" -ForegroundColor Cyan
        }
        return
    }
    
    # Step 1: Check prerequisites
    if (-not (Test-Prerequisites)) {
        Write-Host "ERROR: Prerequisites check failed" -ForegroundColor Red
        exit 1
    }
    
    # Step 2: Create directory structure
    $dirs = New-ApplicationStructure
    
    # Step 3: Copy application script
    Write-Host "Calling Copy-ApplicationScript with ScriptsDir: $($dirs.ScriptsDir)" -ForegroundColor Cyan
    $scriptPath = Copy-ApplicationScript -ScriptsDir $dirs.ScriptsDir
    Write-Host "Script path result: $scriptPath" -ForegroundColor Cyan
    Write-Host "Script path type: $($scriptPath.GetType().Name)" -ForegroundColor Cyan
    Write-Host "Script path is null: $($scriptPath -eq $null)" -ForegroundColor Cyan
    Write-Host "Script path is false: $($scriptPath -eq $false)" -ForegroundColor Cyan
    
    if (-not $scriptPath) {
        Write-Host "ERROR: Failed to copy application script" -ForegroundColor Red
        Write-Host "Copy-ApplicationScript returned: $scriptPath" -ForegroundColor Red
        Write-Host "ScriptsDir parameter was: $($dirs.ScriptsDir)" -ForegroundColor Red
        exit 1
    }
    
    # Step 4: Create configuration files
    New-ConfigurationFiles -ConfigDir $dirs.ConfigDir -VaultUrl $VaultUrl -VaultRole $VaultRole -SecretPaths $SecretPaths
    
    # Step 5: Create scheduled task
    if (-not (New-VaultClientScheduledTask -ScriptPath $scriptPath -TaskName $TaskName -Schedule $Schedule -Time $Time -VaultUrl $VaultUrl -VaultRole $VaultRole -SecretPaths $SecretPaths)) {
        Write-Host "ERROR: Failed to create scheduled task" -ForegroundColor Red
        exit 1
    }
    
    # Step 6: Test the setup
    if (Test-Setup -TaskName $TaskName -ScriptPath $scriptPath) {
        Write-Host ""
        Write-Host "SUCCESS: Setup Completed Successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Yellow
        Write-Host "1. Ensure secrets exist in Vault (see $($dirs.ConfigDir)\VAULT_SETUP_INSTRUCTIONS.txt)" -ForegroundColor White
        Write-Host "2. Test the scheduled task manually:" -ForegroundColor White
        Write-Host "   Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
        Write-Host "3. Monitor execution:" -ForegroundColor White
        Write-Host "   Get-ScheduledTaskInfo -TaskName '$TaskName'" -ForegroundColor Gray
        Write-Host "   Get-Content '$($dirs.ConfigDir)\vault-client.log'" -ForegroundColor Gray
        Write-Host "4. Check output files:" -ForegroundColor White
        Write-Host "   Get-ChildItem '$($dirs.ConfigDir)'" -ForegroundColor Gray
        Write-Host "5. Check for updates:" -ForegroundColor White
        Write-Host "   .\setup-vault-client.ps1 -CheckUpdates" -ForegroundColor Gray
        Write-Host ""
        Write-Host "IMPORTANT: The application MUST run under gMSA identity to work properly." -ForegroundColor Yellow
        Write-Host "   Manual execution (running the script directly) will fail because it runs under your user account." -ForegroundColor Yellow
        Write-Host "   Always use the scheduled task for testing and production use." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "The application will run automatically $Schedule at $Time under gMSA identity!" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Setup test failed" -ForegroundColor Red
        exit 1
    }
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Run the setup
Start-Setup

# =============================================================================
# Usage Examples
# =============================================================================

<#
USAGE EXAMPLES:

1. Basic setup with defaults:
   .\setup-vault-client.ps1

2. Custom Vault server and role:
   .\setup-vault-client.ps1 -VaultUrl "https://vault.company.com:8200" -VaultRole "my-role"

3. Custom schedule (weekly on Monday at 3 AM):
   .\setup-vault-client.ps1 -Schedule "Weekly" -Time "03:00"

4. Custom secret paths:
   .\setup-vault-client.ps1 -SecretPaths @("secret/data/prod/db", "secret/data/prod/api")

5. Custom task name:
   .\setup-vault-client.ps1 -TaskName "MyVaultApp"

6. Check for script updates:
   .\setup-vault-client.ps1 -CheckUpdates

7. Update script (always overwrites with current directory version):
   .\setup-vault-client.ps1

8. Update with custom parameters:
   .\setup-vault-client.ps1 -VaultUrl "https://vault.company.com:8200"

WHAT THIS SETUP DOES:
- Checks prerequisites (Administrator, gMSA, Vault connectivity)
- Creates application directory structure
- Copies the client application script
- Creates scheduled task under gMSA identity
- Creates configuration files and setup instructions
- Tests the complete setup

OUTPUT STRUCTURE:
C:\vault-client\
├── config\
│   ├── vault-client-config.json
│   ├── VAULT_SETUP_INSTRUCTIONS.txt
│   ├── database-config.json (created by app)
│   ├── api-config.json (created by app)
│   ├── .env (created by app)
│   └── vault-client.log (created by app)
├── logs\
└── scripts\
    └── vault-client-app.ps1
#>
