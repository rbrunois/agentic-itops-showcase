# Deployment and agent onboarding

## Configuration contract

Work in a dedicated demo resource group. Do not reuse a shared application.
The same values must be supplied to provisioning, incident scripts, agent
scope, and query parameters.

| Value | Source |
| --- | --- |
| Subscription ID | Explicit operator-selected subscription GUID |
| Resource group and app | Explicit operator-selected demo names |
| Location | Region selected after checking resource availability and quotas |
| Image | Public synthetic image pinned by digest (`@sha256:...`; mutable tags are discouraged), or a digest-pinned private ACR build of `app/Dockerfile` |
| Agent resource and region | Separately onboarded Azure SRE Agent; check current availability |
| Telemetry | Workspace and Application Insights created for the demo |
| Incident state | Unique file under ignored `scripts\.state`; use the printed recovery path |

There is no baked-in personal subscription, repository, agent name, or region.
The endpoint is unauthenticated and contains no business data, so ingress
exposure is an explicit provisioning decision. `provision.ps1` refuses to run
(before any Azure call, including `-WhatIf`) unless you pass exactly one of:

- `-AllowedIngressCidr '<cidr>', ...` (recommended): restricts ingress to
  approved IPv4 source ranges through Bicep `allowedIngressCidrs`. Include the
  operator address because the scripts verify `/healthz` and `/readyz` from
  the operator machine.
- `-AllowPublicIngress`: accepts a public, unauthenticated endpoint reachable
  from the whole internet; the script prints a warning after provisioning.

Passing both is rejected as ambiguous. When deploying the Bicep template
directly, a non-empty `allowedIngressCidrs` always applies; with an empty list
the app gets external ingress only if `allowPublicIngress=true`, otherwise it
is deployed with environment-internal ingress (fail closed), which the operator
scripts refuse as a demo target. This package does not implement a private
network boundary, restricted egress, production availability, or a production
identity design.

## Local image

From the repository root:

```powershell
docker build --tag azure-sre-incident-response:local Tools\azure-sre-incident-response\app
docker run --rm --publish 8080:8080 azure-sre-incident-response:local
```

Check `/healthz` and `/readyz`. For Azure, explicitly publish only the sanitized
sample image to an operator-owned registry. Verify anonymous pull access before
provisioning. A successful authenticated push does not establish public access;
new GHCR packages may require an explicit visibility change. Never change the
visibility of an existing private package containing other code.

The blueprint `examples/deploy.yml` is deliberately **inactive**. To use it,
review it in your own repository, configure its inputs, and deliberately copy
it to the root workflow directory. It uses manual dispatch rather than push
deployment. Protect its deployment environment with required reviewers and
scope the Azure federated identity to that environment and the demo resource
group. Follow the
[Azure Login OIDC guidance](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect).
No repository secret with Contributor credentials is supplied by this package.

The example requires `sre-demo=true` on the resource group and on any existing
target app; it refuses to overwrite an unmarked app. Do not tag arbitrary
resources simply to pass this check. When redeploying the instrumented app
created by provisioning, configure the deployment environment's
`APPLICATIONINSIGHTS_CONNECTION_STRING` secret through your approved secret
store. The blueprint refuses to remove existing telemetry silently if that
secret is missing. Direct Bicep deployment with an empty connection-string
parameter disables app instrumentation, so review that choice explicitly.

The public-image blueprint refuses to redeploy an app with private registry
configuration, so it cannot silently remove its pull identity. To update a
private deployment, use the existing registry and pull identity parameters
with the Bicep template and obtain separate deployment approval.

The blueprint's package-write permission is for publishing the explicitly
selected synthetic image, not for creating a permanent Container Apps pull
credential. Private images need an approved alternative such as an ACR pull
identity; do not persist a workflow `GITHUB_TOKEN` in Container Apps.

## Private image build without local Docker

Use the alternative `-RegistryName` parameter instead of `-Image`:

```powershell
.\scripts\provision.ps1 @scope -Location canadacentral `
    -RegistryName '<globally-unique-lowercase-alphanumeric-name>' `
    -AllowedIngressCidr '203.0.113.10/32' -WhatIf
# After reviewing the additional billable registry, build, and scoped role:
.\scripts\provision.ps1 @scope -Location canadacentral `
    -RegistryName '<globally-unique-lowercase-alphanumeric-name>' `
    -AllowedIngressCidr '203.0.113.10/32'
```

Define `$scope` as shown below and replace `203.0.113.10/32` with your
operator's public address. This mode creates a private Basic Azure
Container Registry with admin credentials disabled, a user-assigned managed
identity, and an `AcrPull` assignment scoped only to that registry. It requires
permission to create that role assignment in addition to the provisioning
permissions. ACR Tasks must be permitted in the subscription.

Only the six allowlisted app build files are uploaded; local dependencies,
`.env`, operator state, and the rest of the repository are excluded. The remote
build must succeed before app deployment and its output is pinned by digest.
Temporary staging files are cleaned on success or failure. Resource creation
is not rolled back automatically on failure.

Private registry authentication does not make the app endpoint private. Its
synthetic HTTP service still has external HTTPS ingress, limited only by the
allow-list or opened by `-AllowPublicIngress`. Both registry parameters
(`registryName`, `registryIdentityName`) must be supplied together when deploying
Bicep directly; the registry and identity must exist in the same resource group
and the identity must already have pull permission.

