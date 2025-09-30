# 🚀 Option B: Full gMSA Production Setup - Execution Guide

## 📋 What You're About to Do

Transform your setup to **100% passwordless authentication** with **automatic keytab rotation**:

- ✅ **Passwordless**: No passwords in scheduled tasks
- ✅ **Auto-Rotation**: Vault automatically updates keytabs before expiry
- ✅ **Production Ready**: Zero maintenance required
- ✅ **Secure**: gMSA passwords managed by Active Directory

**Time Required**: 30 minutes  
**Difficulty**: Moderate (automated script provided)

---

## 🎯 Quick Start (Automated)

### **Option 1: Run Complete Setup (Recommended)**

```powershell
# Download and run the automated setup script
.\setup-gmsa-production.ps1 -Step all
```

This will execute all 7 steps automatically!

---

### **Option 2: Run Steps Individually** 

If you prefer to run each step separately for better control:

```powershell
# Step 1: Create gMSA on Domain Controller
.\setup-gmsa-production.ps1 -Step 1

# Step 2: Move SPN from vault-keytab-svc to vault-gmsa
.\setup-gmsa-production.ps1 -Step 2

# Step 3: Generate initial keytab
.\setup-gmsa-production.ps1 -Step 3

# Step 4: Install gMSA on Windows client
.\setup-gmsa-production.ps1 -Step 4

# Step 5: Update scheduled task (passwordless!)
.\setup-gmsa-production.ps1 -Step 5

# Step 6: Configure Vault with auto-rotation
.\setup-gmsa-production.ps1 -Step 6

# Step 7: Test authentication
.\setup-gmsa-production.ps1 -Step 7
```

---

## 📝 Detailed Step-by-Step Guide

### **Prerequisites**

Before you begin, ensure you have:

- [ ] **Domain Controller access** (or machine with RSAT AD tools)
- [ ] **Administrator privileges** on Windows client
- [ ] **Vault server access** (SSH or console)
- [ ] **Current SPN**: `HTTP/vault.local.lab` on `vault-keytab-svc`

---

### **STEP 1: Create gMSA on Domain Controller** (5 min)

**Location**: Domain Controller or machine with AD tools

**What it does**:
- Creates KDS root key (if needed)
- Creates gMSA `vault-gmsa`
- Creates AD group `Vault-Clients`
- Adds your Windows client to the group

**Commands**:

```powershell
# On Domain Controller

# Check if AD module is available
Import-Module ActiveDirectory

# Create KDS root key (if not exists)
Get-KdsRootKey
# If empty:
Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))

# Create gMSA
New-ADServiceAccount -Name vault-gmsa `
    -DNSHostName vault-gmsa.local.lab `
    -ServicePrincipalNames "HTTP/vault.local.lab" `
    -PrincipalsAllowedToRetrieveManagedPassword "Vault-Clients"

# Create AD group
New-ADGroup -Name "Vault-Clients" `
    -GroupCategory Security `
    -GroupScope Global

# Add your Windows client computer (replace with actual computer name)
Add-ADGroupMember -Identity "Vault-Clients" -Members "YOUR-CLIENT-COMPUTER$"

# Verify
Get-ADServiceAccount vault-gmsa
Get-ADGroupMember Vault-Clients
```

**Or use the automated script**:

```powershell
.\setup-gmsa-production.ps1 -Step 1
```

**Expected Output**:
```
✓ KDS root key created
✓ gMSA 'vault-gmsa' created successfully
✓ Client group 'Vault-Clients' created successfully
✓ Computer added to group
⚠️  IMPORTANT: Reboot the computer for group membership to take effect!
```

**⚠️ IMPORTANT**: If you just added the computer to the group, **REBOOT** the Windows client before proceeding!

---

### **STEP 2: Move SPN from vault-keytab-svc to vault-gmsa** (2 min)

**Location**: Domain Controller or Windows client with AD tools

**What it does**:
- Removes SPN from old account (`vault-keytab-svc`)
- Adds SPN to new gMSA (`vault-gmsa`)
- Verifies the move

**Commands**:

```powershell
# Remove SPN from old account
setspn -D HTTP/vault.local.lab vault-keytab-svc

