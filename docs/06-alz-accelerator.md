# 06 · Microsoft ALZ IaC Accelerator Hands-on Lab

[中文版](06-alz-accelerator_cn.md)

This phase uses the official Microsoft ALZ IaC Accelerator after the teaching deployment has been understood and, for an actual Accelerator deployment, removed. It is not a second home-grown implementation: the generated Terraform starter configuration, bootstrap resources and delivery assets come from the official ALZ PowerShell module and AVM-based starter module.

The route now depends on how many subscriptions Azure actually permits. Current official guidance strongly recommends four platform subscriptions and documents two subscriptions as the SMB minimum. It does not document a one-subscription Platform landing zone deployment. A subscription can also have only one parent management group, so the same GUID must never be entered for several platform roles.

The helper scripts in `accelerator/` are optional guards around official commands. They support only scenarios 5 and 6 and deliberately require four distinct Management, Connectivity, Identity and Security subscription GUIDs. They are not a one- or two-subscription compatibility layer.

## 1. Subscription gate: choose the supported route

| Available subscriptions | Supported outcome | Route in this repository | Execution gate |
|---|---|---|---|
| 1 | No documented official Accelerator deployment topology | Run the executable [single-subscription capability lab](05-single-subscription.md). Use the official Accelerator only to generate and review Scenario 5 configuration. | Do **not** run `Deploy-Accelerator`, Phase 3 apply, or either repository wrapper. Never repeat the same GUID across platform roles. |
| 2 | Official SMB minimum: Management and Connectivity; Identity and Security are deferred | Use the unmodified official wizard with Terraform Scenario 10 or 11. | The repository wrapper does not support this route. Approve cost and validate both distinct subscriptions before bootstrap/apply. |
| 4 | Recommended complete platform: Management, Connectivity, Identity and Security | Use the guarded four-subscription route below or the unmodified official wizard. | All four GUIDs must be distinct. Apply only after transition, access and cost gates pass. |

The manual Terraform roots remain the source of truth for the one-subscription capability lab. Once a supported two- or four-subscription Accelerator deployment is adopted, its generated repository, pipeline and state become the source of truth. Never let the manual roots and the Accelerator manage the same hierarchy or resources.

