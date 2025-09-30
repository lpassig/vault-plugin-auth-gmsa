# 🚀 Switch to Computer Account Authentication

## Overview

We're switching from gMSA to **computer account** authentication based on:
- ✅ Microsoft's official security recommendation
- ✅ Easier keytab extraction
- ✅ Better resistance to Kerberoasting attacks
- ✅ Simpler implementation

---

## 📋 Step-by-Step Implementation

### **Step 1: Extract Computer Account Password (Windows Client)**

On your **Windows client** (as Administrator):

```powershell
# Method 1: Using mimikatz (if available)
# Download from: https://github.com/gentilkiwi/mimikatz/releases

# OR Method 2: Reset computer password (generates new one we can capture)
# This is the safest and most reliable method

# Get computer name
$computerName = $env:COMPUTERNAME
Write-Host "Computer Name: $computerName" -ForegroundColor Green

# Reset the computer account password and capture it
# This will generate a new random password
$newPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object {[char]$_})

# Use netdom to reset (requires Domain Admin or appropriate permissions)
netdom resetpwd /server:ADDC.local.lab /userd:LOCAL\Administrator /passwordd:*

# The password will be displayed during the process
```

**ALTERNATIVE (Recommended)**: Use DSInternals on the Domain Controller to extract the current password without resetting:

```powershell
# On ADDC (as Administrator)
Import-Module DSInternals

$computerName = "EC2AMAZ-UB1QVDL"  # Your client computer name
$computer = Get-ADComputer -Identity $computerName -Properties 'msDS-ManagedPassword'

# Note: Computer accounts don't have msDS-ManagedPassword like gMSAs
# We need to use a different approach

# The SIMPLEST method: Create a keytab using ktpass on the DC
# This will use the current computer account password
```

---

### **Step 2: Create Keytab Using ktpass (Simplest Method)**

On your **Domain Controller (ADDC)**:

```powershell
# This is the EASIEST method - ktpass can work with computer accounts!

ktpass -princ HTTP/vault.local.lab@LOCAL.LAB `
    -mapuser LOCAL\EC2AMAZ-UB1QVDL$ `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -pass * `
    -out C:\vault-computer.keytab

# When prompted "Do you want to change the password?", answer 'n' (NO)
# This will create a keytab with the CURRENT computer account password

# Base64 encode it
$keytabBytes = [System.IO.File]::ReadAllBytes("C:\vault-computer.keytab")
$keytabB64 = [Convert]::ToBase64String($keytabBytes)

Write-Host "Keytab Base64:" -ForegroundColor Green
Write-Host $keytabB64
Write-Host ""
Write-Host "Copy this base64 string!"
```

---

### **Step 3: Update SPN Registration**

On **ADDC**:

```powershell
# Remove SPN from gMSA
setspn -D HTTP/vault.local.lab vault-gmsa

# Add SPN to computer account
setspn -A HTTP/vault.local.lab EC2AMAZ-UB1QVDL

# Verify
setspn -L EC2AMAZ-UB1QVDL
```

---

### **Step 4: Update Scheduled Task to Run as SYSTEM**

On **Windows Client**:

```powershell
# Update the scheduled task to run as NT AUTHORITY\SYSTEM
# SYSTEM uses the computer account for network authentication

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\vault-client\scripts\vault-client-app.ps1"

$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM

$principal = New-ScheduledTaskPrincipal `
    -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName "VaultClientApp" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Force

Write-Host "✅ Scheduled task updated to run as SYSTEM" -ForegroundColor Green
```

---

### **Step 5: Update Vault Keytab**

I'll do this via SSH once you provide the base64 keytab from Step 2.

---

### **Step 6: Test Authentication**

```powershell
# Test the scheduled task
Start-ScheduledTask -TaskName 'VaultClientApp'

# Check logs
Get-Content C:\vault-client\config\vault-client.log -Tail 50
```

---

## 🎯 **Expected Result**

```
[INFO] Current user: nt authority\system
[INFO] Method 3: Using curl.exe with --negotiate for direct authentication...
> Authorization: Negotiate YIIHKwY...  (computer account SPNEGO token)
< HTTP/1.1 200 OK
[SUCCESS] SUCCESS: Vault authentication successful via curl.exe with --negotiate!
[INFO] Client token: hvs.CAES...
```

---

## 📊 **What Changed**

| Component | Before (gMSA) | After (Computer Account) |
|-----------|---------------|--------------------------|
| **Identity** | vault-gmsa$ | EC2AMAZ-UB1QVDL$ |
| **Task Runs As** | vault-gmsa | NT AUTHORITY\SYSTEM |
| **SPN** | HTTP/vault.local.lab (on vault-gmsa) | HTTP/vault.local.lab (on EC2AMAZ-UB1QVDL) |
| **Keytab** | gMSA password (hard to extract) | Computer password (easy via ktpass) |
| **Security** | Good | Better (per Microsoft) |

---

## 🔒 **Security Notes**

1. ✅ **Same security posture** - both use Kerberos with AES256
2. ✅ **Microsoft recommended** - explicitly preferred over service accounts
3. ✅ **Automatic password rotation** - managed by AD
4. ✅ **No human password management** - fully automated
5. ✅ **Audit trail** - all auth logged in Windows Security logs

---

## 🚀 **Let's Start!**

Run **Step 2** on your **ADDC** now:

```powershell
ktpass -princ HTTP/vault.local.lab@LOCAL.LAB `
    -mapuser LOCAL\EC2AMAZ-UB1QVDL$ `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -pass * `
    -out C:\vault-computer.keytab

# Then base64 encode and paste here!
```

**Paste the base64 output and I'll configure Vault immediately!** 🎯
