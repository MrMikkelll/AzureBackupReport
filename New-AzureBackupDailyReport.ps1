#Requires -Version 7.0
param(
    [string]$MailFrom,
    [string]$MailTo,
    [int]$LookbackHours = 24
)

$ErrorActionPreference = 'Stop'

# Automation uses the managed identity. On a PC this falls back to an interactive login.
if ($env:AUTOMATION_ASSET_ACCOUNTID) {
    Connect-AzAccount -Identity | Out-Null
}
else {
    Connect-AzAccount | Out-Null
}

$since = [datetime]::UtcNow.AddHours(-$LookbackHours).ToString('yyyy-MM-ddTHH:mm:ssZ')
$subs = @(Get-AzSubscription | Where-Object State -eq 'Enabled' | ForEach-Object Id)

$jobs = @(Search-AzGraph -Subscription $subs -First 1000 -Query @"
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
"@)

$ok      = @($jobs | Where-Object Status -eq 'Completed').Count
$failed  = @($jobs | Where-Object Status -eq 'Failed').Count
$warning = @($jobs | Where-Object Status -like '*Warning*').Count
$running = @($jobs | Where-Object Status -eq 'InProgress').Count
$problems = @($jobs | Where-Object { $_.Status -eq 'Failed' -or $_.Status -like '*Warning*' })

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
<h2>Failed and warning jobs</h2>
"@

$html = $problems |
    Select-Object Item, Vault, Status, Started, Message |
    ConvertTo-Html -Head $css -PreContent $pre |
    Out-String

if ($MailFrom -and $MailTo) {
    $token = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com').Token
    if ($token -is [securestring]) {
        $token = [System.Net.NetworkCredential]::new('', $token).Password
    }
    $mail = @{
        message = @{
            subject = "Azure Backup report - $failed failed"
            body    = @{ contentType = 'HTML'; content = $html }
            toRecipients = @(@{ emailAddress = @{ address = $MailTo } })
        }
    } | ConvertTo-Json -Depth 6 -Compress
    Invoke-RestMethod -Method Post -ContentType 'application/json' -Body $mail `
        -Uri ("https://graph.microsoft.com/v1.0/users/$MailFrom/sendMail") `
        -Headers @{ Authorization = "Bearer $token" }
}

if (-not $env:AUTOMATION_ASSET_ACCOUNTID) {
    $file = Join-Path (Get-Location) 'AzureBackupReport.html'
    $html | Set-Content -Path $file -Encoding utf8
    Write-Output "Wrote $file"
}

Write-Output "Jobs=$($jobs.Count) OK=$ok Failed=$failed Warning=$warning Running=$running"
