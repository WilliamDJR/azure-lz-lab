# Azure Landing Zone 企业架构实验室

[English](README.md)

本仓库按**先学基础知识，再部署和验证**的顺序组织。它同时支持受限的单订阅能力实验，以及接近企业形态的多订阅 Azure Landing Zone（ALZ）；昂贵服务均设计成可选、限时启用的实验。

重要的计费限制：Azure Sponsorship 额度与创建额外订阅的资格是两项独立能力。某些 Sponsorship、促销、MOSP 或新建 MCA 账户会因 `PurchaseNeedsReview` 拒绝第二个订阅。尝试多订阅前请先阅读[多订阅引导文档](docs/04-subscription-vending_cn.md)。

## 按可用订阅数量选择路线

| 可用订阅 | 路线 | 结果 |
|---|---|---|
| 只有一个现有订阅 | [单订阅能力实验](docs/05-single-subscription_cn.md) | 部署手工 Terraform，以逻辑角色资源组实践治理、Policy、网络、可观测性和交付，但不宣称具备订阅隔离 |
| 两个订阅 | 官方 Accelerator SMB 场景：Management + Connectivity | 使用官方向导，不使用仓库中要求四订阅的 Wrapper；提前规划后续 Identity 和 Security 订阅 |
| 4 个专用平台订阅及额外工作负载订阅 | 下面的多订阅路线，然后进入[完整 Accelerator 实验](docs/06-alz-accelerator_cn.md) | 验证企业订阅归位、跨订阅权限和平台/工作负载边界；下方手工拓扑需要 9 个唯一角色 ID。 |

官方 Accelerator 当前推荐四个平台订阅，SMB 最低模型为两个。单订阅由本仓库的手工能力实验支持，不属于官方 Accelerator 部署拓扑。[官方规划指南](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/)

多订阅目标不是完整生产级 ALZ，但边界按照真实企业方式设计：计费层级与治理层级分离；平台能力使用独立订阅；开发和生产工作负载分订阅；Terraform 使用远程状态；所有 Azure CLI 操作都显式指定订阅。

## 当前覆盖范围

| ALZ 设计领域 | 本实验的覆盖 |
|---|---|
| 计费与租户 | MCA Billing Profile/Invoice Section、多订阅清单、分阶段创建订阅 |
| 身份与访问 | 管理组 RBAC 输入、托管身份、流水线联合身份；PIM 作为后续扩展 |
| 资源组织 | 中间根、Platform、Security、Corp、Online、Sandbox、Decommissioned；支持 9 个真实角色订阅或 1 个逻辑分区订阅 |
| 网络与连接 | 跨订阅或单订阅 Hub-Spoke、UDR、Firewall、VPN Gateway、Private Endpoint、中央 Private DNS |
| 安全 | Policy、NSG、Firewall、私网访问、可选独立 Sentinel workspace |
| 管理与运维 | 中央 Log Analytics、诊断、KQL、每日采集上限、订阅预算 |
| 治理 | Audit、Deny、DINE、合规和修复模式 |
| 平台自动化 | 远程 Terraform 状态、provider alias、Azure Pipelines 示例和安全清理脚本 |

## 多订阅目标架构

```text
MCA Billing Profile + Invoice Section（共享符合条件的赞助额度池）
  ├── Management 订阅 ─────── Log Analytics + Terraform 状态
  ├── Connectivity 订阅 ───── Hub + Firewall + VPN + Private DNS
  ├── Identity 订阅 ───────── 身份支撑设施边界（可留空）
  ├── Security 订阅 ───────── 可选 Sentinel workspace
  ├── Corp Dev 订阅 ───────── 实验 Spoke + 私有 Storage
  ├── Corp Prod 订阅 ──────── 被治理的生产边界
  ├── Online Dev 订阅 ─────── 被治理的互联网负载边界
  ├── Online Prod 订阅 ────── 被治理的生产边界
  └── Sandbox 订阅 ────────── 隔离实验 / 模拟本地环境

Entra 租户
└── ALZ 中间根
    ├── Platform
    │   ├── Management
    │   ├── Connectivity
    │   ├── Identity
    │   └── Security
    ├── Landing Zones
    │   ├── Corp       （Dev 和 Prod 订阅）
    │   └── Online     （Dev 和 Prod 订阅）
    ├── Sandbox
    └── Decommissioned
```

计费归属决定发票与额度扣减；管理组归属决定继承的 Policy 与 RBAC。改变其中一项不会改变另一项。

## 仓库结构

