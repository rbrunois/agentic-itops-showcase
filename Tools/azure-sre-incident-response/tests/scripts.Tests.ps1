#requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Standalone offline harness: every native Azure call and HTTP request is intercepted.
$root = Join-Path $PSScriptRoot ".runs\$([guid]::NewGuid().ToString('N'))"
$scripts = Join-Path $root 'scripts'
[void](New-Item -ItemType Directory -Path $scripts -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $root 'infra') -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $root 'app') -Force)
foreach ($name in @('Dockerfile', '.dockerignore', '.npmrc', 'package.json', 'package-lock.json', 'server.js', '.env')) {
    Set-Content -LiteralPath (Join-Path $root "app\$name") -Value 'synthetic build fixture'
}
Copy-Item -Path "$PSScriptRoot\..\scripts\*.ps1" -Destination $scripts
Set-Content -LiteralPath (Join-Path $root 'infra\containerapp.bicep') -Value '// Mock: never deployed'
$scope = @{ SubscriptionId = '00000000-0000-0000-0000-000000000001'; ResourceGroup = 'demo-rg'; AppName = 'demo-app'; Confirm = $false }
$breakScript = Join-Path $scripts 'demo-break.ps1'
$fixScript = Join-Path $scripts 'demo-fix.ps1'
$provisionScript = Join-Path $scripts 'provision.ps1'
$passed = 0

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}
function Assert-Throws([scriptblock]$Action, [string]$Match) {
    $caught = $false
    try { & $Action } catch {
        $caught = $true
        if ($_.Exception.Message -notmatch $Match) { throw "Unexpected error: $($_.Exception.Message); expected $Match" }
    }
    Assert $caught "Expected failure matching $Match"
}
function Reset-Mock {
    if (Test-Path "$scripts\.state") { Remove-Item "$scripts\.state" -Recurse -Force }
    $app = @'
{
  "id": "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/demo-rg/providers/Microsoft.App/containerApps/demo-app",
  "tags": {"sre-demo": "true"},
  "properties": {
    "provisioningState": "Succeeded",
    "latestRevisionName": "demo-app--green",
    "configuration": {
      "activeRevisionsMode": "Multiple",
      "ingress": {"external": true, "fqdn": "demo.example.test", "traffic": [
        {"revisionName":"demo-app--blue","weight":70},
        {"latestRevision":true,"weight":30}
      ]}
    },
    "template": {"revisionSuffix":"green","containers":[{"name":"app","image":"example.test/node:v1","probes":[{"type":"Readiness","httpGet":{"path":"/readyz","port":8080}},{"type":"Liveness","httpGet":{"path":"/healthz","port":8080}}]}]}
  }
}
'@ | ConvertFrom-Json -Depth 100
    $revisions = [System.Collections.Generic.List[object]]::new()
    foreach ($name in @('blue', 'green', 'unrelated')) {
        $revisions.Add([pscustomobject]@{
            name = "demo-app--$name"
            properties = [pscustomobject]@{ active = $true; runningState = 'Running'; healthState = 'Healthy'; fqdn = "$name.example.test" }
        })
    }
    $global:DemoMock = @{
        App = $app; Revisions = $revisions; Calls = [System.Collections.Generic.List[object]]::new()
        Fail = ''; FailHttp = $false; GroupExists = $false; IgnoreTraffic = $false; HttpCalls = 0
        RevisionDelay = 0; PendingRevision = $null; Polls = 0; PollFailure = $false
        InjectedProvisioning = 'Provisioned'; SubmittedTemplate = $null; HttpFailuresRemaining = 0
        AppProvisioningFailure = $false
        HttpBodyOverrides = @{}; HttpExceptionsRemaining = 0
        BuildStatus = 'Succeeded'; BuildFiles = @(); BuildContext = ''
        DeploymentParameters = $null; DeploymentParametersFile = ''
    }
}
function global:az {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:LASTEXITCODE = 0
    $global:DemoMock.Calls.Add($Arguments)
    $text = $Arguments -join ' '
    if ($Arguments -contains 'account') { throw 'Global Azure account mutation is forbidden.' }
    $index = [array]::IndexOf($Arguments, '--subscription')
    if ($index -lt 0 -or $Arguments[$index + 1] -ne '00000000-0000-0000-0000-000000000001') { throw 'Missing explicit subscription scope.' }
    if ($global:DemoMock.Fail -and $text.StartsWith($global:DemoMock.Fail)) { $global:LASTEXITCODE = 19; return }
    if ($text.StartsWith('containerapp show ')) { return $global:DemoMock.App | ConvertTo-Json -Depth 100 }
    if ($text.StartsWith('containerapp revision list ')) {
        if ($global:DemoMock.PendingRevision) {
            $global:DemoMock.Polls++
            if ($global:DemoMock.PollFailure) { $global:LASTEXITCODE = 19; return }
            if ($global:DemoMock.Polls -gt $global:DemoMock.RevisionDelay) {
                $global:DemoMock.Revisions.Add($global:DemoMock.PendingRevision)
                $global:DemoMock.PendingRevision = $null
                $global:DemoMock.App.properties.provisioningState = 'Succeeded'
            }
        }
        return ConvertTo-Json -InputObject @($global:DemoMock.Revisions.ToArray()) -Depth 100
    }
    if ($text.StartsWith('containerapp update ')) {
        if ($Arguments -notcontains '--no-wait') { throw 'Fault submission must use --no-wait.' }
        $yaml = $Arguments[[array]::IndexOf($Arguments, '--yaml') + 1]
        $change = Get-Content -LiteralPath $yaml -Raw | ConvertFrom-Json -Depth 100
        $suffix = $change.properties.template.revisionSuffix
        # Azure: app name + "--" + suffix <= 54; app names may be up to 32 characters.
        Assert ($suffix -cmatch '^[a-z][a-z0-9-]*[a-z0-9]$' -and $suffix.Length -le 20) "Revision suffix '$suffix' can exceed the Container Apps name limit"
        $name = "demo-app--$suffix"
        $global:DemoMock.App.properties.latestRevisionName = $name
        $global:DemoMock.SubmittedTemplate = $change.properties.template
        $global:DemoMock.App.properties.provisioningState = 'InProgress'
        if ($global:DemoMock.AppProvisioningFailure) { $global:DemoMock.App.properties.provisioningState = 'Failed' }
        $global:DemoMock.PendingRevision = [pscustomobject]@{
            name = $name
            properties = [pscustomobject]@{ active = $true; runningState = 'Failed'; healthState = 'Unhealthy'; fqdn = 'fault.example.test'; provisioningState = $global:DemoMock.InjectedProvisioning }
        }
        return '{}'
    }
    if ($text.StartsWith('containerapp ingress traffic set ')) {
        if ($global:DemoMock.IgnoreTraffic) { return '{}' }
        $index = [array]::IndexOf($Arguments, '--revision-weight') + 1
        $traffic = @()
        while ($index -lt $Arguments.Count -and -not $Arguments[$index].StartsWith('--')) {
            $name, $weight = $Arguments[$index] -split '='
            $traffic += [pscustomobject]@{ revisionName = $name; weight = [int]$weight }
            $index++
        }
        $global:DemoMock.App.properties.configuration.ingress.traffic = $traffic
        return '{}'
    }
    if ($text.StartsWith('containerapp revision deactivate ')) {
        $name = $Arguments[[array]::IndexOf($Arguments, '--revision') + 1]
        ($global:DemoMock.Revisions | Where-Object name -EQ $name).properties.active = $false
        return '{}'
    }
    if ($text.StartsWith('group exists ')) { return ($global:DemoMock.GroupExists | ConvertTo-Json) }
    if ($text.StartsWith('group create ')) { return '{}' }
    if ($text.StartsWith('acr create ')) { return '{"id":"/mock/registry","loginServer":"demotestregistry.azurecr.io"}' }
    if ($text.StartsWith('identity create ')) { return '{"principalId":"mock-principal"}' }
    if ($text.StartsWith('role assignment create ')) { return '{}' }
    if ($text.StartsWith('acr build ')) {
        $path = $Arguments[[array]::IndexOf($Arguments, '--no-logs') + 1]
        $dockerfile = $Arguments[[array]::IndexOf($Arguments, '--file') + 1]
        Assert ([System.IO.Path]::IsPathRooted($dockerfile) -and (Test-Path -LiteralPath $dockerfile)) 'ACR resolves --file from the working directory; require an existing absolute path'
        $global:DemoMock.BuildContext = $path
        $global:DemoMock.BuildFiles = @(Get-ChildItem -LiteralPath $path -Force | Select-Object -ExpandProperty Name)
        return @{ status = $global:DemoMock.BuildStatus } | ConvertTo-Json
    }
    if ($text.StartsWith('acr repository show ')) { return @{ digest = "sha256:$('a' * 64)" } | ConvertTo-Json }
    if ($text.StartsWith('monitor log-analytics workspace create ')) { return '{"id":"/mock/workspace","customerId":"mock-customer"}' }
    if ($text.StartsWith('monitor app-insights component create ')) { return '{"connectionString":"synthetic-test-value"}' }
    if ($text.StartsWith('monitor log-analytics workspace get-shared-keys ')) { return '{"primarySharedKey":"synthetic-test-key"}' }
    if ($text.StartsWith('containerapp env create ')) { return '{}' }
    if ($text.StartsWith('deployment group create ')) {
        $file = @($Arguments | Where-Object { $_ -like '@*' })
        Assert ($file.Count -eq 1) 'Deployment must pass exactly one parameters file'
        $global:DemoMock.DeploymentParametersFile = $file[0].Substring(1)
        $global:DemoMock.DeploymentParameters = (Get-Content -LiteralPath $global:DemoMock.DeploymentParametersFile -Raw | ConvertFrom-Json -Depth 10).parameters
        return '{}'
    }
    if ($text.StartsWith('monitor action-group create ')) { return '{"id":"/mock/action-group"}' }
    if ($text.StartsWith('monitor metrics alert create ')) { return '{}' }
    throw "Unmocked az command: $text"
}
function global:Invoke-WebRequest {
    param($Uri, $TimeoutSec, $MaximumRedirection, [switch]$SkipHttpErrorCheck)
    $global:DemoMock.HttpCalls++
    if ($global:DemoMock.HttpExceptionsRemaining -gt 0) {
        $global:DemoMock.HttpExceptionsRemaining--
        throw [System.Net.Http.HttpRequestException]::new('Synthetic transient connection failure')
    }
    if ($global:DemoMock.HttpFailuresRemaining -gt 0) {
        $global:DemoMock.HttpFailuresRemaining--
        return [pscustomobject]@{ StatusCode = 503 }
    }
    $path = ([uri]$Uri).AbsolutePath
    $content = switch ($path) {
        '/healthz' { '{"status":"ok","version":"1.2.0"}' }
        '/readyz' { '{"ready":true}' }
        default { 'Synthetic sample greeting v1.2.0' }
    }
    if ($Uri -like 'https://demo.example.test/*' -and $global:DemoMock.HttpBodyOverrides.ContainsKey($path)) {
        $content = $global:DemoMock.HttpBodyOverrides[$path]
    }
    [pscustomobject]@{
        StatusCode = $(if ($global:DemoMock.FailHttp -and $Uri -like 'https://demo.example.test/*') { 503 } else { 200 })
        Content = $content
    }
}
function global:Start-Sleep { param($Seconds) }
function Get-State {
    $files = @(Get-ChildItem -LiteralPath "$scripts\.state" -Filter '*.json')
    Assert ($files.Count -eq 1) 'Exactly one state record expected'
    $files[0].FullName
}
function Get-Mutations {
    @($global:DemoMock.Calls | Where-Object { ($_ -join ' ') -match '^(containerapp (update|ingress traffic set|revision deactivate)|group create)' })
}
function Test-Case([string]$Name, [scriptblock]$Body) {
    Reset-Mock
    & $Body
    $script:passed++
    Write-Host "PASS $Name"
}

