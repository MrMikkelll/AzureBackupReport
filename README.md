# Azure Backup report

Azure Automation runbook: [New-AzureBackupDailyReport.ps1](New-AzureBackupDailyReport.ps1)

Uses the account managed identity with `Connect-AzAccount -Identity` and `Connect-MgGraph -Identity`. Backup jobs come from `Search-AzGraph`. Mail is sent with `Send-MgUserMail`.

## Deploy

The repo must stay **public** so Azure can read the runbook from GitHub.

1. Create resource group `rg-azbackupreport-bicep` in `westeurope` if it does not exist.
2. Edit [`infra/main.parameters.json`](infra/main.parameters.json) (`mailFrom`, `mailTo`).
3. In VS Code, right-click [`infra/main.bicep`](infra/main.bicep) → **Deploy Bicep File…** and choose that resource group plus `infra/main.parameters.json`.

That creates:

- Automation Account with a system-assigned managed identity
- **PowerShell 7.6** runtime (`PowerShell-76`) with Az 15.1.0, Azure CLI 2.77.0, and Microsoft Graph 2.39.0
- Daily schedule (not linked yet — see below)
- The published runbook, pulled from this repo’s raw GitHub URL

In the portal, open the Automation Account and use **Runtime environment experience** — PowerShell 7.6 runbooks do not show on the old Runbooks blade the same way as 7.2.

Then link the schedule **once**: open `New-AzureBackupDailyReport` → **Schedules** → **Add a schedule** → pick **Daily**, and set `MailFrom`, `MailTo`, and `LookbackHours`. Azure cannot create that link from Bicep on a redeploy (same job-schedule id always conflicts).

Wait until the Graph packages on that runtime show **Available** before the first job. After you change the `.ps1` on GitHub, redeploy the Bicep file so Automation picks up the new script.

## After deploy

**1. Reader** on each subscription that should appear in the report:

```powershell
New-AzRoleAssignment -ObjectId <principalId> -RoleDefinitionName Reader -Scope /subscriptions/<subscriptionId>
```

**2. Graph application permission Mail.Send** on that identity, sending as `mailFrom`.
