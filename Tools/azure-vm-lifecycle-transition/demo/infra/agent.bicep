// Azure SRE Agent for the VM lifecycle lab, plus the subscription-scope read
// access that quota, VM size, and Azure Policy checks need. Reader on resource
// groups doesn't cover those subscription-level APIs. Deploy after main.bicep.
targetScope = 'subscription'

@description('Agent name: lowercase letters, digits, and hyphens.')
param agentName string = 'vmlt-lab-${take(uniqueString(subscription().id), 5)}'

@description('Azure SRE Agent region. It must be supported for the subscription and allowed by policy.')
param location string = 'canadacentral'

param agentResourceGroupName string = 'rg-contoso-vmlt-agent'

@description('Resource groups the agent can read. They must already exist.')
param targetResourceGroups array = [
  'rg-contoso-vmlt-estate'
  'rg-contoso-vmlt-pilot'
]

@description('Monthly active-flow limit in Azure Agent Units (500 to 1,000,000).')
@minValue(500)
@maxValue(1000000)
param monthlyAgentUnitLimit int = 100000

@description('Log Analytics workspace with the lab VM insights data, connected to the agent. Empty means no connector.')
param logAnalyticsWorkspaceId string = ''

param tags object = {
  Environment: 'Lab'
  CostCenter: 'Lab'
  Purpose: 'vm-lifecycle-lab'
}

resource agentRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: agentResourceGroupName
  location: location
  tags: tags
}

resource landingReader 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'vm-lifecycle-landing-reader')
  properties: {
    roleName: 'VM lifecycle landing reader (${subscription().subscriptionId})'
    description: 'Reads VM quota usage, VM sizes, and Azure Policy at subscription scope for VM lifecycle landing checks. No write access.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Compute/locations/usages/read'
          'Microsoft.Compute/skus/read'
          'Microsoft.Authorization/policyAssignments/read'
          'Microsoft.Authorization/policyDefinitions/read'
          'Microsoft.Authorization/policySetDefinitions/read'
          'Microsoft.Authorization/policyExemptions/read'
          'Microsoft.Resources/subscriptions/read'
        ]
        notActions: []
      }
    ]
    assignableScopes: [
      subscription().id
    ]
  }
}

module agentCore 'modules/agent-core.bicep' = {
  scope: agentRg
  name: 'vmlt-agent-core'
  params: {
    agentName: agentName
    location: location
    targetResourceGroups: targetResourceGroups
    monthlyAgentUnitLimit: monthlyAgentUnitLimit
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    tags: tags
  }
}

resource identityLanding 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, agentName, 'landing-reader-uami')
  properties: {
    roleDefinitionId: landingReader.id
    principalId: agentCore.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource systemLanding 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, agentName, 'landing-reader-system')
  properties: {
    roleDefinitionId: landingReader.id
    principalId: agentCore.outputs.systemPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output agentId string = agentCore.outputs.agentId
output agentName string = agentCore.outputs.agentName
output agentResourceGroup string = agentRg.name
