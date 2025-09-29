# Vault gMSA Authentication Setup Requirements

## Overview

This document outlines the complete setup requirements for implementing Windows Client → Linux Vault gMSA authentication using the vault-plugin-auth-gmsa.

## Prerequisites

### 1. **Active Directory Environment**
- Windows Server with Active Directory Domain Services (AD DS)
- Domain Controller with PowerShell and AD management tools
- Domain-joined Windows clients
- Network connectivity between clients and Vault server

### 2. **Vault Server**
- Linux server (Ubuntu, CentOS, RHEL, etc.)
- Vault binary installed and configured
- Network access to Active Directory domain
- Plugin binary deployed

### 3. **Windows Clients**
- Windows Server 2012 R2+ or Windows 10/11
- Domain-joined to the same AD domain
- PowerShell 5.0+
- RSAT Active Directory PowerShell module

## Step-by-Step Setup

### **Phase 1: Active Directory Configuration**

#### 1.1 Create KDS Root Key
```powershell
# Check if KDS root key exists
Get-KdsRootKey

# Create KDS root key (run on domain controller)
# For lab/testing (immediate effect):
Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))

# For production (10-hour delay):
Add-KdsRootKey -EffectiveImmediately
```

#### 1.2 Create gMSA Account
```powershell
# Create gMSA for client authentication
New-ADServiceAccount -Name "vault-gmsa" -DNSHostName "vault-gmsa.local.lab" -ServicePrincipalNames "HTTP/vault.local.lab"

# Verify SPN was created
setspn -L LOCAL\vault-gmsa$
```

#### 1.3 Create AD Groups
```powershell
# Create group for Vault servers
New-ADGroup -Name "Vault-Servers" -SamAccountName "Vault-Servers" -GroupCategory Security -GroupScope Global

# Create group for Vault clients  
New-ADGroup -Name "Vault-Clients" -SamAccountName "Vault-Clients" -GroupCategory Security -GroupScope Global

# Add computer accounts to groups
Add-ADGroupMember -Identity "Vault-Servers" -Members "VAULT-SERVER$"
Add-ADGroupMember -Identity "Vault-Clients" -Members "CLIENT-COMPUTER$"
```

#### 1.4 Grant gMSA Permissions
```powershell
# Grant clients permission to retrieve gMSA password
Set-ADServiceAccount -Identity "vault-gmsa" -PrincipalsAllowedToRetrieveManagedPassword "Vault-Clients"

# Verify configuration
Get-ADServiceAccount vault-gmsa -Properties PrincipalsAllowedToRetrieveManagedPassword
```

#### 1.5 Create Service Account for Keytab
```powershell
# Create regular service account for Vault server keytab
New-ADUser -Name "vault-keytab-svc" -UserPrincipalName "vault-keytab-svc@local.lab" -AccountPassword (ConvertTo-SecureString "TempPassword123!" -AsPlainText -Force) -Enabled $true -PasswordNeverExpires $true

# Add SPN for the service account
setspn -A HTTP/vault.local.lab LOCAL\vault-keytab-svc

# Generate keytab
ktpass -princ HTTP/vault.local.lab@local.lab -mapuser LOCAL\vault-keytab-svc -crypto AES256-SHA1 -ptype KRB5_NT_PRINCIPAL -pass TempPassword123! -out vault-keytab.keytab

# Convert to base64 for Vault configuration
[Convert]::ToBase64String([IO.File]::ReadAllBytes("vault-keytab.keytab"))
```

### **Phase 2: Vault Server Configuration**

#### 2.1 Deploy Plugin
```bash
# Build the plugin
make build

# Copy plugin to Vault plugins directory
sudo cp bin/vault-plugin-auth-gmsa /usr/local/bin/

# Set permissions
sudo chmod +x /usr/local/bin/vault-plugin-auth-gmsa
```

#### 2.2 Configure Vault
```bash
# Enable the gMSA auth method
vault auth enable -path=gmsa vault-plugin-auth-gmsa

# Configure the auth method
vault write auth/gmsa/config \
    realm="LOCAL.LAB" \
    kdcs="dc1.local.lab" \
    spn="HTTP/vault.local.lab" \
    keytab="<base64-keytab-content>" \
    clock_skew_sec=300 \
    allow_channel_binding=true
```

#### 2.3 Create Policies and Roles
```bash
# Create policy for secrets
vault policy write vault-agent-policy - <<EOF
path "secret/data/my-app/*" {
  capabilities = ["read"]
}
EOF

# Create role for gMSA
vault write auth/gmsa/role/vault-gmsa-role \
    name="vault-gmsa-role" \
    allowed_realms="LOCAL.LAB" \
    allowed_spns="HTTP/vault.local.lab" \
    bound_group_sids="S-1-5-21-1234567890-1234567890-1234567890-1234" \
    token_policies="vault-agent-policy" \
    token_type="service" \
    period=3600 \
    max_ttl=7200
```

#### 2.4 Store Secrets
```bash
# Store application secrets
vault kv put secret/my-app/database \
    host="db-server.local.lab" \
    username="app-user" \
    password="secure-password"

vault kv put secret/my-app/api \
    api_key="your-api-key" \
    endpoint="https://api.local.lab"
```

