# Vault gMSA PowerShell Client Validation Against Go Implementation

## Executive Summary

After analyzing the Go authentication method implementation and comparing it with the PowerShell client, I've identified several critical issues that explain why the PowerShell client is failing with "400 Bad Request" errors.

## Key Findings

### 1. **SPNEGO Token Generation Issue** ❌
**Problem**: The PowerShell client is generating **mock/fake SPNEGO tokens** instead of real ones.

**Current Implementation**:
```powershell
# This generates a fake token, not a real SPNEGO token
$spnegoData = "KERBEROS_TICKET_BASED_TOKEN_$($ticketHashString.Substring(0,16))_$timestamp"
$spnegoToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($spnegoData))
```

**Go Implementation Expects**:
- Real SPNEGO token structure
- Valid Kerberos ticket embedded in SPNEGO
- Proper base64 encoding of binary SPNEGO data

### 2. **Missing SPNEGO Negotiation Flow** ❌
**Problem**: The PowerShell client doesn't implement proper SPNEGO negotiation.

**Required Flow**:
1. Make initial request to trigger 401 challenge
2. Server responds with `WWW-Authenticate: Negotiate`
3. Client generates SPNEGO token using Windows SSPI
4. Client sends SPNEGO token in `Authorization: Negotiate <token>` header
5. Server validates SPNEGO token using keytab

**Current Implementation**: Skips steps 2-4 and generates fake tokens.

### 3. **Vault Server Configuration Issues** ⚠️
**Problem**: The Vault server may not be properly configured for gMSA authentication.

**Evidence from Logs**:
- No `WWW-Authenticate: Negotiate` header in responses
- 400 Bad Request instead of 401 Unauthorized
- Missing SPNEGO negotiation challenge

## Go Implementation Analysis

### Authentication Endpoint
```go
// From pkg/backend/paths_login.go
Pattern: "login"
Fields: {
    "role":    {Type: framework.TypeString, Required: true},
    "spnego":  {Type: framework.TypeString, Required: true},
    "cb_tlse": {Type: framework.TypeString, Optional: true}
}
```

### SPNEGO Validation Process
```go
// From internal/kerb/validator.go
func (v *Validator) ValidateSPNEGO(ctx context.Context, spnegoB64, channelBind string) (*ValidationResult, safeErr) {
    // 1. Decode base64 SPNEGO token
    spnegoBytes, err := base64.StdEncoding.DecodeString(spnegoB64)
    
    // 2. Parse SPNEGO token structure
    var token spnego.SPNEGOToken
    if err := token.Unmarshal(spnegoBytes); err != nil {
        return nil, fail(newAuthError(ErrCodeInvalidSPNEGO, "spnego token unmarshal failed", err), "spnego token unmarshal failed")
    }
    
    // 3. Validate using keytab
    service := spnego.SPNEGOService(kt)
    ok, spnegoCtx, status := service.AcceptSecContext(&token)
    if !ok {
        return nil, fail(newAuthError(ErrCodeKerberosFailed, "kerberos negotiation failed", status), "kerberos negotiation failed")
    }
    
    // 4. Extract principal and realm
    // 5. Validate against role constraints
}
```

### Input Validation
```go
// From pkg/backend/paths_login.go
func (b *gmsaBackend) validateLoginInput(roleName, spnegoB64, cb string) error {
    // Validate SPNEGO token
    if spnegoB64 == "" {
        return fmt.Errorf("spnego token is required")
    }
    if len(spnegoB64) > 64*1024 {
        return fmt.Errorf("spnego token too large")
    }
    if !isValidBase64(spnegoB64) {
        return fmt.Errorf("invalid spnego token encoding")
    }
}
```

## Required Fixes

### 1. **Implement Real SPNEGO Token Generation**

Replace the mock token generation with proper Windows SSPI integration:

```powershell
function Get-RealSPNEGOToken {
    param(
        [string]$TargetSPN,
        [string]$VaultUrl
    )
    
    try {
        # Step 1: Make initial request to trigger 401 challenge
        $initialRequest = [System.Net.HttpWebRequest]::Create("$VaultUrl/v1/auth/gmsa/login")
        $initialRequest.Method = "POST"
        $initialRequest.ContentType = "application/json"
        
        $body = @{
            role = "vault-gmsa-role"
        } | ConvertTo-Json
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $initialRequest.ContentLength = $bodyBytes.Length
        
        $requestStream = $initialRequest.GetRequestStream()
        $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $requestStream.Close()
        
        try {
            $initialResponse = $initialRequest.GetResponse()
            # Should not reach here - expect 401
        } catch {
            $statusCode = $_.Exception.Response.StatusCode
            if ($statusCode -eq 401) {
                # Step 2: Check for WWW-Authenticate: Negotiate
                $response = $_.Exception.Response
                if ($response.Headers["WWW-Authenticate"] -like "*Negotiate*") {
                    # Step 3: Make authenticated request with Windows credentials
                    $authRequest = [System.Net.HttpWebRequest]::Create("$VaultUrl/v1/auth/gmsa/login")
                    $authRequest.Method = "POST"
                    $authRequest.UseDefaultCredentials = $true
                    $authRequest.PreAuthenticate = $true
                    $authRequest.ContentType = "application/json"
                    
                    $authRequest.ContentLength = $bodyBytes.Length
                    $authStream = $authRequest.GetRequestStream()
                    $authStream.Write($bodyBytes, 0, $bodyBytes.Length)
                    $authStream.Close()
                    
                    # Step 4: Capture SPNEGO token from Authorization header
                    if ($authRequest.Headers.Contains("Authorization")) {
                        $authHeader = $authRequest.Headers.GetValues("Authorization")
                        if ($authHeader[0] -like "Negotiate *") {
                            $spnegoToken = $authHeader[0].Substring(10) # Remove "Negotiate "
                            return $spnegoToken
                        }
                    }
                }
            }
        }
    } catch {
        Write-Log "SPNEGO token generation failed: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}
```

