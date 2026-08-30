// Automation Account for the daily Azure Backup report (PowerShell 7.6 runtime).
targetScope = 'resourceGroup'

@description('Intended resource group. Create it if needed, then deploy this file to it from the Bicep extension.')
param resourceGroupName string = 'rg-azbackupreport-bicep'

@description('Azure region. Use a full name such as westeurope (not westeu).')
param location string = 'westeurope'

@description('Automation Account name.')
param automationAccountName string = 'aa-backup-report'

@description('Existing mailbox UPN that sends the report (shared mailbox recommended).')
param mailFrom string

@description('Recipient email addresses, comma-separated.')
param mailTo string

@description('Hours of backup jobs to include. Passed to the runbook.')
param lookbackHours int = 24

@description('First scheduled run (UTC). Must be at least 15 minutes in the future. Default: 1 hour from deploy time.')
param scheduleStartTime string = dateTimeAdd(utcNow(), 'PT1H')

@description('Public raw URL of the runbook. Redeploy after you change the .ps1 on GitHub.')
param runbookUri string = 'https://raw.githubusercontent.com/MrMikkelll/AzureBackupReport/master/New-AzureBackupDailyReport.ps1'

var runtimeEnvironmentName = 'PowerShell-76'

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
  }
}

resource runtimeEnv 'Microsoft.Automation/automationAccounts/runtimeEnvironments@2024-10-23' = {
  parent: automationAccount
  name: runtimeEnvironmentName
  location: location
  properties: {
    description: 'PowerShell 7.6 with Az 15.1.0, Azure CLI, and Microsoft Graph 2.39.0.'
    runtime: {
      language: 'PowerShell'
      version: '7.6'
    }
    defaultPackages: {
      Az: '15.1.0'
      'Azure CLI': '2.77.0'
    }
  }
}

resource graphAuth 'Microsoft.Automation/automationAccounts/runtimeEnvironments/packages@2024-10-23' = {
  parent: runtimeEnv
  name: 'Microsoft.Graph.Authentication'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Microsoft.Graph.Authentication/2.39.0'
      version: '2.39.0'
    }
  }
}

resource graphUsersActions 'Microsoft.Automation/automationAccounts/runtimeEnvironments/packages@2024-10-23' = {
  parent: runtimeEnv
  name: 'Microsoft.Graph.Users.Actions'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Microsoft.Graph.Users.Actions/2.39.0'
      version: '2.39.0'
    }
  }
  dependsOn: [
    graphAuth
  ]
}

resource graphMeta 'Microsoft.Automation/automationAccounts/runtimeEnvironments/packages@2024-10-23' = {
  parent: runtimeEnv
  name: 'Microsoft.Graph'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Microsoft.Graph/2.39.0'
      version: '2.39.0'
    }
  }
  dependsOn: [
    graphAuth
    graphUsersActions
  ]
}

resource dailySchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'Daily'
  properties: {
    description: 'Daily Azure Backup report'
    frequency: 'Day'
    interval: 1
    startTime: scheduleStartTime
    timeZone: 'UTC'
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = {
  parent: automationAccount
  name: 'New-AzureBackupDailyReport'
  location: location
  properties: {
    description: 'Emails an HTML Azure Backup job report'
    runbookType: 'PowerShell'
    runtimeEnvironment: runtimeEnv.name
    logProgress: false
    logVerbose: false
    publishContentLink: {
      uri: runbookUri
    }
  }
}

// Job schedules are omitted on purpose. Azure rejects a second Create with the
// same GUID ("A jobSchedule with same id already exists"), including after you
// delete the account. Link Daily to the runbook once in the portal.

output principalId string = automationAccount.identity.principalId
output automationAccountName string = automationAccount.name
output resourceGroupName string = resourceGroupName
output runtimeEnvironmentName string = runtimeEnv.name
output runbookName string = runbook.name
output mailFrom string = mailFrom
output mailTo string = mailTo
output lookbackHours string = string(lookbackHours)
