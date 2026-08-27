param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 60 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60
}
function Get-ErpDoc { param([string]$DocType,[string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}
function Upsert-ErpDoc { param([string]$DocType,[string]$Name,$Body)
    $Existing = Get-ErpDoc $DocType $Name
    if ($null -eq $Existing) { $Body.name=$Name; $C=(Invoke-ErpRequest Post "/api/resource/$(Enc $DocType)" $Body).data; return [pscustomobject]@{action="created";name=$C.name} }
    $U=(Invoke-ErpRequest Put "/api/resource/$(Enc $DocType)/$(Enc $Name)" $Body).data; return [pscustomobject]@{action="updated";name=$U.name}
}
function Build-CustomFieldBody ($f) {
    $Body=[ordered]@{dt=$f.dt; fieldname=$f.fieldname; label=$f.label; fieldtype=$f.fieldtype}
    foreach($Prop in @("options","insert_after","default","read_only","in_list_view","in_standard_filter","allow_on_submit","description")){ if($f.PSObject.Properties[$Prop]){ $Body[$Prop]=$f.$Prop } }
    return $Body
}

$TaskFields = @(
    [pscustomobject]@{name="Task-custom_is_team_queue_task";dt="Task";fieldname="custom_is_team_queue_task";label="Team Queue Task";fieldtype="Check";insert_after="task_kind";default="0";in_standard_filter=1},
    [pscustomobject]@{name="Task-custom_team_queue_role";dt="Task";fieldname="custom_team_queue_role";label="Team Queue Role";fieldtype="Link";options="Role";insert_after="custom_is_team_queue_task";in_standard_filter=1},
    [pscustomobject]@{name="Task-custom_team_queue_status";dt="Task";fieldname="custom_team_queue_status";label="Team Queue Status";fieldtype="Select";options="Not Team Queue`nOpen For Team`nAccepted`nClosed";insert_after="custom_team_queue_role";default="Not Team Queue";in_standard_filter=1},
    [pscustomobject]@{name="Task-custom_accepted_by";dt="Task";fieldname="custom_accepted_by";label="Accepted By";fieldtype="Link";options="User";insert_after="custom_team_queue_status";read_only=1;in_standard_filter=1},
    [pscustomobject]@{name="Task-custom_accepted_at";dt="Task";fieldname="custom_accepted_at";label="Accepted At";fieldtype="Datetime";insert_after="custom_accepted_by";read_only=1},
    [pscustomobject]@{name="Task-custom_team_notified";dt="Task";fieldname="custom_team_notified";label="Team Notified";fieldtype="Check";insert_after="custom_accepted_at";default="0";read_only=1}
)

$TaskQueueAfterSave = @'
def run_script():
    TASK_KIND_TEAM_ROLE = {
        "Order entry": "Ops - Order Accepting",
        "Pack / prepare items": "Ops - Inventory",
        "Dispatch picking / hand-off": "Ops - Delivery",
        "Delivery": "Delivery Driver",
        "Pickup Returns": "Delivery Driver",
        "Return drop-off at warehouse": "Delivery Driver",
        "Returns processing / verification": "Ops - Returns",
        "Returns restocking": "Ops - Returns",
        "Invoice preparation / create invoice": "Ops - Accounting",
        "Debt Collection": "Ops - Finance",
        "Discount Approval": "Ops - Directors",
        "Purchase Approval": "Ops - Directors",
        "Write-off Approval": "Ops - Directors",
    }
    team_role = doc.get("custom_team_queue_role") or TASK_KIND_TEAM_ROLE.get(doc.get("task_kind"))
    if not team_role:
        return
    if doc.status in ("Completed", "Cancelled", "Template"):
        if doc.get("custom_team_queue_status") != "Closed":
            frappe.db.set_value("Task", doc.name, "custom_team_queue_status", "Closed", update_modified=False)
        return
    assigned = []
    try:
        assigned = frappe.parse_json(doc.get("_assign") or "[]") or []
    except Exception:
        assigned = []
    team_placeholders = ["inventory.team@example.com", "delivery.team@example.com", "returns.team@example.com", "accounting.team@example.com", "finance.team@example.com", "order.creation.team@example.com", "order.team@example.com"]
    real_assigned = [u for u in assigned if u not in team_placeholders]
    updates = {}
    if not doc.get("custom_is_team_queue_task"):
        updates["custom_is_team_queue_task"] = 1
    if not doc.get("custom_team_queue_role"):
        updates["custom_team_queue_role"] = team_role
    if real_assigned:
        updates["custom_team_queue_status"] = "Accepted"
        updates["custom_accepted_by"] = real_assigned[0]
    else:
        updates["custom_team_queue_status"] = "Open For Team"
    if updates:
        frappe.db.set_value("Task", doc.name, updates, update_modified=False)
    if real_assigned or doc.get("custom_team_notified"):
        return
    users = frappe.get_all("Has Role", filters={"role": team_role, "parenttype": "User"}, pluck="parent")
    created = 0
    for user in users or []:
        enabled = frappe.db.get_value("User", user, "enabled")
        if not enabled:
            continue
        exists = frappe.db.exists("ToDo", {"reference_type": "Task", "reference_name": doc.name, "allocated_to": user, "status": "Open"})
        if exists:
            continue
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = user
        todo.reference_type = "Task"
        todo.reference_name = doc.name
        todo.description = "Team task available: " + (doc.subject or doc.name)
        todo.assigned_by = frappe.session.user
        todo.insert(ignore_permissions=True)
        created += 1
    if created:
        frappe.db.set_value("Task", doc.name, "custom_team_notified", 1, update_modified=False)
run_script()
'@
$TaskAcceptApi = @'
task_name = frappe.form_dict.get("task_name")
if not task_name:
    frappe.throw("Task is required.")
task = frappe.get_doc("Task", task_name)
if task.status not in ("Open", "Working"):
    frappe.throw("Only Open or Working tasks can be accepted.")
TASK_KIND_ALLOWED_ROLES = {
    "Order entry": ["Ops - Order Accepting", "Ops - Order Creating"],
    "Pack / prepare items": ["Ops - Inventory"],
    "Dispatch picking / hand-off": ["Ops - Delivery"],
    "Delivery": ["Delivery Driver", "Ops - Delivery"],
    "Pickup Returns": ["Delivery Driver", "Ops - Delivery", "Ops - Returns"],
    "Return drop-off at warehouse": ["Delivery Driver", "Ops - Delivery"],
    "Returns processing / verification": ["Ops - Returns", "Ops - Inventory"],
    "Returns restocking": ["Ops - Returns"],
    "Invoice preparation / create invoice": ["Ops - Accounting"],
    "Debt Collection": ["Ops - Finance", "Ops - Directors"],
    "Discount Approval": ["Ops - Directors"],
    "Purchase Approval": ["Ops - Directors"],
    "Write-off Approval": ["Ops - Directors"],
}
allowed = TASK_KIND_ALLOWED_ROLES.get(task.task_kind) or []
roles = frappe.get_roles(frappe.session.user) or []
if allowed and not any(r in roles for r in allowed) and frappe.session.user != "Administrator" and "System Manager" not in roles:
    frappe.throw("You are not allowed to accept this task kind. Required role: " + ", ".join(allowed))
try:
    assigned = frappe.parse_json(task.get("_assign") or "[]") or []
except Exception:
    assigned = []
team_placeholders = ["inventory.team@example.com", "delivery.team@example.com", "returns.team@example.com", "accounting.team@example.com", "finance.team@example.com", "order.creation.team@example.com", "order.team@example.com"]
real_assigned = [u for u in assigned if u not in team_placeholders]
if real_assigned and frappe.session.user not in real_assigned:
    frappe.throw("Task is already accepted by: " + ", ".join(real_assigned))
task._assign = frappe.as_json([frappe.session.user])
task.status = "Working"
task.custom_is_team_queue_task = 1
task.custom_team_queue_status = "Accepted"
task.custom_accepted_by = frappe.session.user
task.custom_accepted_at = now_datetime()
task.flags.ignore_permissions = True
task.save()
open_todos = frappe.get_all("ToDo", filters={"reference_type": "Task", "reference_name": task.name, "status": "Open"}, pluck="name")
for td in open_todos or []:
    allocated_to = frappe.db.get_value("ToDo", td, "allocated_to")
    if allocated_to != frappe.session.user:
        frappe.db.set_value("ToDo", td, "status", "Cancelled")
frappe.response["message"] = {"ok": True, "task": task.name, "assigned_to": frappe.session.user, "status": task.status}
'@

$TaskQueueClient = @'
frappe.listview_settings["Task"] = frappe.listview_settings["Task"] || {};
frappe.listview_settings["Task"].onload = function(listview) {
    listview.page.add_inner_button(__("My Team Queue"), function() {
        listview.filter_area.clear();
        listview.filter_area.add([["Task", "custom_is_team_queue_task", "=", 1]]);
        listview.filter_area.add([["Task", "custom_team_queue_status", "=", "Open For Team"]]);
        listview.refresh();
    });
};
frappe.ui.form.on("Task", {
    refresh(frm) {
        if (!frm.is_new() && frm.doc.custom_is_team_queue_task && frm.doc.custom_team_queue_status === "Open For Team") {
            frm.add_custom_button(__("Accept / Start Task"), function() {
                frappe.call({ method: "dispatch_task_accept", args: { task_name: frm.doc.name }, freeze: true, callback: function() { frm.reload_doc(); } });
            });
        }
    }
});
'@

$ServerScripts = @(
    [pscustomobject]@{name="Task-team-queue-notify";script_type="DocType Event";reference_doctype="Task";doctype_event="After Save";script=$TaskQueueAfterSave},
    [pscustomobject]@{name="dispatch_task_accept";script_type="API";api_method="dispatch_task_accept";script=$TaskAcceptApi}
)
$ClientScripts = @([pscustomobject]@{name="Task-Team Queue";dt="Task";script=$TaskQueueClient})

$Report=[ordered]@{mode=$Mode;custom_fields=@();server_scripts=@();client_scripts=@();notes=@()}
foreach($f in $TaskFields){
    $E=Get-ErpDoc "Custom Field" $f.name
    if($Mode -eq "Deploy"){ $Report.custom_fields += Upsert-ErpDoc "Custom Field" $f.name (Build-CustomFieldBody $f) } else { $Report.custom_fields += [pscustomobject]@{name=$f.name;exists=($null -ne $E)} }
}
foreach($s in $ServerScripts){
    $E=Get-ErpDoc "Server Script" $s.name
    if($Mode -eq "Deploy"){
        $Body=[ordered]@{script_type=$s.script_type;allow_guest=0;disabled=0;enable_rate_limit=0;script=$s.script}
        if($s.reference_doctype){$Body.reference_doctype=$s.reference_doctype;$Body.doctype_event=$s.doctype_event;$Body.event_frequency="All"}
        if($s.api_method){$Body.api_method=$s.api_method}
        $Report.server_scripts += Upsert-ErpDoc "Server Script" $s.name $Body
    } else { $Report.server_scripts += [pscustomobject]@{name=$s.name;exists=($null -ne $E)} }
}
foreach($c in $ClientScripts){
    $E=Get-ErpDoc "Client Script" $c.name
    if($Mode -eq "Deploy"){ $Report.client_scripts += Upsert-ErpDoc "Client Script" $c.name ([ordered]@{dt=$c.dt;view="List";enabled=1;script=$c.script}) } else { $Report.client_scripts += [pscustomobject]@{name=$c.name;exists=($null -ne $E)} }
}
$Report.notes += "Step 1 deployed team queue fields, task role queue notification ToDos, and enhanced accept/start tracking."
$Report | ConvertTo-Json -Depth 30
