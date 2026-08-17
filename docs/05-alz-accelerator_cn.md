# 05 · Microsoft ALZ IaC Accelerator 实操

[English](05-alz-accelerator.md)

本实验在仓库的小型教学实现之外，增加一条面向生产化的官方 Microsoft ALZ IaC Accelerator 路线。建议先完成手工 Terraform 实验，理解生成的模块、身份、状态和流水线所解决的问题，再使用 Accelerator。

`accelerator/` 中的辅助脚本刻意采用保守设计：

- `prepare-config.ps1` 通过 ALZ PowerShell 模块取得当前官方场景，填入 4 个平台订阅 ID、区域和安全联系人，只生成本地配置。
- 默认使用场景 5：部署管理组、Policy 和管理资源，不包含完整连接平台。
- 除非显式传入 `-EnablePaidDefenderPlans`，否则 Defender 计划的 Policy 参数会设为 `Disabled`。
- `deploy-accelerator.ps1` 默认只预览。只有传入 `-Execute` 后才会执行，同时检查 Azure CLI 当前订阅并要求输入确认短语。
- 生成的工作目录已被 Git 忽略，因为其中可能包含租户配置和生成的状态元数据。

这些控制可以减少误部署，但不代表部署免费或已经达到生产审批要求。

## 1. 明确它与手工实验的关系

| 路线 | 最适合的用途 | 所有权与状态 |
|---|---|---|
| `terraform/00-bootstrap`、`10-governance`、`20-platform` | 理解每个 Azure/Terraform 机制，运行小型、可控成本的故障实验 | 由本仓库维护 |
| 官方 ALZ IaC Accelerator | 练习 Microsoft 官方引导模式、Azure Verified Modules、ALZ Policy 库、工作负载身份和交付流水线 | 通过官方 ALZ 工具链生成和升级 |

不要让两个实现管理同一套管理组层级，也不要把同一批 Azure 资源同时纳入两个 Terraform State。如果手工实验已经部署，应先清理再复用 4 个平台订阅；或者为 Accelerator 使用独立父管理组和另一套经过审查的订阅。同一个订阅同一时间只能有一个父管理组。

## 2. 前置条件

当前官方前置条件要求 PowerShell 7.4 或更高版本、Azure CLI 2.55 或更高版本、Git、互联网连接，以及足够的租户和订阅权限。请在本地 PowerShell 终端运行；Accelerator 不支持 Azure Cloud Shell。

```powershell
$PSVersionTable.PSVersion
az version
git --version
az login --tenant "<tenant-id>" --use-device-code
az account set --subscription "<management-subscription-id>"
az account show --query '{name:name,id:id,tenantId:tenantId}' --output table
```

使用[订阅自动交付实验](04-subscription-vending_cn.md)中的 4 个专用平台订阅：Management、Connectivity、Identity 和 Security。本实验把 Management 同时作为 Bootstrap 订阅。

## 3. 阶段 A：生成成本受控的配置

先使用官方 Terraform 场景 5：只部署管理组、Policy 和管理资源。从仓库根目录运行：

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

安装/更新开关是显式的，因为模块版本会变化。后续运行时，如需复用已经审查过的已安装版本，可省略该开关。脚本会把版本写入 `accelerator/work/lab-metadata.json`。

场景 5 仍会创建 Log Analytics 等收费的管理资源。Apply 前应审查保留期、每日上限、由 Policy 触发的部署以及完整 Plan；“仅管理资源”不等于“没有成本”。

此步骤**不会**创建 Azure 或版本控制资源。重点审查：

```text
accelerator/work/config/inputs.yaml
accelerator/work/config/platform-landing-zone.tfvars
accelerator/work/config/lib/
accelerator/work/lab-metadata.json
```

确认：

- 所有订阅 ID 和 `bootstrap_subscription_id` 正确；
- `root_parent_management_group_id` 符合预期——空值按生成模板的定义使用租户根；
- 所有 `starter_locations` 有效并符合数据驻留要求；
- Defender 安全联系人正确；
- 本次成本受控实验中，每个 `enableAsc...` 参数都是 `Disabled`；
- 命名、IP 地址范围、管理组 ID、Policy Assignment 和日志保留符合设计。

先预览 Bootstrap 包装脚本：

```powershell
pwsh ./accelerator/deploy-accelerator.ps1 `
  -WorkspacePath ./accelerator/work
```

预览只检查目录和占位符，不会调用 `Deploy-Accelerator`。

## 4. 执行 Bootstrap 并部署平台

再次确认当前订阅，然后显式执行：

```powershell
az account set --subscription "<management-subscription-id>"

pwsh ./accelerator/deploy-accelerator.ps1 `
  -WorkspacePath ./accelerator/work `
  -Execute
```

核对显示的路径和订阅后，才输入 `DEPLOY-ALZ-ACCELERATOR`。官方 ALZ 模块随后还会生成 Terraform Plan 并要求确认。第一次运行会创建经过审查的 Bootstrap 资源和本地交付产物；这不代表 Platform Landing Zone 已经部署。

查找生成的本地部署脚本：

```powershell
Get-ChildItem `
  -Path ./accelerator/work/output `
  -Recurse `
  -Filter deploy-local.ps1
```

