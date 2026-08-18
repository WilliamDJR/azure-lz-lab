# Azure Landing Zone Enterprise Lab

[中文版](README_cn.md)

This repository is organized as **foundations first, deployment and validation second**. It builds an enterprise-shaped Azure Landing Zone (ALZ) across multiple subscriptions while keeping expensive services optional and short-lived.

The lab is intentionally smaller than a production ALZ, but its boundaries are realistic: billing and governance are separate, platform capabilities have dedicated subscriptions, development and production have separate workload subscriptions, Terraform state is remote, and every Azure CLI operation is subscription-aware.

## What the lab now covers

| ALZ design area | Lab coverage |
|---|---|
| Billing and tenant | MCA Billing Profile/Invoice Section bootstrap, multi-subscription manifest, staged subscription creation |
| Identity and access | Management-group RBAC inputs, managed identities, pipeline federation; PIM remains a manual extension |
| Resource organization | Intermediate root, Platform, Security, Corp, Online, Sandbox, Decommissioned, and nine role subscriptions |
| Network and connectivity | Cross-subscription Hub-Spoke, UDR, Firewall, VPN Gateway, Private Endpoint, and centralized Private DNS |
| Security | Policy, NSG, Firewall, private access, optional dedicated Sentinel workspace |
| Management and operations | Central Log Analytics, diagnostics, KQL, daily ingestion caps, subscription budgets |
| Governance | Audit, Deny, DINE, compliance and remediation patterns |
| Platform automation | Remote Terraform state, provider aliases, reusable Azure Pipelines example, safe cleanup scripts |

## Target architecture

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
  05-alz-accelerator.md

accelerator/
  prepare-config.ps1             generate reviewed official local inputs
  deploy-accelerator.ps1          preview or explicitly run the bootstrap

terraform/
  subscriptions.tfvars.example   shared role-to-subscription manifest
  00-bootstrap/                   protected remote state storage
  10-governance/                  management groups, Policy, RBAC, budgets
  20-platform/                    resources deployed across role subscriptions

scripts/
  create-subscriptions.sh         dry-run-first MCA subscription vending
  init-backends.sh                initialise separate remote state keys
  test-private-dns.sh             validate Private Endpoint DNS from Corp Dev
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
5. [Microsoft ALZ IaC Accelerator](docs/05-alz-accelerator.md): official production-oriented bootstrap, AVM/Policy configuration, generated delivery assets, cost review, upgrades and cleanup.

Checkpoints before deployment:

- Explain why Billing Profile placement and Management Group placement are independent.
- Place a new private workload into the correct role subscription and management group.
- Draw the traffic and DNS path from Corp Dev to the private Storage endpoint.
- Explain why DINE needs both a managed identity and RBAC.
- Identify which resources are billed continuously and how they will be removed.

# Part 2: Deployment and validation

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

Read [the subscription vending guide](docs/04-subscription-vending.md) first. The safest path is to create only Management, deploy a tiny eligible resource, and verify credit attribution before creating the remaining subscriptions.

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

./scripts/init-backends.sh
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
```

```bash
terraform fmt -check
terraform validate
terraform plan -var-file=../subscriptions.tfvars -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Inspect the hierarchy and Policy assignments in the portal before moving any subscription. Management-group and Policy propagation can take time.

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

The baseline creates Management logging, the Connectivity Hub and Private DNS zone, a Corp Dev spoke and private Storage endpoint, and a private test VM. Cross-subscription peering and DNS links are created with explicit provider aliases.

## 5. Connect central logging and place subscriptions

Get the central workspace ID:

```bash
terraform output -raw log_analytics_workspace_id
```

Set that value as `log_analytics_workspace_id` in `terraform/10-governance/terraform.tfvars`. Review and apply governance again. This enables the DINE Activity Log assignment and its remediation identity.

After checking every ID and target management group, change:

```hcl
move_subscriptions_into_hierarchy = true
```

Plan, review, and apply the governance root with `-var-file=../subscriptions.tfvars`. Confirm all nine subscriptions appear in their intended management groups.

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
```

Use the KQL in [the operations guide](docs/03-azure-devops.md) to inspect Firewall decisions.

### Simulated hybrid connectivity

After removing Firewall, enable both gateway switches:

```hcl
enable_vpn_gateway      = true
enable_simulated_onprem = true
```

Gateway provisioning can take a long time and both gateways are billed while present. Inspect peering gateway transit and effective routes, then remove them immediately.

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
./scripts/nuke-everything.sh
```

This destroys Platform first and Governance second. It deliberately retains the bootstrap storage and subscriptions. Delete the state store only after both state files are no longer needed; cancel or reuse subscriptions through the billing process rather than treating them as ordinary Terraform resources.

# Part 3: Official Accelerator path

After completing the smaller manual implementation, clean it up and follow the [Microsoft ALZ IaC Accelerator hands-on lab](docs/05-alz-accelerator.md). The official `Deploy-Accelerator` command is the canonical final path. The repository helpers are optional safety wrappers around the official `New-AcceleratorFolderStructure` and `Deploy-Accelerator` commands:

```powershell
# Canonical final path, after the manual resources have been cleaned up.
Deploy-Accelerator
```

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

The manual Terraform roots are the learning phase; the official Accelerator is the final platform phase. Do not let both manage the same hierarchy or resources. The Accelerator guide starts with the cleanup gate, then covers the official local workflow, Azure DevOps exercise, full Hub-Spoke scenario, upgrade discipline and two-stage cleanup procedure.

## Production gaps and next extensions

The lab is enterprise-shaped, not production-ready. A production program should evaluate:

- Promotion of the [Accelerator exercise](docs/05-alz-accelerator.md) into a reviewed platform repository with pinned versions, release management and environment-specific approvals.
- Entra groups, PIM, access reviews, break-glass accounts, custom roles, and separation of platform identities.
- Azure Policy initiatives, assignment archetypes, automated remediation and expiring exemptions.
- Defender for Cloud, Sentinel data connectors, Key Vault, customer-managed keys and security incident integration.
- DNS Private Resolver, DDoS Network Protection, multi-region hubs, ExpressRoute, IPAM and network watcher controls.
- Alert rules, action groups, backup, recovery testing, service health and platform SLOs.
- A reviewed subscription-vending pipeline with CMDB/IPAM integration and lifecycle decommissioning.
- Production resilience, quotas, availability zones, data residency, regulatory controls and disaster recovery.

Prefer the official [Azure Landing Zone IaC Accelerator](https://azure.github.io/Azure-Landing-Zones/terraform/) when moving from this teaching implementation to an organizational platform.
