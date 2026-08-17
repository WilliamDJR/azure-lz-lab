# 01 · Azure Landing Zone 核心概念

[English](01-ALZ-concepts.md)

> 目标：读完这一篇，你能理解 ALZ 的核心结构，并知道每个概念在 GCP 里对应什么。
> 预计阅读时间 30 分钟。配合 `terraform/10-governance/` 一起看。

---

## 一句话定义

**Azure Landing Zone (ALZ) 是在跑任何业务负载之前，用代码预置好的一整套租户级底座**——组织结构、身份、网络、策略护栏、监控、计费全部就位，之后每个应用团队拿到的是一个"已经被治理好的订阅"，而不是一张白纸。

它是微软 **Cloud Adoption Framework (CAF)** 的 "Ready" 阶段产物。

**最关键的认知转变**：landing zone 不是"一个网络"。它是**一个预先治理好的订阅（a pre-governed subscription）**。网络只是它八个设计域里的一个。把 ALZ 等同于 hub-spoke 是最典型的理解偏差。

---

## 与 GCP 的概念映射

你在 GCP 上接触过的许多平台概念，在 Azure 里都有对应物。对照这些概念，可以更快理解 Azure 的边界和机制差异。

| 你熟悉的 GCP | Azure 对应 | 关键差异 |
|---|---|---|
| Organization | Tenant Root Group（Entra 租户） | Azure 的租户边界是**身份**边界，不是资源边界 |
| Folder | **Management Group**（最多 6 层，不含租户根） | 可以嵌套，策略沿层级继承 |
| Project | **Subscription** | 订阅同时是**计费边界**和**配额边界**，比 project 更"重"，不能随便开几百个 |
| — | **Resource Group** | GCP 没有这一层。RG 是部署/生命周期/RBAC 的单位，同一 RG 的资源通常一起生死 |
| Organization Policy | **Azure Policy**（+ Initiative 策略集） | Azure Policy 强得多：除了 Deny/Audit，还能 **deployIfNotExists / modify** 自动修复 |
| IAM Policy binding | **Azure RBAC**（role assignment） | 作用域是 MG / Sub / RG / Resource 四级，向下继承 |
| — | **Microsoft Entra ID** | 身份平面和资源平面是**分开**的。Entra 角色（Global Admin）≠ Azure RBAC 角色（Owner）。这是最容易混淆的点 |
| Shared VPC | **没有等价物** → 用 Hub-Spoke VNet peering 代替 | 这就是 hub-spoke 存在的根本原因 |
| VPC Peering | VNet Peering | 同样**不传递** |
| Cloud Interconnect / Partner Interconnect | **ExpressRoute** | 通过连接服务商接入 Microsoft 骨干网 |
| Cloud VPN | VPN Gateway | |
| Private Service Connect | **Private Endpoint / Private Link** | Azure 版本强依赖 DNS 覆写，坑全在 DNS |
| Cloud Logging + Monitoring | **Azure Monitor**（Log Analytics workspace + KQL） | 查询语言是 KQL |
| Cloud Asset Inventory | Azure Resource Graph（也是 KQL） | |
| Terraform on GCP | Terraform on Azure / **Bicep** | Bicep 是 ARM JSON 的人类可读层，微软原生 |

---

## 标准管理组层级

```
Tenant Root Group                        ← 永远不要在这里挂 policy
└── ALZ  (intermediate root)             ← 所有 policy 挂在这里
    ├── Platform                         ← 平台团队自己的订阅
    │   ├── Identity                     ← 域控 / Entra Connect / 域加入
    │   ├── Management                   ← Log Analytics / 备份 / 自动化
    │   ├── Connectivity                 ← hub VNet / ExpressRoute / Firewall / 私有 DNS
    │   └── Security                     ← Sentinel / SOC 管理的安全服务
    ├── Landing Zones                    ← 交付给业务团队的订阅
    │   ├── Corp                         ← 需要私网回连本地的负载
    │   └── Online                       ← 纯互联网面向的负载
    ├── Sandbox                          ← 故意放松策略，代价是没有企业网连接
    └── Decommissioned                   ← 待下线订阅的停车场
```

