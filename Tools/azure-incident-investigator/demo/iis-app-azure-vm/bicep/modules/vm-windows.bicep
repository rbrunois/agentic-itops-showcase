// Generic Windows VM with UAMI + AMA + DCR + auto-shutdown + inline CSE.
targetScope = 'resourceGroup'

param location string
param tags     object

param vmName          string
param subnetId        string
param vmSize          string
param imagePublisher  string
param imageOffer      string
param imageSku        string
param adminUsername   string
@secure()
param adminPassword   string

param uamiResourceId string
param dcrId          string

param autoShutdownTime     string
param autoShutdownTimeZone string

@secure()
@description('Plain PowerShell script content, up to 1 MB, run via RunCommand v2. Empty = skip.')
param inlineScript string = ''

// ---------- NIC ----------
resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name:     'nic-${vmName}'
  location: location
  tags:     tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: subnetId }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// ---------- VM ----------
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name:     vmName
  location: location
  tags:     tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiResourceId}': {}
    }
  }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer:     imageOffer
        sku:       imageSku
        version:   'latest'
      }
      osDisk: {
        name:         'osdisk-${vmName}'
        createOption: 'FromImage'
        managedDisk:  { storageAccountType: 'Premium_LRS' }
      }
    }
    osProfile: {
      computerName:  take(vmName, 15)
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent:       true
        enableAutomaticUpdates: false
      }
    }
    networkProfile: {
      networkInterfaces: [ { id: nic.id } ]
    }
    diagnosticsProfile: {
      bootDiagnostics: { enabled: true }
    }
  }
}

// ---------- Auto-shutdown ----------
resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name:     'shutdown-computevm-${vmName}'
  location: location
  tags:     tags
  properties: {
    status:           'Enabled'
    taskType:         'ComputeVmShutdownTask'
    dailyRecurrence:  { time: autoShutdownTime }
    timeZoneId:       autoShutdownTimeZone
    targetResourceId: vm.id
    notificationSettings: { status: 'Disabled', timeInMinutes: 30 }
  }
}

// ---------- Azure Monitor Agent + DCR ----------
resource ama 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent:   vm
  name:     'AzureMonitorWindowsAgent'
  location: location
  properties: {
    publisher:               'Microsoft.Azure.Monitor'
    type:                    'AzureMonitorWindowsAgent'
    typeHandlerVersion:      '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade:  true
    settings: {
      authentication: {
        managedIdentity: {
          'identifier-name':  'mi_res_id'
          'identifier-value': uamiResourceId
        }
      }
    }
  }
}

resource dcra 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name:  'dcra-${vmName}'
  scope: vm
  properties: {
    dataCollectionRuleId: dcrId
    description: 'Associate DCR to send Windows event/perf logs to LAW'
  }
  dependsOn: [ ama ]
}

// ---------- Run Command v2 (inline PowerShell, up to 1 MB) ----------
resource runCommand 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = if (!empty(inlineScript)) {
  parent:   vm
  name:     'ConfigureVM'
  location: location
  properties: {
    source: { script: inlineScript }
    asyncExecution: false
    timeoutInSeconds: 1800
    treatFailureAsDeploymentFailure: true
  }
  dependsOn: [ ama ]
}

output vmId       string = vm.id
output privateIp  string = nic.properties.ipConfigurations[0].properties.privateIPAddress
