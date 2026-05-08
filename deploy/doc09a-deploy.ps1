param(
    [ValidateSet("Check", "Deploy", "Verify")]
    [string]$Mode = "Check"
)

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{
    Authorization = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
}

function Enc([string]$Value) {
    return [uri]::EscapeDataString($Value)
}

function Invoke-ErpRequest {
    param(
        [string]$Method,
        [string]$Path,
        $Body = $null
    )

    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method
    }

    $Json = $Body | ConvertTo-Json -Depth 30
    $JsonBytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body $JsonBytes
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)

    try {
        return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data
    }
    catch {
        return $null
    }
}

function Get-ErpList {
    param(
        [string]$DocType,
        [array]$Fields = @("name"),
        [array]$Filters = @(),
        [int]$Limit = 20
    )

    $FieldsJson = $Fields | ConvertTo-Json -Compress
    $Path = "/api/resource/$(Enc $DocType)?limit_page_length=$Limit&fields=$(Enc $FieldsJson)"
    if ($Filters.Count -gt 0) {
        $FiltersJson = $Filters | ConvertTo-Json -Compress -Depth 10
        $Path += "&filters=$(Enc $FiltersJson)"
    }
    return (Invoke-ErpRequest -Method Get -Path $Path).data
}

function Upsert-ErpDoc {
    param([string]$DocType, [string]$Name, $Body)

    $Existing = Get-ErpDoc -DocType $DocType -Name $Name
    if ($null -eq $Existing) {
        $Body.name = $Name
        $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ doctype = $DocType; name = $Name; action = "created"; result = $Created.name }
    }

    $Updated = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{ doctype = $DocType; name = $Name; action = "updated"; result = $Updated.name }
}

# =============================================================================
# CUSTOM FIELDS
# =============================================================================

