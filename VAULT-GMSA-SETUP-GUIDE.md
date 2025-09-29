# Vault gMSA Configuration Guide

## Overview
This guide helps you configure HashiCorp Vault with gMSA authentication for Windows clients connecting to a Linux Vault server.

## Prerequisites ✅
- [x] gMSA created: `vault-gmsa`
- [x] SPN registered: `HTTP/vault.local.lab`
- [x] Keytab created: `vault-keytab.keytab`
- [x] Windows client in `Vault-Clients` group
- [x] PowerShell script ready: `vault-client-app.ps1`

## Step 1: Copy Keytab to Linux Server

### Option A: Using SCP (Recommended)
```powershell
.\copy-keytab-to-linux.ps1 -LinuxServer "107.23.32.117" -Username "lennart"
```

### Option B: Manual Copy
1. Use WinSCP or similar tool
2. Copy `C:\vault-keytab.keytab` to Linux server
3. Place in `/home/lennart/vault-keytab.keytab`

## Step 2: Convert Keytab to Base64

SSH to Linux server and convert:
```bash
ssh lennart@107.23.32.117
base64 -w 0 /home/lennart/vault-keytab.keytab
```

Copy the base64 output for Vault configuration.

## Step 3: Configure Vault Server

Run these commands on the Linux Vault server:

### Enable gMSA Authentication
```bash
vault auth enable gmsa
```

### Configure gMSA Authentication
```bash
vault write auth/gmsa/config \
    keytab_b64='<BASE64_KEYTAB_HERE>' \
    spn='HTTP/vault.local.lab' \
    realm='LOCAL.LAB' \
    require_cb=false
```

### Create gMSA Role
```bash
vault write auth/gmsa/role/vault-gmsa-role \
    bound_service_account_names='vault-gmsa' \
    bound_service_account_namespaces='LOCAL.LAB' \
    token_policies='vault-gmsa-policy' \
    token_ttl=1h \
    token_max_ttl=24h
```

### Create Policy
```bash
vault policy write vault-gmsa-policy - <<EOF
path "kv/data/my-app/*" {
  capabilities = ["read"]
}
EOF
```

### Enable KV Secrets Engine
```bash
vault secrets enable -path=kv kv-v2
```

### Create Test Secrets
```bash
vault kv put kv/my-app/database username=dbuser password=dbpass123
vault kv put kv/my-app/api api_key=abc123 secret=xyz789
```

## Step 4: DNS Configuration

Ensure DNS resolution:
- `vault.local.lab` should resolve to Linux Vault server IP
- This allows Windows clients to request Kerberos tickets

## Step 5: Test Configuration

### On Linux Vault Server
```bash
# Check authentication methods
vault auth list

# Check gMSA configuration
vault read auth/gmsa/config

# Check role configuration
vault read auth/gmsa/role/vault-gmsa-role
```

### On Windows Client
```powershell
# Run the PowerShell script
.\vault-client-app.ps1
```

## Troubleshooting

### Common Issues

1. **SPN Not Found**
   - Verify SPN is registered: `setspn -L LOCAL\vault-gmsa$`
   - Check DNS resolution: `nslookup vault.local.lab`

2. **Kerberos Ticket Issues**
   - Check ticket cache: `klist`
   - Request new ticket: `kinit HTTP/vault.local.lab`

3. **Vault Authentication Errors**
   - Check Vault logs: `vault audit list`
   - Verify keytab: `klist -kt vault-keytab.keytab`

### Log Locations
- **Windows Client:** `C:\vault-client\config\vault-client.log`
- **Linux Vault:** `/var/log/vault.log`

## Security Considerations

1. **Keytab Security**
   - Store keytab securely on Linux server
   - Use proper file permissions (600)
   - Consider keytab rotation

2. **Network Security**
   - Use TLS for Vault communication
   - Consider channel binding for additional security

3. **Access Control**
   - Limit gMSA permissions
   - Use least privilege principles
   - Regular access reviews

## Success Indicators

✅ **Windows Client:**
- Script runs without errors
- Kerberos tickets obtained
- Vault authentication successful
- Secrets retrieved successfully

✅ **Linux Vault Server:**
- gMSA authentication enabled
- Role and policy configured
- Test secrets accessible
- Audit logs show successful authentication

## Next Steps

1. **Production Deployment**
   - Set up proper monitoring
   - Configure log aggregation
   - Implement backup procedures

2. **Security Hardening**
   - Enable channel binding
   - Implement keytab rotation
   - Set up alerting

3. **Scaling**
   - Add more gMSAs as needed
   - Configure multiple roles
   - Set up high availability
