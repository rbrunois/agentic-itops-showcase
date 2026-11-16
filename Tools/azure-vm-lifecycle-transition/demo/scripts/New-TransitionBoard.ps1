<#
.SYNOPSIS
Writes the VM lifecycle transition board as a self-contained HTML page.

.DESCRIPTION
Runs queries/live-report-transition-board.kql against a Log Analytics workspace
with the signed-in Azure CLI account, then writes one HTML file with summary
tiles, a sortable table with the next step for each resource, and a bar chart.
The page loads nothing from the internet. Read-only.

Use it while Azure SRE Agent live reports can't read the Log Analytics data: in
the lab, live reports listed no Log Analytics or Azure Monitor connector. Run it
again to refresh the board.

.EXAMPLE
./New-TransitionBoard.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [string]$ResourceGroup = 'rg-contoso-vmlt-estate',

    [string]$WorkspaceName = 'law-contoso-vmlt',

    [string]$OutFile = (Join-Path $HOME (".vmlt-lab/results/transition-board-{0:yyyyMMdd-HHmmss}.html" -f (Get-Date)))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$query = Get-Content (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'queries/live-report-transition-board.kql') -Raw

function Get-Token([string]$Resource) {
    $token = & az account get-access-token --subscription $SubscriptionId --resource $Resource --query accessToken -o tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $token) { throw "Couldn't get a token for $Resource." }
    return $token
}

$armToken = Get-Token 'https://management.azure.com/'
$workspaceUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName" + '?api-version=2023-09-01'
$workspaceId = (Invoke-RestMethod -Uri $workspaceUri -Headers @{ Authorization = "Bearer $armToken" }).properties.customerId

$result = Invoke-RestMethod -Method Post -Uri "https://api.loganalytics.io/v1/workspaces/$workspaceId/query" `
    -Headers @{ Authorization = "Bearer $(Get-Token 'https://api.loganalytics.io')" } -ContentType 'application/json' `
    -Body (@{ query = $query } | ConvertTo-Json)
$columns = $result.tables[0].columns.name
$rows = foreach ($row in $result.tables[0].rows) {
    $item = [ordered]@{}
    for ($i = 0; $i -lt $columns.Count; $i++) { $item[$columns[$i]] = $row[$i] }
    [pscustomobject]$item
}
$rows = @($rows)

function Get-Html($Value) { [System.Net.WebUtility]::HtmlEncode([string]$Value) }

function Get-Day($Value) {
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-dd') }
    return ([string]$Value).Substring(0, [Math]::Min(10, ([string]$Value).Length))
}

$generated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'
$instances = ($rows | Measure-Object -Property instances -Sum).Sum
$tiles = @(
    @{ label = 'Resources on End of Life series'; value = $rows.Count }
    @{ label = 'VM instances'; value = $instances }
) + @($rows | Group-Object priority | Sort-Object Name | ForEach-Object { @{ label = $_.Name; value = $_.Count } }) +
@($rows | Group-Object { Get-Day $_.retirementDate } | Sort-Object Name | ForEach-Object { @{ label = "Retire on $($_.Name)"; value = $_.Count } })

$tileHtml = ($tiles | ForEach-Object { "<div class=`"tile`"><span class=`"value`">$(Get-Html $_.value)</span><span class=`"label`">$(Get-Html $_.label)</span></div>" }) -join "`n"

