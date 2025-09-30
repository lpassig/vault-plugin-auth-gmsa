#!/bin/bash
# Execute Vault setup via SSH
# This uploads and runs the setup script on the Vault server

VAULT_IP="107.23.32.117"
VAULT_USER="lennart"
VAULT_TOKEN="${VAULT_TOKEN:-your-vault-token-here}"

echo "=========================================="
echo "DEPLOYING OFFICIAL KERBEROS PLUGIN TO VAULT"
echo "=========================================="
echo ""

echo "Uploading setup script to Vault server..."
scp -o StrictHostKeyChecking=no setup-official-kerberos-vault.sh ${VAULT_USER}@${VAULT_IP}:/tmp/

if [ $? -eq 0 ]; then
    echo "✓ Script uploaded successfully"
else
    echo "✗ Failed to upload script"
    exit 1
fi

echo ""
echo "Executing setup on Vault server..."
echo "----------------------------------"

ssh -o StrictHostKeyChecking=no ${VAULT_USER}@${VAULT_IP} "export VAULT_TOKEN='${VAULT_TOKEN}' && chmod +x /tmp/setup-official-kerberos-vault.sh && /tmp/setup-official-kerberos-vault.sh"

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "VAULT SETUP COMPLETE!"
    echo "=========================================="
    echo ""
    echo "Next steps on Windows CLIENT:"
    echo "-----------------------------"
    echo "1. Download vault-client-kerberos.ps1"
    echo "2. Deploy to C:\\vault-client\\scripts\\"
    echo "3. Update/create scheduled task"
    echo "4. Test authentication"
    echo ""
else
    echo ""
    echo "✗ Setup failed - check output above"
    exit 1
fi
