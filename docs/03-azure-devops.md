# 03 · Azure DevOps for GitHub Actions Users

[中文版](03-azure-devops_cn.md)

> You already understand reusable CI/CD platform design. This chapter focuses on the Azure Pipelines concepts and syntax that differ from GitHub Actions. Runnable examples are in `azure-devops/`.

---

## 1. Concept map

| GitHub Actions | Azure DevOps | Key difference |
|---|---|---|
| Repository | **Azure Repos**, or a connected GitHub repo | An ADO project can contain multiple repositories |
| Workflow | Pipeline, commonly `azure-pipelines.yml` | A repository can register multiple pipelines pointing at different YAML files |
| `on:` | `trigger:`, `pr:`, `schedules:` | PR execution also depends on branch policies |
| Job | **Stage -> job -> step** | ADO adds the stage abstraction |
| Step or action | Step or **task** | Tasks such as `AzureCLI@2` are packaged ADO integrations |
| Reusable workflow | **Template**, through `extends:` or `- template:` | `extends` can own the entire consumer structure |
| Composite action | Step template | |
| Runner | **Agent** in an **agent pool** | Microsoft-hosted and self-hosted options |
| Repository/organization secrets | **Variable group**, optionally backed by Key Vault | A project-scoped shared object |
| Environments and protection rules | **Environments with approvals and checks** | Includes business hours, REST calls, Azure Monitor checks, and template checks |
| OIDC to cloud | **Service connection** with workload identity federation | Short-lived identity without a client secret |
| GitHub Packages | **Azure Artifacts** | |
| `${{ }}` | `${{ }}`, `$[ ]`, and `$(var)` | Three evaluation phases |
| No direct equivalent | **Boards and Test Plans** | Integrated planning and manual test management |
| No direct equivalent | **Classic release pipeline** | Legacy UI-defined deployment pipelines |

## 2. The three areas to learn first

### 2.1 Expression syntax and evaluation time

```yaml
variables:
  buildConfig: Release

steps:
  # ${{ }}: compile-time template expansion.
  # It can generate or omit pipeline structure, but cannot see runtime values.
  - ${{ if eq(variables['Build.SourceBranchName'], 'main') }}:
    - script: echo "only compiled into the plan on main"

  # $[ ] and conditions: runtime evaluation, including previous-job output.
  - script: echo "runtime"
    condition: and(succeeded(), eq(variables['Build.Reason'], 'PullRequest'))

  # $( ): macro substitution immediately before the step runs.
  - script: echo "Building $(buildConfig)"
```

A useful model is:

- `${{ }}` decides **what pipeline structure is generated**.
- Runtime expressions and conditions decide **whether a generated item runs**.
- `$( )` decides **which value is substituted when a step runs**.

GitHub Actions uses `${{ }}` for several of these roles, so evaluation time is a common source of migration errors.

### 2.2 `extends` templates

```yaml
# The consumer can provide approved parameters but does not own the structure.
extends:
  template: templates/stages/terraform.yml@platform-templates
  parameters:
    environment: production
    workingDirectory: terraform/20-platform
```

With `extends`, the template defines the **entire pipeline structure**. A platform team can:

- Insert mandatory security scanning before every deployment.
- Restrict which task types can appear through template structure and validation.
- Add a **required template check** to an environment or service connection, ensuring production access is possible only through an approved template.

A reusable workflow is invoked by a caller that still controls the surrounding workflow. An extends template becomes the caller's structure. This distinction makes Azure Pipelines particularly useful for centrally governed self-service.

### 2.3 Variable groups, service connections, and environments

These are project-level Azure DevOps objects rather than ordinary YAML declarations:

- **Variable group**: shared variables under Pipelines -> Library. A group can link to Azure Key Vault so secret values are retrieved when needed.
- **Service connection**: the Azure identity used by tasks. Prefer workload identity federation, where Azure DevOps exchanges an OIDC token for short-lived Entra credentials and stores no long-lived client secret.
- **Environment**: an abstract deployment target carrying approvals and checks, such as manual approval, business hours, Azure Monitor state, REST validation, and required templates.

## 3. Hands-on path

1. Create a free organization and project at `dev.azure.com`.
2. Push the repository, including `azure-devops/`, to Azure Repos or connect a GitHub repository.
3. Create an Azure Resource Manager service connection using **Workload Identity federation (automatic)** and scope it to the lab subscription.
4. Create a variable group named `platform-common`; add non-sensitive values such as `TF_VERSION`. Optionally compare it with a Key Vault-linked group.
5. Create an environment named `alz-lab` or `production` and add a manual approval check.
6. Register `azure-devops/azure-pipelines.yml` as a pipeline and run it.
7. Verify that Validate and Plan run automatically and Apply waits for the environment approval.

New organizations might not immediately have a Microsoft-hosted parallel-job grant. A self-hosted agent is a useful alternative and is common when pipelines must reach private network resources.

