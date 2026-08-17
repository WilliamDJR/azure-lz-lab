terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  backend "azurerm" {}

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
  subscription_id = var.subscription_ids.management

  features {
    resource_group {
      # Lab safety: refuse to delete a resource group that still has resources
      # in it, so a stray `destroy` cannot silently eat something.
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "azurerm" {
  alias           = "connectivity"
  subscription_id = var.subscription_ids.connectivity
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "azurerm" {
  alias           = "identity"
  subscription_id = var.subscription_ids.identity
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "azurerm" {
  alias           = "security"
  subscription_id = var.subscription_ids.security
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "azurerm" {
  alias           = "corp_dev"
  subscription_id = var.subscription_ids.corp_dev
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "azurerm" {
  alias           = "sandbox"
  subscription_id = var.subscription_ids.sandbox
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
