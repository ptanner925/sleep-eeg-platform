locals {
  tags = {
    project   = var.prefix
    owner     = var.owner
    env       = "dev"
    lifecycle = "ephemeral" # destroyed by `make down` every session
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.prefix}-dev"
  location = var.location
  tags     = local.tags
}

# ---- Phase 1: wire the modules in this order (see infra/modules/*/README.md) ----
# module "network"       { source = "../../modules/network" ... }
# module "storage"       { source = "../../modules/storage" ... }
# module "workspace"     { source = "../../modules/workspace" ... }
# module "unity_catalog" { source = "../../modules/unity_catalog" ... }
