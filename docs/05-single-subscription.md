# 05 · Single-Subscription ALZ Capability Lab

[中文版](05-single-subscription_cn.md)

Use this path when the organization has one usable Azure subscription and Azure does not approve additional subscription creation. It preserves the multi-subscription target architecture in the rest of the repository, but lets you practise the underlying ALZ mechanisms now.

This is a **capability lab, not a complete enterprise ALZ**. Provider aliases and resource groups represent Management, Connectivity, Security, Corp and Sandbox responsibilities inside one subscription. They do not create subscription-level billing, quota, RBAC, policy or incident boundaries.

## 1. Architecture and limits

One subscription can have only one parent management group. This lab initially creates the full hierarchy without moving the subscription, then optionally places the one subscription under `Corp` so it inherits the intermediate-root and Corp policies.

```text
Tenant Root Group
└── alz1sub (intermediate root)
    ├── Platform
    │   ├── Management
    │   ├── Connectivity
    │   ├── Identity
    │   └── Security
    ├── Landing Zones
    │   ├── Corp
    │   │   └── Existing subscription  <- only actual placement
    │   └── Online
    ├── Sandbox
    └── Decommissioned

Existing subscription
├── rg-alz1sub-management-*       logical Management role
├── rg-alz1sub-connectivity-*     logical Connectivity role
├── rg-alz1sub-corp-app1-*        logical Corp workload role
├── rg-alz1sub-security-*         optional logical Security role
└── rg-alz1sub-simulated-onprem-* optional logical Sandbox role
```

Management groups contain child management groups and subscriptions, not resource groups. The resource groups above remain direct children of the same subscription.

| Capability | One subscription | Limitation |
|---|---|---|
| Remote Terraform state and separate state keys | Yes | State storage shares the same subscription as the resources |
| Management-group hierarchy | Yes | Only one branch can contain the subscription at a time |
| Policy inheritance, Audit, Deny and DINE | Yes | Moving the subscription changes policy for every resource in it |
| Management-group and resource-group RBAC | Yes | Cannot prove simultaneous team isolation across subscriptions |
| Hub-Spoke, UDR, NSG, Firewall, VPN, Private Endpoint and DNS | Yes | Provider aliases point to the same subscription |
| Log Analytics, diagnostics, KQL and one subscription budget | Yes | Costs and quotas are consolidated |
| Cross-subscription authorization and blast radius | No | Requires genuinely different subscriptions |
| Billing Profile attribution per subscription and vending | No | Requires additional subscriptions and billing eligibility |
| Official ALZ IaC Accelerator apply | No | Official guidance recommends four platform subscriptions; SMB scenarios require at least Management and Connectivity |

Microsoft's current Accelerator planning guidance recommends four platform subscriptions and documents a two-subscription minimum for SMB scenarios. It does not document a one-subscription deployment topology. [Official planning guidance](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/)

## Quota-limited transition: four new platform subscriptions plus the protected workload

The account review leaves four creation slots after the existing Active
Sponsorship subscription and four historical Deleted records are counted. If
all four slots are approved, use `subscriptions.quota-limited.tfvars.example`:

- the four new IDs are distinct `management`, `connectivity`, `identity` and `security` subscriptions;
- the existing Sponsorship ID is repeated only for the logical workload roles;
- Terraform creates one actual Corp association for that workload ID, never five conflicting parent associations;
- the existing workload subscription is never deleted, and its organization-owned resource groups and resources are never selected as lab targets.

Prepare the three root files and the bootstrap file, then use a separate state key:

```bash
cp terraform/subscriptions.quota-limited.tfvars.example terraform/subscriptions.quota-limited.tfvars
cp terraform/00-bootstrap/terraform.quota-limited.tfvars.example terraform/00-bootstrap/terraform.tfvars
cp terraform/10-governance/terraform.quota-limited.tfvars.example terraform/10-governance/terraform.tfvars
cp terraform/20-platform/terraform.quota-limited.tfvars.example terraform/20-platform/terraform.tfvars
./scripts/init-backends.sh --mode quota-limited
```

