# Azure Backup report

One PowerShell 7 runbook: [New-AzureBackupDailyReport.ps1](New-AzureBackupDailyReport.ps1)

It does not use Az or Microsoft.Graph PowerShell modules. Backup jobs come from the Azure Resource Graph REST API; mail is sent with Microsoft Graph `sendMail`. Tokens come from the Automation managed identity, or from Azure CLI locally.

**On your PC**

```powershell
az login
pwsh -File .\New-AzureBackupDailyReport.ps1
```

Writes `AzureBackupReport.html` in the current folder.

**Deploy to Azure Automation**

```powershell
Install-Module Az.Accounts, Az.Resources, Az.Automation -Scope CurrentUser
pwsh -File .\infra\deploy.ps1 `
    -ResourceGroupName rg-backup-report `
    -Location westeurope `
    -MailFrom 'backup-reports@contoso.com' `
    -MailTo 'ops@contoso.com'
```

That creates the Automation Account (managed identity, daily 06:00 UTC schedule) and publishes the PowerShell 7.2 runbook. The runbook needs no Az modules in the Automation account; leftover Az.Accounts / Az.ResourceGraph modules can be left or deleted.

Then assign the printed identity **Reader** on your subscriptions, and Graph **Mail.Send** so it can send as `MailFrom`.
