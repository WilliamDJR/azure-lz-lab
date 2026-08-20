# 05 · 单订阅 ALZ 能力实验

[English](05-single-subscription.md)

当组织只有一个可用 Azure 订阅，并且 Azure 没有批准创建额外订阅时，使用本路线。仓库中的多订阅目标架构继续保留；单订阅路线用于先实践 ALZ 的底层机制。

这是**能力实验，不是完整企业 ALZ**。Provider alias 和资源组在一个订阅中分别代表 Management、Connectivity、Security、Corp 和 Sandbox 职责，但不会产生订阅级计费、配额、RBAC、Policy 或故障域隔离。

## 1. 架构与能力边界

一个订阅只能有一个父管理组。本实验先创建完整管理组层级但不移动订阅；完成审查后，可以把唯一订阅放入 `Corp`，从而继承中间根和 Corp 的 Policy。

```text
Tenant Root Group
└── alz1sub（中间根）
    ├── Platform
    │   ├── Management
    │   ├── Connectivity
    │   ├── Identity
    │   └── Security
    ├── Landing Zones
    │   ├── Corp
    │   │   └── 现有订阅  <- 唯一真实归位
    │   └── Online
    ├── Sandbox
    └── Decommissioned

现有订阅
├── rg-alz1sub-management-*       逻辑 Management 角色
├── rg-alz1sub-connectivity-*     逻辑 Connectivity 角色
├── rg-alz1sub-corp-app1-*        逻辑 Corp 工作负载角色
├── rg-alz1sub-security-*         可选逻辑 Security 角色
└── rg-alz1sub-simulated-onprem-* 可选逻辑 Sandbox 角色
```

管理组只能包含子管理组和订阅，不能直接包含资源组。上面的资源组仍然都是同一个订阅的直接子资源。

| 能力 | 单订阅能否实验 | 限制 |
|---|---|---|
| 远程 Terraform State 和独立 State Key | 可以 | 状态存储与实验资源共用订阅 |
| 管理组层级 | 可以 | 同一时刻只有一个分支能包含该订阅 |
| Policy 继承、Audit、Deny 和 DINE | 可以 | 移动订阅会影响其中全部资源 |
| 管理组与资源组 RBAC | 可以 | 无法证明多订阅团队隔离 |
| Hub-Spoke、UDR、NSG、Firewall、VPN、Private Endpoint 和 DNS | 可以 | Provider alias 指向同一订阅 |
| Log Analytics、诊断、KQL 和单一订阅预算 | 可以 | 成本与配额合并计算 |
| 跨订阅授权与故障域 | 不可以 | 必须使用真实不同订阅 |
| 按订阅验证 Billing Profile 与 Subscription Vending | 不可以 | 需要额外订阅和计费资格 |
| 官方 ALZ IaC Accelerator Apply | 不可以 | 官方推荐四个平台订阅；SMB 最少也需要 Management 和 Connectivity |

Microsoft 当前 Accelerator 规划指南推荐四个平台订阅，并为 SMB 场景说明了两个订阅的最低模型；官方没有记录单订阅部署拓扑。[官方规划指南](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/)

## 配额受限过渡：四个新平台订阅 + 受保护工作负载订阅

账户审核在现有 Active Sponsorship 订阅和四条历史 Deleted 记录之外，只剩四个
创建名额。如果四个名额都获批，请使用 `subscriptions.quota-limited.tfvars.example`：

- 四个新 ID 分别用于互不相同的 `management`、`connectivity`、`identity` 和 `security` 订阅；
- 现有 Sponsorship ID 只在逻辑工作负载角色中复用；
- Terraform 只为这个工作负载 ID 创建一个真实的 Corp Association，不会创建五个冲突的父级 Association；
- 现有工作负载订阅绝不删除，也绝不把组织资源组和资源当作实验目标。

准备三个 Root 文件和 Bootstrap 文件，并使用独立 State Key：

