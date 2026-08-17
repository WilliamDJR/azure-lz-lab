# 02 · 企业级 Azure 网络深挖

[English](02-networking.md)

> JD 原文点名的四项：**Hub & Spoke、ExpressRoute、VPN、Private Endpoints**。
> 这一篇覆盖全部，加上路由——路由是真正决定你能不能通过技术面的部分。
> 配合 `terraform/20-platform/` 和 `scripts/show-effective-routes.sh`。

---

## 1. 为什么 Azure 必须搞 Hub-Spoke

GCP 有 **Shared VPC**：一个宿主项目持有网络，多个服务项目直接在里面开子网。一张网，天然互通。

**Azure 没有这个东西。** 每个订阅里的 VNet 都是独立的网络对象。要让它们互通只能 **peering**，而 peering 有一条铁律：

> **VNet peering 不传递（non-transitive）。**
> A↔Hub 通，B↔Hub 通，**A↔B 不通**。

这一条决定了 Azure 企业网络的整个形态。想让 spoke 之间互通，只有三条路：

| 方案 | 做法 | 适用 |
|---|---|---|
| **Hub 里放 NVA + UDR**（本 lab） | spoke 的路由表把流量指向 hub 里的 Azure Firewall，防火墙转发到另一个 spoke | 标准企业做法，流量可审计可管控 |
| **Azure Virtual WAN** | 微软托管的 hub，自带路由服务，支持大规模分支接入 | 站点很多、全球多区域、不想自己管路由 |
| **spoke 直接 peering** | 两两互联 | 只在极少数、延迟敏感的场景用；VNet 数一多就是 O(n²) 灾难 |

设计结论：由于 VNet peering 不传递，spoke-to-spoke 流量需要经过 Hub 中的 Azure Firewall 或其他 NVA，并由 Spoke 子网的 UDR 指定下一跳。规模较大、路由表维护成为瓶颈时，可以评估 Virtual WAN。

---

## 2. 路由：整个话题的核心

Azure 的有效路由 = **系统路由 + UDR + BGP 学到的路由** 三者合并。

### 匹配规则（必须能脱口而出）

1. **最长前缀匹配永远优先。** `/24` 打败 `/16` 打败 `/8` 打败 `0.0.0.0/0`。
2. **前缀长度相同**时，优先级：**UDR > BGP > 系统路由**。

第 2 条是很多人答不上来的。

### 一个真实的坑（本 lab 里就有）

`terraform/20-platform/20-spoke.tf` 的路由表里有一条 `10.0.0.0/8 → 防火墙`。你可能以为这会让 spoke 去 hub 的流量也走防火墙——**不会**。

因为 peering 给 spoke 装了一条系统路由 `10.0.0.0/16 → VNetPeering`（hub 的地址空间），`/16` 比 `/8` 更具体，所以 peering 赢。那条 `/8` 只对**其他** RFC1918 网段生效（比如模拟的本地 `10.100.0.0/16`）。

想让去 hub 的流量也被检查，你必须写一条**至少同样具体**的 UDR。

跑 `scripts/show-effective-routes.sh` 亲眼看一遍。这个实验做过一次，你答路由题就再也不会心虚。

### 强制隧道（forced tunnelling）

在 spoke 子网上放 `0.0.0.0/0 → VirtualAppliance(防火墙私有 IP)`，所有出站流量被拉去防火墙检查。

**两个致命陷阱：**

1. **绝不要在 `AzureFirewallSubnet` 上放 `0.0.0.0/0` 的 UDR** —— 防火墙把流量发给自己，路由环路，整个出口瘫痪。
2. **`GatewaySubnet` 上的 UDR** 用来让本地→spoke 的入向流量也过防火墙。写错了会打断 ExpressRoute 的控制平面。微软明确禁止在 GatewaySubnet 上放 `0.0.0.0/0`。

### `bgp_route_propagation_enabled`

关掉（Terraform 里设 `false`，对应 Portal 的 "Propagate gateway routes: Disabled"）后，网关从本地学到的 BGP 路由**不会**注入这张路由表。效果是本地网段的流量落到你的 `0.0.0.0/0` 默认路由上，也就是被送去防火墙。这是"让回本地的流量也被检查"的标准手法。

---

## 3. Azure Firewall vs NSG vs 应用网关

这三种控制并不是替代关系，而是分层协作：

