# 02 · Enterprise Azure Networking

[中文版](02-networking_cn.md)

This chapter explains the network mechanisms used by `terraform/20-platform/`: Hub-Spoke topology, effective routes, Azure Firewall, VPN/ExpressRoute gateway transit, Private Endpoint and Private DNS. The same packet and DNS behavior can be tested in both repository tracks. In the single-subscription track, provider aliases point to one subscription and resource groups are only logical boundaries; they do not reproduce cross-subscription access or failure isolation.

In the quota-limited track, the four platform aliases point to four new
subscriptions while the workload aliases point to the protected existing
subscription. The hub, private DNS and workload resource groups can therefore
be tested end to end, but the repeated workload roles do not create separate
network or failure domains. Use the quota-limited manifest and backend key;
never mix it with the nine-role or single-subscription state.

## 1. Why Azure uses Hub-Spoke

Azure VNets are independent network objects. VNet peering connects two VNets, but peering is non-transitive:

```text
Spoke A <-> Hub <-> Spoke B

The two peerings do not automatically create Spoke A <-> Spoke B reachability.
```

Common ways to provide broader connectivity are:

| Pattern | Mechanism | Typical use |
|---|---|---|
| Hub NVA plus UDRs | Spoke route tables send selected traffic to Azure Firewall or another NVA in the hub | Central inspection and auditable egress |
| Azure Virtual WAN | Microsoft-managed hubs and routing | Large branch or multi-region estates |
| Direct spoke peering | Peer selected spokes to each other | A small number of latency-sensitive paths |

Direct spoke peering grows rapidly as the number of VNets increases. A central hub or Virtual WAN is normally easier to govern at scale.

## 2. Routing and effective routes

Azure calculates a NIC's effective routes from system routes, user-defined routes (UDRs), and routes learned through a virtual network gateway.

### Route selection

1. Longest-prefix match wins: `/24` is preferred to `/16`, `/16` to `/8`, and all are preferred to `0.0.0.0/0`.
2. For equal prefixes, the usual preference is UDR, then BGP, then system route.

Always inspect the effective route table instead of inferring behavior from one route-table resource.

### Deliberate example in this repository

When Firewall is enabled, `terraform/20-platform/20-spoke.tf` adds `10.0.0.0/8 -> VirtualAppliance`. The hub peering also contributes a more specific `10.0.0.0/16 -> VNetPeering` route. The `/16` wins, so that broad `/8` route does not inspect hub-bound traffic. It applies only where no more-specific route wins.

Run `scripts/show-effective-routes.sh` before and after enabling Firewall and compare the `Address Prefix`, `Next Hop Type`, `Source`, and `State` columns.

### Forced tunnelling

A spoke UDR of `0.0.0.0/0 -> VirtualAppliance(<firewall-private-ip>)` sends general outbound traffic through the hub firewall. Two safety rules matter:

- Do not place a self-referencing default route on `AzureFirewallSubnet`; it can create a routing loop.
- Do not place `0.0.0.0/0` on `GatewaySubnet`. Gateway-subnet route changes require the supported ExpressRoute/VPN design because an invalid route can disrupt the gateway control plane.

Do not design around Azure's implicit default outbound access. For API versions released after 31 March 2026, new VNets default to private subnets and need an explicit outbound method such as a NAT Gateway, Load Balancer outbound rule, public IP, or firewall path. The baseline result can therefore depend on the API behavior used by the installed provider; record what the script observes instead of assuming internet access. [Microsoft default outbound access guidance](https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access)

### Gateway route propagation

`bgp_route_propagation_enabled` controls whether routes learned by a virtual network gateway are added to the associated subnet's route table. Disabling propagation can make traffic fall through to a UDR, but it can also remove the only route to a hybrid prefix. Change it only with an expected-route table and a rollback plan.

## 3. Azure Firewall, NSG, and Application Gateway

These controls operate at different layers:

| | NSG | Azure Firewall | Application Gateway with WAF |
|---|---|---|---|
| Primary layer | L3/L4 | L3-L7; Premium supports additional inspection | L7 HTTP/HTTPS |
| Placement | Subnet or NIC | Central hub | In front of web applications |
| FQDN rules | No | Yes | Host- and HTTP-aware routing/protection |
| Cost | No separate NSG charge | Deployment time plus data processing | Instance/capacity based |
| Typical purpose | Distributed segmentation | Central egress/east-west control | Inbound web delivery and WAF |

