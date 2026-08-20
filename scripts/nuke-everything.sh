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
Usage: ./scripts/nuke-everything.sh [--mode multi|single|quota-limited] [--var-file PATH]

The mode selects the matching remote-state keys before destroy. The default
manifests are terraform/subscriptions.tfvars for multi,
terraform/subscriptions.single.tfvars for single and
terraform/subscriptions.quota-limited.tfvars for quota-limited.
SUBSCRIPTION_VAR_FILE or --var-file can override the manifest path.

This script never deletes subscriptions. In quota-limited mode it removes only
resources recorded in the manual Terraform states; it must not be used to
clean up an official Accelerator deployment.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "--mode requires multi, single or quota-limited" >&2
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
  quota-limited)
    default_var_file="$ROOT/terraform/subscriptions.quota-limited.tfvars"
    ;;
  *)
    echo "--mode must be multi, single or quota-limited" >&2
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
echo "This removes only resources recorded in the manual Terraform states."
echo "It does not delete subscriptions, billing records, or resources outside those states."
if [[ "$MODE" == "quota-limited" ]]; then
  echo "The workload subscription may contain organizational resources; review both destroy plans carefully."
fi
read -rp "Type 'destroy-lab-resources' to continue: " confirm
[[ "$confirm" == "destroy-lab-resources" ]] || { echo "Aborted."; exit 1; }

"$ROOT/scripts/init-backends.sh" --mode "$MODE"

plan_and_apply_destroy() {
  local directory=$1
  local label=$2
  local plan_file
  plan_file=$(mktemp "${TMPDIR:-/tmp}/alz-${MODE}-${label}.XXXXXX")
  trap 'rm -f "$plan_file"' RETURN

  echo "==> $label destroy plan"
  (cd "$directory" && $TF plan -destroy -var-file="$SUBSCRIPTION_VAR_FILE" -out="$plan_file")
  (cd "$directory" && $TF show "$plan_file")
  read -rp "Review complete. Type 'apply-destroy' to apply this $label plan: " apply_confirm
  [[ "$apply_confirm" == "apply-destroy" ]] || { echo "Aborted before $label changes."; exit 1; }
  (cd "$directory" && $TF apply "$plan_file")
  rm -f "$plan_file"
  trap - RETURN
}

# Platform must go first. The plan review is intentional: in quota-limited
# mode the existing workload subscription may contain organization resources.
plan_and_apply_destroy "$ROOT/terraform/20-platform" "20-platform"

# Terraform removes only the governance resources recorded in this state,
# including its association and management-group Policies. Azure does not
# promise to restore a subscription's previous parent; verify it afterwards.
plan_and_apply_destroy "$ROOT/terraform/10-governance" "10-governance"

echo
echo "Management groups can take a few minutes to disappear from the portal."
echo "If a delete fails with 'not empty', check for subscriptions still"
echo "parented under it:  az account management-group show -n <name> -e -r"
echo "Also verify the surviving subscription's actual parent in the portal or"
echo "with: az account management-group subscription show --name <mg-id> --subscription <subscription-id>"
echo "The 00-bootstrap state storage is deliberately retained. Destroy it only"
echo "after both remote state files are no longer needed."
