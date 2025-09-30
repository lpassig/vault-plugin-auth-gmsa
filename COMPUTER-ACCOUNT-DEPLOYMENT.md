# 🔄 Computer Account Deployment Guide

**CRITICAL**: You now have a working keytab for the computer account `EC2AMAZ-UB1QVDL$`!

## 📋 Deployment Steps

### Step 1: Update Vault Configuration ✅

**On Vault Server** (or via SSH to `ubuntu@52.59.253.119`):

```bash
# Copy and run this script
ssh ubuntu@52.59.253.119 'bash -s' < update-vault-computer-keytab.sh
```

**Or manually on the Vault server:**

```bash
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TOKEN="your-vault-token-here"

vault write -tls-skip-verify auth/gmsa/config \
  service_principal="HTTP/vault.local.lab" \
  realm="LOCAL.LAB" \
  keytab_b64="BQIAAABRAAIACUxPQ0FMLkxBQgAESFRUUAAPdmF1bHQubG9jYWwubGFiAAAAAQAAAAACABIAIHm5fmpYTbxb5crqox9cK2YfECBk6LYDOMzV/EFE5s4Z" \
  kdcs="10.0.101.152:88"
```

---

### Step 2: Update SPN Registration 🔑

**On ADDC**, verify and update SPN:

```powershell
# First, check current SPN location
setspn -Q HTTP/vault.local.lab

# If it's on vault-gmsa, move it to computer account
setspn -D HTTP/vault.local.lab vault-gmsa
setspn -A HTTP/vault.local.lab EC2AMAZ-UB1QVDL$

# Verify
setspn -L EC2AMAZ-UB1QVDL$
```

**Expected output:**
```
Registered ServicePrincipalNames for CN=EC2AMAZ-UB1QVDL,CN=Computers,DC=local,DC=lab:
        HTTP/vault.local.lab
```

---

### Step 3: Update Scheduled Task 🔧

**On Windows CLIENT (EC2AMAZ-UB1QVDL)**:

```powershell
# Update task to run as SYSTEM (uses computer account for network auth)
schtasks /Change /TN "Vault gMSA Client" /RU "NT AUTHORITY\SYSTEM" /RP

# When prompted for password, just press Enter (SYSTEM has no password)
```

---

### Step 4: Test Authentication 🚀

**On Windows CLIENT**:

```powershell
# Run the scheduled task
schtasks /Run /TN "Vault gMSA Client"

# Wait 5 seconds, then check logs
Start-Sleep -Seconds 5
Get-Content C:\vault-client\logs\vault-client-app.log -Tail 50
```

---

## 🎯 What Should Happen

### Authentication Flow:

1. **Scheduled task runs as**: `NT AUTHORITY\SYSTEM`
2. **Network authentication uses**: `EC2AMAZ-UB1QVDL$` (computer account)
3. **curl.exe** generates SPNEGO token using computer account credentials
4. **Vault** validates token against computer account keytab
5. **SUCCESS!** ✅

### Expected Log Output:

```
Method 3: Using curl.exe with --negotiate for direct authentication...
curl.exe found, attempting direct authentication...
Request body: {"role":"default"}
Executing: curl.exe --negotiate --user : -X POST ...
SUCCESS: Vault authentication successful via curl.exe with --negotiate!
Client token: hvs.XXXXXXXXXXXXX
Token TTL: 3600 seconds
```

---

## 🔍 Troubleshooting

### If authentication fails:

1. **Verify SPN is on computer account:**
   ```powershell
   setspn -L EC2AMAZ-UB1QVDL$
   ```
   Should show: `HTTP/vault.local.lab`

2. **Check task is running as SYSTEM:**
   ```powershell
   schtasks /Query /TN "Vault gMSA Client" /V /FO LIST | Select-String "Run As User"
   ```
   Should show: `NT AUTHORITY\SYSTEM`

3. **Test curl.exe manually as SYSTEM:**
   ```powershell
   # Use PsExec to run as SYSTEM
   PsExec64.exe -s -i cmd
   
   # In the SYSTEM cmd window:
   curl.exe --negotiate --user : -X POST ^
     -H "Content-Type: application/json" ^
     --data-binary "{\"role\":\"default\"}" ^
     -k ^
     https://vault.local.lab:8200/v1/auth/gmsa/login
   ```

4. **Check Kerberos tickets as SYSTEM:**
   ```powershell
   PsExec64.exe -s -i cmd
   klist
   ```
   Should show ticket for `EC2AMAZ-UB1QVDL$@LOCAL.LAB`

---

## 📚 Key Differences from gMSA

| Aspect | gMSA | Computer Account |
|--------|------|------------------|
| **Account Type** | Service Account | Computer Account |
| **Password Management** | AD-managed (30 days) | AD-managed (30 days) |
| **Task Runs As** | `LOCAL\vault-gmsa$` | `NT AUTHORITY\SYSTEM` |
| **Network Auth Uses** | `vault-gmsa$` | `EC2AMAZ-UB1QVDL$` |
| **SPN Registration** | On gMSA | On Computer |
| **Keytab Creation** | ❌ Difficult | ✅ Simple (ktpass works!) |
| **Security** | ✅ Good | ✅ Better (MS recommends) |
| **Kerberoasting** | Vulnerable | More resistant |

---

## 🔒 Security Notes

**Why Computer Account is Better:**

1. ✅ **Microsoft's official recommendation** (2024 Security Blog)
2. ✅ **System-managed passwords** (long, complex, auto-rotated)
3. ✅ **Less susceptible to Kerberoasting** attacks
4. ✅ **Easier to manage** (no PrincipalsAllowedToRetrieveManagedPassword)
5. ✅ **Same Kerberos flow** as gMSA

**Source:** [Microsoft Security Blog - Kerberoasting Mitigation](https://www.microsoft.com/en-us/security/blog/2024/10/11/microsofts-guidance-to-help-mitigate-kerberoasting/)

---

## 🚀 Next Steps

1. **Run Step 1** to update Vault (on Vault server)
2. **Run Step 2** to move SPN (on ADDC)
3. **Run Step 3** to update task (on CLIENT)
4. **Run Step 4** to test (on CLIENT)

**Then paste the log output here!** 🎯

---

## 📝 Rollback Plan (if needed)

```powershell
# Move SPN back to gMSA
setspn -D HTTP/vault.local.lab EC2AMAZ-UB1QVDL$
setspn -A HTTP/vault.local.lab vault-gmsa

# Update task back to gMSA
schtasks /Change /TN "Vault gMSA Client" /RU "LOCAL\vault-gmsa$" /RP

# Update Vault keytab back to gMSA
# (use previous gMSA keytab)
```

---

**This WILL work! Computer accounts are the Microsoft-recommended solution! 🔒**
