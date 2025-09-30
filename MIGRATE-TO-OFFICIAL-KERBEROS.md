# 🔄 Migration to Official HashiCorp Kerberos Plugin

## Decision: Use Official Kerberos Plugin

**Why switch from custom gMSA plugin to official Kerberos plugin:**

✅ **Official HashiCorp support** - Better maintenance and updates  
✅ **Standard HTTP Negotiate protocol** - Proven implementation  
✅ **Better documentation** - Community resources available  
✅ **Same functionality** - Supports computer accounts and service accounts  
✅ **Cross-platform tested** - Windows ↔ Linux validated by HashiCorp  

## Architecture Overview

```
Windows Client (EC2AMAZ-UB1QVDL)
  ├─ Runs as: NT AUTHORITY\SYSTEM
  ├─ Network auth: EC2AMAZ-UB1QVDL$@LOCAL.LAB (computer account)
  ├─ Client: curl.exe --negotiate
  └─ SPNEGO Token → Authorization: Negotiate header

Linux Vault Server (52.59.253.119)
  ├─ Plugin: vault-plugin-auth-kerberos (official)
  ├─ Endpoint: /v1/auth/kerberos/login
  ├─ Validation: Keytab-based (no domain join needed)
  └─ SPN: HTTP/vault.local.lab@LOCAL.LAB
```

---

## Part 1: Vault Server Setup (Linux)

### Step 1.1: Install Official Kerberos Plugin

**On Vault server:**

```bash
# The official Kerberos plugin is built-in to Vault (v1.2.0+)
# No separate installation needed!

# Verify Vault version
vault version

# Expected: Vault v1.11.0+ or higher
```

### Step 1.2: Enable Kerberos Auth Method

```bash
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TOKEN="your-vault-token-here"

# Enable the official Kerberos auth method
vault auth enable \
  -passthrough-request-headers=Authorization \
  -allowed-response-headers=www-authenticate \
  kerberos

# Verify it's enabled
vault auth list
```

### Step 1.3: Configure Kerberos Auth with Computer Account Keytab

**Using the keytab we already generated:**

```bash
# Base64 keytab for computer account EC2AMAZ-UB1QVDL$
KEYTAB_B64="BQIAAABRAAIACUxPQ0FMLkxBQgAESFRUUAAPdmF1bHQubG9jYWwubGFiAAAAAQAAAAACABIAIHm5fmpYTbxb5crqox9cK2YfECBk6LYDOMzV/EFE5s4Z"

# Decode and save keytab
echo "$KEYTAB_B64" | base64 -d > /tmp/vault-computer.keytab

# Configure Kerberos auth
vault write auth/kerberos/config \
  keytab="$(cat /tmp/vault-computer.keytab | base64)" \
  service_account="HTTP/vault.local.lab" \
  realm="LOCAL.LAB" \
  remove_instance_name=true \
  disable_fast_negotiation=false

# Verify configuration
vault read auth/kerberos/config
```

### Step 1.4: Create Role for Computer Accounts

```bash
# Create role for Windows machine accounts
vault write auth/kerberos/config/ldap \
  url="ldap://10.0.101.152" \
  binddn="CN=vault-keytab-svc,CN=Users,DC=local,DC=lab" \
  bindpass="your-password-here" \
  userdn="CN=Computers,DC=local,DC=lab" \
  userattr="sAMAccountName" \
  groupdn="CN=Users,DC=local,DC=lab" \
  groupattr="cn"

# Create role for computer accounts
vault write auth/kerberos/role/computer-accounts \
  bound_service_account_names="*$@LOCAL.LAB" \
  token_policies="default,computer-policy" \
  token_ttl=3600 \
  token_max_ttl=7200
```

### Step 1.5: Create Policy for Computer Accounts

```bash
# Create policy for computer accounts
vault policy write computer-policy - <<EOF
# Allow reading secrets in secret/data/app/*
path "secret/data/app/*" {
  capabilities = ["read", "list"]
}

# Allow reading database credentials
path "database/creds/app-role" {
  capabilities = ["read"]
}

# Allow token renewal
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF
```

---

## Part 2: Windows Client Setup

### Step 2.1: Update PowerShell Client Script

**Create new client script for official Kerberos plugin:**

