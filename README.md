# Azure Backup report

One PowerShell 7 runbook: [New-AzureBackupDailyReport.ps1](New-AzureBackupDailyReport.ps1)

**On your PC**

```powershell
Install-Module Az.Accounts, Az.ResourceGraph -Scope CurrentUser
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

That creates the Automation Account (managed identity, PowerShell 7.2 modules, daily 06:00 UTC schedule) and publishes the runbook.

Then assign the printed identity **Reader** on your subscriptions, and Graph **Mail.Send** so it can send as `MailFrom`.
