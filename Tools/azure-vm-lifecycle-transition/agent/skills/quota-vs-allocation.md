---
name: quota-vs-allocation
description: Use when checking whether proposed target VM families can land - regional and family vCPU quota headroom, SKU and zone availability, Azure Policy restrictions on VM sizes, capacity reservation advice, disaster recovery footprint - or when drafting (never submitting) a quota increase request.
tools:
  - RunAzCliReadCommands
---

# Quota, availability, and capacity

Read-only. Drafts quota requests; never submits them.

## Inputs

- Proposed target families and size classes from `sku-advisor`.
- Region, zone, and subscription for each VM; the disaster recovery (DR) region
  for DR-tagged workloads.
- Template: `quota-request-draft.md` in the knowledge base.

## Procedure

1. **Quota.** For each subscription and region:

   ```bash
   az vm list-usage --location <region> --subscription <subscriptionId> --output json
   ```

   Read the family quota (for example `standardDDSv5Family`) and the regional
   total (`cores`). Headroom is `limit - currentValue` for both; the lower value
   wins.
2. **Demand.** Add the vCPUs of the proposed sizes per family. Constrained vCPU
   sizes (for example `E32-8s_v5`) consume quota for the parent size's full vCPU
   count, so count 32 for that example.
3. **Availability.** Check the candidate sizes in the region and zones. Each call
   downloads the region's full size list and can take minutes, so query once per
   region with a family prefix (for example `--size Standard_D` returns every
   D-family size) and filter the output:

   ```bash
   az vm list-skus --location <region> --size <Standard_FamilyPrefix> --resource-type virtualMachines --all --output json
   ```

   Report restrictions such as `NotAvailableForSubscription` and the zones where the
   size is offered.
4. **Policy.** Quota and availability don't help if Azure Policy denies the size.
   List the assignments that apply to the VM's resource group:

   ```bash
   az policy assignment list --scope <resourceGroupId> --disable-scope-strict-match \
     --query "[].{name:name, displayName:displayName, definition:policyDefinitionId, enforcementMode:enforcementMode, parameters:parameters}" \
     --output json
   ```

   For each enforced assignment, read its definition (`az policy definition show`,
   or `az policy set-definition show` for initiatives) and look for `deny` rules on
   `Microsoft.Compute/virtualMachines/sku.name`, such as the built-in *Allowed
   virtual machine size SKUs* policy and its `listOfAllowedSKUs` parameter. For a
   scale set, look for rules on `Microsoft.Compute/virtualMachineScaleSets/sku.name`
   instead: a rule only on `virtualMachines` doesn't cover the instances of a
   Uniform scale set. Check
   exemptions with `az policy exemption list --scope <resourceGroupId>
   --disable-scope-strict-match`. Set `policyCheck` to `blocked` and name the
   assignment in `policyBlockedBy` when a target size is denied, to `allowed` when
   no rule denies it, or to `unknown` when you can't read policy. A blocked size
   needs an exemption or an allowed-list change from the policy owner; it isn't
   landable until then.
5. **Capacity.** State in every report: "Quota authorizes consumption; it doesn't
   reserve capacity." For time-critical waves or large memory-optimized sizes,
   advise an on-demand capacity reservation for the exact size, region, and zone,
   and note that it's billed at the size's rate even when unused.
6. **DR footprint.** For DR-tagged workloads, add up the vCPUs needed to start
   them all at the same time in the DR region and compare with that region's
   headroom. Set `drCheck` to `pass`, `fail`, or `unknown` (`not-applicable`
   without a DR tag), and put the details in `evidence` and
   `remainingValidations`.
7. **Fallback.** When the target is unavailable, denied by policy, or short on
   headroom, propose the v5 fallback family and check it the same way.
8. **Draft.** When headroom is short, fill in `quota-request-draft.md`. Say clearly
   that the customer reviews and submits it.

## Output

A `landing` object per VM that matches `disposition-record.schema.json`, a
headroom table per subscription, region, and family, and any quota request drafts.

## Rules

- Never run quota, support ticket, capacity reservation, reservation, or savings
  plan write commands. Tool access policies deny them; don't try to work around
  that.
- End of Life series under capacity growth restrictions don't get more quota. Plan
  new growth on newer series.
- Never say capacity is available. Say what you checked and when.