$CustomFields = @(

    # ---------- Sales Order: prepaid ----------
    [pscustomobject]@{
        name = "Sales Order-is_prepaid"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Sales Order"
            label        = "Is Prepaid"
            fieldname    = "is_prepaid"
            fieldtype    = "Check"
            insert_after = "doctor_name"
            default      = "0"
            reqd         = 0
            read_only    = 0
        }
    },
    [pscustomobject]@{
        name = "Sales Order-prepayment_required_amount_amd"
        body = [ordered]@{
            doctype           = "Custom Field"
            dt                = "Sales Order"
            label             = "Prepayment Required Amount (AMD)"
            fieldname         = "prepayment_required_amount_amd"
            fieldtype         = "Currency"
            insert_after      = "is_prepaid"
            depends_on        = "eval:doc.is_prepaid==1"
            mandatory_depends_on = "eval:doc.is_prepaid==1"
            reqd              = 0
            read_only         = 0
        }
    },
    [pscustomobject]@{
        name = "Sales Order-prepayment_payment_entry"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Sales Order"
            label        = "Prepayment Payment Entry"
            fieldname    = "prepayment_payment_entry"
            fieldtype    = "Link"
            options      = "Payment Entry"
            insert_after = "prepayment_required_amount_amd"
            depends_on   = "eval:doc.is_prepaid==1"
            reqd         = 0
            read_only    = 0
        }
    },

    # ---------- Sales Order: discount approval ----------
    [pscustomobject]@{
        name = "Sales Order-discount_approval_status"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Sales Order"
            label        = "Discount Approval Status"
            fieldname    = "discount_approval_status"
            fieldtype    = "Select"
            options      = "Not Required`nPending`nApproved`nRejected"
            insert_after = "prepayment_payment_entry"
            default      = "Not Required"
            reqd         = 0
            read_only    = 1
            in_list_view = 0
        }
    },
    [pscustomobject]@{
        name = "Sales Order-discount_approval_task"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Sales Order"
            label        = "Discount Approval Task"
            fieldname    = "discount_approval_task"
            fieldtype    = "Link"
            options      = "Task"
            insert_after = "discount_approval_status"
            reqd         = 0
            read_only    = 1
        }
    },
    [pscustomobject]@{
        name = "Sales Order-discount_approval_note"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Sales Order"
            label        = "Discount Approval Note"
            fieldname    = "discount_approval_note"
            fieldtype    = "Small Text"
            insert_after = "discount_approval_task"
            reqd         = 0
            read_only    = 1
        }
    },
    [pscustomobject]@{
        name = "Sales Order-manual_pricing_reason"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Sales Order"
            label        = "Manual Pricing Reason"
            fieldname    = "manual_pricing_reason"
            fieldtype    = "Small Text"
            insert_after = "discount_approval_note"
            reqd         = 0
            read_only    = 0
        }
    },

    # ---------- Task: sales link + customer ----------
    [pscustomobject]@{
        name = "Task-sales_order"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Task"
            label        = "Sales Order"
            fieldname    = "sales_order"
            fieldtype    = "Link"
            options      = "Sales Order"
            insert_after = "purchase_order"
            reqd         = 0
            read_only    = 0
            in_list_view = 0
        }
    },
    [pscustomobject]@{
        name = "Task-customer"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Task"
            label        = "Customer"
            fieldname    = "customer"
            fieldtype    = "Link"
            options      = "Customer"
            insert_after = "sales_order"
            reqd         = 0
            read_only    = 0
            in_list_view = 0
        }
    },

    # ---------- Task: photo attachments ----------
    [pscustomobject]@{
        name = "Task-warehouse_pickup_photo"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Task"
            label        = "Warehouse Pickup Photo"
            fieldname    = "warehouse_pickup_photo"
            fieldtype    = "Attach"
            insert_after = "approval_note"
            reqd         = 0
            read_only    = 0
        }
    },
    [pscustomobject]@{
        name = "Task-warehouse_dropoff_photo"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Task"
            label        = "Warehouse Drop-off Photo"
            fieldname    = "warehouse_dropoff_photo"
            fieldtype    = "Attach"
            insert_after = "warehouse_pickup_photo"
            reqd         = 0
            read_only    = 0
        }
    },

    # ---------- Task: payment entry link ----------
    [pscustomobject]@{
        name = "Task-payment_entry"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Task"
            label        = "Payment Entry"
            fieldname    = "payment_entry"
            fieldtype    = "Link"
            options      = "Payment Entry"
            insert_after = "warehouse_dropoff_photo"
            reqd         = 0
            read_only    = 0
        }
    },

    # ---------- Task: debt fields ----------
    [pscustomobject]@{
        name = "Task-current_debt_amd"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Task"
            label        = "Current Debt (AMD)"
            fieldname    = "current_debt_amd"
            fieldtype    = "Currency"
            insert_after = "payment_entry"
            reqd         = 0
            read_only    = 0
        }
    },
    [pscustomobject]@{
        name = "Task-debt_threshold_amd"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Task"
            label        = "Debt Threshold (AMD)"
            fieldname    = "debt_threshold_amd"
            fieldtype    = "Currency"
            insert_after = "current_debt_amd"
            reqd         = 0
            read_only    = 0
        }
    },

    # ---------- Stock Entry: sales order link ----------
    [pscustomobject]@{
        name = "Stock Entry-sales_order"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Stock Entry"
            label        = "Sales Order"
            fieldname    = "sales_order"
            fieldtype    = "Link"
            options      = "Sales Order"
            insert_after = "purpose"
            reqd         = 0
            read_only    = 0
            in_list_view = 0
        }
    }
)

# =============================================================================
# SERVER SCRIPTS
# =============================================================================
# NOTE: import statements are omitted — frappe, json, now_datetime are globals
# in Frappe safe_exec context. Using them directly matches existing scripts.
#
# NOTE (§8.3): writeback uses frappe.db.set_value() instead of so.save() because
# the Sales Order is already submitted when the director completes the task.
# so.save(ignore_permissions=True) raises "Cannot edit submitted document" in
# Frappe regardless of ignore_permissions. frappe.db.set_value() bypasses this.
# =============================================================================

# --- 8.2: Sales Order — create / maintain Discount Approval task ---
$SODiscountApprovalScript = @'
DIRECTOR_ROLE = "Ops - Directors"