Official boundary references: [Accelerator planning](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/), [platform subscriptions and permissions](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/platform-subscriptions/), and [management-group subscription moves](https://learn.microsoft.com/en-us/azure/governance/management-groups/manage).

## 2. Transition gate before any supported Accelerator apply

The one-subscription review-only exercise in section 4 creates local files only and does not require this transition. Before a two- or four-subscription bootstrap/apply:

1. Finish the manual governance, networking, DNS, Policy and cost exercises, and save the evidence you need.
2. Follow the cleanup section of the active manual route. For the single-subscription route, use [its cleanup and migration procedure](05-single-subscription.md#10-cleanup-and-later-migration). For the multi-subscription teaching route, run:

   ```bash
   ./scripts/nuke-everything.sh --mode multi
   ```

3. Verify that teaching resources, management-group associations, Policy assignments and role assignments are gone. The script deliberately retains bootstrap state storage.
4. Archive the manual state and plan evidence. Do not reuse its backend for the Accelerator and do not run those manual roots after cutover.
5. Verify that each target subscription is active, belongs to the intended tenant and is empty enough for the reviewed design. A two-subscription route needs distinct Management and Connectivity IDs; the guarded route needs four distinct IDs.
6. Start from a new, empty Accelerator target folder. Do not import the same resources into both states.

## 3. Prerequisites

The current official prerequisites require PowerShell 7.4 or later, Azure CLI 2.55 or later, Git, internet access and a local PowerShell terminal. Azure Cloud Shell and corporate-proxy execution are not explicitly supported. Check the installed tools and Azure context:

```powershell
$PSVersionTable.PSVersion
az version
git --version
az login --tenant "<tenant-id>" --use-device-code
az account set --subscription "<management-subscription-id>"
az account show --query '{name:name,id:id,tenantId:tenantId}' --output table
```

For an actual bootstrap, the operator needs Owner on the selected parent management group and on every platform subscription in the chosen model. The official default uses the Management subscription for bootstrap resources. Verify subscription availability and permissions before generating an executable configuration; billing eligibility is handled separately in [the subscription vending guide](04-subscription-vending.md).

## 4. One subscription: official configuration review only

One subscription is enough to learn the official file-generation and review workflow, but not to perform a supported Accelerator Platform landing zone apply. Use a new local review folder and the unmodified official folder-generation command:

```powershell
$reviewPath = './accelerator/work-single-sub-review'

$alzModule = Get-InstalledPSResource -Name ALZ -ErrorAction SilentlyContinue
if ($null -eq $alzModule) {
  Install-PSResource -Name ALZ
}

Import-Module ALZ -Force
Test-AcceleratorRequirement

New-AcceleratorFolderStructure `
  -iacType 'terraform' `
  -versionControl 'local' `
  -scenarioNumber 5 `
  -targetFolderPath $reviewPath

Get-InstalledPSResource -Name ALZ | Select-Object Name, Version
Get-ChildItem "$reviewPath/config" -Recurse
Select-String `
  -Path "$reviewPath/config/inputs.yaml", "$reviewPath/config/platform-landing-zone.tfvars" `
  -Pattern 'subscription_ids|subscription_placement|connectivity_type|management_resources_enabled|management_groups_enabled|enableAsc'
```

Use a target path that does not already exist. Review the generated `inputs.yaml`, `platform-landing-zone.tfvars` and `lib/` directory, then record:

- the installed ALZ module version and Scenario 5 selection;
- the four platform-role inputs and subscription-placement blocks;
- `connectivity_type = "none"` and which management resources remain enabled;
- Defender, monitoring, Policy and management-group defaults;
- the missing distinct Connectivity subscription and the resulting **No-Go** decision.

Stop here. Do not fill all roles with the same GUID, do not run `prepare-config.ps1` or `deploy-accelerator.ps1`, and do not invoke `Deploy-Accelerator` or Phase 3 apply. `New-AcceleratorFolderStructure` creates local configuration; it does not deploy the Platform landing zone. Continue the actual Azure work in [the single-subscription capability lab](05-single-subscription.md).

This is intentionally a product-boundary exercise: Scenario 5 is the closest official configuration, but the official prerequisite model still does not document a one-subscription Accelerator deployment. [Scenario 5 details](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/scenarios/management-only/) and [advanced folder generation](https://azure.github.io/Azure-Landing-Zones/accelerator/2_bootstrap/advanced/).

## 5. Two subscriptions: official SMB route

With two distinct subscriptions, use the official SMB model: Management is required for bootstrap and management resources, and Connectivity is required for hub networking. Identity and Security are recommended but can be deferred. Choose one of the current cost-optimized starters:

- Scenario 10: SMB single-region Hub-Spoke with Azure Firewall.
- Scenario 11: SMB single-region Virtual WAN with Azure Firewall.

The repository wrapper accepts only scenarios 5 and 6 and requires four different GUIDs, so it must not be used here. Start from a new folder with the canonical official wizard:

```powershell
Deploy-Accelerator
```

Choose Terraform, the Platform landing zone starter module, the required version-control target and Scenario 10 or 11. In the generated bootstrap input, provide distinct Management and Connectivity IDs, leave Identity and Security blank as directed by the current official planning guide, and use Management as `bootstrap_subscription_id`. Before approving anything, inspect all generated files and confirm no stale placeholder or third subscription is being inferred.

The official scenario table estimates **USD 689.85 per month** of fixed infrastructure for each SMB scenario in `westus`, dated **2026-04-02**. Consumption-based costs and regional/currency differences are excluded. Generate a current estimate, create a budget and obtain explicit approval before bootstrap/apply; “SMB” does not mean inexpensive for a personal credit balance.

## 6. Four subscriptions: guarded Scenario 5 baseline

The repository wrapper is exclusively for four distinct Management, Connectivity, Identity and Security subscriptions. It supports only scenarios 5 and 6. Start with Scenario 5, which deploys management groups, Policy and management resources without connectivity resources:

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

`prepare-config.ps1` invokes the official `New-AcceleratorFolderStructure`, fills the four IDs and review values, and writes local configuration only. It refuses duplicate GUIDs and existing target folders. The install/update switch is explicit; later runs can omit it to retain a reviewed module version. The version is recorded in `lab-metadata.json`. Unless `-EnablePaidDefenderPlans` is supplied, the wrapper disables the generated paid Defender plan parameters.

The official Scenario 5 table estimates **USD 0.00 of fixed infrastructure** in `westus`, dated **2026-04-02**, but that is not a zero-cost guarantee. The scenario creates management resources including Log Analytics, Data Collection Rules, managed identity and Automation Account; consumption-based log ingestion and other usage, plus bootstrap resources, are excluded from the estimate. Review retention, caps, Policy-driven deployments and current prices.

Review these generated files:

```text
accelerator/work/config/inputs.yaml
accelerator/work/config/platform-landing-zone.tfvars
accelerator/work/config/lib/
accelerator/work/lab-metadata.json
```

Confirm all four role IDs and `bootstrap_subscription_id`, parent management group, regions, security contact, disabled Defender parameters, naming, Policy assignments, subscription placements, retention and expected plan. Then run the wrapper preview, which validates local inputs but does not call `Deploy-Accelerator`:

```powershell
pwsh ./accelerator/deploy-accelerator.ps1 `
  -WorkspacePath ./accelerator/work
```

## 7. Bootstrap, apply and verify a supported route

For the two-subscription route, continue in the official wizard and generated repository. For the guarded four-subscription route, reconfirm Management as the bootstrap subscription and explicitly execute:

```powershell
az account set --subscription "<management-subscription-id>"
az account show --query '{name:name,id:id,tenantId:tenantId}' --output table

pwsh ./accelerator/deploy-accelerator.ps1 `
  -WorkspacePath ./accelerator/work `
  -Execute
```

Type `DEPLOY-ALZ-ACCELERATOR` only after checking every displayed path and ID. The official ALZ module generates a Terraform plan and presents its own confirmation. Bootstrap creates the reviewed state, identities and delivery output; it does **not** mean that the Platform landing zone has already been applied.

For a local target, find the generated script, then review it and all generated Terraform before running it from its own directory:

```powershell
Get-ChildItem `
  -Path ./accelerator/work/output `
  -Recurse `
  -Filter deploy-local.ps1
```

Never approve an unexplained replacement, management-group move, role assignment, Policy remediation or paid service. After apply, verify the route-specific result:

| Check | Two-subscription SMB | Four-subscription route |
|---|---|---|
| Placement | Management and Connectivity are in their intended management groups; Identity/Security placements are absent | All four platform subscriptions are in their intended management groups |
| Resources | Management and selected SMB connectivity resources match Scenario 10/11 | Scenario 5 management resources, or explicitly approved Scenario 6 resources, match the configuration |
| Governance | Expected management groups, Policy definitions, initiatives, assignments and remediation identities exist | Same, including the intended Platform and Security boundaries |
| Delivery | Remote state, workload identities and pipeline permissions contain no local developer secret | Same |
| Idempotency | A second plan has no unexplained changes | A second plan has no unexplained changes |
| Cost | Budget and cost alerts show the expected scopes and services | Same |

## 8. Four subscriptions: Scenario 6 connectivity is plan-only by default

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

Scenario 6 is the full single-region Hub-Spoke architecture with Azure Firewall. The official table estimates **USD 5,638.36 per month** of fixed infrastructure in `westus`, dated **2026-04-02**. Consumption-based charges and regional/currency differences are additional. Treat configuration generation and plan as the default end point; do not execute the wrapper or generated apply until a named approver accepts a current estimate, budget, maximum duration and cleanup owner.

Search the generated configuration and library for at least:

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

Use the official option guides to disable or resize services correctly; some changes require a library override rather than one apparent Boolean. Recalculate the price after every change. Sponsorship credit is a payment source, not approval to deploy. If execution is approved, time-box Firewall, gateways, Bastion, DDoS, Private DNS Resolver, Defender and log ingestion, capture evidence, and run the official cleanup while the owner is still present.

## 9. Canonical official run and Azure DevOps delivery

This section applies only after the two- or four-subscription gate passes. To practise the full delivery flow, use a new empty target folder and run the unmodified official interactive wizard:

```powershell
Deploy-Accelerator
```

Choose Terraform, Azure DevOps, the Platform landing zone starter module and the approved scenario. Complete the official Azure DevOps prerequisites, including organization/project permissions and authentication material. Before bootstrap, inspect `config/inputs.yaml`, `config/platform-landing-zone.tfvars` and `config/lib`, verify subscription counts and IDs, and repeat the cost gate.

Bootstrap can create the repository, workload-federated deployment identities, remote state and pipelines. In Azure DevOps, run **02 Azure landing zone Continuous Delivery**, inspect the Terraform plan and approve apply only through the protected environment. Use Microsoft-hosted agents for a public bootstrap; evaluate self-hosted agents and private connectivity for a production platform.

Do not copy the separate sample under `azure-devops/` over the Accelerator-generated pipeline. Compare them only to understand controls. After cutover, the Accelerator-generated repository, pipeline and state are the source of truth.

## 10. Cleanup boundaries

Cleanup depends on what was actually executed:

- One-subscription Accelerator review created only local generated files. Preserve the evidence you need, then remove that review folder normally; no Accelerator Azure cleanup is required. Clean actual one-subscription Azure resources by following Part 05.
- Two- and four-subscription Accelerator deployments use the official generated configuration and official cleanup commands below. Do not use the manual Terraform state to remove Accelerator resources.

First preview removal of the Platform landing zone. For the two-subscription SMB route, pass only the two subscriptions that were deployed:

```powershell
Remove-PlatformLandingZone `
  -ManagementGroups "<root-parent-management-group-id>" `
  -Subscriptions "<management-subscription-id>", "<connectivity-subscription-id>" `
  -SubscriptionsTargetManagementGroup "<root-parent-management-group-id>" `
  -PlanMode
```

For the guarded four-subscription route:

```powershell
Remove-PlatformLandingZone `
  -ManagementGroups "<root-parent-management-group-id>" `
  -Subscriptions "<management-subscription-id>", "<connectivity-subscription-id>", "<identity-subscription-id>", "<security-subscription-id>" `
  -SubscriptionsTargetManagementGroup "<root-parent-management-group-id>" `
  -PlanMode
```

Use `-AdditionalSubscriptions "<bootstrap-subscription-id>"` only when bootstrap used a separate fifth subscription. Review subscription targets, moves and every proposed deletion, then rerun without `-PlanMode` only when the preview is correct.

Second, remove bootstrap/version-control resources using the exact saved configuration and output directory from that deployment:

```powershell
Deploy-Accelerator `
  -Inputs "./accelerator/work/config/inputs.yaml", "./accelerator/work/config/platform-landing-zone.tfvars" `
  -StarterAdditionalFiles "./accelerator/work/config/lib" `
  -Output "./accelerator/work/output" `
  -Destroy
```

The repository's `scripts/nuke-everything.sh` understands only the manual Terraform roots and must never be used as the Accelerator cleanup procedure. Retain the generated folder, state references and version evidence until both cleanup phases and verification are complete. Confirm that paid resources, Policy assignments, identities, role assignments, state storage and repository/pipeline assets are in their expected final state.

## 11. Change and upgrade discipline

For each change:

1. Record the ALZ PowerShell, bootstrap, starter-module and ALZ library versions together with the scenario and option set.
2. Create a branch and read the official release notes and upgrade guide.
3. Generate a comparison in a separate folder and review the diff. Never regenerate over the active configuration.
4. Merge reviewed upstream changes into the owned configuration; do not silently accept new Policy, placement, networking or paid-service defaults.
5. Run a plan, capture Policy and architecture differences, and test in a non-production hierarchy with the same subscription model.
6. Apply through approval gates, then run a second plan for drift and recheck cost alerts.

This turns the Accelerator into a maintained platform product rather than a one-time deployment wizard.

## Official references

- [ALZ Terraform implementation guidance](https://azure.github.io/Azure-Landing-Zones/terraform/)
- [Accelerator planning](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/)
- [Platform subscriptions and permissions](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/platform-subscriptions/)
- [Tool prerequisites](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/)
- [Advanced bootstrap](https://azure.github.io/Azure-Landing-Zones/accelerator/2_bootstrap/advanced/)
- [Phase 3: run](https://azure.github.io/Azure-Landing-Zones/accelerator/3_run/)
- [Terraform scenarios](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/scenarios/)
- [Scenario 5: management only](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/scenarios/management-only/)
- [Terraform options](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/options/)
- [Upgrade guidance](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/upgrade-guide/)
- [Cleanup FAQ](https://azure.github.io/Azure-Landing-Zones/accelerator/faq/cleanup/)
- [Official scenario cost-estimate script](https://github.com/Azure/Azure-Landing-Zones/blob/main/utl/cost-estimates/Get-ScenarioCostEstimates.ps1)
