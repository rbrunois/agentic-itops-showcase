# Architecture

The public HTTPS endpoint routes through a Container Apps environment to the
Node sample on port 8080. The app serves `/`, `/healthz`, and `/readyz`.
Multiple revisions allow a healthy baseline to remain available while an
operator creates an isolated failing revision.

Container Apps sends configured console and system logs to Log Analytics.
The app optionally sends telemetry using the Application Insights SDK. The
infrastructure passes its connection string through a Container Apps secret;
do not place it in committed configuration or diagnostic output.

| Dependency | What its failure affects |
| --- | --- |
| Container Apps environment | App scheduling, ingress, and revision availability |
| Image registry | New deployments, restarts, and scaling that need image pulls |
| Log Analytics | Visibility into console/system logs; missing logs do not prove app failure |
| Application Insights | Request/exception telemetry when SDK configuration is present |
| Alert/incident integration | Notification and agent investigation delivery |

The package does not provision Front Door, AKS, private networking, an egress
allowlist, or the SRE Agent itself. Do not describe planned components as
observed resources. Agent and workload regions may differ only where supported
by the operator's current product configuration.

Read resource IDs and deployed properties before interpreting this topology
as a description of a live environment.
