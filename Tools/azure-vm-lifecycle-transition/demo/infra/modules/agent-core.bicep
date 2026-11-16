// Azure SRE Agent for the VM lifecycle lab: agent, managed identity, Log
// Analytics, Application Insights, and read-only roles on the lab resource
// groups. Adapted from microsoft/sre-agent sreagent-templates/bicep/agent-core.bicep
// (MIT License), commit 6c6c48b4ff558f6b6858e2eb6a3a34198f3f6bc0.
param agentName string
param location string
param targetResourceGroups array
param monthlyAgentUnitLimit int
param tags object

@description('Log Analytics workspace to connect to the agent. Empty means no connector.')
param logAnalyticsWorkspaceId string = ''

var monitoringReaderRole = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
var sreAgentAdministratorRole = 'e79298df-d852-4c6d-84f9-5d13249d1e55'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${agentName}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${agentName}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'SreAgent'
    WorkspaceResourceId: workspace.id
  }
}

#disable-next-line BCP073
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-${agentName}'
  location: location
  tags: tags
  properties: {
    isolationScope: 'Regional'
  }
}

module identityTargetRoles 'agent-target-roles.bicep' = [
  for (group, i) in targetResourceGroups: {
    name: 'vmlt-agent-uami-roles-${i}'
    scope: resourceGroup(group)
    params: {
      principalId: identity.properties.principalId
    }
  }
]

resource monitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, identity.id, monitoringReaderRole)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRole)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

#disable-next-line BCP081
resource agent 'Microsoft.App/agents@2025-05-01-preview' = {
  name: agentName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    knowledgeGraphConfiguration: {
      identity: identity.id
      managedResources: [for group in targetResourceGroups: subscriptionResourceId('Microsoft.Resources/resourceGroups', group)]
    }
    actionConfiguration: {
      accessLevel: 'Low'
      identity: identity.id
      mode: 'Review'
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsights.properties.AppId
        connectionString: appInsights.properties.ConnectionString
        applicationInsightsResourceId: appInsights.id
      }
    }
    upgradeChannel: 'Preview'
    monthlyAgentUnitLimit: monthlyAgentUnitLimit
    defaultModel: {
      provider: 'MicrosoftFoundry'
      name: 'Automatic'
    }
    experimentalSettings: {
      EnableWorkspaceTools: true
      EnableHttpTriggers: true
      EnableV2AgentLoop: true
    }
  }
  dependsOn: [
    identityTargetRoles
    monitoringReader
  ]
}

// The agent uses its system-assigned identity for connector queries.
module systemTargetRoles 'agent-target-roles.bicep' = [
  for (group, i) in targetResourceGroups: {
    name: 'vmlt-agent-system-roles-${i}'
    scope: resourceGroup(group)
    params: {
      principalId: agent.identity.principalId
    }
  }
]

resource deployerAdministrator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(agent.id, deployer().objectId, sreAgentAdministratorRole)
  scope: agent
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sreAgentAdministratorRole)
    principalId: deployer().objectId
    principalType: 'User'
  }
}

// A Log Analytics connector gives the agent preconfigured access to the lab
// workspace. Live reports in the lab couldn't use this connector type. The
// system-assigned identity already has Log Analytics Reader on the target
// resource groups.
#disable-next-line BCP081
resource logAnalyticsConnector 'Microsoft.App/agents/connectors@2025-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  parent: agent
  name: 'lab-log-analytics'
  properties: {
    dataConnectorType: 'LogAnalytics'
    dataSource: logAnalyticsWorkspaceId
    extendedProperties: {
      armResourceId: logAnalyticsWorkspaceId
      resource: {
        name: last(split(logAnalyticsWorkspaceId, '/'))
      }
    }
    identity: 'system'
  }
  dependsOn: [
    systemTargetRoles
  ]
}

output agentId string = agent.id
output agentName string = agent.name
output identityPrincipalId string = identity.properties.principalId
output systemPrincipalId string = agent.identity.principalId
