# Demo roles and escalation

Assign actual people and approved communication destinations at runtime.
The repository intentionally includes no personal contacts or real on-call
channel names.

| Role | Responsibility |
| --- | --- |
| Demo owner | Owns the isolated subscription/resource scope, cost, and cleanup |
| Operator / approver | Approves deployment, simulated downtime, and recovery; retains incident state |
| Investigator | Reads evidence and knowledge; proposes scoped actions without executing them |
| Escalation owner | Handles unexpected impact, missing baseline, or failed recovery |

The investigator must cite the knowledge and evidence used, distinguish
observations from assumptions, and report unresolved failures. External
messages, incident closure, and additional cloud changes require explicit
authorization under the operator's integration policy. This sample does not
grant permission to post to Teams, send email, or page an actual team.
