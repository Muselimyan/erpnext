#Requires -Version 5.1
<#
.SYNOPSIS
    Doc 12A - Surgery Case Workflow deployment script.
    Creates Surgery Case child tables + parent DocType, adds Surgery Case link
    custom fields on Task/Stock Entry/Sales Invoice, creates the Surgery Case
    Workflow (12 states, 11 transitions), automation Server Script, and Client
    Script for field locking.
.PARAMETER Mode
    Check  - report current state without making changes (default)
    Deploy - create / update all artefacts (idempotent)
#>
param(
    [ValidateSet("Check","Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method }
    $Json = $Body | ConvertTo-Json -Depth 30
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
        $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ action="created"; name=$C.name }
    }
    $U = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{ action="updated"; name=$U.name }
}

# ---------------------------------------------------------------------------
# 1) Surgery Case Item (child table)
# ---------------------------------------------------------------------------
$CaseItemDocBody = [ordered]@{
    module="Custom"; custom=1; istable=1
    fields=@(
        [ordered]@{ fieldname="item";             fieldtype="Link";  label="Item";              options="Item"; reqd=1; in_list_view=1 },
        [ordered]@{ fieldname="dispatched_qty";   fieldtype="Float"; label="Dispatched Qty";    reqd=1;         in_list_view=1 },
        [ordered]@{ fieldname="returned_qty";     fieldtype="Float"; label="Returned Qty";      default="0";    in_list_view=1 },
        [ordered]@{ fieldname="lost_damaged_qty"; fieldtype="Float"; label="Lost / Damaged Qty";default="0";    in_list_view=1 },
        [ordered]@{ fieldname="used_qty";         fieldtype="Float"; label="Used Qty";          read_only=1;    in_list_view=1 }
    )
}

# ---------------------------------------------------------------------------
# 2) Surgery Case Serial Exception (child table)
# ---------------------------------------------------------------------------
$SerialExcDocBody = [ordered]@{
    module="Custom"; custom=1; istable=1
    fields=@(
        [ordered]@{ fieldname="item";           fieldtype="Link";       label="Item";           options="Item"; reqd=1 },
        [ordered]@{ fieldname="serial_no";      fieldtype="Data";       label="Serial No";      reqd=1 },
        [ordered]@{ fieldname="exception_type"; fieldtype="Select";     label="Exception Type"; options="`nMissing`nDamaged`nNot Serialized"; reqd=1 },
        [ordered]@{ fieldname="notes";          fieldtype="Small Text"; label="Notes" }
    )
}

# ---------------------------------------------------------------------------
# 3) Surgery Case (parent)
# ---------------------------------------------------------------------------
$WfOpts = "Draft`nPreparing`nDispatch Picking`nDispatched`nDelivered`nReturn Pickup Scheduled`nReturn Pickup In Transit`nReturns Verification`nReturns Received`nUsage Derived`nInvoiced`nClosed"

