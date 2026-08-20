# Azure Landing Zone Enterprise Lab

[中文版](README_cn.md)

This repository is organized as **foundations first, deployment and validation second**. It supports both a constrained one-subscription capability lab and an enterprise-shaped multi-subscription Azure Landing Zone (ALZ), while keeping expensive services optional and short-lived.

Important billing constraint: an Azure Sponsorship credit balance and permission to create additional subscriptions are separate capabilities. Some sponsorship, promotional, MOSP, or newly created MCA accounts reject a second subscription with `PurchaseNeedsReview`. Read the [subscription vending guide](docs/04-subscription-vending.md) before attempting multi-subscription creation.

## Choose the route that matches the available subscriptions

| Available subscriptions | Route | Outcome |
|---|---|---|
| One existing subscription | [Single-subscription capability lab](docs/05-single-subscription.md) | Deploy the manual Terraform implementation with logical role resource groups; practise governance, Policy, networking, observability and delivery without claiming subscription isolation |
| Two subscriptions | Official Accelerator SMB scenario with Management + Connectivity | Use the official wizard rather than this repository's four-subscription wrapper; plan Identity and Security subscriptions for later |
| Existing Active subscription plus up to four new subscriptions | Quota-limited transition route below, then the [full Accelerator exercise](docs/06-alz-accelerator.md) | Reuse the existing subscription as a protected workload/experiment boundary and reserve the four new subscriptions for Management, Connectivity, Identity and Security |
| Four dedicated platform subscriptions plus workload subscriptions | Multi-subscription route below, followed by the [full Accelerator exercise](docs/06-alz-accelerator.md) | Validate enterprise subscription placement, cross-subscription permissions and platform/workload boundaries. The manual topology below requires nine unique role IDs. |

The official Accelerator currently recommends four platform subscriptions and documents two as the SMB minimum. One subscription is supported by this repository's manual capability lab, not as an official Accelerator deployment topology. [Official planning guidance](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/)

For this account, Microsoft Support confirmed that four historical Deleted
records still count toward the subscription limit. Raising the limit to nine
therefore leaves four creation slots; deleting a newly created subscription
does not return a slot. The existing Active Sponsorship subscription is
protected and must not be deleted or treated as disposable lab capacity.

The multi-subscription target is intentionally smaller than a production ALZ, but its boundaries are realistic: billing and governance are separate, platform capabilities have dedicated subscriptions, development and production have separate workload subscriptions, Terraform state is remote, and every Azure CLI operation is subscription-aware.

## What the lab now covers

| ALZ design area | Lab coverage |
|---|---|
| Billing and tenant | MCA Billing Profile/Invoice Section bootstrap, multi-subscription manifest, staged subscription creation |
| Identity and access | Management-group RBAC inputs, managed identities, pipeline federation; PIM remains a manual extension |
| Resource organization | Intermediate root, Platform, Security, Corp, Online, Sandbox and Decommissioned; nine real role subscriptions or one logically partitioned subscription |
| Network and connectivity | Cross-subscription or single-subscription Hub-Spoke, UDR, Firewall, VPN Gateway, Private Endpoint, and centralized Private DNS |
| Security | Policy, NSG, Firewall, private access, optional dedicated Sentinel workspace |
| Management and operations | Central Log Analytics, diagnostics, KQL, daily ingestion caps, subscription budgets |
| Governance | Audit, Deny, DINE, compliance and remediation patterns |
| Platform automation | Remote Terraform state, provider aliases, reusable Azure Pipelines example, safe cleanup scripts |

## Multi-subscription target architecture

```text
MCA Billing Profile + Invoice Section (shared eligible credit pool)
  ├── Management subscription ───── Log Analytics + Terraform state
  ├── Connectivity subscription ─── Hub + Firewall + VPN + Private DNS
  ├── Identity subscription ──────── reserved identity infrastructure boundary
  ├── Security subscription ──────── optional Sentinel workspace
  ├── Corp Dev subscription ──────── lab workload spoke + private storage
  ├── Corp Prod subscription ─────── governed production boundary
  ├── Online Dev subscription ────── governed internet-workload boundary
  ├── Online Prod subscription ───── governed production boundary
  └── Sandbox subscription ───────── isolated experiments / simulated on-premises

Entra tenant
└── ALZ intermediate root
    ├── Platform
    │   ├── Management
    │   ├── Connectivity
    │   ├── Identity
    │   └── Security
    ├── Landing Zones
    │   ├── Corp       (Dev and Prod subscriptions)
    │   └── Online     (Dev and Prod subscriptions)
    ├── Sandbox
    └── Decommissioned
```

