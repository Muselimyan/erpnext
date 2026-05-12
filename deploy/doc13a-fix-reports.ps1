#Requires -Version 5.1
<#
.SYNOPSIS
  Doc 13A — Report Fixes (post-mismatch-audit)
  - Fix Surgery Case SQL → Dispatch Case in two reports
  - Delete RPT — Surgery Cases — Aging; create RPT — Dispatch Cases — Aging
  - Rename 3 transit reports: drop "- Inmed" name suffix
  - Update Ops — Reporting Pack workspace shortcuts

.PARAMETER Mode
  Check  — verify only (no writes)
  Deploy — apply fixes (default)
#>
param([string]$Mode = "Deploy")
Set-StrictMode -Off
$ErrorActionPreference = "Stop"
$EM = [char]0x2014

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config  = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token ${ApiKey}:${ApiSec}"; "Content-Type" = "application/json" }

function Enc($s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method }
    $Json = $Body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($Json))
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data }
    catch { return $null }
}

function Remove-ErpDoc {
    param([string]$DocType, [string]$Name)
    try {
        Invoke-ErpRequest -Method Delete -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" | Out-Null
        Write-Host "  DELETED  $Name" -ForegroundColor Cyan
    } catch {
        Write-Host "  DEL-SKIP $Name (not found)" -ForegroundColor Yellow
    }
}

function Set-ErpQuery {
    param([string]$ReportName, [string]$Query)
    $exists = Get-ErpDoc "Report" $ReportName
    if (-not $exists) { Write-Host "  NOT-FOUND $ReportName" -ForegroundColor Yellow; return $false }
    if ($Mode -eq "Check") { Write-Host "  CHECK  $ReportName  (would patch query)" -ForegroundColor Gray; return $true }
    try {
        Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc 'Report')/$(Enc $ReportName)" `
            -Body @{ query = $Query } | Out-Null
        Write-Host "  PATCHED  $ReportName" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  FAILED   $ReportName : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Upsert-ErpDoc {
    param([string]$DocType, [string]$Name, $Body)
    $Existing = Get-ErpDoc -DocType $DocType -Name $Name
    if ($null -eq $Existing) {
        $Body.name = $Name
        $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ action = "created"; name = $C.name }
    }
    Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body | Out-Null
    return [pscustomobject]@{ action = "updated"; name = $Name }
}

