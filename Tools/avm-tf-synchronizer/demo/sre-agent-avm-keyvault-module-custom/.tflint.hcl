plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# prevent_destroy blocks consumers from intentionally decommissioning a vault.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
