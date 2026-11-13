#requires -Version 5.1
$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -notmatch '^(PRD|NPRD)-SRV(WKS|IIS|SQL)01$') {
    throw "Unsupported lab host: $env:COMPUTERNAME"
}
$sqlComputer = "$($Matches[1])-SRVSQL01"
$incidentPassword = '__INCIDENT_PASSWORD__'
$artifacts = @{
    'Trigger-Incident.ps1' = '__TRIGGER_SCRIPT_B64__'
    'Reset-Lab.ps1' = '__RESET_SCRIPT_B64__'
}

Start-Service WinRM
$trustedHosts = @((Get-Item WSMan:\localhost\Client\TrustedHosts).Value -split ',' | Where-Object { $_ })
if ($trustedHosts -notcontains $sqlComputer) {
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value (($trustedHosts + $sqlComputer) -join ',') -Force
}

New-Item -ItemType Directory -Path 'C:\temp' -Force | Out-Null
foreach ($name in $artifacts.Keys) {
    $body = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($artifacts[$name]))
    $body = $body.Replace('##INCIDENT_PASSWORD##', $incidentPassword.Replace("'", "''"))
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseInput($body, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) { throw "Invalid PowerShell in $name" }
    $path = Join-Path 'C:\temp' $name
    if (-not (Test-Path $path)) { New-Item -ItemType File -Path $path | Out-Null }
    & icacls.exe $path /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to protect $path" }
    [IO.File]::WriteAllText($path, $body, [Text.UTF8Encoding]::new($false))
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$env:PUBLIC\Desktop\Lab PowerShell (C-temp).lnk")
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = '-NoProfile -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList ''-NoExit -NoProfile -ExecutionPolicy Bypass -Command Set-Location C:\temp''"'
$shortcut.WorkingDirectory = 'C:\temp'
$shortcut.IconLocation = 'powershell.exe,0'
$shortcut.Save()
if ('__VERIFY_SCRIPTS__' -eq 'True') {
    foreach ($name in $artifacts.Keys) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path 'C:\temp' $name) -Check
        if ($LASTEXITCODE -ne 0) { throw "Installed script check failed: $name" }
    }
}
Write-Host "LAB_SCRIPTS_INSTALLED: $env:COMPUTERNAME (C:\temp)"