| | NSG | Azure Firewall | Application Gateway (WAF) |
|---|---|---|---|
| 层级 | L3/L4 | L3–L7（Premium 可 TLS 解密） | L7 HTTP/HTTPS |
| 位置 | 附在子网或网卡上，分布式执行 | hub 里的集中式实例 | 应用前面 |
| FQDN 过滤 | ❌ | ✅（应用规则） | ✅ |
| 成本 | 不单独收费 | 按部署时长并可能包含数据处理费 | 按实例和容量计费 |
| 日志 | 需开 NSG flow logs，且只有元数据 | 完整的允许/拒绝日志 | 完整 |
| 典型职责 | 微分段：谁能访问谁 | 出口控制 + 东西向检查 | 入向 Web 防护 |

### 防火墙策略的父子继承

生产环境的正确做法：安全团队拥有**父策略**（基线拒绝、强制允许清单、威胁情报），每个区域的防火墙用**子策略**继承它，应用团队只能在子策略里加规则。

这种父子策略模式允许应用团队扩展规则，同时保留中央安全基线的控制权。

---

## 4. ExpressRoute

ExpressRoute 需要连接服务商提供物理电路，因此本实验不直接部署它。实验仍可通过 VPN Gateway 练习 Azure 侧的网关传递、路由传播和冗余设计。

### 必须能讲清楚的结构

```
你的机房/托管 ──── 服务商网络 ──── MSEE ──── Microsoft 骨干
   (CE 路由器)      (PCCW/Megaport/    (微软边缘  
                     Equinix...)        路由器，成对冗余)
```

- **Circuit（电路）**：逻辑对象，有带宽（50Mbps–100Gbps）和 SKU（Local / Standard / Premium）
- **永远是一对冗余连接**。单条不是"省钱"，是配置错误——微软的 SLA 只覆盖冗余对。
- **Peering 类型（务必分清）：**
  - **Private peering** — 通到你的 VNet（IaaS 私有 IP）。日常说的 ExpressRoute 就是这个。
  - **Microsoft peering** — 通到微软的公网服务（Microsoft 365、Azure PaaS 公网端点），走公网 IP 但不经互联网。
  - *（Public peering 已弃用，被 Microsoft peering 取代——知道这点说明你读过近几年的文档。）*
- **SKU 差异：** Local 只能连同 metro 的 Azure 区域，最便宜；Standard 覆盖同一地缘政治区域；**Premium** 才能跨区域全球连接、支持更多 VNet 连接数和更大路由表。企业选型题基本就在 Standard vs Premium。
- **ExpressRoute Global Reach**：让两个通过 ExpressRoute 接入的本地站点，借道微软骨干互通——本质上是拿 Azure 当 WAN 用。这是你在运营商世界里最熟悉的那类需求。
- **FastPath**：让数据面绕过 ExpressRoute 网关，直接进 VNet，降低延迟、提高吞吐。代价是部分功能（早期不支持 UDR/NVA 场景）受限。
- **ExpressRoute + VPN 做备份**：标准高可用设计，VPN 作为 ExpressRoute 失效时的降级路径，靠 BGP local preference / AS path prepending 控制优先级。**这句话你说出来会非常有说服力，因为这是纯粹的运营商网络知识。**

### 从 spoke 的角度看

ExpressRoute 网关和 VPN 网关行为几乎一样：都住在 `GatewaySubnet`，都通过 BGP 注入路由，都需要 hub 侧 `allow_gateway_transit = true` + spoke 侧 `use_remote_gateways = true`。

**这就是本 lab 用 VPN 网关代练的原因**——从 spoke 往下看，两者不可区分。`terraform/20-platform/40-vpn-and-onprem.tf` 里的注释也写了这一点。

---

## 5. Private Endpoint 与 DNS（最容易翻车，也最能拉分）

### 解析链路（必须能一口气讲完）

```
1. 客户端解析  myaccount.blob.core.windows.net
2. 公共 Azure DNS 返回 CNAME：
      myaccount.blob.core.windows.net
        → myaccount.privatelink.blob.core.windows.net
3. 因为私有 DNS 区域 privatelink.blob.core.windows.net
   已经 LINK 到客户端所在的 VNet，第二个名字在私网内解析
4. 该区域里的 A 记录（由 private endpoint 的 DNS zone group 自动创建）
   返回 10.1.1.x
5. 客户端连 10.1.1.x，全程走 VNet，不碰互联网
```

**断掉任何一环的症状都一样：名字还能解析，但解析到公网 IP，然后连接失败。**

"能解析但连不上"几乎永远是**私有 DNS 区域没有 link 到那个 VNet**。

`scripts/test-private-dns.sh` 会带你把这条链路跑一遍，然后**故意删掉 VNet link 再跑一次**，看着答案从私有 IP 变成公网 IP。做过这一次，这道题你永远丢不了分。