$SurgCaseDocBody = [ordered]@{
    module="Custom"; custom=1; autoname="SC-.YYYY.-.#####"
    fields=@(
        [ordered]@{ fieldname="client";                        fieldtype="Link";       label="Client (Doctor)";           options="Customer";       reqd=1; in_list_view=1 },
        [ordered]@{ fieldname="hospital";                      fieldtype="Link";       label="Hospital";                  options="Customer" },
        [ordered]@{ fieldname="hospital_branch";               fieldtype="Data";       label="Hospital Branch";           reqd=1 },
        [ordered]@{ fieldname="client_location_warehouse";     fieldtype="Link";       label="Client Location Warehouse"; options="Warehouse"; reqd=1 },
        [ordered]@{ fieldname="doctor_name";                   fieldtype="Data";       label="Doctor Name" },
        [ordered]@{ fieldname="surgery_date";                  fieldtype="Date";       label="Surgery Date";              reqd=1; in_list_view=1 },
        [ordered]@{ fieldname="surgery_set_type";              fieldtype="Link";       label="Collection Set";             options="Collection Set"; reqd=1 },
        [ordered]@{ fieldname="workflow_state";                fieldtype="Select";     label="Status";                    options=$WfOpts; default="Draft"; read_only=1; in_list_view=1 },
        [ordered]@{ fieldname="dispatch_group_id";             fieldtype="Data";       label="Dispatch Group ID" },
        [ordered]@{ fieldname="delivery_person";               fieldtype="Link";       label="Delivery Person";           options="User" },
        [ordered]@{ fieldname="return_pickup_delivery_person"; fieldtype="Link";       label="Return Pickup Person";      options="User" },
        [ordered]@{ fieldname="shortage_note";                 fieldtype="Long Text";  label="Shortage Note";             read_only=1 },
        [ordered]@{ fieldname="notes";                         fieldtype="Small Text"; label="Notes" },
        [ordered]@{ fieldname="packed_scan_log";               fieldtype="Long Text";  label="Packed Scan Log" },
        [ordered]@{ fieldname="returned_scan_log";             fieldtype="Long Text";  label="Returned Scan Log" },
        [ordered]@{ fieldname="dispatch_stock_entry";          fieldtype="Link";       label="Dispatch Stock Entry";      options="Stock Entry";   read_only=1 },
        [ordered]@{ fieldname="delivery_stock_entry";          fieldtype="Link";       label="Delivery Stock Entry";      options="Stock Entry";   read_only=1 },
        [ordered]@{ fieldname="return_pickup_stock_entry";     fieldtype="Link";       label="Return Pickup SE";          options="Stock Entry";   read_only=1 },
        [ordered]@{ fieldname="return_receive_stock_entry";    fieldtype="Link";       label="Return Receive SE";         options="Stock Entry";   read_only=1 },
        [ordered]@{ fieldname="consumption_stock_entry";       fieldtype="Link";       label="Consumption Stock Entry";   options="Stock Entry";   read_only=1 },
        [ordered]@{ fieldname="sales_invoice";                 fieldtype="Link";       label="Sales Invoice";             options="Sales Invoice"; read_only=1 },
        [ordered]@{ fieldname="delivery_task";                 fieldtype="Link";       label="Delivery Task";             options="Task";          read_only=1 },
        [ordered]@{ fieldname="return_pickup_task";            fieldtype="Link";       label="Return Pickup Task";        options="Task";          read_only=1 },
        [ordered]@{ fieldname="return_dropoff_task";           fieldtype="Link";       label="Return Drop-off Task";      options="Task";          read_only=1 },
        [ordered]@{ fieldname="case_items";                    fieldtype="Table";      label="Case Items";                options="Surgery Case Item" },
        [ordered]@{ fieldname="tool_serial_exceptions";        fieldtype="Table";      label="Tool Serial Exceptions";    options="Surgery Case Serial Exception" }
    )
    permissions=@(
        [ordered]@{ role="Ops - Order Accepting"; read=1; write=1; create=1; delete=0; permlevel=0 },
        [ordered]@{ role="Ops - Inventory";       read=1; write=1; create=0; delete=0; permlevel=0 },
        [ordered]@{ role="Ops - Delivery";        read=1; write=1; create=0; delete=0; permlevel=0 },
        [ordered]@{ role="Ops - Returns";         read=1; write=1; create=0; delete=0; permlevel=0 },
        [ordered]@{ role="Ops - Accounting";      read=1; write=1; create=0; delete=0; permlevel=0 },
        [ordered]@{ role="Delivery Driver";       read=1; write=0; create=0; delete=0; permlevel=0 }
    )
}

# ---------------------------------------------------------------------------
# 4) Custom Fields on existing DocTypes
# ---------------------------------------------------------------------------
$CustomFields = @(
    [pscustomobject]@{ name="Task-surgery_case";             dt="Task";         fieldname="surgery_case";     label="Surgery Case";    fieldtype="Link"; options="Surgery Case"; insert_after="dispatch_group_id" },
    [pscustomobject]@{ name="Stock Entry-surgery_case";      dt="Stock Entry";  fieldname="surgery_case";     label="Surgery Case";    fieldtype="Link"; options="Surgery Case"; insert_after="sales_order" },
    [pscustomobject]@{ name="Stock Entry-dispatch_group_id"; dt="Stock Entry";  fieldname="dispatch_group_id";label="Dispatch Group ID";fieldtype="Data";                         insert_after="surgery_case" },
    [pscustomobject]@{ name="Sales Invoice-surgery_case";    dt="Sales Invoice";fieldname="surgery_case";     label="Surgery Case";    fieldtype="Link"; options="Surgery Case"; insert_after="doctor_name" }
)

# ---------------------------------------------------------------------------
# 5) Workflow pre-requisites — Workflow State + Workflow Action Master records
#    Frappe v14 validates Workflow Document State.state as Link->Workflow State
#    and Workflow Transition.action as Link->Workflow Action Master.
# ---------------------------------------------------------------------------
$WorkflowStateNames = @(
    "Draft","Preparing","Dispatch Picking","Dispatched","Delivered",
    "Return Pickup Scheduled","Return Pickup In Transit",
    "Returns Verification","Returns Received","Usage Derived","Invoiced","Closed"
)

$WorkflowActionNames = @(
    "Start Preparing","Move to Dispatch Picking","Mark as Dispatched",
    "Mark as Delivered","Schedule Return Pickup","Mark Pickup In Transit",
    "Start Returns Verification","Mark Returns Received",
    "Derive Usage","Create Invoice","Close Case"
)

