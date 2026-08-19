# 02 · 企业级 Azure 网络

[English](02-networking.md)

本章说明 `terraform/20-platform/` 使用的网络机制：Hub-Spoke、有效路由、Azure Firewall、VPN/ExpressRoute Gateway Transit、Private Endpoint 和 Private DNS。仓库的两条路线都能验证相同的报文与 DNS 行为。在单订阅路线中，Provider Alias 指向同一个订阅，资源组也只是逻辑边界，不能模拟跨订阅访问控制和故障隔离。

## 1. 为什么使用 Hub-Spoke

Azure VNet 是彼此独立的网络对象。VNet Peering 可以连接两个 VNet，但 Peering 不具备传递性：

```text
Spoke A <-> Hub <-> Spoke B

这两条 Peering 不会自动产生 Spoke A <-> Spoke B 可达性。
```

常见的扩展连接方式包括：

| 模式 | 机制 | 常见用途 |
|---|---|---|
| Hub NVA 加 UDR | Spoke 路由表把指定流量发送到 Hub 中的 Azure Firewall 或其他 NVA | 集中检查与可审计出口 |
| Azure Virtual WAN | Microsoft 托管 Hub 与路由 | 大量分支或多区域环境 |
| Spoke 直接 Peering | 只把部分 Spoke 两两连接 | 少量对延迟敏感的路径 |

直接 Spoke Peering 的连接数量会随 VNet 数量快速增长。规模扩大后，中央 Hub 或 Virtual WAN 通常更容易治理。

## 2. 路由与有效路由

Azure 根据系统路由、用户定义路由（UDR）和 Virtual Network Gateway 学到的路由，计算网卡的有效路由。

### 路由选择

1. 最长前缀匹配优先：`/24` 优先于 `/16`，`/16` 优先于 `/8`，以上均优先于 `0.0.0.0/0`。
2. 前缀相同时，通常按 UDR、BGP、系统路由的顺序选择。

应检查最终有效路由表，而不是只根据某一张 Route Table 推断真实行为。

### 仓库中的验证示例

启用 Firewall 后，`terraform/20-platform/20-spoke.tf` 会增加 `10.0.0.0/8 -> VirtualAppliance`。Hub Peering 同时提供更具体的 `10.0.0.0/16 -> VNetPeering` 路由，因此 `/16` 获胜；宽泛的 `/8` 不会检查前往 Hub 的流量，只会在没有更具体路由时生效。

启用 Firewall 前后分别运行 `scripts/show-effective-routes.sh`，对比 `Address Prefix`、`Next Hop Type`、`Source` 和 `State`。

### 强制隧道

Spoke 上的 `0.0.0.0/0 -> VirtualAppliance(<firewall-private-ip>)` UDR 会把常规出站流量送到 Hub Firewall。需要遵守两个安全规则：

- 不要在 `AzureFirewallSubnet` 上配置指回防火墙自身的默认路由，否则可能形成路由环路。
- 不要在 `GatewaySubnet` 上配置 `0.0.0.0/0`。Gateway Subnet 的路由修改必须符合受支持的 ExpressRoute/VPN 设计，错误路由可能破坏网关控制平面。

不要把 Azure 隐式 Default Outbound Access 当作设计前提。对于 2026 年 3 月 31 日之后发布的 API 版本，新 VNet 默认使用 Private Subnet，需要 NAT Gateway、Load Balancer Outbound Rule、公网 IP 或 Firewall 路径等显式出口。基线结果可能受已安装 Provider 使用的 API 行为影响；应记录脚本实际结果，而不是假设一定能访问互联网。[Microsoft Default Outbound Access 指南](https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access)

### Gateway 路由传播

`bgp_route_propagation_enabled` 控制 Virtual Network Gateway 学到的路由是否进入关联子网的 Route Table。关闭传播可以让流量落到 UDR，但也可能移除通往混合网络前缀的唯一有效路由。修改前应先准备预期路由表和回滚方案。

## 3. Azure Firewall、NSG 与 Application Gateway

三类控制工作在不同层次：

| | NSG | Azure Firewall | 带 WAF 的 Application Gateway |
|---|---|---|---|
| 主要层次 | L3/L4 | L3-L7；Premium 提供额外检查能力 | L7 HTTP/HTTPS |
| 部署位置 | 子网或网卡 | 中央 Hub | Web 应用之前 |
| FQDN 规则 | 不支持 | 支持 | 支持主机与 HTTP 感知路由/防护 |
| 成本 | NSG 无单独费用 | 部署时长加数据处理 | 实例/容量计费 |
| 典型用途 | 分布式微分段 | 中央出口与东西向控制 | 入向 Web 交付和 WAF |

NSG 负责子网或网卡通信边界，Azure Firewall 负责集中网络与应用规则，Application Gateway/WAF 负责入向 HTTP 控制。

### Firewall Policy 继承

