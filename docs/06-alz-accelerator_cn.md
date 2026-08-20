# 06 · Microsoft ALZ IaC Accelerator 实操

[English](06-alz-accelerator.md)

本阶段在理解教学部署之后使用官方 Microsoft ALZ IaC Accelerator；如果要实际部署 Accelerator，应先清理教学实现。它不是第二套自建 ALZ：生成的 Terraform Starter 配置、Bootstrap 资源和交付资产来自官方 ALZ PowerShell 模块及基于 AVM 的 Starter Module。

现在必须根据 Azure 实际允许的订阅数量选择路线。官方当前强烈推荐 4 个平台订阅，并把 2 个订阅记录为 SMB 最低模型；官方没有记录单订阅 Platform Landing Zone 部署拓扑。一个订阅也只能有一个父管理组，因此绝不能把同一个 GUID 填到多个平台角色中。

`accelerator/` 中的辅助脚本只是官方命令的可选安全封装。它们只支持场景 5 和 6，并刻意要求 Management、Connectivity、Identity、Security 使用 4 个不同的订阅 GUID；它们不是单订阅或双订阅兼容层。

## 1. 订阅 Gate：选择受支持路线

| 可用订阅数 | 受支持结果 | 本仓库路线 | 执行 Gate |
|---|---|---|---|
| 1 | 官方未记录 Accelerator 部署拓扑 | 执行[单订阅能力实验](05-single-subscription_cn.md)；官方 Accelerator 只生成和审阅场景 5 配置。 | **不要**运行 `Deploy-Accelerator`、Phase 3 Apply 或本仓库任一 Wrapper；不要在多个平台角色重复同一 GUID。 |
| 2 | 官方 SMB 最低模型：Management + Connectivity；Identity/Security 延后 | 使用未修改的官方向导和 Terraform 场景 10 或 11。 | 本仓库 Wrapper 不支持这条路线。Bootstrap/Apply 前批准成本，并验证两个不同的订阅。 |
| 4 | 推荐的完整平台：Management、Connectivity、Identity、Security | 使用下文 4 订阅安全封装，或直接使用未修改的官方向导。 | 4 个 GUID 必须互不相同；切换、权限和成本 Gate 全部通过后才能 Apply。 |

单订阅能力实验继续以手工 Terraform Root 为事实来源。采用受支持的 2/4 订阅 Accelerator 部署后，官方生成的仓库、流水线和 State 成为事实来源。绝不能让手工 Root 和 Accelerator 同时管理同一层级或资源。

对当前账户而言，四订阅门槛对应四个新建的 Active 订阅，分别作为 Accelerator
平台订阅。现有 Sponsorship 订阅中有组织资源，应作为受保护的工作负载/实验订阅。
它不是 Accelerator 的平台输入，不能删除，也不能放入官方清理命令。仓库的
quota-limited 手工 profile 可以在逻辑工作负载角色中复用它，但不会产生工作负载隔离。

