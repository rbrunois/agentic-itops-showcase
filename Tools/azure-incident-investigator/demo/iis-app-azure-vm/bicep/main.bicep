// Subscription-scope orchestrator: creates 3 RGs + all lab infrastructure.
//
// On-VM configuration scripts (Configure-WebTier/DbTier/Workstation) are passed
// in as base64-encoded strings by Deploy-Lab.ps1 (which composes them from
// scripts/*.ps1 plus embedded artifacts). CSE runs them inline — no storage
// account, no fileUris. This avoids the tenant policy that forces
// publicNetworkAccess=Disabled on storage accounts.
targetScope = 'subscription'

param location string
param tags     object

param sharedRgName string
param prdRgName    string
param nprdRgName   string

@description('Reuse an existing Log Analytics workspace resource ID. Leave empty to create one in the SHARED RG.')
param existingLawResourceId string = ''

// Networking
param hubVnetCidr       string
param bastionSubnetCidr string
param prdVnetCidr       string
param prdWebSubnetCidr  string
param prdDbSubnetCidr   string
param prdWksSubnetCidr  string
param nprdVnetCidr      string
param nprdWebSubnetCidr string
param nprdDbSubnetCidr  string
param nprdWksSubnetCidr string

// DNS
param prdDnsZoneName  string
param nprdDnsZoneName string

// Compute
param vmAdminUsername string
@secure()
param vmAdminPassword string
param webVmSize       string
param dbVmSize        string
param wksVmSize       string

// Auto-shutdown
param autoShutdownTime     string
param autoShutdownTimeZone string

// Inline scripts (plain PowerShell text). Composed by Deploy-Lab.ps1.
@secure()
param webTierScript     string
@secure()
param dbTierScript      string
@secure()
param workstationScript string

// ---------- Resource Groups ----------
resource sharedRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name:     sharedRgName
  location: location
  tags:     union(tags, { EnvRole: 'Shared' })
}

resource prdRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name:     prdRgName
  location: location
  tags:     union(tags, { EnvRole: 'Prod' })
}

resource nprdRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name:     nprdRgName
  location: location
  tags:     union(tags, { EnvRole: 'NonProd' })
}

// ---------- SHARED module ----------
module shared 'modules/shared.bicep' = {
  name:  'shared-deploy'
  scope: sharedRg
  params: {
    location:               location
    tags:                   tags
    hubVnetCidr:            hubVnetCidr
    bastionSubnetCidr:      bastionSubnetCidr
    prdDnsZoneName:         prdDnsZoneName
    nprdDnsZoneName:        nprdDnsZoneName
    existingLawResourceId:  existingLawResourceId
  }
}

// ---------- PRD environment ----------
module prd 'modules/environment.bicep' = {
  name:  'prd-deploy'
  scope: prdRg
  params: {
    location:              location
    tags:                  union(tags, { EnvRole: 'Prod' })
    envPrefix:             'PRD'
    vnetCidr:              prdVnetCidr
    webSubnetCidr:         prdWebSubnetCidr
    dbSubnetCidr:          prdDbSubnetCidr
    wksSubnetCidr:         prdWksSubnetCidr
    hubVnetId:             shared.outputs.hubVnetId
    hubVnetName:           shared.outputs.hubVnetName
    hubRgName:             sharedRgName
    hubVnetCidr:           hubVnetCidr
    dnsZoneName:           prdDnsZoneName
    dnsZoneRgName:         sharedRgName
    dcrId:                 shared.outputs.dcrId
    uamiResourceId:        shared.outputs.uamiResourceId
    vmAdminUsername:       vmAdminUsername
    vmAdminPassword:       vmAdminPassword
    webVmSize:             webVmSize
    dbVmSize:              dbVmSize
    wksVmSize:             wksVmSize
    autoShutdownTime:      autoShutdownTime
    autoShutdownTimeZone:  autoShutdownTimeZone
    webTierScript:      webTierScript
    dbTierScript:       dbTierScript
    workstationScript:  workstationScript
  }
}

// ---------- NPRD environment ----------
module nprd 'modules/environment.bicep' = {
  name:  'nprd-deploy'
  scope: nprdRg
  params: {
    location:              location
    tags:                  union(tags, { EnvRole: 'NonProd' })
    envPrefix:             'NPRD'
    vnetCidr:              nprdVnetCidr
    webSubnetCidr:         nprdWebSubnetCidr
    dbSubnetCidr:          nprdDbSubnetCidr
    wksSubnetCidr:         nprdWksSubnetCidr
    hubVnetId:             shared.outputs.hubVnetId
    hubVnetName:           shared.outputs.hubVnetName
    hubRgName:             sharedRgName
    hubVnetCidr:           hubVnetCidr
    dnsZoneName:           nprdDnsZoneName
    dnsZoneRgName:         sharedRgName
    dcrId:                 shared.outputs.dcrId
    uamiResourceId:        shared.outputs.uamiResourceId
    vmAdminUsername:       vmAdminUsername
    vmAdminPassword:       vmAdminPassword
    webVmSize:             webVmSize
    dbVmSize:              dbVmSize
    wksVmSize:             wksVmSize
    autoShutdownTime:      autoShutdownTime
    autoShutdownTimeZone:  autoShutdownTimeZone
    webTierScript:      webTierScript
    dbTierScript:       dbTierScript
    workstationScript:  workstationScript
  }
}

// ---------- Outputs ----------
output sharedRgName        string = sharedRgName
output prdRgName           string = prdRgName
output nprdRgName          string = nprdRgName
output bastionName         string = shared.outputs.bastionName
output prdWebPrivateIp     string = prd.outputs.webPrivateIp
output prdSqlPrivateIp     string = prd.outputs.sqlPrivateIp
output prdWksPrivateIp     string = prd.outputs.wksPrivateIp
output nprdWebPrivateIp    string = nprd.outputs.webPrivateIp
output nprdSqlPrivateIp    string = nprd.outputs.sqlPrivateIp
output nprdWksPrivateIp    string = nprd.outputs.wksPrivateIp
output lawResourceId       string = shared.outputs.lawResourceId
output keyVaultName        string = shared.outputs.keyVaultName
