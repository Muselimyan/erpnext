#Requires -Version 5.1
<#
.SYNOPSIS
    Doc 16A — Unified Dispatch Flow deployment script.
    Creates roles, team users, Task custom fields, Task Access Policies,
    child DocTypes (Dispatch Case Item, Debt Collection Invoice, Debt Collection Payment),
    parent Dispatch Case DocType, updated Task governance script, new dispatch
    flow server scripts, and the Dispatch Case client script.
.PARAMETER Mode
    Check  — report current state without making changes (default)
    Deploy — create / update all artefacts (idempotent)
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
# 1) ROLES
# ---------------------------------------------------------------------------
$NewRoles = @("Ops - Order Creating", "Ops - Finance")

# ---------------------------------------------------------------------------
# 2) TEAM USERS
# ---------------------------------------------------------------------------
$NewUsers = @(
    [pscustomobject]@{
        email      = "order.creation.team@example.com"
        first_name = "Order Creation"
        last_name  = "Team"
        role       = "Ops - Order Creating"
    },
    [pscustomobject]@{
        email      = "finance.team@example.com"
        first_name = "Finance"
        last_name  = "Team"
        role       = "Ops - Finance"
    }
)

# ---------------------------------------------------------------------------
# 3) CUSTOM FIELDS ON TASK
# ---------------------------------------------------------------------------
$TaskKindOptions = @(
    "Order entry",
    "Pack / prepare items",
    "Dispatch picking / hand-off",
    "Delivery",
    "Return to warehouse (aborted delivery / cancelled order)",
    "Pickup Returns",
    "Return drop-off at warehouse",
    "Returns processing / verification",
    "Returns restocking",
    "Invoice preparation / create invoice",
    "Debt Collection",
    "Distribute Payment",
    "Payment Received",
    "Discount Approval",
    "Purchase Approval",
    "Write-off Approval",
    "Other"
) -join "`n"

$TaskCustomFields = @(
    [pscustomobject]@{
        name         = "Task-task_kind"
        dt           = "Task"; fieldname="task_kind"; label="Task Kind"
        fieldtype    = "Select"; options=$TaskKindOptions.Trim()
        in_list_view = 1; in_standard_filter=1
        update_only  = $true
    },
    [pscustomobject]@{
        name="Task-dispatch_case"; dt="Task"; fieldname="dispatch_case"; label="Dispatch Case"
        fieldtype="Link"; options="Dispatch Case"
        insert_after="surgery_case"; in_list_view=1; in_standard_filter=1
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-dispatch_case_status"; dt="Task"; fieldname="dispatch_case_status"; label="Dispatch Case Status"
        fieldtype="Data"; read_only=1
        insert_after="dispatch_case"
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-delivery_status"; dt="Task"; fieldname="delivery_status"; label="Delivery Status"
        fieldtype="Select"; options="Todo`nPicked Up`nDelivered"
        insert_after="dispatch_case_status"; default="Todo"
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-pickup_status"; dt="Task"; fieldname="pickup_status"; label="Pickup Status"
        fieldtype="Select"; options="Todo`nPicked Up`nReturned to Warehouse"
        insert_after="delivery_status"; default="Todo"
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-return_pickup_driver"; dt="Task"; fieldname="return_pickup_driver"; label="Return Pickup Driver"
        fieldtype="Link"; options="User"; insert_after="pickup_status"
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-scheduled_return_date"; dt="Task"; fieldname="scheduled_return_date"; label="Scheduled Return Date"
        fieldtype="Date"; insert_after="return_pickup_driver"
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-new_payment_amount"; dt="Task"; fieldname="new_payment_amount"; label="New Payment Amount"
        fieldtype="Currency"; insert_after="scheduled_return_date"
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-payment_method_dc"; dt="Task"; fieldname="payment_method_dc"; label="Payment Method"
        fieldtype="Select"; options="`nCash`nBank Transfer`nCard"
        insert_after="new_payment_amount"
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-payment_reference_dc"; dt="Task"; fieldname="payment_reference_dc"; label="Payment Reference"
        fieldtype="Data"; insert_after="payment_method_dc"
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-total_outstanding"; dt="Task"; fieldname="total_outstanding"; label="Total Outstanding"
        fieldtype="Currency"; read_only=1; insert_after="payment_reference_dc"
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-available_advance_credit"; dt="Task"; fieldname="available_advance_credit"; label="Available Advance Credit"
        fieldtype="Currency"; read_only=1; insert_after="total_outstanding"
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-open_invoices"; dt="Task"; fieldname="open_invoices"; label="Open Invoices"
        fieldtype="Table"; options="Debt Collection Invoice"
        insert_after="available_advance_credit"
        update_only=$false
    },
    [pscustomobject]@{
        name="Task-payment_history"; dt="Task"; fieldname="payment_history"; label="Payment History"
        fieldtype="Table"; options="Debt Collection Payment"; read_only=1
        insert_after="open_invoices"
        update_only=$false
    }
)

# ---------------------------------------------------------------------------
# 4) TASK ACCESS POLICIES (2 new)
# ---------------------------------------------------------------------------
$NewTaskAccessPolicies = @("Payment Received", "Returns restocking")

# ---------------------------------------------------------------------------
# 5) CHILD DOCTYPE: Dispatch Case Item
# ---------------------------------------------------------------------------
$DispatchCaseItemBody = [ordered]@{
    name="Dispatch Case Item"; module="Custom"; custom=1; istable=1
    fields=@(
        [ordered]@{ fieldname="item_code";        fieldtype="Link";       label="Item Code";         options="Item";  reqd=1; in_list_view=1 },
        [ordered]@{ fieldname="item_name";        fieldtype="Data";       label="Item Name";         read_only=1 },
        [ordered]@{ fieldname="dispatched_qty";   fieldtype="Float";      label="Dispatched Qty";    reqd=1; in_list_view=1 },
        [ordered]@{ fieldname="serial_no";        fieldtype="Small Text"; label="Serial No" },
        [ordered]@{ fieldname="batch_no";         fieldtype="Link";       label="Batch No";          options="Batch" },
        [ordered]@{ fieldname="unit_price";       fieldtype="Currency";   label="Unit Price";        reqd=0 },
        [ordered]@{ fieldname="discount_pct";     fieldtype="Percent";    label="Discount %";        default="0" },
        [ordered]@{ fieldname="returned_qty";     fieldtype="Float";      label="Returned Qty";      default="0" },
        [ordered]@{ fieldname="lost_damaged_qty"; fieldtype="Float";      label="Lost / Damaged Qty";default="0" },
        [ordered]@{ fieldname="used_qty";         fieldtype="Float";      label="Used Qty";          read_only=1 }
    )
}