# ---------------------------------------------------------------------------
# 5b) Workflow  (12 states, 11 transitions)
# ---------------------------------------------------------------------------
$WorkflowBody = [ordered]@{
    workflow_name        = "Surgery Case Workflow"
    document_type        = "Surgery Case"
    workflow_state_field = "workflow_state"
    is_active            = 1
    states = @(
        [ordered]@{ state="Draft";                    doc_status="0"; allow_edit="Ops - Order Accepting" },
        [ordered]@{ state="Preparing";               doc_status="0"; allow_edit="Ops - Order Accepting" },
        [ordered]@{ state="Dispatch Picking";        doc_status="0"; allow_edit="Ops - Inventory" },
        [ordered]@{ state="Dispatched";              doc_status="0"; allow_edit="Ops - Delivery" },
        [ordered]@{ state="Delivered";               doc_status="0"; allow_edit="Ops - Order Accepting" },
        [ordered]@{ state="Return Pickup Scheduled"; doc_status="0"; allow_edit="Ops - Delivery" },
        [ordered]@{ state="Return Pickup In Transit";doc_status="0"; allow_edit="Ops - Returns" },
        [ordered]@{ state="Returns Verification";    doc_status="0"; allow_edit="Ops - Returns" },
        [ordered]@{ state="Returns Received";        doc_status="0"; allow_edit="Ops - Returns" },
        [ordered]@{ state="Usage Derived";           doc_status="0"; allow_edit="Ops - Accounting" },
        [ordered]@{ state="Invoiced";                doc_status="0"; allow_edit="Ops - Order Accepting" },
        [ordered]@{ state="Closed";                  doc_status="0"; allow_edit="System Manager" }
    )
    transitions = @(
        [ordered]@{ state="Draft";                    action="Start Preparing";           next_state="Preparing";                allowed="Ops - Order Accepting" },
        [ordered]@{ state="Preparing";               action="Move to Dispatch Picking";   next_state="Dispatch Picking";         allowed="Ops - Inventory" },
        [ordered]@{ state="Dispatch Picking";        action="Mark as Dispatched";         next_state="Dispatched";               allowed="Ops - Inventory" },
        [ordered]@{ state="Dispatched";              action="Mark as Delivered";          next_state="Delivered";                allowed="Ops - Delivery" },
        [ordered]@{ state="Delivered";               action="Schedule Return Pickup";     next_state="Return Pickup Scheduled";  allowed="Ops - Order Accepting" },
        [ordered]@{ state="Return Pickup Scheduled"; action="Mark Pickup In Transit";     next_state="Return Pickup In Transit"; allowed="Ops - Delivery" },
        [ordered]@{ state="Return Pickup In Transit";action="Start Returns Verification"; next_state="Returns Verification";     allowed="Ops - Returns" },
        [ordered]@{ state="Returns Verification";    action="Mark Returns Received";      next_state="Returns Received";         allowed="Ops - Returns" },
        [ordered]@{ state="Returns Received";        action="Derive Usage";               next_state="Usage Derived";            allowed="Ops - Returns" },
        [ordered]@{ state="Usage Derived";           action="Create Invoice";             next_state="Invoiced";                 allowed="Ops - Accounting" },
        [ordered]@{ state="Invoiced";                action="Close Case";                 next_state="Closed";                   allowed="Ops - Order Accepting" }
    )
}