### 2. **Fix Vault Server Configuration**

Ensure the Vault server is properly configured:

```bash
# 1. Enable gMSA authentication method
vault auth enable gmsa

# 2. Configure gMSA authentication
vault write auth/gmsa/config \
    keytab_b64='<BASE64_KEYTAB_HERE>' \
    spn='HTTP/vault.local.lab' \
    realm='LOCAL.LAB' \
    allow_channel_binding=false

# 3. Create gMSA role
vault write auth/gmsa/role/vault-gmsa-role \
    allowed_realms='LOCAL.LAB' \
    allowed_spns='HTTP/vault.local.lab' \
    token_policies='vault-gmsa-policy' \
    token_ttl=1h \
    token_max_ttl=24h
```

### 3. **Implement Proper Error Handling**

Handle the specific error responses from the Go implementation:

```powershell
function Handle-VaultAuthenticationError {
    param([System.Exception]$Exception)
    
    if ($Exception.Response) {
        $statusCode = $Exception.Response.StatusCode
        $errorStream = $Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorStream)
        $errorBody = $reader.ReadToEnd()
        $reader.Close()
        $errorStream.Close()
        
        $errorJson = $errorBody | ConvertFrom-Json
        if ($errorJson.errors) {
            $errorMessage = $errorJson.errors -join ', '
            
            # Map Go error messages to PowerShell actions
            switch -Wildcard ($errorMessage) {
                "*spnego token unmarshal failed*" {
                    Write-Log "SPNEGO token format is invalid" -Level "ERROR"
                    Write-Log "Ensure you're generating real SPNEGO tokens, not mock ones" -Level "ERROR"
                }
                "*kerberos negotiation failed*" {
                    Write-Log "Kerberos authentication failed" -Level "ERROR"
                    Write-Log "Check that gMSA has valid tickets for SPN: $SPN" -Level "ERROR"
                }
                "*role not found*" {
                    Write-Log "Vault role '$VaultRole' does not exist" -Level "ERROR"
                    Write-Log "Create the role using: vault write auth/gmsa/role/$VaultRole ..." -Level "ERROR"
                }
                "*auth method not configured*" {
                    Write-Log "gMSA authentication method is not configured" -Level "ERROR"
                    Write-Log "Configure using: vault write auth/gmsa/config ..." -Level "ERROR"
                }
                default {
                    Write-Log "Vault authentication error: $errorMessage" -Level "ERROR"
                }
            }
        }
    }
}
```

## Testing Strategy

### 1. **Vault Server Configuration Test**
```powershell
# Test if gMSA auth method is enabled
$authResponse = Invoke-RestMethod -Uri "$VaultUrl/v1/sys/auth"
if ($authResponse.data.gmsa) {
    Write-Host "✅ gMSA auth method is enabled"
} else {
    Write-Host "❌ gMSA auth method is NOT enabled"
}
```

### 2. **SPNEGO Negotiation Test**
```powershell
# Test if server sends WWW-Authenticate: Negotiate
$request = [System.Net.HttpWebRequest]::Create("$VaultUrl/v1/auth/gmsa/login")
$request.Method = "POST"
$request.ContentType = "application/json"

try {
    $response = $request.GetResponse()
} catch {
    if ($_.Exception.Response.Headers["WWW-Authenticate"] -like "*Negotiate*") {
        Write-Host "✅ SPNEGO negotiation is configured"
    } else {
        Write-Host "❌ SPNEGO negotiation is NOT configured"
    }
}
```

### 3. **Real SPNEGO Token Test**
```powershell
# Test with real SPNEGO token
$realSpnegoToken = Get-RealSPNEGOToken -TargetSPN $SPN -VaultUrl $VaultUrl
if ($realSpnegoToken) {
    $loginBody = @{
        role = $VaultRole
        spnego = $realSpnegoToken
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Method POST -Uri "$VaultUrl/v1/auth/gmsa/login" -Body $loginBody -ContentType "application/json"
        Write-Host "✅ Authentication successful!"
    } catch {
        Write-Host "❌ Authentication failed: $($_.Exception.Message)"
    }
}
```

## Conclusion

The PowerShell client is failing because it's not generating real SPNEGO tokens that the Go implementation can validate. The solution requires:

1. **Implementing proper Windows SSPI integration** for real SPNEGO token generation
2. **Fixing the Vault server configuration** to enable SPNEGO negotiation
3. **Implementing proper error handling** for Go-specific error messages
4. **Testing the complete authentication flow** with real gMSA identity

The current mock token approach will never work with the Go implementation, which expects valid Kerberos tickets embedded in proper SPNEGO token structures.