# Add SPN to gMSA
setspn -A HTTP/vault.local.lab vault-gmsa

# Verify
setspn -L vault-gmsa
# Should show: HTTP/vault.local.lab
```

**Or use the automated script**:

```powershell
.\setup-gmsa-production.ps1 -Step 2
```

**Expected Output**:
```
✓ SPN removed from 'vault-keytab-svc'
✓ SPN 'HTTP/vault.local.lab' added to 'vault-gmsa'
✓ Verified: SPN is on 'vault-gmsa'

Registered SPNs for vault-gmsa:
  HTTP/vault.local.lab
```

---

### **STEP 3: Generate Initial Keytab** (3 min)

**Location**: Domain Controller

**What it does**:
- Generates a keytab file for the gMSA
- Converts to base64 for Vault

**Commands**:

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
```

**⚠️ CRITICAL**: When `ktpass` asks "Do you want to change the password?", answer **`n` (NO)**!

**Expected Behavior**:
- If you answer `n`: `ktpass` may exit without creating the file (this is OK for gMSA)
- If this happens: You can use the existing `vault-keytab-svc` keytab temporarily
- The auto-rotation feature will generate proper keytabs automatically

**Convert to Base64**:

```powershell
# If keytab was created
[Convert]::ToBase64String([IO.File]::ReadAllBytes("vault-gmsa.keytab")) | Out-File vault-gmsa.keytab.b64 -Encoding ASCII
```

**Or use the automated script**:

```powershell
.\setup-gmsa-production.ps1 -Step 3
```

---

### **STEP 4: Install gMSA on Windows Client** (3 min)

**Location**: Windows Client

**What it does**:
- Installs the gMSA on the Windows client
- Tests that passwordless retrieval works

**Commands**:

```powershell
# On Windows Client

# Install gMSA
Install-ADServiceAccount -Identity vault-gmsa

# Test gMSA (MUST return True)
Test-ADServiceAccount -Identity vault-gmsa
```

**Expected Output**:
```
True
```

**If you get `False`**:

```powershell
# Check group membership
Get-ADGroupMember -Identity "Vault-Clients" | Where-Object { $_.Name -eq $env:COMPUTERNAME }

# If not in group, add and REBOOT
Add-ADGroupMember -Identity "Vault-Clients" -Members "$env:COMPUTERNAME$"
Restart-Computer

# After reboot, test again
Test-ADServiceAccount -Identity vault-gmsa
```

**Or use the automated script**:

```powershell
.\setup-gmsa-production.ps1 -Step 4
```

**Expected Output**:
```
✓ gMSA installed successfully
✓ gMSA test PASSED! Passwordless authentication is working!
```

---

### **STEP 5: Update Scheduled Task (Passwordless!)** (2 min)

**Location**: Windows Client

**What it does**:
- Updates the scheduled task to use gMSA instead of `vault-keytab-svc`
- **No password required!** (passwordless!)

**Commands**:

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
```

**Or use the automated script**:

```powershell
.\setup-gmsa-production.ps1 -Step 5
```

**Expected Output**:
```
✓ Scheduled task updated to use gMSA!
✓ NO PASSWORD REQUIRED - gMSA provides passwordless authentication!

Updated configuration:
  User: local.lab\vault-gmsa$
  LogonType: Password
```

**Note**: `LogonType: Password` for gMSA means **passwordless** - Windows automatically retrieves the password from AD!

---

### **STEP 6: Configure Vault with Auto-Rotation** (5 min)

**Location**: Vault Server

**What it does**:
- Uploads the keytab to Vault
- Enables auto-rotation
- Configures rotation threshold

**Commands**:

```bash
# On Vault Server

# Copy keytab from Domain Controller
scp vault-gmsa.keytab.b64 user@vault-server:/tmp/