```bash
cp terraform/subscriptions.quota-limited.tfvars.example terraform/subscriptions.quota-limited.tfvars
cp terraform/00-bootstrap/terraform.quota-limited.tfvars.example terraform/00-bootstrap/terraform.tfvars
cp terraform/10-governance/terraform.quota-limited.tfvars.example terraform/10-governance/terraform.tfvars
cp terraform/20-platform/terraform.quota-limited.tfvars.example terraform/20-platform/terraform.tfvars
./scripts/init-backends.sh --mode quota-limited
```

任何 Apply 前，先盘点现有 Sponsorship 订阅，确认四个新订阅均为 Active，且属于
预期 Billing Profile/Invoice Section，并分别审查两个 Root 的 Plan。除非组织明确
批准工作负载订阅继承实验管理组 Policy，否则保持
`move_subscriptions_into_hierarchy = false`。在经过审查的移动变更中，同时设置
`allow_protected_workload_policy_inheritance = true`；没有显式确认时 Terraform 会拒绝移动。
平台资源可以部署到四个平台订阅，
以及现有工作负载订阅中一个唯一命名的实验资源组；不得删除或修改无关资源。

这条路线最多得到五个 Active 订阅（四个新建 + 一个现有），但并不等于五个独立
的工作负载边界。不要为了模拟它们创建或删除可丢弃的工作负载订阅。

## 2. 修改治理前的前置条件与订阅盘点

### 工具、登录与授权

本路线只应在专用实验租户，或已经明确批准层级、Policy 和 RBAC 变更的租户中运行。本地需要 Azure CLI、Terraform `>= 1.5, < 2.0`、Git 和 Bash：

```bash
az version
terraform version
git --version
az login --tenant '<tenant-id>'
az account show --query '{name:name,id:id,tenantId:tenantId,state:state}' --output table
```

创建任何资源前先确认授权模型：

- 现有订阅必须处于 Active 状态。操作者需要创建本文资源和预算的权限，以及创建 Role Assignment 的权限。在专用实验订阅上使用 `Owner` 是最简单的实验配置；组织环境也可以提供经过批准的最小权限组合。
- Governance Root 会在 Tenant Root Group 下创建子管理组、管理组级 Policy Definition/Assignment、Subscription Association 和管理组级 Role Assignment，因此操作者需要在目标父 Scope 具备相应权限。在该父管理组拥有 `Owner` 是最简单的实验配置；最小权限模型通常会分离 Management Group、Resource Policy 和 RBAC 管理权限。
- 仅有订阅 `Owner` 不代表拥有 Tenant Root 级 Management Group 或 Policy 权限。未经批准不得在组织租户中提升访问权限。如果没有所需父 Scope 权限，应跳过 Governance Root，只运行已获准的 Platform/网络实验。
- RBAC 实验中的临时 Entra 组还需要目录权限；也可以改用现有测试组的 Object ID。
- 本路线使用现有订阅且不创建新订阅，因此不需要 Billing Profile 或 Invoice Section 权限。

不要把凭据、Subscription ID、保存的 Plan 或 Terraform State 提交到 Git。启用 VM、Firewall、VPN Gateway、Sentinel 或其他收费功能前，应检查当前 Azure 价格和订阅配额。

### 盘点现有订阅

显式选择订阅，并保存当前状态证据：

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

在 Portal 中记录订阅当前父管理组，保存为 `ORIGINAL_MANAGEMENT_GROUP_ID`。同时盘点已有资源区域、Policy Exemption、预算、生产资源和资源锁。

如果订阅中有不能继承实验 Policy 或 RBAC 的重要工作负载，保持 `move_subscriptions_into_hierarchy = false`，并跳过管理组继承实验。仍可使用唯一前缀运行平台网络实验，但必须审查每次 Plan。

## 3. 准备单订阅配置

创建本地文件；它们已被 Git 忽略。以下 `cp` 命令会替换当前 `terraform.tfvars`，运行前应保存已有路线的配置。

