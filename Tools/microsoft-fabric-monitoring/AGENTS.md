# Contributor and AI agent guidance

These rules apply to anyone, human or AI coding agent, changing the Microsoft
Fabric monitoring accelerator in this folder.

## Rules

- Keep the shared core free of tenant, subscription, workspace, capacity, item,
  semantic model, and report IDs.
- Put customer values only in `config/client.parameters.yaml`, which is ignored.
- Preserve separate French and English deliverables. `README.en.md` is
  canonical; update `README.fr.md` in the same change.
- Keep the agent read-only by default. Never add a write operation without the
  approval guard and an audit record.
- Surface API errors and schema drift. Honor `Retry-After`.
- Generate PBIR with `scripts/generate-report.mjs`, then validate both reports.
- Validate TMDL before publishing.
- Update `docs/solution.fr.md` and `docs/solution.en.md` for behavior changes.
- Run `scripts/validate.ps1` before submitting a change. See the
  [prerequisites](README.en.md#prerequisites).
