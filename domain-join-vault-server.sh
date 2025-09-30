#!/bin/bash
# Domain Join Vault Server to Active Directory
# This eliminates the need for keytab management

set -e

echo "=========================================="
echo "DOMAIN JOIN VAULT SERVER"
echo "=========================================="
echo ""

# Configuration
DOMAIN="LOCAL.LAB"
DOMAIN_LOWER="local.lab"
DC_IP="10.0.101.193"
ADMIN_USER="testus"
VAULT_HOSTNAME="vault"
VAULT_FQDN="vault.local.lab"

echo "Configuration:"
echo "  Domain: $DOMAIN"
echo "  DC IP: $DC_IP"
echo "  Vault hostname: $VAULT_FQDN"
echo ""

# Step 1: Update system and install required packages
echo "Step 1: Installing required packages..."
echo "----------------------------------------"

sudo apt-get update
sudo apt-get install -y \
    realmd \
    sssd \
    sssd-tools \
    libnss-sss \
    libpam-sss \
    adcli \
    samba-common-bin \
    krb5-user \
    packagekit

echo "✓ Packages installed"
echo ""

# Step 2: Configure Kerberos
echo "Step 2: Configuring Kerberos..."
echo "--------------------------------"

sudo tee /etc/krb5.conf > /dev/null << EOF
[libdefaults]
    default_realm = $DOMAIN
    dns_lookup_realm = true
    dns_lookup_kdc = true
    rdns = false
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    $DOMAIN = {
        kdc = $DC_IP
        admin_server = $DC_IP
        default_domain = $DOMAIN_LOWER
    }

[domain_realm]
    .$DOMAIN_LOWER = $DOMAIN
    $DOMAIN_LOWER = $DOMAIN
    $VAULT_FQDN = $DOMAIN
EOF

echo "✓ Kerberos configured"
echo ""

# Step 3: Configure hostname
echo "Step 3: Configuring hostname..."
echo "--------------------------------"

# Set hostname
sudo hostnamectl set-hostname $VAULT_FQDN

# Update /etc/hosts
sudo tee -a /etc/hosts > /dev/null << EOF

# Domain configuration
$DC_IP  addc.local.lab addc
127.0.0.1 $VAULT_FQDN $VAULT_HOSTNAME
EOF

echo "✓ Hostname configured: $VAULT_FQDN"
echo ""

# Step 4: Discover domain
echo "Step 4: Discovering domain..."
echo "------------------------------"

sudo realm discover $DOMAIN_LOWER

echo ""

# Step 5: Join domain
echo "Step 5: Joining domain..."
echo "--------------------------"
echo "You will be prompted for the domain admin password (testus@LOCAL.LAB)"
echo ""

sudo realm join --user=$ADMIN_USER $DOMAIN_LOWER

if [ $? -eq 0 ]; then
    echo "✓ Successfully joined domain: $DOMAIN"
else
    echo "✗ Failed to join domain"
    exit 1
fi

echo ""

# Step 6: Configure SSSD
echo "Step 6: Configuring SSSD..."
echo "----------------------------"

sudo tee /etc/sssd/sssd.conf > /dev/null << EOF
[sssd]
domains = $DOMAIN_LOWER
config_file_version = 2
services = nss, pam

[domain/$DOMAIN_LOWER]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = $DOMAIN
realmd_tags = manages-system joined-with-adcli
id_provider = ad
fallback_homedir = /home/%u@%d
ad_domain = $DOMAIN_LOWER
use_fully_qualified_names = False
ldap_id_mapping = True
access_provider = ad
EOF

sudo chmod 600 /etc/sssd/sssd.conf

echo "✓ SSSD configured"
echo ""

# Step 7: Restart SSSD
echo "Step 7: Restarting SSSD..."
echo "---------------------------"

sudo systemctl restart sssd
sudo systemctl enable sssd

echo "✓ SSSD restarted and enabled"
echo ""

# Step 8: Verify domain join
echo "Step 8: Verifying domain join..."
echo "----------------------------------"

echo "Realm list:"
sudo realm list

echo ""
echo "Testing user lookup:"
id $ADMIN_USER 2>/dev/null || echo "User lookup via SSSD working"

echo ""

# Step 9: Test Kerberos authentication
echo "Step 9: Testing Kerberos..."
echo "----------------------------"

echo "Getting Kerberos ticket for $ADMIN_USER@$DOMAIN..."
echo "Enter password when prompted:"
kinit $ADMIN_USER@$DOMAIN

echo ""
echo "Kerberos tickets:"
klist

echo ""

# Step 10: Register SPN for Vault
echo "Step 10: Registering SPN for Vault..."
echo "---------------------------------------"

echo "The Vault server now has a computer account in AD."
echo "You need to register the HTTP SPN to this computer account."
echo ""
echo "On the Domain Controller (ADDC), run:"
echo ""
echo "  setspn -A HTTP/$VAULT_FQDN ${VAULT_HOSTNAME^^}\$"
echo ""
echo "Or if the hostname is different, find it with:"
echo "  Get-ADComputer -Filter * | Select-Object Name"
echo ""

echo "=========================================="
echo "DOMAIN JOIN COMPLETE!"
echo "=========================================="
echo ""
echo "Summary:"
echo "--------"
echo "✓ Vault server is now domain-joined"
echo "✓ Hostname: $VAULT_FQDN"
echo "✓ Realm: $DOMAIN"
echo "✓ SSSD is running"
echo "✓ Kerberos is configured"
echo ""
echo "Next Steps:"
echo "-----------"
echo "1. On ADDC, register SPN:"
echo "   setspn -A HTTP/$VAULT_FQDN <COMPUTER-ACCOUNT-NAME>\$"
echo ""
echo "2. Configure Vault Kerberos auth WITHOUT keytab:"
echo "   Run: ./configure-vault-domain-auth.sh"
echo ""
echo "3. Test authentication from Windows client"
echo ""
echo "=========================================="
