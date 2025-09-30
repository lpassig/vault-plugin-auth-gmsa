# 🧪 Complete Testing Guide - gMSA with Auto-Rotation

## 📋 Current Status

Based on your session:
- ✅ SPN `HTTP/vault.local.lab` is on `vault-keytab-svc` (you moved it earlier)
- ✅ Keytab exists for `vault-keytab-svc`
- ✅ Vault is configured with this keytab
- ✅ Plugin has auto-rotation capability
- ⚠️ Need to switch to gMSA for full passwordless + auto-rotation

---

## 🎯 **Option A: Quick Test (Current Setup - vault-keytab-svc)**

**Test what you have RIGHT NOW (5 minutes):**

### **Step 1: Update Scheduled Task to Use vault-keytab-svc**

```powershell
# On Windows Client

# Update scheduled task to use vault-keytab-svc
$password = Read-Host "Enter password for vault-keytab-svc" -AsSecureString

$principal = New-ScheduledTaskPrincipal `
    -UserId "local.lab\vault-keytab-svc" `
    -LogonType Password `
    -RunLevel Highest

Set-ScheduledTask -TaskName "VaultClientApp" -Principal $principal

Write-Host "Scheduled task updated to use vault-keytab-svc" -ForegroundColor Green
```

### **Step 2: Test Authentication**

```powershell
# Run the scheduled task
Start-ScheduledTask -TaskName "VaultClientApp"

# Wait for completion
Start-Sleep -Seconds 5

# Check logs
Get-Content "C:\vault-client\config\vault-client.log" -Tail 30
```

**Expected Success:**
```
[SUCCESS] Service ticket obtained for HTTP/vault.local.lab
[SUCCESS] Credentials handle acquired
[SUCCESS] Security context initialized
[SUCCESS] Real SPNEGO token generated!
[SUCCESS] Vault authentication successful!
[SUCCESS] Retrieved 2 secrets
```

**If this works:** ✅ Your setup is functional! You can stop here or proceed to Option B for passwordless.

**If this fails:** Go to Troubleshooting section below.

---

## 🚀 **Option B: Full gMSA Setup (Passwordless + Auto-Rotation)**

**Recommended for production (30 minutes):**

### **Step 1: Create gMSA (Domain Controller)**

```powershell
# On Domain Controller

# Check if KDS root key exists
Get-KdsRootKey

# If not, create one (use backdated for lab)
Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))

# Create gMSA with SPN
New-ADServiceAccount -Name vault-gmsa `
    -DNSHostName vault-gmsa.local.lab `
    -ServicePrincipalNames "HTTP/vault.local.lab" `
    -PrincipalsAllowedToRetrieveManagedPassword "Vault-Clients"

# Create AD group
New-ADGroup -Name "Vault-Clients" `
    -GroupCategory Security `
    -GroupScope Global `
    -Path "CN=Users,DC=local,DC=lab"

# Add your Windows client to the group (replace with your actual computer name)
$clientComputer = "YOUR-CLIENT-COMPUTER"
Add-ADGroupMember -Identity "Vault-Clients" -Members "$clientComputer$"

# Verify
Get-ADServiceAccount vault-gmsa -Properties PrincipalsAllowedToRetrieveManagedPassword
Get-ADGroupMember Vault-Clients
```

### **Step 2: Move SPN from vault-keytab-svc to vault-gmsa**

```powershell
# On Domain Controller or Windows Client with AD tools

# Remove SPN from vault-keytab-svc
setspn -D HTTP/vault.local.lab vault-keytab-svc

# Add SPN to vault-gmsa
setspn -A HTTP/vault.local.lab vault-gmsa

# Verify
setspn -L vault-gmsa
# Should show: HTTP/vault.local.lab
```

### **Step 3: Generate Initial Keytab for gMSA**

```powershell
# On Domain Controller

