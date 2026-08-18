# Azure Backup daily report

One PowerShell 7 runbook: [New-AzureBackupDailyReport.ps1](New-AzureBackupDailyReport.ps1).

It reads Recovery Services vaults with Azure Resource Graph and builds a short HTML overview (KPIs + jobs/items that need attention).

## Run once on your PC

```powershell
Install-Module Az.Accounts, Az.ResourceGraph -Scope CurrentUser
pwsh -File .\New-AzureBackupDailyReport.ps1
```

That signs you in, scans every subscription you can read, and writes an HTML file in the current folder.

## Azure Automation (daily email)

1. Create an Automation Account with a **system-assigned managed identity**.
2. Runtime: **PowerShell 7.2**. Import gallery modules **Az.Accounts** and **Az.ResourceGraph** for 7.2.
3. Import `New-AzureBackupDailyReport.ps1` as a **PowerShell 7.2** runbook and publish it.
4. Assign the identity **Reader** on each subscription (or a management group) that should appear in the report.
5. Grant the identity Graph application permission **Mail.Send**, and use an existing mailbox as `MailFrom` (shared mailbox is typical).
6. Create a daily schedule. Runbook parameters:

| Parameter | Example |
| --- | --- |
| `MailFrom` | `backup-reports@contoso.com` |
| `MailTo` | `ops@contoso.com` |
| `LookbackHours` | `24` (optional) |

You can store `MailFrom` / `MailTo` as Automation variables with those names instead of passing them each time.

If Graph send is blocked, add an Exchange application access policy for this managed identity on the sender mailbox.
