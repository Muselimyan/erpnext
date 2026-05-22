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
$Headers    = @{
    Authorization = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
}

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 30 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 30
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
        return [pscustomobject]@{ action="created"; name=$Created.name }
    }
    $Updated = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{ action="updated"; name=$Updated.name }
}

function Build-CustomFieldBody ($f) {
    $Body = [ordered]@{
        dt        = $f.dt
        fieldname = $f.fieldname
        label     = $f.label
        fieldtype = $f.fieldtype
    }
    foreach ($Prop in @("options", "insert_after", "default", "read_only", "in_list_view", "in_standard_filter", "allow_on_submit", "depends_on", "description")) {
        if ($f.PSObject.Properties[$Prop]) { $Body[$Prop] = $f.$Prop }
    }
    return $Body
}

$CustomFields = @(
    [pscustomobject]@{ name="Dispatch Case-custom_packing_scan_barcode"; dt="Dispatch Case"; fieldname="custom_packing_scan_barcode"; label="Packing Scan Barcode"; fieldtype="Data"; insert_after="case_items"; allow_on_submit=1 },
    [pscustomobject]@{ name="Dispatch Case-custom_packing_scan_qty"; dt="Dispatch Case"; fieldname="custom_packing_scan_qty"; label="Packing Scan Qty"; fieldtype="Float"; insert_after="custom_packing_scan_barcode"; default="1"; allow_on_submit=1 },
    [pscustomobject]@{ name="Dispatch Case-custom_packing_scan_result"; dt="Dispatch Case"; fieldname="custom_packing_scan_result"; label="Packing Scan Result"; fieldtype="Small Text"; insert_after="custom_packing_scan_qty"; read_only=1; allow_on_submit=1 },
    [pscustomobject]@{ name="Dispatch Case-custom_packing_last_warning"; dt="Dispatch Case"; fieldname="custom_packing_last_warning"; label="Packing Last Warning"; fieldtype="Small Text"; insert_after="custom_packing_scan_result"; read_only=1; allow_on_submit=1 },

    [pscustomobject]@{ name="Dispatch Case Item-custom_packing_status"; dt="Dispatch Case Item"; fieldname="custom_packing_status"; label="Packing Status"; fieldtype="Select"; options="Pending`nPartial`nComplete`nOver Scanned`nProblem"; insert_after="dispatched_qty"; default="Pending"; in_list_view=1; allow_on_submit=1 },
    [pscustomobject]@{ name="Dispatch Case Item-custom_scanned_qty"; dt="Dispatch Case Item"; fieldname="custom_scanned_qty"; label="Scanned Qty"; fieldtype="Float"; insert_after="custom_packing_status"; default="0"; in_list_view=1; allow_on_submit=1 },
    [pscustomobject]@{ name="Dispatch Case Item-custom_remaining_qty"; dt="Dispatch Case Item"; fieldname="custom_remaining_qty"; label="Remaining Qty"; fieldtype="Float"; insert_after="custom_scanned_qty"; read_only=1; in_list_view=1; allow_on_submit=1 },
    [pscustomobject]@{ name="Dispatch Case Item-custom_last_scanned_barcode"; dt="Dispatch Case Item"; fieldname="custom_last_scanned_barcode"; label="Last Scanned Barcode"; fieldtype="Data"; insert_after="batch_no"; read_only=1; allow_on_submit=1 },
    [pscustomobject]@{ name="Dispatch Case Item-custom_last_scan_at"; dt="Dispatch Case Item"; fieldname="custom_last_scan_at"; label="Last Scan At"; fieldtype="Datetime"; insert_after="custom_last_scanned_barcode"; read_only=1; allow_on_submit=1 },
    [pscustomobject]@{ name="Dispatch Case Item-custom_last_scanned_by"; dt="Dispatch Case Item"; fieldname="custom_last_scanned_by"; label="Last Scanned By"; fieldtype="Link"; options="User"; insert_after="custom_last_scan_at"; read_only=1; allow_on_submit=1 },
    [pscustomobject]@{ name="Dispatch Case Item-custom_fefo_warning"; dt="Dispatch Case Item"; fieldname="custom_fefo_warning"; label="FEFO Warning"; fieldtype="Small Text"; insert_after="custom_last_scanned_by"; read_only=1; allow_on_submit=1 },
    [pscustomobject]@{ name="Dispatch Case Item-custom_scan_note"; dt="Dispatch Case Item"; fieldname="custom_scan_note"; label="Packing Scan Note"; fieldtype="Small Text"; insert_after="custom_fefo_warning"; allow_on_submit=1 }
)