**五个关键设计决策：**

1. **为什么要有 intermediate root（`ALZ` 这一层）？**
   Tenant Root Group 删不掉、改不动，而且租户里**所有**订阅都在它下面，包括你不拥有的。在它上面挂 Deny 策略，出事没有回滚路径。中间根给你一个可以整体删除、可以并行搭建新版本的作用域。

2. **为什么 Corp 和 Online 要分开？**
   因为策略不同。Corp 负载有回本地的私网通路，所以**禁止公网 IP**——否则就绕过了企业边界，形成一条"意外的桥"。Online 负载本来就该有公网 IP。这个策略差异就是拆分的全部理由。`terraform/10-governance/main.tf` 里那条自定义策略只挂在 Corp 上，就是这个原因。

3. **为什么 Sandbox 挂在 Landing Zones 外面？**
   工程师需要一个能乱试的地方，否则他们会去申请例外，最后策略形同虚设。Sandbox 用**放松策略 + 零企业网连接**做交换。这是一个务实的权衡，不是疏漏。

4. **为什么 Platform 要拆成三个订阅？**
   订阅是配额和计费边界。连接性资源（ExpressRoute circuit、Firewall）的成本要能单独摊销给整个组织；身份资源的变更节奏和爆炸半径与网络完全不同；管理订阅要在其他一切都挂掉时还能查日志。分开也让 RBAC 更干净——网络工程师不需要碰域控。

5. **为什么增加 Security 订阅？**
   安全运营与平台运维经常需要不同的访问边界。独立订阅让 SOC 管理 Sentinel 及相关服务，而不需要获得 Management 或 Connectivity 的广泛写权限。

---

## Platform 三个订阅到底装什么 + 资源归属判断法则

### Identity 订阅 ≠ Entra ID

**Entra ID 不住在任何订阅里。** 它是租户级服务，和订阅是两个平面——这就是"身份平面 ≠ 资源平面"的具体体现。你不会在某个订阅里"找到" Entra ID。

Identity 订阅装的是**支撑身份的 IaaS 基础设施**：

- **AD DS 域控 VM**——如果还有需要域加入的 Windows 负载（企业里非常普遍）
- **Entra Connect / Cloud Sync 服务器**——把本地 AD 同步到 Entra 的那台机器
- **Entra Domain Services**（托管域，如果用）
- **AD FS / AD CS**（遗留联合身份、内部 PKI）
- 这些东西专用的 DNS

**关键推论：纯 cloud-native、没有本地 AD、没有域加入需求的企业，这个订阅可以完全不存在。** 很多 CAF 图把它画成必需项，但它应根据实际身份需求决定。

### Management 订阅

- **中央 Log Analytics workspace**（所有订阅的日志汇聚点）
- Azure Monitor 配套：Data Collection Rules、Managed Prometheus / Managed Grafana
- **Automation Account**——Update Management、Change Tracking、Runbook
- **Recovery Services vault / Backup vault**——中央备份策略
- Azure Site Recovery
- 长期日志归档的存储账户（冷/归档层）

**它独立存在的理由是一句运维常识：日志和备份必须在它监控的东西挂掉时还能访问。**

> **Sentinel 的 workspace 放 Management 还是单独的 Security 订阅？** 如果合规要求安全日志与运维日志使用不同 RBAC 边界，就应拆分。Security 订阅是很多企业在参考层级上增加的可选边界。

### Connectivity 订阅

- hub VNet、**Azure Firewall**、ExpressRoute circuit + gateway、VPN gateway、Virtual WAN
- **所有 `privatelink.*` 私有 DNS 区域** + DNS Private Resolver
- 全局入口：Front Door、Traffic Manager
- 集中式 Application Gateway
- 公网 IP prefix、DDoS Protection plan

### VM / AKS 放哪？**都不放 Platform，放 Application Landing Zone**

从名字上找不到位置，是因为**在按"技术类型"分类，而 ALZ 是按"所有权"分类的**。

分界线不是 IaaS vs PaaS，也不是底层 vs 上层：

