terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  # azurerm v4 requires an explicit subscription id (or ARM_SUBSCRIPTION_ID env var).
  # Management groups live at TENANT scope, but the provider still needs a
  # subscription to authenticate against. This is the #1 gotcha when people
  # first run ALZ code.
  subscription_id = var.subscription_id
  features {}
}
