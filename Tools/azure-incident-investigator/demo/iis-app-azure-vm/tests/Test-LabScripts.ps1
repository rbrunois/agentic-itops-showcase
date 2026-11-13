#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Check', 'Incident')]
    [string]$Mode = 'Check'
)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -notmatch '^(PRD|NPRD)-SRV(WKS|IIS|SQL)01$') {
    throw "Unsupported lab host: $env:COMPUTERNAME"
}
$envPrefix = $Matches[1]
if ($Mode -eq 'Incident' -and $env:COMPUTERNAME -ne 'NPRD-SRVWKS01') {
    throw 'Incident tests are restricted to NPRD-SRVWKS01.'
}
$zone = if ($envPrefix -eq 'PRD') { 'contoso.com' } else { 'nprd.contoso.com' }
$appUrl = "http://app1.$zone/Departments.aspx"

function Invoke-Operator([string]$Name, [switch]$CheckOnly) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "C:\temp\$Name.ps1")
    if ($CheckOnly) { $arguments += '-Check' }
    & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name failed on $env:COMPUTERNAME" }
}

function Assert-AppData([bool]$Expected) {
    $response = Invoke-WebRequest -Uri $appUrl -UseBasicParsing -TimeoutSec 30
    $hasData = $response.Content -match 'CC-100' -and $response.Content -match 'CC-200'
    $isEmpty = $response.Content -match 'No data available\.'
    if ($response.StatusCode -ne 200 -or ($Expected -and (-not $hasData -or $isEmpty)) -or (-not $Expected -and (-not $isEmpty -or $hasData))) {
        throw "Unexpected app data state; expected populated=$Expected"
    }
    Write-Output "APP_DATA_PASS: populated=$Expected HTTP=$($response.StatusCode)"
}

foreach ($name in 'Trigger-Incident', 'Reset-Lab') {
    Invoke-Operator -Name $name -CheckOnly
}
if (-not (Test-Path "$env:PUBLIC\Desktop\Lab PowerShell (C-temp).lnk")) {
    throw 'Lab PowerShell shortcut is missing.'
}
Assert-AppData -Expected $true

if ($env:COMPUTERNAME -like '*-SRVIIS01') {
    $generatorPath = 'C:\ProgramData\ContosoHR\ActivityGenerator.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($generatorPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Activity generator syntax is invalid.' }
    $assignment = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$queries'
    }, $true)
    if (-not $assignment) { throw 'Activity generator queries not found.' }
    $queries = @($assignment.Right.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
    }, $true) | ForEach-Object { $_.Value })
    if ($queries.Count -eq 0) { throw 'No literal activity-generator queries found.' }
    [xml]$config = Get-Content -Raw 'C:\inetpub\ContosoGlobalHR\Web.config'
    $connectionString = ($config.configuration.connectionStrings.add | Where-Object { $_.name -eq 'ContosoHR' }).connectionString
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    try {
        $connection.Open()
        foreach ($query in $queries) {
            $command = $connection.CreateCommand()
            $command.CommandText = $query
            $reader = $command.ExecuteReader()
            while ($reader.Read()) { }
            $reader.Close()
            $command.Dispose()
        }
    } finally {
        $connection.Dispose()
    }
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($connectionString)
    $started = Get-Date
    & $generatorPath -SqlHost $builder.DataSource -DbName $builder.InitialCatalog `
        -DbUser $builder.UserID -DbPassword $builder.Password -EnvPrefix $envPrefix
    $heartbeat = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'; ProviderName = 'ContosoHR-Activity'; StartTime = $started
    } -MaxEvents 1
    if ($heartbeat.Id -ne 1001) { throw 'Activity generator did not emit a healthy heartbeat.' }
    $task = Get-ScheduledTask -TaskName 'ContosoHR-Activity'
    if ($task.State -eq 'Disabled' -or $task.Actions.Arguments -notlike "*$generatorPath*") {
        throw 'Activity generator scheduled task is not configured correctly.'
    }
    Write-Output "ACTIVITY_PASS: $($queries.Count) queries, heartbeat 1001, scheduled task enabled"
}

if ($Mode -eq 'Incident') {
    try {
        Invoke-Operator -Name 'Trigger-Incident'
        Assert-AppData -Expected $false
    } finally {
        Invoke-Operator -Name 'Reset-Lab'
    }
    $deadline = (Get-Date).AddSeconds(60)
    do {
        try {
            Assert-AppData -Expected $true
            break
        } catch {
            if ((Get-Date) -ge $deadline) { throw }
        }
    } while ($true)
}
Write-Output "LAB_TEST_PASS: $env:COMPUTERNAME mode=$Mode"