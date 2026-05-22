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
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}
function Get-ErpDoc { param([string]$DocType,[string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}
function Upsert-ErpDoc { param([string]$DocType,[string]$Name,$Body)
    $Existing = Get-ErpDoc $DocType $Name
    if ($null -eq $Existing) { $Body.name=$Name; $C=(Invoke-ErpRequest Post "/api/resource/$(Enc $DocType)" $Body).data; return [pscustomobject]@{action="created";name=$C.name} }
    $U=(Invoke-ErpRequest Put "/api/resource/$(Enc $DocType)/$(Enc $Name)" $Body).data; return [pscustomobject]@{action="updated";name=$U.name}
}

$IntegrationApi = @'
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
team_placeholders = ["inventory.team@example.com", "delivery.team@example.com", "returns.team@example.com", "accounting.team@example.com", "finance.team@example.com", "order.creation.team@example.com", "order.team@example.com", "directors.team@example.com"]
limit = int(frappe.form_dict.get("limit") or 200)
updated = 0
scanned = 0
tasks = frappe.get_all(
    "Task",
    filters={"dispatch_case": ["is", "set"], "status": ["not in", ["Completed", "Cancelled", "Template"]]},
    fields=["name", "task_kind", "status", "_assign", "custom_is_team_queue_task", "custom_team_queue_role", "custom_team_queue_status"],
    limit_page_length=limit,
)
for t in tasks:
    scanned += 1
    role = TASK_KIND_TEAM_ROLE.get(t.task_kind)
    if not role:
        continue
    try:
        assigned = frappe.parse_json(t.get("_assign") or "[]") or []
    except Exception:
        assigned = []
    real_assigned = [u for u in assigned if u not in team_placeholders]
    queue_status = "Accepted" if real_assigned else "Open For Team"
    values = {
        "custom_is_team_queue_task": 1,
        "custom_team_queue_role": role,
        "custom_team_queue_status": queue_status,
    }
    if real_assigned:
        values["custom_accepted_by"] = real_assigned[0]
    frappe.db.set_value("Task", t.name, values, update_modified=False)
    updated += 1
frappe.response["message"] = {"ok": True, "scanned": scanned, "updated": updated}
'@

$AfterSave = @'
def _run():
    if not doc.get("dispatch_case"):
        return
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
    role = TASK_KIND_TEAM_ROLE.get(doc.get("task_kind"))
    if not role:
        return
    if doc.status in ("Completed", "Cancelled", "Template"):
        frappe.db.set_value("Task", doc.name, "custom_team_queue_status", "Closed", update_modified=False)
        return
    team_placeholders = ["inventory.team@example.com", "delivery.team@example.com", "returns.team@example.com", "accounting.team@example.com", "finance.team@example.com", "order.creation.team@example.com", "order.team@example.com", "directors.team@example.com"]
    try:
        assigned = frappe.parse_json(doc.get("_assign") or "[]") or []
    except Exception:
        assigned = []
    real_assigned = [u for u in assigned if u not in team_placeholders]
    values = {
        "custom_is_team_queue_task": 1,
        "custom_team_queue_role": role,
        "custom_team_queue_status": "Accepted" if real_assigned else "Open For Team",
    }
    if real_assigned:
        values["custom_accepted_by"] = real_assigned[0]
    frappe.db.set_value("Task", doc.name, values, update_modified=False)
_run()
'@

$ServerScripts = @(
    [pscustomobject]@{name="dispatch_task_queue_backfill";script_type="API";api_method="dispatch_task_queue_backfill";script=$IntegrationApi},
    [pscustomobject]@{name="Task-dispatch-queue-integration";script_type="DocType Event";reference_doctype="Task";doctype_event="After Save";script=$AfterSave}
)

$Report=[ordered]@{mode=$Mode;server_scripts=@();backfill=$null;notes=@()}
foreach($s in $ServerScripts){
    $E=Get-ErpDoc "Server Script" $s.name
    if($Mode -eq "Deploy"){
        $Body=[ordered]@{script_type=$s.script_type;allow_guest=0;disabled=0;enable_rate_limit=0;script=$s.script}
        if($s.api_method){$Body.api_method=$s.api_method}
        if($s.reference_doctype){$Body.reference_doctype=$s.reference_doctype;$Body.doctype_event=$s.doctype_event;$Body.event_frequency="All"}
        $Report.server_scripts += Upsert-ErpDoc "Server Script" $s.name $Body
    } else { $Report.server_scripts += [pscustomobject]@{name=$s.name;exists=($null -ne $E)} }
}
if($Mode -eq "Deploy"){
    try { $Report.backfill = (Invoke-ErpRequest Get "/api/method/dispatch_task_queue_backfill?limit=500").message }
    catch { $Report.backfill = [pscustomobject]@{error=$_.Exception.Message} }
}
$Report.notes += "Step 3 integrates Dispatch Case operational tasks with team queue fields for existing and future tasks."
$Report | ConvertTo-Json -Depth 30
