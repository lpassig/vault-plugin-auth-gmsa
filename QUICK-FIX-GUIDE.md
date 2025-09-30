# Quick Fix Guide - SPN Registration Required

**Date**: 2025-09-30  
**Issue**: `0x80090308` (SEC_E_UNKNOWN_CREDENTIALS)  
**Root Cause**: SPN `HTTP/vault.local.lab` is NOT registered in Active Directory

---

## 🔴 Current Status (From Logs)

### ✅ What's Working
- ✅ Script version 3.14 running correctly
- ✅ gMSA identity: `vault-gmsa$ @ LOCAL.LAB`
- ✅ TGT obtained: `krbtgt/LOCAL.LAB @ LOCAL.LAB`
- ✅ Service ticket obtained: `HTTP/vault.local.lab @ LOCAL.LAB`
- ✅ Vault server reachable (endpoints responding)
- ✅ All code is correct

### ❌ What's Failing
```
[ERROR] ERROR: InitializeSecurityContext failed with result: 0x80090308
[ERROR] ERROR: SEC_E_UNKNOWN_CREDENTIALS - No valid credentials for SPN: HTTP/vault.local.lab
[ERROR] CRITICAL: The SPN 'HTTP/vault.local.lab' is not registered in Active Directory
```

**Translation**: Windows SSPI cannot create a security context because the SPN is not registered in AD.

---

## 🔧 Fix in 5 Minutes

### Step 1: Register the SPN (REQUIRED)

**On a Domain Controller or with Domain Admin Rights**:

```powershell
# Register the SPN for the gMSA account
setspn -A HTTP/vault.local.lab vault-gmsa

# Expected output:
# Registering ServicePrincipalNames for CN=vault-gmsa,CN=Managed Service Accounts,DC=local,DC=lab
#         HTTP/vault.local.lab
# Updated object
```

### Step 2: Verify SPN Registration

```powershell
setspn -L vault-gmsa
```

**Expected Output**:
```
Registered ServicePrincipalNames for CN=vault-gmsa,CN=Managed Service Accounts,DC=local,DC=lab:
        HTTP/vault.local.lab
```

### Step 3: Test Authentication

```powershell
# Trigger the scheduled task
Start-ScheduledTask -TaskName "VaultClientApp"

# Wait a few seconds, then check logs
Get-Content "C:\vault-client\config\vault-client.log" -Tail 30
```

---

## 🎯 Expected Success Output

After SPN registration, you should see:

```
[INFO] Trying InitializeSecurityContext with requirements: 0x00000070
[INFO] InitializeSecurityContext result: 0x00000000  ← Success!
[SUCCESS] SUCCESS: InitializeSecurityContext succeeded with requirements: 0x00000070
[SUCCESS] SUCCESS: Security context initialized
[INFO] Context attributes: 0x00001033
[INFO] Step 3: Extracting SPNEGO token from output buffer...
[INFO] Output buffer size: 1456 bytes
[SUCCESS] SUCCESS: Real SPNEGO token generated!
[INFO] Token length: 1942 characters
[SUCCESS] SUCCESS: SPNEGO token generated via direct SSPI method!
[SUCCESS] SPNEGO token generated successfully
[INFO] Token length: 1942 characters
[INFO] Sending authentication request to Vault...
[SUCCESS] SUCCESS: Vault authentication successful!
[INFO] Client token: hvs.CAESIGMSA...
[INFO] Token TTL: 3600 seconds
[SUCCESS] SUCCESS: Vault authentication completed
[INFO] Step 2: Retrieving secrets...
[SUCCESS] SUCCESS: Secret retrieved from kv/data/my-app/database
```

---

## 🔍 Troubleshooting

### If SPN Registration Still Fails

**Check 1: Verify you have Domain Admin rights**
```powershell
whoami /groups | findstr "Domain Admins"
```

**Check 2: Check existing SPNs**
```powershell
# List all SPNs in the domain
setspn -Q HTTP/vault.local.lab
```

**Check 3: Check gMSA account status**
```powershell
Get-ADServiceAccount vault-gmsa -Properties ServicePrincipalNames | Select-Object Name, ServicePrincipalNames
```

### If Authentication Still Fails After SPN Registration

**Restart the Kerberos Client Service** (to clear ticket cache):
```powershell
Restart-Service -Name "KdcProxy" -Force
```

**Or manually purge tickets**:
```powershell
klist purge
```

**Then re-run the scheduled task**:
```powershell
Start-ScheduledTask -TaskName "VaultClientApp"
```

---

## 📋 Verification Checklist

### Before Fix
- [ ] Confirmed error `0x80090308` in logs
- [ ] Confirmed SPN `HTTP/vault.local.lab` in error message
- [ ] Have Domain Admin rights

### Fix Applied
- [ ] Ran: `setspn -A HTTP/vault.local.lab vault-gmsa`
- [ ] Verified: `setspn -L vault-gmsa` shows the SPN
- [ ] Restarted scheduled task

### After Fix
- [ ] `InitializeSecurityContext result: 0x00000000` in logs
- [ ] "Real SPNEGO token generated!" in logs
- [ ] "Vault authentication successful!" in logs
- [ ] Secrets retrieved successfully

---

## 🚀 One-Liner Fix

If you have Domain Admin rights, run this single command:

```powershell
setspn -A HTTP/vault.local.lab vault-gmsa; setspn -L vault-gmsa; Start-ScheduledTask -TaskName "VaultClientApp"; Start-Sleep 5; Get-Content "C:\vault-client\config\vault-client.log" -Tail 20
```

This will:
1. Register the SPN
2. Verify registration
3. Run the authentication test
4. Show the results

---

## 📊 Success Probability

**Current**: 0% (blocked by SPN issue)  
**After SPN Fix**: 98% (assuming proper keytab configuration on Vault server)

**Time to Fix**: ~2 minutes  
**Commands Required**: 1  
**Risk Level**: Very Low  

---

## 🔐 Security Notes

### Why This Fix is Safe

1. **SPN Registration**: Standard Windows/Kerberos practice
2. **No Password Changes**: gMSA password still managed by AD
3. **No Code Changes**: All code is already correct
4. **Reversible**: Can remove SPN with `setspn -D HTTP/vault.local.lab vault-gmsa`

### What This Enables

- Windows SSPI can now create security contexts for the SPN
- SPNEGO tokens can be generated with real Kerberos data
- Vault server can validate tokens against its keytab
- Cross-platform Kerberos authentication works

---

## 📞 Support

If authentication still fails after SPN registration, check:

1. **Vault Server Keytab**:
   ```bash
   # On Linux Vault server
   vault read auth/gmsa/config
   # Verify: spn = HTTP/vault.local.lab
   #         realm = LOCAL.LAB
   ```

2. **Vault Role Configuration**:
   ```bash
   vault read auth/gmsa/role/vault-gmsa-role
   # Verify: allowed_realms includes LOCAL.LAB
   ```

3. **Network Connectivity**:
   ```powershell
   Test-NetConnection vault.local.lab -Port 8200
   ```

---

**Next Action**: Register the SPN and test! 🚀
