terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    resource_group {
      # Lab safety: refuse to delete a resource group that still has resources
      # in it, so a stray `destroy` cannot silently eat something.
      prevent_deletion_if_contains_resources = true
    }
  }
}