# ---------------------------------------------------------------------------
# 6) CHILD DOCTYPE: Debt Collection Invoice
# ---------------------------------------------------------------------------
$DebtCollectionInvoiceBody = [ordered]@{
    name="Debt Collection Invoice"; module="Custom"; custom=1; istable=1
    fields=@(
        [ordered]@{ fieldname="sales_invoice";      fieldtype="Link";     label="Sales Invoice";   options="Sales Invoice";  read_only=1; in_list_view=1 },
        [ordered]@{ fieldname="invoice_amount";     fieldtype="Currency"; label="Invoice Amount";  read_only=1; in_list_view=1 },
        [ordered]@{ fieldname="paid_amount";        fieldtype="Currency"; label="Paid Amount";     read_only=1 },
        [ordered]@{ fieldname="outstanding_amount"; fieldtype="Currency"; label="Outstanding";     read_only=1; in_list_view=1 },
        [ordered]@{ fieldname="allocated_now";      fieldtype="Currency"; label="Allocate Now" }
    )
}

# ---------------------------------------------------------------------------
# 7) CHILD DOCTYPE: Debt Collection Payment
# ---------------------------------------------------------------------------
$DebtCollectionPaymentBody = [ordered]@{
    name="Debt Collection Payment"; module="Custom"; custom=1; istable=1
    fields=@(
        [ordered]@{ fieldname="payment_date";   fieldtype="Datetime"; label="Payment Date";  read_only=1; in_list_view=1 },
        [ordered]@{ fieldname="amount";         fieldtype="Currency"; label="Amount";        read_only=1; in_list_view=1 },
        [ordered]@{ fieldname="method";         fieldtype="Select";   label="Method";        options="Cash`nBank Transfer`nCard"; read_only=1 },
        [ordered]@{ fieldname="reference";      fieldtype="Data";     label="Reference";     read_only=1 },
        [ordered]@{ fieldname="payment_entry";  fieldtype="Link";     label="Payment Entry"; options="Payment Entry"; read_only=1 }
    )
}

# ---------------------------------------------------------------------------
# 8) PARENT DOCTYPE: Dispatch Case
# ---------------------------------------------------------------------------
$StatusOpts = "Draft`nAwaiting Approval`nConfirmed`nPacked`nIn Transit`nDelivered`nAwaiting Return Pickup`nReturn Pickup Scheduled`nReturn In Transit`nReturns Received`nInvoice Pending`nInvoiced`nPayment Pending`nClosed"
$DiscApprOpts = "`nPending`nApproved`nRejected"

$DispatchCaseBody = [ordered]@{
    name="Dispatch Case"; module="Custom"; custom=1; is_submittable=1; autoname="DC-.YYYY.-.#####"
    fields=@(
        # Basic Info
        [ordered]@{ fieldname="customer";                   fieldtype="Link";       label="Customer";                    options="Customer"; reqd=1; in_list_view=1 },
        [ordered]@{ fieldname="currency";                   fieldtype="Link";       label="Currency";                    options="Currency"; default="AMD"; reqd=1 },
        [ordered]@{ fieldname="client_location_warehouse";  fieldtype="Link";       label="Client Location Warehouse";   options="Warehouse"; reqd=1 },
        [ordered]@{ fieldname="return_expected";            fieldtype="Check";      label="Return Expected";             default="0" },
        [ordered]@{ fieldname="surgery_date";               fieldtype="Date";       label="Surgery / Delivery Date" },
        [ordered]@{ fieldname="surgery_set_type";           fieldtype="Link";       label="Item Template";               options="Collection Set" },
        [ordered]@{ fieldname="status";                     fieldtype="Select";     label="Status";                      options=$StatusOpts; default="Draft"; read_only=1; allow_on_submit=1; in_list_view=1 },
        [ordered]@{ fieldname="notes";                      fieldtype="Small Text"; label="Notes" },
        # Items
        [ordered]@{ fieldname="items_section"; fieldtype="Section Break"; label="Items" },
        [ordered]@{ fieldname="case_items";                 fieldtype="Table";      label="Case Items";                  options="Dispatch Case Item" },
        # Linked Tasks
        [ordered]@{ fieldname="tasks_section"; fieldtype="Section Break"; label="Linked Tasks" },
        [ordered]@{ fieldname="order_entry_task";           fieldtype="Link";       label="Order Entry Task";            options="Task"; read_only=1 },
        [ordered]@{ fieldname="discount_approval_task";     fieldtype="Link";       label="Discount Approval Task";      options="Task"; read_only=1 },
        [ordered]@{ fieldname="discount_approval_status";   fieldtype="Select";     label="Discount Approval Status";    options=$DiscApprOpts; read_only=1 },
        [ordered]@{ fieldname="pack_task";                  fieldtype="Link";       label="Pack Task";                   options="Task"; read_only=1 },
        [ordered]@{ fieldname="delivery_task";              fieldtype="Link";       label="Delivery Task";               options="Task"; read_only=1 },
        [ordered]@{ fieldname="return_waiting_task";        fieldtype="Link";       label="Return Waiting Task";         options="Task"; read_only=1 },
        [ordered]@{ fieldname="return_pickup_task";         fieldtype="Link";       label="Return Pickup Task";          options="Task"; read_only=1 },
        [ordered]@{ fieldname="returns_inspection_task";    fieldtype="Link";       label="Returns Inspection Task";     options="Task"; read_only=1 },
        [ordered]@{ fieldname="restock_task";               fieldtype="Link";       label="Restock Task";                options="Task"; read_only=1 },
        [ordered]@{ fieldname="invoice_task";               fieldtype="Link";       label="Invoice Task";                options="Task"; read_only=1 },
        # Stock Entries
        [ordered]@{ fieldname="se_section"; fieldtype="Section Break"; label="Stock Entries" },
        [ordered]@{ fieldname="dispatch_stock_entry";       fieldtype="Link";       label="Dispatch SE";                 options="Stock Entry"; read_only=1 },
        [ordered]@{ fieldname="delivery_stock_entry";       fieldtype="Link";       label="Delivery SE";                 options="Stock Entry"; read_only=1 },
        [ordered]@{ fieldname="consumption_stock_entry";    fieldtype="Link";       label="Consumption SE";              options="Stock Entry"; read_only=1 },
        [ordered]@{ fieldname="return_pickup_stock_entry";  fieldtype="Link";       label="Return Pickup SE";            options="Stock Entry"; read_only=1 },
        [ordered]@{ fieldname="return_receive_stock_entry"; fieldtype="Link";       label="Return Receive SE";           options="Stock Entry"; read_only=1 },
        [ordered]@{ fieldname="restock_stock_entry";        fieldtype="Link";       label="Restock SE";                  options="Stock Entry"; read_only=1 },
        # Invoice & Payment
        [ordered]@{ fieldname="payment_section"; fieldtype="Section Break"; label="Invoice and Payment" },
        [ordered]@{ fieldname="sales_invoice";              fieldtype="Link";       label="Sales Invoice";               options="Sales Invoice"; read_only=1 },
        [ordered]@{ fieldname="prepaid_amount";             fieldtype="Currency";   label="Prepaid Amount";              default="0" },
        [ordered]@{ fieldname="prepaid_payment_entry";      fieldtype="Link";       label="Prepaid Payment Entry";       options="Payment Entry"; read_only=1 },
        [ordered]@{ fieldname="total_invoice_amount";       fieldtype="Currency";   label="Invoice Amount";              read_only=1 },
        [ordered]@{ fieldname="total_paid_amount";          fieldtype="Currency";   label="Total Paid";                  read_only=1 },
        [ordered]@{ fieldname="outstanding_amount";         fieldtype="Currency";   label="Outstanding";                 read_only=1 },
        # Photos
        [ordered]@{ fieldname="photo_section"; fieldtype="Section Break"; label="Photos" },
        [ordered]@{ fieldname="delivery_photo";             fieldtype="Attach";     label="Delivery Photo";              read_only=1 },
        [ordered]@{ fieldname="return_dropoff_photo";       fieldtype="Attach";     label="Return Drop-off Photo";       read_only=1 }
    )
}

