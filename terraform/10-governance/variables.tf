variable "subscription_id" {
  description = "Subscription used to authenticate the provider, and (optionally) the subscription moved into a landing-zone management group."
  type        = string
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

variable "move_subscription_into_hierarchy" {
  description = "Move var.subscription_id under the Corp landing-zone management group. Set false on the first run if you want to inspect the hierarchy before moving anything."
  type        = bool
  default     = false
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
