// Automation Account for the daily Azure Backup report (PowerShell 7.2).
// Deploy this file against a resource group. See README.md for portal and CLI steps.
targetScope = 'resourceGroup'

@description('Azure region for the Automation Account.')
param location string = resourceGroup().location

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

// Public copy of the runbook in this repo. Redeploy after you change the .ps1 on GitHub.
param runbookUri string = 'https://raw.githubusercontent.com/MrMikkelll/AzureBackupReport/master/New-AzureBackupDailyReport.ps1'

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned' // used by Connect-AzAccount -Identity in the runbook
  }
  properties: {
    sku: {
      name: 'Basic'
    }
  }
}

// PowerShell 7.2 modules the runbook imports at runtime.
resource azAccounts 'Microsoft.Automation/automationAccounts/powerShell72Modules@2023-11-01' = {
  parent: automationAccount
  name: 'Az.Accounts'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Az.Accounts'
    }
  }
}

resource azResourceGraph 'Microsoft.Automation/automationAccounts/powerShell72Modules@2023-11-01' = {
  parent: automationAccount
  name: 'Az.ResourceGraph'
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/Az.ResourceGraph'
    }
  }
  dependsOn: [
    azAccounts
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

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'New-AzureBackupDailyReport'
  location: location
  properties: {
    description: 'Emails an HTML Azure Backup job report'
    runbookType: 'PowerShell72'
    logProgress: false
    logVerbose: false
    publishContentLink: {
      uri: runbookUri
    }
  }
}

// Links the published runbook to the daily schedule.
resource jobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.id, runbook.name, dailySchedule.name)
  properties: {
    runbook: {
      name: runbook.name
    }
    schedule: {
      name: dailySchedule.name
    }
    parameters: {
      MailFrom: mailFrom
      MailTo: mailTo
      LookbackHours: string(lookbackHours)
    }
  }
}

output principalId string = automationAccount.identity.principalId
output automationAccountName string = automationAccount.name
output runbookName string = runbook.name
