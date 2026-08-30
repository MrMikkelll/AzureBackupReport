targetScope = 'managementGroup'

@description('Object ID of the Automation Account managed identity.')
param principalId string

var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

resource reader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managementGroup().id, principalId, readerRoleId)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: tenantResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
  }
}