```powershell
# vault-client-kerberos.ps1
# Windows Client for Official HashiCorp Vault Kerberos Plugin

param(
    [string]$VaultUrl = "https://vault.local.lab:8200",
    [string]$Role = "computer-accounts"
)

$LogFile = "C:\vault-client\logs\vault-kerberos.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

function Test-KerberosAuth {
    Write-Log "=== Vault Kerberos Authentication (Official Plugin) ===" "INFO"
    Write-Log "Current User: $env:USERNAME" "INFO"
    Write-Log "Computer: $env:COMPUTERNAME" "INFO"
    Write-Log "Domain: $env:USERDNSDOMAIN" "INFO"
    Write-Log "Vault URL: $VaultUrl" "INFO"
    Write-Log "Role: $Role" "INFO"
    
    # Check Kerberos tickets
    Write-Log "Checking Kerberos tickets..." "INFO"
    $tickets = klist 2>&1 | Out-String
    Write-Log $tickets "INFO"
    
    # Authenticate using curl.exe with --negotiate
    Write-Log "Authenticating to Vault using curl.exe --negotiate..." "INFO"
    
    $curlPath = "C:\Windows\System32\curl.exe"
    if (-not (Test-Path $curlPath)) {
        Write-Log "curl.exe not found!" "ERROR"
        return $null
    }
    
    # Create request body
    $body = @{role = $Role} | ConvertTo-Json -Compress
    $tempFile = "$env:TEMP\vault-kerberos-body.json"
    $body | Out-File -FilePath $tempFile -Encoding ASCII -NoNewline -Force
    
    # Use curl.exe with --negotiate for automatic SPNEGO
    $curlArgs = @(
        "--negotiate",
        "--user", ":",
        "-X", "POST",
        "-H", "Content-Type: application/json",
        "--data-binary", "@$tempFile",
        "-k",
        "-s",
        "$VaultUrl/v1/auth/kerberos/login"
    )
    
    Write-Log "Executing: curl.exe $($curlArgs -join ' ')" "INFO"
    
    try {
        $response = & $curlPath $curlArgs 2>&1 | Out-String
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        
        Write-Log "Response: $response" "INFO"
        
        # Parse JSON response
        $authResponse = $response | ConvertFrom-Json -ErrorAction Stop
        
        if ($authResponse.auth -and $authResponse.auth.client_token) {
            Write-Log "SUCCESS! Vault token obtained" "SUCCESS"
            Write-Log "Token: $($authResponse.auth.client_token)" "INFO"
            Write-Log "TTL: $($authResponse.auth.lease_duration) seconds" "INFO"
            
            return $authResponse.auth.client_token
        } else {
            Write-Log "Authentication failed - no token in response" "ERROR"
            return $null
        }
        
    } catch {
        Write-Log "Authentication failed: $($_.Exception.Message)" "ERROR"
        Write-Log "Response: $response" "ERROR"
        return $null
    }
}

function Get-VaultSecret {
    param(
        [string]$Token,
        [string]$SecretPath = "secret/data/app/config"
    )
    
    Write-Log "Retrieving secret from: $SecretPath" "INFO"
    
    $curlArgs = @(
        "-H", "X-Vault-Token: $Token",
        "-k",
        "-s",
        "$VaultUrl/v1/$SecretPath"
    )
    
    try {
        $response = & "C:\Windows\System32\curl.exe" $curlArgs 2>&1 | Out-String
        $secret = $response | ConvertFrom-Json -ErrorAction Stop
        
        Write-Log "Secret retrieved successfully" "SUCCESS"
        return $secret
        
    } catch {
        Write-Log "Failed to retrieve secret: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Main execution
try {
    # Authenticate
    $token = Test-KerberosAuth
    
    if ($token) {
        # Get a sample secret
        $secret = Get-VaultSecret -Token $token -SecretPath "secret/data/app/config"
        
        if ($secret) {
            Write-Log "Application configured successfully!" "SUCCESS"
        }
    } else {
        Write-Log "Authentication failed!" "ERROR"
        exit 1
    }
    
} catch {
    Write-Log "Script failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
```

### Step 2.2: Deploy Updated Client

**On Windows CLIENT:**

