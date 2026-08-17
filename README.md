# Azure Landing Zone Learning and Deployment Lab

[中文版](README_cn.md)

> This lab is organized as **foundations first, deployment and validation second**. It uses Terraform to build Azure Landing Zone (ALZ) governance, Hub-Spoke networking, Private Endpoint, Azure Firewall, VPN Gateway, observability, and an Azure Pipelines example.

## Learning outcomes

After completing the main path, you should be able to:

- Explain the boundaries between management groups, subscriptions, platform landing zones, and application landing zones.
- Use Azure Policy for location restrictions, public-IP controls, and DeployIfNotExists (DINE) governance.
- Explain Hub-Spoke, system routes, UDRs, VNet peering, gateway route propagation, and forced tunnelling.
- Validate the Private Endpoint DNS chain from a workload and diagnose common failure modes.
- Deploy Azure Firewall and simulated hybrid connectivity, then observe changes in effective routes and logs.
- Use Terraform and Azure Pipelines to create a repeatable, reviewable infrastructure-delivery process.

## Is the current lab sufficient?

The repository covers the most important governance, networking, Private Link, logging, and automation topics for understanding ALZ and completing an end-to-end hands-on exercise. It is not a complete Azure curriculum or a production-ready ALZ.

| ALZ design area | Coverage | Included here |
|---|---|---|
| Billing and tenant | Introductory | Single-subscription lab, cost switches, and budget guidance |
| Identity and access | Limited | Managed identities and pipeline workload identity; no systematic RBAC/PIM lab |
| Resource organization | Strong | Management groups, subscription placement, and Platform/Corp/Online/Sandbox hierarchy |
| Network and connectivity | Strong | Hub-Spoke, UDR, Firewall, VPN Gateway, and Private DNS |
| Security | Partial | Azure Policy, NSG, and Firewall; no Defender for Cloud or Key Vault lab |
| Management and operations | Partial | Log Analytics, diagnostic settings, and KQL; no alerting, backup, or disaster recovery lab |
| Governance | Strong | Audit, Deny, DINE, compliance evaluation, and remediation concepts |
| Platform automation and DevOps | Strong | Terraform, Azure Pipelines templates, approvals, and OIDC |

Complete this main path first, then use the extension roadmap near the end to add identity, security, resilience, and a real application workload.

## Repository structure

```text
docs/
  01-ALZ-concepts.md       ALZ, management groups, subscription organization, and Policy
  02-networking.md         Hub-Spoke, routing, Firewall, hybrid connectivity, and Private DNS
  03-azure-devops.md       Pipelines, templates, expressions, approvals, and KQL

terraform/
  10-governance/           Management-group hierarchy, subscription placement, and Policy
  20-platform/             Hub/Spoke, Private Link, logging, Firewall, and VPN Gateway

azure-devops/              Runnable Azure Pipelines template example

scripts/
  test-private-dns.sh      Validate Private Endpoint DNS from the test VM
  show-effective-routes.sh Display the test VM NIC's effective routes
  destroy-expensive.sh     Remove hourly billed Firewall and Gateway resources
  nuke-everything.sh       Remove the complete lab
```

---

# Part 1: Foundations

Complete this part before deployment. It gives you enough context to understand each resource in the Terraform plan instead of only running commands.

## 1. ALZ and governance foundations

Read [`docs/01-ALZ-concepts.md`](docs/01-ALZ-concepts.md), focusing on:

- The Tenant, Management Group, Subscription, and Resource Group hierarchy.
- Platform Landing Zones versus Application Landing Zones.
- The responsibilities of Platform, Landing Zones, Corp, Online, Sandbox, and Decommissioned.
- Azure Policy scope, inheritance, exemptions, and the differences between Audit, Deny, and DINE.
- Why governance normally starts at an intermediate root rather than placing broad controls on the Tenant Root Group.

Checkpoint: given a new workload, determine its subscription and management-group placement and the policies it should inherit.

## 2. Networking foundations

Read [`docs/02-networking.md`](docs/02-networking.md), focusing on:

- Hub-Spoke traffic paths and non-transitive VNet peering.
- Longest-prefix route selection and UDR, BGP, and system-route precedence.
- The distinct responsibilities of NSGs, Azure Firewall, and Application Gateway.
- The relationship between Private Endpoint, Private DNS Zone, VNet Link, and DNS Zone Group.
- VPN/ExpressRoute gateway transit and the matching remote-gateway peering configuration.

Checkpoint: draw the path from a spoke to the internet, the hub, another spoke, a Private Endpoint, and an on-premises network.

## 3. Operations and automation foundations

Read sections 1–5 of [`docs/03-azure-devops.md`](docs/03-azure-devops.md) and review [`azure-devops/README.md`](azure-devops/README.md), focusing on:

- The Terraform `init`, `validate`, `plan`, `apply`, and `destroy` lifecycle.
- Azure Pipelines templates, variable groups, service connections, environments, and approvals.
- Compile-time, runtime, and macro expression evaluation.
- How Log Analytics, diagnostic settings, and KQL form a basic troubleshooting loop.