$fields = @(
    @('name', 'Name'), @('resourceGroup', 'Resource group'), @('vmSize', 'Size'), @('lifecycleSeries', 'Series'),
    @('retirementDate', 'Retires'), @('daysToRetirement', 'Days left'), @('instances', 'Instances'), @('powerState', 'Power state'),
    @('owner', 'Owner'), @('cpuP95', 'CPU p95 (%)'), @('utilizationNote', 'Utilization data'), @('nextStep', 'Next step')
)
$headerHtml = ($fields | ForEach-Object { "<th scope=`"col`"><button type=`"button`">$(Get-Html $_[1])</button></th>" }) -join ''
$bodyHtml = ($rows | ForEach-Object {
        $row = $_
        $cells = foreach ($field in $fields) {
            $value = $row.($field[0])
            if ($field[0] -eq 'retirementDate') { $value = Get-Day $value }
            if ($field[0] -eq 'powerState') { $value = ([string]$value) -replace '^PowerState/', '' }
            if ($null -eq $value -or "$value" -eq '') { $value = '-' }
            "<td>$(Get-Html $value)</td>"
        }
        "<tr>$($cells -join '')</tr>"
    }) -join "`n"

$groups = @($rows | Group-Object { ($_.nextStep -split '[:;]')[0].TrimEnd('.') } | Sort-Object Count -Descending)
$barHeight = 28
$chartHeight = [Math]::Max(1, $groups.Count) * ($barHeight + 10) + 10
$maxCount = [Math]::Max(1, ($groups | Measure-Object -Property Count -Maximum).Maximum)
$bars = for ($i = 0; $i -lt $groups.Count; $i++) {
    $y = 10 + $i * ($barHeight + 10)
    $width = [Math]::Round(300 * $groups[$i].Count / $maxCount)
    $label = $groups[$i].Name
    if ($label.Length -gt 80) { $label = $label.Substring(0, 77) + '...' }
    "<text x=`"0`" y=`"$($y + 19)`" class=`"bar-label`">$(Get-Html $label)</text>" +
    "<rect x=`"620`" y=`"$y`" width=`"$width`" height=`"$barHeight`" rx=`"4`" fill=`"#0f6cbd`"/>" +
    "<text x=`"$(628 + $width)`" y=`"$($y + 19)`" class=`"bar-label`">$($groups[$i].Count)</text>"
}
$chartDescription = ($groups | ForEach-Object { "$($_.Name): $($_.Count)" }) -join '; '

$html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>VM lifecycle transition board</title>
<style>
  body { font-family: "Segoe UI", Helvetica, Arial, sans-serif; margin: 32px; color: #1b1b1b; }
  h1 { font-size: 26px; margin-bottom: 4px; }
  .meta { color: #424242; margin-top: 0; }
  .tiles { display: flex; flex-wrap: wrap; gap: 12px; margin: 24px 0; }
  .tile { border: 1px solid #c7d3e6; border-radius: 8px; padding: 12px 16px; min-width: 150px; background: #f7f9fc; }
  .tile .value { display: block; font-size: 28px; font-weight: 700; color: #0f6cbd; }
  .tile .label { font-size: 13px; color: #424242; }
  table { border-collapse: collapse; width: 100%; font-size: 13px; }
  caption { text-align: left; font-weight: 700; font-size: 16px; margin-bottom: 8px; }
  th, td { border-bottom: 1px solid #e0e0e0; padding: 6px 8px; text-align: left; vertical-align: top; }
  th button { font: inherit; font-weight: 700; background: none; border: none; padding: 0; cursor: pointer; color: #1b1b1b; }
  th button:focus { outline: 2px solid #0f6cbd; }
  .bar-label { font-size: 13px; fill: #1b1b1b; }
  .note { color: #616161; font-size: 12px; max-width: 900px; }
</style>
</head>
<body>
<h1>VM lifecycle transition board</h1>
<p class="meta">Generated $generated from Log Analytics workspace $(Get-Html $WorkspaceName). Read-only data from Azure Resource Graph and VM insights.</p>
<div class="tiles">
$tileHtml
</div>
<table id="board">
<caption>Resources on End of Life VM series, with the next step for each. Select a column heading to sort.</caption>
<thead><tr>$headerHtml</tr></thead>
<tbody>
$bodyHtml
</tbody>
</table>
<h2>Resources by next step</h2>
<svg role="img" aria-labelledby="chart-title chart-desc" width="980" height="$chartHeight" viewBox="0 0 980 $chartHeight">
<title id="chart-title">Resources by next step</title>
<desc id="chart-desc">$(Get-Html $chartDescription)</desc>
$($bars -join "`n")
</svg>
<p class="note">Next steps are deterministic first actions from tags and configuration, not dispositions. Confirm them with the owner and the agent's disposition records. Quota authorizes consumption; it doesn't reserve capacity.</p>
<script>
  document.querySelectorAll('#board th button').forEach(function (button, index) {
    button.addEventListener('click', function () {
      var body = document.querySelector('#board tbody');
      var ascending = button.dataset.order !== 'asc';
      var rows = Array.prototype.slice.call(body.rows);
      rows.sort(function (a, b) {
        var x = a.cells[index].textContent, y = b.cells[index].textContent;
        var nx = parseFloat(x), ny = parseFloat(y);
        var compare = (!isNaN(nx) && !isNaN(ny)) ? nx - ny : x.localeCompare(y);
        return ascending ? compare : -compare;
      });
      rows.forEach(function (row) { body.appendChild(row); });
      button.dataset.order = ascending ? 'asc' : 'desc';
    });
  });
</script>
</body>
</html>
"@

$folder = Split-Path -Parent $OutFile
if ($folder) { New-Item -ItemType Directory -Force -Path $folder | Out-Null }
[IO.File]::WriteAllText($OutFile, $html, [Text.UTF8Encoding]::new($false))
Write-Host "$($rows.Count) resources. Board written to $OutFile"
