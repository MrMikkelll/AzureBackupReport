# Azure Backup report

PowerShell 7.2 Azure Automation runbook that emails a daily Recovery Services backup job report.

## Deploy the Bicep template

The template in [`infra/main.bicep`](infra/main.bicep) creates:

- Automation Account with a system-assigned managed identity
- PowerShell 7.2 modules `Az.Accounts` and `Az.ResourceGraph`
- Runbook `New-AzureBackupDailyReport` (pulled from this GitHub repo)
- Daily schedule (first run about 1 hour after deploy, then every 24 hours UTC)

Edit [`infra/main.parameters.json`](infra/main.parameters.json) and set `mailFrom` and `mailTo` before you deploy.

### Azure portal

1. Create a resource group (or use an existing one).
2. In the portal search box, open **Deploy a custom template**.
3. Choose **Build your own template in the editor**.
4. **Load file** and select `infra/main.bicep`. Save.
5. Select the resource group. Fill in:

   - `mailFrom` — existing mailbox UPN (shared mailbox recommended)
   - `mailTo` — recipient
   - `automationAccountName` — optional, default `aa-backup-report`
6. **Review + create**, then **Create**.
7. Open the deployment outputs and copy `principalId`.

If the portal will not accept a `.bicep` file, deploy with Azure CLI instead (below), or paste the compiled JSON from `az bicep build --file infra/main.bicep`.

### Azure CLI

```bash
az group create --name rg-backup-report --location westeurope

az deployment group create \
  --resource-group rg-backup-report \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json
```

### PowerShell

```powershell
New-AzResourceGroup -Name rg-backup-report -Location westeurope

New-AzResourceGroupDeployment `
  -ResourceGroupName rg-backup-report `
  -TemplateFile .\infra\main.bicep `
  -TemplateParameterFile .\infra\main.parameters.json
```

Wait until both PowerShell 7.2 modules show **Succeeded** on the Automation Account before the first job runs.

## After deploy

The identity cannot see vaults or send mail until you do these two steps.

**1. Reader on each subscription** (or a management group) that should appear in the report:

```powershell
New-AzRoleAssignment -ObjectId <principalId> -RoleDefinitionName Reader -Scope /subscriptions/<subscriptionId>
```

In the portal: Automation Account → **Identity** → **Azure role assignments** → **Add role assignment** → Reader.

**2. Graph permission Mail.Send** on that same identity, sending as `mailFrom`.

The mailbox must already exist. If Graph rejects the send, add an Exchange application access policy for this managed identity.

## Change the runbook later

Push the updated `New-AzureBackupDailyReport.ps1` to `master`, then redeploy the Bicep (it republishes from GitHub). Or in the portal: Runbooks → import the `.ps1` as type **PowerShell 7.2** → Publish → keep it linked to the **Daily** schedule.