def assign_single_owner(task_name, user):
    frappe.db.set_value("Task", task_name, "_assign", json.dumps([user]), update_modified=False)

    other_todos = frappe.get_all(
        "ToDo",
        filters={
            "reference_type": "Task",
            "reference_name": task_name,
            "allocated_to": ["!=", user],
            "status": "Open",
        },
        pluck="name",
    )

    for td in (other_todos or []):
        frappe.db.set_value("ToDo", td, "status", "Cancelled")

    if not frappe.db.exists(
        "ToDo",
        {
            "reference_type": "Task",
            "reference_name": task_name,
            "allocated_to": user,
            "status": "Open",
        },
    ):
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = user
        todo.reference_type = "Task"
        todo.reference_name = task_name
        todo.description = frappe.db.get_value("Task", task_name, "subject") or task_name
        todo.assigned_by = frappe.session.user
        todo.insert(ignore_permissions=True)

def user_has_role(role):
    return bool(frappe.db.exists("Has Role", {"parent": frappe.session.user, "role": role}))

def is_manual_rate_override(row):
    price_list_rate = float(row.get("price_list_rate") or 0)
    discount_pct = float(row.get("discount_percentage") or 0)
    rate = float(row.get("rate") or 0)
    expected = price_list_rate * (1 - (discount_pct / 100.0))
    return abs(rate - expected) > 0.01

def has_discount(doc):
    if float(doc.get("additional_discount_percentage") or 0) != 0:
        frappe.throw("Do not use header-level additional discount. Use per-line Discount Percentage so approvals and reporting stay consistent.")
    for row in (doc.items or []):
        if float(row.get("discount_percentage") or 0) > 0:
            return True
        if is_manual_rate_override(row):
            return True
    return False

def has_manual_pricing(doc):
    for row in (doc.items or []):
        if is_manual_rate_override(row):
            return True
    return False

def discount_signature(doc):
    sig = {
        "additional_discount_percentage": float(doc.get("additional_discount_percentage") or 0),
        "items": [],
    }
    for row in (doc.items or []):
        sig["items"].append({
            "item_code": row.get("item_code"),
            "discount_percentage": float(row.get("discount_percentage") or 0),
            "rate": float(row.get("rate") or 0),
            "price_list_rate": float(row.get("price_list_rate") or 0),
        })
    return sig

before = doc.get_doc_before_save()
discount_present = has_discount(doc)

if not discount_present:
    doc.discount_approval_status = "Not Required"
    doc.discount_approval_task = None
    doc.discount_approval_note = None

    open_tasks = frappe.get_all(
        "Task",
        filters={
            "task_kind": "Discount Approval",
            "sales_order": doc.name,
            "status": ["!=", "Completed"],
        },
        pluck="name",
    )

    for tname in (open_tasks or []):
        desc = frappe.db.get_value("Task", tname, "description") or ""
        note = "Cancelled automatically: discount removed from Sales Order."
        if note not in desc:
            desc = (desc + "\n" if desc else "") + note
            frappe.db.set_value("Task", tname, "description", desc)
        frappe.db.set_value("Task", tname, "status", "Cancelled")

        todos = frappe.get_all(
            "ToDo",
            filters={"reference_type": "Task", "reference_name": tname, "status": "Open"},
            pluck="name",
        )
        for td in (todos or []):
            frappe.db.set_value("ToDo", td, "status", "Cancelled")

