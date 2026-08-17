# Azure Landing Zone 学习与部署实验室

[English](README.md)

> 这是一套按“先理解基础知识，再动手部署和验证”组织的 Azure Landing Zone（ALZ）实验。
> 它使用 Terraform 搭建治理、Hub-Spoke 网络、Private Endpoint、Azure Firewall、
> VPN Gateway、可观测性和 Azure Pipelines 示例。

## 学习目标

完成主路径后，你应该能够：

- 解释 ALZ 中管理组、订阅、平台 Landing Zone 和应用 Landing Zone 的职责边界。
- 使用 Azure Policy 实现区域限制、禁止公网 IP，以及 DeployIfNotExists（DINE）治理。
- 理解 Hub-Spoke、系统路由、UDR、VNet Peering、网关路由传播和强制隧道。
- 从工作负载端验证 Private Endpoint 的 DNS 解析链路，并定位常见故障。
- 部署 Azure Firewall 和模拟混合连接，观察有效路由及日志的变化。
- 使用 Terraform 和 Azure Pipelines 形成可重复、可审查的基础设施交付流程。

## 当前内容是否足够

对于“理解 ALZ 核心机制并完成一次端到端动手实验”，当前内容已经覆盖了最重要的治理、
网络、Private Link、日志和自动化主题。它不是完整的 Azure 学习体系，也不是生产级 ALZ。

| ALZ 设计领域 | 当前覆盖程度 | 仓库中的内容 |
|---|---|---|
| 计费与租户 | 入门 | 单订阅实验、成本开关、预算建议 |
| 身份与访问 | 较少 | 托管身份、流水线工作负载身份；尚未系统练习 RBAC/PIM |
| 资源组织 | 重点 | 管理组、订阅归属、Platform/Corp/Online/Sandbox 层级 |
| 网络与连接 | 重点 | Hub-Spoke、UDR、防火墙、VPN Gateway、Private DNS |
| 安全 | 部分 | Azure Policy、NSG、防火墙；尚未覆盖 Defender for Cloud 和 Key Vault |
| 管理与运维 | 部分 | Log Analytics、诊断设置、KQL；尚未覆盖告警、备份和灾难恢复 |
| 治理 | 重点 | Audit、Deny、DINE、合规评估和修复机制 |
| 平台自动化与 DevOps | 重点 | Terraform、Azure Pipelines 模板、审批和 OIDC |

因此，建议先完成本 README 的主路径，再按文末的“后续扩展方向”补齐身份、安全、运维和
真实工作负载部署。

## 仓库结构

```text
docs/
  01-ALZ-concepts_cn.md    ALZ、管理组、订阅组织、Policy 和八大设计领域
  02-networking_cn.md      Hub-Spoke、路由、防火墙、混合连接和 Private Endpoint DNS
  03-azure-devops_cn.md    Azure Pipelines、模板、表达式、环境审批和 KQL

terraform/
  10-governance/           管理组层级、订阅归属和 Azure Policy
  20-platform/             Hub/Spoke、Private Link、日志、防火墙和 VPN Gateway

azure-devops/              可运行的 Azure Pipelines 模板示例

scripts/
  test-private-dns.sh      从测试 VM 验证 Private Endpoint DNS
  show-effective-routes.sh 查看测试 VM 网卡的有效路由
  destroy-expensive.sh     删除按小时计费的防火墙和网关
  nuke-everything.sh       删除整个实验环境
```

---

# 第一部分：基础知识

先完成这一部分，再开始部署。这样可以在查看 Terraform 计划时理解每项资源的用途，
而不是只执行命令。

## 1. ALZ 与治理基础

阅读 [`docs/01-ALZ-concepts_cn.md`](docs/01-ALZ-concepts_cn.md)，重点理解：

- Tenant、Management Group、Subscription、Resource Group 的层级关系。
- Platform Landing Zone 与 Application Landing Zone 的区别。
- Platform、Landing Zones、Corp、Online、Sandbox、Decommissioned 的职责。
- Azure Policy 的作用域、继承、豁免，以及 Audit、Deny、DINE 的差异。
- 为什么治理策略通常从一个中间根管理组开始，而不是直接堆在 Tenant Root Group。

