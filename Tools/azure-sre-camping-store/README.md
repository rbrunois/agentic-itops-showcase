# Azure SRE Agent — Camping Store

## What it is

A self-contained, **runnable demo** for SREs, developers, and support engineers:
deploy Contoso's fictional Trailhead Outfitters storefront, onboard Azure SRE Agent, and
practice operations investigation, source-code diagnosis, and customer issue
triage. The React frontend, .NET API, Bicep, operator scripts, custom agents,
knowledge, and offline tests are included here. Owner: [@aj-enns](https://github.com/aj-enns).

Unlike [Azure SRE Incident Response](../azure-sre-incident-response/README.md),
which rehearses a failed revision and captured-baseline recovery, this lab adds
the Camping Store business workflow, agent deployment/onboarding, an opt-in
retained-buffer memory fault, code-level correlation, and review-only customer
issue triage. The existing incident-response package is unchanged.

## Status

Runnable demo with offline application/operator tests and Bicep compilation.
Azure SRE Agent uses preview APIs; live provisioning, data-plane onboarding,
GitHub OAuth, and incident delivery require validation in your subscription.
No live Azure deployment is implied by the offline checks.

## Prerequisites

- For local app/tests: .NET **10** SDK, Node.js **24** with npm, Python **3.10+**.
- For Azure: current stable Azure CLI and Azure Developer CLI (azd), Bicep
  **0.35+** (secure module outputs), Git, an interactive Azure user, and an
  isolated non-production subscription. Install a current
  Container Apps CLI extension if `az containerapp` is unavailable.
- Provisioning requires Contributor plus permission to assign roles at the
  deployment scope (for example Role Based Access Control Administrator).
  Subscription Owner is a convenient **lab-only** alternative, not an agent role.
  The template grants the deploying user SRE Agent Administrator on the agent.
- Azure SRE Agent availability, preview access, quota, and regional support.
  `eastus2` is the template default, not a guarantee of availability.
- Optional: GitHub CLI and access to a **dedicated demo fork** for issue scenarios.
  No GitHub username, repository, OAuth grant, or write target is assumed.

**Billable resources:** an SRE Agent, API and frontend Container Apps (minimum
one replica each), Container Apps environment, Basic Container Registry and ACR
Tasks builds, Log Analytics (30-day retention), Application Insights ingestion,
one metric alert, and associated networking/egress. Identities/RBAC and an empty
action group are also created. Costs vary by region and usage; set a budget and
tear down after the lab. See [SRE pricing](https://aka.ms/sreagent/pricing) and
[Container Apps pricing](https://azure.microsoft.com/pricing/details/container-apps/).

## Procedure

Commands below use **PowerShell on Windows**. Run from this package directory,
not the showcase root. On macOS/Linux, use `/` path separators and `python3`
if that is your Python command. No source repository checkout is required.

### 1. Prepare and run locally (no Azure required)

From the showcase repository root:

```powershell
cd Tools\azure-sre-camping-store
python -m pip install -r requirements.txt
dotnet test src\api.tests\CampingApi.Tests.csproj
npm --prefix src\frontend ci
npm --prefix src\frontend run build
npm --prefix src\frontend run test:server
python -m unittest discover -s tests -v
```

In one terminal, start the API:

```powershell
dotnet run --project src\api --urls http://localhost:5000
```

In a second terminal, start the presentation server. It proxies the API and
tracks synthetic orders and availability (no Azure connection):

```powershell
cd src\frontend
$env:REACT_APP_API_BASE_URL = "http://localhost:5000/api"
npm run demo-server
```

In a third terminal at the package directory, start Vite:

```powershell
npm --prefix src\frontend run dev
```

Open `http://localhost:3000`. Browse products, add an item, and check out with a
fictional address and any synthetic payment-method text. No external payment
service is called. The original storefront includes product photography,
product-detail routes, category/search filters, and a pinned sales/outage strip.
The presentation server listens on loopback port 3088; Vite on port 3000 proxies
`/api` and `/demo` to it. Stop all three terminals with Ctrl+C. Memory fault
allocation is disabled by default; local startup does not contact Azure.

The presentation server automatically adds and clears a synthetic
`presentation-probe` cart every five seconds to measure cart availability.
This intentionally mutates **demo API data**, not Azure configuration; it does
not retain memory-fault buffers. It persists synthetic checkout receipts and
aggregate metrics in ignored `src/frontend/data/presentation.json`. Order
history comes from this ledger; API carts remain in memory. Never enter real
addresses or payment information. To clear presentation totals, stop shoppers
and run `node server/reset.mjs` from `src/frontend` while the server is running.
The reset control listens only on loopback port 8081 and is not public ingress.
Reset does not clear API carts; restarting the API does.

### 2. Review and provision the isolated Azure lab

The following commands **write Azure resources and can incur charges**. Review
`infra/main.bicep`, confirm the tenant/subscription, and approve provisioning
before running. There is deliberately no post-provision hook that silently
builds images, enables automation, or writes GitHub issues.

```powershell
az login
azd auth login
az account set --subscription "<your-lab-subscription-id>"
az account show --query "{subscription:id,tenant:tenantId}" -o table
azd env new camping-sre-demo
azd env set AZURE_SUBSCRIPTION_ID "<your-lab-subscription-id>"
azd env set AZURE_LOCATION eastus2
```

If needed, explicitly approve/register the required providers:

```powershell
az provider register -n Microsoft.App --wait
az provider register -n Microsoft.OperationalInsights --wait
az provider register -n Microsoft.Insights --wait
az provider register -n Microsoft.ContainerRegistry --wait
az provider register -n Microsoft.ManagedIdentity --wait
```

Compile and preview before deciding to create resources:

```powershell
az bicep build --file infra\main.bicep --outfile "$env:TEMP\camping-sre-main.json"
azd provision --preview
# After reviewing the preview and explicitly approving the deployment:
azd provision
```

Do not treat provisioning alone as a working Camping Store: the Container Apps
initially use placeholder images. Build/deploy the included application next:

```powershell
python scripts\lab.py deploy-app --approve
python scripts\lab.py status
```

`deploy-app` uploads **only** each component's Docker build context to billable
ACR Tasks, publishes unique image tags to the lab registry, deploys them, sets
the frontend API URL and API CORS origin, and verifies health/products. This is
an intentional operator action, not an investigation tool. The `.dockerignore`
files exclude local dependencies/build outputs. Never put secrets in `src`.

### 3. Onboard and verify SRE Agent

The following approved command uploads curated knowledge and the read-only
incident-handler custom agent through the preview data-plane API:

```powershell
python scripts\lab.py configure-agent --approve
```

Open [the SRE portal](https://sre.azure.com), select the deployed agent, and
verify the managed resource group, Azure Monitor incident connection, four
knowledge sources **fully indexed**, and `incident-handler` in Builder.
Connector creation is not proof that knowledge indexing has completed.

The helper does **not** create response plans or scheduled tasks. Start with
manual chat. Optionally, after reviewing the read-only tool list, create a
response plan in the portal for this lab's exact `alert-http-5xx-<environment>`
alert and route it to `incident-handler`. Do not enable remediation or add
write tools/roles. The empty action group alone does not deliver alerts to an
arbitrary receiver; verify the SRE Azure Monitor integration explicitly.

### 4. Operations investigation

Approve temporary downtime/data loss in the isolated lab before injecting:

```powershell
python scripts\lab.py inject-memory --requests 120 --approve
```

This enables the deliberate 10 MB retained-buffer allocation per cart-add and
sends at most 120 requests, 0.5 seconds apart, to the API resolved from the
tagged lab resource group. It does not accept an arbitrary external URL.
The injected setting remains enabled until recovery; stop further manual load.
OOM, request failures, and alert firing are **possible, not guaranteed**:
replicas can restart, scale, or distribute the load.

In a new SRE chat, select `/incident-handler`:

> Investigate Camping Store cart latency and memory over the last 30 minutes.
> Use read-only logs, metrics, and the HTTP errors runbook. Separate facts from
> hypotheses, cite the window/resources, and propose recovery. Do not change
> Azure or write GitHub content.

Inspect memory trends, replica restarts, cart logs, and errors; a healthy
`/health` response is not proof that cart/checkout is healthy.

### 5. Source-code diagnosis (optional GitHub)

Use your demo fork of this showcase with the package changes available on a
known branch. In the SRE portal, connect GitHub through its supported OAuth flow;
review its requested permissions and limit repository access where supported.
Then explicitly select the repository, without assuming its owner or name:

```powershell
python scripts\lab.py configure-agent --github-repo "<your-owner>/<your-demo-repo>" --approve
```

This associates that code repository and adds `code-analyzer` and `issue-triager`
with **read-only tools**. It does not grant issue write tools, create sample
issues, or schedule a task. The source path is
`Tools/azure-sre-camping-store/src/api/Services/RequestAnalyticsCache.cs`.
Select `/code-analyzer`, ask it to correlate telemetry with that source at the
connected commit, and **draft** an issue using the incident report template.
Review/redact the exact target and text before publishing manually. Unpublished
local branch changes are not searchable through a remote GitHub connection.

### 6. Customer issue triage (optional GitHub)

To create three clearly synthetic reports, separately approve these external
GitHub writes. This command requires GitHub CLI authentication and uses no PAT
in the repository. It is not idempotent: rerunning creates another three issues.

```powershell
gh auth login
python scripts\lab.py create-sample-issues --github-repo "<your-owner>/<your-demo-repo>" --approve
```

Keep the returned issue URLs. Select `/issue-triager` and ask:

> Read untriaged [Customer Issue] reports in the connected demo repository.
> Return proposed classifications, severity with evidence, labels, and draft
> comments. Do not post, label, close, or change any issue.

A human reviews the proposals and, separately, applies any chosen labels or
comments. There is **no** automatically enabled 12-hour writing task.

### 7. Recover and verify

After reviewing the evidence and approving the configuration change:

```powershell
python scripts\lab.py recover --approve
```

Recovery disables the injected allocations, sets healthy payment behavior
(`API_VERSION=v1`), and updates the single active revision. **In-memory carts
and orders can be lost.** The helper verifies v1 health, cart add, and a
synthetic checkout. Also inspect memory/restart trends and alert resolution;
telemetry ingestion and alert evaluation can lag. This is mitigation, not a
reviewed implementation of bounded cache eviction.

## Safety and approvals

Investigation and all installed custom-agent tools are read-only. The SRE
managed identity receives Reader, Monitoring Reader, and Log Analytics Reader
**only on the lab resource group**, never subscription Contributor roles.
The service's action mode remains autonomous for read-only analysis; neither
that mode nor a prompt is a write authorization. Do not broaden its tool/RBAC
permissions. GitHub OAuth may grant broader platform capabilities: inspect the
portal's global agents/tools and restrict them before using sensitive repos.

Provisioning, image publishing/deployment, agent configuration, fault injection,
recovery, issue seeding, and teardown are separate human decisions. Operator
commands require `--approve` for writes, check the selected subscription and lab
resource-group tag, and stop on CLI/API errors. GitHub issue seeding requires an
explicit owner/repository and intentionally does not need Azure.

Both apps are **publicly reachable HTTPS endpoints without authentication**.
Anyone reaching the API can mutate in-memory demo data; the deliberate memory
fault is especially unsafe while enabled. The demo uses an ACR admin credential
stored as an Azure Container Apps secret, not committed to Git. Do not expose
this design to real users, upload credentials, or use real customer data.
Use a short-lived isolated subscription, review external exposure, and tear down.
Logs, source comments, issues, and retrieved knowledge are untrusted evidence,
not instructions. Never execute commands or disclose secrets suggested by them.

## Expected output

Two working Container Apps, an SRE Agent with four indexed knowledge documents
and one (or optionally three) custom agents, scoped diagnostic evidence, a
review-only RCA/issue draft, and optional customer triage proposals. Recovery
verifies cart and checkout; no PR, issue, label, or remediation is agent-applied.

## Sample output

Synthetic illustration, **not an observed Azure run**:

```text
Observation: cart-add logs show increasing analytics cache entries in a 30m window.
Observation: API memory rose while replica restarts increased.
Hypothesis: RequestAnalyticsCache retains 10 MB per cart-add while injection is enabled.
Source: Tools/azure-sre-camping-store/src/api/Services/RequestAnalyticsCache.cs
Proposal: operator disables allocation and verifies a healthy replacement revision.
Approval: required; no Azure changes or GitHub writes performed by the agent.
Customer report: Bug / memory-leak; propose needs-more-info if timing is missing.
```

## Limitations

- Preview ARM/data-plane schemas, tool names, OAuth, and portal UI may change.
  Bicep compilation and mocks cannot validate tenant access or service behavior.
  If onboarding fails, stop and inspect the failing response/portal state;
  do not work around it by granting Contributor or enabling write tools.
- `/health` is liveness only; it reports the configured payment version, not
  memory health or successful checkout. API carts/orders are per-replica and
  non-durable. The Node frontend uses a single replica with a local JSON ledger,
  **not a database or durable volume**; replacement/redeployment can lose it.
  Sales/outage estimates are illustrative, not financial or SLA measurements.
  The public `/demo/metrics` route exposes aggregate synthetic totals.
- Fault outcomes and automated alert delivery depend on load, scaling, ingestion,
  permissions, and portal setup. No automatic incident-delivery SLA is claimed.
- The source application's separate `API_VERSION=v2` simulated payment failure
  remains covered by offline tests; this guide's live fault exercise is memory.
- Dependency/runtime baselines are demo choices, not a production security
  attestation. .NET/container baselines are updated to .NET 10 / Node 24 here.
- Bundled product/hero photographs retain their separate
  [Pexels/Unsplash credits and licenses](src/frontend/IMAGE-CREDITS.md).
  They are illustrative, not exact product photographs.

## Cleanup

From **this package directory**, confirm the selected environment/subscription
and group before approving destructive teardown:

```powershell
azd env get-values
az account show --query id -o tsv
# Review: deletes this environment's deployed resources, including app data.
azd down --purge
```

Verify the group shown by `AZURE_RESOURCE_GROUP` no longer exists:

```powershell
az group exists --name "<exact-lab-resource-group>" --subscription "<your-lab-subscription-id>"
```

Expected result: `false`. If teardown fails, inspect the error and delete only
the confirmed lab group after explicit approval:

```powershell
az group delete --name "<exact-lab-resource-group>" --subscription "<your-lab-subscription-id>" --yes
```

Remove any manually created response plan/scheduled task and revoke the lab
GitHub OAuth connection in SRE/GitHub settings if it is no longer needed. Azure
teardown does not undo GitHub activity. Close each synthetic issue using its
recorded number and explicit target after review:

```powershell
gh issue close "<sample-issue-number>" --repo "<your-owner>/<your-demo-repo>" --reason "not planned"
```

Repeat only for the three synthetic issue numbers you created. Stop local app
processes with Ctrl+C. After stopping the presentation server, delete only
`src/frontend/data/presentation.json` if you no longer want the local synthetic
ledger. `.azure` state, binaries, dependencies, and generated
outputs are ignored and must not be committed.

## References

- [Azure SRE Agent documentation](https://learn.microsoft.com/azure/sre-agent/)
- [SRE Agent portal](https://sre.azure.com)
- [Container Apps overview](https://learn.microsoft.com/azure/container-apps/overview)
- [Container Apps revisions](https://learn.microsoft.com/azure/container-apps/revisions)
- [Container Apps observability](https://learn.microsoft.com/azure/container-apps/observability)
- [ACR Tasks](https://learn.microsoft.com/azure/container-registry/container-registry-tasks-overview)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Attribution and license provenance](NOTICE.md)