Before any apply, inventory the existing Sponsorship subscription, confirm all
four new subscriptions are Active and in the intended Billing Profile/Invoice
Section, and run plans for both roots. Keep
`move_subscriptions_into_hierarchy = false` unless the organization approves
the workload subscription inheriting the experimental management-group Policy.
In that reviewed change also set
`allow_protected_workload_policy_inheritance = true`; Terraform rejects the
move when the explicit acknowledgement is absent.
The platform resources can be deployed to the four new platform subscriptions
and to a dedicated, uniquely named lab resource group in the existing workload
subscription without deleting or modifying unrelated resources.

This route gives at most five Active subscriptions (four new plus the existing
one), but it does not give five independent workload boundaries. Do not create
or delete disposable workload subscriptions to simulate them.

## 2. Prerequisites and inventory before changing governance

### Tools, sign-in and authorization

Run this route only in a dedicated lab tenant or a tenant where the hierarchy, Policy and RBAC changes have been explicitly approved. Required local tools are Azure CLI, Terraform `>= 1.5, < 2.0`, Git and Bash:

```bash
az version
terraform version
git --version
az login --tenant '<tenant-id>'
az account show --query '{name:name,id:id,tenantId:tenantId,state:state}' --output table
```

Confirm the authorization model before creating anything:

- The existing subscription must be active. The operator needs permission to create the documented resources and budgets, plus permission to create role assignments. `Owner` on a dedicated lab subscription is the simplest lab setup; an organization can instead grant an approved least-privilege combination.
- The governance root creates child management groups under the Tenant Root Group, management-group Policy definitions and assignments, subscription associations, and management-group role assignments. The operator therefore needs the corresponding permissions at the intended parent scope. `Owner` on that parent is the simplest lab setup; a least-privilege model normally separates management-group, Resource Policy and RBAC administration permissions.
- Subscription `Owner` alone does not grant tenant-root management-group or Policy permissions. Do not elevate access in an organizational tenant without approval. If the required parent-scope permissions are unavailable, skip the governance root and run only the platform/network exercises that are approved for the subscription.
- Creating the disposable Entra group in the RBAC exercise also requires directory permission. An existing test-group object ID can be used instead.
- Billing Profile or Invoice Section permissions are not required because this route uses an existing subscription and does not create another one.

Keep credentials, subscription IDs, saved plans and Terraform state out of Git. Review current Azure prices and subscription quotas before enabling the VM, Firewall, VPN Gateway, Sentinel or other billed features.

### Inventory the existing subscription

Select the subscription explicitly and capture evidence of its current state:

```bash
export ALZ_SUBSCRIPTION_ID='<existing-sponsorship-subscription-id>'

az account set --subscription "$ALZ_SUBSCRIPTION_ID"
az account show \
  --query '{name:name,id:id,tenantId:tenantId,state:state}' \
  --output table

az resource list \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --query '[].{name:name,type:type,resourceGroup:resourceGroup,location:location}' \
  --output table

az policy assignment list \
  --scope "/subscriptions/$ALZ_SUBSCRIPTION_ID" \
  --disable-scope-strict-match \
  --query '[].{name:name,scope:scope,enforcementMode:enforcementMode}' \
  --output table

az lock list \
  --scope "/subscriptions/$ALZ_SUBSCRIPTION_ID" \
  --output table
```

In the portal, record the subscription's current parent management group as `ORIGINAL_MANAGEMENT_GROUP_ID`. Also inventory existing regions, Policy exemptions, budgets, production resources and resource locks.

If the subscription contains important workloads that must not inherit experimental Policy or RBAC, keep `move_subscriptions_into_hierarchy = false` and skip the management-group inheritance exercises. The platform networking exercises can still run, but use a unique prefix and review every plan.

