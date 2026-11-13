#requires -Version 5.1
<#
Starts MSSQLSERVER on the SQL VM of whichever environment this lab VM is in.
Companion to Trigger-Incident.ps1. Run from an elevated PowerShell on any lab VM:

    C:\temp\Reset-Lab.ps1

Use -Check to verify SQL service access as svc-oncall without changing its state.
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

Write-Host "== Reset-Lab ($envPrefix) ==" -ForegroundColor Green
Write-Host "  target SQL host: $sqlComputer"

$sec  = ConvertTo-SecureString $svcPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("$sqlComputer\svc-oncall", $sec)

try {
    Invoke-Command -ComputerName $sqlComputer -Credential $cred -Authentication Negotiate -ErrorAction Stop -ArgumentList ([bool]$Check) -ScriptBlock {
        param([bool]$CheckOnly)
        if (-not $CheckOnly) {
            Start-Service -Name MSSQLSERVER -ErrorAction Stop
            (Get-Service MSSQLSERVER).WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
        }
        whoami
        Get-Service MSSQLSERVER | Format-Table Name, Status, StartType -AutoSize
    }
    if ($Check) {
        Write-Host "Connectivity and credentials verified; no service changes made." -ForegroundColor Green
        return
    }
    Write-Host "MSSQLSERVER restarted on $sqlComputer. App data should reappear within a minute." -ForegroundColor Green
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
