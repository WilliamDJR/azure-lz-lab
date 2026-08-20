# 04 · 多订阅引导与自动交付

[English](04-subscription-vending.md)

本实验把 Azure 的计费归属与 ALZ 治理归属分开处理。两者有关联，但任何一套层级都不会自动配置另一套。

本章保留企业多订阅路线。如果创建订阅返回 `PurchaseNeedsReview`，不要把重复 ID 填入自动交付命令，也不要持续重试。请转到独立的[单订阅能力实验](05-single-subscription_cn.md)；只有 Azure 后续批准额外订阅后，才返回本章继续。

## 当前账户配额与安全分配

Microsoft Support 已确认该账户共有五条历史订阅记录：一条 Active、四条
Deleted。Deleted 记录仍计入账户上限，因此即使上限调整为 9，实际也只剩下
**4 个创建名额**，而不是可以新建 9 个订阅。根据支持回复，新建后再删除的订阅
也会继续占用名额。规划时应把每一次创建都视为基本不可回收的配额消耗。

因此本实验采用以下配额受限分配：

| 实际订阅 | 本仓库中的逻辑用途 | 生命周期规则 |
|---|---|---|
| 现有 Active Sponsorship | 受保护的工作负载/实验订阅 | 保留；没有经过负责人批准的盘点和变更计划，不删除、不移动 |
| 新建 1 | Management | 只创建一次，验证计费和额度归属 |
| 新建 2 | Connectivity | 只创建一次，验证计费和额度归属 |
| 新建 3 | Identity | 只创建一次；保持可选资源关闭 |
| 新建 4 | Security | 只创建一次；未经批准保持 Sentinel 关闭 |

这会得到四个互相独立的平台订阅，加上一个现有工作负载订阅。仓库的
`quota-limited` profile 可以让逻辑工作负载角色（`corp_dev`、`corp_prod`、
`online_*`、`sandbox`）复用受保护订阅；它们不构成独立的计费、Policy 或配额
边界。九角色清单保留为未来/参考拓扑，在没有新的配额批准前不可执行。

## 两套彼此独立的层级

```text
MCA 计费层级                              Entra 租户资源层级

Billing Account                           Tenant Root Group
└── Billing Profile                       └── ALZ 中间根管理组
    └── Invoice Section                       ├── Platform
        ├── Management 订阅                   ├── Landing Zones
        ├── Connectivity 订阅                 ├── Sandbox
        └── ...                              └── Decommissioned
```

- **Billing Profile 和 Invoice Section** 决定订阅费用开到哪里，以及消耗哪个符合条件的额度池。
- **Management Group** 决定继承的 Azure Policy 和 RBAC。
- 在正确的 Invoice Section 下创建订阅，并不会自动把它放入 ALZ 管理组。
- 在管理组之间移动订阅，也不会改变它的计费归属。
- 管理组只能包含子管理组和订阅。资源组始终位于订阅内，不能直接放入不同的管理组分支。

## 本实验采用的订阅模型

| 角色 | 管理组 | 预期资源 |
|---|---|---|
| `management` | Platform / Management | Terraform 状态、中央 Log Analytics、运维服务 |
| `connectivity` | Platform / Connectivity | Hub VNet、防火墙、网关、Private DNS |
| `identity` | Platform / Identity | 可选的 AD DS、同步、PKI 等身份支撑设施 |
| `security` | Platform / Security | 可选的 Sentinel workspace 和安全团队服务 |
| `corp_dev` | Landing Zones / Corp | 开发工作负载和实验 Spoke |
| `corp_prod` | Landing Zones / Corp | 生产私网工作负载边界；本实验中故意留空 |
| `online_dev` | Landing Zones / Online | 开发互联网工作负载边界；本实验中故意留空 |
| `online_prod` | Landing Zones / Online | 生产互联网工作负载边界；本实验中故意留空 |
| `sandbox` | Sandbox | 隔离实验和模拟本地网络的 VNet |

