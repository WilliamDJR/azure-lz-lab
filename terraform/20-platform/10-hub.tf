###############################################################################
# PLATFORM LANDING ZONE - Connectivity
#
# In a real ALZ this whole file lives in its own "Connectivity" subscription
# under the Platform management group, owned by the platform team, and no
# application team has write access to it.
#
# GCP mental model: this is the Shared VPC host project. The difference is
# that Azure has no Shared VPC - spokes get their OWN VNet and you stitch them
# together with peering. That is why hub-and-spoke exists at all.
###############################################################################

locals {
  # Deterministic subnet carve-up from the hub CIDR.
  # Azure reserves several subnet NAMES - they are not conventions, they are
  # magic strings the platform looks for:
  #   AzureFirewallSubnet           - minimum /26
  #   AzureFirewallManagementSubnet - minimum /26, required for Basic SKU
  #   GatewaySubnet                 - minimum /27 for VPN, /27 for ExpressRoute
  #   AzureBastionSubnet            - minimum /26
  # Getting the name wrong is a deployment failure, not a warning.
  hub_firewall_subnet      = cidrsubnet(var.hub_address_space, 10, 0)    # 10.0.0.0/26
  hub_fw_mgmt_subnet       = cidrsubnet(var.hub_address_space, 10, 1)    # 10.0.0.64/26
  hub_gateway_subnet       = cidrsubnet(var.hub_address_space, 11, 8)    # 10.0.1.0/27
  hub_shared_svcs_subnet   = cidrsubnet(var.hub_address_space, 8, 2)     # 10.0.2.0/24
  spoke_workload_subnet    = cidrsubnet(var.spoke_address_space, 8, 0)   # 10.1.0.0/24
  spoke_privatelink_subnet = cidrsubnet(var.spoke_address_space, 8, 1)   # 10.1.1.0/24
  onprem_gateway_subnet    = cidrsubnet(var.onprem_address_space, 11, 0) # 10.100.0.0/27
  onprem_workload_subnet   = cidrsubnet(var.onprem_address_space, 8, 1)  # 10.100.1.0/24
}

resource "azurerm_resource_group" "connectivity" {
  provider = azurerm.connectivity

  name     = "rg-${var.prefix}-connectivity-${var.location}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "hub" {
  provider = azurerm.connectivity

  name                = "vnet-${var.prefix}-hub-${var.location}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = azurerm_resource_group.connectivity.location
  address_space       = [var.hub_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "hub_firewall" {
  provider = azurerm.connectivity

  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.connectivity.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.hub_firewall_subnet]
}

resource "azurerm_subnet" "hub_firewall_mgmt" {
  provider = azurerm.connectivity

  count = var.enable_firewall && var.firewall_sku_tier == "Basic" ? 1 : 0

  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.connectivity.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.hub_fw_mgmt_subnet]
}

resource "azurerm_subnet" "hub_gateway" {
  provider = azurerm.connectivity

  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.connectivity.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.hub_gateway_subnet]
}

resource "azurerm_subnet" "hub_shared" {
  provider = azurerm.connectivity

  name                 = "snet-shared-services"
  resource_group_name  = azurerm_resource_group.connectivity.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.hub_shared_svcs_subnet]
}

###############################################################################
# Peering
#
# Peering is NOT transitive. Spoke A peered to Hub and Spoke B peered to Hub
# does not give you A <-> B. If you want spoke-to-spoke traffic you must either
# route it through a network virtual appliance in the hub (Azure Firewall, via
# UDR - what this lab does), or use Azure Virtual WAN, or peer the spokes
# directly (which does not scale past a handful of VNets).
#
# This non-transitivity is the reason hub-and-spoke needs Azure Firewall or
# another routing appliance when spokes must communicate.
###############################################################################

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  provider = azurerm.connectivity

  name                      = "peer-hub-to-corp"
  resource_group_name       = azurerm_resource_group.connectivity.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true # required: traffic arriving via the firewall was forwarded, not originated

  # Lets the spoke use the hub's VPN/ExpressRoute gateway. The mirror side must
  # set use_remote_gateways = true. Both sides must agree or peering sits in
  # "Disconnected".
  allow_gateway_transit = var.enable_vpn_gateway
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  provider = azurerm.corp_dev

  name                      = "peer-corp-to-hub"
  resource_group_name       = azurerm_resource_group.landing_zone.name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = var.enable_vpn_gateway

  # Terraform cannot see this dependency: use_remote_gateways fails unless the
  # gateway already exists on the hub side.
  depends_on = [azurerm_virtual_network_gateway.hub]
}
