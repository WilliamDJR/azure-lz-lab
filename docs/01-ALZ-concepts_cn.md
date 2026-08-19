# 01 · Azure Landing Zone 核心概念

[English](01-ALZ-concepts.md)

本章说明 Azure Landing Zone（ALZ）模型，映射相关 GCP 概念，并把设计决策对应到 `terraform/10-governance/`。

---

## 定义

**Azure Landing Zone 是在工作负载部署前建立的、租户规模且由代码定义的基础环境。** 它预先准备资源组织、身份、网络拓扑、Policy 护栏、监控和计费结构，使应用团队获得的是受治理的订阅，而不是空白订阅。

ALZ 属于 Microsoft Cloud Adoption Framework（CAF）的 **Ready** 阶段。

Landing Zone 不只是网络。更准确的理解是一个**预先治理的订阅**；网络只是使订阅能够安全承载工作负载的多个设计领域之一。

## GCP 与 Azure 概念映射

| GCP 概念 | Azure 对应项 | 重要差异 |
|---|---|---|
| Organization | Microsoft Entra 租户中的 Tenant Root Group | 租户首先是身份边界 |
| Folder | **Management Group** | 支持嵌套层级，并向下继承 Policy 与 RBAC |
| Project | **Subscription** | 同时是计费、配额和资源边界 |
| 无直接对应项 | **Resource Group** | 相关资源的部署、生命周期和 RBAC 作用域 |
| Organization Policy | **Azure Policy** 与 Initiative | 可以 Audit、Deny、Modify 或部署缺失配置 |
| IAM policy binding | **Azure RBAC** Role Assignment | 作用域可以是管理组、订阅、资源组或资源 |
| 无直接对应项 | **Microsoft Entra ID** | Entra 目录角色与 Azure 资源角色属于不同授权平面 |
| Shared VPC | 无直接对应项；通常使用 Hub-Spoke 和 VNet Peering | 这是 Azure 采用 Hub-Spoke 的重要原因之一 |
| VPC Peering | VNet Peering | 不具备传递性 |
| Cloud Interconnect | **ExpressRoute** | 通过服务提供商私下接入 Microsoft 骨干网 |
| Cloud VPN | VPN Gateway | |
| Private Service Connect | **Private Endpoint / Private Link** | Azure 方案高度依赖 Private DNS 覆写 |
| Cloud Logging and Monitoring | **Azure Monitor**、Log Analytics 与 KQL | KQL 是主要查询语言 |
| Cloud Asset Inventory | Azure Resource Graph | 同样使用 KQL 查询 |
| GCP 上的 Terraform | Azure 上的 Terraform 或 **Bicep** | Bicep 是 ARM 上的 Azure 原生声明式语言 |

## 参考管理组层级

```text
Tenant Root Group                         <- 避免在此分配宽泛 Policy
└── ALZ（中间根）                         <- 可控的 ALZ Policy 作用域
    ├── Platform                          <- 共享平台订阅
    │   ├── Identity                      <- AD DS / 同步 / 域服务
    │   ├── Management                    <- 监控 / 备份 / 自动化
    │   ├── Connectivity                  <- Hub / Gateway / Firewall / DNS
    │   └── Security                      <- Sentinel / SOC 所有的服务
    ├── Landing Zones                     <- 应用订阅
    │   ├── Corp                          <- 需要企业私网连接的工作负载
    │   └── Online                        <- 面向互联网的工作负载
    ├── Sandbox                           <- 放宽 Policy，不连接企业网络
    └── Decommissioned                    <- 正在退役的订阅
```

### 层级背后的五项设计决策

1. **中间根：** Tenant Root Group 对整个租户生效且不能删除。在该层分配 Deny 可能影响平台团队不负责的订阅，并且难以回滚。中间根提供可管理生命周期的 ALZ 边界，也允许并行建立不同版本的层级。
2. **分离 Corp 与 Online：** 两类工作负载需要不同护栏。Corp 通常具有企业私网连接并禁止直接公网 IP；Online 原本就需要互联网入口。拆分依据是 Policy 要求，而不是组织架构图。
3. **Sandbox 位于 Landing Zones 之外：** 工程师需要受控实验空间。该分支以放宽 Policy 换取不连接企业网络。
4. **拆分 Platform 订阅：** 订阅是配额、计费和访问边界。Connectivity 成本可以集中分摊；Identity 与网络变更具有不同故障半径；工作负载订阅不可用时，监控能力仍应可访问。
5. **独立 Security 边界：** 安全运营通常需要不同于平台运维的访问边界。独立订阅使 SOC 可以管理 Sentinel 和相关控制，而不必获得 Management 或 Connectivity 的广泛写权限。

## Platform 订阅资源归位

### Identity 订阅不等于 Microsoft Entra ID

**Entra ID 不属于任何订阅。** 它是身份平面的租户级服务。Identity 订阅按需承载支撑设施：

- AD DS 域控制器 VM
- Entra Connect 或 Cloud Sync 服务器
- Microsoft Entra Domain Services
- 用于遗留联合身份和 PKI 的 AD FS 或 AD CS
- 配套 DNS 服务

