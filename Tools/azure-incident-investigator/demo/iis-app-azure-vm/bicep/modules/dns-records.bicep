// Creates A records inside an existing private DNS zone.
targetScope = 'resourceGroup'

param zoneName string
param records array   // [ { name: 'app1', ipv4: '10.10.1.4' }, ... ]

resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: zoneName
}

resource a 'Microsoft.Network/privateDnsZones/A@2024-06-01' = [for r in records: {
  parent: zone
  name:   r.name
  properties: {
    ttl:      300
    aRecords: [ { ipv4Address: r.ipv4 } ]
  }
}]