# ---------------------------------------------------------------------------
# 9) SERVER SCRIPTS
# ---------------------------------------------------------------------------

# 9.1  Updated Task governance (adds new roles + skips old photo gates for dispatch tasks)
$TaskGovernanceScript = @'
before = doc.get_doc_before_save()
before_status = before.status if before else None
is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")
DIRECTOR_ROLE = "Ops - Directors"
TASK_KIND_ALLOWED_ROLES = {
    "Order entry": ["Ops - Order Accepting", "Ops - Order Creating"],
    "Pack / prepare items": ["Ops - Inventory"],
    "Dispatch picking / hand-off": ["Ops - Delivery"],
    "Delivery": ["Delivery Driver", "Ops - Delivery"],
    "Return to warehouse (aborted delivery / cancelled order)": ["Delivery Driver", "Ops - Delivery"],
    "Pickup Returns": ["Delivery Driver", "Ops - Delivery", "Ops - Returns"],
    "Return drop-off at warehouse": ["Delivery Driver", "Ops - Delivery"],
    "Returns processing / verification": ["Ops - Returns", "Ops - Inventory"],
    "Returns restocking": ["Ops - Returns"],
    "Invoice preparation / create invoice": ["Ops - Accounting"],
    "Debt Collection": ["Ops - Finance", "Ops - Directors"],
    "Distribute Payment": ["Ops - Finance", "Ops - Directors"],
    "Payment Received": ["Ops - Finance", "Ops - Directors"],
    "Discount Approval": ["Ops - Directors"],
    "Purchase Approval": ["Ops - Directors"],
    "Write-off Approval": ["Ops - Directors"],
    "Other": ["Ops - Order Accepting", "Ops - Order Creating", "Ops - Inventory", "Ops - Returns", "Ops - Delivery", "Ops - Accounting", "Ops - Directors", "Ops - Finance", "Delivery Driver"],
}
def current_user_roles():
    return set(frappe.get_all("Has Role", filters={"parent": frappe.session.user}, pluck="role"))
def has_any_role(user_roles, allowed_roles):
    return any(r in user_roles for r in (allowed_roles or []))
def is_admin_override(user_roles):
    return bool("System Manager" in user_roles or "Ops - Directors" in user_roles or frappe.session.user == "Administrator")
def get_assigned_users(task_doc):
    try:
        return json.loads(task_doc.get("_assign") or "[]") or []
    except Exception:
        return []
def user_has_allowed_role(user, allowed_roles):
    user_roles = set(frappe.get_all("Has Role", filters={"parent": user}, pluck="role"))
    return any(r in user_roles for r in (allowed_roles or []))
if doc.task_kind and not doc.task_access_policy:
    doc.task_access_policy = doc.task_kind
if doc.task_access_policy and not frappe.db.exists("Task Access Policy", doc.task_access_policy):
    frappe.throw("Task Access Policy '" + doc.task_access_policy + "' does not exist.")
user_roles = current_user_roles()
allowed_roles = TASK_KIND_ALLOWED_ROLES.get(doc.task_kind) or []
if before and doc.task_kind and not is_admin_override(user_roles):
    if not has_any_role(user_roles, allowed_roles):
        frappe.throw("You are not allowed to edit Task Kind '" + doc.task_kind + "'.")
if is_becoming_completed and doc.task_kind and not is_admin_override(user_roles):
    if not has_any_role(user_roles, allowed_roles):
        frappe.throw("Only " + ", ".join(allowed_roles) + " can complete Task Kind '" + doc.task_kind + "'.")
# Old-flow mandatory attachments (only for tasks NOT linked to a Dispatch Case)
if not doc.dispatch_case:
    if is_becoming_completed and doc.task_kind == "Delivery":
        if not doc.warehouse_pickup_photo:
            frappe.throw("Warehouse Pickup Photo is required to complete a Delivery task.")
    if is_becoming_completed and doc.task_kind == "Return drop-off at warehouse":
        if not doc.warehouse_dropoff_photo:
            frappe.throw("Warehouse Drop-off Photo is required to complete a Return drop-off at warehouse task.")
assigned_users = get_assigned_users(doc)
is_becoming_working = (doc.status == "Working" and before_status != "Working")
# TEMPORARILY DISABLED FOR LAUNCH - assignment validation causes issues with accept workflow
# Will re-enable after launch when workflow is stable
# if doc.task_kind and doc.status not in ("Cancelled", "Open", "Working") and not is_becoming_working:
#     if len(assigned_users) != 1:
#         frappe.throw("Each operational task must be assigned to exactly 1 user. Current count: " + str(len(assigned_users)) + ".")
# if doc.task_kind and len(assigned_users) == 1 and allowed_roles:
#     owner = assigned_users[0]
#     if not user_has_allowed_role(owner, allowed_roles):
#         frappe.throw("Task Kind '" + doc.task_kind + "' must be assigned to a user in: " + ", ".join(allowed_roles) + ".")
# if is_becoming_completed:
#     if len(assigned_users) != 1:
#         frappe.throw("Assign exactly 1 owner before completing this task.")
if is_becoming_completed and not doc.completed_at:
    doc.completed_at = frappe.utils.now_datetime()
'@

# 9.2  Dispatch Case Before Save — compute used_qty, detect discount
$DispatchCaseBeforeSave = @'
for row in (doc.case_items or []):
    dispatched = row.dispatched_qty or 0
    returned = row.returned_qty or 0
    lost = row.lost_damaged_qty or 0
    row.used_qty = dispatched - returned - lost
    if row.used_qty < 0:
        frappe.throw(f"Row {row.idx}: used_qty cannot be negative (dispatched={dispatched}, returned={returned}, lost={lost}).")
if doc.status == "Draft":
    has_discount = any(float(row.discount_pct or 0) > 0 for row in (doc.case_items or []))
    if has_discount:
        doc.status = "Awaiting Approval"
        doc.discount_approval_status = "Pending"
'@

