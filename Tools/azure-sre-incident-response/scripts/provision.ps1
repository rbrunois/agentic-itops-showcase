#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'PublicImage')]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')][string]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_-][a-zA-Z0-9_.()-]{0,89}$')][string]$ResourceGroup,
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]{0,30}[a-z0-9]$')][string]$AppName,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+$')][string]$Location,
    [Parameter(Mandatory, ParameterSetName = 'PublicImage')][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._:/@-]+$')][string]$Image,
    [Parameter(Mandatory, ParameterSetName = 'PrivateBuild')][ValidatePattern('^[a-z0-9]{5,50}$')][string]$RegistryName,
    [ValidatePattern('^[a-z][a-z0-9-]{0,58}[a-z0-9]$')][string]$EnvironmentName = "$AppName-env",
    # IPv4 CIDR allow-list for the ingress. Exactly one of -AllowedIngressCidr or -AllowPublicIngress is required.
    [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}/(3[0-2]|[12]?\d)$')][string[]]$AllowedIngressCidr = @(),
    # Explicit opt-in to a public, unauthenticated endpoint reachable from the whole internet.
    [switch]$AllowPublicIngress,
    # Optional email receiver for the demo action group; without it alerts fire but notify no one.
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')][string]$AlertEmail
)
. "$PSScriptRoot\common.ps1"
$groupCreated = $false
trap {
    if ($groupCreated) {
        Write-Warning "Provisioning failed after creating resource group '$ResourceGroup'. Billable resources may remain and nothing is deleted automatically. Follow 'Cleanup after failed provisioning' in the package README."
    }
    break
}

if (@($AllowedIngressCidr).Count -eq 0 -and -not $AllowPublicIngress) {
    throw 'Ingress exposure must be explicit: pass -AllowedIngressCidr with at least one approved source range (include the operator address used for health checks), or -AllowPublicIngress to accept a public, unauthenticated endpoint.'
}
if (@($AllowedIngressCidr).Count -gt 0 -and $AllowPublicIngress) {
    throw 'Specify either -AllowedIngressCidr or -AllowPublicIngress, not both.'
}
if ($PSCmdlet.ParameterSetName -eq 'PublicImage' -and ($Image -match '(?i)(k8se/quickstart|://)' -or $Image -notmatch '/')) {
    throw 'Image must be the public registry image of this package Node application (port 8080), not the port-80 quickstart.'
}
$template = Join-Path $PSScriptRoot '..\infra\containerapp.bicep'
if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw "Missing Bicep template: $template" }
$ingressDescription = if ($AllowPublicIngress) { 'PUBLIC unauthenticated ingress' } else { "ingress restricted to $(@($AllowedIngressCidr) -join ', ')" }
if (-not $PSCmdlet.ShouldProcess("$SubscriptionId/$ResourceGroup/$AppName", "Create a NEW dedicated resource group, monitoring, Container Apps environment, Node baseline with $ingressDescription and alerts; PrivateBuild also creates ACR, builds the image and grants a scoped pull identity (billable)")) { return }

