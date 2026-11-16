<#
.SYNOPSIS
Publishes the package's agent configuration to an Azure SRE Agent.

.DESCRIPTION
Uses the agent data-plane API (token audience https://azuresre.dev), the same
calls that microsoft/sre-agent sreagent-templates make. Publishes, in order:
1. knowledge: knowledge/*.md and the templates;
2. skills: agent/skills/*.md, each with the queries/*.kql files it names;
3. custom agents: the read-only specialists, then vm-lifecycle-coordinator;
4. the tool access policy (agent/tool-access-policy.json), which replaces the
   permissions in the agent's global settings;
5. the agent-level hooks in agent/hooks;
6. the weekly drift scan scheduled task, in Review mode.

The Phase 3 migration-executor agent, its coordinator handoff, and the pilot
runbook are published only with -IncludePilotExecutor.

Needs Python 3 with PyYAML to read the YAML files, and the SRE Agent
Administrator role on the agent.

.EXAMPLE
./Publish-AgentConfig.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -AgentName vmlt-lab-abcde
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [string]$ResourceGroup = 'rg-contoso-vmlt-agent',

    [Parameter(HelpMessage = 'Defaults to the agent that Deploy-Lab.ps1 recorded in the state directory.')]
    [string]$AgentName,

    [Parameter(HelpMessage = 'Subscription that the scheduled scan covers. Defaults to -SubscriptionId.')]
    [string]$ScanSubscriptionId,

    [switch]$IncludePilotExecutor,

    [switch]$SkipScheduledTask,

    [string]$StateDirectory = (Join-Path $HOME '.vmlt-lab')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$package = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$agentFolder = Join-Path $package 'agent'
if (-not $ScanSubscriptionId) { $ScanSubscriptionId = $SubscriptionId }
if (-not $AgentName) {
    $recorded = Join-Path $StateDirectory 'agent.json'
    if (-not (Test-Path $recorded)) { throw 'Pass -AgentName, or run Deploy-Lab.ps1 first.' }
    $AgentName = (Get-Content $recorded -Raw | ConvertFrom-Json).agentName.value
}

$readFile = @'
import json, sys, yaml
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
if path.endswith(".md"):
    _, front, body = text.split("---", 2)
    print(json.dumps({"frontMatter": yaml.safe_load(front), "body": body.lstrip("\r\n")}))
else:
    print(json.dumps(yaml.safe_load(text)))
'@

function Read-ConfigFile([string]$Path) {
    $json = $readFile | & python - $Path
    if ($LASTEXITCODE -ne 0) { throw "Couldn't read $Path. Python 3 with PyYAML is required." }
    return $json | ConvertFrom-Json -AsHashtable
}

function Get-Token([string]$Resource) {
    $token = & az account get-access-token --subscription $SubscriptionId --resource $Resource --query accessToken -o tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $token) { throw "Couldn't get a token for $Resource." }
    return $token
}

$armToken = Get-Token 'https://management.azure.com/'
$agentUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.App/agents/$AgentName" + '?api-version=2025-05-01-preview'
$endpoint = (Invoke-RestMethod -Uri $agentUri -Headers @{ Authorization = "Bearer $armToken" }).properties.agentEndpoint
if (-not $endpoint) { throw "Agent $AgentName has no data-plane endpoint yet." }
Write-Host "Agent $AgentName at $endpoint"

$token = Get-Token 'https://azuresre.dev'
$headers = @{ Authorization = "Bearer $token" }
$failures = [System.Collections.Generic.List[string]]::new()

function Publish-Item([string]$Kind, [string]$Name, [string]$Type, $Properties) {
    $body = @{ name = $Name; type = $Type; tags = @(); properties = $Properties } | ConvertTo-Json -Depth 30
    try {
        Invoke-RestMethod -Method Put -Uri "$endpoint/api/v2/extendedAgent/$Kind/$([uri]::EscapeDataString($Name))" -Headers $headers `
            -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 60 | Out-Null
        Write-Host "  ok $Kind/$Name"
    }
    catch {
        $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        $failures.Add("$Kind/$Name - $detail")
        Write-Host "  FAILED $Kind/$Name - $detail" -ForegroundColor Red
    }
}

function Send-KnowledgeFile([string]$Path) {
    $name = Split-Path $Path -Leaf
    $mime = if ($name.EndsWith('.json')) { 'application/json' } else { 'text/markdown' }
    $boundary = [guid]::NewGuid().ToString()
    $head = [Text.Encoding]::UTF8.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"files`"; filename=`"$name`"`r`nContent-Type: $mime`r`n`r`n")
    $tail = [Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n")
    $stream = [IO.MemoryStream]::new()
    foreach ($part in @($head, [IO.File]::ReadAllBytes($Path), $tail)) { $stream.Write($part, 0, $part.Length) }
    try {
        Invoke-WebRequest -Method Post -Uri "$endpoint/api/v1/AgentMemory/upload?triggerIndexing=true" -Headers $headers `
            -ContentType "multipart/form-data; boundary=$boundary" -Body $stream.ToArray() -TimeoutSec 60 | Out-Null
        Write-Host "  ok knowledge/$name"
    }
    catch {
        $failures.Add("knowledge/$name - $($_.Exception.Message)")
        Write-Host "  FAILED knowledge/$name - $($_.Exception.Message)" -ForegroundColor Red
    }
    finally { $stream.Dispose() }
}

Write-Host 'Knowledge'
$knowledgeFiles = @(Get-ChildItem (Join-Path $package 'knowledge') -Filter '*.md' -File) +
@(Get-ChildItem (Join-Path $package 'templates') -File | Where-Object Extension -in '.md', '.json')
if ($IncludePilotExecutor) { $knowledgeFiles += Get-Item (Join-Path $package 'docs/pilot-runbook.md') }
foreach ($file in $knowledgeFiles) { Send-KnowledgeFile $file.FullName }

Write-Host 'Skills'
# Skill file attachments (additionalFiles) returned HTTP 405 on a workspace-mode
# agent, so each query the skill names is appended to the skill content instead.
foreach ($file in Get-ChildItem (Join-Path $agentFolder 'skills') -Filter '*.md' -File) {
    $skill = Read-ConfigFile $file.FullName
    $front = $skill.frontMatter
    $content = $skill.body.TrimEnd()
    foreach ($query in ([regex]::Matches($skill.body, '[a-z0-9-]+\.kql') | ForEach-Object Value | Sort-Object -Unique)) {
        $queryPath = Join-Path $package "queries/$query"
        if (Test-Path $queryPath) {
            $content += "`n`n## Supporting query: $query`n`n``````kusto`n$((Get-Content $queryPath -Raw).TrimEnd())`n```````n"
        }
    }
    Publish-Item 'skills' $front.name 'Skill' ([ordered]@{
            name            = $front.name
            description     = $front.description
            tools           = @($front.tools)
            skillContent    = $content
            additionalFiles = @()
        })
}

Write-Host 'Custom agents'
# Workspace-mode agents reject new handoffs, so every agent is published without
# them; migration-executor is used directly through /agent in Phase 3.
$specialists = @('inventory-scout', 'compat-analyst', 'sku-advisor', 'quota-capacity-checker')
if ($IncludePilotExecutor) { $specialists += 'migration-executor' }
foreach ($name in $specialists) {
    $definition = Read-ConfigFile (Join-Path $agentFolder "subagents/$name.yaml")
    Publish-Item 'agents' $definition.metadata.name 'ExtendedAgent' $definition.spec
}
$coordinator = Read-ConfigFile (Join-Path $agentFolder 'agent.yaml')
Publish-Item 'agents' $coordinator.metadata.name 'ExtendedAgent' $coordinator.spec

Write-Host 'Tool access policy'
try {
    $settingsUri = "$endpoint/api/v2/agent/settings/global"
    $current = Invoke-WebRequest -Uri $settingsUri -Headers $headers -TimeoutSec 60
    $settings = if ($current.Content) { $current.Content | ConvertFrom-Json -AsHashtable } else { @{} }
    $settings['permissions'] = (Get-Content (Join-Path $agentFolder 'tool-access-policy.json') -Raw | ConvertFrom-Json -AsHashtable).permissions
    $etag = @($current.Headers['ETag'])[0]
    $putHeaders = $headers.Clone()
    $putHeaders['If-Match'] = if ($etag) { $etag } else { '*' }
    Invoke-RestMethod -Method Put -Uri $settingsUri -Headers $putHeaders -ContentType 'application/json; charset=utf-8' `
        -Body ($settings | ConvertTo-Json -Depth 30) -TimeoutSec 60 | Out-Null
    Write-Host '  ok settings/global permissions'
}
catch {
    $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
    $failures.Add("settings/global - $detail")
    Write-Host "  FAILED settings/global - $detail" -ForegroundColor Red
}

Write-Host 'Hooks'
foreach ($file in Get-ChildItem (Join-Path $agentFolder 'hooks') -Filter '*.yaml' -File) {
    $hook = Read-ConfigFile $file.FullName
    Publish-Item 'hooks' $hook.metadata.name 'GlobalHook' $hook.spec
}

if (-not $SkipScheduledTask) {
    Write-Host 'Scheduled task'
    $task = Read-ConfigFile (Join-Path $agentFolder 'scheduled-tasks/weekly-drift-scan.yaml')
    $spec = $task.spec
    Publish-Item 'scheduledtasks' $task.metadata.name 'ScheduledTask' ([ordered]@{
            name           = $task.metadata.name
            description    = $spec.description
            cronExpression = $spec.schedule
            agentPrompt    = $spec.prompt.Replace('00000000-0000-0000-0000-000000000000', $ScanSubscriptionId)
            agent          = $spec.handlingAgent
            agentMode      = $spec.mode
            isEnabled      = $spec.enabled
        })
}

if ($failures.Count) {
    throw "$($failures.Count) item(s) failed:`n$($failures -join "`n")"
}
Write-Host 'Agent configuration published.'