# 9.3  Dispatch Case After Save — create Discount Approval task if needed
$DispatchCaseAfterSave = @'
if doc.status == "Awaiting Approval" and not doc.discount_approval_task:
    existing = frappe.db.exists("Task", {"dispatch_case": doc.name, "task_kind": "Discount Approval", "status": ["not in", ["Completed", "Cancelled"]]})
    if not existing:
        disc_lines = "\n".join(
            f"- {r.item_code} x{r.dispatched_qty}: {r.unit_price} AMD ({r.discount_pct}% off)"
            for r in doc.case_items if float(r.discount_pct or 0) > 0
        )
        t = frappe.get_doc({
            "doctype": "Task",
            "subject": f"Discount Approval: {doc.name} — {doc.customer}",
            "task_kind": "Discount Approval",
            "task_access_policy": "Discount Approval",
            "dispatch_case": doc.name,
            "customer": doc.customer,
            "description": f"Review and approve or reject discounts.\n\n{disc_lines}",
        })
        t.flags.ignore_permissions = True
        t.insert()
        frappe.db.set_value("Dispatch Case", doc.name, "discount_approval_task", t.name)
        # FIXED: Update _assign via db (assign_to module not available in RestrictedPython)
        frappe.db.set_value("Task", t.name, "_assign", json.dumps(["directors.team@example.com"]))
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = "directors.team@example.com"
        todo.reference_type = "Task"
        todo.reference_name = t.name
        todo.description = t.subject
        todo.assigned_by = frappe.session.user
        todo.flags.ignore_permissions = True
        todo.insert()
'@

# 9.4  Dispatch Case Before Submit — validate + create Pack task (no-discount path)
$DispatchCaseBeforeSubmit = @'
if not doc.case_items:
    frappe.throw("Add at least one item before submitting.")
if doc.status not in ("Draft", "Confirmed"):
    frappe.throw("Cannot submit a Dispatch Case in status: " + doc.status)
if doc.status == "Draft":
    doc.status = "Confirmed"
existing_pack = frappe.db.exists("Task", {"dispatch_case": doc.name, "task_kind": "Pack / prepare items", "status": ["not in", ["Completed", "Cancelled"]]})
if not existing_pack:
    items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in doc.case_items)
    t = frappe.get_doc({
        "doctype": "Task",
        "subject": f"Pack: {doc.name} — {doc.customer}",
        "task_kind": "Pack / prepare items",
        "task_access_policy": "Pack / prepare items",
        "dispatch_case": doc.name,
        "customer": doc.customer,
        "description": f"Pack for delivery to: {doc.customer}\nDest: {doc.client_location_warehouse}\n\n{items_txt}",
    })
    t.flags.ignore_permissions = True
    t.insert()
    doc.pack_task = t.name
    # FIXED: Update _assign via db (assign_to module not available in RestrictedPython)
    frappe.db.set_value("Task", t.name, "_assign", json.dumps(["inventory.team@example.com"]))
    todo = frappe.new_doc("ToDo")
    todo.status = "Open"
    todo.allocated_to = "inventory.team@example.com"
    todo.reference_type = "Task"
    todo.reference_name = t.name
    todo.description = t.subject
    todo.assigned_by = frappe.session.user
    todo.flags.ignore_permissions = True
    todo.insert()
'@

# 9.5  Task Before Save — dispatch gates (photo, serial/batch, quantities, approval)
$TaskDispatchGates = @'
if not doc.dispatch_case:
    pass
else:
    # Update dispatch_case_status field for display
    if doc.dispatch_case:
        dc_status = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "status")
        if dc_status:
            doc.dispatch_case_status = dc_status
    before = doc.get_doc_before_save()
    before_status = before.status if before else None
    before_ds = (before.delivery_status if before else None) or "Todo"
    before_ps = (before.pickup_status if before else None) or "Todo"
    is_completing = (doc.status == "Completed" and before_status != "Completed")
    ds_changing = (doc.task_kind == "Delivery" and doc.delivery_status != before_ds)
    ps_changing = (doc.task_kind == "Pickup Returns" and doc.pickup_status != before_ps)

    # Auto-complete Delivery task when marked Delivered
    if ds_changing and doc.delivery_status == "Delivered":
        if not doc.warehouse_pickup_photo:
            frappe.throw("Delivery Photo (Warehouse Pickup Photo) is required before marking Delivered.")
        doc.status = "Completed"

    # Auto-complete Return Pickup task when Returned to Warehouse
    if ps_changing and doc.pickup_status == "Returned to Warehouse":
        if not doc.warehouse_dropoff_photo:
            frappe.throw("Drop-off Photo (Warehouse Drop-off Photo) is required before marking Returned to Warehouse.")
        doc.status = "Completed"

    # Pack completion: require serial/batch
    # TEMPORARILY DISABLED FOR LAUNCH - will re-enable after barcode scanning is implemented
    # if is_completing and doc.task_kind == "Pack / prepare items":
    #     case = frappe.get_doc("Dispatch Case", doc.dispatch_case)
    #     for row in (case.case_items or []):
    #         item_doc = frappe.get_doc("Item", row.item_code)
    #         if item_doc.has_serial_no and not (row.serial_no or "").strip():
    #             frappe.throw(f"Serial No required for '{row.item_code}'. Open Dispatch Case and fill it in.")
    #         if item_doc.has_batch_no and not row.batch_no:
    #             frappe.throw(f"Batch No required for '{row.item_code}'. Open Dispatch Case and fill it in.")

    # Returns Inspection completion: require returned_qty
    if is_completing and doc.task_kind == "Returns processing / verification":
        case = frappe.get_doc("Dispatch Case", doc.dispatch_case)
        for row in (case.case_items or []):
            if row.returned_qty is None:
                frappe.throw("Fill returned_qty for ALL items in Dispatch Case before completing.")

    # Invoice Preparation completion: require submitted invoice
    if is_completing and doc.task_kind == "Invoice preparation / create invoice":
        inv = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "sales_invoice")
        if not inv:
            frappe.throw("No Sales Invoice linked to this Dispatch Case yet.")
        if frappe.db.get_value("Sales Invoice", inv, "docstatus") != 1:
            frappe.throw("Submit the Sales Invoice before completing this task.")

    # Discount Approval completion: require approval_outcome
    if is_completing and doc.task_kind == "Discount Approval":
        if not doc.approval_outcome:
            frappe.throw("Set Approval Outcome (Approved or Rejected) before completing.")
'@

# 9.6  Task After Save — main dispatch flow orchestrator
$TaskDispatchFlow = @'
COMPANY = "InMED"
MAIN_WH = "Main - Inmed"
DELIVERY_TRANSIT_WH = "Delivery In-Transit - Inmed"
RETURN_PICKUP_TRANSIT_WH = "Return Pickup In-Transit - Inmed"
RETURNS_WH = "Returns - Inmed"
INVENTORY_TEAM = "inventory.team@example.com"
DELIVERY_TEAM = "delivery.team@example.com"
RETURNS_TEAM = "returns.team@example.com"
ACCOUNTING_TEAM = "accounting.team@example.com"
FINANCE_TEAM = "finance.team@example.com"
ORDER_CREATION_TEAM = "order.creation.team@example.com"

if not doc.dispatch_case:
    pass
