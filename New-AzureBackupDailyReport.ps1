#Requires -Version 7.0
<#
.SYNOPSIS
    Azure Backup daily report (PowerShell 7). One runbook, two ways to run it:

    Azure Automation (PowerShell 7.2)
      - Connects with the account's managed identity
      - Emails the HTML report with Graph Mail.Send
      Parameters: MailFrom, MailTo. LookbackHours optional (default 24).

    Local (pwsh)
      - Interactive Azure login
      - Writes an HTML file (and emails it if you also pass MailFrom/MailTo)

.EXAMPLE
    pwsh -File .\New-AzureBackupDailyReport.ps1
    pwsh -File .\New-AzureBackupDailyReport.ps1 -OutputPath .\backup-report.html
#>
param(
    [string]$MailFrom,
    [string]$MailTo,
    [int]$LookbackHours = 24,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Html($text) {
    if ($null -eq $text -or $text -eq '') { return '' }
    [System.Net.WebUtility]::HtmlEncode([string]$text)
}

function Get-GraphToken {
    $t = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com').Token
    if ($t -is [securestring]) {
        return [System.Net.NetworkCredential]::new('', $t).Password
    }
    return [string]$t
}

function Invoke-ArgQuery {
    param([string]$Query, [string[]]$SubscriptionId)
    $all = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $SubscriptionId.Count; $i += 100) {
        $end = [Math]::Min($i + 99, $SubscriptionId.Count - 1)
        $skip = $null
        do {
            $p = @{ Query = $Query; First = 1000; Subscription = @($SubscriptionId[$i..$end]) }
            if ($skip) { $p.SkipToken = $skip }
            $r = Search-AzGraph @p
            $data = if ($r.PSObject.Properties.Name -contains 'Data') { $r.Data } else { $r }
            foreach ($row in @($data)) { if ($null -ne $row) { [void]$all.Add($row) } }
            $skip = $r.SkipToken
        } while ($skip)
    }
    return $all
}

$inAutomation = [bool](Get-Command Get-AutomationVariable -ErrorAction SilentlyContinue)

if ($inAutomation) {
    Write-Output 'Connecting with managed identity...'
    Connect-AzAccount -Identity | Out-Null
    if (-not $MailFrom) { $MailFrom = Get-AutomationVariable -Name MailFrom }
    if (-not $MailTo) { $MailTo = Get-AutomationVariable -Name MailTo }
    if (-not $MailFrom -or -not $MailTo) {
        throw 'Set MailFrom and MailTo as runbook parameters or Automation variables.'
    }
}
else {
    Import-Module Az.Accounts, Az.ResourceGraph -ErrorAction Stop
    if (-not (Get-AzContext)) {
        Write-Host 'Sign in to Azure...'
        Connect-AzAccount | Out-Null
    }
}

$to = [datetime]::UtcNow
$from = $to.AddHours(-$LookbackHours)
$fromKusto = $from.ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-Output 'Listing subscriptions...'
$subs = @(Get-AzSubscription | Where-Object State -eq 'Enabled')
if ($subs.Count -eq 0) { throw 'No subscriptions found. Assign Reader to this identity/account.' }
$subIds = @($subs.Id)
$subNames = @{}
foreach ($s in $subs) { $subNames[[string]$s.Id] = [string]$s.Name }

Write-Output ("Querying Resource Graph in {0} subscription(s)..." -f $subIds.Count)

$vaults = Invoke-ArgQuery -SubscriptionId $subIds -Query @'
Resources
| where type =~ 'microsoft.recoveryservices/vaults'
| project id, name, subscriptionId, location
'@

$jobs = Invoke-ArgQuery -SubscriptionId $subIds -Query @"
RecoveryServicesResources
| where type =~ 'microsoft.recoveryservices/vaults/backupjobs'
| extend startTime = todatetime(properties.startTime)
| where startTime >= datetime($fromKusto)
| project id, name, subscriptionId, properties
"@

$items = Invoke-ArgQuery -SubscriptionId $subIds -Query @'
RecoveryServicesResources
| where type =~ 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems'
| project id, name, subscriptionId, properties
'@

function StatusGroup($status) {
    switch -Regex ([string]$status) {
        '^(Completed|Succeeded|Success)$' { 'OK' }
        '^(Failed|Failure)$' { 'Failed' }
        'Warning' { 'Warning' }
        'InProgress|^Running' { 'Running' }
        default { 'Other' }
    }
}

function VaultNameFromId($id) {
    $p = ([string]$id).Split('/')
    if ($p.Count -gt 8) { return $p[8] }
    return ''
}

