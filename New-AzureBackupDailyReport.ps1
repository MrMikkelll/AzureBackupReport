#Requires -Version 7.0
param(
    [string]$MailFrom,
    [string]$MailTo,
    [int]$LookbackHours = 24
)

$ErrorActionPreference = 'Stop'

Import-Module Az.Accounts, Az.ResourceGraph, Microsoft.Graph.Authentication, Microsoft.Graph.Users.Actions
Connect-AzAccount -Identity | Out-Null
Connect-MgGraph -Identity | Out-Null

$since = [datetime]::UtcNow.AddHours(-$LookbackHours).ToString('yyyy-MM-ddTHH:mm:ssZ')
$subs = @(Get-AzSubscription | Where-Object State -eq 'Enabled' | ForEach-Object Id)

$result = Search-AzGraph -Subscription $subs -First 1000 -Query @"
RecoveryServicesResources
| where type =~ 'microsoft.recoveryservices/vaults/backupjobs'
| extend startTime = todatetime(properties.startTime)
| where startTime >= datetime($since)
| project Item = tostring(properties.entityFriendlyName),
          Vault = tostring(split(id, '/')[8]),
          Status = tostring(properties.status),
          Started = startTime,
          Message = tostring(properties.statusMessage)
| order by Started desc
"@
$jobs = @($(if ($result.PSObject.Properties['Data']) { $result.Data } else { $result }))

$ok      = @($jobs | Where-Object { $_.Status -match 'Completed|Succeeded|Success' -and $_.Status -notmatch 'Warning' }).Count
$failed  = @($jobs | Where-Object { $_.Status -match 'Failed' }).Count
$warning = @($jobs | Where-Object { $_.Status -match 'Warning' }).Count
$running = @($jobs | Where-Object { $_.Status -match 'InProgress|Running' }).Count

$css = @'
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #323130; }
  h1 { color: #0078D4; }
  .kpi { font-size: 22px; font-weight: 700; margin-right: 24px; }
  .ok { color: #107C10; } .fail { color: #D13438; } .warn { color: #C19C00; }
  table { border-collapse: collapse; width: 100%; margin-top: 16px; }
  th { background: #0078D4; color: #fff; text-align: left; padding: 8px 10px; }
  td { border-bottom: 1px solid #E1DFDD; padding: 8px 10px; }
  tr:nth-child(even) td { background: #FAF9F8; }
</style>
'@

$pre = @"
<h1>Azure Backup report</h1>
<p>Last $LookbackHours hours &nbsp;|&nbsp; $($subs.Count) subscriptions &nbsp;|&nbsp; $($jobs.Count) jobs</p>
<p>
  <span class="kpi ok">$ok ok</span>
  <span class="kpi fail">$failed failed</span>
  <span class="kpi warn">$warning warnings</span>
  <span class="kpi">$running running</span>
</p>
<h2>Backup jobs</h2>
"@

$html = $jobs |
    Select-Object Item, Vault, Status, Started, Message |
    ConvertTo-Html -Head $css -PreContent $pre |
    Out-String

if ($MailFrom -and $MailTo) {
    Send-MgUserMail -UserId $MailFrom -BodyParameter @{
        message = @{
            subject      = "Azure Backup report - $failed failed"
            body         = @{ contentType = 'HTML'; content = $html }
            toRecipients = @(@{ emailAddress = @{ address = $MailTo } })
        }
    }
}

Write-Output "Jobs=$($jobs.Count) OK=$ok Failed=$failed Warning=$warning Running=$running"
