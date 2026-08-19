# 04 · 多订阅引导与自动交付

[English](04-subscription-vending.md)

本实验把 Azure 的计费归属与 ALZ 治理归属分开处理。两者有关联，但任何一套层级都不会自动配置另一套。

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
5. 验证成功后再创建其余角色订阅。
6. 把订阅 ID 记录在 `terraform/subscriptions.tfvars` 中，绝不要提交该文件。
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

# 验证成本归属后再创建全部角色订阅
./scripts/create-subscriptions.sh --role all --execute
```

全量运行会复用已有 alias，并且只会在 `terraform/subscriptions.tfvars` 不存在时写入该文件。执行任何 Terraform apply 前都要检查生成的 ID。

如果订阅已经存在，不要运行创建脚本。把 `terraform/subscriptions.tfvars.example` 复制为 `terraform/subscriptions.tfvars`，然后手工填写 ID。

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