## 3. Prepare the single-subscription configuration

Create local files; they are ignored by Git. The following `cp` commands replace any active `terraform.tfvars` files, so preserve an existing route-specific configuration before running them.

```bash
cp terraform/subscriptions.single.tfvars.example terraform/subscriptions.single.tfvars
cp terraform/00-bootstrap/terraform.single.tfvars.example terraform/00-bootstrap/terraform.tfvars
cp terraform/10-governance/terraform.single.tfvars.example terraform/10-governance/terraform.tfvars
cp terraform/20-platform/terraform.single.tfvars.example terraform/20-platform/terraform.tfvars
```

Edit `terraform/subscriptions.single.tfvars` and replace all nine placeholders with the same `ALZ_SUBSCRIPTION_ID`. The file already sets:

```hcl
allow_shared_subscription_ids = true
```

Set `management_subscription_id` in `terraform/00-bootstrap/terraform.tfvars` to the same ID. Keep these initial safety settings in the governance file:

```hcl
move_subscriptions_into_hierarchy    = false
single_subscription_management_group_key = "corp"
enforce_allowed_locations_policy     = false
public_ip_policy_effect               = "Audit"
```

`enforce_allowed_locations_policy = false` creates the assignment in `DoNotEnforce` mode. Do not enable the Deny behavior until every existing resource and required deployment region has been reviewed.

## 4. Bootstrap remote state with single-mode keys

```bash
terraform -chdir=terraform/00-bootstrap init
terraform -chdir=terraform/00-bootstrap fmt -check
terraform -chdir=terraform/00-bootstrap validate
terraform -chdir=terraform/00-bootstrap plan -out=tfplan
terraform -chdir=terraform/00-bootstrap apply tfplan

./scripts/init-backends.sh --mode single
```

Single mode uses `10-governance-single.tfstate` and `20-platform-single.tfstate`. The normal multi-subscription route keeps its original keys. Never change one state directly from repeated IDs to nine different subscription IDs.

## 5. Create and inspect governance before moving the subscription

```bash
terraform -chdir=terraform/10-governance fmt -check
terraform -chdir=terraform/10-governance validate
terraform -chdir=terraform/10-governance plan \
  -var-file=../subscriptions.single.tfvars \
  -out=tfplan
terraform -chdir=terraform/10-governance show tfplan
terraform -chdir=terraform/10-governance apply tfplan

terraform -chdir=terraform/10-governance output hierarchy
terraform -chdir=terraform/10-governance output actual_subscription_placement
```

The hierarchy and assignments now exist, but `actual_subscription_placement` is empty. Confirm that the Allowed Locations assignment is `DoNotEnforce` and the public-IP policy is `Audit`.

Only after checking the inventory and plan, set:

```hcl
move_subscriptions_into_hierarchy = true
```

Plan and apply again. The root manages exactly one association and places the subscription under `Corp`:

```bash
terraform -chdir=terraform/10-governance plan \
  -var-file=../subscriptions.single.tfvars \
  -out=tfplan
terraform -chdir=terraform/10-governance apply tfplan
terraform -chdir=terraform/10-governance output actual_subscription_placement

az account management-group subscription show \
  --name alz1sub-landingzones-corp \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --output table
```

Changing `single_subscription_management_group_key` to `online`, `sandbox`, `management`, `connectivity`, `identity` or `security` moves the **whole subscription**. Use that only as a controlled inheritance exercise; it does not split the logical resource groups across branches.

## 6. Deploy the cost-controlled platform baseline

The first platform apply creates a hub and spoke, NSG, private Storage account and endpoint, Private DNS, Log Analytics and a small private VM. These resources have a cost even though Firewall, VPN and Sentinel are disabled.

