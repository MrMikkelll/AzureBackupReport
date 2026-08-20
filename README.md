# Azure Backup report

Azure Automation runbook: [New-AzureBackupDailyReport.ps1](New-AzureBackupDailyReport.ps1)

Uses the account managed identity with `Connect-AzAccount -Identity` and `Connect-MgGraph -Identity`. Backup jobs come from `Search-AzGraph`. Mail is sent with `Send-MgUserMail` using application permission **Mail.Send** (from mailbox `MailFrom`).

**Deploy**

```powershell
Install-Module Az.Accounts, Az.Resources, Az.Automation -Scope CurrentUser
pwsh -File .\infra\deploy.ps1 `
    -ResourceGroupName rg-backup-report `
    -Location westeurope `
    -MailFrom 'backup-reports@contoso.com' `
    -MailTo 'ops@contoso.com'
```

That creates the Automation Account (managed identity, daily 06:00 UTC schedule), a **PowerShell 7.6** runtime (`PowerShell-76`) with Az 15.1.0, Az.ResourceGraph, and the Graph mail modules, then publishes the runbook.

Wait until the Graph packages show as Available on that runtime before the first job.

Then assign the printed identity **Reader** on your subscriptions, and Graph application permission **Mail.Send** so it can send as `MailFrom`.
