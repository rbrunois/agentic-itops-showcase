<#
.SYNOPSIS
Deploys the VM lifecycle lab and, optionally, its Azure SRE Agent.

.DESCRIPTION
Creates billable resources in the subscription:
- rg-<prefix>-estate and rg-<prefix>-pilot with the VMs, scale set, network,
  Log Analytics workspace, and VM insights rule defined in lab-design.json;
- unless -SkipAgent, rg-contoso-vmlt-agent with Azure SRE Agent, its managed
  identity, Log Analytics, and Application Insights, plus a custom
  subscription-scope role that only reads quota, VM sizes, and policy.

Run Test-LabFeasibility.ps1 first. The SSH key and the answer key (which
contains real resource IDs) are written to -StateDirectory, outside the
repository. Remove everything with Remove-Lab.ps1.

.EXAMPLE
./Deploy-Lab.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -WhatIf
./Deploy-Lab.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [string]$Location = 'canadacentral',

    [string]$Prefix = 'contoso-vmlt',

    [string]$StateDirectory = (Join-Path $HOME '.vmlt-lab'),

    [ValidateRange(500, 1000000)]
    [int]$MonthlyAgentUnitLimit = 100000,

    [switch]$SkipAgent,

    [Parameter(HelpMessage = 'Deploy only the agent, for example to retry it. The lab must already exist.')]
    [switch]$SkipLab
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$demoRoot = Split-Path -Parent $PSScriptRoot
$infra = Join-Path $demoRoot 'infra'
$design = Get-Content (Join-Path $demoRoot 'lab-design.json') -Raw | ConvertFrom-Json

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & az @Arguments --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Arguments[0..2] -join ' ') failed: $($output | Out-String)"
    }
    return $output
}

# Local preparation runs even with -WhatIf, because the what-if deployment needs the key.
New-Item -ItemType Directory -Force -Path $StateDirectory -WhatIf:$false | Out-Null

$keyPath = Join-Path $StateDirectory 'lab_rsa'
if (-not (Test-Path "$keyPath.pub")) {
    Write-Host "Creating an SSH key for the lab VMs in $StateDirectory"
    & ssh-keygen -q -t rsa -b 3072 -f $keyPath -N '' -C 'vmlt-lab' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen failed.' }
}
$publicKey = (Get-Content "$keyPath.pub" -Raw).Trim()

$labParameters = Join-Path $StateDirectory 'main.parameters.json'
@{
    '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters     = @{
        location     = @{ value = $Location }
        prefix       = @{ value = $Prefix }
        sshPublicKey = @{ value = $publicKey }
    }
} | ConvertTo-Json -Depth 5 | Set-Content -Path $labParameters -Encoding utf8 -WhatIf:$false

$labDeployment = @('deployment', 'sub', 'create', '--name', "vmlt-lab-$Prefix", '--location', $Location,
    '--subscription', $SubscriptionId, '--template-file', (Join-Path $infra 'main.bicep'), '--parameters', "@$labParameters")

if (-not $PSCmdlet.ShouldProcess("subscription $SubscriptionId", 'Deploy the VM lifecycle lab')) {
    Write-Host 'What-if for the lab deployment:'
    $labDeployment[2] = 'what-if'
    & az @labDeployment --only-show-errors
    return
}

if (-not $SkipLab) {
    Write-Host 'Deploying the lab estate and pilot (VMs take several minutes)...'
    Invoke-Az -Arguments ($labDeployment + @('--query', 'properties.provisioningState', '-o', 'tsv')) | Write-Host

    foreach ($vm in @($design.vms | Where-Object { $_.deallocate })) {
        $group = "rg-$Prefix-$($vm.resourceGroup)"
        Write-Host "Deallocating $($vm.name) so the lab includes a stopped VM"
        Invoke-Az -Arguments @('vm', 'deallocate', '--resource-group', $group, '--name', $vm.name, '--subscription', $SubscriptionId, '--no-wait') | Out-Null
    }
}

if (-not $SkipAgent) {
    # A parameters file avoids quoting problems: az is a .cmd wrapper on Windows.
    $agentParameters = Join-Path $StateDirectory 'agent.parameters.json'
    @{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters     = @{
            location                = @{ value = $Location }
            monthlyAgentUnitLimit   = @{ value = $MonthlyAgentUnitLimit }
            targetResourceGroups    = @{ value = @("rg-$Prefix-estate", "rg-$Prefix-pilot") }
            logAnalyticsWorkspaceId = @{ value = "/subscriptions/$SubscriptionId/resourceGroups/rg-$Prefix-estate/providers/Microsoft.OperationalInsights/workspaces/law-$Prefix" }
        }
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $agentParameters -Encoding utf8

    Write-Host 'Deploying Azure SRE Agent (it bills hourly for as long as it exists)...'
    $agentOutputs = Invoke-Az -Arguments @('deployment', 'sub', 'create', '--name', "vmlt-agent-$Prefix", '--location', $Location,
        '--subscription', $SubscriptionId, '--template-file', (Join-Path $infra 'agent.bicep'),
        '--parameters', "@$agentParameters", '--query', 'properties.outputs', '-o', 'json') | Out-String | ConvertFrom-Json
    Write-Host "Agent: $($agentOutputs.agentName.value) in $($agentOutputs.agentResourceGroup.value)"
    $agentOutputs | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $StateDirectory 'agent.json') -Encoding utf8
}

# The answer key is the lab design plus real resource IDs. It stays outside the repository.
$answers = @()
foreach ($vm in $design.vms) {
    $answers += [pscustomobject]@{
        name                  = $vm.name
        resourceId            = "/subscriptions/$SubscriptionId/resourceGroups/rg-$Prefix-$($vm.resourceGroup)/providers/Microsoft.Compute/virtualMachines/$($vm.name)"
        type                  = 'virtualMachine'
        size                  = $design.vmSize
        hyperVGeneration      = $vm.generation
        trustedLaunch         = $vm.trustedLaunch
        acceleratedNetworking = $vm.acceleratedNetworking
        ipForwarding          = $vm.ipForwarding
        deallocated           = $vm.deallocate
        tags                  = $vm.tags
        expected              = $vm.expected
    }
}
foreach ($scaleSet in $design.scaleSets) {
    $answers += [pscustomobject]@{
        name       = $scaleSet.name
        resourceId = "/subscriptions/$SubscriptionId/resourceGroups/rg-$Prefix-$($scaleSet.resourceGroup)/providers/Microsoft.Compute/virtualMachineScaleSets/$($scaleSet.name)"
        type       = 'virtualMachineScaleSet'
        size       = $design.vmSize
        instances  = $scaleSet.capacity
        tags       = $scaleSet.tags
        expected   = $scaleSet.expected
    }
}
[pscustomobject]@{
    subscriptionId     = $SubscriptionId
    createdAt          = (Get-Date).ToUniversalTime().ToString('o')
    expectedForEveryVm = $design.expectedForEveryVm
    resources          = $answers
} | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $StateDirectory 'answer-key.json') -Encoding utf8

Write-Host "Done. Answer key: $(Join-Path $StateDirectory 'answer-key.json')"
