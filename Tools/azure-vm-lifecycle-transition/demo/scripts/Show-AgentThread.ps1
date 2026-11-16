<#
.SYNOPSIS
Prints a compact timeline of an Azure SRE Agent thread: messages, Azure CLI
commands, Python runs, subagent tasks, hook decisions, and approvals.

.DESCRIPTION
Read-only. Uses the agent data-plane API (GET /api/v1/threads/{id}/messages).
Use it to review what the agent ran during a lab test.

.EXAMPLE
./Show-AgentThread.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -ThreadId <thread-id>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ThreadId,

    [string]$ResourceGroup = 'rg-contoso-vmlt-agent',

    [string]$AgentName,

    [string]$StateDirectory = (Join-Path $HOME '.vmlt-lab'),

    [Parameter(HelpMessage = 'Characters to show per item. 0 shows everything.')]
    [int]$Width = 220,

    [Parameter(HelpMessage = 'Show only items after this many messages.')]
    [int]$Skip = 0,

    [Parameter(HelpMessage = 'Also save the raw thread messages (JSON) to this file, for example for score_agent_output.py.')]
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $AgentName) {
    $AgentName = (Get-Content (Join-Path $StateDirectory 'agent.json') -Raw | ConvertFrom-Json).agentName.value
}

function Get-Token([string]$Resource) {
    $token = & az account get-access-token --subscription $SubscriptionId --resource $Resource --query accessToken -o tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $token) { throw "Couldn't get a token for $Resource." }
    return $token
}

$armToken = Get-Token 'https://management.azure.com/'
$agentUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.App/agents/$AgentName" + '?api-version=2025-05-01-preview'
$endpoint = (Invoke-RestMethod -Uri $agentUri -Headers @{ Authorization = "Bearer $armToken" }).properties.agentEndpoint
$raw = (Invoke-WebRequest -Uri "$endpoint/api/v1/threads/$ThreadId/messages" -Headers @{ Authorization = "Bearer $(Get-Token 'https://azuresre.dev')" } -TimeoutSec 60).Content
if ($OutFile) {
    $folder = Split-Path -Parent $OutFile
    if ($folder) { New-Item -ItemType Directory -Force -Path $folder | Out-Null }
    [IO.File]::WriteAllText($OutFile, $raw, [Text.UTF8Encoding]::new($false))
}
$response = $raw | ConvertFrom-Json
$messages = @(if ($response.PSObject.Properties['value']) { $response.value } else { $response })

function Format-Text($Value) {
    $text = ((($Value | Out-String) -replace '\s+', ' ').Trim())
    if ($Width -gt 0 -and $text.Length -gt $Width) { $text = $text.Substring(0, $Width) + '...' }
    return $text
}

function Get-Field($Message, [string]$Name) {
    $property = $Message.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

$index = 0
foreach ($message in $messages) {
    $index++
    if ($index -le $Skip) { continue }
    $time = ([datetime]$message.timeStamp).ToUniversalTime().ToString('HH:mm:ss')
    $who = if ($message.author.role -eq 'User') { 'USER' } else { 'AGENT' }
    $kind = Get-Field $message 'messageType'
    $line = $null
    if ($cli = Get-Field $message 'azCliExecution') {
        $line = "az: $(Format-Text ($cli | ConvertTo-Json -Depth 6 -Compress))"
    }
    elseif ($python = Get-Field $message 'pythonExecutionResult') {
        $line = "python: $(Format-Text ($python | ConvertTo-Json -Depth 6 -Compress))"
    }
    elseif ($task = Get-Field $message 'taskToolExecutionGroup') {
        $line = "subagents: $(Format-Text ($task | ConvertTo-Json -Depth 6 -Compress))"
    }
    elseif ($hook = Get-Field $message 'hookExecution') {
        $line = "hook: $(Format-Text ($hook | ConvertTo-Json -Depth 6 -Compress))"
    }
    elseif ($approval = Get-Field $message 'approval') {
        $line = "APPROVAL: $(Format-Text ($approval | ConvertTo-Json -Depth 6 -Compress))"
    }
    elseif ($arm = Get-Field $message 'armQuery') {
        $line = "arm: $(Format-Text ($arm | ConvertTo-Json -Depth 6 -Compress))"
    }
    elseif ($mcp = Get-Field $message 'mcpToolExecution') {
        $line = "mcp: $(Format-Text ($mcp | ConvertTo-Json -Depth 6 -Compress))"
    }
    elseif ($todo = Get-Field $message 'todoInfo') {
        $line = "todo: $(Format-Text ($todo | ConvertTo-Json -Depth 6 -Compress))"
    }
    elseif ($memory = Get-Field $message 'memorySearchResult') {
        $line = "memory: $(Format-Text $memory.symptoms)"
    }
    elseif ($report = Get-Field $message 'liveReportCard') {
        $line = "live report: $(Format-Text ($report | ConvertTo-Json -Depth 6 -Compress))"
    }
    elseif ($message.text) {
        $prefix = if ($kind -eq 'Reasoning') { 'thinking: ' } else { '' }
        $line = "$prefix$(Format-Text $message.text)"
    }
    else {
        $set = @($message.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -isnot [bool] -and $_.Name -notin 'id', 'timeStamp', 'author', 'text', 'posted', 'isComplete', 'messageType', 'attachments', 'submittedAt' } | ForEach-Object Name)
        $line = "(other: $($set -join ', '))"
    }
    '{0,3} {1} {2,-5} {3}' -f $index, $time, $who, $line
}
