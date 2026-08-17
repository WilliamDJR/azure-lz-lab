# 04 · Multi-subscription Bootstrap and Vending

[中文版](04-subscription-vending_cn.md)

This lab separates Azure billing placement from ALZ governance placement. They are related, but neither hierarchy automatically configures the other.

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
5. Create the remaining role subscriptions only after that verification.
6. Record subscription IDs in `terraform/subscriptions.tfvars`; never commit that file.
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

# After cost attribution has been verified
./scripts/create-subscriptions.sh --role all --execute
```

The all-role run reuses an existing alias and writes `terraform/subscriptions.tfvars` only when that file does not already exist. Review the generated IDs before any Terraform apply.

If the subscriptions already exist, do not run the creation helper. Copy `terraform/subscriptions.tfvars.example` to `terraform/subscriptions.tfvars` and enter the IDs manually.

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

