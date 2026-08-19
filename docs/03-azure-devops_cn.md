# 03 · 面向 GitHub Actions 使用者的 Azure DevOps

[English](03-azure-devops.md)

本章把可复用 CI/CD 平台概念映射到 Azure Pipelines，并说明它与 GitHub Actions 不同的语法和运营控制。可运行示例位于 `azure-devops/`。

---

## 1. 概念映射

| GitHub Actions | Azure DevOps | 主要差异 |
|---|---|---|
| Repository | **Azure Repos**，或连接的 GitHub Repository | 一个 ADO Project 可以包含多个 Repository |
| Workflow | Pipeline，文件通常为 `azure-pipelines.yml` | 一个 Repository 可以注册多条指向不同 YAML 文件的 Pipeline |
| `on:` | `trigger:`、`pr:`、`schedules:` | PR 执行还取决于 Branch Policy |
| Job | **Stage -> Job -> Step** | ADO 增加了 Stage 抽象 |
| Step 或 Action | Step 或 **Task** | `AzureCLI@2` 等 Task 是封装的 ADO 集成 |
| Reusable workflow | 通过 `extends:` 或 `- template:` 使用的 **Template** | `extends` 可以控制消费方的完整结构 |
| Composite action | Step Template | |
| Runner | Agent Pool 中的 **Agent** | 提供 Microsoft-hosted 和 Self-hosted 选项 |
| Repository/Organization Secret | **Variable Group**，可由 Key Vault 支持 | Project Scope 的共享对象 |
| Environment 与 Protection Rule | 带 Approval 和 Check 的 **Environment** | 包括业务时间、REST 调用、Azure Monitor Check 和 Template Check |
| 云端 OIDC | 使用 Workload Identity Federation 的 **Service Connection** | 使用短期身份，不保存 Client Secret |
| GitHub Packages | **Azure Artifacts** | |
| `${{ }}` | `${{ }}`、`$[ ]` 和 `$(var)` | 三个求值阶段 |
| 无直接对应项 | **Boards 与 Test Plans** | 集成规划与手工测试管理 |
| 无直接对应项 | **Classic Release Pipeline** | 遗留的 UI 定义部署 Pipeline |

## 2. Azure Pipelines 核心概念

### 2.1 表达式语法与求值时间

```yaml
variables:
  buildConfig: Release

steps:
  # ${{ }}：编译期 Template 展开。
  # 可以生成或省略 Pipeline 结构，但无法读取运行期值。
  - ${{ if eq(variables['Build.SourceBranchName'], 'main') }}:
    - script: echo "only compiled into the plan on main"

  # $[ ] 和 Condition：运行期求值，包括前一个 Job 的输出。
  - script: echo "runtime"
    condition: and(succeeded(), eq(variables['Build.Reason'], 'PullRequest'))

  # $( )：Step 执行前进行宏替换。
  - script: echo "Building $(buildConfig)"
```

可以采用以下模型：

- `${{ }}` 决定**生成哪些 Pipeline 结构**。
- 运行期表达式和 Condition 决定**已生成的项目是否执行**。
- `$( )` 决定**Step 执行时替换哪个值**。

GitHub Actions 使用 `${{ }}` 承担其中多个角色，因此求值时间是迁移错误的常见来源。

### 2.2 `extends` Template

```yaml
# 消费方可以提供获准参数，但不控制整体结构。
extends:
  template: templates/stages/terraform.yml@platform-templates
  parameters:
    environment: production
    workingDirectory: terraform/20-platform
```

使用 `extends` 时，Template 定义**完整 Pipeline 结构**。平台团队可以：

- 在每次部署前插入强制安全扫描。
- 通过 Template 结构和验证限制可以出现的 Task 类型。
- 在 Environment 或 Service Connection 上增加 **Required Template Check**，确保只有经过批准的 Template 才能访问生产资源。

Reusable Workflow 由仍然控制外围 Workflow 的调用方调用；`extends` Template 则成为调用方的整体结构。这一区别使 Azure Pipelines 能够支持集中治理的自助交付。

### 2.3 Variable Group、Service Connection 与 Environment

这些是 Project 级 Azure DevOps 对象，而不是普通 YAML 声明：

- **Variable Group**：位于 Pipelines -> Library 的共享变量。它可以链接 Azure Key Vault，并在需要时读取 Secret 值。
- **Service Connection**：Task 使用的 Azure 身份。优先使用 Workload Identity Federation，由 Azure DevOps 使用 OIDC Token 换取短期 Entra 凭据，不保存长期 Client Secret。
- **Environment**：携带 Approval 和 Check 的抽象部署目标，例如人工审批、业务时间、Azure Monitor 状态、REST 验证与 Required Template。

## 3. 实操路径

1. 在 `dev.azure.com` 创建 Azure DevOps Organization 和 Project。
2. 把包含 `azure-devops/` 的 Repository 推送到 Azure Repos，或连接 GitHub Repository。
3. 使用 **Workload Identity federation (automatic)** 创建 Azure Resource Manager Service Connection，并把 Scope 限制到实验订阅。
4. 创建名为 `platform-common` 的 Variable Group，加入 `TF_VERSION` 等非敏感值；可以另行比较连接 Key Vault 的 Variable Group。
5. 创建名为 `alz-lab` 或 `production` 的 Environment，并增加人工 Approval Check。
6. 把 `azure-devops/azure-pipelines.yml` 注册为 Pipeline 并运行。
7. 验证 Validate 和 Plan 自动运行，Apply 等待 Environment Approval。

