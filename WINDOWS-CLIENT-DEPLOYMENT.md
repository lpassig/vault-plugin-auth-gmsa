# 🚀 Windows Client Deployment - 2 Scripts Only!

## ✅ **Simple 2-Script Deployment**

You only need **2 files** on your Windows client to deploy and test the gMSA authentication:

1. **`test-http-negotiate.ps1`** - Test authentication
2. **`setup-vault-client.ps1`** - Deploy application and create scheduled task

That's it! Everything else is automated.

---

## 📥 **Step 1: Download the 2 Scripts**

On your Windows client:

```powershell
# Clone the repository
git clone https://github.com/lpassig/vault-plugin-auth-gmsa.git
cd vault-plugin-auth-gmsa

# You now have:
# ✓ test-http-negotiate.ps1
# ✓ setup-vault-client.ps1
# ✓ vault-client-app.ps1 (will be deployed by setup script)
```

---

## 🧪 **Step 2: Test Authentication (Optional but Recommended)**

Run this **once** to verify authentication works:

```powershell
# As Administrator
.\test-http-negotiate.ps1
```

**Expected Output:**
```
=========================================
Test HTTP Negotiate Authentication
=========================================

Current Identity: LOCAL\vault-gmsa$
Vault URL: https://vault.local.lab:8200

✓ Service ticket found for HTTP/vault.local.lab

Test 1: Invoke-RestMethod with UseDefaultCredentials
-----------------------------------------------
✓ SUCCESS!
  Token: hvs.CAESIJ3OhFlnPCzJqRq7dDgBEWtMZRtzI3UGTXcDBV9RRWlm...
  TTL: 768h0m0s
  Policies: gmsa-policy

=========================================
✅ HTTP Negotiate authentication WORKS!
=========================================
```

**If the test fails**, see the troubleshooting section at the bottom.

---

## 📦 **Step 3: Deploy with Setup Script**

Run this **once** to deploy everything:

```powershell
# As Administrator
.\setup-vault-client.ps1

# OR with custom parameters
.\setup-vault-client.ps1 `
    -VaultUrl "https://vault.local.lab:8200" `
    -VaultRole "default" `
    -TaskName "VaultClientApp" `
    -Schedule "Daily" `
    -Time "02:00"
```

**What this script does:**

1. ✅ **Checks prerequisites**
   - Running as Administrator
   - gMSA is installed and working
   - Vault server is reachable

2. ✅ **Creates directory structure**
   ```
   C:\vault-client\
   ├── config\
   ├── logs\
   └── scripts\
   ```

3. ✅ **Deploys `vault-client-app.ps1`**
   - Copies from current directory to `C:\vault-client\scripts\`
   - Creates backup of old version (if exists)
   - Verifies file size and version

4. ✅ **Creates scheduled task**
   - Name: `VaultClientApp` (or custom name)
   - Identity: `local.lab\vault-gmsa$`
   - Schedule: Daily at 02:00 (or custom)
   - Action: Run `vault-client-app.ps1`

5. ✅ **Tests the deployment**
   - Triggers the scheduled task
   - Checks logs
   - Displays recent log entries

**Expected Output:**
```
=== Vault Client Application Setup ===
Vault URL: https://vault.local.lab:8200
Vault Role: default
Task Name: VaultClientApp

✓ Running as Administrator
✓ gMSA 'vault-gmsa' is installed and working
✓ Vault server is reachable: vault.local.lab:8200
✓ Created directory: C:\vault-client\scripts
✓ Application script updated: C:\vault-client\scripts\vault-client-app.ps1
✓ Scheduled task created successfully: VaultClientApp
✓ Log file exists: C:\vault-client\config\vault-client.log

SUCCESS: Setup Completed Successfully!

The application will run automatically Daily at 02:00 under gMSA identity!
```

---

## ✅ **Step 4: Verify Deployment**

Check if everything is working:

```powershell
# Check the scheduled task
Get-ScheduledTask -TaskName "VaultClientApp"

# Manually trigger the task
Start-ScheduledTask -TaskName "VaultClientApp"

# Wait a few seconds
Start-Sleep -Seconds 5

# Check the logs
Get-Content "C:\vault-client\config\vault-client.log" -Tail 30
```

**Expected Log Output:**
```
[2025-09-30 10:XX:XX] [INFO] Script version: 4.0 (HTTP Negotiate Protocol)
[2025-09-30 10:XX:XX] [INFO] Current user: LOCAL\vault-gmsa$
[2025-09-30 10:XX:XX] [INFO] Vault URL: https://vault.local.lab:8200
[2025-09-30 10:XX:XX] [INFO] Method 1: Using Invoke-RestMethod with UseDefaultCredentials...
[2025-09-30 10:XX:XX] [SUCCESS] Vault authentication successful via HTTP Negotiate!
[2025-09-30 10:XX:XX] [INFO] Client token: hvs.CAESIJ...
[2025-09-30 10:XX:XX] [SUCCESS] Secret retrieved from kv/data/my-app/database
[2025-09-30 10:XX:XX] [SUCCESS] Retrieved 2 secrets
[2025-09-30 10:XX:XX] [SUCCESS] Vault Client Application completed successfully
```

---

## 📂 **Final Directory Structure**

After deployment, your Windows client will have:

```
C:\vault-client\
├── config\
│   ├── vault-client-config.json     # Created by setup
│   ├── vault-client.log             # Created by app
│   ├── database-config.json         # Created by app (if secrets exist)
│   └── api-config.json              # Created by app (if secrets exist)
├── logs\
└── scripts\
    └── vault-client-app.ps1         # Deployed by setup