# ---------------------------------------------------------------------------
# 6) Server Script - Surgery Case automation (Before Save)
#    Wrapped in _run() to allow internal return statements (safe_exec compat)
# ---------------------------------------------------------------------------
$SurgCaseScript = @'
def _run():
    MAIN_WH           = "Main - Inmed"
    DELIVERY_WH       = "Delivery In-Transit - Inmed"
    RETURN_TRANSIT_WH = "Return Pickup In-Transit - Inmed"
    RETURNS_WH        = "Returns - Inmed"

    def split_serials(s):
        if not s: return []
        return [x.strip() for x in str(s).split("\n") if x.strip()]

    def get_bin_qty(item_code, warehouse):
        return float(frappe.db.get_value("Bin", {"item_code": item_code, "warehouse": warehouse}, "actual_qty") or 0)

    def make_transfer(items, s_wh, t_wh, posting_dt=None):
        se = frappe.new_doc("Stock Entry")
        se.stock_entry_type = "Material Transfer"
        if posting_dt:
            se.set_posting_time = 1
            if hasattr(posting_dt, "date"):
                se.posting_date = posting_dt.date()
                se.posting_time = posting_dt.time()
            else:
                parts = str(posting_dt).split(" ")
                se.posting_date = parts[0]
                if len(parts) > 1: se.posting_time = parts[1].split(".")[0]
        for it in items:
            row = {"item_code": it["item_code"], "qty": it["qty"], "s_warehouse": s_wh, "t_warehouse": t_wh}
            if it.get("batch_no"):  row["batch_no"]  = it["batch_no"]
            if it.get("serial_no"): row["serial_no"] = it["serial_no"]
            se.append("items", row)
        if hasattr(se, "surgery_case"): se.surgery_case = doc.name
        if hasattr(se, "dispatch_group_id") and doc.dispatch_group_id:
            se.dispatch_group_id = doc.dispatch_group_id
        se.insert(ignore_permissions=True)
        return se

    def make_task(subject, task_kind, assign_user):
        t = frappe.new_doc("Task")
        t.subject = subject
        t.task_kind = task_kind
        t.task_access_policy = task_kind
        if hasattr(t, "surgery_case"): t.surgery_case = doc.name
        if hasattr(t, "customer"):     t.customer = doc.client
        if doc.dispatch_group_id:      t.dispatch_group_id = doc.dispatch_group_id
        if assign_user: t._assign = json.dumps([assign_user])
        t.insert(ignore_permissions=True)
        return t.name

    before       = doc.get_doc_before_save()
    before_state = (before.workflow_state if before else None) or "Draft"
    after_state  = doc.workflow_state or "Draft"
    state_changed = (before_state != after_state)

    # Auto-load template items on new case
    if after_state == "Draft" and doc.surgery_set_type and not (doc.case_items or []):
        st = frappe.get_doc("Collection Set", doc.surgery_set_type)
        for r in (st.items or []):
            if r.item and float(r.default_qty or 0) > 0:
                doc.append("case_items", {"item": r.item, "dispatched_qty": float(r.default_qty),
                                          "returned_qty": 0, "lost_damaged_qty": 0, "used_qty": 0})

    # Draft: non-blocking stock shortage warning
    if after_state == "Draft":
        warnings = []
        for row in (doc.case_items or []):
            planned = float(row.dispatched_qty or 0)
            if planned > 0:
                avail = get_bin_qty(row.item, MAIN_WH)
                if avail < planned:
                    warnings.append(row.item + ": planned=" + str(planned) + " avail=" + str(avail))
        doc.shortage_note = ("Draft stock warning:\n" + "\n".join(warnings)) if warnings else ""
        if warnings: frappe.msgprint(doc.shortage_note, title="Stock warning (Draft)")

    if after_state != "Draft" and not doc.client_location_warehouse:
        frappe.throw("Client Location Warehouse is required.")

    CLIENT_WH = doc.client_location_warehouse or ""

    dispatch_items = [{"item_code": r.item, "qty": float(r.dispatched_qty or 0)}
                      for r in (doc.case_items or []) if float(r.dispatched_qty or 0) > 0]
    returned_items = [{"item_code": r.item, "qty": float(r.returned_qty or 0)}
                      for r in (doc.case_items or []) if float(r.returned_qty or 0) > 0]

    # Create delivery task when delivery_person first set (idempotent)
    if (doc.delivery_person and not doc.delivery_task
            and after_state not in ("Draft", "Preparing", "Dispatch Picking")):
        doc.delivery_task = make_task(
            "Deliver - " + doc.name, "Delivery", doc.delivery_person)

    # Create return tasks when person set in Return Pickup Scheduled (idempotent)
    if doc.return_pickup_delivery_person and after_state == "Return Pickup Scheduled":
        if not doc.return_pickup_task:
            doc.return_pickup_task = make_task(
                "Pickup Returns - " + doc.name, "Pickup Returns", doc.return_pickup_delivery_person)
        if not doc.return_dropoff_task:
            doc.return_dropoff_task = make_task(
                "Return drop-off - " + doc.name, "Return drop-off at warehouse",
                doc.return_pickup_delivery_person)

    if not state_changed: return

    # Preparing -> Dispatch Picking: stock gate + draft dispatch SE
    if before_state == "Preparing" and after_state == "Dispatch Picking":
        shortages = []
        for it in dispatch_items:
            avail = get_bin_qty(it["item_code"], MAIN_WH)
            if avail < it["qty"]:
                shortages.append(it["item_code"] + ": need " + str(it["qty"]) + " have " + str(avail))
        if shortages:
            frappe.throw("Insufficient stock in " + MAIN_WH + ":\n" + "\n".join(shortages))
        if not doc.dispatch_stock_entry:
            doc.dispatch_stock_entry = make_transfer(dispatch_items, MAIN_WH, DELIVERY_WH, now_datetime()).name

    # Dispatch Picking -> Dispatched: dispatch SE must be submitted
    if before_state == "Dispatch Picking" and after_state == "Dispatched":
        if not doc.dispatch_stock_entry:
            frappe.throw("Dispatch Stock Entry is missing.")
        if frappe.db.get_value("Stock Entry", doc.dispatch_stock_entry, "docstatus") != 1:
            frappe.throw("Dispatch Stock Entry must be submitted before marking as Dispatched.")

    # Dispatched -> Delivered: delivery task gate + auto-submit delivery SE
    if before_state == "Dispatched" and after_state == "Delivered":
        if not doc.delivery_task:
            frappe.throw("Delivery Task is required. Set Delivery Person and save first.")
        if frappe.db.get_value("Task", doc.delivery_task, "status") != "Completed":
            frappe.throw("Delivery Task must be Completed (with Warehouse Pickup Photo) before marking Delivered.")
        if not doc.delivery_stock_entry:
            d_se = frappe.get_doc("Stock Entry", doc.dispatch_stock_entry)
            items_to_deliver = [{"item_code": it.item_code, "qty": float(it.qty or 0),
                                  "batch_no": getattr(it, "batch_no", None),
                                  "serial_no": getattr(it, "serial_no", None)} for it in d_se.items]
            se = make_transfer(items_to_deliver, DELIVERY_WH, CLIENT_WH, now_datetime())
            se.submit()
            doc.delivery_stock_entry = se.name

    # Return Pickup Scheduled -> Return Pickup In Transit: pickup task gate
    if before_state == "Return Pickup Scheduled" and after_state == "Return Pickup In Transit":
        if not doc.return_pickup_task:
            frappe.throw("Pickup Returns Task is required.")
        if frappe.db.get_value("Task", doc.return_pickup_task, "status") != "Completed":
            frappe.throw("Pickup Returns Task must be Completed before moving to In Transit.")

    # Return Pickup In Transit -> Returns Verification: dropoff task gate + draft return SEs
    if before_state == "Return Pickup In Transit" and after_state == "Returns Verification":
        if not doc.return_dropoff_task:
            frappe.throw("Return drop-off at warehouse Task is required.")
        if frappe.db.get_value("Task", doc.return_dropoff_task, "status") != "Completed":
            frappe.throw("Return drop-off Task must be Completed (with Warehouse Drop-off Photo) first.")
        pickup_dt = (frappe.db.get_value("Task", doc.return_pickup_task, "completed_at")
                     if doc.return_pickup_task else None) or now_datetime()
        if returned_items:
            if not doc.return_pickup_stock_entry:
                doc.return_pickup_stock_entry = make_transfer(
                    returned_items, CLIENT_WH, RETURN_TRANSIT_WH, pickup_dt).name
            if not doc.return_receive_stock_entry:
                doc.return_receive_stock_entry = make_transfer(
                    returned_items, RETURN_TRANSIT_WH, RETURNS_WH, now_datetime()).name

    # Returns Verification -> Returns Received: return SEs must be submitted
    if before_state == "Returns Verification" and after_state == "Returns Received":
        for fn in ("return_pickup_stock_entry", "return_receive_stock_entry"):
            se_name = getattr(doc, fn, None)
            if se_name and frappe.db.get_value("Stock Entry", se_name, "docstatus") != 1:
                frappe.throw("Return Stock Entry " + str(se_name) + " must be submitted before proceeding.")

    # Returns Received -> Usage Derived: compute used_qty + auto-submit Consumption SE
    if before_state == "Returns Received" and after_state == "Usage Derived":
        for row in (doc.case_items or []):
            row.used_qty = (float(row.dispatched_qty or 0) - float(row.returned_qty or 0)
                            - float(row.lost_damaged_qty or 0))
            if row.used_qty < 0:
                frappe.throw("Used Qty negative for " + row.item + ". Check dispatched/returned/lost.")
        if not doc.consumption_stock_entry:
            if not doc.delivery_stock_entry or not doc.return_pickup_stock_entry:
                frappe.throw("Delivery and Return Pickup SEs required before consumption posting.")
            d_se = frappe.get_doc("Stock Entry", doc.delivery_stock_entry)
            r_se = frappe.get_doc("Stock Entry", doc.return_pickup_stock_entry)
            d_by_key = {}; d_serials = {}
            for it in d_se.items:
                key = (it.item_code, getattr(it, "batch_no", None))
                d_by_key[key] = d_by_key.get(key, 0) + float(it.qty or 0)
                sers = split_serials(getattr(it, "serial_no", None))
                if sers: d_serials.setdefault(it.item_code, set()).update(sers)
            r_by_key = {}; r_serials = {}
            for it in r_se.items:
                key = (it.item_code, getattr(it, "batch_no", None))
                r_by_key[key] = r_by_key.get(key, 0) + float(it.qty or 0)
                sers = split_serials(getattr(it, "serial_no", None))
                if sers: r_serials.setdefault(it.item_code, set()).update(sers)
            cons = frappe.new_doc("Stock Entry")
            cons.stock_entry_type = "Material Issue"
            _now = now_datetime()
            cons.set_posting_time = 1
            if hasattr(_now, "date"):
                cons.posting_date = _now.date()
                cons.posting_time = _now.time()
            exc_set = set(r.serial_no for r in (doc.get("tool_serial_exceptions") or [])
                          if getattr(r, "serial_no", None))
            for row in (doc.case_items or []):
                issue_qty = float(row.dispatched_qty or 0) - float(row.returned_qty or 0)
                if issue_qty <= 0: continue
                missing_s = sorted(d_serials.get(row.item, set()) - r_serials.get(row.item, set()))
                if missing_s:
                    not_recorded = [s for s in missing_s if s not in exc_set]
                    if not_recorded:
                        frappe.throw("Missing serials must be in Tool Serial Exceptions before deriving usage:\n"
                                     + "\n".join(not_recorded))
                    cons.append("items", {"item_code": row.item, "qty": len(missing_s),
                                          "s_warehouse": CLIENT_WH, "serial_no": "\n".join(missing_s)})
                    continue
                batch_keys = [k for k in d_by_key if k[0] == row.item and k[1]]
                if batch_keys:
                    rem = issue_qty
                    for key in batch_keys:
                        used_by_batch = d_by_key[key] - r_by_key.get(key, 0)
                        if used_by_batch <= 0: continue
                        take = min(rem, used_by_batch)
                        cons.append("items", {"item_code": row.item, "qty": take,
                                               "s_warehouse": CLIENT_WH, "batch_no": key[1]})
                        rem -= take
                        if rem <= 0: break
                    if rem > 0:
                        frappe.throw("Cannot allocate used qty by batch for item " + row.item)
                else:
                    cons.append("items", {"item_code": row.item, "qty": issue_qty, "s_warehouse": CLIENT_WH})
            if hasattr(cons, "surgery_case"): cons.surgery_case = doc.name
            if hasattr(cons, "dispatch_group_id") and doc.dispatch_group_id:
                cons.dispatch_group_id = doc.dispatch_group_id
            cons.insert(ignore_permissions=True)
            cons.submit()
            doc.consumption_stock_entry = cons.name

    # Usage Derived -> Invoiced: create draft Sales Invoice for used qty
    if before_state == "Usage Derived" and after_state == "Invoiced":
        if not doc.sales_invoice:
            inv = frappe.new_doc("Sales Invoice")
            inv.customer = doc.client
            inv.update_stock = 0
            if hasattr(inv, "surgery_case"):    inv.surgery_case    = doc.name
            if hasattr(inv, "hospital"):        inv.hospital        = doc.hospital
            if hasattr(inv, "hospital_branch"): inv.hospital_branch = doc.hospital_branch
            if hasattr(inv, "doctor_name"):     inv.doctor_name     = doc.doctor_name
            for row in (doc.case_items or []):
                if float(row.used_qty or 0) > 0:
                    inv.append("items", {"item_code": row.item, "qty": row.used_qty})
            inv.insert(ignore_permissions=True)
            doc.sales_invoice = inv.name

    # Invoiced -> Closed: serial accountability gate
    if before_state == "Invoiced" and after_state == "Closed":
        if doc.delivery_stock_entry and doc.return_pickup_stock_entry:
            d_se2 = frappe.get_doc("Stock Entry", doc.delivery_stock_entry)
            r_se2 = frappe.get_doc("Stock Entry", doc.return_pickup_stock_entry)
            exc_set2 = set(r.serial_no for r in (doc.get("tool_serial_exceptions") or [])
                           if getattr(r, "serial_no", None))
            d_sers2 = {}
            for it in d_se2.items:
                sers = split_serials(getattr(it, "serial_no", None))
                if sers: d_sers2.setdefault(it.item_code, set()).update(sers)
            r_sers2 = {}
            for it in r_se2.items:
                sers = split_serials(getattr(it, "serial_no", None))
                if sers: r_sers2.setdefault(it.item_code, set()).update(sers)
            missing_all = [item_code + ": " + s
                           for item_code, sers in d_sers2.items()
                           for s in sorted(sers - r_sers2.get(item_code, set()))
                           if s not in exc_set2]
            if missing_all:
                frappe.throw("Cannot close: serial-tracked tools missing and not in Tool Serial Exceptions:\n"
                             + "\n".join(missing_all))

