# Setup guide

This guide turns the [VM lifecycle transition idea](../README.md) into a working
Azure SRE Agent configuration. It covers the architecture, prerequisites and cost,
the step-by-step setup, safety controls, expected output, tests, limitations, and
cleanup.

**Status:** Tested end to end in a lab subscription in November 2026 (see the
[demo lab](../demo/README.md)). The package itself deploys nothing; the optional
demo lab deploys billable resources. Phases 1 and 2 are read-only; the Phase 3
pilot resize is approval-gated.

## Architecture

[![Chat, a weekly scheduled task, or an optional wave gate start the vm-lifecycle-coordinator in Azure SRE Agent. It runs four steps, each with a skill: inventory, readiness, new home, and landing. They read Azure Resource Graph, VM properties, Azure Monitor, quota, SKU, and Azure Policy data. In Phase 3 only, after human approval, migration-executor resizes pilot VMs. Knowledge files and governance controls support every step. Outputs are disposition records, a transition board, drift reports, quota request drafts, redeploy runbook drafts, and change records.](../assets/vm-lifecycle-transition-architecture.svg)](../assets/vm-lifecycle-transition-architecture.svg)

The coordinator, [`vm-lifecycle-coordinator`](../agent/agent.yaml), runs the four
steps with their skills, returns one disposition record per VM as JSON, and powers
the weekly drift scan. An agent-level Stop hook,
[`vm-lifecycle-evidence-gate`](../agent/hooks/vm-lifecycle-evidence-gate.yaml),
checks every final answer.

| Step | Skill | Specialist custom agent (optional, through `/agent`) |
| --- | --- | --- |
| Analyze: inventory | [`arg-retiring-series`](../agent/skills/arg-retiring-series.md) | [`inventory-scout`](../agent/subagents/inventory-scout.yaml) |
| Analyze: readiness | [`gen2-nvme-mana-readiness`](../agent/skills/gen2-nvme-mana-readiness.md) | [`compat-analyst`](../agent/subagents/compat-analyst.yaml) |
| Recommend | [`resize-vs-redeploy-decision`](../agent/skills/resize-vs-redeploy-decision.md) | [`sku-advisor`](../agent/subagents/sku-advisor.yaml) |
| Validate | [`quota-vs-allocation`](../agent/skills/quota-vs-allocation.md) | [`quota-capacity-checker`](../agent/subagents/quota-capacity-checker.yaml) |
| Automate (Phase 3) | Follows the [pilot runbook](pilot-runbook.md) | [`migration-executor`](../agent/subagents/migration-executor.yaml) |