else:
    sig_preserved = False
    if before and before.get("discount_approval_status") in ("Approved", "Rejected"):
        before_sig = discount_signature(before)
        after_sig = discount_signature(doc)
        if before_sig == after_sig:
            doc.discount_approval_status = before.discount_approval_status
            doc.discount_approval_task = before.discount_approval_task
            doc.discount_approval_note = before.discount_approval_note
            sig_preserved = True

    if not sig_preserved:
        doc.discount_approval_status = "Pending"
        doc.discount_approval_task = None
        doc.discount_approval_note = None

        if has_manual_pricing(doc):
            if not (user_has_role("Ops - Accounting") or user_has_role("Ops - Directors")):
                frappe.throw("Manual rate changes are allowed only for Accounting/Directors (Doc 09 policy).")
            if not (doc.manual_pricing_reason or "").strip():
                frappe.throw("Manual Pricing Reason is required when any line rate is manually overridden.")

        existing = frappe.get_all(
            "Task",
            filters={
                "task_kind": "Discount Approval",
                "sales_order": doc.name,
                "status": ["!=", "Completed"],
            },
            pluck="name",
        )

        if existing:
            doc.discount_approval_task = existing[0]
        else:
            subject = f"Discount Approval — SO {doc.name}"

            task = frappe.new_doc("Task")
            task.subject = subject
            task.status = "Open"
            task.task_kind = "Discount Approval"
            task.task_access_policy = "Discount Approval"
            task.sales_order = doc.name
            task.customer = doc.customer

            task.insert(ignore_permissions=True)

            director_users = frappe.get_all(
                "Has Role",
                filters={"role": DIRECTOR_ROLE},
                pluck="parent",
            )
            director_users = sorted(list(set(director_users or [])))

            director_users = [
                u
                for u in director_users
                if u not in ("Administrator", "Guest") and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
            ]

            if not director_users:
                frappe.throw(f"No director users found. Create at least one User with role '{DIRECTOR_ROLE}'.")

            assign_single_owner(task.name, director_users[0])
            doc.discount_approval_task = task.name
'@

# --- 8.3: Task — write Discount Approval result back to Sales Order ---
# Uses frappe.db.set_value() because the Sales Order is already submitted
# when the director completes the task. so.save() would throw on a submitted doc.
# No top-level return — uses nested if, matching existing script pattern.
$TaskDiscountWritebackScript = @'
before = doc.get_doc_before_save()
before_status = before.status if before else None

is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

if is_becoming_completed and doc.task_kind == "Discount Approval":
    if not doc.sales_order:
        frappe.throw("Discount Approval task must be linked to a Sales Order.")

    if doc.approval_outcome not in ("Approved", "Rejected"):
        frappe.throw("Approval Outcome must be set to Approved or Rejected before completing the task.")

    frappe.db.set_value(
        "Sales Order",
        doc.sales_order,
        {
            "discount_approval_status": doc.approval_outcome,
            "discount_approval_note": doc.approval_note or "",
            "discount_approval_task": doc.name,
        },
    )
'@

# --- 8.4: Stock Entry — block dispatch staging without approval / photo / prepaid ---
$StockEntryDispatchGateScript = @'
if doc.stock_entry_type == "Material Transfer":
    MAIN_WH = "Main - Inmed"
    DELIVERY_IN_TRANSIT_WH = "Delivery In-Transit - Inmed"

    to_wh = doc.get("to_warehouse")
    from_wh = doc.get("from_warehouse")
    row_targets = [(r.get("s_warehouse"), r.get("t_warehouse")) for r in (doc.get("items") or [])]

    is_dispatch_staging = (
        (from_wh == MAIN_WH and to_wh == DELIVERY_IN_TRANSIT_WH)
        or any((s == MAIN_WH and t == DELIVERY_IN_TRANSIT_WH) for (s, t) in row_targets)
    )

    if is_dispatch_staging:
        if not doc.sales_order:
            frappe.throw("Dispatch staging Stock Entry must be linked to a Sales Order.")

        so = frappe.get_doc("Sales Order", doc.sales_order)

        if so.discount_approval_status in ("Pending", "Rejected"):
            frappe.throw(
                "Discount approval is required before dispatch staging. "
                "Complete the Discount Approval task (Approved) or remove the discount."
            )

        tasks = frappe.get_all(
            "Task",
            filters={
                "task_kind": "Delivery",
                "sales_order": so.name,
                "status": ["!=", "Cancelled"],
            },
            fields=["name", "warehouse_pickup_photo"],
        )

        if not tasks:
            frappe.throw("Dispatch staging requires an existing Delivery Task linked to this Sales Order.")

        if not any(t.get("warehouse_pickup_photo") for t in tasks):
            frappe.throw("Warehouse Pickup Photo must be attached to the Delivery Task before dispatch staging.")

        if so.is_prepaid:
            if not so.prepayment_payment_entry:
                frappe.throw("Prepaid order requires Prepayment Payment Entry before dispatch staging.")

            pe = frappe.get_doc("Payment Entry", so.prepayment_payment_entry)
            if pe.docstatus != 1:
                frappe.throw("Prepayment Payment Entry must be submitted before dispatch staging.")

            required = float(so.prepayment_required_amount_amd or 0)
            if required > 0:
                paid = float(pe.paid_amount or 0)
                if paid < required:
                    frappe.throw("Prepayment amount is below required amount for this order.")
