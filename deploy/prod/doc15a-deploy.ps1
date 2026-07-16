#Requires -Version 5.1
<#
.SYNOPSIS
  Doc 15A — Reporting Requirements: Phase 1 deployment.
  Creates custom field buffer_percentage on Item Reorder and
  deploys 7 new Query Reports (stock balance, entries, movement, sold items detail,
  sales documents and payments).

  Run BEFORE doc15b-deploy.ps1 — the buffer_percentage field must exist before the
  Norm/Reorder report (in doc15b) can be executed.

.PARAMETER Mode
  Check  — verify existence only (no writes)
  Deploy — create/update all artefacts (default)
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

# ---------------------------------------------------------------------------
# Custom field definition
# ---------------------------------------------------------------------------
$CustomFieldName = "Item Reorder-buffer_percentage"
$CustomFieldBody = [ordered]@{
    dt           = "Item Reorder"
    label        = "Safety Stock Buffer %"
    fieldname    = "buffer_percentage"
    fieldtype    = "Float"
    insert_after = "warehouse_reorder_qty"
    default      = "0.20"
    description  = "Safety stock buffer as a fraction (e.g. 0.20 = 20%). Used in norm calculation. Defaults to 20% when blank."
}

# ---------------------------------------------------------------------------
# Report definitions
# ---------------------------------------------------------------------------
$Reports = @()

# §5.1 — Stock Balance with filters (multi-field, all warehouses)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Stock ${EM} Balance Multi-Select"
    report_type = "Query Report"
    ref_doctype = "Bin"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  b.warehouse,
  b.item_code,
  i.item_name,
  i.item_group,
  i.brand,
  b.actual_qty,
  b.reserved_qty,
  b.ordered_qty,
  b.projected_qty
from `tabBin` b
join `tabItem` i on i.name = b.item_code
where
  b.actual_qty != 0
  and (%(warehouse)s is null or %(warehouse)s = '' or b.warehouse = %(warehouse)s)
  and (%(item_code)s is null or %(item_code)s = '' or b.item_code = %(item_code)s)
  and (%(item_group)s is null or %(item_group)s = '' or i.item_group = %(item_group)s)
  and (%(brand)s is null or %(brand)s = '' or i.brand = %(brand)s)
