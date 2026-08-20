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
SUBSCRIPTION_VAR_FILE=${SUBSCRIPTION_VAR_FILE:-}

if [[ -z "$SUBSCRIPTION_VAR_FILE" ]]; then
  deployment_mode=$($TF output -raw deployment_mode 2>/dev/null || true)
  if [[ "$deployment_mode" == "single-subscription" ]]; then
    SUBSCRIPTION_VAR_FILE="../subscriptions.single.tfvars"
  elif [[ "$deployment_mode" == "quota-limited" ]]; then
    SUBSCRIPTION_VAR_FILE="../subscriptions.quota-limited.tfvars"
  else
    SUBSCRIPTION_VAR_FILE="../subscriptions.tfvars"
  fi
fi

if [[ ! -f "$SUBSCRIPTION_VAR_FILE" ]]; then
  echo "Subscription manifest not found: $SUBSCRIPTION_VAR_FILE" >&2
  echo "Set SUBSCRIPTION_VAR_FILE to the manifest used for this deployment." >&2
  exit 2
fi

echo "Setting all cost toggles to false and applying..."
echo

$TF apply \
  -var-file="$SUBSCRIPTION_VAR_FILE" \
  "$@" \
  -var 'enable_firewall=false' \
  -var 'enable_vpn_gateway=false' \
  -var 'enable_simulated_onprem=false' \
  -var 'enable_test_vm=false' \
  -var 'enable_sentinel=false'

echo
echo "Done. Remember to also set these back to false in terraform.tfvars,"
echo "otherwise the next plain 'terraform apply' will rebuild them."
echo
echo "Sanity check - anything still billing by the hour:"
checked_subscriptions=()
for output_name in connectivity_subscription_id sandbox_subscription_id corp_dev_subscription_id security_subscription_id; do
  subscription_id=$($TF output -raw "$output_name")

  already_checked=false
  for checked_subscription_id in "${checked_subscriptions[@]-}"; do
    if [[ "$checked_subscription_id" == "$subscription_id" ]]; then
      already_checked=true
      break
    fi
  done
  if [[ "$already_checked" == true ]]; then
    continue
  fi

  checked_subscriptions+=("$subscription_id")
  echo "Subscription: $output_name ($subscription_id)"
  az resource list \
    --subscription "$subscription_id" \
    --tag lab=true \
    --query "[?type=='Microsoft.Network/azureFirewalls' || type=='Microsoft.Network/virtualNetworkGateways' || type=='Microsoft.Compute/virtualMachines'].{name:name, type:type, rg:resourceGroup}" \
    --output table
done
