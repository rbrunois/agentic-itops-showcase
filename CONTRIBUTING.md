# Contributing

Thank you for helping improve the Agentic ITOps Showcase. This
repository accepts improvements to existing use cases, runnable demos, and new
use cases that show how agents can safely support IT operations.

By participating, you agree to follow the [code of conduct](CODE_OF_CONDUCT.md).
Report security issues privately as described in [SECURITY.md](SECURITY.md).

## Add a use case

1. Open a [use case proposal](.github/ISSUE_TEMPLATE/use_case_proposal.md)
   issue to agree on scope before investing in a large contribution.
2. Create `Tools/<kebab-case-name>/README.md`. The README is the single
   operational document for the use case and must cover:
   - **What it is** and **who it is for**;
   - **Status** (runnable demo, design or guidance package, or **Planned**);
   - **Prerequisites**, including Azure services, permissions, and cost;
   - **Procedure** or quick start, with real commands run from a stated directory;
   - **Safety and approvals**: what is read-only and which actions need human approval;
   - **Expected output** and a **Sample output** (synthetic);
   - **Limitations**;
   - **Cleanup**: exact teardown steps when resources are deployed, or an
     explicit "not applicable" statement for documentation-only packages;
   - **References** to the Microsoft documentation the use case relies on.

   A use case may start as a README-only placeholder clearly marked
   **Planned**, but must not be described as usable until those sections exist.
3. Keep supporting documents, templates, examples, scripts, and assets beside
   the README (for example in `assets/`, `docs/`, `scripts/`, or `templates/`).
   Use kebab-case folder and file names.
4. Add the use case to the catalogue table and the use case types table in
   [README.md](README.md).
5. Add an owner entry to [.github/CODEOWNERS](.github/CODEOWNERS).
6. If the use case has automated checks, add a root workflow under
   `.github/workflows/` with a `paths` filter and least-privilege
   `permissions`. GitHub does not run workflows stored inside `Tools/`. Pin
   third-party actions to a full commit SHA with the version as a comment
   (for example `actions/checkout@<sha> # v7.0.1`); Dependabot keeps the pins
   current. Add new package manifests or Dockerfiles to
   [.github/dependabot.yml](.github/dependabot.yml).
7. Add an entry under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).

An optional `Tools/<name>/SKILL.md` manifest is supported for agent platforms
that consume skills. When present, it must contain YAML front matter with a
unique `name`, an intent-oriented `description`, and a non-empty `tools` list,
plus the sections enforced by the
[repository validation](.github/workflows/validate-repository.yml).

## Improve an existing use case

Keep the use case README and root catalogue in sync. Preserve sample
data conventions and update every reference when moving files or changing
identifiers. Avoid broad replacements that could break registry, control,
module, or fixture relationships.

When a use case is documented in several languages, English is canonical and
translations must be updated in the same pull request.

## Data and security rules

- Use synthetic data only: Contoso or Fabrikam names, `contoso.example`
  emails, and `00000000-0000-0000-0000-000000000000` for tenant and
  subscription IDs. Never commit real customer names, people, emails,
  hostnames, IP addresses, inventory exports, or screenshots of real
  environments.
- Never commit credentials, keys, tokens, connection strings, or generated
  files containing secrets.
- Make discovery and analysis read-only by default and request only the
  permissions required for the current step.
- Separate analysis and proposal generation from application or deployment.
- Require explicit human review for patches, pull requests, production changes,
  destructive operations, exceptions, and changes to security controls.
- Document every billable resource and provide cleanup steps.

## Tests and validation

Run the narrowest relevant fixture, mock scenario, or test suite. Validate JSON
and YAML, check local Markdown links, and run Terraform, Bicep, PowerShell, or
Node.js validation when those files change and the runtime is available.

The [repository validation workflow](.github/workflows/validate-repository.yml)
checks optional manifests, YAML, JSON, Python syntax, SVG accessibility, local
Markdown links, and nested Git metadata on every pull request. Use-case
workflows add behavioral checks. They complement rather than replace manual
testing.

## Pull requests

Keep pull requests focused and complete the
[pull request template](.github/pull_request_template.md): explain the user
value, changed behavior, security impact, validation performed, and known
limitations. Include representative sample output when a report shape changes.

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
