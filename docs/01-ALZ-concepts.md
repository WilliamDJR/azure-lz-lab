# 01 · Azure Landing Zone Concepts

[中文版](01-ALZ-concepts_cn.md)

> Goal: understand the Azure Landing Zone (ALZ) model, relate it to familiar GCP concepts, and connect the design decisions to `terraform/10-governance/`.

---

## Definition

An **Azure Landing Zone is the tenant-scale, code-defined foundation established before workloads are deployed**. Resource organization, identity, network topology, policy guardrails, monitoring, and billing are prepared so an application team receives a governed subscription rather than a blank one.

ALZ belongs to the **Ready** phase of Microsoft's Cloud Adoption Framework (CAF).

The most important distinction is that a landing zone is not merely a network. It is best understood as a **pre-governed subscription**. Networking is one of several design areas that make the subscription ready for workloads.

## GCP-to-Azure concept map

| GCP concept | Azure counterpart | Important difference |
|---|---|---|
| Organization | Tenant Root Group in a Microsoft Entra tenant | The tenant is primarily an identity boundary |
| Folder | **Management Group** | Nested hierarchy with inherited policy and RBAC |
| Project | **Subscription** | A billing and quota boundary as well as a resource boundary |
| No direct equivalent | **Resource Group** | Deployment, lifecycle, and RBAC scope for related resources |
| Organization Policy | **Azure Policy** and initiatives | Azure Policy can audit, deny, modify, or deploy missing configuration |
| IAM policy binding | **Azure RBAC** role assignment | Scope can be management group, subscription, resource group, or resource |
| No direct equivalent | **Microsoft Entra ID** | Entra directory roles and Azure resource roles are separate planes |
| Shared VPC | No direct equivalent; use Hub-Spoke and VNet peering | A key reason for Azure's Hub-Spoke pattern |
| VPC Peering | VNet Peering | Non-transitive |
| Cloud Interconnect | **ExpressRoute** | Private provider connectivity into Microsoft's backbone |
| Cloud VPN | VPN Gateway | |
| Private Service Connect | **Private Endpoint / Private Link** | Azure depends heavily on private DNS overrides |
| Cloud Logging and Monitoring | **Azure Monitor**, Log Analytics, and KQL | KQL is the primary query language |
| Cloud Asset Inventory | Azure Resource Graph | Also queried with KQL |
| Terraform on GCP | Terraform on Azure or **Bicep** | Bicep is Azure's native declarative language over ARM |

## Reference management-group hierarchy

```text
Tenant Root Group                         <- avoid broad policy here
└── ALZ (intermediate root)               <- controlled ALZ policy scope
    ├── Platform                          <- shared platform subscriptions
    │   ├── Identity                      <- AD DS / sync / domain services
    │   ├── Management                    <- monitoring / backup / automation
    │   └── Connectivity                  <- hub / gateways / firewall / DNS
    ├── Landing Zones                     <- application subscriptions
    │   ├── Corp                          <- workloads needing private corporate connectivity
    │   └── Online                        <- internet-facing workloads
    ├── Sandbox                           <- relaxed policy, no corporate connectivity
    └── Decommissioned                    <- subscriptions being retired
```

### Four design decisions behind the hierarchy

1. **Why use an intermediate root?** The Tenant Root Group is universal and cannot be removed. A Deny policy there can affect subscriptions the platform team does not own and is difficult to roll back. An intermediate root creates a lifecycle-managed ALZ boundary and allows parallel versions of the hierarchy.
2. **Why separate Corp and Online?** They require different guardrails. Corp workloads have private connectivity to the enterprise and generally prohibit direct public IPs. Online workloads are designed for internet exposure. Policy requirements, not organizational charts, justify the split.
3. **Why keep Sandbox outside Landing Zones?** Engineers need a safe place for experimentation. The trade is deliberately relaxed policy in exchange for no connectivity to the corporate network.
4. **Why separate Platform into subscriptions?** Subscriptions are quota, billing, and access boundaries. Connectivity costs can be allocated centrally; identity and network changes have different blast radii; and monitoring should remain accessible when a workload subscription fails.

## What belongs in the Platform subscriptions?

### Identity subscription is not Microsoft Entra ID

