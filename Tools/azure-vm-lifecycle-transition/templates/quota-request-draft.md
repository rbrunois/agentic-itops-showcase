# Quota increase request: draft for customer review

<!-- Prepared by quota-capacity-checker. The customer reviews the draft and
submits it in the Azure portal. The agent never submits it. -->

| Field | Value |
| --- | --- |
| Status | **Draft, not submitted** |
| Prepared | `<yyyy-mm-dd>` by `<custom agent name>` |
| Subscription | `<subscription ID>` |
| Region | `<region>` |
| Quota name | `<for example standardDDSv5Family>` |
| Current limit and usage (vCPUs) | `<limit>` and `<currentValue>` |
| Requested new limit (vCPUs) | `<value>` |
| Regional vCPU limit and usage | `<limit>` and `<currentValue>`; raise it too when the new family limit exceeds the regional headroom |

## Justification

Move `<n>` VMs from `<End of Life series>` (planned retirement `<date>`, see
`<Microsoft Learn link>`) to `<target family>` in `<waves and dates>`.

| Wave | VMs | Target size class | vCPUs (constrained sizes at the parent size's vCPUs) |
| --- | --- | --- | --- |
| `<wave>` | `<n>` | `<size class>` | `<n>` |

## Zones and capacity

- Zones needed: `<zones>`
- Capacity reservation advised: `<yes or no, and why>`. Quota authorizes
  consumption; it doesn't reserve capacity.
- Disaster recovery: `<vCPUs needed to start DR workloads at the same time in the
  DR region, and that region's headroom>`

## Before submitting

- [ ] The workload owners confirmed the waves and target families.
- [ ] The regional vCPU quota covers the new family limit.
- [ ] The target isn't an End of Life series; those don't get more quota.
- [ ] Submit through
  [Increase VM-family vCPU quotas](https://learn.microsoft.com/azure/quotas/per-vm-quota-requests)
  in the Azure portal.