Checkpoint: explain why a reviewed Terraform plan should be saved and that same plan applied.

---

# Part 2: Deployment and validation

## 0. Prepare the environment

### Tools and permissions

- A dedicated Azure lab subscription. Do not run the lab in a production subscription or company tenant without approval.
- Azure CLI, Terraform `>= 1.5.0`, Git, and Bash.
- Permission to deploy resources in the subscription.
- Tenant-level permission to create management groups, assign management-group Policy, move a subscription, and create role assignments. In an enterprise tenant, an administrator normally grants these rights explicitly. Without them, you can still complete the platform networking portion.
- Regional quota for Standard_B1s, Azure Firewall, and VpnGw1. Firewall and gateways are optional exercises.

Check local tools:

```bash
az version
terraform version
```

Sign in and verify the target subscription:

```bash
az login
az account set --subscription "<subscription name or ID>"
az account show --query '{name:name,id:id,tenantId:tenantId}' --output table
```

If deployment reports an unregistered resource provider and you have permission to register it:

```bash
for namespace in Microsoft.Network Microsoft.Compute Microsoft.Storage \
  Microsoft.OperationalInsights Microsoft.Insights; do
  az provider register --namespace "$namespace"
done
```

### Cost protection

Before deployment, create a monthly budget under **Cost Management + Billing -> Budgets**, with notifications such as 50%, 80%, and 100%. Prices vary by region, currency, and agreement, so confirm the current cost with the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) before enabling Firewall or gateways.

The default platform configuration creates a B1s test VM, Private Endpoint, and Log Analytics Workspace. `enable_firewall`, `enable_vpn_gateway`, and `enable_simulated_onprem` are all `false` by default.

## 1. Deploy governance

```bash
cd terraform/10-governance
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. At minimum, set `subscription_id` and choose a short `prefix` that is unique in the tenant. Keep these values for the first deployment:

```hcl
move_subscription_into_hierarchy = false
public_ip_policy_effect           = "Audit"
```

Initialize, validate, and review the plan before applying it:

```bash
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Check **Management groups** and **Policy** in the Azure portal. Initial management-group service setup and resource visibility can take time.

## 2. Validate subscription placement and Policy

Change the governance `terraform.tfvars` values to:

```hcl
move_subscription_into_hierarchy = true
public_ip_policy_effect           = "Deny"
```

Run `terraform plan -out=tfplan`, review it, and run `terraform apply tfplan`. After Policy propagation and initial evaluation, deliberately attempt to create a VM with a public IP:

```bash
az group create --name rg-alz-policy-test --location australiaeast

az vm create \
  --resource-group rg-alz-policy-test \
  --name vm-should-fail \
  --image Ubuntu2404 \
  --public-ip-address pip-policy-test \
  --generate-ssh-keys
```

The VM/NIC deployment should be denied. Inspect the Policy assignment and definition IDs in the error, then remove the test resource group:

```bash
az group delete --name rg-alz-policy-test --yes --no-wait
```

If deployment succeeds, first confirm that the subscription is under the Corp management group and allow more time for Policy propagation before retrying.

## 3. Deploy the baseline platform

```bash
cd ../20-platform
cp terraform.tfvars.example terraform.tfvars
```

Set the same `subscription_id`. Keep all three expensive switches disabled and retain the test VM:

```hcl
enable_firewall         = false
enable_vpn_gateway      = false
enable_simulated_onprem = false
enable_test_vm          = true
```

```bash
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
terraform output
```

This creates Hub/Spoke VNets, peering, NSGs, Private DNS, a Storage Private Endpoint, Log Analytics, and a test VM without a public IP.

## 4. Validate routes and Private Endpoint DNS

Return to the repository root:

```bash
cd ../..
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-baseline.txt
./scripts/test-private-dns.sh
```

The expected DNS result is a `privatelink` CNAME followed by an A record for the Private Endpoint in `10.1.1.x`.

Remove the spoke Private DNS Zone Link deliberately and observe the change:

```bash
terraform -chdir=terraform/20-platform destroy \
  -target=azurerm_private_dns_zone_virtual_network_link.blob_to_spoke

./scripts/test-private-dns.sh
terraform -chdir=terraform/20-platform apply
```

Use `-target` only for this controlled failure exercise, not as the normal deployment workflow. Rerun the DNS test after repair.

## 5. Connect governance to logging

Retrieve the Log Analytics Workspace resource ID:

```bash
terraform -chdir=terraform/20-platform output -raw log_analytics_workspace_id
```

Set this value as `log_analytics_workspace_id` in `terraform/10-governance/terraform.tfvars`, then plan and apply the governance root again. This enables the DINE example together with its managed identity and role assignment.

In **Policy -> Compliance**, inspect compliance state and observe that existing resources normally require reevaluation or a remediation task before missing configuration is deployed.