| | Platform 订阅 | Application Landing Zone |
|---|---|---|
| **谁拥有** | 平台团队 | 业务/应用团队 |
| **服务谁** | 整个组织 | 一个（或一组）工作负载 |
| **成本怎么摊** | 集中摊销给全公司 | 记在那个产品头上 |
| **变更节奏跟随** | 平台基线 | 应用发布周期 |

跑业务应用的 AKS、VM、数据库、App Service——**全部在 Corp 或 Online landing zone 里**。Platform 订阅里几乎没有"业务"，只有"给业务用的共享基础设施"。

### 资源归属判断法则

不知道一个资源往哪放，问三个问题：

1. **它挂了谁受影响？** 一个团队 → landing zone；全公司 → platform
2. **成本该记在谁头上？** 一个产品 → landing zone；共享摊销 → platform
3. **它跟着谁的节奏变更？** 应用发布 → landing zone；平台基线 → platform

三个答案通常一致。不一致时**第 1 条优先**——爆炸半径决定归属。

### 边界情况

- **域控 VM** → Identity。是 VM，但服务全组织身份，三条法则都满足。
- **共享自托管 CI agent 池 / 中央 Container Registry** → CAF 官方没给位置。实践中塞 Management，或加一个 **"Platform – Tooling/DevOps" 订阅**。这是官方图之外最常见的第四个平台订阅。
- **内部开发者平台性质的共享 AKS**（多团队租用）→ 按三条法则像 platform，但 CAF 更倾向当成一个 landing zone，只是拥有者恰好是平台团队。两种划分都可以成立，关键是记录所有权和故障域的权衡。

### Security 订阅

- 按需启用 Microsoft Sentinel workspace 和 Data Connector
- SOC 管理的自动化、Playbook 与调查服务
- 需要独立访问和成本边界的安全工具

在需要这些能力前，该订阅可以保持为空。建立治理边界不等于必须立即启用收费的安全服务。

### GCP 对照

- Platform 订阅 ≈ 你的**宿主/共享项目**（Shared VPC host project、中央日志项目、CI/CD 工具项目）
- Application landing zone ≈ 业务 **project**

DCN 迁移时你决定"哪些资源进共享项目、哪些进业务项目"，用的就是同一套逻辑：归属和故障半径比资源类型更重要。

---

## CAF 八大设计域

| # | 设计域 | 核心问题 | 本 lab 里的体现 |
|---|---|---|---|
| 1 | **Azure billing & Entra tenant** | 一个租户还是多个？EA/MCA 计费层级怎么切？ | 一个租户、一个 MCA Invoice Section、9 个角色订阅；见 [04-subscription-vending_cn.md](04-subscription-vending_cn.md) |
| 2 | **Identity & access management** | 谁能做什么？特权怎么管？ | Entra RBAC、role assignment、PIM（讨论） |
| 3 | **Resource organization** | 管理组/订阅/RG 怎么分层，怎么命名，怎么打标签 | `10-governance` 全部 |
| 4 | **Network topology & connectivity** | Hub-spoke 还是 Virtual WAN？出口怎么控？混合怎么连？ | `20-platform` 全部，见 [02-networking_cn.md](02-networking_cn.md) |
| 5 | **Security** | 加密、密钥、威胁检测、边界 | Firewall、NSG、Private Endpoint、Defender for Cloud |
| 6 | **Management** | 监控、备份、补丁、告警 | Log Analytics + diagnostic settings |
| 7 | **Governance** | 用什么机制保证前面几条不会被绕过 | Azure Policy + Initiative + 合规仪表盘 |
| 8 | **Platform automation & DevOps** | 这一切怎么用代码交付和演进 | Terraform + Azure DevOps，见 [03-azure-devops_cn.md](03-azure-devops_cn.md) |

**理解顺序**：计费与租户 → 身份 → 资源组织 → 网络 → 安全 → 运维 → 治理 → 自动化。

---

## Azure Policy：比 GCP Org Policy 强在哪

这是最值得你花时间的一块，因为它没有干净的 GCP 对应物。

**五种 effect：**

