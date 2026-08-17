###############################################################################
# Hybrid connectivity  (COST TOGGLE: var.enable_vpn_gateway)
#
# You cannot lab ExpressRoute - it needs a physical circuit from a connectivity
# provider. What you CAN lab is everything downstream of
# the circuit: the gateway, the GatewaySubnet, route propagation, transit, and
# how spokes reach on-prem ranges.
#
# A VPN gateway and an ExpressRoute gateway behave almost identically from the
# spoke's point of view: both live in GatewaySubnet, both inject routes via
# BGP, both need allow_gateway_transit on the hub peering and
# use_remote_gateways on the spoke peering.
#
# Gateway provisioning takes 25-45 minutes. Start the apply, go read
# docs/02-networking.md, come back.
###############################################################################

resource "azurerm_public_ip" "vpn_gateway" {
  provider = azurerm.connectivity

  count = var.enable_vpn_gateway ? 1 : 0

  name                = "pip-${var.prefix}-vgw-hub"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = azurerm_resource_group.connectivity.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "hub" {
  provider = azurerm.connectivity

  count = var.enable_vpn_gateway ? 1 : 0

  name                = "vgw-${var.prefix}-hub-${var.location}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = azurerm_resource_group.connectivity.location

  type     = "Vpn"
  vpn_type = "RouteBased" # PolicyBased is legacy, single tunnel, no BGP
  sku      = "VpnGw1"

  active_active = false
  bgp_enabled   = false
  tags          = var.tags

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.hub_gateway.id
  }
}

###############################################################################
# Simulated "on-premises" site  (COST TOGGLE: var.enable_simulated_onprem)
#
# A second VNet with its own gateway, connected VNet-to-VNet. From the hub's
# perspective this is indistinguishable from a real branch office over IPsec.
# Doubles your gateway spend, so treat it as a one-afternoon exercise.
###############################################################################

resource "azurerm_resource_group" "onprem" {
  provider = azurerm.sandbox

  count = var.enable_simulated_onprem ? 1 : 0

  name     = "rg-${var.prefix}-simulated-onprem-${var.location}"
  location = var.location
  tags     = merge(var.tags, { role = "simulated-onprem" })
}

resource "azurerm_virtual_network" "onprem" {
  provider = azurerm.sandbox

  count = var.enable_simulated_onprem ? 1 : 0

  name                = "vnet-${var.prefix}-onprem"
  resource_group_name = azurerm_resource_group.onprem[0].name
  location            = azurerm_resource_group.onprem[0].location
  address_space       = [var.onprem_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "onprem_gateway" {
  provider = azurerm.sandbox

  count = var.enable_simulated_onprem ? 1 : 0

  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.onprem[0].name
  virtual_network_name = azurerm_virtual_network.onprem[0].name
  address_prefixes     = [local.onprem_gateway_subnet]
}

resource "azurerm_subnet" "onprem_workload" {
  provider = azurerm.sandbox

  count = var.enable_simulated_onprem ? 1 : 0

  name                 = "snet-onprem-servers"
  resource_group_name  = azurerm_resource_group.onprem[0].name
  virtual_network_name = azurerm_virtual_network.onprem[0].name
  address_prefixes     = [local.onprem_workload_subnet]
}

resource "azurerm_public_ip" "onprem_gateway" {
  provider = azurerm.sandbox

  count = var.enable_simulated_onprem ? 1 : 0

  name                = "pip-${var.prefix}-vgw-onprem"
  resource_group_name = azurerm_resource_group.onprem[0].name
  location            = azurerm_resource_group.onprem[0].location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "onprem" {
  provider = azurerm.sandbox

  count = var.enable_simulated_onprem ? 1 : 0

  name                = "vgw-${var.prefix}-onprem"
  resource_group_name = azurerm_resource_group.onprem[0].name
  location            = azurerm_resource_group.onprem[0].location

  type     = "Vpn"
  vpn_type = "RouteBased"
  sku      = "VpnGw1"
  tags     = var.tags

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.onprem_gateway[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.onprem_gateway[0].id
  }
}

# A VNet-to-VNet connection needs BOTH directions. Create only one and the
# tunnel sits in "Connecting" forever - a good failure to see on purpose once.
resource "azurerm_virtual_network_gateway_connection" "hub_to_onprem" {
  provider = azurerm.connectivity

  count = var.enable_simulated_onprem ? 1 : 0

  name                = "cn-hub-to-onprem"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = azurerm_resource_group.connectivity.location

  type                            = "Vnet2Vnet"
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.hub[0].id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.onprem[0].id
  shared_key                      = var.vpn_shared_key
  tags                            = var.tags
}

resource "azurerm_virtual_network_gateway_connection" "onprem_to_hub" {
  provider = azurerm.sandbox

  count = var.enable_simulated_onprem ? 1 : 0

  name                = "cn-onprem-to-hub"
  resource_group_name = azurerm_resource_group.onprem[0].name
  location            = azurerm_resource_group.onprem[0].location

  type                            = "Vnet2Vnet"
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.onprem[0].id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.hub[0].id
  shared_key                      = var.vpn_shared_key
  tags                            = var.tags
}
