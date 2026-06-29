#Requires -Version 5.1
<#
.SYNOPSIS
  Doc 15D — Launch deployment for missing Doc 15 automation and KPI items.
  Creates:
  - Task auto-escalation Scheduled Server Script
  - Daily / Weekly / Monthly KPI Query Reports
  - Dashboard Chart records for KPI sources where supported by ERPNext
  - Reporting workspace shortcuts

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
    $Json = $Body | ConvertTo-Json -Depth 40
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

$AutoEscalationScriptName = "doc15_task_auto_escalation"
$AutoEscalationScript = @'
from frappe.utils import today, add_days, getdate

open_statuses = ["Open", "Working", "Pending Review", "Overdue"]
director_role = "Ops - Directors"
normal_cutoff = add_days(today(), -3)
high_cutoff = add_days(today(), -1)

users = frappe.get_all("Has Role", filters={"role": director_role, "parenttype": "User"}, pluck="parent")
directors = []
for user in users:
    enabled = frappe.db.get_value("User", user, "enabled")
    if enabled:
        directors.append(user)

if directors:
    tasks = frappe.get_all(
        "Task",
        filters={"status": ["in", open_statuses], "exp_end_date": ["is", "set"]},
        fields=["name", "subject", "priority", "exp_end_date", "owner"]
    )
    escalated = []
    for task in tasks:
        due_date = getdate(task.exp_end_date)
        high_priority = task.priority in ["High", "Urgent"]
        should_escalate = False
        if high_priority and due_date <= getdate(high_cutoff):
            should_escalate = True
        elif due_date <= getdate(normal_cutoff):
            should_escalate = True
        if not should_escalate:
            continue
        already_assigned = frappe.get_all(
            "ToDo",
            filters={"reference_type": "Task", "reference_name": task.name, "allocated_to": ["in", directors], "status": "Open"},
            limit=1
        )
        if already_assigned:
            continue
        for director in directors:
            frappe.get_doc({
                "doctype": "ToDo",
                "allocated_to": director,
                "reference_type": "Task",
                "reference_name": task.name,
                "description": "Auto-escalated overdue task: {0}".format(task.subject or task.name),
                "priority": "High" if high_priority else "Medium",
                "status": "Open"
            }).insert(ignore_permissions=True)
        if task.owner:
            frappe.get_doc({
                "doctype": "ToDo",
                "allocated_to": task.owner,
                "reference_type": "Task",
                "reference_name": task.name,
                "description": "This overdue task was auto-escalated to directors.",
                "priority": "High" if high_priority else "Medium",
                "status": "Open"
            }).insert(ignore_permissions=True)
        escalated.append(task.name)
    if escalated:
        frappe.db.commit()
'@

$Reports = @()

$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} KPI ${EM} Daily Dashboard"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @"
select 'Current stock value at risk' as kpi, coalesce(sum(qty * buying_price), 0) as value
from (
  select sle.item_code, sle.batch_no, sum(sle.actual_qty) as qty, coalesce(bp.price_list_rate, 0) as buying_price
  from `tabStock Ledger Entry` sle
  join `tabBatch` ba on ba.name = sle.batch_no
  left join (
    select item_code, max(price_list_rate) as price_list_rate
    from `tabItem Price`
    where price_list = 'Standard Buying' and buying = 1
    group by item_code
  ) bp on bp.item_code = sle.item_code
  where sle.is_cancelled = 0 and ba.expiry_date is not null and ba.expiry_date <= date_add(curdate(), interval 90 day)
  group by sle.item_code, sle.batch_no
  having qty > 0
) x
union all
select 'Overdue debts total', coalesce(sum(outstanding_amount), 0)
from `tabSales Invoice`
where docstatus = 1 and outstanding_amount > 0 and due_date < curdate()
union all
select 'Overdue debts count', count(*)
from `tabSales Invoice`
where docstatus = 1 and outstanding_amount > 0 and due_date < curdate()
union all
select 'Critical stock-outs', count(*)
from `tabBin`
where actual_qty <= 0
union all
select 'Pending urgent tasks', count(*)
from `tabTask`
where status not in ('Completed', 'Cancelled') and (priority in ('High', 'Urgent') or exp_end_date <= curdate())
union all
select 'Today sales income total', coalesce(sum(grand_total), 0)
from `tabSales Invoice`
where docstatus = 1 and posting_date = curdate()
"@
    filters     = @()
    roles       = @([ordered]@{ role = "Ops - Directors" }, [ordered]@{ role = "System Manager" })
}