### 私有 DNS 区域名不是随便起的

| 服务 | 区域名 |
|---|---|
| Blob 存储 | `privatelink.blob.core.windows.net` |
| Key Vault | `privatelink.vaultcore.azure.net` |
| Azure SQL | `privatelink.database.windows.net` |
| AKS API server | `privatelink.<region>.azmk8s.io` |
| Azure Container Registry | `privatelink.azurecr.io` |

写错一个字母，静默失败。

### 企业里的正确架构

私有 DNS 区域**集中放在 Connectivity 订阅**，link 到所有 spoke，由平台团队用 Azure Policy（DINE）强制每个新建的 private endpoint 自动注册到中央区域。

否则每个应用团队各建各的区域，很快就会出现同名冲突和陈旧 A 记录指向已回收私有 IP 的问题。

本 lab 就是这么做的：区域建在 connectivity 资源组里（`50-private-link.tf`）。

### Private Endpoint vs Service Endpoint

还会被问到的一对：

- **Service Endpoint**：把子网的身份带给 PaaS 服务，PaaS 侧按子网做访问控制。流量还是走公网 IP 空间，只是不出微软骨干。**不能**从本地访问，不解决 DNS 问题，免费。
- **Private Endpoint**：在你的 VNet 里给 PaaS 服务分配一个**真实私有 IP**。可以从本地经 ExpressRoute/VPN 访问。按小时+流量计费。

**现代企业基本一律用 Private Endpoint**，Service Endpoint 是遗留方案。

### 168.63.129.16

这个地址要认识。它是 Azure 平台在**每一个 VNet** 里都存在的魔法地址，承担 DNS 解析、DHCP、负载均衡健康探测、VM agent 心跳。私有 DNS 区域能生效，就是因为 VM 默认把 DNS 指向它。

如果你在防火墙上把它的 53 端口封了，整个 VNet 的名字解析就断了——`30-firewall.tf` 里那条 `allow-dns-out` 规则就是为此存在。

### Azure DNS Private Resolver

本 lab 没部署（要额外收费），但要知道它解决什么问题：**让本地 DNS 服务器能解析 Azure 私有区域**。

在有 ExpressRoute 的混合环境里，本地机器也要访问 private endpoint，就需要在 hub 里放一个 inbound endpoint，本地 DNS 条件转发过来。以前大家用一对自建 DNS 转发 VM 做这件事，Private Resolver 是它的托管替代品。

在混合环境中，本地 DNS 可以通过条件转发把私有区域查询转发到 Hub 中 DNS Private Resolver 的 inbound endpoint。

---

## 6. 动手清单

对照 `terraform/20-platform/`：

**第一阶段（几乎零成本，先做这个）**
- [ ] apply 基础拓扑（所有开关关闭，只留 test VM）
- [ ] 跑 `scripts/show-effective-routes.sh`，记下基线路由表
- [ ] 跑 `scripts/test-private-dns.sh`，看懂 CNAME 链
- [ ] **故意破坏**：`terraform destroy -target=azurerm_private_dns_zone_virtual_network_link.blob_to_spoke`，再跑一次 DNS 测试，观察解析结果变成公网 IP
- [ ] `terraform apply` 修回来

**第二阶段（一个下午，用完即拆）**
- [ ] `enable_firewall = true`，apply
- [ ] 再跑 `show-effective-routes.sh`，diff 对比——看到 User 来源的路由出现
- [ ] 在 VM 上 `curl https://github.com`（应该通，防火墙规则允许了）
- [ ] `curl https://www.reddit.com`（应该被拒——不在允许清单里）
- [ ] 去 Log Analytics 用 KQL 查那条拒绝记录：
  ```kusto
  AZFWApplicationRule
  | where TimeGenerated > ago(30m)
  | project TimeGenerated, SourceIp, Fqdn, Action, Rule
  | order by TimeGenerated desc
  ```
- [ ] 跑 `scripts/destroy-expensive.sh`

**第三阶段（一个下午，网关建起来要 40 分钟）**
- [ ] `enable_vpn_gateway = true` + `enable_simulated_onprem = true`
- [ ] 在 Portal 看两条连接从 Connecting 变 Connected
- [ ] 第三次跑 `show-effective-routes.sh`——看到 VirtualNetworkGateway 来源的路由
- [ ] 从 spoke 的 VM ping 模拟本地网段的地址，验证 gateway transit 生效
- [ ] `scripts/destroy-expensive.sh`
