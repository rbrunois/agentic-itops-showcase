mock_provider "azurerm" {}
mock_provider "time" {}

variables {
  location            = "swedencentral"
  name                = "kv-sre-test-01"
  resource_group_name = "rg-kv-test"
  tenant_id           = "00000000-0000-0000-0000-000000000000"
  environment         = "dev"
  owner               = "sre-team"
  cost_center         = "cc-0000"
  tags = {
    environment = "should-be-overridden"
    extra       = "kept"
  }
}

run "mandatory_tags_and_name" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.name == "kv-sre-test-01"
    error_message = "The Key Vault name must be passed through from var.name."
  }

  assert {
    condition = alltrue([
      azurerm_key_vault.this.tags["environment"] == "dev",
      azurerm_key_vault.this.tags["owner"] == "sre-team",
      azurerm_key_vault.this.tags["cost_center"] == "cc-0000",
      azurerm_key_vault.this.tags["managed_by"] == "terraform",
      azurerm_key_vault.this.tags["module"] == "sre-agent-avm-keyvault-module-custom",
      azurerm_key_vault.this.tags["extra"] == "kept",
    ])
    error_message = "Mandatory tags must be present and take precedence over user supplied tags."
  }
}

run "invalid_environment" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}

run "bad_name_prefix" {
  command = plan

  variables {
    name = "vault-sre-test"
  }

  expect_failures = [var.name]
}

run "name_too_long" {
  command = plan

  variables {
    name = "kv-abcdefghijklmnopqrstuv"
  }

  expect_failures = [var.name]
}