_run()
'@

$SurgCaseServerScript = [pscustomobject]@{
    name              = "Surgery-Case-before-save"
    script_type       = "DocType Event"
    reference_doctype = "Surgery Case"
    doctype_event     = "Before Save"
    event_frequency   = "All"
    allow_guest       = 0
    disabled          = 0
    enable_rate_limit = 0
    script            = $SurgCaseScript
}

# ---------------------------------------------------------------------------
# 7) Client Script - field locking based on workflow_state
# ---------------------------------------------------------------------------
$ClientJsScript = @'
frappe.ui.form.on('Surgery Case', {
    refresh(frm) {
        const s = frm.doc.workflow_state || 'Draft';
        const dispatch_editable = ['Draft', 'Preparing', 'Dispatch Picking'].includes(s);
        const returns_editable  = ['Return Pickup In Transit', 'Returns Verification'].includes(s);
        frm.fields_dict.case_items.grid.update_docfield_property('dispatched_qty',   'read_only', dispatch_editable ? 0 : 1);
        frm.fields_dict.case_items.grid.update_docfield_property('returned_qty',     'read_only', returns_editable  ? 0 : 1);
        frm.fields_dict.case_items.grid.update_docfield_property('lost_damaged_qty', 'read_only', returns_editable  ? 0 : 1);
        frm.fields_dict.case_items.grid.update_docfield_property('used_qty',         'read_only', 1);
        frm.refresh_fields();
    }
});
'@