官方边界资料：[Accelerator 规划](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/)、[平台订阅与权限](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/platform-subscriptions/)以及[管理组中的订阅移动](https://learn.microsoft.com/en-us/azure/governance/management-groups/manage)。

## 2. 任何受支持 Accelerator Apply 前的切换 Gate

第 4 节的单订阅只读审阅只创建本地文件，不需要先切换。执行 2/4 订阅 Bootstrap/Apply 前：

1. 完成手工治理、网络、DNS、Policy 和成本实验，并保存所需证据。
2. 按当前手工路线执行清理。单订阅使用[其清理与迁移步骤](05-single-subscription_cn.md#10-清理与后续迁移)；配额受限教学路线运行会显示 Plan 的资源级清理：

   ```bash
   ./scripts/nuke-everything.sh --mode quota-limited
   ```

   脚本只在显示 Destroy Plan 并确认后删除手工 Terraform State 中的资源，绝不删除订阅。
   如果 Plan 中出现组织资源或资源组，应立即停止。历史九角色教学路线只有在九个
   ID 确实可用且目标订阅获准清理时，才使用 `--mode multi`。

3. 确认教学资源、管理组 Association、Policy Assignment 和 Role Assignment 已删除。脚本会刻意保留 Bootstrap State Storage 和受保护工作负载订阅。
4. 归档手工 State 和 Plan 证据。不要把其 Backend 交给 Accelerator；切换后不要再运行这些手工 Root。
5. 确认四个平台订阅处于 Active 状态、属于正确 Tenant，并且足够干净；受保护工作负载订阅留在 Accelerator 迁移范围之外。双订阅路线要求不同的 Management/Connectivity ID；安全封装路线要求 4 个不同 ID。
6. 从全新空目录开始 Accelerator。不要把相同资源同时导入两个 State。

## 3. 前置条件

官方当前要求 PowerShell 7.4 或更高版本、Azure CLI 2.55 或更高版本、Git、互联网连接和本地 PowerShell 终端。官方没有明确支持 Azure Cloud Shell 和企业 Proxy 后的执行环境。检查工具和 Azure Context：

```powershell
$PSVersionTable.PSVersion
az version
git --version
az login --tenant "<tenant-id>" --use-device-code
az account set --subscription "<management-subscription-id>"
az account show --query '{name:name,id:id,tenantId:tenantId}' --output table
```

实际 Bootstrap 时，操作者需要目标父管理组以及所选模型中每个平台订阅的 Owner 权限。官方默认使用 Management 订阅存放 Bootstrap 资源。生成可执行配置前验证订阅可用性和权限；计费资格在[订阅自动交付指南](04-subscription-vending_cn.md)中单独处理。

## 4. 单订阅：只审阅官方配置

一个订阅足以学习官方文件生成和配置审阅流程，但不能执行受支持的 Accelerator Platform Landing Zone Apply。使用全新的本地审阅目录和未修改的官方生成命令：

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

目标路径必须尚不存在。审阅生成的 `inputs.yaml`、`platform-landing-zone.tfvars` 和 `lib/`，然后记录：

- 已安装的 ALZ Module 版本和场景 5 选择；
- 4 个平台角色输入和 Subscription Placement Block；
- `connectivity_type = "none"` 以及仍启用的 Management Resource；
- Defender、监控、Policy 和管理组默认值；
- 缺少不同 Connectivity 订阅，以及因此得出的 **No-Go** 结论。

到此停止。不要给所有角色填相同 GUID，不要运行 `prepare-config.ps1` 或 `deploy-accelerator.ps1`，也不要调用 `Deploy-Accelerator` 或 Phase 3 Apply。`New-AcceleratorFolderStructure` 只创建本地配置，不会部署 Platform Landing Zone。实际 Azure 实验继续执行[单订阅能力实验](05-single-subscription_cn.md)。

这里刻意练习产品边界：场景 5 是最接近的官方配置，但官方前置模型仍没有记录单订阅 Accelerator 部署。[场景 5 说明](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/scenarios/management-only/)和[高级文件生成](https://azure.github.io/Azure-Landing-Zones/accelerator/2_bootstrap/advanced/)。

## 5. 双订阅：官方 SMB 路线

有两个不同订阅时使用官方 SMB 模型：Management 用于 Bootstrap 和管理资源，Connectivity 用于 Hub 网络，两者都是必需的；Identity 和 Security 推荐但可延后。选择当前的成本优化 Starter：

- 场景 10：带 Azure Firewall 的 SMB 单区域 Hub-Spoke。
- 场景 11：带 Azure Firewall 的 SMB 单区域 Virtual WAN。

本仓库 Wrapper 只接受场景 5/6，并要求 4 个不同 GUID，因此这条路线不能使用 Wrapper。用新目录运行官方原始向导：

```powershell
Deploy-Accelerator
```

选择 Terraform、Platform Landing Zone Starter Module、所需版本控制目标和场景 10/11。在生成的 Bootstrap 输入中填写不同的 Management/Connectivity ID，按照当前官方规划把 Identity/Security 留空，并使用 Management 作为 `bootstrap_subscription_id`。批准任何操作前，审查全部生成文件，并确认没有残留占位符或被推断出的第三个订阅。

官方场景表对两个 SMB 场景给出的固定基础设施估算均为每月 **USD 689.85**，区域为 `westus`，估算日期为 **2026-04-02**；它不包含消费型费用和区域/币种差异。Bootstrap/Apply 前应生成当前估算、创建 Budget 并取得明确批准；“SMB”并不代表对个人 Credit 来说成本很低。

## 6. 四订阅：安全封装的场景 5 基线

本仓库 Wrapper 只适用于 4 个不同的 Management、Connectivity、Identity、Security 订阅，并且只支持场景 5/6。先使用场景 5；它部署管理组、Policy 和管理资源，不部署 Connectivity Resource：

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

`prepare-config.ps1` 调用官方 `New-AcceleratorFolderStructure`，填入 4 个 ID 和审阅值，并且只写本地配置。它会拒绝重复 GUID 和已存在的目标目录。安装/更新开关是显式的；后续可省略该开关以保留已经审阅的 Module 版本，版本会记录在 `lab-metadata.json` 中。除非传入 `-EnablePaidDefenderPlans`，Wrapper 会禁用生成的付费 Defender Plan 参数。

官方场景 5 表格在 `westus`、**2026-04-02** 的固定基础设施估算为 **USD 0.00**，但这不是零成本保证。场景仍创建 Log Analytics、Data Collection Rule、Managed Identity 和 Automation Account 等管理资源；估算不包含日志采集等消费型用量，也不包含 Bootstrap 资源。应审查保留期、上限、Policy 驱动部署和当前价格。

审阅以下生成文件：

```text
accelerator/work/config/inputs.yaml
accelerator/work/config/platform-landing-zone.tfvars
accelerator/work/config/lib/
accelerator/work/lab-metadata.json
```

确认 4 个角色 ID 与 `bootstrap_subscription_id`、父管理组、区域、安全联系人、已禁用的 Defender 参数、命名、Policy Assignment、Subscription Placement、保留期和预期 Plan。然后运行 Wrapper 预览；它只校验本地输入，不调用 `Deploy-Accelerator`：

```powershell
pwsh ./accelerator/deploy-accelerator.ps1 `
  -WorkspacePath ./accelerator/work
```

## 7. 对受支持路线执行 Bootstrap、Apply 与验证

双订阅路线继续使用官方向导和生成的仓库。4 订阅安全封装路线再次确认 Management 是 Bootstrap 订阅，然后显式执行：

```powershell
az account set --subscription "<management-subscription-id>"
az account show --query '{name:name,id:id,tenantId:tenantId}' --output table

pwsh ./accelerator/deploy-accelerator.ps1 `
  -WorkspacePath ./accelerator/work `
  -Execute
```

检查显示的每个路径和 ID 后，才输入 `DEPLOY-ALZ-ACCELERATOR`。官方 ALZ Module 会生成 Terraform Plan，并给出自己的确认步骤。Bootstrap 创建经过审阅的 State、身份和交付输出；它**不代表** Platform Landing Zone 已经 Apply。

对于 Local 目标，查找生成的脚本；进入其目录运行前，先审查脚本和所有生成的 Terraform：

```powershell
Get-ChildItem `
  -Path ./accelerator/work/output `
  -Recurse `
  -Filter deploy-local.ps1
```

不要批准无法解释的替换、管理组移动、Role Assignment、Policy Remediation 或付费服务。Apply 后按路线验证：

| 检查项 | 双订阅 SMB | 四订阅路线 |
|---|---|---|
| Placement | Management/Connectivity 位于正确管理组；不存在 Identity/Security Placement | 4 个平台订阅均位于正确管理组 |
| 资源 | 管理资源和所选场景 10/11 的 SMB Connectivity Resource 与配置一致 | 场景 5 管理资源，或明确批准的场景 6 资源，与配置一致 |
| 治理 | 预期管理组、Policy Definition、Initiative、Assignment 和 Remediation Identity 已创建 | 相同，并包含预期 Platform/Security 边界 |
| 交付 | Remote State、Workload Identity 和 Pipeline 权限不包含本地开发者 Secret | 相同 |
| 幂等性 | 第二次 Plan 没有无法解释的变更 | 第二次 Plan 没有无法解释的变更 |
| 成本 | Budget 和成本告警显示正确 Scope 与服务 | 相同 |

## 8. 四订阅：场景 6 默认只做 Plan

只有在理解场景 5 并实际验证过清理流程后，才在独立工作目录生成场景 6：

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

场景 6 是带 Azure Firewall 的完整单区域 Hub-Spoke 架构。官方表格在 `westus`、**2026-04-02** 的固定基础设施估算为每月 **USD 5,638.36**；消费型费用和区域/币种差异另计。默认终点是生成配置和 Plan；在指定审批人接受当前估算、Budget、最长运行时间和清理负责人之前，不要执行 Wrapper 或生成的 Apply。

至少在生成配置和 Library 中搜索：

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

按照官方 Options 正确关闭或调整服务；某些修改需要 Library Override，而不是改一个看起来相关的布尔值。每次修改后重新计算价格。Sponsorship Credit 是支付来源，不是部署批准。如果获准执行，应限制 Firewall、Gateway、Bastion、DDoS、Private DNS Resolver、Defender 和日志采集的时间，保存证据，并在清理负责人仍在线时执行官方清理。

## 9. 官方主流程与 Azure DevOps 交付

本节只适用于通过双订阅或四订阅 Gate 后的路线。要练习完整交付流程，在全新空目录运行未修改的官方交互式向导：

```powershell
Deploy-Accelerator
```

选择 Terraform、Azure DevOps、Platform Landing Zone Starter Module 和已批准场景。先完成官方 Azure DevOps 前置条件，包括组织/项目权限和认证资料。Bootstrap 前审查 `config/inputs.yaml`、`config/platform-landing-zone.tfvars` 和 `config/lib`，验证订阅数量和 ID，并重新执行成本 Gate。

Bootstrap 可以创建代码仓库、使用 Workload Federation 的部署身份、Remote State 和 Pipeline。在 Azure DevOps 中运行 **02 Azure landing zone Continuous Delivery**，审查 Terraform Plan，只通过受保护 Environment 批准 Apply。公开网络 Bootstrap 可使用 Microsoft-hosted Agent；生产平台应评估 Self-hosted Agent 和私网连接。

不要用 `azure-devops/` 下的独立示例覆盖 Accelerator 生成的 Pipeline。两者只能用于比较控制点。完成切换后，Accelerator 生成的仓库、Pipeline 和 State 是事实来源。

## 10. 清理边界

清理方式取决于实际执行过什么：

- 单订阅 Accelerator 审阅只生成本地文件。保存所需证据后，按普通方式删除该审阅目录；不需要 Accelerator Azure 清理。实际单订阅 Azure 资源按照第 05 部分清理。
- 2/4 订阅 Accelerator 部署使用官方生成配置和下方官方清理命令。不要使用手工 Terraform State 删除 Accelerator 资源。

先预览删除 Platform Landing Zone。双订阅 SMB 路线只传入实际部署的两个订阅：

```powershell
Remove-PlatformLandingZone `
  -ManagementGroups "<root-parent-management-group-id>" `
  -Subscriptions "<management-subscription-id>", "<connectivity-subscription-id>" `
  -SubscriptionsTargetManagementGroup "<root-parent-management-group-id>" `
  -PlanMode
```

4 订阅安全封装路线只传入四个新建的平台订阅：

```powershell
Remove-PlatformLandingZone `
  -ManagementGroups "<root-parent-management-group-id>" `
  -Subscriptions "<management-subscription-id>", "<connectivity-subscription-id>", "<identity-subscription-id>", "<security-subscription-id>" `
  -SubscriptionsTargetManagementGroup "<root-parent-management-group-id>" `
  -PlanMode
```

只有 Bootstrap 使用独立的第五个平台/Bootstrap 订阅时，才增加 `-AdditionalSubscriptions "<bootstrap-subscription-id>"`。绝不要传入受保护的现有工作负载订阅。检查 Subscription Target、移动和每项计划删除内容；只有预览正确时，才去掉 `-PlanMode` 再次运行。

第二步，使用该次部署保存的完全相同配置和 Output 目录删除 Bootstrap/版本控制资源：

```powershell
Deploy-Accelerator `
  -Inputs "./accelerator/work/config/inputs.yaml", "./accelerator/work/config/platform-landing-zone.tfvars" `
  -StarterAdditionalFiles "./accelerator/work/config/lib" `
  -Output "./accelerator/work/output" `
  -Destroy
```

仓库中的 `scripts/nuke-everything.sh` 只理解手工 Terraform Root，绝不能用于 Accelerator 清理。两个清理阶段及验证完成前，应保留生成目录、State Reference 和版本证据。确认付费资源、Policy Assignment、Identity、Role Assignment、State Storage 以及代码仓库/Pipeline 资产都处于预期最终状态。

## 11. 变更与升级纪律

每次变更都应：

1. 同时记录 ALZ PowerShell、Bootstrap、Starter Module、ALZ Library 版本以及 Scenario/Option 集合。
2. 创建分支并阅读官方 Release Notes 与 Upgrade Guide。
3. 在独立目录生成对照版本并审查 Diff；绝不能重新生成并覆盖活动配置。
4. 把已审查的上游变更合并到受管配置；不要静默接受新的 Policy、Placement、网络或付费服务默认值。
5. 执行 Plan，记录 Policy 和架构差异，并在具有相同订阅模型的非生产层级测试。
6. 通过审批 Gate Apply，然后再次 Plan 检查漂移并复核成本告警。

这样才能把 Accelerator 当成持续维护的平台产品，而不是一次性部署向导。

## 官方资料

- [ALZ Terraform 实施建议](https://azure.github.io/Azure-Landing-Zones/terraform/)
- [Accelerator 规划](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/)
- [平台订阅与权限](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/platform-subscriptions/)
- [工具前置条件](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/)
- [高级 Bootstrap](https://azure.github.io/Azure-Landing-Zones/accelerator/2_bootstrap/advanced/)
- [阶段 3：运行](https://azure.github.io/Azure-Landing-Zones/accelerator/3_run/)
- [Terraform 场景](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/scenarios/)
- [场景 5：仅管理资源](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/scenarios/management-only/)
- [Terraform 选项](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/options/)
- [升级指南](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/upgrade-guide/)
- [清理 FAQ](https://azure.github.io/Azure-Landing-Zones/accelerator/faq/cleanup/)
- [官方场景成本估算脚本](https://github.com/Azure/Azure-Landing-Zones/blob/main/utl/cost-estimates/Get-ScenarioCostEstimates.ps1)
