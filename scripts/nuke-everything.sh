#!/usr/bin/env bash
#
# Full teardown, in the right order. The platform root must go before the
# governance root, because policy assignments and management groups cannot be
# deleted while subscriptions and resources still sit under them.
#
set -euo pipefail

ROOT="$(dirname "$0")/.."
TF=${TF:-terraform}

read -rp "This destroys the ENTIRE lab. Type 'destroy' to continue: " confirm
[[ "$confirm" == "destroy" ]] || { echo "Aborted."; exit 1; }

echo "==> 20-platform"
(cd "$ROOT/terraform/20-platform" && $TF destroy -auto-approve)

echo "==> 10-governance"
# Move the subscription back out of the hierarchy first, or the management
# group delete will fail with "management group is not empty".
(cd "$ROOT/terraform/10-governance" && $TF destroy -auto-approve)

echo
echo "Management groups can take a few minutes to disappear from the portal."
echo "If a delete fails with 'not empty', check for subscriptions still"
echo "parented under it:  az account management-group show -n <name> -e -r"
