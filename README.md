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

Automation's PowerShell 7.2 runtime cannot load Az.Accounts 5.3 or later. The template pins **Az.Accounts 5.2.0** and **Az.ResourceGraph 1.2.1**. If the account already has a newer Az.Accounts, wait until those modules show as Available (Runtime 7.2) after deploy, then start the runbook.

Then assign the printed identity **Reader** on your subscriptions, and Graph **Mail.Send** so it can send as `MailFrom`.
