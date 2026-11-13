# Operator runbook: incident, investigation, approved recovery

Use only a dedicated demo app provisioned for this package. The injected
revision intentionally fails; this is not a production chaos-testing tool.
Complete [deployment and onboarding](deployment.md) first.

## Establish the baseline

From `Tools\azure-sre-incident-response`:

```powershell
$scope = @{
    SubscriptionId = '<subscription-guid>'
    ResourceGroup  = '<dedicated-demo-resource-group>'
    AppName        = '<demo-app>'
}
az containerapp revision list --subscription $scope.SubscriptionId `
    --resource-group $scope.ResourceGroup --name $scope.AppName --output table
```

Verify the selected resource identity and demo designation, active healthy
baseline, expected image, explicit traffic allocation, and HTTP 200 from
`/healthz` and `/readyz`. Record evidence and confirm alert routing.
Pause concurrent deployments and other incident runs until this rehearsal is
recovered. Do not edit or reuse an incident record from another scope.

## Preview, then inject

```powershell
.\scripts\demo-break.ps1 @scope -WhatIf
# Only after explicit approval for simulated downtime:
.\scripts\demo-break.ps1 @scope
```

Copy the printed `Recovery state:` path into `$state`; it points to a unique
JSON record in the ignored `scripts\.state` directory. The script captures the
baseline and creates a uniquely named failure revision. If any operation fails, inspect the current
state and retain the record for recovery; do not assume a failed command
means Azure made no change.

Container Apps readiness and routing can keep an unready revision from
receiving traffic. Observe actual revision health, endpoint behavior, and
alerts instead of promising a fixed outage or detection interval.

## Investigate read-only

Supply the agent with the precise resource and revision scope and this prompt:

```text
Investigate this demo incident read-only. Consult knowledge/overview.md and
the crash runbook. Correlate revision inventory, traffic, timestamps, console
and system logs, and metric evidence. Distinguish observed from inferred
causes and report missing evidence. Identify the captured healthy baseline
and propose rollback with its impact and verification steps. Do not change
resources, send messages, or close incidents without explicit approval.
```

The canonical diagnostic procedure is
[the crash runbook](../knowledge/runbook-container-app-crash.md).
The failing revision is manually injected: do not falsely attribute its
creation to a source commit just because a healthy revision came from CI.

## Approve and verify recovery

Review the stored scope and intended baseline with the operator:

```powershell
$state = '<exact Recovery state path printed by demo-break>'
.\scripts\demo-fix.ps1 @scope -StatePath $state -WhatIf
# Only after explicit rollback approval:
.\scripts\demo-fix.ps1 @scope -StatePath $state
```

Recovery uses the captured traffic, verifies the restored endpoint, and
deactivates only the injected revision. Never substitute "newest running
revision" for a verified baseline. If recovery reports failure, retain state,
review the diagnostics, and retry only after understanding the current scope
and traffic. Do not deactivate additional revisions to force a green result.

Independently confirm:

- Original traffic targets and weights are restored and healthy.
- `/healthz` reports the expected app version and `/readyz` reports readiness.
- The injected revision is inactive.
- Telemetry shows recovery; allow for ingestion/alert evaluation delay.
- The alert and agent incident are verified separately, not assumed resolved.

Document observations, approval, action result, residual gaps, and follow-up.
Any incident closure or external communication remains a separate decision.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Wrong scope or missing demo tag | Stop; confirm resource identity and setup, never retag an arbitrary workload to bypass the guard |
| Baseline unhealthy or missing | Stop injection; deploy and verify a healthy baseline first |
| Image pull failure | Verify the selected public image exists and is anonymously pullable |
| Agent sees no alert | Check the configured receiver/incident integration and agent scope |
| Logs are empty | Check workspace context, diagnostic configuration, table schema, and ingestion delay |
| Recovery endpoint fails | Keep incident state and baseline; inspect revision-specific health and ingress before approving more actions |
| An unrecovered state exists for this app | Recover or review that incident first; do not overwrite its baseline |
