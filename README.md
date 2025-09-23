# vault-plugin-auth-gmsa
A reference Vault **auth method** that verifies Windows clients using **gMSA / Kerberos (SPNEGO)** and maps AD group SIDs to Vault policies. This is designed as a standalone plugin binary served by Vault’s plugin system.

# Vault gMSA / Kerberos Auth Method (Reference)


This auth method lets Windows workloads that possess a **gMSA** log into Vault using **Kerberos (SPNEGO/Negotiate)**. Vault validates the ticket using a keytab for the gMSA’s SPN and mints a Vault token with mapped policies.


## Why this design
- **No passwords on clients**: gMSA credentials are managed by AD.
- **Mutual trust**: Kerberos tickets are validated by Vault using the gMSA SPN key.
- **Policy mapping**: Use AD **group SIDs** or principal names to map to Vault policies.


## Prereqs
1. AD domain with KDCs reachable by the Vault server.
2. A **gMSA** with an SPN for Vault, e.g. `HTTP/vault.example.com`.
3. Export a **keytab** for that SPN (or generate via `ktpass`) and place it on the Vault server.
4. Time sync between Vault and domain controllers.
5. (Optional) Create AD groups for policy mapping; note their **SIDs**.


> Production note: Prefer secure keytab distribution (e.g., wrapped via Vault’s own file mount with tight ACLs). Rotate when SPN keys rotate.


## Build
```bash
make build
# or
go build -o vault-plugin-auth-gmsa ./cmd/vault-plugin-auth-gmsa
```


## Register the plugin
```bash
# On Vault server
sha256sum vault-plugin-auth-gmsa > /etc/vault.d/plugins/vault-plugin-auth-gmsa.sha256
mv vault-plugin-auth-gmsa /etc/vault.d/plugins/


vault plugin register -sha256="$(cat /etc/vault.d/plugins/vault-plugin-auth-gmsa.sha256 | awk '{print $1}')" \
auth vault-plugin-auth-gmsa


vault auth enable -path=gmsa vault-plugin-auth-gmsa
```


## Configure
```bash
vault write auth/gmsa/config \
realm=EXAMPLE.COM \
kdc_hosts="dc1.example.com,dc2.example.com" \
spn="HTTP/vault.example.com" \
keytab_path="/etc/vault.d/krb5/vault.keytab" \
group_policy_map=@group-map.json \
principal_policy_map=@principal-map.json
```


**group-map.json**
```json
{
"S-1-5-21-1111111111-2222222222-3333333333-512": ["default", "kv-read"],
"S-1-5-21-1111111111-2222222222-3333333333-419": ["prod-app"]
}
```


**principal-map.json** (optional)
```json
{
"APP01$@EXAMPLE.COM": ["app01-policy"]
}
```


## Client login (Windows workload using gMSA)
1. The service obtains a Negotiate (SPNEGO) token for SPN `HTTP/vault.example.com` using SSPI.
2. POST to Vault:
```powershell
$token = [System.Convert]::ToBase64String($spnegoBytes)
Invoke-RestMethod -Method POST -Uri "https://vault.example.com/v1/auth/gmsa/login" -Body (@{ spnego=$token } | ConvertTo-Json)
```


> Tip: Many HTTP stacks (WinHTTP, .NET HttpClient with `UseDefaultCredentials`) will produce the SPNEGO token automatically for the request if the server advertises `WWW-Authenticate: Negotiate`. You can also manually acquire it via SSPI (`AcquireCredentialsHandle` + `InitializeSecurityContext`).


## Security notes
- **PAC validation**: For strict group authorization, implement MS-PAC validation (KDC- and service-signed PAC) before trusting SIDs. The stub `ExtractGroupSIDsFromPAC` should be replaced with full parsing and signature checks.
- **Channel binding**: Optionally bind to TLS channel (extended protection) by including channel bindings in the SPNEGO context and verifying on the server.
- **Replay protection**: Kerberos includes replay protection; ensure Vault nodes have synchronized clocks.
- **mTLS**: Still recommended between clients and Vault.


## Limitations / TODOs
- PAC parsing & signature verification.
- Configurable realm/SPN normalization rules.
- Better error surfaces and audit field redaction.
- Health and metrics endpoints.
- CI tests with a real or mocked KDC.


## Troubleshooting
- `KRB_AP_ERR_SKEW`: Time skew; fix NTP.
- `preauth failed` when minting tokens client-side: verify the gMSA is permitted on the node and SPN is correct.
- `key not found` on server: regenerate/export keytab after SPN updates.


```
Audit fields
- request.client_principal
- request.group_sids (if extracted)
