#Requires -Version 5.1
<#
.SYNOPSIS
  Doc 15E â€” Remaining reporting/workspace polish deployment.
  Creates/updates:
  - RPT - Item - Sort and Classify
  - RPT - Item - Nomenclature and Prices
  - RPT - Returns - Refund Queue
  - Scheduled Server Script: doc15_norm_reorder_daily_notifications
  - Clean workspaces: Management - KPI Dashboard, Dispatch - Task Queues
.PARAMETER Mode
  Check  â€” verify existence only (no writes)
  Deploy â€” create/update all artefacts
#>
param([ValidateSet("Check","Deploy")][string]$Mode = "Check")
Set-StrictMode -Off
$ErrorActionPreference = "Stop"
$EM = "-"

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
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json))
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
        $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ doctype=$DocType; action="created"; name=$Created.name }
    }
    Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body | Out-Null
    return [pscustomobject]@{ doctype=$DocType; action="updated"; name=$Name }
}

function Exists-Result {
    param([string]$DocType, [string]$Name)
    return [pscustomobject]@{ doctype=$DocType; name=$Name; exists=($null -ne (Get-ErpDoc -DocType $DocType -Name $Name)) }
}

$Reports = @()

$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Item ${EM} Sort and Classify"
    report_type = "Query Report"
    ref_doctype = "Item"
    is_standard = "No"
    disabled    = 0
    query       = @'
select
  i.item_code,
  i.item_name,
  i.item_group,
  i.brand,
  i.stock_uom as uom,
  coalesce(total_stock.total_qty, 0) as total_qty,
  coalesce(main_stock.main_warehouse_qty, 0) as main_warehouse_qty,
  coalesce(selling.price_list_rate, 0) as selling_price,
  coalesce(buying.price_list_rate, 0) as buying_price,
  case
    when coalesce(total_stock.total_qty, 0) <= 0 then 'Out of Stock'
    when coalesce(main_stock.main_warehouse_qty, 0) <= 0 then 'Not in Main Warehouse'
    else 'In Stock'
  end as stock_classification
from `tabItem` i
left join (
  select item_code, sum(actual_qty) as total_qty
  from `tabBin`
  group by item_code
) total_stock on total_stock.item_code = i.name
left join (
  select item_code, sum(actual_qty) as main_warehouse_qty
  from `tabBin`
  where warehouse = 'Main - Inmed'
  group by item_code
) main_stock on main_stock.item_code = i.name
left join (
  select item_code, max(price_list_rate) as price_list_rate
  from `tabItem Price`
  where selling = 1 and price_list = 'Standard Selling'
  group by item_code
) selling on selling.item_code = i.name
left join (
  select item_code, max(price_list_rate) as price_list_rate
  from `tabItem Price`
  where buying = 1 and price_list = 'Standard Buying'
  group by item_code
) buying on buying.item_code = i.name
where
  i.disabled = 0
order by
  coalesce(total_stock.total_qty, 0) asc,
  i.item_group asc,
  i.brand asc,
  i.item_code asc
'@
    filters     = @()
    roles       = @([ordered]@{ role="Ops - Directors" }, [ordered]@{ role="System Manager" })
}

$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Item ${EM} Nomenclature and Prices"
    report_type = "Query Report"
    ref_doctype = "Item"
    is_standard = "No"
    disabled    = 0
    query       = @'
select
  i.item_code,
  i.item_name,
  i.item_group,
  i.brand,
  i.stock_uom,
  i.has_batch_no,
  i.has_serial_no,
  i.disabled,
  coalesce(selling.price_list_rate, 0) as standard_selling_price,
  coalesce(buying.price_list_rate, 0) as standard_buying_price,
  i.hs_code,
  i.import_tax_rate
from `tabItem` i
left join (
  select item_code, max(price_list_rate) as price_list_rate
  from `tabItem Price`
  where selling = 1 and price_list = 'Standard Selling'
  group by item_code
) selling on selling.item_code = i.name
left join (
  select item_code, max(price_list_rate) as price_list_rate
  from `tabItem Price`
  where buying = 1 and price_list = 'Standard Buying'
  group by item_code
) buying on buying.item_code = i.name
where
  i.disabled = 0
