# Azure Backup report

Azure Automation runbook: [New-AzureBackupDailyReport.ps1](New-AzureBackupDailyReport.ps1)

Uses the account managed identity with `Connect-AzAccount -Identity` and `Connect-MgGraph -Identity`. Backup jobs come from `Search-AzGraph`. Mail is sent with `Send-MgUserMail`.

## Deploy

Edit [`infra/main.parameters.json`](infra/main.parameters.json) (`mailFrom`, `mailTo`). Resource group defaults to `rg-azbackupreport-bicep` in `westeurope`.

```powershell
pwsh -File .\infra\deploy.ps1
```

That creates:

- Automation Account with a system-assigned managed identity
- **PowerShell 7.6** runtime (`PowerShell-76`) with Az 15.1.0, Azure CLI 2.77.0, and Microsoft Graph 2.39.0 (`Authentication`, `Users.Actions`)
- Daily schedule
- The runbook uploaded from this repo (not GitHub content-link)

Wait until the Graph packages on that runtime show **Available** before the first job.

## After deploy

**1. Reader** on each subscription that should appear in the report:

```powershell
New-AzRoleAssignment -ObjectId <principalId> -RoleDefinitionName Reader -Scope /subscriptions/<subscriptionId>
```

**2. Graph application permission Mail.Send** on that identity, sending as `mailFrom`.
