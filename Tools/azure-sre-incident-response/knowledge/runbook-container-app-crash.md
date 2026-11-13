# Runbook: Container App crash/restart incident

## Trigger and scope

An observed unhealthy revision, restart alert, replica-count alert, or failing
endpoint in the explicitly designated demo app. Verify subscription, resource
group, app, and incident time before investigation.

## Read-only procedure

1. Read revision inventory and current traffic using
   [deployment knowledge](deployment.md).
2. Identify the injected revision and pre-injection baseline from the trusted
   local incident record. Do not infer active scope from the latest log row.
3. Use [scoped queries](queries/restart-investigation.md) for console and system
   evidence. Differentiate process exits, OOM, probe failures, and image pulls.
4. Correlate timestamps with the injection and current endpoint behavior.
   Record missing or delayed metrics/logs.
5. Propose restoration of the captured baseline traffic with health checks,
   impact, and rollback limitations. Stop before any mutation.

## Approval and recovery

An authorized human reviews the scope and executes
[the operator recovery procedure](../docs/demo-runbook.md).
The agent must not activate/deactivate revisions, change traffic, scale,
re-provision, change probes, or modify monitoring on its own.

Verify restored `/healthz` and `/readyz`, expected version, traffic weights,
baseline revision health, and deactivation of only the injected revision.
Metric evaluation and incident-platform state may lag application recovery;
do not mark them successful without evidence.

## Exceptions and escalation

If the baseline is absent, unhealthy, or no longer matches the recorded scope,
stop and involve the designated [operator](team.md). Preserve diagnostic
evidence and the incident record. Do not guess a replacement baseline, widen
the blast radius, or restart/re-provision an environment as an automatic fix.

If no agent integration is available, the same investigation can be presented
manually with clearly labeled synthetic evidence. Do not describe this as a
verified live agent response.