| Effect | 行为 | 典型用途 |
|---|---|---|
| `Audit` | 记录不合规，不阻止 | 新策略上线的第一阶段，永远从这里开始 |
| `Deny` | 直接拒绝部署 | allowed locations、禁止公网 IP |
| `Append` | 部署时追加属性 | 强制加标签 |
| `Modify` | 修改现有资源的属性（配合 remediation task） | 批量补标签、开加密 |
| `DeployIfNotExists` (DINE) | **缺什么就替你部署什么** | 自动给每个新资源挂诊断设置、自动装监控 agent |

**DINE 是 ALZ 的重要机制**，也是常见故障源。需要注意三点：

1. DINE 和 Modify 的 assignment **必须有 managed identity**（Terraform 里就是 `identity {}` + `location`）。
2. 那个 identity **必须在 assignment 作用域上有 RBAC 角色**，否则修复会静默失败，报 "insufficient permissions"。
3. DINE **只对新建或重新评估的资源生效**。存量不合规资源需要手动发起 **remediation task**。

**Initiative（策略集）**：把几十条相关策略打包成一个可分配单元。ALZ 官方提供的 initiative 有上百条策略。企业里你不会一条条分配。

**策略豁免（exemption）**：真实世界里一定会有例外。Azure Policy 支持带**到期时间**的 exemption；设置到期时间可以避免"临时例外"永久化。

---

## 落地路径：企业里 ALZ 通常怎么建

### "Accelerator" 是一个被过度重载的词 —— 至少指四种不同的东西

这是最容易误解的一点。听到 "ALZ accelerator" 必须先问是哪一个：

| 名称 | 是什么 | 符合 GitOps 吗 |
|---|---|---|
| **Portal accelerator**（门户里的 "Azure landing zone" 部署向导） | 纯 UI 点击，后台跑 ARM 模板 | ❌ **完全不符合**。产物不在你的 Git 里，无法评审、无法回滚、无法追溯。**只适合 demo 和 POC，企业不要用** |
| **ALZ Bicep**（`Azure/ALZ-Bicep` 仓库） | 一组 Bicep 模块，你在自己的 repo 里引用 | ✅ 代码，你的流水线部署 |
| **ALZ Terraform / AVM 的 ALZ 模块** | 一组 Terraform 模块，同上 | ✅ 代码 |
| **ALZ Accelerator（bootstrap，`ALZ` PowerShell 模块）** | **一次性脚手架**。本地跑一次，它替你创建 Git 仓库、配好 OIDC 身份、种下 IaC 代码、建好 CI/CD 流水线 | ✅ 它本身不是运行时，**跑完之后一切都在 Git 里**，和 `create-react-app` 是同一类东西 |

Portal accelerator 偏向交互式评估；Bicep/Terraform accelerator 是模块库，bootstrap accelerator 是脚手架，后两者适合代码化交付流程。

完成手工治理、网络和交付实验后，继续阅读 [05-alz-accelerator_cn.md](05-alz-accelerator_cn.md)，生成并审查官方 Terraform 路线。

### 但要说清楚：Azure 的 ALZ 不是 Argo CD 那种 GitOps

Kubernetes 中的 Argo CD 是常驻控制器，会持续读取 Git 并把集群拉回期望状态。Azure 平台层没有完全相同的默认机制：

| | Kubernetes + Argo CD | Azure ALZ |
|---|---|---|
| 模式 | **拉取式**，控制器主动 reconcile | **推送式**，流水线跑 `terraform apply` |
| 漂移检测 | 控制器持续对比，自动 self-heal | 靠**定时 `terraform plan`**（多数企业跑夜间 plan，有 diff 就告警） |
| 谁能改 | 改集群会被立刻拉回去 | 有人在 Portal 手改，要等下次 plan 才发现 |

**唯一真正持续 reconcile 的机制是 Azure Policy。** `deployIfNotExists` 和 `modify` 效果就是平台层的 reconciliation loop：它持续评估，发现缺失就补上。

这给你一个很漂亮的架构叙述：

> "Terraform defines desired state and the pipeline pushes it, but the continuous reconciliation loop in Azure is Azure Policy — DINE and modify effects are what actually pull configuration back to the baseline without a human. So the pattern is: Terraform for what exists, Policy for how it must be configured. On GKE I get both from Argo CD; on Azure they're two different mechanisms, and knowing which belongs where is most of the design."

