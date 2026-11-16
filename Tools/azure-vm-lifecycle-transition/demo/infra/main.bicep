// VM lifecycle lab: an estate of VMs on an End of Life series, plus a pilot
// resource group, for testing the Azure SRE Agent configuration end to end.
// Deploy with scripts/Deploy-Lab.ps1. Every VM uses the same deployable size.
targetScope = 'subscription'

@description('Region for the lab. Use one where Test-LabFeasibility.ps1 shows the lab size is offered and allowed.')
param location string = 'canadacentral'

@description('Prefix for resource group and resource names.')
param prefix string = 'contoso-vmlt'

@description('Admin user for the Linux VMs. The VMs have no public IP; nobody needs to sign in.')
param adminUsername string = 'labadmin'

@description('SSH public key for the Linux VMs.')
param sshPublicKey string

@description('Optional. VM size for every lab VM and scale set. Empty uses vmSize from lab-design.json.')
param vmSize string = ''

@description('Daily auto-shutdown time as HHmm. Empty disables auto-shutdown. Scale sets aren\'t covered.')
param autoShutdownTime string = '1900'

param autoShutdownTimeZone string = 'Eastern Standard Time'

param tags object = {
  Environment: 'Lab'
  CostCenter: 'Lab'
  Purpose: 'vm-lifecycle-lab'
}

var design = loadJsonContent('../lab-design.json')
var size = empty(vmSize) ? design.vmSize : vmSize
var cpuLoad = loadTextContent('../cloud-init/cpu-load.yaml')
var estateVms = filter(design.vms, vm => vm.resourceGroup == 'estate')
var pilotVms = filter(design.vms, vm => vm.resourceGroup == 'pilot')

resource estateRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${prefix}-estate'
  location: location
  tags: tags
}

resource pilotRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${prefix}-pilot'
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  scope: estateRg
  name: 'vmlt-monitoring'
  params: {
    location: location
    prefix: prefix
    tags: tags
  }
}

module estateNetwork 'modules/network.bicep' = {
  scope: estateRg
  name: 'vmlt-estate-network'
  params: {
    location: location
    name: 'vnet-${prefix}-estate'
    addressPrefix: '10.60.0.0/24'
    tags: tags
  }
}

module pilotNetwork 'modules/network.bicep' = {
  scope: pilotRg
  name: 'vmlt-pilot-network'
  params: {
    location: location
    name: 'vnet-${prefix}-pilot'
    addressPrefix: '10.61.0.0/24'
    tags: tags
  }
}

module estateVmDeployments 'modules/vm.bicep' = [
  for vm in estateVms: {
    scope: estateRg
    name: 'vmlt-${vm.name}'
    params: {
      location: location
      name: vm.name
      size: size
      subnetId: estateNetwork.outputs.subnetId
      generation: vm.generation
      trustedLaunch: vm.trustedLaunch
      acceleratedNetworking: vm.acceleratedNetworking
      ipForwarding: vm.ipForwarding
      customData: vm.cpuLoad ? cpuLoad : ''
      adminUsername: adminUsername
      sshPublicKey: sshPublicKey
      dataCollectionRuleId: monitoring.outputs.dataCollectionRuleId
      autoShutdownTime: autoShutdownTime
      autoShutdownTimeZone: autoShutdownTimeZone
      tags: union(tags, vm.tags)
    }
  }
]

module pilotVmDeployments 'modules/vm.bicep' = [
  for vm in pilotVms: {
    scope: pilotRg
    name: 'vmlt-${vm.name}'
    params: {
      location: location
      name: vm.name
      size: size
      subnetId: pilotNetwork.outputs.subnetId
      generation: vm.generation
      trustedLaunch: vm.trustedLaunch
      acceleratedNetworking: vm.acceleratedNetworking
      ipForwarding: vm.ipForwarding
      customData: vm.cpuLoad ? cpuLoad : ''
      adminUsername: adminUsername
      sshPublicKey: sshPublicKey
      dataCollectionRuleId: monitoring.outputs.dataCollectionRuleId
      autoShutdownTime: autoShutdownTime
      autoShutdownTimeZone: autoShutdownTimeZone
      tags: union(tags, vm.tags)
    }
  }
]

module scaleSetDeployments 'modules/vmss.bicep' = [
  for scaleSet in design.scaleSets: {
    scope: estateRg
    name: 'vmlt-${scaleSet.name}'
    params: {
      location: location
      name: scaleSet.name
      size: size
      capacity: scaleSet.capacity
      subnetId: estateNetwork.outputs.subnetId
      adminUsername: adminUsername
      sshPublicKey: sshPublicKey
      dataCollectionRuleId: monitoring.outputs.dataCollectionRuleId
      tags: union(tags, scaleSet.tags)
    }
  }
]

output estateResourceGroup string = estateRg.name
output pilotResourceGroup string = pilotRg.name
output workspaceId string = monitoring.outputs.workspaceId
