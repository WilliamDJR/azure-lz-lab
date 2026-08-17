#!/usr/bin/env bash
#
# Tears down ONLY the hourly-billed components (firewall, both gateways,
# their public IPs and the UDR that depends on the firewall), leaving the
# VNets, peering, private endpoint, DNS zones and Log Analytics in place.
#
# Run this at the end of every session. Firewall, gateways, VMs and log
# ingestion continue to accrue charges while enabled.
#
set -euo pipefail

cd "$(dirname "$0")/../terraform/20-platform"

TF=${TF:-terraform}
SUBSCRIPTION_VAR_FILE=${SUBSCRIPTION_VAR_FILE:-../subscriptions.tfvars}

echo "Setting all cost toggles to false and applying..."
echo

$TF apply \
  -var 'enable_firewall=false' \
  -var 'enable_vpn_gateway=false' \
  -var 'enable_simulated_onprem=false' \
  -var 'enable_test_vm=false' \
  -var 'enable_sentinel=false' \
  -var-file="$SUBSCRIPTION_VAR_FILE" \
  "$@"

echo
echo "Done. Remember to also set these back to false in terraform.tfvars,"
echo "otherwise the next plain 'terraform apply' will rebuild them."
echo
echo "Sanity check - anything still billing by the hour:"
for output_name in connectivity_subscription_id sandbox_subscription_id corp_dev_subscription_id security_subscription_id; do
  subscription_id=$($TF output -raw "$output_name")
  echo "Subscription: $output_name ($subscription_id)"
  az resource list \
    --subscription "$subscription_id" \
    --tag lab=true \
    --query "[?type=='Microsoft.Network/azureFirewalls' || type=='Microsoft.Network/virtualNetworkGateways' || type=='Microsoft.Compute/virtualMachines'].{name:name, type:type, rg:resourceGroup}" \
    --output table
done