```bash
terraform -chdir=terraform/20-platform fmt -check
terraform -chdir=terraform/20-platform validate
terraform -chdir=terraform/20-platform plan \
  -var-file=../subscriptions.single.tfvars \
  -out=tfplan
terraform -chdir=terraform/20-platform show tfplan
terraform -chdir=terraform/20-platform apply tfplan
terraform -chdir=terraform/20-platform output
```

All provider aliases use the same subscription, but taggable resources carry an `alz-role` tag. Verify the logical boundaries:

```bash
az group list \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --query "[?starts_with(name, 'rg-alz1sub-')].{name:name,location:location}" \
  --output table

az resource list \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --tag 'alz-role=connectivity' \
  --query '[].{name:name,type:type,resourceGroup:resourceGroup}' \
  --output table
```

In Cost Analysis, group by Resource group and by the `alz-role` tag. In this mode Terraform creates at most one subscription budget; use the `management` key in `monthly_budget_overrides`. Terraform names the one budget instance `shared`, but it deliberately reads the Management amount rather than selecting a role by map order.

## 7. Run the experiments

### Private Endpoint and DNS failure

```bash
./scripts/test-private-dns.sh

terraform -chdir=terraform/20-platform destroy \
  -var-file=../subscriptions.single.tfvars \
  -target=azurerm_private_dns_zone_virtual_network_link.blob_to_spoke

./scripts/test-private-dns.sh

terraform -chdir=terraform/20-platform apply \
  -var-file=../subscriptions.single.tfvars
```

The first lookup should resolve the Storage FQDN through its public CNAME to a private `10.1.1.x` address. With the link removed, resolution changes and public network access remains disabled. Use `-target` only for this controlled failure.

### Policy inheritance and Deny

With the subscription under `Corp`, set `public_ip_policy_effect = "Deny"`, plan, apply, and wait for Policy propagation. Then run a disposable public-IP deployment:

```bash
az group create \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --name rg-alz1sub-policy-test \
  --location australiaeast

az vm create \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --resource-group rg-alz1sub-policy-test \
  --name vm-should-be-denied \
  --image Ubuntu2404 \
  --public-ip-address pip-policy-test \
  --generate-ssh-keys

az group delete \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --name rg-alz1sub-policy-test \
  --yes --no-wait
```

The VM operation should be denied. Capture the Policy assignment and definition IDs from the error. If it succeeds, verify the subscription's Corp placement, confirm the governance apply used `"Deny"`, trigger a Policy scan, and retry only after propagation.

Keep Allowed Locations in `DoNotEnforce` until the subscription inventory is safe. To test it, deliberately choose an unapproved region in a reviewed disposable deployment, set `enforce_allowed_locations_policy = true`, apply, capture the denial, and immediately return it to `false`.

### DINE Activity Log remediation

Copy the platform output into the governance configuration:

```bash
terraform -chdir=terraform/20-platform output -raw log_analytics_workspace_id
```

Set `log_analytics_workspace_id`, plan and apply governance, then trigger evaluation and remediation:

```bash
az policy state trigger-scan --subscription "$ALZ_SUBSCRIPTION_ID"

az policy state summarize \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --output table

ASSIGNMENT_ID=$(terraform -chdir=terraform/10-governance \
  output -raw activity_log_policy_assignment_id)
POLICY_PRINCIPAL_ID=$(terraform -chdir=terraform/10-governance \
  output -raw activity_log_policy_identity_principal_id)

az role assignment list \
  --assignee-object-id "$POLICY_PRINCIPAL_ID" \
  --scope '/providers/Microsoft.Management/managementGroups/alz1sub' \
  --include-inherited \
  --query '[].{role:roleDefinitionName,scope:scope}' \
  --output table

az policy remediation create \
  --name remediate-activity-log-single \
  --management-group alz1sub \
  --policy-assignment "$ASSIGNMENT_ID" \
  --resource-discovery-mode ReEvaluateCompliance

az policy remediation show \
  --name remediate-activity-log-single \
  --management-group alz1sub \
  --output table

az monitor diagnostic-settings subscription list \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --output table
```

