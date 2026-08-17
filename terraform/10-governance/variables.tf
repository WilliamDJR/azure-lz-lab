variable "subscription_ids" {
  description = "Existing Azure subscription IDs mapped to their ALZ roles."
  type = object({
    management   = string
    connectivity = string
    identity     = string
    security     = string
    corp_dev     = string
    corp_prod    = string
    online_dev   = string
    online_prod  = string
    sandbox      = string
  })

  validation {
    condition = alltrue([
      for subscription_id in values(var.subscription_ids) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", subscription_id))
    ]) && length(distinct(values(var.subscription_ids))) == length(values(var.subscription_ids))
    error_message = "Every subscription ID must look like a GUID and each ALZ role must use a different subscription."
  }
}

variable "prefix" {
  description = "Short prefix for all management group names. Keep it unique in the tenant."
  type        = string
  default     = "alz"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,10}$", var.prefix))
    error_message = "prefix must be 2-10 lowercase alphanumeric/hyphen characters."
  }
}

variable "root_display_name" {
  description = "Display name of the intermediate root management group."
  type        = string
  default     = "ALZ Lab"
}

variable "allowed_locations" {
  description = "Regions workloads are permitted to deploy into. 'global' is required for resources such as DNS zones and Front Door."
  type        = list(string)
  default     = ["australiaeast", "australiasoutheast", "global"]
}

variable "move_subscriptions_into_hierarchy" {
  description = "Associate all role subscriptions with their target ALZ management groups. Keep false until the hierarchy and permissions have been reviewed."
  type        = bool
  default     = false
}

variable "budget_start_date" {
  description = "Optional first day of the current monthly budget period in RFC3339 format, for example 2026-08-01T00:00:00Z. Null disables subscription budgets."
  type        = string
  default     = null

  validation {
    condition     = var.budget_start_date == null || can(regex("^[0-9]{4}-[0-9]{2}-01T00:00:00Z$", var.budget_start_date))
    error_message = "budget_start_date must be null or the first day of a month in UTC, for example 2026-08-01T00:00:00Z."
  }
}

variable "default_monthly_budget" {
  description = "Default monthly budget amount for each subscription when budget_start_date is set."
  type        = number
  default     = 25
}

variable "monthly_budget_overrides" {
  description = "Optional monthly budget amounts keyed by subscription role."
  type        = map(number)
  default     = {}
}

variable "budget_contact_emails" {
  description = "Email addresses that receive budget notifications in addition to subscription Owners."
  type        = set(string)
  default     = []
}

variable "role_assignments" {
  description = "Optional least-privilege management-group role assignments keyed by a stable name."
  type = map(object({
    scope_key            = string
    principal_id         = string
    role_definition_name = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for assignment in values(var.role_assignments) :
      contains(["root", "platform", "identity", "management", "connectivity", "security", "landing_zones", "corp", "online", "sandbox"], assignment.scope_key)
    ])
    error_message = "Each role assignment scope_key must be a supported ALZ scope."
  }
}

variable "public_ip_policy_effect" {
  description = "Effect for the 'no public IP on NICs' custom policy. Start with Audit; switch to Deny once you understand the blast radius."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.public_ip_policy_effect)
    error_message = "public_ip_policy_effect must be Audit, Deny or Disabled."
  }
}

variable "log_analytics_workspace_id" {
  description = "Optional. Resource ID of the Log Analytics workspace created by the 20-platform root. When set, a deployIfNotExists policy streams subscription Activity Logs into it - this is the pattern ALZ uses to guarantee every subscription is observable by default."
  type        = string
  default     = null
}
