// Per-environment module: VNet + NSGs + 3 VMs (Web/SQL/Workstation) with UAMI
// + AMA + inline CSE scripts, hub peering, DNS zone link, A records, per-VM
// auto-shutdown.
targetScope = 'resourceGroup'

param location string
param tags     object

@allowed([ 'PRD', 'NPRD' ])
param envPrefix string

param vnetCidr      string
param webSubnetCidr string
param dbSubnetCidr  string
param wksSubnetCidr string

param hubVnetId    string
param hubVnetName  string
param hubRgName    string
param hubVnetCidr  string

param dnsZoneName   string
param dnsZoneRgName string

param dcrId         string
param uamiResourceId string

param vmAdminUsername string
@secure()
param vmAdminPassword string
param webVmSize string
param dbVmSize  string
param wksVmSize string

param autoShutdownTime     string
param autoShutdownTimeZone string

@secure()
param webTierScript     string
@secure()
param dbTierScript      string
@secure()
param workstationScript string

// ---------- NSG ----------
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name:     'nsg-${envPrefix}-01'
  location: location
  tags:     tags
  properties: {
    securityRules: [
      {
        name: 'AllowVnetInBound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowBastionInBound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: [ '3389', '22' ]
          sourceAddressPrefix: hubVnetCidr
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'DenyInternetInBound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ---------- VNet ----------
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name:     'vnet-${envPrefix}-01'
  location: location
  tags:     tags
  properties: {
    addressSpace: { addressPrefixes: [ vnetCidr ] }
    subnets: [
      { name: 'snet-web', properties: { addressPrefix: webSubnetCidr, networkSecurityGroup: { id: nsg.id } } }
      { name: 'snet-db',  properties: { addressPrefix: dbSubnetCidr,  networkSecurityGroup: { id: nsg.id } } }
      { name: 'snet-wks', properties: { addressPrefix: wksSubnetCidr, networkSecurityGroup: { id: nsg.id } } }
    ]
  }
}

// ---------- Peering: spoke -> hub ----------
resource peerToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: vnet
  name:   'peer-to-hub'
  properties: {
    remoteVirtualNetwork:      { id: hubVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic:     true
    allowGatewayTransit:       false
    useRemoteGateways:         false
  }
}

module peerFromHub 'peering-hub.bicep' = {
  name:  'peer-hub-to-${envPrefix}'
  scope: resourceGroup(hubRgName)
  params: {
    hubVnetName:   hubVnetName
    spokeName:     envPrefix
    spokeVnetId:   vnet.id
  }
}

// ---------- Link private DNS zone to this spoke VNet ----------
module dnsLink 'dns-link.bicep' = {
  name:  'dnslink-${envPrefix}'
  scope: resourceGroup(dnsZoneRgName)
  params: {
    zoneName: dnsZoneName
    linkName: 'link-${envPrefix}'
    vnetId:   vnet.id
  }
}

// ---------- VMs ----------
module webVm 'vm-windows.bicep' = {
  name: 'vm-${envPrefix}-web'
  params: {
    location:              location
    tags:                  tags
    vmName:                '${envPrefix}-SRVIIS01'
    subnetId:              '${vnet.id}/subnets/snet-web'
    vmSize:                webVmSize
    imagePublisher:        'MicrosoftWindowsServer'
    imageOffer:            'WindowsServer'
    imageSku:              '2022-datacenter-azure-edition'
    adminUsername:         vmAdminUsername
    adminPassword:         vmAdminPassword
    uamiResourceId:        uamiResourceId
    dcrId:                 dcrId
    autoShutdownTime:      autoShutdownTime
    autoShutdownTimeZone:  autoShutdownTimeZone
    inlineScript:          webTierScript
  }
}

module sqlVm 'vm-sql.bicep' = {
  name: 'vm-${envPrefix}-sql'
  params: {
    location:              location
    tags:                  tags
    vmName:                '${envPrefix}-SRVSQL01'
    subnetId:              '${vnet.id}/subnets/snet-db'
    vmSize:                dbVmSize
    adminUsername:         vmAdminUsername
    adminPassword:         vmAdminPassword
    uamiResourceId:        uamiResourceId
    dcrId:                 dcrId
    autoShutdownTime:      autoShutdownTime
    autoShutdownTimeZone:  autoShutdownTimeZone
    inlineScript:          dbTierScript
  }
}

module wksVm 'vm-windows.bicep' = {
  name: 'vm-${envPrefix}-wks'
  params: {
    location:              location
    tags:                  tags
    vmName:                '${envPrefix}-SRVWKS01'
    subnetId:              '${vnet.id}/subnets/snet-wks'
    vmSize:                wksVmSize
    imagePublisher:        'MicrosoftWindowsServer'
    imageOffer:            'WindowsServer'
    imageSku:              '2022-datacenter-azure-edition'
    adminUsername:         vmAdminUsername
    adminPassword:         vmAdminPassword
    uamiResourceId:        uamiResourceId
    dcrId:                 dcrId
    autoShutdownTime:      autoShutdownTime
    autoShutdownTimeZone:  autoShutdownTimeZone
    inlineScript:          workstationScript
  }
}

// ---------- DNS A records ----------
module dnsRecords 'dns-records.bicep' = {
  name:  'dnsrec-${envPrefix}'
  scope: resourceGroup(dnsZoneRgName)
  params: {
    zoneName: dnsZoneName
    records: [
      { name: 'app1', ipv4: webVm.outputs.privateIp }
      { name: 'sql1', ipv4: sqlVm.outputs.privateIp }
      { name: 'wks1', ipv4: wksVm.outputs.privateIp }
    ]
  }
}

// ---------- Outputs ----------
output webPrivateIp string = webVm.outputs.privateIp
output sqlPrivateIp string = sqlVm.outputs.privateIp
output wksPrivateIp string = wksVm.outputs.privateIp
