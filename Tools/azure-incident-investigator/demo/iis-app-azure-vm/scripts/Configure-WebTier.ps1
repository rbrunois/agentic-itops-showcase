#requires -Version 5.1
<#
Runs on PRD-SRVIIS01 / NPRD-SRVIIS01 via CustomScriptExtension `script` (inline
base64). Deploy-Lab.ps1 substitutes __APP_ZIP_B64__ + __ACTIVITY_GEN_B64__
placeholders with actual artifact content before base64-encoding the whole
script for CSE.

Args are baked in via string interpolation by Deploy-Lab.ps1 (not passed on
the command line — CSE `script` doesn't accept args).
#>
$ErrorActionPreference = 'Stop'
$log = 'C:\Windows\Temp\Configure-WebTier.log'
Start-Transcript -Path $log -Append -Force

Set-TimeZone -Name '__TIMEZONE__' -ErrorAction SilentlyContinue

# ---- Baked-in parameters (Deploy-Lab.ps1 replaces these) ----
$DbName     = 'ContosoHR'
$DbUser     = 'hrapp'
$DbPassword = '__DB_PASSWORD__'

# ---- Environment auto-detected from hostname (PRD-* vs NPRD-*) ----
$EnvPrefix = if ($env:COMPUTERNAME -like 'PRD-*') { 'PRD' } else { 'NPRD' }
$zone      = if ($EnvPrefix -eq 'PRD') { 'contoso.com' } else { 'nprd.contoso.com' }
$SqlHost   = "sql1.$zone"

Write-Host "== Configure-WebTier =="
Write-Host "Env=$EnvPrefix  SqlHost=$SqlHost  DbName=$DbName"

# ---- Materialize embedded artifacts from base64 ----
$stagingDir = 'C:\Windows\Temp\SREAgentLab'
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

$appZipB64      = '__APP_ZIP_B64__'
$activityGenB64 = '__ACTIVITY_GEN_B64__'

[IO.File]::WriteAllBytes((Join-Path $stagingDir 'ContosoGlobalHR.zip'),
    [Convert]::FromBase64String($appZipB64))
[IO.File]::WriteAllText((Join-Path $stagingDir 'Start-ActivityGenerator.ps1'),
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($activityGenB64)))

# ---- 1. IIS + ASP.NET 4.8 ----
Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Net-Ext45, `
    Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Mgmt-Console -IncludeManagementTools | Out-Null

# ---- 2. Deploy the app ----
$appDir = 'C:\inetpub\ContosoGlobalHR'
New-Item -ItemType Directory -Force -Path $appDir | Out-Null
Expand-Archive -Path (Join-Path $stagingDir 'ContosoGlobalHR.zip') -DestinationPath $appDir -Force

# ---- 3. Tokenize Web.config ----
$webConfig = Join-Path $appDir 'Web.config'
$xml = Get-Content -Raw -Path $webConfig
$xml = $xml -replace '##SQL_HOST##',    $SqlHost
$xml = $xml -replace '##DB_NAME##',     $DbName
$xml = $xml -replace '##DB_USER##',     $DbUser
$xml = $xml -replace '##DB_PASSWORD##', $DbPassword
$xml = $xml -replace '##ENV_PREFIX##',  $EnvPrefix
Set-Content -Path $webConfig -Value $xml -Encoding UTF8

# ---- 4. IIS site ----
Import-Module WebAdministration
if (Get-Website -Name 'Default Web Site' -ErrorAction SilentlyContinue) {
    Remove-Website -Name 'Default Web Site'
}
if (-not (Get-Website -Name 'ContosoGlobalHR' -ErrorAction SilentlyContinue)) {
    New-Website -Name 'ContosoGlobalHR' -Port 80 -PhysicalPath $appDir -ApplicationPool 'DefaultAppPool' | Out-Null
}
Set-ItemProperty 'IIS:\AppPools\DefaultAppPool' -Name managedRuntimeVersion -Value 'v4.0'
icacls $appDir /grant "IIS_IUSRS:(OI)(CI)RX" /T | Out-Null

# ---- 5. Activity generator scheduled task ----
New-Item -ItemType Directory -Force -Path 'C:\ProgramData\ContosoHR' | Out-Null
Copy-Item (Join-Path $stagingDir 'Start-ActivityGenerator.ps1') `
    'C:\ProgramData\ContosoHR\ActivityGenerator.ps1' -Force

$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\ContosoHR\ActivityGenerator.ps1 -SqlHost $SqlHost -DbName $DbName -DbUser $DbUser -DbPassword `"$DbPassword`" -EnvPrefix $EnvPrefix"
$trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Seconds 60) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
$trigger2 = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName 'ContosoHR-Activity' -Action $action `
    -Trigger @($trigger, $trigger2) -Principal $principal -Settings $settings -Force | Out-Null

# ---- 6. IIS log fields — richer telemetry ----
& "$env:windir\system32\inetsrv\appcmd.exe" set config -section:system.applicationHost/sites /siteDefaults.logFile.logExtFileFlags:"Date,Time,ClientIP,UserName,SiteName,ComputerName,ServerIP,Method,UriStem,UriQuery,HttpStatus,Win32Status,BytesSent,BytesRecv,TimeTaken,ServerPort,UserAgent,Cookie,Referer,ProtocolVersion,Host,HttpSubStatus" /commit:apphost | Out-Null

# ---- 7. Event source for the app's own audit trail ----
if (-not [System.Diagnostics.EventLog]::SourceExists('ContosoHR-Activity')) {
    [System.Diagnostics.EventLog]::CreateEventSource('ContosoHR-Activity','Application')
}

iisreset /restart | Out-Null
Write-Host "IIS site configured. App reachable at http://app1.$zone"

Stop-Transcript