新建 Organization 可能不会立即获得 Microsoft-hosted Parallel Job 配额。Self-hosted Agent 是一种替代方式，也适用于 Pipeline 必须访问私网资源的环境。

## 4. 从 Jenkins 或 GitHub Actions 迁移

迁移应作为平台整合处理，而不是逐行转换语法：

1. **先识别公共 Pipeline 形态。** 大量 Jenkinsfile 通常只代表少数交付模式。为每种模式建立 Template，再把 Repository 映射到相应 Template。
2. **对独立 Template Repository 进行版本管理。** 消费方应固定到 `refs/tags/v1.2.0`，而不是 `main`，避免一次 Template 变更同时影响全部 Repository。
3. **并行运行新旧 Pipeline。** 切换前比较 Artifact 和行为。
4. **提供自助接入。** 目标是缩短新 Repository 的接入周期，而不只是生成转换后的 YAML。
5. **把文档和 Runbook 作为交付物。** 其他团队使用的平台必须包含运营说明。

语法转换只是迁移的一部分。长期价值来自用少量有版本且受治理的 Template 替换大量手工维护的 Pipeline。

## 5. KQL 快速参考

```kusto
// 被 Firewall 拒绝的请求
AZFWApplicationRule
| where TimeGenerated > ago(1h)
| where Action == "Deny"
| summarize count() by Fqdn, SourceIp
| order by count_ desc

// 订阅中的资源变更
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationNameValue contains "WRITE"
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup, ActivityStatusValue
| order by TimeGenerated desc

// 不合规 Policy 资源
// 该查询在 Azure Resource Graph 而不是 Log Analytics 中运行。
policyresources
| where type == "microsoft.policyinsights/policystates"
| where properties.complianceState == "NonCompliant"
| summarize count() by tostring(properties.policyDefinitionName)
```

KQL 的核心构件包括管道操作符、`where`、`summarize ... by`、`project` 和 `ago()` 等时间函数。

## 6. Azure DevOps 与 GitHub 的产品定位

Microsoft 的 2026 指南把最新 Agentic Development 能力放在 GitHub，同时继续在安全、代码质量、Boards、Pipelines 和 Test Plans 方面支持并改进 Azure DevOps。组织也可以采用混合模式：源代码位于 GitHub，同时保留 Azure Boards 和 Azure Pipelines。

当前相关信号包括：

1. 对于符合条件的用户，GitHub Enterprise 包含 Azure DevOps Basic 使用权。
2. Enterprise Live Migrations 可以在短暂受控切换期间把 Azure DevOps Repository 迁移到 GitHub，同时保留 Boards/Pipelines 混合模式。
3. Azure DevOps 持续发布 Service Update 和公开 Roadmap，尚未公布生命周期结束日期。

Azure DevOps 仍是受支持的企业平台，而最新 Agentic 源代码工作流会优先在 GitHub 提供。

### 支持保留 Azure DevOps 的能力

| 能力 | 作用 |
|---|---|
| **Azure Boards** | 层级 Work Item、跨 Project Portfolio View、Iteration、Capacity Planning 与 Analytics 集成 |
| **Azure Test Plans** | 为受监管交付流程管理手工 Test Case 和测试证据 |
| **Pipelines extends Template 与 Required Template Check** | 集中控制消费方 Pipeline 结构和生产 Service Connection |
| **Classic Release Pipeline** | 遗留环境可能依赖该能力，迁移时需要显式重写 |
| **Azure Artifacts Upstream Source** | 集成 Package Feed 和上游依赖缓存 |

### 评估组织方向的标准

不能只因为存在新平台就决定迁移。应先识别：

- 团队当前依赖哪些 Azure DevOps 能力。
- 源代码迁移能否带来足以覆盖成本和风险的收益。
- 哪些 Boards、Pipelines、Test Plans、身份、合规与审计集成必须保留。
- GitHub Repository 加 Azure Boards/Pipelines 的混合模式能否降低迁移风险。
- Template、Artifact、权限和 Branch Policy 如何在规模化迁移中统一并验证。

大规模 CI/CD 迁移除了语法转换，还需要 Template 设计、版本管理、并行验证与受控发布。

### 建议掌握范围

建议范围包括以下能力：

1. 准确描述和排查 Azure Pipelines，而不只是映射 GitHub Actions 名称。
2. 安全维护和治理现有 Azure DevOps 平台。
3. 根据证据评估保留、集成或迁移部分平台的方案。

## 7. Accelerator 生成的交付体系

`azure-devops/` 中的 Pipeline 是精简教学示例。官方 ALZ IaC Accelerator 可以把 Azure DevOps Repository、Federated Identity、Terraform Remote State 和 Platform Landing Zone 交付 Pipeline 作为一个经过审查的系统进行 Bootstrap。

完成本实验后继续阅读 [06-alz-accelerator_cn.md](06-alz-accelerator_cn.md)。可以比较控制点，但不要用该示例 Pipeline 覆盖 Accelerator 生成的 Repository；应升级和运营官方生成的 Repository，并把它作为平台事实来源。

## 官方参考

- [Azure DevOps and GitHub: Journeying into the AI Era](https://devblogs.microsoft.com/devops/azure-devops-and-github-journeying-into-the-ai-era/)
- [Azure DevOps Roadmap](https://learn.microsoft.com/azure/devops/release-notes/features-timeline)
- [Enterprise Live Migrations 概览](https://learn.microsoft.com/azure/devops/repos/enterprise-live-migrations/overview)