$SurgCaseClientScript = [pscustomobject]@{
    name        = "Surgery-Case-field-locking"
    dt          = "Surgery Case"
    script_type = "Client"
    enabled     = 1
    script      = $ClientJsScript
}

# ---------------------------------------------------------------------------
# CHECK MODE
# ---------------------------------------------------------------------------
if ($Mode -eq "Check") {
    $Report = [ordered]@{
        mode="Check"; doctypes=@(); custom_fields=@(); workflow=$null; server_scripts=@(); client_scripts=@()
    }
    foreach ($Dt in @("Surgery Case Item","Surgery Case Serial Exception","Surgery Case")) {
        $E = Get-ErpDoc -DocType "DocType" -Name $Dt
        $Report.doctypes += [pscustomobject]@{ name=$Dt; exists=($null -ne $E) }
    }
    foreach ($F in $CustomFields) {
        $E = Get-ErpDoc -DocType "Custom Field" -Name $F.name
        $Report.custom_fields += [pscustomobject]@{ name=$F.name; dt=$F.dt; exists=($null -ne $E) }
    }
    $Report.workflow_states  = $WorkflowStateNames  | ForEach-Object { [pscustomobject]@{ name=$_; exists=($null -ne (Get-ErpDoc -DocType "Workflow State" -Name $_)) } }
    $Report.workflow_actions = $WorkflowActionNames | ForEach-Object { [pscustomobject]@{ name=$_; exists=($null -ne (Get-ErpDoc -DocType "Workflow Action Master" -Name $_)) } }
    $Wf = Get-ErpDoc -DocType "Workflow" -Name "Surgery Case Workflow"
    $Report.workflow = [pscustomobject]@{ name="Surgery Case Workflow"; exists=($null -ne $Wf); is_active=if($null -ne $Wf){$Wf.is_active}else{$null} }
    $Ss = Get-ErpDoc -DocType "Server Script" -Name $SurgCaseServerScript.name
    $Report.server_scripts += [pscustomobject]@{ name=$SurgCaseServerScript.name; exists=($null -ne $Ss); disabled=if($null -ne $Ss){$Ss.disabled}else{$null} }
    $Cs = Get-ErpDoc -DocType "Client Script" -Name $SurgCaseClientScript.name
    $Report.client_scripts += [pscustomobject]@{ name=$SurgCaseClientScript.name; exists=($null -ne $Cs); enabled=if($null -ne $Cs){$Cs.enabled}else{$null} }
    $Report | ConvertTo-Json -Depth 10
    return
}