打开并审查该脚本和生成的 Terraform，再进入它所在的目录运行。它会先生成 Plan，并在 Apply 前要求确认。对于无法解释的替换、订阅移动、角色分配或收费服务，不要批准。

Apply 后验证：

- 预期的 ALZ 层级已创建，包括 Platform 和 Security 边界；
- Management、Connectivity、Identity、Security 订阅归位正确；
- ALZ Policy Definition、Initiative 和 Assignment 位于预期作用域；
- Management Workspace 和监控资源符合所选场景；
- 生成的 Terraform State 和身份不是本地开发者密钥；
- 再次执行 Plan 时没有无法解释的变更。

## 5. 阶段 B：接近企业的连接架构

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

场景 6 是带 Azure Firewall 的单区域 Hub-Spoke 架构，其生成的默认值可能包含持续收费服务。至少在生成的配置和 Library 中搜索：

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

根据官方选项文档正确关闭或调整服务；有些修改需要 Library Override，而不是改一个看起来相关的布尔值。审查最终 Plan 和当前区域价格。即使有 Sponsorship Credit，也要设置预算并限制 Firewall、Gateway、Bastion、DDoS、Private DNS Resolver、Defender 和日志采集的运行时长。

## 6. Azure DevOps 生产化实验

本地场景适合安全理解生成物。如需练习完整企业交付流程，在新的空目录运行官方交互式向导：

```powershell
Deploy-Accelerator
```

选择 Terraform、Azure DevOps、Platform Landing Zone Starter Module 和已审查的场景。先完成官方 Azure DevOps 前置条件，包括组织/项目权限和所需身份验证资料。批准 Bootstrap 前，像本地实验一样审查生成的 `config/inputs.yaml`、`config/platform-landing-zone.tfvars` 和 `config/lib`。

Bootstrap 可以创建代码仓库、联合部署身份、远程状态和流水线。在 Azure DevOps 中运行 **02 Azure landing zone Continuous Delivery**，审查 Terraform Plan，只通过受保护 Environment 批准 Apply。公开网络的实验 Bootstrap 可使用 Microsoft-hosted Agent；生产平台应评估 Self-hosted Agent 和私网连接。

不要用 `azure-devops/` 下的独立示例覆盖 Accelerator 生成的流水线。可比较两者理解控制点，但应把 Accelerator 生成的仓库作为事实来源。

## 7. 清理演练

Accelerator 清理分为两个阶段。首先预览删除 Platform Landing Zone：

```powershell
Remove-PlatformLandingZone `
  -ManagementGroups "<root-parent-management-group-id>" `
  -Subscriptions "<management-subscription-id>", "<connectivity-subscription-id>", "<identity-subscription-id>", "<security-subscription-id>" `
  -SubscriptionsTargetManagementGroup "<root-parent-management-group-id>" `
  -PlanMode
```

只有当 Bootstrap 订阅不在 4 个平台订阅中时，才增加 `-AdditionalSubscriptions "<bootstrap-subscription-id>"`。逐项检查计划删除内容，然后去掉 `-PlanMode` 再次运行。

第二步，使用保存的同一套配置删除 Bootstrap/版本控制资源：

```powershell
Deploy-Accelerator `
  -Inputs "./accelerator/work/config/inputs.yaml", "./accelerator/work/config/platform-landing-zone.tfvars" `
  -StarterAdditionalFiles "./accelerator/work/config/lib" `
  -Output "./accelerator/work/output" `
  -Destroy
```

仓库中的 `scripts/nuke-everything.sh` 只理解手工 Terraform Root，不能用作 Accelerator 清理流程。完成清理和证据留存前，不要删除生成目录。

## 8. 变更与升级纪律

每次变更都应：

1. 记录 ALZ PowerShell 模块、Starter Module 和 ALZ Library 版本。
2. 创建分支并阅读官方 Release Notes 与 Upgrade Guidance。
3. 把经过审查的上游变更合并进现有配置，不要直接重新生成并覆盖生产文件。
4. 执行 Plan，记录 Policy 与架构差异，先在非生产层级测试。
5. 通过审批门部署，再执行一次 Plan 检查漂移。

这样才能把 Accelerator 当成持续维护的平台产品，而不是一次性部署向导。

## 官方资料

- [ALZ Terraform 实施建议](https://azure.github.io/Azure-Landing-Zones/terraform/)
- [Accelerator 规划](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/)
- [前置条件](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/)
- [高级 Bootstrap](https://azure.github.io/Azure-Landing-Zones/accelerator/2_bootstrap/advanced/)
- [阶段 3：运行](https://azure.github.io/Azure-Landing-Zones/accelerator/3_run/)
- [Terraform 场景](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/scenarios/)
- [Terraform 选项](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/options/)
- [升级指南](https://azure.github.io/Azure-Landing-Zones/accelerator/starter-terraform/upgrade-guide/)
- [清理 FAQ](https://azure.github.io/Azure-Landing-Zones/accelerator/faq/cleanup/)
