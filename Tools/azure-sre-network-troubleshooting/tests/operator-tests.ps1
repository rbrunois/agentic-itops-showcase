#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$package = Split-Path -Parent $PSScriptRoot
. (Join-Path $package 'scripts\common.ps1')
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('contoso-network-tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temporary)
$contextPath = Join-Path $temporary 'deployment-context.json'
$outputPath = Join-Path $temporary 'normalized.json'
$subscriptionId = [guid]::NewGuid().ToString()
$groupId = "/subscriptions/$subscriptionId/resourceGroups/rg-sre-network-demo"
$fixture = [pscustomobject]@{
    subscriptionId = $subscriptionId
    resourceGroupName = 'rg-sre-network-demo'
    resourceGroupId = $groupId
    location = 'westcentralus'
    clientVmName = 'vm-sre-client'
    workloadVmName = 'vm-sre-web'
    clientVmId = "$groupId/providers/Microsoft.Compute/virtualMachines/vm-sre-client"
    workloadVmId = "$groupId/providers/Microsoft.Compute/virtualMachines/vm-sre-web"
    clientVnetId = "$groupId/providers/Microsoft.Network/virtualNetworks/vnet-sre-network-demo-client"
    workloadVnetId = "$groupId/providers/Microsoft.Network/virtualNetworks/vnet-sre-network-demo-workload"
    clientPrivateIp = '10.10.1.4'
    workloadPrivateIp = '10.20.1.4'
    clientSubnetPrefix = '10.10.1.0/24'
    workloadSubnetPrefix = '10.20.1.0/24'
    workloadNsgName = 'nsg-sre-network-demo-workload'
    workspaceCustomerId = [guid]::NewGuid().ToString()
    workspaceResourceId = "$groupId/providers/Microsoft.OperationalInsights/workspaces/law-sre-network-demo"
    networkWatcherResourceGroup = 'NetworkWatcherRG'
    networkWatcherName = 'NetworkWatcher_westcentralus'
    flowLogNames = @('fl-sre-network-demo-client', 'fl-sre-network-demo-workload')
    roleAssignmentIds = @()
}
$watcherId = "/subscriptions/$subscriptionId/resourceGroups/NetworkWatcherRG/providers/Microsoft.Network/networkWatchers/$($fixture.networkWatcherName)"
$passed = 0

function Assert-Test([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    $caught = $false
    try { & $Action | Out-Null } catch {
        $caught = $true
        if ($_.Exception.Message -notmatch $Pattern) { throw }
    }
    Assert-Test $caught "Expected rejection matching '$Pattern'."
}
function Reset-Mock {
    $fixture | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $contextPath
    if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath }
    $global:ContosoNetworkMock = @{
        Calls = [Collections.Generic.List[object]]::new()
        Subscription = $subscriptionId
        Tags = @{ workload = 'sre-network-demo'; environment = 'demo' }
        Rules = @([pscustomobject]@{ Name = 'Allow-Client-To-Web-Demo'; Access = 'Allow'; Direction = 'Inbound'; DestinationPortRange = '80' })
        FlowTarget = $fixture.clientVnetId
        QueryMode = 'records'
        GuestSummary = 'summary attempts=2 failures=0 tcp_failures=0 web_failures=0'
        Extensions = @([pscustomobject]@{ Name = 'AzureMonitorWindowsAgent'; Publisher = 'Microsoft.Azure.Monitor'; ExtensionType = 'AzureMonitorWindowsAgent'; ProvisioningState = 'Succeeded' })
        Outputs = $fixture
        EndpointIp = $fixture.clientPrivateIp
    }
}
function Invoke-Operator([string]$Name, [hashtable]$Options = @{}) {
    $arguments = @{ ContextPath = $contextPath }
    if ($Name -in @('generate-good-traffic','generate-bad-traffic','create-network-failure','restore-network',
        'create-application-failure','restore-application','validate-kql-schema','validate-telemetry','wait-for-telemetry')) {
        $arguments.EvidenceDirectory = $temporary
    }
    foreach ($key in $Options.Keys) { $arguments[$key] = $Options[$key] }
    & (Join-Path $package "scripts\$Name.ps1") @arguments
}
function Get-Mutations {
    @($global:ContosoNetworkMock.Calls | Where-Object Name -match '^(Add|Set|Remove|Invoke-AzVM|New)-Az|^Invoke-AzVM')
}
function Invoke-MockAzure([string]$Command, [System.Collections.IDictionary]$Parameters) {
    $global:ContosoNetworkMock.Calls.Add([pscustomobject]@{ Name = $Command; Parameters = $Parameters })
    switch ($Command) {
        'Get-AzContext' { return [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $global:ContosoNetworkMock.Subscription } } }
        'Get-AzSubscriptionDeployment' { return [pscustomobject]@{ Name = 'contoso-test'; Outputs = $global:ContosoNetworkMock.Outputs } }
        'Get-AzNetworkSecurityGroup' { return [pscustomobject]@{ Name = $fixture.workloadNsgName; Id = "$groupId/providers/Microsoft.Network/networkSecurityGroups/$($fixture.workloadNsgName)"; SecurityRules = $global:ContosoNetworkMock.Rules } }
        'Add-AzNetworkSecurityRuleConfig' {
            Assert-Test ($Parameters.Name -ceq 'Deny-Client-To-Web-Demo' -and $Parameters.Priority -eq 100 -and
                $Parameters.SourceAddressPrefix -eq $fixture.clientSubnetPrefix -and
                $Parameters.DestinationAddressPrefix -eq $fixture.workloadPrivateIp -and
                $Parameters.DestinationPortRange -eq '80' -and $Parameters.Direction -eq 'Inbound' -and
                $Parameters.Access -eq 'Deny') 'Fault changed the exact approved network contract.'
            return $Parameters.NetworkSecurityGroup
        }
        'Remove-AzNetworkSecurityRuleConfig' {
            Assert-Test ($Parameters.Name -ceq 'Deny-Client-To-Web-Demo') 'Removal must target only the injected deny.'
            return $Parameters.NetworkSecurityGroup
        }
        'Set-AzNetworkSecurityGroup' { return $Parameters.NetworkSecurityGroup }
        'Invoke-AzVMRunCommand' {
            Assert-Test ($Parameters.ResourceGroupName -eq $fixture.resourceGroupName -and
                $Parameters.VMName -in @($fixture.clientVmName,$fixture.workloadVmName)) 'Guest execution escaped the lab.'
            return [pscustomobject]@{ Status = 'Succeeded'; Value = @([pscustomobject]@{
                Code = 'ComponentStatus/StdOut/succeeded'; Level = 'Info'; DisplayStatus = 'Succeeded'; Message = $global:ContosoNetworkMock.GuestSummary
            }) }
        }
        'Invoke-AzOperationalInsightsQuery' {
            Assert-Test ($Parameters.WorkspaceId -eq $fixture.workspaceCustomerId) 'Query escaped workspace scope.'
            Assert-Test ($Parameters.Query -notmatch '__[A-Z_]+__') 'Unbound KQL placeholder.'
            if ($global:ContosoNetworkMock.QueryMode -eq 'error') { throw 'Synthetic query error' }
            if ($Parameters.Query -match '\bEvent\b') {
                Assert-Test ($Parameters.Query.Contains($fixture.workloadVmId)) 'Health query must bind destination VM.'
            }
            $empty = $global:ContosoNetworkMock.QueryMode -eq 'empty' -or
                ($global:ContosoNetworkMock.QueryMode -eq 'no-health' -and $Parameters.Query -match '\bEvent\b') -or
                ($global:ContosoNetworkMock.QueryMode -eq 'no-samples' -and $Parameters.Query -notmatch 'getschema')
            return [pscustomobject]@{ Results = $(if ($empty) { @() } else { @([pscustomobject]@{ Value = 'synthetic-evidence' }) }) }
        }
        'Get-AzResourceGroup' { return [pscustomobject]@{ ResourceId = $groupId; Tags = $global:ContosoNetworkMock.Tags } }
        'Get-AzNetworkWatcher' { return [pscustomobject]@{ Id = $watcherId; Location = $fixture.location; ProvisioningState = 'Succeeded' } }
        'Get-AzResource' {
            if ($Parameters.ContainsKey('ResourceId')) { return [pscustomobject]@{ ResourceType = 'Microsoft.OperationalInsights/workspaces' } }
            if ($Parameters.ContainsKey('ResourceType')) {
                return @(
                    [pscustomobject]@{ ResourceId = "$watcherId/flowLogs/$($fixture.flowLogNames[0])"; Properties = [pscustomobject]@{ targetResourceId = $global:ContosoNetworkMock.FlowTarget } },
                    [pscustomobject]@{ ResourceId = "$watcherId/flowLogs/$($fixture.flowLogNames[1])"; Properties = [pscustomobject]@{ targetResourceId = $fixture.workloadVnetId } },
                    [pscustomobject]@{ ResourceId = "$watcherId/flowLogs/fl-unrelated"; Properties = [pscustomobject]@{ targetResourceId = '/unrelated' } }
                )
            }
            return @()
        }
        'Get-AzRoleAssignment' { return @() }
        'Remove-AzResource' {
            Assert-Test ($Parameters.ResourceId -in @("$watcherId/flowLogs/$($fixture.flowLogNames[0])","$watcherId/flowLogs/$($fixture.flowLogNames[1])")) 'Deletion escaped exact owned flow logs.'
            return
        }
        'Remove-AzResourceGroup' {
            Assert-Test ($Parameters.Name -eq $fixture.resourceGroupName) 'Deletion escaped dedicated group.'
            return
        }
        'Get-AzVM' {
            $nic = if ($Parameters.Name -eq $fixture.clientVmName) { 'client' } else { 'web' }
            return [pscustomobject]@{ Location = $fixture.location; NetworkProfile = [pscustomobject]@{ NetworkInterfaces = @([pscustomobject]@{ Id = "$groupId/providers/Microsoft.Network/networkInterfaces/nic-$nic" }) } }
        }
        'Get-AzNetworkInterface' {
            $ip = if ($Parameters.Name -eq 'nic-client') { $global:ContosoNetworkMock.EndpointIp } else { $fixture.workloadPrivateIp }
            return [pscustomobject]@{ IpConfigurations = @([pscustomobject]@{ Primary = $true; PrivateIpAddress = $ip }) }
        }
        'Get-AzVMExtension' { return $global:ContosoNetworkMock.Extensions }
        'Test-AzResourceGroupDeployment' { return @() }
        'New-AzResourceGroupDeployment' {
            Assert-Test ($Parameters.TemplateFile -like '*\connection-monitor.bicep' -and
                $Parameters.Mode -eq 'Incremental') 'Monitor must use only the additive entry point.'
            return [pscustomobject]@{ ProvisioningState = 'Succeeded'; Outputs = @{} }
        }
        default { throw "Unexpected Azure command in offline suite: $Command" }
    }
}

