[CmdletBinding(DefaultParameterSetName = 'Object')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Object')]$DeploymentObject,
    [Parameter(Mandatory, ParameterSetName = 'Azure')][string]$DeploymentName,
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(ParameterSetName = 'Azure')][switch]$Execute,
    [string]$ContextPath = (Join-Path $PSScriptRoot 'deployment-context.json')
)

. (Join-Path $PSScriptRoot 'common.ps1')

if ($PSCmdlet.ParameterSetName -eq 'Azure') {
    if (-not (Assert-Execute -Execute $Execute -Operation "read deployment '$DeploymentName' outputs")) {
        return
    }
    Assert-DeploymentSubscription -SubscriptionId $SubscriptionId
    $DeploymentObject = Get-AzSubscriptionDeployment -Name $DeploymentName
}

$outputs = $DeploymentObject.Outputs
if (-not $outputs) { throw 'The deployment has no outputs.' }
$normalized = [ordered]@{
    schemaVersion = 1
    capturedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    deploymentName = if ($DeploymentObject.PSObject.Properties['DeploymentName'] -and $DeploymentObject.DeploymentName) {
        $DeploymentObject.DeploymentName
    } else { $DeploymentObject.Name }
    subscriptionId = Get-OutputValue $outputs @('subscriptionId')
    resourceGroupName = Get-OutputValue $outputs @('resourceGroupName') -Required
    resourceGroupId = Get-OutputValue $outputs @('resourceGroupId') -Required
    location = Get-OutputValue $outputs @('location')
    clientVnetId = Get-OutputValue $outputs @('clientVnetId') -Required
    workloadVnetId = Get-OutputValue $outputs @('workloadVnetId') -Required
    clientVmId = Get-OutputValue $outputs @('clientVmId') -Required
    workloadVmId = Get-OutputValue $outputs @('workloadVmId') -Required
    clientVmName = Get-OutputValue $outputs @('clientVmName') -Required
    workloadVmName = Get-OutputValue $outputs @('workloadVmName', 'webVmName') -Required
    clientPrivateIp = Get-OutputValue $outputs @('clientPrivateIp', 'clientPrivateIPAddress') -Required
    workloadPrivateIp = Get-OutputValue $outputs @('workloadPrivateIp', 'webPrivateIp', 'workloadPrivateIPAddress') -Required
    clientSubnetPrefix = Get-OutputValue $outputs @('clientSubnetPrefix') -Required
    workloadSubnetPrefix = Get-OutputValue $outputs @('workloadSubnetPrefix') -Required
    workloadNsgName = Get-OutputValue $outputs @('workloadNsgName') -Required
    workspaceCustomerId = Get-OutputValue $outputs @('workspaceCustomerId') -Required
    workspaceResourceId = Get-OutputValue $outputs @('workspaceResourceId')
    networkWatcherResourceGroup = Get-OutputValue $outputs @('networkWatcherResourceGroup') -Required
    networkWatcherName = Get-OutputValue $outputs @('networkWatcherName') -Required
    flowLogNames = @(
        Get-OutputValue $outputs @('flowLogNames') -Required |
            ForEach-Object { [string]$_ }
    )
    roleAssignmentIds = @(
        Get-OutputValue $outputs @('roleAssignmentIds') |
            Where-Object { $null -ne $_ } |
            ForEach-Object { [string]$_ }
    )
}
Assert-DeploymentContext -Context ([pscustomobject]$normalized)
if ($normalized.subscriptionId -ine $SubscriptionId) {
    throw 'Deployment outputs do not match the explicitly requested subscription. No context was saved.'
}
Save-JsonEvidence -InputObject $normalized -Path $ContextPath
