# 🔧 Generate Fresh Keytab for Current gMSA Password

## 🎉 GOOD NEWS: curl.exe IS WORKING!

The verbose output confirms:
```
> Authorization: Negotiate YIIHKwYGKwYBBQUCoIIHHzCCBx...
```

✅ **SPNEGO token IS being generated**  
✅ **Windows SSPI IS working**  
✅ **curl.exe IS sending the Authorization header**  

## ❌ THE PROBLEM: Keytab Mismatch

Vault is returning:
```
{"errors":["kerberos negotiation failed"]}
```

This means the **keytab on Vault doesn't match the gMSA's current password**.

The gMSA password has likely rotated since we last generated the keytab.

---

## 🚀 SOLUTION: Use extract-aes-key.ps1

You already have this script! Run it on your **Domain Controller** or **Windows client** (where you have gMSA access):

### Step 1: Extract Current AES256 Key

```powershell
cd C:\Users\Testus\vault-plugin-auth-gmsa  
.\extract-aes-key.ps1
```

This will output:
```
Hex Key: A1B2C3D4E5F6...  (64 hex characters)
```

**Copy this hex key!**

---

### Step 2: Create Fresh Keytab on Vault Server

SSH to Vault server and run:

```bash
ssh lennart@107.23.32.117

# Replace this with your actual hex key from Step 1
HEX_KEY="PASTE_YOUR_HEX_KEY_HERE"

# Get Docker container ID
CONTAINER_ID=$(sudo docker ps --filter ancestor=hashicorp/vault --format '{{.ID}}')

# Create keytab inside Docker container
sudo docker exec -it $CONTAINER_ID bash << EOF
cd /tmp

# Convert hex to binary
echo "$HEX_KEY" | xxd -r -p > password.bin

# Create keytab using ktutil
ktutil << KTUTIL_EOF
addent -password -p HTTP/vault.local.lab@LOCAL.LAB -k 1 -e aes256-cts-hmac-sha1-96 -f password.bin
wkt vault-gmsa-fresh.keytab
q
KTUTIL_EOF

# Base64 encode
cat vault-gmsa-fresh.keytab | base64 -w0
EOF
```

**Copy the base64 output!**

---

### Step 3: Update Vault Configuration

Still on Vault server:

```bash
export VAULT_ADDR='https://127.0.0.1:8200'
export VAULT_SKIP_VERIFY=1

# Get the base64 keytab from the container
CONTAINER_ID=$(sudo docker ps --filter ancestor=hashicorp/vault --format '{{.ID}}')
KEYTAB_B64=$(sudo docker exec $CONTAINER_ID cat /tmp/vault-gmsa-fresh.keytab | base64 -w0)

# Update Vault config
vault write auth/gmsa/config \
    realm="LOCAL.LAB" \
    kdcs="ADDC.local.lab:88" \
    spn="HTTP/vault.local.lab" \
    keytab="$KEYTAB_B64" \
    clock_skew_sec=300

echo "✅ Vault keytab updated with fresh gMSA password!"
```

---

### Step 4: Test Authentication

On Windows client:

```powershell
Start-ScheduledTask -TaskName 'VaultClientApp'
Get-Content C:\vault-client\config\vault-client.log -Tail 50
```

---

## 📊 Expected Success:

```
[INFO] Method 3: Using curl.exe with --negotiate for direct authentication...
[INFO] curl.exe output: {"auth":{"client_token":"hvs.CAES...","lease_duration":3600}}
[SUCCESS] SUCCESS: Vault authentication successful via curl.exe with --negotiate!
[INFO] Client token: hvs.CAES...
[INFO] Token TTL: 3600 seconds
```

---

## 🎯 Why This Will Work

| Component | Status |
|-----------|--------|
| **Windows Client** | ✅ Working - generating SPNEGO tokens |
| **curl.exe** | ✅ Working - sending Authorization header |
| **Vault Server** | ❌ OLD keytab - needs fresh one |
| **Fresh Keytab** | 🔄 Generate with current gMSA password |

---

**The solution is simple: just regenerate the keytab with the current password!** 🚀