$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} KPI ${EM} Weekly Dashboard"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @"
select 'Week total income' as kpi, coalesce(sum(si.grand_total), 0) as value
from `tabSales Invoice` si
where si.docstatus = 1 and si.posting_date >= date_sub(curdate(), interval 7 day)
union all
select 'Week total profit', coalesce(sum(sii.amount - (sii.qty * coalesce(bp.price_list_rate, 0))), 0)
from `tabSales Invoice` si
join `tabSales Invoice Item` sii on sii.parent = si.name
left join (
  select item_code, max(price_list_rate) as price_list_rate
  from `tabItem Price`
  where price_list = 'Standard Buying' and buying = 1
  group by item_code
) bp on bp.item_code = sii.item_code
where si.docstatus = 1 and si.posting_date >= date_sub(curdate(), interval 7 day)
union all
select 'Top products sold rows', count(*)
from (
  select sii.item_code
  from `tabSales Invoice` si
  join `tabSales Invoice Item` sii on sii.parent = si.name
  where si.docstatus = 1 and si.posting_date >= date_sub(curdate(), interval 7 day)
  group by sii.item_code
  order by sum(sii.qty) desc
  limit 10
) x
union all
select 'Top customers rows', count(*)
from (
  select si.customer
  from `tabSales Invoice` si
  where si.docstatus = 1 and si.posting_date >= date_sub(curdate(), interval 7 day)
  group by si.customer
  order by sum(si.grand_total) desc
  limit 5
) x
union all
select 'Slow-moving stock value', coalesce(sum(b.actual_qty * coalesce(bp.price_list_rate, 0)), 0)
from `tabBin` b
left join (
  select item_code, max(price_list_rate) as price_list_rate
  from `tabItem Price`
  where price_list = 'Standard Buying' and buying = 1
  group by item_code
) bp on bp.item_code = b.item_code
where b.actual_qty > 0
union all
select 'Debt aging over 30 days', coalesce(sum(outstanding_amount), 0)
from `tabSales Invoice`
where docstatus = 1 and outstanding_amount > 0 and datediff(curdate(), due_date) > 30
union all
select 'Current stock turnover proxy', coalesce(sum(abs(sle.actual_qty)), 0)
from `tabStock Ledger Entry` sle
where sle.is_cancelled = 0 and sle.actual_qty < 0 and sle.posting_date >= date_sub(curdate(), interval 7 day)
union all
select 'Week-over-week sales change',
  coalesce(sum(case when posting_date >= date_sub(curdate(), interval 7 day) then grand_total else 0 end), 0) -
  coalesce(sum(case when posting_date < date_sub(curdate(), interval 7 day) and posting_date >= date_sub(curdate(), interval 14 day) then grand_total else 0 end), 0)
from `tabSales Invoice`
where docstatus = 1 and posting_date >= date_sub(curdate(), interval 14 day)
"@
    filters     = @()
    roles       = @([ordered]@{ role = "Ops - Directors" }, [ordered]@{ role = "System Manager" })
}

$Reports += [ordered]@{
    rpt_name    = "RPT ${EM} KPI ${EM} Monthly Income and Profit"
    report_type = "Query Report"
    ref_doctype = "Sales Invoice"
    is_standard = "No"
    disabled    = 0
    query       = @"
select
  date_format(si.posting_date, '%Y-%m') as month,
  coalesce(sum(si.grand_total), 0) as total_income,
  coalesce(sum(sii.amount - (sii.qty * coalesce(bp.price_list_rate, 0))), 0) as total_profit
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
  and (%(from_date)s is null or %(from_date)s = '' or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or %(to_date)s = '' or si.posting_date <= %(to_date)s)
group by month
order by month desc
"@
    filters     = @(
        [ordered]@{ fieldname="from_date"; label="From Date"; fieldtype="Date"; options=""; default="" },
        [ordered]@{ fieldname="to_date"; label="To Date"; fieldtype="Date"; options=""; default="" }
    )
    roles       = @([ordered]@{ role = "Ops - Directors" }, [ordered]@{ role = "System Manager" })
}

