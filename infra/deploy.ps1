#Requires -Version 7.0
<#
  Deploys infra/main.bicep from this PC.
  Defaults come from infra/main.parameters.json (edit mailFrom / mailTo there).
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
$templateFile = Join-Path $PSScriptRoot 'main.bicep'
$parameterFile = Join-Path $PSScriptRoot 'main.parameters.json'
$fileParams = (Get-Content -Raw $parameterFile | ConvertFrom-Json).parameters

if (-not $ResourceGroupName) { $ResourceGroupName = $fileParams.resourceGroupName.value }
if (-not $Location) { $Location = $fileParams.location.value }

foreach ($name in @('Az.Accounts', 'Az.Resources')) {
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

$principalId = $deployment.Outputs.principalId.Value
Write-Output "Deployed $($deployment.Outputs.automationAccountName.Value) in $ResourceGroupName ($Location)"
Write-Output "Managed identity: $principalId"
Write-Output "Still needed:"
Write-Output "  1. Reader on each subscription:  New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName Reader -Scope /subscriptions/<id>"
Write-Output "  2. Graph application permission Mail.Send on that identity, sending as the mailFrom mailbox"
