# Azure SRE Incident Response

## Purpose

Demonstrate a complete, human-approved incident workflow with a small Node.js
service on Azure Container Apps: establish a healthy baseline, inject a scoped
failure, investigate with Azure SRE Agent and curated knowledge, approve
recovery, and verify the result.

This package complements the toolbox's architecture documentation and fleet
assessment offerings with a runnable application incident scenario. It includes
the workload and operator tools, **not an implementation or automatic
installation of Azure SRE Agent**. Adapted from the contributor's existing SRE
demo with local credentials, personal environment settings, and Git history
excluded.

**Status:** runnable demo. The app, operator scripts, Bicep, and container are
validated offline in CI; live Azure and SRE Agent behavior requires a separate
authorized rehearsal (see [Limitations](#limitations)).

## When to use

Use for an isolated demonstration of deployment correlation, crash-loop
diagnosis, evidence-backed rollback proposals, and approval boundaries.
Do not use against production, shared workloads, or a customer environment.

> [!WARNING]
> **Unauthenticated endpoint.** The demo app uses external Container Apps
> ingress with no authentication. It serves only synthetic data. Provisioning
> requires an explicit exposure decision: restrict ingress to approved source
> ranges with `provision.ps1 -AllowedIngressCidr` (Bicep `allowedIngressCidrs`,
> recommended; include the operator address used for health checks), or pass
> `-AllowPublicIngress` to accept an endpoint that anyone who learns the FQDN
> can reach. With neither (or both), the script stops before any Azure call.
> Tear the environment down after the rehearsal.

> [!CAUTION]
> **Billable resources.** Provisioning creates a Container Apps environment and
> app, Log Analytics, Application Insights, alerts, and optionally an Azure
> Container Registry. Set an [Azure budget alert](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets)
> on the subscription or resource group first. Nothing is deleted automatically,
> including after a failed run; see [Cleanup](#cleanup).

## Prerequisites

For local use: a supported Node.js runtime matching [package.json](app/package.json)
and the [Dockerfile](app/Dockerfile), npm, and optionally Docker.
PowerShell 7 is required for operator scripts and their offline tests.

For an explicitly approved live rehearsal:

- Azure CLI with the Container Apps and Application Insights capabilities,
  Bicep, a signed-in operator, and registered resource providers.
- An operator-selected subscription, dedicated demo resource group, suitable
  region and quotas, and permission to create only the required resources.
- An ingress decision: the approved IPv4 source range(s) for
  `-AllowedIngressCidr`, including the operator's public address (for example
  `203.0.113.10/32`), or explicit approval to use `-AllowPublicIngress`.
- A public container image built from this package, or permission to build
  it in a new private ACR using the provisioning script's `-RegistryName` mode.
  Never publish private application code or configuration to make a pull work.
- Separate Azure SRE Agent onboarding, read-only resource/log access, knowledge
  attachment, and alert/incident routing configured for the selected scope.
- An operator authorized to approve infrastructure changes, simulated downtime,
  traffic changes, and recovery.

See [deployment and onboarding](docs/deployment.md) for permissions, image
publishing, telemetry, current product references, and cost/teardown boundaries.

### Least-privilege roles

Use separate identities for each responsibility and scope roles to the
dedicated demo resource group wherever possible.

| Identity | Needs | Suggested built-in roles |
| --- | --- | --- |
| **Operator** running `provision.ps1`, `demo-break.ps1`, `demo-fix.ps1` | Create the new resource group, then manage resources inside it | **Contributor** at subscription scope only for the provisioning run (or have an administrator pre-approve group creation), then **Contributor** on the demo resource group. `-RegistryName` mode also needs **Role Based Access Control Administrator** on the group, constrained to assigning `AcrPull`. |
| **Deployment identity** (inactive [workflow blueprint](examples/deploy.yml), OIDC) | Redeploy the app into an existing group and environment | **Contributor** on the demo resource group only; no subscription scope and no role-assignment rights. |
| **Investigating agent** (Azure SRE Agent) | Read revisions, logs, metrics, and alerts | **Reader** on the demo resource group plus **Log Analytics Reader** on the demo workspace (or **Monitoring Reader**). No write access; recovery is executed by the operator after approval. |

## Procedure

1. **Run locally.** From the repository root:

   ```powershell
   Set-Location Tools\azure-sre-incident-response\app
   npm ci
   npm test
   npm start
   ```

   The default port is 8080. `/healthz` returns
   `{"status":"ok","version":"1.2.0"}` and `/readyz` returns `{"ready":true}`.
   Telemetry is optional; do not set credentials for local tests.

2. **Prepare the environment.** Follow [deployment](docs/deployment.md).
   Deployment and image publication are separate operator decisions. The
   [workflow blueprint](examples/deploy.yml) is outside the root workflow
   directory and cannot run as stored. Prefer an image pinned by digest
   (`<registry>/<image>@sha256:<digest>`); `-RegistryName` mode pins
   automatically. Mutable tags can silently change what a later revision runs.
   From `Tools\azure-sre-incident-response`, preview and then provision with
   an ingress allow-list:

   ```powershell
   $scope = @{
       SubscriptionId = '<subscription-guid>'
       ResourceGroup  = '<dedicated-demo-resource-group>'
       AppName        = '<demo-app>'
   }
   $image = '<registry>/<image>@sha256:<digest>'
   .\scripts\provision.ps1 @scope -Location canadacentral -Image $image `
       -AllowedIngressCidr '203.0.113.10/32' -WhatIf
   # Only after reviewing scope, resources, ingress exposure, and cost:
   .\scripts\provision.ps1 @scope -Location canadacentral -Image $image `
       -AllowedIngressCidr '203.0.113.10/32'
   ```

   Replace `203.0.113.10/32` with your approved source range(s). Use
   `-AllowPublicIngress` instead of `-AllowedIngressCidr` only when an open,
   unauthenticated endpoint is explicitly approved.

   Expected provisioning outcome: a new resource group tagged `sre-demo=true`
   with the monitoring resources, the Container Apps environment, a verified
   healthy baseline revision, two metric alerts, and an action group. The
   action group has **no receivers** unless you pass `-AlertEmail`, so alerts
   fire without notifying anyone until you add and test a receiver. The
   Application Insights connection string is passed to the deployment through
   a short-lived parameters file under the ignored `scripts\.state` folder,
   which is deleted afterwards, rather than on the command line.
3. **Attach the knowledge.** Use [knowledge/overview.md](knowledge/overview.md)
   as the index and paste the
   [agent instructions](sre-agent-assets/sre-agent-instructions.md) into the
   agent's custom instructions. Supply the selected resource IDs and incident scope through
   approved runtime configuration, not edits that commit personal identifiers.
   **Azure SRE Agent onboarding and alert integration cannot be reproduced from
   this repository alone:** creating the agent, granting its access, attaching
   knowledge, and routing alerts to it are manual product configuration steps
   (see [SRE Agent and alert routing](docs/deployment.md#sre-agent-and-alert-routing)).
4. **Rehearse the incident.** Follow the
   [operator runbook](docs/demo-runbook.md): verify health, preview changes,
   confirm fault injection, gather evidence, then approve recovery.
5. **Verify and hand off.** Check the restored endpoint, traffic allocation,
   revision health, and alert state independently. Keep unresolved or delayed
   signals explicit.

## Safety and approvals

**Fault injection deliberately disrupts the selected demo app.** Operator
scripts require explicit scope and support `-WhatIf` and confirmation.
Never suppress confirmation for a live demonstration without a separately
approved procedure.

Provisioning, deployment, fault injection, rollback, and teardown are distinct
decisions. An agent's recommendation is not approval. Keep investigation
read-only; do not configure unattended remediation for this scenario.
Ingress exposure is also an explicit decision: `provision.ps1` refuses to run
without exactly one of `-AllowedIngressCidr` or `-AllowPublicIngress`, and
public exposure is reported as a warning.
The local incident state records the original traffic and injected revision so
recovery does not guess from naming conventions or disable unrelated revisions.
Protect this local state from modification and do not commit it.

No AKS cluster is required. Do not import local credentials, `.git`, `.env`,
dependency directories, or production logs. The root validation workflow runs
offline checks only and cannot deploy or publish images.

## Cleanup

Teardown is a separate, explicit destructive decision. There is no teardown
script: everything provisioned lives in the dedicated resource group created by
`provision.ps1`, so cleanup deletes that one reviewed group. First recover the
app with the [operator runbook](docs/demo-runbook.md) and retain any incident
evidence you need. Then, with the same values used for provisioning:

```powershell
$subscription  = '<subscription-guid>'
$resourceGroup = '<dedicated-demo-resource-group>'

# 1. Verify the target: demo tag and only demo resources
az group show --subscription $subscription --name $resourceGroup --query tags   # expect "sre-demo": "true"
az resource list --subscription $subscription --resource-group $resourceGroup --output table

# 2. Delete the group (prompts for confirmation; add --no-wait to return immediately)
az group delete --subscription $subscription --name $resourceGroup

# 3. Confirm deletion; billing stops only once this returns false
az group exists --subscription $subscription --name $resourceGroup
```

Do not delete groups by wildcard or inferred prefix. In `-RegistryName` mode
the registry, pull identity, and its `AcrPull` assignment are inside the group
and are removed with it.

Deleting the group does **not** remove configuration that lives elsewhere.
Remove or update these separately:

- **Azure SRE Agent:** detach the demo resource group from the agent's managed
  scope, remove the attached `knowledge` files, and delete any response plans,
  scheduled tasks, or incident-platform connections created for the demo; delete
  the agent itself if it was created only for this rehearsal.
- **Role assignments outside the group:** remove the agent's and operator's
  demo-specific assignments (for example a subscription-scope Contributor
  granted for provisioning). Assignments scoped to the deleted group go with it.
- **Alerting outside the group:** the two metric alerts and the
  `<demo-app>-actions` action group are deleted with the group; remove any
  external incident routing (PagerDuty, ServiceNow, Teams, email rules) or
  action groups you created elsewhere to forward them.
- **Deployment automation:** if you activated the
  [workflow blueprint](examples/deploy.yml), delete the copied workflow, its
  `sre-demo` environment and variables, the `APPLICATIONINSIGHTS_CONNECTION_STRING`
  secret, and the Microsoft Entra federated credential.
- **Images and local state:** delete any published demo image package you no
  longer need, and remove `scripts\.state` records according to your
  data-retention policy.

See also [Cost and teardown](docs/deployment.md#cost-and-teardown).

### Cleanup after failed provisioning

`provision.ps1` refuses an existing resource group and never deletes anything.
If it fails after creating the group, it prints a warning and leaves partial,
possibly billable resources. Because the group was created by this run and is
dedicated to the demo, review and delete it as a separate, explicit decision:

```powershell
az resource list --subscription '<subscription-guid>' `
    --resource-group '<dedicated-demo-resource-group>' --output table
az group show --subscription '<subscription-guid>' `
    --name '<dedicated-demo-resource-group>' --query tags   # expect sre-demo=true
az group delete --subscription '<subscription-guid>' `
    --name '<dedicated-demo-resource-group>'                # prompts for confirmation
```

Then re-run provisioning with a new group name, or after deletion completes.
Anything created outside the group (the SRE Agent, image packages, alert or
incident integrations, federated credentials) is not removed by deleting it;
review those separately as described above.

## Expected output

| Stage | Output |
| --- | --- |
| Local app | HTTP responses at `/`, `/healthz`, `/readyz` |
| Provisioning | Dedicated demo workload, monitoring resources, and explicit onboarding follow-ups |
| Fault injection | Scoped incident state and one uniquely identified failing revision |
| Investigation | Observations with resource/revision IDs, timestamps, evidence, and a proposed rollback |
| Recovery | Restored captured traffic, verified endpoint health, and retirement of only the injected revision |

Application recovery does not prove that an alert has resolved or that an agent
has closed an incident. Verify those through the configured integration.

## Sample output

The following is **synthetic**, not a record of a live deployment:

```text
Scope: <subscription-id> / <demo-resource-group> / <demo-app>
Baseline: <demo-app>--git-<sha>; /healthz HTTP 200
Incident: <demo-app>--fault-<unique-id>; process exits repeatedly
Evidence: revision-specific console logs and health observations
Proposal: restore captured baseline traffic; operator approval required
Recovery: /healthz HTTP 200; injected revision deactivated
Alert / agent incident: verification pending
```

## Limitations

- Without Azure or SRE Agent access, demonstrate the app locally and use
  synthetic incident evidence; label it as an offline walkthrough.
- Log-table names and agent onboarding vary by workspace and product
  configuration. Map them explicitly rather than claiming an unavailable tool.
- Private ACR provisioning uses a user-assigned identity with registry-scoped
  `AcrPull`, not a job token stored as a long-lived secret. Other private
  registries require a separately reviewed integration. The inactive GitHub
  deployment blueprint remains public-image-only.
- Live Azure behavior is not established by local tests. A separate authorized
  rehearsal is required before describing alert routing or agent recovery as
  verified.

## Offline validation

From the repository root:

```powershell
npm --prefix Tools\azure-sre-incident-response\app ci
npm --prefix Tools\azure-sre-incident-response\app test
pwsh -NoProfile -File Tools\azure-sre-incident-response\tests\scripts.Tests.ps1
az bicep build --file Tools\azure-sre-incident-response\infra\containerapp.bicep --stdout | Out-Null
docker build --tag azure-sre-incident-response:local Tools\azure-sre-incident-response\app
```

The PowerShell suite mocks Azure CLI and HTTP operations; it does not sign in
or change Azure resources. Bicep compilation requires the local CLI/toolchain
but no Azure session. Container validation requires a running Docker daemon;
missing tools or an unavailable daemon are unverified checks, not passes.
The root SRE validation workflow runs these non-deploying checks separately
from the toolbox's static asset and Markdown-link validator.

## References

- [Operator runbook](docs/demo-runbook.md)
- [Deployment, onboarding, and teardown](docs/deployment.md)
- [Knowledge index](knowledge/overview.md)
- [Azure SRE Agent instructions](sre-agent-assets/sre-agent-instructions.md)
- [Azure SRE Agent overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
- [Container Apps revisions](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Container Apps observability](https://learn.microsoft.com/en-us/azure/container-apps/observability)
