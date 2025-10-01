# Generate Keytab for VAULT$ Computer Account

## On Windows Domain Controller (as Administrator)

Since we can't extract the existing computer password, we need to generate a new keytab with a new password.

**⚠️ IMPORTANT**: This will reset the VAULT$ computer account password, which means the Linux server will need to rejoin the domain.

### Step 1: Generate Keytab with ktpass

```powershell
ktpass -out C:\vault-computer-http.keytab `
  -princ HTTP/vault.local.lab@LOCAL.LAB `
  -mapuser CN=VAULT,CN=Computers,DC=local,DC=lab `
  -crypto AES256-SHA1 `
  -ptype KRB5_NT_PRINCIPAL `
  +rndpass `
  -setupn `
  -setpass
```

**Answer 'y' when asked to reset password** (this is necessary for computer accounts)

### Step 2: Base64 Encode the Keytab

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\vault-computer-http.keytab'))
```

Copy the base64 output.

### Step 3: Update Vault (I'll do this via SSH)

Just paste the base64 keytab in the chat!

---

## Alternative: Use the existing domain keytab approach

Instead of resetting passwords, we can configure the Linux Vault server to use its domain-joined keytab more effectively.

The issue is that the domain keytab has `host/vault.local.lab` but not `HTTP/vault.local.lab`.

We can either:
1. **Reset VAULT$ password** (use ktpass above)
2. **Use `msktutil` on Linux** to update the keytab with HTTP SPN
3. **Configure Vault to accept `host/` instead of `HTTP/`** (non-standard)

Which approach do you prefer?
