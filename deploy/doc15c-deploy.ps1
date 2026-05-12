#Requires -Version 5.1
<#
.SYNOPSIS
  Doc 15C — Reporting Requirements: Phase 3/4 deployment.
  Deploys 6 final Query Reports (Comparative Periods, Slow-Moving, Near Expiry Value
  at Risk, Missing Doctor or Hospital, Negative Stock, Supplier Performance) and
  updates the Ops — Reporting Pack workspace with shortcuts to all Doc 15 reports.

  PREREQUISITE: Run doc15a-deploy.ps1 and doc15b-deploy.ps1 first.

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
# Report definitions
# ---------------------------------------------------------------------------
$Reports = @()

# §8.3 — Sales Comparative Periods (item-level comparison between two date ranges)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Sales ${EM} Comparative Periods"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  sii.item_code,
  i.item_name,
  i.item_group,
  sum(case when si.posting_date between %(period1_from)s and %(period1_to)s then sii.qty    else 0 end) as p1_qty,
  sum(case when si.posting_date between %(period1_from)s and %(period1_to)s then sii.amount else 0 end) as p1_amount,
  sum(case when si.posting_date between %(period2_from)s and %(period2_to)s then sii.qty    else 0 end) as p2_qty,
  sum(case when si.posting_date between %(period2_from)s and %(period2_to)s then sii.amount else 0 end) as p2_amount,
  sum(case when si.posting_date between %(period2_from)s and %(period2_to)s then sii.amount else 0 end)
    - sum(case when si.posting_date between %(period1_from)s and %(period1_to)s then sii.amount else 0 end) as change_amount
from `tabSales Invoice` si
join `tabSales Invoice Item` sii on sii.parent = si.name
join `tabItem` i on i.name = sii.item_code
where
  si.docstatus = 1
  and (
    (si.posting_date between %(period1_from)s and %(period1_to)s)
    or (si.posting_date between %(period2_from)s and %(period2_to)s)
  )
  and (%(item_group)s is null or %(item_group)s = '' or sii.item_group = %(item_group)s)
  and (%(customer)s is null or %(customer)s = '' or si.customer = %(customer)s)