'@

# --- 8.5: Stock Entry — block staging into client location warehouses ---
$StockEntryNoClientWhScript = @'
CLIENTS_ROOT = "Clients - Inmed"

if doc.get("sales_order"):
    root = frappe.get_doc("Warehouse", CLIENTS_ROOT)
    root_lft = int(root.lft)
    root_rgt = int(root.rgt)

    for row in (doc.items or []):
        wh = row.t_warehouse or doc.get("to_warehouse")
        if wh:
            is_client_wh = frappe.db.exists(
                "Warehouse",
                {"name": wh, "lft": [">=", root_lft], "rgt": ["<=", root_rgt]},
            )

            if is_client_wh:
                frappe.throw("Standard sales must not move stock into client location warehouses (Clients - Inmed).")
'@

# --- 8.6: Delivery Note — enforce transit warehouse + discount/prepaid gates ---
$DeliveryNoteGateScript = @'
DELIVERY_IN_TRANSIT_WH = "Delivery In-Transit - Inmed"

for row in (doc.items or []):
    if row.warehouse != DELIVERY_IN_TRANSIT_WH:
        frappe.throw(
            f"Standard sales Delivery Note must issue from {DELIVERY_IN_TRANSIT_WH}. "
            f"Row warehouse is {row.warehouse or 'not set'}."
        )

sales_orders = sorted(list(set([r.against_sales_order for r in (doc.items or []) if r.against_sales_order])))
for so_name in sales_orders:
    so = frappe.get_doc("Sales Order", so_name)

    if so.discount_approval_status in ("Pending", "Rejected"):
        frappe.throw("Discount approval is required before delivery.")

    if so.is_prepaid:
        if not so.prepayment_payment_entry:
            frappe.throw("Prepaid order requires Prepayment Payment Entry before delivery.")

        pe = frappe.get_doc("Payment Entry", so.prepayment_payment_entry)
        if pe.docstatus != 1:
            frappe.throw("Prepayment Payment Entry must be submitted before delivery.")
'@

# --- 8.7: Task — require warehouse drop-off photo before completing transit return tasks ---
$TaskReturnDropoffScript = @'
before = doc.get_doc_before_save()
before_status = before.status if before else None

is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

if is_becoming_completed and doc.task_kind == "Return drop-off at warehouse":
    if not doc.warehouse_dropoff_photo:
        frappe.throw("Warehouse Drop-off Photo is required to complete this task.")

    if not doc.completed_at:
        doc.completed_at = now_datetime()
'@

# --- 9.2: Scheduled — create / update Debt Collection tasks (hourly) ---
$DebtCollectionScheduledScript = @'
DIRECTOR_ROLE = "Ops - Directors"

def assign_single_owner(task_name, user):
    frappe.db.set_value("Task", task_name, "_assign", json.dumps([user]), update_modified=False)

    other_todos = frappe.get_all(
        "ToDo",
        filters={
            "reference_type": "Task",
            "reference_name": task_name,
            "allocated_to": ["!=", user],
            "status": "Open",
        },
        pluck="name",
    )

    for td in (other_todos or []):
        frappe.db.set_value("ToDo", td, "status", "Cancelled")

    if not frappe.db.exists(
        "ToDo",
        {
            "reference_type": "Task",
            "reference_name": task_name,
            "allocated_to": user,
            "status": "Open",
        },
    ):
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = user
        todo.reference_type = "Task"
        todo.reference_name = task_name
        todo.description = frappe.db.get_value("Task", task_name, "subject") or task_name
        todo.assigned_by = frappe.session.user
        todo.insert(ignore_permissions=True)

def get_net_receivable_amd(customer, company):
    rows = frappe.db.sql(
        """
        select coalesce(sum(debit - credit), 0)
        from `tabGL Entry`
        where is_cancelled = 0
          and company = %s
          and party_type = 'Customer'
          and party = %s
        """,
        (company, customer),
    )
    return float(rows[0][0] or 0)

