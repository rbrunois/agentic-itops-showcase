// Virtual network for lab VMs. No public IPs are created.
param location string
param name string
param addressPrefix string
param tags object

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${name}'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-lab'
        properties: {
          addressPrefix: addressPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          // New subnets are private by default. The Azure Monitor agent needs
          // outbound access to send VM insights data, and the VMs have no public IP.
          defaultOutboundAccess: true
        }
      }
    ]
  }
}

output subnetId string = vnet.properties.subnets[0].id
