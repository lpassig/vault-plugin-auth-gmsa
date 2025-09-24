# 🌐 Cross-Platform Support for gMSA Auth Plugin

This document explains how the gMSA auth plugin works across different platforms, particularly focusing on Linux Vault deployments with gMSA authentication.

## 🎯 Platform Support Overview

The gMSA auth plugin supports **both Windows and Linux** Vault deployments:

| Platform | Vault Server | Authentication | Rotation | Status |
|----------|--------------|---------------|----------|---------|
| **Windows** | ✅ Supported | ✅ Native gMSA | ✅ PowerShell + ktpass | **Full Support** |
| **Linux** | ✅ Supported | ✅ SPNEGO Tokens | ✅ LDAP + ktutil | **Full Support** |

## 🏗️ Architecture Differences

### **Windows Deployment**
- **Vault Server**: Windows Server
- **Authentication**: Native Windows Kerberos
- **Rotation**: PowerShell + ktpass
- **AD Integration**: Direct Windows APIs

### **Linux Deployment**
- **Vault Server**: Linux (Ubuntu, RHEL, etc.)
- **Authentication**: SPNEGO token validation
- **Rotation**: LDAP + ktutil
- **AD Integration**: LDAP queries

## 🔧 Linux Vault Deployment

### **How It Works**

Even when Vault runs on Linux, the plugin can authenticate Windows clients using gMSA:

1. **Windows Client**: Uses native Kerberos to get SPNEGO token
2. **Linux Vault**: Validates SPNEGO token using keytab
3. **Cross-Platform**: No Windows dependencies on Vault server

### **Key Components**

#### **1. SPNEGO Token Validation**
```go
// Linux Vault validates SPNEGO tokens from Windows clients
func (v *Validator) ValidateSPNEGO(ctx context.Context, spnegoB64, channelBind string) (*ValidationResult, safeErr) {
    // Parse and validate SPNEGO token using keytab
    // This works identically on Linux and Windows
}
```

#### **2. Keytab Management**
```go
// Keytab parsing works the same on both platforms
kt := &keytab.Keytab{}
if err := kt.Unmarshal(keytabBytes); err != nil {
    return nil, fail(err, "failed to parse keytab")
}
```

#### **3. Platform-Specific Rotation**
```go
// Automatic platform detection
if runtime.GOOS == "windows" {
    b.rotationManager = NewRotationManager(b, &config)      // Windows
} else {
    b.rotationManager = NewLinuxRotationManager(b, &config) // Linux
}
```

## 🚀 Linux Setup Guide

### **Prerequisites**

#### **1. Linux Vault Server Requirements**
```bash
# Install Kerberos utilities
sudo apt-get install krb5-user krb5-config

# Install LDAP utilities
sudo apt-get install ldap-utils

# Configure krb5.conf
sudo nano /etc/krb5.conf
```

#### **2. krb5.conf Configuration**
```ini
[libdefaults]
    default_realm = YOURDOMAIN.COM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
YOURDOMAIN.COM = {
    kdc = dc1.yourdomain.com
    kdc = dc2.yourdomain.com
    admin_server = dc1.yourdomain.com
}

[domain_realm]
.yourdomain.com = YOURDOMAIN.COM
yourdomain.com = YOURDOMAIN.COM
```

### **3. gMSA Setup (Windows)**

The gMSA must still be created on Windows Active Directory:

```powershell
# Create gMSA (run on Windows domain controller)
New-ADServiceAccount -Name "vault-linux-gmsa" -DNSHostName "vault-linux-gmsa.yourdomain.com" -ServicePrincipalNames "HTTP/vault-linux.yourdomain.com"

# Add SPN for Linux Vault server
setspn -A HTTP/vault-linux.yourdomain.com YOURDOMAIN\vault-linux-gmsa$

# Grant permissions
Add-ADServiceAccount -Identity "vault-linux-gmsa" -PrincipalsAllowedToRetrieveManagedPassword "YOURDOMAIN\vault-linux-gmsa$"
```

### **4. Keytab Generation (Windows)**

Generate keytab on Windows domain controller:

```powershell
# Generate keytab for Linux Vault
ktpass -princ HTTP/vault-linux.yourdomain.com@YOURDOMAIN.COM -mapuser YOURDOMAIN\vault-linux-gmsa$ -crypto AES256-SHA1 -ptype KRB5_NT_PRINCIPAL -pass * -out vault-linux.keytab

# Convert to base64
$keytabB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("vault-linux.keytab"))
```

### **5. Linux Vault Configuration**

```bash
# Configure gMSA auth method
vault write auth/gmsa/config \
    realm="YOURDOMAIN.COM" \
    kdcs="dc1.yourdomain.com,dc2.yourdomain.com" \
    spn="HTTP/vault-linux.yourdomain.com" \
    keytab="$keytabB64" \
    allow_channel_binding=true \
    clock_skew_sec=300
```

## 🔄 Automated Rotation on Linux

### **Linux-Specific Rotation**

The Linux rotation manager uses different tools:

#### **1. LDAP Queries**
```bash
# Query AD for password information
ldapsearch -H ldap://dc1.yourdomain.com \
    -D "admin@yourdomain.com" \
    -w "password" \
    -b "CN=vault-linux-gmsa,CN=Managed Service Accounts,CN=Users,DC=yourdomain,DC=com" \
    -s base "(objectClass=msDS-GroupManagedServiceAccount)" \
    pwdLastSet msDS-ManagedPasswordId
```

