# Runbook 01 — App up but no data

**Symptom:** the site and its navigation render fine, but data grids show
"No data available" and dashboard tiles read `0`. **No error banner, no HTTP
500.** This is the silent-failure class — the app swallows data-layer
exceptions and returns empty results.

> **Worked example — the lab's signature incident.** On-call `svc-oncall`
> intended to stop SQL on non-prod but connected to `PRD-SRVSQL01` (identical
> `sql1` short-name) and ran `Stop-Service MSSQLSERVER -Force`. The web tier
> kept serving pages; every data call returned an empty list. RCA below.

---

## Hypotheses (most → least likely for this class)

1. **Database engine is down** on the SQL host (service stopped/crashed).
2. **DB reachable but auth failing** — password/login change, disabled login.
3. **Network/DNS break** between web and DB tier (name resolves to wrong host, NSG, firewall).
4. **Schema/query failure** — missing table/column after a change.
5. **Connection pool exhaustion / timeouts** under load (see [04](04-app-slow.md)).

---

## Investigate

### Step 1 — Confirm and time-stamp the app degradation
Run `kql-library.md` §1.1 and §1.2. The `1001 → 1002` flip gives you the
incident start time and the affected web host. If there is **no** heartbeat at
all, jump to [05](05-vm-host-health.md) / [06](06-service-stopped.md) — the
activity task or VM may be down rather than the DB.

### Step 2 — Is the database engine running?
Run `kql-library.md` §2.2 with `ServiceDisplayName = "SQL Server (MSSQLSERVER)"`.
- A `7036 … stopped` on the SQL host at ~the same minute as the `1002` flip →
  **Hypothesis 1 confirmed.** Go to Step 5.
- No stop event → continue.

### Step 3 — Is the DB rejecting connections?
Run `kql-library.md` §3.1 and §3.2 on the SQL host.
- `18456` login-failure bursts → **Hypothesis 2** (credential/login issue).
- SQL error/warning events → schema or engine problem (**Hypothesis 4**).

### Step 4 — Rule out network/DNS
If SQL is running and not rejecting logins but the web tier still can't reach
it, suspect DNS or NSG. Check for a recent change ([07](07-unauthorized-change.md))
and validate that `sql1.<zone>` resolves to the **correct** environment's SQL
IP. (Wrong-zone resolution is a lab foot-gun.)

### Step 5 — Attribute the cause (who/what/when)
Run `kql-library.md` §4.3 (`Needle = "Stop-Service"`) then §4.4 to tie the
command to a logon session, and finally §6 for the one-shot timeline.

---

## Root-cause confirmation (lab example)

The §6 correlation query returns, in order:
`4624` logon of `svc-oncall` → `4688` `powershell.exe … Stop-Service MSSQLSERVER -Force`
on `PRD-SRVSQL01` → `7036` MSSQLSERVER **stopped** → `1002` degraded heartbeat on
`PRD-SRVIIS01`. That chain is the RCA.

---

## Remediate

**Restore service** (whichever tier is at fault):

```powershell
# Database engine down — restart it
az vm run-command invoke -g PRD-SREAgent-IISappAzureVM-01 --name PRD-SRVSQL01 `
    --command-id RunPowerShellScript --scripts "Start-Service MSSQLSERVER"
```

Data returns within 30–60 s as the web-tier connection pool warms. Confirm by
re-running §1.1 and watching the heartbeat flip back to `1001`.

**Preventive (write these into the RCA):**
- Alert on the `1001 → 1002` heartbeat flip and on `7036` stop of `MSSQLSERVER`.
- Make the app **surface** DB errors instead of returning empty lists.
- Disambiguate environments (distinct hostnames / env-confirm guard) so a
  "wrong host" action is far harder.

---

## Report
Use [templates/rca-report.md](../templates/rca-report.md). Timeline from §6;
one-line root cause = the confirmed trigger + the silent-failure design flaw.
