# Azure DevOps 实操目录

[English](README.md)

这是一个半天内可以完成的 Azure Pipelines 实操实验，用来理解模板、身份认证、审批和排障流程。
概念对照和三套表达式语法在 [`../docs/03-azure-devops_cn.md`](../docs/03-azure-devops_cn.md)。

## 文件

| 文件 | 作用 | GitHub Actions 对应 |
|---|---|---|
| `azure-pipelines.yml` | 消费方 pipeline，用 `extends` | 调用 reusable workflow 的 caller |
| `templates/stages/terraform-plan-apply.yml` | 平台团队拥有的 stage 模板 | reusable workflow（但强得多） |
| `templates/steps/terraform-setup.yml` | step 级模板 | composite action |

## 30 分钟跑通

```bash
# 1. 建组织和项目
open https://dev.azure.com          # 用 Microsoft 账号，免费

# 2. Project settings → Service connections → New
#    Azure Resource Manager → Workload Identity federation (automatic)
#    命名为 sc-azure-alzlab，指向你的订阅
#    ↑ 这一步使用无密钥的工作负载身份联合

# 3. Pipelines → Library → + Variable group
#    命名 platform-common，加一个 TF_VERSION = 1.9.8
#    再建一个勾选 "Link secrets from an Azure key vault" 的组，对比感受

# 4. Pipelines → Environments → New environment
#    命名 alz-lab → Approvals and checks → Approvals → 把自己加为审批人

# 5. 把本仓库推到 Azure Repos，Pipelines → New pipeline → 选 azure-pipelines.yml
```

**注意**：`azure-pipelines.yml` 里的 `resources.repositories` 指向一个独立的
`Platform/pipeline-templates` 仓库。单仓库练习时，把 `resources` 块删掉、
`extends.template` 改成本地相对路径即可：

```yaml
extends:
  template: templates/stages/terraform-plan-apply.yml
  parameters:
    ...
```

但**要理解为什么生产环境要分仓库并打 tag**：模板改一次会同时影响所有消费方，
必须用版本号控制爆炸半径。这一点你在 PCCW 做 100+ repo 的共享 workflow 时已经
这是大型共享流水线仓库中常见的版本和爆炸半径控制问题。

## 你要观察的三件事

1. **Validate → Plan → Apply 三个 stage 的依赖关系**，以及 Apply 停在审批门前的样子。
   Actions 里 job 之间是 `needs:`，ADO 多了 stage 这一层抽象。
2. **plan 产物被 publish 成 artifact，apply 阶段 download 后执行的是同一个 plan 文件**——
   不是重新 plan。这是审批有意义的前提：你批准的和执行的是同一件事。
3. **`addSpnToEnvironment: true`** 把联邦凭据暴露成 `$servicePrincipalId` / `$idToken`，
   Terraform 用 `ARM_USE_OIDC` 消费。全流程没有任何 secret 落地。

## 三个必会的排障点

| 症状 | 原因 |
|---|---|
| `${{ }}` 里引用的变量是空的 | 编译期展开，看不到运行时才产生的值。改用 `$[ ]` 或 `$( )` |
| deployment job 跑了但没停在审批 | approval 挂在 **environment** 上，不是 pipeline 上。检查环境名拼写 |
| 模板引用报 "repository not found" | `resources.repositories` 的 `name` 要写成 `项目名/仓库名`，且需要授权该 pipeline 访问 |
