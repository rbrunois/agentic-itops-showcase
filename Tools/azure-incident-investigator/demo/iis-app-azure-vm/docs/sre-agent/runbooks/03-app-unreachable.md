# Runbook 03 — App unreachable / down

**Symptom:** the site times out or refuses the connection — the browser never
gets a page (not even an error page). The problem is at the **host, web
server, or network** layer, before the app runs.

---

## Hypotheses

1. **Web VM is stopped/deallocated or rebooting** (auto-shutdown fired, crash, patch reboot).
2. **W3SVC / WWW Publishing Service or the app pool is stopped**.
3. **Network path blocked** — NSG rule, DNS not resolving, wrong IP.
4. **Host resource exhaustion** so severe the VM is unresponsive (see [05](05-vm-host-health.md)).

---

## Investigate

### Step 1 — Is the VM alive and reporting?
Run `kql-library.md` §0.3 (Heartbeat). A gap for the web host = agent/VM down.
Cross-check power state:
```powershell
az vm get-instance-view -g <RG> -n <WEB_HOST> --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus" -o tsv
```
If `deallocated`/`stopped` → **Hypothesis 1**. (Auto-shutdown at 22:00 Toronto
is the usual lab cause.)

### Step 2 — Recent reboot / shutdown?
Run `kql-library.md` §5.3. A `1074`/`6008`/`41` near the outage explains an
unexpected drop.

### Step 3 — Is the web server service up?
Run `kql-library.md` §2.2 with `ServiceDisplayName = "World Wide Web Publishing Service"`.
A `7036 … stopped` for W3SVC = **Hypothesis 2**.

### Step 4 — Reachability / network
From a peer VM (run-command), test the path and DNS:
```powershell
az vm run-command invoke -g <RG> --name <WKS_HOST> --command-id RunPowerShellScript `
  --scripts "Resolve-DnsName app1.contoso.com; Test-NetConnection app1.contoso.com -Port 80 | Format-List RemoteAddress,TcpTestSucceeded"
```
`TcpTestSucceeded : False` with a good IP = NSG/firewall/service. Wrong/blank
IP = DNS (**Hypothesis 3**).

---

## Remediate
```powershell
# VM stopped — start it (allow ~90s)
az vm start -g <RG> -n <WEB_HOST>

# Web service/app pool stopped — start them
az vm run-command invoke -g <RG> --name <WEB_HOST> --command-id RunPowerShellScript `
  --scripts "Start-Service W3SVC; Start-WebAppPool -Name DefaultAppPool; iisreset /status"
```
Re-test with the smoke probe from [demo-script §2.2](../../demo-script.md).

## Report
[templates/incident-report.md](../templates/incident-report.md) while down;
[templates/rca-report.md](../templates/rca-report.md) after. Note MTTD if
auto-shutdown or an unmonitored reboot caused it.
