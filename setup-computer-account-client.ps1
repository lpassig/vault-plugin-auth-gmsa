# Setup Windows Client for Computer Account Authentication
# Run this on the Windows CLIENT (EC2AMAZ-UB1QVDL)

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$Role = "default",
    [string]$ScriptPath = "C:\vault-client\scripts\vault-client-app.ps1",
    [string]$LogPath = "C:\vault-client\logs"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "COMPUTER ACCOUNT CLIENT SETUP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Create directories
Write-Host "Step 1: Creating directories..." -ForegroundColor Yellow
$directories = @(
    "C:\vault-client\scripts",
    "C:\vault-client\logs"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  ✓ Created: $dir" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Exists: $dir" -ForegroundColor Green
    }
}

# Step 2: Copy vault-client-app.ps1
Write-Host ""
Write-Host "Step 2: Deploying vault-client-app.ps1..." -ForegroundColor Yellow

$sourceScript = ".\vault-client-app.ps1"
if (Test-Path $sourceScript) {
    Copy-Item -Path $sourceScript -Destination $ScriptPath -Force
    Write-Host "  ✓ Deployed: $ScriptPath" -ForegroundColor Green
} else {
    Write-Host "  ✗ ERROR: vault-client-app.ps1 not found in current directory!" -ForegroundColor Red
    Write-Host "  Please run this script from the directory containing vault-client-app.ps1" -ForegroundColor Red
    exit 1
}

# Step 3: Create scheduled task
Write-Host ""
Write-Host "Step 3: Creating scheduled task..." -ForegroundColor Yellow

$taskName = "Vault Computer Account Auth"
$taskDescription = "Authenticate to Vault using computer account (SYSTEM identity)"

# Remove existing task if it exists
$existingTask = schtasks /Query /TN "$taskName" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  Removing existing task..." -ForegroundColor Yellow
    schtasks /Delete /TN "$taskName" /F | Out-Null
}

# Create scheduled task using schtasks command (avoid XML parsing issues)
# Build the task using schtasks /Create with parameters
$action = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -VaultUrl `"$VaultUrl`" -Role `"$Role`""

# Create the task with basic settings
schtasks /Create /TN "$taskName" /TR "$action" /SC HOURLY /RU "NT AUTHORITY\SYSTEM" /RL HIGHEST /F | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Scheduled task created: $taskName" -ForegroundColor Green
    Write-Host "  ✓ Runs as: NT AUTHORITY\SYSTEM" -ForegroundColor Green
    Write-Host "  ✓ Trigger: Every 1 hour" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to create scheduled task!" -ForegroundColor Red
    exit 1
}

# Step 4: Verify setup
Write-Host ""
Write-Host "Step 4: Verifying setup..." -ForegroundColor Yellow

# Check task exists
$task = schtasks /Query /TN "$taskName" /FO LIST /V 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Scheduled task verified" -ForegroundColor Green
    
    # Show task details
    $taskInfo = $task | Select-String "Task To Run", "Run As User", "Next Run Time"
    $taskInfo | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
} else {
    Write-Host "  ✗ Scheduled task verification failed!" -ForegroundColor Red
}

# Check script exists
if (Test-Path $ScriptPath) {
    $scriptVersion = Select-String -Path $ScriptPath -Pattern 'Script Version:' | Select-Object -First 1
    Write-Host "  ✓ Script deployed: $ScriptPath" -ForegroundColor Green
    if ($scriptVersion) {
        Write-Host "    $($scriptVersion.Line.Trim())" -ForegroundColor Gray
    }
}

# Step 5: Check current Kerberos tickets (as SYSTEM)
Write-Host ""
Write-Host "Step 5: Checking Kerberos tickets (current user)..." -ForegroundColor Yellow
Write-Host "  Current user: $env:USERNAME" -ForegroundColor Gray
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Gray

# Note: klist will show tickets for current user (Administrator), not SYSTEM
Write-Host ""
Write-Host "  Note: When task runs as SYSTEM, it will use computer account:" -ForegroundColor Yellow
Write-Host "  $env:COMPUTERNAME`$@$env:USERDNSDOMAIN" -ForegroundColor Cyan

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SETUP COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "----------" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Verify SPN is registered to computer account (on ADDC):" -ForegroundColor White
Write-Host "   setspn -L $env:COMPUTERNAME$" -ForegroundColor Cyan
Write-Host "   Should show: HTTP/vault.local.lab" -ForegroundColor Gray
Write-Host ""
Write-Host "2. If SPN is on vault-gmsa, move it (on ADDC):" -ForegroundColor White
Write-Host "   setspn -D HTTP/vault.local.lab vault-gmsa" -ForegroundColor Cyan
Write-Host "   setspn -A HTTP/vault.local.lab $env:COMPUTERNAME$" -ForegroundColor Cyan
Write-Host ""
Write-Host "3. Test authentication (run scheduled task):" -ForegroundColor White
Write-Host "   schtasks /Run /TN `"$taskName`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "4. Check logs after 5-10 seconds:" -ForegroundColor White
Write-Host "   Get-Content $LogPath\vault-client-app.log -Tail 50" -ForegroundColor Cyan
Write-Host ""
Write-Host "5. Verify task ran as SYSTEM:" -ForegroundColor White
Write-Host "   Get-Content $LogPath\vault-client-app.log | Select-String 'Current User'" -ForegroundColor Cyan
Write-Host "   Should show: NT AUTHORITY\SYSTEM" -ForegroundColor Gray
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
