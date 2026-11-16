# Pilot resize runbook (Phase 3)

This runbook is what the `migration-executor` custom agent follows. People can
run the same steps by hand. It applies only to:

- VMs in the approved pilot resource group (`rg-contoso-vmlt-pilot` in the
  examples);
- VMs whose disposition record says `resize-to-v5` and whose readiness and
  landing checks pass;
- VMs with no hard gate (SAP, ISV appliance) that aren't domain controllers.

Every write command needs approval from an SRE Agent Administrator. Keep the
Phase 3 thread or scheduled task in **Review** mode; in Autonomous mode, an
`ask` policy is auto-approved.

## Before the pilot

- [ ] The sponsor approved the pilot scope and maintenance windows.
- [ ] The agent identity has **Virtual Machine Contributor** on the pilot resource
  group only, and Reader-level roles elsewhere.
- [ ] The global tool access policy from
  [`tool-access-policy.json`](../agent/tool-access-policy.json) is applied.
- [ ] The hooks in [`agent/hooks/`](../agent/hooks/) are created, with the pilot
  resource group name replaced, or the team confirmed that only the primary
  controls apply.
- [ ] A rollback test on a non-critical pilot VM is planned.

## 1. Pre-checks (read-only)

Stop and report at the first failed check.

```bash
# Current size: record it for rollback.
az vm show -g rg-contoso-vmlt-pilot -n vm-contoso-web01 --query hardwareProfile.vmSize -o tsv

# Sizes available on the VM's current hardware cluster.
az vm list-vm-resize-options -g rg-contoso-vmlt-pilot -n vm-contoso-web01 --query "[].name" -o tsv

# Target size offered in the region and the VM's zone, with no restriction.
az vm list-skus --location canadacentral --size Standard_D4ds_v5 --all --output table

# Quota headroom for the target family and the regional total.
az vm list-usage --location canadacentral --output table

# Accelerated Networking on each NIC (required by Intel D-family v5 targets).
az vm show -g rg-contoso-vmlt-pilot -n vm-contoso-web01 --query "networkProfile.networkInterfaces[].id" -o tsv
az network nic show --ids <nic-id> --query enableAcceleratedNetworking
```

Also confirm that:

- a backup recovery point or a snapshot from the last 24 hours exists;
- the maintenance window is open and the workload owner is available;
- the `list-skus` output shows no restriction for the subscription or for the
  VM's zone. If the target size isn't in `list-vm-resize-options`, the VM must be
  deallocated so it can move to other hardware, which this runbook always does.

## 2. Approval

The agent posts the pre-check evidence and asks for approval of each write
command. The approver checks the current size, target size, quota headroom,
backup evidence, and window. Only SRE Agent Administrators can approve.

## 3. Execute (each command approved)

```bash
az vm deallocate -g rg-contoso-vmlt-pilot -n vm-contoso-web01
# Intel D-family v5 targets only, while deallocated, when a NIC lacks it:
az network nic update --ids <nic-id> --accelerated-networking true
az vm resize -g rg-contoso-vmlt-pilot -n vm-contoso-web01 --size Standard_D4ds_v5
az vm start -g rg-contoso-vmlt-pilot -n vm-contoso-web01
```

## 4. Verify (read-only)

```bash
az vm get-instance-view -g rg-contoso-vmlt-pilot -n vm-contoso-web01 \
  --query "{power: instanceView.statuses[?starts_with(code, 'PowerState')].displayStatus | [0], agent: instanceView.vmAgent.statuses[0].displayStatus, extensions: instanceView.extensions[].{name: name, status: statuses[0].displayStatus}}"
az vm boot-diagnostics get-boot-log -g rg-contoso-vmlt-pilot -n vm-contoso-web01
az vm show -g rg-contoso-vmlt-pilot -n vm-contoso-web01 --query "{size: hardwareProfile.vmSize, luns: storageProfile.dataDisks[].lun}"
az network nic show --ids <nic-id> --query enableAcceleratedNetworking
```

Then run the application health probe when one is defined, and ask the workload
owner to confirm.

Rollback criteria: the VM doesn't reach `VM running`, the guest agent or a
required extension isn't healthy, a data disk LUN is missing, Accelerated
Networking is off where it's required, or the owner rejects the result.

## 5. Roll back (each command approved)

```bash
az vm deallocate -g rg-contoso-vmlt-pilot -n vm-contoso-web01
az vm resize -g rg-contoso-vmlt-pilot -n vm-contoso-web01 --size <recorded-original-size>
az vm start -g rg-contoso-vmlt-pilot -n vm-contoso-web01
```

Flag the VM for a person and record why the rollback happened.

## 6. Change record

Post a short record to the thread (and to Teams or email when a connector is
configured):

| Field | Example |
| --- | --- |
| VM | `vm-contoso-web01` |
| Change | `Standard_DS3_v2` to `Standard_D4ds_v5` |
| Why | Dsv2 retires 2028-05-01; disposition `resize-to-v5` |
| When | Start and end time in UTC |
| Approver | The SRE Agent Administrator who approved each command |
| Evidence | Pre-check and verification output |
| Outcome | Succeeded, rolled back, or stopped at a pre-check |

## Out of scope

- Redeploys to v6 or v7: the agent writes a draft runbook; people or the
  migration partner run it.
- Scale sets, availability sets with several members, and clustered workloads:
  plan them as waves with the workload owner.
- Purchases, capacity reservations, and quota submissions: the customer decides
  and acts.
