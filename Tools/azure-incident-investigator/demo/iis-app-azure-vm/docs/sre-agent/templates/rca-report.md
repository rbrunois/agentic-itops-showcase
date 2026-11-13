# RCA report — `<incident title>`

> Post-incident root-cause analysis. Fill every field. Attach the KQL results
> that support each claim. Every root-cause statement must be backed by an
> event in the workspace (`<workspace-name>`), cited by
> `TimeGenerated` + `Computer` + `EventID`.

---

## Summary

| Field | Value |
|---|---|
| Incident ID | `<id>` |
| Severity | `<Sev1 / Sev2 / Sev3>` |
| Environment | `<PRD / NPRD>` |
| Affected service | `<e.g. Contoso Global HR portal>` |
| Detected at | `<UTC>` (`<local>`) |
| Root cause identified at | `<UTC>` |
| Resolved at | `<UTC>` |
| Customer impact duration | `<mm minutes>` |
| Author (agent/human) | `<name>` |

**One-line root cause:**
`<e.g. MSSQLSERVER was stopped on PRD-SRVSQL01 by svc-oncall at 15:47 local; the web tier silently returned empty result sets.>`

---

## Impact

- **What users saw:** `<e.g. Portal loaded but every data grid showed "No data available"; dashboard tiles read 0. No error banner.>`
- **Scope:** `<which env / hosts / how many users>`
- **What still worked:** `<e.g. site chrome, navigation, static content>`

---

## Timeline (UTC)

Populate from the correlation query (`kql-library.md` §6).

| Time | Host | Signal | Evidence (EventID / Source) |
|---|---|---|---|
| `<t0>` | `<host>` | `<actor logged on>` | `4624` |
| `<t1>` | `<host>` | `<destructive command run>` | `4688` |
| `<t2>` | `<host>` | `<service stopped>` | `7036` |
| `<t3>` | `<host>` | `<app heartbeat degraded>` | `1002 / ContosoHR-Activity` |
| `<t4>` | `<host>` | `<detected / alerted>` | `<alert rule>` |
| `<t5>` | `<host>` | `<remediation applied>` | `7036 (running)` |
| `<t6>` | `<host>` | `<recovery confirmed>` | `1001 / ContosoHR-Activity` |

---

## Root cause

`<Narrative. State the trigger, the mechanism, and why it produced the observed
symptom. Distinguish the trigger (e.g. wrong-host service stop) from the
contributing design flaw (e.g. app swallows SQL exceptions and returns empty
lists, hiding the outage).>`

**Evidence:**

- `<paste the decisive KQL result or a link to the query>`

---

## Contributing factors

- `<e.g. Identical DNS short-names (sql1) across PRD and NPRD enabled a wrong-host action.>`
- `<e.g. App has no health endpoint and swallows exceptions — outage was invisible from the UI.>`
- `<e.g. svc-oncall could stop MSSQLSERVER interactively (no change-control gate).>`

---

## Detection

- **How it was found:** `<alert / user report / agent sweep>`
- **Detection gap:** `<e.g. no alert on 1001→1002 heartbeat flip; MTTD was N min.>`

---

## Remediation

**Immediate (what restored service):**

- `<e.g. Start-Service MSSQLSERVER on PRD-SRVSQL01; data returned within 60 s.>`

**Preventive (stop recurrence):**

| Action | Owner | Type |
|---|---|---|
| `<Add alert on heartbeat 1001→1002 flip>` | `<>` | Detection |
| `<Add alert on SCM 7036 for MSSQLSERVER>` | `<>` | Detection |
| `<Distinct hostnames per env / env-confirm guard on destructive ops>` | `<>` | Prevention |
| `<Surface DB errors in the app instead of empty lists>` | `<>` | Prevention |
| `<Restrict svc-oncall service-control rights>` | `<>` | Hardening |

---

## Lessons learned

- **What went well:** `<>`
- **What went poorly:** `<>`
- **Where we got lucky:** `<>`