# Configure Vault auth method with AUTO-ROTATION
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

**Key Parameters**:
- `enable_rotation=true`: Enables automatic keytab rotation
- `rotation_threshold=5d`: Rotates 5 days before password expiry (default 30 days)
- `backup_keytabs=true`: Backs up keytabs before rotation

**Expected Output**:

```
Key                      Value
---                      -----
realm                    LOCAL.LAB
kdcs                     [addc.local.lab]
spn                      HTTP/vault.local.lab
enable_rotation          true
rotation_threshold       120h0m0s (5 days)
backup_keytabs           true
```

**Rotation Status**:

```
Key                Value
---                -----
enabled            true
status             idle
last_check         2025-09-30T...
next_rotation      2025-10-25T...
password_age       0 days
```

**Or follow the automated script prompts**:

```powershell
.\setup-gmsa-production.ps1 -Step 6
# (will display commands to run on Vault server)
```

---

### **STEP 7: Test Authentication** (5 min)

**Location**: Windows Client

**What it does**:
- Runs the scheduled task
- Verifies passwordless authentication works
- Checks logs for success

**Commands**:

```powershell
# On Windows Client

# Run the scheduled task
Start-ScheduledTask -TaskName "VaultClientApp"

# Wait for completion
Start-Sleep -Seconds 5

# Check logs
Get-Content "C:\vault-client\config\vault-client.log" -Tail 30
```

**Or use the automated script**:

```powershell
.\setup-gmsa-production.ps1 -Step 7
```

**Expected Success Output**:

```
[INFO] Running under: LOCAL\vault-gmsa$
[SUCCESS] Service ticket obtained for HTTP/vault.local.lab
[SUCCESS] Credentials handle acquired
[SUCCESS] Security context initialized
[SUCCESS] Real SPNEGO token generated!
[SUCCESS] Vault authentication successful!
[SUCCESS] Token obtained with policies: [vault-gmsa-policy]
[SUCCESS] Retrieved 2 secrets successfully
```

**If successful**:

```
✓ Task completed successfully! (Exit code: 0)
✓ 🎉 PASSWORDLESS gMSA AUTHENTICATION IS WORKING!
✓ Auto-rotation is enabled on Vault server!
```

---

## ✅ Complete Setup Checklist

Use this to verify everything is configured correctly:

### **Domain Controller:**
- [ ] KDS root key exists (`Get-KdsRootKey`)
- [ ] gMSA `vault-gmsa` created
- [ ] AD group `Vault-Clients` created
- [ ] Windows client computer added to `Vault-Clients` group
- [ ] SPN `HTTP/vault.local.lab` registered to `vault-gmsa`
- [ ] Keytab generated (or using temporary keytab)

### **Windows Client:**
- [ ] Computer rebooted after group membership change
- [ ] gMSA installed (`Install-ADServiceAccount`)
- [ ] gMSA test passes (`Test-ADServiceAccount` = True)
- [ ] Scheduled task updated to use `vault-gmsa$`
- [ ] Task uses `LogonType: Password` (passwordless for gMSA)
- [ ] No password configured in task

### **Vault Server:**
- [ ] Keytab uploaded to Vault
- [ ] Auth method configured with `enable_rotation=true`
- [ ] Rotation threshold set (e.g., `5d`)
- [ ] Backup enabled (`backup_keytabs=true`)
- [ ] Role configured with correct policies
- [ ] Rotation status shows `enabled: true`

### **Authentication Test:**
- [ ] Scheduled task runs successfully
- [ ] Logs show `Running under: LOCAL\vault-gmsa$`
- [ ] Logs show `SUCCESS.*token generated`
- [ ] Logs show `SUCCESS.*authentication`
- [ ] No errors in logs

---

## 🎯 Final Result

After completing all steps, you'll have:

✅ **100% Passwordless Authentication**
- Windows client uses gMSA (no password in task)
- gMSA auto-retrieves password from AD
- Zero password management