group by sii.item_code
having (p1_amount > 0 or p2_amount > 0)
order by p2_amount desc
"@
    filters     = @(
        [ordered]@{ fieldname="period1_from"; label="Period 1 From"; fieldtype="Date"; options=""; default="" },
        [ordered]@{ fieldname="period1_to";   label="Period 1 To";   fieldtype="Date"; options=""; default="" },
        [ordered]@{ fieldname="period2_from"; label="Period 2 From"; fieldtype="Date"; options=""; default="" },
        [ordered]@{ fieldname="period2_to";   label="Period 2 To";   fieldtype="Date"; options=""; default="" },
        [ordered]@{ fieldname="item_group";   label="Item Group";    fieldtype="Link"; options="Item Group"; default="" },
        [ordered]@{ fieldname="customer";     label="Customer";      fieldtype="Link"; options="Customer";   default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §9.1 — Slow-Moving Products (in stock but no outbound movement for N+ days)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Stock ${EM} Slow-Moving Products"
    report_type = "Query Report"
    ref_doctype = "Bin"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  i.item_code,
  i.item_name,
  i.item_group,
  i.brand,
  coalesce(stock.qty, 0)  as current_stock,
  sales.last_sale_date,
  datediff(curdate(), coalesce(sales.last_sale_date, date(i.creation))) as days_since_last_sale
from `tabItem` i
left join (
  select item_code, sum(actual_qty) as qty
  from `tabBin`
  where actual_qty > 0
  group by item_code
) stock on stock.item_code = i.name
left join (
  select item_code, max(posting_date) as last_sale_date
  from `tabStock Ledger Entry`
  where
    is_cancelled = 0
    and actual_qty < 0
    and voucher_type in ('Sales Invoice', 'Delivery Note')
  group by item_code
) sales on sales.item_code = i.name
where
  i.disabled = 0
  and i.is_stock_item = 1
  and coalesce(stock.qty, 0) > 0
  and datediff(curdate(), coalesce(sales.last_sale_date, date(i.creation))) >= %(min_days)s
  and (%(item_group)s is null or %(item_group)s = '' or i.item_group = %(item_group)s)
order by days_since_last_sale desc
"@
    filters     = @(
        [ordered]@{ fieldname="min_days";   label="Min Days Without Sale"; fieldtype="Int";  options="";            default="30" },
        [ordered]@{ fieldname="item_group"; label="Item Group";            fieldtype="Link"; options="Item Group"; default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Inventory" },
        [ordered]@{ role = "Ops - Purchasing" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §9.2 — Near Expiry Value at Risk (batch qty × buying price for expiring stock)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Stock ${EM} Near Expiry Value at Risk"
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
  datediff(ba.expiry_date, curdate())                            as days_to_expiry,
  sum(sle.actual_qty)                                           as qty,
  coalesce(bp.price_list_rate, 0)                               as buying_price,
  sum(sle.actual_qty) * coalesce(bp.price_list_rate, 0)         as value_at_risk
from `tabStock Ledger Entry` sle
join `tabBatch` ba on ba.name = sle.batch_no
join `tabItem` i on i.name = sle.item_code
left join (
  select item_code, max(price_list_rate) as price_list_rate
  from `tabItem Price`
  where price_list = 'Standard Buying' and buying = 1
  group by item_code
) bp on bp.item_code = sle.item_code
where
  sle.is_cancelled = 0
  and sle.batch_no is not null and sle.batch_no != ''
  and ba.expiry_date is not null
  and ba.expiry_date <= date_add(curdate(), interval %(near_expiry_days)s day)
  and (%(warehouse)s is null or %(warehouse)s = '' or sle.warehouse = %(warehouse)s)
  and (%(item_group)s is null or %(item_group)s = '' or i.item_group = %(item_group)s)
group by sle.warehouse, sle.item_code, sle.batch_no
having qty > 0
order by ba.expiry_date asc, sle.warehouse, sle.item_code
"@
    filters     = @(
        [ordered]@{ fieldname="near_expiry_days"; label="Expiring Within (Days)"; fieldtype="Int";  options="";            default="30" },
        [ordered]@{ fieldname="warehouse";        label="Warehouse";              fieldtype="Link"; options="Warehouse";   default="" },
        [ordered]@{ fieldname="item_group";       label="Item Group";             fieldtype="Link"; options="Item Group"; default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Inventory" },
        [ordered]@{ role = "Ops - Accounting" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §9.5 — Data Quality: Sales Invoices Missing Doctor or Hospital
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Data Quality ${EM} Missing Doctor or Hospital"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  si.name         as sales_invoice,
  si.posting_date,
  si.customer,
  si.grand_total,
  si.status,
  si.surgery_case
from `tabSales Invoice` si
where
  si.docstatus = 1
  and (si.hospital   is null or si.hospital   = '')
  and (si.doctor_name is null or si.doctor_name = '')
  and (%(from_date)s is null or %(from_date)s = '' or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or si.posting_date <= %(to_date)s)
order by si.posting_date desc
"@
    filters     = @(
        [ordered]@{ fieldname="from_date"; label="From Date"; fieldtype="Date"; options=""; default="" },
        [ordered]@{ fieldname="to_date";   label="To Date";   fieldtype="Date"; options=""; default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Order Creating" },
        [ordered]@{ role = "Ops - Accounting" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §9.6 — Data Quality: Negative Stock (bins with actual_qty < 0)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Data Quality ${EM} Negative Stock"
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
  b.actual_qty,
  b.reserved_qty,
  b.projected_qty
from `tabBin` b
join `tabItem` i on i.name = b.item_code
where
  b.actual_qty < 0
order by b.actual_qty asc
"@
    filters     = @()
    roles       = @(
        [ordered]@{ role = "Ops - Inventory" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §9.8 — Supplier Performance (PO fulfillment rate and delivery delay per order)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Purchasing ${EM} Supplier Performance"
    report_type = "Query Report"
    ref_doctype = "Purchase Order"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  po.supplier,
  po.name                       as purchase_order,
  po.transaction_date           as order_date,
  po.delivery_date              as expected_date,
  po.grand_total                as order_value,
  po.per_received               as received_pct,
  min(pr.posting_date)          as first_receipt_date,
  datediff(min(pr.posting_date), po.delivery_date) as delay_days
from `tabPurchase Order` po
left join `tabPurchase Receipt Item` pri
  on pri.purchase_order = po.name
left join `tabPurchase Receipt` pr
  on pr.name = pri.parent
  and pr.docstatus = 1
where
  po.docstatus = 1
  and (%(supplier)s is null or %(supplier)s = '' or po.supplier = %(supplier)s)
  and (%(from_date)s is null or %(from_date)s = '' or po.transaction_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or po.transaction_date <= %(to_date)s)
group by po.name
order by po.transaction_date desc
"@
    filters     = @(
        [ordered]@{ fieldname="supplier";  label="Supplier";  fieldtype="Link"; options="Supplier"; default="" },
        [ordered]@{ fieldname="from_date"; label="From Date"; fieldtype="Date"; options="";          default="" },
        [ordered]@{ fieldname="to_date";   label="To Date";   fieldtype="Date"; options="";          default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Purchasing" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# ---------------------------------------------------------------------------
# Workspace — full shortcut list (Doc 13A originals + all Doc 15 additions)
# ---------------------------------------------------------------------------
$WsName      = "Ops ${EM} Reporting Pack"
$WsShortcuts = @(
    # --- Stock: existing transit / client location reports ---
    [ordered]@{ label="Delivery In-Transit Stock";          type="Report";  link_to="RPT ${EM} Stock ${EM} Delivery In-Transit - Inmed" },
    [ordered]@{ label="Return Pickup In-Transit Stock";     type="Report";  link_to="RPT ${EM} Stock ${EM} Return Pickup In-Transit - Inmed" },
    [ordered]@{ label="Returns Backlog";                    type="Report";  link_to="RPT ${EM} Stock ${EM} Returns - Inmed" },
    [ordered]@{ label="Client Locations Stock";             type="Report";  link_to="RPT ${EM} Stock ${EM} Client Locations (All)" },
    [ordered]@{ label="In-Transit Stuck Check";             type="Report";  link_to="RPT ${EM} Stock ${EM} In-Transit Stuck (Age Check)" },
    [ordered]@{ label="Client Stock (No Open Cases)";       type="Report";  link_to="RPT ${EM} Ops ${EM} Client Stock With No Open Cases" },
    # --- Stock: Doc 15 additions ---
    [ordered]@{ label="Stock Balance (All Warehouses)";     type="Report";  link_to="RPT ${EM} Stock ${EM} Balance Multi-Select" },
    [ordered]@{ label="Batch and Expiry Balance";           type="Report";  link_to="RPT ${EM} Stock ${EM} Batch and Expiry Balance" },
    [ordered]@{ label="Expiry Classification";              type="Report";  link_to="RPT ${EM} Stock ${EM} Expiry Classification" },
    [ordered]@{ label="Stock Entries by Period";            type="Report";  link_to="RPT ${EM} Stock ${EM} Entries by Period" },
    [ordered]@{ label="Warehouse Movement";                 type="Report";  link_to="RPT ${EM} Stock ${EM} Warehouse Movement" },
    [ordered]@{ label="Near Expiry Stock";                  type="Report";  link_to="RPT ${EM} Stock ${EM} Near Expiry (Main - Inmed)" },
    [ordered]@{ label="Near Expiry Value at Risk";          type="Report";  link_to="RPT ${EM} Stock ${EM} Near Expiry Value at Risk" },
    [ordered]@{ label="Slow-Moving Products";               type="Report";  link_to="RPT ${EM} Stock ${EM} Slow-Moving Products" },
    # --- Operations ---
    [ordered]@{ label="Driver Task Queue";                  type="Report";  link_to="RPT ${EM} Ops ${EM} Driver Task Queue (Derived)" },
    [ordered]@{ label="Surgery Cases Aging (Open)";         type="Report";  link_to="RPT ${EM} Surgery Cases ${EM} Aging (Open)" },
    [ordered]@{ label="VIEW: Cases Delivered";              type="DocType"; link_to="Surgery Case"; doc_view="List"; stats_filter='[["workflow_state","=","Delivered"]]' },
    [ordered]@{ label="VIEW: Cases Pickup In Transit";      type="DocType"; link_to="Surgery Case"; doc_view="List"; stats_filter='[["workflow_state","=","Return Pickup In Transit"]]' },
    [ordered]@{ label="VIEW: Cases Returns Received";       type="DocType"; link_to="Surgery Case"; doc_view="List"; stats_filter='[["workflow_state","=","Returns Received"]]' },
    [ordered]@{ label="VIEW: Cases Usage Derived";          type="DocType"; link_to="Surgery Case"; doc_view="List"; stats_filter='[["workflow_state","=","Usage Derived"]]' },
    # --- Sales ---
    [ordered]@{ label="Sales History by Client";            type="Report";  link_to="RPT ${EM} Sales ${EM} History by Client" },
    [ordered]@{ label="Sold Items Detail";                  type="Report";  link_to="RPT ${EM} Sales ${EM} Sold Items Detail" },
    [ordered]@{ label="Top Products";                       type="Report";  link_to="RPT ${EM} Sales ${EM} Top Products" },
    [ordered]@{ label="Top Customers";                      type="Report";  link_to="RPT ${EM} Sales ${EM} Top Customers" },
    [ordered]@{ label="Comparative Periods";                type="Report";  link_to="RPT ${EM} Sales ${EM} Comparative Periods" },
    # --- Pricing ---
    [ordered]@{ label="Manual Rate Edits";                  type="Report";  link_to="RPT ${EM} Pricing ${EM} Sales Orders With Manual Rate Edits" },
    [ordered]@{ label="Price Overrides by Client";          type="DocType"; link_to="Item Price"; doc_view="List"; stats_filter='[["selling","=","1"],["customer","!=",""]]' },
    # --- Receivables / Accounting ---
    [ordered]@{ label="Unpaid Invoices (Aging)";            type="Report";  link_to="RPT ${EM} Receivables ${EM} Unpaid Invoices (Aging)" },
    [ordered]@{ label="Unallocated Advances";               type="Report";  link_to="RPT ${EM} Receivables ${EM} Unallocated Advances" },
    [ordered]@{ label="Sales Documents and Payments";       type="Report";  link_to="RPT ${EM} Accounting ${EM} Sales Documents and Payments" },
    [ordered]@{ label="Debt Status Board";                  type="Report";  link_to="RPT ${EM} Accounting ${EM} Debt Status Board" },
    [ordered]@{ label="Income by Period";                   type="Report";  link_to="RPT ${EM} Accounting ${EM} Income by Period" },
    # --- Risk / Debt ---
    [ordered]@{ label="Debt Threshold Exceeded";            type="Report";  link_to="RPT ${EM} Risk ${EM} Debt Threshold Exceeded" },
    [ordered]@{ label="Prepaid Orders Awaiting Delivery";   type="Report";  link_to="RPT ${EM} Ops ${EM} Prepaid Orders Awaiting Delivery" },
    # --- Task views ---
    [ordered]@{ label="VIEW: Debt Collection Tasks";        type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Debt Collection"],["status","not in","Completed,Cancelled"]]' },
    [ordered]@{ label="VIEW: Distribute Payment Tasks";     type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Distribute Payment"],["status","not in","Completed,Cancelled"]]' },
    [ordered]@{ label="VIEW: Return to Warehouse Tasks";    type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Return to warehouse (aborted delivery / cancelled order)"],["status","not in","Completed,Cancelled"]]' },
    [ordered]@{ label="VIEW: Discount Approval Tasks";      type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Discount Approval"],["status","not in","Completed,Cancelled"]]' },
    [ordered]@{ label="VIEW: Purchase Approval Tasks";      type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Purchase Approval"],["status","not in","Completed,Cancelled"]]' },
    [ordered]@{ label="VIEW: Write-off Approval Tasks";     type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Write-off Approval"],["status","not in","Completed,Cancelled"]]' },
    # --- Purchasing ---
    [ordered]@{ label="Norm and Reorder";                   type="Report";  link_to="RPT ${EM} Purchasing ${EM} Norm and Reorder" },
    [ordered]@{ label="Supplier Performance";               type="Report";  link_to="RPT ${EM} Purchasing ${EM} Supplier Performance" },
    # --- Data Quality ---
    [ordered]@{ label="Tracked Items Missing Identifiers";  type="Report";  link_to="RPT ${EM} Data Quality ${EM} Tracked Items Missing Identifiers" },
    [ordered]@{ label="Missing Doctor or Hospital";         type="Report";  link_to="RPT ${EM} Data Quality ${EM} Missing Doctor or Hospital" },
    [ordered]@{ label="Negative Stock";                     type="Report";  link_to="RPT ${EM} Data Quality ${EM} Negative Stock" },
    # --- Catalog ---
    [ordered]@{ label="Collection Sets Readiness";           type="DocType"; link_to="Collection Set"; doc_view="List" }
)

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
    Get-Snapshot | ConvertTo-Json -Depth 5
    return
}

# ---------------------------------------------------------------------------
# Deploy mode
# ---------------------------------------------------------------------------
$Results = [ordered]@{ mode="Deploy"; reports=@(); workspace=$null }

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

Write-Host "--- Updating Workspace: $WsName ---"
$Results.workspace = Upsert-ErpDoc -DocType "Workspace" -Name $WsName -Body $WorkspaceBody
Write-Host "  $($Results.workspace.action): $WsName"

Write-Host ""
Write-Host "--- Deploy results ---"
$Results | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "--- Post-deploy verification ---"
Get-Snapshot | ConvertTo-Json -Depth 5

exit 0
