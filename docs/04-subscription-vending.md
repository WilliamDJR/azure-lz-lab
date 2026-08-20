# 04 · Multi-subscription Bootstrap and Vending

[中文版](04-subscription-vending_cn.md)

This lab separates Azure billing placement from ALZ governance placement. They are related, but neither hierarchy automatically configures the other.

This chapter retains the enterprise multi-subscription route. If subscription creation returns `PurchaseNeedsReview`, do not substitute repeated IDs into the vending commands or keep retrying. Continue with the separate [single-subscription capability lab](05-single-subscription.md), then return here only if Azure later approves additional subscriptions.

## Current account quota and the safe allocation

Microsoft Support confirmed that this account has five historical subscription
records: one Active and four Deleted. The Deleted records still count toward
the account limit, so an increase to nine leaves **four creation slots**, not
nine usable new subscriptions. A new subscription that is later deleted also
continues to consume a slot according to the support response. Treat every
creation as effectively permanent for quota planning.

The quota-aware lab allocation is therefore:

| Actual subscription | Logical use in this repository | Lifecycle rule |
|---|---|---|
| Existing Active Sponsorship | Protected workload/experiment subscription | Keep it; do not delete or move it without an explicit owner-approved inventory and change plan |
| New 1 | Management | Create once, verify billing and cost attribution |
| New 2 | Connectivity | Create once, verify billing and cost attribution |
| New 3 | Identity | Create once; keep optional resources disabled |
| New 4 | Security | Create once; keep Sentinel disabled unless approved |

This gives four distinct platform subscriptions plus one existing workload
subscription. The logical workload roles (`corp_dev`, `corp_prod`, `online_*`
and `sandbox`) may reuse the protected subscription in the repository's
`quota-limited` profile; they are not separate billing, policy or quota
boundaries. The nine-role manifest remains a future/reference topology and is
not executable against this account without another quota increase.

## Two independent hierarchies

```text
MCA billing hierarchy                       Entra tenant resource hierarchy

Billing account                             Tenant Root Group
└── Billing profile                         └── ALZ intermediate root
    └── Invoice section                         ├── Platform
        ├── Management subscription             ├── Landing Zones
        ├── Connectivity subscription           ├── Sandbox
        └── ...                                 └── Decommissioned
```

- The **Billing Profile and Invoice Section** determine where subscription charges are invoiced and which eligible credit pool is consumed.
- The **Management Group** determines inherited Azure Policy and RBAC.
- Creating a subscription under the correct invoice section does not place it in the ALZ hierarchy.
- Moving a subscription between management groups does not change its billing profile.
- Management groups contain child management groups and subscriptions. Resource groups remain inside a subscription and cannot be placed directly under different management-group branches.

## Subscription model used by the lab

| Role | Management group | Intended contents |
|---|---|---|
| `management` | Platform / Management | Terraform state, central Log Analytics, operations services |
| `connectivity` | Platform / Connectivity | Hub VNet, Firewall, gateways, Private DNS |
| `identity` | Platform / Identity | Optional AD DS, sync, PKI, or identity-supporting infrastructure |
| `security` | Platform / Security | Optional Sentinel workspace and security-team-owned services |
| `corp_dev` | Landing Zones / Corp | Development workload and the lab spoke |
| `corp_prod` | Landing Zones / Corp | Production private workload boundary; intentionally empty in the lab |
| `online_dev` | Landing Zones / Online | Development internet-facing workload boundary; intentionally empty |
| `online_prod` | Landing Zones / Online | Production internet-facing workload boundary; intentionally empty |
| `sandbox` | Sandbox | Isolated experiments and the simulated on-premises VNet |

Separate development and production subscriptions give each environment an independent quota, cost, access, policy, and incident blast-radius boundary. Empty subscriptions are not a problem: the lab creates resources only where they teach a specific platform pattern.

## Safe creation sequence

1. In Cost Management + Billing, identify the intended MCA Billing Account, Billing Profile, and Invoice Section.
2. Confirm that the caller has the required invoice-section subscription-creation role and tenant permissions.
3. Create only the `management` subscription first.
4. Deploy a tiny eligible resource, wait for cost data, and confirm that charges reduce the intended sponsorship balance.
5. Create `connectivity`, `identity` and `security` only after that verification; never create disposable workload subscriptions for this lab.
6. Record the four new IDs plus the existing protected ID in `terraform/subscriptions.quota-limited.tfvars`; never commit that file.
7. Apply governance once with subscription movement disabled, inspect the plan and hierarchy, then enable placement.

The helper is a dry run by default:

```bash
./scripts/create-subscriptions.sh --role management
```

For an MCA, obtain the complete invoice-section billing scope from the portal or billing APIs. Do not store it in the repository.