order by b.warehouse, i.item_group, b.item_code
"@
    filters     = @(
        [ordered]@{ fieldname="warehouse";   label="Warehouse";   fieldtype="Link"; options="Warehouse";   default="" },
        [ordered]@{ fieldname="item_code";   label="Item Code";   fieldtype="Link"; options="Item";        default="" },
        [ordered]@{ fieldname="item_group";  label="Item Group";  fieldtype="Link"; options="Item Group";  default="" },
        [ordered]@{ fieldname="brand";       label="Brand";       fieldtype="Data"; options="";            default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Inventory" },
        [ordered]@{ role = "Ops - Order Accepting" },
        [ordered]@{ role = "Ops - Returns" },
        [ordered]@{ role = "Ops - Purchasing" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §5.2 — Stock Balance by Batch and Expiry (all warehouses, with expiry status)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Stock ${EM} Batch and Expiry Balance"
    report_type = "Query Report"
    ref_doctype = "Stock Ledger Entry"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  sle.warehouse,
  sle.item_code,
  i.item_name,
  i.item_group,
  sle.batch_no,
  ba.expiry_date,
  case
    when ba.expiry_date is null then 'No Expiry'
    when ba.expiry_date < curdate() then 'Expired'
    when ba.expiry_date <= date_add(curdate(), interval 30 day) then 'Near Expiry'
    else 'Valid'
  end as expiry_status,
  datediff(ba.expiry_date, curdate()) as days_to_expiry,
  sum(sle.actual_qty) as qty
from `tabStock Ledger Entry` sle
join `tabItem` i on i.name = sle.item_code
left join `tabBatch` ba on ba.name = sle.batch_no
where
  sle.is_cancelled = 0
  and sle.batch_no is not null
  and sle.batch_no != ''
  and (%(warehouse)s is null or %(warehouse)s = '' or sle.warehouse = %(warehouse)s)
  and (%(item_code)s is null or %(item_code)s = '' or sle.item_code = %(item_code)s)
  and (%(item_group)s is null or %(item_group)s = '' or i.item_group = %(item_group)s)
group by sle.warehouse, sle.item_code, sle.batch_no
having qty > 0
order by ba.expiry_date asc, sle.warehouse, sle.item_code
"@
    filters     = @(
        [ordered]@{ fieldname="warehouse";  label="Warehouse";  fieldtype="Link"; options="Warehouse";  default="" },
        [ordered]@{ fieldname="item_code";  label="Item Code";  fieldtype="Link"; options="Item";       default="" },
        [ordered]@{ fieldname="item_group"; label="Item Group"; fieldtype="Link"; options="Item Group"; default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Inventory" },
        [ordered]@{ role = "Ops - Order Accepting" },
        [ordered]@{ role = "Ops - Returns" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §5.3 — Expiry Classification (item-level: Expirable / Non-Expirable)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Stock ${EM} Expiry Classification"
    report_type = "Query Report"
    ref_doctype = "Item"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  i.item_code,
  i.item_name,
  i.item_group,
  i.brand,
  case when i.has_expiry_date = 1 then 'Expirable' else 'Non-Expirable' end as expiry_tracking,
  case when i.has_batch_no = 1 then 'Yes' else 'No' end as batch_tracking,
  coalesce(stock.qty, 0) as stock_qty
from `tabItem` i
left join (
  select item_code, sum(actual_qty) as qty
  from `tabBin`
  where actual_qty > 0
  group by item_code
) stock on stock.item_code = i.name
where
  i.disabled = 0
  and i.is_stock_item = 1
  and coalesce(stock.qty, 0) > 0
  and (%(item_group)s is null or %(item_group)s = '' or i.item_group = %(item_group)s)
  and (
    %(expiry_tracking)s is null or %(expiry_tracking)s = ''
    or (%(expiry_tracking)s = 'Expirable'     and i.has_expiry_date = 1)
    or (%(expiry_tracking)s = 'Non-Expirable' and i.has_expiry_date = 0)
  )
order by i.item_group, i.has_expiry_date desc, i.item_code
"@
    filters     = @(
        [ordered]@{ fieldname="item_group";      label="Item Group";      fieldtype="Link";   options="Item Group"; default="" },
        [ordered]@{ fieldname="expiry_tracking"; label="Expiry Tracking"; fieldtype="Select"; options="Expirable`nNon-Expirable"; default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Inventory" },
        [ordered]@{ role = "Ops - Order Accepting" },
        [ordered]@{ role = "Ops - Purchasing" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §5.4 — Stock Entries by Period (all entry types with dispatch + surgery links)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Stock ${EM} Entries by Period"
    report_type = "Query Report"
    ref_doctype = "Stock Entry"
    is_standard = "No"
    disabled    = 0
    query       = @"
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
  se.surgery_case,
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
    filters     = @(
        [ordered]@{ fieldname="from_date";  label="From Date";  fieldtype="Date"; options=""; default="" },
        [ordered]@{ fieldname="to_date";    label="To Date";    fieldtype="Date"; options=""; default="" },
        [ordered]@{ fieldname="warehouse";  label="Warehouse";  fieldtype="Link"; options="Warehouse";  default="" },
        [ordered]@{ fieldname="item_code";  label="Item Code";  fieldtype="Link"; options="Item";       default="" },
        [ordered]@{ fieldname="item_group"; label="Item Group"; fieldtype="Link"; options="Item Group"; default="" },
        [ordered]@{ fieldname="purpose";    label="Entry Type"; fieldtype="Data"; options="";           default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Inventory" },
        [ordered]@{ role = "Ops - Order Accepting" },
        [ordered]@{ role = "Ops - Returns" },
        [ordered]@{ role = "Ops - Accounting" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §5.5 — Warehouse-to-Warehouse Movement (transfer/dispatch entries with Dispatch Case link)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Stock ${EM} Warehouse Movement"
    report_type = "Query Report"
    ref_doctype = "Stock Entry"
    is_standard = "No"
    disabled    = 0
    query       = @"
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
  se.surgery_case,
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
    filters     = @(
        [ordered]@{ fieldname="from_date";         label="From Date";       fieldtype="Date"; options="";            default="" },
        [ordered]@{ fieldname="to_date";           label="To Date";         fieldtype="Date"; options="";            default="" },
        [ordered]@{ fieldname="s_warehouse";       label="From Warehouse";  fieldtype="Link"; options="Warehouse";   default="" },
        [ordered]@{ fieldname="t_warehouse";       label="To Warehouse";    fieldtype="Link"; options="Warehouse";   default="" },
        [ordered]@{ fieldname="item_code";         label="Item Code";       fieldtype="Link"; options="Item";        default="" },
        [ordered]@{ fieldname="dispatch_group_id"; label="Dispatch Case";   fieldtype="Data"; options="";            default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Inventory" },
        [ordered]@{ role = "Ops - Order Accepting" },
        [ordered]@{ role = "Ops - Returns" },
        [ordered]@{ role = "Delivery Driver" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §6.1 — Sold Items Detail with buying price and gross profit (Directors only)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Sales ${EM} Sold Items Detail"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  si.posting_date,
  si.name              as sales_invoice,
  si.customer,
  si.hospital,
  si.hospital_branch,
  si.doctor_name,
  si.status            as payment_status,
  si.surgery_case,
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
    filters     = @(
        [ordered]@{ fieldname="customer";       label="Customer";       fieldtype="Link";   options="Customer";   default="" },
        [ordered]@{ fieldname="from_date";      label="From Date";      fieldtype="Date";   options="";           default="" },
        [ordered]@{ fieldname="to_date";        label="To Date";        fieldtype="Date";   options="";           default="" },
        [ordered]@{ fieldname="item_code";      label="Item Code";      fieldtype="Link";   options="Item";       default="" },
        [ordered]@{ fieldname="item_group";     label="Item Group";     fieldtype="Link";   options="Item Group"; default="" },
        [ordered]@{ fieldname="payment_status"; label="Payment Status"; fieldtype="Select"; options="Unpaid`nPartly Paid`nPaid`nOverdue"; default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §6.2 — Sales Documents and Payments (invoice ↔ payment linkage)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Accounting ${EM} Sales Documents and Payments"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  si.posting_date,
  si.name            as sales_invoice,
  si.customer,
  si.grand_total,
  si.outstanding_amount,
  si.status          as payment_status,
  pe.name            as payment_entry,
  pe.posting_date    as payment_date,
  per.allocated_amount,
  pe.reference_no    as bank_ref
from `tabSales Invoice` si
left join `tabPayment Entry Reference` per
  on per.reference_doctype = 'Sales Invoice'
  and per.reference_name = si.name
left join `tabPayment Entry` pe
  on pe.name = per.parent
  and pe.docstatus = 1
where
  si.docstatus = 1
  and (%(customer)s is null or %(customer)s = '' or si.customer = %(customer)s)
  and (%(from_date)s is null or %(from_date)s = '' or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or si.posting_date <= %(to_date)s)
  and (%(payment_status)s is null or %(payment_status)s = '' or si.status = %(payment_status)s)
order by si.posting_date desc, si.name desc
"@
    filters     = @(
        [ordered]@{ fieldname="customer";       label="Customer";       fieldtype="Link";   options="Customer"; default="" },
        [ordered]@{ fieldname="from_date";      label="From Date";      fieldtype="Date";   options="";         default="" },
        [ordered]@{ fieldname="to_date";        label="To Date";        fieldtype="Date";   options="";         default="" },
        [ordered]@{ fieldname="payment_status"; label="Payment Status"; fieldtype="Select"; options="Unpaid`nPartly Paid`nPaid`nOverdue"; default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Accounting" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# ---------------------------------------------------------------------------
# Snapshot helper
# ---------------------------------------------------------------------------
function Get-Snapshot {
    $S = [ordered]@{ mode="Verify"; custom_field=$null; reports=@() }
    $CF = Get-ErpDoc -DocType "Custom Field" -Name $CustomFieldName
    $S.custom_field = [pscustomobject]@{ name=$CustomFieldName; exists=($null -ne $CF) }
    foreach ($Rpt in $Reports) {
        $E = Get-ErpDoc -DocType "Report" -Name $Rpt.rpt_name
        $S.reports += [pscustomobject]@{ name=$Rpt.rpt_name; exists=($null -ne $E) }
    }
    return $S
}

# ---------------------------------------------------------------------------
# Check mode
# ---------------------------------------------------------------------------
if ($Mode -eq "Check") {
    Get-Snapshot | ConvertTo-Json -Depth 5
    return
}

# ---------------------------------------------------------------------------
# Deploy mode
# ---------------------------------------------------------------------------
$Results = [ordered]@{ mode="Deploy"; custom_field=$null; reports=@() }

Write-Host "--- Deploying Custom Field: buffer_percentage on Item Reorder ---"
$Results.custom_field = Upsert-ErpDoc -DocType "Custom Field" -Name $CustomFieldName -Body $CustomFieldBody

Write-Host "--- Deploying Query Reports ---"
foreach ($Rpt in $Reports) {
    $N    = $Rpt.rpt_name
    $Body = [ordered]@{
        report_name = $N
        report_type = $Rpt.report_type
        ref_doctype = $Rpt.ref_doctype
        is_standard = $Rpt.is_standard
        disabled    = $Rpt.disabled
        query       = $Rpt.query
        filters     = $Rpt.filters
        roles       = $Rpt.roles
    }
    $Result = Upsert-ErpDoc -DocType "Report" -Name $N -Body $Body
    $Results.reports += $Result
    Write-Host "  $($Result.action): $N"
}

Write-Host ""
Write-Host "--- Deploy results ---"
$Results | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "--- Post-deploy verification ---"
Get-Snapshot | ConvertTo-Json -Depth 5

exit 0