## 6. Deploy Azure Firewall and inspect forced tunnelling

Set these values in `terraform/20-platform/terraform.tfvars`:

```hcl
enable_firewall   = true
firewall_sku_tier = "Standard"
```

Plan and apply, then save and compare the new effective routes:

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-firewall.txt
diff -u /tmp/alz-routes-baseline.txt /tmp/alz-routes-firewall.txt
```

Test an allowed and a denied egress request:

```bash
RG=$(terraform -chdir=terraform/20-platform output -raw landing_zone_resource_group)
VM=$(terraform -chdir=terraform/20-platform output -raw test_vm_name)

az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript \
  --scripts "curl -sS -o /dev/null -w 'github: %{http_code}\n' https://github.com; \
             curl -sS -m 10 -o /dev/null -w 'reddit: %{http_code}\n' https://www.reddit.com || echo 'reddit: blocked'"
```

Use the KQL in section 5 of [`docs/03-azure-devops.md`](docs/03-azure-devops.md) to inspect Firewall allow/deny logs. Ingestion can take several minutes.

Immediately remove hourly billed resources, then reset the corresponding value in `terraform.tfvars` to `false`:

```bash
./scripts/destroy-expensive.sh
```

## 7. Deploy simulated hybrid connectivity

Confirm that the Firewall has been removed, then set:

```hcl
enable_vpn_gateway      = true
enable_simulated_onprem = true
```

Plan and apply. Gateway deployment can take a significant amount of time. After completion, capture effective routes again:

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-gateway.txt
```

Identify routes with a `VirtualNetworkGateway` source and inspect the pairing of `allow_gateway_transit` and `use_remote_gateways` on the Hub/Spoke peerings.

Remove the gateways immediately after validation:

```bash
./scripts/destroy-expensive.sh
```

Reset both gateway switches in `terraform.tfvars` to `false` so a later `terraform apply` does not rebuild them.

## 8. Run the Azure Pipelines example (optional)

Follow [`azure-devops/README.md`](azure-devops/README.md) to create a service connection, variable group, and environment, then run `azure-devops/azure-pipelines.yml`. Verify that:

- Pull requests run Validate and Plan without Apply.
- Apply on the main branch requires environment approval.
- Workload identity federation avoids a long-lived client secret.
- Apply consumes the reviewed plan artifact instead of creating a new plan.

## 9. Stop billing and clean up

Deallocate only the test VM:

```bash
az vm deallocate --resource-group \
  "$(terraform -chdir=terraform/20-platform output -raw landing_zone_resource_group)" \
  --name "$(terraform -chdir=terraform/20-platform output -raw test_vm_name)"
```

Remove only Firewall and Gateway resources:

```bash
./scripts/destroy-expensive.sh
```

Remove the entire lab:

```bash
./scripts/nuke-everything.sh
```

After cleanup, verify Terraform state, the Azure portal, and resources tagged `lab=true` so nothing billable remains.

---

## Evidence worth keeping

- Effective-route output for baseline, Firewall, and Gateway phases.
- Private DNS results before link removal, after failure, and after repair.
- The Policy Deny error with its assignment and definition IDs.
- Log Analytics results showing Firewall allow/deny decisions.
- Reviewed Terraform plans and a final topology diagram.
- A troubleshooting record containing symptom, hypotheses, validation, root cause, and fix.

## Extension roadmap

1. **Identity and access**: RBAC, custom roles, managed identity, PIM, break-glass accounts, and Conditional Access.
2. **Secrets and security**: Key Vault Private Endpoint, rotation, Defender for Cloud, and security-baseline Policy.
3. **Real workload**: App Service, Container Apps, or AKS in an Application Landing Zone, with Application Gateway/WAF.
4. **Operations and resilience**: Azure Monitor alerts, Action Groups, Update Manager, Backup, Site Recovery, and multi-region design.
5. **Platform at scale**: multiple subscriptions, subscription vending, remote Terraform state, module versioning, and policy-as-code testing.

## Known limitations

- This is a simplified, single-subscription ALZ. A production architecture normally separates platform and application subscriptions.
- ExpressRoute requires a provider circuit. The lab covers only downstream gateway transit and route propagation.
- The code passes `terraform fmt`, but AzureRM Provider versions, regional quotas, and tenant policy can still produce `validate` or `plan` differences. Always review the plan before applying it.
- For production, evaluate Microsoft's ALZ IaC Accelerator, Azure Verified Modules, or official Bicep implementation and tailor it to organizational requirements instead of copying this lab directly.

## Official references

- [What is an Azure landing zone?](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/)
- [Azure landing zone design areas](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas)
- [Authenticate Terraform to Azure](https://learn.microsoft.com/azure/developer/terraform/authenticate-to-azure)
- [Create a management group](https://learn.microsoft.com/azure/governance/management-groups/create-management-group-portal)
- [Azure CLI budget commands](https://learn.microsoft.com/cli/azure/consumption/budget)
