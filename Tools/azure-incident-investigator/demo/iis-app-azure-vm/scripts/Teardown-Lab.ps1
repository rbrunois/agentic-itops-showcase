#requires -Version 7.0
<#
Tears down the SREAgent-IISappAzureVM lab by deleting the 3 resource groups.
Requires explicit confirmation.
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $repoRoot 'config\lab.config.jsonc'
if (-not (Test-Path $configPath)) {
    throw "Config not found: $configPath. Teardown uses the same config/lab.config.jsonc as Deploy-Lab.ps1."
}
$configRaw = Get-Content -Raw -Path $configPath
$configJson = ($configRaw -split "`n" | ForEach-Object { $_ -replace '\s*//.*$','' }) -join "`n"
$cfg = $configJson | ConvertFrom-Json
$subscriptionGuid = [guid]::Empty
if (-not [guid]::TryParse([string]$cfg.subscriptionId, [ref]$subscriptionGuid) -or $subscriptionGuid -eq [guid]::Empty) {
    throw "Set 'subscriptionId' in config/lab.config.jsonc before running teardown."
}

az account set --subscription $cfg.subscriptionId | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not select subscription $($cfg.subscriptionId). Run 'az login' first." }

$rgs = @(
    "$($cfg.prodRgPrefix)-$($cfg.rgBaseName)",
    "$($cfg.nonProdRgPrefix)-$($cfg.rgBaseName)",
    "$($cfg.sharedRgPrefix)-$($cfg.rgBaseName)"
)

Write-Host "About to DELETE these resource groups in subscription $($cfg.subscriptionId):" -ForegroundColor Yellow
$rgs | ForEach-Object { Write-Host "  - $_" }

if (-not $Force) {
    $confirm = Read-Host "Type 'yes' to proceed"
    if ($confirm -ne 'yes') { Write-Host "Aborted." -ForegroundColor Cyan; return }
}

foreach ($rg in $rgs) {
    if ((az group exists --name $rg) -eq 'true') {
        Write-Host "Deleting $rg (async)..." -ForegroundColor Red
        az group delete --name $rg --yes --no-wait
    }
}
Write-Host "All 3 deletes queued. Check portal for completion." -ForegroundColor Green
Write-Host "After the deletes finish, remove the local secrets/ folder (lab passwords)." -ForegroundColor Yellow
