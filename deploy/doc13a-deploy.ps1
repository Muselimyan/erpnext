#Requires -Version 5.1
<#
.SYNOPSIS
  Doc 13A — Reporting Pack deployment script.
  Creates 16 Query Reports and the Ops — Reporting Pack workspace.
  Named list views (VIEW — ...) are documented in migration-notes.md as manual steps.

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
# Report definitions  ($Reports = ordered array; rpt_name = actual ERPNext name)
# ---------------------------------------------------------------------------
$Reports = @()

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Stock ${EM} Client Locations (All)"
    report_type  = "Query Report"
    ref_doctype  = "Bin"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  b.warehouse as client_location_warehouse,
  b.item_code,
  i.item_name,
  i.item_group,
  b.actual_qty
from `tabBin` b
join `tabWarehouse` w on w.name = b.warehouse
join `tabItem` i on i.name = b.item_code
where
  w.parent_warehouse = 'Clients - Inmed'
  and w.is_group = 0
  and b.actual_qty > 0
  and (%(client_location_warehouse)s is null or %(client_location_warehouse)s = '' or b.warehouse = %(client_location_warehouse)s)
  and (%(item_group)s is null or %(item_group)s = '' or i.item_group = %(item_group)s)
  and (%(item_code)s is null or %(item_code)s = '' or b.item_code = %(item_code)s)
order by b.warehouse, i.item_group, b.item_code
"@
    filters = @(
        [ordered]@{ fieldname="client_location_warehouse"; label="Client Location Warehouse"; fieldtype="Link"; options="Warehouse"; default="" },
        [ordered]@{ fieldname="item_group";                label="Item Group";                fieldtype="Link"; options="Item Group"; default="" },
        [ordered]@{ fieldname="item_code";                 label="Item Code";                 fieldtype="Link"; options="Item";       default="" }
    )
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Stock ${EM} Delivery In-Transit - Inmed"
    report_type  = "Query Report"
    ref_doctype  = "Bin"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  b.item_code,
  i.item_name,
  i.item_group,
  b.actual_qty
from `tabBin` b
join `tabItem` i on i.name = b.item_code
where
  b.warehouse = 'Delivery In-Transit - Inmed'
  and b.actual_qty > 0
order by i.item_group, b.item_code
"@
    filters = @()
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Stock ${EM} Return Pickup In-Transit - Inmed"
    report_type  = "Query Report"
    ref_doctype  = "Bin"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  b.item_code,
  i.item_name,
  i.item_group,
  b.actual_qty
from `tabBin` b
join `tabItem` i on i.name = b.item_code
where
  b.warehouse = 'Return Pickup In-Transit - Inmed'
  and b.actual_qty > 0
order by i.item_group, b.item_code
"@
    filters = @()
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Stock ${EM} Returns - Inmed"
    report_type  = "Query Report"
    ref_doctype  = "Bin"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  b.item_code,
  i.item_name,
  i.item_group,
  b.actual_qty
from `tabBin` b
join `tabItem` i on i.name = b.item_code
where
  b.warehouse = 'Returns - Inmed'
  and b.actual_qty > 0
order by i.item_group, b.item_code
"@
    filters = @()
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Ops ${EM} Driver Task Queue (Derived)"
    report_type  = "Query Report"
    ref_doctype  = "Task"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  json_unquote(json_extract(t._assign, '$[0]')) as assigned_to,
  t.name as task,
  t.task_kind,
  t.status,
  t.customer,
  t.surgery_case,
  t.sales_order,
  t.sales_invoice,
  t.dispatch_group_id,
  t.subject,
  t.modified
from `tabTask` t
where
  t.status not in ('Completed', 'Cancelled')
  and t.task_kind in ('Delivery', 'Pickup Returns', 'Return drop-off at warehouse')
  and (
    %(assigned_to)s is null
    or %(assigned_to)s = ''
    or t._assign like concat('%', %(assigned_to)s, '%')
  )
