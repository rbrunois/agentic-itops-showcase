#requires -Version 5.1
<#
Runs on PRD-SRVSQL01 / NPRD-SRVSQL01 via CustomScriptExtension `script` (inline).
Deploy-Lab.ps1 replaces __*_SQL_B64__ placeholders + parameters before base64-
encoding the whole script.
#>
$ErrorActionPreference = 'Stop'
$log = 'C:\Windows\Temp\Configure-DbTier.log'
Start-Transcript -Path $log -Append -Force

Set-TimeZone -Name '__TIMEZONE__' -ErrorAction SilentlyContinue

# ---- Baked-in parameters ----
$DbName           = 'ContosoHR'
$AppLogin         = 'hrapp'
$AppPassword      = '__APP_PASSWORD__'
$IncidentUser     = 'svc-oncall'
$IncidentPassword = '__INCIDENT_PASSWORD__'
$LocalAdmin       = 'azureadmin'
$LocalAdminPwd    = '__ADMIN_PASSWORD__'

$EnvPrefix = if ($env:COMPUTERNAME -like 'PRD-*') { 'PRD' } else { 'NPRD' }

Write-Host "== Configure-DbTier =="
Write-Host "Env=$EnvPrefix  DbName=$DbName"

# ---- Materialize embedded SQL files ----
$stagingDir = 'C:\Windows\Temp\SREAgentLab'
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

$schemaSqlB64 = '__SCHEMA_SQL_B64__'
$seedSqlB64   = '__SEED_SQL_B64__'
$loginsSqlB64 = '__LOGINS_SQL_B64__'

[IO.File]::WriteAllText((Join-Path $stagingDir '01-schema.sql'),
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($schemaSqlB64)))
[IO.File]::WriteAllText((Join-Path $stagingDir '02-seed.sql'),
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($seedSqlB64)))
[IO.File]::WriteAllText((Join-Path $stagingDir '03-logins.sql'),
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($loginsSqlB64)))

# ---- SQL Server: enable mixed mode, TCP/IP, port 1433, open firewall ----
Import-Module SqlServer -ErrorAction SilentlyContinue

Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer' -Name LoginMode -Value 2 -ErrorAction SilentlyContinue

# Enable TCP/IP via registry (no SMO WMI dependency)
$tcpKey = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer\SuperSocketNetLib\Tcp'
Set-ItemProperty -Path $tcpKey -Name 'Enabled' -Value 1 -Type DWord
Get-ChildItem $tcpKey | ForEach-Object {
    $sub = $_.PSPath
    if (Test-Path (Join-Path $sub 'TcpDynamicPorts')) {
        Set-ItemProperty -Path $sub -Name 'TcpDynamicPorts' -Value '' -Type String -ErrorAction SilentlyContinue
    }
    if (Test-Path (Join-Path $sub 'TcpPort')) {
        Set-ItemProperty -Path $sub -Name 'TcpPort' -Value '1433' -Type String -ErrorAction SilentlyContinue
    }
}

New-NetFirewallRule -DisplayName 'SQL Server TCP 1433' -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow -ErrorAction SilentlyContinue | Out-Null

Restart-Service -Name MSSQLSERVER -Force
Start-Sleep -Seconds 30

# ---- Prepare a session as azureadmin (member of BUILTIN\Administrators,
#      which is a SQL sysadmin on the marketplace image). WinRM local loopback
#      uses NTLM so this doesn't depend on the Secondary Logon service. ----
Write-Host "Preparing WinRM session as $LocalAdmin..."
Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
$sec = ConvertTo-SecureString $LocalAdminPwd -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("$env:COMPUTERNAME\$LocalAdmin", $sec)

$session = $null
$tries = 0
while ($tries -lt 20) {
    try {
        $session = New-PSSession -ComputerName localhost -Credential $cred -Authentication Negotiate -ErrorAction Stop
        break
    } catch {
        Start-Sleep -Seconds 5; $tries++
    }
}
if (-not $session) { throw "Could not open local WinRM session as $LocalAdmin" }

# ---- Wait for SQL to be reachable from within the azureadmin session ----
# Use sqlcmd.exe (native, in PATH after SQL install) — Invoke-Sqlcmd needs the
# SqlServer module which may not be present in the WinRM session's scope.
$tries = 0
while ($tries -lt 30) {
    $ok = Invoke-Command -Session $session -ScriptBlock {
        & sqlcmd -S localhost -E -Q "SELECT 1" -b 2>$null | Out-Null
        $LASTEXITCODE -eq 0
    }
    if ($ok) { break }
    Start-Sleep -Seconds 3; $tries++
}
if ($tries -eq 30) { throw "SQL not reachable after restart" }
Write-Host "SQL reachable, azureadmin authenticated."

# ---- Run schema, seed, logins (all executed as azureadmin -> sysadmin) ----
foreach ($f in '01-schema.sql','02-seed.sql','03-logins.sql') {
    $p = Join-Path $stagingDir $f
    Write-Host "Running $f..."
    $sql = Get-Content -Raw -Path $p
    $sql = $sql -replace '##DB_NAME##',     $DbName
    $sql = $sql -replace '##APP_LOGIN##',   $AppLogin
    $sql = $sql -replace '##APP_PASSWORD##',$AppPassword
    $tokenized = "$p.tokenized"
    Set-Content -Path $tokenized -Value $sql -Encoding UTF8

    Invoke-Command -Session $session -ScriptBlock {
        param($sqlFile)
        & sqlcmd -S localhost -E -i $sqlFile -f 65001 -b
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed for $sqlFile (exit $LASTEXITCODE)" }
    } -ArgumentList $tokenized
}

Remove-PSSession $session

# ---- Create the "admin who makes the mistake" ----
$secure = ConvertTo-SecureString $IncidentPassword -AsPlainText -Force
if (-not (Get-LocalUser -Name $IncidentUser -ErrorAction SilentlyContinue)) {
    New-LocalUser -Name $IncidentUser -Password $secure -FullName 'Incident Actor' `
        -Description 'Local admin used by Trigger-Incident.ps1' `
        -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
} else {
    Set-LocalUser -Name $IncidentUser -Password $secure
}
Add-LocalGroupMember -Group 'Administrators'       -Member $IncidentUser -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $IncidentUser -ErrorAction SilentlyContinue

# ---- Allow local-admin network logon (WinRM from WKS as svc-oncall needs full token) ----
$polKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
New-ItemProperty -Path $polKey -Name 'LocalAccountTokenFilterPolicy' -Value 1 -PropertyType DWord -Force | Out-Null

# ---- Open WinRM firewall from Any (default: LocalSubnet-only on Public profile) ----
Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP-PUBLIC' -EA SilentlyContinue | Set-NetFirewallRule -RemoteAddress Any
Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP'        -EA SilentlyContinue | Set-NetFirewallRule -RemoteAddress Any

# ---- Enable Security auditing (process creation, service state) ----
AuditPol /set /subcategory:"Process Creation"           /success:enable /failure:enable | Out-Null
AuditPol /set /subcategory:"Logon"                      /success:enable /failure:enable | Out-Null
AuditPol /set /subcategory:"Logoff"                     /success:enable                  | Out-Null
AuditPol /set /subcategory:"Security State Change"      /success:enable /failure:enable | Out-Null
AuditPol /set /subcategory:"Other Object Access Events" /success:enable /failure:enable | Out-Null

# Include command line in 4688 events (helps the SRE Agent)
$path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
New-ItemProperty -Path $path -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -PropertyType DWORD -Force | Out-Null

Write-Host "Database, incident user, and audit policy configured."
Stop-Transcript
