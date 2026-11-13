# Changelog

All notable changes to this repository are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases
use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Dedicated Azure SRE Agent instructions
  (`sre-agent-assets/sre-agent-instructions.md`) for Architecture Writer, Fleet
  Security & Patch Remediation, Retirement Readiness, and SRE Incident Response,
  linked from each use case README.
- Azure SRE Network Troubleshooting runnable demo: VNet Flow Logs, Traffic
  Analytics, independent Windows application-health evidence, read-only SRE
  Agent investigation, optional additive Connection Monitor, and separately
  approved operator fault/restoration/cleanup actions with offline validation.

- `CHANGELOG.md` and a changelog item in the pull request template.
- Dependabot coverage for Python (`pip`) and Docker base images.
- Status, limitations, cleanup, sample output, and reference sections in every
  use case README, as now required by `CONTRIBUTING.md`.

### Changed

- Retitled the root README to "Agentic ITOps Showcase: AI Agents for IT
  Operations" and updated the project name in CONTRIBUTING.
- The root README Owner column now lists each owner's full name, linked to
  their GitHub account, instead of a first name.
- Removed the `Tools/avmdemo` package and the planned `Tools/finops-intelligence`
  placeholder, and renumbered the root README catalogue to 01–09.
- Removed the root `docs/` folder (installation, architecture, and
  customization guides); each use case README is now the single source for its
  prerequisites, architecture, and customization.
- Renamed the repository from `AI-IT-tool-box` to `agentic-itops-showcase` and
  updated badge, security advisory, and clone links.
- Microsoft Fabric monitoring: discover dedicated capacities on each CU
  collection and bind `CapacitiesList` separately for each capacity in the
  notebook collector and read-only MCP. Reject partial query results, report
  missing CU coverage, and use the Power BI authentication audience.
- Microsoft Fabric monitoring: English and French guides distinguish Azure
  Reader from Fabric capacity permissions, identify the connector identity,
  explain managed-identity selection errors, and document paginated visibility
  checks and approval/audit requirements for privileged assignments.
- GitHub Actions in workflows and example blueprints are pinned to full commit
  SHAs.
- Microsoft Fabric monitoring: write actions are disabled until listed in
  `allowedActions`, which is empty in the example and enforced at approval time.
  Requests send a standard `User-Agent` instead of a skill attribution header.
  The English and French READMEs cover permissions, cost, and cleanup.
- Azure SRE Incident Response: live provisioning requires an ingress allow-list
  or an explicit public-ingress opt-in; Bicep defaults to internal ingress.
- Azure Incident Investigator: the demo documentation only claims the logs that
  are actually collected.
- Architecture writer: example output is attributed to the configured
  architecture agent, and the DR diagram layout overlap is fixed.

## [1.0.0] - 2026-10-16

### Added

- Initial public-ready catalogue of nine IT operations use cases under `Tools/`.
- MIT license, security policy, code of conduct, contributing guide, code
  owners, issue and pull request templates, and repository validation workflows.

## [1.1.0] - 2026-10-27

### Added

- AVM TF Synchronizer use case