order by assigned_to, t.modified asc
"@
    filters = @(
        [ordered]@{ fieldname="assigned_to"; label="Assigned To"; fieldtype="Link"; options="User"; default="" }
    )
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Stock ${EM} In-Transit Stuck (Age Check)"
    report_type  = "Query Report"
    ref_doctype  = "Stock Ledger Entry"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  b.warehouse,
  b.item_code,
  i.item_name,
  b.actual_qty,
  x.last_movement_date,
  datediff(curdate(), x.last_movement_date) as days_since_last_movement
from `tabBin` b
join `tabItem` i on i.name = b.item_code
join (
  select
    warehouse,
    item_code,
    max(posting_date) as last_movement_date
  from `tabStock Ledger Entry`
  where
    is_cancelled = 0
    and warehouse in ('Delivery In-Transit - Inmed', 'Return Pickup In-Transit - Inmed')
  group by warehouse, item_code
) x on x.warehouse = b.warehouse and x.item_code = b.item_code
where
  b.warehouse in ('Delivery In-Transit - Inmed', 'Return Pickup In-Transit - Inmed')
  and b.actual_qty > 0
  and datediff(curdate(), x.last_movement_date) >= %(min_days)s
order by days_since_last_movement desc, b.warehouse, b.item_code
"@
    filters = @(
        [ordered]@{ fieldname="min_days"; label="Min Days"; fieldtype="Int"; options=""; default="1" }
    )
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Surgery Cases ${EM} Aging (Open)"
    report_type  = "Query Report"
    ref_doctype  = "Surgery Case"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  sc.name as surgery_case,
  sc.workflow_state,
  sc.client,
  sc.hospital,
  sc.hospital_branch,
  sc.surgery_date,
  sc.delivery_person,
  sc.return_pickup_delivery_person,
  sc.modified,
  datediff(curdate(), date(sc.modified)) as age_days
from `tabSurgery Case` sc
where
  sc.workflow_state not in ('Closed')
  and (%(min_age_days)s is null or datediff(curdate(), date(sc.modified)) >= %(min_age_days)s)
order by age_days desc, sc.modified asc
"@
    filters = @(
        [ordered]@{ fieldname="min_age_days"; label="Min Age Days"; fieldtype="Int"; options=""; default="0" }
    )
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Receivables ${EM} Unpaid Invoices (Aging)"
    report_type  = "Query Report"
    ref_doctype  = "Sales Invoice"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  si.customer,
  si.name as sales_invoice,
  si.posting_date,
  si.due_date,
  si.status,
  si.outstanding_amount,
  datediff(curdate(), si.posting_date) as age_days,
  datediff(curdate(), si.due_date) as overdue_days
from `tabSales Invoice` si
where
  si.docstatus = 1
  and si.outstanding_amount > 0
  and (%(customer)s is null or %(customer)s = '' or si.customer = %(customer)s)
  and (%(from_date)s is null or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or si.posting_date <= %(to_date)s)
order by si.customer, overdue_days desc, age_days desc
"@
    filters = @(
        [ordered]@{ fieldname="customer";   label="Customer";   fieldtype="Link"; options="Customer"; default="" },
        [ordered]@{ fieldname="from_date";  label="From Date";  fieldtype="Date"; options="";          default="" },
        [ordered]@{ fieldname="to_date";    label="To Date";    fieldtype="Date"; options="";          default="" }
    )
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Receivables ${EM} Unallocated Advances"
    report_type  = "Query Report"
    ref_doctype  = "Payment Entry"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  pe.party as customer,
  pe.name as payment_entry,
  pe.posting_date,
  pe.paid_amount,
  coalesce(sum(per.allocated_amount), 0) as allocated_amount,
  (pe.paid_amount - coalesce(sum(per.allocated_amount), 0)) as unallocated_amount
from `tabPayment Entry` pe
left join `tabPayment Entry Reference` per
  on per.parent = pe.name
  and per.reference_doctype = 'Sales Invoice'
where
  pe.docstatus = 1
  and pe.party_type = 'Customer'
  and pe.payment_type = 'Receive'
  and (%(customer)s is null or %(customer)s = '' or pe.party = %(customer)s)