```

**Scheduled Task:**
- Name: `VaultClientApp`
- Identity: `local.lab\vault-gmsa$`
- Schedule: Daily at 02:00 (or custom)
- Script: `C:\vault-client\scripts\vault-client-app.ps1`

---

## 🔄 **Updating the Script**

If you need to update `vault-client-app.ps1`:

```powershell
# Pull latest changes
git pull

# Re-run setup (it will backup old version and deploy new one)
.\setup-vault-client.ps1
```

The setup script **automatically**:
- ✅ Creates a backup of the old script
- ✅ Copies the new version
- ✅ Updates the scheduled task
- ✅ Verifies the update

---

## 🔍 **Troubleshooting**

### **Test Script Fails**

**Error: "No token in response"**

```powershell
# Check SPN registration
setspn -L vault-gmsa

# Should show:
# HTTP/vault.local.lab

# If missing, register it:
setspn -A HTTP/vault.local.lab vault-gmsa
```

**Error: "SSL/TLS certificate error"**

```powershell
# The script already handles this, but verify:
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
```

**Error: "Cannot resolve vault.local.lab"**

```powershell
# Add to hosts file
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "`n107.23.32.117 vault.local.lab"

# OR use IP address
.\setup-vault-client.ps1 -VaultUrl "https://107.23.32.117:8200"
```

### **Scheduled Task Fails**

**Check task identity:**

```powershell
$task = Get-ScheduledTask -TaskName "VaultClientApp"
$task.Principal

# Should show:
# UserId: local.lab\vault-gmsa$
# LogonType: Password
```

**Check gMSA permissions:**

```powershell
# Verify gMSA has "Log on as a batch job" right
secpol.msc

# Navigate to:
# Local Policies → User Rights Assignment → Log on as a batch job
# Add: local.lab\vault-gmsa$
```

**Check logs for errors:**

```powershell
Get-Content "C:\vault-client\config\vault-client.log" -Tail 50
```

---

## 📋 **Quick Reference**

### **Installation (One-Time Setup)**

```powershell
# 1. Download scripts
git clone https://github.com/lpassig/vault-plugin-auth-gmsa.git
cd vault-plugin-auth-gmsa

# 2. Test (optional)
.\test-http-negotiate.ps1

# 3. Deploy
.\setup-vault-client.ps1
```

### **Verification**

```powershell
# Check task
Get-ScheduledTask -TaskName "VaultClientApp"

# Run manually
Start-ScheduledTask -TaskName "VaultClientApp"

# Check logs
Get-Content "C:\vault-client\config\vault-client.log" -Tail 30
```

### **Update Script**

```powershell
# Pull updates
git pull

# Re-deploy
.\setup-vault-client.ps1
```

---

## ✅ **Success Checklist**

- [ ] Downloaded 2 scripts: `test-http-negotiate.ps1` and `setup-vault-client.ps1`
- [ ] Test script succeeds (optional but recommended)
- [ ] Setup script completes successfully
- [ ] Scheduled task created: `Get-ScheduledTask -TaskName "VaultClientApp"`
- [ ] Task runs under gMSA: `Get-ScheduledTask | Select Principal`
- [ ] Logs show success: `Get-Content vault-client.log`
- [ ] Secrets retrieved (check logs)

---

## 🎉 **That's It!**

You've successfully deployed the gMSA authentication client using **only 2 scripts**:

1. ✅ `test-http-negotiate.ps1` - Test authentication
2. ✅ `setup-vault-client.ps1` - Deploy and configure

The application now runs automatically under gMSA identity and authenticates to Vault using the **HTTP Negotiate protocol** - no more `0x80090308` errors!

**The scheduled task will run automatically** according to your schedule (default: Daily at 02:00).

---

## 📚 **Additional Documentation**

- [HTTP Negotiate Protocol Support](HTTP-NEGOTIATE-PROTOCOL-SUPPORT.md)
- [Complete Deployment Guide](DEPLOYMENT-GUIDE-HTTP-NEGOTIATE.md)
- [Final Solution Summary](FINAL-SOLUTION-SUMMARY.md)

Need help? Check the troubleshooting section above or review the logs!
