# 🚀 Production Deployment Guide

## Zero-Installation gMSA-to-Vault Authentication

This guide shows you how to deploy the **complete, production-ready** solution in your environment.

---

## ✅ **Prerequisites (5 Minutes)**

### **On Domain Controller:**
```powershell
# 1. Create gMSA (if not exists)
New-ADServiceAccount -Name vault-gmsa `
    -DNSHostName vault-gmsa.local.lab `
    -PrincipalsAllowedToRetrieveManagedPassword "Vault-Clients" `
    -KerberosEncryptionType AES256

# 2. Register SPN
setspn -A HTTP/vault.local.lab vault-gmsa

# 3. Verify
Test-ADServiceAccount -Identity vault-gmsa
setspn -L vault-gmsa
```

### **On Windows Client:**
```powershell
# 1. Install gMSA
Install-ADServiceAccount -Identity vault-gmsa

# 2. Verify installation
Test-ADServiceAccount -Identity vault-gmsa
# Expected: True

# 3. Join Vault-Clients group (if needed)
Add-ADGroupMember -Identity "Vault-Clients" -Members "EC2AMAZ-UB1QVDL$"
```

### **On Linux Vault Server:**
```bash
# 1. Enable gMSA auth method
vault auth enable -path=gmsa vault-plugin-auth-gmsa

# 2. Create policy
vault policy write vault-gmsa-policy - <<EOF
path "kv/data/*" {
  capabilities = ["read", "list"]
}
path "database/creds/*" {
  capabilities = ["read"]
}
EOF

# 3. Create role (will be updated with keytab in next step)
vault write auth/gmsa/role/vault-gmsa-role \
    bound_service_account_names="vault-gmsa" \
    policies="vault-gmsa-policy" \
    ttl=1h \
    max_ttl=4h
```

---

## 🎬 **Step 1: Deploy Client Scripts (2 Minutes)**

```powershell
# On Windows Client

# 1. Clone repository
git clone https://github.com/lpassig/vault-plugin-auth-gmsa.git
cd vault-plugin-auth-gmsa

# 2. Verify scripts are present
Get-ChildItem *.ps1 | Select-Object Name

# Expected files:
# - vault-client-app.ps1 (main script)
# - setup-vault-client.ps1 (deployment script)
# - setup-gmsa-complete.ps1 (complete automation)
# - generate-gmsa-keytab-dsinternals.ps1 (keytab generator)
# - monthly-keytab-rotation.ps1 (rotation script)
```

---

## 🔑 **Step 2: Generate Keytab (3 Minutes)**

```powershell
# On Windows Client (must be able to retrieve gMSA password)

# Option A: Complete automation (recommended)
.\setup-gmsa-complete.ps1 `
    -GMSAName "vault-gmsa" `
    -SPN "HTTP/vault.local.lab" `
    -Realm "LOCAL.LAB" `
    -VaultUrl "https://vault.local.lab:8200" `
    -VaultRole "vault-gmsa-role" `
    -VaultServer "107.23.32.117" `
    -VaultUser "lennart"

# Option B: Manual keytab generation only
.\generate-gmsa-keytab-dsinternals.ps1 `
    -GMSAName "vault-gmsa" `
    -SPN "HTTP/vault.local.lab" `
    -Realm "LOCAL.LAB" `
    -UpdateVault

# Expected output:
# ✓ DSInternals Module: Installed
# ✓ gMSA Password: Extracted from AD (240 chars)
# ✓ Keytab File: vault-gmsa-generated.keytab
# ✓ Base64 File: vault-gmsa-generated.keytab.b64
# ✓ Vault Server: Updated
```

---

## 🖥️ **Step 3: Setup Windows Client (2 Minutes)**

```powershell
# On Windows Client (as Administrator)

# 1. Run client setup
.\setup-vault-client.ps1 `
    -VaultUrl "https://vault.local.lab:8200" `
    -VaultRole "vault-gmsa-role" `
    -TaskName "VaultClientApp" `
    -SecretPaths @("kv/data/my-app/database", "kv/data/my-app/api")

# Expected output:
# ✓ Running as Administrator
# ✓ gMSA 'vault-gmsa' is installed and working
# ✓ Vault server is reachable: vault.local.lab:8200
# ✓ Created directory: C:\vault-client\scripts
# ✓ Application script updated: C:\vault-client\scripts\vault-client-app.ps1
# ✓ Scheduled task created successfully: VaultClientApp
#   - Identity: local.lab\vault-gmsa$
#   - Schedule: Daily at 02:00
#   - Script: C:\vault-client\scripts\vault-client-app.ps1
```

