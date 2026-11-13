@description('Existing Container Apps environment in this deployment resource group.')
@minLength(1)
param environmentName string

@description('Explicitly selected dedicated demo Container App name.')
@minLength(1)
@maxLength(32)
param appName string

@description('Operator-selected demo image. Pin by digest (image@sha256:...) for any shared or repeated rehearsal; mutable tags can change between revisions. Private ACR images require registryName and registryIdentityName.')
@minLength(1)
param image string

@description('Unique revision suffix; lowercase letters, digits and hyphens, beginning with a letter.')
@minLength(1)
@maxLength(30)
param revisionSuffix string

@description('Must match the existing Container Apps environment region.')
param location string = resourceGroup().location

@secure()
@description('Optional Application Insights connection string. Empty disables telemetry.')
param applicationInsightsConnectionString string = ''

@description('Optional private Azure Container Registry in the same resource group. Both registry parameters must be supplied together.')
param registryName string = ''

@description('Existing user-assigned managed identity in the same resource group with AcrPull on the private registry.')
param registryIdentityName string = ''

@description('IPv4 CIDR allow-list for the ingress (for example ["203.0.113.10/32"]); include the operator address used for health checks. When non-empty it always applies, even if allowPublicIngress is true.')
param allowedIngressCidrs array = []

@description('Explicit opt-in to unrestricted, unauthenticated internet ingress when allowedIngressCidrs is empty. When both are empty/false the app is deployed with environment-internal ingress only (fail closed).')
param allowPublicIngress bool = false

var telemetryEnabled = !empty(applicationInsightsConnectionString)
var privateRegistry = !empty(registryName)
var ingressRestricted = !empty(allowedIngressCidrs)
var externalIngress = ingressRestricted || allowPublicIngress
var ingressRestrictions = [for (cidr, i) in allowedIngressCidrs: {
  name: 'allow-${i}'
  description: 'Operator-approved source range'
  ipAddressRange: cidr
  action: 'Allow'
}]

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (privateRegistry) {
  name: registryName
}

resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = if (privateRegistry) {
  name: registryIdentityName
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  tags: {
    'sre-demo': 'true'
  }
  identity: privateRegistry ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${pullIdentity!.id}': {}
    }
  } : null
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Multiple'
      registries: privateRegistry ? [
        {
          server: registry!.properties.loginServer
          identity: pullIdentity!.id
        }
      ] : []
      secrets: telemetryEnabled ? [
        {
          name: 'application-insights-connection-string'
          value: applicationInsightsConnectionString
        }
      ] : []
      ingress: {
        external: externalIngress
        allowInsecure: false
        targetPort: 8080
        ipSecurityRestrictions: ingressRestricted ? ingressRestrictions : null
        traffic: [
          {
            revisionName: '${appName}--${revisionSuffix}'
            weight: 100
          }
        ]
      }
    }
    template: {
      revisionSuffix: revisionSuffix
      containers: [
        {
          name: appName
          image: image
          env: concat([
            {
              name: 'PORT'
              value: '8080'
            }
          ], telemetryEnabled ? [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'application-insights-connection-string'
            }
          ] : [])
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/healthz'
                port: 8080
              }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/readyz'
                port: 8080
              }
              initialDelaySeconds: 3
              periodSeconds: 5
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

output appFqdn string = containerApp.properties.configuration.ingress.fqdn
output appId string = containerApp.id