学习检查：给定一个新工作负载，能够判断它应进入哪个订阅/管理组，以及它会继承哪些策略。

## 2. 网络基础

阅读 [`docs/02-networking_cn.md`](docs/02-networking_cn.md)，重点理解：

- Hub-Spoke 的流量路径和 VNet Peering 的非传递性。
- Azure 路由的最长前缀匹配，以及 UDR、BGP 和系统路由的优先关系。
- NSG、Azure Firewall 和应用网关解决的是哪些不同问题。
- Private Endpoint、Private DNS Zone、VNet Link 和 DNS Zone Group 的关系。
- VPN Gateway/ExpressRoute Gateway、网关传递和远程网关的配对配置。

学习检查：能够画出 Spoke 到互联网、Hub、另一个 Spoke、Private Endpoint 和本地网络的路径。

## 3. 运维与自动化基础

阅读 [`docs/03-azure-devops_cn.md`](docs/03-azure-devops_cn.md) 的第 1–5 节，并浏览
[`azure-devops/README_cn.md`](azure-devops/README_cn.md)，重点理解：

- Terraform 的 `init`、`validate`、`plan`、`apply` 和 `destroy` 生命周期。
- Azure Pipelines 中模板、变量组、服务连接、Environment 和审批的职责。
- 编译期、运行期和宏变量三类表达式的求值时机。
- Log Analytics、诊断设置和 KQL 如何形成基本排障闭环。

学习检查：能够说明为什么应先审查保存的 Terraform plan，再应用同一个 plan。

---

# 第二部分：部署与验证

## 0. 准备环境

### 工具与权限

- 一个专门用于实验的 Azure 订阅。不要直接在生产订阅或公司租户中运行。
- Azure CLI、Terraform `>= 1.5.0`、Git 和 Bash。
- 订阅资源部署权限。
- 创建管理组、分配管理组级 Policy、移动订阅和创建角色分配所需的租户级权限。
  在企业租户中，这些权限通常需要管理员明确授予；没有权限时可只做平台网络部分。
- 区域配额足以创建 Standard_B1s VM、Azure Firewall 和 VpnGw1。防火墙和网关是可选实验。

确认工具版本：

```bash
az version
terraform version
```

登录并确认目标订阅：

```bash
az login
az account set --subscription "<订阅名称或 ID>"
az account show --query '{name:name,id:id,tenantId:tenantId}' --output table
```

如果部署提示资源提供程序未注册，并且你有注册权限，可运行：

```bash
for namespace in Microsoft.Network Microsoft.Compute Microsoft.Storage \
  Microsoft.OperationalInsights Microsoft.Insights; do
  az provider register --namespace "$namespace"
done
```

### 成本保护

在 Azure Portal 的 **Cost Management + Billing → Budgets** 中先创建月度预算，建议设置
50%、80% 和 100% 通知。价格会随区域、币种和计费协议变化，请在启用防火墙或网关前使用
[Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) 重新确认。

默认配置会创建一台 B1s 测试 VM、Private Endpoint 和 Log Analytics Workspace；
`enable_firewall`、`enable_vpn_gateway`、`enable_simulated_onprem` 默认均为 `false`。

## 1. 部署治理层

```bash
cd terraform/10-governance
cp terraform.tfvars.example terraform.tfvars
```

编辑 `terraform.tfvars`，至少填写 `subscription_id`，并为 `prefix` 使用租户内唯一的短名称。
第一次部署保持：

```hcl
move_subscription_into_hierarchy = false
public_ip_policy_effect           = "Audit"
```

初始化、检查并审查部署计划：

```bash
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

到 Portal 的 **Management groups** 和 **Policy** 页面核对层级与分配。首次启用管理组服务时，
资源出现可能需要一些时间。

## 2. 验证订阅归属和 Policy

将治理层 `terraform.tfvars` 修改为：

```hcl
move_subscription_into_hierarchy = true
public_ip_policy_effect           = "Deny"
```

重新执行 `terraform plan -out=tfplan`、审查后 `terraform apply tfplan`。等待 Policy 完成传播和
首次评估，然后故意部署一个带公网 IP 的 VM，验证 Deny：

```bash
az group create --name rg-alz-policy-test --location australiaeast

