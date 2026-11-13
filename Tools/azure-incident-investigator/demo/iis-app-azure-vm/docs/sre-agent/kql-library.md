# KQL query library

Reusable, copy-paste queries for the Contoso HR lab workspace
(the lab Log Analytics workspace) and any IIS + SQL-on-VM workload that
streams to the **`Event`**, **`Perf`**, and **`Heartbeat`** tables.

**Conventions**
- Replace `<COMPUTER>` with a VM name (e.g. `PRD-SRVIIS01`) or drop the filter
  to search fleet-wide.
- Adjust the lookback (`ago(4h)`) to bracket the incident.
- Times are UTC in the workspace; the lab runs Toronto time — convert when
  narrating (`datetime_utc_to_local(TimeGenerated, "America/Toronto")`).

---

## 0. First-pass sweep (run these first on any incident)

### 0.1 Error & warning firehose across both logs

```kusto
Event
| where TimeGenerated > ago(4h)
| where EventLog in ("System", "Application")
| where EventLevelName in ("Error", "Warning")
| project TimeGenerated, Computer, EventLog, Source, EventID, EventLevelName, RenderedDescription
| order by TimeGenerated desc
```

### 0.2 Timeline of state-changing events (service + security)

```kusto
Event
| where TimeGenerated > ago(4h)
| where EventID in (7036, 7040, 4624, 4688)
| project TimeGenerated, Computer, EventLog, EventID, RenderedDescription
| order by TimeGenerated asc
```

### 0.3 Which VMs are even reporting? (agent liveness)

```kusto
Heartbeat
| where TimeGenerated > ago(1h)
| summarize LastSeen = max(TimeGenerated) by Computer
| extend MinutesSinceLastHeartbeat = datetime_diff("minute", now(), LastSeen)
| order by MinutesSinceLastHeartbeat desc
```

---

## 1. Application health (Contoso HR heartbeat)

### 1.1 Healthy → degraded transition (the earliest outage signal)

```kusto
Event
| where TimeGenerated > ago(6h)
| where Source == "ContosoHR-Activity" and EventID in (1001, 1002)
| extend State = iff(EventID == 1001, "healthy", "degraded")
| summarize count() by bin(TimeGenerated, 5m), Computer, State
| order by TimeGenerated asc
```

Read it: a clean flip from `healthy` to `degraded` marks the moment the web
tier lost its database. The first `degraded` bin ≈ incident start.

### 1.2 Exact minute the heartbeat degraded

```kusto
Event
| where TimeGenerated > ago(6h)
| where Source == "ContosoHR-Activity" and EventID == 1002
| summarize FirstDegraded = min(TimeGenerated), LastDegraded = max(TimeGenerated) by Computer
```

### 1.3 Is the heartbeat missing entirely? (task not running vs. degraded)

```kusto
Event
| where TimeGenerated > ago(2h)
| where Source == "ContosoHR-Activity"
| summarize LastBeat = max(TimeGenerated) by Computer
| extend MinutesSinceBeat = datetime_diff("minute", now(), LastBeat)
```

---

## 2. Service state (SCM 7036 / 7040)

### 2.1 All service start/stop transitions

```kusto
Event
| where TimeGenerated > ago(6h)
| where EventID == 7036 and Source == "Service Control Manager"
| extend State = extract(@"entered the (\w+) state", 1, RenderedDescription)
| project TimeGenerated, Computer, RenderedDescription, State
| order by TimeGenerated desc
```

### 2.2 A specific service stopping (parameterized — default: SQL Server)

```kusto
let ServiceDisplayName = "SQL Server (MSSQLSERVER)";   // e.g. "World Wide Web Publishing Service"
Event
| where TimeGenerated > ago(6h)
| where EventID == 7036 and RenderedDescription has ServiceDisplayName
| extend State = extract(@"entered the (\w+) state", 1, RenderedDescription)
| project TimeGenerated, Computer, State, RenderedDescription
| order by TimeGenerated asc
```

### 2.3 Service set to Disabled / start-type tampering

```kusto
Event
| where TimeGenerated > ago(24h)
| where EventID == 7040 and Source == "Service Control Manager"
| project TimeGenerated, Computer, RenderedDescription
| order by TimeGenerated desc
```

---

## 3. SQL Server errors (Application log)

### 3.1 SQL engine errors, login failures, deadlocks

```kusto
Event
| where TimeGenerated > ago(6h)
| where Source in ("MSSQLSERVER", "MSSQL$MSSQLSERVER")
| where EventLevelName in ("Error", "Warning")
| project TimeGenerated, Computer, EventID, EventLevelName, RenderedDescription
| order by TimeGenerated desc
```

### 3.2 Login failures only (event 18456 — bad password / disabled login)

```kusto
Event
| where TimeGenerated > ago(6h)
| where EventID == 18456
| project TimeGenerated, Computer, RenderedDescription
| order by TimeGenerated desc
```

---

## 4. Who did what (Security 4624 / 4688)

### 4.1 Interactive / remote logons around the incident

```kusto
Event
| where TimeGenerated > ago(6h)
| where EventID == 4624
| extend Account   = extract(@"Account Name:\s+([^\r\n]+)", 1, RenderedDescription)
| extend LogonType = extract(@"Logon Type:\s+(\d+)", 1, RenderedDescription)
| where Account !endswith "$" and Account !in ("SYSTEM", "-")
| project TimeGenerated, Computer, Account, LogonType, RenderedDescription
| order by TimeGenerated desc
```

