# ✅ Vault Configured - Ready for Testing!

## 🎉 Configuration Complete!

The official HashiCorp Kerberos plugin has been successfully configured on your Vault server.

---

## Current Configuration

### Vault Server (107.23.32.117)

✅ **Auth Method:** `kerberos` (official plugin)  
✅ **Endpoint:** `/v1/auth/kerberos/login`  
✅ **SPN:** `HTTP/vault.local.lab@LOCAL.LAB`  
✅ **Keytab:** Computer account `EC2AMAZ-UB1QVDL$`  
✅ **LDAP:** Configured for group lookups  

### Groups & Policies

| Group | Policies | Purpose |
|-------|----------|---------|
| `computer-accounts` | `computer-policy`, `default` | For Windows computer accounts |
| `default` | `default` | Fallback for authenticated users |

### computer-policy Permissions

```hcl
# Read secrets
path "secret/data/*" {
  capabilities = ["read", "list"]
}

# Database credentials
path "database/creds/*" {
  capabilities = ["read"]
}

# Token operations
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
```

---

## Test from Windows Client

### Prerequisites

1. **SPN Registration (on ADDC)**
   ```powershell
   # Verify SPN is on computer account
   setspn -L EC2AMAZ-UB1QVDL$
   
   # Should show:
   # HTTP/vault.local.lab
   
   # If not, move it:
   setspn -D HTTP/vault.local.lab vault-gmsa
   setspn -A HTTP/vault.local.lab EC2AMAZ-UB1QVDL$
   ```

2. **Client Files (on Windows CLIENT)**
   - `test-invoke-restmethod.ps1` (Pure PowerShell approach)
   - `vault-client-kerberos.ps1` (curl.exe approach)

---

## Option A: Test with Invoke-RestMethod (Recommended)

This is the **pure PowerShell** approach that uses `-UseDefaultCredentials`.

```powershell
# On Windows CLIENT
cd C:\Users\Testus\vault-plugin-auth-gmsa

# Pull latest version
git pull

# Run test
.\test-invoke-restmethod.ps1 -VaultAddr "https://vault.local.lab:8200"

# Script will pause - press any key when done reading

# Or check logs
Get-Content C:\vault-client\logs\test-invoke-restmethod.log -Tail 50
```

### Expected Success Output

```
========================================
TEST: Invoke-RestMethod with -UseDefaultCredentials
========================================

Environment Information:
  Current User: EC2AMAZ-UB1QVDL$
  Computer: EC2AMAZ-UB1QVDL
  Domain: local.lab
  Vault URL: https://vault.local.lab:8200

Checking Kerberos tickets...
[Shows TGT and service tickets]

Attempting authentication with Invoke-RestMethod...

========================================
SUCCESS! Authentication succeeded!
========================================

Token obtained: hvs.XXXXXXXXXXXXX
Token TTL: 3600 seconds
Token policies: computer-policy, default

✓ Token is valid - successfully retrieved secret

========================================
TEST COMPLETED SUCCESSFULLY!
========================================

Conclusion: Invoke-RestMethod with -UseDefaultCredentials WORKS!
This approach automatically generates SPNEGO tokens via Windows SSPI

Press any key to exit...
```

---

## Option B: Test with curl.exe

This approach uses `curl.exe --negotiate`.

```powershell
# On Windows CLIENT
C:\vault-client\scripts\vault-client-kerberos.ps1

# Or via scheduled task
schtasks /Create /TN "Vault Kerberos Auth" `
  /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\vault-client\scripts\vault-client-kerberos.ps1" `
  /SC HOURLY /RU "NT AUTHORITY\SYSTEM" /RL HIGHEST /F

schtasks /Run /TN "Vault Kerberos Auth"

# Check logs
Get-Content C:\vault-client\logs\vault-kerberos.log -Tail 50
```

---

## Troubleshooting

### If you get "401 Unauthorized"

1. **Check SPN registration (on ADDC):**
   ```powershell
   setspn -Q HTTP/vault.local.lab
   # Should show it's registered to EC2AMAZ-UB1QVDL$
   ```

2. **Check Kerberos tickets (on Windows CLIENT):**
   ```powershell
   klist
   # Should show TGT for EC2AMAZ-UB1QVDL$@LOCAL.LAB
   ```

3. **Verify Vault configuration (on Vault server):**
   ```bash
   export VAULT_ADDR="https://127.0.0.1:8200"
   export VAULT_TOKEN="your-token"
   
   vault read -tls-skip-verify auth/kerberos/config
   vault list -tls-skip-verify auth/kerberos/groups
   ```

### If you get "kerberos negotiation failed"

1. **Check keytab on Vault server:**
   ```bash
   vault read -tls-skip-verify auth/kerberos/config
   # Should show: service_account="HTTP/vault.local.lab"
   ```

2. **Verify computer account password hasn't rotated:**
   - Computer account passwords rotate every 30 days
   - If keytab is older than 30 days, regenerate it using `ktpass`

### If SSL/TLS errors

The test script already bypasses SSL validation for testing. For production:

```powershell
# Add Vault certificate to trusted root
# Or update $VaultUrl to use IP address
```

---

## Authentication Methods Comparison

| Method | Technology | Pros | Cons |
|--------|-----------|------|------|
| **Invoke-RestMethod** | Pure PowerShell | ✅ No curl dependency<br>✅ Native .NET<br>✅ Better error handling | ❌ Requires PowerShell 5.1+ |
| **curl.exe** | System curl | ✅ Always available<br>✅ Proven reliable | ❌ Less detailed errors<br>❌ Harder to parse output |

**Recommendation:** Use `Invoke-RestMethod` (test-invoke-restmethod.ps1) for better debugging and error messages.

---

## Next Steps

1. **Test authentication** with `test-invoke-restmethod.ps1`
2. **Verify token works** by accessing secrets
3. **Deploy to production** using scheduled task
4. **Monitor authentication** via Vault audit logs

---

## Architecture Summary

```
Windows Client (EC2AMAZ-UB1QVDL)
  ├─ Runs as: NT AUTHORITY\SYSTEM
  ├─ Network identity: EC2AMAZ-UB1QVDL$@LOCAL.LAB
  ├─ Kerberos ticket: HTTP/vault.local.lab
  └─ SPNEGO token: Auto-generated via Windows SSPI

        ↓ HTTPS + Negotiate Header

Linux Vault Server (107.23.32.117)
  ├─ Plugin: vault-plugin-auth-kerberos (official)
  ├─ Validates: SPNEGO token with keytab
  ├─ LDAP lookup: Group membership (optional)
  ├─ Group: computer-accounts
  ├─ Policies: computer-policy, default
  └─ Returns: Vault token (TTL: 3600s)

        ↓ Token-based Access

Vault Secrets
  ├─ secret/data/* (read, list)
  └─ database/creds/* (read)
```

---

## Quick Reference Commands

**Test authentication:**
```powershell
.\test-invoke-restmethod.ps1 -VaultAddr "https://vault.local.lab:8200"
```

**Check SPN (ADDC):**
```powershell
setspn -L EC2AMAZ-UB1QVDL$
```

**Check tickets (CLIENT):**
```powershell
klist
```

**Verify Vault (SERVER):**
```bash
vault read -tls-skip-verify auth/kerberos/config
```

---

**Everything is ready! Run the test script on Windows now!** 🚀
