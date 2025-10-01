# Verify gMSA Setup and Scheduled Task
# This script verifies that gMSA is properly configured for scheduled task execution

param(
    [string]$GMSAAccount = "LOCAL\vault-gmsa$",
    [string]$SPN = "HTTP/vault.local.lab"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "GMSA SETUP VERIFICATION" -ForegroundColor Cyan
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
Write-Host "  Current User: $(whoami)" -ForegroundColor White
Write-Host ""

# Function to check gMSA account
function Test-GMSAAccount {
    Write-Host "Step 1: Checking gMSA account..." -ForegroundColor Yellow
    Write-Host "--------------------------------" -ForegroundColor Yellow
    
    try {
        $gmsa = Get-ADServiceAccount -Identity $GMSAAccount -ErrorAction SilentlyContinue
        
        if ($gmsa) {
            Write-Host "✓ gMSA account exists" -ForegroundColor Green
            Write-Host "  Name: $($gmsa.Name)" -ForegroundColor Gray
            Write-Host "  SID: $($gmsa.SID)" -ForegroundColor Gray
            Write-Host "  Enabled: $($gmsa.Enabled)" -ForegroundColor Gray
            
            # Check if we can retrieve password
            try {
                $password = Get-ADServiceAccountPassword -Identity $GMSAAccount -ErrorAction SilentlyContinue
                if ($password) {
                    Write-Host "✓ Can retrieve gMSA password" -ForegroundColor Green
                } else {
                    Write-Host "⚠ Cannot retrieve gMSA password" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "⚠ Cannot retrieve gMSA password: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            
            return $true
        } else {
            Write-Host "❌ gMSA account does not exist" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Error checking gMSA account: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to check SPN registration
function Test-SPNRegistration {
    Write-Host ""
    Write-Host "Step 2: Checking SPN registration..." -ForegroundColor Yellow
    Write-Host "------------------------------------" -ForegroundColor Yellow
    
    try {
        $spnResult = setspn -Q $SPN 2>&1
        Write-Host "SPN query result:" -ForegroundColor White
        Write-Host $spnResult -ForegroundColor Gray
        
        if ($spnResult -match $GMSAAccount) {
            Write-Host "✓ SPN is registered to gMSA account" -ForegroundColor Green
            return $true
        } elseif ($spnResult -match "No such SPN found") {
            Write-Host "❌ SPN is not registered" -ForegroundColor Red
            return $false
        } else {
            Write-Host "⚠ SPN is registered to a different account" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "❌ Error checking SPN registration: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to check scheduled task
function Test-ScheduledTask {
    Write-Host ""
    Write-Host "Step 3: Checking scheduled task..." -ForegroundColor Yellow
    Write-Host "-----------------------------------" -ForegroundColor Yellow
    
    $taskName = "Vault-gMSA-Authentication"
    
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        
        if ($task) {
            Write-Host "✓ Scheduled task exists: $taskName" -ForegroundColor Green
            Write-Host "  State: $($task.State)" -ForegroundColor Gray
            Write-Host "  Principal: $($task.Principal.UserId)" -ForegroundColor Gray
            
            # Check if principal matches gMSA account
            if ($task.Principal.UserId -eq $GMSAAccount) {
                Write-Host "✓ Task runs under correct gMSA account" -ForegroundColor Green
            } else {
                Write-Host "⚠ Task runs under different account: $($task.Principal.UserId)" -ForegroundColor Yellow
            }
            
            # Check task info
            $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
            Write-Host "  Last Run Time: $($taskInfo.LastRunTime)" -ForegroundColor Gray
            Write-Host "  Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
            
            if ($taskInfo.LastTaskResult -eq 0) {
                Write-Host "✓ Task executed successfully last time" -ForegroundColor Green
            } elseif ($taskInfo.LastTaskResult -eq 267014) {
                Write-Host "⚠ Task has not run yet" -ForegroundColor Yellow
            } else {
                Write-Host "⚠ Task had issues last time (Result: $($taskInfo.LastTaskResult))" -ForegroundColor Yellow
            }
            
            return $true
        } else {
            Write-Host "❌ Scheduled task does not exist: $taskName" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Error checking scheduled task: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to check log files
function Test-LogFiles {
    Write-Host ""
    Write-Host "Step 4: Checking log files..." -ForegroundColor Yellow
    Write-Host "-----------------------------" -ForegroundColor Yellow
    
    $logDir = "C:\vault-client\logs"
    
    if (Test-Path $logDir) {
        Write-Host "✓ Log directory exists: $logDir" -ForegroundColor Green
        
        $logFiles = Get-ChildItem -Path $logDir -Filter "vault-gmsa-*.log" -ErrorAction SilentlyContinue
        
        if ($logFiles) {
            Write-Host "✓ Found $($logFiles.Count) log files" -ForegroundColor Green
            
            $latestLog = $logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            Write-Host "  Latest log: $($latestLog.Name)" -ForegroundColor Gray
            Write-Host "  Last modified: $($latestLog.LastWriteTime)" -ForegroundColor Gray
            
            # Show last few lines
            Write-Host ""
            Write-Host "Last 5 lines from latest log:" -ForegroundColor Cyan
            $lastLines = Get-Content -Path $latestLog.FullName -Tail 5
            foreach ($line in $lastLines) {
                Write-Host "  $line" -ForegroundColor Gray
            }
            
            return $true
        } else {
            Write-Host "⚠ No log files found" -ForegroundColor Yellow
            return $false
        }
    } else {
        Write-Host "❌ Log directory does not exist: $logDir" -ForegroundColor Red
        return $false
    }
}

# Function to test manual execution
function Test-ManualExecution {
    Write-Host ""
    Write-Host "Step 5: Testing manual execution..." -ForegroundColor Yellow
    Write-Host "-----------------------------------" -ForegroundColor Yellow
    
    $taskName = "Vault-gMSA-Authentication"
    
    try {
        Write-Host "Starting scheduled task manually..." -ForegroundColor Cyan
        Start-ScheduledTask -TaskName $taskName
        
        Write-Host "Waiting for execution..." -ForegroundColor Cyan
        Start-Sleep -Seconds 10
        
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
        Write-Host "Execution result: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
        
        if ($taskInfo.LastTaskResult -eq 0) {
            Write-Host "✓ Manual execution successful!" -ForegroundColor Green
            return $true
        } else {
            Write-Host "❌ Manual execution failed (Result: $($taskInfo.LastTaskResult))" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Error testing manual execution: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main execution
function Main {
    Write-Host "Starting gMSA setup verification..." -ForegroundColor Green
    Write-Host ""
    
    # Run all tests
    $gmsaAccount = Test-GMSAAccount
    $spnRegistration = Test-SPNRegistration
    $scheduledTask = Test-ScheduledTask
    $logFiles = Test-LogFiles
    
    # Ask if user wants to test manual execution
    Write-Host ""
    $testManual = Read-Host "Do you want to test manual execution? (y/n)"
    
    $manualExecution = $false
    if ($testManual -eq "y" -or $testManual -eq "Y") {
        $manualExecution = Test-ManualExecution
    }
    
    # Summary
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "VERIFICATION SUMMARY" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Results:" -ForegroundColor Yellow
    Write-Host "  gMSA Account: $(if ($gmsaAccount) { '✓ PASS' } else { '❌ FAIL' })" -ForegroundColor $(if ($gmsaAccount) { 'Green' } else { 'Red' })
    Write-Host "  SPN Registration: $(if ($spnRegistration) { '✓ PASS' } else { '❌ FAIL' })" -ForegroundColor $(if ($spnRegistration) { 'Green' } else { 'Red' })
    Write-Host "  Scheduled Task: $(if ($scheduledTask) { '✓ PASS' } else { '❌ FAIL' })" -ForegroundColor $(if ($scheduledTask) { 'Green' } else { 'Red' })
    Write-Host "  Log Files: $(if ($logFiles) { '✓ PASS' } else { '❌ FAIL' })" -ForegroundColor $(if ($logFiles) { 'Green' } else { 'Red' })
    
    if ($testManual -eq "y" -or $testManual -eq "Y") {
        Write-Host "  Manual Execution: $(if ($manualExecution) { '✓ PASS' } else { '❌ FAIL' })" -ForegroundColor $(if ($manualExecution) { 'Green' } else { 'Red' })
    }
    
    Write-Host ""
    
    if ($gmsaAccount -and $spnRegistration -and $scheduledTask) {
        Write-Host "🎉 SUCCESS: gMSA setup is working correctly!" -ForegroundColor Green
        Write-Host "Your scheduled task should be able to authenticate with Vault using gMSA." -ForegroundColor Green
    } else {
        Write-Host "❌ ISSUES FOUND: gMSA setup needs attention" -ForegroundColor Red
        Write-Host ""
        Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
        
        if (-not $gmsaAccount) {
            Write-Host "1. Create gMSA account: New-ADServiceAccount -Name vault-gmsa -DNSHostName vault.local.lab" -ForegroundColor White
        }
        
        if (-not $spnRegistration) {
            Write-Host "2. Register SPN: setspn -A HTTP/vault.local.lab LOCAL\vault-gmsa$" -ForegroundColor White
        }
        
        if (-not $scheduledTask) {
            Write-Host "3. Create scheduled task: .\create-gmsa-task-simple.ps1" -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "VERIFICATION COMPLETE" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
}

# Run main function
Main
