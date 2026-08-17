###############################################################################
# APPLICATION LANDING ZONE - "Corp" spoke
#
# In a real ALZ this is a separate subscription handed to an application team.
# They own what runs inside it; the platform team owns the VNet, the peering,
# the route table and the policy that constrains all of it.
#
# The mental shift that makes ALZ click: a landing zone is not a network, it is
# a PRE-GOVERNED SUBSCRIPTION. Network is one of eight design areas.
###############################################################################

resource "azurerm_resource_group" "landing_zone" {
  provider = azurerm.corp_dev

  name     = "rg-${var.prefix}-corp-app1-${var.location}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "spoke" {
  provider = azurerm.corp_dev

  name                = "vnet-${var.prefix}-corp-${var.location}"
  resource_group_name = azurerm_resource_group.landing_zone.name
  location            = azurerm_resource_group.landing_zone.location
  address_space       = [var.spoke_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "workload" {
  provider = azurerm.corp_dev

  name                 = "snet-workload"
  resource_group_name  = azurerm_resource_group.landing_zone.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.spoke_workload_subnet]
}

resource "azurerm_subnet" "private_link" {
  provider = azurerm.corp_dev

  name                 = "snet-privatelink"
  resource_group_name  = azurerm_resource_group.landing_zone.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.spoke_privatelink_subnet]

  # Private endpoints historically could not sit behind NSGs or UDRs; the
  # network policies flag is what controls that. Modern default is Disabled.
  # If you ever need to NSG-protect a private endpoint subnet, this is the
  # switch you change.
  private_endpoint_network_policies = "Disabled"
}

###############################################################################
# NSG - the L4 control, applied at the subnet
#
# NSG and Azure Firewall are not alternatives, they are different layers. NSG
# is a stateful distributed L4 ACL enforced at the vNIC,
# free, and has no logging of allowed flows unless you enable flow logs.
# Azure Firewall is a centralised, billed, L3-L7 appliance with FQDN filtering,
# TLS inspection (Premium) and full logging. Defence in depth uses both.
###############################################################################

resource "azurerm_network_security_group" "workload" {
  provider = azurerm.corp_dev

  name                = "nsg-${var.prefix}-corp-workload"
  resource_group_name = azurerm_resource_group.landing_zone.name
  location            = azurerm_resource_group.landing_zone.location
  tags                = var.tags

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Explicit deny above the implicit DenyAllInbound (65500) so the intent is
  # visible in the portal and in any audit export.
  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  provider = azurerm.corp_dev

  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

###############################################################################
# UDR - forced tunnelling through the firewall
#
# This is the heart of hub-and-spoke and the thing most people get wrong.
#
# Azure's default system routes send 0.0.0.0/0 straight out to the internet
# from any subnet. To make traffic traverse the firewall you must OVERRIDE that
# with a user-defined route pointing at the firewall's PRIVATE ip as a
# VirtualAppliance next hop.
#
# Two traps:
#   1. Setting a 0.0.0.0/0 UDR on the AzureFirewallSubnet itself creates a
#      routing loop. Never do it (unless you are deliberately forced-tunnelling
#      to on-prem, which needs a different design).
#   2. disable_bgp_route_propagation = true stops on-prem routes learned over
#      ExpressRoute/VPN from being injected here, forcing that traffic through
#      the firewall too. Leave it false while you are learning, then turn it on
#      and watch the effective routes change.
###############################################################################

resource "azurerm_route_table" "spoke" {
  provider = azurerm.corp_dev

  count = var.enable_firewall ? 1 : 0

  name                          = "rt-${var.prefix}-corp-workload"
  resource_group_name           = azurerm_resource_group.landing_zone.name
  location                      = azurerm_resource_group.landing_zone.location
  bgp_route_propagation_enabled = true
  tags                          = var.tags

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.hub[0].ip_configuration[0].private_ip_address
  }

  # Spoke-to-spoke and spoke-to-onprem also via the firewall, so the whole
  # RFC1918 space is inspected. In a real estate you would route the specific
  # ranges you actually use, not all three blocks.
  route {
    name                   = "rfc1918-10-to-firewall"
    address_prefix         = "10.0.0.0/8"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.hub[0].ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "workload" {
  provider = azurerm.corp_dev

  count = var.enable_firewall ? 1 : 0

  subnet_id      = azurerm_subnet.workload.id
  route_table_id = azurerm_route_table.spoke[0].id
}
