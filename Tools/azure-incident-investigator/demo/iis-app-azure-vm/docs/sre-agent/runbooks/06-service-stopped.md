# Runbook 06 — Service stopped / crashed

**Symptom:** a Windows service that should be running is down — SQL Server
(`MSSQLSERVER`), IIS (`W3SVC`), the activity task's host, or the monitoring
agent. Generalizes the lab's signature incident to **any** service.

---

## Hypotheses

1. **Deliberately stopped** by a person/script (`Stop-Service`, `net stop`, SCM UI).
2. **Crashed** (faulting → SCM restarts or leaves it stopped).
3. **Failed to start after reboot** (dependency, start-type set to Disabled).
4. **Start-type tampered** (`7040` → Disabled) so it won't come back.

---

## Investigate

### Step 1 — Confirm the stop and its time
Run `kql-library.md` §2.2 with the service display name:

| Service | `ServiceDisplayName` |
|---|---|
| SQL Server | `SQL Server (MSSQLSERVER)` |
| IIS | `World Wide Web Publishing Service` |
| Monitor agent | `Azure Monitor Agent` |

A `7036 … stopped` gives the exact timestamp and host.

### Step 2 — Stopped on purpose, or crashed?
- Run `kql-library.md` §4.3 with `Needle = "Stop-Service"` (also try
  `"net stop"`, the service name). A matching `4688` near the stop time =
  **deliberate** (Hypothesis 1) → go to Step 4 to attribute.
- No such command, but an `Application Error`/`.NET Runtime` fault or SQL error
  just before = **crash** (Hypothesis 2).

### Step 3 — Was it disabled?
Run `kql-library.md` §2.3 (`7040`). A change to **Disabled** means a plain
restart won't hold — re-enable the start type first.

### Step 4 — Attribute (who / from where)
Run `kql-library.md` §4.4 to bind the `4688` command to the `4624` logon
session (account + logon type — `10` = RDP/Bastion). This is your actor.

---

## Remediate
```powershell
# Re-enable if it was disabled, then start
az vm run-command invoke -g <RG> --name <HOST> --command-id RunPowerShellScript `
  --scripts "Set-Service <ServiceName> -StartupType Automatic; Start-Service <ServiceName>; Get-Service <ServiceName>"
```
Confirm recovery via the relevant app signal (e.g. §1.1 heartbeat back to
`1001` after restarting `MSSQLSERVER`).

**Preventive:** alert on `7036` stop for critical services; gate destructive
service-control behind change-control; least-privilege the operator account.

## Report
[templates/rca-report.md](../templates/rca-report.md). If deliberate, this
overlaps [07](07-unauthorized-change.md) — include the actor attribution.