开发和生产使用独立订阅，可以分别控制配额、成本、访问、策略和事故影响范围。订阅暂时为空并没有问题：本实验只在有明确学习目的的位置创建资源。

## 安全的创建顺序

1. 在 Cost Management + Billing 中确认目标 MCA Billing Account、Billing Profile 和 Invoice Section。
2. 确认执行人具备 Invoice Section 级订阅创建角色及所需租户权限。
3. 先只创建 `management` 订阅。
4. 部署一个很小且符合额度条件的资源，等待成本数据出现，确认费用扣减了预期的赞助余额。
5. 验证成功后再创建 `connectivity`、`identity` 和 `security`；不要为本实验创建可丢弃的工作负载订阅。
6. 把四个新 ID 与现有受保护 ID 记录在 `terraform/subscriptions.quota-limited.tfvars` 中，绝不要提交该文件。
7. 第一次部署治理层时关闭订阅移动；检查计划和层级后，再启用订阅归位。

辅助脚本默认只预览：

```bash
./scripts/create-subscriptions.sh --role management
```

对于 MCA，需要从 Portal 或计费 API 获取完整的 Invoice Section billing scope。不要把它保存到仓库。

```bash
export AZURE_BILLING_SCOPE='/providers/Microsoft.Billing/billingAccounts/<account>/billingProfiles/<profile>/invoiceSections/<section>'

# 先只创建一个订阅
./scripts/create-subscriptions.sh --role management --execute

# 验证成本归属后只创建四个平台订阅
./scripts/create-subscriptions.sh --role platform --execute
```

`platform` 只选择 Management、Connectivity、Identity 和 Security。历史上的九角色
`--role all` 现在受到保护，必须显式传入 `--allow-nine-role-run`；当前账户不要使用。
在任何 Terraform apply 前，都要逐一检查生成的 ID 和计费归属。

如果订阅已经存在，不要运行创建脚本。把 `terraform/subscriptions.tfvars.example` 复制为 `terraform/subscriptions.tfvars`，然后手工填写 ID。

## Sponsorship 资格与计费归属是两件事

即使 MCA Billing Profile 和 Invoice Section 正确，登录账户也不一定有资格再购买新的 Azure 订阅。是否允许创建订阅，是 Azure 计费后端对账户和 Offer 做出的资格判断。

