###############################################################################
# 10-governance
#
# Builds the "resource organization" and "governance" design areas of an Azure
# Landing Zone: a management group hierarchy plus the policy guardrails that
# hang off it.
#
# GCP mental model:
#   Management Group  ~= Folder
#   Subscription      ~= Project
#   Azure Policy      ~= Organization Policy (but far more capable:
#                        Azure Policy can also *remediate*, not just deny)
#
# Nothing in this file costs money. Deploy it and leave it running.
###############################################################################

###############################################################################
# 1. Management group hierarchy
#
# This mirrors the canonical Microsoft CAF shape. The important design point is:
#
#   You never assign policy to the Tenant Root Group. You create an
#   *intermediate root* one level below it and assign there, because the
#   Tenant Root Group cannot be deleted or easily rolled back, and every
#   subscription in the tenant - including ones you do not own - sits under it.
###############################################################################

resource "azurerm_management_group" "intermediate_root" {
  name         = var.prefix
  display_name = var.root_display_name
  # No parent_management_group_id => parented to the Tenant Root Group.
}

# --- Platform: subscriptions the PLATFORM TEAM owns -------------------------
resource "azurerm_management_group" "platform" {
  name                       = "${var.prefix}-platform"
  display_name               = "Platform"
  parent_management_group_id = azurerm_management_group.intermediate_root.id
}

resource "azurerm_management_group" "platform_identity" {
  name                       = "${var.prefix}-platform-identity"
  display_name               = "Identity"
  parent_management_group_id = azurerm_management_group.platform.id
}

resource "azurerm_management_group" "platform_management" {
  name                       = "${var.prefix}-platform-management"
  display_name               = "Management"
  parent_management_group_id = azurerm_management_group.platform.id
}

resource "azurerm_management_group" "platform_connectivity" {
  name                       = "${var.prefix}-platform-connectivity"
  display_name               = "Connectivity"
  parent_management_group_id = azurerm_management_group.platform.id
}

resource "azurerm_management_group" "platform_security" {
  name                       = "${var.prefix}-platform-security"
  display_name               = "Security"
  parent_management_group_id = azurerm_management_group.platform.id
}

# --- Landing zones: subscriptions APPLICATION TEAMS own ---------------------
resource "azurerm_management_group" "landing_zones" {
  name                       = "${var.prefix}-landingzones"
  display_name               = "Landing Zones"
  parent_management_group_id = azurerm_management_group.intermediate_root.id
}

# "Corp" = workloads that need private connectivity back to on-premises.
resource "azurerm_management_group" "corp" {
  name                       = "${var.prefix}-landingzones-corp"
  display_name               = "Corp"
  parent_management_group_id = azurerm_management_group.landing_zones.id
}

# "Online" = internet-facing workloads with no corporate network dependency.
resource "azurerm_management_group" "online" {
  name                       = "${var.prefix}-landingzones-online"
  display_name               = "Online"
  parent_management_group_id = azurerm_management_group.landing_zones.id
}

# --- Sandbox: deliberately OUTSIDE the landing-zone policy scope ------------
# This is a design decision worth being able to defend: sandbox subscriptions
# get looser policy so engineers can experiment, and in exchange they get no
# connectivity to the corporate network.
resource "azurerm_management_group" "sandbox" {
  name                       = "${var.prefix}-sandbox"
  display_name               = "Sandbox"
  parent_management_group_id = azurerm_management_group.intermediate_root.id
}

# --- Decommissioned: parking lot for subscriptions on their way out ---------
resource "azurerm_management_group" "decommissioned" {
  name                       = "${var.prefix}-decommissioned"
  display_name               = "Decommissioned"
  parent_management_group_id = azurerm_management_group.intermediate_root.id
}

###############################################################################
# 2. Subscription placement
#
# GCP equivalent: moving a project into a folder.
###############################################################################

locals {
  subscription_management_group_ids = {
    management   = azurerm_management_group.platform_management.id
    connectivity = azurerm_management_group.platform_connectivity.id
    identity     = azurerm_management_group.platform_identity.id
    security     = azurerm_management_group.platform_security.id
    corp_dev     = azurerm_management_group.corp.id
    corp_prod    = azurerm_management_group.corp.id
    online_dev   = azurerm_management_group.online.id
    online_prod  = azurerm_management_group.online.id
    sandbox      = azurerm_management_group.sandbox.id
  }

  role_assignment_scopes = {
    root          = azurerm_management_group.intermediate_root.id
    platform      = azurerm_management_group.platform.id
    identity      = azurerm_management_group.platform_identity.id
    management    = azurerm_management_group.platform_management.id
    connectivity  = azurerm_management_group.platform_connectivity.id
    security      = azurerm_management_group.platform_security.id
    landing_zones = azurerm_management_group.landing_zones.id
    corp          = azurerm_management_group.corp.id
    online        = azurerm_management_group.online.id
    sandbox       = azurerm_management_group.sandbox.id
  }
}

