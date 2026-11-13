# Debugging reference

## Evidence sources

| Signal | Source |
| --- | --- |
| Revision identity and health | Container Apps revision inventory and ingress traffic |
| Replica restart / replica count | Container App metric definitions and time series |
| App stdout/stderr | `ContainerAppConsoleLogs_CL` in the configured workspace |
| Platform events | `ContainerAppSystemLogs_CL` in the configured workspace |
| HTTP/exception telemetry | `requests` / `exceptions` in Application Insights query context, or `AppRequests` / `AppExceptions` in workspace context |

Table availability and columns depend on telemetry configuration. Inspect the
schema first and record absent sources. An empty query is not proof of recovery.

## Investigation order

1. Confirm the exact resource, failing revision, baseline, and incident time.
2. Compare revision creation and traffic changes with first observed errors.
3. Inspect console/system logs for startup, process exit, probe failure, OOM,
   and image pull evidence.
4. Compare endpoint behavior and health with metrics over the same interval.
5. Propose the least disruptive scoped recovery with explicit unknowns.

| Finding | Interpretation and proposed next step |
| --- | --- |
| Repeated process exits in injected revision | Expected demo fault; propose captured-baseline recovery |
| Readiness/liveness errors | Inspect endpoint response and startup before proposing a change; never disable probes to hide failure |
| OOM evidence | Investigate memory constraints or leak; do not blindly scale the failing revision |
| Image pull errors | Verify image reference and registry access; public image access must be tested explicitly |
| Healthy probes but client errors | Investigate traffic, ingress, DNS, and request scope; a health endpoint does not prove every client path |

Use the [query examples](queries/restart-investigation.md) and
[crash runbook](runbook-container-app-crash.md). This knowledge authorizes no
resource changes.
