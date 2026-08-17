output "log_analytics_workspace_id" {
  description = "Feed this back into the 10-governance root as log_analytics_workspace_id to switch on the deployIfNotExists policy."
  value       = azurerm_log_analytics_workspace.platform.id
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

output "estimated_hourly_cost_aud" {
  description = "Rough order of magnitude only. Check the Azure pricing calculator for real numbers."
  value = join(" + ", compact([
    "baseline ~A$0.03",
    var.enable_firewall ? (var.firewall_sku_tier == "Basic" ? "firewall ~A$0.50" : "firewall ~A$1.50") : "",
    var.enable_vpn_gateway ? "hub gateway ~A$0.19" : "",
    var.enable_simulated_onprem ? "onprem gateway ~A$0.19" : "",
    var.enable_test_vm ? "test vm ~A$0.02" : "",
  ]))
}