Billing placement controls invoice and credit attribution. Management-group placement controls inherited Policy and RBAC. Changing one does not change the other.

## Repository map

```text
docs/
  01-ALZ-concepts.md
  02-networking.md
  03-azure-devops.md
  04-subscription-vending.md
  05-single-subscription.md
  06-alz-accelerator.md

accelerator/
  prepare-config.ps1             generate reviewed official local inputs
  deploy-accelerator.ps1          preview or explicitly run the bootstrap

terraform/
  subscriptions.tfvars.example   shared role-to-subscription manifest
  subscriptions.single.tfvars.example
                                  one-subscription role manifest
  subscriptions.quota-limited.tfvars.example
                                  four platform IDs + protected workload ID
  00-bootstrap/                   protected remote state storage
  10-governance/                  management groups, Policy, RBAC, budgets
  20-platform/                    resources deployed across role subscriptions

scripts/
  create-subscriptions.sh         dry-run-first MCA subscription vending
  init-backends.sh                initialise separate remote state keys
  test-private-dns.sh             validate Private Endpoint DNS from Corp Dev
  test-egress.sh                  compare default and Firewall egress
  show-effective-routes.sh        inspect Corp Dev effective routes
  destroy-expensive.sh            remove billed session resources
  nuke-everything.sh              remove platform and governance roots
```

# Part 1: Foundations

Read these in order before applying Terraform:

1. [ALZ concepts and governance](docs/01-ALZ-concepts.md): subscriptions as management boundaries, the management-group hierarchy, Policy effects, and platform ownership.
2. [Enterprise Azure networking](docs/02-networking.md): Hub-Spoke routing, peering, Firewall, hybrid connectivity, Private Endpoint and DNS.
3. [Azure DevOps and operations](docs/03-azure-devops.md): Terraform delivery, approvals, workload identity federation, diagnostic settings and KQL.
4. [Multi-subscription bootstrap and vending](docs/04-subscription-vending.md): MCA billing scope, safe creation order, subscription roles, vending and cost controls.
5. [Single-subscription capability lab](docs/05-single-subscription.md): executable fallback, logical role boundaries, Policy inheritance, networking, validation, cleanup and later migration.
6. [Microsoft ALZ IaC Accelerator](docs/06-alz-accelerator.md): official production-oriented bootstrap, AVM/Policy configuration, generated delivery assets, cost review, upgrades and cleanup.

Checkpoints before deployment:

- Explain why Billing Profile placement and Management Group placement are independent.
- Place a new private workload into the correct role subscription and management group.
- Draw the traffic and DNS path from Corp Dev to the private Storage endpoint.
- Explain why DINE needs both a managed identity and RBAC.
- Identify which resources are billed continuously and how they will be removed.

# Part 2Q: Quota-limited platform route

When the account has four creation slots but the existing Sponsorship
subscription contains organization resources, use the four new subscriptions
for the platform roles and keep the existing subscription as the protected
workload/experiment subscription. This is the maximum useful expansion without
spending irreversible quota on disposable workload subscriptions.

```bash
cp terraform/subscriptions.quota-limited.tfvars.example terraform/subscriptions.quota-limited.tfvars
cp terraform/00-bootstrap/terraform.quota-limited.tfvars.example terraform/00-bootstrap/terraform.tfvars
cp terraform/10-governance/terraform.quota-limited.tfvars.example terraform/10-governance/terraform.tfvars
cp terraform/20-platform/terraform.quota-limited.tfvars.example terraform/20-platform/terraform.tfvars
./scripts/init-backends.sh --mode quota-limited
```

