#Requires -Version 5.1
<#
.SYNOPSIS
  Remove stale surgery_case SELECT columns from 4 reports deployed by Doc 15A/15C.
  - RPT — Data Quality — Missing Doctor or Hospital
  - RPT — Sales — Sold Items Detail
  - RPT — Stock — Entries by Period
  - RPT — Stock — Warehouse Movement
  No dispatch_case field exists on Sales Invoice or Stock Entry; Stock Entry reports
  already carry dispatch_group_id as the Dispatch Case identifier.
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

function Set-ErpQuery {
    param([string]$ReportName, [string]$Query)
    if ($Mode -eq "Check") { Write-Host "  CHECK  $ReportName  (would patch)" -ForegroundColor Gray; return $true }
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

$ok = 0; $err = 0
function tally($r) { if ($r) { $script:ok++ } else { $script:err++ } }

# ---------------------------------------------------------------
# 1. RPT — Data Quality — Missing Doctor or Hospital
#    Remove: si.surgery_case
# ---------------------------------------------------------------
Write-Host "`n[1] RPT ${EM} Data Quality ${EM} Missing Doctor or Hospital"
$q1 = @"
select
  si.name         as sales_invoice,
  si.posting_date,
  si.customer,
  si.grand_total,
  si.status
from `tabSales Invoice` si
where
  si.docstatus = 1
  and (si.hospital   is null or si.hospital   = '')
  and (si.doctor_name is null or si.doctor_name = '')
  and (%(from_date)s is null or %(from_date)s = '' or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or si.posting_date <= %(to_date)s)
order by si.posting_date desc
"@
tally (Set-ErpQuery "RPT ${EM} Data Quality ${EM} Missing Doctor or Hospital" $q1)

# ---------------------------------------------------------------
# 2. RPT — Sales — Sold Items Detail
#    Remove: si.surgery_case
# ---------------------------------------------------------------
Write-Host "`n[2] RPT ${EM} Sales ${EM} Sold Items Detail"
$q2 = @"
select
  si.posting_date,
  si.name              as sales_invoice,
  si.customer,
  si.hospital,
  si.hospital_branch,
  si.doctor_name,
  si.status            as payment_status,
  sii.item_code,
  sii.item_name,
  sii.item_group,
  sii.qty,
  sii.uom,
  sii.rate             as selling_price,
  sii.amount           as selling_amount,
  coalesce(bp.price_list_rate, 0)                                    as buying_price,
  sii.qty * coalesce(bp.price_list_rate, 0)                          as buying_amount,
  sii.amount - sii.qty * coalesce(bp.price_list_rate, 0)             as gross_profit,
  sii.batch_no,
  sii.serial_no,
  si.sales_order
from `tabSales Invoice` si
join `tabSales Invoice Item` sii on sii.parent = si.name
left join (
  select item_code, max(price_list_rate) as price_list_rate
  from `tabItem Price`
  where price_list = 'Standard Buying' and buying = 1
  group by item_code
) bp on bp.item_code = sii.item_code
where
  si.docstatus = 1
  and (%(customer)s is null or %(customer)s = '' or si.customer = %(customer)s)
  and (%(from_date)s is null or %(from_date)s = '' or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or si.posting_date <= %(to_date)s)
  and (%(item_code)s is null or %(item_code)s = '' or sii.item_code = %(item_code)s)
  and (%(item_group)s is null or %(item_group)s = '' or sii.item_group = %(item_group)s)
  and (%(payment_status)s is null or %(payment_status)s = '' or si.status = %(payment_status)s)
order by si.posting_date desc, si.name desc
"@
tally (Set-ErpQuery "RPT ${EM} Sales ${EM} Sold Items Detail" $q2)

# ---------------------------------------------------------------
# 3. RPT — Stock — Entries by Period
#    Remove: se.surgery_case  (dispatch_group_id already present)
# ---------------------------------------------------------------
Write-Host "`n[3] RPT ${EM} Stock ${EM} Entries by Period"
$q3 = @"
select
  se.posting_date,
  se.name            as stock_entry,
  se.purpose         as entry_type,
  sed.s_warehouse,
  sed.t_warehouse,
  sed.item_code,
  i.item_name,
  i.item_group,
  sed.qty,
  sed.batch_no,
  sed.serial_no,
  se.sales_order,
  se.dispatch_group_id,
  se.owner           as created_by,
  se.remarks
from `tabStock Entry` se
join `tabStock Entry Detail` sed on sed.parent = se.name
join `tabItem` i on i.name = sed.item_code
where
  se.docstatus = 1
  and (%(from_date)s is null or %(from_date)s = '' or se.posting_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or se.posting_date <= %(to_date)s)
  and (%(warehouse)s is null or %(warehouse)s = '' or sed.s_warehouse = %(warehouse)s or sed.t_warehouse = %(warehouse)s)
  and (%(item_code)s is null or %(item_code)s = '' or sed.item_code = %(item_code)s)
  and (%(item_group)s is null or %(item_group)s = '' or i.item_group = %(item_group)s)
  and (%(purpose)s is null or %(purpose)s = '' or se.purpose = %(purpose)s)
order by se.posting_date desc, se.name desc
"@
tally (Set-ErpQuery "RPT ${EM} Stock ${EM} Entries by Period" $q3)

# ---------------------------------------------------------------
# 4. RPT — Stock — Warehouse Movement
#    Remove: se.surgery_case  (dispatch_group_id already present)
# ---------------------------------------------------------------
Write-Host "`n[4] RPT ${EM} Stock ${EM} Warehouse Movement"
$q4 = @"
select
  se.posting_date,
  se.name              as stock_entry,
  se.purpose           as movement_type,
  sed.s_warehouse,
  sed.t_warehouse,
  sed.item_code,
  i.item_name,
  i.item_group,
  sed.qty,
  sed.batch_no,
  sed.serial_no,
  se.sales_order,
  se.dispatch_group_id,
  se.remarks
from `tabStock Entry` se
join `tabStock Entry Detail` sed on sed.parent = se.name
join `tabItem` i on i.name = sed.item_code
where
  se.docstatus = 1
  and sed.s_warehouse is not null and sed.s_warehouse != ''
  and sed.t_warehouse is not null and sed.t_warehouse != ''
  and (%(from_date)s is null or %(from_date)s = '' or se.posting_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or se.posting_date <= %(to_date)s)
  and (%(s_warehouse)s is null or %(s_warehouse)s = '' or sed.s_warehouse = %(s_warehouse)s)
  and (%(t_warehouse)s is null or %(t_warehouse)s = '' or sed.t_warehouse = %(t_warehouse)s)
  and (%(item_code)s is null or %(item_code)s = '' or sed.item_code = %(item_code)s)
  and (%(dispatch_group_id)s is null or %(dispatch_group_id)s = '' or se.dispatch_group_id = %(dispatch_group_id)s)
order by se.posting_date desc, se.name desc
"@
tally (Set-ErpQuery "RPT ${EM} Stock ${EM} Warehouse Movement" $q4)

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
Write-Host "`n================================"
Write-Host "Mode: $Mode   OK: $ok   ERR: $err"
if ($err -gt 0) { Write-Host "Check errors above." -ForegroundColor Red }
elseif ($Mode -eq "Deploy") { Write-Host "Done. Run export.ps1 to sync snapshot." -ForegroundColor Green }
else { Write-Host "Check complete." -ForegroundColor Green }
