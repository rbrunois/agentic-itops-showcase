<#
.SYNOPSIS
Validates the Microsoft Fabric monitoring accelerator before deployment.

.DESCRIPTION
Runs the Python unit tests, Ruff, the deterministic PBIR generator, the Power BI
report validator for both languages, and JSON parsing of the configuration
schema and pipeline template.

Prerequisites:
- Python 3.11+ with the development and MCP service test dependencies:
  python -m pip install -e ".[dev]" -r services/fabric-admin-mcp/requirements.txt
- Node.js 20+ (22 recommended)
- Power BI report authoring CLI:
  npm install -g @microsoft/powerbi-report-authoring-cli@0.5.0

By default, a missing prerequisite fails validation with an actionable message.
Use -SkipUnavailableTools to skip the checks whose tooling is missing and
continue with a warning. Real validation errors always fail.

.EXAMPLE
./scripts/validate.ps1

.EXAMPLE
./scripts/validate.ps1 -SkipUnavailableTools
#>
[CmdletBinding()]
param(
    [string]$Python = "python",
    [switch]$SkipUnavailableTools
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$skipped = [System.Collections.Generic.List[string]]::new()

function Test-ExternalCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @("--version")
    )

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        & $Command @Arguments *> $null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Confirm-Tool {
    param(
        [Parameter(Mandatory)][bool]$Available,
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$Remedy
    )

    if ($Available) {
        return $true
    }
    $message = "$Step skipped: required tooling is unavailable. $Remedy"
    if ($SkipUnavailableTools) {
        Write-Warning $message
        $skipped.Add($Step)
        return $false
    }
    throw "$Step cannot run: required tooling is unavailable. $Remedy Use -SkipUnavailableTools to continue without it."
}

Push-Location $root
try {
    $pythonReady = (Test-ExternalCommand -Command $Python) -and
        (Test-ExternalCommand -Command $Python -Arguments @("-m", "pytest", "--version")) -and
        (Test-ExternalCommand -Command $Python -Arguments @("-m", "ruff", "--version"))
    if (Confirm-Tool -Available $pythonReady -Step "Python tests and Ruff" `
            -Remedy "Install Python 3.11+ and run: $Python -m pip install -e "".[dev]"" -r services/fabric-admin-mcp/requirements.txt") {
        & $Python -m pytest
        if ($LASTEXITCODE -ne 0) { throw "Python tests failed." }

        & $Python -m ruff check src tests notebooks
        if ($LASTEXITCODE -ne 0) { throw "Ruff validation failed." }
    }

    $nodeReady = Test-ExternalCommand -Command "node"
    if (Confirm-Tool -Available $nodeReady -Step "Power BI report generation" `
            -Remedy "Install Node.js 20 or later (22 recommended).") {
        node scripts\generate-report.mjs
        if ($LASTEXITCODE -ne 0) { throw "Power BI report generation failed." }
    }

    $authorReady = Test-ExternalCommand -Command "powerbi-report-author"
    if (Confirm-Tool -Available $authorReady -Step "PBIR validation" `
            -Remedy "Run: npm install -g @microsoft/powerbi-report-authoring-cli@0.5.0") {
        powerbi-report-author validate "powerbi\FabricSRE\fr\FabricSRE-fr.Report" --pretty
        if ($LASTEXITCODE -ne 0) { throw "French PBIR validation failed." }

        powerbi-report-author validate "powerbi\FabricSRE\en\FabricSRE-en.Report" --pretty
        if ($LASTEXITCODE -ne 0) { throw "English PBIR validation failed." }
    }

    Get-Content "config\client.parameters.schema.json" -Raw | ConvertFrom-Json | Out-Null
    Get-Content "pipelines\daily-collection.pipeline.template.json" -Raw | ConvertFrom-Json | Out-Null

    if ($skipped.Count -gt 0) {
        Write-Warning ("Fabric SRE validation completed with skipped checks: " + ($skipped -join ", ") + ".")
    }
    else {
        Write-Host "Fabric SRE validation succeeded."
    }
}
finally {
    Pop-Location
}
