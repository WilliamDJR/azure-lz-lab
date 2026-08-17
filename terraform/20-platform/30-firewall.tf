###############################################################################
# Azure Firewall  (COST TOGGLE: var.enable_firewall)
#
# All SKUs are billed while deployed and can add data-processing charges.
# Basic requires a second, dedicated management subnet and public IP.
#
# Turn it on for a session, run scripts/test-egress.sh, then run
# scripts/destroy-expensive.sh. Do not leave it running overnight.
###############################################################################

resource "azurerm_public_ip" "firewall" {
  provider = azurerm.connectivity

  count = var.enable_firewall ? 1 : 0

  name                = "pip-${var.prefix}-fw-${var.location}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = azurerm_resource_group.connectivity.location
  allocation_method   = "Static"
  sku                 = "Standard" # Azure Firewall requires Standard SKU, Static
  tags                = var.tags
}

resource "azurerm_public_ip" "firewall_mgmt" {
  provider = azurerm.connectivity

  count = var.enable_firewall && var.firewall_sku_tier == "Basic" ? 1 : 0

  name                = "pip-${var.prefix}-fw-mgmt-${var.location}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = azurerm_resource_group.connectivity.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

###############################################################################
# Firewall Policy
#
# Policy is a separate object from the firewall on purpose: in a real estate
# you build a PARENT policy owned by security (baseline deny, mandatory
# allow-list, threat intel) and CHILD policies inherited by each regional
# firewall, which application teams can extend without touching the baseline.
# That parent/child inheritance is the answer to "how do you let app teams
# self-serve firewall rules without giving them the firewall".
###############################################################################

resource "azurerm_firewall_policy" "hub" {
  provider = azurerm.connectivity

  count = var.enable_firewall ? 1 : 0

  name                = "afwp-${var.prefix}-hub"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = azurerm_resource_group.connectivity.location
  sku                 = var.firewall_sku_tier
  tags                = var.tags

  threat_intelligence_mode = "Alert"

  dns {
    proxy_enabled = true # required for FQDN filtering in NETWORK rules
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "baseline" {
  provider = azurerm.connectivity

  count = var.enable_firewall ? 1 : 0

  name               = "rcg-baseline"
  firewall_policy_id = azurerm_firewall_policy.hub[0].id
  priority           = 500

  # NETWORK rules match on IP/port/protocol (L3-L4).
  network_rule_collection {
    name     = "nrc-core-infrastructure"
    priority = 400
    action   = "Allow"

    rule {
      name                  = "allow-dns-out"
      protocols             = ["UDP", "TCP"]
      source_addresses      = [var.spoke_address_space]
      destination_addresses = ["168.63.129.16"] # Azure platform DNS / wire server
      destination_ports     = ["53"]
    }

    rule {
      name                  = "allow-ntp"
      protocols             = ["UDP"]
      source_addresses      = [var.spoke_address_space]
      destination_addresses = ["*"]
      destination_ports     = ["123"]
    }
  }

  # APPLICATION rules match on FQDN (L7) and can do TLS SNI inspection.
  # This is the capability an NSG cannot give you and the usual justification
  # for paying for a firewall at all.
  application_rule_collection {
    name     = "arc-allowed-egress"
    priority = 500
    action   = "Allow"

    rule {
      name             = "allow-package-repos"
      source_addresses = [var.spoke_address_space]

      protocols {
        type = "Https"
        port = 443
      }
      protocols {
        type = "Http"
        port = 80
      }

      destination_fqdns = [
        "*.ubuntu.com",
        "*.debian.org",
        "*.microsoft.com",
        "*.azure.com",
      ]
    }

    rule {
      name             = "allow-github"
      source_addresses = [var.spoke_address_space]

      protocols {
        type = "Https"
        port = 443
      }

      destination_fqdns = ["github.com", "*.github.com", "*.githubusercontent.com"]
    }
  }
}

resource "azurerm_firewall" "hub" {
  provider = azurerm.connectivity

  count = var.enable_firewall ? 1 : 0

  name                = "afw-${var.prefix}-hub-${var.location}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = azurerm_resource_group.connectivity.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  firewall_policy_id  = azurerm_firewall_policy.hub[0].id
  tags                = var.tags

  ip_configuration {
    name                 = "ipconfig-primary"
    subnet_id            = azurerm_subnet.hub_firewall.id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }

  dynamic "management_ip_configuration" {
    for_each = var.firewall_sku_tier == "Basic" ? [1] : []

    content {
      name                 = "ipconfig-management"
      subnet_id            = azurerm_subnet.hub_firewall_mgmt[0].id
      public_ip_address_id = azurerm_public_ip.firewall_mgmt[0].id
    }
  }
}

###############################################################################
# Diagnostics
#
# Without this the firewall tells you nothing. AzureFirewallApplicationRule and
# AzureFirewallNetworkRule (or the newer resource-specific tables) are where
# you prove a flow was allowed or denied - the first thing you reach for when
# an app team says "the firewall is blocking us".
###############################################################################

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  provider = azurerm.connectivity

  count = var.enable_firewall ? 1 : 0

  name                           = "diag-to-law"
  target_resource_id             = azurerm_firewall.hub[0].id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.platform.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AZFWNetworkRule"
  }

  enabled_log {
    category = "AZFWApplicationRule"
  }

  enabled_log {
    category = "AZFWDnsQuery"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
