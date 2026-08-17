# 03 · Azure DevOps 与平台交付

[English](03-azure-devops.md)

> 你已经会的：可复用工作流的平台化设计。你不会的：Azure Pipelines 的方言。
> 后者两三天就够。这一篇只讲差异，不讲你已经懂的东西。
> 配套可跑代码在 `azure-devops/`。

---

## 1. 概念映射表

| GitHub Actions | Azure DevOps | 差异要点 |
|---|---|---|
| Repository | **Azure Repos**（或直接连 GitHub） | ADO 项目里可以有多个 repo |
| workflow (`.github/workflows/*.yml`) | pipeline（文件名随意，通常 `azure-pipelines.yml`） | 一个 repo 可以注册多条 pipeline，每条指向不同的 YAML |
| `on:` triggers | `trigger:` / `pr:` / `schedules:` | PR 触发由**分支策略**控制，不完全在 YAML 里 |
| job | **stage → job → step** | ADO 多一层 **stage**，这是它比 Actions 强的地方 |
| step / uses | step / **task** | task 是 ADO 的官方动作单元，如 `AzureCLI@2` |
| **reusable workflow** | **template**（`extends:` 或 `- template:`） | **最重要的差异，见下** |
| composite action | step 级 template | |
| runner / self-hosted runner | **agent** / **agent pool** | Microsoft-hosted 免费额度需要申请 |
| `secrets.*` | **variable group**（可关联 Key Vault） | 变量组是项目级共享对象，比 repo secrets 灵活 |
| environments + protection rules | **environments + approvals and checks** | ADO 的检查类型更丰富（业务时间窗、REST 调用、Azure Monitor 告警状态） |
| OIDC to cloud | **service connection**（workload identity federation） | 现代默认就是 WIF，不再用 client secret |
| GitHub Packages | **Azure Artifacts** | |
| `${{ }}` | `${{ }}` / `$[ ]` / `$(var)` | **三套语法，见下** |
| — | **Boards / Test Plans** | Actions 没有的模块 |
| — | **classic release pipeline** | UI 拖拽式的遗留物，很多大企业还有一堆 |

---

## 2. 三个真正需要花时间的地方

### 2.1 三套表达式语法（最容易踩坑）

```yaml
variables:
  buildConfig: Release

steps:
  # ${{ }}  编译期展开。在 pipeline 编译成执行计划时求值。
  #         可以用在结构位置（决定要不要生成某个 step）。
  #         看不到运行时产生的值。
  - ${{ if eq(variables['Build.SourceBranchName'], 'main') }}:
    - script: echo "only compiled into the plan on main"

  # $[ ]    运行期求值。可以引用前一个 job 的输出。
  - script: echo "runtime"
    condition: and(succeeded(), eq(variables['Build.Reason'], 'PullRequest'))

  # $( )    宏替换。在 step 执行前做文本替换，最接近 shell 变量。
  - script: echo "Building $(buildConfig)"
```

**记忆口诀：`${{ }}` 决定"生成什么"，`$[ ]` 决定"要不要跑"，`$( )` 决定"跑的时候值是什么"。**

对应 GitHub Actions，只有一个 `${{ }}`，它同时干了这三件事。这是你最容易写错的地方。

### 2.2 `extends` 模板 —— 比 reusable workflow 强

这是 ADO 有而 GitHub Actions 没有的能力，也是企业流水线治理的重点。

```yaml
# 消费方 pipeline —— 它只能填参数，不能自由发挥
extends:
  template: templates/stages/terraform.yml@platform-templates
  parameters:
    environment: production
    workingDirectory: terraform/20-platform
```

用 `extends` 时，消费方 pipeline 的**整个结构**都由模板定义。平台团队可以在模板里：

- 强制在每次部署前插入安全扫描 step
- 用 `step` 级的 template 限制**允许出现的 task 类型**
- 通过 **template check**（在环境或服务连接上配置）保证「只有经过批准的模板才能使用这个生产服务连接」

**这就是"让应用团队自助，但绕不过护栏"的机制。** GitHub Actions 的 reusable workflow 做不到这一层——被调用方无法约束调用方的其余部分。

### 2.3 变量组、服务连接与环境

三个 ADO 特有对象，都在**项目设置**里，不在 YAML 里：

- **Variable group**（Pipelines → Library）：项目级共享变量。可以直接**关联 Key Vault**，变量值实时从 Key Vault 读，不落盘。
- **Service connection**（Project settings → Service connections）：到 Azure 的凭据。现在默认用 **workload identity federation**：ADO 拿 OIDC token 换 Entra 的短期凭据，**没有 client secret 需要轮转**。
- **Environment**（Pipelines → Environments）：部署目标的抽象。挂 **approvals and checks**——人工审批、业务时间窗、Azure Monitor 告警状态、REST API 调用、以及上面说的 template check。

---

## 3. 上手路径（一个下午）

1. 去 `dev.azure.com` 用你的 Microsoft 账号建一个免费组织和项目（免费额度：5 个用户、无限私有 repo）。
2. 把 `azure-devops/` 目录推进 Azure Repos。
3. 建一个 **service connection**，类型选 Azure Resource Manager → **Workload Identity federation (automatic)**，指向你的非营利订阅。
4. 建一个 **variable group** 叫 `platform-common`，放 `TF_VERSION` 之类的非敏感变量；再建一个关联 Key Vault 的组，感受一下差异。
5. 建一个 **environment** 叫 `production`，加一个"你自己批准"的 approval check。
6. 注册 `azure-devops/azure-pipelines.yml` 为一条 pipeline，跑一次。
7. 观察：plan 阶段自动跑，apply 阶段停在等待审批。

