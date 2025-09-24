# 🔄 Automated Password Rotation for gMSA Auth Plugin

This document describes the automated password rotation feature built into the gMSA auth plugin.

## 🎯 Overview

The automated password rotation feature eliminates the manual overhead of managing gMSA password changes by:

- **Automatically detecting** when gMSA passwords need rotation
- **Generating new keytabs** using current AD credentials
- **Updating Vault configuration** with zero downtime
- **Validating new keytabs** before activation
- **Providing rollback** capabilities if rotation fails
- **Sending notifications** about rotation status

## 🏗️ Architecture

### Components

1. **RotationManager**: Core rotation logic and background processing
2. **RotationConfig**: Configuration for rotation behavior
3. **RotationStatus**: Real-time status tracking
4. **API Endpoints**: Management and monitoring interfaces

### Key Features

- ✅ **Background Processing**: Runs continuously without blocking authentication
- ✅ **AD Integration**: Queries Active Directory for password information
- ✅ **Automatic Detection**: Monitors password age and expiry
- ✅ **Zero Downtime**: Updates configuration without service interruption
- ✅ **Validation**: Tests new keytabs before activation
- ✅ **Rollback**: Automatically reverts on failure
- ✅ **Notifications**: Webhook support for status updates
- ✅ **Monitoring**: Comprehensive status and metrics

## 🚀 Quick Start

### 1. Enable Automated Rotation

```bash
# Configure rotation settings
vault write auth/gmsa/rotation/config \
    enabled=true \
    check_interval=3600 \
    rotation_threshold=86400 \
    domain_controller="dc1.yourdomain.com" \
    domain_admin_user="admin@yourdomain.com" \
    domain_admin_password="secure_password" \
    backup_keytabs=true \
    notification_endpoint="https://your-webhook.com/rotation"
```

### 2. Start Rotation

```bash
# Start the rotation process
vault write auth/gmsa/rotation/start
```

### 3. Monitor Status

```bash
# Check rotation status
vault read auth/gmsa/rotation/status
```

## 📋 Configuration Options

### RotationConfig Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enabled` | bool | false | Enable automatic rotation |
| `check_interval` | int | 3600 | Check frequency (seconds) |
| `rotation_threshold` | int | 86400 | Rotate before expiry (seconds) |
| `max_retries` | int | 3 | Maximum retry attempts |
| `retry_delay` | int | 300 | Delay between retries (seconds) |
| `domain_controller` | string | - | AD domain controller |
| `domain_admin_user` | string | - | Admin user for AD operations |
| `domain_admin_password` | string | - | Admin password (encrypted) |
| `keytab_command` | string | "ktpass" | Command to generate keytab |
| `backup_keytabs` | bool | true | Keep backup keytabs |
| `notification_endpoint` | string | - | Webhook for notifications |

### Example Configuration

```bash
vault write auth/gmsa/rotation/config \
    enabled=true \
    check_interval=1800 \
    rotation_threshold=172800 \
    max_retries=5 \
    retry_delay=600 \
    domain_controller="dc1.yourdomain.com" \
    domain_admin_user="vault-admin@yourdomain.com" \
    domain_admin_password="$(vault kv get -field=password secret/vault-admin)" \
    keytab_command="ktpass" \
    backup_keytabs=true \
    notification_endpoint="https://monitoring.company.com/webhooks/vault-rotation"
```

## 🔧 API Endpoints

### Configuration Management

#### Configure Rotation
```bash
vault write auth/gmsa/rotation/config \
    enabled=true \
    check_interval=3600 \
    rotation_threshold=86400
```

#### Read Configuration
```bash
vault read auth/gmsa/rotation/config
```

#### Delete Configuration
```bash
vault delete auth/gmsa/rotation/config
```

### Process Management

#### Start Rotation
```bash
vault write auth/gmsa/rotation/start
```

#### Stop Rotation
```bash
vault write auth/gmsa/rotation/stop
```

#### Manual Rotation
```bash
vault write auth/gmsa/rotation/rotate
```

### Status Monitoring

#### Get Status
```bash
vault read auth/gmsa/rotation/status
```

**Response:**
```json
{
  "status": "idle",
  "last_check": "2024-01-15T10:30:00Z",
  "last_rotation": "2024-01-10T14:20:00Z",
  "next_rotation": "2024-01-20T14:20:00Z",
  "rotation_count": 3,
  "last_error": "",
  "password_age": 5,
  "password_expiry": "2024-01-20T14:20:00Z",
  "is_running": true
}
```

## 🔄 Rotation Process

### 1. Detection Phase

The rotation manager continuously monitors:

- **Password Age**: Days since last password change
- **Password Expiry**: When password will expire
- **AD Status**: Current password state in Active Directory

### 2. Rotation Phase

When rotation is needed:

1. **Generate New Keytab**: Use `ktpass` with current credentials
2. **Backup Current**: Save current keytab for rollback
3. **Validate New**: Test new keytab parsing and structure
4. **Update Config**: Store new keytab in Vault configuration
5. **Test Authentication**: Verify new keytab works
6. **Cleanup**: Remove temporary files

### 3. Rollback Phase

