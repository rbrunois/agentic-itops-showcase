// SHARED RG: hub VNet + Bastion, UAMI, DNS zones, Key Vault, and DCR wired
// to the existing SRE-Agent LAW.
targetScope = 'resourceGroup'

param location string
param tags     object

param hubVnetCidr       string
param bastionSubnetCidr string
param prdDnsZoneName    string
param nprdDnsZoneName   string

@description('Existing LAW resource ID to reuse. Empty = create new LAW here.')
param existingLawResourceId string

var uniq = uniqueString(subscription().id, resourceGroup().id)

// ---------- User-assigned managed identity (shared by all VMs) ----------
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name:     'id-sreagent-iisapp-shared'
  location: location
  tags:     tags
}

// ---------- Log Analytics Workspace (reuse-or-create) ----------
resource newLaw 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (empty(existingLawResourceId)) {
  name:     'law-sreagent-iisapp-${uniq}'
  location: location
  tags:     tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
  }
}

var lawId = empty(existingLawResourceId) ? newLaw.id : existingLawResourceId

// ---------- Data Collection Rule ----------
resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name:     'dcr-sreagent-iisapp-vms'
  location: location
  tags:     tags
  properties: {
    dataSources: {
      windowsEventLogs: [
        {
          name: 'sysAppSec'
          streams: [ 'Microsoft-Event' ]
          xPathQueries: [
            'System!*[System[(Level=1 or Level=2 or Level=3 or Level=4)]]'
            'Application!*[System[(Level=1 or Level=2 or Level=3 or Level=4)]]'
            'Security!*[System[(EventID=4624 or EventID=4634 or EventID=4688)]]'
          ]
        }
      ]
      performanceCounters: [
        {
          name: 'perfCounters'
          streams: [ 'Microsoft-Perf' ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available MBytes'
            '\\LogicalDisk(_Total)\\% Free Space'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'primary'
          workspaceResourceId: lawId
        }
      ]
    }
    dataFlows: [
      { streams: [ 'Microsoft-Event' ], destinations: [ 'primary' ] }
      { streams: [ 'Microsoft-Perf' ],  destinations: [ 'primary' ] }
    ]
  }
}

// ---------- Hub VNet + Bastion ----------
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name:     'vnet-shared-01'
  location: location
  tags:     tags
  properties: {
    addressSpace: { addressPrefixes: [ hubVnetCidr ] }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: { addressPrefix: bastionSubnetCidr }
      }
    ]
  }
}

resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name:     'pip-bastion-01'
  location: location
  tags:     tags
  sku:      { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-01-01' = {
  name:     'bas-sreagent-iisapp-01'
  location: location
  tags:     tags
  sku:      { name: 'Standard' }
  properties: {
    enableTunneling: true
    enableIpConnect: true
    enableShareableLink: true
    scaleUnits: 2
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet:          { id: '${hubVnet.id}/subnets/AzureBastionSubnet' }
          publicIPAddress: { id: bastionPip.id }
        }
      }
    ]
  }
}

// ---------- Private DNS zones ----------
resource prdZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name:     prdDnsZoneName
  location: 'global'
  tags:     tags
}

resource nprdZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name:     nprdDnsZoneName
  location: 'global'
  tags:     tags
}

// Also link both zones to the HUB VNet — so the workstation user (via Bastion) can resolve either FQDN.
resource prdZoneHubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent:   prdZone
  name:     'link-hub'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: hubVnet.id }
  }
}

resource nprdZoneHubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent:   nprdZone
  name:     'link-hub'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: hubVnet.id }
  }
}

// ---------- Key Vault (holds VM admin password so the deploy is idempotent) ----------
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name:     'kv-sre-${uniq}'
  location: location
  tags:     tags
  properties: {
    tenantId: subscription().tenantId
    sku:      { name: 'standard', family: 'A' }
    enableRbacAuthorization: true
    enabledForDeployment:    true
    enableSoftDelete:        true
    softDeleteRetentionInDays: 7
    enablePurgeProtection:   null
    publicNetworkAccess:     'Enabled'
  }
}

// ---------- Outputs ----------
output uamiResourceId  string = uami.id
output uamiPrincipalId string = uami.properties.principalId
output uamiClientId    string = uami.properties.clientId
output lawResourceId   string = lawId
output dcrId           string = dcr.id
output hubVnetId       string = hubVnet.id
output hubVnetName     string = hubVnet.name
output bastionName     string = bastion.name
output keyVaultName    string = kv.name
