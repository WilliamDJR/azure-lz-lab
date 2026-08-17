#!/usr/bin/env bash
# Initialises the governance and platform roots against the state storage
# created by terraform/00-bootstrap. Each root gets an independent state key.
set -euo pipefail

ROOT="$(dirname "$0")/.."
TF=${TF:-terraform}
BOOTSTRAP="$ROOT/terraform/00-bootstrap"

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

init_root "$ROOT/terraform/10-governance" "10-governance.tfstate"
init_root "$ROOT/terraform/20-platform" "20-platform.tfstate"

echo "Remote backends initialised with separate state keys."
