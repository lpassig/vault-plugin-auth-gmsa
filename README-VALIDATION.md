# gMSA Authentication Flow Validation

This document describes how to validate the complete Windows Client → Linux Vault gMSA authentication scenario.

## Scenario Overview

**Windows Client** (running under gMSA identity) → **Linux Vault Server** (with gMSA plugin)

### Authentication Flow

1. **Windows Client** runs under gMSA identity (`LOCAL\vault-gmsa$`)
2. **SPNEGO Token Generation** using Windows SSPI/Kerberos
3. **Vault Authentication** via gMSA plugin on Linux Vault
4. **Secret Retrieval** from Vault using authenticated token
5. **Alternative NTLM Hash** authentication for enhanced compatibility

## Validation Scripts

### 1. `validate-gmsa-flow.ps1`

Comprehensive validation script that tests all components:

```powershell
# Basic validation
.\validate-gmsa-flow.ps1

# Verbose validation with detailed output
.\validate-gmsa-flow.ps1 -Verbose

# Custom Vault URL
.\validate-gmsa-flow.ps1 -VaultUrl "https://vault.company.com:8200"
```

**Tests:**
- Environment validation (gMSA identity, PowerShell version, AD module)
- SPNEGO token generation methods
- gMSA credential retrieval and NTLM hash calculation
- Vault connectivity and health checks
- Authentication function availability
- Secret retrieval function availability

### 2. `test-gmsa-scenario.ps1`

End-to-end scenario test that simulates the complete authentication flow:

```powershell
# Dry run (no actual Vault calls)
.\test-gmsa-scenario.ps1 -DryRun

# Full test with actual Vault authentication
.\test-gmsa-scenario.ps1

# Custom parameters
.\test-gmsa-scenario.ps1 -VaultUrl "https://vault.company.com:8200" -VaultRole "my-gmsa-role"
```

**Steps:**
1. **Environment Setup** - Verify gMSA identity
2. **SPNEGO Token Generation** - Generate authentication token
3. **Vault Authentication** - Authenticate to Linux Vault
4. **Secret Retrieval** - Retrieve secrets from Vault
5. **gMSA NTLM Hash Authentication** - Test alternative authentication method

## Prerequisites

### Windows Client Requirements

1. **gMSA Identity**: Script must run under gMSA identity (`*vault-gmsa$`)
2. **PowerShell 5.0+**: Required for advanced features
3. **Active Directory Module**: For gMSA credential retrieval
4. **Kerberos Tickets**: Valid tickets for target SPN
5. **Network Access**: Connectivity to Linux Vault server

### Linux Vault Server Requirements

1. **gMSA Plugin**: Vault plugin for gMSA authentication installed
2. **gMSA Auth Method**: Enabled and configured
3. **SPN Configuration**: Proper Service Principal Name setup
4. **Role Configuration**: gMSA role with appropriate policies

## Validation Results

### Expected Output

```
[2025-09-26 10:30:00] [SUCCESS] ✓ Running under gMSA identity
[2025-09-26 10:30:01] [SUCCESS] ✓ SPNEGO token generated successfully
[2025-09-26 10:30:02] [SUCCESS] ✓ Vault authentication successful
[2025-09-26 10:30:03] [SUCCESS] ✓ Secret retrieval successful
[2025-09-26 10:30:04] [SUCCESS] ✓ All scenario steps passed!
```

### Common Issues

#### 1. gMSA Identity Issues
```
[ERROR] ✗ Not running under gMSA identity
```
**Solution**: Run script under gMSA identity or use scheduled task

#### 2. SPNEGO Token Generation Failures
```
[ERROR] ✗ Failed to generate SPNEGO token
```
**Solutions**:
- Check Kerberos tickets: `klist`
- Verify SPN configuration
- Check network connectivity to Vault

#### 3. Vault Authentication Failures
```
[ERROR] ✗ Vault authentication failed
```
**Solutions**:
- Verify Vault URL and port
- Check gMSA plugin installation
- Verify role configuration
- Check Vault logs

#### 4. NTLM Hash Authentication
```
[WARNING] ⚠ NTLM hash authentication failed (expected - requires Vault enhancement)
```
**Note**: This is expected until Vault LDAP auth method supports NTLM hash authentication

## Troubleshooting

### 1. Check gMSA Identity
```powershell
[System.Security.Principal.WindowsIdentity]::GetCurrent().Name
```

### 2. Check Kerberos Tickets
```powershell
klist
klist get HTTP/vault.example.com
```

### 3. Test Vault Connectivity
```powershell
Invoke-RestMethod -Uri "https://vault.example.com:8200/v1/sys/health" -Method GET
```

### 4. Check gMSA Plugin
```powershell
# On Vault server
vault auth list
vault auth -methods
```

### 5. Verify Role Configuration
```powershell
# On Vault server
vault read auth/gmsa/role/vault-gmsa-role
```

## Advanced Validation

### 1. Network Connectivity
```powershell
Test-NetConnection -ComputerName "vault.example.com" -Port 8200
```

### 2. DNS Resolution
```powershell
Resolve-DnsName "vault.example.com"
```

### 3. Certificate Validation
```powershell
$cert = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
```

### 4. Firewall Rules
```powershell
Get-NetFirewallRule -DisplayName "*Vault*"
```

## Performance Testing

### 1. Authentication Latency
```powershell
Measure-Command { .\test-gmsa-scenario.ps1 }
```

### 2. Token Generation Speed
```powershell
Measure-Command { Get-SPNEGOToken -TargetSPN "HTTP/vault.example.com" }
```

### 3. Secret Retrieval Performance
```powershell
Measure-Command { Get-VaultSecret -VaultUrl $VaultUrl -VaultToken $Token -SecretPath "kv/data/test" }
```

## Security Considerations

1. **gMSA Permissions**: Ensure gMSA has minimal required permissions
2. **Network Security**: Use TLS/SSL for all Vault communications
3. **Token Security**: Secure storage and transmission of Vault tokens
4. **Logging**: Monitor authentication attempts and failures
5. **Rotation**: Regular rotation of gMSA passwords and Vault tokens

## Support and Maintenance

### Regular Validation
- Run validation scripts weekly
- Monitor authentication success rates
- Check for gMSA password rotation issues
- Verify Vault plugin updates

### Monitoring
- Set up alerts for authentication failures
- Monitor Vault server health
- Track gMSA credential expiration
- Log authentication performance metrics

### Updates
- Keep Vault plugin updated
- Monitor for Windows updates affecting gMSA
- Update PowerShell scripts as needed
- Review and update security configurations
