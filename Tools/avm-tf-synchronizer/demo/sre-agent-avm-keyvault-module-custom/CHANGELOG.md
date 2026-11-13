# Changelog

## 1.0.0 – Initial release based on AVM v0.10.2

- Derived from `Azure/terraform-azurerm-avm-res-keyvault-vault` v0.10.2 using the internal flat file template.
- Vanilla module: no security controls enforced; upstream inputs (`purge_protection_enabled`, `public_network_access_enabled`, `soft_delete_retention_days`, `network_acls`, `legacy_access_policies_enabled`, `legacy_access_policies`) are exposed with permissive defaults.
- `private_endpoints` and `diagnostic_settings` are optional.
- Added mandatory tags (`environment`, `owner`, `cost_center`, `managed_by`, `module`) and the `kv-` naming convention.
- Removed AVM telemetry and submodules (keys/secrets inlined).
- Added unit tests and CI (fmt, validate, test, tflint, sandbox plan) plus release-please.