- 在新版 Azure credits 体验中，额度存放在 Billing Profile 上，该 Profile 下的所有订阅都可以使用额度；但这并不会取消账户的订阅创建资格检查。[Azure sponsorship credits 与 Billing Profile](https://learn.microsoft.com/partner-center/benefits/mpn-benefits-azure-cloud)
- 在旧版 Sponsorship 兑换流程中，兑换会创建新的 sponsorship 订阅，不能简单地把额度应用到已有的 pay-as-you-go 订阅。[Azure credits 兑换说明](https://learn.microsoft.com/partner-center/benefits/mpn-benefits-azure-cloud)
- 对于直接从 Azure.com 购买的 Microsoft Customer Agreement，Microsoft 文档说明默认最多五个订阅，通常每天只能创建一个；是否允许继续创建还取决于消费历史和账户个体资格。[多订阅创建故障排查](https://learn.microsoft.com/azure/cost-management-billing/troubleshoot-subscription/create-subscriptions-deploy-resources)

`PurchaseNeedsReview` 和 `user is not eligible for an Azure account` 表示 Azure 在创建订阅之前就拒绝了购买请求。这不是 Terraform、alias 名称或 Billing Scope 格式错误。请先到 [aka.ms/AccountReview](https://aka.ms/AccountReview) 发起账户审核；如果仍被拦截，提交 Azure Billing/Subscription Management 支持请求。准备好 Billing Account、Profile、Invoice Section、Tenant ID、时间戳和完整错误码，但不要公开真实 Billing Scope。

在 Azure 允许创建第二个订阅之前，可以选择以下实验路线：

1. **单订阅学习路线：** 保留现有 Sponsorship 订阅，创建 ALZ 管理组层级，把唯一订阅按需放入一个经过审查的分支，并通过资源组和标签区分逻辑平台/工作负载角色。按照完整的[单订阅能力实验](05-single-subscription_cn.md)执行。它不具备企业级订阅隔离边界。
2. **配额受限过渡路线：** 最多创建上面的四个平台订阅，保留现有 Sponsorship 订阅作为受保护工作负载订阅，并使用仓库的 quota-limited 清单。这样无需把配额花在可丢弃的工作负载订阅上，也可以验证平台边界。只清理手工实验资源后，使用四个新平台 ID 进入[官方 Accelerator 实验](06-alz-accelerator_cn.md)；受保护工作负载订阅不纳入 Accelerator 迁移。
3. **完整九角色路线：** 使用明确允许创建足够多额外订阅的账户/Offer，或请 Microsoft provision/解除限制。只有这样才使用九个唯一 ID 的 Terraform 参考拓扑。

不要反复重试 `--role all`；脚本现在检测到 `PurchaseNeedsReview` 时会直接停止并给出说明。

## 继续创建其他订阅前先验证

只有当辅助脚本输出真实的订阅 GUID 时，才能把摘要视为成功。`az account alias` 属于 Azure CLI 的 `account` 扩展；辅助脚本现在会在命令替换前安装该扩展，并拒绝把扩展提示或其他文本当成订阅 ID。官方命令参考中，alias 资源的 `provisioningState` 和 `properties.subscriptionId` 是关键字段。[Azure CLI `az account alias`](https://learn.microsoft.com/cli/azure/account/alias?view=azure-cli-latest)

默认前缀下，management 的规范 alias 是显示名称 `alzlab-platform-management`。辅助脚本还会兼容检查旧的短 alias `alzlab-management`。以示例 alias 为例，先验证 alias 本身：

```bash
az extension show --name account --only-show-errors >/dev/null 2>&1 || \
  az extension add --name account --only-show-errors

ALIAS_NAME='alzlab-platform-management'
SUBSCRIPTION_ID=$(az account alias show \
  --name "$ALIAS_NAME" \
  --query properties.subscriptionId \
  --output tsv \
  --only-show-errors)

if [[ ! "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "没有返回有效的订阅 ID，不要继续。" >&2
  exit 1
fi

az account alias show \
  --name "$ALIAS_NAME" \
  --query '{alias:name,state:properties.provisioningState,subscriptionId:properties.subscriptionId,displayName:properties.displayName,billingScope:properties.billingScope}' \
  --output json

az account list --refresh \
  --query "[?id=='$SUBSCRIPTION_ID'].{name:name,id:id,state:state,tenantId:tenantId}" \
  --output table

az account show --subscription "$SUBSCRIPTION_ID" \
  --query '{name:name,id:id,tenantId:tenantId,state:state}' \
  --output table
```

Alias 状态必须是 `Succeeded`，Azure CLI 返回的 `id` 也必须是同一个 GUID。如果输出只有 `The command requires the extension account` 之类的提示，就没有返回订阅 ID；上一次脚本运行必须视为结果不确定，不能当成成功复用或成功创建。

### 验证 Billing Profile 和 Invoice Section

从创建订阅时使用的完整 `AZURE_BILLING_SCOPE` 中解析三个 ID。不要替换成其他 Billing Account、Profile 或 Invoice Section：

```bash
BILLING_SCOPE="${AZURE_BILLING_SCOPE:?请先设置 AZURE_BILLING_SCOPE}"
BILLING_ACCOUNT_ID="${BILLING_SCOPE#*/billingAccounts/}"
BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID%%/billingProfiles/*}"
BILLING_PROFILE_ID="${BILLING_SCOPE#*/billingProfiles/}"
BILLING_PROFILE_ID="${BILLING_PROFILE_ID%%/invoiceSections/*}"
INVOICE_SECTION_ID="${BILLING_SCOPE##*/invoiceSections/}"

printf 'Billing account:  %s\nBilling profile:  %s\nInvoice section:  %s\n' \
  "$BILLING_ACCOUNT_ID" "$BILLING_PROFILE_ID" "$INVOICE_SECTION_ID"

az billing account show \
  --name "$BILLING_ACCOUNT_ID" \
  --expand 'soldTo,billingProfiles,billingProfiles/invoiceSections' \
  --output json

az billing profile show \
  --account-name "$BILLING_ACCOUNT_ID" \
  --name "$BILLING_PROFILE_ID" \
  --expand invoiceSections \
  --output json

az billing account invoice-section show \
  --billing-account-name "$BILLING_ACCOUNT_ID" \
  --invoice-section-name "$INVOICE_SECTION_ID" \
  --expand billingProfiles \
  --output json

az billing subscription list \
  --account-name "$BILLING_ACCOUNT_ID" \
  --profile-name "$BILLING_PROFILE_ID" \
  --invoice-section-name "$INVOICE_SECTION_ID" \
  --output json
```

最后一条命令的结果中必须出现新的 `SUBSCRIPTION_ID`。Azure Billing CLI 命令组目前是预览 API，因此还应在 Portal 的 **Cost Management + Billing → Billing scopes → Invoice sections → Subscriptions** 中确认相同关系。使用量和 Sponsorship Credit 归属可能需要时间才显示；部署一个很小的测试资源后，先在 Cost Management 中确认费用归属，再创建其他订阅。以上 Billing 命令都是只读操作。[Azure billing subscription CLI](https://learn.microsoft.com/cli/azure/billing/subscription?view=azure-cli-latest)

### 后续验证 ALZ 管理组归位

Billing 归属不会自动把订阅放入 ALZ 管理组。治理 Terraform Root 创建层级并且明确启用 `move_subscriptions_into_hierarchy` 后，单独验证管理组关系：

```bash
az account management-group subscription show \
  --name '<alz-intermediate-root-or-target-management-group-id>' \
  --subscription "$SUBSCRIPTION_ID" \
  --output json
```

在 plan 显示目标管理组正确之前，不要启用订阅移动。

## 企业级 Subscription Vending 流程

本地脚本用于演示引导机制。成熟的平台应把订阅交付做成经过审查的产品流程：

```text
申请或 Pull Request
  -> 校验负责人、环境、数据分级、区域和网络类型
  -> 在批准的计费作用域下创建或复用订阅
  -> 放入正确的管理组
  -> 为 Entra 组而不是个人分配权限
  -> 配置预算、标签、策略和诊断默认值
  -> 分配不重叠的地址空间，并按需连接 Spoke
  -> 返回订阅 ID 和运维说明
```

自动化身份应使用工作负载身份联合，在各作用域遵循最小权限；部署前审查 plan，生产环境增加审批，并保留每次订阅交付的审计记录。

## 成本控制

- 每个订阅分别配置预算；预算只能告警，不能强制停止消费。
- 学习用 workspace 设置保守的每日采集上限。
- 在对应实验开始前，保持 Firewall、VPN Gateway、测试 VM、Defender 计划、Sentinel 连接器等收费功能关闭。
- 每次实验结束运行 `scripts/destroy-expensive.sh`。
- 实验期间每天按订阅和服务检查成本。
- 不要假设 Marketplace、支持、预留实例或第三方费用都符合赞助额度条件；应以赞助条款和 Cost Management 数据为准。

## 官方参考

- [以编程方式创建 MCA 订阅](https://learn.microsoft.com/azure/cost-management-billing/manage/programmatically-create-subscription-microsoft-customer-agreement)
- [Subscription vending 指南](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/subscription-vending)
- [管理组与订阅组织](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-management-groups)
