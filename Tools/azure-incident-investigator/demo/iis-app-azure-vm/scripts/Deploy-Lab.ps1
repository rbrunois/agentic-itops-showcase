#requires -Version 7.0
<#
.SYNOPSIS
    Deploys the SREAgent-IISappAzureVM lab (both PRD and NPRD stacks).

.DESCRIPTION
    - Composes 3 inline PowerShell scripts (WebTier, DbTier, Workstation) by
      taking the Configure-*.ps1 templates and substituting __*__ placeholders
      with real values (admin password, base64-inlined app zip, SQL files).
    - Writes a JSON parameters file with all Bicep params (including the multi-
      line scripts as-is) and runs the subscription-scope deployment.
    - VM configuration runs via Microsoft.Compute/virtualMachines/runCommands v2
      (up to 1 MB inline PowerShell), which sidesteps restrictive tenant
      storage policies entirely — no storage account, no fileUris, no SAS.

    Change tenant / subscription / region by copying
    config/lab.config.example.jsonc to config/lab.config.jsonc (gitignored)
    and editing the copy; no code changes needed.

    Credentials: the script generates an independent random password for each
    lab account (azureadmin VM admin, hrapp SQL login, svc-oncall incident
    actor) and stores them under secrets/ (gitignored, ACL restricted to the
    current user). Labs deployed before per-account passwords keep working:
    with -ScriptsOnly, a missing per-account file falls back to
    secrets/vm-admin.txt; a full deployment rotates the accounts to
    independent passwords.

.PARAMETER WhatIf
    Runs `az deployment sub what-if` instead of `create`.

.PARAMETER ScriptsOnly
    Installs the operator scripts on all six existing VMs without redeploying infrastructure.

.PARAMETER StoreSecretsInKeyVault
    After a successful deployment, also copies the generated passwords into the
    lab Key Vault (requires the Key Vault Secrets Officer role on the vault).
    Failures are reported as warnings; the local secrets/ files remain.
#>
[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$ScriptsOnly,
    [switch]$StoreSecretsInKeyVault
)

$ErrorActionPreference = 'Stop'
if ($ScriptsOnly -and $WhatIf) { throw 'ScriptsOnly cannot be combined with WhatIf.' }
if ($ScriptsOnly -and $StoreSecretsInKeyVault) { throw 'StoreSecretsInKeyVault cannot be combined with ScriptsOnly.' }
$repoRoot = Split-Path $PSScriptRoot -Parent
$tmpDir   = [System.IO.Path]::GetTempPath()

function Get-FileAsB64([string]$path) {
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Path $path)))
}

function Compose-Script([string]$templatePath, [hashtable]$substitutions) {
    $body = Get-Content -Raw -Path $templatePath
    foreach ($key in $substitutions.Keys) {
        $body = $body.Replace("__${key}__", $substitutions[$key])
    }
    return $body
}

# ---------- 1. Load config ----------
$configPath = Join-Path $repoRoot 'config/lab.config.jsonc'
if (-not (Test-Path $configPath)) {
    throw "Config not found: $configPath. Copy config/lab.config.example.jsonc to config/lab.config.jsonc and set tenantId and subscriptionId."
}
$configRaw  = Get-Content -Raw -Path $configPath
$configJson = ($configRaw -split "`n" | ForEach-Object { $_ -replace '\s*//.*$','' }) -join "`n"
$cfg        = $configJson | ConvertFrom-Json

foreach ($setting in 'tenantId', 'subscriptionId') {
    $value = [string]$cfg.$setting
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($value, [ref]$parsed) -or $parsed -eq [guid]::Empty) {
        throw "Set '$setting' in config/lab.config.jsonc to your lab tenant / subscription ID (the all-zero placeholder is not deployable)."
    }
}

Write-Host "Target tenant:       $($cfg.tenantId)"        -ForegroundColor Cyan
Write-Host "Target subscription: $($cfg.subscriptionId)"  -ForegroundColor Cyan
Write-Host "Region:              $($cfg.location)"        -ForegroundColor Cyan

az account set --subscription $cfg.subscriptionId | Out-Null
$currentTenant = az account show --query tenantId -o tsv
if ($currentTenant -ne $cfg.tenantId) {
    throw "Logged into tenant $currentTenant but config expects $($cfg.tenantId). Run 'az login --tenant $($cfg.tenantId)' first."
}