# Generate keytab
ktpass -princ HTTP/vault.local.lab@LOCAL.LAB `
    -mapuser LOCAL\vault-gmsa$ `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -pass * `
    -out vault-gmsa.keytab

# When prompted: "Do you want to change the password? (y/n)"
# Answer: n (NO) to preserve gMSA managed password

# If it exits without creating keytab (expected for gMSA):
# Use the current vault-keytab-svc keytab temporarily
# The auto-rotation will generate a new one automatically

# Convert to base64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("vault-gmsa.keytab")) | Out-File vault-gmsa.keytab.b64 -Encoding ASCII
```

### **Step 4: Install gMSA on Windows Client**

```powershell
# On Windows Client

# Install gMSA
Install-ADServiceAccount -Identity vault-gmsa

# IMPORTANT: Reboot if you just added computer to Vault-Clients group
Restart-Computer

# After reboot, test gMSA
Test-ADServiceAccount -Identity vault-gmsa
# MUST return: True
```

**If `Test-ADServiceAccount` returns `False`:**
```powershell
# Check group membership
Get-ADGroupMember -Identity "Vault-Clients"

# Wait for replication
Start-Sleep -Seconds 300

# Test again
Test-ADServiceAccount -Identity vault-gmsa
```

### **Step 5: Configure Vault with Auto-Rotation**

```bash
# On Vault server

# Copy keytab (use existing vault-keytab-svc keytab if gMSA keytab generation failed)
scp vault-gmsa.keytab.b64 user@vault-server:/tmp/

# Update Vault configuration with AUTO-ROTATION enabled
vault write auth/gmsa/config \
  realm="LOCAL.LAB" \
  kdcs="addc.local.lab" \
  spn="HTTP/vault.local.lab" \
  keytab="$(cat /tmp/vault-gmsa.keytab.b64)" \
  clock_skew_sec=300 \
  allow_channel_binding=true \
  enable_rotation=true \
  rotation_threshold=5d \
  backup_keytabs=true

# Verify configuration
vault read auth/gmsa/config

# Check rotation status
vault read auth/gmsa/rotation/status
```

### **Step 6: Update Scheduled Task to Use gMSA (Passwordless!)**

```powershell
# On Windows Client

# Update scheduled task to use gMSA (NO PASSWORD!)
$principal = New-ScheduledTaskPrincipal `
    -UserId "local.lab\vault-gmsa$" `
    -LogonType Password `
    -RunLevel Highest

Set-ScheduledTask -TaskName "VaultClientApp" -Principal $principal

# Verify
Get-ScheduledTask -TaskName "VaultClientApp" | Select-Object -ExpandProperty Principal

Write-Host "✓ Scheduled task now uses gMSA (passwordless!)" -ForegroundColor Green
```

### **Step 7: Test gMSA Authentication**

```powershell
# On Windows Client

# Run the scheduled task
Start-ScheduledTask -TaskName "VaultClientApp"

# Wait for completion
Start-Sleep -Seconds 5

# Check logs
Get-Content "C:\vault-client\config\vault-client.log" -Tail 30
```

**Expected Success:**
```
[INFO] Running under: LOCAL\vault-gmsa$
[SUCCESS] Service ticket obtained for HTTP/vault.local.lab
[SUCCESS] Real SPNEGO token generated!
[SUCCESS] Vault authentication successful!
```

---

## 🔍 **Verification Tests**

### **Test 1: Verify gMSA Passwordless Operation**

```powershell
# On Windows Client

# Check current user in scheduled task
Get-ScheduledTask -TaskName "VaultClientApp" | Select-Object -ExpandProperty Principal

# Expected:
# UserId: local.lab\vault-gmsa$
# LogonType: Password (this means passwordless for gMSA!)

# Check if task ran successfully
Get-ScheduledTaskInfo -TaskName "VaultClientApp"

# Expected:
# LastTaskResult: 0 (success)
```

### **Test 2: Verify Auto-Rotation is Active**

```bash
# On Vault server

