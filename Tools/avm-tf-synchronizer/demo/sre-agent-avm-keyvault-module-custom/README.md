# sre-agent-avm-keyvault-module-custom

Vanilla internal Terraform module for Azure Key Vault. It is derived from the Azure Verified Module [`Azure/terraform-azurerm-avm-res-keyvault-vault` v0.10.2](https://github.com/Azure/terraform-azurerm-avm-res-keyvault-vault/tree/v0.10.2) and restructured to the internal template described in [TEMPLATE.md](TEMPLATE.md).

> **No security controls are enforced by this module.** Defaults are deliberately permissive. Remediation against the Key Vault controls in [contoso/sre-agent-avm-security-controls](https://github.com/contoso/sre-agent-avm-security-controls) is performed by the Azure SRE Agent via pull requests to this repository.

## Usage

```hcl
module "key_vault" {
  source = "git::https://github.com/contoso/sre-agent-avm-keyvault-module-custom.git?ref=v1.0.0"

  name                = "kv-app-dev-001"
  location            = "swedencentral"
  resource_group_name = "rg-app-dev"
  tenant_id           = data.azurerm_client_config.current.tenant_id

  environment = "dev"
  owner       = "sre-team"
  cost_center = "cc-1234"

  legacy_access_policies = {
    current_client = {
      object_id          = data.azurerm_client_config.current.object_id
      secret_permissions = ["Get", "List", "Set"]
    }
  }
}
```

A complete example is in [examples/default](examples/default/main.tf).

## Required inputs

| Name | Type | Description |
|------|------|-------------|
| `name` | `string` | Key Vault name. Must start with `kv-`, 3–24 alphanumerics/hyphens. |
| `location` | `string` | Azure region. |
| `resource_group_name` | `string` | Resource group of the Key Vault. |
| `tenant_id` | `string` | Entra ID tenant ID (lowercase GUID). |
| `environment` | `string` | `dev`, `test` or `prod`. |
| `owner` | `string` | Owning team/contact. |
| `cost_center` | `string` | Cost center. |

## Optional inputs

| Name | Default | Description |
|------|---------|-------------|
| `purge_protection_enabled` | `false` | Enable purge protection (cannot be disabled once enabled). |
| `public_network_access_enabled` | `true` | Allow public network access. |
| `soft_delete_retention_days` | `null` | Soft delete retention (7–90 days); `null` uses the Azure default. |
| `network_acls` | `null` | Firewall (`bypass`, `default_action`, `ip_rules`, `virtual_network_subnet_ids`); `null` means no firewall. |
| `legacy_access_policies_enabled` | `true` | Use vault access policies instead of Azure RBAC for the data plane. |
| `legacy_access_policies` | `{}` | Access policies to create (requires `legacy_access_policies_enabled = true`). |
| `private_endpoints` | `{}` | Private endpoints to create. |
| `diagnostic_settings` | `{}` | Diagnostic settings to create. |

Other optional inputs (`sku_name`, `role_assignments`, `keys`, `secrets`, `secrets_value`, `contacts`, `lock`, `tags`, `enabled_for_*`, `private_endpoints_manage_dns_zone_group`, `wait_for_rbac_before_*`) behave as in upstream AVM v0.10.2; see `variables.vault.tf`.

### Tags

All taggable resources receive `merge(var.tags, local.mandatory_tags)`; mandatory tags (`environment`, `owner`, `cost_center`, `managed_by = "terraform"`, `module = "sre-agent-avm-keyvault-module-custom"`) cannot be overridden.

## Outputs

`name`, `resource_id`, `uri`, `private_endpoints`, `keys`, `keys_resource_ids`, `secrets`, `secrets_resource_ids` (same as upstream; `keys`/`secrets` expose identifiers only).

## Differences from upstream

See `.avm-sync/mapping.yaml` and `.avm-sync/exclusions.yaml`. In short:

- Internal template: flat `resource.<area>.tf` / `variables.<area>.tf` layout, keys and secrets inlined (no submodules), no AVM telemetry.
- Mandatory tags (`environment`, `owner`, `cost_center`, `managed_by`, `module`) and the `kv-` naming convention.
- Permissive defaults: `purge_protection_enabled = false`, `network_acls = null`, `legacy_access_policies_enabled = true` (upstream: `true`, `{}` and `false`).

## Versioning

Releases are tagged `vX.Y.Z` (Semantic Versioning) and created automatically by [release-please](https://github.com/googleapis/release-please) from Conventional Commit messages merged to `main`. Pin the module with `?ref=vX.Y.Z`. See [CHANGELOG.md](CHANGELOG.md).