$exists = Invoke-DemoAz @('group', 'exists', '-n', $ResourceGroup) $SubscriptionId
if ($exists) { throw 'Resource group already exists. Provision only into a new dedicated group; inspect partial deployments and perform separately approved scoped cleanup before retrying.' }
$law = "$AppName-law"
$ai = "$AppName-ai"
$actionGroup = "$AppName-actions"
$null = Invoke-DemoAz @('group', 'create', '-n', $ResourceGroup, '-l', $Location, '--tags', 'sre-demo=true') $SubscriptionId
$groupCreated = $true
$registryParameters = @()
$acrPullRoleDefinitionId = '7f951dda-4ed3-4680-a7ca-43fe172d538d' # Built-in AcrPull role
if ($PSCmdlet.ParameterSetName -eq 'PrivateBuild') {
    $registry = Invoke-DemoAz @('acr', 'create', '-g', $ResourceGroup, '-n', $RegistryName, '-l', $Location,
        '--sku', 'Basic', '--admin-enabled', 'false', '--role-assignment-mode', 'rbac', '--tags', 'sre-demo=true') $SubscriptionId
    $identityName = "$AppName-pull"
    $identity = Invoke-DemoAz @('identity', 'create', '-g', $ResourceGroup, '-n', $identityName, '-l', $Location,
        '--tags', 'sre-demo=true') $SubscriptionId
    if (-not $registry.id -or -not $registry.loginServer -or -not $identity.principalId) {
        throw 'Registry or pull identity information was not returned; inspect the partial resource group.'
    }
    $null = Invoke-DemoAz @('role', 'assignment', 'create', '--assignee-object-id', $identity.principalId,
        '--assignee-principal-type', 'ServicePrincipal', '--role', $acrPullRoleDefinitionId,
        '--scope', $registry.id) $SubscriptionId
    $imageTag = "sre-demo-app:build-$([guid]::NewGuid().ToString('N'))"
    $context = Join-Path $PSScriptRoot ".state\build-$([guid]::NewGuid().ToString('N'))"
    [void](New-Item -ItemType Directory -Path $context -Force)
    try {
        # Only these reviewed app files leave the machine; never upload the repository or local settings.
        foreach ($file in @('Dockerfile', '.dockerignore', '.npmrc', 'package.json', 'package-lock.json', 'server.js')) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\app\$file") -Destination $context
        }
        $build = Invoke-DemoAz @('acr', 'build', '-r', $RegistryName, '-g', $ResourceGroup,
            '--image', $imageTag, '--file', (Join-Path $context 'Dockerfile'), '--platform', 'linux', '--timeout', '1200',
            '--no-logs', $context) $SubscriptionId
        if (-not $build -or $build.status -ne 'Succeeded') {
            throw "Private image build did not succeed. Inspect ACR runs for $RegistryName; no app was deployed."
        }
    } finally {
        Remove-Item -LiteralPath $context -Recurse -Force
    }
    $metadata = Invoke-DemoAz @('acr', 'repository', 'show', '-n', $RegistryName, '--image', $imageTag) $SubscriptionId
    if ($metadata.digest -notmatch '^sha256:[0-9a-f]{64}$') { throw 'Built image digest was not returned; deployment stopped.' }
    $Image = "$($registry.loginServer)/sre-demo-app@$($metadata.digest)"
    $registryParameters = @("registryName=$RegistryName", "registryIdentityName=$identityName")
    Write-Host "Private image built and pinned by digest: $Image"
}
$workspace = Invoke-DemoAz @('monitor', 'log-analytics', 'workspace', 'create', '-g', $ResourceGroup, '-n', $law, '-l', $Location) $SubscriptionId
$insights = Invoke-DemoAz @('monitor', 'app-insights', 'component', 'create', '--app', $ai, '-g', $ResourceGroup, '-l', $Location, '--workspace', $workspace.id) $SubscriptionId
$keys = Invoke-DemoAz @('monitor', 'log-analytics', 'workspace', 'get-shared-keys', '-g', $ResourceGroup, '-n', $law) $SubscriptionId
if (-not $keys.primarySharedKey -or -not $workspace.customerId -or -not $insights.connectionString) {
    throw 'Monitoring configuration was not returned; stop and inspect the partial resource group.'
}
try {
    $null = Invoke-DemoAz @('containerapp', 'env', 'create', '-g', $ResourceGroup, '-n', $EnvironmentName, '-l', $Location,
        '--logs-workspace-id', $workspace.customerId, '--logs-workspace-key', $keys.primarySharedKey) $SubscriptionId
} finally { $keys = $null }
$suffix = "baseline-$([guid]::NewGuid().ToString('N').Substring(0,12))"
# Values that must not appear in process listings or shell history go through a short-lived parameters file.
$stateDir = Join-Path $PSScriptRoot '.state'
[void](New-Item -ItemType Directory -Path $stateDir -Force)
$parametersFile = Join-Path $stateDir "deploy-$([guid]::NewGuid().ToString('N')).parameters.json"
try {
    @{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters     = @{
            applicationInsightsConnectionString = @{ value = [string]$insights.connectionString }
            allowedIngressCidrs                 = @{ value = @($AllowedIngressCidr) }
            allowPublicIngress                  = @{ value = [bool]$AllowPublicIngress }
        }
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $parametersFile -Encoding utf8NoBOM
    if (-not $IsWindows) { chmod 600 $parametersFile }
    $null = Invoke-DemoAz (@('deployment', 'group', 'create', '-g', $ResourceGroup, '-n', "sre-demo-$suffix",
        '--template-file', $template, '--parameters', "@$parametersFile", "environmentName=$EnvironmentName", "appName=$AppName",
        "image=$Image", "revisionSuffix=$suffix", "location=$Location") + $registryParameters) $SubscriptionId
} finally {
    $insights = $null
    Remove-Item -LiteralPath $parametersFile -Force -ErrorAction SilentlyContinue
}
$app = Get-DemoApp $SubscriptionId $ResourceGroup $AppName
$traffic = @(Get-DemoTraffic $app)
$revisions = @(Invoke-DemoAz @('containerapp', 'revision', 'list', '-g', $ResourceGroup, '-n', $AppName, '--all') $SubscriptionId)
Assert-DemoBaseline $traffic $revisions
Assert-DemoHttp $app.properties.configuration.ingress.fqdn
$actionGroupArguments = @('monitor', 'action-group', 'create', '-g', $ResourceGroup, '-n', $actionGroup, '--short-name', 'SreDemo')
if ($AlertEmail) { $actionGroupArguments += @('--action', 'email', 'operator', $AlertEmail) }
$ag = Invoke-DemoAz $actionGroupArguments $SubscriptionId
foreach ($alert in @(
    @{ Name = "$AppName-restarts"; Condition = 'max RestartCount > 0'; Severity = '2' },
    @{ Name = "$AppName-no-replicas"; Condition = 'max Replicas < 1'; Severity = '1' }
)) {
    $null = Invoke-DemoAz @('monitor', 'metrics', 'alert', 'create', '-g', $ResourceGroup, '-n', $alert.Name,
        '--scopes', $app.id, '--condition', $alert.Condition, '--window-size', '5m',
        '--evaluation-frequency', '1m', '--severity', $alert.Severity, '--action', $ag.id) $SubscriptionId
}
Write-Host "Baseline verified: https://$($app.properties.configuration.ingress.fqdn)"
if ($AllowPublicIngress) {
    Write-Warning 'The app endpoint is PUBLIC and unauthenticated (-AllowPublicIngress). Anyone who learns the FQDN can reach it; tear it down after the rehearsal or use -AllowedIngressCidr instead.'
} else {
    Write-Host "Ingress restricted to: $($AllowedIngressCidr -join ', ')"
}
if ($AlertEmail) {
    Write-Host "Action group '$actionGroup' has one email receiver. Confirm the Azure Monitor subscription email and test delivery."
} else {
    Write-Host "Provisioned action group '$actionGroup' has NO receivers: alerts fire but notify no one. Use -AlertEmail or configure and test a receiver manually."
}
Write-Host 'Azure SRE Agent is NOT provisioned: onboard separately, select the explicit demo scope, assign least-privilege read access, attach knowledge, and configure supported alert integration. Grant execution access only with human approval.'
Write-Host 'Image publicity, telemetry ingestion, live alert delivery, agent investigation and incident closure require a separately approved rehearsal. No automatic cleanup is performed on failure.'