else:
    before = doc.get_doc_before_save()
    before_status = before.status if before else None
    before_ds = (before.delivery_status if before else None) or "Todo"
    before_ps = (before.pickup_status if before else None) or "Todo"
    is_completing = (doc.status == "Completed" and before_status != "Completed")
    ds_changed = (doc.task_kind == "Delivery" and doc.delivery_status != before_ds)
    ps_changed = (doc.task_kind == "Pickup Returns" and doc.pickup_status != before_ps)

    def create_se(src_wh, tgt_wh, items, purpose="Material Transfer"):
        se_items = []
        for ic, q, sn, bn in items:
            if (q or 0) <= 0:
                continue
            item_doc = frappe.get_doc("Item", ic)
            stock_uom = item_doc.stock_uom or "Nos"
            row = {
                "item_code": ic, 
                "qty": q,
                "transfer_qty": q,
                "uom": stock_uom,
                "stock_uom": stock_uom,
                "conversion_factor": 1,
                "s_warehouse": src_wh,
                "expense_account": "Cost of Goods Sold - Inmed",
                "cost_center": "Main - Inmed",
                "allow_zero_valuation_rate": 1
            }
            if sn:
                row["serial_no"] = sn
            if bn:
                row["batch_no"] = bn
            if purpose != "Material Issue":
                row["t_warehouse"] = tgt_wh
            se_items.append(row)
        if not se_items:
            return None
        se = frappe.get_doc({"doctype": "Stock Entry", "stock_entry_type": purpose, "purpose": purpose, "company": "InMED", "items": se_items})
        se.flags.ignore_permissions = True
        se.flags.ignore_validate = True
        frappe.flags.ignore_stock_validation = True
        se.insert()
        se.submit()
        frappe.flags.ignore_stock_validation = False
        return se

    def all_items(c):
        return [(r.item_code, r.dispatched_qty, r.serial_no, r.batch_no) for r in (c.case_items or [])]

    def used_items(c):
        return [(r.item_code, r.used_qty, r.serial_no, r.batch_no) for r in (c.case_items or []) if (r.used_qty or 0) > 0]

    def returned_items(c):
        return [(r.item_code, r.returned_qty, r.serial_no, r.batch_no) for r in (c.case_items or []) if (r.returned_qty or 0) > 0]

    def make_task(kind, subject, assignee, desc="", link_field=None, dispatch_case_name=None, customer=None):
        dc_name = dispatch_case_name or doc.dispatch_case
        cust = customer or (case.customer if case else None)
        existing = frappe.db.exists("Task", {"dispatch_case": dc_name, "task_kind": kind, "status": ["not in", ["Completed", "Cancelled"]]})
        if existing:
            return existing
        t = frappe.get_doc({
            "doctype": "Task", "subject": subject, "task_kind": kind, "task_access_policy": kind,
            "dispatch_case": dc_name, "customer": cust, "description": desc,
        })
        t.flags.ignore_permissions = True
        t.insert()
        if link_field:
            frappe.db.set_value("Dispatch Case", dc_name, link_field, t.name)
        # FIXED: Update _assign via db (assign_to module not available in RestrictedPython)
        frappe.db.set_value("Task", t.name, "_assign", json.dumps([assignee]))
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = assignee
        todo.reference_type = "Task"
        todo.reference_name = t.name
        todo.description = subject
        todo.assigned_by = frappe.session.user
        todo.flags.ignore_permissions = True
        todo.insert()
        return t.name

    def create_invoice(c):
        items_rows = []
        for r in (c.case_items or []):
            qty = r.used_qty if (r.used_qty or 0) > 0 else r.dispatched_qty
            if not qty:
                continue
            rate = (r.unit_price or 0) * (1 - (r.discount_pct or 0) / 100)
            items_rows.append({"item_code": r.item_code, "qty": qty, "rate": rate})
        if not items_rows:
            return
        currency = "AMD"
        if c.get("currency"):
            currency = c.currency
        si = frappe.get_doc({"doctype": "Sales Invoice", "customer": c.customer, "company": "InMED", "currency": currency, "update_stock": 0, "items": items_rows})
        si.flags.ignore_permissions = True
        si.insert()
        frappe.db.set_value("Dispatch Case", c.name, "sales_invoice", si.name)

    def create_or_update_debt_task(c, outstanding, inv_name):
        FINANCE_TEAM = "finance.team@example.com"
        existing = frappe.db.get_value("Task", {"customer": c.customer, "task_kind": "Debt Collection", "status": ["not in", ["Completed", "Cancelled"]]}, "name")
        inv_row = {"dispatch_case": c.name, "sales_invoice": inv_name, "invoice_amount": outstanding, "paid_amount": 0, "outstanding_amount": outstanding}
        if existing:
            t = frappe.get_doc("Task", existing)
            t.append("open_invoices", inv_row)
            t.total_outstanding = sum((r.outstanding_amount or 0) for r in t.open_invoices)
            t.flags.ignore_permissions = True
            t.save()
        else:
            t = frappe.get_doc({
                "doctype": "Task", "subject": f"Debt Collection: {c.customer}",
                "task_kind": "Debt Collection", "task_access_policy": "Debt Collection",
                "customer": c.customer, "total_outstanding": outstanding,
                "open_invoices": [inv_row],
            })
            t.flags.ignore_permissions = True
            t.insert()
            # FIXED: Update _assign via db (assign_to module not available in RestrictedPython)
            frappe.db.set_value("Task", t.name, "_assign", json.dumps([FINANCE_TEAM]))
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = FINANCE_TEAM
            todo.reference_type = "Task"
            todo.reference_name = t.name
            todo.description = t.subject
            todo.assigned_by = frappe.session.user
            todo.flags.ignore_permissions = True
            todo.insert()

    case = frappe.get_doc("Dispatch Case", doc.dispatch_case)

    # Delivery: Picked Up
    if ds_changed and doc.delivery_status == "Picked Up":
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "In Transit")

    # Delivery: Delivered
    if ds_changed and doc.delivery_status == "Delivered":
        if doc.warehouse_pickup_photo:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "delivery_photo", doc.warehouse_pickup_photo)
        se = create_se(DELIVERY_TRANSIT_WH, case.client_location_warehouse, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Delivered", "delivery_stock_entry": se.name if se else ""})
        case.reload()
        if not case.return_expected:
            c_se = create_se(case.client_location_warehouse, "", all_items(case), "Material Issue")
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"consumption_stock_entry": c_se.name if c_se else "", "status": "Invoice Pending"})
            create_invoice(case)
            make_task("Invoice preparation / create invoice", f"Invoice: {case.name} — {case.customer}", ACCOUNTING_TEAM, f"Review and submit draft Sales Invoice for {case.name}.", "invoice_task", doc.dispatch_case, case.customer)
        else:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Awaiting Return Pickup")
            make_task("Pickup Returns", f"Wait for return call: {case.name} — {case.customer}", RETURNS_TEAM, f"Wait for {case.customer} to call re return.", "return_waiting_task", doc.dispatch_case, case.customer)

    # Return Pickup: Picked Up
    if ps_changed and doc.pickup_status == "Picked Up":
        case.reload()
        se = create_se(case.client_location_warehouse, RETURN_PICKUP_TRANSIT_WH, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Return In Transit", "return_pickup_stock_entry": se.name if se else ""})

    # Return Pickup: Returned to Warehouse
    if ps_changed and doc.pickup_status == "Returned to Warehouse":
        if doc.warehouse_dropoff_photo:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "return_dropoff_photo", doc.warehouse_dropoff_photo)
        se = create_se(RETURN_PICKUP_TRANSIT_WH, RETURNS_WH, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Returns Received", "return_receive_stock_entry": se.name if se else ""})
        make_task("Returns processing / verification", f"Inspect returns: {case.name} — {case.customer}", RETURNS_TEAM, "Open Dispatch Case and fill returned_qty for each item.", "returns_inspection_task", doc.dispatch_case, case.customer)

    # Pack task Completed
    if is_completing and doc.task_kind == "Pack / prepare items":
        case.reload()
        se = create_se(MAIN_WH, DELIVERY_TRANSIT_WH, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Packed", "dispatch_stock_entry": se.name if se else ""})
        items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
        make_task("Delivery", f"Deliver: {case.name} — {case.customer}", DELIVERY_TEAM, f"Deliver to {case.customer}\nDest: {case.client_location_warehouse}\n\n{items_txt}", "delivery_task", doc.dispatch_case, case.customer)

    # Return Waiting task Completed
    if is_completing and doc.task_kind == "Pickup Returns":
        case.reload()
        if case.status == "Awaiting Return Pickup":
            driver = doc.return_pickup_driver or DELIVERY_TEAM
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Return Pickup Scheduled")
            items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
            tid = make_task("Pickup Returns", f"Pickup Returns: {case.name} — {case.customer}", driver, f"Collect from {case.customer}\nAt: {case.client_location_warehouse}\n\n{items_txt}", "return_pickup_task", doc.dispatch_case, case.customer)
            if doc.scheduled_return_date and tid:
                frappe.db.set_value("Task", tid, "exp_end_date", doc.scheduled_return_date)

    # Returns Inspection Completed
    if is_completing and doc.task_kind == "Returns processing / verification":
        case.reload()
        u = used_items(case)
        if u:
            c_se = create_se(case.client_location_warehouse, "", u, "Material Issue")
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "consumption_stock_entry", c_se.name if c_se else "")
        create_invoice(case)
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Invoice Pending")
        make_task("Invoice preparation / create invoice", f"Invoice: {case.name} — {case.customer}", ACCOUNTING_TEAM, f"Review draft invoice for {case.name}.", "invoice_task", doc.dispatch_case, case.customer)
        r = returned_items(case)
        if r:
            ret_txt = "\n".join(f"- {ic} x{q}" for ic, q, sn, bn in r)
            make_task("Returns restocking", f"Restock returns: {case.name}", RETURNS_TEAM, f"Move from Returns WH to Main WH:\n{ret_txt}", "restock_task", doc.dispatch_case, case.customer)

    # Restock task Completed
    if is_completing and doc.task_kind == "Returns restocking":
        case.reload()
        r = returned_items(case)
        if r:
            se = create_se(RETURNS_WH, MAIN_WH, r)
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "restock_stock_entry", se.name if se else "")

    # Invoice Preparation Completed
    if is_completing and doc.task_kind == "Invoice preparation / create invoice":
        case.reload()
        inv_name = case.sales_invoice
        if inv_name:
            inv_total = frappe.db.get_value("Sales Invoice", inv_name, "grand_total") or 0
            outstanding = inv_total - (case.prepaid_amount or 0)
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"total_invoice_amount": inv_total, "outstanding_amount": outstanding})
            if outstanding <= 0:
                frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Closed")
            else:
                frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Payment Pending")
                create_or_update_debt_task(case, outstanding, inv_name)

    # Discount Approval Completed
    if is_completing and doc.task_kind == "Discount Approval":
        if doc.approval_outcome == "Approved":
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Confirmed", "discount_approval_status": "Approved"})
            case.reload()
            items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
            make_task("Pack / prepare items", f"Pack: {case.name} — {case.customer}", INVENTORY_TEAM, f"Pack for {case.customer}\n\n{items_txt}", "pack_task", doc.dispatch_case, case.customer)
        else:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Draft", "discount_approval_status": "Rejected"})
            make_task("Order entry", f"Discount rejected — revise: {case.name} — {case.customer}", ORDER_CREATION_TEAM, "Discount rejected by Directors. Open Dispatch Case, fix prices, save again.", None, doc.dispatch_case, case.customer)
