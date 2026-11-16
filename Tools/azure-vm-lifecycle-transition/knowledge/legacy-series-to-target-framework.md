# End of Life series to target family framework

Upload this file to the Azure SRE Agent knowledge base. It gives **family-level
directions** for finding End of Life VMs a new home. It never selects a final size:
a final size needs the workload's utilization baseline, readiness checks,
region and zone availability, quota, and owner sign-off.

Target families and platform changes come from the public Microsoft Learn guidance
listed in [Sources](#sources); the notes column adds engineering guidance. The
evidence date is 2026-11-11; re-verify before external use.

## Decision order

1. **Hard gates first.** SAP workloads can only use sizes on the SAP-certified list.
   ISV virtual appliances (firewalls, network virtual appliances, backup and storage
   appliances) can only use families the vendor certifies. Record the gate and stop;
   don't automate these workloads.
2. **Workload pattern.** Classify the workload (table below). The pattern decides
   whether you resize a VM, replace a pool, change a service setting, or redeploy.
3. **Smoothest path versus newest path.** The v5 series (Extended stage) is the
   smoothest transition for existing D-family and E-family workloads. The v6 and v7
   series (Current stage) need Generation 2, NVMe, and MANA, so treat them as a
   planned upgrade or redeploy, not a blind in-place resize.
4. **Landing.** Confirm region and zone availability, quota for the target family,
   and capacity needs before any target appears in a record.

## Workload patterns

| Pattern (`workloadClass.value`) | Typical workloads | How the move usually happens |
| --- | --- | --- |
| A. Compute pools (`A-compute-pool`) | Stateless pools, scale sets, immutable infrastructure | Update the model or image and replace instances in controlled batches |
| B. Image-based hosts (`B-image-based-host`) | Pooled virtual desktop session hosts | Assess and rebuild the golden image once, then replace hosts |
| C. Service-managed compute (`C-service-managed`) | Compute that a managed service creates | Change the size through the service's supported-size list |
| D. Cluster re-creation (`D-cluster-recreation`) | Clusters recreated from a definition | Recreate on a supported size |
| E. Customer-managed VMs (`E-customer-managed`) | Individually managed servers | Resize where compatible; otherwise rebuild from a current image |
| F. Stateful and clustered (`F-stateful-clustered`) | Databases, clustered services | Like E, plus replication, role transfer, and application-aware sequencing |
| G. Certified appliances (`G-certified-appliance`) | Vendor appliances | Vendor certification for the exact target family gates everything |

Label a pattern inferred from names or tags as a hypothesis until the workload owner
or the configuration management database confirms it. Domain controllers
(`domain-controller`) follow their own pattern: build new, replicate, then demote
the old server.

## Family-level directions

For the D-family and E-family, the v5 series (Extended stage) is the smoothest
transition and the v6 and v7 series (Current stage) bring the latest features.

| End of Life series | Learn-listed targets: smoothest transition | Learn-listed targets: latest features | Notes |
| --- | --- | --- | --- |
| D, Ds, Dv2, Dsv2 | Dsv5, Ddsv5, Dasv5, Dadsv5 | Dsv6, Ddsv6, Dasv6, Dadsv6, Dasv7, Dadsv7; memory-heavy sizes toward Esv6, Edsv6, Easv6, Eadsv6, Easv7, Eadsv7 | v5 targets use SCSI; v6 and v7 use NVMe |
| Dv3, Dsv3 | Dv5, Dsv5, Ddv5, Ddsv5, Dasv5, Dadsv5 | v6 and v7 D-family series | Every v3 size has a local temporary disk |
| Ev3, Esv3 | Ev5, Esv5, Edv5, Edsv5, Easv5, Eadsv5 | Esv6, Esv7 and other v6 and v7 E-family series | Constrained vCPU sizes exist on both sides |
| Av2, Amv2 | Bsv2, Basv2, Dsv5, Ddv5, Dasv5, Esv5, Edv5, Easv5 | Dsv6, Ddsv6, Dasv6, Esv6, Edsv6, Easv6 | Right-size from utilization; don't preserve the A-series by name |
| B (v1) | Bsv2, Basv2, Dlsv5, Dldsv5, Dalsv5, Daldsv5 | Dlsv6, Dldsv6, Dalsv6, Daldsv6 | Flag chronically busy burstable VMs for a non-burstable family |
| F, Fs, Fsv2 | Dlsv5, Dldsv5, Dsv5, Ddsv5 | Dlsv6, Dldsv6, Dalsv6, Daldsv6, Falsv6 | Compare per-core performance, not only vCPU count |
| G, Gs | Lsv3, Lasv3, and the v4 L-series | Learn names Lasv5 and Laosv5 as the Current L-series | Validate memory and local storage needs |
| Ls, Lsv2 | Lsv3, Lasv3, and the v4 L-series | Learn names Lasv5 and Laosv5 as the Current L-series | Local NVMe storage; plan data re-hydration |
| NP | Not applicable | NDv2, NCads_H100_v5, NCasT4_v3 | FPGA to GPU means porting the workload; never a resize |
| HBv2 | Not applicable | HBv3, HBv4, HBv5, HX | Validate MPI, memory bandwidth, and RDMA |
| HC, NVv3, NVv4, M192i v2, DCsv3, DCdsv3 | See the series-specific retirement guide | See the series-specific retirement guide | Specialized; follow the guide linked from the dates file |

Confirm the exact v4 L-series names on the
[retired sizes modernization guide](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirement/retired-sizes-modernization-guide)
before citing them.

## What changes with the target family

| Signal | v5 (smoothest transition) | v6 and v7 (latest features) |
| --- | --- | --- |
| Boot generation | Generation 1 and Generation 2 supported; a resize usually doesn't need a generation change | Generation 2 (UEFI) only; a Generation 1 v3 VM can't convert in place |
| Disk interface | SCSI | NVMe; the image and OS must support NVMe; replace hard-coded SCSI device paths |
| Networking | Accelerated Networking is **required** on Intel D-family v5 (Dv5, Dsv5, Ddv5, Ddsv5) and supported on AMD and E-family v5; enable it on the source VM before the resize | MANA adapter; Linux needs kernel 5.15 or later, Windows needs a current image with the built-in driver |
| Local temporary disk | Only on `d` sizes (for example Ddsv5, Edsv5) | Only on `d` sizes, presented as raw NVMe, recreated after every deallocation; a source with a temporary disk can't convert in place |
| Encryption | No change | Azure Disk Encryption for Linux isn't supported with NVMe; decrypt or redeploy |
| Image | Refresh old images and guest drivers before a broad wave | Current Generation 2, NVMe-ready, MANA-ready image |
| Quota | v5 family quota | v6 and v7 use distinct quota families; request quota early |

## Transition methods

| Method | Use when |
| --- | --- |
| Resize the existing VM | The VM's disks, boot generation, networking, region, and availability configuration support the target size. Usually needs a restart and possibly a deallocation. |
| Rebuild from a current image | The OS image or guest configuration needs modernizing, or the target needs Generation 2. Move configuration and data, then cut over. |
| Replace instances in a scale set | The workload uses scale sets or immutable infrastructure. Update the model or image and roll out in batches. |
| Replicate and cut over | The workload needs extended testing, reduced cutover risk, or a move to another region. Plan replication, identity, networking, DNS, and rollback. |

## Rules for recommendations

- Give a family direction and a size-class hint, never a final size. Mark every
  target `isFinal: false`.
- Don't match on vCPU count alone. Compare memory, disk limits, network bandwidth,
  local disk, and the workload's measured utilization.
- Prefer a `d` variant only when the workload depends on a local temporary disk.
- Offer a v5 fallback when the v6 or v7 target is constrained or not available in
  the required region or zone.
- Never promise a performance gain or a price change. Recommend a benchmark on the
  candidate size and point to the customer's own pricing.
- List the validations that remain, such as owner confirmation, temporary disk use,
  vendor certification, licensing, and a benchmark.

## Sources

- [Retired VM sizes modernization guide](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirement/retired-sizes-modernization-guide)
- [Modernize to the v5 VM series](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/sizes-v5-modernization-overview)
- [Modernize to the v6 and v7 VM series](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/sizes-v6-v7-modernization-overview)
- [Assess readiness for the v6 and v7 VM series](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/sizes-v6-v7-modernization-assess)
- [VM lifecycle overview](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/lifecycle-overview)
- [Constrained vCPU sizes](https://learn.microsoft.com/azure/virtual-machines/constrained-vcpu)
