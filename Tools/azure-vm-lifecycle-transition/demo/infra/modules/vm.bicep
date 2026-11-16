// One lab VM: network interface, Ubuntu VM, Azure Monitor agent, VM insights
// association, and an optional daily auto-shutdown.
param location string
param name string
param size string
param subnetId string

@allowed([
  'V1'
  'V2'
])
param generation string

param trustedLaunch bool = false
param acceleratedNetworking bool
param ipForwarding bool
param customData string = ''
param adminUsername string
param sshPublicKey string
param dataCollectionRuleId string

@description('Daily auto-shutdown time as HHmm. Empty disables auto-shutdown.')
param autoShutdownTime string = ''
param autoShutdownTimeZone string = 'Eastern Standard Time'
param tags object

var imageSku = generation == 'V1' ? '22_04-lts' : '22_04-lts-gen2'

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${name}'
  location: location
  tags: tags
  properties: {
    enableAcceleratedNetworking: acceleratedNetworking
    enableIPForwarding: ipForwarding
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: size
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: imageSku
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-${name}'
        createOption: 'FromImage'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: name
      adminUsername: adminUsername
      customData: empty(customData) ? null : base64(customData)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    securityProfile: trustedLaunch
      ? {
          securityType: 'TrustedLaunch'
          uefiSettings: {
            secureBootEnabled: true
            vTpmEnabled: true
          }
        }
      : null
  }
}

resource monitorAgent 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'AzureMonitorLinuxAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

resource vmInsightsAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'vminsights-dcr-association'
  scope: vm
  properties: {
    description: 'VM insights for the VM lifecycle lab'
    dataCollectionRuleId: dataCollectionRuleId
  }
}

resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (!empty(autoShutdownTime)) {
  name: 'shutdown-computevm-${name}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: autoShutdownTimeZone
    targetResourceId: vm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

output id string = vm.id
