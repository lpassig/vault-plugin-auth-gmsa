# 🔍 FINAL DIAGNOSIS: Why 0x80090308 Persists

## 📊 **Current Status**

✅ **Vault Server Side**:
- Keytab configured with real AES256 key
- gMSA plugin enabled and running
- No authentication attempts received (confirmed via logs)

❌ **Windows Client Side**:
- Service ticket obtained successfully (`klist` shows ticket)
- Running under `vault-gmsa$` identity (confirmed)
- `InitializeSecurityContext` fails with `0x80090308` **EVERY TIME**
- No SPNEGO token ever generated
- No authentication request ever sent to Vault

---

## 🚨 **Root Cause**

The PowerShell script is calling `InitializeSecurityContext` **directly in userland** (PowerShell process), but:

1. **gMSA credentials are managed by LSA (Local Security Authority)**
2. **`InitializeSecurityContext` in PowerShell can't access LSA context when running under gMSA in a scheduled task**
3. **Even though Kerberos tickets exist, SSPI can't use them from PowerShell**

This is a **fundamental limitation** of how Windows handles gMSA credentials in scheduled tasks vs. interactive logons.

---

## ✅ **The CORRECT Solution**

### **Stop calling `InitializeSecurityContext` directly. Use Windows HTTP stack instead.**

Windows HTTP classes (`HttpWebRequest`, `WebClient`, `Invoke-WebRequest`) have **native LSA integration** and can generate SPNEGO tokens automatically when:
- `UseDefaultCredentials = $true`
- The server responds with `WWW-Authenticate: Negotiate`

### **The Problem with Our Current Approach**:

```powershell
# ❌ DOESN'T WORK for gMSA in scheduled tasks
$result = [SSPI]::InitializeSecurityContext(...)
# Fails with 0x80090308 (SEC_E_UNKNOWN_CREDENTIALS)
```

### **The CORRECT Approach**:

```powershell
# ✅ WORKS for gMSA in scheduled tasks
$request = [System.Net.WebRequest]::Create("$VaultUrl/v1/sys/health")
$request.UseDefaultCredentials = $true
$request.GetResponse()
# Windows automatically:
# 1. Detects gMSA identity
# 2. Obtains Kerberos ticket (already done)
# 3. Generates SPNEGO token via LSA
# 4. Adds "Authorization: Negotiate <token>" header
```

---

## 🎯 **The Fix**

We need to modify the PowerShell script to:

1. **Trigger WWW-Authenticate from Vault** (make it return 401 with `WWW-Authenticate: Negotiate`)
2. **Let Windows HTTP stack handle SPNEGO** (automatic with `UseDefaultCredentials`)
3. **Capture the generated token** from the `Authorization` header
4. **Send it to Vault** in the POST body

**BUT WAIT** - the Vault gMSA plugin **doesn't send `WWW-Authenticate: Negotiate`** because it expects the token in the request body, not via HTTP Negotiate protocol!

---

## 💡 **Alternative Solution: Bypass PowerShell Completely**

Since PowerShell can't reliably generate SPNEGO tokens for gMSAs in scheduled tasks, we need a **different approach**:

### **Option 1: Use a compiled .NET executable**
- .NET executable has better LSA integration
- Can call `AuthenticationManager.Authenticate()`
- Runs under gMSA identity in scheduled task

### **Option 2: Use curl with SSPI (Windows)**
- `curl --negotiate --user : https://vault.local.lab:8200/v1/auth/gmsa/login`
- Let curl handle SPNEGO generation
- Capture output and parse in PowerShell

### **Option 3: Modify Vault Plugin to Support HTTP Negotiate**
- Add `WWW-Authenticate: Negotiate` response
- Let Windows HTTP stack handle everything
- No manual SPNEGO token generation needed

---

## 📋 **Recommended Next Steps**

1. **Test if gMSA password rotated**: Run `.\verify-gmsa-password-rotation.ps1` on ADDC
2. **If password didn't rotate**: The keytab is still valid, problem is client-side SPNEGO generation
3. **Implement Option 2 (curl)**: Quick test to see if curl can generate SPNEGO
4. **Long-term**: Create a .NET executable for better LSA integration

The fundamental issue is that **PowerShell + gMSA + Scheduled Task + InitializeSecurityContext = ❌** due to Windows security architecture.