group by pe.name
having unallocated_amount > 0.0001
order by pe.party, pe.posting_date desc
"@
    filters = @(
        [ordered]@{ fieldname="customer"; label="Customer"; fieldtype="Link"; options="Customer"; default="" }
    )
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Ops ${EM} Prepaid Orders Awaiting Delivery"
    report_type  = "Query Report"
    ref_doctype  = "Sales Order"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  so.customer,
  so.name as sales_order,
  so.transaction_date,
  so.delivery_date,
  so.grand_total,
  so.per_delivered,
  coalesce(sum(case when pe.name is not null then per.allocated_amount else 0 end), 0) as advance_allocated
from `tabSales Order` so
left join `tabPayment Entry Reference` per
  on per.reference_doctype = 'Sales Order'
  and per.reference_name = so.name
left join `tabPayment Entry` pe
  on pe.name = per.parent
  and pe.docstatus = 1
  and pe.party_type = 'Customer'
  and pe.payment_type = 'Receive'
where
  so.docstatus = 1
  and so.status not in ('Closed', 'Completed')
  and so.per_delivered < 100
  and (%(customer)s is null or %(customer)s = '' or so.customer = %(customer)s)
group by so.name
having advance_allocated > 0
order by so.delivery_date asc, so.transaction_date asc
"@
    filters = @(
        [ordered]@{ fieldname="customer"; label="Customer"; fieldtype="Link"; options="Customer"; default="" }
    )
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Risk ${EM} Debt Threshold Exceeded"
    report_type  = "Query Report"
    ref_doctype  = "Customer"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  c.name as customer,
  c.customer_name,
  c.debt_threshold_amd,
  coalesce(gl.net_receivable_amd, 0) as net_receivable_amd,
  (coalesce(gl.net_receivable_amd, 0) - coalesce(c.debt_threshold_amd, 0)) as exceeded_by_amd
from `tabCustomer` c
left join (
  select
    party as customer,
    sum(debit - credit) as net_receivable_amd
  from `tabGL Entry`
  where
    is_cancelled = 0
    and party_type = 'Customer'
  group by party
) gl on gl.customer = c.name
where
  c.disabled = 0
  and coalesce(c.debt_threshold_amd, 0) > 0
  and coalesce(gl.net_receivable_amd, 0) > coalesce(c.debt_threshold_amd, 0)
order by exceeded_by_amd desc
"@
    filters = @()
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Sales ${EM} History by Client"
    report_type  = "Query Report"
    ref_doctype  = "Sales Invoice"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  si.customer,
  si.hospital,
  si.hospital_branch,
  si.doctor_name,
  si.name as sales_invoice,
  si.posting_date,
  sii.item_code,
  sii.item_name,
  sii.qty,
  sii.rate,
  sii.amount
from `tabSales Invoice` si
join `tabSales Invoice Item` sii on sii.parent = si.name
where
  si.docstatus = 1
  and (%(customer)s is null or %(customer)s = '' or si.customer = %(customer)s)
  and (%(from_date)s is null or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or si.posting_date <= %(to_date)s)
order by si.customer, si.posting_date desc, si.name desc
"@
    filters = @(
        [ordered]@{ fieldname="customer";   label="Customer";   fieldtype="Link"; options="Customer"; default="" },
        [ordered]@{ fieldname="from_date";  label="From Date";  fieldtype="Date"; options="";          default="" },
        [ordered]@{ fieldname="to_date";    label="To Date";    fieldtype="Date"; options="";          default="" }
    )
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Stock ${EM} Near Expiry (Main - Inmed)"
    report_type  = "Query Report"
    ref_doctype  = "Stock Ledger Entry"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  sle.item_code,
  i.item_name,
  sle.batch_no,
  b.expiry_date,
  sum(sle.actual_qty) as qty_in_main_wh,
  datediff(b.expiry_date, curdate()) as days_to_expiry
from `tabStock Ledger Entry` sle
join `tabBatch` b on b.name = sle.batch_no
join `tabItem` i on i.name = sle.item_code
where
  sle.is_cancelled = 0
  and sle.warehouse = 'Main - Inmed'
  and sle.batch_no is not null
  and sle.batch_no != ''
  and b.expiry_date is not null
  and b.expiry_date <= date_add(curdate(), interval %(near_expiry_days)s day)
