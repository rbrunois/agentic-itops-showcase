// Reader and Log Analytics Reader for one agent identity on one resource group.
param principalId string

var roles = [
  'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
  '73c42c96-874c-492b-b04d-ab87d138a893' // Log Analytics Reader
]

resource assignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for role in roles: {
    name: guid(resourceGroup().id, principalId, role)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role)
      principalId: principalId
      principalType: 'ServicePrincipal'
    }
  }
]