```powershell
# Create directories
New-Item -ItemType Directory -Path "C:\vault-client\scripts" -Force
New-Item -ItemType Directory -Path "C:\vault-client\logs" -Force

# Save the script above as C:\vault-client\scripts\vault-client-kerberos.ps1

# Update scheduled task
$taskName = "Vault Kerberos Auth"
$scriptPath = "C:\vault-client\scripts\vault-client-kerberos.ps1"

schtasks /Delete /TN "$taskName" /F 2>$null

schtasks /Create /TN "$taskName" `
  /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -VaultUrl `"https://vault.local.lab:8200`" -Role `"computer-accounts`"" `
  /SC HOURLY /RU "NT AUTHORITY\SYSTEM" /RL HIGHEST /F
```

### Step 2.3: Verify SPN Registration

**On ADDC:**

```powershell
# Check current SPN registration
setspn -Q HTTP/vault.local.lab

# If on vault-gmsa, move to computer account
setspn -D HTTP/vault.local.lab vault-gmsa
setspn -A HTTP/vault.local.lab EC2AMAZ-UB1QVDL$

# Verify
setspn -L EC2AMAZ-UB1QVDL$
# Should show: HTTP/vault.local.lab
```

---

## Part 3: Testing

### Step 3.1: Test Authentication

**On Windows CLIENT:**

```powershell
# Run the scheduled task
schtasks /Run /TN "Vault Kerberos Auth"

# Wait for completion
Start-Sleep -Seconds 5

# Check logs
Get-Content C:\vault-client\logs\vault-kerberos.log -Tail 50
```

### Step 3.2: Expected Output

```
[2025-09-30 12:00:00] [INFO] === Vault Kerberos Authentication (Official Plugin) ===
[2025-09-30 12:00:00] [INFO] Current User: EC2AMAZ-UB1QVDL$
[2025-09-30 12:00:00] [INFO] Computer: EC2AMAZ-UB1QVDL
[2025-09-30 12:00:00] [INFO] Domain: local.lab
[2025-09-30 12:00:00] [INFO] Vault URL: https://vault.local.lab:8200
[2025-09-30 12:00:00] [INFO] Role: computer-accounts
[2025-09-30 12:00:00] [INFO] Authenticating to Vault using curl.exe --negotiate...
[2025-09-30 12:00:01] [SUCCESS] SUCCESS! Vault token obtained
[2025-09-30 12:00:01] [INFO] Token: hvs.XXXXXXXXXXXXXXXXXX
[2025-09-30 12:00:01] [INFO] TTL: 3600 seconds
[2025-09-30 12:00:01] [SUCCESS] Application configured successfully!
```

---

## Part 4: Troubleshooting

### Issue 1: 401 Unauthorized

**Check keytab configuration:**

```bash
# On Vault server
vault read auth/kerberos/config

# Verify keytab is configured
# Expected: service_account="HTTP/vault.local.lab"
```

### Issue 2: SPN Issues

**On ADDC:**

```powershell
# Verify SPN is on computer account
setspn -L EC2AMAZ-UB1QVDL$

# Should show HTTP/vault.local.lab
```

### Issue 3: No Kerberos Ticket

**On Windows CLIENT (as SYSTEM):**

```powershell
# Use PsExec to check tickets as SYSTEM
PsExec64.exe -s -i cmd
klist

# Should show TGT for EC2AMAZ-UB1QVDL$@LOCAL.LAB
```

---

## Migration Checklist

- [ ] **Vault Server**: Enable official Kerberos auth method
- [ ] **Vault Server**: Configure with computer account keytab
- [ ] **Vault Server**: Create role for computer accounts
- [ ] **Vault Server**: Create policy for computer accounts
- [ ] **Windows CLIENT**: Deploy new `vault-client-kerberos.ps1`
- [ ] **Windows CLIENT**: Update scheduled task
- [ ] **ADDC**: Verify/move SPN to computer account
- [ ] **Testing**: Run scheduled task and verify logs
- [ ] **Cleanup**: Disable custom gMSA auth method (optional)

---

## Benefits of Official Plugin

✅ **Maintained by HashiCorp** - Regular updates and security patches  
✅ **Standard protocol** - HTTP Negotiate (RFC 4559)  
✅ **Better documentation** - Official docs and community support  
✅ **Cross-platform** - Tested with Windows/Linux/macOS  
✅ **LDAP integration** - Group-based authorization  
✅ **Enterprise features** - MFA, audit logging, monitoring  

---

## Next Steps

1. **Run Vault server setup commands** (Part 1)
2. **Deploy new client script** (Part 2)
3. **Test authentication** (Part 3)
4. **Monitor and validate** (Part 4)

**Ready to migrate!** 🚀
