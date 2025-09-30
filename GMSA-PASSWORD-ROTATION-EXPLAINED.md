# 🔄 gMSA Password Rotation - How It Works in This Setup

## ✅ **Yes, Password Rotation Still Works on Windows!**

This is the **key advantage** of the solution - you get the best of both worlds:

---

## 🔑 **How gMSA Password Rotation Works**

### **On Windows Client Side:**

✅ **Password DOES rotate** (default: every 30 days)  
✅ **Automatic rotation** by Active Directory  
✅ **No manual intervention** needed  
✅ **Client always gets latest password** from AD  

### **Why This Works:**

1. **Windows client is in `Vault-Clients` group**
2. **gMSA allows `Vault-Clients` to retrieve managed password**
3. **AD automatically rotates gMSA password every 30 days**
4. **Windows client retrieves NEW password from AD automatically**
5. **Scheduled task continues to work** (gets new password transparently)

---

## 🖥️ **The Complete Picture**

### **Scenario: gMSA Password Rotates After 30 Days**

```
Day 1-30: gMSA password = "AutoGenPassword123ABC"
│
├── Windows Client:
│   ├── Retrieves password from AD: "AutoGenPassword123ABC"
│   ├── Generates Kerberos ticket with this password
│   └── Creates SPNEGO token
│
└── Vault Server:
    ├── Has keytab with password: "VaultGMSA2025!Complex" (from ktpass)
    └── ❌ MISMATCH! Authentication will FAIL

Day 31: AD rotates gMSA password → "AutoGenPassword456DEF"
│
├── Windows Client:
│   ├── Retrieves NEW password from AD: "AutoGenPassword456DEF"
│   ├── Generates Kerberos ticket with NEW password
│   └── Creates SPNEGO token
│
└── Vault Server:
    ├── Still has old keytab: "VaultGMSA2025!Complex"
    └── ❌ MISMATCH! Authentication FAILS
```

---

## ⚠️ **The Critical Issue**

**When you set the password with `ktpass` (answering 'y'), you're temporarily setting a KNOWN password.**

**But AD will STILL rotate it after 30 days (or configured interval), and then:**
- ✅ Windows client gets new password → Works fine
- ❌ Vault keytab has old password → **Authentication FAILS**

---

## 🎯 **The REAL Solution: Disable Password Rotation**