order by i.item_group, i.brand, i.item_name
'@
    filters     = @()
    roles       = @([ordered]@{ role="Ops - Directors" }, [ordered]@{ role="Ops - Purchasing" }, [ordered]@{ role="System Manager" })
}

$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} Returns ${EM} Refund Queue"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @'
select
  si.name as credit_note,
  si.customer,
  si.posting_date,
  abs(si.grand_total) as refund_amount,
  abs(si.outstanding_amount) as outstanding_refund_amount,
  si.status,
  si.return_against as original_sales_invoice,
  dc.name as dispatch_case,
  si.remarks
from `tabSales Invoice` si
left join `tabDispatch Case` dc on dc.sales_invoice = si.return_against or dc.sales_invoice = si.name
where
  si.docstatus = 1
  and si.is_return = 1
order by si.posting_date desc, si.name desc
'@
    filters     = @()
    roles       = @([ordered]@{ role="Ops - Accounting" }, [ordered]@{ role="Ops - Returns" }, [ordered]@{ role="Ops - Directors" }, [ordered]@{ role="System Manager" })
}

$NormSchedulerName = "doc15_norm_reorder_daily_notifications"
$NormSchedulerScript = @'
from frappe.utils import nowdate

recipients = []
for role in ["Ops - Purchasing", "Ops - Directors"]:
    for user in frappe.get_all("Has Role", filters={"role": role, "parenttype": "User"}, pluck="parent"):
        if frappe.db.get_value("User", user, "enabled") and user not in recipients:
            recipients.append(user)

if recipients:
    below_reorder = frappe.db.sql("""
        select distinct b.item_code
        from `tabBin` b
        join `tabItem` i on i.name = b.item_code
        left join `tabItem Reorder` ir on ir.parent = i.name and ir.warehouse = b.warehouse
        where i.disabled = 0
          and coalesce(ir.warehouse_reorder_level, 0) > 0
          and b.actual_qty <= ir.warehouse_reorder_level
        limit 100
    """, as_dict=True)

    if below_reorder:
        subject = "Daily norm/reorder alert: {0} item(s) need review".format(len(below_reorder))
        item_lines = "\n".join(["- " + row.item_code for row in below_reorder[:50]])
        description = subject + "\n\n" + item_lines + "\n\nOpen report: RPT â€” Purchasing â€” Norm and Reorder"
        for user in recipients:
            existing = frappe.get_all(
                "ToDo",
                filters={"allocated_to": user, "description": ["like", "Daily norm/reorder alert%"], "status": "Open", "date": nowdate()},
                limit=1
            )
            if not existing:
                frappe.get_doc({
                    "doctype": "ToDo",
                    "allocated_to": user,
                    "description": description,
                    "priority": "Medium",
                    "status": "Open",
                    "date": nowdate()
                }).insert(ignore_permissions=True)
        frappe.db.commit()
'@

$ManagementWorkspaceName = "Management ${EM} KPI Dashboard"
$ManagementWorkspaceBody = [ordered]@{
    label = $ManagementWorkspaceName
    title = $ManagementWorkspaceName
    module = "Custom"
    is_public = 0
    shortcuts = @(
        [ordered]@{ label="Item Sort and Classify"; type="Report"; link_to="RPT ${EM} Item ${EM} Sort and Classify" },
        [ordered]@{ label="Item Nomenclature and Prices"; type="Report"; link_to="RPT ${EM} Item ${EM} Nomenclature and Prices" },
        [ordered]@{ label="Returns Refund Queue"; type="Report"; link_to="RPT ${EM} Returns ${EM} Refund Queue" }
    )
    content = '[]'
    charts = @()
    links = @()
}

