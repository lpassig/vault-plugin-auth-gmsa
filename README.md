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


## Configuration API

Path: `auth/gmsa/config`

Fields on write:
- `realm` (string, required): Kerberos realm, uppercase (e.g., `EXAMPLE.COM`).
- `kdcs` (string, required): Comma-separated KDCs, each `host` or `host:port`.
- `keytab` (string, required): Base64-encoded keytab content for the service account (SPN).
- `spn` (string, required): e.g., `HTTP/vault.example.com` or `HTTP/vault.example.com@EXAMPLE.COM` (service must be uppercase).
- `allow_channel_binding` (bool): Enforce TLS channel binding (tls-server-end-point) if true.
- `clock_skew_sec` (int): Allowed clock skew seconds (default 300).

Examples:
```bash
base64 -w0 /etc/vault.d/krb5/vault.keytab > keytab.b64

vault write auth/gmsa/config \
  realm=EXAMPLE.COM \
  kdcs="dc1.example.com,dc2.example.com:88" \
  spn=HTTP/vault.example.com \
  keytab=@keytab.b64 \
  allow_channel_binding=true \
  clock_skew_sec=300

vault read auth/gmsa/config
vault delete auth/gmsa/config
```

## Role Management API

Paths:
- `auth/gmsa/role/<name>` (write/read/delete)
- `auth/gmsa/roles` (list)

Role fields:
- `name` (string, required)
- `allowed_realms` (string): Comma-separated realms
- `allowed_spns` (string): Comma-separated SPNs
- `bound_group_sids` (string): Comma-separated AD group SIDs
- `token_policies` (string): Comma-separated policy names
- `token_type` (string): `default` or `service`
- `period` (seconds): Periodic token renewal period
- `max_ttl` (seconds): Maximum TTL
- `deny_policies` (string): Comma-separated policies to remove
- `merge_strategy` (string): `union` or `override` (default `union`)

Example:
```bash
vault write auth/gmsa/role/app \
  name=app \
  allowed_realms=EXAMPLE.COM \
  allowed_spns=HTTP/vault.example.com \
  bound_group_sids=S-1-5-21-111-222-333-419 \
  token_policies=default,kv-read \
  token_type=service \
  period=3600 \
  max_ttl=7200 \
  deny_policies=dev-only \
  merge_strategy=union
```

## Login API

Path: `auth/gmsa/login` (unauthenticated)

Request fields:
- `role` (string, required): Role to authorize against
- `spnego` (string, required): Base64-encoded SPNEGO token
- `cb_tlse` (string, optional): TLS channel binding value when enforced

Response:
- Vault token per role configuration. Metadata includes `principal`, `realm`, `role`, `spn`, `sids_count`.

Windows example (PowerShell):
```powershell
$token = [Convert]::ToBase64String($spnegoBytes)
Invoke-RestMethod -Method POST -Uri "https://vault.example.com/v1/auth/gmsa/login" `
  -Body (@{ role = "app"; spnego = $token } | ConvertTo-Json)
```

## How it works
1. Client obtains a service ticket for configured `spn` via SSPI.
2. Client sends SPNEGO token to `auth/gmsa/login`.
3. Plugin validates the ticket using the configured keytab and SPN; enforces optional TLS channel binding and clock skew.
4. Role checks apply (allowed realms, SPNs, group SIDs intersection).
5. Vault token is issued with policies and TTLs per role.

## Security notes
- PAC / group membership: Validate PAC if you rely on SIDs for strict authorization.
- Channel binding: When enabled, supply `cb_tlse` from the TLS connection to mitigate MITM.
- Time sync: Keep NTP healthy to avoid Kerberos skew errors.
- mTLS: Use TLS (prefer mTLS) between clients and Vault.
- Keytab hygiene: Protect keytabs at rest/in transit; rotate on SPN key changes.

## Troubleshooting
- `KRB_AP_ERR_SKEW`: Fix clock skew / NTP.
- `invalid spnego encoding`: Ensure the `spnego` field is base64 of the raw SPNEGO blob.
- `role "..." not found`: Create the role or correct the `role` value.
- `realm not allowed for role` / `SPN not allowed for role`: Update role constraints or client config.
- `no bound group SID matched`: Client lacks required AD group membership.
- `auth method not configured`: Configure `auth/gmsa/config` first.

Compatibility:
- Build with Go 1.25+. If dependencies require `go1.25` build tags, ensure your toolchain is Go 1.25+.

Development:
```bash
go version   # ensure go1.25+
go mod tidy
go build ./...
```

License: see `LICENSE`.