Replace the five placeholders only after confirming all four new subscriptions
are Active and tied to the intended Billing Profile and Invoice Section. Keep
`move_subscriptions_into_hierarchy = false` until the owner of the existing
Sponsorship subscription approves inheritance of management-group Policy. Run
both roots with `plan`, review the target subscriptions and resource groups,
then apply the low-cost baseline. All lab resource groups are uniquely named
and tagged `lab=true`; never select an organization resource group as a target.
If that owner later approves inheritance, set
`allow_protected_workload_policy_inheritance = true` in the Governance vars in
the same reviewed change; otherwise Terraform refuses the move.

This route has four distinct platform subscriptions plus one existing
workload subscription. The workload roles are logical labels only, and the
governance root creates at most one Corp parent association for the repeated
workload ID. The four new platform subscriptions are the IDs to use for the
official Accelerator; leave the protected workload subscription outside the
Accelerator platform input and cleanup.

At the end of a session, disable billed features first. For full manual cleanup,
use the matching state and inspect the destroy plans:

```bash
./scripts/destroy-expensive.sh
./scripts/nuke-everything.sh --mode quota-limited
```

The script deletes only resources recorded in the manual Terraform states. It
never deletes subscriptions. Stop if a destroy plan includes an organization
resource, diagnostic setting, lock or resource group.

# Part 2: Multi-subscription deployment and validation

The steps below are the nine-role reference route and require all nine
role-subscription IDs to be unique. It is not the current quota-limited default.
If only one subscription is available, follow [Part 05](docs/05-single-subscription.md);
if four creation slots remain, follow Part 2Q above.

## 0. Prerequisites and safety

Required locally:

- Azure CLI, Terraform `>= 1.5, < 2.0`, Git, and Bash.
- Permission to create resources and role assignments in the role subscriptions.
- Tenant permissions for management groups, management-group Policy, and subscription association.
- MCA invoice-section subscription-creation permission only if the helper will create subscriptions.

```bash
az version
terraform version
az login
az account show --query '{name:name,id:id,tenantId:tenantId}' --output table
```

Use a lab tenant or explicitly approved tenant. Never paste a real Billing Scope, subscription manifest, secret, or saved plan into Git. Review current Azure prices and sponsorship eligibility before enabling billed services.

## 1. Prepare the subscriptions

Read [the subscription vending guide](docs/04-subscription-vending.md) first. If Azure permits another subscription, create only Management, deploy a tiny eligible resource, and verify credit attribution before creating the remaining subscriptions. If Azure returns `PurchaseNeedsReview`, stop and use the documented single-subscription track or request an account review.

Preview the helper without changing Azure:

```bash
./scripts/create-subscriptions.sh --role management
```

If the subscriptions already exist, create the local manifest manually:

```bash
cp terraform/subscriptions.tfvars.example terraform/subscriptions.tfvars
```

Replace all placeholders and verify that all nine IDs are unique. This file is ignored by Git.

## 2. Bootstrap remote Terraform state

The bootstrap root uses local state because it creates the remote state store itself. It places the storage account in Management, disables shared-key authentication, uses Microsoft Entra authentication, enables versioning and soft delete, and creates a private container.

```bash
cd terraform/00-bootstrap
cp terraform.tfvars.example terraform.tfvars
# Set management_subscription_id to the Management subscription.

terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
cd ../..

./scripts/init-backends.sh --mode multi
```

Azure RBAC propagation can delay first access to the container. If the role assignment was created successfully but container access is initially denied, wait briefly and apply again.

Do not delete `00-bootstrap` while either remote state file is in use.

## 3. Deploy governance safely

```bash
cd terraform/10-governance
cp terraform.tfvars.example terraform.tfvars
```

Use these safe first-run values:

```hcl
move_subscriptions_into_hierarchy = false
public_ip_policy_effect            = "Audit"
enforce_allowed_locations_policy   = false
```

