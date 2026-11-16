# Azure VM lifecycle dates: public sources only

Upload this file to the Azure SRE Agent knowledge base so every custom agent uses
the same dates. It contains only dates published on Microsoft Learn, each with its
source. The series keys match the `lifecycleSeries` values returned by
[`arg-affected-vms.kql`](../queries/arg-affected-vms.kql); the package tests fail if
the two drift apart.

| Field | Value |
| --- | --- |
| Evidence date | 2026-11-11 |
| Primary source | [VM size series retirements, capacity growth restrictions, and modernization guidance](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions) (Learn page dated 2026-09-25) |
| Supporting sources | [Retired VM sizes modernization guide](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirement/retired-sizes-modernization-guide), [End of Life Azure VM size series](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/end-of-life-sizes-list), [VM lifecycle overview](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/lifecycle-overview) |

## Rules for the agent

1. Use only the dates in this file. If a series isn't listed, report
   `lifecycle date unknown - verify on Microsoft Learn` instead of guessing.
2. Cite the source link with every date that appears in a report.
3. Don't state price changes, discounts, or percentages. This file intentionally
   contains none; pricing depends on the customer's agreement, meter, and
   commitments.
4. Treat retirement and capacity growth restrictions as separate facts. A series
   can have both.
5. When the current date is more than 30 days after the evidence date, state that
   the dates need re-verification before external use.

## Lifecycle stages

| Stage | What it means | Recommended action |
| --- | --- | --- |
| Current | Newest series in the family, for example v6 and v7 general purpose series | Adopt for new deployments |
| Extended | Fully supported, for example v4 and v5 general purpose series | Continue; a practical first step when moving off End of Life series |
| End of Life | Retirement is announced; deployment through new subscriptions is restricted | Plan and complete the move before the retirement date |
| Retired | Can't be created, resized into, or run; remaining VMs are deallocated | Move to a supported size; managed disk data is preserved |

## Series matched by the inventory query

| Series key | Example sizes | Planned retirement | Capacity growth restricted | Source |
| --- | --- | --- | --- | --- |
| `NCv3` | Standard_NC6s_v3, Standard_NC24rs_v3 | 2025-09-30 | No | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#gpu-accelerated-retired-sizes) |
| `DCsv2` | Standard_DC2s_v2, Standard_DC8_v2 | 2026-06-30 | No | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `NVv3` | Standard_NV12s_v3 | 2026-09-30 | No | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#gpu-accelerated-retired-sizes) |
| `NVv4` | Standard_NV8as_v4 | 2026-09-30 | No | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#gpu-accelerated-retired-sizes) |
| `M192i_v2` | Standard_M192idms_v2, Standard_M192ids_v2, Standard_M192ims_v2, Standard_M192is_v2 | 2027-03-31 | No | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#memory-optimized-retired-sizes) |
| `NP` | Standard_NP10s, Standard_NP20s, Standard_NP40s | 2027-05-31 | No | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#fpga-accelerated-retired-sizes) |
| `HC` | Standard_HC44rs, Standard_HC44-16rs | 2027-05-31 | No | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#hpc-retired-sizes) |
| `HBv2` | Standard_HB120rs_v2, Standard_HB120-96rs_v2 | 2027-05-31 | No | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#hpc-retired-sizes) |
| `D` | Standard_D2, Standard_D12 | 2028-05-01 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `Ds` | Standard_DS2, Standard_DS13-2 | 2028-05-01 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `Dv2` | Standard_D2_v2, Standard_D12_v2 | 2028-05-01 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `Dsv2` | Standard_DS3_v2, Standard_DS11-1_v2 | 2028-05-01 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `Ls` | Standard_L8s | 2028-05-01 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#storage-optimized-retired-sizes) |
| `Av2` | Standard_A2_v2 | 2028-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `Amv2` | Standard_A4m_v2 | 2028-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `Bv1` | Standard_B1ls, Standard_B2s, Standard_B4ms | 2028-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `F` | Standard_F4 | 2028-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#compute-optimized-retired-sizes) |
| `Fs` | Standard_F4s | 2028-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#compute-optimized-retired-sizes) |
| `Fsv2` | Standard_F8s_v2 | 2028-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#compute-optimized-retired-sizes) |
| `G` | Standard_G2 | 2028-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#memory-optimized-retired-sizes) |
| `Gs` | Standard_GS2, Standard_GS4-8 | 2028-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#memory-optimized-retired-sizes) |
| `Lsv2` | Standard_L16s_v2 | 2028-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#storage-optimized-retired-sizes) |
| `DCsv3` | Standard_DC2s_v3 | 2029-10-31 | No | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `DCdsv3` | Standard_DC2ds_v3 | 2029-10-31 | No | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `Dv3` | Standard_D4_v3 | 2029-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `Dsv3` | Standard_D4s_v3 | 2029-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#general-purpose-retired-sizes) |
| `Ev3` | Standard_E8_v3, Standard_E64i_v3 | 2029-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#memory-optimized-retired-sizes) |
| `Esv3` | Standard_E8s_v3, Standard_E32-8s_v3 | 2029-11-15 | Yes | [Learn](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions#memory-optimized-retired-sizes) |

Other retired series that the query doesn't match, including confidential
computing `*_cc_v5` sizes and dedicated host SKUs, are listed on the primary
source page.

## Capacity growth restrictions (since July 2026)

The restriction applies to F, Fs, Fsv2, D, Ds, Dv2, Dsv2, Dv3, Dsv3, B, Bs, Av2,
Amv2, Ev3, Esv3, G, Gs, Ls, and Lsv2. It's separate from retirement.

| Scenario | Outcome published on Learn |
| --- | --- |
| New subscription | Can't deploy the affected series |
| Existing subscription within approved quota | Can deploy or redeploy, subject to capacity availability |
| Existing subscription asking for more quota | More quota for the affected series isn't approved |
| Existing subscription with quota but no regional capacity | Deployment might fail although quota is available |

Quota is an approved limit; it isn't a capacity reservation or a guarantee. Use
[on-demand capacity reservations](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-overview)
when a wave needs guaranteed supply for a specific size, region, and zone. A
capacity reservation is billed at the same rate as the underlying VM size, even
when no VM uses it.

## Reservations and savings plans

Source: the reserved instances section of the primary source page and the
[retired sizes modernization guide](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirement/retired-sizes-modernization-guide#modernization-steps).

- Existing reserved instances (RIs) stay valid until the end of their term. They're
  billing discounts, not capacity reservations.
- New or renewed one-year and three-year RIs aren't available for the affected A,
  B, D, E, F, and L variants of the v1 through v3 series. After an RI expires,
  usage moves to pay-as-you-go rates unless the customer chooses another
  commitment.
- RIs don't move automatically to a new series. Exchange an eligible RI or trade it
  in for an Azure savings plan for compute.
- RI exchanges are available until **2027-02-01**. After that date, each eligible
  active reservation purchased before the deadline keeps one final exchange.
- Azure savings plan for compute remains available across eligible VM generations.

The agent reads reservation and savings plan coverage only when its identity has
read access. It never buys, exchanges, or trades in a commitment.
