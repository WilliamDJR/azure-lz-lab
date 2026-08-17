###############################################################################
# Private Endpoint + Private DNS  (essentially free - leave this running)
#
# This is the highest-value, lowest-cost part of the lab. Private Endpoint DNS
# is a common Azure enterprise networking failure, so this lab makes the
# resolution chain observable and testable.
#
# GCP mental model: Private Service Connect. Same idea - give a PaaS service a
# private IP inside your VNet - but Azure's version depends on a DNS override
# that you have to wire up yourself, and that is where it goes wrong.
#
# The chain, in order. Memorise this:
#
#   1. Client resolves myaccount.blob.core.windows.net
#   2. Public Azure DNS returns a CNAME:
#        myaccount.blob.core.windows.net
#          -> myaccount.privatelink.blob.core.windows.net
#   3. Because a PRIVATE DNS ZONE named privatelink.blob.core.windows.net is
#      LINKED to the client's VNet, that second name resolves privately
#   4. The A record in that zone - created automatically by the private
#      endpoint's DNS zone group - returns 10.1.1.x
#   5. Client connects to 10.1.1.x over the VNet. No internet path involved.
#
# Break any one of those links and you get the classic symptom: the name still
# resolves, but to a PUBLIC IP, and the connection then fails closed because
# public network access is disabled. "It resolves but I can't connect" is
# almost always a missing VNet link on the private DNS zone.
#
# In a real hub-and-spoke the private DNS zones live in the CONNECTIVITY
# subscription and are linked to every spoke, so that DNS is a platform
# service rather than something each app team reinvents. This lab does the
# same: the zone sits in the connectivity resource group.
###############################################################################

resource "random_string" "sa_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "private" {
  name                = "st${var.prefix}pe${random_string.sa_suffix.result}"
  resource_group_name = azurerm_resource_group.landing_zone.name
  location            = azurerm_resource_group.landing_zone.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  # The point of the exercise: no public path at all. With this false, if your
  # DNS is wrong the client gets a public IP and the connection is REFUSED -
  # which is exactly the failure mode you want to be able to diagnose.
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"

  tags = var.tags
}

# The private DNS zone name is NOT arbitrary. Each PaaS service has a specific
# privatelink zone name and getting it wrong silently breaks resolution.
#   blob      -> privatelink.blob.core.windows.net
#   Key Vault -> privatelink.vaultcore.azure.net
#   SQL DB    -> privatelink.database.windows.net
#   AKS API   -> privatelink.<region>.azmk8s.io
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.connectivity.name
  tags                = var.tags
}

# Link the zone to the SPOKE so workloads there resolve privately.
resource "azurerm_private_dns_zone_virtual_network_link" "blob_to_spoke" {
  name                  = "link-to-corp-spoke"
  resource_group_name   = azurerm_resource_group.connectivity.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = var.tags
}

# ...and to the HUB, so anything in the hub (and, once the firewall DNS proxy
# is on, anything resolving through the firewall) sees the same answer.
resource "azurerm_private_dns_zone_virtual_network_link" "blob_to_hub" {
  name                  = "link-to-hub"
  resource_group_name   = azurerm_resource_group.connectivity.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${var.prefix}-blob"
  resource_group_name = azurerm_resource_group.landing_zone.name
  location            = azurerm_resource_group.landing_zone.location
  subnet_id           = azurerm_subnet.private_link.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.private.id
    subresource_names              = ["blob"] # one endpoint per sub-resource
    is_manual_connection           = false
  }

  # This block is what auto-creates the A record in the zone. Omit it and you
  # must maintain A records by hand - which is how estates end up with stale
  # records pointing at recycled private IPs.
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}