纯云原生且没有 AD DS 或域加入需求的组织可能不需要该订阅。

### Management 订阅

- 中央 Log Analytics Workspace
- Data Collection Rule、Managed Prometheus、Managed Grafana 等 Azure Monitor 组件
- Automation Account、Runbook、更新与变更跟踪
- Recovery Services Vault、Backup Vault 与 Azure Site Recovery
- 长期日志归档 Storage

被监控资源不可用时，监控和恢复服务仍应可访问。部分组织把 Microsoft Sentinel 放在独立 Security 订阅，以分离 SOC 与平台运维的访问边界。

### Connectivity 订阅

- Hub VNet、Azure Firewall、ExpressRoute Circuit/Gateway、VPN Gateway 或 Virtual WAN
- 中央 `privatelink.*` Private DNS Zone 与 DNS Private Resolver
- Front Door、Traffic Manager 或 Application Gateway 等共享入口
- Public IP Prefix 与 DDoS Protection Plan

### Security 订阅

- 按需启用的 Microsoft Sentinel Workspace 与 Data Connector
- SOC 所有的自动化、Playbook 和调查服务
- 需要独立访问与成本边界的安全工具

在需要这些能力之前，订阅可以保持为空。建立治理边界不等于必须启用收费的安全服务。

### 工作负载 VM 和 AKS 属于应用 Landing Zone

ALZ 按**所有权和故障半径**组织资源，而不是按资源类型组织。

| 判断项 | Platform 订阅 | Application Landing Zone |
|---|---|---|
| 所有者 | 平台团队 | 应用或产品团队 |
| 服务对象 | 整个组织 | 一个工作负载或产品组 |
| 成本归属 | 共享平台成本 | 产品成本中心 |
| 变更节奏 | 平台基线 | 应用发布周期 |

因此，业务 VM、AKS Cluster、Database 和 App Service 应位于 Corp 或 Online 订阅。Platform 订阅主要包含工作负载共同使用的共享服务。

### 资源归位标准

应评估三个标准：

1. 资源故障影响一个团队，还是整个组织？
2. 成本应归属于一个产品，还是共享平台预算？
3. 资源随应用发布周期变更，还是随平台基线变更？

这些结果通常一致；不一致时优先考虑故障半径。

示例：

- 域控制器 VM 服务整个组织，因此位于 Identity。
- 共享 CI Agent 或中央 Container Registry 可能需要独立的 Platform Tooling/DevOps 订阅。
- 多团队使用的内部开发者平台 AKS Cluster 是真实的边界案例。它可以作为平台服务，也可以作为平台团队所有的 Landing Zone；应记录所有权和故障域取舍。

## CAF 八个设计领域

| # | 设计领域 | 核心问题 | 本实验覆盖 |
|---|---|---|---|
| 1 | **Azure 计费与 Entra 租户** | 租户和计费层级 | 多订阅路线：一个租户、一个 MCA Invoice Section 和九个角色订阅；单订阅路线：一个现有订阅和逻辑角色。参见 [04-subscription-vending_cn.md](04-subscription-vending_cn.md) 与 [05-single-subscription_cn.md](05-single-subscription_cn.md) |
| 2 | **身份与访问管理** | 谁能执行哪些操作，特权如何受控？ | Role Assignment 与 Managed Identity；PIM 作为概念扩展 |
| 3 | **资源组织** | Management Group、Subscription、Resource Group、名称和标签如何分层？ | `10-governance` |
| 4 | **网络拓扑与连接** | Hub-Spoke 或 Virtual WAN、出口和混合连接 | `20-platform`；参见 [02-networking_cn.md](02-networking_cn.md) |
| 5 | **安全** | 加密、密钥、威胁检测和网络边界 | Firewall、NSG、Private Endpoint；不部署 Defender |
| 6 | **管理** | 监控、备份、补丁和告警 | Log Analytics 与 Diagnostic Setting |
| 7 | **治理** | 如何强制执行前述设计决策？ | Azure Policy 与合规状态 |
| 8 | **平台自动化与 DevOps** | 平台如何以代码交付和演进？ | Terraform 与 Azure Pipelines；参见 [03-azure-devops_cn.md](03-azure-devops_cn.md) |

一种实用顺序是：计费 → 身份 → 资源组织 → 网络 → 安全 → 运维 → 强制执行 → 自动化。

## Azure Policy

Azure Policy 提供的 Effect 不限于传统 Audit 或 Deny：

| Effect | 行为 | 常见用途 |
|---|---|---|
| `Audit` | 记录不合规但不阻止 | 新 Policy 上线的第一阶段 |
| `Deny` | 拒绝部署 | Allowed Locations 或禁止公网 IP |
| `Append` | 部署期间追加字段 | 必需标签或属性 |
| `Modify` | 修改受支持的属性，通常配合 Remediation | 增加标签或启用设置 |
| `DeployIfNotExists`（DINE） | 部署缺失配置 | Diagnostic Setting 或监控 Agent |

DINE 实施需要满足三项条件：