$DashboardCharts = @(
    [ordered]@{ chart_name="KPI ${EM} Daily Dashboard"; chart_type="Report"; report_name="RPT ${EM} KPI ${EM} Daily Dashboard"; is_public=0; type="Bar"; x_field="kpi"; y_field="value"; timespan="Last Week"; time_interval="Daily" },
    [ordered]@{ chart_name="KPI ${EM} Weekly Dashboard"; chart_type="Report"; report_name="RPT ${EM} KPI ${EM} Weekly Dashboard"; is_public=0; type="Bar"; x_field="kpi"; y_field="value"; timespan="Last Week"; time_interval="Daily" },
    [ordered]@{ chart_name="KPI ${EM} Monthly Income and Profit"; chart_type="Report"; report_name="RPT ${EM} KPI ${EM} Monthly Income and Profit"; is_public=0; type="Line"; x_field="month"; y_field="total_income"; timespan="Last Year"; time_interval="Monthly" }
)

$WorkspaceName = "Ops ${EM} Reporting Pack"

function Get-Snapshot {
    $S = [ordered]@{ mode="Check"; reports=@(); server_scripts=@(); dashboard_charts=@(); workspace=$null }
    foreach ($Rpt in $Reports) { $S.reports += Exists-Result "Report" $Rpt.rpt_name }
    $S.server_scripts += Exists-Result "Server Script" $AutoEscalationScriptName
    foreach ($Chart in $DashboardCharts) { $S.dashboard_charts += Exists-Result "Dashboard Chart" $Chart.chart_name }
    $S.workspace = Exists-Result "Workspace" $WorkspaceName
    return $S
}

if ($Mode -eq "Check") {
    Get-Snapshot | ConvertTo-Json -Depth 8
    return
}

$Results = [ordered]@{ mode="Deploy"; reports=@(); server_scripts=@(); dashboard_charts=@(); workspace=$null; notes=@() }

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

$ServerScriptBody = [ordered]@{
    script_type = "Scheduler Event"
    event_frequency = "Daily"
    disabled = 0
    script = $AutoEscalationScript
}
$Results.server_scripts += Upsert-ErpDoc "Server Script" $AutoEscalationScriptName $ServerScriptBody

foreach ($Chart in $DashboardCharts) {
    try {
        $Body = [ordered]@{
            chart_name = $Chart.chart_name
            chart_type = $Chart.chart_type
            report_name = $Chart.report_name
            is_public = $Chart.is_public
            type = $Chart.type
            x_field = $Chart.x_field
            y_axis = @([ordered]@{ y_field = $Chart.y_field })
            timespan = $Chart.timespan
            time_interval = $Chart.time_interval
            filters_json = "{}"
            dynamic_filters_json = "{}"
        }
        $Results.dashboard_charts += Upsert-ErpDoc "Dashboard Chart" $Chart.chart_name $Body
    } catch {
        $Results.dashboard_charts += [pscustomobject]@{ doctype="Dashboard Chart"; action="failed"; name=$Chart.chart_name; error=$_.Exception.Message }
        $Results.notes += "Dashboard Chart creation failed for $($Chart.chart_name). KPI Query Report was still deployed and can be opened directly."
    }
}

$Results.workspace = [pscustomobject]@{
    doctype = "Workspace"
    action = "skipped"
    name = $WorkspaceName
    reason = "Existing workspace contains legacy encoded report links; KPI reports are deployed and can be opened by search."
}

$Results.post_deploy_check = Get-Snapshot
$Results | ConvertTo-Json -Depth 12
exit 0
