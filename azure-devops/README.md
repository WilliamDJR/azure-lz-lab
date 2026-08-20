# Azure DevOps Hands-on Lab

[中文版](README_cn.md)

This is a short practical lab for learning how Azure Pipelines works in concrete terms. For the concept mapping and the three expression syntaxes, see [`../docs/03-azure-devops.md`](../docs/03-azure-devops.md).

## Files

| File | Purpose | GitHub Actions equivalent |
|---|---|---|
| `azure-pipelines.yml` | Consumer pipeline using `extends` | Caller of a reusable workflow |
| `templates/stages/terraform-plan-apply.yml` | Stage template owned by the platform team | Reusable workflow, with stronger governance |
| `templates/steps/terraform-setup.yml` | Step-level template | Composite action |

## Run it in about 30 minutes

```bash
# 1. Create an Azure DevOps organization and project
open https://dev.azure.com          # A Microsoft account is sufficient

# 2. Project settings -> Service connections -> New
#    Azure Resource Manager -> Workload Identity federation (automatic)
#    Name it sc-azure-alzlab and point it at your subscription.
#    This provides secretless authentication.

# 3. Pipelines -> Library -> + Variable group
#    Name it platform-common and add:
#      TF_VERSION, TF_BACKEND_RESOURCE_GROUP, TF_BACKEND_STORAGE_ACCOUNT,
#      TF_BACKEND_CONTAINER, TF_BACKEND_KEY, SUBSCRIPTION_IDS_JSON,
#      ALLOW_SHARED_SUBSCRIPTION_IDS, and
#      ALLOW_LOGICAL_WORKLOAD_SUBSCRIPTION_IDS.
#    SUBSCRIPTION_IDS_JSON is the JSON object matching terraform/subscriptions.tfvars.
#    Use false for multi-subscription mode and true only for the documented
#    single-subscription track.
#    Set ALLOW_LOGICAL_WORKLOAD_SUBSCRIPTION_IDS=true only for the
#    quota-limited profile (four distinct platform IDs plus one protected
#    existing workload ID); otherwise keep it false.
#    Single mode must use 10-governance-single.tfstate or
#    20-platform-single.tfstate as appropriate.
#    Quota-limited mode must use 10-governance-quota-limited.tfstate or
#    20-platform-quota-limited.tfstate as appropriate.

# 4. Pipelines -> Environments -> New environment
#    Name it alz-lab -> Approvals and checks -> Approvals -> add yourself.

# 5. Push this repository to Azure Repos, then choose
#    Pipelines -> New pipeline -> azure-pipelines.yml.
```

`azure-pipelines.yml` references a separate `Platform/pipeline-templates` repository through `resources.repositories`. For a single-repository lab, remove the `resources` block and use a local relative path:

```yaml
extends:
  template: templates/stages/terraform-plan-apply.yml
  parameters:
    ...
```

In production, keep shared templates in a separate repository and pin consumers to a tag. One template change can affect every consuming repository, so versioning is essential for controlling blast radius.

The workload identity behind the service connection must have the required least-privilege roles in every subscription used by the provider aliases, plus Blob Data access to the state container. Scoping the Azure DevOps service connection to Management alone does not automatically grant access to Connectivity, Security, Corp Dev, or Sandbox.

Never point single- and multi-subscription runs, or the Governance and Platform roots, at the same `TF_BACKEND_KEY`. Separate keys prevent one simulated layout from overwriting another root's state.

## What to observe

1. The **Validate -> Plan -> Apply** stage dependencies, and the Apply stage waiting at the approval gate. Azure DevOps adds a stage level above jobs.
2. The plan is published as an artifact and the Apply stage downloads and runs that exact plan file. Approval is meaningful only when the reviewed plan is the plan that executes.
3. `addSpnToEnvironment: true` exposes the federated `$servicePrincipalId` and `$idToken`. Terraform consumes them through `ARM_USE_OIDC`; no long-lived secret is stored.

## Common troubleshooting cases

| Symptom | Likely cause |
|---|---|
| A variable referenced inside `${{ }}` is empty | Template expressions run at compile time and cannot see values produced at runtime. Use `$[ ]` or `$( )` as appropriate. |
| A deployment job runs without pausing for approval | Approval belongs to the **environment**, not the pipeline. Check that the environment name matches. |
| Template reference reports `repository not found` | `resources.repositories.name` must use `ProjectName/RepositoryName`, and the pipeline must be authorized to access it. |