According to [Microsoft's documentation](https://learn.microsoft.com/en-us/answers/questions/172186/manage-service-account-kvno-and-keytab):

> **"If you only use your gMSA on the Linux boxes and do not assign it to any Windows computer that is a member of AD, the password will not get changed."**

### **But in YOUR case:**

❌ You ARE using gMSA on Windows computers (for authentication)  
❌ This TRIGGERS password rotation  
❌ Keytab will become invalid after 30 days  

---

## ✅ **Correct Solution for Your Use Case**

You have **THREE options**:

### **Option 1: Computer Account (Recommended for Passwordless)**

**Use computer account instead of gMSA for client authentication:**

```powershell
# Client authenticates with computer account (passwordless)
# SPN registered to: COMPUTERNAME$
# Scheduled task runs as: NT AUTHORITY\SYSTEM

# Server validates with gMSA keytab (static)
# gMSA is NOT used by any Windows computers
# Password never rotates, keytab never expires
```

**Result:**
- ✅ Windows: 100% passwordless (computer account, auto-managed)
- ✅ Vault: Static keytab (gMSA not used by Windows, never rotates)
- ✅ Best of both worlds!

---

### **Option 2: Keytab Rotation Script (If Using gMSA on Windows)**

**If you MUST use gMSA on Windows client, implement keytab rotation:**

```powershell
# Scheduled script (runs before gMSA password rotation - e.g., every 25 days)

# 1. Get current gMSA password (requires special permissions)
$gmsaPassword = Get-ADServiceAccountPassword -Identity vault-gmsa

# 2. Generate new keytab with current password
ktpass -princ HTTP/vault.local.lab@LOCAL.LAB `
    -mapuser LOCAL\vault-gmsa$ `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -pass $gmsaPassword `
    -out vault-gmsa.keytab

# 3. Convert to base64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("vault-gmsa.keytab")) | Out-File vault-gmsa.keytab.b64 -Encoding ASCII

# 4. Update Vault configuration
vault write auth/gmsa/config keytab="$(cat /tmp/vault-gmsa.keytab.b64)"
```

**Challenges:**
- ❌ Complex (requires retrieving managed password)
- ❌ Needs elevated permissions
- ❌ Must run before each password rotation
- ❌ Introduces automation complexity

---

### **Option 3: Increase Password Rotation Interval**

**Extend gMSA password change interval:**

```powershell
# Set password to rotate less frequently (e.g., 365 days)
Set-ADServiceAccount -Identity vault-gmsa -ManagedPasswordIntervalInDays 365
```

**Then generate keytab and update Vault once per year.**

**Pros:**
- ✅ Simpler than Option 2
- ✅ Still uses gMSA on Windows

**Cons:**
- ❌ Still need manual keytab rotation annually
- ❌ Reduces security (password changes less often)

---

## 🎯 **My Recommendation: Option 1 (Computer Account)**

**For TRUE passwordless with no maintenance:**

### **Architecture:**

```
Windows Client:
├── Computer Account: COMPUTERNAME$ (auto password rotation by AD)
├── SPN: HTTP/vault.local.lab registered to COMPUTERNAME$
├── Scheduled Task: Runs as NT AUTHORITY\SYSTEM (uses computer account)
└── Result: 100% passwordless, no password management

Vault Server:
├── gMSA: vault-gmsa (NOT used by any Windows computers)
├── gMSA password: NEVER rotates (no computers retrieve it)
├── Keytab: Generated once, NEVER expires
└── Result: Static keytab, no rotation needed
```

### **Setup:**

```powershell
# === DOMAIN CONTROLLER ===
# Create gMSA WITHOUT PrincipalsAllowedToRetrieveManagedPassword
New-ADServiceAccount -Name vault-gmsa `
    -DNSHostName vault-gmsa.local.lab `
    -ServicePrincipalNames "HTTP/vault.local.lab"

# Generate keytab (answer 'y' - safe because no Windows computers use it)
ktpass -princ HTTP/vault.local.lab@LOCAL.LAB `
    -mapuser LOCAL\vault-gmsa$ `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -pass "StaticPassword123!" `
    -out vault-gmsa.keytab

# === WINDOWS CLIENT ===
# Register SPN to computer account
setspn -A HTTP/vault.local.lab COMPUTERNAME$

# Create scheduled task as SYSTEM (passwordless)
$principal = New-ScheduledTaskPrincipal `
    -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

Register-ScheduledTask -TaskName "VaultClientApp" -Action $action -Trigger $trigger -Principal $principal
```

**Benefits:**
- ✅ 100% passwordless on Windows (no password in task)
- ✅ Computer account password auto-rotates (security maintained)
- ✅ gMSA keytab NEVER expires (static password on Vault side)
- ✅ No maintenance, no automation needed
- ✅ Best security with zero complexity

---

## 📊 **Comparison Table**

| Aspect | gMSA on Windows (Current) | Computer Account (Recommended) |
|--------|---------------------------|--------------------------------|
| **Passwordless** | ✅ Yes | ✅ Yes |
| **Password Rotation** | ✅ Auto (30 days) | ✅ Auto (30 days) |
| **Keytab Rotation** | ❌ Required (30 days) | ✅ Never (static) |
| **Maintenance** | ❌ High (keytab sync) | ✅ Zero |
| **Complexity** | ❌ Medium-High | ✅ Low |
| **Security** | ✅ Good | ✅ Good |

---

## 🎯 **Direct Answer to Your Question**

**Q: Is the password rotation feature of gMSA still being used on the Windows client side?**

**A: It depends on the configuration:**

### **If you use gMSA on Windows client (PrincipalsAllowedToRetrieveManagedPassword set):**
- ✅ **YES**, password rotates every 30 days (default)
- ❌ **BUT** Vault keytab becomes invalid after rotation
- ⚠️ **REQUIRES** keytab rotation automation

### **If you use computer account on Windows client (recommended):**
- ✅ **YES**, computer account password rotates every 30 days
- ✅ **AND** gMSA is only for Vault keytab (never rotates)
- ✅ **NO** maintenance needed - perfect passwordless solution!

---

## 🚀 **Recommended Implementation Path**

1. **Use computer account for Windows client** (100% passwordless)
2. **Use gMSA only for Vault keytab** (static, never rotates)
3. **SPN on computer account**, not gMSA
4. **Scheduled task as SYSTEM**, not gMSA
5. **Zero maintenance** required

This gives you:
- ✅ Passwordless authentication (gMSA-like behavior via computer account)
- ✅ Automatic password rotation on Windows (computer account)
- ✅ Static keytab on Vault (no rotation needed)
- ✅ No automation complexity
- ✅ Production-ready solution

---

**Would you like me to provide the exact commands to implement Option 1 (Computer Account approach)?**