'@

# 9.7  Task Before Save — payment recording on Debt Collection task
$TaskPaymentRecording = @'
if doc.task_kind != "Debt Collection":
    pass
elif not (doc.new_payment_amount or 0) > 0:
    pass
else:
    before = doc.get_doc_before_save()
    before_amt = (before.new_payment_amount if before else None) or 0
    if doc.new_payment_amount == before_amt:
        pass
    else:
        amount = doc.new_payment_amount
        method = doc.payment_method_dc or "Cash"
        ref = doc.payment_reference_dc or ""
        remaining = amount
        for row in sorted(doc.open_invoices, key=lambda r: r.sales_invoice):
            to_apply = min(remaining, row.outstanding_amount or 0)
            row.allocated_now = to_apply
            remaining -= to_apply
            if remaining <= 0:
                break
        for row in doc.open_invoices:
            apply = row.allocated_now or 0
            if apply > 0:
                row.paid_amount = (row.paid_amount or 0) + apply
                row.outstanding_amount = (row.outstanding_amount or 0) - apply
                row.allocated_now = 0
        doc.total_outstanding = sum((r.outstanding_amount or 0) for r in doc.open_invoices)
        doc.append("payment_history", {
            "payment_date": frappe.utils.now_datetime(),
            "amount": amount,
            "method": method,
            "reference": ref,
        })
        pe = frappe.get_doc({
            "doctype": "Payment Entry",
            "payment_type": "Receive",
            "party_type": "Customer",
            "party": doc.customer,
            "paid_amount": amount,
            "received_amount": amount,
            "mode_of_payment": method,
            "reference_no": ref,
            "reference_date": frappe.utils.nowdate(),
            "company": "InMED",
            "paid_to": "Cash - Inmed",
        })
        for row in doc.open_invoices:
            if (row.allocated_now or 0) > 0:
                pe.append("references", {
                    "reference_doctype": "Sales Invoice",
                    "reference_name": row.sales_invoice,
                    "allocated_amount": row.allocated_now,
                })
        pe.flags.ignore_permissions = True
        pe.insert()
        pe.submit()
        if doc.payment_history:
            frappe.db.set_value("Debt Collection Payment", doc.payment_history[-1].name, "payment_entry", pe.name)
        t = frappe.get_doc({
            "doctype": "Task",
            "subject": f"Distribute Payment: {doc.customer} — {amount} AMD",
            "task_kind": "Distribute Payment",
            "task_access_policy": "Distribute Payment",
            "customer": doc.customer,
            "description": f"Amount: {amount} AMD\nMethod: {method}\nRef: {ref}",
            "_assign": json.dumps(["finance.team@example.com"]),
        })
        t.flags.ignore_permissions = True
        t.insert()
        doc.new_payment_amount = 0
        doc.payment_method_dc = ""
        doc.payment_reference_dc = ""
        if doc.total_outstanding <= 0:
            doc.status = "Completed"