az vm create \
  --resource-group rg-alz-policy-test \
  --name vm-should-fail \
  --image Ubuntu2404 \
  --public-ip-address pip-policy-test \
  --generate-ssh-keys
```

预期 VM/NIC 部署被 Policy 拒绝。检查错误中的 Policy assignment/definition ID，再删除测试资源组：

```bash
az group delete --name rg-alz-policy-test --yes --no-wait
```

如果 VM 成功创建，不要直接判定配置错误；先确认订阅已经位于 Corp 管理组下，并等待策略传播后重试。

## 3. 部署基础平台

```bash
cd ../20-platform
cp terraform.tfvars.example terraform.tfvars
```

填写同一个 `subscription_id`。第一次保持三个高成本开关为 `false`，并保留测试 VM：

```hcl
enable_firewall         = false
enable_vpn_gateway      = false
enable_simulated_onprem = false
enable_test_vm          = true
```

```bash
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
terraform output
```

这一步会创建 Hub/Spoke、Peering、NSG、Private DNS、Storage Private Endpoint、Log Analytics
和一台无公网 IP 的测试 VM。

## 4. 验证路由和 Private Endpoint DNS

回到仓库根目录：

```bash
cd ../..
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-baseline.txt
./scripts/test-private-dns.sh
```

DNS 测试的预期结果是：Storage 公网名称返回 `privatelink` CNAME，最终 A 记录解析到
`10.1.1.x` 的 Private Endpoint 地址。

故意删除 Spoke 的 Private DNS Zone Link，再观察结果：

```bash
terraform -chdir=terraform/20-platform destroy \
  -target=azurerm_private_dns_zone_virtual_network_link.blob_to_spoke

./scripts/test-private-dns.sh
terraform -chdir=terraform/20-platform apply
```

`-target` 只用于这个受控故障实验，不应作为日常部署方式。修复后再次运行 DNS 测试，确认私有解析恢复。

## 5. 连接治理与日志

平台层部署后，获取 Log Analytics Workspace ID：

```bash
terraform -chdir=terraform/20-platform output -raw log_analytics_workspace_id
```

把输出填入 `terraform/10-governance/terraform.tfvars` 的 `log_analytics_workspace_id`，然后在治理层
重新执行 plan/apply。该步骤会启用 DINE 示例及其托管身份和角色分配。

在 Portal 的 **Policy → Compliance** 中检查合规状态，并观察现有资源通常需要重新评估或创建
remediation task 才会补齐配置。

## 6. 部署 Azure Firewall 并观察强制隧道

在 `terraform/20-platform/terraform.tfvars` 中设置：

```hcl
enable_firewall   = true
firewall_sku_tier = "Standard"
```

执行 plan/apply。部署完成后保存新的有效路由并与基线比较：

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-firewall.txt
diff -u /tmp/alz-routes-baseline.txt /tmp/alz-routes-firewall.txt
```

验证允许和拒绝的出口请求：

```bash
RG=$(terraform -chdir=terraform/20-platform output -raw landing_zone_resource_group)
VM=$(terraform -chdir=terraform/20-platform output -raw test_vm_name)

az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript \
  --scripts "curl -sS -o /dev/null -w 'github: %{http_code}\n' https://github.com; \
             curl -sS -m 10 -o /dev/null -w 'reddit: %{http_code}\n' https://www.reddit.com || echo 'reddit: blocked'"
```

在 Log Analytics 中使用 [`docs/03-azure-devops_cn.md`](docs/03-azure-devops_cn.md) 第 5 节的 KQL
查询 Firewall allow/deny 记录。日志写入可能有几分钟延迟。

完成后立即删除高成本资源，并把 `terraform.tfvars` 中相应开关改回 `false`：

```bash
./scripts/destroy-expensive.sh
```