This demonstrates the assignment identity, its Monitoring Contributor role, compliance evaluation and remediation. It does not demonstrate collection from several subscriptions.

### RBAC inheritance

Use an existing Entra test group, not an individual production identity. If you have permission to create groups, the following makes a disposable one; otherwise ask the directory owner for a test-group object ID:

```bash
az ad group create \
  --display-name alz1sub-corp-readers \
  --mail-nickname alz1sub-corp-readers

TEST_GROUP_OBJECT_ID=$(az ad group show \
  --group alz1sub-corp-readers \
  --query id --output tsv)
printf 'Test group object ID: %s\n' "$TEST_GROUP_OBJECT_ID"
```

Add this entry to `terraform/10-governance/terraform.tfvars`, replace the placeholder, then plan and apply governance:

```hcl
role_assignments = {
  single_corp_reader = {
    scope_key            = "corp"
    principal_id         = "<test-group-object-id>"
    role_definition_name = "Reader"
  }
}
```

Inspect the inherited assignment:

```bash
az role assignment list \
  --scope "/subscriptions/$ALZ_SUBSCRIPTION_ID" \
  --include-inherited \
  --query '[].{principal:principalName,role:roleDefinitionName,scope:scope}' \
  --output table
```

Management-, Connectivity- and Security-branch roles do not simultaneously govern similarly named resource groups while the subscription is under Corp. Use resource-group RBAC for logical team separation, or move the whole subscription between branches as a sequential inheritance experiment.

Terraform removes the role assignment during governance cleanup. Delete the disposable Entra group separately after the exercise if it is no longer needed:

```bash
az ad group delete --group alz1sub-corp-readers
```

### Routing and Firewall

Capture the baseline, then enable Firewall for a short session:

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-baseline.txt
./scripts/test-egress.sh

# Set enable_firewall = true in terraform/20-platform/terraform.tfvars.
terraform -chdir=terraform/20-platform plan \
  -var-file=../subscriptions.single.tfvars \
  -out=tfplan
terraform -chdir=terraform/20-platform show tfplan
terraform -chdir=terraform/20-platform apply tfplan

./scripts/show-effective-routes.sh | tee /tmp/alz-routes-firewall.txt
diff -u /tmp/alz-routes-baseline.txt /tmp/alz-routes-firewall.txt
./scripts/test-egress.sh
```

The pre-Firewall egress result is observational. New VNet API versions after 31 March 2026 default to private subnets, so both public destinations can fail until an explicit outbound method exists. After Firewall is enabled, use its route and logs to prove the explicit path.

Use Firewall logs to prove why a request was allowed or blocked. Run `./scripts/destroy-expensive.sh` when the session ends.

### Simulated hybrid routing

VPN gateways are expensive and slow to provision. If explicitly approved, set the following locally, then review and apply the platform plan:

```hcl
enable_firewall         = false
enable_vpn_gateway      = true
enable_simulated_onprem = true
enable_test_vm          = true
vpn_shared_key          = "<local-value-at-least-16-characters>"
```

The preceding Firewall cleanup removes the test VM and NIC. `enable_test_vm = true` recreates the NIC required by `show-effective-routes.sh` in the same apply as the gateway topology.

```bash
terraform -chdir=terraform/20-platform plan \
  -var-file=../subscriptions.single.tfvars \
  -out=tfplan
terraform -chdir=terraform/20-platform show tfplan
terraform -chdir=terraform/20-platform apply tfplan

CONNECTIVITY_SUB=$(terraform -chdir=terraform/20-platform output -raw connectivity_subscription_id)
SANDBOX_SUB=$(terraform -chdir=terraform/20-platform output -raw sandbox_subscription_id)

az network vpn-connection list \
  --subscription "$CONNECTIVITY_SUB" \
  --query '[].{name:name,resourceGroup:resourceGroup,status:connectionStatus}' \
  --output table