company = frappe.db.get_single_value("Global Defaults", "default_company")
if not company:
    companies = frappe.get_all("Company", pluck="name")
    company = companies[0] if companies else None

if company:
    director_users = frappe.get_all(
        "Has Role",
        filters={"role": DIRECTOR_ROLE},
        pluck="parent",
    )
    director_users = sorted(list(set(director_users or [])))

    director_users = [
        u
        for u in director_users
        if u not in ("Administrator", "Guest") and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
    ]

    if director_users:
        assigned_director = director_users[0]

        customers = frappe.get_all(
            "Customer",
            filters={"disabled": 0},
            fields=["name", "customer_name", "debt_threshold_amd"],
        )

if company and director_users:
    for c in customers:
        threshold = float(c.debt_threshold_amd or 0)
        if threshold <= 0:
            continue

        debt = get_net_receivable_amd(c.name, company)

        if debt <= threshold:
            continue

        existing = frappe.get_all(
            "Task",
            filters={
                "task_kind": "Debt Collection",
                "customer": c.name,
                "status": ["!=", "Completed"],
            },
            pluck="name",
        )

        if existing:
            task = frappe.get_doc("Task", existing[0])
        else:
            task = frappe.new_doc("Task")
            task.subject = f"Debt Collection — {c.customer_name}"
            task.status = "Open"
            task.task_kind = "Debt Collection"
            task.task_access_policy = "Debt Collection"
            task.customer = c.name
            task.insert(ignore_permissions=True)
            assign_single_owner(task.name, assigned_director)

        task.current_debt_amd = debt
        task.debt_threshold_amd = threshold
        task.description = f"Client debt exceeded threshold. Current debt: {debt}. Threshold: {threshold}."
        task.save(ignore_permissions=True)
'@

# --- 10.1: Payment Entry — create Distribute Payment task on submit ---
$PaymentEntryDistributeScript = @'
DIRECTOR_ROLE = "Ops - Directors"

def assign_single_owner(task_name, user):
    frappe.db.set_value("Task", task_name, "_assign", json.dumps([user]), update_modified=False)

    other_todos = frappe.get_all(
        "ToDo",
        filters={
            "reference_type": "Task",
            "reference_name": task_name,
            "allocated_to": ["!=", user],
            "status": "Open",
        },
        pluck="name",
    )

    for td in (other_todos or []):
        frappe.db.set_value("ToDo", td, "status", "Cancelled")

    if not frappe.db.exists(
        "ToDo",
        {
            "reference_type": "Task",
            "reference_name": task_name,
            "allocated_to": user,
            "status": "Open",
        },
    ):
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = user
        todo.reference_type = "Task"
        todo.reference_name = task_name
        todo.description = frappe.db.get_value("Task", task_name, "subject") or task_name
        todo.assigned_by = frappe.session.user
        todo.insert(ignore_permissions=True)

if doc.party_type == "Customer" and doc.payment_type == "Receive":
    director_users = frappe.get_all(
        "Has Role",
        filters={"role": DIRECTOR_ROLE},
        pluck="parent",
    )
    director_users = sorted(list(set(director_users or [])))

    director_users = [
        u
        for u in director_users
        if u not in ("Administrator", "Guest") and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
    ]

    if director_users:
        assigned_director = director_users[0]

        existing = frappe.get_all(
            "Task",
            filters={
                "task_kind": "Distribute Payment",
                "payment_entry": doc.name,
                "status": ["!=", "Completed"],
            },
            pluck="name",
        )

        if not existing:
            task = frappe.new_doc("Task")
            task.subject = f"Distribute Payment — PE {doc.name}"
            task.status = "Open"
            task.task_kind = "Distribute Payment"
            task.task_access_policy = "Distribute Payment"
            task.payment_entry = doc.name
            task.customer = doc.party

            task.insert(ignore_permissions=True)

            assign_single_owner(task.name, assigned_director)
'@