```bash
cp terraform/subscriptions.single.tfvars.example terraform/subscriptions.single.tfvars
cp terraform/00-bootstrap/terraform.single.tfvars.example terraform/00-bootstrap/terraform.tfvars
cp terraform/10-governance/terraform.single.tfvars.example terraform/10-governance/terraform.tfvars
cp terraform/20-platform/terraform.single.tfvars.example terraform/20-platform/terraform.tfvars
```

编辑 `terraform/subscriptions.single.tfvars`，把九个占位符全部替换为同一个 `ALZ_SUBSCRIPTION_ID`。该文件已经设置：

```hcl
allow_shared_subscription_ids = true
```

在 `terraform/00-bootstrap/terraform.tfvars` 中把 `management_subscription_id` 设为同一个 ID。治理配置先保持以下安全值：

```hcl
move_subscriptions_into_hierarchy         = false
single_subscription_management_group_key = "corp"
enforce_allowed_locations_policy          = false
public_ip_policy_effect                    = "Audit"
```

`enforce_allowed_locations_policy = false` 会以 `DoNotEnforce` 模式创建 Assignment。在完成已有资源和必要区域盘点前，不要启用 Deny。

## 4. 使用单订阅专用 State Key 创建远程状态

```bash
terraform -chdir=terraform/00-bootstrap init
terraform -chdir=terraform/00-bootstrap fmt -check
terraform -chdir=terraform/00-bootstrap validate
terraform -chdir=terraform/00-bootstrap plan -out=tfplan
terraform -chdir=terraform/00-bootstrap apply tfplan

./scripts/init-backends.sh --mode single
```

单订阅模式使用 `10-governance-single.tfstate` 和 `20-platform-single.tfstate`；普通多订阅路线继续使用原来的 Key。不要把同一份 State 从重复 ID 直接改成九个不同订阅 ID。

## 5. 先创建治理层，再决定是否移动订阅

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

此时层级和 Assignment 已存在，但 `actual_subscription_placement` 为空。确认 Allowed Locations 为 `DoNotEnforce`，公网 IP Policy 为 `Audit`。

只有在检查 Inventory 和 Plan 后，才设置：

```hcl
move_subscriptions_into_hierarchy = true
```

重新 Plan 和 Apply。治理 Root 只管理一个 Association，把订阅放入 `Corp`：

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

把 `single_subscription_management_group_key` 改为 `online`、`sandbox`、`management`、`connectivity`、`identity` 或 `security`，会移动**整个订阅**。只把它用于受控的继承差异实验；它不会把逻辑资源组同时拆到不同分支。

## 6. 部署成本受控的平台基线

第一次 Platform Apply 会创建 Hub、Spoke、NSG、私有 Storage 与 Endpoint、Private DNS、Log Analytics 和一台小型私网 VM。即使 Firewall、VPN 和 Sentinel 均关闭，这些资源也不是免费。

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

所有 Provider Alias 都使用同一订阅，但可加标签的资源带有 `alz-role` 标签。验证逻辑边界：

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

在 Cost Analysis 中分别按 Resource Group 和 `alz-role` 标签分组。单订阅模式最多创建一个订阅预算；`monthly_budget_overrides` 使用 `management` Key。Terraform 中唯一预算实例名为 `shared`，但金额明确读取 Management 配置，不会根据 Map 顺序随机选择角色。

## 7. 实验步骤

### Private Endpoint 与 DNS 故障

```bash
./scripts/test-private-dns.sh

terraform -chdir=terraform/20-platform destroy \
  -var-file=../subscriptions.single.tfvars \
  -target=azurerm_private_dns_zone_virtual_network_link.blob_to_spoke

./scripts/test-private-dns.sh

terraform -chdir=terraform/20-platform apply \
  -var-file=../subscriptions.single.tfvars
```

第一次查询应从 Storage 公共 CNAME 最终解析到私有 `10.1.1.x` 地址。删除 Link 后，解析结果会变化，而 Storage 公网访问仍然关闭。`-target` 只用于这个受控故障实验。

