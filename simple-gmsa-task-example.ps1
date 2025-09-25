# =============================================================================
# Simple gMSA Scheduled Task Example for Vault Authentication
# =============================================================================
# This is a minimal example showing the essential steps to create a scheduled task
# that runs under gMSA identity and authenticates to Vault
# =============================================================================

# Run as Administrator
# Prerequisites: gMSA installed and Vault server configured

# =============================================================================
# Step 1: Create the PowerShell script that runs under gMSA
# =============================================================================

$scriptContent = @'
# Simple Vault authentication script (runs under gMSA)
param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$Role = "vault-gmsa-role"
)

Write-Host "Running under identity: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Host "Timestamp: $(Get-Date)"

# In a real implementation, you would:
# 1. Get SPNEGO token using Windows SSPI
# 2. Authenticate to Vault using the token
# 3. Retrieve secrets
# 4. Update your application configuration

# For demonstration, we'll just show the authentication flow
try {
    # This is where you'd implement actual SPNEGO token generation
    $spnegoToken = "YOUR_SPNEGO_TOKEN_HERE"
    
    # Authenticate to Vault
    $authBody = @{
        role = $Role
        spnego = $spnegoToken
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Method POST -Uri "$VaultUrl/v1/auth/gmsa/login" -Body $authBody -ContentType "application/json"
    
    if ($response.auth.client_token) {
        Write-Host "✅ Successfully authenticated to Vault!"
        Write-Host "Token: $($response.auth.client_token.Substring(0,20))..."
        
        # Here you would retrieve secrets and update your application
        Write-Host "✅ Secrets refreshed successfully!"
    }
} catch {
    Write-Error "Authentication failed: $($_.Exception.Message)"
}
'@

# Save the script
$scriptPath = "C:\vault\scripts\vault-auth.ps1"
$scriptDir = Split-Path $scriptPath -Parent

if (-not (Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Path $scriptDir -Force
}

$scriptContent | Out-File -FilePath $scriptPath -Encoding UTF8
Write-Host "✅ Created script: $scriptPath"

# =============================================================================
# Step 2: Create the scheduled task action
# =============================================================================

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""

# =============================================================================
# Step 3: Create the trigger (daily at 2 AM)
# =============================================================================

$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"

# =============================================================================
# Step 4: Configure task settings
# =============================================================================

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

# =============================================================================
# Step 5: Register the task under gMSA identity
# =============================================================================

try {
    Register-ScheduledTask -TaskName "VaultAuthTask" -Action $action -Trigger $trigger -Settings $settings -User "local.lab\vault-gmsa$" -Password ""
    
    Write-Host "✅ Scheduled task 'VaultAuthTask' created successfully!" -ForegroundColor Green
    Write-Host "   - Runs under: local.lab\vault-gmsa$" -ForegroundColor Cyan
    Write-Host "   - Schedule: Daily at 2:00 AM" -ForegroundColor Cyan
    Write-Host "   - Script: $scriptPath" -ForegroundColor Cyan
    
} catch {
    Write-Error "Failed to create scheduled task: $($_.Exception.Message)"
    Write-Host "Make sure you're running as Administrator and the gMSA is installed." -ForegroundColor Red
}

# =============================================================================
# Step 6: Verify the task
# =============================================================================

try {
    $task = Get-ScheduledTask -TaskName "VaultAuthTask"
    Write-Host "✅ Task verification:" -ForegroundColor Green
    Write-Host "   - Name: $($task.TaskName)" -ForegroundColor Cyan
    Write-Host "   - State: $($task.State)" -ForegroundColor Cyan
    Write-Host "   - Principal: $($task.Principal.UserId)" -ForegroundColor Cyan
} catch {
    Write-Warning "Could not verify task: $($_.Exception.Message)"
}

Write-Host "`n🎉 Setup complete! The task will run daily under the gMSA identity." -ForegroundColor Green