# ---------- 1b. Check for VNet CIDR conflicts across the subscription ----------
Write-Host "`nChecking VNet CIDR uniqueness across the subscription..." -ForegroundColor Cyan

function Get-CidrRange([string]$cidr) {
    $parts = $cidr.Split('/')
    $ip    = [Net.IPAddress]::Parse($parts[0])
    $bits  = [int]$parts[1]
    $addr  = [BitConverter]::ToUInt32($ip.GetAddressBytes()[3..0], 0)
    $mask  = if ($bits -eq 0) { 0 } else { [uint32]::MaxValue -shl (32 - $bits) }
    $start = $addr -band $mask
    $end   = $start + ([uint32]::MaxValue -bxor $mask)
    return @{ Start = $start; End = $end }
}

function Test-CidrOverlap([string]$a, [string]$b) {
    $ra = Get-CidrRange $a; $rb = Get-CidrRange $b
    return ($ra.Start -le $rb.End) -and ($rb.Start -le $ra.End)
}

$myVnets = @(
    @{ name = 'Hub';  cidr = $cfg.hubVnetCidr;  rg = "$($cfg.sharedRgPrefix)-$($cfg.rgBaseName)" }
    @{ name = 'PRD';  cidr = $cfg.prdVnetCidr;  rg = "$($cfg.prodRgPrefix)-$($cfg.rgBaseName)" }
    @{ name = 'NPRD'; cidr = $cfg.nprdVnetCidr; rg = "$($cfg.nonProdRgPrefix)-$($cfg.rgBaseName)" }
)

$existing = az network vnet list --query "[].{name:name, rg:resourceGroup, cidrs:addressSpace.addressPrefixes}" -o json | ConvertFrom-Json
$conflicts = @()
foreach ($mine in $myVnets) {
    foreach ($e in $existing) {
        # Skip the same VNet if this is a re-run (same RG + name)
        if ($e.rg -eq $mine.rg -and $e.name -like "vnet-*") { continue }
        foreach ($c in $e.cidrs) {
            if (Test-CidrOverlap $mine.cidr $c) {
                $conflicts += "  $($mine.name) [$($mine.cidr)] overlaps with $($e.name) [$c] in RG $($e.rg)"
            }
        }
    }
}

if ($conflicts.Count -gt 0) {
    Write-Host "CIDR conflicts detected:" -ForegroundColor Red
    $conflicts | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "`nEdit config/lab.config.jsonc to use non-overlapping CIDRs. Aborting." -ForegroundColor Red
    throw "CIDR conflict"
}
Write-Host "  no CIDR conflicts detected" -ForegroundColor Green

# ---------- 2. Generate / reuse per-account passwords ----------
$secretsDir      = Join-Path $repoRoot 'secrets'
$adminSecretPath = Join-Path $secretsDir 'vm-admin.txt'
$legacySharedPassword = Test-Path $adminSecretPath

function Protect-LabSecretPath([string]$Path, [switch]$Directory) {
    if ($IsWindows) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $grant = if ($Directory) { "${identity}:(OI)(CI)F" } else { "${identity}:F" }
        & icacls.exe $Path /inheritance:r /grant:r $grant | Out-Null
    } else {
        & chmod ($Directory ? '700' : '600') $Path
    }
    if ($LASTEXITCODE -ne 0) { Write-Warning "Could not restrict permissions on $Path" }
}

function New-LabPassword {
    $bytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $rand = ([Convert]::ToBase64String($bytes) -replace '[^a-zA-Z0-9]','').Substring(0,20)
    return "L@b!$rand"
}

function Get-LabSecret([string]$FileName, [string]$Description) {
    $path = Join-Path $secretsDir $FileName
    if (Test-Path $path) {
        Write-Host "Reusing $Description from secrets/$FileName" -ForegroundColor Yellow
        return (Get-Content -Raw -Path $path).Trim()
    }
    if ($ScriptsOnly) {
        if ($FileName -ne 'vm-admin.txt' -and $legacySharedPassword) {
            Write-Warning "secrets/$FileName not found; assuming a lab deployed with one shared password and reusing secrets/vm-admin.txt. Run a full Deploy-Lab.ps1 to rotate to independent passwords."
            return (Get-Content -Raw -Path $adminSecretPath).Trim()
        }
        throw "ScriptsOnly requires the existing secrets/$FileName; no password will be generated."
    }
    $value = New-LabPassword
    New-Item -ItemType File -Path $path -Force | Out-Null
    Protect-LabSecretPath $path
    [IO.File]::WriteAllText($path, $value)
    Write-Host "Generated $Description (saved to secrets/$FileName — gitignored, current-user ACL)" -ForegroundColor Green
    return $value
}

