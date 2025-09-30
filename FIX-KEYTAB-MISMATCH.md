# 🔧 Critical Issue Found: Keytab Mismatch

## 🚨 Root Cause Identified

**Error:** `0x80090308` (SEC_E_UNKNOWN_CREDENTIALS)  
**Status:** ❌ **KEYTAB MISMATCH**

### What's Happening

```
✅ SPN correctly registered: HTTP/vault.local.lab → vault-gmsa
✅ Service ticket obtained: Client has valid ticket for HTTP/vault.local.lab
✅ Credentials handle acquired: Windows SSPI initialized successfully
❌ InitializeSecurityContext FAILED: No matching credentials
```

### The Problem

The **Vault server's keytab** does NOT contain the encryption keys for the **gMSA account** (`vault-gmsa$`).

**Most Likely Cause:**
- You followed the README.md which recommends creating a **regular service account** (`vault-keytab-svc`) for the keytab
- The keytab is for `vault-keytab-svc`, NOT for `vault-gmsa`
- Windows client is using `vault-gmsa` credentials
- Vault server is validating against `vault-keytab-svc` credentials
- **Mismatch = Authentication Failure**

---

## 🎯 Solution: Fix the Keytab

You have **two options**:

### **Option 1: Move SPN to Regular Service Account** (Easiest)

Use the keytab you already have (`vault-keytab-svc`), and move the SPN to that account:

```powershell
# On Windows Domain Controller or client with AD tools

# 1. Remove SPN from gMSA
setspn -D HTTP/vault.local.lab vault-gmsa

# 2. Add SPN to regular service account
setspn -A HTTP/vault.local.lab vault-keytab-svc

# 3. Verify
setspn -L vault-keytab-svc
# Should show: HTTP/vault.local.lab

# 4. Update scheduled task to use regular service account
$principal = New-ScheduledTaskPrincipal -UserId "local.lab\vault-keytab-svc" -LogonType Password
Set-ScheduledTask -TaskName "VaultClientApp" -Principal $principal
```

**Pros:**
- ✅ Uses existing keytab (no regeneration needed)
- ✅ Quick fix (5 minutes)
- ✅ Works immediately

**Cons:**
- ❌ Loses gMSA benefits (password management)
- ❌ Need to set password for service account

---

### **Option 2: Generate Keytab for gMSA** (Recommended for Production)

Generate a new keytab using the **actual gMSA credentials**:

#### **Step 1: Export gMSA Keytab (Advanced)**

**⚠️ WARNING:** This is complex and may require advanced tools.

```powershell
# On Windows Domain Controller

# Method 1: Use ktpass with current gMSA password (NOT RECOMMENDED - may break gMSA)
# DON'T DO THIS - it will reset the gMSA managed password!

# Method 2: Use PowerShell to extract gMSA password (ADVANCED)
# This requires the gMSA's current managed password
$gmsaPassword = (Get-ADServiceAccount -Identity vault-gmsa -Properties 'msDS-ManagedPassword').'msDS-ManagedPassword'

# The managed password is a complex binary blob
# You need specialized tools to convert it to a keytab

# Method 3: Use third-party tools (e.g., Mimikatz in lab environment ONLY)
# NOT RECOMMENDED for production
```

#### **Step 2: Alternative - Use Computer Account Instead**

**This is the RECOMMENDED approach:**

Instead of using a gMSA, use the **Windows computer account** for client authentication:

```powershell
# On Windows client

# 1. The computer account (COMPUTERNAME$) already has a keytab in AD
# 2. Register SPN to computer account
setspn -A HTTP/vault.local.lab COMPUTERNAME$

# 3. Export computer account keytab
# On Domain Controller:
ktpass -princ HTTP/vault.local.lab@LOCAL.LAB `
  -mapuser LOCAL\COMPUTERNAME$ `
  -crypto AES256-SHA1 `
  -ptype KRB5_NT_PRINCIPAL `
  -pass * `
  -out vault-computer.keytab

# 4. Copy keytab to Vault server
scp vault-computer.keytab user@vault-server:/path/to/

