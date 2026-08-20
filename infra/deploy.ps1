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

$runtimeName = $deployment.Outputs.runtimeEnvironmentName.Value
$subId = (Get-AzContext).Subscription.Id
$runbookName = 'New-AzureBackupDailyReport'
$runbookPath = "/subscriptions/$subId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/runbooks/$runbookName"

# Import-AzAutomationRunbook has no RuntimeEnvironment parameter; use the 2024-10-23 API.
$runbookMeta = @{
    name     = $runbookName
    location = $Location
    properties = @{
        runbookType         = 'PowerShell'
        runtimeEnvironment  = $runtimeName
        logProgress         = $false
        logVerbose          = $false
        draft               = @{}
    }
} | ConvertTo-Json -Depth 6 -Compress

$create = Invoke-AzRestMethod -Method PUT -Path "$runbookPath`?api-version=2024-10-23" -Payload $runbookMeta
if ($create.StatusCode -notin 200, 201) {
    # Existing PowerShell 7.2 runbooks cannot change type in place.
    Write-Output "Replacing the existing runbook so it can use runtime $runtimeName..."
    Remove-AzAutomationRunbook `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Name $runbookName `
        -Force `
        -ErrorAction SilentlyContinue
    $create = Invoke-AzRestMethod -Method PUT -Path "$runbookPath`?api-version=2024-10-23" -Payload $runbookMeta
}
if ($create.StatusCode -notin 200, 201) {
    throw "Failed to create runbook ($($create.StatusCode)): $($create.Content)"
}

$content = Get-Content -Raw -Path $runbookFile
$draft = Invoke-AzRestMethod -Method PUT -Path "$runbookPath/draft/content?api-version=2024-10-23" -Payload $content
if ($draft.StatusCode -notin 200, 201, 202) {
    throw "Failed to upload runbook draft ($($draft.StatusCode)): $($draft.Content)"
}

Publish-AzAutomationRunbook `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -Name $runbookName | Out-Null

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
Write-Output "Runtime: $runtimeName (PowerShell 7.6)"
Write-Output "Managed identity: $principalId"
Write-Output "Still needed:"
Write-Output "  1. Reader on each subscription:  New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName Reader -Scope /subscriptions/<id>"
Write-Output "  2. Graph application permission Mail.Send on that identity, sending as $MailFrom"
