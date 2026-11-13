# SREAgent-IISappAzureVM

> [!WARNING]
> **Isolated lab only — not for production.** This lab deliberately deploys an
> insecure legacy application (anonymous access, HTTP without TLS, SQL
> authentication with a plaintext connection string, WinRM opened inside the
> lab VNets, an over-privileged incident actor account). Deploy it only in a
> dedicated, disposable subscription with no production connectivity, keep it
> private (Bastion access only), and tear it down when you are done. It creates
> **billable** resources (see [Known cost gotchas](#known-cost-gotchas)).

A repeatable Azure lab that recreates a **classic legacy IIS + SQL Server web
app on Windows VMs** with two identical environments (PRD and NPRD), a private
DNS setup that maps `app1.contoso.com` (PRD) and `app1.nprd.contoso.com` (NPRD),
and enough Windows/SQL activity to give the **Microsoft SRE Agent** a rich log
trail to reason over.

The demo scenario: an on-call admin thinks they're on non-prod and stops the
SQL Server service — the web app keeps serving pages but every data tab shows
nothing (no error banner). The SRE Agent's job is to trace the silent failure
back to `svc-oncall` stopping `MSSQLSERVER` on the wrong host.

> **👉 Running the demo?** See **[docs/demo-script.md](docs/demo-script.md)** —
> access instructions, pre-demo checklist, step-by-step scenario, reset,
> troubleshooting.

---

## Deployment model

The lab is deployed on demand by the operator into a subscription they choose
in `config/lab.config.jsonc`. Nothing in this repository refers to a running
instance; resource names, private IPs, and the Log Analytics workspace depend
on your configuration. Earlier revisions used `/16` VNets; the current code
uses tight `/26` VNets and refuses to deploy when a CIDR overlaps an existing
VNet in the target subscription.

---

## What gets deployed

Three resource groups in one subscription:

| Resource group | Contents |
|---|---|
| `SHARED-SREAgent-IISappAzureVM-01` | Hub VNet + **Azure Bastion (Standard)** + shared UAMI + Key Vault + both **Private DNS zones** + **DCR** wired to an existing (`existingLawResourceId`) or lab-created Log Analytics workspace |
| `PRD-SREAgent-IISappAzureVM-01`    | `PRD-SRVIIS01` (D2s_v5), `PRD-SRVSQL01` (D4s_v5, SQL 2022 Developer), `PRD-SRVWKS01` (D2s_v5), VNet `10.50.1.0/26` |
| `NPRD-SREAgent-IISappAzureVM-01`   | `NPRD-SRVIIS01`, `NPRD-SRVSQL01`, `NPRD-SRVWKS01`, VNet `10.50.2.0/26` |

### Network sizing

Tight sizing — the whole lab uses **192 IP addresses total** (`10.50.0.0/22` block):

| VNet | CIDR | Subnets |
|---|---|---|
| Hub | `10.50.0.0/26` (64 addr) | `AzureBastionSubnet` /26 (Bastion minimum) |
| PRD | `10.50.1.0/26` (64 addr) | `snet-web`, `snet-db`, `snet-wks` — each /28 (16 addr, 11 usable) |
| NPRD | `10.50.2.0/26` (64 addr) | same as PRD |

`Deploy-Lab.ps1` runs a **CIDR-uniqueness check** against every existing VNet in
the target subscription and refuses to deploy if any overlap is detected. To
retarget, edit `hubVnetCidr` / `prdVnetCidr` / `nprdVnetCidr` in
`config/lab.config.jsonc`.

All VMs are joined to a single **user-assigned managed identity**
(`id-sreagent-iisapp-shared`) and stream Windows System and Application event logs (including SQL Server
and app-heartbeat events), selected Security events, and performance counters to a **Log Analytics workspace**: the one set
in `existingLawResourceId` (for example, the workspace your SRE Agent already
reads from) or, when that value is empty, a new workspace in the SHARED RG.

Auto-shutdown is enabled per-VM (default 22:00 Toronto time).

### The two DNS zones (this is the point of confusion)

| Zone | Linked to | Records |
|---|---|---|
| `contoso.com`      | Hub VNet + PRD VNet  | `app1`, `sql1`, `wks1` → PRD IPs |
| `nprd.contoso.com` | Hub VNet + NPRD VNet | `app1`, `sql1`, `wks1` → NPRD IPs |

From the workstation, the *short* hostnames are identical (`sql1`, `app1`).
That's what enables the "admin stopped SQL on the wrong host" story.

### The app — "Contoso Global HR"

Classic ASP.NET Framework 4.8 WebForms + Bootstrap 5. Sidebar navigation,
tabs for Dashboard / Employees / Departments / Global Presence /
Timesheets / Reports. Data seeded across **4 countries** (Canada, Japan,
Germany, Brazil), **10 departments**, **100 employees**.

Every data method wraps its SqlClient call in a broad `try/catch` and returns
an empty list on failure. This produces the silent failure mode: page + chrome
+ menu render fine when SQL is down, tables just say "No data available."

### The activity generator

Windows Scheduled Task on each web VM (`ContosoHR-Activity`), fires every 60s.
It runs a random SELECT plus an INSERT into `dbo.AuditLog`, and emits an
Application-log event (source `ContosoHR-Activity`, Event ID 1001 healthy /
1002 degraded) so the Log Analytics workspace has continuous app heartbeat
data on both environments.

### The incident actor

A local admin user `svc-oncall` is created on both SQL VMs. When the demo
runs `Trigger-Incident.ps1`, `Stop-Service MSSQLSERVER` executes under that
user, producing:

- **System log** — Event **7036** (`The SQL Server (MSSQLSERVER) service entered the stopped state`).
- **Security log** — Event **4624** logon of `svc-oncall`, **4688** process-creation with cmdline (PowerShell + `Stop-Service`).

Those flow into the LAW; the SRE Agent can correlate.

---

## Prerequisites

- Windows 10/11 with **PowerShell 7+** (`pwsh`)
- **Azure CLI 2.60+**, logged in against the target tenant
- **Bicep** (`az bicep install`; the Azure CLI installs it on first use)
- A **dedicated lab subscription** where you hold **Contributor** (or Owner)
  to create the resource groups and resources. Optional: **Key Vault Secrets
  Officer** on the lab Key Vault if you use `-StoreSecretsInKeyVault`.
- Roughly **~$880/month** budget headroom if you leave the VMs on ~14h/day;
  set an [Azure budget alert](https://learn.microsoft.com/azure/cost-management-billing/costs/tutorial-acm-create-budgets)
  on the subscription before deploying.
- An Azure SRE Agent with read access to the Log Analytics workspace (created
  separately; onboarding the agent is not automated by this lab).

---

## Deploy

```powershell
git clone https://github.com/rbrunois/agentic-itops-showcase.git
cd agentic-itops-showcase/Tools/azure-incident-investigator/demo/iis-app-azure-vm

# 1. Create your local config (gitignored) and set tenantId / subscriptionId
Copy-Item config/lab.config.example.jsonc config/lab.config.jsonc
code config/lab.config.jsonc

# 2. Log in (once)
az login --tenant <your-tenant-id>

# 3. Preview, then deploy — creates 3 RGs, everything else, then runs on-VM configuration
pwsh ./scripts/Deploy-Lab.ps1 -WhatIf
pwsh ./scripts/Deploy-Lab.ps1
```

The deploy is idempotent — re-running fixes drift. `-WhatIf` runs
`az deployment sub what-if` without creating resources. Add
`-StoreSecretsInKeyVault` to also copy the generated passwords into the lab
Key Vault.

### First-run detail

`Deploy-Lab.ps1`:

1. Reads `config/lab.config.jsonc` and refuses to run while `tenantId` or
   `subscriptionId` is still the all-zero placeholder
2. Sets the Azure CLI context to the target sub and checks VNet CIDR overlaps
3. Generates an **independent random password per account** and saves each
   under `secrets/` (gitignored, ACL restricted to the current user):
   `vm-admin.txt` (`azureadmin`), `sql-app.txt` (`hrapp`),
   `incident-account.txt` (`svc-oncall`). Existing files are reused.
4. Packages the app, SQL files, and operator scripts into inline VM configuration scripts
5. Appends the shared operator-script installer to all three VM roles
6. Runs `az deployment sub create` against `bicep/main.bicep`; VM configuration
   uses managed Run Command, without a staging storage account or SAS. The
   temporary parameters file (which contains the passwords) is deleted as soon
   as the CLI call returns.
7. Prints the private IPs of all six VMs and where each credential is stored

Approximate wall-clock time: **20–25 minutes** (SQL VM extension is the long pole).

> [!CAUTION]
> The `secrets/` files are plaintext and only protected by the local file ACL.
> Never commit, share, or sync them; delete the folder after teardown. The
> passwords are also embedded in the VM configuration (Run Command scripts,
> `Web.config`, and the `C:\temp` operator scripts) by design of this lab.

### Expected output

A successful run ends with `DEPLOYMENT COMPLETE`, the six private IPs with
their `*.contoso.com` / `*.nprd.contoso.com` names, the Bastion name, and the
three credential file locations. Validate the guests with the
[Run Command test](#running-the-demo) (`LAB_TEST_PASS`).

### Cleanup after a failed deployment

`az deployment sub create` does not roll back. If a run fails:

1. Read the error (`az deployment sub show -n <deployment-name>` or the
   portal **Deployments** blade), fix the cause, and re-run `Deploy-Lab.ps1`
   — it is idempotent; or
2. Remove everything with `pwsh ./scripts/Teardown-Lab.ps1` (deletes the three
   lab resource groups). The Key Vault is soft-deleted for 7 days; purge it
   with `az keyvault purge --name <kv-name>` if you need to redeploy with the
   same name immediately.

---

## Retargeting to another tenant / subscription / region

Everything lives in your local `config/lab.config.jsonc` (copied from
`config/lab.config.example.jsonc`). Change:

```jsonc
{
  "tenantId":       "<your-tenant-id>",
  "subscriptionId": "<your-subscription-id>",
  "location":       "eastus",   // or any region
  "rgBaseName":     "SREAgent-IISappAzureVM-01",  // rename if you want
  ...
}
```

Everything downstream (Bicep params, deploy script, DNS zones, VM names) is
derived from those values. No code changes needed. The `Owner` tag defaults to
the signed-in Azure CLI account when left empty.

---

## Running the demo

Every workstation, IIS VM, and SQL VM has these runnable operator scripts:

- `C:\temp\Trigger-Incident.ps1`: stops SQL Server in that VM's environment.
- `C:\temp\Reset-Lab.ps1`: starts SQL Server in that VM's environment.

Open the **Lab PowerShell (C-temp)** desktop shortcut and accept elevation.
The scripts contain the lab account credential and are restricted to
Administrators and SYSTEM. Use `-Check` to verify credentials and connectivity
without changing service state:

```powershell
C:\temp\Trigger-Incident.ps1 -Check
C:\temp\Reset-Lab.ps1 -Check
```

On IIS VMs, the scheduled activity generator remains at
`C:\ProgramData\ContosoHR\ActivityGenerator.ps1`, run by the
`ContosoHR-Activity` task. Provisioning and teardown scripts stay in the
repository; they are not standalone VM utilities.

To install or refresh the operator scripts on all six existing, running VMs,
run this from the lab repository using PowerShell 7 and an authenticated Azure CLI:

```powershell
pwsh ./scripts/Deploy-Lab.ps1 -ScriptsOnly
```

This reuses the existing `secrets/` password files (labs deployed before
per-account passwords fall back to `secrets/vm-admin.txt`) and does not
redeploy infrastructure, reseed
the database, or stop SQL Server. Both installed operator scripts must pass
their `-Check` before a VM reports success. Do not combine it with `-WhatIf`.

Run the VM-side checks from the repository through Azure Run Command:

```powershell
az vm run-command invoke -g NPRD-SREAgent-IISappAzureVM-01 -n NPRD-SRVIIS01 --command-id RunPowerShellScript --scripts '@tests/Test-LabScripts.ps1'
```

Check that the returned script output contains `LAB_TEST_PASS`; Azure CLI
success alone does not mean the guest script passed. The test verifies both
operator scripts, the desktop shortcut, and populated app data. On IIS VMs it
also executes every activity-generator query and verifies a healthy heartbeat.

For a deliberate NPRD stop/reset test, use `NPRD-SRVWKS01` and append
`--parameters Mode=Incident`. Incident mode is rejected on every other host
and always attempts reset in a `finally` block.

1. **From the Azure portal → Bastion**, RDP into `PRD-SRVWKS01` as
   `azureadmin` (password in `secrets/vm-admin.txt`).
2. Double-click **Contoso HR (PRD)** shortcut on the desktop. The app loads;
   click through tabs and see data.
3. Repeat with `NPRD-SRVWKS01`. Same app, but green wallpaper and NPRD badge.
4. Trigger the incident from the elevated lab PowerShell on `PRD-SRVWKS01`.
  For the production-incident demo, say the operator thought this was NPRD.
  The script connects to the matching SQL VM as **`svc-oncall`**:
   ```powershell
  C:\temp\Trigger-Incident.ps1
   ```
  This deliberately interrupts PRD. Use `NPRD-SRVWKS01` for a nonproduction rehearsal.
5. From `PRD-SRVWKS01`, refresh the app. Nav + menu render, every data tab
   says "No data available." **No error banner.**
6. Ask the **SRE Agent** to investigate the PRD Contoso HR app. It should
   correlate the drop-off in app heartbeat events with the SCM 7036 stop event
   and the `svc-oncall` process-creation trail, and pin the RCA to
   *"MSSQLSERVER stopped by svc-oncall on PRD-SRVSQL01"*.
7. Reset from the same VM with `C:\temp\Reset-Lab.ps1`.

`docs/demo-script.md` has the narrated version.

---

## Teardown

```powershell
pwsh ./scripts/Teardown-Lab.ps1
```

Prompts for confirmation, then deletes the three resource groups (`--no-wait`).
It does not touch the SRE Agent or an existing workspace referenced by
`existingLawResourceId`. When the deletes finish:

- Remove the local `secrets/` folder (plaintext lab passwords).
- Optionally purge the soft-deleted Key Vault (`az keyvault purge --name <kv-name>`).
- Verify with `az group list --query "[?contains(name,'SREAgent-IISappAzureVM')].name" -o tsv`
  that no lab resource group remains (billing stops only once they are gone).

---

## Repository layout

```
bicep/                 subscription-scope templates
  main.bicep           creates 3 RGs, calls shared + PRD + NPRD modules
  modules/
    shared.bicep       hub VNet, Bastion, UAMI, KV, DNS zones, DCR
    environment.bicep  per-env VNet + NSGs + 3 VMs + DNS records
    vm-windows.bicep   reusable Windows VM with AMA + auto-shutdown + Run Command
    vm-sql.bicep       WS2022 + SQL 2022 Dev + IaaS agent + AMA + Run Command
    peering-hub.bicep  reverse-peering helper (deployed to SHARED RG)
    dns-link.bicep     link a private DNS zone to a spoke VNet
    dns-records.bicep  create A records inside a private DNS zone
scripts/
  Deploy-Lab.ps1              orchestrator (reads config, generates passwords, deploys)
  Teardown-Lab.ps1            deletes the 3 RGs
  Trigger-Incident.ps1        C:\temp on all VMs; stops matching SQL service (-Check is read-only)
  Reset-Lab.ps1               C:\temp on all VMs; starts matching SQL service (-Check is read-only)
  Install-LabScripts.ps1      shared inline installer template; invoked by Deploy-Lab.ps1
  Configure-WebTier.ps1       Run Command on IIS VMs — IIS + app + scheduled task
  Configure-DbTier.ps1        Run Command on SQL VMs — schema, seed, audit policy, incident user
  Configure-Workstation.ps1   Run Command on workstations — Edge shortcut, wallpaper, banner
  Start-ActivityGenerator.ps1 runs every 60s on IIS VMs
sql/
  01-schema.sql / 02-seed.sql / 03-logins.sql
app/ContosoGlobalHR/  ASP.NET 4.8 WebForms source (no build step; synthetic, intentionally insecure)
app-architecture/     application architecture doc + deployment diagram
config/
  lab.config.example.jsonc  committed template
  lab.config.jsonc          your local copy (gitignored) — the *only* file you edit to retarget
docs/
  demo-script.md      demo narration
  sre-agent/          SRE Agent instructions, runbooks, KQL library, report templates
tests/
  Test-LabScripts.ps1 in-guest validation run through Azure Run Command
secrets/              gitignored — generated lab passwords live here
```

---

## Known cost gotchas

- **Azure Bastion Standard runs 24/7** (~$175/mo). Bastion cannot be
  auto-stopped. If you shut everything else down and don't demo for a week,
  you're still paying for Bastion.
- Premium SSD OS disks bill even when the VM is deallocated (~$36/mo total).
- Auto-shutdown deallocates VMs nightly but does not stop Bastion, disks, Key
  Vault, or Log Analytics ingestion/retention charges. Tear the lab down when
  you are not using it.
- The `secrets/` folder is gitignored — never commit the password files.

---

## Limitations

- The SRE Agent itself is **not** deployed or configured by this lab. Create it
  separately, grant it read access to the lab resource groups and the Log
  Analytics workspace, and load the instructions, runbooks, and KQL library
  from [`docs/sre-agent/`](docs/sre-agent/README.md) as agent knowledge/skills.
- Prices above are rough estimates; check the
  [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/)
  for your region.
- Windows hosts only for the in-guest scripts; the deploy/teardown scripts need
  PowerShell 7 and Azure CLI.