New-Item -ItemType Directory -Force -Path $secretsDir | Out-Null
Protect-LabSecretPath $secretsDir -Directory
$vmAdminPassword  = Get-LabSecret 'vm-admin.txt'          'VM admin password (azureadmin)'
$sqlAppPassword   = Get-LabSecret 'sql-app.txt'           'SQL app login password (hrapp)'
$incidentPassword = Get-LabSecret 'incident-account.txt'  'incident account password (svc-oncall)'
Write-Warning 'Lab passwords are stored in plaintext under secrets/. Keep this folder local, never commit or share it, and delete it after Teardown-Lab.ps1.'

$labScriptsInstaller = Compose-Script (Join-Path $repoRoot 'scripts/Install-LabScripts.ps1') @{
    'VERIFY_SCRIPTS' = ([bool]$ScriptsOnly).ToString()
    'INCIDENT_PASSWORD' = $incidentPassword.Replace("'", "''")
    'TRIGGER_SCRIPT_B64' = Get-FileAsB64 (Join-Path $repoRoot 'scripts/Trigger-Incident.ps1')
    'RESET_SCRIPT_B64' = Get-FileAsB64 (Join-Path $repoRoot 'scripts/Reset-Lab.ps1')
}

if ($ScriptsOnly) {
    $installerPath = [IO.Path]::GetTempFileName()
    try {
        if (-not $IsWindows) { & chmod 600 $installerPath }
        [IO.File]::WriteAllText($installerPath, $labScriptsInstaller)
        foreach ($environment in @(
            @{ Prefix = 'PRD'; ResourceGroup = "$($cfg.prodRgPrefix)-$($cfg.rgBaseName)" },
            @{ Prefix = 'NPRD'; ResourceGroup = "$($cfg.nonProdRgPrefix)-$($cfg.rgBaseName)" }
        )) {
            foreach ($role in 'WKS', 'IIS', 'SQL') {
                $vmName = "$($environment.Prefix)-SRV${role}01"
                Write-Host "Installing operator scripts on $vmName..." -ForegroundColor Cyan
                $result = az vm run-command invoke --resource-group $environment.ResourceGroup `
                    --name $vmName --command-id RunPowerShellScript --scripts "@$installerPath" -o json
                if ($LASTEXITCODE -ne 0) { throw "Run Command failed on $vmName" }
                $messages = (($result | ConvertFrom-Json).value.message) -join "`n"
                if ($messages -notlike "*LAB_SCRIPTS_INSTALLED: $vmName*") {
                    throw "Script installation failed on ${vmName}: $messages"
                }
                Write-Host "LAB_SCRIPTS_INSTALLED: $vmName (C:\temp)" -ForegroundColor Green
            }
        }
    } finally {
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    }
    return
}

# ---------- 3. Package the app + read artifacts ----------
Write-Host "`nPackaging Contoso Global HR app..." -ForegroundColor Cyan
$appSource = Join-Path $repoRoot 'app/ContosoGlobalHR'
$appZip    = Join-Path $tmpDir 'ContosoGlobalHR.zip'
if (Test-Path $appZip) { Remove-Item $appZip -Force }
Compress-Archive -Path (Join-Path $appSource '*') -DestinationPath $appZip -Force
$appZipB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($appZip))
Remove-Item $appZip -Force -ErrorAction SilentlyContinue

$activityGenB64 = Get-FileAsB64 (Join-Path $repoRoot 'scripts/Start-ActivityGenerator.ps1')
$schemaSqlB64   = Get-FileAsB64 (Join-Path $repoRoot 'sql/01-schema.sql')
$seedSqlB64     = Get-FileAsB64 (Join-Path $repoRoot 'sql/02-seed.sql')
$loginsSqlB64   = Get-FileAsB64 (Join-Path $repoRoot 'sql/03-logins.sql')
# ---------- 4. Compose the 3 scripts (plain text) ----------
Write-Host "Composing on-VM scripts..." -ForegroundColor Cyan

