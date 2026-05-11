#Requires -Version 5.1
<#
.SYNOPSIS
  Doc 15B — Reporting Requirements: Phase 2 deployment.
  Deploys 5 new Query Reports: Debt Status Board, Income by Period,
  Norm and Reorder, Top Products, and Top Customers.

  PREREQUISITE: Run doc15a-deploy.ps1 first.
  The Norm/Reorder report references the buffer_percentage field
  on Item Reorder which is created in doc15a.

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

# §6.4 — Debt Status Board (full invoice lifecycle: Unpaid → Partly Paid → Paid)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Accounting ${EM} Debt Status Board"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  si.customer,
  si.name            as sales_invoice,
  si.posting_date,
  si.due_date,
  si.grand_total,
  si.outstanding_amount,
  (si.grand_total - si.outstanding_amount) as paid_amount,
  si.status,
  datediff(curdate(), si.due_date)          as overdue_days
from `tabSales Invoice` si
where
  si.docstatus = 1
  and si.grand_total > 0
  and (%(customer)s is null or %(customer)s = '' or si.customer = %(customer)s)
  and (%(from_date)s is null or %(from_date)s = '' or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or si.posting_date <= %(to_date)s)
  and (%(status)s is null or %(status)s = '' or si.status = %(status)s)
order by si.customer, si.due_date asc
"@
    filters     = @(
        [ordered]@{ fieldname="customer";  label="Customer";       fieldtype="Link";   options="Customer"; default="" },
        [ordered]@{ fieldname="from_date"; label="From Date";      fieldtype="Date";   options="";         default="" },
        [ordered]@{ fieldname="to_date";   label="To Date";        fieldtype="Date";   options="";         default="" },
        [ordered]@{ fieldname="status";    label="Payment Status"; fieldtype="Select"; options="Unpaid`nPartly Paid`nPaid`nOverdue"; default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Accounting" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §6.5 — Income by Period (monthly summary: sales volume, invoiced, collected)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Accounting ${EM} Income by Period"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  date_format(si.posting_date, '%Y-%m')       as period,
  count(distinct si.name)                     as invoice_count,
  count(distinct si.customer)                 as customer_count,
  sum(sii.amount)                             as net_sales,
  sum(si.grand_total)                         as gross_sales,
  sum(si.grand_total - si.outstanding_amount) as collected_amount
from `tabSales Invoice` si
join `tabSales Invoice Item` sii on sii.parent = si.name
where
  si.docstatus = 1
  and (%(from_date)s is null or %(from_date)s = '' or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or si.posting_date <= %(to_date)s)
  and (%(customer)s is null or %(customer)s = '' or si.customer = %(customer)s)
  and (%(item_group)s is null or %(item_group)s = '' or sii.item_group = %(item_group)s)
group by period
order by period
"@
    filters     = @(
        [ordered]@{ fieldname="from_date";  label="From Date";  fieldtype="Date"; options="";            default="" },
        [ordered]@{ fieldname="to_date";    label="To Date";    fieldtype="Date"; options="";            default="" },
        [ordered]@{ fieldname="customer";   label="Customer";   fieldtype="Link"; options="Customer";   default="" },
        [ordered]@{ fieldname="item_group"; label="Item Group"; fieldtype="Link"; options="Item Group"; default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §7.1 — Norm and Reorder (dynamic norm based on avg daily usage + buffer_percentage)
# NOTE: Requires buffer_percentage custom field on Item Reorder (deployed by doc15a).
# buffer_percentage is read per item+warehouse row; defaults to 0.20 when null.
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Purchasing ${EM} Norm and Reorder"
    report_type = "Query Report"
    ref_doctype = "Item"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  i.item_code,
  i.item_name,
  i.item_group,
  ir.warehouse,
  ir.warehouse_reorder_level                                                                as reorder_level,
  ir.warehouse_reorder_qty                                                                 as reorder_qty,
  round(coalesce(ir.buffer_percentage, 0.20) * 100, 0)                                   as buffer_pct,
  coalesce(b.actual_qty, 0)                                                               as current_stock,
  round(coalesce(usage.avg_daily_qty, 0), 3)                                              as avg_daily_usage,
  round(coalesce(usage.avg_daily_qty, 0) * 30 * (1 + coalesce(ir.buffer_percentage, 0.20)), 1) as norm_30d,
  round(coalesce(usage.avg_daily_qty, 0) * 60 * (1 + coalesce(ir.buffer_percentage, 0.20)), 1) as norm_60d,
  case
    when coalesce(b.actual_qty, 0) <= coalesce(ir.warehouse_reorder_level, 0)
      then 'Below Reorder Level'
    when coalesce(b.actual_qty, 0) < coalesce(usage.avg_daily_qty, 0) * 30 * (1 + coalesce(ir.buffer_percentage, 0.20))
      then 'Below 30d Norm'
    else 'OK'
  end as reorder_status
from `tabItem` i
join `tabItem Reorder` ir on ir.parent = i.name
left join `tabBin` b
  on b.item_code = i.name and b.warehouse = ir.warehouse
left join (
  select
    item_code,
    warehouse,
    abs(sum(actual_qty)) / greatest(datediff(curdate(), min(posting_date)), 1) as avg_daily_qty
  from `tabStock Ledger Entry`
  where
    is_cancelled = 0
    and actual_qty < 0
    and posting_date >= date_sub(curdate(), interval %(analysis_days)s day)
  group by item_code, warehouse
) usage on usage.item_code = i.name and usage.warehouse = ir.warehouse
where
  i.disabled = 0
  and (%(item_group)s is null or %(item_group)s = '' or i.item_group = %(item_group)s)
  and (%(warehouse)s is null or %(warehouse)s = '' or ir.warehouse = %(warehouse)s)
order by reorder_status desc, i.item_group, i.item_code
"@
    filters     = @(
        [ordered]@{ fieldname="analysis_days"; label="Analysis Period (days)"; fieldtype="Int";  options="";            default="30" },
        [ordered]@{ fieldname="item_group";    label="Item Group";             fieldtype="Link"; options="Item Group";  default="" },
        [ordered]@{ fieldname="warehouse";     label="Warehouse";              fieldtype="Link"; options="Warehouse";   default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Purchasing" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §8.1 — Top Products (ranked by sales amount in period)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Sales ${EM} Top Products"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  sii.item_code,
  i.item_name,
  i.item_group,
  count(distinct si.name) as transaction_count,
  sum(sii.qty)            as total_qty,
  sum(sii.amount)         as total_amount
from `tabSales Invoice` si
join `tabSales Invoice Item` sii on sii.parent = si.name
join `tabItem` i on i.name = sii.item_code
where
  si.docstatus = 1
  and (%(from_date)s is null or %(from_date)s = '' or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or si.posting_date <= %(to_date)s)
  and (%(item_group)s is null or %(item_group)s = '' or sii.item_group = %(item_group)s)
  and (%(customer)s is null or %(customer)s = '' or si.customer = %(customer)s)
group by sii.item_code
order by total_amount desc
limit 100
"@
    filters     = @(
        [ordered]@{ fieldname="from_date";  label="From Date";  fieldtype="Date"; options="";            default="" },
        [ordered]@{ fieldname="to_date";    label="To Date";    fieldtype="Date"; options="";            default="" },
        [ordered]@{ fieldname="item_group"; label="Item Group"; fieldtype="Link"; options="Item Group"; default="" },
        [ordered]@{ fieldname="customer";   label="Customer";   fieldtype="Link"; options="Customer";   default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Order Accepting" },
        [ordered]@{ role = "Ops - Inventory" },
        [ordered]@{ role = "Ops - Purchasing" },
        [ordered]@{ role = "Ops - Accounting" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# §8.1 — Top Customers (ranked by sales amount — doctors and hospitals are customers)
$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Sales ${EM} Top Customers"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  si.customer,
  c.customer_group,
  count(distinct si.name) as invoice_count,
  sum(sii.qty)            as total_qty,
  sum(sii.amount)         as total_amount
from `tabSales Invoice` si
join `tabSales Invoice Item` sii on sii.parent = si.name
join `tabCustomer` c on c.name = si.customer
where
  si.docstatus = 1
  and (%(from_date)s is null or %(from_date)s = '' or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or si.posting_date <= %(to_date)s)
  and (%(item_group)s is null or %(item_group)s = '' or sii.item_group = %(item_group)s)
  and (%(customer_group)s is null or %(customer_group)s = '' or c.customer_group = %(customer_group)s)
group by si.customer
order by total_amount desc
limit 100
"@
    filters     = @(
        [ordered]@{ fieldname="from_date";      label="From Date";      fieldtype="Date"; options="";               default="" },
        [ordered]@{ fieldname="to_date";        label="To Date";        fieldtype="Date"; options="";               default="" },
        [ordered]@{ fieldname="item_group";     label="Item Group";     fieldtype="Link"; options="Item Group";     default="" },
        [ordered]@{ fieldname="customer_group"; label="Customer Group"; fieldtype="Link"; options="Customer Group"; default="" }
    )
    roles       = @(
        [ordered]@{ role = "Ops - Order Accepting" },
        [ordered]@{ role = "Ops - Accounting" },
        [ordered]@{ role = "Ops - Directors" },
        [ordered]@{ role = "System Manager" }
    )
}

# ---------------------------------------------------------------------------
# Snapshot helper
# ---------------------------------------------------------------------------
function Get-Snapshot {
    $S = [ordered]@{ mode="Verify"; reports=@() }
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
$Results = [ordered]@{ mode="Deploy"; reports=@() }

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
