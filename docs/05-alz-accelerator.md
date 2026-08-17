# 05 · Microsoft ALZ IaC Accelerator Hands-on Lab

[中文版](05-alz-accelerator_cn.md)

This lab adds the official Microsoft ALZ IaC Accelerator as a production-oriented path alongside the repository's smaller teaching implementation. Complete the manual Terraform labs first so that the generated modules, identities, state and pipelines are understandable rather than opaque.

The helper scripts in `accelerator/` are deliberately conservative:

- `prepare-config.ps1` downloads the current official scenario through the ALZ PowerShell module, fills the four platform subscription IDs, region and security contact, and creates local configuration only.
- Scenario 5 is the default. It deploys management groups, Policy and management resources without the full connectivity platform.
- Defender plan policy parameters are set to `Disabled` unless `-EnablePaidDefenderPlans` is explicitly supplied.
- `deploy-accelerator.ps1` is preview-only unless `-Execute` is supplied. Execution checks the current Azure CLI subscription and requires a typed confirmation.
- Generated work folders are ignored by Git because they can contain tenant-specific configuration and generated state metadata.

These controls reduce accidental deployment; they do not make a deployment free or production-approved.

## 1. Decide how this relates to the manual lab

| Path | Best use | Ownership and state |
|---|---|---|
| `terraform/00-bootstrap`, `10-governance`, `20-platform` | Learn each Azure and Terraform mechanism, run small cost-controlled failure exercises | Maintained by this repository |
| Official ALZ IaC Accelerator | Practise a Microsoft-supported bootstrap pattern, Azure Verified Modules, ALZ Policy library, workload identities and delivery pipelines | Generated and upgraded through the official ALZ toolchain |

Do not apply both implementations to the same management-group hierarchy or adopt the same Azure resources into both Terraform states. If the manual lab is already deployed, either clean it up before reusing the four platform subscriptions, or give the Accelerator a separate parent management group and a separately reviewed set of subscriptions. A subscription can have only one parent management group at a time.

## 2. Prerequisites

The current official prerequisites require PowerShell 7.4 or later, Azure CLI 2.55 or later, Git, internet access and sufficient tenant/subscription permissions. Run the exercise in a local PowerShell terminal; Azure Cloud Shell is not supported by the Accelerator.

```powershell
$PSVersionTable.PSVersion
az version
git --version
az login --tenant "<tenant-id>" --use-device-code
az account set --subscription "<management-subscription-id>"
az account show --query '{name:name,id:id,tenantId:tenantId}' --output table
```

Use these four dedicated platform subscriptions from [the subscription vending lab](04-subscription-vending.md): Management, Connectivity, Identity and Security. This lab uses Management as the bootstrap subscription.

## 3. Stage A: generate a cost-controlled configuration

Start with official Terraform scenario 5: management groups, Policy and management resources only. From the repository root, run:

```powershell
pwsh ./accelerator/prepare-config.ps1 `
  -ManagementSubscriptionId "<management-subscription-id>" `
  -ConnectivitySubscriptionId "<connectivity-subscription-id>" `
  -IdentitySubscriptionId "<identity-subscription-id>" `
  -SecuritySubscriptionId "<security-subscription-id>" `
  -DefenderSecurityContact "<security-contact@example.com>" `
  -Location "australiaeast" `
  -ScenarioNumber 5 `
  -InstallOrUpdateAlzModule
```

The install/update switch is explicit because module versions can change. On later runs, omit it when you want to reuse the reviewed installed version. The script records that version in `accelerator/work/lab-metadata.json`.

Scenario 5 still creates billed management resources such as Log Analytics. Review retention, daily caps, Policy-driven deployments and the plan before applying; “management only” does not mean “no cost.”

This step does **not** create Azure or version-control resources. Review all generated files, especially:

```text
accelerator/work/config/inputs.yaml
accelerator/work/config/platform-landing-zone.tfvars
accelerator/work/config/lib/
accelerator/work/lab-metadata.json
```

Confirm:

- all subscription IDs and `bootstrap_subscription_id` are correct;
- `root_parent_management_group_id` has the intended value—an empty value means the tenant root is used according to the generated template;
- every `starter_locations` entry is valid and data-residency requirements are met;
- the Defender security contact is correct;
- each `enableAsc...` parameter is `Disabled` for this cost-controlled exercise;
- naming, IP ranges, management-group IDs, Policy assignments and data retention meet the intended design.

Preview the bootstrap wrapper:

```powershell
pwsh ./accelerator/deploy-accelerator.ps1 `
  -WorkspacePath ./accelerator/work
```

The preview validates the folder and placeholders but does not invoke `Deploy-Accelerator`.

## 4. Bootstrap and run the platform deployment

Reconfirm the selected subscription, then explicitly execute:

```powershell
az account set --subscription "<management-subscription-id>"

pwsh ./accelerator/deploy-accelerator.ps1 `
  -WorkspacePath ./accelerator/work `
  -Execute
```

Type `DEPLOY-ALZ-ACCELERATOR` only after checking the displayed paths and subscription. The official ALZ module then generates a Terraform plan and asks for its own confirmation. This first deployment creates the reviewed bootstrap resources and local delivery output; it does not imply that the Platform landing zone has already been applied.

Locate the generated local deployment script:

```powershell
Get-ChildItem `
  -Path ./accelerator/work/output `
  -Recurse `
  -Filter deploy-local.ps1
```

