#!/bin/bash
# Update Vault with Computer Account Keytab
# Run this ON the Vault server or via SSH

export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TOKEN="${VAULT_TOKEN:-your-vault-token-here}"

KEYTAB_B64="BQIAAABRAAIACUxPQ0FMLkxBQgAESFRUUAAPdmF1bHQubG9jYWwubGFiAAAAAQAAAAACABIAIHm5fmpYTbxb5crqox9cK2YfECBk6LYDOMzV/EFE5s4Z"

echo "=========================================="
echo "UPDATING VAULT WITH COMPUTER ACCOUNT KEYTAB"
echo "=========================================="
echo ""

echo "Current Configuration:"
echo "----------------------"
vault read -tls-skip-verify auth/gmsa/config 2>/dev/null || echo "No existing config"
echo ""

echo "Updating Configuration..."
echo "-------------------------"

vault write -tls-skip-verify auth/gmsa/config \
  service_principal="HTTP/vault.local.lab" \
  realm="LOCAL.LAB" \
  keytab_b64="$KEYTAB_B64" \
  kdcs="10.0.101.152:88"

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ SUCCESS! Vault now configured with computer account keytab"
  echo ""
  echo "New Configuration:"
  echo "------------------"
  vault read -tls-skip-verify auth/gmsa/config
  echo ""
  echo "=========================================="
  echo "READY FOR TESTING!"
  echo "=========================================="
  echo ""
  echo "On Windows CLIENT (EC2AMAZ-UB1QVDL), run:"
  echo ""
  echo "1. First, verify SPN is on computer account:"
  echo "   setspn -L EC2AMAZ-UB1QVDL$"
  echo ""
  echo "2. Update scheduled task to run as SYSTEM:"
  echo "   schtasks /Change /TN \"Vault gMSA Client\" /RU \"NT AUTHORITY\\SYSTEM\""
  echo ""
  echo "3. Run authentication test:"
  echo "   schtasks /Run /TN \"Vault gMSA Client\""
  echo ""
  echo "4. Check logs:"
  echo "   Get-Content C:\\vault-client\\logs\\vault-client-app.log -Tail 50"
  echo ""
else
  echo "❌ Failed to update Vault configuration"
  exit 1
fi