```text
docs/
  01-ALZ-concepts_cn.md
  02-networking_cn.md
  03-azure-devops_cn.md
  04-subscription-vending_cn.md
  05-single-subscription_cn.md
  06-alz-accelerator_cn.md

accelerator/
  prepare-config.ps1             生成并填写官方本地配置
  deploy-accelerator.ps1          预览或显式执行 Bootstrap

terraform/
  subscriptions.tfvars.example   角色到订阅的共享清单
  subscriptions.single.tfvars.example
                                  单订阅角色清单
  00-bootstrap/                   受保护的远程状态存储
  10-governance/                  管理组、Policy、RBAC、预算
  20-platform/                    跨角色订阅部署的平台资源

scripts/
  create-subscriptions.sh         默认只预览的 MCA 订阅创建工具
  init-backends.sh                初始化两个独立的远程状态 key
  test-private-dns.sh             从 Corp Dev 验证 Private Endpoint DNS
  test-egress.sh                  对比默认出口与 Firewall 出口
  show-effective-routes.sh        查看 Corp Dev 有效路由
  destroy-expensive.sh            删除本次实验的收费资源
  nuke-everything.sh              删除平台层与治理层
```

# 第一部分：基础知识

部署 Terraform 前按顺序阅读：

1. [ALZ 概念与治理](docs/01-ALZ-concepts_cn.md)：订阅作为管理边界、管理组层级、Policy effect 和平台所有权。
2. [企业 Azure 网络](docs/02-networking_cn.md)：Hub-Spoke 路由、Peering、Firewall、混合连接、Private Endpoint 与 DNS。
3. [Azure DevOps 与运维](docs/03-azure-devops_cn.md)：Terraform 交付、审批、工作负载身份联合、诊断设置和 KQL。
4. [多订阅引导与自动交付](docs/04-subscription-vending_cn.md)：MCA 计费作用域、安全创建顺序、订阅角色、自动交付和成本控制。
5. [单订阅能力实验](docs/05-single-subscription_cn.md)：可执行的备用路线、逻辑角色边界、Policy 继承、网络、验证、清理与后续迁移。
6. [Microsoft ALZ IaC Accelerator](docs/06-alz-accelerator_cn.md)：官方生产化 Bootstrap、AVM/Policy 配置、生成的交付资产、成本审查、升级与清理。

开始部署前应能够：

- 解释为什么 Billing Profile 归属和 Management Group 归属彼此独立。
- 把新的私网工作负载放入正确的角色订阅和管理组。
- 画出 Corp Dev 到私有 Storage Endpoint 的流量与 DNS 路径。
- 解释为什么 DINE 同时需要托管身份与 RBAC。
- 识别持续收费资源，并明确何时删除它们。

# 第二部分：多订阅部署与验证

以下步骤要求 9 个角色订阅 ID 全部唯一。如果只有一个订阅，请改为按照[第 05 部分](docs/05-single-subscription_cn.md)执行；其中包含独立 Manifest、Backend Key、安全闸门和验证顺序。

## 0. 前置条件与安全边界

本地需要：

- Azure CLI、Terraform `>= 1.5, < 2.0`、Git 和 Bash。
- 在角色订阅中创建资源和角色分配的权限。
- 管理组、管理组级 Policy 和订阅归位所需的租户权限。
- 只有在使用辅助脚本创建订阅时，才需要 MCA Invoice Section 级的订阅创建权限。

```bash
az version
terraform version
az login
az account show --query '{name:name,id:id,tenantId:tenantId}' --output table
```

只在实验租户或明确获批的租户中运行。不要把真实 Billing Scope、订阅清单、密钥或保存的 plan 提交到 Git。启用收费服务前，重新确认 Azure 当前价格和赞助额度适用条件。

## 1. 准备订阅

先阅读[多订阅引导文档](docs/04-subscription-vending_cn.md)。只有 Azure 允许创建额外订阅时，才先创建 Management，部署一个很小且符合条件的资源，验证赞助额度归属后再创建其余订阅。如果 Azure 返回 `PurchaseNeedsReview`，请停止重试，使用文档中的单订阅路线或申请账户审核。

辅助工具默认不会更改 Azure：

```bash
./scripts/create-subscriptions.sh --role management
```

如果订阅已经存在，手工创建本地清单：

```bash
cp terraform/subscriptions.tfvars.example terraform/subscriptions.tfvars
```

替换全部占位符，确认 9 个 ID 各不相同。该文件已被 Git 忽略。

## 2. 创建远程 Terraform 状态

Bootstrap root 必须使用本地状态，因为它创建的正是远程状态存储。Storage Account 位于 Management 订阅，禁用共享密钥，使用 Microsoft Entra 身份验证，启用版本控制与软删除，并创建私有 Container。

