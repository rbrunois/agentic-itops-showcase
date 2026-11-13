# Derivation Rules

The agent **computes** these values. It never asks for them. It **displays** them in the summary (hard rule #3).
Every derived value feeds a parameter of the AVM module `avm/ptn/lz/sub-vending`.

Conventions: `{app}` = `appId` lowercased, `{env}` = `environment`, `{region}` = `canadacentral` (default) / `canadaeast` (DR).

---

## 1. Naming convention

| Element | Formula | Example |
|---|---|---|
| Subscription alias | `sub-{app}-{env}` | `sub-app01234-prod` |
| Display name | `{APPID} - {ENV}` | `APP01234 - PROD` |
| Main resource group | `rg-{app}-{env}-{region}-001` | `rg-app01234-prod-cc-001` |
| Network resource group | `rg-{app}-{env}-network-001` | `rg-app01234-prod-network-001` |
| VNet | `vnet-{app}-{env}-{region}-001` | `vnet-app01234-prod-cc-001` |
| Managed identity | `id-{app}-{env}-deploy` | `id-app01234-prod-deploy` |
| Entra group | `AZ-{APPID}-{ENV}-{ROLE}` | `AZ-APP01234-PROD-CONTRIBUTOR` |
| IIQ role | `AZURE_{APPID}_{ENV}_{ROLE}` | `AZURE_APP01234_PROD_CONTRIBUTOR` |

Region abbreviations: `canadacentral` → `cc`, `canadaeast` → `ce`.

---

## 2. Target Management Group → `subscriptionManagementGroupId`

Decision table on `dataClassification` × `environment`:

| dataClassification | environment | Management Group |
|---|---|---|
| public / internal | prod | `mg-landingzones-corp` |
| public / internal | dev, test, uat | `mg-landingzones-corp-nonprod` |
| confidential | prod | `mg-landingzones-corp` |
| confidential | dev, test, uat | `mg-landingzones-corp-nonprod` |
| restricted | *(all)* | `mg-landingzones-confidential` **+ mandatory security review** |
| *(any)* | dev **and** networkNeed=none | `mg-landingzones-sandbox` |

`restricted` ⇒ set `security_review_required = true` on the ServiceNow ticket and route to approval group `SEC-CLOUD-REVIEW`.

---

## 3. Workload → `subscriptionWorkload`

| environment | subscriptionWorkload |
|---|---|
| prod | `Production` |
| dev, test, uat | `DevTest` |

---

## 4. Network → `virtualNetworkEnabled`, address space, peering

| networkNeed | vnetEnabled | CIDR size | Hub peering | `virtualNetworkUseRemoteGateways` |
|---|---|---|---|---|
| `none` | `false` | — | — | — |
| `isolated` | `true` | `/26` (64) | no | `false` |
| `spoke-small` | `true` | `/24` (251) | yes | `true` |
| `spoke-medium` | `true` | `/23` (507) | yes | `true` |
| `spoke-large` | `true` | `/22` (1019) | yes | `true` |

- The **exact CIDR is never chosen by the agent**. The ticket carries the *requested size*, and the pipeline calls IPAM to allocate the prefix. The agent displays "prefix /24 — allocated by IPAM at deployment time".
- Target hub: `hub-canadacentral-prod` when `environment=prod`, otherwise `hub-canadacentral-nonprod`.
- `deployDdosProtectionPlan` = `true` only when `environment=prod` **and** `networkNeed` starts with `spoke`.

Default subnets created for any spoke: `snet-app` (50% of the space), `snet-data` (25%), `snet-pe` (25%, `privateEndpointNetworkPolicies: Disabled`).

---

## 5. Managed identity and federated credential

- Name: `id-{app}-{env}-deploy`, inside `rg-{app}-{env}-{region}-001`.
- Federated credential issuer depends on `workzoneRepo`:
  - GitHub → `https://token.actions.githubusercontent.com`
  - Azure DevOps → `https://vstoken.dev.azure.com/{orgId}`
- Subject:
  - `prod` → `repo:{workzoneRepo}:environment:prod`
  - non-prod → `repo:{workzoneRepo}:ref:refs/heads/main`
- Identity's role on the subscription: `Contributor` plus a **conditional** `User Access Administrator` scoped to data-plane role assignments only.

---

## 6. Access → `roleAssignments`

| accessPersona | Entra group | Azure role | Mode |
|---|---|---|---|
| `app-team-standard` | `AZ-{APPID}-{ENV}-READER` | `Reader` | permanent |
| `app-team-elevated` | `AZ-{APPID}-{ENV}-CONTRIBUTOR` | `Contributor` | **PIM eligible**, 8 h max activation, justification required |
| `data-team` | `AZ-{APPID}-{ENV}-DATAREADER` | `Reader` + `Storage Blob Data Reader` | permanent |
| `readonly-audit` | `AZ-{APPID}-{ENV}-AUDIT` | `Reader` | permanent |

Always added: `AZ-PLATFORM-CLOUDOPS` → `Owner` (permanent, platform team).
Groups are provisioned through IIQ under role `AZURE_{APPID}_{ENV}_{ROLE}`.

---

## 7. Default resource providers → `resourceProviders`

Baseline (always):
`Microsoft.Insights`, `Microsoft.OperationalInsights`, `Microsoft.KeyVault`, `Microsoft.Storage`, `Microsoft.ManagedIdentity`, `Microsoft.Resources`, `Microsoft.Security`, `Microsoft.PolicyInsights`, `Microsoft.Advisor`

Conditional additions:
- `networkNeed != none` → `Microsoft.Network`
- `accessPersona = data-team` → `Microsoft.Sql`, `Microsoft.Databricks`, `Microsoft.DataFactory`
- `environment = prod` → `Microsoft.AlertsManagement`, `Microsoft.RecoveryServices`

**Any provider outside the approved Contoso list is rejected**: the agent explains and offers to either drop the provider or file an exception request with cloud architecture.

---

## 8. Budget → `subscriptionBudgets`

```
name:       budget-{app}-{env}-monthly
amount:     {monthlyBudget}
thresholds: [50, 80, 100]   # % of the amount
contact:    owner.upn + AZ-{APPID}-{ENV}-* owners + CloudFinOps distribution list
```
`environment=prod` adds a forecast threshold at `110`.

---

## 9. Tags → `subscriptionTags`

```
ApplicationId    = {appId}
Environment      = {environment}
CostCenter       = {costCenter}
DataClass        = {dataClassification}
Owner            = {owner.upn}
Repo             = {workzoneRepo}
RequestId        = {serviceNowNumber}
ManagedBy        = subscription-vending
DecommissionDate = {decommissionDate | "n/a"}
```

---

## 10. Locks and miscellaneous

- `subscriptionBillingScope`: the platform MCA billing profile (environment constant, never asked).
- `virtualNetworkLocation` / subscription location: `canadacentral` by default; `canadaeast` only if the requester explicitly said so.
- `CanNotDelete` lock on `rg-{app}-{env}-network-001` when `environment=prod`.
- `subscriptionAliasEnabled` = `true`.