az network vpn-connection list \
  --subscription "$SANDBOX_SUB" \
  --query '[].{name:name,resourceGroup:resourceGroup,status:connectionStatus}' \
  --output table

./scripts/show-effective-routes.sh
```

In single mode both subscription IDs are the same, so the second connection query is intentionally redundant. The current topology has no simulated on-prem VM: validate both connection states and `VirtualNetworkGateway` routes rather than claiming an end-to-end application test. Remove both gateways and the test VM immediately after collecting evidence:

```bash
./scripts/destroy-expensive.sh
```

Restore `enable_vpn_gateway`, `enable_simulated_onprem` and `enable_test_vm` to `false` in `terraform/20-platform/terraform.tfvars`.

### Pipeline and idempotency

Follow the [Azure Pipelines lab](../azure-devops/README.md). Set `ALLOW_SHARED_SUBSCRIPTION_IDS=true`, set `TF_BACKEND_KEY=20-platform-single.tfstate` for the Platform pipeline, and make every value in `SUBSCRIPTION_IDS_JSON` the existing subscription ID. A separate Governance pipeline must use `10-governance-single.tfstate`; never share a key between roots or modes. For example:

```json
{"management":"<same-id>","connectivity":"<same-id>","identity":"<same-id>","security":"<same-id>","corp_dev":"<same-id>","corp_prod":"<same-id>","online_dev":"<same-id>","online_prod":"<same-id>","sandbox":"<same-id>"}
```

The service connection needs access to only that subscription plus the state container and relevant management-group scopes. Keep the apply environment approval enabled and verify that the pipeline applies the published plan artifact rather than generating a new plan after approval.

For the quota-limited profile, use the same template with
`ALLOW_SHARED_SUBSCRIPTION_IDS=false`,
`ALLOW_LOGICAL_WORKLOAD_SUBSCRIPTION_IDS=true`,
`TF_BACKEND_KEY=20-platform-quota-limited.tfstate` (or the governance key),
and the JSON from `subscriptions.quota-limited.tfvars`. The federated identity
must have only the four platform subscriptions plus the protected workload
subscription and state container. Do not grant the pipeline permission to
delete subscriptions or to manage organization resource groups.

After every stable stage, run another plan. Exit code `0` means no drift, `2` means changes, and `1` means an error:

```bash
terraform -chdir=terraform/20-platform plan \
  -detailed-exitcode \
  -var-file=../subscriptions.single.tfvars
```

## 8. Cost controls and session closeout

Single-subscription consolidation does not make services cheaper. It only places their usage on one invoice and quota boundary.

- Baseline costs can include the test VM and disk, Private Endpoint, Storage transactions/capacity, and Log Analytics ingestion.
- Firewall, both VPN gateways, Sentinel ingestion and enabled security services need explicit time-boxing.
- Configure one subscription budget through the governance root. Budgets alert but do not stop resource consumption.
- Review Cost Analysis by resource group and `alz-role`; cost and tag data can take time to appear.
- Keep every cost switch `false` outside its exercise.

At the end of each session, inspect the active lab resources and Terraform's cost-feature output:

```bash
terraform -chdir=terraform/20-platform output enabled_cost_features

az resource list \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --tag lab=true \
  --query '[].{name:name,type:type,resourceGroup:resourceGroup}' \
  --output table

az consumption budget list \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --output table
```

If any hourly feature was enabled, run `./scripts/destroy-expensive.sh`, then also restore its Terraform switch to `false`.

## 9. Official Accelerator: review only with one subscription

One subscription does not prevent learning the official Accelerator's planning and generated configuration, but it does prevent a supported Platform landing zone apply. Do not pass the same GUID as Management, Connectivity, Identity and Security, and do not use this repository's four-subscription wrapper.

You may generate Scenario 5 files in an isolated review folder:

```powershell
$reviewPath = './accelerator/work-single-sub-review'
Import-Module ALZ -Force
Test-AcceleratorRequirement
New-AcceleratorFolderStructure `
  -iacType 'terraform' `
  -versionControl 'local' `
  -scenarioNumber 5 `
  -targetFolderPath $reviewPath