```bash
terraform fmt -check
terraform validate
terraform plan -var-file=../subscriptions.tfvars -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Inspect the hierarchy and Policy assignments in the portal before moving any subscription. The Allowed Locations assignment starts in `DoNotEnforce` mode because it would otherwise affect every resource in each moved subscription. Inventory current regions and update `allowed_locations` before deliberately enabling it. Management-group and Policy propagation can take time.

To enable per-subscription budgets, set `budget_start_date` to the first day of the current month, configure amounts and contact emails, then review another plan. Budgets alert; they do not stop consumption.

## 4. Deploy the baseline platform

```bash
cd ../20-platform
cp terraform.tfvars.example terraform.tfvars
```

Keep the expensive features off initially:

```hcl
enable_firewall         = false
enable_vpn_gateway      = false
enable_simulated_onprem = false
enable_sentinel         = false
enable_test_vm          = true
```

```bash
terraform fmt -check
terraform validate
terraform plan -var-file=../subscriptions.tfvars -out=tfplan
terraform show tfplan
terraform apply tfplan
terraform output
```

The baseline creates Management logging, the Connectivity Hub and Private DNS zone, a Corp Dev spoke and private Storage endpoint, and a private test VM. Cross-subscription peering and DNS links are created with explicit provider aliases. It is low-cost, not free: the VM, disk, Storage, Private Endpoint and log ingestion can all generate charges.

## 5. Connect central logging and place subscriptions

Get the central workspace ID:

```bash
terraform output -raw log_analytics_workspace_id
```

Set that value as `log_analytics_workspace_id` in `terraform/10-governance/terraform.tfvars`. Review and apply governance again. This enables the DINE Activity Log assignment, its managed identity and the RBAC role required for remediation.

After checking every ID and target management group, change:

```hcl
move_subscriptions_into_hierarchy = true
```

Plan, review, and apply the governance root with `-var-file=../subscriptions.tfvars`. Confirm all nine subscriptions appear in their intended management groups. Then trigger a compliance scan, create a remediation task for `activity-log-to-law`, and verify that each subscription receives an Activity Log diagnostic setting pointing to the Management workspace. The [single-subscription DINE exercise](docs/05-single-subscription.md) provides the complete CLI sequence; the same assignment/evaluation/remediation pattern applies at management-group scope here.

## 6. Validate Private DNS and routing

From the repository root:

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-baseline.txt
./scripts/test-private-dns.sh
```

The expected answer is a public Azure CNAME followed by a private `10.1.1.x` A record from `privatelink.blob.core.windows.net`.

For a controlled failure exercise, remove only the spoke DNS link, run the test, then restore it:

```bash
terraform -chdir=terraform/20-platform destroy \
  -var-file=../subscriptions.tfvars \
  -target=azurerm_private_dns_zone_virtual_network_link.blob_to_spoke

./scripts/test-private-dns.sh

terraform -chdir=terraform/20-platform apply \
  -var-file=../subscriptions.tfvars
```

Use `-target` only for this exercise.

## 7. Mature Policy from Audit to Deny

Set `public_ip_policy_effect = "Deny"`, review the governance plan, and apply. After Policy propagation, deliberately attempt a public-IP deployment in Corp Dev, specifying that subscription explicitly:

```bash
CORP_DEV=$(terraform -chdir=terraform/20-platform output -raw corp_dev_subscription_id)

az group create --subscription "$CORP_DEV" \
  --name rg-alz-policy-test --location australiaeast

az vm create --subscription "$CORP_DEV" \
  --resource-group rg-alz-policy-test \
  --name vm-should-fail \
  --image Ubuntu2404 \
  --public-ip-address pip-policy-test \
  --generate-ssh-keys

az group delete --subscription "$CORP_DEV" \
  --name rg-alz-policy-test --yes --no-wait
```

Inspect the assignment and definition IDs in the denial. If the deployment succeeds, verify subscription placement and wait for Policy propagation before retrying.

## 8. Run time-boxed paid exercises

### Firewall and forced tunnelling