group by sle.item_code, sle.batch_no
having qty_in_main_wh > 0
order by b.expiry_date asc, sle.item_code
"@
    filters = @(
        [ordered]@{ fieldname="near_expiry_days"; label="Near Expiry Days"; fieldtype="Int"; options=""; default="30" }
    )
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Ops ${EM} Client Stock With No Open Cases"
    report_type  = "Query Report"
    ref_doctype  = "Warehouse"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  w.name as client_location_warehouse,
  sum(b.actual_qty) as total_qty
from `tabWarehouse` w
join `tabBin` b on b.warehouse = w.name
left join `tabSurgery Case` sc
  on sc.client_location_warehouse = w.name
  and sc.workflow_state not in ('Closed')
where
  w.parent_warehouse = 'Clients - Inmed'
  and w.is_group = 0
group by w.name
having
  total_qty > 0
  and count(sc.name) = 0
order by total_qty desc
"@
    filters = @()
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Data Quality ${EM} Tracked Items Missing Identifiers"
    report_type  = "Query Report"
    ref_doctype  = "Stock Entry"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  se.name as stock_entry,
  se.posting_date,
  sed.item_code,
  i.item_name,
  i.has_batch_no,
  i.has_serial_no,
  sed.qty,
  sed.s_warehouse,
  sed.t_warehouse,
  sed.batch_no,
  sed.serial_no
from `tabStock Entry` se
join `tabStock Entry Detail` sed on sed.parent = se.name
join `tabItem` i on i.name = sed.item_code
where
  se.docstatus = 1
  and (
    (i.has_batch_no = 1 and (sed.batch_no is null or sed.batch_no = ''))
    or
    (i.has_serial_no = 1 and (sed.serial_no is null or sed.serial_no = ''))
  )
order by se.posting_date desc, se.name desc
"@
    filters = @()
}

$Reports += [ordered]@{
    rpt_name     = "RPT ${EM} Pricing ${EM} Sales Orders With Manual Rate Edits"
    report_type  = "Query Report"
    ref_doctype  = "Sales Order"
    is_standard  = "No"
    disabled     = 0
    query        = @"
select
  so.customer,
  so.name as sales_order,
  so.transaction_date,
  soi.item_code,
  soi.item_name,
  soi.qty,
  soi.price_list_rate,
  soi.rate,
  (soi.rate - soi.price_list_rate) as rate_diff
from `tabSales Order` so
join `tabSales Order Item` soi on soi.parent = so.name
where
  so.docstatus = 1
  and abs(soi.rate - soi.price_list_rate) > 0.0001
order by so.transaction_date desc, so.name desc
"@
    filters = @()
}

# ---------------------------------------------------------------------------
# Workspace definition
# ---------------------------------------------------------------------------
$WsShortcuts = @(
    [ordered]@{ label="Delivery In-Transit Stock";        type="Report";  link_to="RPT ${EM} Stock ${EM} Delivery In-Transit - Inmed" },
    [ordered]@{ label="Return Pickup In-Transit Stock";   type="Report";  link_to="RPT ${EM} Stock ${EM} Return Pickup In-Transit - Inmed" },
    [ordered]@{ label="Returns Backlog";                  type="Report";  link_to="RPT ${EM} Stock ${EM} Returns - Inmed" },
    [ordered]@{ label="Client Locations Stock";           type="Report";  link_to="RPT ${EM} Stock ${EM} Client Locations (All)" },
    [ordered]@{ label="In-Transit Stuck Check";           type="Report";  link_to="RPT ${EM} Stock ${EM} In-Transit Stuck (Age Check)" },
    [ordered]@{ label="Client Stock (No Open Cases)";     type="Report";  link_to="RPT ${EM} Ops ${EM} Client Stock With No Open Cases" },
    [ordered]@{ label="Driver Task Queue";                type="Report";  link_to="RPT ${EM} Ops ${EM} Driver Task Queue (Derived)" },
    [ordered]@{ label="Surgery Cases Aging (Open)";       type="Report";  link_to="RPT ${EM} Surgery Cases ${EM} Aging (Open)" },
    [ordered]@{ label="VIEW: Cases Delivered";            type="DocType"; link_to="Surgery Case"; doc_view="List"; stats_filter='[["workflow_state","=","Delivered"]]' },
    [ordered]@{ label="VIEW: Cases Pickup In Transit";    type="DocType"; link_to="Surgery Case"; doc_view="List"; stats_filter='[["workflow_state","=","Return Pickup In Transit"]]' },
    [ordered]@{ label="VIEW: Cases Returns Received";     type="DocType"; link_to="Surgery Case"; doc_view="List"; stats_filter='[["workflow_state","=","Returns Received"]]' },
    [ordered]@{ label="VIEW: Cases Usage Derived";        type="DocType"; link_to="Surgery Case"; doc_view="List"; stats_filter='[["workflow_state","=","Usage Derived"]]' },
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
    [ordered]@{ label="Surgery Set Types Readiness";      type="DocType"; link_to="Surgery Set Type"; doc_view="List" },
    [ordered]@{ label="Price Overrides by Client";        type="DocType"; link_to="Item Price"; doc_view="List"; stats_filter='[["selling","=","1"],["customer","!=",""]]' }
)

