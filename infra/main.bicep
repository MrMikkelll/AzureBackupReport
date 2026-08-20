targetScope = 'resourceGroup'

@description('Region for the Automation Account.')
param location string = resourceGroup().location

@description('Automation Account name.')
param automationAccountName string = 'aa-backup-report'

@description('Mailbox UPN that sends the report (must already exist).')
param mailFrom string

@description('Recipient email address.')
param mailTo string

@description('First run time, ISO 8601 UTC, at least 15 minutes in the future.')
param scheduleStartTime string

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

var runtimeEnvironmentName = 'PowerShell-76'

resource runtimeEnv 'Microsoft.Automation/automationAccounts/runtimeEnvironments@2024-10-23' = {
  parent: automationAccount
  name: runtimeEnvironmentName
  location: location
  properties: {
    description: 'PowerShell 7.6 with the built-in Az 15.1.0 package (includes Az.Accounts).'
    runtime: {
      language: 'PowerShell'
      version: '7.6'
    }
    defaultPackages: {
      Az: '15.1.0'
    }
  }
}

// Search-AzGraph is not always in the default Az bundle; import it onto this runtime.
resource azResourceGraph 'Microsoft.Automation/automationAccounts/runtimeEnvironments/packages@2024-10-23' = {
  parent: runtimeEnv
  name: 'Az.ResourceGraph'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Az.ResourceGraph/1.2.1'
      version: '1.2.1'
    }
  }
}

resource dailySchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'Daily'
  properties: {
    frequency: 'Day'
    interval: 1
    startTime: scheduleStartTime
    timeZone: 'UTC'
  }
}

resource mailFromVar 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount
  name: 'MailFrom'
  properties: {
    isEncrypted: false
    value: '"${mailFrom}"'
  }
}

resource mailToVar 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: automationAccount
  name: 'MailTo'
  properties: {
    isEncrypted: false
    value: '"${mailTo}"'
  }
}

output principalId string = automationAccount.identity.principalId
output automationAccountName string = automationAccount.name
output runtimeEnvironmentName string = runtimeEnv.name
