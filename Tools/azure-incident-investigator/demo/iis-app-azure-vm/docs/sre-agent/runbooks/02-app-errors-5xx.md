# Runbook 02 — App errors / HTTP 5xx

**Symptom:** the app throws — HTTP 500, ASP.NET exception ("yellow screen"),
or pages that partially render then fail. Unlike [01](01-app-up-no-data.md),
the failure is **visible**.

---

## Hypotheses

1. **Bad configuration** — malformed `Web.config`, unresolved placeholder in
   the connection string (e.g. `##DB_PASSWORD##` left un-tokenized).
2. **App pool / worker process crash** — `w3wp.exe` faulting (`.NET Runtime`
   or `Application Error` events).
3. **Unhandled data-layer error** that isn't swallowed (rare here by design).
4. **Dependency failure surfaced as 5xx** — e.g. auth handshake to SQL failing
   hard rather than timing out.

---

## Investigate

### Step 1 — App/runtime errors on the web host
```kusto
Event
| where TimeGenerated > ago(4h)
| where Computer == "<WEB_HOST>"
| where EventLog == "Application" and EventLevelName == "Error"
| where Source in (".NET Runtime", "ASP.NET 4.0.30319", "Application Error", "W3SVC-WP", "IIS AspNetCore Module V2")
| project TimeGenerated, Source, EventID, RenderedDescription
| order by TimeGenerated desc
```
Look for `.NET Runtime` / `Application Error` (unhandled exception, faulting
module) — that is Hypothesis 2/3.

### Step 2 — App pool / worker-process crashes (WAS)
```kusto
Event
| where TimeGenerated > ago(4h)
| where Source == "Microsoft-Windows-WAS" or Source == "WAS"
| project TimeGenerated, Computer, EventID, RenderedDescription
| order by TimeGenerated desc
```
Repeated `5011` / `5009` (worker process terminated) = app pool crash-looping.

### Step 3 — Configuration cause
The classic lab failure is a plaintext-config or unresolved token. Verify on
the web VM (run-command) that `Web.config` has a real password, not a
placeholder:
```powershell
az vm run-command invoke -g <RG> --name <WEB_HOST> --command-id RunPowerShellScript `
  --scripts "Select-String -Path C:\inetpub\ContosoGlobalHR\Web.config -Pattern '##|Password=' | Select-Object -First 5"
```
If a `##...##` token is present, re-run `Deploy-Lab.ps1` (re-tokenizes config).

### Step 4 — Rule out a hard SQL-auth failure
Run `kql-library.md` §3.2 (`18456`). Hard login failures can surface as 500s
if a code path doesn't swallow them.

---

## Remediate
- **Config fix:** correct `Web.config`, `iisreset` (or recycle the app pool),
  re-test.
- **App pool crash:** recycle the pool; if crash-looping, capture the faulting
  module from Step 1 before restarting.
```powershell
az vm run-command invoke -g <RG> --name <WEB_HOST> --command-id RunPowerShellScript `
  --scripts "Restart-WebAppPool -Name DefaultAppPool; iisreset /status"
```

## Report
Use [templates/incident-report.md](../templates/incident-report.md) while
mitigating, then [templates/rca-report.md](../templates/rca-report.md).
Cite the faulting event from Step 1/2 as evidence.
