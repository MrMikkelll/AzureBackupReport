#Requires -Version 7.0
param(
    [string]$MailFrom,
    [string]$MailTo,
    [int]$LookbackHours = 24
)

$ErrorActionPreference = 'Stop'

function Get-AccessToken([string]$Resource) {
    if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
        $join = if ($env:IDENTITY_ENDPOINT.Contains('?')) { '&' } else { '?' }
        $uri = "$($env:IDENTITY_ENDPOINT)${join}resource=$([uri]::EscapeDataString($Resource))"
        if ($uri -notmatch 'api-version=') { $uri += '&api-version=2019-08-01' }
        return (Invoke-RestMethod -Uri $uri -Headers @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER }).access_token
    }

    if (Get-Command az -ErrorAction SilentlyContinue) {
        $token = az account get-access-token --resource $Resource --query accessToken -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $token) { return $token.Trim() }
        throw "Azure CLI is not logged in. Run 'az login' first."
    }

    throw 'No managed identity token endpoint, and Azure CLI was not found. Enable a managed identity in Automation, or install Azure CLI and run az login locally.'
}

$armToken = Get-AccessToken 'https://management.azure.com/'
$since = [datetime]::UtcNow.AddHours(-$LookbackHours).ToString('yyyy-MM-ddTHH:mm:ssZ')

$subs = [System.Collections.Generic.List[string]]::new()
$subUri = 'https://management.azure.com/subscriptions?api-version=2022-12-01'
while ($subUri) {
    $page = Invoke-RestMethod -Uri $subUri -Headers @{ Authorization = "Bearer $armToken" }
    foreach ($sub in @($page.value)) {
        if ($sub.state -eq 'Enabled') { $subs.Add($sub.subscriptionId) }
    }
    $subUri = $page.nextLink
}

$query = @"
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

$jobs = [System.Collections.Generic.List[object]]::new()
$skipToken = $null
do {
    $body = @{
        subscriptions = @($subs)
        query         = $query
        options       = @{ resultFormat = 'objectArray'; '$top' = 1000 }
    }
    if ($skipToken) { $body.options['$skipToken'] = $skipToken }
    $result = Invoke-RestMethod `
        -Method Post `
        -Uri 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' `
        -Headers @{ Authorization = "Bearer $armToken" } `
        -ContentType 'application/json' `
        -Body ($body | ConvertTo-Json -Depth 6 -Compress)
    foreach ($row in @($result.data)) { $jobs.Add($row) }
    $skipToken = $result.PSObject.Properties['$skipToken']?.Value
} while ($skipToken)

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
    $graphToken = Get-AccessToken 'https://graph.microsoft.com/'
    $mail = @{
        message = @{
            subject = "Azure Backup report - $failed failed"
            body    = @{ contentType = 'HTML'; content = $html }
            toRecipients = @(@{ emailAddress = @{ address = $MailTo } })
        }
    } | ConvertTo-Json -Depth 6 -Compress
    Invoke-RestMethod -Method Post -ContentType 'application/json' -Body $mail `
        -Uri ("https://graph.microsoft.com/v1.0/users/$MailFrom/sendMail") `
        -Headers @{ Authorization = "Bearer $graphToken" }
}

if (-not $env:AUTOMATION_ASSET_ACCOUNTID) {
    $file = Join-Path (Get-Location) 'AzureBackupReport.html'
    $html | Set-Content -Path $file -Encoding utf8
    Write-Output "Wrote $file"
}

Write-Output "Jobs=$($jobs.Count) OK=$ok Failed=$failed Warning=$warning Running=$running"
