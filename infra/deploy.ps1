#Requires -Version 7.0
<#
  Deploys infra/main.bicep, then publishes New-AzureBackupDailyReport.ps1
  onto the PowerShell 7.6 runtime. Defaults come from main.parameters.json.
#>
param(
    [string]$ResourceGroupName,
    [string]$Location,
    [string]$MailFrom,
    [string]$MailTo,
    [string]$AutomationAccountName,
    [int]$LookbackHours
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$templateFile = Join-Path $PSScriptRoot 'main.bicep'
$parameterFile = Join-Path $PSScriptRoot 'main.parameters.json'
$runbookFile = Join-Path $repoRoot 'New-AzureBackupDailyReport.ps1'
$fileParams = (Get-Content -Raw $parameterFile | ConvertFrom-Json).parameters

if (-not $ResourceGroupName) { $ResourceGroupName = $fileParams.resourceGroupName.value }
if (-not $Location) { $Location = $fileParams.location.value }

foreach ($name in @('Az.Accounts', 'Az.Resources', 'Az.Automation')) {
    if (-not (Get-Module $name -ListAvailable)) {
        Install-Module $name -Scope CurrentUser -Force
    }
    Import-Module $name
}

if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }

if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
}

$extra = @{ location = $Location }
if ($MailFrom) { $extra.mailFrom = $MailFrom }
if ($MailTo) { $extra.mailTo = $MailTo }
if ($AutomationAccountName) { $extra.automationAccountName = $AutomationAccountName }
if ($PSBoundParameters.ContainsKey('LookbackHours')) { $extra.lookbackHours = $LookbackHours }

$deployment = New-AzResourceGroupDeployment `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile $templateFile `
    -TemplateParameterFile $parameterFile `
    @extra

$runtimeName = $deployment.Outputs.runtimeEnvironmentName.Value
$accountName = $deployment.Outputs.automationAccountName.Value
$from = if ($MailFrom) { $MailFrom } else { $deployment.Outputs.mailFrom.Value }
$to = if ($MailTo) { $MailTo } else { $deployment.Outputs.mailTo.Value }
$hours = if ($PSBoundParameters.ContainsKey('LookbackHours')) { $LookbackHours } else { [int]$deployment.Outputs.lookbackHours.Value }

$subId = (Get-AzContext).Subscription.Id
$runbookName = 'New-AzureBackupDailyReport'
$runbookPath = "/subscriptions/$subId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$accountName/runbooks/$runbookName"

$runbookMeta = @{
    name     = $runbookName
    location = $Location
    properties = @{
        runbookType        = 'PowerShell'
        runtimeEnvironment = $runtimeName
        logProgress        = $false
        logVerbose         = $false
        draft              = @{}
    }
} | ConvertTo-Json -Depth 6 -Compress

$create = Invoke-AzRestMethod -Method PUT -Path "$runbookPath`?api-version=2024-10-23" -Payload $runbookMeta
if ($create.StatusCode -notin 200, 201) {
    Write-Output "Replacing the existing runbook so it can use runtime $runtimeName..."
    Remove-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $accountName -Name $runbookName -Force -ErrorAction SilentlyContinue
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

Publish-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $accountName -Name $runbookName | Out-Null

try {
    Unregister-AzAutomationScheduledRunbook `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $accountName `
        -RunbookName $runbookName `
        -ScheduleName 'Daily' `
        -Force `
        -ErrorAction Stop | Out-Null
}
catch { }

Register-AzAutomationScheduledRunbook `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $accountName `
    -RunbookName $runbookName `
    -ScheduleName 'Daily' `
    -Parameters @{ MailFrom = $from; MailTo = $to; LookbackHours = $hours } | Out-Null

$principalId = $deployment.Outputs.principalId.Value
Write-Output "Deployed $accountName in $ResourceGroupName ($Location)"
Write-Output "Runtime: $runtimeName (PowerShell 7.6)"
Write-Output "Managed identity: $principalId"
Write-Output "Still needed:"
Write-Output "  1. Reader on each subscription:  New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName Reader -Scope /subscriptions/<id>"
Write-Output "  2. Graph application permission Mail.Send on that identity, sending as the mailFrom mailbox"
Write-Output "Wait until Graph packages on $runtimeName show Available before the first job."