# Check rotation status
vault read auth/gmsa/rotation/status

# Expected output:
# Key              Value
# ---              -----
# enabled          true
# status           idle
# last_check       2025-09-30T...
# next_rotation    (future date)
# password_age     X days
```

### **Test 3: Manual Rotation Test**

```bash
# On Vault server

# Trigger manual rotation (to test the feature)
vault write -f auth/gmsa/rotation/rotate

# Check status
vault read auth/gmsa/rotation/status

# Expected:
# status           completed
# last_rotation    (just now)

# Test authentication still works
# (run scheduled task on Windows client again)
```

### **Test 4: Check Logs for Rotation Events**

```bash
# On Vault server

# Check Vault logs for rotation events
journalctl -u vault -n 100 | grep -i rotation

# Or if using Docker:
docker logs vault-container | grep -i rotation

# Expected:
# "Starting password rotation..."
# "Password rotation completed successfully"
```

---

## 🐛 **Troubleshooting**

### **Issue: `Test-ADServiceAccount` returns `False`**

**Solution:**
```powershell
# 1. Verify computer is in group
Get-ADGroupMember -Identity "Vault-Clients" | Where-Object { $_.Name -eq $env:COMPUTERNAME }

# 2. If not in group, add it
Add-ADGroupMember -Identity "Vault-Clients" -Members "$env:COMPUTERNAME$"

# 3. REBOOT the computer
Restart-Computer

# 4. Test again after reboot
Test-ADServiceAccount -Identity vault-gmsa
```

### **Issue: `0x80090308` Error (SEC_E_UNKNOWN_CREDENTIALS)**

**Solution:**
```powershell
# Verify SPN is on gMSA
setspn -L vault-gmsa

# Should show: HTTP/vault.local.lab
# If not:
setspn -A HTTP/vault.local.lab vault-gmsa

# Verify keytab on Vault server matches
vault read auth/gmsa/config
# Check that SPN matches
```

### **Issue: "400 Bad Request" from Vault**

**Solution:**
```bash
# On Vault server

# Check Vault logs
vault audit-log | tail -50

# Verify role configuration
vault read auth/gmsa/role/vault-gmsa-role

# Ensure bound_group_sids is correct
# Get the SID:
# On Windows: Get-ADGroup "Vault-Clients" | Select-Object SID
```

### **Issue: Scheduled Task Fails with "User not logged on"**

**Solution:**
```powershell
# Ensure you used LogonType Password for gMSA
$principal = New-ScheduledTaskPrincipal `
    -UserId "local.lab\vault-gmsa$" `
    -LogonType Password `
    -RunLevel Highest

Set-ScheduledTask -TaskName "VaultClientApp" -Principal $principal

# Grant "Log on as a batch job" right (if needed)
# Run: secpol.msc
# Navigate: Local Policies → User Rights Assignment → Log on as a batch job
# Add: local.lab\vault-gmsa$
```

---

## 📊 **Complete Testing Checklist**

### **Initial Setup:**
- [ ] Domain Controller: KDS root key exists (`Get-KdsRootKey`)
- [ ] Domain Controller: gMSA created with SPN
- [ ] Domain Controller: Vault-Clients group created with client computers
- [ ] Domain Controller: SPN moved to gMSA (`setspn -L vault-gmsa`)
- [ ] Vault Server: Auto-rotation enabled (`vault read auth/gmsa/config`)
- [ ] Windows Client: Computer in Vault-Clients group
- [ ] Windows Client: Rebooted after group membership change

### **gMSA Installation:**
- [ ] Windows Client: gMSA installed (`Install-ADServiceAccount`)
- [ ] Windows Client: gMSA test passes (`Test-ADServiceAccount` = True)

### **Scheduled Task:**
- [ ] Windows Client: Task created with gMSA identity
- [ ] Windows Client: LogonType is Password (not ServiceAccount)
- [ ] Windows Client: No password configured (passwordless!)