$PackingScanApi = @'
case_name = frappe.form_dict.get("case_name")
barcode = (frappe.form_dict.get("barcode") or "").strip()
qty = float(frappe.form_dict.get("qty") or 1)
MAIN_WH = "Main - Inmed"

if not case_name:
    frappe.throw("Dispatch Case is required.")
if not barcode:
    frappe.throw("Barcode is required.")
if qty <= 0:
    frappe.throw("Scan quantity must be greater than zero.")

case = frappe.get_doc("Dispatch Case", case_name)

item_code = None
batch_no = None
expiry_date = None
raw = barcode.replace("]C1", "").replace("]d2", "")

if frappe.db.exists("Item", barcode):
    item_code = barcode

if not item_code:
    ib = frappe.db.get_value("Item Barcode", {"barcode": barcode}, "parent")
    if ib:
        item_code = ib

if "17" in raw and "10" in raw:
    try:
        p17 = raw.index("17")
        exp6 = raw[p17 + 2:p17 + 8]
        if len(exp6) == 6 and exp6.isdigit():
            yy = int(exp6[0:2])
            mm = int(exp6[2:4])
            dd = int(exp6[4:6])
            yyyy = 2000 + yy
            expiry_date = f"{yyyy:04d}-{mm:02d}-{dd:02d}"
        p10 = raw.index("10")
        lot = raw[p10 + 2:]
        for marker in ["17", "11", "21"]:
            cut = lot.find(marker)
            if cut > 0:
                lot = lot[:cut]
        batch_no = lot.strip("() ")[:80]
    except Exception:
        pass

if batch_no and not item_code:
    b_item = frappe.db.get_value("Batch", batch_no, "item")
    if b_item:
        item_code = b_item

if not item_code:
    frappe.throw("Could not identify Item from barcode. Scan the product REF/item barcode first, or use a barcode linked to an Item.")

matching_rows = []
for row in (case.case_items or []):
    required = float(row.dispatched_qty or 0)
    scanned = float(row.get("custom_scanned_qty") or 0)
    if row.item_code == item_code and scanned < required:
        matching_rows.append(row)

if not matching_rows:
    frappe.throw("This item is not required for this Dispatch Case, or it is already fully scanned: " + item_code)

row = matching_rows[0]
required = float(row.dispatched_qty or 0)
scanned = float(row.get("custom_scanned_qty") or 0) + qty
remaining = required - scanned

warning = ""
if batch_no:
    row.batch_no = batch_no
    batch_expiry = frappe.db.get_value("Batch", batch_no, "expiry_date")
    if batch_expiry and not expiry_date:
        expiry_date = str(batch_expiry)

if expiry_date:
    try:
        earlier_batches = frappe.get_all(
            "Batch",
            filters={"item": item_code, "disabled": 0, "expiry_date": ["<", expiry_date]},
            fields=["name", "expiry_date"],
            order_by="expiry_date asc",
            limit_page_length=10,
        )
        available_earlier = []
        for b in earlier_batches:
            available_qty = 0
            try:
                res = frappe.db.sql(
                    """
                    select coalesce(sum(actual_qty), 0)
                    from `tabStock Ledger Entry`
                    where item_code=%s and warehouse=%s and batch_no=%s and is_cancelled=0
                    """,
                    (item_code, MAIN_WH, b.name),
                )
                available_qty = float(res[0][0] or 0) if res else 0
            except Exception:
                available_qty = 0
            if available_qty > 0:
                available_earlier.append(f"{b.name} exp {b.expiry_date} qty {available_qty}")
        if available_earlier:
            warning = "FEFO warning only: earlier-expiring stock exists in Main - Inmed. Consider using first: " + "; ".join(available_earlier[:3])
    except Exception as e:
        warning = "FEFO check could not be completed: " + str(e)

