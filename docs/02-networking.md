# 02 · Enterprise Azure Networking

[中文版](02-networking_cn.md)

> This chapter covers Hub-Spoke, ExpressRoute, VPN, Private Endpoints, and the routing behavior that connects them. Read it alongside `terraform/20-platform/` and `scripts/show-effective-routes.sh`.

---

## 1. Why Azure uses Hub-Spoke

GCP has **Shared VPC**: a host project owns a network and service projects place workloads directly in its subnets. Azure has no direct equivalent. Each VNet is an independent network object, and connectivity between VNets uses peering.

The governing rule is:

> **VNet peering is non-transitive.** If A can reach Hub and B can reach Hub, A still cannot automatically reach B.

There are three common ways to provide spoke-to-spoke connectivity:

| Option | Implementation | Best fit |
|---|---|---|
| **NVA plus UDR in the hub** (this lab) | Spoke route tables direct traffic to Azure Firewall, which forwards it to the other spoke | Standard enterprise design with centralized inspection and logging |
| **Azure Virtual WAN** | A Microsoft-managed hub provides routing and large-scale branch connectivity | Many sites, multiple regions, or route-table operations becoming a bottleneck |
| **Direct spoke peering** | Peer selected spokes to each other | A small number of latency-sensitive pairs; it becomes O(n²) at scale |

The design principle is that shared, expensive services live in the hub, while workloads remain isolated in their own subscriptions and VNets.

## 2. Routing: the core of the design

An Azure effective route table combines **system routes, user-defined routes (UDRs), and BGP-learned routes**.

### Route selection

1. **Longest prefix match always wins.** `/24` beats `/16`, which beats `/8`, which beats `0.0.0.0/0`.
2. For equal prefix lengths, precedence is **UDR > BGP > system route**.

### A deliberate example in this lab

The route table in `terraform/20-platform/20-spoke.tf` contains `10.0.0.0/8 -> firewall`. It does not force traffic to the hub through the firewall.

Peering installs a system route such as `10.0.0.0/16 -> VNetPeering` for the hub address space. The `/16` is more specific than the `/8`, so peering wins. The `/8` affects other RFC1918 destinations, such as the simulated on-premises range `10.100.0.0/16`.

To inspect hub-bound traffic, add a UDR at least as specific as the peering route. Run `scripts/show-effective-routes.sh` to see the merged result directly.

### Forced tunnelling

Attach `0.0.0.0/0 -> VirtualAppliance(<firewall-private-IP>)` to a spoke subnet to send its egress through Azure Firewall.

Two important constraints:

1. Never attach a `0.0.0.0/0` UDR to `AzureFirewallSubnet`; the firewall can route traffic back to itself and break egress.
2. UDRs on `GatewaySubnet` can steer inbound on-premises traffic through inspection, but incorrect routes can disrupt the gateway control plane. Do not place `0.0.0.0/0` on `GatewaySubnet`.

### `bgp_route_propagation_enabled`

When gateway route propagation is disabled on a spoke route table, routes learned by the gateway are not injected into that table. On-premises traffic then falls through to the configured default route and can be sent through the firewall. Use this deliberately: it changes how hybrid routes are selected.

## 3. Azure Firewall, NSG, and Application Gateway

These controls are complementary, not alternatives:

| | NSG | Azure Firewall | Application Gateway (WAF) |
|---|---|---|---|
| Layer | L3/L4 | L3-L7; Premium can perform TLS inspection | L7 HTTP/HTTPS |
| Placement | Distributed on subnets or NICs | Centralized in the hub | In front of an application |
| FQDN filtering | No | Yes, through application rules | Yes |
| Cost model | No separate charge | Hourly plus data processing | Instance and capacity based |
| Logging | Flow logs must be enabled | Detailed allow/deny logs | Detailed request and WAF logs |
| Typical role | Microsegmentation | Egress and east-west inspection | Inbound web protection |

Use NSGs to express which subnets or NICs can communicate. Use Azure Firewall for centralized FQDN filtering, threat intelligence, and auditable traffic decisions. Use Application Gateway/WAF for HTTP-aware inbound protection.

### Firewall Policy inheritance

A common production model is for the security team to own a **parent policy** containing mandatory baselines, deny rules, and threat-intelligence settings. Regional firewalls use child policies, where delegated teams can add rules without modifying the baseline.

## 4. ExpressRoute

ExpressRoute requires a physical service-provider circuit, so the lab cannot deploy one. It can still reproduce the Azure-side gateway transit and route-propagation behavior by using VPN gateways.

### Architecture

```text
Your datacenter/colo ---- provider network ---- MSEE ---- Microsoft backbone
      CE router          carrier/exchange      redundant Microsoft edge routers
```

- A **circuit** is the logical service with a bandwidth and a Local, Standard, or Premium SKU.
- Production connectivity uses a redundant pair; the ExpressRoute SLA assumes redundancy.
- **Private peering** reaches private IPs in VNets.
- **Microsoft peering** reaches selected Microsoft public services over advertised public prefixes without traversing the public internet. The former Public peering option is retired.
- **Local** is limited to supported regions in the local metro, **Standard** covers the relevant geopolitical region, and **Premium** expands global reach, route scale, and VNet limits.
- **Global Reach** connects two on-premises sites across Microsoft's backbone.
- **FastPath** allows the data path to bypass the ExpressRoute gateway for higher throughput and lower latency, subject to feature constraints.
- A VPN backup path is a common resilience design. BGP attributes determine which path is preferred.

