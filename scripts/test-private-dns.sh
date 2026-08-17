#!/usr/bin/env bash
#
# Proves the Private Endpoint DNS resolution chain from inside the spoke,
# without Bastion, without a jump host and without a public IP.
#
# This is the single most useful thing in the lab. Run it, read the output,
# then run it again after deliberately breaking the DNS zone VNet link and
# watch the answer change from a private 10.1.1.x address to a public one.
#
# Usage:  ./scripts/test-private-dns.sh
#
set -euo pipefail

cd "$(dirname "$0")/../terraform/20-platform"

TF=${TF:-terraform}

RG=$($TF output -raw landing_zone_resource_group)
VM=$($TF output -raw test_vm_name)
FQDN=$($TF output -raw storage_private_fqdn)
EXPECTED=$($TF output -raw private_endpoint_ip)

echo "Resource group : $RG"
echo "VM             : $VM"
echo "FQDN           : $FQDN"
echo "Expected IP    : $EXPECTED   (the private endpoint's address in snet-privatelink)"
echo
echo "Running nslookup on the VM via the Azure control plane..."
echo

az vm run-command invoke \
  --resource-group "$RG" \
  --name "$VM" \
  --command-id RunShellScript \
  --scripts "echo '--- resolv.conf ---'; cat /etc/resolv.conf; echo; echo '--- dig ---'; (command -v dig >/dev/null || (apt-get update -qq && apt-get install -y -qq dnsutils)) >/dev/null 2>&1; dig +noall +answer ${FQDN}; echo; echo '--- getent ---'; getent hosts ${FQDN}" \
  --query "value[0].message" -o tsv

cat <<'EOF'

------------------------------------------------------------------------------
How to read this
------------------------------------------------------------------------------
You should see a CNAME chain:

    <account>.blob.core.windows.net.  CNAME  <account>.privatelink.blob.core.windows.net.
    <account>.privatelink.blob...     A      10.1.1.x

The CNAME is returned by PUBLIC Azure DNS and always exists once a private
endpoint is created. The A record only resolves privately because the private
DNS zone is LINKED to this VNet.

resolv.conf will point at 168.63.129.16 - the Azure platform DNS resolver.
Every VM in every VNet talks to that same magic address; it is the hook that
makes private zones work at all.

Now break it on purpose:

    terraform destroy -target=azurerm_private_dns_zone_virtual_network_link.blob_to_spoke
    ./scripts/test-private-dns.sh

The name still resolves - but to a PUBLIC IP. Traffic then fails closed
because the storage account has public_network_access_enabled = false.
"It resolves but I cannot connect" is the exact symptom, and a missing VNet
link is the most common cause of it in real estates.

Put it back with:  terraform apply
------------------------------------------------------------------------------
EOF
