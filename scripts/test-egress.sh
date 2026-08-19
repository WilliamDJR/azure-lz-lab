#!/usr/bin/env bash
# Compare outbound access from the private test VM before and after Azure
# Firewall is enabled. The command uses Azure Run Command, so no public IP or
# Bastion host is required.
set -euo pipefail

cd "$(dirname "$0")/../terraform/20-platform"

TF=${TF:-terraform}
RG=$($TF output -raw landing_zone_resource_group)
VM=$($TF output -raw test_vm_name)
SUBSCRIPTION_ID=$($TF output -raw corp_dev_subscription_id)

if [[ -z "$VM" || "$VM" == "null" ]]; then
  echo "The test VM is not deployed. Set enable_test_vm = true and apply first." >&2
  exit 2
fi

echo "Testing egress from $VM in $RG ($SUBSCRIPTION_ID)..."
az vm run-command invoke \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RG" \
  --name "$VM" \
  --command-id RunShellScript \
  --scripts 'for url in https://github.com https://example.com; do echo "--- $url"; curl -I -sS --max-time 20 -o /dev/null -w "http=%{http_code} remote_ip=%{remote_ip}\n" "$url" || echo "blocked-or-failed"; done; exit 0' \
  --query "value[0].message" \
  --output tsv

cat <<'EOF'

Expected observations:
  - With Firewall disabled, record the actual result. New virtual networks
    created with API versions after 31 March 2026 use private subnets by
    default, so both URLs can fail until an explicit outbound method exists.
  - With Firewall enabled, github.com is allowed by the application rule.
  - example.com should be blocked because it is not in the allow-list.

Confirm the result in Azure Firewall application-rule logs; a curl timeout by
itself does not prove the firewall was the cause.

Reference: https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access
EOF
