<#
.SYNOPSIS
Removes everything Deploy-Lab.ps1 created.

.DESCRIPTION
Deletes, in order:
1. assignments of the custom "VM lifecycle landing reader" role at subscription
   scope, then the role definition;
2. the lab resource groups and the agent resource group, which also removes the
   resource-group-scoped role assignments and any pilot policy exemption;
3. the subscription deployment history entries.

The Log Analytics workspaces are soft-deleted for 14 days, as usual.

.EXAMPLE
./Remove-Lab.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [string]$Prefix = 'contoso-vmlt',

    [string]$AgentResourceGroupName = 'rg-contoso-vmlt-agent',

    [string]$StateDirectory = (Join-Path $HOME '.vmlt-lab'),

    [Parameter(HelpMessage = 'Also delete the local SSH key and answer key.')]
    [switch]$RemoveLocalState,

    [switch]$NoWait
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & az @Arguments --subscription $SubscriptionId --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Arguments[0..2] -join ' ') failed: $($output | Out-String)"
    }
    return $output
}

$subscriptionScope = "/subscriptions/$SubscriptionId"
$roleName = "VM lifecycle landing reader ($SubscriptionId)"

$roles = @(Invoke-Az -Arguments @('role', 'definition', 'list', '--custom-role-only', 'true', '--scope', $subscriptionScope,
        '--name', $roleName, '-o', 'json') | Out-String | ConvertFrom-Json)
foreach ($role in $roles) {
    $assignments = @(Invoke-Az -Arguments @('role', 'assignment', 'list', '--scope', $subscriptionScope, '--role', $role.name,
            '--fill-principal-name', 'false', '--fill-role-definition-name', 'false', '-o', 'json') | Out-String | ConvertFrom-Json)
    foreach ($assignment in $assignments) {
        if ($PSCmdlet.ShouldProcess($assignment.id, 'Delete role assignment')) {
            Invoke-Az -Arguments @('role', 'assignment', 'delete', '--ids', $assignment.id) | Out-Null
        }
    }
    if ($PSCmdlet.ShouldProcess($roleName, 'Delete custom role definition')) {
        Invoke-Az -Arguments @('role', 'definition', 'delete', '--name', $role.name, '--scope', $subscriptionScope) | Out-Null
    }
}

# The pilot group goes first: its VM is associated with the estate's data collection rule.
foreach ($group in @("rg-$Prefix-pilot", "rg-$Prefix-estate", $AgentResourceGroupName)) {
    $exists = (Invoke-Az -Arguments @('group', 'exists', '--name', $group)) -eq 'true'
    if ($exists -and $PSCmdlet.ShouldProcess($group, 'Delete resource group and everything in it')) {
        Write-Host "Deleting $group"
        $arguments = @('group', 'delete', '--name', $group, '--yes')
        if ($NoWait) { $arguments += '--no-wait' }
        Invoke-Az -Arguments $arguments | Out-Null
    }
}

foreach ($deployment in @("vmlt-lab-$Prefix", "vmlt-agent-$Prefix")) {
    $found = Invoke-Az -Arguments @('deployment', 'sub', 'list', '--query', "[?name=='$deployment'].name", '-o', 'tsv')
    if ($found -and $PSCmdlet.ShouldProcess($deployment, 'Delete subscription deployment record')) {
        Invoke-Az -Arguments @('deployment', 'sub', 'delete', '--name', $deployment) | Out-Null
    }
}

if ($RemoveLocalState -and (Test-Path $StateDirectory) -and $PSCmdlet.ShouldProcess($StateDirectory, 'Delete local lab state')) {
    Remove-Item -Recurse -Force $StateDirectory
}

Write-Host 'Lab removal finished.'