$ok = 0; $failed = 0; $warn = 0; $running = 0
$problemJobs = [System.Collections.Generic.List[object]]::new()
foreach ($j in $jobs) {
    $st = [string]$j.properties.status
    $g = StatusGroup $st
    switch ($g) {
        'OK' { $ok++ }
        'Failed' { $failed++ }
        'Warning' { $warn++ }
        'Running' { $running++ }
    }
    if ($g -in @('Failed', 'Warning')) {
        $msg = [string]$j.properties.statusMessage
        if (-not $msg -and $j.properties.errorDetails) { $msg = [string]$j.properties.errorDetails }
        [void]$problemJobs.Add([pscustomobject]@{
                Name    = [string]$j.properties.entityFriendlyName
                Vault   = VaultNameFromId $j.id
                Sub     = $(if ($subNames.ContainsKey([string]$j.subscriptionId)) { $subNames[[string]$j.subscriptionId] } else { $j.subscriptionId })
                Status  = $st
                Started = $j.properties.startTime
                Message = $msg
            })
    }
}

$problemItems = [System.Collections.Generic.List[object]]::new()
foreach ($it in $items) {
    $lastStatus = [string]$it.properties.lastBackupStatus
    $lastTime = $null
    if ($it.properties.lastBackupTime) {
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse([string]$it.properties.lastBackupTime, [ref]$parsed)) {
            $lastTime = $parsed.ToUniversalTime()
        }
    }
    $badStatus = (StatusGroup $lastStatus) -in @('Failed', 'Warning')
    $stale = (-not $lastTime) -or ($lastTime -lt $from)
    $prot = [string]$it.properties.protectionState
    $unhealthy = $prot -match 'Stop|Error|Invalid'
    if ($badStatus -or $stale -or $unhealthy) {
        $why = @()
        if ($badStatus) { $why += $lastStatus }
        if ($stale) { $why += 'No backup in lookback window' }
        if ($unhealthy) { $why += $prot }
        [void]$problemItems.Add([pscustomobject]@{
                Name   = [string]$it.properties.friendlyName
                Vault  = VaultNameFromId $it.id
                Sub    = $(if ($subNames.ContainsKey([string]$it.subscriptionId)) { $subNames[[string]$it.subscriptionId] } else { $it.subscriptionId })
                Status = $lastStatus
                Last   = $lastTime
                Why    = ($why -join '; ')
            })
    }
}

$bannerColor = '#107C10'
$bannerText = 'All backup jobs completed successfully.'
if ($failed -gt 0) {
    $bannerColor = '#D13438'
    $bannerText = "$failed failed job(s) need attention."
}
elseif ($warn -gt 0 -or $problemItems.Count -gt 0) {
    $bannerColor = '#FFB900'
    $bannerText = 'Completed with warnings or stale items.'
}
elseif ($running -gt 0) {
    $bannerColor = '#0078D4'
    $bannerText = 'Some jobs are still running.'
}
elseif ($jobs.Count -eq 0) {
    $bannerColor = '#8A8886'
    $bannerText = 'No backup jobs in this window.'
}

function Kpi($label, $value, $color) {
    @"
<td style="width:25%;padding:8px;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#fff;border:1px solid #E1DFDD;border-top:4px solid $color;">
    <tr><td style="padding:14px 16px;">
      <div style="font-size:12px;color:#605E5C;text-transform:uppercase;">$(Html $label)</div>
      <div style="font-size:28px;font-weight:700;color:$color;">$(Html $value)</div>
    </td></tr>
  </table>
</td>
"@
}

function Rows($objects, $headers, $getCells) {
    if (-not $objects -or $objects.Count -eq 0) {
        return '<p style="color:#605E5C;font-size:13px;margin:0;">None.</p>'
    }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;border:1px solid #E1DFDD;">')
    [void]$sb.Append('<tr>')
    foreach ($h in $headers) {
        [void]$sb.Append("<th align='left' style='background:#FAF9F8;font-size:11px;text-transform:uppercase;color:#605E5C;padding:8px 10px;border-bottom:1px solid #E1DFDD;'>$(Html $h)</th>")
    }
    [void]$sb.Append('</tr>')
    $i = 0
    foreach ($o in ($objects | Select-Object -First 40)) {
        $bg = if ($i % 2 -eq 0) { '#fff' } else { '#FAF9F8' }
        [void]$sb.Append('<tr>')
        foreach ($c in (& $getCells $o)) {
            [void]$sb.Append("<td style='background:$bg;font-size:13px;padding:8px 10px;border-bottom:1px solid #EDEBE9;'> $c</td>")
        }
        [void]$sb.Append('</tr>')
        $i++
    }
    [void]$sb.Append('</table>')
    if ($objects.Count -gt 40) {
        [void]$sb.Append("<p style='font-size:12px;color:#605E5C;'>Showing first 40 of $($objects.Count).</p>")
    }
    return $sb.ToString()
}