resource "azurerm_management_group_subscription_association" "role" {
  for_each = var.move_subscriptions_into_hierarchy ? var.subscription_ids : {}

  management_group_id = local.subscription_management_group_ids[each.key]
  subscription_id     = "/subscriptions/${each.value}"
}

resource "azurerm_role_assignment" "management_group" {
  for_each = var.role_assignments

  scope                = local.role_assignment_scopes[each.value.scope_key]
  principal_id         = each.value.principal_id
  role_definition_name = each.value.role_definition_name
}

###############################################################################
# 3. Guardrails - built-in policy: allowed locations
#
# Deny effect. This is the single most common first guardrail in any tenant:
# it stops data landing in a region you have no legal basis to use.
###############################################################################

resource "azurerm_management_group_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  display_name         = "Allowed locations for resources"
  management_group_id  = azurerm_management_group.intermediate_root.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  description          = "Restricts resource deployment to approved regions."

  parameters = jsonencode({
    listOfAllowedLocations = {
      value = var.allowed_locations
    }
  })
}

###############################################################################
# 4. Guardrails - custom policy: no public IPs on NICs
#
# The canonical "Corp" landing-zone control: workloads that have private
# connectivity back to on-prem must not also have a direct path to the
# internet, because that is how you build an accidental bridge around the
# corporate perimeter.
#
# Note this is assigned to the CORP management group only - Online landing
# zones are expected to have public IPs. That scoping decision is the whole
# reason the Corp/Online split exists.
###############################################################################

resource "azurerm_policy_definition" "deny_nic_public_ip" {
  name                = "${var.prefix}-deny-nic-public-ip"
  policy_type         = "Custom"
  mode                = "All"
  display_name        = "Network interfaces must not have a public IP address"
  management_group_id = azurerm_management_group.intermediate_root.id

  metadata = jsonencode({
    category = "Network"
    version  = "1.0.0"
  })

  parameters = jsonencode({
    effect = {
      type = "String"
      allowedValues = [
        "Audit",
        "Deny",
        "Disabled"
      ]
      defaultValue = "Audit"
      metadata = {
        displayName = "Effect"
        description = "Enable or disable the execution of the policy."
      }
    }
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Network/networkInterfaces"
        },
        {
          not = {
            field  = "Microsoft.Network/networkInterfaces/ipConfigurations[*].publicIpAddress.id"
            equals = ""
          }
        }
      ]
    }
    then = {
      effect = "[parameters('effect')]"
    }
  })
}

resource "azurerm_management_group_policy_assignment" "deny_nic_public_ip" {
  name                 = "deny-nic-public-ip"
  display_name         = "Corp workloads must not have public IPs on NICs"
  management_group_id  = azurerm_management_group.corp.id
  policy_definition_id = azurerm_policy_definition.deny_nic_public_ip.id

  parameters = jsonencode({
    effect = {
      value = var.public_ip_policy_effect
    }
  })
}

###############################################################################
# 5. Guardrails - deployIfNotExists: stream Activity Logs to Log Analytics
#
# This is the pattern that has no clean GCP equivalent and therefore the one
# most worth understanding. A deployIfNotExists policy does not just block a
# non-compliant resource - it DEPLOYS the missing configuration for you.
#
# Two implementation requirements:
#   1. The assignment needs a MANAGED IDENTITY (identity {} + location).
#   2. That identity needs an RBAC role at the assignment scope, otherwise
#      remediation silently fails with "insufficient permissions". This is the
#      classic ALZ troubleshooting question.
#
# Also note: deployIfNotExists only acts on NEW or RE-EVALUATED resources.
# Existing non-compliant resources need a REMEDIATION TASK to be kicked off.
###############################################################################

resource "azurerm_management_group_policy_assignment" "activity_log_to_law" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                 = "activity-log-to-law"
  display_name         = "Stream subscription Activity Logs to Log Analytics"
  management_group_id  = azurerm_management_group.intermediate_root.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/2465583e-4e78-4c15-b6be-a36cbc7c8b0f"
  location             = "australiaeast"

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    logAnalytics = {
      value = var.log_analytics_workspace_id
    }
  })
}

# Without this, the policy above will evaluate but never successfully remediate.
resource "azurerm_role_assignment" "policy_identity_monitoring_contributor" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  scope                = azurerm_management_group.intermediate_root.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_management_group_policy_assignment.activity_log_to_law[0].identity[0].principal_id
}