function New-ErpReport {
    param([hashtable]$Def)
    $name = $Def.report_name
    if ($Mode -eq "Check") { Write-Host "  CHECK  $name  (would create)" -ForegroundColor Gray; return $true }
    try {
        Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc 'Report')" -Body $Def | Out-Null
        Write-Host "  CREATED  $name" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  FAILED   $name : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

$ok = 0; $err = 0
function tally($r) { if ($r) { $script:ok++ } else { $script:err++ } }

# ---------------------------------------------------------------
# 1. Fix RPT — Ops — Client Stock With No Open Cases
#    SQL: tabSurgery Case → tabDispatch Case
# ---------------------------------------------------------------
Write-Host "`n[1] Patching $("RPT ${EM} Ops ${EM} Client Stock With No Open Cases")"
$q1 = "select`n  w.name as client_location_warehouse,`n  sum(b.actual_qty) as total_qty`nfrom ``tabWarehouse`` w`njoin ``tabBin`` b on b.warehouse = w.name`nleft join ``tabDispatch Case`` dc`n  on dc.client_location_warehouse = w.name`n  and dc.status not in ('Closed', 'Cancelled')`nwhere`n  w.parent_warehouse = 'Clients - Inmed'`n  and w.is_group = 0`ngroup by w.name`nhaving`n  total_qty > 0`n  and count(dc.name) = 0`norder by total_qty desc"
tally (Set-ErpQuery "RPT ${EM} Ops ${EM} Client Stock With No Open Cases" $q1)

# ---------------------------------------------------------------
# 2. Fix RPT — Ops — Driver Task Queue (Derived)
#    SQL: t.surgery_case → t.dispatch_case
# ---------------------------------------------------------------
Write-Host "`n[2] Patching $("RPT ${EM} Ops ${EM} Driver Task Queue (Derived)")"
$q2 = "select`n  json_unquote(json_extract(t._assign, '`$[0]')) as assigned_to,`n  t.name as task,`n  t.task_kind,`n  t.status,`n  t.customer,`n  t.dispatch_case,`n  t.sales_order,`n  t.sales_invoice,`n  t.dispatch_group_id,`n  t.subject,`n  t.modified`nfrom ``tabTask`` t`nwhere`n  t.status not in ('Completed', 'Cancelled')`n  and t.task_kind in ('Delivery', 'Pickup Returns', 'Return drop-off at warehouse')`n  and (`n    %(assigned_to)s is null`n    or %(assigned_to)s = ''`n    or t._assign like concat('%', %(assigned_to)s, '%')`n  )`norder by assigned_to, t.modified asc"
tally (Set-ErpQuery "RPT ${EM} Ops ${EM} Driver Task Queue (Derived)" $q2)

# ---------------------------------------------------------------
# 3. Delete RPT — Surgery Cases — Aging (Open)
#    Create RPT — Dispatch Cases — Aging (Open)
# ---------------------------------------------------------------
Write-Host "`n[3] Replacing Surgery Cases Aging ${EM} Dispatch Cases Aging"
if ($Mode -ne "Check") { Remove-ErpDoc "Report" "RPT ${EM} Surgery Cases ${EM} Aging (Open)" }
$q3 = "select`n  dc.name as dispatch_case,`n  dc.status,`n  dc.customer,`n  dc.return_expected,`n  dc.creation,`n  dc.modified,`n  datediff(curdate(), date(dc.creation)) as age_days`nfrom ``tabDispatch Case`` dc`nwhere`n  dc.status not in ('Closed', 'Cancelled')`n  and (%(min_age_days)s is null or datediff(curdate(), date(dc.creation)) >= %(min_age_days)s)`norder by age_days desc, dc.modified asc"
tally (New-ErpReport @{
    report_name  = "RPT ${EM} Dispatch Cases ${EM} Aging (Open)"
    ref_doctype  = "Dispatch Case"
    report_type  = "Query Report"
    is_standard  = "No"
    module       = "Custom"
    disabled     = 0
    query        = $q3
    filters      = @( @{ label="Min Age Days"; fieldname="min_age_days"; fieldtype="Int"; default="0" } )
    roles        = @(
        @{ role="Ops - Order Accepting" }, @{ role="Ops - Inventory" }, @{ role="Ops - Returns" },
        @{ role="Ops - Delivery" }, @{ role="Ops - Accounting" }, @{ role="Ops - Directors" },
        @{ role="System Manager" }
    )
})

# ---------------------------------------------------------------
# 4. Rename transit reports: delete old, create with clean name
# ---------------------------------------------------------------
$BinQ = { param($wh) "select`n  b.item_code,`n  i.item_name,`n  i.item_group,`n  b.actual_qty`nfrom ``tabBin`` b`njoin ``tabItem`` i on i.name = b.item_code`nwhere`n  b.warehouse = '$wh'`n  and b.actual_qty > 0`norder by i.item_group, b.item_code" }

$transits = @(
    @{ old="RPT ${EM} Stock ${EM} Delivery In-Transit - Inmed";      new="RPT ${EM} Stock ${EM} Delivery In-Transit";      wh="Delivery In-Transit - Inmed" },
    @{ old="RPT ${EM} Stock ${EM} Return Pickup In-Transit - Inmed"; new="RPT ${EM} Stock ${EM} Return Pickup In-Transit"; wh="Return Pickup In-Transit - Inmed" },
    @{ old="RPT ${EM} Stock ${EM} Returns - Inmed";                  new="RPT ${EM} Stock ${EM} Returns";                  wh="Returns - Inmed" }
)

foreach ($t in $transits) {
    Write-Host "`n[4] Renaming: $($t.old) ${EM} $($t.new)"
    $old = Get-ErpDoc "Report" $t.old
    $roles = if ($old) { $old.roles | ForEach-Object { @{ role = $_.role } } } else { @(@{ role="Ops - Inventory" }, @{ role="Ops - Directors" }, @{ role="System Manager" }) }
    if ($Mode -ne "Check") { Remove-ErpDoc "Report" $t.old }
    tally (New-ErpReport @{
        report_name = $t.new
        ref_doctype = "Bin"
        report_type = "Query Report"
        is_standard = "No"
        module      = "Stock"
        disabled    = 0
        query       = (& $BinQ $t.wh)
        roles       = $roles
    })
}

# ---------------------------------------------------------------
# 5. Rebuild Ops — Reporting Pack workspace with corrected shortcuts
# ---------------------------------------------------------------
Write-Host "`n[5] Rebuilding workspace: Ops ${EM} Reporting Pack"
$wsName = "Ops ${EM} Reporting Pack"
$WsShortcuts = @(
    [ordered]@{ label="Delivery In-Transit Stock";        type="Report";  link_to="RPT ${EM} Stock ${EM} Delivery In-Transit" },
    [ordered]@{ label="Return Pickup In-Transit Stock";   type="Report";  link_to="RPT ${EM} Stock ${EM} Return Pickup In-Transit" },
    [ordered]@{ label="Returns Backlog";                  type="Report";  link_to="RPT ${EM} Stock ${EM} Returns" },
    [ordered]@{ label="Client Locations Stock";           type="Report";  link_to="RPT ${EM} Stock ${EM} Client Locations (All)" },
    [ordered]@{ label="In-Transit Stuck Check";           type="Report";  link_to="RPT ${EM} Stock ${EM} In-Transit Stuck (Age Check)" },
    [ordered]@{ label="Client Stock (No Open Cases)";     type="Report";  link_to="RPT ${EM} Ops ${EM} Client Stock With No Open Cases" },
    [ordered]@{ label="Driver Task Queue";                type="Report";  link_to="RPT ${EM} Ops ${EM} Driver Task Queue (Derived)" },
    [ordered]@{ label="Dispatch Cases Aging (Open)";      type="Report";  link_to="RPT ${EM} Dispatch Cases ${EM} Aging (Open)" },
    [ordered]@{ label="VIEW: Cases Awaiting Return Pickup"; type="DocType"; link_to="Dispatch Case"; doc_view="List"; stats_filter='[["status","=","Awaiting Return Pickup"]]' },
    [ordered]@{ label="VIEW: Cases Return In Transit";    type="DocType"; link_to="Dispatch Case"; doc_view="List"; stats_filter='[["status","=","Return In Transit"]]' },
    [ordered]@{ label="VIEW: Cases Returns Received";     type="DocType"; link_to="Dispatch Case"; doc_view="List"; stats_filter='[["status","=","Returns Received"]]' },
    [ordered]@{ label="VIEW: Cases Invoice Pending";      type="DocType"; link_to="Dispatch Case"; doc_view="List"; stats_filter='[["status","=","Invoice Pending"]]' },
    [ordered]@{ label="Unpaid Invoices (Aging)";          type="Report";  link_to="RPT ${EM} Receivables ${EM} Unpaid Invoices (Aging)" },
    [ordered]@{ label="Unallocated Advances";             type="Report";  link_to="RPT ${EM} Receivables ${EM} Unallocated Advances" },
    [ordered]@{ label="Prepaid Orders Awaiting Delivery"; type="Report";  link_to="RPT ${EM} Ops ${EM} Prepaid Orders Awaiting Delivery" },
    [ordered]@{ label="Debt Threshold Exceeded";          type="Report";  link_to="RPT ${EM} Risk ${EM} Debt Threshold Exceeded" },
    [ordered]@{ label="VIEW: Debt Collection Tasks";      type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Debt Collection"],["status","not in","Completed,Cancelled"]]' },
    [ordered]@{ label="VIEW: Distribute Payment Tasks";   type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Distribute Payment"],["status","not in","Completed,Cancelled"]]' },
    [ordered]@{ label="VIEW: Return to Warehouse Tasks";  type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Return to warehouse (aborted delivery / cancelled order)"],["status","not in","Completed,Cancelled"]]' },
    [ordered]@{ label="VIEW: Discount Approval Tasks";    type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Discount Approval"],["status","not in","Completed,Cancelled"]]' },
    [ordered]@{ label="VIEW: Purchase Approval Tasks";    type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Purchase Approval"],["status","not in","Completed,Cancelled"]]' },
    [ordered]@{ label="VIEW: Write-off Approval Tasks";   type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Write-off Approval"],["status","not in","Completed,Cancelled"]]' },
    [ordered]@{ label="Sales History by Client";          type="Report";  link_to="RPT ${EM} Sales ${EM} History by Client" },
    [ordered]@{ label="Manual Rate Edits";                type="Report";  link_to="RPT ${EM} Pricing ${EM} Sales Orders With Manual Rate Edits" },
    [ordered]@{ label="Near Expiry Stock";                type="Report";  link_to="RPT ${EM} Stock ${EM} Near Expiry (Main - Inmed)" },
    [ordered]@{ label="Tracked Items Missing Identifiers"; type="Report"; link_to="RPT ${EM} Data Quality ${EM} Tracked Items Missing Identifiers" },
    [ordered]@{ label="Collection Sets Readiness";         type="DocType"; link_to="Collection Set"; doc_view="List" },
    [ordered]@{ label="Price Overrides by Client";        type="DocType"; link_to="Item Price"; doc_view="List"; stats_filter='[["selling","=","1"],["customer","!=",""]]' }
)
$WsBody = [ordered]@{
    label     = $wsName
    title     = $wsName
    module    = "Custom"
    is_public = 1
    shortcuts = $WsShortcuts
    content   = '[]'
    charts    = @()
    links     = @()
}
if ($Mode -eq "Check") {
    Write-Host "  CHECK  workspace (would rebuild shortcuts)" -ForegroundColor Gray
} else {
    try {
        $r5 = Upsert-ErpDoc -DocType "Workspace" -Name $wsName -Body $WsBody
        Write-Host "  $($r5.action.ToUpper())  $wsName" -ForegroundColor Green
        $ok++
    } catch {
        Write-Host "  FAILED   $wsName : $($_.Exception.Message)" -ForegroundColor Red
        $err++
    }
}

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
Write-Host "`n================================"
Write-Host "Mode: $Mode   OK: $ok   ERR: $err"
if ($err -gt 0) { Write-Host "Check errors above before running export.ps1" -ForegroundColor Red }
elseif ($Mode -eq "Deploy") { Write-Host "All fixes applied. Run export.ps1 to sync snapshot." -ForegroundColor Green }
else { Write-Host "Check complete." -ForegroundColor Green }
