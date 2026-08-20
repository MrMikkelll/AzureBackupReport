# Azure Backup report

One PowerShell 7 runbook: [New-AzureBackupDailyReport.ps1](New-AzureBackupDailyReport.ps1)

Uses Az.Accounts (`Connect-AzAccount`) and Az.ResourceGraph (`Search-AzGraph`). Mail still goes out through Microsoft Graph `sendMail`.

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

That creates the Automation Account (managed identity, daily 06:00 UTC schedule), a **PowerShell 7.6** runtime environment with built-in **Az 15.1.0**, Az.ResourceGraph 1.2.1, and publishes the runbook onto that runtime.

In the portal, the runbook must show runtime **PowerShell-76** (not 7.2). Current Az.Accounts needs 7.4/7.6; 7.2 cannot load it.

Then assign the printed identity **Reader** on your subscriptions, and Graph **Mail.Send** so it can send as `MailFrom`.
