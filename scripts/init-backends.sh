#!/usr/bin/env bash
# Initialises the governance and platform roots against the state storage
# created by terraform/00-bootstrap. Each root gets an independent state key.
set -euo pipefail

ROOT="$(dirname "$0")/.."
TF=${TF:-terraform}
BOOTSTRAP="$ROOT/terraform/00-bootstrap"
MODE="multi"

usage() {
  cat <<'EOF'
Usage: ./scripts/init-backends.sh [--mode multi|single|quota-limited]

The modes use different backend keys so single-subscription and
quota-limited deployments are never silently repointed at the nine-role
multi-subscription Terraform state.
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
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

case "$MODE" in
  multi) STATE_SUFFIX="" ;;
  single) STATE_SUFFIX="-single" ;;
  quota-limited) STATE_SUFFIX="-quota-limited" ;;
  *) echo "--mode must be multi, single or quota-limited" >&2; exit 2 ;;
esac

resource_group=$($TF -chdir="$BOOTSTRAP" output -raw state_resource_group_name)
storage_account=$($TF -chdir="$BOOTSTRAP" output -raw state_storage_account_name)
container=$($TF -chdir="$BOOTSTRAP" output -raw state_container_name)

init_root() {
  local directory=$1
  local key=$2

  $TF -chdir="$directory" init -reconfigure \
    -backend-config="resource_group_name=$resource_group" \
    -backend-config="storage_account_name=$storage_account" \
    -backend-config="container_name=$container" \
    -backend-config="key=$key" \
    -backend-config="use_azuread_auth=true"
}

init_root "$ROOT/terraform/10-governance" "10-governance${STATE_SUFFIX}.tfstate"
init_root "$ROOT/terraform/20-platform" "20-platform${STATE_SUFFIX}.tfstate"

echo "Remote backends initialised for $MODE mode with separate state keys."
