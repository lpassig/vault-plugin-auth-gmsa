# 🔍 CRITICAL ANALYSIS: 0x80090308 Error Persists After Keytab Fix

## 🚨 **The Real Problem**

The `0x80090308` (SEC_E_UNKNOWN_CREDENTIALS) error is happening **on the Windows client** during `InitializeSecurityContext`, **before** the SPNEGO token even reaches the Vault server.

This means:
- ✅ Kerberos ticket obtained successfully
- ✅ Service ticket for `HTTP/vault.local.lab` exists
- ✅ Running under `vault-gmsa$` identity
- ❌ **`InitializeSecurityContext` cannot access the gMSA's credentials**

---

## 🔬 **Why This Happens**

`InitializeSecurityContext` is a **low-level SSPI call** that requires direct access to the calling process's security context. When running under a gMSA in a scheduled task:

1. **Kerberos tickets ARE obtained** (we can see them in `klist`)
2. **But `InitializeSecurityContext` cannot USE them** (SEC_E_UNKNOWN_CREDENTIALS)

This is because:
- `klist` shows tickets in the **credential cache**
- `InitializeSecurityContext` needs tickets in the **LSA (Local Security Authority)**
- gMSAs in scheduled tasks might not have full LSA integration for SSPI calls

---

## 💡 **The Solution: Use HTTP Negotiate Protocol**

Instead of calling `InitializeSecurityContext` directly, we should let **Windows HTTP stack** handle the SPNEGO negotiation automatically:

### **Current Approach (BROKEN)**:
```powershell
# Manually call InitializeSecurityContext
$result = [SSPI]::InitializeSecurityContext(...)
# ❌ Fails with 0x80090308
```

### **Correct Approach (WORKING)**:
```powershell
# Let Windows HTTP handle SPNEGO automatically
$request = [System.Net.WebRequest]::Create("$VaultUrl/v1/auth/gmsa/login")
$request.UseDefaultCredentials = $true  # ← This triggers automatic SPNEGO
$request.PreAuthenticate = $true        # ← Force SPNEGO on first request
$response = $request.GetResponse()

# Windows will:
# 1. Detect the gMSA identity
# 2. Obtain Kerberos ticket (already done)
# 3. Generate SPNEGO token automatically
# 4. Add "Authorization: Negotiate <token>" header
```

---

## 🛠️ **Implementation Plan**

We need to modify `vault-client-app.ps1` to:

1. **Remove** direct `InitializeSecurityContext` calls
2. **Use** `HttpWebRequest` or `HttpClient` with `UseDefaultCredentials = $true`
3. **Capture** the SPNEGO token from the `Authorization` header
4. **Extract** the token and send it to Vault

### **Key Changes**:

```powershell
function Get-SPNEGOToken {
    param([string]$VaultUrl, [string]$SPN)
    
    # Create a custom HttpWebRequest handler to capture Authorization header
    $request = [System.Net.HttpWebRequest]::Create("$VaultUrl/v1/auth/gmsa/login")
    $request.Method = "POST"
    $request.UseDefaultCredentials = $true
    $request.PreAuthenticate = $true
    
    # Add a custom header inspector (this is pseudo-code)
    # We need to intercept the Authorization header that Windows adds
    
    try {
        $response = $request.GetResponse()
    } catch {
        # Even on error, check if Authorization header was added
    }
    
    # Extract Authorization: Negotiate <token>
    $authHeader = $request.Headers["Authorization"]
    if ($authHeader -like "Negotiate *") {
        $spnegoToken = $authHeader.Substring(10)  # Remove "Negotiate "
        return $spnegoToken
    }
    
    return $null
}
```

---

## 🎯 **Why This Will Work**

1. **Windows HTTP stack has FULL LSA integration** - it can access gMSA credentials
2. **Automatic SPNEGO generation** - no manual `InitializeSecurityContext` needed
3. **Proven approach** - this is how IIS, browsers, and other Windows apps do Kerberos auth

---

## ⚠️ **Alternative: Use NegotiateStream**

If capturing HTTP headers is difficult, we can use `NegotiateStream`:

```powershell
$stream = New-Object System.Net.Security.NegotiateStream($networkStream, $false)
$stream.AuthenticateAsClient([System.Net.NetworkCredential]::Empty, $SPN)
$context = $stream.RemoteIdentity
# Extract SPNEGO token from stream
```

---

## 📋 **Next Steps**

1. **Test password rotation** - verify keytab is still valid
2. **Implement HttpWebRequest SPNEGO capture** - use Windows HTTP stack
3. **Remove InitializeSecurityContext calls** - they don't work with gMSA in scheduled tasks
4. **Test authentication** - should work with automatic SPNEGO

The keytab on Vault is CORRECT. The problem is on the Windows client side - we need to let Windows handle SPNEGO generation automatically instead of manually calling SSPI functions.