### **Authentication Test:**
- [ ] Windows Client: Task runs successfully (`Start-ScheduledTask`)
- [ ] Windows Client: Logs show success (`Get-Content ...log -Tail 30`)
- [ ] Vault Server: Audit logs show successful login

### **Auto-Rotation Test:**
- [ ] Vault Server: Rotation status is `idle` or `completed`
- [ ] Vault Server: Manual rotation works (`vault write -f .../rotate`)
- [ ] Windows Client: Authentication still works after rotation

---

## 🎯 **Quick Start Script**

Save as `test-gmsa-setup.ps1`:

```powershell
# Complete gMSA Setup and Test Script

param(
    [string]$GMSAName = "vault-gmsa",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$ClientGroup = "Vault-Clients",
    [string]$TaskName = "VaultClientApp"
)

Write-Host "=== gMSA Setup and Test ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: gMSA installation
Write-Host "[1] Testing gMSA installation..." -ForegroundColor Yellow
$gmsaTest = Test-ADServiceAccount -Identity $GMSAName -ErrorAction SilentlyContinue

if ($gmsaTest) {
    Write-Host "✓ gMSA is working" -ForegroundColor Green
} else {
    Write-Host "✗ gMSA test failed - installing..." -ForegroundColor Red
    Install-ADServiceAccount -Identity $GMSAName
    $gmsaTest = Test-ADServiceAccount -Identity $GMSAName
    
    if (-not $gmsaTest) {
        Write-Host "✗ gMSA installation failed - check group membership and reboot" -ForegroundColor Red
        exit 1
    }
}

# Test 2: SPN registration
Write-Host ""
Write-Host "[2] Verifying SPN registration..." -ForegroundColor Yellow
$spnCheck = setspn -L $GMSAName | Select-String $SPN

if ($spnCheck) {
    Write-Host "✓ SPN is registered: $SPN" -ForegroundColor Green
} else {
    Write-Host "✗ SPN not found on $GMSAName" -ForegroundColor Red
    exit 1
}

# Test 3: Scheduled task configuration
Write-Host ""
Write-Host "[3] Checking scheduled task..." -ForegroundColor Yellow
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($task) {
    Write-Host "✓ Scheduled task exists" -ForegroundColor Green
    Write-Host "  User: $($task.Principal.UserId)" -ForegroundColor Cyan
    Write-Host "  LogonType: $($task.Principal.LogonType)" -ForegroundColor Cyan
} else {
    Write-Host "✗ Scheduled task not found" -ForegroundColor Red
    exit 1
}

# Test 4: Run authentication test
Write-Host ""
Write-Host "[4] Testing authentication..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 5

# Check results
$logFile = "C:\vault-client\config\vault-client.log"
if (Test-Path $logFile) {
    $recentLogs = Get-Content $logFile -Tail 10
    
    if ($recentLogs -match "SUCCESS.*authentication") {
        Write-Host "✓ Authentication successful!" -ForegroundColor Green
    } else {
        Write-Host "✗ Authentication failed" -ForegroundColor Red
        Write-Host "Recent logs:" -ForegroundColor Yellow
        $recentLogs | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
} else {
    Write-Host "✗ Log file not found: $logFile" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan
```

---

## 🚀 **Recommended Testing Path**

**For Immediate Testing (5 min):**
1. Run **Option A** (current setup with vault-keytab-svc)
2. Verify authentication works
3. If successful, you're done!

**For Production Setup (30 min):**
1. Run **Option B** (full gMSA with auto-rotation)
2. Follow all steps in order
3. Verify with complete testing checklist
4. Test manual rotation
5. Monitor for 30 days to confirm auto-rotation

---

**Which option would you like to start with?**

- **Option A**: Quick test with current setup (5 min) ⚡
- **Option B**: Full gMSA passwordless setup (30 min) 🚀
