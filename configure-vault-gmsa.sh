#!/bin/bash
# Configure Vault gMSA Auth with Auto-Rotation
# Run this script on your Vault server (ssh lennart@107.23.32.117)

set -e

echo "========================================="
echo " Configuring Vault gMSA Auth"
echo " with Auto-Rotation"
echo "========================================="
echo ""

# Configuration
REALM="LOCAL.LAB"
KDCS="addc.local.lab"
SPN="HTTP/vault.local.lab"
KEYTAB_B64="BQIAAABRAAIACUxPQ0FMLkxBQgAESFRUUAAPdmF1bHQubG9jYWwubGFiAAAAAQAAAAAFABIAILBYBG52/nfd2vUaZ1VDMhXQYJTe/rtdnuknqsm8vbhj"

echo "Configuration:"
echo "  Realm: $REALM"
echo "  KDCs: $KDCS"
echo "  SPN: $SPN"
echo ""

# Configure Vault auth method with AUTO-ROTATION
echo "Configuring Vault auth/gmsa with auto-rotation..."
vault write auth/gmsa/config \
  realm="$REALM" \
  kdcs="$KDCS" \
  spn="$SPN" \
  keytab="$KEYTAB_B64" \
  clock_skew_sec=300 \
  allow_channel_binding=true \
  enable_rotation=true \
  rotation_threshold=5d \
  backup_keytabs=true

echo ""
echo "✓ Configuration complete!"
echo ""

# Verify configuration
echo "Verifying configuration..."
vault read auth/gmsa/config

echo ""
echo "Checking rotation status..."
vault read auth/gmsa/rotation/status

echo ""
echo "========================================="
echo " ✓ Vault gMSA Auth Configured!"
echo "========================================="
echo ""
echo "Auto-rotation enabled:"
echo "  - Threshold: 5 days before expiry"
echo "  - Backup: Enabled"
echo "  - Status: Check above"
echo ""
echo "Next steps:"
echo "  1. Go back to Windows client"
echo "  2. Run: .\setup-gmsa-production.ps1 -Step 7"
echo "  3. Test passwordless authentication!"
echo ""