# ---------------------------------------------------------------------------
# DEPLOY MODE
# ---------------------------------------------------------------------------
$Results = [ordered]@{
    mode="Deploy"; doctypes=@(); custom_fields=@(); workflow=$null; server_scripts=@(); client_scripts=@()
}

# -- Surgery Case Item (child table) --
$E = Get-ErpDoc -DocType "DocType" -Name "Surgery Case Item"
if ($null -ne $E) {
    if (-not $E.istable) {
        $U = (Invoke-ErpRequest -Method Put -Path "/api/resource/DocType/$(Enc 'Surgery Case Item')" -Body ([ordered]@{istable=1})).data
        $Results.doctypes += [pscustomobject]@{ action="fixed-istable"; name=$U.name }
    } else { $Results.doctypes += [pscustomobject]@{ action="exists"; name="Surgery Case Item" } }
} else {
    $CaseItemDocBody.name = "Surgery Case Item"
    $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/DocType" -Body $CaseItemDocBody).data
    $Results.doctypes += [pscustomobject]@{ action="created"; name=$C.name }
}

# -- Surgery Case Serial Exception (child table) --
$E = Get-ErpDoc -DocType "DocType" -Name "Surgery Case Serial Exception"
if ($null -ne $E) {
    if (-not $E.istable) {
        $U = (Invoke-ErpRequest -Method Put -Path "/api/resource/DocType/$(Enc 'Surgery Case Serial Exception')" -Body ([ordered]@{istable=1})).data
        $Results.doctypes += [pscustomobject]@{ action="fixed-istable"; name=$U.name }
    } else { $Results.doctypes += [pscustomobject]@{ action="exists"; name="Surgery Case Serial Exception" } }
} else {
    $SerialExcDocBody.name = "Surgery Case Serial Exception"
    $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/DocType" -Body $SerialExcDocBody).data
    $Results.doctypes += [pscustomobject]@{ action="created"; name=$C.name }
}
Start-Sleep -Seconds 2

