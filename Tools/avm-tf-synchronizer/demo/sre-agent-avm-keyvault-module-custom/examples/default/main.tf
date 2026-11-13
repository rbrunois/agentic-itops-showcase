terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.117, < 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  location = "swedencentral"
  name     = "rg-kv-example-${random_string.suffix.result}"
}

module "key_vault" {
  source = "../../"

  location            = azurerm_resource_group.this.location
  name                = "kv-example-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  environment = "dev"
  owner       = "sre-team"
  cost_center = "cc-0000"

  legacy_access_policies = {
    current_client = {
      object_id          = data.azurerm_client_config.current.object_id
      secret_permissions = ["Get", "List", "Set"]
    }
  }

  tags = {
    example = "default"
  }
}

output "key_vault_resource_id" {
  value = module.key_vault.resource_id
}

output "key_vault_uri" {
  value = module.key_vault.uri
}