Get-ChildItem "$reviewPath/config" -Recurse
Select-String `
  -Path "$reviewPath/config/inputs.yaml", "$reviewPath/config/platform-landing-zone.tfvars" `
  -Pattern 'subscription_ids|subscription_placement|connectivity_type|management_resources_enabled|management_groups_enabled|enableAsc'
```

Stop after configuration review. Do not execute `Deploy-Accelerator` or Phase 3 apply. Record the ALZ module version, scenario, generated differences, missing Connectivity subscription and the resulting no-go decision. After at least two subscriptions become available, evaluate the official SMB scenarios; with four platform subscriptions, follow [the full Accelerator exercise](06-alz-accelerator.md). [Official platform-subscription prerequisites](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/platform-subscriptions/)

## 10. Cleanup and later migration

Before Terraform teardown, list subscription-level diagnostic settings. A DINE remediation creates a resource outside the Terraform state; destroying its Policy assignment does not necessarily remove that deployed setting:

```bash
az monitor diagnostic-settings subscription list \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --query 'value[].{name:name,workspaceId:properties.workspaceId}' \
  --output table

# Delete only the setting that points to this lab's workspace.
az monitor diagnostic-settings subscription delete \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --name '<lab-activity-log-diagnostic-setting-name>'
```

Do not delete pre-existing organization diagnostic settings. Then remove hourly billed components and destroy only the manual Terraform resources. For the single-subscription route use:

```bash
./scripts/destroy-expensive.sh
./scripts/nuke-everything.sh --mode single
```

For the quota-limited route, use the matching manifest and state key:

```bash
./scripts/nuke-everything.sh --mode quota-limited
```

The script shows a separate destroy plan for Platform and Governance and asks
for `apply-destroy` after each plan. The quota-limited cleanup never deletes a
subscription and must not delete an organization-owned resource, diagnostic
setting, lock or resource group. If a lab resource group contains an unrelated
resource, stop and remove the lab resource from Terraform state or obtain an
owner-approved resource-level plan; do not force-delete the group. Keep all
five subscriptions for later official Accelerator use or normal organizational
operations.

The full teardown removes the managed association, but Azure does not promise to restore the subscription's previous parent. Verify the resulting parent and restore `ORIGINAL_MANAGEMENT_GROUP_ID` if required:

```bash
az account management-group subscription add \
  --name '<original-management-group-id>' \
  --subscription "$ALZ_SUBSCRIPTION_ID"
```

If the original parent was the Tenant Root Group and the subscription has already returned there, no restore command is required. Wait for management-group propagation and verify the result in the portal before deleting the recorded inventory.

The bootstrap state storage is deliberately retained. Only after both single-mode state files are unused and the platform/governance resources are gone should you run:

```bash
terraform -chdir=terraform/00-bootstrap plan -destroy -out=destroy.tfplan
terraform -chdir=terraform/00-bootstrap apply destroy.tfplan
```

Before migrating to multi-subscription or the official Accelerator:

1. Destroy only the manual lab resources using their original manifest and state; never delete the existing workload subscription.
2. Verify that no lab resources, Policy assignments, associations or role assignments remain, while organization-owned settings remain intact.
3. Keep the four platform subscriptions and start the official Accelerator from a clean generated repository, or create a nine-unique-ID manifest only after a future quota increase.
4. Run `./scripts/init-backends.sh --mode multi` only when the nine-role manual route is genuinely approved and available.

Do not replace the repeated IDs with unique IDs in the existing single-mode state. That can propose cross-subscription recreation and does not constitute an ALZ migration.
