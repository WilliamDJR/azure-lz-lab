###############################################################################
# Core
###############################################################################

variable "subscription_ids" {
  description = "Existing Azure subscription IDs mapped to their ALZ roles. In single-subscription mode, the same ID may be repeated when allow_shared_subscription_ids is true."
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
    ])
    error_message = "Every subscription ID must be a GUID."
  }
}

variable "allow_shared_subscription_ids" {
  description = "Permit all ALZ role keys to reference one existing subscription for the single-subscription learning track. Keep false for enterprise subscription isolation."
  type        = bool
  default     = false
}

variable "allow_logical_workload_subscription_ids" {
  description = "Permit four distinct platform subscriptions while the logical workload roles reuse one existing protected subscription. This is a quota-limited transition profile, not full subscription isolation."
  type        = bool
  default     = false
}

variable "prefix" {
  description = "Short prefix used in every resource name."
  type        = string
  default     = "alz"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,10}$", var.prefix))
    error_message = "prefix must be 2-10 lowercase alphanumeric/hyphen characters."
  }
}

variable "location" {
  description = "Primary region."
  type        = string
  default     = "australiaeast"
}

variable "tags" {
  description = "Tags applied to every resource. 'lab = true' makes cleanup queries trivial."
  type        = map(string)
  default = {
    lab         = "true"
    owner       = "platform-team"
    environment = "lab"
  }
}

###############################################################################
# Address space
#
# Non-overlapping RFC1918 allocation. In a real ALZ this comes out of a
# central IPAM allocation - overlapping spoke ranges is the single most
# expensive networking mistake an enterprise can make, because it cannot be
# fixed without re-addressing a live workload.
###############################################################################

variable "hub_address_space" {
  description = "Hub VNet CIDR."
  type        = string
  default     = "10.0.0.0/16"
}

variable "spoke_address_space" {
  description = "Corp spoke VNet CIDR."
  type        = string
  default     = "10.1.0.0/16"
}

variable "onprem_address_space" {
  description = "Simulated on-premises VNet CIDR."
  type        = string
  default     = "10.100.0.0/16"
}

###############################################################################
# Cost toggles
#
# Every switch below turns on something that bills by the hour. Default is OFF.
# Review current Azure pricing before flipping any of them, and run
# scripts/destroy-expensive.sh when you finish a session.
###############################################################################

variable "enable_firewall" {
  description = "Deploy Azure Firewall, Firewall Policy, and a forced-tunnelling UDR. This is continuously billed; verify current regional pricing first."
  type        = bool
  default     = false
}

variable "firewall_sku_tier" {
  description = "Basic is roughly a third of the price of Standard and is enough to see the traffic-inspection behaviour. Basic REQUIRES a management IP configuration and a dedicated AzureFirewallManagementSubnet."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.firewall_sku_tier)
    error_message = "firewall_sku_tier must be Basic, Standard or Premium."
  }
}

variable "enable_vpn_gateway" {
  description = "Deploy a continuously billed VpnGw1 gateway in the hub. Provisioning commonly takes tens of minutes."
  type        = bool
  default     = false
}

variable "enable_simulated_onprem" {
  description = "Deploy a second VNet with its own VPN gateway and a VNet-to-VNet connection, to stand in for an on-premises site behind ExpressRoute/VPN. Doubles the gateway cost. Requires enable_vpn_gateway = true."
  type        = bool
  default     = false
}

variable "enable_test_vm" {
  description = "Deploy a billed Standard_B1s Linux VM without a public IP. Use Azure Run Command to test private DNS without Bastion or a jump host."
  type        = bool
  default     = true
}

variable "enable_sentinel" {
  description = "Create a dedicated Security workspace and enable Microsoft Sentinel. Disabled by default because ingestion and enabled data connectors can consume credit."
  type        = bool
  default     = false
}

###############################################################################
# Misc
###############################################################################

variable "vpn_shared_key" {
  description = "Pre-shared key for the simulated site-to-site connection. Set it locally only when enable_simulated_onprem is true."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.vpn_shared_key == null || length(var.vpn_shared_key) >= 16
    error_message = "vpn_shared_key must be null or at least 16 characters."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention. 30 days is the free-tier floor."
  type        = number
  default     = 30
}
