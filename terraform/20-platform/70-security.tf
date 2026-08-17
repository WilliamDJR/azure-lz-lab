###############################################################################
# Security platform subscription
#
# The subscription exists as a separate blast-radius and RBAC boundary even
# when Sentinel is disabled. Enabling this block gives the security team its
# own analytics workspace instead of granting broad write access to the
# Management subscription.
###############################################################################

resource "azurerm_resource_group" "security" {
  provider = azurerm.security
  count    = var.enable_sentinel ? 1 : 0

  name     = "rg-${var.prefix}-security-${var.location}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "security" {
  provider = azurerm.security
  count    = var.enable_sentinel ? 1 : 0

  name                = "log-${var.prefix}-security-${var.location}"
  resource_group_name = azurerm_resource_group.security[0].name
  location            = azurerm_resource_group.security[0].location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = 1
  tags                = var.tags
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "security" {
  provider = azurerm.security
  count    = var.enable_sentinel ? 1 : 0

  workspace_id = azurerm_log_analytics_workspace.security[0].id
}
