<#
.SYNOPSIS
Runs the guardrail prompts against the lab agent and scores the answers.

.DESCRIPTION
Starts one thread per test in demo/guardrail-tests.json through the agent
data-plane API (POST /api/v1/threads), waits until each thread is quiet or
waiting for an approval, exports the messages, and runs score_guardrails.py.

Never approves anything: a thread that asks for approval, or for elevated access
on behalf of the signed-in user, stays waiting. Each thread uses active-flow Azure
Agent Units. Results go to <StateDirectory>/results/guardrails-<timestamp>,
outside the repository.

.EXAMPLE
./Invoke-GuardrailTests.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000
./Invoke-GuardrailTests.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -TestId appliance-vendor-gate
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [string]$ResourceGroup = 'rg-contoso-vmlt-agent',

    [string]$AgentName,

    [Parameter(HelpMessage = 'Run only these test IDs.')]
    [string[]]$TestId,

    [Parameter(HelpMessage = 'A thread with no new message for this long is treated as finished.')]
    [int]$QuietSeconds = 150,

    [int]$TimeoutMinutes = 30,

    [string]$StateDirectory = (Join-Path $HOME '.vmlt-lab')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$demoRoot = Split-Path -Parent $PSScriptRoot
$tests = @((Get-Content (Join-Path $demoRoot 'guardrail-tests.json') -Raw | ConvertFrom-Json).tests)
if ($TestId) { $tests = @($tests | Where-Object id -in $TestId) }
if (-not $tests) { throw 'No tests selected.' }
if (-not $AgentName) {
    $AgentName = (Get-Content (Join-Path $StateDirectory 'agent.json') -Raw | ConvertFrom-Json).agentName.value
}

function Get-Token([string]$Resource) {
    $token = & az account get-access-token --subscription $SubscriptionId --resource $Resource --query accessToken -o tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $token) { throw "Couldn't get a token for $Resource." }
    return $token
}

function Get-Headers { @{ Authorization = "Bearer $(Get-Token 'https://azuresre.dev')" } }

$armToken = Get-Token 'https://management.azure.com/'
$agentUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.App/agents/$AgentName" + '?api-version=2025-05-01-preview'
$endpoint = (Invoke-RestMethod -Uri $agentUri -Headers @{ Authorization = "Bearer $armToken" }).properties.agentEndpoint

$results = Join-Path $StateDirectory ("results/guardrails-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
New-Item -ItemType Directory -Force -Path $results | Out-Null

$runs = foreach ($test in $tests) {
    $body = @{ StartMessage = @{ text = $test.prompt } } | ConvertTo-Json -Depth 5
    $thread = Invoke-RestMethod -Method Post -Uri "$endpoint/api/v1/threads" -Headers (Get-Headers) -ContentType 'application/json' -Body $body -TimeoutSec 60
    $threadId = if ($thread.PSObject.Properties['id']) { $thread.id } else { $thread.threadId }
    Write-Host "Started $($test.id): thread $threadId"
    [pscustomobject]@{ id = $test.id; threadId = $threadId; state = 'running' }
}
$runs | ConvertTo-Json | Set-Content (Join-Path $results 'threads.json') -Encoding utf8

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while (@($runs | Where-Object state -eq 'running') -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 30
    $headers = Get-Headers
    foreach ($run in @($runs | Where-Object state -eq 'running')) {
        $thread = Invoke-RestMethod -Uri "$endpoint/api/v1/threads/$($run.threadId)" -Headers $headers -TimeoutSec 60
        $last = $thread.lastMessage
        $quiet = ((Get-Date).ToUniversalTime() - ([datetime]$thread.modifiedTimestamp).ToUniversalTime()).TotalSeconds
        if ($last -and $last.approval) {
            $run.state = 'waiting-for-approval'
        }
        elseif ($last -and $last.azCliExecution -and $last.azCliExecution.status -match 'PendingAuthorization') {
            $run.state = 'waiting-for-elevation'
        }
        elseif ($quiet -ge $QuietSeconds -and $last -and $last.author.role -ne 'User' -and $last.messageType -ne 'Reasoning') {
            $run.state = 'finished'
        }
        if ($run.state -ne 'running') { Write-Host "$($run.id): $($run.state)" }
    }
}
foreach ($run in @($runs | Where-Object state -eq 'running')) { $run.state = 'timed-out'; Write-Host "$($run.id): timed out" }

$headers = Get-Headers
foreach ($run in $runs) {
    $raw = (Invoke-WebRequest -Uri "$endpoint/api/v1/threads/$($run.threadId)/messages" -Headers $headers -TimeoutSec 60).Content
    [IO.File]::WriteAllText((Join-Path $results "$($run.id).json"), $raw, [Text.UTF8Encoding]::new($false))
}
$runs | ConvertTo-Json | Set-Content (Join-Path $results 'threads.json') -Encoding utf8

& python (Join-Path $PSScriptRoot 'score_guardrails.py') --results $results
Write-Host "Thread exports and scores: $results"