Use NSGs for subnet/NIC communication boundaries, Azure Firewall for centralized network and application rules, and Application Gateway/WAF for inbound HTTP controls.

### Firewall Policy inheritance

A common operating model gives the security team a parent Firewall Policy containing mandatory rules and threat-intelligence settings. Regional or delegated child policies can add permitted local rules without replacing the central baseline. The repository deploys one policy; parent/child delegation remains a production extension.

## 4. ExpressRoute and the VPN simulation

ExpressRoute needs a provider circuit, so this repository does not create one. It uses VPN gateways to demonstrate Azure-side gateway transit and effective-route behavior.

```text
Datacenter/colo ---- provider network ---- Microsoft Enterprise Edge ---- Azure backbone
      CE router          carrier/exchange          redundant edge routers
```

- An ExpressRoute circuit is a logical service with bandwidth and a Local, Standard, or Premium SKU.
- Production designs use redundant connections and validate both paths.
- Private peering connects private VNet address spaces.
- Microsoft peering reaches supported Microsoft public services over advertised public prefixes; the former Public peering option is retired.
- Local, Standard, and Premium have different geographic reach, route scale, and connection limits.
- Global Reach connects supported on-premises sites through Microsoft's backbone.
- FastPath can bypass the gateway in the data path for supported configurations.
- A VPN backup path is a common resilience option, but route preference and failover must be tested.

### Behavior from the spoke

Both VPN and ExpressRoute gateways use `GatewaySubnet` and can advertise remote prefixes to a spoke. Hub peering uses `allow_gateway_transit = true`; spoke peering uses `use_remote_gateways = true`. The VPN exercise demonstrates those Azure-side controls, but it does not reproduce an ExpressRoute provider circuit, SLA, Microsoft peering, or FastPath.

The simulated on-premises topology contains a second VNet, two VPN gateways, and two VNet-to-VNet connections. It currently has no VM or other endpoint in the simulated on-premises workload subnet. Therefore its valid evidence is gateway connection state and learned/effective routes, not end-to-end application traffic.

## 5. Private Endpoint and DNS

### Resolution path

```text
1. A client resolves myaccount.blob.core.windows.net.
2. Public Azure DNS returns a CNAME to
   myaccount.privatelink.blob.core.windows.net.
3. A private DNS zone named privatelink.blob.core.windows.net is linked to
   the client's VNet.
4. The Private Endpoint DNS zone group maintains an A record such as 10.1.1.x.
5. The client connects to that private address over the VNet.
```

If the zone link or private record is missing, the name can resolve to a public address. In this repository the Storage account has public network access disabled, so that public connection fails closed. A successful DNS query by itself therefore does not prove that the private path is correct.

### Service-specific zone names

| Service | Common private DNS zone |
|---|---|
| Blob Storage | `privatelink.blob.core.windows.net` |
| Key Vault | `privatelink.vaultcore.azure.net` |
| Azure SQL Database | `privatelink.database.windows.net` |
| Azure Container Registry | `privatelink.azurecr.io` |

Use the current Microsoft Private Link DNS reference for the exact service and cloud. An incorrect zone name or subresource produces an incomplete resolution path.

### Central DNS design

In the multi-subscription target, private DNS zones live in Connectivity and are linked to approved spokes. In the single-subscription track, the same resources live in the logical Connectivity resource group. The DNS behavior is the same, but subscription-level ownership and RBAC separation are not.

At scale, automate zone links and record registration, and define ownership for duplicate zones, stale records, and application-team requests.

### Private Endpoint versus Service Endpoint

- A Service Endpoint lets a PaaS service authorize traffic from selected VNet subnets while the service keeps its public endpoint addressing.
- A Private Endpoint places a private IP for a specific PaaS subresource in the VNet and introduces Private Link DNS requirements.

Select between them from access, hybrid-connectivity, DNS, exfiltration, cost, and service-support requirements. Private Endpoint is appropriate when the service must be reached through private addressing from Azure or hybrid networks.

### `168.63.129.16` and DNS Private Resolver

`168.63.129.16` is an Azure platform virtual IP used for services including Azure-provided DNS and VM-agent communication. Do not block platform dependencies without checking the documented NSG, route, firewall, and guest-OS behavior.

