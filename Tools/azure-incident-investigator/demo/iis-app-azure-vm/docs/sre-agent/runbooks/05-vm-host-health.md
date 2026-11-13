# Runbook 05 — VM & host health

**Symptom:** a host is under resource pressure, missing from monitoring, or
behaving as if it rebooted. Use this when the concern is the **VM itself**
rather than a specific app symptom.

---

## Hypotheses

1. **CPU saturation** — a runaway process or genuine overload.
2. **Memory pressure** — low `Available MBytes`, paging.
3. **Disk full** — low `% Free Space` (logs, tempdb, updates).
4. **Agent/telemetry gap** — VM up but Azure Monitor Agent not reporting (blind spot).
5. **Unexpected reboot / dirty shutdown**.

---

## Investigate

### Step 1 — Telemetry gaps first (are we even blind?)
Run `kql-library.md` §0.3. A host with a stale `LastSeen` is either down or
its agent stopped — investigate that before trusting any "all green".

### Step 2 — Resource pressure sweep
Run `kql-library.md` §5.2 for a one-shot breach list, then §5.1 to trend the
offending counter on the specific host.

Reference thresholds:

| Counter | Watch | Act |
|---|---|---|
| `% Processor Time` | > 80 sustained | > 90 sustained |
| `Available MBytes` | < 1024 | < 512 |
| `% Free Space` | < 15 | < 10 |

### Step 3 — Reboots / power events
Run `kql-library.md` §5.3. Correlate any `1074`/`6008`/`41` with the symptom
timeline.

### Step 4 — System-log errors on the host
```kusto
Event
| where TimeGenerated > ago(6h)
| where Computer == "<COMPUTER>" and EventLog == "System" and EventLevelName == "Error"
| summarize count(), max(TimeGenerated) by Source, EventID, RenderedDescription
| order by count_ desc
```
Disk, storage-controller, or NIC errors here often underlie "the VM is weird".

---

## Remediate
- **CPU/mem:** find the top consumer (run-command `Get-Process | Sort CPU/WS -Desc | Select -First 5`); restart the offending service, or resize the VM if genuinely undersized.
- **Disk full:** clear the space hog (old logs, SQL backups, Windows Update cache); expand the disk if it's a real growth trend.
- **Agent gap:** restart `AzureMonitorAgent` service on the host; confirm heartbeat resumes.
```powershell
az vm run-command invoke -g <RG> --name <COMPUTER> --command-id RunPowerShellScript `
  --scripts "Restart-Service AzureMonitorAgent -ErrorAction SilentlyContinue; Get-Service AzureMonitorAgent"
```

## Report
[templates/rca-report.md](../templates/rca-report.md). Attach the §5.1
timechart; if this was a blind-spot (Step 1), record the detection gap.
