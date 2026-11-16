// Log Analytics workspace and VM insights data collection rule for the lab.
param location string
param prefix string
param tags object

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${prefix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource vmInsights 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'MSVMI-${prefix}'
  location: location
  tags: tags
  properties: {
    description: 'VM insights performance counters for the VM lifecycle lab'
    dataSources: {
      performanceCounters: [
        {
          name: 'VMInsightsPerfCounters'
          streams: [
            'Microsoft-InsightsMetrics'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\VmInsights\\DetailedMetrics'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'vminsights'
          workspaceResourceId: workspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-InsightsMetrics'
        ]
        destinations: [
          'vminsights'
        ]
      }
    ]
  }
}

output workspaceId string = workspace.id
output dataCollectionRuleId string = vmInsights.id