如需拉取式持续协调，可以使用 **Azure Service Operator** 或 **Crossplane** 从 Kubernetes 声明 Azure 资源。这样会把 Azure 治理依赖于 Kubernetes 控制平面，应作为明确的架构取舍。

---

## 落地路径（续）

1. **策略先 Audit 再 Deny**。先跑两周，看合规仪表盘，把误伤修掉，再切 Deny。
2. **subscription vending**：landing zone 的交付要产品化——业务团队提一个 PR 或填一个表单，流水线自动创建订阅、挂到正确的管理组、建 VNet、peering 到 hub、配好 RBAC 和预算告警。这是"平台即产品"在 Azure 上的具体形态。

---

## "ALZ 不是一次性项目" 指的是什么

**两个方向同时在推，这是一个持续的产品运营工作，不是一个有交付日期的项目。**

### 方向一：微软在变（外部推力）

- **模块有版本发布**，AVM / ALZ-Bicep 定期发新版，**有 breaking change**。你 pin 在 v0.x 上不升级，两年后就升不动了。
- **官方策略基线在更新**——新增内置策略定义、旧的被弃用、initiative 内容变化。
- **Azure 平台本身在长新东西**：每出一个新 PaaS 服务，就多一个 `privatelink.*` DNS 区域要加、多一批需要被策略覆盖的资源类型。**你的"必须用 private endpoint"策略覆盖不到上个月 GA 的那个新服务——这就是治理空洞，而且是自动产生的。**

### 方向二：企业在变（内部推力）

- 新业务单元、新区域、收购来的公司要并进来
- 新合规要求：APRA CPS 234、IRAP、PCI-DSS、行业审计发现
- 新的 landing zone 原型（data landing zone、AI/ML landing zone、给第三方的隔离区）
- **策略基线要持续收紧**：上线时一大半策略是 Audit，随着治理成熟逐条转 Deny。这本身就是长期工作。
- **豁免到期管理**：每个 exemption 都有到期日，到期要么修好要么重新论证。没人管的话"临时豁免"会永久化，治理就名存实亡。

### 所以正确的组织方式

ALZ 要像产品一样运营：**有 owner、有 backlog、有版本号、有 release notes、有面向内部客户的文档**。不是一个搭完就解散的项目组。

---

## 常见误解

| 误解 | 实情 |
|---|---|
| "ALZ 就是 hub-spoke 网络" | 网络只是八分之一。ALZ 的核心是**被治理的订阅** |
| "landing zone 是一次性搭好的" | 它是持续演进的产品，有版本、有 backlog、有 breaking change |
| "策略在管理组上设了就一定生效" | Deny 不能追溯已存在的资源；DINE 需要 identity + RBAC + remediation task |
| "Entra Global Admin 就能管所有 Azure 资源" | 身份平面 ≠ 资源平面。需要在 Entra 里做 **elevate access** 才能拿到租户根的 User Access Administrator |
| "管理组越多越好" | 每一层都增加策略排障难度。CAF 的建议是**尽量扁平**，不要按部门镜像组织架构 |

---

## 动手清单（对照 `terraform/10-governance/`）

- [ ] `terraform apply`，在 Portal 的 Management groups 页面看到层级
- [ ] 设置 `move_subscriptions_into_hierarchy = true`，并确认所有角色订阅归位正确
- [ ] 去 Policy → Compliance 看合规状态（第一次评估要等 10-30 分钟）
- [ ] 把 `public_ip_policy_effect` 从 `Audit` 改成 `Deny`，然后**故意**去建一个带公网 IP 的 VM，看着它被拒绝，并读懂错误信息里的 policy assignment id
- [ ] 给自己写一条策略豁免（Portal 上操作即可），观察合规状态变化
- [ ] 打开 `log_analytics_workspace_id`，观察 DINE 策略的 identity 和 role assignment 被创建；再去 Remediation 页面手动发起一次修复任务

完成这六步后，你将覆盖 ALZ 治理层的核心机制。

---

下一篇：[02-networking_cn.md](02-networking_cn.md) — 企业级 Azure 网络