### Policy 继承与 Deny

订阅位于 `Corp` 后，把 `public_ip_policy_effect` 改为 `"Deny"`，Plan、Apply 并等待 Policy 传播。然后运行一次可清理的公网 IP 部署：

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

VM 操作应被拒绝。保存错误中的 Policy Assignment 和 Definition ID。如果操作成功，应核对订阅是否位于 Corp、治理 Apply 是否确实使用 `"Deny"`，触发 Policy Scan，并只在传播完成后重试。

在确认订阅 Inventory 安全前，Allowed Locations 始终保持 `DoNotEnforce`。需要实验时，在经过审查的临时部署中选择未批准区域，设置 `enforce_allowed_locations_policy = true`，Apply、保存拒绝证据，然后立即恢复为 `false`。

### DINE Activity Log 修复

取得 Platform Workspace ID：

```bash
terraform -chdir=terraform/20-platform output -raw log_analytics_workspace_id
```

设置 `log_analytics_workspace_id`，Plan 并 Apply 治理层，然后触发扫描和 Remediation：

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

这里可以验证 Assignment Identity、Monitoring Contributor 权限、合规评估和修复，但不能验证多个订阅的集中采集。

### RBAC 继承

使用已有 Entra 测试组，不要使用生产个人身份。如果有创建组的权限，可以建立一个临时组；否则向目录管理员获取测试组 Object ID：

```bash
az ad group create \
  --display-name alz1sub-corp-readers \
  --mail-nickname alz1sub-corp-readers

TEST_GROUP_OBJECT_ID=$(az ad group show \
  --group alz1sub-corp-readers \
  --query id --output tsv)
printf 'Test group object ID: %s\n' "$TEST_GROUP_OBJECT_ID"
```

把以下配置加入 `terraform/10-governance/terraform.tfvars`，替换占位符，再 Plan/Apply 治理层：

```hcl
role_assignments = {
  single_corp_reader = {
    scope_key            = "corp"
    principal_id         = "<test-group-object-id>"
    role_definition_name = "Reader"
  }
}
```

检查继承的 Assignment：

```bash
az role assignment list \
  --scope "/subscriptions/$ALZ_SUBSCRIPTION_ID" \
  --include-inherited \
  --query '[].{principal:principalName,role:roleDefinitionName,scope:scope}' \
  --output table
```

当订阅位于 Corp 时，Management、Connectivity 和 Security 分支的角色不会同时治理同名逻辑资源组。逻辑团队隔离应使用资源组级 RBAC；也可以顺序移动整个订阅来观察管理组继承变化。

治理层清理时 Terraform 会删除 Role Assignment。如果临时 Entra 组不再需要，应单独删除：

```bash
az ad group delete --group alz1sub-corp-readers
```

### 路由与 Firewall

保存基线，然后限时启用 Firewall：

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-baseline.txt
./scripts/test-egress.sh

# 在 terraform/20-platform/terraform.tfvars 中设置 enable_firewall = true。
terraform -chdir=terraform/20-platform plan \
  -var-file=../subscriptions.single.tfvars \
  -out=tfplan
terraform -chdir=terraform/20-platform show tfplan
terraform -chdir=terraform/20-platform apply tfplan