Azure DNS Private Resolver provides managed inbound and outbound DNS endpoints for hybrid resolution. An on-premises resolver can conditionally forward Azure private-zone queries to an inbound endpoint in the hub. This repository explains the pattern but does not deploy the resolver because it adds cost.

## 6. Hands-on workflow

Run commands from the repository root. Complete the platform baseline first and keep `enable_test_vm = true` while using the validation scripts.

Choose exactly one manifest for the active route and keep the export in the same shell. The path is relative to `terraform/20-platform/`, which is where both `terraform -chdir` and the helper scripts evaluate it.

Multi-subscription route:

```bash
export SUBSCRIPTION_VAR_FILE='../subscriptions.tfvars'
```

Single-subscription route:

```bash
export SUBSCRIPTION_VAR_FILE='../subscriptions.single.tfvars'
```

Do not use the multi-subscription manifest with the single-mode state, or the single-subscription manifest with the multi-mode state.

### Phase 1: low-cost baseline

The baseline is cost-controlled, not free. It can include a small VM, OS disk, Log Analytics ingestion, Storage, and a Private Endpoint.

```bash
./scripts/show-effective-routes.sh | tee /tmp/alz-routes-baseline.txt
./scripts/test-private-dns.sh
./scripts/test-egress.sh
```

Expected observations:

- The Storage FQDN resolves through its CNAME to the Terraform output `private_endpoint_ip`.
- The test VM NIC has system and peering routes but no Firewall UDR.
- Before Firewall is enabled, the egress test records whether the subnet has implicit outbound access. On a private-by-default subnet, both public tests can fail until an explicit outbound method is added.

Run the controlled DNS failure only after the successful baseline:

```bash
terraform -chdir=terraform/20-platform destroy \
  -var-file="$SUBSCRIPTION_VAR_FILE" \
  -target=azurerm_private_dns_zone_virtual_network_link.blob_to_spoke

./scripts/test-private-dns.sh

terraform -chdir=terraform/20-platform apply \
  -var-file="$SUBSCRIPTION_VAR_FILE"

./scripts/test-private-dns.sh
```

DNS caching and Azure propagation can delay the changed answer. Wait and retry before concluding that the link removal or restoration failed. Use `-target` only for this controlled exercise.

### Phase 2: Firewall session

Set `enable_firewall = true`, review the plan, and apply:

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

`github.com` should match the allowed application rule; the unlisted test destination should be blocked. Confirm the cause in Log Analytics rather than treating a timeout alone as proof:

```kusto
AZFWApplicationRule
| where TimeGenerated > ago(30m)
| project TimeGenerated, SourceIp, Fqdn, Action, Rule
| order by TimeGenerated desc
```

End the paid session immediately:

```bash
./scripts/destroy-expensive.sh
```

The cleanup script also removes the private test VM and its NIC. Return the cost switches in `terraform/20-platform/terraform.tfvars` to `false` so a later apply does not recreate them unintentionally.

### Phase 3: simulated hybrid routing

Run this phase only after cost approval. The previous cleanup removed the NIC needed by `show-effective-routes.sh`, so explicitly recreate the test VM for this phase. Keep Firewall disabled, set both gateway switches to `true`, and set a local `vpn_shared_key` of at least 16 characters:

```hcl
enable_firewall         = false
enable_vpn_gateway      = true
enable_simulated_onprem = true
enable_test_vm          = true
vpn_shared_key          = "<local-value-at-least-16-characters>"
```

Review and apply with the active route manifest:

```bash
terraform -chdir=terraform/20-platform plan \
  -var-file="$SUBSCRIPTION_VAR_FILE" \
  -out=tfplan
terraform -chdir=terraform/20-platform show tfplan
terraform -chdir=terraform/20-platform apply tfplan
```

After provisioning completes, verify both subscriptions used by the provider aliases. In single-subscription mode the two IDs are identical and the second query is intentionally redundant:

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

Collect evidence of `Connected` gateway connections and `VirtualNetworkGateway` routes. Do not claim an application connectivity test because the simulated on-premises subnet has no endpoint. Then remove the gateways and test VM:

```bash
./scripts/destroy-expensive.sh
```

Restore `enable_vpn_gateway`, `enable_simulated_onprem` and `enable_test_vm` to `false` in `terraform/20-platform/terraform.tfvars`.

---

Next: [03-azure-devops.md](03-azure-devops.md) — platform delivery and operations