'@

# 9.8  Task After Save — advance payment from Payment Received task
$TaskAdvancePayment = @'
before = doc.get_doc_before_save()
before_status = before.status if before else None
is_completing = (doc.status == "Completed" and before_status != "Completed")
if not (is_completing and doc.task_kind == "Payment Received"):
    pass
elif not (doc.new_payment_amount or 0) > 0:
    pass
else:
    pe = frappe.get_doc({
        "doctype": "Payment Entry",
        "payment_type": "Receive",
        "party_type": "Customer",
        "party": doc.customer,
        "paid_amount": doc.new_payment_amount,
        "received_amount": doc.new_payment_amount,
        "mode_of_payment": doc.payment_method_dc or "Cash",
        "reference_no": doc.payment_reference_dc or "",
        "reference_date": today(),
        "company": "InMED",
        "paid_to": "Cash - Inmed",
    })
    pe.flags.ignore_permissions = True
    pe.insert()
    if doc.dispatch_case:
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"prepaid_amount": doc.new_payment_amount, "prepaid_payment_entry": pe.name})
    existing_dc = frappe.db.get_value("Task", {"customer": doc.customer, "task_kind": "Debt Collection", "status": ["not in", ["Completed", "Cancelled"]]}, "name")
    if existing_dc:
        current_credit = frappe.db.get_value("Task", existing_dc, "available_advance_credit") or 0
        frappe.db.set_value("Task", existing_dc, "available_advance_credit", current_credit + doc.new_payment_amount)
'@

$ServerScripts = @(
    [pscustomobject]@{ name="Task-before-save-policy";       type="DocType Event"; ref_dt="Task";          event="Before Save"; disabled=0; script=$TaskGovernanceScript;      action="upsert" },
    [pscustomobject]@{ name="Dispatch-Case-before-save";     type="DocType Event"; ref_dt="Dispatch Case"; event="Before Save"; disabled=0; script=$DispatchCaseBeforeSave;    action="upsert" },
    [pscustomobject]@{ name="Dispatch-Case-after-save";      type="DocType Event"; ref_dt="Dispatch Case"; event="After Save";  disabled=0; script=$DispatchCaseAfterSave;     action="upsert" },
    [pscustomobject]@{ name="Dispatch-Case-before-submit";   type="DocType Event"; ref_dt="Dispatch Case"; event="Before Submit"; disabled=0; script=$DispatchCaseBeforeSubmit; action="upsert" },
    [pscustomobject]@{ name="Task-before-save-dispatch-gates"; type="DocType Event"; ref_dt="Task";        event="Before Save"; disabled=0; script=$TaskDispatchGates;         action="upsert" },
    [pscustomobject]@{ name="Task-after-save-dispatch-flow"; type="DocType Event"; ref_dt="Task";          event="After Save";  disabled=0; script=$TaskDispatchFlow;          action="upsert" },
    [pscustomobject]@{ name="Task-before-save-payment-recording"; type="DocType Event"; ref_dt="Task";     event="Before Save"; disabled=0; script=$TaskPaymentRecording;      action="upsert" },
    [pscustomobject]@{ name="Task-after-save-advance-payment"; type="DocType Event"; ref_dt="Task";        event="After Save";  disabled=0; script=$TaskAdvancePayment;        action="upsert" }
)

# ---------------------------------------------------------------------------
# 10) CLIENT SCRIPT — Dispatch Case "Load from Template" button
# ---------------------------------------------------------------------------
$DispatchCaseClientScript = @'
frappe.ui.form.on("Dispatch Case", {
    surgery_set_type: function(frm) {
        if (!frm.doc.surgery_set_type) return;
        frappe.call({
            method: "frappe.client.get",
            args: { doctype: "Collection Set", name: frm.doc.surgery_set_type },
            callback: function(r) {
                if (!r.message) return;
                frm.clear_table("case_items");
                (r.message.items || []).forEach(function(row) {
                    var nr = frm.add_child("case_items");
                    nr.item_code = row.item;
                    nr.dispatched_qty = row.qty || 1;
                    nr.unit_price = row.rate || 0;
                });
                frm.refresh_field("case_items");
            }
        });
    }
});
'@

# ===========================================================================
# CHECK MODE
# ===========================================================================
if ($Mode -eq "Check") {
    $R = [ordered]@{ mode="Check"; roles=@(); users=@(); custom_fields=@(); task_access_policies=@(); doctypes=@(); server_scripts=@() }

    foreach ($role in $NewRoles) {
        $E = Get-ErpDoc -DocType "Role" -Name $role
        $R.roles += [pscustomobject]@{ name=$role; exists=($null -ne $E) }
    }
    foreach ($u in $NewUsers) {
        $E = Get-ErpDoc -DocType "User" -Name $u.email
        $R.users += [pscustomobject]@{ email=$u.email; exists=($null -ne $E) }
    }
    foreach ($f in $TaskCustomFields) {
        $E = Get-ErpDoc -DocType "Custom Field" -Name $f.name
        $R.custom_fields += [pscustomobject]@{ name=$f.name; exists=($null -ne $E) }
    }
    foreach ($p in $NewTaskAccessPolicies) {
        $E = Get-ErpDoc -DocType "Task Access Policy" -Name $p
        $R.task_access_policies += [pscustomobject]@{ name=$p; exists=($null -ne $E) }
    }
    foreach ($dt in @("Dispatch Case Item","Debt Collection Invoice","Debt Collection Payment","Dispatch Case")) {
        $E = Get-ErpDoc -DocType "DocType" -Name $dt
        $R.doctypes += [pscustomobject]@{ name=$dt; exists=($null -ne $E) }
    }
    foreach ($s in $ServerScripts) {
        $E = Get-ErpDoc -DocType "Server Script" -Name $s.name
        $R.server_scripts += [pscustomobject]@{ name=$s.name; exists=($null -ne $E) }
    }
    $R | ConvertTo-Json -Depth 5
    return
}

# ===========================================================================
# DEPLOY MODE
# ===========================================================================
$Results = [ordered]@{ mode="Deploy"; roles=@(); users=@(); custom_fields=@(); task_access_policies=@(); doctypes=@(); server_scripts=@(); client_scripts=@() }

# -- 1) Roles --
foreach ($role in $NewRoles) {
    $Results.roles += Upsert-ErpDoc -DocType "Role" -Name $role -Body ([ordered]@{ role_name=$role; desk_access=1 })
}

