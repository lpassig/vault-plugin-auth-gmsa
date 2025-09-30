# ✅ gMSA Keytab Solution - Complete Guide

## 🎯 Objective

Use **gMSA** for client authentication with a proper keytab on the Vault server.

---

## 📋 Current Situation

You've moved the SPN from `vault-gmsa` to `vault-keytab-svc`, but you want to use gMSA. Here's how to fix it:

---

## 🔧 Solution Steps

### **Step 1: Restore SPN to gMSA**

```powershell
# Remove SPN from vault-keytab-svc
setspn -D HTTP/vault.local.lab vault-keytab-svc

# Add SPN back to vault-gmsa
setspn -A HTTP/vault.local.lab vault-gmsa

# Verify
setspn -L vault-gmsa
```

**Expected output:**
```
Registered ServicePrincipalNames for CN=vault-gmsa,CN=Managed Service Accounts,DC=local,DC=lab:
        HTTP/vault.local.lab
```

---

### **Step 2: Generate Keytab for gMSA**

⚠️ **CRITICAL WARNING:** When running `ktpass`, it will ask if you want to change the password. **YOU MUST ANSWER 'n' (NO)**. If you answer 'y' (yes), it will reset the gMSA's managed password and break the account!

```powershell
# Run ktpass to generate keytab
ktpass -princ HTTP/vault.local.lab@LOCAL.LAB `
    -mapuser LOCAL\vault-gmsa$ `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -pass * `
    -out vault-gmsa.keytab

# When prompted: "Do you want to change the password? (y/n)"
# ANSWER: n
```

**Expected output:**
```
Targeting domain controller: ADDC.local.lab
Successfully mapped HTTP/vault.local.lab to vault-gmsa$.
WARNING: Account vault-gmsa$ is not a user account (uacflags do not include UF_NORMAL_ACCOUNT).
WARNING: Resetting vault-gmsa$'s password may cause authentication problems if vault-gmsa$ is being used as an interdomain trust account.
Do you want to continue this operation? (y/n) [n]:  n
Key created.
Output keytab to vault-gmsa.keytab:
Keytab version: 0x502
keysize 73 HTTP/vault.local.lab@LOCAL.LAB ptype 1 (KRB5_NT_PRINCIPAL) vno 3 etype 0x12 (AES256-SHA1) keylength 32 (0x8d5a...)
```

**Important Notes:**
- The warning about "not a user account" is **NORMAL** for gMSA
- The warning about "resetting password" is why you must answer **'n' (NO)**
- If the keytab is created successfully, you'll see "Key created" and "Output keytab to vault-gmsa.keytab"

---

### **Step 3: Convert Keytab to Base64**

```powershell
# Convert keytab to base64 for Vault configuration
[Convert]::ToBase64String([IO.File]::ReadAllBytes("vault-gmsa.keytab")) | Out-File vault-gmsa.keytab.b64 -Encoding ASCII

# Verify the file was created
Get-Item vault-gmsa.keytab.b64
```

---

### **Step 4: Copy Keytab to Vault Server**

```powershell
# Copy keytab to Vault server (use your actual server details)
scp vault-gmsa.keytab.b64 user@vault-server:/tmp/
```

---

### **Step 5: Update Vault Configuration**

On the **Vault server**:

```bash
# Update Vault auth method configuration with new keytab
vault write auth/gmsa/config \
  realm="LOCAL.LAB" \
  kdcs="addc.local.lab" \
  spn="HTTP/vault.local.lab" \
  keytab="$(cat /tmp/vault-gmsa.keytab.b64)" \
  clock_skew_sec=300 \
  allow_channel_binding=true

# Verify configuration
vault read auth/gmsa/config
```

**Expected output:**
```
Key                       Value
---                       -----
allow_channel_binding     true
clock_skew_sec            300
kdcs                      [addc.local.lab]
realm                     LOCAL.LAB
spn                       HTTP/vault.local.lab
```

(Note: The keytab itself won't be displayed for security reasons)

---

### **Step 6: Test Authentication**

On the **Windows client**:

```powershell
# Run the scheduled task
Start-ScheduledTask -TaskName 'VaultClientApp'

