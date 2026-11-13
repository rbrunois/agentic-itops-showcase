# Incident report — `<incident title>` (LIVE / interim)

> Short status update posted while an incident is **still open**. Keep it
> factual and current; update the status line each time you learn something.
> For the full write-up after resolution, use
> [rca-report.md](rca-report.md).

---

**Status:** `<INVESTIGATING / IDENTIFIED / MITIGATING / MONITORING / RESOLVED>`
**Severity:** `<Sev1 / Sev2 / Sev3>`
**Environment:** `<PRD / NPRD>`
**Started (first impact):** `<UTC>` (`<local>`)
**Last updated:** `<UTC>`

---

## Current impact

`<One or two sentences: what is broken, for whom, right now.>`

## What we know

- `<Confirmed fact + evidence, e.g. "App heartbeat flipped to degraded (1002) at 15:47 on PRD-SRVIIS01.">`
- `<Confirmed fact + evidence>`

## Working hypothesis

`<Most likely root cause, and what we're doing to confirm it.>`

## Actions in progress

| Time (UTC) | Action | By | Result |
|---|---|---|---|
| `<t>` | `<e.g. Ran service-state query, found 7036 stop on PRD-SRVSQL01>` | `<agent>` | `<confirmed>` |
| `<t>` | `<e.g. Restarting MSSQLSERVER>` | `<>` | `<pending>` |

## Next update

`<time / trigger, e.g. "within 15 min or on state change">`