$jobTable = Rows $problemJobs @('Item', 'Vault', 'Subscription', 'Status', 'Started', 'Message') {
    param($o)
    $when = if ($o.Started) { ([datetime]$o.Started).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC' } else { '-' }
    $color = if ((StatusGroup $o.Status) -eq 'Failed') { '#D13438' } else { '#FFB900' }
    @(
        (Html $o.Name)
        (Html $o.Vault)
        (Html $o.Sub)
        "<span style='color:$color;font-weight:600;'>$(Html $o.Status)</span>"
        (Html $when)
        (Html $o.Message)
    )
}

$itemTable = Rows $problemItems @('Item', 'Vault', 'Subscription', 'Last backup', 'Last time', 'Why') {
    param($o)
    $when = if ($o.Last) { $o.Last.ToString('yyyy-MM-dd HH:mm') + ' UTC' } else { '-' }
    @(
        (Html $o.Name)
        (Html $o.Vault)
        (Html $o.Sub)
        (Html $o.Status)
        (Html $when)
        (Html $o.Why)
    )
}

$title = 'Azure Backup Report'
$html = @"
<!DOCTYPE html>
<html><head><meta charset="utf-8"/><title>$(Html $title)</title></head>
<body style="margin:0;background:#F3F2F1;font-family:Segoe UI,Tahoma,Arial,sans-serif;color:#323130;">
<table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px;">
<table width="860" cellpadding="0" cellspacing="0" style="max-width:860px;width:100%;">
  <tr><td style="background:#0078D4;color:#fff;padding:24px;">
    <div style="font-size:13px;letter-spacing:.08em;text-transform:uppercase;">Azure Backup</div>
    <div style="font-size:24px;font-weight:700;margin-top:4px;">$(Html $title)</div>
    <div style="font-size:13px;margin-top:8px;opacity:.95;">Last $LookbackHours hours ($($from.ToString('yyyy-MM-dd HH:mm')) UTC to $($to.ToString('yyyy-MM-dd HH:mm')) UTC)</div>
    <div style="font-size:13px;margin-top:4px;opacity:.95;">$($subs.Count) subscriptions · $($vaults.Count) vaults · $($items.Count) protected items</div>
  </td></tr>
  <tr><td style="background:$bannerColor;color:#fff;padding:12px 24px;font-weight:600;">$(Html $bannerText)</td></tr>
  <tr><td style="padding:16px 8px 0 8px;"><table width="100%" cellpadding="0" cellspacing="0"><tr>
    $(Kpi 'Successful' $ok '#107C10')
    $(Kpi 'Failed' $failed '#D13438')
    $(Kpi 'Warnings' $warn '#FFB900')
    $(Kpi 'In progress' $running '#0078D4')
  </tr></table></td></tr>
  <tr><td style="padding:16px 24px;">
    <div style="font-size:16px;font-weight:700;margin-bottom:8px;">Jobs that need attention</div>
    $jobTable
  </td></tr>
  <tr><td style="padding:0 24px 24px 24px;">
    <div style="font-size:16px;font-weight:700;margin-bottom:8px;">Protected items that need attention</div>
    <div style="font-size:12px;color:#605E5C;margin-bottom:8px;">Failed last backup, unhealthy protection, or no backup in the last $LookbackHours hours.</div>
    $itemTable
  </td></tr>
  <tr><td style="padding:0 24px 24px 24px;font-size:12px;color:#605E5C;">Recovery Services vaults only. Generated $($to.ToString('yyyy-MM-dd HH:mm')) UTC.</td></tr>
</table>
</td></tr></table>
</body></html>
"@

$stamp = $to.ToString('yyyy-MM-dd')
$subject = if ($failed -gt 0) { "Azure Backup Report - $stamp ($failed failed)" } else { "Azure Backup Report - $stamp" }

if ($MailFrom -and $MailTo) {
    Write-Output "Sending mail from $MailFrom to $MailTo..."
    $recipients = @(
        $MailTo.Split(@(',', ';'), [StringSplitOptions]::RemoveEmptyEntries) |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
    $body = @{
        message         = @{
            subject      = $subject
            body         = @{ contentType = 'HTML'; content = $html }
            toRecipients = @($recipients | ForEach-Object { @{ emailAddress = @{ address = $_ } } })
        }
        saveToSentItems = $true
    } | ConvertTo-Json -Depth 8 -Compress
    $uri = 'https://graph.microsoft.com/v1.0/users/{0}/sendMail' -f [uri]::EscapeDataString($MailFrom)
    Invoke-RestMethod -Method Post -Uri $uri -Headers @{ Authorization = "Bearer $(Get-GraphToken)" } -ContentType 'application/json; charset=utf-8' -Body $body | Out-Null
    Write-Output 'Mail sent.'
}

if (-not $inAutomation) {
    if (-not $OutputPath) {
        $OutputPath = Join-Path (Get-Location) "AzureBackupReport-$($to.ToString('yyyyMMdd-HHmmss')).html"
    }
    $dir = Split-Path $OutputPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    if (-not [IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
    }
    [IO.File]::WriteAllText($OutputPath, $html, [Text.UTF8Encoding]::new($true))
    Write-Output "HTML written to $OutputPath"
}

Write-Output "Done. Jobs=$($jobs.Count) OK=$ok Failed=$failed Warn=$warn Running=$running Items=$($items.Count) Attention=$($problemItems.Count)"
