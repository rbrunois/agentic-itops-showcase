<#
.SYNOPSIS
Runs the package queries against the lab and checks them against lab-design.json.

.DESCRIPTION
Read-only. Runs queries/arg-affected-vms.kql and queries/arg-vm-profile.kql with
Azure Resource Graph, and queries/metrics-30d-utilization.kql against the lab
Log Analytics workspace. Run it after Deploy-Lab.ps1; the utilization checks need
about 15 minutes of VM insights data.

Returns one object per check. Results are also saved to
<StateDirectory>/results, outside the repository, because they contain real
resource IDs.

.EXAMPLE
./Test-LabQueries.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [string]$Prefix = 'contoso-vmlt',

    [string]$StateDirectory = (Join-Path $HOME '.vmlt-lab')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$demoRoot = Split-Path -Parent $PSScriptRoot
$queries = Join-Path (Split-Path -Parent $demoRoot) 'queries'
$design = Get-Content (Join-Path $demoRoot 'lab-design.json') -Raw | ConvertFrom-Json

function Get-Token([string]$Resource) {
    $token = & az account get-access-token --subscription $SubscriptionId --resource $Resource --query accessToken -o tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $token) { throw "Couldn't get a token for $Resource." }
    return $token
}

function Invoke-ResourceGraph([string]$Query) {
    $token = Get-Token 'https://management.azure.com/'
    $body = @{ subscriptions = @($SubscriptionId); query = $Query; options = @{ resultFormat = 'objectArray' } } | ConvertTo-Json -Depth 5
    $result = Invoke-RestMethod -Method Post -Uri 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' `
        -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $body
    # The lab is far below one page (1,000 rows), so paging isn't needed here.
    return @($result.data)
}