### Behavior from the spoke

ExpressRoute and VPN gateways both reside in `GatewaySubnet`, inject routes toward spokes, and require:

- Hub peering: `allow_gateway_transit = true`
- Spoke peering: `use_remote_gateways = true`

This is why the VPN scenario in `terraform/20-platform/40-vpn-and-onprem.tf` is useful: from the spoke's routing perspective it demonstrates the same gateway-transit mechanics.

## 5. Private Endpoint and DNS

### Resolution path

```text
1. The client resolves myaccount.blob.core.windows.net.
2. Public Azure DNS returns a CNAME:
     myaccount.blob.core.windows.net
       -> myaccount.privatelink.blob.core.windows.net
3. A private DNS zone named privatelink.blob.core.windows.net is linked to
   the client's VNet, so the second name is resolved privately.
4. The A record created by the private endpoint DNS zone group returns 10.1.1.x.
5. The client connects to 10.1.1.x over the VNet, without using the internet.
```

If the VNet link or private record is missing, the name can still resolve through public DNS, but it resolves to a public endpoint and the connection fails when public network access is disabled. A missing VNet link is therefore the first thing to check when DNS succeeds but connectivity fails.

`scripts/test-private-dns.sh` shows the chain from the test VM. The lab then removes the VNet link deliberately so you can compare the private and public answers.

### Private DNS zone names are service-specific

| Service | Private DNS zone |
|---|---|
| Blob Storage | `privatelink.blob.core.windows.net` |
| Key Vault | `privatelink.vaultcore.azure.net` |
| Azure SQL | `privatelink.database.windows.net` |
| AKS API server | `privatelink.<region>.azmk8s.io` |
| Azure Container Registry | `privatelink.azurecr.io` |

An incorrect zone name fails silently from the application's perspective.

### Enterprise DNS design

Keep private DNS zones centrally in the Connectivity subscription, link them to the relevant spokes, and automate endpoint registration through DNS zone groups and policy. Letting every application team create its own copy leads to conflicts and stale A records.

This lab follows that model: `50-private-link.tf` creates the zone in the connectivity resource group.

### Private Endpoint versus Service Endpoint

- A **Service Endpoint** extends subnet identity to a PaaS service. The service still uses a public address, although traffic remains on the Microsoft backbone. It cannot be reached from on-premises in the same way and has no Private Link DNS requirement.
- A **Private Endpoint** allocates a real private IP in your VNet for a PaaS subresource. It can be reached over VPN or ExpressRoute and is charged by endpoint and data usage.

Private Endpoint is the usual choice where private addressing and hybrid access are required.

### `168.63.129.16`

This Azure platform virtual IP provides services including DNS, DHCP, load-balancer health probes, and VM agent communication. Azure-provided DNS uses this address inside every VNet. Blocking DNS to it breaks name resolution; the lab firewall policy explicitly allows port 53 to this address.

### Azure DNS Private Resolver

DNS Private Resolver is the managed answer to hybrid private DNS. An inbound endpoint in the hub allows on-premises resolvers to conditionally forward Azure private-zone queries into Azure. It replaces the common pattern of self-managed DNS forwarder VMs. The lab does not deploy it because it has an additional cost.

## 6. Hands-on checklist

### Phase 1: low-cost baseline

- [ ] Apply the baseline topology with the optional firewall and gateways disabled.
- [ ] Run `scripts/show-effective-routes.sh` and save the baseline.
- [ ] Run `scripts/test-private-dns.sh` and inspect the CNAME chain.
- [ ] Remove `azurerm_private_dns_zone_virtual_network_link.blob_to_spoke`, rerun the DNS test, and observe the public result.
- [ ] Run `terraform apply` to restore the link and verify private resolution.

### Phase 2: firewall session

- [ ] Set `enable_firewall = true` and apply.
- [ ] Save and diff the effective route table; identify routes with a `User` source.
- [ ] From the VM, verify that `https://github.com` is allowed and an unlisted destination is denied.
- [ ] Query the denied request in Log Analytics:

  ```kusto
  AZFWApplicationRule
  | where TimeGenerated > ago(30m)
  | project TimeGenerated, SourceIp, Fqdn, Action, Rule
  | order by TimeGenerated desc
  ```

- [ ] Run `scripts/destroy-expensive.sh` immediately afterward.

### Phase 3: simulated hybrid connectivity

- [ ] Set `enable_vpn_gateway = true` and `enable_simulated_onprem = true`.
- [ ] Wait for both gateway connections to reach `Connected`.
- [ ] Run `show-effective-routes.sh` and identify `VirtualNetworkGateway` routes.
- [ ] Test traffic from the spoke toward the simulated on-premises range.
- [ ] Run `scripts/destroy-expensive.sh` immediately afterward.
