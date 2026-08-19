#!/usr/bin/env bash
#
# Safe subscription-vending helper for a Microsoft Customer Agreement (MCA).
# It is a dry run unless --execute is supplied. Start with --role management,
# verify that subscription's charges use the intended sponsorship credit, then
# run --role all. Existing aliases are reused instead of recreated.
#
set -euo pipefail

PREFIX="alzlab"
ROLE="all"
EXECUTE=false
BILLING_SCOPE="${AZURE_BILLING_SCOPE:-}"
SUBSCRIPTION_ID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

usage() {
  cat <<'EOF'
Usage:
  ./scripts/create-subscriptions.sh [--prefix alzlab] [--role management|all]
                                    [--billing-scope <MCA scope>] [--execute]

The billing scope has this form:
  /providers/Microsoft.Billing/billingAccounts/<account>/billingProfiles/<profile>/invoiceSections/<section>

Without --execute, the script only prints the subscriptions it would create.
Never commit a real billing scope or generated subscriptions.tfvars file.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --billing-scope) BILLING_SCOPE="$2"; shift 2 ;;
    --execute) EXECUTE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

all_roles=(management connectivity identity security corp_dev corp_prod online_dev online_prod sandbox)
if [[ "$ROLE" == "all" ]]; then
  selected_roles=("${all_roles[@]}")
elif [[ " ${all_roles[*]} " == *" $ROLE "* ]]; then
  selected_roles=("$ROLE")
else
  echo "--role must be one of: management, connectivity, identity, security, corp_dev, corp_prod, online_dev, online_prod, sandbox, all" >&2
  exit 2
fi

display_name() {
  case "$1" in
    management) echo "$PREFIX-platform-management" ;;
    connectivity) echo "$PREFIX-platform-connectivity" ;;
    identity) echo "$PREFIX-platform-identity" ;;
    security) echo "$PREFIX-platform-security" ;;
    corp_dev) echo "$PREFIX-corp-dev" ;;
    corp_prod) echo "$PREFIX-corp-prod" ;;
    online_dev) echo "$PREFIX-online-dev" ;;
    online_prod) echo "$PREFIX-online-prod" ;;
    sandbox) echo "$PREFIX-sandbox" ;;
  esac
}

extract_subscription_id() {
  local output="$1"
  local line
  while IFS= read -r line; do
    if [[ "$line" =~ $SUBSCRIPTION_ID_RE ]]; then
      printf '%s\n' "$line"
      return 0
    fi
  done <<<"$output"
  return 1
}

if [[ "$EXECUTE" != true ]]; then
  echo "DRY RUN: no subscription will be created."
  echo "Use --execute only after confirming the Billing Profile and Invoice Section."
  echo
  for role in "${selected_roles[@]}"; do
    echo "$role -> $(display_name "$role") (alias: $(display_name "$role"))"
  done
  exit 0
fi

if [[ -z "$BILLING_SCOPE" ]]; then
  echo "Set AZURE_BILLING_SCOPE or pass --billing-scope before using --execute." >&2
  exit 2
fi

if [[ ! "$BILLING_SCOPE" =~ ^/providers/Microsoft\.Billing/billingAccounts/.+/billingProfiles/.+/invoiceSections/.+$ ]]; then
  echo "The billing scope does not look like a complete MCA invoice-section scope." >&2
  exit 2
fi

if ! az extension show --name account --only-show-errors >/dev/null 2>&1; then
  echo "Installing the Azure CLI account extension required by az account alias..."
  az extension add --name account --only-show-errors
fi

az account show --only-show-errors >/dev/null

declare -A subscription_ids
for role in "${selected_roles[@]}"; do
  name=$(display_name "$role")
  # The display name is the canonical alias. The short form is checked as a
  # compatibility fallback for subscriptions created by an earlier helper.
  alias_name="$name"
  legacy_alias_name="$PREFIX-${role//_/-}"

  for candidate_alias in "$alias_name" "$legacy_alias_name"; do
    existing_output=$(az account alias show \
      --name "$candidate_alias" \
      --query properties.subscriptionId \
      -o tsv \
      --only-show-errors 2>/dev/null || true)
    if existing_id=$(extract_subscription_id "$existing_output"); then
      echo "Reusing $name ($candidate_alias): $existing_id"
      subscription_ids[$role]="$existing_id"
      break
    fi
  done
  if [[ -n "${subscription_ids[$role]:-}" ]]; then
    continue
  fi

  echo "Creating $name under the supplied Billing Profile and Invoice Section..."
  create_output=$(az account alias create \
    --name "$alias_name" \
    --display-name "$name" \
    --billing-scope "$BILLING_SCOPE" \
    --workload Production \
    --query properties.subscriptionId \
    -o tsv \
    --only-show-errors 2>&1) || {
      echo "$create_output" >&2
      exit 1
    }

  if ! created_id=$(extract_subscription_id "$create_output"); then
    echo "The alias command did not return a subscription GUID for $name." >&2
    echo "Raw command output:" >&2
    echo "$create_output" >&2
    exit 1
  fi
  subscription_ids[$role]="$created_id"
done

echo
echo "Created or discovered subscription IDs:"
for role in "${selected_roles[@]}"; do
  printf '  %-14s %s\n' "$role" "${subscription_ids[$role]}"
done

if [[ "$ROLE" == "all" ]]; then
  output_file="$(dirname "$0")/../terraform/subscriptions.tfvars"
  if [[ -e "$output_file" ]]; then
    echo
    echo "Refusing to overwrite existing $output_file. Update it manually with the IDs above."
    exit 0
  fi

  {
    echo "subscription_ids = {"
    for role in "${all_roles[@]}"; do
      printf '  %-14s = "%s"\n' "$role" "${subscription_ids[$role]}"
    done
    echo "}"
  } >"$output_file"
  chmod 600 "$output_file"
  echo
  echo "Wrote local subscription manifest: $output_file"
fi
