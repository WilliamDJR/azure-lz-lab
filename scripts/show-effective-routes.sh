#!/usr/bin/env bash
#
# Shows the EFFECTIVE routes on the test VM's NIC - i.e. what Azure actually
# programmed, after merging system routes, UDRs and BGP-learned routes.
#
# Run this three times and diff the output:
#   1. Baseline (firewall off, gateway off)
#   2. After enable_firewall = true
#   3. After enable_vpn_gateway = true and enable_simulated_onprem = true
#
# Watching that table change is the fastest way to internalise Azure routing.
#
set -euo pipefail

cd "$(dirname "$0")/../terraform/20-platform"

TF=${TF:-terraform}
RG=$($TF output -raw landing_zone_resource_group)
SUBSCRIPTION_ID=$($TF output -raw corp_dev_subscription_id)
NIC=$(az network nic list --subscription "$SUBSCRIPTION_ID" -g "$RG" --query "[0].name" -o tsv)

echo "Effective routes on NIC: $NIC (resource group $RG)"
echo

az network nic show-effective-route-table \
  --resource-group "$RG" \
  --name "$NIC" \
  --subscription "$SUBSCRIPTION_ID" \
  --output table

cat <<'EOF'

------------------------------------------------------------------------------
What to look for
------------------------------------------------------------------------------
Source column:
  Default        - system route Azure created for you
  VirtualNetworkPeering - learned because of the hub peering
  User           - your UDR
  VirtualNetworkGateway - learned over BGP from the VPN/ExpressRoute gateway

Longest prefix match wins, ALWAYS. This is why the 10.0.0.0/8 UDR in the
route table does not send hub traffic to the firewall: the peering system
route for the hub is 10.0.0.0/16, which is more specific than /8, so peering
wins. If you actually want hub-bound traffic inspected you must write a UDR
that is at least as specific as the peering route.

If two routes have the SAME prefix length, the tie-break order is:
  User-defined route  >  BGP route  >  System route

State column: an "Invalid" next hop almost always means the firewall or
gateway the UDR points at no longer exists.
------------------------------------------------------------------------------
EOF
