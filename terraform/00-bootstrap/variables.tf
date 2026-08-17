variable "management_subscription_id" {
  description = "Management subscription that owns the Terraform state storage account."
  type        = string
}

variable "prefix" {
  description = "Short lowercase prefix used in state resource names."
  type        = string
  default     = "alzlab"
}

variable "location" {
  description = "Azure region for the state resource group and storage account."
  type        = string
  default     = "australiaeast"
}

variable "allowed_ip_cidrs" {
  description = "Optional public IPv4 CIDRs allowed through the storage firewall. Empty permits the endpoint but still requires Microsoft Entra authentication."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to bootstrap resources."
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "terraform-state"
  }
}
