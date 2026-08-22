#Requires -Version 7.0
<#
  Azure Automation runbook (PowerShell 7.2).
  Signs in with the account's managed identity, reads Recovery Services
  backup jobs from Resource Graph, and emails an HTML report with Graph Mail.Send.
#>
param(
    # Existing mailbox UPN that sends the mail (shared mailbox is typical).
    [Parameter(Mandatory)]
    [string]$MailFrom,

    # Recipients, comma or semicolon separated.
    [Parameter(Mandatory)]
    [string]$MailTo,

    # How far back to include backup jobs.
    [int]$LookbackHours = 24
)

$ErrorActionPreference = 'Stop'

# Managed identity on this Automation Account. Needs Reader on the subscriptions
# and Graph application permission Mail.Send.
Connect-AzAccount -Identity | Out-Null

# Jobs that started after this UTC timestamp.
$since = [datetime]::UtcNow.AddHours(-$LookbackHours).ToString('yyyy-MM-ddTHH:mm:ssZ')

# Every enabled subscription this identity can list.
$subs = @(Get-AzSubscription | Where-Object State -eq 'Enabled' | ForEach-Object Id)

# One Resource Graph query across those subscriptions (max 1000 rows).
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

# Newer Az.ResourceGraph wraps rows in .Data. Older versions return the rows directly.
$jobs = @($(if ($result.PSObject.Properties['Data']) { $result.Data } else { $result }))

$ok      = @($jobs | Where-Object { $_.Status -match 'Completed|Succeeded|Success' -and $_.Status -notmatch 'Warning' }).Count
$failed  = @($jobs | Where-Object { $_.Status -match 'Failed' }).Count
$warning = @($jobs | Where-Object { $_.Status -match 'Warning' }).Count
$running = @($jobs | Where-Object { $_.Status -match 'InProgress|Running' }).Count

# Simple HTML that works in Outlook (no JavaScript).
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

# Graph token. Az.Accounts may return it as a SecureString.
$token = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com').Token
if ($token -is [securestring]) {
    $token = [System.Net.NetworkCredential]::new('', $token).Password
}

$recipients = @(
    $MailTo.Split(@(',', ';'), [StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)
if ($recipients.Count -eq 0) {
    throw 'MailTo must contain at least one email address.'
}

$mail = @{
    message = @{
        subject      = "Azure Backup report - $failed failed"
        body         = @{ contentType = 'HTML'; content = $html }
        toRecipients = @($recipients | ForEach-Object { @{ emailAddress = @{ address = $_ } } })
    }
} | ConvertTo-Json -Depth 6 -Compress

# Application Mail.Send: send as MailFrom (the identity has no mailbox of its own).
Invoke-RestMethod -Method Post -ContentType 'application/json' -Body $mail `
    -Uri ("https://graph.microsoft.com/v1.0/users/$MailFrom/sendMail") `
    -Headers @{ Authorization = "Bearer $token" }

Write-Output "Jobs=$($jobs.Count) OK=$ok Failed=$failed Warning=$warning Running=$running"