$DispatchWorkspaceName = "Dispatch ${EM} Task Queues"
$DispatchWorkspaceBody = [ordered]@{
    label = $DispatchWorkspaceName
    title = $DispatchWorkspaceName
    module = "Custom"
    is_public = 1
    shortcuts = @(
        [ordered]@{ label="VIEW: Pack Tasks"; type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Pack / prepare items"],["status","not in","Completed,Cancelled"]]' },
        [ordered]@{ label="VIEW: Delivery Tasks"; type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Delivery"],["status","not in","Completed,Cancelled"]]' },
        [ordered]@{ label="VIEW: Return Pickup Tasks"; type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Pickup Returns"],["status","not in","Completed,Cancelled"]]' },
        [ordered]@{ label="VIEW: Returns Inspection Tasks"; type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Returns processing / verification"],["status","not in","Completed,Cancelled"]]' },
        [ordered]@{ label="VIEW: Restock Tasks"; type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Returns restocking"],["status","not in","Completed,Cancelled"]]' },
        [ordered]@{ label="VIEW: Invoice Tasks"; type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Invoice preparation / create invoice"],["status","not in","Completed,Cancelled"]]' },
        [ordered]@{ label="VIEW: Debt Collection Tasks"; type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Debt Collection"],["status","not in","Completed,Cancelled"]]' },
        [ordered]@{ label="VIEW: Payment Received Tasks"; type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Payment Received"],["status","not in","Completed,Cancelled"]]' },
        [ordered]@{ label="VIEW: Distribute Payment Tasks"; type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["task_kind","=","Distribute Payment"],["status","not in","Completed,Cancelled"]]' },
        [ordered]@{ label="VIEW: All Dispatch Cases"; type="DocType"; link_to="Dispatch Case"; doc_view="List" },
        [ordered]@{ label="All Urgent Tasks"; type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["status","not in","Completed,Cancelled"],["priority","in","High,Urgent"]]' },
        [ordered]@{ label="Overdue Tasks"; type="DocType"; link_to="Task"; doc_view="List"; stats_filter='[["status","not in","Completed,Cancelled"],["exp_end_date","<","Today"]]' }
    )
    content = '[]'
    charts = @()
    links = @()
}

function Get-Snapshot {
    $S = [ordered]@{ mode="Check"; reports=@(); server_scripts=@(); workspaces=@() }
    foreach ($Rpt in $Reports) { $S.reports += Exists-Result "Report" $Rpt.rpt_name }
    $S.server_scripts += Exists-Result "Server Script" $NormSchedulerName
    $S.workspaces += Exists-Result "Workspace" $ManagementWorkspaceName
    $S.workspaces += Exists-Result "Workspace" $DispatchWorkspaceName
    return $S
}

if ($Mode -eq "Check") {
    Get-Snapshot | ConvertTo-Json -Depth 10
    return
}

$Results = [ordered]@{ mode="Deploy"; reports=@(); server_scripts=@(); workspaces=@(); post_deploy_check=$null }

foreach ($Rpt in $Reports) {
    $Body = [ordered]@{
        report_name = $Rpt.rpt_name
        report_type = $Rpt.report_type
        ref_doctype = $Rpt.ref_doctype
        is_standard = $Rpt.is_standard
        disabled    = $Rpt.disabled
        query       = $Rpt.query
        filters     = $Rpt.filters
        roles       = $Rpt.roles
    }
    $Results.reports += Upsert-ErpDoc "Report" $Rpt.rpt_name $Body
}

$Results.server_scripts += Upsert-ErpDoc "Server Script" $NormSchedulerName ([ordered]@{
    script_type = "Scheduler Event"
    event_frequency = "Daily"
    disabled = 0
    script = $NormSchedulerScript
})

$Results.workspaces += Upsert-ErpDoc "Workspace" $ManagementWorkspaceName $ManagementWorkspaceBody
$Results.workspaces += Upsert-ErpDoc "Workspace" $DispatchWorkspaceName $DispatchWorkspaceBody
$Results.post_deploy_check = Get-Snapshot
$Results | ConvertTo-Json -Depth 20
exit 0
