# Changelog

All notable changes to this repository are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases
use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Azure SRE Agent — Camping Store (`Tools/azure-sre-camping-store`): self-contained
  React/.NET storefront, Bicep deployment and SRE onboarding, read-only custom
  agents and knowledge, approval-gated memory injection/recovery and optional
  GitHub sample issues, source diagnosis and review-only customer triage.
  Includes attribution/MIT notices, offline tests, scoped CI/Dependabot coverage,
  catalogue and site page. Existing Azure SRE Incident Response is unchanged.
  Preserves the current original Trailhead storefront's photographs, product
  pages, and shared sales/outage strip, with a Node presentation server,
  separate image-license credits, and offline presentation-server tests.

- Azure VM Lifecycle Transition (`Tools/azure-vm-lifecycle-transition`): Azure
  SRE Agent custom agents, skills, hooks, a tool access policy, and a weekly
  scheduled task that find VMs and scale sets on End of Life VM size series,
  propose a target family for each with evidence, check quota, zone
  availability, and Azure Policy, and report drift. Includes Resource Graph and
  Log Analytics queries, public lifecycle dates, a disposition record schema, a
  pilot runbook for approval-gated resizes, a billable demo lab with scoring
  scripts and lab results, offline tests, and a validation workflow.
- Repository branding and a GitHub Pages landing page (`docs/`): an interactive
  Azure SRE Agent workspace example across four use cases, the Trigger →
  Analyze → Approve → Apply operating model, the guardrails, and a filterable
  use case catalogue. Includes the logo, light and dark README banners, and a
  social preview image.
- Use case pages: each use case has a marketing page on the project site
  (problem, benefits, how it works, an interactive sample run, safety and fit),
  linked from the landing page catalogue. Each page opens with an architecture
  diagram drawn in the site style, and each catalogue card shows its owners as
  chips that link to their GitHub profiles. The site is static HTML in `docs/`,
  published by GitHub Pages from `main`.
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