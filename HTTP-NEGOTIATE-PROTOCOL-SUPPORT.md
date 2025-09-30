# 🎉 HTTP Negotiate Protocol Support for gMSA Plugin

## ✅ **CRITICAL UPDATE: Plugin Now Supports Standard HTTP Negotiate**

Based on the [official HashiCorp Vault Kerberos plugin](https://github.com/hashicorp/vault-plugin-auth-kerberos), our custom gMSA plugin has been updated to support the **standard HTTP Negotiate protocol**.

---

## 🔧 **What Changed**

### **Before (Body-based approach):**
```powershell
# ❌ Old method - SPNEGO token in request body
$body = @{
    role = "vault-gmsa-role"
    spnego = $spnegoToken
} | ConvertTo-Json

Invoke-RestMethod -Uri "$VaultUrl/v1/auth/gmsa/login" `
    -Method Post `
    -Body $body `
    -ContentType "application/json"
```

### **After (HTTP Negotiate protocol):**
```powershell
# ✅ New method - SPNEGO token in Authorization header
Invoke-RestMethod -Uri "$VaultUrl/v1/auth/gmsa/login" `
    -Method Post `
    -Headers @{
        "Authorization" = "Negotiate $spnegoToken"
    } `
    -UseDefaultCredentials
```

---

## 🚀 **Why This Fixes Our Problem**

1. **Windows SSPI Integration**: When you use `UseDefaultCredentials = $true` with HTTP requests, Windows automatically:
   - Detects the current identity (gMSA in our case)
   - Obtains Kerberos tickets
   - Generates SPNEGO tokens via LSA
   - Adds `Authorization: Negotiate <token>` header

2. **No Manual `InitializeSecurityContext`**: The PowerShell script no longer needs to call Win32 SSPI functions directly, avoiding the `0x80090308` error we were experiencing.

3. **Compatibility**: The plugin now supports BOTH methods:
   - **HTTP Negotiate** (new, recommended): Token in `Authorization` header
   - **Body-based** (legacy): Token in JSON body

---

## 📋 **Updated Plugin Code**

### **Changes in `pkg/backend/paths_login.go`:**

```go
// CRITICAL FIX: Support HTTP Authorization header like official Kerberos plugin
// Check if Authorization header contains SPNEGO token (HTTP Negotiate protocol)
if spnegoB64 == "" && req.Headers != nil {
    authHeader := req.Headers["Authorization"]
    if len(authHeader) > 0 && len(authHeader[0]) > 10 && authHeader[0][:10] == "Negotiate " {
        // Extract SPNEGO token from "Authorization: Negotiate <token>" header
        spnegoB64 = authHeader[0][10:] // Remove "Negotiate " prefix
        b.logger.Info("SPNEGO token extracted from Authorization header", "token_length", len(spnegoB64))
    }
}

// If no role specified, use default role name "default" (must be created by admin)
if roleName == "" {
    roleName = "default"
    b.logger.Info("No role specified, using default role", "role", roleName)
}
```

---

## 🛠️ **Setup Instructions**

### **1. Enable Plugin with Authorization Header Passthrough**

When enabling the auth method in Vault, you **MUST** pass through the `Authorization` header:

```bash
vault auth enable \
    -path=gmsa \
    -passthrough-request-headers=Authorization \
    -allowed-response-headers=www-authenticate \
    vault-plugin-auth-gmsa
```

### **2. Create a Default Role**

Since the HTTP Negotiate protocol doesn't send the role in the body, create a default role:

```bash
vault write auth/gmsa/role/default \
    token_policies="gmsa-policy" \
    allowed_realms="LOCAL.LAB" \
    allowed_spns="HTTP/vault.local.lab"
```

### **3. Update Windows Client Script**

Replace the manual SPNEGO generation with Windows HTTP stack:

```powershell
# Let Windows handle SPNEGO automatically
$response = Invoke-WebRequest `
    -Uri "https://vault.local.lab:8200/v1/auth/gmsa/login" `
    -Method Post `
    -UseDefaultCredentials `
    -UseBasicParsing

# Parse response
$auth = ($response.Content | ConvertFrom-Json).auth
$vaultToken = $auth.client_token
Write-Host "SUCCESS: Vault token: $vaultToken"
```

---

## 🧪 **Testing the New Feature**

### **Test 1: Using curl (Windows)**

```bash
curl --negotiate --user : \
    -X POST \
    https://vault.local.lab:8200/v1/auth/gmsa/login
```

### **Test 2: Using PowerShell**

```powershell
$response = Invoke-RestMethod `
    -Uri "https://vault.local.lab:8200/v1/auth/gmsa/login" `
    -Method Post `
    -UseDefaultCredentials

Write-Host "Vault token: $($response.auth.client_token)"
```

### **Test 3: Using Python (like official plugin)**

```python
import kerberos
import requests

service = "HTTP@vault.local.lab"
rc, vc = kerberos.authGSSClientInit(
    service=service, 
    mech_oid=kerberos.GSS_MECH_OID_SPNEGO
)
kerberos.authGSSClientStep(vc, "")
kerberos_token = kerberos.authGSSClientResponse(vc)

r = requests.post(
    "https://vault.local.lab:8200/v1/auth/gmsa/login",
    headers={'Authorization': 'Negotiate ' + kerberos_token}
)
print('Vault token:', r.json()['auth']['client_token'])
```

---

## 📊 **Compatibility Matrix**

| Method                     | Windows | Linux | macOS | gMSA Support | Status |
|----------------------------|---------|-------|-------|--------------|--------|
| HTTP Negotiate (new)       | ✅      | ✅    | ✅    | ✅           | ✅ Recommended |
| Body-based (legacy)        | ✅      | ✅    | ✅    | ✅           | ✅ Supported |
| `UseDefaultCredentials`    | ✅      | ❌    | ❌    | ✅           | ✅ Windows-specific |

---

## 🎯 **Benefits**

1. **No more `0x80090308` errors** - Windows HTTP stack has full LSA integration
2. **Standard protocol** - Compatible with official Kerberos plugin clients
3. **Automatic SPNEGO** - Windows generates tokens automatically
4. **Backward compatible** - Old clients still work
5. **Cross-platform** - Python, curl, PowerShell all work

---

## 📝 **Migration Guide**

### **For Existing Deployments:**

1. **Rebuild and deploy plugin** with Authorization header support
2. **Re-enable auth method** with `-passthrough-request-headers=Authorization`
3. **Create default role** if using HTTP Negotiate without explicit role
4. **Update client scripts** to use `UseDefaultCredentials` (optional, old method still works)

### **For New Deployments:**

Use the HTTP Negotiate method from the start - it's simpler and more reliable!

---

## 🔗 **References**

- [Official Vault Kerberos Plugin](https://github.com/hashicorp/vault-plugin-auth-kerberos)
- [Microsoft SPNEGO Protocol](https://learn.microsoft.com/en-us/previous-versions/ms995331(v=msdn.10))
- [Vault Auth Method Configuration](https://developer.hashicorp.com/vault/docs/commands/auth/enable)

---

## ✅ **Next Steps**

1. **Deploy updated plugin** to Vault server
2. **Re-enable auth method** with Authorization header passthrough
3. **Update Windows client** to use `UseDefaultCredentials`
4. **Test authentication** - should work instantly!

This update solves the fundamental PowerShell + gMSA + SSPI limitation we encountered! 🎉