如果 Microsoft-hosted agent 的免费额度没批下来（新组织常见，需要填表申请，通常 2–3 个工作日），在自己机器上跑一个 self-hosted agent 即可——那本身也是一次有价值的练习，因为企业环境里几乎一定用 self-hosted agent（要访问私网资源）。

---

## 4. 从 Jenkins/GitHub Actions 迁移到 ADO 的思路

Jenkins → GitHub Actions 的迁移方法论同样适用于 ADO：

1. **先找共性，别逐条翻译。** 一百个 Jenkinsfile 里通常只有三到五种真实形态。识别形态，为每种形态写一个模板，然后把 repo 映射到模板上。逐个手工移植是最慢的路。
2. **模板库单独放一个 repo，打 tag，语义化版本。** 消费方引用 `@refs/tags/v1.2.0` 而不是 `@main`——否则你改模板会同时炸掉一百个仓库。
3. **并行运行一段时间。** 新旧流水线同时跑，比对产物，确认一致后再切。
4. **迁移工具本身要能自助。** 我们做的是让新 repo 接入 CI/CD 从五个工作日降到一天以内——真正的产出不是流水线，是**接入速度**。
5. **文档和 runbook 是交付物的一部分**，不是可选项。

---

## 5. KQL 示例（Azure Monitor）

从 Cloud Logging 转过来，语法差异不大。下面是几个可直接用于实验的查询：

```kusto
// 防火墙拒绝了什么
AZFWApplicationRule
| where TimeGenerated > ago(1h)
| where Action == "Deny"
| summarize count() by Fqdn, SourceIp
| order by count_ desc

// 谁改了生产订阅里的东西
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationNameValue contains "WRITE"
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup, ActivityStatusValue
| order by TimeGenerated desc

// 策略不合规的资源
// (这个查 Resource Graph，不是 Log Analytics，但语法同样是 KQL)
policyresources
| where type == "microsoft.policyinsights/policystates"
| where properties.complianceState == "NonCompliant"
| summarize count() by tostring(properties.policyDefinitionName)
```

**要点：** `|` 管道、`where` 过滤、`summarize ... by` 聚合、`project` 选列、`ago()` 时间。

---

## 6. ADO 的产品定位

### 事实

微软在 Build 2026 给了明确定性：**"GitHub is the home of agentic development, and Azure DevOps is the stable, well supported workhorse."**

翻译过来：新东西（agentic planning、autonomous code review、Copilot 深度集成、Advanced Security）**全部先落在 GitHub**；Azure DevOps 保持活跃支持但不是创新焦点，承诺的只是 PR 代码质量和安全修复方面的**渐进改善**，Boards / Pipelines / Test Plans 维持现状。

两个强信号说明微软在**主动补贴迁移**：

1. **Azure DevOps 的基础使用权现在包含在 GitHub Enterprise 里**——过渡期不双重收费。
2. **Enterprise Live Migrations (ELM)** 支持从 Azure DevOps 到 GitHub 的低停机仓库迁移。

同时，**ADO 没有 EOL 日期**，按 Modern Lifecycle Policy 持续支持，月度 sprint 更新照常，2026 路线图公开在案。唯一真正被弃用的是旧的 OAuth 应用注册平台（改用 Entra ID）。

因此可以把 ADO 理解为持续支持的稳定企业平台，同时 GitHub 优先承载最新的 agentic 开发能力。

### ADO 今天仍然不可替代的地方

| 能力 | GitHub 的差距 |
|---|---|
| **Azure Boards** | 多层级工作项（Epic → Feature → Story → Task）、跨项目 portfolio 视图、iteration 与 capacity planning、Analytics/OData 直连 Power BI。GitHub Projects 更轻量，未必覆盖同样的层级和容量规划需求 |
| **Azure Test Plans** | GitHub **完全没有等价物**。受监管行业要留手工测试证据的（金融、医疗、政府），这是刚需而不是偏好 |
| **Pipelines 的 extends 模板 + template check** | GitHub 的 reusable workflow 无法约束调用方的整体结构。GitHub 用 rulesets / required workflows 在追，但治理强度还不等同 |
| **Classic release pipeline** | 无对应物，纯存量，只能重写 |
| **Azure Artifacts upstream sources** | GitHub Packages 的 upstream 能力较弱 |

### 如何评估组织的方向

不要仅因为存在新平台就迁移。应先评估：

- 当前团队依赖哪些 Azure DevOps 能力。
- 代码迁移能否带来足以抵消成本和风险的收益。
- Boards、Pipelines、Test Plans、身份、合规和审计集成如何保留。
- GitHub 仓库与 Azure Boards/Pipelines 的混合模式是否能降低迁移风险。
- 模板、制品、权限和分支策略如何在规模化迁移中统一验证。

### 学习重点

建议掌握以下内容：

1. 能够准确描述和排查 Azure Pipelines，而不只是把它映射成 GitHub Actions 的名称。
2. 能够安全地维护和治理现有 Azure DevOps 平台。
3. 能够基于实际依赖、风险和收益评估保留、集成或迁移方案。

## 7. Accelerator 生成的交付体系

`azure-devops/` 中的流水线是精简的教学示例。官方 ALZ IaC Accelerator 可以把 Azure DevOps 仓库、联合身份、Terraform 远程状态和 Platform Landing Zone 交付流水线作为一套系统完成 Bootstrap。

完成本文后继续运行 [05-alz-accelerator_cn.md](05-alz-accelerator_cn.md)。可以比较两套流程的控制点，但不要用教学示例覆盖 Accelerator 生成的仓库；后者应作为平台事实来源，并按官方升级流程持续维护。