function Invoke-LogAnalytics([string]$WorkspaceId, [string]$Query) {
    $token = Get-Token 'https://api.loganalytics.io'
    $result = Invoke-RestMethod -Method Post -Uri "https://api.loganalytics.io/v1/workspaces/$WorkspaceId/query" `
        -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body (@{ query = $Query } | ConvertTo-Json)
    $columns = $result.tables[0].columns.name
    foreach ($row in $result.tables[0].rows) {
        $item = [ordered]@{}
        for ($i = 0; $i -lt $columns.Count; $i++) { $item[$columns[$i]] = $row[$i] }
        [pscustomobject]$item
    }
}

function Format-Day($Value) {
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Local) { $Value = $Value.ToUniversalTime() }
        return $Value.ToString('yyyy-MM-dd')
    }
    return ([string]$Value).Substring(0, 10)
}

function Get-Tag($Tags, [string]$Name) {
    $property = $Tags.PSObject.Properties[$Name]
    if ($property) { return [string]$property.Value }
    return ''
}

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check([string]$Layer, [string]$Resource, [string]$Check, $Expected, $Actual) {
    # Resource Graph returns booleans as 1 or 0.
    if ($Expected -is [bool] -and ($Actual -is [long] -or $Actual -is [int])) { $Actual = [bool]$Actual }
    $checks.Add([pscustomobject]@{
            layer    = $Layer
            resource = $Resource
            check    = $Check
            expected = "$Expected"
            actual   = "$Actual"
            result   = if ("$Expected" -eq "$Actual") { 'PASS' } else { 'FAIL' }
        })
}

function Get-ResourceId([string]$Group, [string]$Type, [string]$Name) {
    return "/subscriptions/$SubscriptionId/resourceGroups/rg-$Prefix-$Group/providers/Microsoft.Compute/$Type/$Name"
}

$vms = @($design.vms | ForEach-Object { $_ | Add-Member -NotePropertyName id -NotePropertyValue (Get-ResourceId $_.resourceGroup 'virtualMachines' $_.name) -PassThru })
$scaleSets = @($design.scaleSets | ForEach-Object { $_ | Add-Member -NotePropertyName id -NotePropertyValue (Get-ResourceId $_.resourceGroup 'virtualMachineScaleSets' $_.name) -PassThru })
$expected = $design.expectedForEveryVm

# 1. Inventory: series, dates, priority, capacity restriction, power state, instances.
$affected = Invoke-ResourceGraph (Get-Content (Join-Path $queries 'arg-affected-vms.kql') -Raw)
foreach ($resource in @($vms) + @($scaleSets)) {
    $row = $affected | Where-Object { $_.id -eq $resource.id }
    Add-Check 'inventory' $resource.name 'returned by arg-affected-vms' $true ([bool]$row)
    if (-not $row) { continue }
    Add-Check 'inventory' $resource.name 'lifecycleSeries' $expected.lifecycleSeries $row.lifecycleSeries
    Add-Check 'inventory' $resource.name 'retirementDate' $expected.retirementDate (Format-Day $row.retirementDate)
    Add-Check 'inventory' $resource.name 'capacityRestricted' $expected.capacityRestricted $row.capacityRestricted
    Add-Check 'inventory' $resource.name 'priority' $expected.priority $row.priority
    if ($resource.PSObject.Properties['capacity']) {
        Add-Check 'inventory' $resource.name 'instances' $resource.capacity $row.instances
    }
    else {
        Add-Check 'inventory' $resource.name 'deallocated' $resource.deallocate ($row.powerState -eq 'PowerState/deallocated')
    }
}

# 2. Readiness profile: generation, security type, networking, ownership and role tags.
$profiles = Invoke-ResourceGraph (Get-Content (Join-Path $queries 'arg-vm-profile.kql') -Raw)
foreach ($vm in $vms) {
    $row = $profiles | Where-Object { $_.id -eq $vm.id }
    Add-Check 'profile' $vm.name 'returned by arg-vm-profile' $true ([bool]$row)
    if (-not $row) { continue }
    Add-Check 'profile' $vm.name 'hyperVGeneration' $vm.generation $row.hyperVGeneration
    Add-Check 'profile' $vm.name 'trustedLaunch' $vm.trustedLaunch ($row.securityType -eq 'TrustedLaunch')
    Add-Check 'profile' $vm.name 'acceleratedNetworking' $(if ($vm.acceleratedNetworking) { 'Yes' } else { 'No' }) $row.acceleratedNetworking
    Add-Check 'profile' $vm.name 'ipForwarding' $(if ($vm.ipForwarding) { 'Yes' } else { 'No' }) $row.ipForwarding
    Add-Check 'profile' $vm.name 'owner tag' (Get-Tag $vm.tags 'owner') $row.owner
    Add-Check 'profile' $vm.name 'role tag' (Get-Tag $vm.tags 'role') $row.role
    Add-Check 'profile' $vm.name 'dr-region tag' (Get-Tag $vm.tags 'dr-region') $row.drRegion
    Add-Check 'profile' $vm.name 'environment tag present' $true (-not [string]::IsNullOrEmpty($row.environment))
}

# 3. Utilization: data present, CPU load where the lab adds it, stale data on deallocated VMs.
$workspace = Invoke-ResourceGraph "Resources | where type =~ 'microsoft.operationalinsights/workspaces' and resourceGroup =~ 'rg-$Prefix-estate' | project customerId = tostring(properties.customerId)"
if (-not $workspace) { throw "No Log Analytics workspace found in rg-$Prefix-estate." }
$utilization = @(Invoke-LogAnalytics $workspace[0].customerId (Get-Content (Join-Path $queries 'metrics-30d-utilization.kql') -Raw))
$now = (Get-Date).ToUniversalTime()
foreach ($vm in $vms) {
    $row = $utilization | Where-Object { $_.resourceId -eq $vm.id.ToLowerInvariant() }
    Add-Check 'utilization' $vm.name 'VM insights data present' $true ([bool]$row)
    if (-not $row) { continue }
    $load = if ([double]$row.cpuP95 -ge 70) { 'high' } else { 'low' }
    Add-Check 'utilization' $vm.name 'CPU P95 band' $(if ($vm.cpuLoad) { 'high' } else { 'low' }) $load
    # VM insights sends every minute; a VM with no sample for 15 minutes has stopped reporting.
    $minutesSinceLast = ($now - ([datetime]$row.lastSample).ToUniversalTime()).TotalMinutes
    Add-Check 'utilization' $vm.name 'still reporting (sample in last 15 minutes)' (-not $vm.deallocate) ($minutesSinceLast -le 15)
}
foreach ($scaleSet in $scaleSets) {
    $instances = @($utilization | Where-Object { $_.scaleSetId -eq $scaleSet.id.ToLowerInvariant() })
    Add-Check 'utilization' $scaleSet.name 'instances with VM insights data' $scaleSet.capacity $instances.Count
}

$failed = @($checks | Where-Object result -eq 'FAIL')
Write-Host "$($checks.Count) checks, $($checks.Count - $failed.Count) passed, $($failed.Count) failed."

$results = Join-Path $StateDirectory 'results'
New-Item -ItemType Directory -Force -Path $results | Out-Null
$file = Join-Path $results ("query-checks-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
$checks | ConvertTo-Json -Depth 4 | Set-Content -Path $file -Encoding utf8
Write-Host "Saved to $file"

$checks
