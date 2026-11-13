// Reverse peering: hub-side of the peering pair. Deployed to the SHARED RG.
targetScope = 'resourceGroup'

param hubVnetName string
param spokeName   string
param spokeVnetId string

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: hubVnetName
}

resource peer 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: hubVnet
  name:   'peer-to-${spokeName}'
  properties: {
    remoteVirtualNetwork:      { id: spokeVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic:     true
    allowGatewayTransit:       false
    useRemoteGateways:         false
  }
}
