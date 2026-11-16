---
name: resize-vs-redeploy-decision
description: Use when deciding how an End of Life VM should move to a new home - resize to v5, redeploy to v6 or v7, replace a pool, change a managed service size, or stop for a vendor gate - and which target family direction and size class to propose.
tools:
  - RunAzCliReadCommands
  - QueryLogAnalyticsByWorkspaceId
---

# Resize, redeploy, or re-platform

Read-only. Produces a proposal, never a change.

## Inputs

- Inventory rows from `arg-retiring-series` and readiness from
  `gen2-nvme-mana-readiness`.
- Utilization baseline from `metrics-30d-utilization.kql`, appended to this
  skill when it's published.
- Knowledge: `legacy-series-to-target-framework.md`.

## Decision sequence

1. **Gate.** `hardGate` other than `none` gives `disposition: vendor-gated`. Stop.
2. **Pattern.** Use the workload class:
   - A or B: `replace-pool-or-image` (update the scale set model or golden image).
   - C: `service-managed-change` (use the service's supported sizes).
   - D: `recreate-cluster`.
   - E or F: continue to step 3. F adds replication and role transfer to the plan.
     Any database is F, clustered or not: for example, a VM with a database role
     tag or a SQL extension.
   - Domain controllers: build new, replicate, demote. Never resize in place.
     Their class is `domain-controller`, not F, and their disposition is
     `rebuild-or-redeploy-v6-v7`: a new controller on the target family, never
     `resize-to-v5` or `replace-pool-or-image`.
   - Unknown class with naming-only evidence: continue when an owner is
     recorded, but cap confidence at `low` and list owner confirmation as a
     remaining validation. Without an owner, use `needs-data`.
3. **Smoothest path (v5 resize).** Propose `resize-to-v5` when all of these hold:
   - the target v5 family supports the VM's generation (v5 supports Generation 1
     and Generation 2);
   - Accelerated Networking is enabled or can be enabled first for Intel D v5;
   - a temporary disk dependency maps to a `d` variant, or there's no dependency;
   - disk count and NIC count fit the target size class;
   - the target is offered in the VM's region and zone (checked later with
     `quota-vs-allocation`).
4. **Newest path (v6 or v7).** Propose `rebuild-or-redeploy-v6-v7` only as a
   planned redeploy from a Generation 2, NVMe-ready, MANA-ready image. Use it when
   the owner wants the latest features or v5 doesn't fit. List the Generation 2,
   NVMe, MANA, and temporary disk prerequisites.
5. **Re-platform.** Mark `re-platform-candidate` only as an option to discuss
   with the owner, never as the default.
6. **Nothing to do.** Use `no-action-not-in-scope` for VMs outside the
   announcement. Use `needs-data` when you can't read the VM's generation,
   Accelerated Networking state, disk count, or NIC count, or when both the
   owner and the workload class are unknown.

Otherwise, a target that Azure Policy denies, utilization coverage shorter than
30 days, unknown temporary disk use, or a class the owner hasn't confirmed
doesn't change the disposition. Keep the path from steps 2 to 4, set the
confidence from the table below, and list the policy exemption, the owner
confirmation, the temporary disk check, or the longer baseline in
`remainingValidations`.

## Right-sizing

- Use p95 CPU and memory. Missing memory data means `memUsedP95: null`, not 0.
- Propose a size class (for example, "4-vCPU Ddsv5 class"), never a final size.
  Set `targetDirection.isFinal` to `false`.
- p95 CPU under 20% over at least 14 days of coverage: suggest evaluating a
  smaller class.
- p95 CPU over 80%: suggest a larger class or a compute-optimized family.
- Burstable B-series VMs that are busy most of the time: suggest a non-burstable
  family.
- Add a v5 fallback family when the main target is v6 or v7.

## Confidence

| Level | When |
| --- | --- |
| high | Owner-confirmed class, readiness known, 30 days of utilization |
| medium | Class from CMDB or tags, at most two unknown readiness signals |
| low | Naming-only class, missing utilization, or several unknowns |

## Output

`disposition`, `targetDirection`, `confidence`, and `remainingValidations` for
the disposition record. Always include a benchmark on the candidate size and any
vendor or licensing checks in `remainingValidations`.

## Record values

Use these exact values; put explanations in `evidence` or
`remainingValidations`, never in an enum field.

- `workloadClass.value`: `A-compute-pool`, `B-image-based-host`,
  `C-service-managed`, `D-cluster-recreation`, `E-customer-managed`,
  `F-stateful-clustered`, `G-certified-appliance`, `domain-controller`, or
  `unknown`.
- `workloadClass.basis`: where the class came from: `owner-confirmed`, `cmdb`,
  `tags`, `extensions`, `naming-hypothesis`, or `unknown`. A class from tags is
  `tags`, even when it's provisional.
- `readiness.securityType`: `Standard` when the VM has no security type,
  otherwise `TrustedLaunch`, `ConfidentialVM`, or `unknown`.
- `utilization30d.coverageDays`: whole days, or `null`.

## Rules

- Never promise performance gains, price changes, or percentages.
- Never present a family as available until the `quota-vs-allocation` checks
  confirm it.