**What This Does:**
1. ✅ Copies `vault-client-app.ps1` to `C:\vault-client\scripts\`
2. ✅ Creates scheduled task under gMSA identity
3. ✅ Configures automatic execution
4. ✅ Sets up logging to `C:\vault-client\config\vault-client.log`

---

## 🧪 **Step 4: Test Authentication (1 Minute)**

```powershell
# On Windows Client

# 1. Manually trigger scheduled task
Start-ScheduledTask -TaskName "VaultClientApp"

# 2. Wait for completion
Start-Sleep -Seconds 5

# 3. Check task status
Get-ScheduledTaskInfo -TaskName "VaultClientApp"
# Expected: LastTaskResult = 0 (success)

# 4. View logs
Get-Content "C:\vault-client\config\vault-client.log" -Tail 30

# Expected output:
# [2025-09-30 14:30:00] [INFO] Script version: 3.15 (DSInternals Integration)
# [2025-09-30 14:30:00] [INFO] Starting Vault authentication process...
# [2025-09-30 14:30:00] [SUCCESS] Credentials handle acquired
# [2025-09-30 14:30:00] [SUCCESS] Security context initialized
# [2025-09-30 14:30:00] [SUCCESS] Real SPNEGO token generated!
# [2025-09-30 14:30:00] [SUCCESS] Vault authentication successful!
# [2025-09-30 14:30:00] [SUCCESS] Secret retrieved from kv/data/my-app/database
# [2025-09-30 14:30:00] [SUCCESS] Retrieved 2 secrets
```

---

## 🔄 **Step 5: Setup Monthly Keytab Rotation (Optional - 2 Minutes)**

```powershell
# On Windows Client (as Administrator)

# Schedule monthly keytab rotation (runs on day 25 of each month)
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\vault-client\scripts\monthly-keytab-rotation.ps1"

$trigger = New-ScheduledTaskTrigger `
    -Monthly `
    -DaysOfMonth 25 `
    -At "02:00AM"

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName "VaultKeytabRotation" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Description "Monthly keytab rotation for gMSA Vault authentication"

# Verify
Get-ScheduledTask -TaskName "VaultKeytabRotation"
```

**What This Does:**
1. ✅ Runs monthly on day 25 (before gMSA password rotation on day 30)
2. ✅ Extracts new gMSA password using DSInternals
3. ✅ Generates new keytab
4. ✅ Updates Vault server
5. ✅ Tests authentication
6. ✅ Rolls back if test fails

---

## 📊 **Step 6: Configure Dynamic Secrets (3 Minutes)**

### **Database Dynamic Secrets:**
```bash
# On Vault Server

# 1. Enable database secrets engine
vault secrets enable database

# 2. Configure PostgreSQL connection
vault write database/config/my-postgres \
    plugin_name=postgresql-database-plugin \
    allowed_roles="my-app-role" \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/mydb?sslmode=require" \
    username="vault" \
    password="vault-password"

# 3. Create role with 5-minute TTL
vault write database/roles/my-app-role \
    db_name=my-postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';" \
    default_ttl=5m \
    max_ttl=10m
```

### **AWS Dynamic Secrets:**
```bash
# On Vault Server

# 1. Enable AWS secrets engine
vault secrets enable aws

# 2. Configure AWS root credentials
vault write aws/config/root \
    access_key=AKIAI... \
    secret_key=wJalr... \
    region=us-east-1

# 3. Create role with 10-minute TTL
vault write aws/roles/my-app-role \
    credential_type=iam_user \
    policy_arns="arn:aws:iam::aws:policy/ReadOnlyAccess" \
    default_ttl=10m \
    max_ttl=15m
```

