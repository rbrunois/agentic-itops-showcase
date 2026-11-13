#requires -Version 5.1
<#
.SYNOPSIS
    Simulates the on-call admin's mistake - stops MSSQLSERVER on the SQL VM
    of whichever environment this lab VM belongs to, authenticated as
    svc-oncall so the audit trail (4624/4688) shows that account.

.DESCRIPTION
    Run this from an elevated PowerShell on any lab VM:

        C:\temp\Trigger-Incident.ps1

    The script auto-detects PRD vs NPRD from the lab VM's computer name
    (PRD-SRVWKS01 => PRD, NPRD-SRVWKS01 => NPRD) and hits the matching
    SQL VM (PRD-SRVSQL01 or NPRD-SRVSQL01) via WinRM.

    Install-LabScripts.ps1 bakes the svc-oncall password into a copy of
    this file at C:\temp so nobody has to type it during the demo.

.PARAMETER Check
    Verifies SQL service access as svc-oncall without stopping the service.
#>
[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$svcPassword = '##INCIDENT_PASSWORD##'

if ($env:COMPUTERNAME -notmatch '^(PRD|NPRD)-SRV(WKS|WEB|IIS|SQL)01$') {
    throw "Unsupported lab host: $env:COMPUTERNAME"
}
$envPrefix = $Matches[1]
$sqlComputer = "$envPrefix-SRVSQL01"

Write-Host "== Trigger-Incident ($envPrefix) ==" -ForegroundColor Yellow
Write-Host "  from lab VM:      $env:COMPUTERNAME"
Write-Host "  target SQL host:  $sqlComputer"
Write-Host "  running as:       $sqlComputer\svc-oncall"
Write-Host ""

$sec  = ConvertTo-SecureString $svcPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("$sqlComputer\svc-oncall", $sec)

try {
    Invoke-Command -ComputerName $sqlComputer -Credential $cred -Authentication Negotiate -ErrorAction Stop -ArgumentList ([bool]$Check) -ScriptBlock {
        param([bool]$CheckOnly)
        if (-not $CheckOnly) {
            Stop-Service -Name MSSQLSERVER -Force -ErrorAction Stop
            (Get-Service MSSQLSERVER).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
        }
        whoami
        Get-Service MSSQLSERVER | Format-Table Name, Status, StartType -AutoSize
    }
    if ($Check) {
        Write-Host "Connectivity and credentials verified; no service changes made." -ForegroundColor Green
        return
    }
    Write-Host "MSSQLSERVER stopped on $sqlComputer." -ForegroundColor Red
    $zone = if ($envPrefix -eq 'PRD') { 'contoso.com' } else { 'nprd.contoso.com' }
    Write-Host "Open http://app1.$zone - data tabs should render empty." -ForegroundColor Yellow
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
