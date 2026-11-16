# VM lifecycle transition: weekly drift report

<!-- Template for vm-lifecycle-coordinator scheduled runs. Replace every
<placeholder>, delete rows that don't apply, and keep the closing statement. -->

| Field | Value |
| --- | --- |
| Scope | `<subscriptions or management group>` |
| Run | `<yyyy-mm-dd hh:mm UTC>`, scheduled task `vm-lifecycle-weekly-drift-scan` |
| Compared with | `<previous run date or "first run">` |
| Lifecycle dates verified | `<evidence date from lifecycle-dates-authoritative.md>` |

## Summary

| Measure | This week | Last week | Change |
| --- | --- | --- | --- |
| Affected VMs and scale-set instances | `<n>` | `<n>` | `<+/-n>` |
| P0: retired, can no longer run | `<n>` | `<n>` | `<+/-n>` |
| P1: retiring within 12 months | `<n>` | `<n>` | `<+/-n>` |
| P2: retiring within 24 months | `<n>` | `<n>` | `<+/-n>` |
| P3: retiring later | `<n>` | `<n>` | `<+/-n>` |
| Complete disposition records | `<n of total>` | `<n of total>` | `<+/-n>` |
| Records with open data gaps | `<n>` | `<n>` | `<+/-n>` |

## Changes since the last run

| Change | Resource | Detail |
| --- | --- | --- |
| New in scope | `<name>` | `<series, retirement date, owner tag>` |
| Left scope | `<name>` | `<resized to, deleted, or moved>` |
| Priority changed | `<name>` | `<old priority to new priority>` |
| Disposition changed | `<name>` | `<old disposition to new disposition, and why>` |

## Landing risks

| Subscription | Region | Target family | vCPUs needed | Headroom vCPUs | Status |
| --- | --- | --- | --- | --- | --- |
| `<id>` | `<region>` | `<family>` | `<n>` | `<n>` | `<ok, short by n, or not offered in zone>` |

Quota authorizes consumption; it doesn't reserve capacity.

## Commitments expiring within 90 days

| Reservation or savings plan | Scope | Expiry | Covered series | Note |
| --- | --- | --- | --- | --- |
| `<name>` | `<scope>` | `<date>` | `<series>` | `<exchange or modernization note>` |

If reservation data isn't readable, replace the table with: "Not assessed: no read
access to reservations."

## Pilot and waves

| Item | Status | Next step | Owner |
| --- | --- | --- | --- |
| `<pilot or wave>` | `<status>` | `<next step>` | `<owner>` |

## Data gaps

- `<subscriptions not readable, VMs without VM insights, missing owner tags, unknown workload classes>`

## Actions for owners

| Owner | Action | Due |
| --- | --- | --- |
| `<owner>` | `<action>` | `<date>` |

---

Read-only report. Targets are family-level proposals that need owner validation
and a benchmark. No prices or percentages are stated. Nothing was submitted,
bought, or changed.
