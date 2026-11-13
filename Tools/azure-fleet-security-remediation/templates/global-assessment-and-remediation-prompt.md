# Global assessment and remediation prompt

```text
Perform a cost-efficient global security, patching, and remediation assessment
for all Azure VMs and Azure Arc-enabled servers in this scope:

<subscription-or-approved-scope>

Objectives:
1. Inventory `Microsoft.Compute/virtualMachines` and
   `Microsoft.HybridCompute/machines` through one compact Resource Graph query.
2. Validate possible duplicate or same-named VM and Arc records before combining
   remediation actions.
3. Collect current Defender posture, patch assessment, patch installation,
   reboot, Update Manager configuration, and assignment evidence.
4. Treat a missing result as a coverage gap, not as proof that a workload is
   healthy or unmanaged.
5. Use targeted Activity Log and guest/extension checks only for failed,
   disconnected, stale, or inconclusive workloads.
6. Map CVEs only when the KB-to-CVE relationship is verified.
7. Produce a remediation plan, but do not patch, reboot, change assignments,
   repair agents, or alter security controls without explicit approval.

Cost-efficiency rules:
- Prefer grouped Azure Resource Graph queries over per-resource scans.
- Avoid broad raw log searches and repeated assessments.
- Use Azure Update Manager as the preferred patch-orchestration capability.
- Do not treat a completed control-plane update request as successful guest
  patching; require a fresh patch-installation result and corroborating evidence.
- Exclude drivers and optional update categories unless explicitly approved.

For every proposed state-changing action, include:
- exact target resource;
- evidence timestamp and source;
- risk and expected availability impact;
- Azure-native remediation method;
- verification signal;
- rollback or safe-stop path; and
- required approval owner.

Output:
- Executive summary: maximum 8 bullets.
- Fleet inventory and telemetry coverage totals.
- Workload matrix: resource, platform, connection state, patch state, reboot
  state, Defender posture, risk, and recommended next action.
- Verified CVE mapping table.
- Update Manager configuration and assignment coverage summary.
- Prioritized remediation plan.
- Cost-efficiency summary: queries performed and operations intentionally avoided.
- Explicit approval request listing only the exact state-changing actions.
```