$webTierScript = Compose-Script (Join-Path $repoRoot 'scripts/Configure-WebTier.ps1') @{
    'DB_PASSWORD'      = $sqlAppPassword
    'APP_ZIP_B64'      = $appZipB64
    'ACTIVITY_GEN_B64' = $activityGenB64
    'TIMEZONE'         = $cfg.autoShutdownTimeZone
}
$dbTierScript = Compose-Script (Join-Path $repoRoot 'scripts/Configure-DbTier.ps1') @{
    'ADMIN_PASSWORD'    = $vmAdminPassword
    'APP_PASSWORD'      = $sqlAppPassword
    'INCIDENT_PASSWORD' = $incidentPassword
    'SCHEMA_SQL_B64'    = $schemaSqlB64
    'SEED_SQL_B64'      = $seedSqlB64
    'LOGINS_SQL_B64'    = $loginsSqlB64
    'TIMEZONE'          = $cfg.autoShutdownTimeZone
}
$workstationScript = Compose-Script (Join-Path $repoRoot 'scripts/Configure-Workstation.ps1') @{
    'TIMEZONE'           = $cfg.autoShutdownTimeZone
}

$webTierScript += "`n" + $labScriptsInstaller
$dbTierScript += "`n" + $labScriptsInstaller
$workstationScript += "`n" + $labScriptsInstaller

foreach ($pair in @(@{n='web';s=$webTierScript},@{n='db';s=$dbTierScript},@{n='wks';s=$workstationScript})) {
    $kb = [Math]::Round([Text.Encoding]::UTF8.GetByteCount($pair.s) / 1024, 1)
    Write-Host "  $($pair.n) tier script: $kb KB"
    if ($kb -gt 1024) { throw "$($pair.n) script too large ($kb KB) — RunCommand limit is 1 MB." }
}

# ---------- 5. Build parameters JSON file ----------
$sharedRg = "$($cfg.sharedRgPrefix)-$($cfg.rgBaseName)"
$prdRg    = "$($cfg.prodRgPrefix)-$($cfg.rgBaseName)"
$nprdRg   = "$($cfg.nonProdRgPrefix)-$($cfg.rgBaseName)"

$tags = [ordered]@{ Project = 'SRE-Agent-IISTest'; ManagedBy = 'LabAgent' }
if ($cfg.tags) {
    foreach ($property in $cfg.tags.PSObject.Properties) { $tags[$property.Name] = [string]$property.Value }
}
$todayUtc = (Get-Date).ToUniversalTime()
if ($tags['CreatedDate'] -in @($null, '', 'auto')) { $tags['CreatedDate'] = $todayUtc.ToString('yyyy-MM-dd') }
if ($tags['ExpiryDate'] -in @($null, '', 'auto')) { $tags['ExpiryDate'] = $todayUtc.AddDays(30).ToString('yyyy-MM-dd') }
if ([string]::IsNullOrWhiteSpace($tags['Owner'])) {
    $tags['Owner'] = az account show --query user.name -o tsv
}

