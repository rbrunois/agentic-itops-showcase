# Azure VM Lifecycle Transition Accelerator

Use Azure SRE Agent to find every virtual machine (VM) that runs on an End of Life
VM size series and plan its move to a supported series before the retirement
date. The agent works from evidence, runs on a schedule, and keeps people in
control of every change.

[![Azure VM size series move through four stages over time: Current, Extended, End of Life, and Retired. VMs on End of Life series need a new home before their retirement date: v5 for the smoothest move, or v6 and v7 for the latest features through a planned upgrade. Without a plan, they stop at the retirement date. Azure SRE Agent finds each VM a new home in four steps: analyze, recommend, and validate, which are read-only, and automate, which needs a person's approval. A weekly scan keeps the picture current, and guardrails keep people in control.](assets/vm-lifecycle-idea.svg)](assets/vm-lifecycle-idea.svg)

## The lifecycle challenge

Every Azure VM size series moves through four lifecycle stages:

| Stage | What it means |
| --- | --- |
| **Current** | The newest series in a family, such as v6 and v7 for general purpose sizes |
| **Extended** | Fully supported series, such as v4 and v5 for general purpose sizes |
| **End of Life** | Retirement is announced; the series stays supported until its retirement date |
| **Retired** | Can't be created, resized into, or run. Remaining VMs are deallocated and stop working |

Many widely used series are End of Life, including:

| Series | Planned retirement |
| --- | --- |
| D, Ds, Dv2, Dsv2, Ls | 2028-05-01 |
| Av2, Amv2, B (v1), F, Fs, Fsv2, G, Gs, Lsv2 | 2028-11-15 |
| Dv3, Dsv3, Ev3, Esv3 | 2029-11-15 |

The retirement date isn't the only deadline:

- **Capacity:** Since July 2026, these series are under capacity growth
  restrictions. New subscriptions can't deploy them, and existing subscriptions
  can't get more quota for them.
- **Commitments:** New or renewed reserved instances aren't available for the
  affected A, B, D, E, F, and L series. When a reservation expires, usage moves to
  pay-as-you-go rates unless you choose another commitment. Eligible reservations
  can be exchanged until 2027-02-01; after that date, each eligible active
  reservation keeps one final exchange.

The [lifecycle dates file](knowledge/lifecycle-dates-authoritative.md) lists
every End of Life series with its Microsoft Learn source.

Choosing a new home for each VM takes more than a size lookup:

- **v5 (Extended)** is the smoothest move for D-family and E-family workloads.
  Base v5 sizes have no local temporary disk, and the Intel D-family v5 series
  require Accelerated Networking.
- **v6 and v7 (Current)** require Generation 2 boot, NVMe storage, and the
  Microsoft Azure Network Adapter (MANA). A move to them is a planned upgrade,
  not a simple resize.
- **Landing** depends on quota and zone availability in each region, and quota
  doesn't reserve capacity. Azure Policy can also block the move: allowed-size
  lists written years ago often name only older sizes. In the lab subscription,
  such a policy denied every proposed v5 size for VMs.
- **Gates:** SAP workloads and vendor appliances can move only to certified
  families.

Each VM needs a dozen checks, and the answers change as VMs, quota, and
commitments change. A spreadsheet is out of date as soon as it's finished.

## The approach

Azure SRE Agent runs in your tenant with its own managed identity and works in
four steps:

| Step | What Azure SRE Agent does | Capabilities used |
| --- | --- | --- |
| **Analyze** | Finds every VM and scale set on an End of Life series, profiles its size, generation, disks, network, and utilization, and classifies the workload pattern | A coordinator custom agent, Azure Resource Graph, Azure Monitor |
| **Recommend** | Chooses a path (resize to v5, upgrade to v6 or v7, replace a pool, or stop at a vendor gate) and proposes a target family and size class with evidence | Skills, knowledge files |
| **Validate** | Checks quota headroom, zone availability, Azure Policy, capacity needs, and the disaster recovery footprint, and drafts quota requests for people to submit | Read-only Azure CLI |
| **Automate** (later) | Resizes pilot VMs in one resource group, one approved command at a time, verifies each change, and rolls back if a check fails | Review mode, tool access policies, hooks |

A weekly scheduled task repeats the read-only steps and reports what changed:
new VMs in scope, quota changes, expiring reservations, and progress on the
transition.

## Why Azure SRE Agent

| | Spreadsheet or one-time script | Azure SRE Agent |
| --- | --- | --- |
| **Freshness** | A snapshot that's out of date as soon as it's finished | Rescanned every week by a scheduled task |
| **Correlation** | People join inventory, metrics, quota, and owner data by hand | One conversation reasons across all of them |
| **Expertise** | Lives with a few people | Written once as skills and knowledge files, and applied in every run |
| **Control** | Runs with whatever permissions it has | Least-privilege identity, Review mode, tool access policies, and hooks |
| **Evidence** | Hard to trace | Each finding cites its query or command, and threads keep the history |

## Example output

For each VM, the agent writes a disposition record: where the VM should go, why,
and what's still to check. This synthetic example shows the main fields:

| VM | Current size | Retires | Proposed new home | Still to check |
| --- | --- | --- | --- | --- |
| `vm-contoso-erp-app01` | Standard_DS3_v2 | 2028-05-01 | Resize to the Ddsv5 family, 4-vCPU class | Temporary disk use; benchmark |
| `vm-contoso-sql01` | Standard_E32s_v3 | 2029-11-15 | Resize to the Edsv5 family, 32-vCPU class; quota is 8 vCPUs short, and a request is drafted | Capacity reservation decision |
| `vmss-contoso-web` (6 instances) | Standard_F4s_v2 | 2028-11-15 | Replace the pool with the Dldsv6 family through a new image | Image validation |
| `vm-contoso-fw01` | Standard_DS3_v2 | 2028-05-01 | A vendor-certified family only | Vendor certification |
| `vm-contoso-batch07` | Standard_D4_v3 | 2029-11-15 | Not proposed yet | Owner and workload class; no utilization data |

Targets are families and size classes, never final sizes. Unknowns are listed,
not guessed. Every record states that quota authorizes consumption but doesn't
reserve capacity. For the full record format, see
[`disposition-record.example.json`](templates/disposition-record.example.json).

## Adopt in phases

| Phase | How the agent runs | Done when |
| --- | --- | --- |
| 0. Scope | Not deployed yet | Subscriptions, owners, and two pilot groups are agreed |
| 1. Analyze | Read-only | Every affected VM is found and profiled, and unknowns are listed |
| 2. Recommend and validate | Read-only | Every VM has a path, a target family, and landing checks, and the weekly drift report runs |
| 3. Automate a pilot | Approval-gated, in one resource group | The first resizes succeed with verification, and a rollback is tested |
| 4. Review | Read-only outside the pilot | The team decides who runs the transition at scale |

## What the lab showed

The [demo lab](demo/README.md) placed seven VMs and a scale set on the Dsv3
series, deployed Azure SRE Agent with this kit, and scored the agent's answers
against an answer key. For every run and the changes made after it, see
[Lab results](demo/README.md#lab-results).

| Test | Result |
| --- | --- |
| Inventory and readiness queries | 133 of 133 checks passed |
| Assessment of the eight resources | 100 of 100 checks passed in the final run, after fixes to the skills and the evidence gate. Each run took 9 to 23 minutes |
| Weekly drift scan | Stayed read-only, kept the report template's section order, and recorded missing access as a data gap instead of requesting more access |
| Phase 3 pilot resize | Resized one VM from Standard_D2s_v3 to Standard_D2ds_v5. Each of its four write commands ran only after its own approval, and all of them stayed in the pilot resource group |

Lessons from the lab:

- **Validate the records.** The agent invented values for fields such as the
  workload class until the evidence gate listed the allowed values and named
  each field to fix.
- **Check Azure Policy first.** Quota and zone availability allowed the v5
  targets, but the subscription's allowed-size policy denied them for VMs. The
  pilot needed a temporary policy exemption on its resource group.
- **Prepare the pilot.** The pilot also needed a write role for the agent on the
  pilot resource group, a recent snapshot, and the owner's confirmation of
  temporary disk use and the exact target size.

Not yet tested with a live agent: a rollback, the executor declining work outside
the pilot, a week-over-week drift comparison, and estates larger than eight
resources. Each record is about 3,200 characters, so assess large estates in
batches.

## What it doesn't do

- Quote prices or promise savings or performance gains. It recommends a
  benchmark on the candidate size instead.
- Pick a final size or state that capacity is available.
- Buy reservations or savings plans, create capacity reservations, or submit
  quota requests. It drafts; people decide.
- Automate changes to vendor appliances, SAP-gated workloads, or domain
  controllers.
- Replace the people who own the design and the change. Its output is evidence
  and proposals.

## Who it's for

- Infrastructure and operations teams with VMs on End of Life series who need a
  per-VM plan they can trust.
- Architects and migration partners who want readiness, quota, and availability
  checked before they plan waves.
- Azure SRE Agent practitioners looking for a change and migration scenario that
  starts read-only.

## Get started

The [setup guide](docs/setup-guide.md) covers the architecture, prerequisites,
cost, setup, safety controls, limitations, and cleanup.

| Folder | Contents |
| --- | --- |
| [`agent/`](agent/) | Six custom agents (a coordinator, four read-only specialists, and a Phase 3 executor), four skills, hooks including an evidence gate, a tool access policy, and the weekly scheduled task |
| [`queries/`](queries/) | Resource Graph and Log Analytics queries for inventory, readiness, utilization, and a transition board with a next step for each VM |
| [`knowledge/`](knowledge/) | Public lifecycle dates and the target family framework, ready to upload |
| [`templates/`](templates/) | The disposition record schema, the weekly drift report, and the quota request draft |
| [`docs/`](docs/) | The setup guide, the pilot runbook, and test prompts |
| [`demo/`](demo/README.md) | A billable lab with VMs on an End of Life series, an agent with this kit, and scripts that score its assessments, drift scans, pilot resizes, and guardrails |
| [`tests/`](tests/) | Offline checks for the queries, dates, hooks, record schema, and scorers |

For retirements of other Azure services, see
[Azure Retirement Readiness](../azure-retirement-readiness/README.md).

## Learn more

- [VM lifecycle overview](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/lifecycle-overview)
- [VM size series retirements, capacity growth restrictions, and modernization guidance](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions)
- [Modernize to the v5 VM series](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/sizes-v5-modernization-overview)
- [Modernize to the v6 and v7 VM series](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/sizes-v6-v7-modernization-overview)
- [Azure SRE Agent overview](https://learn.microsoft.com/azure/sre-agent/overview)
- [Custom agents](https://learn.microsoft.com/azure/sre-agent/sub-agents), [skills](https://learn.microsoft.com/azure/sre-agent/skills), and [scheduled tasks](https://learn.microsoft.com/azure/sre-agent/scheduled-tasks) in Azure SRE Agent
- [Run modes](https://learn.microsoft.com/azure/sre-agent/run-modes), [tool access policies](https://learn.microsoft.com/azure/sre-agent/tool-access-policies), and [agent hooks](https://learn.microsoft.com/azure/sre-agent/agent-hooks)