# Wait a moment
Start-Sleep -Seconds 5

# Check the logs
Get-Content 'C:\vault-client\config\vault-client.log' -Tail 30
```

**Expected successful output:**
```
[INFO] Generating SPNEGO token using Windows SSPI for SPN: HTTP/vault.local.lab
[SUCCESS] Credentials handle acquired
[SUCCESS] Security context initialized
[SUCCESS] Real SPNEGO token generated!
[SUCCESS] Vault authentication successful!
[SUCCESS] Retrieved 2 secrets
```

---

## 🚀 Automated Script

For your convenience, I've created `fix-for-gmsa-keytab.ps1` that automates all these steps:

```powershell
# Run the automated fix script
.\fix-for-gmsa-keytab.ps1
```

This script will:
1. ✅ Restore SPN to vault-gmsa
2. ✅ Generate keytab for gMSA
3. ✅ Convert to base64
4. ✅ Provide next steps for Vault configuration

---

## 🔍 Troubleshooting

### Issue: "ktpass failed to create keytab"

**Cause:** You answered 'y' to the password change prompt.

**Solution:** 
1. Run `Test-ADServiceAccount -Identity vault-gmsa` - if it returns `False`, the gMSA is broken
2. Reset the gMSA: `Reset-ADServiceAccountPassword -Identity vault-gmsa`
3. Run the keytab generation again, this time answering **'n' (NO)**

---

### Issue: "Still getting 0x80090308 error"

**Possible causes:**

1. **Keytab not updated on Vault server**
   ```bash
   # Verify Vault configuration
   vault read auth/gmsa/config
   ```

2. **SPN not correctly registered**
   ```powershell
   # Verify SPN
   setspn -L vault-gmsa
   # Should show: HTTP/vault.local.lab
   ```

3. **Keytab encryption type mismatch**
   ```bash
   # Check keytab contents (on Linux)
   ktutil -k vault-gmsa.keytab list
   # Should show: AES256-SHA1 encryption
   ```

---

### Issue: "Access Denied when running ktpass"

**Solution:** Run PowerShell as **Administrator** on a **Domain Controller** or a machine with AD management tools.

---

## 📊 Verification Checklist

After completing all steps, verify:

- [ ] SPN is registered to `vault-gmsa`: `setspn -L vault-gmsa`
- [ ] Keytab file exists: `Test-Path vault-gmsa.keytab`
- [ ] Base64 file exists: `Test-Path vault-gmsa.keytab.b64`
- [ ] Keytab copied to Vault server
- [ ] Vault configuration updated: `vault read auth/gmsa/config`
- [ ] gMSA is working: `Test-ADServiceAccount -Identity vault-gmsa` returns `True`
- [ ] Scheduled task uses gMSA: `(Get-ScheduledTask -TaskName "VaultClientApp").Principal.UserId` shows `local.lab\vault-gmsa$`

---

## 🎉 Expected Final Result

After completing these steps, your authentication should succeed:

```
Client (Windows):   Uses vault-gmsa credentials
                    ↓
                    Obtains service ticket for HTTP/vault.local.lab
                    ↓
                    Generates real SPNEGO token
                    ↓
Vault Server:       Validates token using vault-gmsa keytab
                    ↓
                    ✅ SUCCESS! Token matches keytab
                    ↓
                    Issues Vault token with policies
```

---

## ⏱️ Time Estimate

- **Automated script:** 5 minutes
- **Manual steps:** 10-15 minutes
- **Total including testing:** 15-20 minutes

---

## 📞 Next Steps

1. Run `.\fix-for-gmsa-keytab.ps1` on Windows client
2. Copy keytab to Vault server
3. Update Vault configuration
4. Test authentication
5. Report results! 🚀