$params = @{
    '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = @{
        location               = @{ value = $cfg.location }
        tags                   = @{ value = $tags }
        sharedRgName           = @{ value = $sharedRg }
        prdRgName              = @{ value = $prdRg }
        nprdRgName             = @{ value = $nprdRg }
        existingLawResourceId  = @{ value = $cfg.existingLawResourceId }
        hubVnetCidr            = @{ value = $cfg.hubVnetCidr }
        bastionSubnetCidr      = @{ value = $cfg.bastionSubnetCidr }
        prdVnetCidr            = @{ value = $cfg.prdVnetCidr }
        prdWebSubnetCidr       = @{ value = $cfg.prdWebSubnetCidr }
        prdDbSubnetCidr        = @{ value = $cfg.prdDbSubnetCidr }
        prdWksSubnetCidr       = @{ value = $cfg.prdWksSubnetCidr }
        nprdVnetCidr           = @{ value = $cfg.nprdVnetCidr }
        nprdWebSubnetCidr      = @{ value = $cfg.nprdWebSubnetCidr }
        nprdDbSubnetCidr       = @{ value = $cfg.nprdDbSubnetCidr }
        nprdWksSubnetCidr      = @{ value = $cfg.nprdWksSubnetCidr }
        prdDnsZoneName         = @{ value = $cfg.prdDnsZoneName }
        nprdDnsZoneName        = @{ value = $cfg.nprdDnsZoneName }
        vmAdminUsername        = @{ value = $cfg.vmAdminUsername }
        vmAdminPassword        = @{ value = $vmAdminPassword }
        webVmSize              = @{ value = $cfg.webVmSize }
        dbVmSize               = @{ value = $cfg.dbVmSize }
        wksVmSize              = @{ value = $cfg.wksVmSize }
        autoShutdownTime       = @{ value = $cfg.autoShutdownTime }
        autoShutdownTimeZone   = @{ value = $cfg.autoShutdownTimeZone }
        webTierScript          = @{ value = $webTierScript }
        dbTierScript           = @{ value = $dbTierScript }
        workstationScript      = @{ value = $workstationScript }
    }
}
$paramsPath = [IO.Path]::GetTempFileName()
if (-not $IsWindows) { & chmod 600 $paramsPath }

# ---------- 6. Deploy Bicep ----------
$deployName   = "sre-lab-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$templateFile = Join-Path $repoRoot 'bicep/main.bicep'

$verb = if ($WhatIf) { 'what-if' } else { 'create' }
Write-Host "`nRunning: az deployment sub $verb --name $deployName" -ForegroundColor Cyan
try {
    # The parameters file contains passwords; it is deleted as soon as the CLI call returns.
    $params | ConvertTo-Json -Depth 8 | Set-Content -Path $paramsPath -Encoding UTF8
    az deployment sub $verb `
        --name $deployName `
        --location $cfg.location `
        --template-file $templateFile `
        --parameters "@$paramsPath"
    if ($LASTEXITCODE -ne 0) { throw "Deployment failed. See README 'Cleanup after a failed deployment'." }
} finally {
    Remove-Item $paramsPath -Force -ErrorAction SilentlyContinue
}

# ---------- 7. Show connection info ----------
if (-not $WhatIf) {
    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Host " DEPLOYMENT COMPLETE" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    $out = az deployment sub show -n $deployName --query properties.outputs -o json | ConvertFrom-Json
    Write-Host "PRD IIS:  $($out.prdWebPrivateIp.value)   (app1.contoso.com)"
    Write-Host "PRD SQL:  $($out.prdSqlPrivateIp.value)   (sql1.contoso.com)"
    Write-Host "PRD WKS:  $($out.prdWksPrivateIp.value)   (wks1.contoso.com)"
    Write-Host "NPRD IIS: $($out.nprdWebPrivateIp.value)  (app1.nprd.contoso.com)"
    Write-Host "NPRD SQL: $($out.nprdSqlPrivateIp.value)  (sql1.nprd.contoso.com)"
    Write-Host "NPRD WKS: $($out.nprdWksPrivateIp.value)  (wks1.nprd.contoso.com)"
    Write-Host ""
    Write-Host "Bastion:  $($out.bastionName.value)"
    Write-Host "Admin:    $($cfg.vmAdminUsername)  (password in secrets/vm-admin.txt)"
    Write-Host "SQL app:  hrapp       (password in secrets/sql-app.txt)"
    Write-Host "Incident: svc-oncall  (password in secrets/incident-account.txt)"

    if ($StoreSecretsInKeyVault) {
        $vaultName = $out.keyVaultName.value
        Write-Host "`nCopying lab passwords to Key Vault $vaultName..." -ForegroundColor Cyan
        foreach ($secret in @(
            @{ Name = 'vm-admin-password';        File = 'vm-admin.txt' },
            @{ Name = 'sql-app-password';         File = 'sql-app.txt' },
            @{ Name = 'incident-account-password'; File = 'incident-account.txt' }
        )) {
            az keyvault secret set --vault-name $vaultName --name $secret.Name `
                --file (Join-Path $secretsDir $secret.File) --encoding utf-8 --output none
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Could not store $($secret.Name) in $vaultName (Key Vault Secrets Officer role required). The local secrets/ file is unchanged."
            }
        }
    }
}
