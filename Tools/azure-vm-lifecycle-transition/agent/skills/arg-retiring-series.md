---
name: arg-retiring-series
description: Use when asked to find VMs or scale sets on End of Life or retired Azure VM series, size the affected estate, or refresh the VM lifecycle transition inventory. Read-only Azure Resource Graph scan with retirement dates and capacity restrictions.
tools:
  - RunAzCliReadCommands
---

# Find VMs on End of Life VM series

Read-only. This skill never changes Azure resources.

## Inputs

- Scope: subscription IDs or a management group. Ask for it when the request
  doesn't name one; never scan every subscription by default.
- Supporting query: `arg-affected-vms.kql`, appended to this skill when it's
  published.
- Knowledge: `lifecycle-dates-authoritative.md` for dates and sources.

## Procedure

1. Confirm the scope and say which subscriptions you're about to query.
2. Run the supporting query with Azure Resource Graph:

   ```bash
   az graph query -q "<contents of arg-affected-vms.kql>" \
     --subscriptions <subscriptionId> [<subscriptionId> ...] \
     --first 1000 --output json
   ```

   If the result has a `skipToken`, repeat with `--skip-token <token>` until all
   pages are read. If `az graph` isn't available, say so and stop; don't
   substitute an unbounded `az vm list` loop.
3. Summarize:
   - affected VMs and scale-set instances, by `lifecycleSeries`, `retirementDate`,
     `priority`, subscription, and region;
   - scale sets: count `instances`, not resources;
   - deallocated VMs (`powerState`) separately, because they still need a decision;
   - series under capacity growth restrictions (`capacityRestricted`).
4. List data gaps explicitly: sizes you couldn't classify, missing tags, and
   subscriptions you couldn't read.
5. Hand the affected resource IDs to the readiness step (`compat-analyst`).

## Output

- A summary table with counts by retirement date and priority, citing the
  Microsoft Learn source for each date.
- One JSON row per resource with `resourceId`, `name`, `subscriptionId`,
  `resourceGroup`, `location`, `zones`, `currentSize`, `lifecycleSeries`,
  `lifecycleStage`, `retirementDate`, `capacityRestricted`, `instances`, and
  `owner` when a tag provides one. These rows seed the disposition records.

## Rules

- A VM that isn't matched is "not in announcement scope", not "safe forever".
- Don't infer business criticality from names. Use tags or owner confirmation.
- Never quote prices or price changes.
