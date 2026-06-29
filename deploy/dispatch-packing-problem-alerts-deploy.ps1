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
function Build-CustomFieldBody ($f) {
    $Body=[ordered]@{dt=$f.dt; fieldname=$f.fieldname; label=$f.label; fieldtype=$f.fieldtype}
    foreach($Prop in @("options","insert_after","default","read_only","in_list_view","in_standard_filter","allow_on_submit","description","depends_on")){ if($f.PSObject.Properties[$Prop]){ $Body[$Prop]=$f.$Prop } }
    return $Body
}

$Fields = @(
    [pscustomobject]@{name="Dispatch Case Item-custom_problem_reason";dt="Dispatch Case Item";fieldname="custom_problem_reason";label="Packing Problem Reason";fieldtype="Select";options="`nMissing Item`nWrong Item`nDamaged Product`nExpired Product`nBatch/LOT Problem`nQuantity Shortage`nOther";insert_after="custom_packing_status";allow_on_submit=1;depends_on="eval:doc.custom_packing_status=='Problem'"},
    [pscustomobject]@{name="Dispatch Case Item-custom_problem_alert_sent";dt="Dispatch Case Item";fieldname="custom_problem_alert_sent";label="Problem Alert Sent";fieldtype="Check";insert_after="custom_problem_reason";default="0";read_only=1;allow_on_submit=1},
    [pscustomobject]@{name="Dispatch Case-custom_packing_problem_status";dt="Dispatch Case";fieldname="custom_packing_problem_status";label="Packing Problem Status";fieldtype="Select";options="No Problem`nProblem Open`nProblem Reviewed";insert_after="custom_packing_last_warning";default="No Problem";in_standard_filter=1;allow_on_submit=1},
    [pscustomobject]@{name="Dispatch Case-custom_packing_problem_summary";dt="Dispatch Case";fieldname="custom_packing_problem_summary";label="Packing Problem Summary";fieldtype="Small Text";insert_after="custom_packing_problem_status";read_only=1;allow_on_submit=1},
    [pscustomobject]@{name="Dispatch Case-custom_problem_alert_sent";dt="Dispatch Case";fieldname="custom_problem_alert_sent";label="Problem Alert Sent";fieldtype="Check";insert_after="custom_packing_problem_summary";default="0";read_only=1;allow_on_submit=1}
)

$ProblemAlertScript = @'
problem_rows = []
for row in doc.get("case_items") or []:
    required = float(row.get("dispatched_qty") or 0)
    scanned = float(row.get("custom_scanned_qty") or 0)
    status = row.get("custom_packing_status")
    reason = row.get("custom_problem_reason") or row.get("custom_scan_note") or ""
    if status == "Problem" or scanned < required and status in ("Partial", "Pending"):
        problem_rows.append({"item_code": row.get("item_code"), "required": required, "scanned": scanned, "reason": reason, "row_name": row.name})
if not problem_rows:
    if doc.get("custom_packing_problem_status") and doc.get("custom_packing_problem_status") != "No Problem":
        frappe.db.set_value("Dispatch Case", doc.name, {"custom_packing_problem_status": "No Problem", "custom_packing_problem_summary": ""}, update_modified=False)