row.custom_scanned_qty = scanned
row.custom_remaining_qty = remaining if remaining > 0 else 0
row.custom_last_scanned_barcode = barcode
row.custom_last_scan_at = now_datetime()
row.custom_last_scanned_by = frappe.session.user
row.custom_fefo_warning = warning
if scanned < required:
    row.custom_packing_status = "Partial"
elif scanned == required:
    row.custom_packing_status = "Complete"
else:
    row.custom_packing_status = "Over Scanned"

all_complete = True
for r in (case.case_items or []):
    req = float(r.dispatched_qty or 0)
    scn = float(r.get("custom_scanned_qty") or 0)
    r.custom_remaining_qty = max(req - scn, 0)
    if scn < req:
        all_complete = False

case.custom_packing_scan_barcode = ""
case.custom_packing_scan_qty = 1
case.custom_packing_scan_result = f"Scanned {qty} x {item_code}. Row scanned {scanned}/{required}."
case.custom_packing_last_warning = warning
case.flags.ignore_permissions = True
case.flags.ignore_validate_update_after_submit = True
case.save()

frappe.response["message"] = {
    "ok": True,
    "item_code": item_code,
    "batch_no": batch_no,
    "expiry_date": expiry_date,
    "row_scanned_qty": scanned,
    "row_required_qty": required,
    "all_complete": all_complete,
    "warning": warning,
}
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
task.flags.ignore_permissions = True
task.save()

open_todos = frappe.get_all("ToDo", filters={"reference_type": "Task", "reference_name": task.name, "status": "Open"}, pluck="name")
for td in open_todos or []:
    frappe.db.set_value("ToDo", td, "status", "Cancelled")

todo = frappe.new_doc("ToDo")
todo.status = "Open"
todo.allocated_to = frappe.session.user
todo.reference_type = "Task"
todo.reference_name = task.name
todo.description = task.subject or task.name
todo.assigned_by = frappe.session.user
todo.insert(ignore_permissions=True)

frappe.response["message"] = {"ok": True, "task": task.name, "assigned_to": frappe.session.user, "status": task.status}
'@

$DispatchCaseClientScript = @'
frappe.ui.form.on("Dispatch Case", {
    refresh(frm) {
        if (!frm.is_new()) {
            frm.add_custom_button(__("Scan Packing Barcode"), function() {
                dispatch_case_scan_packing_barcode(frm);
            }, __("Packing"));
        }
    },
    custom_packing_scan_barcode(frm) {
        if (frm.doc.custom_packing_scan_barcode) {
            dispatch_case_scan_packing_barcode(frm);
        }
    }
});

function dispatch_case_scan_packing_barcode(frm) {
    const barcode = (frm.doc.custom_packing_scan_barcode || "").trim();
    const qty = frm.doc.custom_packing_scan_qty || 1;
    if (!barcode) {
        frappe.msgprint(__("Scan or enter a barcode first."));
        return;
    }
    frappe.call({
        method: "dispatch_case_packing_scan",
        args: { case_name: frm.doc.name, barcode: barcode, qty: qty },
        freeze: true,
        freeze_message: __("Checking packing scan..."),
        callback: function(r) {
            const msg = r.message || {};
            if (msg.warning) {
                frappe.msgprint({ title: __("FEFO Warning"), indicator: "orange", message: msg.warning });
            } else {
                frappe.show_alert({ message: __("Scan accepted"), indicator: "green" });
            }
            frm.reload_doc();
        }
    });
}
'@

