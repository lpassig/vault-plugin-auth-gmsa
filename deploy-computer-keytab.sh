#!/bin/bash
# Deploy Computer Account Keytab to Vault
# This script configures Vault to use the computer account keytab

set -e

VAULT_ADDR="https://52.59.253.119:8200"
VAULT_TOKEN="${VAULT_TOKEN:-your-vault-token-here}"
KEYTAB_B64="BQIAAABRAAIACUxPQ0FMLkxBQgAESFRUUAAPdmF1bHQubG9jYWwubGFiAAAAAQAAAAACABIAIHm5fmpYTbxb5crqox9cK2YfECBk6LYDOMzV/EFE5s4Z"

echo "=========================================="
echo "DEPLOYING COMPUTER ACCOUNT KEYTAB TO VAULT"
echo "=========================================="
echo ""

# Step 1: Verify SPN is registered to computer account
echo "Step 1: SPN Registration Status"
echo "--------------------------------"
echo "Expected SPN: HTTP/vault.local.lab"
echo "Expected Account: EC2AMAZ-UB1QVDL$"
echo ""
echo "✅ Run on ADDC to verify:"
echo "   setspn -L EC2AMAZ-UB1QVDL$"
echo ""

# Step 2: Update Vault configuration with computer account keytab
echo "Step 2: Updating Vault Configuration"
echo "-------------------------------------"

vault write -tls-skip-verify auth/gmsa/config \
  service_principal="HTTP/vault.local.lab" \
  realm="LOCAL.LAB" \
  keytab_b64="$KEYTAB_B64" \
  kdcs="10.0.101.152:88"

if [ $? -eq 0 ]; then
  echo "✅ Vault configuration updated successfully!"
else
  echo "❌ Failed to update Vault configuration"
  exit 1
fi

echo ""
echo "Step 3: Verify Configuration"
echo "-----------------------------"

vault read auth/gmsa/config -tls-skip-verify

echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "----------"
echo ""
echo "1. On Windows CLIENT (EC2AMAZ-UB1QVDL):"
echo "   - Update scheduled task to run as 'NT AUTHORITY\\SYSTEM'"
echo "   - Run: .\vault-client-app.ps1"
echo ""
echo "2. The authentication flow:"
echo "   - Task runs as SYSTEM"
echo "   - curl.exe uses computer account (EC2AMAZ-UB1QVDL$) for network auth"
echo "   - Vault validates against computer account keytab"
echo ""
echo "3. Test with:"
echo "   schtasks /Run /TN 'Vault gMSA Client'"
echo ""
echo "=========================================="