./scripts/show-effective-routes.sh | tee /tmp/alz-routes-firewall.txt
diff -u /tmp/alz-routes-baseline.txt /tmp/alz-routes-firewall.txt
./scripts/test-egress.sh
```

启用 Firewall 前的出口结果只用于观察。2026 年 3 月 31 日之后的新 VNet API 版本默认使用 Private Subnet，因此在显式出口出现前，两个公网地址都可能失败。启用 Firewall 后，再通过其路由和日志证明显式出口路径。

使用 Firewall 日志证明请求为何被允许或拒绝。实验结束立即运行 `./scripts/destroy-expensive.sh`。

### 模拟混合网络路由

VPN Gateway 成本高且部署缓慢。只有明确批准后，才设置以下本地配置，并审查、Apply Platform Plan：

```hcl
enable_firewall         = false
enable_vpn_gateway      = true
enable_simulated_onprem = true
enable_test_vm          = true
vpn_shared_key          = "<local-value-at-least-16-characters>"
```

前面的 Firewall 清理会删除测试 VM 和 NIC。`enable_test_vm = true` 会在同一次 Apply 中重建 `show-effective-routes.sh` 所需的 NIC 和 Gateway 拓扑。

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

单订阅模式下两个 Subscription ID 相同，因此第二次 Connection 查询会有意重复。当前拓扑没有模拟本地 VM；应验证两条 Connection 状态和 `VirtualNetworkGateway` 路由，不要声称完成端到端应用流量测试。保存证据后立即删除两个 Gateway 和测试 VM：

```bash
./scripts/destroy-expensive.sh
```

把 `terraform/20-platform/terraform.tfvars` 中的 `enable_vpn_gateway`、`enable_simulated_onprem` 和 `enable_test_vm` 恢复为 `false`。

### Pipeline 与幂等性

按照 [Azure Pipelines 实验](../azure-devops/README_cn.md)操作。设置 `ALLOW_SHARED_SUBSCRIPTION_IDS=true`，Platform Pipeline 使用 `TF_BACKEND_KEY=20-platform-single.tfstate`，并让 `SUBSCRIPTION_IDS_JSON` 中每个值都等于现有订阅 ID。独立 Governance Pipeline 必须使用 `10-governance-single.tfstate`；不同 Root 或模式绝不能共用 State Key。例如：

```json
{"management":"<same-id>","connectivity":"<same-id>","identity":"<same-id>","security":"<same-id>","corp_dev":"<same-id>","corp_prod":"<same-id>","online_dev":"<same-id>","online_prod":"<same-id>","sandbox":"<same-id>"}
```

Service Connection 只需访问这一个订阅、State Container 和相关管理组 Scope。保留 Apply Environment 审批，并确认 Pipeline Apply 的是已发布的 Plan Artifact，而不是在审批后重新生成 Plan。

配额受限 profile 使用相同模板，但设置
`ALLOW_SHARED_SUBSCRIPTION_IDS=false`、
`ALLOW_LOGICAL_WORKLOAD_SUBSCRIPTION_IDS=true`，Platform 使用
`20-platform-quota-limited.tfstate`（Governance 使用对应的 State Key），并填入
`subscriptions.quota-limited.tfvars` 中的 JSON。联邦身份只需要四个平台订阅、
受保护工作负载订阅和 State Container 的权限；不要授予 Pipeline 删除订阅或管理
组织资源组的权限。

每个稳定阶段后再次运行 Plan。退出码 `0` 表示无漂移，`2` 表示有变更，`1` 表示错误：

```bash
terraform -chdir=terraform/20-platform plan \
  -detailed-exitcode \
  -var-file=../subscriptions.single.tfvars
