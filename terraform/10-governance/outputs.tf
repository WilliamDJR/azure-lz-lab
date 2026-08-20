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
  description = "Reference role-to-management-group map for the enterprise topology. In single-subscription mode these are conceptual targets, not simultaneous placements."
  value       = local.subscription_management_group_ids
}

output "deployment_mode" {
  description = "Whether this root is modelling one shared subscription or separate enterprise role subscriptions."
  value = var.allow_shared_subscription_ids ? "single-subscription" : (
    var.allow_logical_workload_subscription_ids ? "quota-limited" : "multi-subscription"
  )
}

output "logical_role_subscription_ids" {
  description = "Logical role-to-subscription map. In quota-limited mode the workload roles intentionally reuse the protected existing subscription."
  value       = var.subscription_ids
}

output "actual_subscription_placement" {
  description = "Subscription associations actually managed by Terraform. Empty until move_subscriptions_into_hierarchy is enabled."
  value = merge(
    {
      for role, association in azurerm_management_group_subscription_association.role : role => {
        subscription_id     = trimprefix(association.subscription_id, "/subscriptions/")
        management_group_id = association.management_group_id
      }
    },
    length(azurerm_management_group_subscription_association.single) == 0 ? {} : {
      single = {
        subscription_id     = trimprefix(azurerm_management_group_subscription_association.single[0].subscription_id, "/subscriptions/")
        management_group_id = azurerm_management_group_subscription_association.single[0].management_group_id
      }
    }
  )
}

output "activity_log_policy_assignment_id" {
  description = "Resource ID used to create or inspect remediation tasks for the Activity Log deployIfNotExists assignment."
  value       = var.log_analytics_workspace_id == null ? null : azurerm_management_group_policy_assignment.activity_log_to_law[0].id
}

output "activity_log_policy_identity_principal_id" {
  description = "Object ID of the Activity Log policy assignment's system-assigned identity."
  value       = var.log_analytics_workspace_id == null ? null : azurerm_management_group_policy_assignment.activity_log_to_law[0].identity[0].principal_id
}