Open and review that script and its generated Terraform before running it from its own directory. It creates a plan and asks for confirmation before applying. Never approve an unexplained replacement, subscription move, role assignment or paid service.

After apply, verify:

- the expected ALZ hierarchy exists, including the Platform and Security boundaries;
- Management, Connectivity, Identity and Security subscriptions are placed correctly;
- ALZ Policy definitions, initiatives and assignments are present at the intended scopes;
- the management workspace and monitoring resources match the scenario;
- generated Terraform state and identities are not local developer secrets;
- a second plan shows no unexplained changes.

## 5. Stage B: enterprise-shaped connectivity

Only after scenario 5 is understood and its cleanup has been tested, generate scenario 6 in a separate work folder:

```powershell
pwsh ./accelerator/prepare-config.ps1 `
  -ManagementSubscriptionId "<management-subscription-id>" `
  -ConnectivitySubscriptionId "<connectivity-subscription-id>" `
  -IdentitySubscriptionId "<identity-subscription-id>" `
  -SecuritySubscriptionId "<security-subscription-id>" `
  -DefenderSecurityContact "<security-contact@example.com>" `
  -Location "australiaeast" `
  -ScenarioNumber 6 `
  -TargetFolderPath ./accelerator/work-full
```

Scenario 6 is the single-region Hub-Spoke architecture with Azure Firewall. Its generated defaults can include continuously billed services. Search the generated configuration and library for at least:

```text
primary_firewall_enabled
primary_firewall_sku_tier
primary_virtual_network_gateway_express_route_enabled
primary_virtual_network_gateway_vpn_enabled
primary_bastion_enabled
primary_private_dns_resolver_enabled
ddos_protection_plan_enabled
enableAsc
```

Use the official option guides to disable or resize services correctly; some changes require a library override rather than changing one apparent Boolean. Review the resulting plan and current regional prices. Even with sponsorship credit, set budgets and time-box Firewall, gateways, Bastion, DDoS, Private DNS Resolver, Defender and log ingestion.

## 6. Azure DevOps production exercise

The local scenario teaches the generated artifacts safely. To practise the full enterprise delivery flow, use a new empty target folder and run the official interactive wizard:

```powershell
Deploy-Accelerator
```

Choose Terraform, Azure DevOps, the Platform landing zone starter module and the reviewed scenario. Complete the official Azure DevOps prerequisites first, including organization/project permissions and the required authentication material. Before approving bootstrap, inspect the generated `config/inputs.yaml`, `config/platform-landing-zone.tfvars` and `config/lib` just as in the local exercise.

The bootstrap can create the repository, federated deployment identities, remote state and pipelines. In Azure DevOps, run **02 Azure landing zone Continuous Delivery**, inspect the Terraform plan, and approve apply only through the protected environment. Use Microsoft-hosted agents for a public lab bootstrap; evaluate self-hosted agents and private connectivity for a production platform.

Do not copy the separate sample under `azure-devops/` over the Accelerator-generated pipeline. Compare them to understand the controls, then treat the generated repository as the source of truth.

## 7. Cleanup rehearsal

Accelerator cleanup has two distinct phases. First preview removal of the Platform landing zone:

```powershell
Remove-PlatformLandingZone `
  -ManagementGroups "<root-parent-management-group-id>" `
  -Subscriptions "<management-subscription-id>", "<connectivity-subscription-id>", "<identity-subscription-id>", "<security-subscription-id>" `
  -SubscriptionsTargetManagementGroup "<root-parent-management-group-id>" `
  -PlanMode
```

Use `-AdditionalSubscriptions "<bootstrap-subscription-id>"` only when the bootstrap subscription is additional to the four platform subscriptions. Review every proposed deletion, then rerun without `-PlanMode`.

Second, remove bootstrap/version-control resources with the same saved configuration:

```powershell
Deploy-Accelerator `
  -Inputs "./accelerator/work/config/inputs.yaml", "./accelerator/work/config/platform-landing-zone.tfvars" `
  -StarterAdditionalFiles "./accelerator/work/config/lib" `
  -Output "./accelerator/work/output" `
  -Destroy
```

The repository's `scripts/nuke-everything.sh` understands only the manual Terraform roots and must not be used as the Accelerator cleanup procedure. Retain the generated folder until cleanup and evidence capture are complete.

## 8. Change and upgrade discipline

For each change:

1. Record the ALZ PowerShell module, starter-module and ALZ library versions.
2. Create a branch and read the official release and upgrade notes.
3. Merge reviewed upstream changes into existing configuration; do not blindly regenerate over production files.
4. Run a plan, capture Policy and architecture differences, and test in a non-production hierarchy.
5. Apply through approval gates, then run a second plan for drift.

This turns the Accelerator into a maintained platform product rather than a one-time deployment wizard.

## Official references

- [ALZ Terraform implementation guidance](https://azure.github.io/Azure-Landing-Zones/terraform/)
- [Accelerator planning](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/)
- [Prerequisites](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/)
- [Advanced bootstrap](https://azure.github.io/Azure-Landing-Zones/accelerator/2_bootstrap/advanced/)
- [Phase 3: run](https://azure.github.io/Azure-Landing-Zones/accelerator/3_run/)
- [Terraform scenarios](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/scenarios/)
- [Terraform options](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/options/)
- [Upgrade guidance](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/upgrade-guide/)
- [Cleanup FAQ](https://azure.github.io/Azure-Landing-Zones/accelerator/faq/cleanup/)
