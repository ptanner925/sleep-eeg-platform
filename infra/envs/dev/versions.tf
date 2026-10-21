terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # Phase 1: add the databricks provider for the unity_catalog module
    # databricks = { source = "databricks/databricks", version = "~> 1.0" }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    resource_group {
      # make down must always succeed; Databricks leaves a managed RG that Azure cleans up itself
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}