$ServerScripts = @(
    [pscustomobject]@{
        name              = "Sales Order-before-save-discount-approval"
        script_type       = "DocType Event"
        reference_doctype = "Sales Order"
        doctype_event     = "Before Save"
        event_frequency   = "All"
        script            = $SODiscountApprovalScript
    },
    [pscustomobject]@{
        name              = "Task-before-save-discount-approval-writeback"
        script_type       = "DocType Event"
        reference_doctype = "Task"
        doctype_event     = "Before Save"
        event_frequency   = "All"
        script            = $TaskDiscountWritebackScript
    },
    [pscustomobject]@{
        name              = "Stock Entry-before-submit-dispatch-gate"
        script_type       = "DocType Event"
        reference_doctype = "Stock Entry"
        doctype_event     = "Before Submit"
        event_frequency   = "All"
        script            = $StockEntryDispatchGateScript
    },
    [pscustomobject]@{
        name              = "Stock Entry-before-save-no-client-wh"
        script_type       = "DocType Event"
        reference_doctype = "Stock Entry"
        doctype_event     = "Before Save"
        event_frequency   = "All"
        script            = $StockEntryNoClientWhScript
    },
    [pscustomobject]@{
        name              = "Delivery Note-before-submit-delivery-gate"
        script_type       = "DocType Event"
        reference_doctype = "Delivery Note"
        doctype_event     = "Before Submit"
        event_frequency   = "All"
        script            = $DeliveryNoteGateScript
    },
    [pscustomobject]@{
        name              = "Task-before-save-return-dropoff-photo"
        script_type       = "DocType Event"
        reference_doctype = "Task"
        doctype_event     = "Before Save"
        event_frequency   = "All"
        script            = $TaskReturnDropoffScript
    },
    [pscustomobject]@{
        name              = "Scheduled-debt-collection"
        script_type       = "Scheduler Event"
        reference_doctype = ""
        doctype_event     = ""
        event_frequency   = "Hourly"
        script            = $DebtCollectionScheduledScript
    },
    [pscustomobject]@{
        name              = "Payment Entry-after-submit-distribute-payment"
        script_type       = "DocType Event"
        reference_doctype = "Payment Entry"
        doctype_event     = "After Submit"
        event_frequency   = "All"
        script            = $PaymentEntryDistributeScript
    }
)

# =============================================================================
# STATUS SNAPSHOT  (used by Check and Verify modes)
# =============================================================================

function Get-StatusSnapshot {
    $FieldStatus = foreach ($F in $CustomFields) {
        $Doc = Get-ErpDoc -DocType "Custom Field" -Name $F.name
        [pscustomobject]@{ name = $F.name; exists = ($null -ne $Doc); dt = $Doc.dt; fieldtype = $Doc.fieldtype }
    }

    $ScriptStatus = foreach ($S in $ServerScripts) {
        $Doc = Get-ErpDoc -DocType "Server Script" -Name $S.name
        [pscustomobject]@{
            name              = $S.name
            exists            = ($null -ne $Doc)
            script_type       = $Doc.script_type
            reference_doctype = $Doc.reference_doctype
            doctype_event     = $Doc.doctype_event
            event_frequency   = $Doc.event_frequency
            disabled          = $Doc.disabled
        }
    }

    [ordered]@{
        mode        = $Mode
        logged_user = (Invoke-ErpRequest -Method Get -Path "/api/method/frappe.auth.get_logged_user").message
        custom_fields  = $FieldStatus
        server_scripts = $ScriptStatus
    }
}

# =============================================================================
# EXECUTION
# =============================================================================

if ($Mode -eq "Check") {
    Get-StatusSnapshot | ConvertTo-Json -Depth 12
    exit 0
}

$Results = @()

foreach ($F in $CustomFields) {
    $Results += Upsert-ErpDoc -DocType "Custom Field" -Name $F.name -Body $F.body
}

foreach ($S in $ServerScripts) {
    $Body = [ordered]@{
        doctype           = "Server Script"
        script_type       = $S.script_type
        event_frequency   = $S.event_frequency
        reference_doctype = $S.reference_doctype
        doctype_event     = $S.doctype_event
        allow_guest       = 0
        disabled          = 0
        enable_rate_limit = 0
        script            = $S.script
    }
    $Results += Upsert-ErpDoc -DocType "Server Script" -Name $S.name -Body $Body
}

[ordered]@{
    mode         = $Mode
    results      = $Results
    verification = Get-StatusSnapshot
} | ConvertTo-Json -Depth 12
