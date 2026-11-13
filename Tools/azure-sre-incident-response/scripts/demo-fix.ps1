#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')][string]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_-][a-zA-Z0-9_.()-]{0,89}$')][string]$ResourceGroup,
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]{0,30}[a-z0-9]$')][string]$AppName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$StatePath
)
. "$PSScriptRoot\common.ps1"

if (-not $PSCmdlet.ShouldProcess("$SubscriptionId/$ResourceGroup/$AppName", 'Restore captured traffic, verify health/HTTP, then retire only the recorded injected revision')) { return }
$state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json -Depth 100
$expectedId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.App/containerApps/$AppName"
if ($state.SchemaVersion -ne 1 -or $state.SubscriptionId -ine $SubscriptionId -or
    $state.ResourceGroup -ine $ResourceGroup -or $state.AppName -ine $AppName -or $state.ResourceId -ine $expectedId) {
    throw 'Recovery state does not match the explicit subscription/resource group/application.'
}
if ($state.Recovered) { Write-Host 'This recovery record is already complete; no changes made.'; return }
if ($state.InjectedRevision -cnotmatch "^$([regex]::Escape($AppName))--fault-[a-f0-9]{12}$") { throw 'Invalid injected revision in recovery state.' }
$traffic = @($state.BaselineTraffic)
if ($traffic.Count -eq 0 -or ($traffic | Measure-Object -Property weight -Sum).Sum -ne 100) { throw 'Invalid baseline traffic in recovery state.' }
$names = @{}
foreach ($rule in $traffic) {
    if ($rule.revisionName -cnotmatch "^$([regex]::Escape($AppName))--[a-z0-9-]+$" -or
        $rule.revisionName -ceq $state.InjectedRevision -or $rule.weight -lt 0 -or $rule.weight -gt 100 -or
        [int]$rule.weight -ne $rule.weight -or $names.ContainsKey($rule.revisionName)) {
        throw 'Invalid or duplicate baseline revision/weight in recovery state.'
    }
    $names[$rule.revisionName] = $true
}
$app = Get-DemoApp $SubscriptionId $ResourceGroup $AppName
# Refuse to overwrite a subsequent operator deployment or a different incident.
foreach ($rule in @(Get-DemoTraffic $app | Where-Object { $_.weight -gt 0 })) {
    if ($rule.revisionName -cne $state.InjectedRevision -and -not $names.ContainsKey($rule.revisionName)) {
        throw 'Current traffic includes an unrelated revision. Review manually; state is retained.'
    }
}
$revisions = @(Invoke-DemoAz @('containerapp', 'revision', 'list', '-g', $ResourceGroup, '-n', $AppName, '--all') $SubscriptionId)
if (-not ($revisions | Where-Object { $_.name -ceq $state.InjectedRevision }) -and
    (-not $app.properties.PSObject.Properties['provisioningState'] -or
        $app.properties.provisioningState -notin @('Succeeded', 'Failed', 'Canceled', 'Cancelled'))) {
    throw 'Injected revision is absent and provisioning has not settled. It may still appear; retain state, inspect provisioning and retry recovery.'
}
Assert-DemoBaseline $traffic $revisions
$weights = @($traffic | ForEach-Object { "$($_.revisionName)=$($_.weight)" })
$null = Invoke-DemoAz (@('containerapp', 'ingress', 'traffic', 'set', '-g', $ResourceGroup, '-n', $AppName, '--revision-weight') + $weights) $SubscriptionId
$restored = Get-DemoApp $SubscriptionId $ResourceGroup $AppName
Assert-DemoTraffic $traffic $restored
Assert-DemoHttp $restored.properties.configuration.ingress.fqdn
$revisions = @(Invoke-DemoAz @('containerapp', 'revision', 'list', '-g', $ResourceGroup, '-n', $AppName, '--all') $SubscriptionId)
Assert-DemoBaseline $traffic $revisions
$injected = @($revisions | Where-Object { $_.name -ceq $state.InjectedRevision -and $_.properties.active })
if ($injected.Count -gt 0) {
    $null = Invoke-DemoAz @('containerapp', 'revision', 'deactivate', '-g', $ResourceGroup, '-n', $AppName, '--revision', $state.InjectedRevision) $SubscriptionId
    $after = @(Invoke-DemoAz @('containerapp', 'revision', 'list', '-g', $ResourceGroup, '-n', $AppName, '--all') $SubscriptionId)
    if ($after | Where-Object { $_.name -ceq $state.InjectedRevision -and $_.properties.active }) {
        throw 'Injected revision is still active; state is retained. Inspect and retry recovery.'
    }
}
$state.Recovered = $true
$state | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $StatePath -Encoding utf8 -NoNewline
Write-Host 'Captured baseline traffic and HTTP health verified; only the recorded injected revision was retired. Verify alert resolution separately.'
