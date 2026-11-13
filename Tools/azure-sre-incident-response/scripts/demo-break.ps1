#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')][string]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_-][a-zA-Z0-9_.()-]{0,89}$')][string]$ResourceGroup,
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]{0,30}[a-z0-9]$')][string]$AppName
)
. "$PSScriptRoot\common.ps1"

$target = "$SubscriptionId/$ResourceGroup/$AppName"
if (-not $PSCmdlet.ShouldProcess($target, 'Capture baseline and inject a crash-looping revision with 100% traffic')) { return }
$app = Get-DemoApp $SubscriptionId $ResourceGroup $AppName
$stateDirectory = Join-Path $PSScriptRoot '.state'
# Do not layer incidents: even a failed injection may need its original traffic restored.
if (Test-Path -LiteralPath $stateDirectory) {
    foreach ($existing in Get-ChildItem -LiteralPath $stateDirectory -Filter '*.json') {
        $prior = Get-Content -LiteralPath $existing.FullName -Raw | ConvertFrom-Json
        if ($prior.SubscriptionId -ieq $SubscriptionId -and $prior.ResourceGroup -ieq $ResourceGroup -and
            $prior.AppName -ieq $AppName -and -not $prior.Recovered) {
            throw "Unrecovered state already exists: $($existing.FullName). Run demo-fix first."
        }
    }
}
if (@($app.properties.template.containers).Count -ne 1) { throw 'Only single-container demo applications are supported.' }
$traffic = @(Get-DemoTraffic $app)
$revisions = @(Invoke-DemoAz @('containerapp', 'revision', 'list', '-g', $ResourceGroup, '-n', $AppName, '--all') $SubscriptionId)
Assert-DemoBaseline $traffic $revisions
Assert-DemoHttp $app.properties.configuration.ingress.fqdn

[void](New-Item -ItemType Directory -Path $stateDirectory -Force)
$runId = [guid]::NewGuid().ToString('N')
# Azure limits app name + "--" + revision suffix to 54 characters.
$suffix = "fault-$($runId.Substring(0, 12))"
$injected = "$AppName--$suffix"
if ($injected.Length -gt 54) { throw "Revision name '$injected' exceeds the 54-character Container Apps limit." }
$statePath = Join-Path $stateDirectory "$runId.json"
$state = [ordered]@{
    SchemaVersion = 1; SubscriptionId = $SubscriptionId; ResourceGroup = $ResourceGroup
    AppName = $AppName; ResourceId = $app.id; CreatedUtc = [datetime]::UtcNow.ToString('o')
    InjectedRevision = $injected; BaselineTraffic = $traffic; Recovered = $false
}
$state | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $statePath -Encoding utf8 -NoNewline
Write-Host "Recovery state: $statePath"
$yamlPath = Join-Path $stateDirectory "$runId.yaml"
try {
    $app.properties.template.revisionSuffix = $suffix
    $container = $app.properties.template.containers[0]
    $container | Add-Member -NotePropertyName command -NotePropertyValue @('node') -Force
    $container | Add-Member -NotePropertyName args -NotePropertyValue @('-e', 'console.log("Synthetic demo fault"); setTimeout(() => process.exit(1), 20000)') -Force
    # JSON is valid YAML. Do not round-trip configuration secrets returned by "show".
    @{ properties = @{ template = $app.properties.template } } |
        ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $yamlPath -Encoding utf8
    # Freeze "latest" rules before creating a new latest revision.
    $weights = @($traffic | ForEach-Object { "$($_.revisionName)=$($_.weight)" })
    $null = Invoke-DemoAz (@('containerapp', 'ingress', 'traffic', 'set', '-g', $ResourceGroup, '-n', $AppName, '--revision-weight') + $weights) $SubscriptionId
    $null = Invoke-DemoAz @('containerapp', 'update', '-g', $ResourceGroup, '-n', $AppName, '--yaml', $yamlPath, '--no-wait') $SubscriptionId
    $found = $false
    for ($attempt = 1; $attempt -le 24; $attempt++) {
        $created = @(Invoke-DemoAz @('containerapp', 'revision', 'list', '-g', $ResourceGroup, '-n', $AppName, '--all') $SubscriptionId)
        $revision = @($created | Where-Object { $_.name -ceq $injected })
        if ($revision.Count -eq 1) {
            if ($revision[0].properties.PSObject.Properties['provisioningState'] -and
                $revision[0].properties.provisioningState -in @('Failed', 'Canceled', 'Cancelled')) {
                throw "Injected revision provisioning failed. Recover using $statePath."
            }
            $found = $true
            break
        }
        $pending = Get-DemoApp $SubscriptionId $ResourceGroup $AppName
        if ($pending.properties.PSObject.Properties['provisioningState'] -and
            $pending.properties.provisioningState -in @('Failed', 'Canceled', 'Cancelled')) {
            throw "Container App provisioning failed before the injected revision appeared. Recover using $statePath."
        }
        if ($attempt -lt 24) { Start-Sleep -Seconds 5 }
    }
    if (-not $found) { throw "Timed out after 24 revision checks (5-second intervals). Injection may still be pending; retain $statePath, inspect provisioning and retry recovery when settled." }
    $null = Invoke-DemoAz @('containerapp', 'ingress', 'traffic', 'set', '-g', $ResourceGroup, '-n', $AppName, '--revision-weight', "$injected=100") $SubscriptionId
    Assert-DemoTraffic @([pscustomobject]@{ revisionName = $injected; weight = 100 }) (Get-DemoApp $SubscriptionId $ResourceGroup $AppName)
    Write-Host "Fault traffic verified. Alert delivery and agent investigation require separate onboarding. Recover with demo-fix.ps1 -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -AppName $AppName -StatePath `"$statePath`"."
} finally {
    if (Test-Path -LiteralPath $yamlPath) { Remove-Item -LiteralPath $yamlPath -Force }
}