### **Phase 3: Windows Client Configuration**

#### 3.1 Install Prerequisites
```powershell
# Install RSAT Active Directory PowerShell module
# On Windows Server:
Install-WindowsFeature RSAT-AD-PowerShell

# On Windows 10/11:
Add-WindowsCapability -Online -Name RSAT:ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0

# Verify installation
Get-Module -ListAvailable | Where-Object Name -eq ActiveDirectory
```

#### 3.2 Install gMSA on Client
```powershell
# Install the gMSA on the client machine
Install-ADServiceAccount -Identity "vault-gmsa"

# Test gMSA availability
Test-ADServiceAccount -Identity "vault-gmsa"
# Should return True
```

#### 3.3 Deploy Client Application
```powershell
# Copy vault-client-app.ps1 to client
# Run setup script
.\setup-vault-client.ps1 -VaultUrl "https://vault.local.lab:8200" -VaultRole "vault-gmsa-role"

# Or create scheduled task manually
Register-ScheduledTask -TaskName "VaultClientApp" -Action $action -User "local.lab\vault-gmsa$" -RunLevel Highest
```

## Configuration Files

### **Vault Server Configuration (vault.hcl)**
```hcl
ui = true
disable_mlock = true

storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = false
  tls_cert_file = "/opt/vault/tls/vault.crt"
  tls_key_file  = "/opt/vault/tls/vault.key"
}

plugin_directory = "/usr/local/bin"

api_addr = "https://vault.local.lab:8200"
cluster_addr = "https://vault.local.lab:8201"
```

### **Client Configuration (config.json)**
```json
{
  "vault_url": "https://vault.local.lab:8200",
  "vault_role": "vault-gmsa-role",
  "spn": "HTTP/vault.local.lab",
  "secret_paths": [
    "secret/data/my-app/database",
    "secret/data/my-app/api"
  ],
  "output_dir": "C:\\vault-client\\config",
  "log_level": "INFO"
}
```

## Network Requirements

### **Ports and Protocols**
- **8200/TCP**: Vault API (HTTPS)
- **88/TCP,UDP**: Kerberos authentication
- **389/TCP**: LDAP (for AD queries)
- **636/TCP**: LDAPS (for secure AD queries)
- **53/TCP,UDP**: DNS (for domain resolution)

### **Firewall Rules**
```bash
# Vault server firewall
sudo ufw allow 8200/tcp
sudo ufw allow 88/tcp
sudo ufw allow 88/udp

# Windows client firewall
New-NetFirewallRule -DisplayName "Vault HTTPS" -Direction Inbound -Protocol TCP -LocalPort 8200 -Action Allow
```

## Security Considerations

### **gMSA Security**
- gMSA passwords are automatically managed by AD
- Passwords rotate every 30 days by default
- Only authorized principals can retrieve passwords
- No password storage on clients

### **Network Security**
- Use TLS for all Vault communications
- Enable channel binding for additional security
- Restrict network access to Vault server
- Use firewall rules to limit access

### **Keytab Security**
- Store keytab files securely
- Use base64 encoding for Vault configuration
- Rotate keytabs regularly
- Monitor for unauthorized access

## Troubleshooting

### **Common Issues**

#### 1. gMSA Installation Fails
```powershell
# Check domain connectivity
Test-NetConnection -ComputerName "dc1.local.lab" -Port 389

# Check group membership
Get-ADGroupMember "Vault-Clients"

# Check gMSA permissions
Get-ADServiceAccount vault-gmsa -Properties PrincipalsAllowedToRetrieveManagedPassword
```

#### 2. Kerberos Authentication Fails
```powershell
# Check Kerberos tickets
klist

# Check SPN configuration
setspn -L LOCAL\vault-gmsa$
setspn -L LOCAL\vault-keytab-svc

# Test Kerberos authentication
kinit -k HTTP/vault.local.lab@LOCAL.LAB
```

#### 3. Vault Plugin Issues
```bash
# Check plugin registration
vault auth list

# Check plugin configuration
vault read auth/gmsa/config

# Check Vault logs
sudo journalctl -u vault -f
```

## Validation

### **Test Authentication Flow**
```powershell
# Run validation script
.\validate-gmsa-flow.ps1 -VaultUrl "https://vault.local.lab:8200"

# Run scenario test
.\test-gmsa-scenario.ps1 -VaultUrl "https://vault.local.lab:8200" -DryRun
```

### **Verify Secrets Access**
```powershell
# Test secret retrieval
.\vault-client-app.ps1 -VaultUrl "https://vault.local.lab:8200" -VaultRole "vault-gmsa-role"
```

## Maintenance

### **Regular Tasks**
- Monitor gMSA password rotation
- Update Vault policies as needed
- Review audit logs
- Test authentication flow
- Update plugin versions

### **Monitoring**
- Vault authentication metrics
- gMSA password expiry
- Network connectivity
- Plugin health status

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review Vault and Windows event logs
3. Test with validation scripts
4. Consult the main README.md for detailed examples