```bash
export AZURE_BILLING_SCOPE='/providers/Microsoft.Billing/billingAccounts/<account>/billingProfiles/<profile>/invoiceSections/<section>'

# First subscription only
./scripts/create-subscriptions.sh --role management --execute

# After cost attribution has been verified, create the remaining platform roles
./scripts/create-subscriptions.sh --role platform --execute
```

The `platform` run selects only Management, Connectivity, Identity and Security.
The historical nine-role `--role all` run is guarded and requires an explicit
`--allow-nine-role-run`; do not use it for this account. Review every generated
ID and its billing relationship before any Terraform apply.

If the subscriptions already exist, do not run the creation helper. Copy `terraform/subscriptions.tfvars.example` to `terraform/subscriptions.tfvars` and enter the IDs manually.

## Sponsorship eligibility is separate from billing placement

A valid MCA Billing Profile and Invoice Section do not guarantee that the signed-in account may purchase another Azure subscription. Subscription creation is an account/offer eligibility decision made by Azure's billing backend.

- In the modernized Azure credits experience, credits are deposited on a Billing Profile and all subscriptions under that profile can use the credits. This does not remove the account's subscription-creation eligibility checks. [Azure sponsorship credits and Billing Profiles](https://learn.microsoft.com/partner-center/benefits/mpn-benefits-azure-cloud)
- In the legacy sponsorship redemption experience, redeeming the benefit creates a new sponsorship subscription; the credits cannot simply be applied to an existing pay-as-you-go subscription. [Azure credits activation guidance](https://learn.microsoft.com/partner-center/benefits/mpn-benefits-azure-cloud)
- For Microsoft Customer Agreement accounts purchased directly through Azure.com, Microsoft documents a maximum of five subscriptions and one new subscription per 24-hour period by default; creation also depends on consumption history and individual eligibility. [Multiple-subscription troubleshooting](https://learn.microsoft.com/azure/cost-management-billing/troubleshoot-subscription/create-subscriptions-deploy-resources)

`PurchaseNeedsReview` with `user is not eligible for an Azure account` means that Azure rejected the purchase before a subscription was created. It is not a Terraform, alias-name, or billing-scope syntax problem. Review the account at [aka.ms/AccountReview](https://aka.ms/AccountReview) and open an Azure Billing/Subscription Management support request if the review does not clear the block. Include the billing account, profile, invoice section, tenant ID, timestamp, and the complete error code, but do not share your billing scope publicly.

Until Azure permits another subscription, use one of these lab tracks:

1. **Single-subscription learning track:** keep the existing sponsorship subscription, create the ALZ management-group hierarchy, optionally place the one subscription under a single reviewed branch, and separate logical platform/workload roles with resource groups and tags. Follow the complete [single-subscription capability lab](05-single-subscription.md). This is not an enterprise subscription-isolation boundary.
2. **Quota-limited transition track:** create at most the four platform subscriptions above, keep the existing Sponsorship subscription as the protected workload subscription, and use the repository's quota-limited manifest. This validates platform boundaries without spending quota on disposable workload subscriptions. After removing only the manual lab resources, continue with the [official Accelerator exercise](06-alz-accelerator.md) using the four new platform IDs; leave the protected workload subscription outside the Accelerator transition.
3. **True nine-role track:** use an account/offer that is eligible to create enough additional subscriptions, or ask Microsoft to provision/clear the restriction. Only then use the nine-unique-ID Terraform reference topology.

Do not repeatedly retry `--role all`; the helper now stops with an explicit explanation when Azure returns `PurchaseNeedsReview`.

## Verify the first subscription before continuing

Do not treat the helper's summary as proof of success unless it contains a real subscription GUID. The `az account alias` command belongs to the Azure CLI `account` extension. The helper installs that extension before command substitution and rejects extension prompts or other text as IDs. The command reference documents the alias resource's `provisioningState` and `properties.subscriptionId` fields. [Azure CLI `az account alias`](https://learn.microsoft.com/cli/azure/account/alias?view=azure-cli-latest)

With the default prefix, the canonical management alias is `alzlab-platform-management` (the display name). The helper also checks the older short alias `alzlab-management` for compatibility. For the example alias, first check the alias itself:

```bash
az extension show --name account --only-show-errors >/dev/null 2>&1 || \
  az extension add --name account --only-show-errors

ALIAS_NAME='alzlab-platform-management'
SUBSCRIPTION_ID=$(az account alias show \
  --name "$ALIAS_NAME" \
  --query properties.subscriptionId \
  --output tsv \
  --only-show-errors)

if [[ ! "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "No valid subscription ID was returned. Do not continue." >&2
  exit 1
fi

az account alias show \
  --name "$ALIAS_NAME" \
  --query '{alias:name,state:properties.provisioningState,subscriptionId:properties.subscriptionId,displayName:properties.displayName,billingScope:properties.billingScope}' \
  --output json

az account list --refresh \
  --query "[?id=='$SUBSCRIPTION_ID'].{name:name,id:id,state:state,tenantId:tenantId}" \
  --output table

az account show --subscription "$SUBSCRIPTION_ID" \
  --query '{name:name,id:id,tenantId:tenantId,state:state}' \
  --output table
```

The alias state must be `Succeeded`, and Azure CLI must return the same GUID for `id`. If your output only contains text such as `The command requires the extension account`, no subscription ID was returned; the previous helper run must be treated as inconclusive, not as a successful reuse or creation.

### Verify the Billing Profile and Invoice Section

Parse the three identifiers from the exact `AZURE_BILLING_SCOPE` used for creation. Do not substitute a billing account, profile or invoice section from a different scope:

```bash
BILLING_SCOPE="${AZURE_BILLING_SCOPE:?Set AZURE_BILLING_SCOPE first}"
BILLING_ACCOUNT_ID="${BILLING_SCOPE#*/billingAccounts/}"
BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID%%/billingProfiles/*}"
BILLING_PROFILE_ID="${BILLING_SCOPE#*/billingProfiles/}"
BILLING_PROFILE_ID="${BILLING_PROFILE_ID%%/invoiceSections/*}"
INVOICE_SECTION_ID="${BILLING_SCOPE##*/invoiceSections/}"

printf 'Billing account:  %s\nBilling profile:  %s\nInvoice section:  %s\n' \
  "$BILLING_ACCOUNT_ID" "$BILLING_PROFILE_ID" "$INVOICE_SECTION_ID"

az billing account show \
  --name "$BILLING_ACCOUNT_ID" \
  --expand 'soldTo,billingProfiles,billingProfiles/invoiceSections' \
  --output json

az billing profile show \
  --account-name "$BILLING_ACCOUNT_ID" \
  --name "$BILLING_PROFILE_ID" \
  --expand invoiceSections \
  --output json

az billing account invoice-section show \
  --billing-account-name "$BILLING_ACCOUNT_ID" \
  --invoice-section-name "$INVOICE_SECTION_ID" \
  --expand billingProfiles \
  --output json

az billing subscription list \
  --account-name "$BILLING_ACCOUNT_ID" \
  --profile-name "$BILLING_PROFILE_ID" \
  --invoice-section-name "$INVOICE_SECTION_ID" \
  --output json
```

The last command must include the new `SUBSCRIPTION_ID`. Azure's billing CLI groups are currently preview APIs, so also confirm the same relationship in **Cost Management + Billing → Billing scopes → Invoice sections → Subscriptions**. Usage and sponsorship-credit attribution can take time to appear; after deploying a small test resource, verify the charge in Cost Management before vending the remaining subscriptions. The billing commands above are read-only. [Azure billing subscription CLI](https://learn.microsoft.com/cli/azure/billing/subscription?view=azure-cli-latest)

### Verify ALZ management-group placement later

Billing placement does not place a subscription in the ALZ hierarchy. After the governance Terraform root has created the hierarchy and `move_subscriptions_into_hierarchy` is intentionally enabled, verify the management-group relationship separately:

```bash
az account management-group subscription show \
  --name '<alz-intermediate-root-or-target-management-group-id>' \
  --subscription "$SUBSCRIPTION_ID" \
  --output json
```

Do not enable subscription movement until the plan shows the intended target management group.

## Enterprise vending workflow

The local script demonstrates the bootstrap mechanism. A mature platform exposes subscription vending as a reviewed product workflow:

```text
Request or pull request
  -> validate owner, environment, data class, region and network archetype
  -> create or reuse subscription under an approved billing scope
  -> place it under the correct management group
  -> assign Entra groups, not individual users
  -> set budgets, tags, policy and diagnostic defaults
  -> allocate non-overlapping IP space and connect the spoke when required
  -> publish the subscription ID and operating instructions
```

Use workload identity federation for the automation identity, apply least privilege at each scope, require plan review and production approval, and keep an auditable record of every vending request.

## Cost controls

- Configure budgets per subscription; a budget alerts but does not stop spend.
- Use conservative daily ingestion caps on learning workspaces.
- Keep Firewall, VPN gateways, test VMs, Defender plans, Sentinel connectors, and other billed features disabled until their exercise starts.
- Run `scripts/destroy-expensive.sh` at the end of a session.
- Review costs by subscription and service each day while the lab is active.
- Do not assume every Marketplace, support, reservation, or third-party charge is credit-eligible; confirm against the sponsorship terms and Cost Management data.

## Official references

- [Programmatically create MCA subscriptions](https://learn.microsoft.com/azure/cost-management-billing/manage/programmatically-create-subscription-microsoft-customer-agreement)
- [Subscription vending guidance](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/subscription-vending)
- [Management-group and subscription organization](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-management-groups)
