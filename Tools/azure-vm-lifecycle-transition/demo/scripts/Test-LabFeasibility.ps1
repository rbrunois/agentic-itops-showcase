<#
.SYNOPSIS
Read-only check: can a subscription host the VM lifecycle transition lab?

.DESCRIPTION
Uses the signed-in Azure CLI account. Reports subscription access, whether the
account can create role assignments, Azure SRE Agent availability, vCPU quota
for the lab's VM families, whether each lab size is offered to the
subscription, whether Azure Policy would deny each size, and assigned policies.
Makes no changes.

New subscriptions can't deploy End of Life VM series, and existing ones can
only use quota they already have, so run this before Deploy-Lab.ps1.

.EXAMPLE
./Test-LabFeasibility.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Location canadacentral, canadaeast
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [string[]]$Location = @('canadacentral'),

    [string[]]$Size = @(
        'Standard_DS2_v2', 'Standard_DS1_v2', 'Standard_D2_v2', 'Standard_D1_v2',
        'Standard_D2s_v3', 'Standard_D2_v3', 'Standard_E2s_v3', 'Standard_E2_v3',
        'Standard_F2s_v2', 'Standard_F2s', 'Standard_B1s', 'Standard_B1ms', 'Standard_B2s',
        'Standard_A2_v2', 'Standard_A1_v2', 'Standard_D2s_v5', 'Standard_D2ds_v5', 'Standard_D2as_v5'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & az @Arguments --only-show-errors -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Arguments -join ' ') failed: $output"
    }
    return ($output | Out-String | ConvertFrom-Json)
}

$account = Invoke-AzJson @('account', 'show', '--subscription', $SubscriptionId)
Write-Host "Subscription: $($account.name) ($($account.id)), state $($account.state), signed in as $($account.user.name)"

# Permissions on the subscription for the signed-in account (read-only API).
$token = (& az account get-access-token --subscription $SubscriptionId --query accessToken -o tsv --only-show-errors)
$permissionUri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/permissions?api-version=2022-04-01"
$permissions = Invoke-RestMethod -Uri $permissionUri -Headers @{ Authorization = "Bearer $token" }
$actions = @($permissions.value | ForEach-Object { $_.actions })
$notActions = @($permissions.value | ForEach-Object { $_.notActions })
$canAssignRoles = ($actions -contains '*' -or $actions -contains 'Microsoft.Authorization/*' -or $actions -contains 'Microsoft.Authorization/roleAssignments/write') -and
    -not ($notActions -contains 'Microsoft.Authorization/*/Write' -or $notActions -contains 'Microsoft.Authorization/roleAssignments/write')
$canWrite = $actions -contains '*'
Write-Host "Can create resources: $canWrite. Can create role assignments (needed for the agent identity): $canAssignRoles"

$app = Invoke-AzJson @('provider', 'show', '--namespace', 'Microsoft.App', '--subscription', $SubscriptionId)
$agentType = @($app.resourceTypes | Where-Object { $_.resourceType -eq 'agents' })
if ($agentType) {
    Write-Host "Azure SRE Agent (Microsoft.App/agents): provider $($app.registrationState); regions: $($agentType[0].locations -join ', ')"
} else {
    Write-Host "Azure SRE Agent (Microsoft.App/agents): not offered to this subscription (provider $($app.registrationState))"
}

# Asks Azure Policy whether a VM of this size would be denied. The policy
# restrictions API only evaluates; it creates nothing.
function Test-PolicyDenied {
    param([string]$Region, [string]$VmSize)
    $body = @{
        resourceDetails = @{
            resourceContent = @{
                type       = 'Microsoft.Compute/virtualMachines'
                location   = $Region
                properties = @{ hardwareProfile = @{ vmSize = $VmSize } }
            }
            apiVersion      = '2024-07-01'
        }
    } | ConvertTo-Json -Depth 8
    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.PolicyInsights/checkPolicyRestrictions?api-version=2022-03-01"
    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $body
    } catch {
        return 'unknown'
    }
    $denials = @($response.contentEvaluationResult.policyEvaluations | Where-Object {
            $_.evaluationResult -eq 'NonCompliant' -and $_.policyInfo.policyDefinitionEffect -eq 'deny'
        })
    if ($denials.Count -gt 0) {
        return 'denied: ' + (($denials | ForEach-Object { $_.policyInfo.policyAssignmentName }) -join ', ')
    }
    return 'allowed'
}

$results = foreach ($region in $Location) {
    $usage = Invoke-AzJson @('vm', 'list-usage', '--location', $region, '--subscription', $SubscriptionId)
    $usageByName = @{}
    foreach ($item in $usage) { $usageByName[$item.name.value] = $item }
    $regional = $usageByName['cores']

    $skus = Invoke-AzJson @('vm', 'list-skus', '--location', $region, '--resource-type', 'virtualMachines', '--all', '--subscription', $SubscriptionId)
    foreach ($name in $Size) {
        $policyDenied = Test-PolicyDenied -Region $region -VmSize $name
        $sku = $skus | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if (-not $sku) {
            [pscustomobject]@{ Region = $region; Size = $name; Family = ''; vCPUs = ''; Offered = $false; Restriction = 'not listed in region'; PolicyDenied = $policyDenied; Zones = ''; QuotaFree = ''; QuotaLimit = '' }
            continue
        }
        $vcpus = ($sku.capabilities | Where-Object { $_.name -eq 'vCPUs' }).value
        $restrictions = @($sku.restrictions | ForEach-Object { "$($_.type):$($_.reasonCode)" }) -join '; '
        $locationBlocked = @($sku.restrictions | Where-Object { $_.type -eq 'Location' }).Count -gt 0
        $zones = @($sku.locationInfo | ForEach-Object { $_.zones }) | Sort-Object
        $quota = $usageByName[$sku.family]
        [pscustomobject]@{
            Region       = $region
            Size         = $name
            Family       = $sku.family
            vCPUs        = $vcpus
            Offered      = -not $locationBlocked
            Restriction  = $restrictions
            PolicyDenied = $policyDenied
            Zones        = ($zones -join ',')
            QuotaFree    = if ($quota) { $quota.limit - $quota.currentValue } else { 'n/a' }
            QuotaLimit   = if ($quota) { $quota.limit } else { 'n/a' }
        }
    }
    Write-Host "Region $region total vCPU quota: $($regional.currentValue) used of $($regional.limit)"
}

$results | Format-Table -AutoSize | Out-String -Width 220 | Write-Host

$assignments = Invoke-AzJson @('policy', 'assignment', 'list', '--subscription', $SubscriptionId, '--disable-scope-strict-match')
Write-Host "Azure Policy assignments that apply: $(@($assignments).Count)"
$assignments | ForEach-Object { "  - $($_.displayName) [$($_.enforcementMode)]" } | Write-Host

$results