## 4. Migrating from Jenkins or GitHub Actions

Treat migration as platform consolidation rather than line-by-line syntax conversion:

1. **Find common pipeline shapes first.** A large set of Jenkinsfiles usually represents only a few delivery patterns. Build a template for each pattern and map repositories to them.
2. **Version a separate template repository.** Consumers should pin `refs/tags/v1.2.0`, not `main`; otherwise one template change reaches every repository simultaneously.
3. **Run old and new pipelines in parallel.** Compare artifacts and behavior before cutover.
4. **Make onboarding self-service.** The valuable output is reduced lead time for a new repository, not merely translated YAML.
5. **Treat documentation and runbooks as deliverables.** They are required for a platform that other teams consume.

The mechanical migration is usually the easy part. The long-term value comes from replacing many hand-maintained pipelines with a small set of versioned, governed templates.

## 5. KQL quick reference

```kusto
// Firewall-denied requests
AZFWApplicationRule
| where TimeGenerated > ago(1h)
| where Action == "Deny"
| summarize count() by Fqdn, SourceIp
| order by count_ desc

// Changes to resources in a subscription
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationNameValue contains "WRITE"
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup, ActivityStatusValue
| order by TimeGenerated desc

// Non-compliant policy resources
// Run this against Azure Resource Graph rather than Log Analytics.
policyresources
| where type == "microsoft.policyinsights/policystates"
| where properties.complianceState == "NonCompliant"
| summarize count() by tostring(properties.policyDefinitionName)
```

Core KQL building blocks are the pipe operator, `where`, `summarize ... by`, `project`, and time functions such as `ago()`.

## 6. Azure DevOps and GitHub positioning

Microsoft's 2026 guidance places the newest agentic development capabilities on GitHub while continuing to support and improve Azure DevOps for security, code quality, Boards, Pipelines, and Test Plans. Organizations can also use a hybrid model: source code in GitHub while retaining Azure Boards and Azure Pipelines.

Relevant current signals include:

1. Azure DevOps Basic usage rights are included with GitHub Enterprise for eligible users.
2. Enterprise Live Migrations can move Azure DevOps repositories to GitHub with a short controlled cutover while preserving a hybrid Boards/Pipelines model.
3. Azure DevOps continues to publish service updates and a public roadmap; it has not been assigned an end-of-life date.

The accurate conclusion is not that Azure DevOps has been abandoned. It is positioned as a stable enterprise platform while the newest agentic source-code workflows arrive first on GitHub.

### Capabilities that can justify retaining Azure DevOps

| Capability | Why it matters |
|---|---|
| **Azure Boards** | Hierarchical work items, cross-project portfolio views, iterations, capacity planning, and analytics integrations |
| **Azure Test Plans** | Managed manual test cases and evidence for regulated delivery processes |
| **Pipelines extends templates and required-template checks** | Strong central control over consumer pipeline structure and production service connections |
| **Classic release pipelines** | Legacy estates may depend on them and require an explicit rewrite to migrate |
| **Azure Artifacts upstream sources** | Integrated package feeds and upstream dependency caching |

### How to evaluate an organization's direction

Do not recommend migration only because a newer platform exists. First identify:

- Which Azure DevOps capabilities teams rely on today.
- Whether source migration unlocks capabilities that justify the cost and risk.
- Which Boards, Pipelines, Test Plans, identity, compliance, and audit integrations must remain.
- Whether a hybrid GitHub repository plus Azure Boards/Pipelines model reduces migration risk.
- How templates, artifacts, permissions, and branch policies will be consolidated and validated at scale.

Large-scale CI/CD migration experience transfers directly: syntax translation is mechanical, while template design, versioning, parallel validation, and safe rollout are the difficult parts.

### How much Azure DevOps depth is useful?

Learn enough to:

1. Describe and troubleshoot Azure Pipelines precisely rather than only mapping names from GitHub Actions.
2. Maintain and govern an existing Azure DevOps platform safely.
3. Assess whether to retain, integrate, or migrate parts of the platform based on evidence.

## 7. Accelerator-generated delivery

The pipeline in `azure-devops/` is a compact teaching example. The official ALZ IaC Accelerator can instead bootstrap an Azure DevOps repository, federated identities, remote Terraform state and the Platform landing zone delivery pipelines as one reviewed system.

Follow [05-alz-accelerator.md](05-alz-accelerator.md) after this lab. Compare the controls, but do not overwrite the generated Accelerator repository with this sample pipeline; upgrade and operate the official generated repository as the platform source of truth.

## Official references

- [Azure DevOps and GitHub: Journeying into the AI Era](https://devblogs.microsoft.com/devops/azure-devops-and-github-journeying-into-the-ai-era/)
- [Azure DevOps roadmap](https://learn.microsoft.com/azure/devops/release-notes/features-timeline)
- [Enterprise Live Migrations overview](https://learn.microsoft.com/azure/devops/repos/enterprise-live-migrations/overview)