try {
    foreach ($file in @((Get-ChildItem -Path $scripts -Filter '*.ps1')) + @(Get-Item -LiteralPath $PSCommandPath)) {
        $tokens = $null; $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        Assert ($errors.Count -eq 0) "Parser: $($file.Name)"
    }
    Test-Case 'WhatIf performs no Azure, HTTP or state operations' {
        & $breakScript @scope -WhatIf
        & $fixScript @scope -StatePath 'missing.json' -WhatIf
        & $provisionScript @scope -Location canadacentral -Image example.test/node:v1 -AllowPublicIngress -WhatIf
        Assert ($global:DemoMock.Calls.Count -eq 0) 'WhatIf invoked Azure'
        Assert ($global:DemoMock.HttpCalls -eq 0) 'WhatIf invoked HTTP'
        Assert (-not (Test-Path "$scripts\.state")) 'WhatIf created state'
    }
    Test-Case 'Parameter validation rejects malformed scope' {
        $bad = $scope.Clone(); $bad.SubscriptionId = 'not-a-subscription'
        Assert-Throws { & $breakScript @bad } 'validate'
        Assert ($global:DemoMock.Calls.Count -eq 0) 'Bad parameter reached Azure'
    }
    Test-Case 'Missing demo tag rejects target without mutation' {
        $global:DemoMock.App.tags = [pscustomobject]@{}
        Assert-Throws { & $breakScript @scope } 'demo tag'
        Assert (@(Get-Mutations).Count -eq 0) 'Untagged mutation'
    }
    Test-Case 'Wrong resource ID rejects target' {
        $global:DemoMock.App.id = '/wrong'
        Assert-Throws { & $breakScript @scope } 'explicit target'
        Assert (@(Get-Mutations).Count -eq 0) 'Wrong target mutation'
    }
    Test-Case 'Running alone is not a healthy baseline' {
        $global:DemoMock.Revisions[0].properties.healthState = 'Unhealthy'
        Assert-Throws { & $breakScript @scope } 'not active, Running and Healthy'
        Assert (@(Get-Mutations).Count -eq 0) 'Unhealthy baseline mutation'
    }
    Test-Case 'Endpoint must be healthy before injection' {
        $global:DemoMock.FailHttp = $true
        Assert-Throws { & $breakScript @scope } 'HTTP verification failed'
        Assert (@(Get-Mutations).Count -eq 0) 'HTTP failure mutation'
    }
    Test-Case 'Wrong 200 response body prevents injection' {
        $global:DemoMock.HttpBodyOverrides['/healthz'] = '{"status":"ok","version":"0.0.0"}'
        Assert-Throws { & $breakScript @scope } 'Unexpected JSON contract'
        Assert (@(Get-Mutations).Count -eq 0) 'Wrong application version was injected'
    }
    Test-Case 'Native read failure stops immediately' {
        $global:DemoMock.Fail = 'containerapp show '
        Assert-Throws { & $breakScript @scope } 'exit 19'
        Assert ($global:DemoMock.Calls.Count -eq 1) 'Continued after native failure'
    }
    Test-Case 'Labeled traffic is rejected before mutation' {
        $global:DemoMock.App.properties.configuration.ingress.traffic[0] | Add-Member label production
        Assert-Throws { & $breakScript @scope } 'Labeled traffic'
        Assert (@(Get-Mutations).Count -eq 0) 'Labeled baseline mutated'
    }
    Test-Case 'Traffic snapshot, latest resolution, scoped recovery and unique runs' {
        & $breakScript @scope
        $path = Get-State
        $state = Get-Content $path -Raw | ConvertFrom-Json
        Assert ($state.BaselineTraffic.Count -eq 2) 'Split baseline lost'
        Assert ($state.BaselineTraffic[1].revisionName -eq 'demo-app--green') 'Latest rule was not resolved'
        Assert ($state.SubscriptionId -eq $scope.SubscriptionId) 'State scope lost'
        Assert (@(Get-ChildItem "$scripts\.state" -Filter '*.yaml').Count -eq 0) 'Transient YAML leaked'
        $count = @(Get-Mutations).Count
        Assert-Throws { & $breakScript @scope } 'Unrecovered state|not active, Running and Healthy'
        Assert (@(Get-Mutations).Count -eq $count) 'Second injection mutated'
        & $fixScript @scope -StatePath $path
        Assert ((Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Recovery not recorded'
        Assert (($global:DemoMock.Revisions | Where-Object name -EQ 'demo-app--unrelated').properties.active) 'Unrelated revision retired'
        Assert (-not ($global:DemoMock.Revisions | Where-Object name -EQ $state.InjectedRevision).properties.active) 'Injected revision still active'
        Assert ($global:DemoMock.App.properties.configuration.ingress.traffic[0].weight -eq 70) 'Split not restored'
        $count = @(Get-Mutations).Count
        & $fixScript @scope -StatePath $path
        Assert (@(Get-Mutations).Count -eq $count) 'Completed recovery mutated'
        & $breakScript @scope
        Assert (@(Get-ChildItem "$scripts\.state" -Filter '*.json').Count -eq 2) 'Run states collided'
    }
    Test-Case 'Failed injection retains recoverable state and cleans YAML' {
        $global:DemoMock.Fail = 'containerapp update '
        Assert-Throws { & $breakScript @scope } 'exit 19'
        $path = Get-State
        Assert (@(Get-ChildItem "$scripts\.state" -Filter '*.yaml').Count -eq 0) 'YAML leaked on failure'
        Assert (@(Get-Mutations).Count -eq 2) 'Expected only baseline freeze then failed update'
        $global:DemoMock.Fail = ''
        & $fixScript @scope -StatePath $path
        Assert ((Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Failed injection could not recover'
    }
    Test-Case 'Async injection polls delayed revision and preserves probes' {
        $global:DemoMock.RevisionDelay = 2
        & $breakScript @scope
        Assert ($global:DemoMock.Polls -eq 3) 'Delayed revision was not polled'
        Assert ($global:DemoMock.SubmittedTemplate.containers[0].probes.Count -eq 2) 'Original probes were removed'
        Assert ($global:DemoMock.SubmittedTemplate.containers[0].probes[0].httpGet.path -eq '/readyz') 'Readiness probe changed'
    }
    Test-Case 'Async injection timeout retains state and does not shift fault traffic' {
        $global:DemoMock.RevisionDelay = 100
        Assert-Throws { & $breakScript @scope } 'Timed out after 24 revision checks'
        $path = Get-State
        Assert ($global:DemoMock.Polls -eq 24) 'Revision polling was not bounded'
        Assert (@(Get-Mutations).Count -eq 2) 'Fault traffic changed before revision existed'
        Assert (@(Get-ChildItem "$scripts\.state" -Filter '*.yaml').Count -eq 0) 'YAML leaked on polling timeout'
        Assert-Throws { & $fixScript @scope -StatePath $path } 'provisioning has not settled'
        Assert (-not (Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Pending injection marked recovered'
        $global:DemoMock.RevisionDelay = 0
        & $fixScript @scope -StatePath $path
        Assert ((Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Settled injection could not recover'
    }
    Test-Case 'Async polling native failure is not hidden or retried' {
        $global:DemoMock.PollFailure = $true
        Assert-Throws { & $breakScript @scope } 'exit 19'
        Assert ($global:DemoMock.Polls -eq 1) 'Retried a native polling error'
        Assert (@(Get-Mutations).Count -eq 2) 'Continued mutating after native polling error'
        $null = Get-State
    }
    Test-Case 'Explicit revision provisioning failure stops traffic shift' {
        $global:DemoMock.InjectedProvisioning = 'Failed'
        Assert-Throws { & $breakScript @scope } 'revision provisioning failed'
        Assert (@(Get-Mutations).Count -eq 2) 'Fault traffic shifted after provisioning failure'
        $null = Get-State
    }
    Test-Case 'App provisioning failure stops polling before timeout' {
        $global:DemoMock.RevisionDelay = 100
        $global:DemoMock.AppProvisioningFailure = $true
        Assert-Throws { & $breakScript @scope } 'provisioning failed before the injected revision appeared'
        Assert ($global:DemoMock.Polls -eq 1) 'Continued polling a terminal failure'
        Assert (@(Get-Mutations).Count -eq 2) 'Fault traffic shifted after app provisioning failure'
        $null = Get-State
    }
    Test-Case 'Recovery tolerates transient HTTP readiness failures' {
        & $breakScript @scope
        $path = Get-State
        $global:DemoMock.HttpFailuresRemaining = 2
        & $fixScript @scope -StatePath $path
        Assert ($global:DemoMock.HttpFailuresRemaining -eq 0) 'HTTP checks did not retry'
        Assert ((Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Transient HTTP failure blocked recovery'
    }
    Test-Case 'Recovery retries transient HTTP exceptions' {
        & $breakScript @scope
        $path = Get-State
        $global:DemoMock.HttpExceptionsRemaining = 2
        & $fixScript @scope -StatePath $path
        Assert ($global:DemoMock.HttpExceptionsRemaining -eq 0) 'Transport exception was not retried'
        Assert ((Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Transient transport failure blocked recovery'
    }
    foreach ($bodyCase in @(
        @{ Name = 'wrong health status'; Path = '/healthz'; Content = '{"status":"error","version":"1.2.0"}'; Error = 'Unexpected JSON contract' },
        @{ Name = 'wrong health version'; Path = '/healthz'; Content = '{"status":"ok","version":"2.0.0"}'; Error = 'Unexpected JSON contract' },
        @{ Name = 'malformed health JSON'; Path = '/healthz'; Content = '{"status":'; Error = 'Malformed JSON' },
        @{ Name = 'false readiness'; Path = '/readyz'; Content = '{"ready":false}'; Error = 'Unexpected JSON contract' },
        @{ Name = 'string readiness'; Path = '/readyz'; Content = '{"ready":"true"}'; Error = 'Unexpected JSON contract' },
        @{ Name = 'array instead of readiness object'; Path = '/readyz'; Content = '[{"ready":true}]'; Error = 'Unexpected JSON contract' },
        @{ Name = 'malformed readiness JSON'; Path = '/readyz'; Content = '<html>not JSON</html>'; Error = 'Malformed JSON' }
    )) {
        Test-Case "Recovery rejects $($bodyCase.Name), retains state and does not retire" {
            & $breakScript @scope
            $path = Get-State
            $global:DemoMock.HttpBodyOverrides[$bodyCase.Path] = $bodyCase.Content
            Assert-Throws { & $fixScript @scope -StatePath $path } $bodyCase.Error
            Assert (-not (Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Wrong 200 body marked recovered'
            Assert (@($global:DemoMock.Calls | Where-Object { ($_ -join ' ') -like 'containerapp revision deactivate *' }).Count -eq 0) 'Revision retired despite wrong response body'
            $global:DemoMock.HttpBodyOverrides.Clear()
            & $fixScript @scope -StatePath $path
            Assert ((Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Corrected response body did not allow retry'
        }
    }
    Test-Case 'Recovery HTTP failure retains state and revision for retry' {
        & $breakScript @scope
        $path = Get-State
        $global:DemoMock.FailHttp = $true
        Assert-Throws { & $fixScript @scope -StatePath $path } 'HTTP verification failed'
        Assert (-not (Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Failed recovery marked complete'
        Assert (@($global:DemoMock.Calls | Where-Object { ($_ -join ' ') -like 'containerapp revision deactivate *' }).Count -eq 0) 'Retired revision before HTTP recovery'
        $global:DemoMock.FailHttp = $false
        & $fixScript @scope -StatePath $path
        Assert ((Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Recovery retry failed'
    }
    Test-Case 'Recovery native failure stops and is retryable' {
        & $breakScript @scope
        $path = Get-State
        $global:DemoMock.Fail = 'containerapp ingress traffic set '
        Assert-Throws { & $fixScript @scope -StatePath $path } 'exit 19'
        Assert (-not (Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Native failure marked complete'
        $global:DemoMock.Fail = ''
        & $fixScript @scope -StatePath $path
    }
    Test-Case 'Recovery deactivation failure can be retried' {
        & $breakScript @scope
        $path = Get-State
        $global:DemoMock.Fail = 'containerapp revision deactivate '
        Assert-Throws { & $fixScript @scope -StatePath $path } 'exit 19'
        Assert (-not (Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Retirement failure marked complete'
        $global:DemoMock.Fail = ''
        & $fixScript @scope -StatePath $path
    }
    Test-Case 'Recovery checks tag and baseline health again' {
        & $breakScript @scope
        $path = Get-State
        $count = @(Get-Mutations).Count
        $global:DemoMock.App.tags.'sre-demo' = 'false'
        Assert-Throws { & $fixScript @scope -StatePath $path } 'demo tag'
        $global:DemoMock.App.tags.'sre-demo' = 'true'
        $global:DemoMock.Revisions[0].properties.healthState = 'Unhealthy'
        Assert-Throws { & $fixScript @scope -StatePath $path } 'not active, Running and Healthy'
        Assert (@(Get-Mutations).Count -eq $count) 'Unhealthy or untagged recovery mutated'
    }
    Test-Case 'Recovery verifies actual traffic before retirement' {
        & $breakScript @scope
        $path = Get-State
        $global:DemoMock.IgnoreTraffic = $true
        Assert-Throws { & $fixScript @scope -StatePath $path } 'Traffic verification failed'
        Assert (-not (Get-Content $path -Raw | ConvertFrom-Json).Recovered) 'Incorrect traffic marked recovered'
        Assert (@($global:DemoMock.Calls | Where-Object { ($_ -join ' ') -like 'containerapp revision deactivate *' }).Count -eq 0) 'Retired before traffic verification'
    }
    Test-Case 'Tampered baseline weights are rejected' {
        & $breakScript @scope
        $path = Get-State
        $state = Get-Content $path -Raw | ConvertFrom-Json
        $state.BaselineTraffic[0].weight = 5
        $state | ConvertTo-Json -Depth 100 | Set-Content $path
        $count = $global:DemoMock.Calls.Count
        Assert-Throws { & $fixScript @scope -StatePath $path } 'Invalid baseline traffic'
        Assert ($global:DemoMock.Calls.Count -eq $count) 'Invalid state reached Azure'
    }
    Test-Case 'Mismatched recovery state fails before Azure calls' {
        & $breakScript @scope
        $path = Get-State
        $bad = $scope.Clone(); $bad.ResourceGroup = 'other-rg'
        $count = $global:DemoMock.Calls.Count
        Assert-Throws { & $fixScript @bad -StatePath $path } 'does not match'
        Assert ($global:DemoMock.Calls.Count -eq $count) 'Wrong recovery scope reached Azure'
    }
    Test-Case 'Unrelated new traffic blocks stale recovery' {
        & $breakScript @scope
        $path = Get-State
        $global:DemoMock.App.properties.configuration.ingress.traffic = @([pscustomobject]@{ revisionName = 'demo-app--unrelated'; weight = 100 })
        $count = @(Get-Mutations).Count
        Assert-Throws { & $fixScript @scope -StatePath $path } 'unrelated revision'
        Assert (@(Get-Mutations).Count -eq $count) 'Stale recovery overwrote new traffic'
    }
    Test-Case 'Provision rejects existing group and quickstart' {
        $global:DemoMock.GroupExists = $true
        Assert-Throws { & $provisionScript @scope -Location canadacentral -Image example.test/node:v1 -AllowPublicIngress } 'already exists'
        Assert (@(Get-Mutations).Count -eq 0) 'Existing group mutated'
        Assert-Throws { & $provisionScript @scope -Location canadacentral -Image mcr.microsoft.com/k8se/quickstart:latest -AllowPublicIngress } 'not the port-80 quickstart'
    }
    Test-Case 'Provision native failure stops dependent actions' {
        $global:DemoMock.Fail = 'group create '
        Assert-Throws { & $provisionScript @scope -Location canadacentral -Image example.test/node:v1 -AllowPublicIngress } 'exit 19'
        Assert ($global:DemoMock.Calls.Count -eq 2) 'Provision continued after failed resource creation'
    }
    Test-Case 'Provision wires Node Bicep, monitoring and scoped alerts' {
        & $provisionScript @scope -Location canadacentral -Image example.test/node:v1 -AllowedIngressCidr '203.0.113.10/32'
        $calls = @($global:DemoMock.Calls | ForEach-Object { $_ -join ' ' })
        Assert (@($calls | Where-Object { $_ -like 'deployment group create *image=example.test/node:v1*' }).Count -eq 1) 'Bicep image contract missing'
        Assert ($global:DemoMock.DeploymentParameters.applicationInsightsConnectionString.value -eq 'synthetic-test-value') 'Telemetry parameter missing'
        Assert (@($calls | Where-Object { $_ -like '*synthetic-test-value*' }).Count -eq 0) 'Connection string exposed on the command line'
        Assert (-not (Test-Path -LiteralPath $global:DemoMock.DeploymentParametersFile)) 'Parameters file not removed'
        Assert (@($calls | Where-Object { $_ -like 'monitor action-group create *--action*' }).Count -eq 0) 'Unexpected action group receiver'
        Assert (@($calls | Where-Object { $_ -like 'containerapp env create *--logs-workspace-id mock-customer*' }).Count -eq 1) 'Workspace linkage missing'
        Assert (@($calls | Where-Object { $_ -like 'monitor metrics alert create *' }).Count -eq 2) 'Expected two metric alerts'
        Assert (@($calls | Where-Object { $_ -match '\baks\b|quickstart|account set' }).Count -eq 0) 'Forbidden provisioning command'
        Assert ($global:DemoMock.HttpCalls -ge 9) 'Baseline endpoints not verified'
    }
    Test-Case 'Provision requires an explicit ingress decision before Azure calls' {
        Assert-Throws { & $provisionScript @scope -Location canadacentral -Image example.test/node:v1 } 'Ingress exposure must be explicit'
        Assert-Throws { & $provisionScript @scope -Location canadacentral -RegistryName demotestregistry } 'Ingress exposure must be explicit'
        Assert-Throws { & $provisionScript @scope -Location canadacentral -Image example.test/node:v1 -WhatIf } 'Ingress exposure must be explicit'
        Assert-Throws { & $provisionScript @scope -Location canadacentral -Image example.test/node:v1 -AllowedIngressCidr '203.0.113.10/32' -AllowPublicIngress } 'not both'
        Assert ($global:DemoMock.Calls.Count -eq 0) 'Missing or conflicting ingress decision reached Azure'
        Assert ($global:DemoMock.HttpCalls -eq 0) 'Missing or conflicting ingress decision invoked HTTP'
        Assert (-not (Test-Path "$scripts\.state")) 'Missing or conflicting ingress decision created state'
    }
    Test-Case 'Provision applies ingress allow-list and alert email' {
        $warnings = @()
        & $provisionScript @scope -Location canadacentral -Image example.test/node:v1 -AllowedIngressCidr '203.0.113.10/32', '198.51.100.0/24' -AlertEmail 'oncall@contoso.com' -WarningVariable warnings -WarningAction SilentlyContinue
        $calls = @($global:DemoMock.Calls | ForEach-Object { $_ -join ' ' })
        $cidrs = @($global:DemoMock.DeploymentParameters.allowedIngressCidrs.value)
        Assert ($cidrs.Count -eq 2 -and $cidrs[0] -eq '203.0.113.10/32' -and $cidrs[1] -eq '198.51.100.0/24') 'Ingress allow-list not passed to Bicep'
        Assert ($global:DemoMock.DeploymentParameters.allowPublicIngress.value -eq $false) 'Allow-listed ingress must not opt in to public ingress'
        Assert (@($warnings | Where-Object { "$_" -match 'PUBLIC' }).Count -eq 0) 'Restricted ingress reported as public'
        Assert (@($calls | Where-Object { $_ -like 'monitor action-group create *--action email operator oncall@contoso.com*' }).Count -eq 1) 'Alert email receiver missing'
    }
    Test-Case 'Provision public ingress opt-in is unrestricted and warns' {
        $warnings = @()
        & $provisionScript @scope -Location canadacentral -Image example.test/node:v1 -AllowPublicIngress -WarningVariable warnings -WarningAction SilentlyContinue
        Assert (@($global:DemoMock.DeploymentParameters.allowedIngressCidrs.value).Count -eq 0) 'Public opt-in passed an allow-list'
        Assert ($global:DemoMock.DeploymentParameters.allowPublicIngress.value -eq $true) 'Public ingress opt-in not passed to Bicep'
        Assert (@($warnings | Where-Object { "$_" -match 'PUBLIC and unauthenticated' }).Count -eq 1) 'Public ingress warning missing'
    }
    Test-Case 'Provision rejects malformed ingress and email values' {
        Assert-Throws { & $provisionScript @scope -Location canadacentral -Image example.test/node:v1 -AllowedIngressCidr '0.0.0.0' } 'AllowedIngressCidr'
        Assert-Throws { & $provisionScript @scope -Location canadacentral -Image example.test/node:v1 -AllowPublicIngress -AlertEmail 'not-an-email' } 'AlertEmail'
        Assert ($global:DemoMock.Calls.Count -eq 0) 'Invalid parameter reached Azure'
    }
    Test-Case 'Private build WhatIf has no side effects' {
        & $provisionScript @scope -Location canadacentral -RegistryName demotestregistry -AllowPublicIngress -WhatIf
        Assert ($global:DemoMock.Calls.Count -eq 0) 'WhatIf contacted Azure'
        Assert (-not (Test-Path "$scripts\.state")) 'WhatIf staged source'
    }
    Test-Case 'Private build uploads allowlist and scopes pull permission' {
        & $provisionScript @scope -Location canadacentral -RegistryName demotestregistry -AllowPublicIngress
        $calls = @($global:DemoMock.Calls | ForEach-Object { $_ -join ' ' })
        Assert ($global:DemoMock.BuildFiles.Count -eq 6 -and $global:DemoMock.BuildFiles -notcontains '.env') 'Build context contains unapproved files'
        Assert (-not (Test-Path -LiteralPath $global:DemoMock.BuildContext)) 'Build context not cleaned'
        Assert (@($calls | Where-Object { $_ -like 'acr create *--sku Basic --admin-enabled false --role-assignment-mode rbac*' }).Count -eq 1) 'Registry admin must remain disabled'
        Assert (@($calls | Where-Object { $_ -like 'role assignment create *--role 7f951dda-4ed3-4680-a7ca-43fe172d538d --scope /mock/registry*' }).Count -eq 1) 'AcrPull is not registry scoped'
        Assert (@($calls | Where-Object { $_ -like 'deployment group create *image=demotestregistry.azurecr.io/sre-demo-app@sha256:*registryName=demotestregistry registryIdentityName=demo-app-pull*' }).Count -eq 1) 'Private image must be digest pinned and have pull identity'
    }
    Test-Case 'Failed remote build stops deployment and cleans context' {
        $global:DemoMock.BuildStatus = 'Failed'
        Assert-Throws { & $provisionScript @scope -Location canadacentral -RegistryName demotestregistry -AllowPublicIngress } 'build did not succeed'
        Assert (-not (Test-Path -LiteralPath $global:DemoMock.BuildContext)) 'Failed build context not cleaned'
        Assert (@($global:DemoMock.Calls | Where-Object { ($_ -join ' ') -like 'deployment group create *' }).Count -eq 0) 'Failed build deployed an app'
    }
    Test-Case 'Failed pull permission stops before image build' {
        $global:DemoMock.Fail = 'role assignment create '
        Assert-Throws { & $provisionScript @scope -Location canadacentral -RegistryName demotestregistry -AllowPublicIngress } 'exit 19'
        Assert (@($global:DemoMock.Calls | Where-Object { ($_ -join ' ') -match '^(acr build|deployment group create) ' }).Count -eq 0) 'Permission failure continued provisioning'
    }
    Write-Host "PASS: $passed offline script tests; all operator scripts parsed."
    # Mocked failures leave a nonzero native exit code; GitHub's pwsh wrapper exits with it.
    $global:LASTEXITCODE = 0
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
    foreach ($name in @('az', 'Invoke-WebRequest', 'Start-Sleep')) { Remove-Item -LiteralPath "Function:\global:$name" -ErrorAction SilentlyContinue }
    Remove-Variable -Name DemoMock -Scope Global -ErrorAction SilentlyContinue
}