### **Update Client Script:**
```powershell
# On Windows Client

# Edit vault-client-app.ps1 parameters
# Change:
# $SecretPaths = @("kv/data/my-app/database", "kv/data/my-app/api")
# To:
# $SecretPaths = @("database/creds/my-app-role", "aws/creds/my-app-role")

# Re-deploy
.\setup-vault-client.ps1 `
    -VaultUrl "https://vault.local.lab:8200" `
    -VaultRole "vault-gmsa-role" `
    -SecretPaths @("database/creds/my-app-role", "aws/creds/my-app-role")
```

---

## 🔍 **Troubleshooting**

### **Issue: Authentication Fails with 0x80090308 (SEC_E_UNKNOWN_CREDENTIALS)**

**Cause:** Keytab mismatch (Vault keytab doesn't match gMSA password)

**Solution:**
```powershell
# Regenerate keytab with current gMSA password
.\generate-gmsa-keytab-dsinternals.ps1 -UpdateVault

# Test again
Start-ScheduledTask -TaskName "VaultClientApp"
Get-Content "C:\vault-client\config\vault-client.log" -Tail 30
```

---

### **Issue: Task Runs but No Logs**

**Cause:** Script not running under gMSA identity

**Solution:**
```powershell
# Verify task identity
Get-ScheduledTask -TaskName "VaultClientApp" | Select-Object -ExpandProperty Principal
# Expected: UserId = local.lab\vault-gmsa$

# Recreate task
.\setup-vault-client.ps1 -VaultUrl "https://vault.local.lab:8200"
```

---

### **Issue: Secrets Not Retrieved**

**Cause:** Vault policies don't allow access

**Solution:**
```bash
# On Vault Server

# Check current policy
vault policy read vault-gmsa-policy

# Update policy to include your secret paths
vault policy write vault-gmsa-policy - <<EOF
path "database/creds/*" {
  capabilities = ["read"]
}
path "aws/creds/*" {
  capabilities = ["read"]
}
path "kv/data/*" {
  capabilities = ["read", "list"]
}
EOF

# Verify role has the policy
vault read auth/gmsa/role/vault-gmsa-role
```

---

## 📈 **Production Checklist**

### **Security:**
- [ ] gMSA password rotates automatically (every 30 days)
- [ ] Keytab rotation scheduled (monthly)
- [ ] Secrets are memory-only (no disk writes)
- [ ] SSL/TLS enabled for Vault (not bypassed)
- [ ] Scheduled task runs with least privilege
- [ ] Logs don't contain sensitive data

### **Monitoring:**
- [ ] Scheduled task execution monitored
- [ ] Log file rotation configured
- [ ] Alerts on authentication failures
- [ ] Keytab rotation success/failure alerts
- [ ] Secret retrieval metrics tracked

### **High Availability:**
- [ ] Multiple Windows clients configured
- [ ] Vault cluster in HA mode
- [ ] Backup keytabs stored securely
- [ ] Fallback mechanisms in place

### **Documentation:**
- [ ] Architecture documented
- [ ] Runbook created for ops team
- [ ] Troubleshooting guide available
- [ ] Contact information for escalation

---

## 🎯 **Summary**

**Deployment Time: ~15 minutes**

1. ✅ Prerequisites (5 min)
2. ✅ Deploy scripts (2 min)
3. ✅ Generate keytab (3 min)
4. ✅ Setup client (2 min)
5. ✅ Test (1 min)
6. ✅ Rotation (optional - 2 min)

**Result:**
- Zero-installation Windows PowerShell client
- Passwordless gMSA authentication
- Dynamic secrets with 5-10 min TTL
- Memory-only processing
- Cross-platform (Windows → Linux Vault)
- Automated keytab rotation

**All requirements met! Ready for production!** 🚀

---

## 📞 **Support**

**Scripts:**
- `vault-client-app.ps1` - Main client script
- `setup-vault-client.ps1` - Deployment automation
- `setup-gmsa-complete.ps1` - Complete automation
- `generate-gmsa-keytab-dsinternals.ps1` - Keytab generator
- `monthly-keytab-rotation.ps1` - Rotation automation

**Documentation:**
- `ARCHITECTURE-SUMMARY.md` - Complete architecture
- `QUICK-START-GUIDE.md` - Quick start for all approaches
- `SOLUTION-COMPARISON.md` - Approach comparison
- `OPTION-1-COMPUTER-ACCOUNT-EXPLAINED.md` - Alternative approach

**GitHub:** https://github.com/lpassig/vault-plugin-auth-gmsa
