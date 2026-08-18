#Requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$Location,
    [Parameter(Mandatory)][string]$MailFrom,
    [Parameter(Mandatory)][string]$MailTo,
    [string]$AutomationAccountName = 'aa-backup-report'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$runbookFile = Join-Path $repoRoot 'New-AzureBackupDailyReport.ps1'

Import-Module Az.Accounts, Az.Resources, Az.Automation
if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }

if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
}

$start = [datetime]::UtcNow.Date.AddDays(1).AddHours(6)
$deployment = New-AzResourceGroupDeployment `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile (Join-Path $PSScriptRoot 'main.bicep') `
    -location $Location `
    -automationAccountName $AutomationAccountName `
    -mailFrom $MailFrom `
    -mailTo $MailTo `
    -scheduleStartTime $start.ToString('yyyy-MM-ddTHH:mm:ssZ')

Import-AzAutomationRunbook `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -Name 'New-AzureBackupDailyReport' `
    -Type PowerShell72 `
    -Path $runbookFile `
    -Force | Out-Null

Publish-AzAutomationRunbook `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -Name 'New-AzureBackupDailyReport' | Out-Null

try {
    Unregister-AzAutomationScheduledRunbook `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -RunbookName 'New-AzureBackupDailyReport' `
        -ScheduleName 'Daily' `
        -Force `
        -ErrorAction Stop | Out-Null
}
catch { }

Register-AzAutomationScheduledRunbook `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -RunbookName 'New-AzureBackupDailyReport' `
    -ScheduleName 'Daily' `
    -Parameters @{ MailFrom = $MailFrom; MailTo = $MailTo } | Out-Null

$principalId = $deployment.Outputs.principalId.Value
Write-Output "Deployed $AutomationAccountName"
Write-Output "Managed identity: $principalId"
Write-Output "Still needed:"
Write-Output "  1. Reader on each subscription:  New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName Reader -Scope /subscriptions/<id>"
Write-Output "  2. Graph application permission Mail.Send on that identity, sending as $MailFrom"
