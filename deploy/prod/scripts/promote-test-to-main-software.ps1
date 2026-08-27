#Requires -Version 5.1
param(
    [ValidateSet("DryRun", "Deploy")]
    [string]$Mode = "DryRun"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$MainUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
$TestUrl = "https://test.erpnext.am"

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir = Join-Path $PSScriptRoot "backups\promote-test-to-main-$Stamp"
$ReportPath = Join-Path $PSScriptRoot "promote-test-to-main-software-$Stamp.json"

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-GetJsonUtf8([string]$Url) {
    $wc = New-Object System.Net.WebClient
    $wc.Headers["Authorization"] = $Headers.Authorization
    $bytes = $wc.DownloadData($Url)
    return [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
}
function Get-ErpDoc([string]$BaseUrl, [string]$DocType, [string]$Name) {
    try { return (Invoke-GetJsonUtf8 "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}
function Get-ErpDocMethod([string]$BaseUrl, [string]$DocType, [string]$Name) {
    try { return (Invoke-GetJsonUtf8 "$BaseUrl/api/method/frappe.client.get?doctype=$(Enc $DocType)&name=$(Enc $Name)").message } catch { return $null }
}
function Convert-CleanDoc($Obj) {
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Array]) {
        $arr = New-Object System.Collections.ArrayList
        foreach ($item in $Obj) { $null = $arr.Add((Convert-CleanDoc $item)) }
        return ,@($arr)
    }
    if ($Obj -is [PSCustomObject]) {
        $isChildRow = $false
        $propNames = @($Obj.PSObject.Properties | ForEach-Object { $_.Name })
        if (($propNames -contains "parent") -and ($propNames -contains "parenttype") -and ($propNames -contains "parentfield")) { $isChildRow = $true }
        $skip = @("modified", "modified_by", "creation", "owner", "idx", "_user_tags", "_comments", "_assign", "_liked_by", "__last_sync_on", "_seen", "_comment_count", "parent", "parenttype", "parentfield")
        if ($isChildRow) { $skip += "name" }
        $ordered = [ordered]@{}
        foreach ($p in $Obj.PSObject.Properties) {
            if ($skip -contains $p.Name) { continue }
            if ($p.Value -is [System.Array]) {
                $child = New-Object System.Collections.ArrayList
                foreach ($item in $p.Value) { $null = $child.Add((Convert-CleanDoc $item)) }
                $ordered[$p.Name] = @($child)
            } else {
                $ordered[$p.Name] = Convert-CleanDoc $p.Value
            }
        }
        return [PSCustomObject]$ordered
    }
    return $Obj
}
function Save-Backup([string]$DocType, [string]$Name, $Doc) {
    if ($Mode -ne "Deploy" -or $null -eq $Doc) { return }
    $safeDt = ($DocType -replace '[^a-zA-Z0-9._-]', '_')
    $safeName = ($Name -replace '[^a-zA-Z0-9._-]', '_')
    $dir = Join-Path $BackupDir $safeDt
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $Doc | ConvertTo-Json -Depth 80 | Set-Content (Join-Path $dir "$safeName.json") -Encoding UTF8
}
function Put-ErpDoc([string]$DocType, [string]$Name, $Doc) {
    $body = (Convert-CleanDoc $Doc) | ConvertTo-Json -Depth 80 -Compress
    Invoke-RestMethod -Uri "$MainUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60 | Out-Null
}
function Post-ErpDoc([string]$DocType, $Doc) {
    $body = (Convert-CleanDoc $Doc) | ConvertTo-Json -Depth 80 -Compress
    Invoke-RestMethod -Uri "$MainUrl/api/resource/$(Enc $DocType)" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60 | Out-Null
}
function Clear-MainCache([string]$Reason) {
    if ($Mode -ne "Deploy") { return }
    Write-Host "Clearing Main cache ($Reason)..." -ForegroundColor DarkCyan
    try {
        Invoke-RestMethod -Uri "$MainUrl/api/method/frappe.clear_cache" -Headers $Headers -Method Post -TimeoutSec 60 | Out-Null
    } catch {
        Write-Warning "Cache clear failed/forbidden; continuing. Users may need browser refresh or server-side cache clear later. $($_.Exception.Message)"
    }
}
function Promote-One([string]$DocType, [string]$Name, [bool]$UseMethod = $false) {
    $testDoc = if ($UseMethod) { Get-ErpDocMethod $TestUrl $DocType $Name } else { Get-ErpDoc $TestUrl $DocType $Name }
    if ($null -eq $testDoc) {
        Write-Warning "SKIP missing/unreadable on Test: $DocType / $Name"
        return [ordered]@{ doctype = $DocType; name = $Name; action = "skip_test_unreadable" }
    }
    $mainDoc = Get-ErpDoc $MainUrl $DocType $Name
    $action = if ($null -eq $mainDoc) { "create" } else { "update" }
    Write-Host ("{0,-7} {1} / {2}" -f $action.ToUpperInvariant(), $DocType, $Name) -ForegroundColor $(if ($action -eq "create") { "Green" } else { "Yellow" })
    if ($Mode -eq "Deploy") {
        Save-Backup $DocType $Name $mainDoc
        if ($action -eq "create") { Post-ErpDoc $DocType $testDoc } else { Put-ErpDoc $DocType $Name $testDoc }
    }
    return [ordered]@{ doctype = $DocType; name = $Name; action = $action }
}

$CustomDocTypes = @(
    "Account Detail Attachment",
    "Surgical Kit Template Item",
    "Surgical Kit Template",
    "Telegram Notification User",
    "Telegram Settings"
)
$Records = @(
    @{ DocType = "Custom Field"; Names = @(
        "Dispatch Case-custom_select_surgical_kit_template",
        "Task-custom_next_task_assign_to",
        "Task-custom_select_surgical_kit_template",
        "Task-custom_account_photos",
        "Task-custom_assigned_to",
        "Task-custom_is_team_queue_task",
        "Task-custom_team_notified",
        "Task-custom_team_queue_role",
        "Task-dispatch_case",
        "Task-sales_invoice"
    ) },
    @{ DocType = "Property Setter"; Names = @(
        "Purchase Receipt-provisional_expense_account-hidden",
        "Task-main-field_order",
        "Task-main-show_title_field_in_link"
    ) },
    @{ DocType = "Client Script"; Names = @(
        "Dispatch Case-Template Auto Fill",
        "Task - Load Surgical Kit Template",
        "Dispatch Case-Item Code Toggle",
        "Global-Mobile Back Button",
        "Task-Accept Start",
        "Task-Account Details UI Cleanup",
        "Task-List Toggle Filters"
    ) },
    @{ DocType = "Server Script"; Names = @(
        "Task-Account Details Default Assignment",
        "Telegram Task Assignment Notification",
        "Telegram Task Status Update",
        "task_list_filtered",
        "Task-after-save-dispatch-flow"
    ) },
    @{ DocType = "Workspace"; Names = @(
        "Build",
        "Integrations",
        "Users",
        "Website"
    ) }
)
$SetupRecords = @(
    @{ DocType = "Surgical Kit Template"; Name = "Hip Surgery Standard Kit"; UseMethod = $false },
    @{ DocType = "Telegram Notification User"; Name = "levonaghinyan77@gmail.com"; UseMethod = $false }
)

Write-Host "=== Promote Test software/config to Main ===" -ForegroundColor Cyan
Write-Host "Mode     : $Mode" -ForegroundColor Cyan
Write-Host "Test     : $TestUrl (read only)" -ForegroundColor Cyan
Write-Host "Main     : $MainUrl" -ForegroundColor Cyan
Write-Host "Backups  : $BackupDir" -ForegroundColor Cyan
Write-Host "Report   : $ReportPath" -ForegroundColor Cyan

$Results = [System.Collections.ArrayList]::new()

Write-Host "`n-- Custom DocTypes first --" -ForegroundColor Magenta
foreach ($name in $CustomDocTypes) { $null = $Results.Add((Promote-One "DocType" $name)) }
Clear-MainCache "after custom doctype promotion"

Write-Host "`n-- Customization records --" -ForegroundColor Magenta
foreach ($group in $Records) {
    foreach ($name in $group.Names) { $null = $Results.Add((Promote-One $group.DocType $name)) }
}
Clear-MainCache "after customization promotion"

Write-Host "`n-- Feature setup records --" -ForegroundColor Magenta
foreach ($rec in $SetupRecords) { $null = $Results.Add((Promote-One $rec.DocType $rec.Name ([bool]$rec.UseMethod))) }
Clear-MainCache "after setup record promotion"

$Report = [ordered]@{
    created_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
    mode = $Mode
    test = $TestUrl
    main = $MainUrl
    backup_dir = $BackupDir
    results = $Results
}
$Report | ConvertTo-Json -Depth 30 | Set-Content $ReportPath -Encoding UTF8
Write-Host "`nPromotion $Mode complete. Report saved: $ReportPath" -ForegroundColor Green
if ($Mode -eq "DryRun") { Write-Host "No changes were made. Re-run with -Mode Deploy to apply." -ForegroundColor Yellow }
