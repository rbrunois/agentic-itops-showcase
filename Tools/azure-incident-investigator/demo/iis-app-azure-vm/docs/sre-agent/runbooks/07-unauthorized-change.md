# Runbook 07 — Unauthorized / suspicious change

**Symptom:** "who did what, when, and from where?" Use this to attribute a
change (a stopped service, a config edit, an unexpected logon) to an actor and
session — whether investigating an incident cause or a security concern.

> **Lab example:** attributing the SQL stop to `svc-oncall` who connected to
> `PRD-SRVSQL01` (thinking it was non-prod) via Bastion and ran
> `Stop-Service MSSQLSERVER -Force`.

---

## What the lab collects for attribution

Security auditing is limited to `4624` (logon), `4634` (logoff), and `4688`
(process creation **with command line**) in the **`Event`** table
(`EventLog == "Security"`). That is enough to reconstruct *who logged on where*
and *what commands they ran*.

---

## Investigate

### Step 1 — Bracket the change
Establish the change time from the effect (e.g. `7036` service stop via
`kql-library.md` §2.1, or the `1002` heartbeat flip via §1.1). Everything below
narrows to a window around that moment.

### Step 2 — Who was logged on?
Run `kql-library.md` §4.1. Filter to the affected host and the window. Note the
**account** and **logon type** (`10` = RDP/Bastion, `2` = console, `3` =
network). Machine accounts (ending `$`) and `SYSTEM` are already excluded.

### Step 3 — What commands did they run?
Run `kql-library.md` §4.2 for all process-creation on the host, or §4.3 to hunt
a specific action (`Stop-Service`, `net stop`, `Disable-`, `shutdown`,
`Remove-Item`, `reg`, `sc.exe`). The `4688` command line is the smoking gun.

### Step 4 — Tie command → session → actor
Run `kql-library.md` §4.4 to join the `4688` action to the originating `4624`
logon on the same host, confirming the actor and their entry method.

### Step 5 — Assess authorization
- Was this account **expected** to act on this host? (`svc-oncall` on **PRD**
  vs. the intended NPRD is the lab's "unauthorized-by-mistake" case.)
- Did the account have more privilege than needed for its role?

---

## Remediate / follow-up
- Reverse the change (see the matching runbook — e.g. [06](06-service-stopped.md) to restart a service).
- If credentials may be compromised, rotate them and review the account's other logons:
```kusto
Event
| where TimeGenerated > ago(7d)
| where EventID == 4624 and RenderedDescription has "<ACCOUNT>"
| extend LogonType = extract(@"Logon Type:\s+(\d+)", 1, RenderedDescription)
| project TimeGenerated, Computer, LogonType
| order by TimeGenerated desc
```
- **Preventive:** least-privilege the operator account; require env-confirmation
  or change-control for destructive actions; alert on `4688` command lines
  matching a destructive-verb watchlist.

## Report
[templates/rca-report.md](../templates/rca-report.md) — populate the timeline
(§6) and the "Contributing factors" section with the authorization gap. Keep
attribution factual: cite the `4624`/`4688` events by `TimeGenerated`, not
assumptions.