Logon types worth knowing: `2` = interactive/console, `3` = network,
`7` = unlock, `10` = RemoteInteractive (RDP/Bastion).

### 4.2 Process-creation with command line — pin the destructive action

```kusto
Event
| where TimeGenerated > ago(6h)
| where EventID == 4688
| extend NewProcess = extract(@"New Process Name:\s+([^\r\n]+)", 1, RenderedDescription)
| extend CmdLine    = extract(@"Process Command Line:\s+([^\r\n]+)", 1, RenderedDescription)
| extend Actor      = extract(@"Account Name:\s+([^\r\n]+)", 1, RenderedDescription)
| project TimeGenerated, Computer, Actor, NewProcess, CmdLine
| order by TimeGenerated desc
```

### 4.3 Hunt a specific destructive command (parameterized)

```kusto
let Needle = "Stop-Service";   // e.g. "Disable-", "shutdown", "net stop", "Remove-Item"
Event
| where TimeGenerated > ago(12h)
| where EventID == 4688 and RenderedDescription has Needle
| extend Actor   = extract(@"Account Name:\s+([^\r\n]+)", 1, RenderedDescription)
| extend CmdLine = extract(@"Process Command Line:\s+([^\r\n]+)", 1, RenderedDescription)
| project TimeGenerated, Computer, Actor, CmdLine
| order by TimeGenerated asc
```

### 4.4 Attribute an actor to a logon session (correlate 4688 → 4624)

```kusto
let window = ago(6h);
let logons =
    Event
    | where TimeGenerated > window and EventID == 4624
    | extend Account = extract(@"Account Name:\s+([^\r\n]+)", 1, RenderedDescription)
    | project LogonTime = TimeGenerated, Computer, Account;
Event
| where TimeGenerated > window and EventID == 4688
| extend Actor   = extract(@"Account Name:\s+([^\r\n]+)", 1, RenderedDescription)
| extend CmdLine = extract(@"Process Command Line:\s+([^\r\n]+)", 1, RenderedDescription)
| project ActionTime = TimeGenerated, Computer, Actor, CmdLine
| join kind=inner logons on Computer, $left.Actor == $right.Account
| where ActionTime between (LogonTime .. (LogonTime + 4h))
| project ActionTime, Computer, Actor, LogonTime, CmdLine
| order by ActionTime desc
```

---

## 5. Host & performance

### 5.1 CPU / memory / disk trend for a host

```kusto
Perf
| where TimeGenerated > ago(6h)
| where Computer == "<COMPUTER>"
| where CounterName in ("% Processor Time", "Available MBytes", "% Free Space")
| summarize avg(CounterValue) by bin(TimeGenerated, 5m), CounterName
| render timechart
```

### 5.2 Resource-pressure breaches (thresholds)

```kusto
Perf
| where TimeGenerated > ago(1h)
| summarize CpuPct = avgif(CounterValue, CounterName == "% Processor Time"),
            FreeMB = avgif(CounterValue, CounterName == "Available MBytes"),
            FreeDiskPct = avgif(CounterValue, CounterName == "% Free Space")
          by Computer
| extend Pressure = case(
        CpuPct > 90,      "CPU saturated",
        FreeMB < 512,     "Low memory",
        FreeDiskPct < 10, "Low disk",
        "ok")
| where Pressure != "ok"
```

### 5.3 Unexpected reboots / dirty shutdowns

```kusto
Event
| where TimeGenerated > ago(24h)
| where EventID in (6005, 6006, 6008, 1074, 41)
| project TimeGenerated, Computer, EventID, RenderedDescription
| order by TimeGenerated desc
```

`6005` = event log started (boot), `6006` = clean shutdown, `6008` = dirty
shutdown, `1074` = initiated shutdown/restart, `41` = unexpected power loss.

---

## 6. Correlation — one-shot incident timeline

Stitches app degradation, service stops, and the actor's command into a single
ordered story. This is the query that produces the RCA narrative.

```kusto
let window = ago(6h);
union
    (Event | where TimeGenerated > window and Source == "ContosoHR-Activity" and EventID == 1002
        | extend Kind = "APP degraded", Detail = strcat(Computer, ": heartbeat 1002")),
    (Event | where TimeGenerated > window and EventID == 7036 and RenderedDescription has "SQL Server (MSSQLSERVER)"
        | extend Kind = "SVC state", Detail = RenderedDescription),
    (Event | where TimeGenerated > window and EventID == 4688 and RenderedDescription has "Stop-Service"
        | extend Kind = "ACTOR cmd",
                 Detail = strcat(
                    extract(@"Account Name:\s+([^\r\n]+)", 1, RenderedDescription), " -> ",
                    extract(@"Process Command Line:\s+([^\r\n]+)", 1, RenderedDescription))),
    (Event | where TimeGenerated > window and EventID == 4624 and RenderedDescription has "svc-oncall"
        | extend Kind = "ACTOR logon",
                 Detail = extract(@"Account Name:\s+([^\r\n]+)", 1, RenderedDescription))
| project TimeGenerated, Computer, Kind, Detail
| order by TimeGenerated asc
```