$TaskClientScript = @'
frappe.ui.form.on("Task", {
    refresh(frm) {
        const operationalKinds = [
            "Order entry", "Pack / prepare items", "Dispatch picking / hand-off", "Delivery",
            "Pickup Returns", "Return drop-off at warehouse", "Returns processing / verification",
            "Returns restocking", "Invoice preparation / create invoice", "Debt Collection",
            "Discount Approval", "Purchase Approval", "Write-off Approval"
        ];
        if (!frm.is_new() && operationalKinds.includes(frm.doc.task_kind) && ["Open", "Working"].includes(frm.doc.status)) {
            frm.add_custom_button(__("Accept / Start Task"), function() {
                frappe.call({
                    method: "dispatch_task_accept",
                    args: { task_name: frm.doc.name },
                    freeze: true,
                    freeze_message: __("Accepting task..."),
                    callback: function() { frm.reload_doc(); }
                });
            });
        }
    }
});
'@

$ServerScripts = @(
    [pscustomobject]@{ name="dispatch_case_packing_scan"; script_type="API"; api_method="dispatch_case_packing_scan"; script=$PackingScanApi; disabled=0 },
    [pscustomobject]@{ name="dispatch_task_accept"; script_type="API"; api_method="dispatch_task_accept"; script=$TaskAcceptApi; disabled=0 }
)

$ClientScripts = @(
    [pscustomobject]@{ name="Dispatch Case-Packing Scan"; dt="Dispatch Case"; script=$DispatchCaseClientScript },
    [pscustomobject]@{ name="Task-Accept Start"; dt="Task"; script=$TaskClientScript }
)

$Report = [ordered]@{ mode=$Mode; custom_fields=@(); server_scripts=@(); client_scripts=@(); notes=@() }

foreach ($f in $CustomFields) {
    $Existing = Get-ErpDoc -DocType "Custom Field" -Name $f.name
    $Report.custom_fields += [pscustomobject]@{ name=$f.name; exists=($null -ne $Existing); action=if($Mode -eq "Deploy"){ "upsert" } else { "check_only" } }
    if ($Mode -eq "Deploy") {
        $Body = Build-CustomFieldBody $f
        $Report.custom_fields[-1] = Upsert-ErpDoc -DocType "Custom Field" -Name $f.name -Body $Body
    }
}

foreach ($s in $ServerScripts) {
    $Existing = Get-ErpDoc -DocType "Server Script" -Name $s.name
    $Report.server_scripts += [pscustomobject]@{ name=$s.name; exists=($null -ne $Existing); action=if($Mode -eq "Deploy"){ "upsert" } else { "check_only" } }
    if ($Mode -eq "Deploy") {
        $Body = [ordered]@{
            script_type       = $s.script_type
            api_method        = $s.api_method
            allow_guest       = 0
            disabled          = $s.disabled
            enable_rate_limit = 0
            script            = $s.script
        }
        $Report.server_scripts[-1] = Upsert-ErpDoc -DocType "Server Script" -Name $s.name -Body $Body
    }
}

foreach ($c in $ClientScripts) {
    $Existing = Get-ErpDoc -DocType "Client Script" -Name $c.name
    $Report.client_scripts += [pscustomobject]@{ name=$c.name; exists=($null -ne $Existing); action=if($Mode -eq "Deploy"){ "upsert" } else { "check_only" } }
    if ($Mode -eq "Deploy") {
        $Body = [ordered]@{ dt=$c.dt; view="Form"; enabled=1; script=$c.script }
        $Report.client_scripts[-1] = Upsert-ErpDoc -DocType "Client Script" -Name $c.name -Body $Body
    }
}

$Report.notes += "FEFO is warning-only. The packing scan API warns when earlier-expiring available stock is detected, but it does not block the scan."
$Report.notes += "This script adds scan/progress fields and accept/start buttons. It does not yet replace the existing Dispatch Case task-generation scripts."
$Report | ConvertTo-Json -Depth 30