# -- Surgery Case (parent) --
$E = Get-ErpDoc -DocType "DocType" -Name "Surgery Case"
if ($null -ne $E) {
    $Results.doctypes += [pscustomobject]@{ action="exists"; name="Surgery Case" }
} else {
    $SurgCaseDocBody.name = "Surgery Case"
    $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/DocType" -Body $SurgCaseDocBody).data
    $Results.doctypes += [pscustomobject]@{ action="created"; name=$C.name }
}
Start-Sleep -Seconds 2

# -- Custom Fields --
foreach ($F in $CustomFields) {
    $Body = [ordered]@{ dt=$F.dt; fieldname=$F.fieldname; label=$F.label; fieldtype=$F.fieldtype }
    if ($F.PSObject.Properties["options"])      { $Body.options      = $F.options }
    if ($F.PSObject.Properties["insert_after"]) { $Body.insert_after = $F.insert_after }
    $Results.custom_fields += Upsert-ErpDoc -DocType "Custom Field" -Name $F.name -Body $Body
}

# -- Workflow State records (Link target for Workflow Document State.state) --
$Results.workflow_states = @()
foreach ($S in $WorkflowStateNames) {
    $Results.workflow_states += Upsert-ErpDoc -DocType "Workflow State" -Name $S -Body ([ordered]@{ workflow_state_name=$S })
}

# -- Workflow Action Master records (Link target for Workflow Transition.action) --
$Results.workflow_actions = @()
foreach ($A in $WorkflowActionNames) {
    $Results.workflow_actions += Upsert-ErpDoc -DocType "Workflow Action Master" -Name $A -Body ([ordered]@{ workflow_action_name=$A })
}

# -- Workflow --
$Results.workflow = Upsert-ErpDoc -DocType "Workflow" -Name "Surgery Case Workflow" -Body $WorkflowBody

# -- Server Script --
$Results.server_scripts += Upsert-ErpDoc -DocType "Server Script" -Name $SurgCaseServerScript.name -Body ([ordered]@{
    script_type=$SurgCaseServerScript.script_type; reference_doctype=$SurgCaseServerScript.reference_doctype
    doctype_event=$SurgCaseServerScript.doctype_event; event_frequency=$SurgCaseServerScript.event_frequency
    allow_guest=$SurgCaseServerScript.allow_guest; disabled=$SurgCaseServerScript.disabled
    enable_rate_limit=$SurgCaseServerScript.enable_rate_limit; script=$SurgCaseServerScript.script
})

# -- Client Script --
$Results.client_scripts += Upsert-ErpDoc -DocType "Client Script" -Name $SurgCaseClientScript.name -Body ([ordered]@{
    dt=$SurgCaseClientScript.dt; script_type=$SurgCaseClientScript.script_type
    enabled=$SurgCaseClientScript.enabled; script=$SurgCaseClientScript.script
})

# ---------------------------------------------------------------------------
# FINAL SNAPSHOT
# ---------------------------------------------------------------------------
$Snapshot = [ordered]@{
    mode="Deploy/Verify"; doctypes=@(); custom_fields=@(); workflow=$null; server_scripts=@(); client_scripts=@()
}
foreach ($Dt in @("Surgery Case Item","Surgery Case Serial Exception","Surgery Case")) {
    $E = Get-ErpDoc -DocType "DocType" -Name $Dt
    $Snapshot.doctypes += [pscustomobject]@{ name=$Dt; exists=($null -ne $E) }
}
foreach ($F in $CustomFields) {
    $E = Get-ErpDoc -DocType "Custom Field" -Name $F.name
    $Snapshot.custom_fields += [pscustomobject]@{ name=$F.name; dt=$F.dt; exists=($null -ne $E) }
}
$Wf = Get-ErpDoc -DocType "Workflow" -Name "Surgery Case Workflow"
$Snapshot.workflow = [pscustomobject]@{ name="Surgery Case Workflow"; exists=($null -ne $Wf); is_active=if($null -ne $Wf){$Wf.is_active}else{$null} }
$Ss = Get-ErpDoc -DocType "Server Script" -Name $SurgCaseServerScript.name
$Snapshot.server_scripts += [pscustomobject]@{ name=$SurgCaseServerScript.name; exists=($null -ne $Ss); disabled=if($null -ne $Ss){$Ss.disabled}else{$null} }
$Cs = Get-ErpDoc -DocType "Client Script" -Name $SurgCaseClientScript.name
$Snapshot.client_scripts += [pscustomobject]@{ name=$SurgCaseClientScript.name; exists=($null -ne $Cs); enabled=if($null -ne $Cs){$Cs.enabled}else{$null} }

$Results | ConvertTo-Json -Depth 10
Write-Host "`n--- Post-deploy verification ---"
$Snapshot | ConvertTo-Json -Depth 10

