# Scoped incident query examples

These queries are examples, not a guarantee of table/column availability.
Use the selected workspace and inspect its schema first. Replace placeholders
with the exact app, resource ID, revision, and UTC incident time from inventory.
Do not infer the active revision from the most recent log entry.

## Console logs for the failing revision

```kql
let app = "<demo-app>";
let revision = "<injected-revision>";
let resource = "<container-app-resource-id>";
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(30m)
| where _ResourceId =~ resource
| where ContainerAppName_s == app and RevisionName_s == revision
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
| take 100
```

## Platform event timeline

```kql
let app = "<demo-app>";
let revision = "<injected-revision>";
let resource = "<container-app-resource-id>";
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(1h)
| where _ResourceId =~ resource
| where ContainerAppName_s == app and RevisionName_s == revision
| project TimeGenerated, RevisionName_s, Reason_s, Log_s
| order by TimeGenerated asc
| take 200
```

System-event counts are not the `RestartCount` metric. Inspect the resource's
metric definitions and correct aggregation before reporting restart totals.

## Requests before and after the observed change

The following uses the **Application Insights resource query context**.
Replace the synthetic date and role with observed runtime values. Do not
assume the SDK role name equals the Container App name.

```kql
let changeTime = datetime(2026-01-01T12:00:00Z);
let role = "<observed-cloud-role-name>";
requests
| where timestamp between ((changeTime - 30m) .. (changeTime + 30m))
| where cloud_RoleName == role
| extend phase = iff(timestamp < changeTime, "before", "after")
| summarize total = count(), errors = countif(success == false) by phase
| extend errorRatePercent = 100.0 * errors / total
```

In **Log Analytics workspace context**, use `AppRequests` and the corresponding
`TimeGenerated`, `AppRoleName`, and `Success` columns after verifying schema and
resource scope. No rows means insufficient evidence, not a zero error rate.