## Provisioning

Install the Azure CLI capabilities and register providers through your normal
approved setup process. Resource-group creation requires subscription-level
permission; scope subsequent deployment and incident operations to the demo
resource group. Do not grant the investigation agent those provisioning rights.

From `Tools\azure-sre-incident-response`, fill in values locally:

```powershell
$scope = @{
    SubscriptionId = '<subscription-guid>'
    ResourceGroup  = '<dedicated-demo-resource-group>'
    AppName        = '<demo-app>'
}
$image = 'ghcr.io/<owner>/<public-demo-image>@sha256:<digest>'
$ingress = @{ AllowedIngressCidr = '203.0.113.10/32' }   # your operator's public address
.\scripts\provision.ps1 @scope @ingress -Location canadacentral -Image $image -WhatIf
# Only after reviewing scope, resource creation, ingress exposure, and cost:
.\scripts\provision.ps1 @scope @ingress -Location canadacentral -Image $image `
    -AlertEmail 'oncall@contoso.example'
# Alternative only when an open endpoint is explicitly approved:
.\scripts\provision.ps1 @scope -Location canadacentral -Image $image -AllowPublicIngress
```

`provision.ps1` stops with an error before contacting Azure if neither
`-AllowedIngressCidr` nor `-AllowPublicIngress` is supplied, or if both are.
Without `-AlertEmail` the action group is created with **no receivers**. The
Application Insights connection string is written to a short-lived parameters
file under the ignored `scripts\.state` folder and deleted after the
deployment, so it does not appear in the process command line or shell history.
The inactive blueprint does not manage ingress allow-lists: it refuses to
redeploy an app that has them and requires its `allow_public_ingress` input to
acknowledge public access. Redeploy restricted apps with Bicep directly,
passing the same `allowedIngressCidrs`.

Provisioning refuses an existing resource group, including a partial prior
deployment. Inspect any partial resources and obtain separate cleanup approval
before retrying; it does not automatically delete or take over existing groups.
The guard tag is `sre-demo=true`. Fault injection supports a single container,
multiple revisions, external ingress, and unlabeled traffic; it refuses other
topologies rather than guessing how to restore them.

`canadacentral` is an example workload location, not an availability guarantee
for the SRE Agent. The provisioning script creates the monitoring resources
and Container Apps environment; `infra/containerapp.bicep` deploys the Node
app into that **existing environment**. Its health probes use port 8080.
Application Insights is instrumented by the Node SDK using runtime
configuration; Container Apps does not automatically instrument this app.

Check that the healthy revision is active, `/healthz` and `/readyz` return
HTTP 200, and the intended image is deployed before moving to fault injection.
CLI success is not evidence of completed agent onboarding.

## SRE Agent and alert routing

Configure these separately using currently supported product capabilities:

1. Create or select an Azure SRE Agent and scope its access to this demo.
   Give investigation only the resource/log read permissions it needs.
   Explicitly select Review for each response plan/task, not unattended
   mutation; do not rely on a default run mode. Review gates infrastructure
   writes, not every external message. Restrict other tools or configure hooks
   and tool access policies for communication and incident closure.
2. Attach the sanitized `knowledge` directory. Supply actual resource IDs,
   workspace context, operator escalation, and approved tools at runtime.
   Do not grant arbitrary instruction files authority to expand scope.
3. Configure the incident/alert integration supported by the selected agent
   setup. An action group without a receiver is **not** a notification route.
   Configure its receiver or incident connector explicitly and verify delivery
   with an approved test.
4. Confirm the agent can read revision inventory, console/system logs, metrics,
   and the relevant knowledge. Missing telemetry must be reported as a gap.
5. Rehearse a read-only investigation. Agent investigation cards, mitigation
   proposals, and incident closure are conditional on these integrations;
   the operator scripts do not provide them.

Consult [SRE Agent overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
and [run modes](https://learn.microsoft.com/en-us/azure/sre-agent/run-modes)
for current onboarding and approval behavior. Do not reuse historical region
lists or assume that an older portal/CLI limitation is still current.

## Cost and teardown

Container Apps replicas, image storage, Log Analytics ingestion/retention,
Application Insights, alerts, and the agent can incur charges. Set an approved
budget and retention policy before deploying. No price or free-tier guarantee
is implied. This scenario does not need AKS.

First recover the app using the incident runbook. Then inspect the resources:

```powershell
az resource list --subscription $scope.SubscriptionId `
    --resource-group $scope.ResourceGroup --output table
```

Teardown is a **separate destructive approval**. Confirm the exact subscription
and resource-group ID, ownership tag, absence of unrelated resources, and
whether any incident evidence must be retained. Using Azure Portal, delete
only that reviewed dedicated resource group after typing its exact name into
the confirmation, or use the Azure CLI commands in the package
[Cleanup](../README.md#cleanup) section. Do not delete a group by a wildcard or
inferred prefix.

The agent, image package, external incident integration, or RBAC/federated
credentials may live outside the group. Review each separately; the package
does not automatically remove them. Retain or dispose of local incident records
according to your approved data-retention policy.