else:
    summary_parts = []
    for p in problem_rows[:5]:
        missing = p["required"] - p["scanned"]
        if missing < 0:
            missing = 0
        part = str(p["item_code"] or "Unknown Item") + " missing " + str(missing)
        if p["reason"]:
            part += " (" + str(p["reason"]) + ")"
        summary_parts.append(part)
    summary = "; ".join(summary_parts)
    updates = {"custom_packing_problem_status": "Problem Open", "custom_packing_problem_summary": summary}
    frappe.db.set_value("Dispatch Case", doc.name, updates, update_modified=False)
    if not doc.get("custom_problem_alert_sent"):
        manager_roles = ["Ops - Inventory Manager", "Ops - Directors", "System Manager"]
        users = []
        for role in manager_roles:
            role_users = frappe.get_all("Has Role", filters={"role": role, "parenttype": "User"}, pluck="parent")
            for user in role_users or []:
                if user not in users and frappe.db.get_value("User", user, "enabled"):
                    users.append(user)
        created = 0
        for user in users:
            exists = frappe.db.exists("ToDo", {"reference_type": "Dispatch Case", "reference_name": doc.name, "allocated_to": user, "status": "Open", "description": ["like", "Packing problem:%"]})
            if exists:
                continue
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = user
            todo.reference_type = "Dispatch Case"
            todo.reference_name = doc.name
            todo.description = "Packing problem: " + summary
            todo.assigned_by = frappe.session.user
            todo.insert(ignore_permissions=True)
            created += 1
        if created:
            frappe.db.set_value("Dispatch Case", doc.name, "custom_problem_alert_sent", 1, update_modified=False)
            for row in doc.get("case_items") or []:
                if row.get("custom_packing_status") == "Problem":
                    frappe.db.set_value("Dispatch Case Item", row.name, "custom_problem_alert_sent", 1, update_modified=False)
'@

$ClientScript = @'
frappe.ui.form.on("Dispatch Case", {
    refresh(frm) {
        if (frm.doc.custom_packing_problem_status === "Problem Open") {
            frm.dashboard.add_comment(__("Packing problem is open: {0}", [frm.doc.custom_packing_problem_summary || "See item rows"]), "red", true);
        }
        if (!frm.is_new() && frm.doc.custom_packing_problem_status === "Problem Open") {
            frm.add_custom_button(__("Mark Packing Problem Reviewed"), function() {
                frm.set_value("custom_packing_problem_status", "Problem Reviewed");
                frm.save();
            }, __("Packing"));
        }
    }
});
'@

$ServerScripts = @([pscustomobject]@{name="Dispatch Case-packing-problem-alerts";script_type="DocType Event";reference_doctype="Dispatch Case";doctype_event="After Save";script=$ProblemAlertScript})
$ClientScripts = @([pscustomobject]@{name="Dispatch Case-Packing Problem Alerts";dt="Dispatch Case";script=$ClientScript})

$Report=[ordered]@{mode=$Mode;custom_fields=@();server_scripts=@();client_scripts=@();notes=@()}
foreach($f in $Fields){
    $E=Get-ErpDoc "Custom Field" $f.name
    if($Mode -eq "Deploy"){ $Report.custom_fields += Upsert-ErpDoc "Custom Field" $f.name (Build-CustomFieldBody $f) } else { $Report.custom_fields += [pscustomobject]@{name=$f.name;exists=($null -ne $E)} }
}
foreach($s in $ServerScripts){
    $E=Get-ErpDoc "Server Script" $s.name
    if($Mode -eq "Deploy"){
        $Body=[ordered]@{script_type=$s.script_type;reference_doctype=$s.reference_doctype;doctype_event=$s.doctype_event;event_frequency="All";allow_guest=0;disabled=0;enable_rate_limit=0;script=$s.script}
        $Report.server_scripts += Upsert-ErpDoc "Server Script" $s.name $Body
    } else { $Report.server_scripts += [pscustomobject]@{name=$s.name;exists=($null -ne $E)} }
}
foreach($c in $ClientScripts){
    $E=Get-ErpDoc "Client Script" $c.name
    if($Mode -eq "Deploy"){ $Report.client_scripts += Upsert-ErpDoc "Client Script" $c.name ([ordered]@{dt=$c.dt;view="Form";enabled=1;script=$c.script}) } else { $Report.client_scripts += [pscustomobject]@{name=$c.name;exists=($null -ne $E)} }
}
$Report.notes += "Step 2 adds shortage/problem status fields and ToDo alerts for inventory managers/directors when packing rows are incomplete or marked Problem."
$Report | ConvertTo-Json -Depth 30