```bash
cd terraform/00-bootstrap
cp terraform.tfvars.example terraform.tfvars
# 把 management_subscription_id 改为 Management 订阅 ID。

terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
cd ../..

./scripts/init-backends.sh --mode multi
```

Azure RBAC 首次传播可能有延迟。如果角色分配已经创建成功，但第一次访问 Container 被拒绝，请稍等后再次 apply。

只要任意远程状态仍在使用，就不要删除 `00-bootstrap`。

## 3. 安全部署治理层

```bash
cd terraform/10-governance
cp terraform.tfvars.example terraform.tfvars
```

第一次运行使用以下安全值：

```hcl
move_subscriptions_into_hierarchy = false
public_ip_policy_effect            = "Audit"
enforce_allowed_locations_policy   = false
```

```bash
terraform fmt -check
terraform validate
terraform plan -var-file=../subscriptions.tfvars -out=tfplan
terraform show tfplan
terraform apply tfplan
```

移动任何订阅前，先在 Portal 检查层级和 Policy Assignment。Allowed Locations Assignment 初始使用 `DoNotEnforce`，否则会影响每个已移动订阅中的全部资源。先盘点现有区域并更新 `allowed_locations`，再有意识地启用。管理组和 Policy 的传播可能需要一些时间。

如需启用每订阅预算，把 `budget_start_date` 设为当前月份第一天，再配置金额和通知邮箱并重新检查 plan。预算只告警，不会停止消费。

## 4. 部署基础平台

```bash
cd ../20-platform
cp terraform.tfvars.example terraform.tfvars
```

第一次保持收费功能关闭：

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

基础平台会创建 Management 中的日志、Connectivity 中的 Hub 和 Private DNS、Corp Dev 中的 Spoke 与私有 Storage Endpoint，以及无公网 IP 的测试 VM。跨订阅 Peering 和 DNS Link 均使用显式 Provider Alias。它是低成本而不是免费：VM、Disk、Storage、Private Endpoint 与日志采集都可能产生费用。

## 5. 接入中央日志并归位订阅

获取中央 Workspace ID：

```bash
terraform output -raw log_analytics_workspace_id
```

把该值设为 `terraform/10-governance/terraform.tfvars` 中的 `log_analytics_workspace_id`，然后再次审查并部署治理层。这会启用 Activity Log 的 DINE Assignment、托管身份，以及修复所需的 RBAC 角色。

确认每个 ID 和目标管理组后，修改：

```hcl
move_subscriptions_into_hierarchy = true
```

使用 `-var-file=../subscriptions.tfvars` 对治理层执行 Plan、审查和 Apply。确认全部 9 个订阅都出现在目标管理组中。随后触发合规扫描，为 `activity-log-to-law` 创建 Remediation Task，并验证每个订阅都生成指向 Management Workspace 的 Activity Log Diagnostic Setting。[单订阅 DINE 实验](docs/05-single-subscription_cn.md)给出了完整 CLI 顺序；多订阅路线在管理组范围使用相同的 Assignment/Evaluation/Remediation 模式。

## 6. 验证 Private DNS 与路由

从仓库根目录运行：

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-baseline.txt
./scripts/test-private-dns.sh
```

预期结果是 Azure 公共 CNAME，随后由 `privatelink.blob.core.windows.net` 返回 `10.1.1.x` 私有 A 记录。

进行受控故障实验：只删除 Spoke DNS Link，运行测试，然后恢复：

```bash
terraform -chdir=terraform/20-platform destroy \
  -var-file=../subscriptions.tfvars \
  -target=azurerm_private_dns_zone_virtual_network_link.blob_to_spoke

./scripts/test-private-dns.sh

terraform -chdir=terraform/20-platform apply \
  -var-file=../subscriptions.tfvars
```

`-target` 只用于这个故障实验。

## 7. 把 Policy 从 Audit 提升为 Deny

设置 `public_ip_policy_effect = "Deny"`，审查并应用治理层计划。等待 Policy 传播后，在 Corp Dev 中故意尝试创建公网 IP，并显式指定订阅：

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

在拒绝信息中检查 Assignment 和 Definition ID。如果部署成功，先核对订阅归位，再等待 Policy 传播后重试。

## 8. 限时运行收费实验

### Firewall 与强制隧道

设置 `enable_firewall = true`，带订阅变量文件执行 plan/apply，然后比较路由：

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-firewall.txt
diff -u /tmp/alz-routes-baseline.txt /tmp/alz-routes-firewall.txt
./scripts/test-egress.sh
```

使用[运维文档](docs/03-azure-devops_cn.md)中的 KQL 查看防火墙决策。

