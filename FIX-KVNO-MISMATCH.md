# Fix KVNO Mismatch Issue

## Problem
The Vault keytab has kvno 2, but the client's service ticket has kvno 5. This happens when the computer account password was changed after keytab generation.

## Solution

### On Windows Client
Purge all Kerberos tickets to force fresh ticket acquisition:

```powershell
# Purge all tickets
klist purge -li 0x3e7

# Verify purged
klist -li 0x3e7
```

### On Domain Controller
Generate a fresh keytab **without resetting the password**:

```powershell
# Get current kvno
Get-ADComputer VAULT -Properties msDS-KeyVersionNumber | Select-Object msDS-KeyVersionNumber

# Generate keytab with current password (answer 'n' to password reset)
ktpass -out C:\vault-computer-http-v5.keytab `
  -princ HTTP/vault.local.lab@LOCAL.LAB `
  -mapuser CN=VAULT,CN=Computers,DC=local,DC=lab `
  -crypto AES256-SHA1 `
  -ptype KRB5_NT_PRINCIPAL `
  +rndpass `
  -setupn

# Answer 'n' when asked to reset password!

# Base64 encode
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\vault-computer-http-v5.keytab'))
```

Paste the base64 keytab here for Vault update.
