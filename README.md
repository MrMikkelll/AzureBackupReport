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
- **Reader** on the subscription you deploy to, and on Tenant Root Group (every subscription in the tenant)
- Graph application permission **Mail.Send** on that identity

The account you deploy with needs Owner or User Access Administrator on Tenant Root Group, plus permission to grant Graph app roles (Privileged Role Administrator or Cloud Application Administrator). If Tenant Root fails, set `assignReaderAtTenantRoot` to `false` and pass the other subscription IDs in `extraSubscriptionIds`.

In the portal, open the Automation Account and use **Runtime environment experience** — PowerShell 7.6 runbooks do not show on the old Runbooks blade the same way as 7.2.

Then link the schedule **once**: open `New-AzureBackupDailyReport` → **Schedules** → **Add a schedule** → pick **Daily**, and set `MailFrom`, `MailTo`, and `LookbackHours`. Azure cannot create that link from Bicep on a redeploy (same job-schedule id always conflicts).

Wait until the Graph packages on that runtime show **Available** before the first job. After you change the `.ps1` on GitHub, redeploy the Bicep file so Automation picks up the new script.

## After deploy

The identity can send as `mailFrom`. If send still fails, add an [Exchange application access policy](https://learn.microsoft.com/exchange/permissions-exo/application-access-policy) that allows that mailbox, or confirm the mailbox exists.
