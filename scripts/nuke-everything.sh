#!/usr/bin/env bash
#
# Full teardown, in the right order. The platform root must go before the
# governance root, because policy assignments and management groups cannot be
# deleted while subscriptions and resources still sit under them.
#
set -euo pipefail

ROOT="$(dirname "$0")/.."
TF=${TF:-terraform}
MODE="multi"
SUBSCRIPTION_VAR_FILE=${SUBSCRIPTION_VAR_FILE:-}

usage() {
  cat <<'EOF'
Usage: ./scripts/nuke-everything.sh [--mode multi|single] [--var-file PATH]

The mode selects the matching remote-state keys before destroy. The default
manifests are terraform/subscriptions.tfvars for multi and
terraform/subscriptions.single.tfvars for single. SUBSCRIPTION_VAR_FILE or
--var-file can override the manifest path.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "--mode requires multi or single" >&2
        exit 2
      fi
      MODE="$2"
      shift 2
      ;;
    --var-file)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "--var-file requires a path" >&2
        exit 2
      fi
      SUBSCRIPTION_VAR_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

case "$MODE" in
  multi)
    default_var_file="$ROOT/terraform/subscriptions.tfvars"
    ;;
  single)
    default_var_file="$ROOT/terraform/subscriptions.single.tfvars"
    ;;
  *)
    echo "--mode must be multi or single" >&2
    exit 2
    ;;
esac

SUBSCRIPTION_VAR_FILE=${SUBSCRIPTION_VAR_FILE:-$default_var_file}
if [[ ! -f "$SUBSCRIPTION_VAR_FILE" ]]; then
  echo "Subscription manifest not found: $SUBSCRIPTION_VAR_FILE" >&2
  exit 2
fi
manifest_directory=$(cd "$(dirname "$SUBSCRIPTION_VAR_FILE")" && pwd)
SUBSCRIPTION_VAR_FILE="$manifest_directory/$(basename "$SUBSCRIPTION_VAR_FILE")"

echo "Mode             : $MODE"
echo "Subscription file: $SUBSCRIPTION_VAR_FILE"
read -rp "This destroys the ENTIRE lab for this mode. Type 'destroy' to continue: " confirm
[[ "$confirm" == "destroy" ]] || { echo "Aborted."; exit 1; }

"$ROOT/scripts/init-backends.sh" --mode "$MODE"

echo "==> 20-platform"
(cd "$ROOT/terraform/20-platform" && $TF destroy -auto-approve -var-file="$SUBSCRIPTION_VAR_FILE")

echo "==> 10-governance"
# Terraform removes the association it manages before deleting its management
# groups. Azure does not promise to restore a subscription's previous parent;
# verify the resulting parent after destroy.
(cd "$ROOT/terraform/10-governance" && $TF destroy -auto-approve -var-file="$SUBSCRIPTION_VAR_FILE")

echo
echo "Management groups can take a few minutes to disappear from the portal."
echo "If a delete fails with 'not empty', check for subscriptions still"
echo "parented under it:  az account management-group show -n <name> -e -r"
echo "Also verify the surviving subscription's actual parent in the portal or"
echo "with: az account management-group subscription show --name <mg-id> --subscription <subscription-id>"
echo "The 00-bootstrap state storage is deliberately retained. Destroy it only"
echo "after both remote state files are no longer needed."
