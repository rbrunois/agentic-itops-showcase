# Internal module template

This module follows the internal Terraform template. It is derived from an Azure Verified Module (AVM) but deliberately uses a different layout. Keep this structure when syncing upstream changes (see `.avm-sync/mapping.yaml`).

## File layout (flat, root module only)

| File | Content |
|------|---------|
| `terraform.tf` | `terraform {}` block: Terraform and provider version constraints. |
| `locals.tf` | All locals, including `local.mandatory_tags` and `local.tags`. |
| `resource.<area>.tf` | Resources for one area: `resource.vault.tf`, `resource.access_policies.tf`, `resource.keys.tf`, `resource.secrets.tf`, `resource.private_endpoint.tf`. |
| `variables.vault.tf` | Inputs derived from upstream `variables.tf` (minus telemetry and any inputs removed by locked security controls). |
| `variables.custom.tf` | Internal-only inputs (`environment`, `owner`, `cost_center`). |
| `outputs.tf` | All outputs. |

- No `modules/` sub-directories: upstream submodules are inlined as resources.
- Upstream `main.<x>.tf` maps to `resource.<x>.tf`; `main.tf` maps to `resource.vault.tf`.

## Tags

- Every resource that accepts `tags` uses `local.tags` (or `merge(<per-object tags>, local.tags)`).
- `local.tags = merge(var.tags, local.mandatory_tags)` – mandatory tags always win.
- `local.mandatory_tags`: `environment`, `owner`, `cost_center`, `managed_by = "terraform"`, `module = "sre-agent-avm-keyvault-module-custom"`.

## Naming

- `var.name` must start with `kv-`, be 3–24 characters long and contain only alphanumerics and hyphens (plus the upstream Key Vault rules).

## Security controls

- When a security control is enforced in code, hard-code the value, remove or constrain any input that could weaken it, and record it in `.avm-sync/mapping.yaml` (`locked: true`, `value`, `control`).
- Add one `terraform test` assertion per enforced control in `tests/basic.tftest.hcl`.
- Mark locked values in one comment block at the top of the resource body, before the first attribute:

  ```hcl
  # Security controls locked by AVM TF Synchronizer (see .avm-sync/mapping.yaml):
  #   SC-KV-001 purge_protection_enabled = true
  ```

  Don't add trailing comments or comment lines between attributes; they break `terraform fmt` alignment.
- Code must be `terraform fmt` clean. CI runs `terraform fmt -check -recursive` and auto-formats `remediation/*` and `avm-sync/*` branches.

## Telemetry

- No AVM telemetry: no `modtm` provider, no `main.telemetry.tf`, no `enable_telemetry` variable.

## Sync metadata

- `.avm-sync/manifest.yaml` – upstream repository and last synced tag.
- `.avm-sync/mapping.yaml` – upstream → internal file/variable mapping and conventions.
- `.avm-sync/exclusions.yaml` – upstream content intentionally not carried over, with reason.

## Releases

- release-please owns `CHANGELOG.md` and `.release-please-manifest.json`; don't edit them by hand.
- PRs are squash-merged and the PR title becomes the commit message, so it must be a Conventional Commit (`fix:`, `feat:`, `fix!:`/`feat!:` for breaking changes). Put breaking-change details in a `BREAKING CHANGE:` footer in the PR body.
