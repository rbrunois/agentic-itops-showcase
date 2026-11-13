Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-DemoAz {
    param([string[]]$Arguments, [string]$SubscriptionId)
    $output = & az @Arguments --subscription $SubscriptionId --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed (exit $LASTEXITCODE): $($Arguments[0..([Math]::Min(2, $Arguments.Count - 1))] -join ' '). Stop and inspect Azure; recovery state, if present, is retained."
    }
    if ($output) { ($output -join "`n") | ConvertFrom-Json -Depth 100 }
}

function Get-DemoApp {
    param([string]$SubscriptionId, [string]$ResourceGroup, [string]$AppName)
    $app = Invoke-DemoAz @('containerapp', 'show', '-g', $ResourceGroup, '-n', $AppName) $SubscriptionId
    $expected = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.App/containerApps/$AppName"
    if (-not $app -or $app.id -ine $expected) { throw 'Returned Container App does not match the explicit target.' }
    $tag = $app.tags.PSObject.Properties['sre-demo']
    if (-not $tag -or $tag.Value -cne 'true') { throw 'Target must have the exact demo tag sre-demo=true.' }
    if ($app.properties.configuration.activeRevisionsMode -ne 'Multiple' -or
        -not $app.properties.configuration.ingress.external -or
        -not $app.properties.configuration.ingress.fqdn) {
        throw 'Target must use Multiple revisions and external HTTPS ingress.'
    }
    $app
}

function Get-DemoTraffic {
    param($App)
    $weights = @{}
    foreach ($rule in $App.properties.configuration.ingress.traffic) {
        if ($rule.PSObject.Properties['label'] -and $rule.label) { throw 'Labeled traffic is not supported by this bounded demo.' }
        $name = if ($rule.PSObject.Properties['latestRevision'] -and $rule.latestRevision) {
            $App.properties.latestRevisionName
        } else { $rule.revisionName }
        if (-not $name -or [int]$rule.weight -lt 0 -or [int]$rule.weight -gt 100) { throw 'Invalid traffic allocation.' }
        if (-not $weights.ContainsKey($name)) { $weights[$name] = 0 }
        $weights[$name] += [int]$rule.weight
    }
    if (($weights.Values | Measure-Object -Sum).Sum -ne 100) { throw 'Traffic must total 100 percent.' }
    foreach ($name in ($weights.Keys | Sort-Object)) {
        [pscustomobject]@{ revisionName = $name; weight = $weights[$name] }
    }
}

function Assert-DemoHttp {
    param([string]$Fqdn, [int]$Attempts = 6)
    if ($Fqdn -notmatch '^[a-zA-Z0-9.-]+$') { throw 'Invalid endpoint hostname.' }
    foreach ($path in @('/', '/healthz', '/readyz')) {
        $ok = $false
        for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
            try {
                $response = Invoke-WebRequest -Uri "https://$Fqdn$path" -TimeoutSec 15 -MaximumRedirection 0 -SkipHttpErrorCheck
                $ok = $response.StatusCode -eq 200
            } catch [System.Net.Http.HttpRequestException], [System.Net.WebException], [System.Threading.Tasks.TaskCanceledException] {
                $ok = $false
            }
            if ($ok) { break }
            if ($attempt -lt $Attempts) { Start-Sleep -Seconds 5 }
        }
        if (-not $ok) { throw "HTTP verification failed for https://$Fqdn$path. State is retained; inspect and retry recovery." }
        if ($path -ne '/') {
            try {
                $body = ConvertFrom-Json -InputObject $response.Content -AsHashtable -NoEnumerate -Depth 20
            } catch [System.ArgumentException] {
                throw "Malformed JSON from https://$Fqdn$path. State is retained; inspect the response and retry recovery."
            }
            $valid = $body -is [System.Collections.IDictionary]
            if ($valid -and $path -eq '/healthz') {
                $valid = $body.Contains('status') -and $body['status'] -is [string] -and $body['status'] -ceq 'ok' -and
                    $body.Contains('version') -and $body['version'] -is [string] -and $body['version'] -ceq '1.2.0'
            } elseif ($valid -and $path -eq '/readyz') {
                $valid = $body.Contains('ready') -and $body['ready'] -is [bool] -and $body['ready']
            }
            if (-not $valid) {
                throw "Unexpected JSON contract from https://$Fqdn$path; expected health status ok/version 1.2.0 or readiness boolean true. State is retained; inspect and retry recovery."
            }
        }
    }
}

function Assert-DemoBaseline {
    param($Traffic, $Revisions)
    foreach ($rule in @($Traffic | Where-Object { $_.weight -gt 0 })) {
        $matches = @($Revisions | Where-Object { $_.name -ceq $rule.revisionName })
        if ($matches.Count -ne 1) { throw "Baseline revision missing: $($rule.revisionName)." }
        $revision = $matches[0]
        if (-not $revision.properties.active -or $revision.properties.runningState -ne 'Running' -or
            $revision.properties.healthState -ne 'Healthy') {
            throw "Baseline revision is not active, Running and Healthy: $($revision.name). No automatic activation or guessed rollback."
        }
        Assert-DemoHttp $revision.properties.fqdn
    }
}

function Assert-DemoTraffic {
    param($Expected, $App)
    $actual = @(Get-DemoTraffic $App | Where-Object { $_.weight -gt 0 })
    $wanted = @($Expected | Where-Object { $_.weight -gt 0 })
    if ($actual.Count -ne $wanted.Count) { throw 'Traffic verification failed; recovery state is retained.' }
    foreach ($rule in $wanted) {
        if (-not ($actual | Where-Object { $_.revisionName -ceq $rule.revisionName -and $_.weight -eq $rule.weight })) {
            throw 'Traffic verification failed; recovery state is retained.'
        }
    }
}
