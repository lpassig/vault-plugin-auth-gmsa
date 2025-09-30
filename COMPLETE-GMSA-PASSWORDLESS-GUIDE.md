# 🎯 Complete gMSA Passwordless Authentication Guide

## 📋 Your Exact Requirement

**Setup:** Windows client → gMSA authentication → Vault auth plugin (passwordless)  
**Execution:** PowerShell script via Scheduled Task  
**Goal:** 100% passwordless, using gMSA as designed

---

## 🔑 The Complete Solution

Based on [Microsoft's documentation](https://learn.microsoft.com/en-us/answers/questions/172186/manage-service-account-kvno-and-keytab), here's how to achieve TRUE passwordless gMSA authentication:

### **Key Architecture:**

```
┌─────────────────────────────────────────────────────────────┐
│  Windows Client (Passwordless)                               │
│  ├── Scheduled Task runs as: local.lab\vault-gmsa$          │
│  ├── NO PASSWORD in task configuration                      │
│  ├── gMSA auto-retrieves its own password from AD           │
│  └── Generates SPNEGO token using gMSA credentials          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ SPNEGO Token
┌─────────────────────────────────────────────────────────────┐
│  Vault Server (Linux) - Validation                           │
│  ├── Auth Plugin: vault-plugin-auth-gmsa                     │
│  ├── Keytab: vault-gmsa keytab (static, never expires)      │
│  └── Validates: SPNEGO token from gMSA                       │
└─────────────────────────────────────────────────────────────┘
```

### **Critical Understanding:**

1. **Client uses gMSA directly** (passwordless on Windows side)
2. **Server uses gMSA keytab** (static, for validation only)
3. **Both use the SAME gMSA**, but differently:
   - **Windows:** gMSA retrieves its own password from AD (passwordless for you)
   - **Linux/Vault:** gMSA keytab with static password (doesn't rotate)

---

## 🚀 **Step-by-Step Implementation**

### **Part 1: Domain Controller Setup**

#### **Step 1.1: Create gMSA**

```powershell
# On Domain Controller

# Create KDS root key (if not exists)
Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))

# Wait 10 hours OR use the backdated command above for lab

# Create gMSA with DUAL configuration:
# 1. Allow Windows client to retrieve password (for client auth)
# 2. Don't rotate password on Linux (for static keytab)

New-ADServiceAccount -Name vault-gmsa `
    -DNSHostName vault-gmsa.local.lab `
    -ServicePrincipalNames "HTTP/vault.local.lab" `
    -PrincipalsAllowedToRetrieveManagedPassword "Vault-Clients"

# Create AD group for clients
New-ADGroup -Name "Vault-Clients" `
    -GroupCategory Security `
    -GroupScope Global

# Add your Windows client computer to the group
Add-ADGroupMember -Identity "Vault-Clients" -Members "YOUR-CLIENT-COMPUTER$"
```

#### **Step 1.2: Generate Static Keytab for Vault**

```powershell
# On Domain Controller

# Generate keytab with a known password
$keytabPassword = "VaultGMSA2025!Complex"

ktpass -princ HTTP/vault.local.lab@LOCAL.LAB `
    -mapuser LOCAL\vault-gmsa$ `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -pass $keytabPassword `
    -out vault-gmsa.keytab

# Answer 'y' (YES) to set the password

# Convert to base64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("vault-gmsa.keytab")) | Out-File vault-gmsa.keytab.b64 -Encoding ASCII
```

**Important:** After setting the password with `ktpass`, the gMSA will NOT auto-rotate this password on the Linux side because no Linux computer is joined to AD. However, Windows clients CAN still retrieve the password for authentication!

---

### **Part 2: Windows Client Setup (Passwordless)**

#### **Step 2.1: Install gMSA on Client**

```powershell
# On Windows Client (as Administrator)

# Install the gMSA
Install-ADServiceAccount -Identity vault-gmsa

# Test that it works
Test-ADServiceAccount -Identity vault-gmsa
# Should return: True

# If it returns False, ensure:
# 1. Client computer is in Vault-Clients group
# 2. You've rebooted after adding to group
# 3. KDS root key is replicated (wait 10 hours or use backdated command)
```

#### **Step 2.2: Configure Scheduled Task (Passwordless)**

```powershell
# On Windows Client

# Create scheduled task with gMSA (NO PASSWORD!)
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File `"C:\vault-client\scripts\vault-client-app.ps1`""

$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable

# CRITICAL: Use LogonType Password for gMSA (NOT ServiceAccount!)
# No password parameter needed - Windows retrieves it from AD automatically
$principal = New-ScheduledTaskPrincipal `
    -UserId "local.lab\vault-gmsa$" `
    -LogonType Password `
    -RunLevel Highest

# Register the task (NO PASSWORD PROMPT!)
Register-ScheduledTask `
    -TaskName "VaultClientApp" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal

# Verify
Get-ScheduledTask -TaskName "VaultClientApp" | Select-Object -ExpandProperty Principal
```

**Key Point:** Using `-LogonType Password` with gMSA means Windows automatically retrieves the password from AD. You don't provide a password - it's truly passwordless!

---

### **Part 3: Vault Server Setup**

#### **Step 3.1: Copy Keytab to Vault Server**

```bash
# Copy keytab from Windows/DC to Vault server
scp vault-gmsa.keytab.b64 user@vault-server:/tmp/
```

#### **Step 3.2: Configure Vault Auth Plugin**

```bash
# On Vault server

# Configure the gMSA auth method
vault write auth/gmsa/config \
  realm="LOCAL.LAB" \
  kdcs="addc.local.lab" \
  spn="HTTP/vault.local.lab" \
  keytab="$(cat /tmp/vault-gmsa.keytab.b64)" \
  clock_skew_sec=300 \
  allow_channel_binding=true

# Create role
vault write auth/gmsa/role/vault-gmsa-role \
  name="vault-gmsa-role" \
  allowed_realms="LOCAL.LAB" \
  allowed_spns="HTTP/vault.local.lab" \
  bound_group_sids="S-1-5-21-XXXXX" \
  token_policies="vault-gmsa-policy" \
  token_type="service" \
  period=3600 \
  max_ttl=7200

# Verify configuration
vault read auth/gmsa/config
vault read auth/gmsa/role/vault-gmsa-role
```

---

### **Part 4: PowerShell Script Configuration**

Your existing `vault-client-app.ps1` already supports this! Just ensure:

```powershell
# The script parameters are set correctly:
$VaultUrl = "https://vault.local.lab:8200"
$VaultRole = "vault-gmsa-role"
$SPN = "HTTP/vault.local.lab"

# The script will:
# 1. Run under gMSA identity (from scheduled task)
# 2. Request Kerberos ticket for SPN (uses gMSA credentials automatically)
# 3. Generate SPNEGO token (Windows SSPI with gMSA)
# 4. Authenticate to Vault (sends SPNEGO token)
# 5. Retrieve secrets (using Vault token)
```

---

## 🔍 **How Passwordless Works**

### **On Windows Client:**

1. Scheduled task runs as `local.lab\vault-gmsa$`
2. Windows automatically contacts AD to get gMSA's current password
3. PowerShell script runs with gMSA credentials (no password visible to you!)
4. Script requests Kerberos ticket using gMSA credentials (automatic)
5. Script generates SPNEGO token (Windows SSPI handles it)

### **On Vault Server:**

1. Receives SPNEGO token from client
2. Uses static gMSA keytab to validate the token
3. Keytab password doesn't change (because Vault isn't domain-joined)
4. Validation succeeds, issues Vault token

### **Why This Works:**

✅ **Same gMSA, different usage:**
- **Windows:** Retrieves live password from AD (passwordless for you)
- **Vault:** Uses static keytab password (doesn't change)

✅ **Both passwords are technically the same when keytab was created**
✅ **Kerberos validation works because both sides know the secret**
✅ **100% passwordless from your perspective**

---

## 📊 **Complete Setup Checklist**

### **Domain Controller:**
- [ ] KDS root key created
- [ ] gMSA `vault-gmsa` created with SPN `HTTP/vault.local.lab`
- [ ] AD group `Vault-Clients` created
- [ ] Windows client added to `Vault-Clients` group
- [ ] gMSA allows `Vault-Clients` to retrieve password
- [ ] Keytab generated and converted to base64

### **Windows Client:**
- [ ] Computer is member of `Vault-Clients` AD group
- [ ] Rebooted after group membership change
- [ ] gMSA installed: `Install-ADServiceAccount -Identity vault-gmsa`
- [ ] gMSA test passes: `Test-ADServiceAccount -Identity vault-gmsa` returns `True`
- [ ] Scheduled task created with `-LogonType Password` (NO password parameter)
- [ ] PowerShell script deployed to `C:\vault-client\scripts\`
- [ ] DNS resolution works: `vault.local.lab` resolves
- [ ] Network connectivity: Can reach Vault on port 8200

### **Vault Server:**
- [ ] Keytab copied to server
- [ ] Auth method configured with keytab
- [ ] Role created with correct policies
- [ ] Network accessible from Windows client

---

## 🧪 **Testing**

### **Test 1: gMSA Installation**

```powershell
# On Windows Client
Test-ADServiceAccount -Identity vault-gmsa
# Expected: True
```

### **Test 2: Scheduled Task**

```powershell
# On Windows Client
Start-ScheduledTask -TaskName "VaultClientApp"
Start-Sleep -Seconds 5
Get-Content "C:\vault-client\config\vault-client.log" -Tail 30
```

**Expected Success:**
```
[SUCCESS] Service ticket obtained for HTTP/vault.local.lab
[SUCCESS] Credentials handle acquired
[SUCCESS] Security context initialized
[SUCCESS] Real SPNEGO token generated!
[SUCCESS] Vault authentication successful!
```

### **Test 3: Manual Verification**

```powershell
# Check current user when task runs
whoami
# Expected: LOCAL\vault-gmsa$

# Check Kerberos tickets
klist
# Expected: Tickets for vault-gmsa$, including HTTP/vault.local.lab
```

---

## 🔧 **Troubleshooting**

### **Issue: `Test-ADServiceAccount` returns `False`**

**Solutions:**
```powershell
# 1. Verify group membership
Get-ADGroupMember -Identity "Vault-Clients"

# 2. Verify gMSA permissions
Get-ADServiceAccount vault-gmsa -Properties PrincipalsAllowedToRetrieveManagedPassword

# 3. Reboot the client
Restart-Computer

# 4. Wait for replication (if multiple DCs)
Start-Sleep -Seconds 300
```

### **Issue: `0x80090308` Error**

**This means SPN mismatch. Verify:**
```powershell
# Check SPN registration
setspn -L vault-gmsa
# Must show: HTTP/vault.local.lab

# Check Vault keytab was created for same SPN
# Keytab must be for HTTP/vault.local.lab
```

### **Issue: Scheduled Task Fails with "User not logged on"**

**Solution:**
```powershell
# Ensure you used LogonType Password, NOT ServiceAccount
$principal = New-ScheduledTaskPrincipal `
    -UserId "local.lab\vault-gmsa$" `
    -LogonType Password `
    -RunLevel Highest

Set-ScheduledTask -TaskName "VaultClientApp" -Principal $principal
```

---

## 🎯 **Summary: Your Passwordless Setup**

```
1. Windows Client (Passwordless):
   ├── Scheduled Task: local.lab\vault-gmsa$ (NO password!)
   ├── gMSA retrieves password from AD automatically
   ├── Script runs with gMSA credentials
   └── Generates SPNEGO token

2. Vault Server:
   ├── Validates using gMSA keytab
   ├── Keytab password is static (doesn't rotate on Linux)
   └── Issues Vault token

3. Result:
   ✅ 100% passwordless (no password management needed)
   ✅ gMSA as designed (auto password retrieval)
   ✅ Secure Kerberos authentication
   ✅ Works with your existing vault-client-app.ps1
```

---

## 📚 **References**

1. [Microsoft - SQL Server on Linux AD Authentication](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-active-directory-authentication)
2. [Microsoft - gMSA KVNO and Keytab Management](https://learn.microsoft.com/en-us/answers/questions/172186/manage-service-account-kvno-and-keytab)
3. [FrankyWeb - gMSA for Tasks and Services](https://www.frankysweb.de/en/group-managed-service-accounts-gmsa-for-tasks-and-services/)

---

## 🚀 **Quick Start Commands**

```powershell
# === ON DOMAIN CONTROLLER ===
# 1. Create gMSA
New-ADServiceAccount -Name vault-gmsa -DNSHostName vault-gmsa.local.lab -ServicePrincipalNames "HTTP/vault.local.lab" -PrincipalsAllowedToRetrieveManagedPassword "Vault-Clients"

# 2. Generate keytab
ktpass -princ HTTP/vault.local.lab@LOCAL.LAB -mapuser LOCAL\vault-gmsa$ -crypto AES256-SHA1 -ptype KRB5_NT_PRINCIPAL -pass "YourPassword123!" -out vault-gmsa.keytab

# === ON WINDOWS CLIENT ===
# 3. Install gMSA
Install-ADServiceAccount -Identity vault-gmsa
Test-ADServiceAccount -Identity vault-gmsa

# 4. Create scheduled task (NO PASSWORD!)
$principal = New-ScheduledTaskPrincipal -UserId "local.lab\vault-gmsa$" -LogonType Password -RunLevel Highest
Register-ScheduledTask -TaskName "VaultClientApp" -Action $action -Trigger $trigger -Principal $principal

# 5. Test
Start-ScheduledTask -TaskName "VaultClientApp"
```

**That's it! Your passwordless gMSA authentication is complete!** 🎉