### 模拟混合连接

删除 Firewall 后启用两个网关开关：

```hcl
enable_vpn_gateway      = true
enable_simulated_onprem = true
enable_test_vm          = true
```

`destroy-expensive.sh` 在删除 Firewall 时也会删除测试 VM 和 NIC，因此如果本阶段在后续会话运行，需要重建 VM；有效路由检查依赖其 NIC。网关创建时间较长，而且两个网关存在期间都会收费。检查 Peering 网关传递和有效路由后立即删除。

### Security 订阅

只在 Sentinel Onboarding 实验期间设置 `enable_sentinel = true`。代码会在 Security 订阅创建独立 Workspace 并设置每日上限；Data Connector 和 Defender 计划不会自动开启。

每次收费实验结束运行：

```bash
./scripts/destroy-expensive.sh
```

同时保持 `terraform/20-platform/terraform.tfvars` 中的开关为 `false`，避免下次 apply 重新创建资源。

## 9. 运行交付流水线

按照[Azure Pipelines 实验](azure-devops/README_cn.md)操作。企业实现应使用工作负载身份联合、分离 plan/apply 身份、受保护 Environment、保存的 plan artifact、远程状态和定时漂移检测。

## 10. 清理

```bash
./scripts/nuke-everything.sh --mode multi
```

脚本先删除 Platform，再删除 Governance，并故意保留 Bootstrap Storage 和订阅。只有在两个状态文件都不再需要后才能删除状态存储；订阅应通过计费流程取消或复用，不应把它当成普通 Terraform 资源销毁。

# 第三部分：官方 Accelerator 路线

官方路线有明确的订阅门槛；不要通过把一个订阅 ID 重复填入多个平台角色来绕过：

| 可用平台订阅 | Accelerator 操作 |
|---|---|
| 1 个 | 只生成和审查官方配置。不要执行 `Deploy-Accelerator` 或 Phase 3 Apply；实际 Azure 部署继续使用本仓库单订阅路线。 |
| Management + Connectivity | 通过官方流程使用 SMB 场景 10 或 11。本仓库辅助脚本不实现二订阅模型。 |
| Management + Connectivity + Identity + Security | 按[完整 Accelerator 实操](docs/06-alz-accelerator_cn.md)执行；提供给本地 Wrapper 的四个 ID 必须不同。 |

清理手工实现并确认满足四订阅门槛后，从全新目录生成官方配置。辅助脚本调用官方 `New-AcceleratorFolderStructure` 和 `Deploy-Accelerator`，并增加输入校验：

```powershell
pwsh ./accelerator/prepare-config.ps1 `
  -ManagementSubscriptionId "<management-subscription-id>" `
  -ConnectivitySubscriptionId "<connectivity-subscription-id>" `
  -IdentitySubscriptionId "<identity-subscription-id>" `
  -SecuritySubscriptionId "<security-subscription-id>" `
  -DefenderSecurityContact "<security-contact@example.com>" `
  -ScenarioNumber 5 `
  -InstallOrUpdateAlzModule

# 默认只预览；审查所有生成文件和成本设置后才增加 -Execute。
pwsh ./accelerator/deploy-accelerator.ps1
```

手工 Terraform Root 与 Accelerator 是两个独立实现，不要让两者管理同一层级或同一批资源。[Accelerator 文档](docs/06-alz-accelerator_cn.md)包含单订阅只审阅、二订阅 SMB、完整四订阅流程、成本审批、升级和两阶段清理。

## 与生产环境的差距及后续扩展

本实验接近企业形态，但并非生产就绪。生产项目还应评估：

- 把 [Accelerator 实操](docs/06-alz-accelerator_cn.md)提升为经过审查的平台仓库，并实施版本锁定、发布管理和分环境审批。
- Entra 组、PIM、Access Review、Break-glass 账号、自定义角色和平台身份分离。
- Azure Policy Initiative、Assignment Archetype、自动修复和有期限的 Exemption。
- Defender for Cloud、Sentinel Data Connector、Key Vault、客户管理密钥和安全事件集成。
- DNS Private Resolver、DDoS Network Protection、多区域 Hub、ExpressRoute、IPAM 和 Network Watcher 控制。
- 告警、Action Group、备份、恢复演练、Service Health 和平台 SLO。
- 与 CMDB/IPAM 集成并包含下线生命周期的 Subscription Vending 流水线。
- 生产弹性、配额、Availability Zone、数据驻留、监管控制和灾难恢复。

从教学实现走向组织级平台时，优先采用官方的 [Azure Landing Zone IaC Accelerator](https://azure.github.io/Azure-Landing-Zones/terraform/)。