一种常见运营模式是由安全团队维护父 Firewall Policy，其中包含强制规则和威胁情报设置。区域或委派团队可以在子 Policy 中添加获准的本地规则，而不替换中央基线。本仓库部署一个 Policy；父子委派属于生产化扩展。

## 4. ExpressRoute 与 VPN 模拟

ExpressRoute 需要服务商电路，因此本仓库不会创建真实电路，而是使用 VPN Gateway 演示 Azure 侧的 Gateway Transit 和有效路由行为。

```text
数据中心/托管机房 ---- 服务商网络 ---- Microsoft Enterprise Edge ---- Azure 骨干网
      CE 路由器            运营商/交换点             冗余边缘路由器
```

- ExpressRoute Circuit 是具有带宽及 Local、Standard 或 Premium SKU 的逻辑服务。
- 生产设计使用冗余连接，并验证两条路径。
- Private Peering 连接 VNet 私网地址空间。
- Microsoft Peering 通过发布的公网前缀访问受支持的 Microsoft 公共服务；原 Public Peering 已停用。
- Local、Standard 和 Premium 的地理范围、路由规模与连接限制不同。
- Global Reach 通过 Microsoft 骨干连接受支持的本地站点。
- FastPath 可在受支持配置中让数据路径绕过 Gateway。
- VPN 可作为弹性备用路径，但必须验证路由优先级和故障切换。

### 从 Spoke 观察

VPN 与 ExpressRoute Gateway 都使用 `GatewaySubnet`，并可以把远端前缀发布给 Spoke。Hub Peering 使用 `allow_gateway_transit = true`，Spoke Peering 使用 `use_remote_gateways = true`。VPN 实验能验证这些 Azure 侧控制，但不能模拟 ExpressRoute 服务商电路、SLA、Microsoft Peering 或 FastPath。

模拟本地拓扑包含第二个 VNet、两个 VPN Gateway 和两条 VNet-to-VNet Connection。目前模拟本地 Workload Subnet 中没有 VM 或其他 Endpoint，因此有效证据是 Gateway Connection 状态和 Learned/Effective Routes，而不是端到端应用流量。

## 5. Private Endpoint 与 DNS

### 解析路径

```text
1. 客户端解析 myaccount.blob.core.windows.net。
2. 公共 Azure DNS 返回指向
   myaccount.privatelink.blob.core.windows.net 的 CNAME。
3. 名为 privatelink.blob.core.windows.net 的 Private DNS Zone
   已链接到客户端 VNet。
4. Private Endpoint DNS Zone Group 维护 10.1.1.x 一类的 A 记录。
5. 客户端通过 VNet 连接该私有地址。
```

如果缺少 Zone Link 或私有记录，名称可能解析到公网地址。本仓库中的 Storage Account 已关闭 Public Network Access，因此公网连接会失败。DNS 查询成功本身并不能证明私有路径正确。

### 服务对应的 Zone 名称

| 服务 | 常用 Private DNS Zone |
|---|---|
| Blob Storage | `privatelink.blob.core.windows.net` |
| Key Vault | `privatelink.vaultcore.azure.net` |
| Azure SQL Database | `privatelink.database.windows.net` |
| Azure Container Registry | `privatelink.azurecr.io` |

应根据当前 Microsoft Private Link DNS 参考确认具体服务和云环境。Zone 名称或 Subresource 错误都会造成解析路径不完整。

### 中央 DNS 设计

在多订阅目标中，Private DNS Zone 位于 Connectivity 订阅，并链接到获准的 Spoke。在单订阅路线中，相同资源位于逻辑 Connectivity 资源组。DNS 行为相同，但没有订阅级所有权和 RBAC 隔离。

规模扩大后，应自动化 Zone Link 和记录注册，并明确重复 Zone、陈旧记录和应用团队请求的处理责任。

### Private Endpoint 与 Service Endpoint

- Service Endpoint 允许 PaaS 服务授权来自指定 VNet Subnet 的流量，服务仍使用公网 Endpoint 地址。
- Private Endpoint 在 VNet 中为特定 PaaS Subresource 放置私有 IP，并引入 Private Link DNS 配置要求。

选型时应同时考虑访问方式、混合连接、DNS、数据泄露防护、成本和服务支持情况。需要从 Azure 或混合网络通过私有地址访问服务时，Private Endpoint 更合适。

### `168.63.129.16` 与 DNS Private Resolver

`168.63.129.16` 是 Azure 平台虚拟 IP，用于 Azure-provided DNS、VM Agent 通信等服务。阻断平台依赖前，应检查 Microsoft 对 NSG、路由、防火墙和 Guest OS 的说明。

Azure DNS Private Resolver 通过托管 Inbound/Outbound Endpoint 支持混合 DNS。On-premises Resolver 可以把 Azure Private Zone 查询条件转发到 Hub 中的 Inbound Endpoint。本仓库说明该模式，但因额外成本不部署 Resolver。

## 6. 实验流程