**Entra ID does not live in a subscription.** It is a tenant-level service on the identity plane. The Identity subscription contains supporting infrastructure when required:

- AD DS domain-controller VMs
- Entra Connect or Cloud Sync servers
- Microsoft Entra Domain Services
- AD FS or AD CS for legacy federation and PKI
- Supporting DNS services

A cloud-native organization with no AD DS or domain-join requirements might not need this subscription at all.

### Management subscription

- Central Log Analytics workspaces
- Azure Monitor components such as Data Collection Rules, Managed Prometheus, and Managed Grafana
- Automation Accounts, runbooks, update, and change tracking
- Recovery Services or Backup vaults and Azure Site Recovery
- Long-term log archive storage

Monitoring and recovery services should remain accessible when the resources they monitor are unavailable. Some organizations place Microsoft Sentinel in a separate Security subscription to enforce a different access boundary between SOC and platform operations.

### Connectivity subscription

- Hub VNets, Azure Firewall, ExpressRoute circuits and gateways, VPN gateways, or Virtual WAN
- Central `privatelink.*` private DNS zones and DNS Private Resolver
- Shared ingress such as Front Door, Traffic Manager, or Application Gateway
- Public IP prefixes and DDoS Protection plans

### Workload VMs and AKS belong in application landing zones

ALZ organizes by **ownership and blast radius**, not by resource type.

| Decision | Platform subscription | Application landing zone |
|---|---|---|
| Owner | Platform team | Application or product team |
| Consumers | Whole organization | One workload or product group |
| Cost allocation | Shared platform cost | Product cost center |
| Change cadence | Platform baseline | Application release cycle |

Business VMs, AKS clusters, databases, and App Services therefore belong in Corp or Online subscriptions. Platform subscriptions primarily contain shared services used by workloads.

### A practical placement test

Ask three questions:

1. Who is affected if the resource fails: one team or the organization?
2. Who should pay for it: one product or a shared platform budget?
3. Which release cadence changes it: an application or the platform baseline?

The answers usually align. If they do not, prioritize blast radius.

Examples:

- Domain-controller VMs belong in Identity because they serve the organization.
- Shared CI agents or a central container registry may justify a dedicated Platform Tooling/DevOps subscription.
- A shared internal-developer-platform AKS cluster is a genuine boundary case. It can be treated as a platform service or as a landing zone owned by the platform team; document the ownership and failure-domain trade-off.

## The eight CAF design areas

| # | Design area | Core question | This lab |
|---|---|---|---|
| 1 | **Azure billing and Entra tenant** | Tenant and billing hierarchy | Single-tenant lab only |
| 2 | **Identity and access management** | Who can do what, and how is privilege controlled? | Role assignments and managed identities; PIM is conceptual |
| 3 | **Resource organization** | How are management groups, subscriptions, resource groups, names, and tags structured? | `10-governance` |
| 4 | **Network topology and connectivity** | Hub-Spoke or Virtual WAN, egress, and hybrid connectivity | `20-platform`; see [02-networking.md](02-networking.md) |
| 5 | **Security** | Encryption, keys, threat detection, and network boundaries | Firewall, NSG, Private Endpoint; Defender is not deployed |
| 6 | **Management** | Monitoring, backup, patching, and alerting | Log Analytics and diagnostic settings |
| 7 | **Governance** | How are the decisions above enforced? | Azure Policy and compliance |
| 8 | **Platform automation and DevOps** | How is the platform delivered and evolved as code? | Terraform and Azure Pipelines; see [03-azure-devops.md](03-azure-devops.md) |

A useful sequence is: billing -> identity -> organization -> network -> security -> operations -> enforcement -> automation.

## Azure Policy

Azure Policy provides effects beyond the traditional audit-or-deny model:

| Effect | Behavior | Typical use |
|---|---|---|
| `Audit` | Records non-compliance without blocking | First phase of a new policy rollout |
| `Deny` | Rejects a deployment | Allowed locations or prohibited public IPs |
| `Append` | Adds fields during deployment | Required tags or properties |
| `Modify` | Changes supported properties, often through remediation | Adding tags or enabling settings |
| `DeployIfNotExists` (DINE) | Deploys missing configuration | Diagnostic settings or monitoring agents |

Three DINE requirements matter in practice:

1. A DINE or Modify assignment needs a managed identity.
2. That identity needs the correct RBAC role at the assignment scope, or remediation fails with insufficient permissions.
3. Existing non-compliant resources normally need an explicit **remediation task**; assignment alone does not retroactively repair everything.

An **initiative** packages related policy definitions into one assignable unit. A **policy exemption** records an approved exception and can include an expiry date. Time-bound exemptions prevent temporary decisions from becoming permanent governance gaps.

### Safe rollout pattern

Begin with Audit, inspect compliance and false positives, remediate existing resources, then move progressively to Deny. Start in lower environments when possible and use documented, expiring exemptions for genuine exceptions.

## ALZ implementation options

The word *accelerator* can refer to different things:

| Option | What it is | Code-first workflow? |
|---|---|---|
| Portal accelerator | A portal wizard that deploys ARM resources | No source-controlled desired state by default; useful for demos and evaluation |
| ALZ-Bicep | Bicep modules consumed from your repository | Yes |
| ALZ Terraform / AVM modules | Terraform modules consumed from your repository | Yes |
| ALZ bootstrap accelerator | One-time scaffolding that creates repositories, federated identities, IaC, and pipelines | Yes; it bootstraps the code-first operating model |

Clarify which accelerator is being discussed. The portal experience, reusable IaC modules, and bootstrap tooling solve different problems.

### Azure ALZ is not identical to Argo CD GitOps

| | Kubernetes with Argo CD | Azure ALZ with Terraform |
|---|---|---|
| Model | Pull-based continuous reconciliation | Pipeline pushes `terraform apply` |
| Drift detection | Continuous and optionally self-healing | Usually scheduled `terraform plan` plus alerts |
| Portal/manual changes | Reconciled by the controller | Detected on a later plan unless policy intervenes |

Azure Policy provides the closest continuous reconciliation loop on the Azure control plane. DINE and Modify continually evaluate resources and can restore required configuration. A practical division of responsibility is: **Terraform defines what exists; Policy defines mandatory configuration and continuously evaluates it.**

Pull-based Azure resource reconciliation is possible with controllers such as Azure Service Operator or Crossplane, but it adds a Kubernetes control-plane dependency and should be an explicit architectural choice.

## Landing zones as a product

An ALZ is not a one-time project. External and internal requirements keep changing:

- ALZ-Bicep and Azure Verified Modules publish new versions, including breaking changes.
- Built-in policy definitions and initiatives evolve and are deprecated or replaced.
- New Azure services introduce resource types and private DNS zones that an older baseline might not cover.
- Organizations add business units, regions, acquisitions, and compliance obligations.
- Policy effects mature from Audit to Deny, and exemptions require review at expiry.

Operate the landing zone as a product with an owner, backlog, versions, release notes, tests, and internal documentation.

**Subscription vending** is a key product capability: a request or pull request should create a subscription, place it under the correct management group, provision networking and peering, assign RBAC, and configure budget and policy controls consistently.

## Common misconceptions

| Misconception | Reality |
|---|---|
| ALZ is a Hub-Spoke network | Networking is one design area; a landing zone is a governed subscription foundation |
| A landing zone is built once | It is a versioned platform product that evolves |
| A policy assignment automatically fixes everything | Deny is not retroactive; DINE needs identity, RBAC, evaluation, and remediation |
| Entra Global Administrator can automatically manage all Azure resources | Directory and resource authorization are separate; elevated access may be required at the tenant root |
| More management-group levels are always better | Every level increases inheritance and troubleshooting complexity; keep the hierarchy as flat as requirements permit |

## Hands-on checklist

- [ ] Apply `terraform/10-governance/` and inspect the hierarchy in the portal.
- [ ] Set `move_subscription_into_hierarchy = true` and verify subscription placement under Corp.
- [ ] Inspect Policy compliance after the initial evaluation completes.
- [ ] Change `public_ip_policy_effect` from `Audit` to `Deny`, attempt a public-IP VM deployment, and identify the assignment ID in the error.
- [ ] Create a time-bound policy exemption and observe its compliance state.
- [ ] Set `log_analytics_workspace_id`, inspect the DINE assignment identity and role assignment, and start a remediation task.

---

Next: [02-networking.md](02-networking.md) — enterprise Azure networking