1. DINE 或 Modify Assignment 需要 Managed Identity。
2. 该身份必须在 Assignment Scope 具有正确 RBAC Role，否则 Remediation 会因权限不足而失败。
3. 现有不合规资源通常需要显式创建 **Remediation Task**；仅创建 Assignment 不会追溯修复全部资源。

**Initiative** 把相关 Policy Definition 组合成一个可分配单元。**Policy Exemption** 记录已批准的例外并可设置到期时间；限时豁免可防止临时决策成为永久治理缺口。

### 安全发布模式

先使用 Audit，检查合规状态和误报，修复现有资源，再逐步提升为 Deny。应尽量先在较低环境验证，并为真实例外使用有记录且会到期的 Exemption。

## ALZ 实施方式

*Accelerator* 一词可能指不同实现：

| 选项 | 内容 | 是否为代码优先流程？ |
|---|---|---|
| Portal Accelerator | 通过 Portal 向导部署 ARM 资源 | 默认没有受源代码管理的期望状态；适合演示和评估 |
| ALZ-Bicep | 在组织仓库中引用的 Bicep Module | 是 |
| ALZ Terraform / AVM Module | 在组织仓库中引用的 Terraform Module | 是 |
| ALZ Bootstrap Accelerator | 一次性创建 Repository、Federated Identity、IaC 和 Pipeline 的脚手架 | 是；用于建立代码优先的运营模型 |

Portal 体验、可复用 IaC Module 和 Bootstrap 工具解决不同问题，实施前应明确所指的 Accelerator。

完成手工治理、网络和交付实验后，按照 [06-alz-accelerator_cn.md](06-alz-accelerator_cn.md)生成并审查官方 Terraform 路线。

### Azure ALZ 与 Argo CD GitOps 的差异

| | Kubernetes 与 Argo CD | 使用 Terraform 的 Azure ALZ |
|---|---|---|
| 模式 | 拉取式持续协调 | Pipeline 推送 `terraform apply` |
| 漂移检测 | 持续检测，可选自动恢复 | 通常使用定时 `terraform plan` 和告警 |
| Portal/手工变更 | Controller 负责协调 | 除非 Policy 介入，否则在后续 Plan 才会发现 |

Azure Policy 是 Azure 控制平面上最接近持续协调循环的机制。DINE 和 Modify 会持续评估资源，并可恢复必需配置。一种实用职责划分是：**Terraform 定义存在哪些资源；Policy 定义资源必须满足的配置并持续评估。**

Azure Service Operator 或 Crossplane 等 Controller 可以提供拉取式 Azure 资源协调，但会引入 Kubernetes 控制平面依赖，应作为明确的架构选择。

## 把 Landing Zone 作为产品运营

ALZ 不是一次性项目，外部和内部需求都会持续变化：

- ALZ-Bicep 与 Azure Verified Modules 会发布新版本，其中可能包含破坏性变更。
- Built-in Policy Definition 与 Initiative 会演进、弃用或替换。
- 新 Azure 服务会引入旧基线尚未覆盖的资源类型和 Private DNS Zone。
- 组织会增加业务单元、区域、收购实体和合规义务。
- Policy Effect 会从 Audit 成熟到 Deny，Exemption 也需要在到期时复核。

Landing Zone 应具有 Owner、Backlog、版本、Release Note、测试和内部文档，并按产品持续运营。

**Subscription Vending** 是关键产品能力：Request 或 Pull Request 应以一致方式创建订阅、放入正确管理组、配置网络与 Peering、分配 RBAC，并应用预算和 Policy 控制。

## 常见误解

| 误解 | 实际情况 |
|---|---|
| ALZ 就是 Hub-Spoke 网络 | 网络只是一个设计领域；Landing Zone 是受治理的订阅基础 |
| Landing Zone 搭建一次即可 | 它是带版本并持续演进的平台产品 |
| Policy Assignment 会自动修复全部资源 | Deny 不追溯现有资源；DINE 需要 Identity、RBAC、Evaluation 和 Remediation |
| Entra Global Administrator 自动拥有全部 Azure 资源权限 | 目录授权与资源授权相互独立；可能需要在租户根提升访问权限 |
| Management Group 层级越多越好 | 每一层都会增加继承和排障复杂度，应在满足要求的前提下保持扁平 |

## 动手检查清单

- [ ] 使用所选路线对应的 Manifest Apply `terraform/10-governance/`，在 `move_subscriptions_into_hierarchy = false` 时检查层级。
- [ ] 多订阅路线：启用移动并验证九个角色订阅；单订阅路线：按需启用移动，并验证唯一订阅只有所选的一个父管理组。
- [ ] 等待第一次评估完成后检查 Policy Compliance。
- [ ] 盘点现有工作负载并把测试订阅置于 Corp 后，将 `public_ip_policy_effect` 从 `Audit` 改为 `Deny`；尝试部署一次性公网 IP VM，并从错误中识别 Assignment ID。
- [ ] 创建限时 Policy Exemption，并观察其合规状态。
- [ ] 设置 `log_analytics_workspace_id`，检查 DINE Assignment Identity 与 Role Assignment，并启动 Remediation Task。

---

下一篇：[02-networking_cn.md](02-networking_cn.md) — 企业级 Azure 网络
