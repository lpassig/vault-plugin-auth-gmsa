#!/bin/bash
# Check Vault Server Kerberos Configuration
# Run this on the Vault server or via SSH

set -e

export VAULT_ADDR="https://127.0.0.1:8200"

echo "=========================================="
echo "VAULT SERVER KERBEROS CONFIGURATION CHECK"
echo "=========================================="
echo ""

# Check if we have a Vault token
if [ -z "$VAULT_TOKEN" ]; then
    echo "⚠ VAULT_TOKEN not set. You may need to provide a token."
    echo "Set it with: export VAULT_TOKEN='your-token-here'"
    echo ""
fi

# Check Vault status
echo "Step 1: Checking Vault status..."
echo "-------------------------------"
if vault status 2>/dev/null; then
    echo "✓ Vault is running and accessible"
else
    echo "❌ Vault is not accessible or not running"
    exit 1
fi
echo ""

# Check enabled auth methods
echo "Step 2: Checking enabled auth methods..."
echo "----------------------------------------"
if vault auth list 2>/dev/null; then
    echo ""
    if vault auth list 2>/dev/null | grep -q kerberos; then
        echo "✓ Kerberos auth method is enabled"
    else
        echo "❌ Kerberos auth method is NOT enabled"
        echo "Enable it with: vault auth enable kerberos"
    fi
else
    echo "⚠ Could not list auth methods (may need token)"
fi
echo ""

# Check Kerberos configuration
echo "Step 3: Checking Kerberos configuration..."
echo "-------------------------------------------"
if vault read auth/kerberos/config 2>/dev/null; then
    echo "✓ Kerberos configuration found"
else
    echo "❌ Kerberos configuration not found or not accessible"
    echo "Configure it with: vault write auth/kerberos/config ..."
fi
echo ""

# Check Kerberos roles
echo "Step 4: Checking Kerberos roles..."
echo "----------------------------------"
if vault list auth/kerberos/role 2>/dev/null; then
    echo ""
    if vault list auth/kerberos/role 2>/dev/null | grep -q computer-accounts; then
        echo "✓ computer-accounts role exists"
        
        # Show role details
        echo ""
        echo "Role details:"
        vault read auth/kerberos/role/computer-accounts 2>/dev/null || echo "Could not read role details"
    else
        echo "❌ computer-accounts role does NOT exist"
        echo "Create it with: vault write auth/kerberos/role/computer-accounts ..."
    fi
else
    echo "⚠ Could not list roles (may need token)"
fi
echo ""

# Check if keytab file exists
echo "Step 5: Checking keytab files..."
echo "--------------------------------"
KEYTAB_PATHS=(
    "/etc/vault/vault.keytab"
    "/opt/vault/vault.keytab"
    "/tmp/vault.keytab"
    "/home/vault/vault.keytab"
    "/var/lib/vault/vault.keytab"
)

KEYTAB_FOUND=false
for keytab_path in "${KEYTAB_PATHS[@]}"; do
    if [ -f "$keytab_path" ]; then
        echo "✓ Found keytab: $keytab_path"
        echo "Keytab contents:"
        klist -kte "$keytab_path" 2>/dev/null || echo "Could not read keytab contents"
        KEYTAB_FOUND=true
        echo ""
    fi
done

if [ "$KEYTAB_FOUND" = false ]; then
    echo "❌ No keytab files found in common locations"
    echo "You may need to create a keytab file"
fi
echo ""

# Check system Kerberos configuration
echo "Step 6: Checking system Kerberos configuration..."
echo "------------------------------------------------"
if [ -f "/etc/krb5.conf" ]; then
    echo "✓ krb5.conf exists"
    echo "Realm configuration:"
    grep -A 5 "\[realms\]" /etc/krb5.conf 2>/dev/null || echo "No realms section found"
else
    echo "⚠ krb5.conf not found"
fi
echo ""

# Check if we can get a Kerberos ticket
echo "Step 7: Testing Kerberos ticket acquisition..."
echo "-----------------------------------------------"
if command -v kinit >/dev/null 2>&1; then
    echo "✓ kinit command available"
    echo "Note: You may need to configure Kerberos to test ticket acquisition"
else
    echo "⚠ kinit command not available"
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "SUMMARY AND RECOMMENDATIONS"
echo "=========================================="
echo ""

echo "Based on the checks above:"
echo ""

if vault auth list 2>/dev/null | grep -q kerberos; then
    echo "✓ Kerberos auth method is enabled"
else
    echo "❌ Enable Kerberos auth: vault auth enable kerberos"
fi

if vault list auth/kerberos/role 2>/dev/null | grep -q computer-accounts; then
    echo "✓ computer-accounts role exists"
else
    echo "❌ Create role: vault write auth/kerberos/role/computer-accounts bound_service_account_names='*$@LOCAL.LAB' token_policies='default'"
fi

if [ "$KEYTAB_FOUND" = true ]; then
    echo "✓ Keytab file found"
else
    echo "❌ Create keytab file for HTTP/vault.local.lab"
fi

echo ""
echo "=========================================="
echo "NEXT STEPS"
echo "=========================================="
echo ""

echo "1. If Kerberos auth is not enabled:"
echo "   vault auth enable kerberos"
echo ""

echo "2. If configuration is missing:"
echo "   vault write auth/kerberos/config \\"
echo "     keytab='<base64-keytab>' \\"
echo "     service_account='HTTP/vault.local.lab' \\"
echo "     realm='LOCAL.LAB'"
echo ""

echo "3. If role is missing:"
echo "   vault write auth/kerberos/role/computer-accounts \\"
echo "     bound_service_account_names='*$@LOCAL.LAB' \\"
echo "     token_policies='default' \\"
echo "     token_ttl=3600"
echo ""

echo "4. If keytab is missing, create it on Windows:"
echo "   ktpass -out vault.keytab \\"
echo "     -princ HTTP/vault.local.lab@LOCAL.LAB \\"
echo "     -mapUser EC2AMAZ-UB1QVDL$ \\"
echo "     -pass * \\"
echo "     -crypto AES256-SHA1"
echo ""

echo "5. Test authentication from Windows:"
echo "   .\\alternative-auth-methods.ps1"
echo ""

echo "=========================================="
echo "CONFIGURATION CHECK COMPLETE"
echo "=========================================="