# -- 2) Team Users --
foreach ($u in $NewUsers) {
    $UserBody = [ordered]@{
        first_name         = $u.first_name
        last_name          = $u.last_name
        email              = $u.email
        enabled            = 1
        send_welcome_email = 0
        new_password       = "ChangeMe123!"
        roles              = @([ordered]@{ role=$u.role })
    }
    $Results.users += Upsert-ErpDoc -DocType "User" -Name $u.email -Body $UserBody
}

# -- 3) Task Access Policies --
foreach ($p in $NewTaskAccessPolicies) {
    $Results.task_access_policies += Upsert-ErpDoc -DocType "Task Access Policy" -Name $p -Body ([ordered]@{ policy_name=$p })
}

# -- 4) Child DocType: Dispatch Case Item --
$E = Get-ErpDoc -DocType "DocType" -Name "Dispatch Case Item"
if ($null -eq $E) {
    try {
        $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/DocType" -Body $DispatchCaseItemBody).data
        $Results.doctypes += [pscustomobject]@{ action="created"; name=$C.name }
    } catch { $Results.doctypes += [pscustomobject]@{ action="error"; name="Dispatch Case Item"; error=$_.Exception.Message } }
} else { $Results.doctypes += [pscustomobject]@{ action="exists"; name="Dispatch Case Item" } }

# -- 5) Child DocType: Debt Collection Invoice --
$E = Get-ErpDoc -DocType "DocType" -Name "Debt Collection Invoice"
if ($null -eq $E) {
    try {
        $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/DocType" -Body $DebtCollectionInvoiceBody).data
        $Results.doctypes += [pscustomobject]@{ action="created"; name=$C.name }
    } catch { $Results.doctypes += [pscustomobject]@{ action="error"; name="Debt Collection Invoice"; error=$_.Exception.Message } }
} else { $Results.doctypes += [pscustomobject]@{ action="exists"; name="Debt Collection Invoice" } }

# -- 6) Child DocType: Debt Collection Payment --
$E = Get-ErpDoc -DocType "DocType" -Name "Debt Collection Payment"
if ($null -eq $E) {
    try {
        $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/DocType" -Body $DebtCollectionPaymentBody).data
        $Results.doctypes += [pscustomobject]@{ action="created"; name=$C.name }
    } catch { $Results.doctypes += [pscustomobject]@{ action="error"; name="Debt Collection Payment"; error=$_.Exception.Message } }
} else { $Results.doctypes += [pscustomobject]@{ action="exists"; name="Debt Collection Payment" } }

# -- 7) Parent DocType: Dispatch Case (MUST come after child tables) --
$E = Get-ErpDoc -DocType "DocType" -Name "Dispatch Case"
if ($null -eq $E) {
    try {
        $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/DocType" -Body $DispatchCaseBody).data
        $Results.doctypes += [pscustomobject]@{ action="created"; name=$C.name }
    } catch { $Results.doctypes += [pscustomobject]@{ action="error"; name="Dispatch Case"; error=$_.Exception.Message } }
} else { $Results.doctypes += [pscustomobject]@{ action="exists"; name="Dispatch Case" } }

# -- 8) Custom Fields (AFTER DocTypes so Link/Table options resolve correctly) --
function Deploy-CustomField ($f) {
    $Body = [ordered]@{ dt=$f.dt; fieldname=$f.fieldname; label=$f.label; fieldtype=$f.fieldtype }
    if ($f.PSObject.Properties["options"])             { $Body.options              = $f.options }
    if ($f.PSObject.Properties["insert_after"])        { $Body.insert_after         = $f.insert_after }
    if ($f.PSObject.Properties["in_list_view"])        { $Body.in_list_view         = $f.in_list_view }
    if ($f.PSObject.Properties["in_standard_filter"])  { $Body.in_standard_filter   = $f.in_standard_filter }
    if ($f.PSObject.Properties["read_only"])           { $Body.read_only            = $f.read_only }
    if ($f.PSObject.Properties["default"])             { $Body.default              = $f.default }
    if ($f.update_only) {
        $Existing = Get-ErpDoc -DocType "Custom Field" -Name $f.name
        if ($null -ne $Existing) {
            $U = (Invoke-ErpRequest -Method Put -Path "/api/resource/Custom Field/$(Enc $f.name)" -Body $Body).data
            return [pscustomobject]@{ action="updated"; name=$U.name }
        } else {
            $Body.name = $f.name
            $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/Custom Field" -Body $Body).data
            return [pscustomobject]@{ action="created"; name=$C.name }
        }
    } else {
        return Upsert-ErpDoc -DocType "Custom Field" -Name $f.name -Body $Body
    }
}
foreach ($f in $TaskCustomFields) {
    $Results.custom_fields += Deploy-CustomField $f
}

# -- 9) Server Scripts --
foreach ($s in $ServerScripts) {
    $Body = [ordered]@{
        script_type       = $s.type
        reference_doctype = $s.ref_dt
        doctype_event     = $s.event
        event_frequency   = "All"
        allow_guest       = 0
        disabled          = $s.disabled
        enable_rate_limit = 0
        script            = $s.script
    }
    $Results.server_scripts += Upsert-ErpDoc -DocType "Server Script" -Name $s.name -Body $Body
}

# -- 10) Client Script: Dispatch Case form --
$CsBody = [ordered]@{
    dt          = "Dispatch Case"
    view        = "Form"
    enabled     = 1
    script      = $DispatchCaseClientScript
}
$Results.client_scripts += Upsert-ErpDoc -DocType "Client Script" -Name "Dispatch Case-Form" -Body $CsBody

# ===========================================================================
# OUTPUT
# ===========================================================================
$Results | ConvertTo-Json -Depth 10

Write-Host "`n=== Post-deploy verification ==="
$Snap = [ordered]@{ roles=@(); users=@(); custom_fields=@(); doctypes=@(); server_scripts=@() }
foreach ($role in $NewRoles)          { $E=$null; $E=Get-ErpDoc "Role" $role;           $Snap.roles          += [pscustomobject]@{ name=$role;  exists=($null -ne $E) } }
foreach ($u in $NewUsers)             { $E=$null; $E=Get-ErpDoc "User" $u.email;         $Snap.users          += [pscustomobject]@{ name=$u.email; exists=($null -ne $E) } }
foreach ($f in $TaskCustomFields)     { $E=$null; $E=Get-ErpDoc "Custom Field" $f.name;  $Snap.custom_fields  += [pscustomobject]@{ name=$f.name; exists=($null -ne $E) } }
foreach ($dt in @("Dispatch Case Item","Debt Collection Invoice","Debt Collection Payment","Dispatch Case")) { $E=$null; $E=Get-ErpDoc "DocType" $dt; $Snap.doctypes += [pscustomobject]@{ name=$dt; exists=($null -ne $E) } }
foreach ($s in $ServerScripts)        { $E=$null; $E=Get-ErpDoc "Server Script" $s.name; $Snap.server_scripts += [pscustomobject]@{ name=$s.name; exists=($null -ne $E) } }
$Snap | ConvertTo-Json -Depth 5