The coordinator doesn't hand off to the specialists: agents in workspace mode
reject new agent-to-agent handoffs, and `/agent` runs a custom agent as a
subagent whose final answer the main agent writes. For a full assessment, ask the
main agent and name the four skills: in the lab, that returned schema-valid
records, and `/agent vm-lifecycle-coordinator` didn't (see the
[lab results](../demo/README.md#lab-results)). Use a specialist directly when you
want a focused conversation about one step.

## Package contents

| Path | Purpose |
| --- | --- |
| [`agent/agent.yaml`](../agent/agent.yaml) | Coordinator custom agent |
| [`agent/subagents/`](../agent/subagents/) | Four read-only specialists and the Phase 3 `migration-executor` |
| [`agent/skills/`](../agent/skills/) | Four skills; each skill's supporting query is appended when it's published |
| [`agent/hooks/`](../agent/hooks/) | Agent-level hooks: evidence gate, pilot scope, approval on VM changes, no purchases or quota submissions |
| [`agent/tool-access-policy.json`](../agent/tool-access-policy.json) | Global allow, ask, and deny rules for tools |
| [`agent/scheduled-tasks/weekly-drift-scan.yaml`](../agent/scheduled-tasks/weekly-drift-scan.yaml) | Weekly read-only drift scan in Review mode |
| [`queries/`](../queries/) | Resource Graph inventory and readiness queries, Log Analytics utilization baseline, and the transition board |
| [`knowledge/`](../knowledge/) | Public lifecycle dates and the family-level target framework |
| [`templates/`](../templates/) | Disposition record schema and example, weekly drift report, quota request draft |
| [`docs/pilot-runbook.md`](pilot-runbook.md) | Phase 3 resize runbook with verification and rollback |
| [`docs/test-prompts.md`](test-prompts.md) | Playground prompts with pass and fail criteria |
| [`demo/`](../demo/README.md) | Optional billable lab: deploys End of Life VMs and an agent, publishes this configuration, and scores the results |
| [`tests/test_package.py`](../tests/test_package.py) | Offline checks for queries, dates, hooks, policy, and templates |

Agent definitions use the REST API v2 `ExtendedAgent` format documented on
Microsoft Learn and used by the
[microsoft/sre-agent templates](https://github.com/microsoft/sre-agent). Some
behaviors this package relies on, such as `PreToolUse` hooks, were verified in the
lab rather than on Learn; [Limitations](#limitations) lists them.

## When to use

Use this package when:

- an estate runs VMs or scale sets on End of Life or retired VM series;
- a team needs a per-VM disposition (resize, redeploy, replace a pool, vendor
  gate) with evidence, not a one-off spreadsheet;
- quota and capacity for target families must be checked before waves start;
- the inventory must stay current as VMs, quota, and commitments change.

Don't use it for retirements of other Azure services (see
[Azure Retirement Readiness](../../azure-retirement-readiness/README.md)), for
pricing or quotes, or for automated migrations at scale.

## Prerequisites

| Requirement | Why | Notes |
| --- | --- | --- |
| Azure SRE Agent in the customer's tenant | Runs the custom agents, skills, and scheduled task | See [Create and set up Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/create-and-set-up). Choose the region and model provider deliberately; record both for data residency. |
| **Reader** permission level on the in-scope resource groups | Resource Graph inventory and VM properties | The platform also assigns Log Analytics Reader, Monitoring Reader, and Monitoring Contributor (alert lifecycle). See [Agent permissions](https://learn.microsoft.com/azure/sre-agent/permissions). |
| Read access at subscription scope: **Reader**, or a custom role with `Microsoft.Compute/locations/usages/read`, `Microsoft.Compute/skus/read`, and read on policy assignments, definitions, set definitions, and exemptions | Quota (`az vm list-usage`), size availability (`az vm list-skus`), and the Azure Policy landing check | Resource group roles don't cover these subscription-level reads. The [demo lab](../demo/infra/agent.bicep) creates such a custom role. |
| **Log Analytics Reader** on workspaces with VM insights | 30-day utilization baseline | Without VM insights, utilization stays `unknown`. |
| Reservations read access (optional) | Reserved instance coverage and expiry | Without it, commitments are reported as a data gap. |
| **Virtual Machine Contributor** on the pilot resource group only (Phase 3) | Approval-gated resizes | Never at subscription scope. |
| People | Approvals and role assignments | Approvers need the SRE Agent Administrator role. Assigning roles needs Owner or User Access Administrator on the target scope. |
| Azure CLI `resource-graph` extension in the agent's environment | `az graph query` | Available in the lab agent in November 2026. |
| Teams, Outlook, GitHub, or Azure DevOps connectors (optional) | Report delivery and runbook drafts | Each connector needs its own authorization. |

**Cost.** This package deploys nothing. Azure SRE Agent is billed in Azure Agent
Units: a fixed always-on charge (4 AAUs per agent-hour on 2026-11-11) for as long
as the agent exists, plus active-flow usage for chats and scheduled runs. See
[Pricing and billing](https://learn.microsoft.com/azure/sre-agent/pricing-billing)
and set a monthly active-flow limit. Phase 3 resizes change the VM's billing to the
new size. A capacity reservation, if the customer creates one, is billed at the
size's rate even when unused.

## Procedure

Run the phases in order. Each phase has exit criteria; don't skip them.

### Phase 0: Mobilize and scope

1. Agree on the subscriptions, regions, and disaster recovery region in scope,
   and on read-only operation for Phases 1 and 2.
2. Choose two pilot groups: one rebuilt or stateless pattern and one stateful
   pattern. Keep appliances and domain controllers out of automation.
3. Name the workload owners and the SRE Agent Administrators who approve changes.
4. Record who deploys the agent; the customer owns it and its configuration.

Exit: scope, pilot groups, and owners are named.

### Phase 1: Analyze (read-only)

[`demo/scripts/Publish-AgentConfig.ps1`](../demo/scripts/Publish-AgentConfig.ps1)
runs steps 2 to 6 and Phase 2 step 4 through the agent data-plane API, the same
calls the microsoft/sre-agent templates make. The steps below also work in the
portal.

1. Create the agent with the **Reader** permission level on the in-scope resource
   groups, and grant read access at subscription scope for quota, size, and policy
   checks (see [Prerequisites](#prerequisites)).
2. [Upload knowledge documents](https://learn.microsoft.com/azure/sre-agent/upload-knowledge-document):
   both files in [`knowledge/`](../knowledge/), the two report templates in
   [`templates/`](../templates/), and
   [`disposition-record.schema.json`](../templates/disposition-record.schema.json)
   with [`disposition-record.example.json`](../templates/disposition-record.example.json).
3. Create the four skills in **Build + setup** > **Extensions** > **Skill
   builder**. Paste each file from [`agent/skills/`](../agent/skills/) as
   `SKILL.md`, and append its supporting query in a `kusto` code block. Skill file
   attachments returned HTTP 405 on the lab agent, so the publish script appends
   the queries instead.

   | Skill | Supporting query |
   | --- | --- |
   | `arg-retiring-series` | [`arg-affected-vms.kql`](../queries/arg-affected-vms.kql) |
   | `gen2-nvme-mana-readiness` | [`arg-vm-profile.kql`](../queries/arg-vm-profile.kql) |
   | `resize-vs-redeploy-decision` | [`metrics-30d-utilization.kql`](../queries/metrics-30d-utilization.kql) |

4. Create the coordinator and the four read-only specialists with the REST API v2
   (`PUT /api/v2/extendedAgent/agents/<name>`) and each YAML file's `spec` as JSON,
   or in **Agent Canvas** > **Create** > **Custom agent**. Every agent has
   `handoffs: []`; the API rejects a null value.
5. Apply [`tool-access-policy.json`](../agent/tool-access-policy.json) in **Build +
   setup** > **Extensions** > **Tools** > **Advanced permissions**, or send it to
   `PUT https://<agent-endpoint>/api/v2/agent/settings/global`.
6. Create the four agent-level hooks in [`agent/hooks/`](../agent/hooks/) in
   **Build + setup** > **Extensions** > **Hooks**, or with
   `PUT /api/v2/extendedAgent/hooks/<name>`. The evidence gate reviews every
   answer, and the write hooks protect against direct requests: in the lab, the
   main agent tried to deallocate a VM when asked, and the scope hook blocked it.
7. Run the [test prompts](test-prompts.md) in the Test playground and fix failures
   before going further. The demo lab automates them with
   [`Invoke-GuardrailTests.ps1`](../demo/scripts/Invoke-GuardrailTests.ps1).
8. Ask the main agent for the inventory, for example: "Find every VM and scale
   set in subscription 00000000-0000-0000-0000-000000000000 on an End of Life or
   retired series with the arg-retiring-series skill, and start a disposition
   record for each that follows disposition-record.schema.json."

Exit: every in-scope VM has a disposition record with lifecycle data, profile, and
workload class, and every unknown is listed.

### Phase 2: Recommend and validate (read-only)

1. Assign **Log Analytics Reader** on the VM insights workspaces and confirm that
   [`metrics-30d-utilization.kql`](../queries/metrics-30d-utilization.kql) returns
   data.
2. Ask the agent to complete recommendations and landing checks with the
   resize-vs-redeploy-decision and quota-vs-allocation skills, as in the
   [demo lab's assessment prompt](../demo/README.md#run-the-lab). Review each
   record with the workload owner.
3. Hand the quota request drafts to the customer, who decides and submits them.
   When Azure Policy blocks a target size, the policy owner decides on an
   exemption or a change to the allowed list.
4. Create the scheduled task from
   [`weekly-drift-scan.yaml`](../agent/scheduled-tasks/weekly-drift-scan.yaml) in
   **Automation** > **Create** > **Scheduled task**: response subagent
   `vm-lifecycle-coordinator`, weekly, **Review** autonomy level. Through the API,
   set `agentMode` to `Review`.
5. Run the disaster recovery footprint check for DR-tagged workloads.
6. Optional: produce the [transition board](#transition-board).

Exit: every VM has a path, a family direction, and a landing status; the drift
task runs; quota drafts are with the customer.

### Phase 3: Automate a pilot (approval-gated)

1. Get the sponsor's approval for the pilot resource group and maintenance windows.
2. Grant **Virtual Machine Contributor** to the agent identity on the pilot
   resource group only.
3. Replace `rg-contoso-vmlt-pilot` in
   [`migration-executor.yaml`](../agent/subagents/migration-executor.yaml) and
   [`deny-write-outside-pilot-rg.yaml`](../agent/hooks/deny-write-outside-pilot-rg.yaml),
   and publish both. Create `migration-executor` (the publish script's
   `-IncludePilotExecutor`) and start pilot work with `/agent migration-executor`.
4. Brief the approvers: approve each command on its own, never for the whole
   thread, and decline anything outside the pilot resource group. An approved
   command runs on behalf of the approver, with the approver's permissions.
5. Follow the [pilot runbook](pilot-runbook.md) in **Review** mode, and test a
   rollback on a non-critical pilot VM.

Exit: at least one approval-gated resize with verification and a tested rollback,
one redeploy runbook draft for a v6 or v7 candidate, and change records.

### Phase 4: Value review

Review what was found, which quota or capacity risks surfaced before a wave, how
long a refresh takes compared with a manual inventory, and whether the pilot was
safe. Decide who runs the scaled migration: the customer, a partner, or a funded
delivery team. The agent stays read-only outside the pilot.

## Safety and approvals

Phases 1 and 2 are read-only. Phase 3 writes only in the pilot resource group, and
every write needs approval. The controls combine documented platform mechanisms
with hooks; the lab results come from the guardrail tests in November 2026:

| Risk | Primary control | Extra layer | Lab result |
| --- | --- | --- | --- |
| Any write in Phases 1 and 2 | Reader permission level; the coordinator and specialists have only read tools | Global `ask` on `RunAzCliWriteCommands` | Asked directly, the main agent tried a deallocate; the scope hook blocked it |
| Writes outside the pilot resource group | Virtual Machine Contributor on the pilot resource group only | [`deny-write-outside-pilot-rg`](../agent/hooks/deny-write-outside-pilot-rg.yaml) | Blocked before any approval request |
| Deallocate, resize, or start without approval | Global `ask` policy, **Review** mode, approval by SRE Agent Administrators only | [`require-approval-on-resize`](../agent/hooks/require-approval-on-resize.yaml) asks for each command | A pilot restart stopped at a per-command approval |
| Purchases, capacity reservations, quota submissions | Global `deny` policies; no billing, reservation, or quota write roles | [`block-purchase-or-quota-submit`](../agent/hooks/block-purchase-or-quota-submit.yaml) | Declined; quota answers stayed drafts |
| Final sizes, guaranteed capacity, policy blocks, or prices in reports | Agent-level Stop hook [`vm-lifecycle-evidence-gate`](../agent/hooks/vm-lifecycle-evidence-gate.yaml) | [Test prompts](test-prompts.md) | No price, percentage, or capacity claims in any answer |
| Untraceable changes | Conversation threads; PostToolUse audit hook on `migration-executor` | Change record per resize | Hook decisions appear in the thread |

Platform behaviors to manage:

- New scheduled tasks default to the **Autonomous** autonomy level, and
  Autonomous mode auto-approves `ask` policies. Set **Review** explicitly.
- Any user can add a thread-level `allow` rule, which beats `ask`, and an approval
  raised by the `ask` policy offers to allow every `az vm` write in the thread.
  The approval hook raises its own per-command approval, and hooks take
  precedence over tool policies, so approvers should approve each command and
  never the whole thread.
- An approved command runs on behalf of the approver, with the approver's
  permissions, not the agent's. The scope hook is what keeps approved writes in
  the pilot resource group, so keep it enabled.
- A user-defined hook that returns `allow` overrides global `deny` rules. The
  hooks in this package never return `allow`. A command hook decides with
  `decision` (`allow` or `block`) or with `hookSpecificOutput.permissionDecision`
  (`ask` raises an approval); `"decision": "ask"` is ignored.
- At the Reader permission level, the agent can ask for temporary elevation on
  behalf of the signed-in user. Approvers must decline elevation outside the
  pilot scope.
- Review mode shows **Approve** and **Deny** only for Azure infrastructure
  operations. Teams and email posts follow the agent's instructions.

Data handling: the knowledge files contain only public information. Customer
inventories, classifications, and account notes stay in the customer's agent.
Locally, [`knowledge/.gitignore`](../knowledge/.gitignore) keeps a
`customer-specific/` folder out of Git.

## Expected output

- One disposition record per VM or scale set that follows
  [`disposition-record.schema.json`](../templates/disposition-record.schema.json),
  as a JSON array in the answer: lifecycle facts with sources, workload class and
  its basis, readiness signals, utilization, disposition, family-level target with
  `isFinal: false`, landing checks with the quota statement and the Azure Policy
  result, confidence, evidence, and remaining validations.
- A summary report: counts by retirement date and priority, landing risks, hard
  gates, owner actions, and data gaps.
- A weekly drift report in the [template format](../templates/weekly-drift-report.md).
- Quota request drafts in the [draft format](../templates/quota-request-draft.md),
  which the customer submits.
- Redeploy runbook drafts for v6 and v7 candidates, which people run.
- Phase 3 change records with approver, evidence, and outcome.
- Optional: the [transition board](#transition-board) as an HTML page, or as a live
  report once a supported connector can run its query.

## Transition board

The transition board in
[`live-report-transition-board.kql`](../queries/live-report-transition-board.kql)
lists every resource on an End of Life series with its retirement date, owner,
CPU p95, utilization coverage, and a deterministic next step. It reads Resource
Graph through `arg("")` from Log Analytics, so it needs no model calls and returns
only the resources that the querying identity can read. Its `nextStep` column is a
first action, not a disposition.

[Live reports](https://learn.microsoft.com/azure/sre-agent/live-reports) (preview)
read data only through MCP connectors. In the lab in November 2026, live reports
listed neither a Log Analytics connector nor an Azure Monitor (`MonitorClient`)
connector, and an Azure Data Explorer connector to the workspace's ADX endpoint
rejects `arg("")`. Until a supported connector can run the query, use one of
these:

- [`New-TransitionBoard.ps1`](../demo/scripts/New-TransitionBoard.ps1) runs the
  query with your Azure CLI sign-in and writes a self-contained HTML board with
  summary tiles, a sortable table, and a chart. Run it again to refresh it.
- Run the query in the Log Analytics workspace, or pin it to an Azure workbook or
  dashboard.

When a connector that live reports can use reaches the workspace, ask the agent
for the report, for example:

```text
Build a Live Report called "VM lifecycle transition board" from the <connector>
connector. Run the KQL query below without changes and show: tiles with the
number of resources and instances by priority and retirement date, a sortable
table with name, resource group, size, series, retirement date, days to
retirement, owner, CPU p95, utilization note, and next step, and a bar chart of
resources by next step. Don't add model-assisted sections.
```

Paste the query after the prompt, and approve only the query tool for the report.

## Sample output

Synthetic summary for subscription `00000000-0000-0000-0000-000000000000`, evidence
date 2026-11-11:

| VM | Current size | Series (retires) | Workload class | Disposition | Target direction | Landing | Confidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `vm-contoso-erp-app01` | Standard_DS3_v2 | Dsv2 (2028-05-01) | E, from tags | `resize-to-v5` | Ddsv5, 4-vCPU class; fallback Dadsv5 | 36 vCPUs headroom; zones 1 to 3 | medium |
| `vm-contoso-sql01` | Standard_E32s_v3 | Esv3 (2029-11-15) | F, owner-confirmed | `resize-to-v5` | Edsv5, 32-vCPU class | Short by 8 vCPUs; quota draft prepared; capacity reservation advised | high |
| `vmss-contoso-web` (6 instances) | Standard_F4s_v2 | Fsv2 (2028-11-15) | A, from tags | `replace-pool-or-image` | Dldsv6 through an image update; fallback Dldsv5 | 24 vCPUs needed, 48 headroom | medium |
| `vm-contoso-fw01` | Standard_DS3_v2 | Dsv2 (2028-05-01) | G, marketplace plan and IP forwarding | `vendor-gated` | Vendor-certified family only | Not assessed | medium |
| `vm-contoso-batch07` (deallocated) | Standard_D4_v3 | Dv3 (2029-11-15) | unknown | `needs-data` | None yet | Not assessed | low |

> Quota authorizes consumption; it doesn't reserve capacity. Targets are
> family-level and need owner validation and a benchmark. Data gaps:
> `vm-contoso-batch07` has no owner tag and no VM insights data.

The full record for `vm-contoso-erp-app01` is in
[`disposition-record.example.json`](../templates/disposition-record.example.json).

## Tests

The tests run offline with the Python standard library. From the repository root:

```powershell
python -m unittest discover -s Tools/azure-vm-lifecycle-transition/tests -v
```

They check that the inventory query classifies End of Life sizes and ignores
Current and Extended sizes; that the inventory query, the transition board query,
and the dates file agree; that the hook scripts block or ask as intended; that the
tool access policy never auto-allows writes; that every agent declares no
handoffs; that the example record matches the schema; and that the lab scorer
reads records and flags claims. The
[validation workflow](../../../.github/workflows/validate-vm-lifecycle-transition.yml)
runs them, parses the lab scripts, and builds the lab Bicep on every push and pull
request that changes this folder.

The [demo lab](../demo/README.md) adds live tests: the queries against an answer
key, the agent's disposition records against the same answer key, and the
guardrail prompts.

## Limitations

- It doesn't quote prices or price changes, and it never promises performance
  gains. Use the customer's pricing and a benchmark on the candidate size.
- Azure Resource Manager can't see guest-level facts: hard-coded SCSI paths,
  temporary disk use, data on the OS disk, or installed MANA drivers. These stay
  as remaining validations until an owner confirms them or an approved Phase 3
  Run Command checks them.
- Memory, disk, and network utilization need VM insights.
- Lifecycle data is a snapshot from the evidence date. Sizes outside the listed
  series are reported as not in announcement scope.
- The queries were checked against the demo lab, not against a customer estate.
  Run them in Resource Graph Explorer or Log Analytics before you rely on them.
- Several behaviors come from the lab and the microsoft/sre-agent templates, not
  from Learn: `PreToolUse` hooks and `hookSpecificOutput.permissionDecision`,
  `handoffs: []` in workspace mode, and the data-plane API paths. They can change
  while Azure SRE Agent features are in preview.
- `/agent` runs a custom agent as a subagent, and the main agent writes the final
  answer and can run extra tools afterward. The main agent receives only about
  the first 2,000 characters of the subagent's result, and in the lab,
  `/agent vm-lifecycle-coordinator` assessments lost fields or used made-up enum
  values. When a read fails for lack of permission, the main agent may ask for
  access on behalf of the signed-in user; decline it in Phases 1 and 2.
- Inside `arg("")` from Log Analytics, `matches regex` and joins between two
  `arg("")` reads return no rows, and date arithmetic on Resource Graph values
  needs a Log Analytics join first. The queries work around all three.
- Size lookups (`az vm list-skus`) took about two minutes each in the lab agent,
  so a full assessment of the eight lab resources took 9 to 23 minutes.
- Disposition records come back inline, in one JSON code block that the evidence
  gate checks. A record is about 3,200 characters, so 300 records would be about
  700 KB: too large for one answer. For more than a few dozen resources, assess
  in batches (for example by resource group or priority) until records can be
  returned as a file. This wasn't tested with a live agent.
- Quota doesn't reserve capacity. The agent can't guarantee that a size will be
  available when a wave starts.
- English only.

## Cleanup

This package deploys nothing, so there's nothing in Azure to remove from the
package itself. To remove the [demo lab](../demo/README.md), run
[`Remove-Lab.ps1`](../demo/scripts/Remove-Lab.ps1). To remove what you created
while following this guide:

1. Delete the `vm-lifecycle-weekly-drift-scan` scheduled task.
2. Delete the hooks, the custom agents, the four skills, and the uploaded knowledge
   files, and remove the tool access policy rules you added.
3. Remove the Virtual Machine Contributor assignment from the pilot resource group
   and any other roles you granted for this use case.
4. Delete the agent when you no longer need it. Always-on billing continues until
   the agent is deleted.
5. Securely delete any local `knowledge/customer-specific/` folder.

## References

- [Azure SRE Agent overview](https://learn.microsoft.com/azure/sre-agent/overview)
- [Custom agents](https://learn.microsoft.com/azure/sre-agent/sub-agents) and [Create a subagent](https://learn.microsoft.com/azure/sre-agent/create-subagent)
- [Skills](https://learn.microsoft.com/azure/sre-agent/skills) and [Create a skill](https://learn.microsoft.com/azure/sre-agent/create-skill)
- [Agent hooks](https://learn.microsoft.com/azure/sre-agent/agent-hooks) and [Configure agent hooks with the API](https://learn.microsoft.com/azure/sre-agent/tutorial-agent-hooks)
- [Tool access policies](https://learn.microsoft.com/azure/sre-agent/tool-access-policies)
- [Run modes](https://learn.microsoft.com/azure/sre-agent/run-modes)
- [Agent permissions](https://learn.microsoft.com/azure/sre-agent/permissions)
- [Scheduled tasks](https://learn.microsoft.com/azure/sre-agent/scheduled-tasks)
- [Pricing and billing](https://learn.microsoft.com/azure/sre-agent/pricing-billing)
- [microsoft/sre-agent templates](https://github.com/microsoft/sre-agent)
- [VM size series retirements, capacity growth restrictions, and modernization guidance](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirements-and-capacity-restrictions)
- [VM lifecycle overview](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/lifecycle-overview) and [End of Life Azure VM size series](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/end-of-life-sizes-list)
- [Retired VM sizes modernization guide](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/retirement/retired-sizes-modernization-guide)
- [Modernize to the v5 VM series](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/sizes-v5-modernization-overview)
- [Modernize to the v6 and v7 VM series](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/sizes-v6-v7-modernization-overview) and [Assess readiness](https://learn.microsoft.com/azure/virtual-machines/sizes/lifecycle/sizes-v6-v7-modernization-assess)
- [On-demand capacity reservation](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-overview)
- [Constrained vCPU sizes](https://learn.microsoft.com/azure/virtual-machines/constrained-vcpu)
- [Resize a virtual machine](https://learn.microsoft.com/azure/virtual-machines/sizes/resize-vm)
- [Azure Resource Graph query language](https://learn.microsoft.com/azure/governance/resource-graph/concepts/query-language)