✅ **Automatic Password Rotation**
- gMSA password rotates every 30 days (AD managed)
- Vault keytab auto-rotates before expiry (plugin managed)
- Zero manual intervention

✅ **Production Ready**
- Keytab backup before rotation
- Automatic rollback on failure
- Monitoring via `vault read auth/gmsa/rotation/status`

✅ **Zero Maintenance**
- Everything is automatic
- No scheduled tasks for keytab updates
- No password expiration issues

---

## 🐛 Troubleshooting

### **Issue: `Test-ADServiceAccount` returns `False`**

**Solution**:
```powershell
# 1. Verify computer is in group
Get-ADGroupMember -Identity "Vault-Clients"

# 2. Add computer if missing
Add-ADGroupMember -Identity "Vault-Clients" -Members "$env:COMPUTERNAME$"

# 3. REBOOT (critical!)
Restart-Computer

# 4. Test again after reboot
Test-ADServiceAccount -Identity vault-gmsa
```

---

### **Issue: `0x80090308` Error (SEC_E_UNKNOWN_CREDENTIALS)**

**Solution**:
```powershell
# Verify SPN is on gMSA
setspn -L vault-gmsa
# Should show: HTTP/vault.local.lab

# If not, add it
setspn -A HTTP/vault.local.lab vault-gmsa
```

---

### **Issue: "400 Bad Request" from Vault**

**Solution**:
```bash
# On Vault server

# Check Vault logs
journalctl -u vault -n 100 | grep -i error

# Verify keytab is configured
vault read auth/gmsa/config

# Verify role exists
vault read auth/gmsa/role/vault-gmsa-role
```

---

### **Issue: Keytab Generation Failed (ktpass)**

**Solution**:

This is **expected** for gMSA when you answer 'n' to password change.

**Workarounds**:

1. **Use existing keytab temporarily** (recommended):
   ```bash
   # Use vault-keytab-svc keytab for now
   # Auto-rotation will generate proper keytab
   ```

2. **Let auto-rotation generate it**:
   - Vault's auto-rotation will generate keytabs automatically
   - No manual keytab needed

3. **Use alternative method** (see `GMSA-WITH-AUTO-ROTATION-GUIDE.md`)

---

## 📊 Monitoring Auto-Rotation

### **Check Rotation Status**:

```bash
# On Vault server
vault read auth/gmsa/rotation/status
```

**Expected Output**:
```
Key                Value
---                -----
enabled            true
status             idle
last_rotation      2025-09-30T10:00:00Z
next_rotation      2025-10-25T10:00:00Z
password_age       5 days
last_error         (none)
```

---

### **Manual Rotation Test**:

```bash
# Trigger manual rotation (to test the feature)
vault write -f auth/gmsa/rotation/rotate

# Check status
vault read auth/gmsa/rotation/status

# Test authentication still works
# (run scheduled task on Windows client)
```

---

### **Check Rotation Logs**:

```bash
# On Vault server
journalctl -u vault -n 200 | grep -i rotation

# Or if using Docker
docker logs vault-container | grep -i rotation
```

**Expected Log Entries**:
```
"Starting password rotation..."
"New keytab generated successfully"
"Password rotation completed successfully"
```

---

## 🚀 Next Steps

After successful setup:

1. **Monitor for 30 days** to confirm auto-rotation works
2. **Check rotation logs** periodically
3. **Verify authentication** continues to work after rotation
4. **Document your setup** for your team

---

## 📚 Additional Resources

- **Full Guide**: `GMSA-WITH-AUTO-ROTATION-GUIDE.md`
- **Testing Guide**: `TESTING-GUIDE.md`
- **Troubleshooting**: `COMPLETE-GMSA-PASSWORDLESS-GUIDE.md`
- **Rotation Details**: See `pkg/backend/rotation.go` in your plugin

---

**Congratulations! You now have a production-ready, passwordless gMSA authentication system with automatic keytab rotation! 🎉**