#### **2. ktutil for Keytab Generation**
```bash
# Generate keytab using ktutil
ktutil << EOF
addent -password -p HTTP/vault-linux.yourdomain.com@YOURDOMAIN.COM -k 1 -e aes256-cts-hmac-sha1-96
wkt /tmp/new-keytab.keytab
q
EOF
```

### **Configuration**

```bash
# Configure Linux rotation
vault write auth/gmsa/rotation/config \
    enabled=true \
    check_interval=3600 \
    rotation_threshold=86400 \
    domain_controller="dc1.yourdomain.com" \
    domain_admin_user="admin@yourdomain.com" \
    domain_admin_password="secure_password" \
    keytab_command="ktutil" \
    backup_keytabs=true
```

## 🧪 Testing Cross-Platform Setup

### **1. Test Authentication**

From Windows client:
```powershell
# Test authentication to Linux Vault
$spnegoToken = [System.Convert]::ToBase64String($spnegoBytes)
Invoke-RestMethod -Method POST -Uri "https://vault-linux.yourdomain.com/v1/auth/gmsa/login" -Body (@{ spnego=$spnegoToken } | ConvertTo-Json)
```

### **2. Test Rotation**

```bash
# Check rotation status on Linux Vault
vault read auth/gmsa/rotation/status

# Trigger manual rotation
vault write auth/gmsa/rotation/rotate
```

### **3. Verify Cross-Platform**

```bash
# Check platform detection
vault read auth/gmsa/health

# Should show Linux rotation manager
vault read auth/gmsa/rotation/status
```

## 🔍 Troubleshooting

### **Common Linux Issues**

#### **1. Kerberos Configuration**
```bash
# Test Kerberos connectivity
kinit admin@YOURDOMAIN.COM

# Check ticket
klist

# Test KDC connectivity
telnet dc1.yourdomain.com 88
```

#### **2. LDAP Connectivity**
```bash
# Test LDAP connection
ldapsearch -H ldap://dc1.yourdomain.com -D "admin@yourdomain.com" -w "password" -b "DC=yourdomain,DC=com" -s base "(objectClass=*)"

# Check gMSA account
ldapsearch -H ldap://dc1.yourdomain.com -D "admin@yourdomain.com" -w "password" -b "CN=vault-linux-gmsa,CN=Managed Service Accounts,CN=Users,DC=yourdomain,DC=com" -s base "(objectClass=*)"
```

#### **3. Keytab Issues**
```bash
# Test keytab parsing
ktutil -k /path/to/keytab -l

# Verify keytab contents
ktutil -k /path/to/keytab -t
```

### **Debug Mode**

```bash
# Enable debug logging
export VAULT_LOG_LEVEL=debug

# Check plugin logs
vault read auth/gmsa/health

# Monitor rotation
watch -n 30 'vault read auth/gmsa/rotation/status'
```

## 📊 Performance Considerations

### **Linux vs Windows Performance**

| Aspect | Linux | Windows | Notes |
|--------|-------|---------|-------|
| **Authentication** | ✅ Fast | ✅ Fast | SPNEGO validation identical |
| **Rotation** | ⚠️ Slower | ✅ Fast | LDAP queries vs native APIs |
| **Memory Usage** | ✅ Lower | ⚠️ Higher | Linux more efficient |
| **Network** | ✅ Efficient | ✅ Efficient | Same protocols |

### **Optimization Tips**

1. **LDAP Caching**: Cache LDAP queries to reduce AD load
2. **Connection Pooling**: Reuse LDAP connections
3. **Async Processing**: Use background goroutines for rotation
4. **Health Monitoring**: Monitor rotation performance

## 🛡️ Security Considerations

### **Cross-Platform Security**

#### **1. Network Security**
- **mTLS**: Use mutual TLS between clients and Vault
- **Firewall**: Restrict access to Vault ports
- **VPN**: Use VPN for cross-platform communication

#### **2. Credential Management**
- **Encrypted Storage**: Domain admin passwords encrypted in Vault
- **Minimal Permissions**: Use dedicated service accounts
- **Rotation**: Regular credential rotation

#### **3. Audit Logging**
- **Cross-Platform**: Same audit trail regardless of platform
- **Compliance**: Meets enterprise security requirements
- **Monitoring**: Real-time security monitoring

## 🎯 Best Practices

### **Linux Deployment**

1. **Use Dedicated Service Account**: Create specific account for Linux Vault
2. **Network Segmentation**: Isolate Vault network from AD network
3. **Regular Testing**: Test authentication and rotation regularly
4. **Monitoring**: Set up comprehensive monitoring
5. **Documentation**: Document cross-platform procedures

### **Hybrid Environments**

1. **Consistent Configuration**: Use same auth method across platforms
2. **Centralized Management**: Manage all Vault instances centrally
3. **Unified Monitoring**: Monitor all platforms together
4. **Disaster Recovery**: Plan for cross-platform failover

## 🔮 Future Enhancements

### **Planned Features**

- **Cloud Integration**: Support for Azure AD, AWS Directory Service
- **Container Support**: Better Docker/Kubernetes integration
- **Advanced Monitoring**: Cross-platform metrics and alerting
- **Automated Testing**: Cross-platform test automation

### **Community Contributions**

We welcome contributions for:

- **Additional Platforms**: Support for other Unix variants
- **Cloud Providers**: Integration with cloud directory services
- **Container Platforms**: Better container orchestration support
- **Monitoring**: Enhanced cross-platform monitoring

---

**The gMSA auth plugin provides full cross-platform support, enabling Linux Vault deployments while maintaining Windows gMSA authentication capabilities.** 🚀
