---
name: gen2-nvme-mana-readiness
description: Use when assessing whether a VM on an End of Life series can move to v5, v6, or v7 sizes. Checks Hyper-V generation, NVMe and MANA readiness, temporary disk dependency, Accelerated Networking, encryption, and hard gates such as SAP certification and ISV appliances.
tools:
  - RunAzCliReadCommands
---

# Readiness for a new VM family

Read-only in Phases 1 and 2. Guest-level checks that need Run Command are Phase 3
actions and require approval.

## Inputs

- Resource IDs from `arg-retiring-series`.
- Supporting query: `arg-vm-profile.kql`, appended to this skill when it's
  published.
- Knowledge: `legacy-series-to-target-framework.md`.

## Procedure

1. Run `arg-vm-profile.kql` through `az graph query`, filtered to the resource IDs.
2. Check hard gates first:
   - **SAP**: only SAP-certified sizes. Set `hardGate: sap-certification`.
   - **ISV appliance**: a marketplace `planPublisher`, `ipForwarding: Yes`, or an
     appliance tag suggests a vendor appliance. Set `hardGate: isv-appliance` and
     require vendor certification for the exact target family. Don't automate.
3. Record readiness signals for each VM:

   | Signal | Source | Rule |
   | --- | --- | --- |
   | Hyper-V generation | `hyperVGeneration` | `V1` means v6 and v7 need a redeploy from a Generation 2 image. If `instanceViewCaptured` is `No`, report `unknown`. |
   | Disk controller | `diskControllerType` | Blank means SCSI. v6 and v7 need an NVMe-capable OS and image. |
   | NVMe readiness | OS and image version | `unknown` until the image or OS version is confirmed as NVMe-capable. |
   | MANA readiness | OS version | Linux kernel 5.15 or later; Windows needs a current image. Otherwise `unknown`. |
   | Source temporary disk | `az vm list-skus` capability `MaxResourceVolumeMB` | Greater than 0 means the source has a temporary disk; a v6 conversion in place isn't possible. |
   | Temporary disk dependency | Owner confirmation | `unknown` until confirmed. If yes, the target needs a `d` size or data relocation. |
   | Accelerated Networking | `acceleratedNetworking` | Required on Intel D-family v5 targets; enable it on the source first. |
   | Linux disk encryption | `adeOsDiskEnabled` with `osType: Linux` | ADE for Linux isn't supported with NVMe: decrypt or redeploy. |
   | Trusted Launch | `securityType`, `secureBootEnabled`, `vTpmEnabled` | Informational; Generation 2 is a prerequisite. |

   Check the source size capabilities with an exact name match, because `--size`
   also matches longer names that share the prefix:

   ```bash
   az vm list-skus --location <region> --size <Standard_SizeName> --resource-type virtualMachines \
     --query "[?name=='<Standard_SizeName>'] | [0].capabilities" --output json
   ```

4. Summarize per VM: ready for v5 resize, needs remediation before v5, v6 and v7
   need redeploy, or gated.

## Output

A `readiness` object per VM that matches `disposition-record.schema.json`, plus
the evidence used (query name, command, timestamp).

## Rules

- Unknown is a valid answer. Never turn missing data into "ready".
- Hard-coded SCSI device paths and persistent data on the OS disk can't be seen
  from Azure Resource Manager. List them as remaining validations.
- Never recommend an exact size here; that's the job of `sku-advisor`.
