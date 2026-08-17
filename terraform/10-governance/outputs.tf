output "intermediate_root_id" {
  description = "Resource ID of the intermediate root management group."
  value       = azurerm_management_group.intermediate_root.id
}

output "corp_management_group_id" {
  description = "Resource ID of the Corp landing-zone management group."
  value       = azurerm_management_group.corp.id
}

output "hierarchy" {
  description = "Human-readable view of the hierarchy you just created."
  value = {
    "${var.prefix}" = {
      platform = [
        azurerm_management_group.platform_identity.name,
        azurerm_management_group.platform_management.name,
        azurerm_management_group.platform_connectivity.name,
        azurerm_management_group.platform_security.name,
      ]
      landing_zones = [
        azurerm_management_group.corp.name,
        azurerm_management_group.online.name,
      ]
      sandbox        = azurerm_management_group.sandbox.name
      decommissioned = azurerm_management_group.decommissioned.name
    }
  }
}

output "subscription_placement" {
  description = "Target management-group ID for every subscription role."
  value       = local.subscription_management_group_ids
}