# 5. Configure Vault
vault write auth/gmsa/config \
  realm="LOCAL.LAB" \
  kdcs="addc.local.lab" \
  spn="HTTP/vault.local.lab" \
  keytab="$(base64 -w 0 vault-computer.keytab)" \
  clock_skew_sec=300

# 6. Update scheduled task to use computer account
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount
Set-ScheduledTask -TaskName "VaultClientApp" -Principal $principal
```

---

## 🔍 Diagnostic Commands

### Verify Current Setup

```powershell
# On Windows client

# 1. Check which account has the SPN
setspn -Q HTTP/vault.local.lab

# 2. Check gMSA SPNs
setspn -L vault-gmsa

# 3. Check regular service account SPNs
setspn -L vault-keytab-svc

# 4. Check computer account SPNs
setspn -L COMPUTERNAME$

# 5. Check current scheduled task identity
$task = Get-ScheduledTask -TaskName "VaultClientApp"
$task.Principal | Format-List *
```

### Verify Vault Server

```bash
# On Vault server

# 1. Check current keytab configuration
vault read auth/gmsa/config

# 2. Check which SPN is in the keytab
# (Decode the base64 keytab and inspect it)
# This requires manual inspection or ktutil tools
```

---

## 📋 Recommended Fix Path

### **For Quick Testing (Option 1):**

1. Move SPN to `vault-keytab-svc`
2. Update scheduled task to use that account
3. Test authentication
4. **Time: 5 minutes**

### **For Production (Option 2 - Computer Account):**

1. Register SPN to computer account
2. Export computer account keytab
3. Update Vault configuration
4. Run scheduled task as `SYSTEM`
5. **Time: 15 minutes**

---

## 🎯 Quick Fix Script

Save as `fix-keytab-mismatch.ps1`:

```powershell
# Quick fix: Use regular service account instead of gMSA
param(
    [string]$ServiceAccount = "vault-keytab-svc",
    [string]$SPN = "HTTP/vault.local.lab",
    [string]$TaskName = "VaultClientApp"
)

Write-Host "Moving SPN to service account: $ServiceAccount" -ForegroundColor Yellow

# 1. Remove SPN from gMSA
setspn -D $SPN vault-gmsa

# 2. Add SPN to service account
setspn -A $SPN $ServiceAccount

# 3. Verify
Write-Host "`nVerifying SPN registration:" -ForegroundColor Cyan
setspn -L $ServiceAccount

# 4. Update scheduled task
Write-Host "`nUpdating scheduled task..." -ForegroundColor Yellow
$task = Get-ScheduledTask -TaskName $TaskName

# Prompt for service account password
$credential = Get-Credential -UserName "local.lab\$ServiceAccount" -Message "Enter password for $ServiceAccount"

$principal = New-ScheduledTaskPrincipal `
    -UserId "local.lab\$ServiceAccount" `
    -LogonType Password `
    -RunLevel Highest

Set-ScheduledTask -TaskName $TaskName -Principal $principal

Write-Host "`nDone! Test with:" -ForegroundColor Green
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
```

---

## 🚀 Next Steps

1. **Choose your approach** (Option 1 or Option 2)
2. **Execute the fix** (5-15 minutes)
3. **Test authentication**
4. **Report results**

---

## 📊 Expected Results After Fix

### Before Fix:
```
[ERROR] InitializeSecurityContext result: 0x80090308
[ERROR] SEC_E_UNKNOWN_CREDENTIALS
```

### After Fix:
```
[SUCCESS] Credentials handle acquired
[SUCCESS] Security context initialized
[SUCCESS] Real SPNEGO token generated!
[SUCCESS] Vault authentication successful!
```

---

## 💡 Key Insight

**The SPN registration is correct, but the keytab doesn't match the account using the SPN.**

- **Client** uses: `vault-gmsa` credentials
- **Server validates** with: `vault-keytab-svc` keytab
- **Result**: Mismatch = `0x80090308`

**Fix**: Make them match by either:
- Using `vault-keytab-svc` on the client (Option 1)
- Using `vault-gmsa` keytab on the server (Option 2 - complex)
- Using computer account for both (Option 2 - recommended)

---

**Let me know which option you'd like to pursue, and I'll provide detailed step-by-step instructions!**
