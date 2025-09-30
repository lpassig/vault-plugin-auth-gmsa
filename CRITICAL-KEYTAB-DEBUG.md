# 🔍 CRITICAL: Keytab Encryption Type Mismatch Investigation

## 📊 **Current Situation**

**Windows Client (EC2AMAZ-UB1QVDL):**
- ✅ Service ticket obtained: `Server: HTTP/vault.local.lab @ LOCAL.LAB`
- ✅ Encryption type: `AES-256-CTS-HMAC-SHA1-96`
- ❌ InitializeSecurityContext fails: `0x80090308` (SEC_E_UNKNOWN_CREDENTIALS)

**Vault Server:**
- ✅ Keytab uploaded and configured
- ✅ SPN: `HTTP/vault.local.lab`
- ✅ Realm: `LOCAL.LAB`
- ❌ Keytab validation failing

---

## 🚨 **ROOT CAUSE: Keytab Generation Method**

The keytab was generated using:
```powershell
ktpass -princ HTTP/vault.local.lab@LOCAL.LAB `
    -mapuser LOCAL\vault-gmsa$ `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -setupn -setpass `
    -pass <password> `
    -out vault-gmsa-new.keytab
```

**PROBLEM:**
- `ktpass` uses the password to generate the keytab
- But the password we extracted might not be the **actual Kerberos key**
- gMSA uses a **128-byte managed password**, but Kerberos keys are derived differently

---

## ✅ **SOLUTION: Use ktutil on Linux**

Instead of `ktpass` (which requires a password), use **`ktutil`** on the Vault server (Linux) to generate the keytab from the **actual Kerberos key**.

### **Step 1: On ADDC (PowerShell as SYSTEM)**

Extract the **Kerberos AES256 key** (not just the password):

```powershell
# Get the gMSA account
$gmsa = Get-ADServiceAccount -Identity vault-gmsa -Properties 'msDS-ManagedPassword'

# Get the password blob
$passwordBlob = $gmsa.'msDS-ManagedPassword'

# Extract the key material (bytes 16-47 for AES256 key)
$aesKey = $passwordBlob[16..47]

# Convert to hex
$aesKeyHex = ($aesKey | ForEach-Object { $_.ToString('X2') }) -join ''

# Output
Write-Host "AES256 Key (hex): $aesKeyHex"
```

### **Step 2: On Vault Server (Linux)**

Create keytab using `ktutil`:

```bash
# Create keytab using ktutil
ktutil << EOF
add_entry -password -p HTTP/vault.local.lab@LOCAL.LAB -k 1 -e aes256-cts-hmac-sha1-96
<paste-hex-key-here>
write_kt /tmp/vault-gmsa.keytab
quit
EOF

# Base64 encode
base64 -w 0 /tmp/vault-gmsa.keytab > /tmp/vault-gmsa.keytab.b64

# Update Vault
export VAULT_SKIP_VERIFY=1
vault write auth/gmsa/config \
    keytab="$(cat /tmp/vault-gmsa.keytab.b64)" \
    spn='HTTP/vault.local.lab' \
    realm='LOCAL.LAB' \
    kdcs='ADDC.local.lab:88'
```

---

## 🔄 **Alternative: Use msDS-KeyCredentialLink (Modern Approach)**

If the above doesn't work, we can use the **new Windows Server Key Credentials API**:

```powershell
# On ADDC - Extract the actual Kerberos key
$gmsa = Get-ADServiceAccount -Identity vault-gmsa -Properties 'msDS-ManagedPassword'
$mp = $gmsa.'msDS-ManagedPassword'

# The actual AES256 key is embedded in the blob
# Bytes 16-47: Current AES256 key
$currentKey = $mp[16..47]

# Output as hex for ktutil
$hexKey = -join ($currentKey | ForEach-Object { '{0:X2}' -f $_ })
Write-Host "Current AES256 Key: $hexKey"
```

---

## 🎯 **Next Steps**

1. **Extract the AES256 key** (not the password) from the gMSA blob on ADDC
2. **Generate keytab on Linux** using `ktutil` with the hex key
3. **Update Vault** with the new keytab
4. **Test authentication** - should work now!

The issue is that `ktpass` on Windows doesn't properly generate keytabs for gMSAs because it expects a password reset, but we need the **actual Kerberos key material** from the managed password blob.
