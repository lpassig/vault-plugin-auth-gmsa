# =============================================================================
# Configure Vault Server with gMSA Keytab
# =============================================================================

Write-Host "=== Vault Server Configuration Script ===" -ForegroundColor Green
Write-Host "This script helps configure the Linux Vault server with the gMSA keytab" -ForegroundColor Yellow

# Read the base64 keytab
$keytabPath = "C:\vault-keytab.b64"
if (Test-Path $keytabPath) {
    $keytabBase64 = Get-Content $keytabPath -Raw
    Write-Host "✅ Keytab loaded successfully" -ForegroundColor Green
    Write-Host "Keytab size: $($keytabBase64.Length) characters" -ForegroundColor Cyan
} else {
    Write-Host "❌ Keytab file not found: $keytabPath" -ForegroundColor Red
    exit 1
}

# Display configuration information
Write-Host "`n=== Vault Server Configuration ===" -ForegroundColor Green
Write-Host "SPN: HTTP/vault.local.lab" -ForegroundColor Cyan
Write-Host "Realm: LOCAL.LAB" -ForegroundColor Cyan
Write-Host "Service Account: vault-keytab-svc" -ForegroundColor Cyan
Write-Host "Keytab: vault-keytab.keytab" -ForegroundColor Cyan

# Generate Vault configuration commands
Write-Host "`n=== Vault Configuration Commands ===" -ForegroundColor Green
Write-Host "Run these commands on your Linux Vault server:" -ForegroundColor Yellow

Write-Host "`n# 1. Enable gMSA authentication method" -ForegroundColor Cyan
Write-Host "vault auth enable gmsa" -ForegroundColor White

Write-Host "`n# 2. Configure gMSA authentication" -ForegroundColor Cyan
Write-Host "vault write auth/gmsa/config \" -ForegroundColor White
Write-Host "    keytab_b64='$keytabBase64' \" -ForegroundColor White
Write-Host "    spn='HTTP/vault.local.lab' \" -ForegroundColor White
Write-Host "    realm='LOCAL.LAB' \" -ForegroundColor White
Write-Host "    require_cb=false" -ForegroundColor White

Write-Host "`n# 3. Create gMSA role" -ForegroundColor Cyan
Write-Host "vault write auth/gmsa/role/vault-gmsa-role \" -ForegroundColor White
Write-Host "    bound_service_account_names='vault-gmsa' \" -ForegroundColor White
Write-Host "    bound_service_account_namespaces='LOCAL.LAB' \" -ForegroundColor White
Write-Host "    token_policies='vault-gmsa-policy' \" -ForegroundColor White
Write-Host "    token_ttl=1h \" -ForegroundColor White
Write-Host "    token_max_ttl=24h" -ForegroundColor White

Write-Host "`n# 4. Create policy for gMSA" -ForegroundColor Cyan
Write-Host "vault policy write vault-gmsa-policy - <<EOF" -ForegroundColor White
Write-Host "path \"kv/data/my-app/*\" {" -ForegroundColor White
Write-Host "  capabilities = [\"read\"]" -ForegroundColor White
Write-Host "}" -ForegroundColor White
Write-Host "EOF" -ForegroundColor White

Write-Host "`n# 5. Enable KV secrets engine" -ForegroundColor Cyan
Write-Host "vault secrets enable -path=kv kv-v2" -ForegroundColor White

Write-Host "`n# 6. Create test secrets" -ForegroundColor Cyan
Write-Host "vault kv put kv/my-app/database username=dbuser password=dbpass123" -ForegroundColor White
Write-Host "vault kv put kv/my-app/api api_key=abc123 secret=xyz789" -ForegroundColor White

Write-Host "`n=== DNS Configuration Required ===" -ForegroundColor Yellow
Write-Host "Ensure DNS resolution is configured:" -ForegroundColor Yellow
Write-Host "- vault.local.lab should resolve to your Linux Vault server IP" -ForegroundColor White
Write-Host "- This allows Windows clients to request Kerberos tickets" -ForegroundColor White

Write-Host "`n=== Testing Commands ===" -ForegroundColor Green
Write-Host "After configuration, test with:" -ForegroundColor Yellow
Write-Host "vault auth list" -ForegroundColor White
Write-Host "vault read auth/gmsa/config" -ForegroundColor White
Write-Host "vault read auth/gmsa/role/vault-gmsa-role" -ForegroundColor White

Write-Host "`n=== Windows Client Test ===" -ForegroundColor Green
Write-Host "Run the PowerShell script on Windows client:" -ForegroundColor Yellow
Write-Host ".\vault-client-app.ps1" -ForegroundColor White

Write-Host "`n=== Configuration Complete ===" -ForegroundColor Green
Write-Host "The keytab is ready for Vault server configuration!" -ForegroundColor Green
