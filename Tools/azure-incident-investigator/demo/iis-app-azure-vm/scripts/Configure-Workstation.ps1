#requires -Version 5.1
<#
Runs on PRD-SRVWKS01 / NPRD-SRVWKS01 via CustomScriptExtension `script` (inline).
Deploy-Lab.ps1 replaces the placeholders before base64-encoding.
#>
$ErrorActionPreference = 'Stop'
$log = 'C:\Windows\Temp\Configure-Workstation.log'
Start-Transcript -Path $log -Append -Force

Set-TimeZone -Name '__TIMEZONE__' -ErrorAction SilentlyContinue

$EnvPrefix = if ($env:COMPUTERNAME -like 'PRD-*') { 'PRD' } else { 'NPRD' }
$zone      = if ($EnvPrefix -eq 'PRD') { 'contoso.com' } else { 'nprd.contoso.com' }
$AppUrl    = "http://app1.$zone"

Write-Host "== Configure-Workstation =="
Write-Host "Env=$EnvPrefix  AppUrl=$AppUrl"

# ---- Public Desktop shortcut ----
$publicDesktop = "$env:PUBLIC\Desktop"
$shortcut = "$publicDesktop\Contoso HR ($EnvPrefix).lnk"
$WshShell = New-Object -ComObject WScript.Shell
$link = $WshShell.CreateShortcut($shortcut)
$link.TargetPath   = "$env:PROGRAMFILES\Microsoft\Edge\Application\msedge.exe"
$link.Arguments    = $AppUrl
$link.IconLocation = "$env:PROGRAMFILES\Microsoft\Edge\Application\msedge.exe,0"
$link.Save()

# ---- Legal-notice banner (env label at login) ----
$key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
Set-ItemProperty -Path $key -Name 'LegalNoticeCaption' -Value "Contoso HR - $EnvPrefix environment"
Set-ItemProperty -Path $key -Name 'LegalNoticeText'    -Value "You are logged into the $EnvPrefix environment of Contoso HR. App: $AppUrl"

# ---- Public Desktop text file with env info (obvious tell) ----
$readme = "$publicDesktop\ENVIRONMENT-$EnvPrefix.txt"
Set-Content -Path $readme -Value "This is the $EnvPrefix environment.`r`nContoso HR app: $AppUrl`r`nSQL host: sql1.$zone" -Encoding UTF8

# ---- Edge policy: disable HTTPS auto-upgrade (the app is HTTP-only) ----
$edgeKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
if (-not (Test-Path $edgeKey)) { New-Item -Path $edgeKey -Force | Out-Null }
Set-ItemProperty -Path $edgeKey -Name 'HttpsUpgradesEnabled'   -Value 0 -Type DWord
Set-ItemProperty -Path $edgeKey -Name 'HttpsOnlyMode'          -Value 'disallowed' -Type String
Set-ItemProperty -Path $edgeKey -Name 'AutomaticHttpsDefault'  -Value 0 -Type DWord

# ---- Enable WinRM (needed for Trigger-Incident.ps1 -> Invoke-Command) ----
Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null

# ---- TrustedHosts: allow NTLM auth to the two SQL VMs (workgroup requirement) ----
Set-Item WSMan:\localhost\Client\TrustedHosts -Value 'PRD-SRVSQL01,NPRD-SRVSQL01,sql1.contoso.com,sql1.nprd.contoso.com' -Force

Write-Host "Workstation configured for $EnvPrefix."
Stop-Transcript
