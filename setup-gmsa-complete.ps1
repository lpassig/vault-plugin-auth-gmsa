# Complete gMSA Setup Script
# This script sets up gMSA authentication from start to finish

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$DNSHostName = "vault.local.lab",
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [switch]$SkipChecks = $false
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "COMPLETE GMSA SETUP" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "SUCCESS: Running as Administrator" -ForegroundColor Green
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  gMSA Account: $GMSAAccount" -ForegroundColor White
Write-Host "  SPN: $SPN" -ForegroundColor White
Write-Host "  DNS Host Name: $DNSHostName" -ForegroundColor White
Write-Host "  Vault URL: $VaultUrl" -ForegroundColor White
Write-Host ""

# Function to create gMSA account
function New-GMSAAccount {
    Write-Host "Step 1: Creating gMSA account..." -ForegroundColor Yellow
    Write-Host "--------------------------------" -ForegroundColor Yellow
    
    try {
        $gmsa = Get-ADServiceAccount -Identity $GMSAAccount -ErrorAction SilentlyContinue
        
        if ($gmsa) {
            Write-Host "✓ gMSA account already exists" -ForegroundColor Green
            Write-Host "  Name: $($gmsa.Name)" -ForegroundColor Gray
            return $true
        } else {
            Write-Host "Creating gMSA account..." -ForegroundColor Cyan
            
            New-ADServiceAccount -Name "vault-gmsa" -DNSHostName $DNSHostName -ErrorAction Stop
            
            Write-Host "✓ gMSA account created successfully" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "❌ Error creating gMSA account: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Make sure you have Domain Admin privileges" -ForegroundColor Yellow
        return $false
    }
}

# Function to register SPN
function Register-SPN {
    Write-Host ""
    Write-Host "Step 2: Registering SPN..." -ForegroundColor Yellow
    Write-Host "-------------------------" -ForegroundColor Yellow
    
    try {
        # Check current SPN registration
        $spnResult = setspn -Q $SPN 2>&1
        
        if ($spnResult -match $GMSAAccount) {
            Write-Host "✓ SPN is already registered to gMSA account" -ForegroundColor Green
            return $true
        } elseif ($spnResult -match "No such SPN found") {
            Write-Host "SPN not found, registering..." -ForegroundColor Cyan
            
            $result = setspn -A $SPN $GMSAAccount 2>&1
            
            if ($result -match "successfully" -or $result -match "registered") {
                Write-Host "✓ SPN registered successfully" -ForegroundColor Green
                return $true
            } else {
                Write-Host "❌ SPN registration failed: $result" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "⚠ SPN is registered to a different account" -ForegroundColor Yellow
            Write-Host "Current registration: $spnResult" -ForegroundColor Gray
            
            # Ask if user wants to force transfer
            $transfer = Read-Host "Do you want to transfer SPN to gMSA account? (y/n)"
            
            if ($transfer -eq "y" -or $transfer -eq "Y") {
                Write-Host "Transferring SPN..." -ForegroundColor Cyan
                
                # Remove from current account
                setspn -D $SPN 2>&1 | Out-Null
                
                # Add to gMSA account
                $result = setspn -A $SPN $GMSAAccount 2>&1
                
                if ($result -match "successfully" -or $result -match "registered") {
                    Write-Host "✓ SPN transferred successfully" -ForegroundColor Green
                    return $true
                } else {
                    Write-Host "❌ SPN transfer failed: $result" -ForegroundColor Red
                    return $false
                }
            } else {
                Write-Host "⚠ SPN transfer skipped" -ForegroundColor Yellow
                return $false
            }
        }
    } catch {
        Write-Host "❌ Error registering SPN: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to install gMSA on client
function Install-GMSAOnClient {
    Write-Host ""
    Write-Host "Step 3: Installing gMSA on client..." -ForegroundColor Yellow
    Write-Host "-------------------------------------" -ForegroundColor Yellow
    
    try {
        $installed = Test-ADServiceAccount -Identity $GMSAAccount -ErrorAction SilentlyContinue
        
        if ($installed) {
            Write-Host "✓ gMSA is already installed on this machine" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Installing gMSA on this machine..." -ForegroundColor Cyan
            
            Install-ADServiceAccount -Identity $GMSAAccount -ErrorAction Stop
            
            Write-Host "✓ gMSA installed successfully" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "❌ Error installing gMSA: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Make sure the machine is domain-joined and you have permissions" -ForegroundColor Yellow
        return $false
    }
}

# Function to get Kerberos tickets
function Get-KerberosTickets {
    Write-Host ""
    Write-Host "Step 4: Getting Kerberos tickets..." -ForegroundColor Yellow
    Write-Host "-----------------------------------" -ForegroundColor Yellow
    
    try {
        Write-Host "Requesting Kerberos tickets..." -ForegroundColor Cyan
        
        $result = kinit -k $GMSAAccount 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Kerberos tickets obtained successfully" -ForegroundColor Green
            
            # Show tickets
            $tickets = klist 2>&1
            Write-Host "Current tickets:" -ForegroundColor Gray
            Write-Host $tickets -ForegroundColor Gray
            
            return $true
        } else {
            Write-Host "❌ Failed to get Kerberos tickets: $result" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Error getting Kerberos tickets: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to create scheduled task
function New-ScheduledTask {
    Write-Host ""
    Write-Host "Step 5: Creating scheduled task..." -ForegroundColor Yellow
    Write-Host "-----------------------------------" -ForegroundColor Yellow
    
    try {
        # Create directories
        $scriptDir = "C:\vault-client"
        $logDir = "$scriptDir\logs"
        
        if (-not (Test-Path $scriptDir)) {
            New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
            Write-Host "✓ Created directory: $scriptDir" -ForegroundColor Green
        }
        
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            Write-Host "✓ Created directory: $logDir" -ForegroundColor Green
        }
        
        # Create the gMSA client script
        $scriptPath = "$scriptDir\vault-gmsa-client.ps1"
        
        $scriptContent = @'
# Vault gMSA Client for Scheduled Task
param([string]$VaultUrl = "https://vault.local.lab:8200")

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    $logFile = "C:\vault-client\logs\vault-gmsa-$(Get-Date -Format 'yyyy-MM-dd').log"
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}

Write-Log "Starting Vault gMSA authentication..." "INFO"
Write-Log "Current user: $(whoami)" "INFO"

# Bypass SSL for testing
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

try {
    Write-Log "Authenticating with Vault..." "INFO"
    
    $response = Invoke-RestMethod -Uri "$VaultUrl/v1/auth/kerberos/login" -Method Post -UseDefaultCredentials -UseBasicParsing -ErrorAction Stop
    
    if ($response.auth -and $response.auth.client_token) {
        Write-Log "SUCCESS: Authentication successful!" "SUCCESS"
        Write-Log "Token: $($response.auth.client_token)" "INFO"
        
        # Test token
        $headers = @{"X-Vault-Token" = $response.auth.client_token}
        $testResponse = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/health" -Headers $headers -UseBasicParsing
        Write-Log "SUCCESS: Token validation successful!" "SUCCESS"
        exit 0
    } else {
        Write-Log "ERROR: No token received" "ERROR"
        exit 1
    }
} catch {
    Write-Log "ERROR: Authentication failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
'@

        Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8
        Write-Host "✓ Created gMSA client script: $scriptPath" -ForegroundColor Green
        
        # Create scheduled task
        $taskName = "Vault-gMSA-Authentication"
        
        # Remove existing task
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Host "✓ Removed existing task" -ForegroundColor Green
        }
        
        # Create new task
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 365)
        $principal = New-ScheduledTaskPrincipal -UserId $GMSAAccount -LogonType Password -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Vault gMSA Authentication"
        
        Write-Host "✓ Created scheduled task: $taskName" -ForegroundColor Green
        Write-Host "✓ Task runs under: $GMSAAccount" -ForegroundColor Green
        Write-Host "✓ Task runs every 5 minutes" -ForegroundColor Green
        
        return $true
    } catch {
        Write-Host "❌ Error creating scheduled task: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to test the setup
function Test-Setup {
    Write-Host ""
    Write-Host "Step 6: Testing the setup..." -ForegroundColor Yellow
    Write-Host "-----------------------------" -ForegroundColor Yellow
    
    try {
        $taskName = "Vault-gMSA-Authentication"
        
        Write-Host "Starting scheduled task manually..." -ForegroundColor Cyan
        Start-ScheduledTask -TaskName $taskName
        
        Write-Host "Waiting for execution..." -ForegroundColor Cyan
        Start-Sleep -Seconds 10
        
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
        Write-Host "Execution result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
        
        if ($taskInfo.LastTaskResult -eq 0) {
            Write-Host "✓ Test execution successful!" -ForegroundColor Green
            
            # Show recent logs
            $logDir = "C:\vault-client\logs"
            if (Test-Path $logDir) {
                $logFiles = Get-ChildItem -Path $logDir -Filter "vault-gmsa-*.log" -ErrorAction SilentlyContinue
                if ($logFiles) {
                    $latestLog = $logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    Write-Host ""
                    Write-Host "Recent log entries:" -ForegroundColor Cyan
                    $lastLines = Get-Content -Path $latestLog.FullName -Tail 5
                    foreach ($line in $lastLines) {
                        Write-Host "  $line" -ForegroundColor Gray
                    }
                }
            }
            
            return $true
        } else {
            Write-Host "❌ Test execution failed (Result: $($taskInfo.LastTaskResult))" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Error testing setup: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main execution
function Main {
    Write-Host "Starting complete gMSA setup..." -ForegroundColor Green
    Write-Host ""
    
    # Run all setup steps
    $step1 = New-GMSAAccount
    $step2 = Register-SPN
    $step3 = Install-GMSAOnClient
    $step4 = Get-KerberosTickets
    $step5 = New-ScheduledTask
    $step6 = Test-Setup
    
    # Summary
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "SETUP SUMMARY" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Results:" -ForegroundColor Yellow
    Write-Host "  gMSA Account: $(if ($step1) { '✓ SUCCESS' } else { '❌ FAILED' })" -ForegroundColor $(if ($step1) { 'Green' } else { 'Red' })
    Write-Host "  SPN Registration: $(if ($step2) { '✓ SUCCESS' } else { '❌ FAILED' })" -ForegroundColor $(if ($step2) { 'Green' } else { 'Red' })
    Write-Host "  gMSA Installation: $(if ($step3) { '✓ SUCCESS' } else { '❌ FAILED' })" -ForegroundColor $(if ($step3) { 'Green' } else { 'Red' })
    Write-Host "  Kerberos Tickets: $(if ($step4) { '✓ SUCCESS' } else { '❌ FAILED' })" -ForegroundColor $(if ($step4) { 'Green' } else { 'Red' })
    Write-Host "  Scheduled Task: $(if ($step5) { '✓ SUCCESS' } else { '❌ FAILED' })" -ForegroundColor $(if ($step5) { 'Green' } else { 'Red' })
    Write-Host "  Test Execution: $(if ($step6) { '✓ SUCCESS' } else { '❌ FAILED' })" -ForegroundColor $(if ($step6) { 'Green' } else { 'Red' })
    
    Write-Host ""
    
    if ($step1 -and $step2 -and $step3 -and $step4 -and $step5 -and $step6) {
        Write-Host "🎉 SUCCESS: Complete gMSA setup is working!" -ForegroundColor Green
        Write-Host "Your gMSA authentication with Vault is now fully configured." -ForegroundColor Green
        Write-Host ""
        Write-Host "Manual commands:" -ForegroundColor Yellow
        Write-Host "  Start task: Start-ScheduledTask -TaskName 'Vault-gMSA-Authentication'" -ForegroundColor White
        Write-Host "  View logs: Get-Content 'C:\vault-client\logs\vault-gmsa-*.log' -Tail 20" -ForegroundColor White
        Write-Host "  Check status: .\check-gmsa-status.ps1" -ForegroundColor White
    } else {
        Write-Host "⚠ SETUP INCOMPLETE: Some steps failed" -ForegroundColor Yellow
        Write-Host "Please review the errors above and retry the failed steps." -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "SETUP COMPLETE" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
}

# Run main function
Main