从仓库根目录运行命令。先完成 Platform 基线，并在使用验证脚本期间保持 `enable_test_vm = true`。

必须为当前路线选择且只选择一个 Manifest，并在同一个 Shell 中保留该 Export。路径相对于 `terraform/20-platform/`；`terraform -chdir` 和辅助脚本都会在该目录解析它。

多订阅路线：

```bash
export SUBSCRIPTION_VAR_FILE='../subscriptions.tfvars'
```

单订阅路线：

```bash
export SUBSCRIPTION_VAR_FILE='../subscriptions.single.tfvars'
```

不要让多订阅 Manifest 指向单订阅 State，也不要让单订阅 Manifest 指向多订阅 State。

### 第一阶段：低成本基线

基线经过成本控制，但不是免费。它可能包含小型 VM、OS Disk、Log Analytics 采集、Storage 和 Private Endpoint。

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-baseline.txt
./scripts/test-private-dns.sh
./scripts/test-egress.sh
```

预期现象：

- Storage FQDN 经过 CNAME 后解析到 Terraform 输出的 `private_endpoint_ip`。
- 测试 VM 网卡包含系统和 Peering 路由，但还没有 Firewall UDR。
- 启用 Firewall 前，出口测试用于记录 Subnet 是否仍有隐式出站能力。如果 Subnet 默认为 Private，两个公网测试都可能失败，直到增加显式出口。

成功完成基线后再运行受控 DNS 故障：

```bash
terraform -chdir=terraform/20-platform destroy \
  -var-file="$SUBSCRIPTION_VAR_FILE" \
  -target=azurerm_private_dns_zone_virtual_network_link.blob_to_spoke

./scripts/test-private-dns.sh

terraform -chdir=terraform/20-platform apply \
  -var-file="$SUBSCRIPTION_VAR_FILE"

./scripts/test-private-dns.sh
```

DNS Cache 和 Azure 传播可能使解析变化延迟。判断 Link 删除或恢复失败前，应等待并重试。`-target` 只用于这个受控实验。

### 第二阶段：Firewall 实验

设置 `enable_firewall = true`，审查 Plan 后 Apply：

```bash
terraform -chdir=terraform/20-platform plan \
  -var-file="$SUBSCRIPTION_VAR_FILE" \
  -out=tfplan
terraform -chdir=terraform/20-platform show tfplan
terraform -chdir=terraform/20-platform apply tfplan

./scripts/show-effective-routes.sh | tee /tmp/alz-routes-firewall.txt
diff -u /tmp/alz-routes-baseline.txt /tmp/alz-routes-firewall.txt
./scripts/test-egress.sh
```

`github.com` 应匹配允许的 Application Rule；未列入清单的测试地址应被阻止。应使用 Log Analytics 确认原因，不能只把 Timeout 当成防火墙证据：

```kusto
AZFWApplicationRule
| where TimeGenerated > ago(30m)
| project TimeGenerated, SourceIp, Fqdn, Action, Rule
| order by TimeGenerated desc
```

立即结束收费会话：

```bash
./scripts/destroy-expensive.sh
```

该清理脚本也会删除私网测试 VM 及其 NIC。同时把 `terraform/20-platform/terraform.tfvars` 中的成本开关恢复为 `false`，避免后续 Apply 意外重新创建资源。

### 第三阶段：模拟混合网络路由

只有完成成本审批后才运行本阶段。前一步清理已删除 `show-effective-routes.sh` 所需的 NIC，因此本阶段必须显式重建测试 VM。保持 Firewall 关闭，把两个 Gateway 开关设为 `true`，并在本地设置至少 16 个字符的 `vpn_shared_key`：

```hcl
enable_firewall         = false
enable_vpn_gateway      = true
enable_simulated_onprem = true
enable_test_vm          = true
vpn_shared_key          = "<local-value-at-least-16-characters>"
```

使用当前路线的 Manifest 审查并 Apply：

```bash
terraform -chdir=terraform/20-platform plan \
  -var-file="$SUBSCRIPTION_VAR_FILE" \
  -out=tfplan
terraform -chdir=terraform/20-platform show tfplan
terraform -chdir=terraform/20-platform apply tfplan
```

部署完成后验证 Provider Alias 使用的两个订阅。在单订阅模式下两个 ID 相同，因此第二次查询会有意重复：

```bash
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

保存 `Connected` Gateway Connection 和 `VirtualNetworkGateway` 路由证据。由于模拟本地 Subnet 没有 Endpoint，不应声称完成应用连通性测试。随后删除 Gateway 和测试 VM：

```bash
./scripts/destroy-expensive.sh
```

把 `terraform/20-platform/terraform.tfvars` 中的 `enable_vpn_gateway`、`enable_simulated_onprem` 和 `enable_test_vm` 恢复为 `false`。

---

下一篇：[03-azure-devops_cn.md](03-azure-devops_cn.md) — 平台交付与运维
