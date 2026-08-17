###############################################################################
# Core
###############################################################################

variable "subscription_id" {
  description = "Subscription to deploy the lab into."
  type        = string
}

variable "prefix" {
  description = "Short prefix used in every resource name."
  type        = string
  default     = "alz"
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
    owner       = "william"
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
# Read docs/COSTS.md before flipping any of them, and run
# scripts/destroy-expensive.sh when you finish a session.
###############################################################################

variable "enable_firewall" {
  description = "Deploy Azure Firewall + firewall policy + forced-tunnelling UDR on the spoke. ~A$1.50/hour plus data processing."
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
  description = "Deploy a VPN gateway in the hub. ~A$0.19/hour (VpnGw1) and takes 25-45 minutes to provision."
  type        = bool
  default     = false
}

variable "enable_simulated_onprem" {
  description = "Deploy a second VNet with its own VPN gateway and a VNet-to-VNet connection, to stand in for an on-premises site behind ExpressRoute/VPN. Doubles the gateway cost. Requires enable_vpn_gateway = true."
  type        = bool
  default     = false
}

variable "enable_test_vm" {
  description = "Deploy a Standard_B1s Linux VM in the spoke with NO public IP (~A$15/month). You reach it with 'az vm run-command', which needs no Bastion and no jump host - this is how you test private DNS resolution for free."
  type        = bool
  default     = true
}

###############################################################################
# Misc
###############################################################################

variable "vpn_shared_key" {
  description = "Pre-shared key for the simulated site-to-site connection."
  type        = string
  default     = "L4bSh4redKey-ChangeMe"
  sensitive   = true
}

variable "log_retention_days" {
  description = "Log Analytics retention. 30 days is the free-tier floor."
  type        = number
  default     = 30
}
