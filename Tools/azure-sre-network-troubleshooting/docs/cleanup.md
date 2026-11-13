# Cleanup

Deletion is irreversible and separately approved. All examples below are operator instructions, not agent actions. Use the same explicitly selected Az PowerShell subscription as the recorded deployment.

Run all commands from `Tools\azure-sre-network-troubleshooting`. Review the
complete ownership/inventory before proceeding. Technical flags/confirmations
do not replace organizational authorization.

## Optional Connection Monitor first

The monitor lives outside the dedicated group. Baseline cleanup intentionally does not discover/delete monitors in the shared group.

In PowerShell, load the validated local context and read the additive deployment's outputs:

```powershell
. .\scripts\common.ps1
$context = Get-DeploymentContext -Path .\scripts\deployment-context.json
Assert-DeploymentSubscription -SubscriptionId $context.subscriptionId
$deployment = Get-AzResourceGroupDeployment -ResourceGroupName $context.resourceGroupName `
    -Name 'sre-network-demo-connection-monitor'
$monitorId = Get-OutputValue $deployment.Outputs @('connectionMonitorId') -Required
$expectedMonitorId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Network/networkWatchers/{2}/connectionMonitors/cm-{3}-client-to-iis' -f `
    $context.subscriptionId, $context.networkWatcherResourceGroup, $context.networkWatcherName, $context.resourceGroupName.Substring(3)
if ($monitorId -ine $expectedMonitorId) { throw 'Unexpected monitor scope; nothing will be deleted.' }
Get-AzResource -ResourceId $monitorId | Format-List Name,ResourceType,ResourceId
```

If a custom deployment name was used, read that exact reviewed deployment instead. Only after independent deletion approval, in the same session:

```powershell
if ((Read-Host "Type DELETE $monitorId") -cne "DELETE $monitorId") { throw 'Deletion not approved.' }
Remove-AzResource -ResourceId $monitorId -Force
```

Verify only this monitor was removed. Do not delete its parent watcher, sibling monitors, shared group, or service-managed ingestion resources. Its source extension disappears with the client VM during full cleanup; if retaining the baseline, leaving that extension installed is acceptable.

## Baseline cleanup

Inspect the local plan first; without `-Execute` no Azure calls occur:

```powershell
.\scripts\cleanup.ps1
```

After explicit approval:

```powershell
.\scripts\cleanup.ps1 -Execute
```

The script:

1. Validates the generic dedicated-group naming boundary and recorded scope/flow names.
2. Checks the authenticated subscription and actual group ID.
3. Requires ownership tags `workload=sre-network-demo` and `environment=demo`.
4. Lists resources, resolves only the two owned flow logs, and verifies their target VNets. Already absent expected logs are reported and skipped.
5. Resolves only recorded role assignments at the dedicated group/workspace scopes.
6. Requires `DELETE <group-name> AND FLOW LOGS <exact-name-list>`.
7. Removes the owned flow-log children first, then recorded assignments, then the dedicated group.

It does not delete the shared watcher/group or unregister providers. Listing is not proof that every resource is disposable: review the entire dedicated group and refuse cleanup if unrelated resources were added.

## Separately created agent resources

The agent is created manually and may live outside the dedicated group. Baseline cleanup does not discover or delete external agents, identities, or manually granted external roles.

Through a separate approved process, list and verify the exact agent, backing resources, managed identity, and manual role assignments created for this lab. Remove only lab-owned items; follow the current SRE Agent lifecycle guidance. Never delete a shared identity or expand deletion to a subscription/shared group.

## Completion checks

- The exact optional monitor and two demo flow-log children are gone.
- The dedicated group, Windows VMs/disks/public IPs, Storage, workspace, DCR and extensions are gone.
- Manual agent resources and lab-only access assignments are removed or deliberately retained with cost/ownership approval.
- Shared watcher/group, siblings, and provider registration state are unchanged.
- Check for remaining lab charges and asynchronous deletion failures.
- Keep any retained deployment context/evidence local and excluded; never upload it as cleanup proof.

## Failed or partial deployment

There is no automatic rollback. A failed deployment can leave billable resources
without a complete runtime context; do not manufacture context to bypass guards.
In the same explicitly selected Az PowerShell subscription, inspect only the
exact resource group and deployment name reviewed before provisioning:

```powershell
. .\scripts\common.ps1
$subscriptionId = Read-Host 'Approved non-production subscription ID'
Assert-DeploymentSubscription -SubscriptionId $subscriptionId
$groupName = Read-Host 'Exact dedicated demo group from the reviewed deployment'
Assert-SafeDemoResourceGroup -Name $groupName
Get-AzResourceGroup -Name $groupName | Format-List ResourceId,Tags
Get-AzResource -ResourceGroupName $groupName | Format-Table Name,ResourceType,ResourceId
```

Select the intended Az PowerShell subscription explicitly beforehand; the
assertion never switches it. Preserve deployment errors locally. Through a separately approved
operator process review and remove only the actual owned resources, including
exact flow-log children outside the group. Never broaden cleanup to the
subscription/shared watcher or delete by wildcard. Verify costs/deletion
afterward; contact the lab owner when ownership is uncertain.