$WsName = "Ops ${EM} Reporting Pack"
$WorkspaceBody = [ordered]@{
    label     = $WsName
    title     = $WsName
    module    = "Custom"
    is_public = 1
    shortcuts = $WsShortcuts
    content   = '[]'
    charts    = @()
    links     = @()
}

# ---------------------------------------------------------------------------
# Snapshot helper
# ---------------------------------------------------------------------------
function Get-Snapshot {
    $S = [ordered]@{ mode="Verify"; reports=@(); workspace=$null }
    foreach ($Rpt in $Reports) {
        $E = Get-ErpDoc -DocType "Report" -Name $Rpt.rpt_name
        $S.reports += [pscustomobject]@{ name=$Rpt.rpt_name; exists=($null -ne $E) }
    }
    $W = Get-ErpDoc -DocType "Workspace" -Name $WsName
    $S.workspace = [pscustomobject]@{ name=$WsName; exists=($null -ne $W) }
    return $S
}

# ---------------------------------------------------------------------------
# Check mode
# ---------------------------------------------------------------------------
if ($Mode -eq "Check") {
    $Report = [ordered]@{ mode="Check"; reports=@(); workspace=$null }
    foreach ($Rpt in $Reports) {
        $E = Get-ErpDoc -DocType "Report" -Name $Rpt.rpt_name
        $Report.reports += [pscustomobject]@{ name=$Rpt.rpt_name; exists=($null -ne $E) }
    }
    $W = Get-ErpDoc -DocType "Workspace" -Name $WsName
    $Report.workspace = [pscustomobject]@{ name=$WsName; exists=($null -ne $W) }
    $Report | ConvertTo-Json -Depth 5
    return
}

# ---------------------------------------------------------------------------
# Deploy mode
# ---------------------------------------------------------------------------
$Results = [ordered]@{
    mode           = "Deploy"
    reports        = @()
    workspace      = $null
}

Write-Host "--- Deploying Query Reports ---"
foreach ($Rpt in $Reports) {
    $N = $Rpt.rpt_name
    $Body = [ordered]@{
        report_name = $N
        report_type = $Rpt.report_type
        ref_doctype = $Rpt.ref_doctype
        is_standard = $Rpt.is_standard
        disabled    = $Rpt.disabled
        query       = $Rpt.query
        filters     = $Rpt.filters
    }
    $Result = Upsert-ErpDoc -DocType "Report" -Name $N -Body $Body
    $Results.reports += $Result
}

Write-Host "--- Deploying Workspace ---"
$Results.workspace = Upsert-ErpDoc -DocType "Workspace" -Name $WsName -Body $WorkspaceBody

Write-Host ""
Write-Host "--- Deploy results ---"
$Results | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "--- Post-deploy verification ---"
Get-Snapshot | ConvertTo-Json -Depth 5

exit 0