Set `enable_firewall = true`, plan and apply with the subscription var file, then compare routes:

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-firewall.txt
diff -u /tmp/alz-routes-baseline.txt /tmp/alz-routes-firewall.txt
./scripts/test-egress.sh
```

Use the KQL in [the operations guide](docs/03-azure-devops.md) to inspect Firewall decisions.

### Simulated hybrid connectivity

After removing Firewall, enable both gateway switches:

```hcl
enable_vpn_gateway      = true
enable_simulated_onprem = true
enable_test_vm          = true
```

`destroy-expensive.sh` removes the test VM and NIC as well as Firewall, so recreate the VM when starting this phase in a later session; its NIC is required for effective-route inspection. Gateway provisioning can take a long time and both gateways are billed while present. Inspect peering gateway transit and effective routes, then remove them immediately.

### Security subscription

Set `enable_sentinel = true` only for the Sentinel onboarding exercise. The code creates a separate Security workspace with a daily quota; data connectors and Defender plans are intentionally not enabled automatically.

At the end of every paid session:

```bash
./scripts/destroy-expensive.sh
```

Also keep the switches false in `terraform/20-platform/terraform.tfvars` so the next apply does not recreate the resources.

## 9. Run the delivery pipeline

Follow [the Azure Pipelines lab](azure-devops/README.md). For an enterprise implementation, use workload identity federation, separate plan and apply identities, protected environments, saved plan artifacts, remote state, and a scheduled drift-detection plan.

## 10. Cleanup

```bash
./scripts/nuke-everything.sh --mode multi
```

This destroys Platform first and Governance second. It deliberately retains the bootstrap storage and subscriptions. Delete the state store only after both state files are no longer needed; cancel or reuse subscriptions through the billing process rather than treating them as ordinary Terraform resources.

# Part 3: Official Accelerator path

The official path has a subscription gate. Do not bypass it by reusing one subscription ID for several platform roles:

| Available platform subscriptions | Accelerator action |
|---|---|
| One | Generate and review official configuration only. Do not run `Deploy-Accelerator` or Phase 3 apply; keep actual Azure deployment on this repository's single-subscription track. |
| Management + Connectivity | Use official SMB scenario 10 or 11 through the official workflow. The local wrappers below do not implement the two-subscription model. |
| Management + Connectivity + Identity + Security | Follow the [full Accelerator hands-on lab](docs/06-alz-accelerator.md). The four IDs supplied to the local wrapper must be distinct. |

After cleaning up the manual implementation and confirming the four-subscription gate, generate a fresh official configuration. The helpers call the official `New-AcceleratorFolderStructure` and `Deploy-Accelerator` commands with additional validation:

```powershell
pwsh ./accelerator/prepare-config.ps1 `
  -ManagementSubscriptionId "<management-subscription-id>" `
  -ConnectivitySubscriptionId "<connectivity-subscription-id>" `
  -IdentitySubscriptionId "<identity-subscription-id>" `
  -SecuritySubscriptionId "<security-subscription-id>" `
  -DefenderSecurityContact "<security-contact@example.com>" `
  -ScenarioNumber 5 `
  -InstallOrUpdateAlzModule

# Preview only; add -Execute after reviewing every generated file and cost setting.
pwsh ./accelerator/deploy-accelerator.ps1
```

The manual Terraform roots and Accelerator are separate implementations. Do not let both manage the same hierarchy or resources. The [Accelerator guide](docs/06-alz-accelerator.md) covers the one-subscription review-only exercise, two-subscription SMB route, full four-subscription workflow, cost approvals, upgrades and two-stage cleanup.

## Production gaps and next extensions

The lab is enterprise-shaped, not production-ready. A production program should evaluate:

- Promotion of the [Accelerator exercise](docs/06-alz-accelerator.md) into a reviewed platform repository with pinned versions, release management and environment-specific approvals.
- Entra groups, PIM, access reviews, break-glass accounts, custom roles, and separation of platform identities.
- Azure Policy initiatives, assignment archetypes, automated remediation and expiring exemptions.
- Defender for Cloud, Sentinel data connectors, Key Vault, customer-managed keys and security incident integration.
- DNS Private Resolver, DDoS Network Protection, multi-region hubs, ExpressRoute, IPAM and network watcher controls.
- Alert rules, action groups, backup, recovery testing, service health and platform SLOs.
- A reviewed subscription-vending pipeline with CMDB/IPAM integration and lifecycle decommissioning.
- Production resilience, quotas, availability zones, data residency, regulatory controls and disaster recovery.

Prefer the official [Azure Landing Zone IaC Accelerator](https://azure.github.io/Azure-Landing-Zones/terraform/) when moving from this teaching implementation to an organizational platform.
