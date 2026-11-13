# Demo service overview

Use this as the knowledge index for the Container Apps demo. All identifiers
are supplied by the operator at runtime. No committed example identifies a
real deployment.

| Field | Contract |
| --- | --- |
| Service | Node.js sample with `/`, `/healthz`, `/readyz` on port 8080 |
| Scope | Explicit subscription, dedicated resource group, and app |
| Platform | Azure Container Apps, multiple revisions, external HTTPS ingress (source allow-list or explicitly approved public access) |
| Baseline | Verified healthy revision(s) and traffic captured before injection |
| Failure | One manually injected, uniquely named crash-loop revision |
| Telemetry | Scoped Container Apps logs/metrics; optional SDK Application Insights |
| Change authority | Human operator; investigation is read-only |

## Topic index

- [Architecture](architecture.md)
- [Deployment and rollback](deployment.md)
- [Debugging](debugging.md)
- [Crash/restart runbook](runbook-container-app-crash.md)
- [Roles and escalation](team.md)
- [Investigation queries](queries/restart-investigation.md)

## Operating principles

Correlate before recommending a rollback. A naming convention, log arrival,
or running state alone does not establish the cause or prove health.
Report observed, inferred, and unknown facts separately. Require evidence
timestamps and exact revision scope. Do not scale through an injected failure,
disable probes, or treat an agent recommendation as approval.

There is no production SLO commitment in this sample. Use endpoint response,
revision health, traffic restoration, and incident evidence as rehearsal
acceptance criteria rather than inventing an availability or MTTR guarantee.
