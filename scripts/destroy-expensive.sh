#!/usr/bin/env bash
#
# Tears down ONLY the hourly-billed components (firewall, both gateways,
# their public IPs and the UDR that depends on the firewall), leaving the
# VNets, peering, private endpoint, DNS zones and Log Analytics in place.
#
# Run this at the end of every session. A forgotten Azure Firewall is about
# A$36/day.
#
set -euo pipefail

cd "$(dirname "$0")/../terraform/20-platform"

TF=${TF:-terraform}

echo "Setting all cost toggles to false and applying..."
echo

$TF apply \
  -var 'enable_firewall=false' \
  -var 'enable_vpn_gateway=false' \
  -var 'enable_simulated_onprem=false' \
  "$@"

echo
echo "Done. Remember to also set these back to false in terraform.tfvars,"
echo "otherwise the next plain 'terraform apply' will rebuild them."
echo
echo "Sanity check - anything still billing by the hour:"
az resource list \
  --tag lab=true \
  --query "[?type=='Microsoft.Network/azureFirewalls' || type=='Microsoft.Network/virtualNetworkGateways' || type=='Microsoft.Compute/virtualMachines'].{name:name, type:type, rg:resourceGroup}" \
  --output table
