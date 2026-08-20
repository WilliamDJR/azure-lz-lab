output "log_analytics_workspace_id" {
  description = "Feed this back into the 10-governance root as log_analytics_workspace_id to switch on the deployIfNotExists policy."
  value       = azurerm_log_analytics_workspace.platform.id
}

output "security_log_analytics_workspace_id" {
  description = "Dedicated Sentinel workspace ID when enable_sentinel is true."
  value       = var.enable_sentinel ? azurerm_log_analytics_workspace.security[0].id : null
}

output "subscription_ids" {
  description = "Reference role-to-subscription map used by the provider aliases. Repeated values represent logical roles, not isolation."
  value       = var.subscription_ids
}

output "deployment_mode" {
  description = "Whether provider aliases target one shared subscription or separate enterprise role subscriptions."
  value = var.allow_shared_subscription_ids ? "single-subscription" : (
    var.allow_logical_workload_subscription_ids ? "quota-limited" : "multi-subscription"
  )
}

output "logical_role_subscription_ids" {
  description = "Logical role-to-subscription map. In quota-limited mode the workload roles intentionally reuse the protected existing subscription."
  value       = var.subscription_ids
}

output "logical_role_resource_groups" {
  description = "Resource groups that represent logical roles. Security and sandbox are null until their optional exercises are enabled."
  value = {
    management   = azurerm_resource_group.management.name
    connectivity = azurerm_resource_group.connectivity.name
    corp_dev     = azurerm_resource_group.landing_zone.name
    security     = try(azurerm_resource_group.security[0].name, null)
    sandbox      = try(azurerm_resource_group.onprem[0].name, null)
  }
}

output "corp_dev_subscription_id" {
  value = var.subscription_ids.corp_dev
}

output "connectivity_subscription_id" {
  value = var.subscription_ids.connectivity
}

output "management_subscription_id" {
  value = var.subscription_ids.management
}

output "security_subscription_id" {
  value = var.subscription_ids.security
}

output "sandbox_subscription_id" {
  value = var.subscription_ids.sandbox
}

output "hub_vnet_id" {
  value = azurerm_virtual_network.hub.id
}

output "spoke_vnet_id" {
  value = azurerm_virtual_network.spoke.id
}

output "firewall_private_ip" {
  description = "The next-hop address every spoke UDR points at. Null when the firewall is switched off."
  value       = var.enable_firewall ? azurerm_firewall.hub[0].ip_configuration[0].private_ip_address : null
}

output "firewall_public_ip" {
  description = "The address the whole estate SNATs behind on egress."
  value       = var.enable_firewall ? azurerm_public_ip.firewall[0].ip_address : null
}

output "storage_account_name" {
  description = "Use this in the DNS resolution test."
  value       = azurerm_storage_account.private.name
}

output "storage_private_fqdn" {
  value = "${azurerm_storage_account.private.name}.blob.core.windows.net"
}

output "private_endpoint_ip" {
  description = "What the private FQDN should resolve to from inside the spoke."
  value       = azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address
}

output "test_vm_name" {
  value = var.enable_test_vm ? azurerm_linux_virtual_machine.test[0].name : null
}

output "landing_zone_resource_group" {
  value = azurerm_resource_group.landing_zone.name
}

output "connectivity_resource_group" {
  value = azurerm_resource_group.connectivity.name
}

output "enabled_cost_features" {
  description = "Billed lab features currently enabled. Check Cost Management and the current pricing calculator for amounts."
  value = {
    firewall           = var.enable_firewall
    hub_vpn_gateway    = var.enable_vpn_gateway
    simulated_onprem   = var.enable_simulated_onprem
    test_vm            = var.enable_test_vm
    sentinel_workspace = var.enable_sentinel
  }
}