```

## 8. 成本控制与会话收尾

把资源集中到一个订阅不会降低服务价格，只会让用量落在同一个账单和配额边界。

- 基线费用可能包括测试 VM 和 Disk、Private Endpoint、Storage 容量/事务及 Log Analytics 采集。
- Firewall、两个 VPN Gateway、Sentinel 采集和已启用安全服务必须限时运行。
- 通过治理层配置一个订阅预算。预算只告警，不会停止资源消费。
- 在 Cost Analysis 中按 Resource Group 和 `alz-role` 检查；费用和标签数据可能延迟出现。
- 对应实验结束后保持所有成本开关为 `false`。

每次会话结束检查当前实验资源和 Terraform 成本功能输出：

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

如果启用过任何按小时计费功能，运行 `./scripts/destroy-expensive.sh`，并把对应 Terraform 开关恢复为 `false`。

## 9. 官方 Accelerator：单订阅只生成和审阅

单订阅不妨碍学习官方 Accelerator 的规划和生成配置，但不满足受支持的 Platform Landing Zone Apply 边界。不要把同一个 GUID 同时填入 Management、Connectivity、Identity 和 Security，也不要使用仓库中要求四个不同订阅的 Wrapper。

可以在隔离目录生成 Scenario 5 文件：

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

到配置审阅为止。不要执行 `Deploy-Accelerator` 或 Phase 3 Apply。记录 ALZ Module 版本、Scenario、生成差异、缺失 Connectivity 订阅以及最终 No-Go 结论。至少有两个订阅后再评估官方 SMB 场景；有四个平台订阅时按照[完整 Accelerator 实验](06-alz-accelerator_cn.md)执行。[官方平台订阅前置条件](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/platform-subscriptions/)

## 10. 清理与后续迁移

Terraform 清理前，先列出订阅级 Diagnostic Setting。DINE Remediation 创建的资源位于 Terraform State 之外；删除 Policy Assignment 不一定会删除已部署的 Setting：

```bash
az monitor diagnostic-settings subscription list \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --query 'value[].{name:name,workspaceId:properties.workspaceId}' \
  --output table

# 只删除指向本实验 Workspace 的 Setting。
az monitor diagnostic-settings subscription delete \
  --subscription "$ALZ_SUBSCRIPTION_ID" \
  --name '<lab-activity-log-diagnostic-setting-name>'
```

不要删除组织原有的 Diagnostic Setting。随后先删除按小时收费的组件，再只销毁手工 Terraform 管理的资源。单订阅路线使用：

```bash
./scripts/destroy-expensive.sh
./scripts/nuke-everything.sh --mode single
```

配额受限路线使用匹配的 Manifest 和 State Key：

```bash
./scripts/nuke-everything.sh --mode quota-limited
```

脚本会分别显示 Platform 和 Governance 的 Destroy Plan，并在每个 Plan 后要求输入
`apply-destroy`。配额受限清理不会删除订阅，也不得删除组织资源、Diagnostic
Setting、Lock 或 Resource Group。如果实验资源组中出现无关资源，应停止操作，从
Terraform State 中移除实验资源或取得负责人批准的资源级方案；不要强制删除资源组。
五个订阅都应保留，以便后续使用官方 Accelerator 或组织日常运行。

完整清理会删除受管 Association，但 Azure 不保证恢复订阅原来的父管理组。检查实际父级，并按需恢复 `ORIGINAL_MANAGEMENT_GROUP_ID`：

```bash
az account management-group subscription add \
  --name '<original-management-group-id>' \
  --subscription "$ALZ_SUBSCRIPTION_ID"
```

如果原父级就是 Tenant Root Group，并且订阅已经回到该位置，则不需要执行恢复命令。等待 Management Group 传播，并在 Portal 验证后再删除保存的 Inventory。

Bootstrap State Storage 会被保留。只有两个单订阅 State 都不再使用，并且 Platform/Governance 资源已经删除后，才运行：

```bash
terraform -chdir=terraform/00-bootstrap plan -destroy -out=destroy.tfplan
terraform -chdir=terraform/00-bootstrap apply destroy.tfplan
```

迁移到多订阅或官方 Accelerator 前：

1. 使用原 Manifest 和 State 只销毁手工实验资源；绝不删除现有工作负载订阅。
2. 确认没有遗留实验资源、Policy Assignment、Association 或 Role Assignment，同时组织原有设置保持完整。
3. 保留四个平台订阅，从全新的生成仓库开始官方 Accelerator；只有未来获得配额后才创建九个唯一 ID 的 Manifest。
4. 只有确实批准并具备九个唯一订阅时，才运行 `./scripts/init-backends.sh --mode multi`。

不要在现有单订阅 State 中把重复 ID 直接替换成唯一 ID。这可能触发跨订阅重建，并不构成 ALZ 迁移。
