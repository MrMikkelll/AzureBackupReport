# Azure Backup report

One PowerShell 7 runbook: [New-AzureBackupDailyReport.ps1](New-AzureBackupDailyReport.ps1)

**On your PC**

```powershell
Install-Module Az.Accounts, Az.ResourceGraph -Scope CurrentUser
pwsh -File .\New-AzureBackupDailyReport.ps1
```

Writes `AzureBackupReport.html` in the current folder.

**In Azure Automation**

Import the script as a PowerShell 7.2 runbook. Use a system-assigned identity with Reader on the subscriptions, Graph permission Mail.Send, and modules Az.Accounts + Az.ResourceGraph (7.2).

Parameters: `MailFrom`, `MailTo`, optional `LookbackHours` (default 24).