## 7. 部署模拟混合连接

确认防火墙已经删除，再设置：

```hcl
enable_vpn_gateway      = true
enable_simulated_onprem = true
```

执行 plan/apply。两个网关可能需要较长时间完成部署。完成后再次查看有效路由：

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-gateway.txt
```

重点检查 `VirtualNetworkGateway` 来源的路由，以及 Hub/Spoke Peering 中
`allow_gateway_transit` 和 `use_remote_gateways` 的配合。

验证完成后立即运行：

```bash
./scripts/destroy-expensive.sh
```

然后把 `terraform.tfvars` 中两个网关开关改回 `false`，避免下一次普通 `terraform apply` 将其重建。

## 8. 运行 Azure Pipelines 示例（可选）

按 [`azure-devops/README_cn.md`](azure-devops/README_cn.md) 创建服务连接、变量组和 Environment，
再运行 `azure-devops/azure-pipelines.yml`。检查以下行为：

- Pull Request 只执行 validate 和 plan。
- 主分支 apply 需要 Environment approval。
- 流水线使用工作负载身份联合，不保存长期客户端密钥。
- apply 使用已发布并经过审查的 plan artifact，而不是重新生成计划。

## 9. 停止计费与完整清理

短暂停止测试 VM：

```bash
az vm deallocate --resource-group \
  "$(terraform -chdir=terraform/20-platform output -raw landing_zone_resource_group)" \
  --name "$(terraform -chdir=terraform/20-platform output -raw test_vm_name)"
```

只删除防火墙和网关：

```bash
./scripts/destroy-expensive.sh
```

删除整个实验室：

```bash
./scripts/nuke-everything.sh
```

清理后同时检查 Terraform 输出、Azure Portal 和带 `lab=true` 标签的资源，确认没有遗漏。

---

## 建议保留的学习证据

- 三份有效路由输出：基线、防火墙开启后、网关开启后。
- Private DNS 正常、断开 VNet Link、修复后的三次解析结果。
- Policy Deny 错误和对应的 assignment/definition ID。
- Log Analytics 中的 Firewall allow/deny 查询结果。
- 每个阶段审查过的 Terraform plan，以及一张最终拓扑图。
- 一份故障记录：现象、假设、验证步骤、根因和修复结果。

## 后续扩展方向

完成本实验后，按以下顺序扩展会更完整：

1. **身份与权限**：RBAC、自定义角色、Managed Identity、PIM、Break-glass 账号和 Conditional Access。
2. **密钥与安全**：Key Vault Private Endpoint、密钥轮换、Defender for Cloud 和安全基线策略。
3. **真实工作负载**：在 Application Landing Zone 部署 App Service、Container Apps 或 AKS，接入应用网关/WAF。
4. **运维与韧性**：Azure Monitor Alert、Action Group、Update Manager、Backup、Site Recovery 和多区域设计。
5. **规模化平台**：多订阅、Subscription Vending、远程 Terraform State、模块版本管理和策略即代码测试。

## 已知限制

- 这是单订阅、手写且简化的 ALZ。真实 ALZ 通常使用多个平台订阅和应用订阅。
- ExpressRoute 需要真实线路和服务商，本实验只覆盖网关之后的路由与传播机制。
- 代码能够通过 `terraform fmt` 解析，但不同 AzureRM Provider 版本、区域配额和租户策略仍可能导致
  `validate` 或 `plan` 出现差异；每次都应审查 plan，不要无条件 apply。
- 生产环境应优先评估 Microsoft 提供的 ALZ IaC Accelerator、Azure Verified Modules 或官方 Bicep
  实现，并根据组织要求调整，而不是直接复制本实验。

## 官方参考

- [What is an Azure landing zone?](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/)
- [Azure landing zone design areas](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas)
- [Authenticate Terraform to Azure](https://learn.microsoft.com/azure/developer/terraform/authenticate-to-azure)
- [Create a management group](https://learn.microsoft.com/azure/governance/management-groups/create-management-group-portal)
- [Azure CLI budget commands](https://learn.microsoft.com/cli/azure/consumption/budget)