$mockNames = @(
    Get-ChildItem (Join-Path $package 'scripts') -Filter '*.ps1' | ForEach-Object {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
        Assert-Test ($errors.Count -eq 0) "PowerShell parse: $($_.Name)"
        $ast.FindAll({ param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -match '^[A-Za-z]+-Az'
        },$true) | ForEach-Object { $_.GetCommandName() }
    }
) | Sort-Object -Unique
foreach ($name in $mockNames) {
    $body = @'
param($ResourceGroupName,$Name,$ResourceId,$ResourceType,$NetworkSecurityGroup,$Description,$Access,$Protocol,
    $Direction,$Priority,$SourceAddressPrefix,$SourcePortRange,$DestinationAddressPrefix,$DestinationPortRange,
    $VMName,$CommandId,$ScriptString,$WorkspaceId,$Query,$Scope,$InputObject,$Mode,$TemplateFile,$location,
    $clientVmName,$workloadVmName,$workloadPrivateIp,$workspaceResourceId,$networkWatcherResourceGroupName,
    $networkWatcherName,$connectionMonitorName,$installSourceAgent,[switch]$Force,[switch]$ExpandProperties,
    [switch]$WhatIf,$ErrorAction)
Invoke-MockAzure -Command '__COMMAND__' -Parameters $PSBoundParameters
'@
    Set-Item -Path "Function:\$name" -Value ([scriptblock]::Create($body.Replace('__COMMAND__',$name)))
}
function Read-Host { throw 'Unexpected interactive approval in offline tests.' }
function Test-Case([string]$Name, [scriptblock]$Action) {
    Reset-Mock
    & $Action | Out-Null
    $script:passed++
    Write-Host "PASS: $Name"
}
$window = @{ TestStartUtc = [datetime]'2026-01-01T10:00:00Z'; TestEndUtc = [datetime]'2026-01-01T10:05:00Z' }
try {
    Test-Case 'All context-based entry points default to zero Azure calls' {
        foreach ($name in @('generate-good-traffic','generate-bad-traffic','create-network-failure','restore-network',
            'create-application-failure','restore-application','cleanup','validate-kql-schema','deploy-connection-monitor')) {
            Invoke-Operator $name
        }
        Invoke-Operator 'validate-telemetry' $window
        Invoke-Operator 'wait-for-telemetry' $window
        & (Join-Path $package 'scripts\deploy.ps1')
        & (Join-Path $package 'scripts\test-prerequisites.ps1')
        & (Join-Path $package 'scripts\get-deployment-context.ps1') -DeploymentName contoso-test -SubscriptionId $subscriptionId
        Assert-Test ($global:ContosoNetworkMock.Calls.Count -eq 0) 'Default invocation contacted Azure.'
    }
    Test-Case 'Zero subscription is rejected by live guard' {
        Assert-Throws { Assert-DeploymentSubscription '00000000-0000-0000-0000-000000000000' } 'nonzero'
        Assert-Test ($global:ContosoNetworkMock.Calls.Count -eq 0) 'Invalid subscription caused Azure read.'
    }
    Test-Case 'Subscription mismatch blocks mutations' {
        $global:ContosoNetworkMock.Subscription = [guid]::NewGuid().ToString()
        Assert-Throws { Invoke-Operator 'create-network-failure' @{ Execute=$true; Confirmation='INJECT NETWORK FAILURE' } } 'does not match'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Mismatch allowed a mutation.'
    }
    Test-Case 'Confirmation without execution opt-in cannot mutate' {
        Invoke-Operator 'create-network-failure' @{Confirmation='INJECT NETWORK FAILURE'}
        Assert-Test ($global:ContosoNetworkMock.Calls.Count -eq 0) 'Confirmation alone opted into execution.'
    }
    Test-Case 'Missing human confirmation cannot mutate' {
        Assert-Throws { Invoke-Operator 'create-network-failure' @{Execute=$true} } 'Unexpected interactive approval'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Missing approval allowed mutation.'
    }
    foreach ($entry in @(
        @{ Name='create-network-failure'; Confirmation='INJECT NETWORK FAILURE' },
        @{ Name='restore-network'; Confirmation='RESTORE NETWORK' },
        @{ Name='create-application-failure'; Confirmation='STOP IIS' },
        @{ Name='restore-application'; Confirmation='START IIS' },
        @{ Name='generate-good-traffic'; Confirmation='GENERATE GOOD TRAFFIC' },
        @{ Name='generate-bad-traffic'; Confirmation='GENERATE BAD TRAFFIC' }
    )) {
        Test-Case "$($entry.Name) rejects wrong confirmation before mutation" {
            Assert-Throws { Invoke-Operator $entry.Name @{ Execute=$true; Confirmation='NOT APPROVED' } } 'Confirmation did not'
            Assert-Test (@(Get-Mutations).Count -eq 0) 'Wrong confirmation allowed a mutation.'
        }
    }
    foreach ($change in @(
        @{ Key='resourceGroupName'; Value='NetworkWatcherRG'; Error='Refusing operation' },
        @{ Key='workloadVmId'; Value="$groupId/providers/Microsoft.Compute/virtualMachines/unrelated"; Error='does not match' },
        @{ Key='flowLogNames'; Value=@('fl-unrelated','fl-other'); Error='flow-log names' },
        @{ Key='workloadPrivateIp'; Value='10.20.1.0'; Error='usable' },
        @{ Key='networkWatcherName'; Value='watcher/other'; Error='invalid watcher' },
        @{ Key='subscriptionId'; Value='00000000-0000-0000-0000-000000000000'; Error='nonzero' }
    )) {
        Test-Case "Reject invalid context: $($change.Key)" {
            $invalid = $fixture | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $invalid.($change.Key) = $change.Value
            $invalid | ConvertTo-Json -Depth 20 | Set-Content $contextPath
            Assert-Throws { Invoke-Operator 'create-network-failure' @{Execute=$true;Confirmation='INJECT NETWORK FAILURE'} } $change.Error
            Assert-Test ($global:ContosoNetworkMock.Calls.Count -eq 0) 'Invalid context reached Azure.'
        }
    }
    Test-Case 'Context refresh checks subscription before Azure read' {
        $global:ContosoNetworkMock.Subscription = [guid]::NewGuid().ToString()
        Assert-Throws {
            & (Join-Path $package 'scripts\get-deployment-context.ps1') -Execute -DeploymentName contoso-test -SubscriptionId $subscriptionId -ContextPath $outputPath
        } 'does not match'
        Assert-Test (@($global:ContosoNetworkMock.Calls | Where-Object Name -eq 'Get-AzSubscriptionDeployment').Count -eq 0) 'Read happened before subscription check.'
    }
    Test-Case 'Context refresh validates outputs before replacing existing file' {
        Set-Content $outputPath 'preserve-existing'
        $invalid = $fixture | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $invalid.workloadVmId = '/unrelated'
        Assert-Throws {
            & (Join-Path $package 'scripts\get-deployment-context.ps1') -DeploymentObject ([pscustomobject]@{Name='contoso-test';Outputs=$invalid}) -SubscriptionId $subscriptionId -ContextPath $outputPath
        } 'does not match'
        Assert-Test ((Get-Content $outputPath -Raw).Trim() -eq 'preserve-existing') 'Invalid outputs replaced context.'
    }
    Test-Case 'Valid normalized deployment outputs persist without Azure calls' {
        & (Join-Path $package 'scripts\get-deployment-context.ps1') -DeploymentObject ([pscustomobject]@{Name='contoso-test';Outputs=$fixture}) -SubscriptionId $subscriptionId -ContextPath $outputPath
        Get-DeploymentContext $outputPath | Out-Null
        Assert-Test ($global:ContosoNetworkMock.Calls.Count -eq 0) 'Object normalization contacted Azure.'
    }
    Test-Case 'Azure context refresh reads only after subscription validation' {
        & (Join-Path $package 'scripts\get-deployment-context.ps1') -Execute -DeploymentName contoso-test -SubscriptionId $subscriptionId -ContextPath $outputPath
        Assert-Test (($global:ContosoNetworkMock.Calls.Name -join ',') -eq 'Get-AzContext,Get-AzSubscriptionDeployment') 'Unexpected refresh call order.'
        Get-DeploymentContext $outputPath | Out-Null
    }
    Test-Case 'ARM wrapped outputs normalize correctly' {
        $wrapped = @{}
        foreach ($property in $fixture.PSObject.Properties) {
            $wrapped[$property.Name] = @{ value = $property.Value }
        }
        & (Join-Path $package 'scripts\get-deployment-context.ps1') -DeploymentObject ([pscustomobject]@{Name='contoso-test';Outputs=$wrapped}) -SubscriptionId $subscriptionId -ContextPath $outputPath
        Get-DeploymentContext $outputPath | Out-Null
    }
    Test-Case 'Valid outputs for a different intended subscription cannot persist' {
        Assert-Throws {
            & (Join-Path $package 'scripts\get-deployment-context.ps1') -DeploymentObject ([pscustomobject]@{Name='contoso-test';Outputs=$fixture}) -SubscriptionId ([guid]::NewGuid().ToString()) -ContextPath $outputPath
        } 'explicitly requested subscription'
        Assert-Test (-not (Test-Path $outputPath)) 'Mismatched context persisted.'
    }
    Test-Case 'Network failure uses exact scoped rule' {
        Invoke-Operator 'create-network-failure' @{Execute=$true;Confirmation='INJECT NETWORK FAILURE'}
        Assert-Test (@(Get-Mutations).Count -eq 2) 'Expected add-config plus save NSG.'
    }
    Test-Case 'Existing injected rule is not overwritten' {
        $global:ContosoNetworkMock.Rules += [pscustomobject]@{Name='Deny-Client-To-Web-Demo'}
        Assert-Throws { Invoke-Operator 'create-network-failure' @{Execute=$true;Confirmation='INJECT NETWORK FAILURE'} } 'already exists'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Existing rule overwritten.'
    }
    Test-Case 'Network restore removes only injected rule' {
        $global:ContosoNetworkMock.Rules += [pscustomobject]@{Name='Deny-Client-To-Web-Demo'}
        Invoke-Operator 'restore-network' @{Execute=$true;Confirmation='RESTORE NETWORK'}
        Assert-Test (@(Get-Mutations).Count -eq 2) 'Expected remove-config plus save NSG.'
    }
    Test-Case 'Network restore is idempotent when injected rule absent' {
        Invoke-Operator 'restore-network' @{Execute=$true;Confirmation='RESTORE NETWORK'}
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Absent rule caused mutation.'
    }
    Test-Case 'Application failure refuses concurrent network failure' {
        $global:ContosoNetworkMock.Rules += [pscustomobject]@{Name='Deny-Client-To-Web-Demo'}
        Assert-Throws { Invoke-Operator 'create-application-failure' @{Execute=$true;Confirmation='STOP IIS'} } 'Scenario A deny'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Application changed while network fault present.'
    }
    Test-Case 'Application failure proves service stopped' {
        $global:ContosoNetworkMock.GuestSummary = 'summary service=W3SVC state=stopped'
        Invoke-Operator 'create-application-failure' @{Execute=$true;Confirmation='STOP IIS'}
        Assert-Test (@(Get-Mutations).Count -eq 1) 'Expected only guest execution.'
    }
    Test-Case 'Application failure requires baseline allow rule' {
        $global:ContosoNetworkMock.Rules = @()
        Assert-Throws { Invoke-Operator 'create-application-failure' @{Execute=$true;Confirmation='STOP IIS'} } 'No baseline inbound allow'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Application changed without baseline allow.'
    }
    Test-Case 'Application stop rejects unproven outcome' {
        $global:ContosoNetworkMock.GuestSummary = 'unproven'
        Assert-Throws { Invoke-Operator 'create-application-failure' @{Execute=$true;Confirmation='STOP IIS'} } 'did not prove'
    }
    Test-Case 'Application restoration proves service running and HTTP 200' {
        $global:ContosoNetworkMock.GuestSummary = 'summary service=W3SVC state=running http_status=200'
        Invoke-Operator 'restore-application' @{Execute=$true;Confirmation='START IIS'}
    }
    Test-Case 'Application restoration rejects unproven HTTP health' {
        $global:ContosoNetworkMock.GuestSummary = 'summary service=W3SVC state=running http_status=503'
        Assert-Throws { Invoke-Operator 'restore-application' @{Execute=$true;Confirmation='START IIS'} } 'did not prove'
    }
    foreach ($mode in @('missing','zero','failed')) {
        Test-Case "Healthy traffic rejects $mode outcome" {
            $global:ContosoNetworkMock.GuestSummary = switch ($mode) {
                'missing' {'no summary'}
                'zero' {'summary attempts=0 failures=0 tcp_failures=0 web_failures=0'}
                'failed' {'summary attempts=2 failures=1 tcp_failures=1 web_failures=1'}
            }
            Assert-Throws { Invoke-Operator 'generate-good-traffic' @{Execute=$true;Confirmation='GENERATE GOOD TRAFFIC'} } 'required summary|no attempts|failed attempt'
        }
    }
    Test-Case 'Healthy traffic succeeds with positive attempts and zero failures' {
        Invoke-Operator 'generate-good-traffic' @{Execute=$true;Confirmation='GENERATE GOOD TRAFFIC'}
    }
    Test-Case 'Failure traffic rejects unexpected complete success' {
        $global:ContosoNetworkMock.GuestSummary = 'summary attempts=2 failures=0 successes=2 tcp_failures=0 web_failures=0'
        Assert-Throws { Invoke-Operator 'generate-bad-traffic' @{Execute=$true;Confirmation='GENERATE BAD TRAFFIC'} } 'no failed'
    }
    Test-Case 'Failure traffic records failures without attributing network cause' {
        $global:ContosoNetworkMock.GuestSummary = 'summary attempts=2 failures=2 successes=0 tcp_failures=2 web_failures=2'
        Invoke-Operator 'generate-bad-traffic' @{Execute=$true;Confirmation='GENERATE BAD TRAFFIC'}
    }
    foreach ($mode in @('empty','error','no-samples')) {
        Test-Case "Schema validation rejects $mode" {
            $global:ContosoNetworkMock.QueryMode = $mode
            Assert-Throws { Invoke-Operator 'validate-kql-schema' @{Execute=$true} } 'schema gate is incomplete'
        }
    }
    Test-Case 'Schema validation needs both columns and samples' {
        Invoke-Operator 'validate-kql-schema' @{Execute=$true}
        Assert-Test (@($global:ContosoNetworkMock.Calls | Where-Object Name -eq 'Invoke-AzOperationalInsightsQuery').Count -eq 2) 'Schema and samples not queried.'
    }
    foreach ($mode in @('empty','error','no-health')) {
        Test-Case "Telemetry validation rejects $mode" {
            $global:ContosoNetworkMock.QueryMode = $mode
            Assert-Throws { Invoke-Operator 'validate-telemetry' ($window + @{Execute=$true}) } 'incomplete'
        }
    }
    Test-Case 'Telemetry binds exact endpoints, window and destination VM' {
        Invoke-Operator 'validate-telemetry' ($window + @{Execute=$true})
        $query = @($global:ContosoNetworkMock.Calls | Where-Object Name -eq 'Invoke-AzOperationalInsightsQuery')[0].Parameters.Query
        Assert-Test ($query.Contains($fixture.clientPrivateIp) -and $query.Contains($fixture.workloadPrivateIp) -and
            $query.Contains('let ActionValidated = false;') -and $query.Contains('let FlowStatusValidated = false;')) 'Unsafe query defaults or endpoint binding.'
    }
    Test-Case 'Polling succeeds on matching evidence' {
        Invoke-Operator 'wait-for-telemetry' ($window + @{Execute=$true})
    }
    Test-Case 'Polling error times out explicitly without real waiting' {
        $global:ContosoNetworkMock.QueryMode = 'error'
        $global:ContosoNetworkClock = [DateTime]::UtcNow
        function script:Get-Date { $global:ContosoNetworkClock = $global:ContosoNetworkClock.AddSeconds(61); return $global:ContosoNetworkClock }
        function script:Start-Sleep { throw 'Offline timeout test must not sleep.' }
        try {
            Assert-Throws { Invoke-Operator 'wait-for-telemetry' ($window + @{Execute=$true;TimeoutMinutes=1}) } 'incomplete'
        } finally {
            Remove-Item Function:\Get-Date
            Remove-Item Function:\Start-Sleep
        }
    }
    Test-Case 'Monitor installs only missing source extension through additive template' {
        Invoke-Operator 'deploy-connection-monitor' @{Execute=$true;Confirmation='DEPLOY CONNECTION MONITOR sre-network-demo-connection-monitor'}
        $deployments = @($global:ContosoNetworkMock.Calls | Where-Object { $_.Name -eq 'New-AzResourceGroupDeployment' -and -not $_.Parameters.ContainsKey('WhatIf') })
        Assert-Test ($deployments.Count -eq 1 -and $deployments[0].Parameters.installSourceAgent) 'Expected additive source extension install.'
    }
    Test-Case 'Monitor reuses healthy source extension' {
        $global:ContosoNetworkMock.Extensions += [pscustomobject]@{Name='AzureNetworkWatcherExtension';Publisher='Microsoft.Azure.NetworkWatcher';ExtensionType='NetworkWatcherAgentWindows';ProvisioningState='Succeeded'}
        Invoke-Operator 'deploy-connection-monitor' @{Execute=$true;Confirmation='DEPLOY CONNECTION MONITOR sre-network-demo-connection-monitor'}
        $deployment = @($global:ContosoNetworkMock.Calls | Where-Object { $_.Name -eq 'New-AzResourceGroupDeployment' -and -not $_.Parameters.ContainsKey('WhatIf') })[0]
        Assert-Test (-not $deployment.Parameters.installSourceAgent) 'Healthy extension would be replaced.'
    }
    Test-Case 'Monitor rejects unhealthy source extension' {
        $global:ContosoNetworkMock.Extensions += [pscustomobject]@{Name='AzureNetworkWatcherExtension';Publisher='Microsoft.Azure.NetworkWatcher';ExtensionType='NetworkWatcherAgentWindows';ProvisioningState='Failed'}
        Assert-Throws { Invoke-Operator 'deploy-connection-monitor' @{Execute=$true;Confirmation='DEPLOY CONNECTION MONITOR sre-network-demo-connection-monitor'} } 'extension state'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Unhealthy extension was changed.'
    }
    Test-Case 'Monitor rejects conflicting extension name' {
        $global:ContosoNetworkMock.Extensions += [pscustomobject]@{Name='AzureNetworkWatcherExtension';Publisher='Contoso';ExtensionType='DifferentExtension';ProvisioningState='Succeeded'}
        Assert-Throws { Invoke-Operator 'deploy-connection-monitor' @{Execute=$true;Confirmation='DEPLOY CONNECTION MONITOR sre-network-demo-connection-monitor'} } 'name conflict'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Conflicting extension was changed.'
    }
    Test-Case 'Monitor wrong confirmation allows preview but no actual deployment' {
        Assert-Throws { Invoke-Operator 'deploy-connection-monitor' @{Execute=$true;Confirmation='NOT APPROVED'} } 'Confirmation did not'
        Assert-Test (@($global:ContosoNetworkMock.Calls | Where-Object {
            $_.Name -eq 'New-AzResourceGroupDeployment' -and -not $_.Parameters.ContainsKey('WhatIf')
        }).Count -eq 0) 'Monitor deployed without approval.'
    }
    Test-Case 'Monitor rejects stale endpoint IP' {
        $global:ContosoNetworkMock.EndpointIp = '10.10.1.5'
        Assert-Throws { Invoke-Operator 'deploy-connection-monitor' @{Execute=$true;Confirmation='DEPLOY CONNECTION MONITOR sre-network-demo-connection-monitor'} } 'private IP differs'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Stale endpoint allowed mutation.'
    }
    Test-Case 'Cleanup rejects missing ownership tags' {
        $global:ContosoNetworkMock.Tags = @{}
        Assert-Throws { Invoke-Operator 'cleanup' @{Execute=$true;Confirmation='NOT APPROVED'} } 'ownership tags'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Missing tags allowed deletion.'
    }
    Test-Case 'Cleanup rejects unrelated flow-log target' {
        $global:ContosoNetworkMock.FlowTarget = "$groupId/providers/Microsoft.Network/networkSecurityGroups/unrelated"
        Assert-Throws { Invoke-Operator 'cleanup' @{Execute=$true;Confirmation='NOT APPROVED'} } 'does not target a VNet'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Wrong target allowed deletion.'
    }
    Test-Case 'Cleanup requires exact separate confirmation' {
        Assert-Throws { Invoke-Operator 'cleanup' @{Execute=$true;Confirmation='NOT APPROVED'} } 'Confirmation did not'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'Wrong cleanup confirmation allowed deletion.'
    }
    Test-Case 'Cleanup rejects role assignment outside demo scope' {
        $invalid = $fixture | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $invalid.roleAssignmentIds = @("$watcherId/providers/Microsoft.Authorization/roleAssignments/$([guid]::NewGuid())")
        $invalid | ConvertTo-Json -Depth 20 | Set-Content $contextPath
        Assert-Throws { Invoke-Operator 'cleanup' @{Execute=$true;Confirmation='NOT APPROVED'} } 'outside the demo group'
        Assert-Test (@(Get-Mutations).Count -eq 0) 'External role assignment allowed deletion.'
    }
    Test-Case 'Cleanup preserves shared watcher, siblings and providers' {
        Invoke-Operator 'cleanup' @{Execute=$true;Confirmation="DELETE $($fixture.resourceGroupName) AND FLOW LOGS $($fixture.flowLogNames -join ',')"}
        Assert-Test (@(Get-Mutations).Count -eq 3) 'Expected only two flow logs and dedicated resource group deletion.'
    }
    Write-Host "PASS: $passed mocked operator cases; no Azure authentication or resources used."
} finally {
    foreach ($name in $mockNames) { Remove-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue }
    Remove-Variable -Name ContosoNetworkMock,ContosoNetworkClock -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
