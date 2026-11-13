# Architecture report: Contoso `<workload>`

> **State:** Draft | Reviewed | Approved baseline
> **Evidence captured:** `<ISO-8601 timestamp>`
> **Scope:** `<subscriptions/resource groups/regions/services>`
> **Audience:** `<operations/architecture/security/audit>`
> **Baseline:** `<Git commit or "none">`
> **Relationship model version:** `<model version>`
> **Report schema version:** `<schema version>`

## Scope and exclusions

- **Included:** `<scope>`
- **Excluded:** `<scope and reason>`
- **Unavailable sources:** `<source and impact>`

## Evidence

| Source | Query or capability | Captured | Freshness | Notes |
| --- | --- | --- | --- | --- |
| Azure Resource Graph | `<sanitized query ID>` | `<timestamp>` | Current | No credentials retained |

## Inventory

| Resource | Type | Region | Resource group | Evidence state | Notes |
| --- | --- | --- | --- | --- | --- |
| `app-contoso-prod-001` | App Service | Canada Central | `rg-contoso-app-prod` | Observed | Synthetic example |

## Boundaries

| Boundary | Members | Evidence state | Source |
| --- | --- | --- | --- |
| `<region/VNet/subnet/resource group>` | `<resources>` | Observed | `<source>` |

## Relationships and flows

| From | To | Direction/purpose | State | Confidence | Evidence/rationale |
| --- | --- | --- | --- | --- | --- |
| `<source>` | `<target>` | `<application/DNS/replication>` | Observed/Inferred/Proposed | High/Medium/Low | `<source or rationale>` |

## Diagram

`<relative link to SVG, Mermaid, or draw.io source>`

## Validation

- [ ] Every in-scope inventory item is represented or explicitly omitted.
- [ ] Diagram and report use the same resource and relationship identifiers.
- [ ] Directional flows have evidence or an inference label.
- [ ] Boundaries, regions, and resource groups are consistent.
- [ ] No secrets or sensitive identifiers are present.
- [ ] Evidence freshness and unknowns are visible.

## Well-Architected review

| Pillar | Evidence-backed observation | Unknowns | Recommendation |
| --- | --- | --- | --- |
| Reliability | `<observation>` | `<unknown>` | `<proposal>` |
| Security | `<observation>` | `<unknown>` | `<proposal>` |
| Cost optimization | `<observation>` | `<unknown>` | `<proposal>` |
| Operational excellence | `<observation>` | `<unknown>` | `<proposal>` |
| Performance efficiency | `<observation>` | `<unknown>` | `<proposal>` |

## Unknowns and conflicts

1. `<question, owner, and evidence needed>`

## Recommendations

| Priority | Proposed change | Evidence | Approval owner | IaC requested |
| --- | --- | --- | --- | --- |
| `<P0-P3>` | `<recommendation>` | `<finding>` | `<owner>` | Yes/No |

## Optional IaC draft

`<not requested | approved draft path and validation status>`

No plan, apply, or deployment is authorized by this report.

## Change history

| Date | Baseline | Observed drift | Author/reviewer |
| --- | --- | --- | --- |
| `<date>` | `<commit>` | `<summary>` | `<role>` |