If rotation fails:

1. **Detect Failure**: Authentication test fails
2. **Restore Backup**: Revert to previous keytab
3. **Log Error**: Record failure details
4. **Send Notification**: Alert administrators
5. **Schedule Retry**: Attempt again after delay

## 📊 Monitoring and Alerting

### Status Values

- **`idle`**: No rotation in progress
- **`checking`**: Checking password status
- **`rotating`**: Performing rotation
- **`error`**: Rotation failed

### Metrics Available

- **Rotation Count**: Total successful rotations
- **Last Rotation**: Timestamp of last rotation
- **Password Age**: Current password age in days
- **Password Expiry**: When password expires
- **Error Count**: Number of failed rotations
- **Uptime**: How long rotation manager has been running

### Webhook Notifications

The plugin can send webhook notifications for:

- **Rotation Started**: When rotation begins
- **Rotation Completed**: When rotation succeeds
- **Rotation Failed**: When rotation fails
- **Status Changes**: When status changes

**Webhook Payload:**
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "message": "Password rotation completed successfully",
  "status": "idle",
  "rotation_count": 3,
  "password_age": 0,
  "password_expiry": "2024-02-14T10:30:00Z"
}
```

## 🛡️ Security Considerations

### Credential Management

- **Domain Admin Password**: Stored encrypted in Vault storage
- **Keytab Backup**: Stored securely with restricted permissions
- **Temporary Files**: Automatically cleaned up after rotation

### Access Control

- **Admin Only**: Rotation configuration requires admin privileges
- **Audit Logging**: All rotation activities are logged
- **Role-Based Access**: Use Vault policies to control access

### Best Practices

1. **Use Dedicated Service Account**: Create specific AD account for rotation
2. **Principle of Least Privilege**: Grant minimal required permissions
3. **Monitor Rotation**: Set up alerts for failed rotations
4. **Test Regularly**: Verify rotation process works in your environment
5. **Backup Strategy**: Keep multiple keytab backups

## 🔧 Troubleshooting

### Common Issues

#### Rotation Fails with "ktpass not found"
```bash
# Install Windows Admin Tools or RSAT
# Ensure ktpass is in PATH
which ktpass
```

#### AD Query Fails
```bash
# Check domain controller connectivity
ping dc1.yourdomain.com

# Verify admin credentials
vault read auth/gmsa/rotation/status
```

#### Keytab Generation Fails
```bash
# Check SPN configuration
setspn -L YOURDOMAIN\vault-agent-gmsa$

# Verify gMSA permissions
Get-ADServiceAccount vault-agent-gmsa
```

### Debug Mode

Enable debug logging to troubleshoot issues:

```bash
# Check Vault logs for rotation activity
vault audit enable file file_path=/var/log/vault-rotation.log

# Monitor rotation status
watch -n 30 'vault read auth/gmsa/rotation/status'
```

### Manual Recovery

If automated rotation fails completely:

```bash
# Stop automated rotation
vault write auth/gmsa/rotation/stop

# Perform manual rotation
vault write auth/gmsa/rotation/rotate

# Or update configuration manually
vault write auth/gmsa/config keytab="$(cat new-keytab.b64)"
```

## 📈 Performance Impact

### Resource Usage

- **CPU**: Minimal impact during checks, moderate during rotation
- **Memory**: Small overhead for background process
- **Network**: Periodic AD queries, keytab generation
- **Storage**: Temporary files during rotation

### Optimization

- **Check Interval**: Balance between responsiveness and resource usage
- **Retry Logic**: Configure appropriate retry delays
- **Backup Cleanup**: Regularly clean old backup keytabs
- **Monitoring**: Use health endpoints to track performance

## 🎯 Production Recommendations

### Environment Setup

1. **Dedicated Service Account**: Create `vault-rotation-admin` account
2. **Minimal Permissions**: Grant only required AD permissions
3. **Network Access**: Ensure Vault can reach domain controllers
4. **Monitoring**: Set up comprehensive monitoring and alerting

### Operational Procedures

1. **Regular Testing**: Test rotation process monthly
2. **Backup Verification**: Verify backup keytabs are valid
3. **Documentation**: Document rotation procedures and contacts
4. **Incident Response**: Have manual rotation procedures ready

### Scaling Considerations

- **Multiple Domains**: Configure separate rotation for each domain
- **High Availability**: Run rotation on multiple Vault instances
- **Load Balancing**: Distribute rotation load across instances
- **Monitoring**: Centralize rotation monitoring and alerting

## 🔮 Future Enhancements

### Planned Features

- **Multi-Domain Support**: Rotate keytabs for multiple domains
- **Advanced Scheduling**: More sophisticated rotation timing
- **Integration**: Better integration with monitoring systems
- **Automation**: More automated recovery procedures

### Community Contributions

We welcome contributions for:

- **Additional AD Integration**: Support for other AD tools
- **Enhanced Monitoring**: More detailed metrics and alerts
- **Cloud Integration**: Support for cloud-based AD services
- **Documentation**: Improvements to this guide

---

**The automated password rotation feature makes gMSA management truly hands-off while maintaining security and reliability.** 🚀
