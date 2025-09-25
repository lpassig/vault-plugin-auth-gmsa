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
    [string[]]$SecretPaths = @("kv/data/my-app/database", "kv/data/my-app/api")
)

# =============================================================================
# Prerequisites Check
# =============================================================================

function Test-Prerequisites {
    Write-Host "Checking prerequisites..." -ForegroundColor Yellow
    
    # Check if running as Administrator
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "❌ This script must be run as Administrator" -ForegroundColor Red
        return $false
    }
    Write-Host "✅ Running as Administrator" -ForegroundColor Green
    
    # Check if gMSA is installed
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $gmsaTest = Test-ADServiceAccount -Identity "vault-gmsa" -ErrorAction Stop
        if ($gmsaTest) {
            Write-Host "✅ gMSA 'vault-gmsa' is installed and working" -ForegroundColor Green
        } else {
            Write-Host "❌ gMSA 'vault-gmsa' is not working properly" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Cannot test gMSA: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Make sure RSAT Active Directory PowerShell module is installed" -ForegroundColor Yellow
        return $false
    }
    
    # Check Vault connectivity
    try {
        $vaultHost = ($VaultUrl -replace "https://", "" -replace "http://", "" -replace ":8200", "")
        $connection = Test-NetConnection -ComputerName $vaultHost -Port 8200 -WarningAction SilentlyContinue
        if ($connection.TcpTestSucceeded) {
            Write-Host "✅ Vault server is reachable: $vaultHost:8200" -ForegroundColor Green
        } else {
            Write-Host "❌ Cannot reach Vault server: $vaultHost:8200" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Network connectivity test failed: $($_.Exception.Message)" -ForegroundColor Red
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
            Write-Host "✅ Created directory: $_" -ForegroundColor Green
        } else {
            Write-Host "✅ Directory exists: $_" -ForegroundColor Green
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
        Copy-Item $sourceScript $targetScript -Force
        Write-Host "✅ Application script copied to: $targetScript" -ForegroundColor Green
        return $targetScript
    } else {
        Write-Host "❌ Source script not found: $sourceScript" -ForegroundColor Red
        Write-Host "Make sure vault-client-app.ps1 is in the current directory" -ForegroundColor Yellow
        return $null
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
            Write-Host "✅ Removed existing task: $TaskName" -ForegroundColor Green
        }
        
        # Create action
        $secretPathsParam = $SecretPaths -join '","'
        $actionArgs = "-ExecutionPolicy Bypass -File `"$ScriptPath`" -VaultUrl `"$VaultUrl`" -VaultRole `"$VaultRole`" -SecretPaths @(`"$secretPathsParam`")"
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
        # Key: Use LogonType ServiceAccount for gMSA (no password stored)
        $principal = New-ScheduledTaskPrincipal -UserId "local.lab\vault-gmsa$" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal
        
        Write-Host "✅ Scheduled task created successfully: $TaskName" -ForegroundColor Green
        Write-Host "   - Identity: local.lab\vault-gmsa$" -ForegroundColor Cyan
        Write-Host "   - Schedule: $Schedule at $Time" -ForegroundColor Cyan
        Write-Host "   - Script: $ScriptPath" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "⚠️  IMPORTANT: Ensure gMSA has 'Log on as a batch job' right:" -ForegroundColor Yellow
        Write-Host "   1. Run secpol.msc on this machine" -ForegroundColor Yellow
        Write-Host "   2. Navigate to: Local Policies → User Rights Assignment → Log on as a batch job" -ForegroundColor Yellow
        Write-Host "   3. Add: local.lab\vault-gmsa$" -ForegroundColor Yellow
        Write-Host "   4. Or configure via GPO if domain-managed" -ForegroundColor Yellow
        
        return $true
        
    } catch {
        Write-Host "❌ Failed to create scheduled task: $($_.Exception.Message)" -ForegroundColor Red
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
    Write-Host "✅ Configuration file created: $ConfigDir\vault-client-config.json" -ForegroundColor Green
    
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
    Write-Host "✅ Setup instructions created: $ConfigDir\VAULT_SETUP_INSTRUCTIONS.txt" -ForegroundColor Green
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
        Write-Host "✅ Scheduled task exists: $($task.TaskName)" -ForegroundColor Green
        Write-Host "   - State: $($task.State)" -ForegroundColor Cyan
        Write-Host "   - Principal: $($task.Principal.UserId)" -ForegroundColor Cyan
        
        # Check if script exists
        if (Test-Path $ScriptPath) {
            Write-Host "✅ Application script exists: $ScriptPath" -ForegroundColor Green
        } else {
            Write-Host "❌ Application script not found: $ScriptPath" -ForegroundColor Red
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
            Write-Host "✅ Scheduled task test initiated successfully" -ForegroundColor Green
            Write-Host "   - Task State: $($taskInfo.State)" -ForegroundColor Cyan
            Write-Host "   - Last Run: $($taskInfo.LastRunTime)" -ForegroundColor Cyan
            Write-Host "   - Check logs at: $ConfigOutputDir\vault-client.log" -ForegroundColor Cyan
        } else {
            Write-Host "⚠️ Could not verify scheduled task execution" -ForegroundColor Yellow
        }
        
        return $true
        
    } catch {
        Write-Host "❌ Setup test failed: $($_.Exception.Message)" -ForegroundColor Red
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
    
    # Step 1: Check prerequisites
    if (-not (Test-Prerequisites)) {
        Write-Host "❌ Prerequisites check failed" -ForegroundColor Red
        exit 1
    }
    
    # Step 2: Create directory structure
    $dirs = New-ApplicationStructure
    
    # Step 3: Copy application script
    $scriptPath = Copy-ApplicationScript -ScriptsDir $dirs.ScriptsDir
    if (-not $scriptPath) {
        Write-Host "❌ Failed to copy application script" -ForegroundColor Red
        exit 1
    }
    
    # Step 4: Create configuration files
    New-ConfigurationFiles -ConfigDir $dirs.ConfigDir -VaultUrl $VaultUrl -VaultRole $VaultRole -SecretPaths $SecretPaths
    
    # Step 5: Create scheduled task
    if (-not (New-VaultClientScheduledTask -ScriptPath $scriptPath -TaskName $TaskName -Schedule $Schedule -Time $Time -VaultUrl $VaultUrl -VaultRole $VaultRole -SecretPaths $SecretPaths)) {
        Write-Host "❌ Failed to create scheduled task" -ForegroundColor Red
        exit 1
    }
    
    # Step 6: Test the setup
    if (Test-Setup -TaskName $TaskName -ScriptPath $scriptPath) {
        Write-Host ""
        Write-Host "=== Setup Completed Successfully! ===" -ForegroundColor Green
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
        Write-Host ""
        Write-Host "⚠️  IMPORTANT: The application MUST run under gMSA identity to work properly." -ForegroundColor Yellow
        Write-Host "   Manual execution (running the script directly) will fail because it runs under your user account." -ForegroundColor Yellow
        Write-Host "   Always use the scheduled task for testing and production use." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "The application will run automatically $Schedule at $Time under gMSA identity!" -ForegroundColor Green
    } else {
        Write-Host "❌ Setup test failed" -ForegroundColor Red
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
