extension microsoftGraphV1

@description('Object ID of the Automation Account managed identity.')
param principalId string

resource graphSp 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: '00000003-0000-0000-c000-000000000000'
}

resource mailSend 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  appRoleId: (filter(graphSp.appRoles, role => role.value == 'Mail.Send')[0]).id
  principalId: principalId
  resourceId: graphSp.id
}
