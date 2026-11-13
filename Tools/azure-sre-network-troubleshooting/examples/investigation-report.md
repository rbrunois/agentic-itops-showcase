# Synthetic Contoso investigation report

Illustration only; not telemetry from a deployed environment. Private addresses,
resource names, times, and results below are synthetic. The all-zero subscription
ID is a documentation placeholder and is intentionally rejected by live scripts.

## Scope

- Subscription: `00000000-0000-0000-0000-000000000000`
- Resource group: `rg-sre-network-demo`
- Source: `vm-sre-client`, private lab address `10.10.1.4`
- Destination: `vm-sre-web`, private lab address `10.20.1.4`, TCP/80
- UTC window: `2026-01-01T10:00:00Z` through `2026-01-01T10:05:00Z`
- Status: likely cause identified; human review required

## Observed Fact

1. Synthetic client test: two fresh attempts, two TCP failures and two HTTP failures.
2. Illustrative matching `NTANetAnalytics` records contain denied counter evidence
   for these endpoints and TCP/80 during the flow window.
3. Destination-scoped `Event` records from `SRE-Network-Demo` contain
   `demo_health iis_state=running`.

These are illustrative evidence references, not claims that a query was run.
In a live investigation cite the actual query, returned rows and UTC times locally.

## Configuration Fact

The workload subnet NSG contains `Deny-Client-To-Web-Demo`, inbound TCP/80
priority 100, scoped from the client subnet to the workload endpoint. It takes
precedence over the priority-200 baseline allow.

## Inference

A network-policy denial likely explains the failed fresh requests. Confidence
is high only when matching flow evidence and the relevant rule/ACL agree.
Running IIS health markers reduce, but do not eliminate, application hypotheses.
NSG configuration alone cannot prove a historical traffic result.

## Recommendation

The human network operator should review the evidence and independently approve
removal of only the injected demo deny through the restore script. Then approve
new healthy traffic and verify post-recovery flow and application evidence.
The agent has not performed any remediation.

## Evidence gaps

- Raw Storage flow records were not inspected.
- No claim is made about unique request counts from aggregated records.
- Missing or contradictory records would make network attribution incomplete.
- Connection Monitor is not enabled in this illustration.

## Application-failure contrast

If the deny is absent, configuration is permissive, and destination-scoped
events report `iis_state=stopped`, application unavailability is observed.
Matching allowed flow evidence supports the distinction. Without matching flow
evidence, report network-path validation as incomplete rather than proven healthy.
