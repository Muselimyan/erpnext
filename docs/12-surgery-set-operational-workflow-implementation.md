# Doc 12A — Surgery Set Workflow (Implementation / ERPNext Setup Guide)

## 1) Purpose
This is a **step-by-step setup guide** to implement the workflow described in **Doc 12 — Surgery Set Operational Workflow**.

This implementation guide configures:
- Custom DocTypes needed for the workflow (`Surgery Case` and its child table)
- Workflow (role-based, sequential; no status jumps)
- Task linking + assignment to a specific delivery person
- Mandatory Task photo enforcement (implemented once in Doc 10A)
- Optional linking fields on Stock Entry / Sales Invoice
- Stock Settings needed for **Option A** (backdated pickup-time stock entries)
- Automated debt-threshold monitoring that creates/updates a director debt-collection Task

It also explains (in detail) how to implement the **automation** described in Doc 12, including:
- which workflow actions create which records
- where the records are created and how they are linked
- how to block workflow progress when stock is insufficient
- how to keep automation idempotent (no duplicates)

---

## 2) Prerequisites / access
You should do this as a user with:
- `System Manager`
- `Stock Manager`
- `Accounts Manager`

Do not start Doc 12A until these are done:
- Doc 03A — roles and permissions exist (Ops roles).
- Doc 04A — clients are modeled as `Customer` (no separate Doctor master) and context fields exist.
- Doc 05A — warehouse model exists:
  - `Main - WH`
  - `Delivery In-Transit - WH`
  - `Clients - WH` group + client-location leaf warehouses
  - `Return Pickup In-Transit - WH`
  - `Returns - WH`
- Doc 06A — item tracking is configured (serial/batch/expiry) and FEFO warning exists.
- Doc 10A — Task system exists (Task Kind + Task Access Policy) and mandatory photo enforcement exists:
  - `Delivery` requires `Warehouse Pickup Photo`
  - `Return drop-off at warehouse` requires `Warehouse Drop-off Photo`
- Doc 11A — `Surgery Set Type` templates exist.

You will also need access to:
- `DocType` (to create custom DocTypes)
- `Customize Form` (to add custom fields)
- `Workflow`
- `Role` + `Role Permission Manager`

Practical navigation tip:
- Use the top search bar (Awesomebar) and type the page name exactly (example: type `DocType`, press Enter).

---

## 3) Create the Surgery Case DocTypes (beginner-friendly)
Doc 12 uses a custom operational record `Surgery Case` with a single unified items grid.

Key idea:
- Users enter dispatch quantities once (in `Draft`).
- Returns are entered once (at warehouse receipt).
- Used quantity is computed.

### 3.1 Create the child table: `Surgery Case Item` (one unified items grid)
1) Open `DocType`.
2) Click `New`.
3) Set:
   - `Name`: `Surgery Case Item`
   - Check `Is Child Table`
4) Add fields (in this order):
   - `item` (Link) → Options: `Item` → Req → In List View
   - `dispatched_qty` (Float) → Req → In List View
   - `returned_qty` (Float) → default 0 → In List View
   - `lost_damaged_qty` (Float) → default 0 → In List View
   - `used_qty` (Float) → Read Only → In List View
5) Save.

Validation:
- Create a test `Surgery Case Item` row inside any parent table (later) and confirm columns show in list view.

### 3.1.1 Create the child table: `Surgery Case Serial Exception` (required for tool accountability)
Doc 12 requires that the system blocks closing a case until all dispatched serial-tracked tools are either:
- returned, or
- explicitly recorded as missing/damaged.

This child table is where you record those missing/damaged serials.

1) Open `DocType`.
2) Click `New`.
3) Set:
   - `Name`: `Surgery Case Serial Exception`
   - Check `Is Child Table`
4) Add fields:
   - `item` (Link) → Options: `Item` → Req
   - `serial_no` (Link) → Options: `Serial No` → Req
   - `exception_type` (Select) → Req → Options (one per line):
     - Missing
     - Damaged
     - Not Serialized
   - `notes` (Small Text) → optional
5) Save.

### 3.2 Create the parent DocType: `Surgery Case`
1) Open `DocType`.
2) Click `New`.
3) Set:
   - `Name`: `Surgery Case`
   - Ensure `Is Child Table` is **unchecked**
4) Add fields (recommended minimum):
   - `client` (Link) → Options: `Customer` → Req
   - `hospital` (Link) → Options: `Customer` → optional
   - `hospital_branch` (Data) → Req
   - `client_location_warehouse` (Link) → Options: `Warehouse` → Req
   - `doctor_name` (Data) → optional
   - `surgery_date` (Date) → Req
   - `surgery_set_type` (Link) → Options: `Surgery Set Type` → Req
   - `dispatch_group_id` (Data) → optional
   - `delivery_person` (Link) → Options: `User` → optional
   - `return_pickup_delivery_person` (Link) → Options: `User` → optional
   - `notes` (Small Text) → optional

Read-only warning field (recommended so shortages are visible on the case):
- `shortage_note` (Long Text) → Read Only

Fields for optional barcode scanning (soft capture; not enforced):
- `packed_scan_log` (Long Text)
- `returned_scan_log` (Long Text)

Fields to support automation (strongly recommended):
- Store links to generated documents so the automation is idempotent (does not create duplicates):
  - `dispatch_stock_entry` (Link → Stock Entry)
  - `delivery_stock_entry` (Link → Stock Entry)
  - `return_pickup_stock_entry` (Link → Stock Entry)
  - `return_receive_stock_entry` (Link → Stock Entry)
  - `consumption_stock_entry` (Link → Stock Entry)
  - `sales_invoice` (Link → Sales Invoice)
  - `delivery_task` (Link → Task)
  - `return_pickup_task` (Link → Task)
  - `return_dropoff_task` (Link → Task)

Field for strict tool return (serial accountability):
- `tool_serial_exceptions` (Table) → Options: `Surgery Case Serial Exception`

5) Add the workflow state field (required for Workflow):
   - `workflow_state` (Select)
   - Options (one per line, exactly):
     - Draft
     - Preparing
     - Dispatch Picking
     - Dispatched
     - Delivered
     - Return Pickup Scheduled
     - Return Pickup In Transit
     - Returns Verification
     - Returns Received
     - Usage Derived
     - Invoiced
     - Closed

6) Add the unified items grid:
   - `case_items` (Table) → Options: `Surgery Case Item`

7) Save.

Validation:
- Create a `Surgery Case`.
- Add at least 2 rows in Case Items.
- Confirm you can enter Dispatched Qty and Returned Qty.

---

## 3.3 Locking rules to prevent repeated data entry
Doc 12 requires:
- Dispatched Qty is editable in `Draft`.
- A controlled reduction is allowed in `Dispatch Picking` if stock became insufficient (partial dispatch).
- Returned Qty is only editable by Returns Team during the returns receiving step.

Implementation approach:
- Use `Client Script` on `Surgery Case` to set fields read-only based on workflow state.

Minimum locking behavior (recommended):
- If `workflow_state` is not `Draft` or `Dispatch Picking`, make `case_items.dispatched_qty` read-only.
- If `workflow_state` is not `Return Pickup In Transit` or `Returns Verification`, make `case_items.returned_qty` read-only.

### 3.3.1 Create the Client Script (step-by-step)
1) Open `Client Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `Client`
   - `Reference DocType`: `Surgery Case`
   - `Enabled`: Yes
4) Paste a script that makes the grid read-only based on `workflow_state`.

Suggested script:
```javascript
frappe.ui.form.on('Surgery Case', {
  refresh(frm) {
    const can_edit_dispatch_qty = ['Draft', 'Dispatch Picking'].includes(frm.doc.workflow_state);
    const can_edit_returns = ['Return Pickup In Transit', 'Returns Verification'].includes(frm.doc.workflow_state);

    // Lock dispatch qty after Draft
    frm.fields_dict.case_items.grid.update_docfield_property('dispatched_qty', 'read_only', !can_edit_dispatch_qty);

    // Lock returned qty except during returns receiving step
    frm.fields_dict.case_items.grid.update_docfield_property('returned_qty', 'read_only', !can_edit_returns);

    // Always keep used qty read-only
    frm.fields_dict.case_items.grid.update_docfield_property('used_qty', 'read_only', 1);
  }
});
```

Validation:
- In `Draft`, you can edit Dispatched Qty.
- After moving to `Preparing`, Dispatched Qty is locked.
- In `Returns Received`, Returned Qty is editable.

---

## 4) Add “link-back” fields on standard ERPNext documents (recommended)
These are not strictly required, but they make reporting and auditing much easier.

### 4.1 Add `Surgery Case` link to Stock Entry
1) Open `Customize Form`.
2) Select DocType: `Stock Entry`.
3) Add a custom field:
   - Label: `Surgery Case`
   - Fieldname: `surgery_case`
   - Fieldtype: `Link`
   - Options: `Surgery Case`
4) Add a second custom field (optional):
   - Label: `Dispatch Group ID`
   - Fieldname: `dispatch_group_id`
   - Fieldtype: `Data`
5) Save.

### 4.2 Add `Surgery Case` link to Sales Invoice
1) Open `Customize Form`.
2) Select DocType: `Sales Invoice`.
3) Add custom field:
   - Label: `Surgery Case`
   - Fieldname: `surgery_case`
   - Fieldtype: `Link`
   - Options: `Surgery Case`
4) Save.

---

## 5) Configure Stock Settings for Option A (backdated pickup-time entries)
Doc 12 uses Option A: drivers do tasks only; Returns Team posts Stock Entries later but with pickup-time posting.

1) Open `Stock Settings`.
2) Enable allowing backdated transactions (wording varies by version), and set limits:
   - Allow backdated stock transactions
   - Maximum backdated days (set to a value that fits your reality, e.g. 7–14)
3) Save.

Operational rule:
- Drivers should not have Stock permissions.
- Ensure the right back-office roles can submit Stock Entries (Preparing/Warehouse for dispatch, Returns Team for returns).

### 5.1 Configure item tracking (Serial Numbers, Batch/Lot Numbers, Expiry)
Doc 12 requires traceability for recalls and strict tool accountability.

For each Item, decide which tracking applies:
- Tools / instruments: **Serial Number** tracking (where the instrument has a serial)
- Implants / consumables: **Batch (Lot)** tracking (and batch expiry where applicable)

#### 5.1.1 Enable serial number tracking on tool items
1) Open an `Item`.
2) Enable the serial number setting (wording varies by version).
3) Save.

Operational result:
- Dispatch and return Stock Entries must record the exact serial numbers moved.

#### 5.1.2 Enable batch tracking + expiry on consumable items
1) Open an `Item`.
2) Enable the batch setting (wording varies by version).
3) Save.
4) When receiving stock, create/choose a Batch and enter its Expiry Date.

Operational result:
- Dispatch/return/consumption stock movements must record batch numbers.
- Recalls are done by batch.

---

## 6) Create roles (recommended)
Doc 12 uses the standard Ops roles (Doc 03A). Confirm these roles exist:
- `Ops - Order Accepting`
- `Ops - Inventory`
- `Ops - Delivery`
- `Ops - Returns`
- `Ops - Accounting`
- `Ops - Directors`
- `Delivery Driver`

---

## 7) Permissions (Role Permission Manager)
### 7.1 Surgery Case permissions
1) Open `Role Permission Manager`.
2) Select DocType: `Surgery Case`.
3) Grant permissions by role (typical starting point):
   - `Ops - Order Accepting`: Read, Write, Create
   - `Ops - Inventory`: Read, Write
   - `Ops - Delivery`: Read, Write
   - `Ops - Returns`: Read, Write
   - `Ops - Accounting`: Read, Write
   - `Delivery Driver`: (no access) or Read-only if you want them to see case info

Note:
- Exact permission sets depend on whether you want “Submit/Cancel” behaviors on `Surgery Case`. If you keep it as a simple operational DocType without submitting, you can avoid submit permissions.

### 7.2 Task permissions for drivers
Drivers must be able to:
- see Tasks assigned to them
- upload attachments
- mark the task completed

1) In `Role Permission Manager`, select DocType: `Task`.
2) Ensure `Delivery Driver` has at least:
   - Read
   - Write
   - (and access to File attachments)
3) Ensure `Delivery Driver` does **not** have permissions for:
   - `Stock Entry`
   - `Sales Invoice`

---

## 8) Create the Surgery Case Workflow (no jumps)
### 8.1 Create workflow
1) Open `Workflow` list.
2) Click `New`.
3) Set:
   - `Workflow Name`: `Surgery Case Workflow`
   - `Document Type`: `Surgery Case`
   - `Workflow State Field`: `workflow_state`
4) Save.

### 8.2 Create workflow states
Add states matching the Select options:
- Draft
- Preparing
- Dispatch Picking
- Dispatched
- Delivered
- Return Pickup Scheduled
- Return Pickup In Transit
- Returns Verification
- Returns Received
- Usage Derived
- Invoiced
- Closed

For each state:
- Set appropriate `Doc Status` (usually 0 for operational tracking)

### 8.3 Create workflow transitions (sequential only)
Create transitions so **only the next step** is possible.

Recommended transitions (minimum):
- Draft → Preparing (Allowed Role: `Ops - Order Accepting`)
- Preparing → Dispatch Picking (Allowed Role: `Ops - Inventory`)
- Dispatch Picking → Dispatched (Allowed Role: `Ops - Inventory`)
- Dispatched → Delivered (Allowed Role: `Ops - Delivery`)
- Delivered → Return Pickup Scheduled (Allowed Role: `Ops - Order Accepting`)
- Return Pickup Scheduled → Return Pickup In Transit (Allowed Role: `Ops - Delivery`)
- Return Pickup In Transit → Returns Verification (Allowed Role: `Ops - Returns`)
- Returns Verification → Returns Received (Allowed Role: `Ops - Returns`)
- Returns Received → Usage Derived (Allowed Role: `Ops - Returns`)
- Usage Derived → Invoiced (Allowed Role: `Ops - Accounting`)
- Invoiced → Closed (Allowed Role: `Ops - Order Accepting` or `Ops - Accounting`)

Validation:
- Log in as a user from each team and verify they only see the workflow actions intended for them.

### 8.4 Automation on workflow transitions (required)
Doc 12 requires that later steps are mostly **workflow/status clicks**, with the system generating documents automatically from what was entered in Step 0.

This section is written for someone new to ERPNext.

### 8.4.1 What gets auto-created (overview)
When users click a workflow action on a Surgery Case, automation will create records.

Target behavior (minimum):
- `Preparing` → `Dispatch Picking`
  - Gate: if planned Dispatched Qty is more than what is available in `Main - WH`, block and tell the user to reduce quantities (partial dispatch is allowed)
  - Create Stock Entry as Draft: `Main - WH` → `Delivery In-Transit - WH`
  - Warehouse selects serials/batches (for tracked items) and submits
- `Dispatch Picking` → `Dispatched`
  - Gate: block if dispatch Stock Entry is not submitted
- `Dispatched` → `Delivered`
  - Gate: block unless the `Delivery` task is completed (Warehouse Pickup Photo required by Doc 10A)
  - Create + submit Stock Entry: `Delivery In-Transit - WH` → `Client Location Warehouse`
  - Must copy the same serials/batches that were submitted on the dispatch Stock Entry
- `Delivered` → `Return Pickup Scheduled`
  - Create (or update) a Pickup Returns Task assigned to the selected return pickup delivery person
  - Create (or update) a Return drop-off at warehouse Task assigned to the same person
- `Return Pickup Scheduled` → `Return Pickup In Transit`
  - Gate: block unless Pickup Returns task is completed
- `Return Pickup In Transit` → `Returns Verification`
  - Gate: block unless Return drop-off at warehouse task is completed (Warehouse Drop-off Photo required by Doc 10A)
  - Create Stock Entry #1 as Draft (backdated to pickup time): `Client Location Warehouse` → `Return Pickup In-Transit - WH`
  - Create Stock Entry #2 as Draft (receipt time): `Return Pickup In-Transit - WH` → `Returns - WH`
  - Returns Team selects returned serials/batches (for tracked items) and submits
- `Returns Verification` → `Returns Received`
  - Gate: block if return Stock Entries are not submitted
- `Returns Received` → `Usage Derived`
  - Compute Used Qty per line and write into Case Items `used_qty`
  - Create + submit Consumption Stock Entry (Material Issue) from `Client Location Warehouse` for the used quantities
- `Usage Derived` → `Invoiced`
  - Create a draft Sales Invoice from Used Qty (do not submit)

Operational policy:
- Some Stock Entries are submitted by users (dispatch picking and returns verification) because serial/batch selection is required.
- Sales Invoice is generated as draft only; Accounting reviews and submits manually.

Idempotency rule (critical):
- Before creating any document, check if the corresponding link field is already filled.
- If filled, do not create a new document.

### 8.4.2 Enable Server Scripts (if not enabled)
1) Open `System Settings`.
2) Find the setting that enables server scripts (wording varies by version).
3) Enable it.
4) Save.

### 8.4.3 Add required custom fields on Task (so pickup time can be used)
We will use a Task field to store the pickup completion timestamp.

1) Open `Customize Form`.
2) Select DocType: `Task`.
3) Ensure these custom fields exist (add if missing):
   - `dispatch_group_id` (Data) — Label: `Dispatch Group ID`
   - `surgery_case` (Link → `Surgery Case`) — Label: `Surgery Case`
   - `task_kind` (Select) — Label: `Task Kind`
   - `warehouse_pickup_photo` (Attach) — Label: `Warehouse Pickup Photo`
   - `warehouse_dropoff_photo` (Attach) — Label: `Warehouse Drop-off Photo`
   - `completed_at` (Datetime) — Label: `Completed At` — Read Only
4) Save.

### 8.4.4 Task governance prerequisites (required)
Doc 12 relies on the Task governance rules implemented in **Doc 10A**.

Do not create new Task scripts here.

Confirm Doc 10A is implemented and working:
- `Delivery` tasks cannot be completed without `Warehouse Pickup Photo`.
- `Return drop-off at warehouse` tasks cannot be completed without `Warehouse Drop-off Photo`.
- `completed_at` is set when a Task becomes Completed.
- Tasks have exactly one assignee (Doc 10: one accountable owner).

### 8.4.5 Surgery Case automation (create stock entries, tasks, usage, invoice)
We implement this as a `Server Script` on Surgery Case that runs on each save and reacts to workflow state changes.

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Surgery Case`
   - `DocType Event`: `Before Save`
4) Paste a script that:
   - detects workflow state transitions
   - performs idempotent create/submit actions
   - blocks invalid transitions (stock shortage, missing submitted Stock Entries)

Suggested script (adjust warehouse names if yours differ):
```python
import frappe
from frappe.utils import now_datetime
from frappe.desk.form.assign_to import add as add_assignment

MAIN_WH = "Main - WH"
DELIVERY_TRANSIT_WH = "Delivery In-Transit - WH"
RETURN_TRANSIT_WH = "Return Pickup In-Transit - WH"
RETURNS_WH = "Returns - WH"

def split_serials(serial_no_field):
    if not serial_no_field:
        return []
    if isinstance(serial_no_field, str):
        return [s.strip() for s in serial_no_field.split("\n") if (s or "").strip()]
    return []

def get_actual_qty(item_code, warehouse):
    return frappe.db.get_value("Bin", {"item_code": item_code, "warehouse": warehouse}, "actual_qty") or 0

def make_material_transfer(items, s_wh, t_wh, posting_dt=None):
    se = frappe.new_doc("Stock Entry")
    se.stock_entry_type = "Material Transfer"
    if hasattr(se, "posting_date") and posting_dt:
        se.posting_date = posting_dt.date()
    if hasattr(se, "posting_time") and posting_dt:
        se.posting_time = posting_dt.time()
    if hasattr(se, "set_posting_time"):
        se.set_posting_time = 1

    for it in items:
        se.append("items", {
            "item_code": it["item_code"],
            "qty": it["qty"],
            "s_warehouse": s_wh,
            "t_warehouse": t_wh,
        })

    if hasattr(se, "surgery_case"):
        se.surgery_case = doc.name
    if hasattr(se, "dispatch_group_id") and doc.dispatch_group_id:
        se.dispatch_group_id = doc.dispatch_group_id

    se.insert()
    return se

def submit_if_ready(se_name):
    se = frappe.get_doc("Stock Entry", se_name)
    if se.docstatus == 0:
        se.submit()
    return se

before = doc.get_doc_before_save()
before_state = before.workflow_state if before else None
after_state = doc.workflow_state

state_changed = (before_state != after_state)

# Step 0 helper: auto-load template into Case Items (Draft only)
if after_state == "Draft" and doc.surgery_set_type:
    if not (doc.case_items or []):
        st = frappe.get_doc("Surgery Set Type", doc.surgery_set_type)
        for r in (st.items or []):
            if not r.item:
                continue
            qty = float(getattr(r, "default_qty", 0) or 0)
            if qty <= 0:
                continue

            doc.append(
                "case_items",
                {
                    "item": r.item,
                    "dispatched_qty": qty,
                    "returned_qty": 0,
                    "lost_damaged_qty": 0,
                    "used_qty": 0,
                },
            )

    # Draft-only warning: show shortages from Main - WH without blocking Draft.
    warnings = []
    for row in (doc.case_items or []):
        planned = float(row.dispatched_qty or 0)
        if planned <= 0:
            continue
        actual = float(get_actual_qty(row.item, MAIN_WH) or 0)
        if actual < planned:
            warnings.append(f"{row.item}: planned {planned}, available {actual}, missing {planned - actual}")

    if warnings:
        text = "Draft stock warning (Main - WH):\n" + "\n".join(warnings)
        if hasattr(doc, "shortage_note"):
            doc.shortage_note = text
        frappe.msgprint(text, title="Stock warning (Draft)")
    else:
        if hasattr(doc, "shortage_note"):
            doc.shortage_note = ""

# Build dispatch item list from Case Items (Dispatched Qty)
dispatch_items = []
for row in (doc.case_items or []):
    if row.dispatched_qty and row.dispatched_qty > 0:
        dispatch_items.append({"item_code": row.item, "qty": row.dispatched_qty})

returned_items = []
for row in (doc.case_items or []):
    if row.returned_qty and row.returned_qty > 0:
        returned_items.append({"item_code": row.item, "qty": row.returned_qty})

if not doc.client_location_warehouse:
    frappe.throw("Client Location Warehouse is required.")

CLIENT_LOCATION_WH = doc.client_location_warehouse

# Ensure delivery/pickup Tasks exist when the coordinator fills assignees
if after_state in ("Dispatched", "Delivered") and doc.delivery_person and not doc.delivery_task:
    t = frappe.new_doc("Task")
    t.subject = f"Deliver — {doc.name}"
    t.task_kind = "Delivery"
    t.task_access_policy = "Delivery"
    t.surgery_case = doc.name
    if hasattr(t, "customer"):
        t.customer = doc.client
    if doc.dispatch_group_id:
        t.dispatch_group_id = doc.dispatch_group_id
    t.insert()
    add_assignment({"assign_to": [doc.delivery_person], "doctype": "Task", "name": t.name})
    frappe.db.set_value("Surgery Case", doc.name, "delivery_task", t.name, update_modified=False)

if after_state == "Return Pickup Scheduled" and doc.return_pickup_delivery_person:
    if not doc.return_pickup_task:
        t = frappe.new_doc("Task")
        t.subject = f"Pickup Returns — {doc.name}"
        t.task_kind = "Pickup Returns"
        t.task_access_policy = "Pickup Returns"
        t.surgery_case = doc.name
        if hasattr(t, "customer"):
            t.customer = doc.client
        if doc.dispatch_group_id:
            t.dispatch_group_id = doc.dispatch_group_id
        t.insert()
        add_assignment({"assign_to": [doc.return_pickup_delivery_person], "doctype": "Task", "name": t.name})
        frappe.db.set_value("Surgery Case", doc.name, "return_pickup_task", t.name, update_modified=False)

    if not doc.return_dropoff_task:
        t = frappe.new_doc("Task")
        t.subject = f"Return drop-off — {doc.name}"
        t.task_kind = "Return drop-off at warehouse"
        t.task_access_policy = "Return drop-off at warehouse"
        t.surgery_case = doc.name
        if hasattr(t, "customer"):
            t.customer = doc.client
        if doc.dispatch_group_id:
            t.dispatch_group_id = doc.dispatch_group_id
        t.insert()
        add_assignment({"assign_to": [doc.return_pickup_delivery_person], "doctype": "Task", "name": t.name})
        frappe.db.set_value("Surgery Case", doc.name, "return_dropoff_task", t.name, update_modified=False)

if not state_changed:
    return

# Transition: Preparing -> Dispatch Picking (stock gate + draft dispatch Stock Entry)
if before_state == "Preparing" and after_state == "Dispatch Picking":
    # Gate: check stock availability in Main - WH (Level 1: actual_qty only)
    shortages = []
    for it in dispatch_items:
        actual = get_actual_qty(it["item_code"], MAIN_WH)
        if actual < it["qty"]:
            shortages.append(f"{it['item_code']}: need {it['qty']}, have {actual}")
    if shortages:
        frappe.throw(
            "Insufficient stock in Main - WH for the planned Dispatched Qty.\n"
            "Reduce Dispatched Qty lines (partial dispatch is allowed) and try again.\n\n"
            + "\n".join(shortages)
        )

    if not doc.dispatch_stock_entry:
        se = make_material_transfer(dispatch_items, MAIN_WH, DELIVERY_TRANSIT_WH, posting_dt=now_datetime())
        doc.dispatch_stock_entry = se.name

# Transition: Dispatch Picking -> Dispatched (requires submitted dispatch Stock Entry)
if before_state == "Dispatch Picking" and after_state == "Dispatched":
    if not doc.dispatch_stock_entry:
        frappe.throw("Dispatch Stock Entry is missing")
    se = frappe.get_doc("Stock Entry", doc.dispatch_stock_entry)
    if se.docstatus != 1:
        frappe.throw("Dispatch Stock Entry must be submitted before moving to Dispatched")

# Transition: Dispatched -> Delivered (delivery Stock Entry)
if before_state == "Dispatched" and after_state == "Delivered":
    if not doc.delivery_task:
        frappe.throw("Delivery Task is required before moving to Delivered.")
    delivery_task_status = frappe.db.get_value("Task", doc.delivery_task, "status")
    if delivery_task_status != "Completed":
        frappe.throw("Delivery Task must be completed (with Warehouse Pickup Photo) before moving to Delivered.")

    if not doc.delivery_stock_entry:
        if not doc.dispatch_stock_entry:
            frappe.throw("Dispatch Stock Entry is missing")
        dispatch_se = frappe.get_doc("Stock Entry", doc.dispatch_stock_entry)

        # Copy serials/batches from dispatch Stock Entry items
        delivery_se = frappe.new_doc("Stock Entry")
        delivery_se.stock_entry_type = "Material Transfer"
        if hasattr(delivery_se, "set_posting_time"):
            delivery_se.set_posting_time = 1
        if hasattr(delivery_se, "posting_date"):
            delivery_se.posting_date = now_datetime().date()
        if hasattr(delivery_se, "posting_time"):
            delivery_se.posting_time = now_datetime().time()

        for it in dispatch_se.items:
            delivery_se.append("items", {
                "item_code": it.item_code,
                "qty": it.qty,
                "s_warehouse": DELIVERY_TRANSIT_WH,
                "t_warehouse": CLIENT_LOCATION_WH,
                "batch_no": getattr(it, "batch_no", None),
                "serial_no": getattr(it, "serial_no", None),
            })

        if hasattr(delivery_se, "surgery_case"):
            delivery_se.surgery_case = doc.name
        if hasattr(delivery_se, "dispatch_group_id") and doc.dispatch_group_id:
            delivery_se.dispatch_group_id = doc.dispatch_group_id

        delivery_se.insert()
        delivery_se.submit()
        doc.delivery_stock_entry = delivery_se.name

# Transition: Return Pickup Scheduled -> Return Pickup In Transit
if before_state == "Return Pickup Scheduled" and after_state == "Return Pickup In Transit":
    if not doc.return_pickup_task:
        frappe.throw("Pickup Returns Task is required before moving to Return Pickup In Transit.")
    pickup_task_status = frappe.db.get_value("Task", doc.return_pickup_task, "status")
    if pickup_task_status != "Completed":
        frappe.throw("Pickup Returns Task must be completed before moving to Return Pickup In Transit.")

# Transition: Return Pickup In Transit -> Returns Verification (drop-off gate + draft return Stock Entries)
if before_state == "Return Pickup In Transit" and after_state == "Returns Verification":
    if not doc.return_dropoff_task:
        frappe.throw("Return drop-off at warehouse Task is required before starting returns processing.")

    dropoff_task_status = frappe.db.get_value("Task", doc.return_dropoff_task, "status")
    if dropoff_task_status != "Completed":
        frappe.throw("Return drop-off at warehouse Task must be completed (with Warehouse Drop-off Photo) before starting returns processing.")

    pickup_completed_at = None
    if doc.return_pickup_task:
        pickup_completed_at = frappe.db.get_value("Task", doc.return_pickup_task, "completed_at")

    pickup_dt = pickup_completed_at or now_datetime()
    receipt_dt = now_datetime()

    if not doc.return_pickup_stock_entry:
        se1 = make_material_transfer(returned_items, CLIENT_LOCATION_WH, RETURN_TRANSIT_WH, posting_dt=pickup_dt)
        doc.return_pickup_stock_entry = se1.name

    if not doc.return_receive_stock_entry:
        se2 = make_material_transfer(returned_items, RETURN_TRANSIT_WH, RETURNS_WH, posting_dt=receipt_dt)
        doc.return_receive_stock_entry = se2.name

# Transition: Returns Verification -> Returns Received (requires submitted return Stock Entries)
if before_state == "Returns Verification" and after_state == "Returns Received":
    if not doc.return_pickup_stock_entry or not doc.return_receive_stock_entry:
        frappe.throw("Return Stock Entries are missing")
    se1 = frappe.get_doc("Stock Entry", doc.return_pickup_stock_entry)
    se2 = frappe.get_doc("Stock Entry", doc.return_receive_stock_entry)
    if se1.docstatus != 1 or se2.docstatus != 1:
        frappe.throw("Return Stock Entries must be submitted before moving to Returns Received")

# Transition: Returns Received -> Usage Derived (compute Used Qty)
if before_state == "Returns Received" and after_state == "Usage Derived":
    for row in (doc.case_items or []):
        d = row.dispatched_qty or 0
        r = row.returned_qty or 0
        l = row.lost_damaged_qty or 0
        row.used_qty = d - r - l

        if row.used_qty < 0:
            frappe.throw(f"Used Qty became negative for item {row.item}. Check dispatched/returned/lost quantities.")

    # Recommended: create Consumption Stock Entry (Material Issue) so invoices can remain batch-less.
    # Stock reduction is posted for everything that did NOT return to the warehouse:
    # - Used quantities
    # - Lost/Damaged quantities
    # For batch-tracked items: derive (used+lost)-by-batch = delivered-by-batch − returned-by-batch.
    if not doc.consumption_stock_entry:
        if not doc.delivery_stock_entry or not doc.return_pickup_stock_entry:
            frappe.throw("Delivery and Return Stock Entries are required before consumption posting")

        delivered = frappe.get_doc("Stock Entry", doc.delivery_stock_entry)
        returned = frappe.get_doc("Stock Entry", doc.return_pickup_stock_entry)

        delivered_by_key = {}
        delivered_serials = {}
        for it in delivered.items:
            key = (it.item_code, getattr(it, "batch_no", None))
            delivered_by_key[key] = delivered_by_key.get(key, 0) + (it.qty or 0)

            serials = split_serials(getattr(it, "serial_no", None))
            if serials:
                delivered_serials.setdefault(it.item_code, set()).update(serials)

        returned_by_key = {}
        returned_serials = {}
        for it in returned.items:
            key = (it.item_code, getattr(it, "batch_no", None))
            returned_by_key[key] = returned_by_key.get(key, 0) + (it.qty or 0)

            serials = split_serials(getattr(it, "serial_no", None))
            if serials:
                returned_serials.setdefault(it.item_code, set()).update(serials)

        cons = frappe.new_doc("Stock Entry")
        cons.stock_entry_type = "Material Issue"
        if hasattr(cons, "set_posting_time"):
            cons.set_posting_time = 1
        if hasattr(cons, "posting_date"):
            cons.posting_date = now_datetime().date()
        if hasattr(cons, "posting_time"):
            cons.posting_time = now_datetime().time()

        for row in (doc.case_items or []):
            issue_qty = float((row.dispatched_qty or 0) - (row.returned_qty or 0))
            if issue_qty <= 0:
                continue

            # Serial-tracked items: issue missing serials (delivered - returned).
            missing_serials = sorted(list((delivered_serials.get(row.item, set()) - returned_serials.get(row.item, set())) or []))
            if missing_serials:
                exceptions_rows = doc.get("tool_serial_exceptions") or []
                exceptions = set([r.serial_no for r in exceptions_rows if getattr(r, "serial_no", None)])
                not_recorded = [s for s in missing_serials if s not in exceptions]
                if not_recorded:
                    frappe.throw(
                        "Missing serials must be recorded in Tool Serial Exceptions before usage can be derived.\n"
                        + "\n".join(not_recorded)
                    )

                cons.append(
                    "items",
                    {
                        "item_code": row.item,
                        "qty": len(missing_serials),
                        "s_warehouse": CLIENT_LOCATION_WH,
                        "serial_no": "\n".join(missing_serials),
                    },
                )
                continue

            # Batch tracking gate: if the item was delivered with batch numbers and any qty was returned,
            # the return Stock Entry must record the returned quantities by batch.
            delivered_batch_total = sum(
                [qty for (ic, bn), qty in delivered_by_key.items() if ic == row.item and bn]
            )
            if delivered_batch_total > 0 and float(row.returned_qty or 0) > 0:
                returned_batch_total = sum(
                    [qty for (ic, bn), qty in returned_by_key.items() if ic == row.item and bn]
                )

                if abs(returned_batch_total - float(row.returned_qty or 0)) > 0.0001:
                    frappe.throw(
                        f"Returned Qty for batch-tracked item '{row.item}' must be recorded by batch numbers on the Return Pickup Stock Entry. "
                        f"Case Returned Qty={float(row.returned_qty or 0)}, returned-by-batch={returned_batch_total}."
                    )

            # Batch-tracked items: consume by batch based on delivered-returned.
            used_remaining = issue_qty
            batch_keys = [k for k in delivered_by_key.keys() if k[0] == row.item]

            if batch_keys:
                for key in batch_keys:
                    delivered_qty = delivered_by_key.get(key, 0)
                    returned_qty = returned_by_key.get(key, 0)
                    used_by_batch = delivered_qty - returned_qty
                    if used_by_batch <= 0:
                        continue

                    take = min(used_remaining, used_by_batch)
                    cons.append("items", {
                        "item_code": row.item,
                        "qty": take,
                        "s_warehouse": CLIENT_LOCATION_WH,
                        "batch_no": key[1],
                    })
                    used_remaining -= take
                    if used_remaining <= 0:
                        break

                if used_remaining > 0:
                    frappe.throw(f"Cannot allocate used quantity by batch for item {row.item}. Check delivery/returns batches.")
            else:
                # Non-batch item: consume by qty only
                cons.append("items", {
                    "item_code": row.item,
                    "qty": issue_qty,
                    "s_warehouse": CLIENT_LOCATION_WH,
                })

        if hasattr(cons, "surgery_case"):
            cons.surgery_case = doc.name
        if hasattr(cons, "dispatch_group_id") and doc.dispatch_group_id:
            cons.dispatch_group_id = doc.dispatch_group_id

        cons.insert()
        cons.submit()
        doc.consumption_stock_entry = cons.name

# Transition: Usage Derived -> Invoiced (create draft Sales Invoice)
if before_state == "Usage Derived" and after_state == "Invoiced":
    if not doc.sales_invoice:
        inv = frappe.new_doc("Sales Invoice")
        inv.customer = doc.client
        inv.update_stock = 0
        if hasattr(inv, "surgery_case"):
            inv.surgery_case = doc.name

        if hasattr(inv, "hospital"):
            inv.hospital = doc.hospital
        if hasattr(inv, "hospital_branch"):
            inv.hospital_branch = doc.hospital_branch
        if hasattr(inv, "doctor_name"):
            inv.doctor_name = doc.doctor_name

        for row in (doc.case_items or []):
            if row.used_qty and row.used_qty > 0:
                inv.append("items", {
                    "item_code": row.item,
                    "qty": row.used_qty,
                })
        inv.insert()
        doc.sales_invoice = inv.name

# Transition: Invoiced -> Closed (serial accountability gate)
if before_state == "Invoiced" and after_state == "Closed":
    if not doc.delivery_stock_entry or not doc.return_pickup_stock_entry:
        frappe.throw("Delivery and Return Stock Entries are required before closing.")

    delivered = frappe.get_doc("Stock Entry", doc.delivery_stock_entry)
    returned = frappe.get_doc("Stock Entry", doc.return_pickup_stock_entry)

    delivered_serials = {}
    for it in delivered.items:
        serials = split_serials(getattr(it, "serial_no", None))
        if serials:
            delivered_serials.setdefault(it.item_code, set()).update(serials)

    returned_serials = {}
    for it in returned.items:
        serials = split_serials(getattr(it, "serial_no", None))
        if serials:
            returned_serials.setdefault(it.item_code, set()).update(serials)

    exceptions_rows = doc.get("tool_serial_exceptions") or []
    exceptions = set([r.serial_no for r in exceptions_rows if getattr(r, "serial_no", None)])

    missing_all = []
    for item_code, serials in delivered_serials.items():
        missing = sorted(list((serials - returned_serials.get(item_code, set())) or []))
        for s in missing:
            if s not in exceptions:
                missing_all.append(f"{item_code}: {s}")

    if missing_all:
        frappe.throw(
            "Cannot close case: dispatched serial-tracked tools are missing and not recorded in Tool Serial Exceptions.\n"
            + "\n".join(missing_all)
        )
```

Notes for beginners:
- The script above is intentionally explicit so you can see which workflow transition creates which records.
- You must adjust any fieldnames if your custom fields differ.
- If you are not comfortable with server scripts, do this in a small custom app.

---

## 8.5) Sample data (required to test end-to-end)
Create one sample Surgery Case so you can test that automation + stock movement works.

Prerequisite sample masters (from earlier docs):
- Customer: `D001 — Dr. A. Petrosyan`
- Hospital context Customer: `H001 — Erebuni MC`
- Client location warehouse (leaf under `Clients - WH`):
  - `D001 — Dr. A. Petrosyan @ H001 — Erebuni MC / Main - WH`
- Surgery Set Type: `Ortho Basic Set (Sample)` (Doc 11A)
- Items exist with tracking:
  - `TOOL-001` (serial-tracked)
  - `IMP-001` (batch-tracked)
  - `CONS-001` (batch or non-tracked, depending on your catalog)

### 8.5.1 Create the sample Surgery Case
1) Open `Surgery Case`.
2) Click `New`.
3) Fill:
   - Client: `D001 — Dr. A. Petrosyan`
   - Hospital: `H001 — Erebuni MC`
   - Hospital Branch: `Main`
   - Client Location Warehouse: `D001 — Dr. A. Petrosyan @ H001 — Erebuni MC / Main - WH`
   - Doctor Name: (leave empty; optional)
   - Surgery Date: today + 2 days (example)
   - Surgery Set Type: `Ortho Basic Set (Sample)`
   - Dispatch Group ID: `DG-0001` (sample)
4) In `Case Items` enter your planned dispatch quantities:
   - `TOOL-001` dispatched_qty = `1`
   - `IMP-001` dispatched_qty = `2`
   - `CONS-001` dispatched_qty = `5`
5) Save.

Expected result:
- Case is saved in `Draft`.
- Dispatched Qty is editable.

---

## 8.6) Standard operating procedure (per-surgery case)
This section is the step-by-step daily procedure that Doc 12 defines. It assumes the Workflow + automation script from section 8.4.5 are installed.

### 8.6.1 Step 0 — Create the case (Order Team)
1) Create the `Surgery Case` (as in section 8.5).
2) Ensure `Case Items.dispatched_qty` reflects what you intend to send.
3) Save.

### 8.6.2 Step 2 — Preparing
1) Open the case.
2) Use the Workflow action to move it from `Draft` → `Preparing`.
3) Pack the items listed in `Case Items`.

### 8.6.3 Step 3 — Dispatch picking + submit dispatch stock entry
1) Use the Workflow action to move the case from `Preparing` → `Dispatch Picking`.
2) Expected result:
   - Draft `dispatch_stock_entry` is created: `Main - WH` → `Delivery In-Transit - WH`.
3) Open the draft dispatch Stock Entry.
4) Select actual serial numbers / batch numbers for tracked items.
5) Submit the Stock Entry.
6) Use the Workflow action to move the case from `Dispatch Picking` → `Dispatched`.

### 8.6.4 Step 4–5 — Delivery
1) On the Surgery Case, set `delivery_person` (a User).
2) Save.
3) Expected result:
   - `delivery_task` is created and assigned to that delivery person.
4) Driver completes the Delivery task (Warehouse Pickup Photo required).
5) Delivery Coordinator uses the Workflow action to move the case `Dispatched` → `Delivered`.
6) Expected result:
   - `delivery_stock_entry` is created/submitted:
     - `Delivery In-Transit - WH` → `client_location_warehouse`
     - same batches/serials as dispatch

### 8.6.5 Step 7–8 — Return pickup + drop-off at warehouse
1) When client requests pickup, set `return_pickup_delivery_person`.
2) Use the Workflow action to move the case `Delivered` → `Return Pickup Scheduled`.
3) Expected result:
   - `return_pickup_task` (Pickup Returns) is created/assigned
   - `return_dropoff_task` (Return drop-off at warehouse) is created/assigned
4) Driver completes Pickup Returns task.
5) Delivery Coordinator moves the case `Return Pickup Scheduled` → `Return Pickup In Transit`.
6) Driver completes Return drop-off at warehouse task (Warehouse Drop-off Photo required).

### 8.6.6 Step 9 — Returns receiving + posting return stock entries
1) Returns Team opens the case.
2) Enter `Case Items.returned_qty` based on counted items.
3) If any serial tool is missing/damaged, record serials in `tool_serial_exceptions`.
4) Move the case `Return Pickup In Transit` → `Returns Verification`.
5) Expected result:
   - Draft return Stock Entries are created:
     - `client_location_warehouse` → `Return Pickup In-Transit - WH` (posting time = pickup task time)
     - `Return Pickup In-Transit - WH` → `Returns - WH` (receipt time)
6) Returns Team opens the return Stock Entries, selects returned serials/batches, and submits them.
7) Move the case `Returns Verification` → `Returns Received`.

### 8.6.7 Step 10 — Usage derived + consumption posting
1) Move the case `Returns Received` → `Usage Derived`.
2) Expected result:
   - `used_qty` is computed per line
   - `consumption_stock_entry` is created/submitted from the client location warehouse

### 8.6.8 Step 11 — Invoice used items
1) Move the case `Usage Derived` → `Invoiced`.
2) Expected result:
   - Draft Sales Invoice is created for Used Qty only.
3) Accounting reviews and submits the Sales Invoice.

### 8.6.9 Step 12 — Close
1) Move the case `Invoiced` → `Closed`.
2) Gate:
   - If any dispatched serial-tracked tool did not return, it must be present in `tool_serial_exceptions`.

## 9) Task setup (assignment to a specific delivery person)
Doc 12 relies on the Task system from **Doc 10A**.

Do not re-implement Task fields/scripts here.

### 9.1 Confirm Task Kinds needed for Doc 12 exist
In Doc 10A, confirm `Task Kind` includes these values:
- `Delivery`
- `Pickup Returns`
- `Return drop-off at warehouse`

### 9.2 Confirm Task visibility model exists (Task Access Policy)
Doc 12 assumes:
- Every operational Task has `task_access_policy` set (Doc 10A auto-fills it from Task Kind).
- Users can only see Tasks whose Task Access Policies they are granted.

Minimum go-live visibility recommendation:
- Delivery drivers:
  - `Delivery`
  - `Pickup Returns`
  - `Return drop-off at warehouse`
- Coordinators (`Ops - Delivery`) and Directors:
  - all Task Access Policies

### 9.3 Confirm mandatory attachment rules (Doc 10A)
Required at go-live:
- `Delivery` task completion requires `Warehouse Pickup Photo`.
- `Return drop-off at warehouse` task completion requires `Warehouse Drop-off Photo`.

Important:
- `Pickup Returns` does **not** require a photo in this operating model.

---

## 10) Driver experience (minimal ERPNext)
Recommended driver operating procedure:
- Driver only uses:
  - `Task` list filtered to “Assigned to me”

Driver actions (Doc 12):
1) Delivery
   - Open the `Delivery` task
   - Attach `Warehouse Pickup Photo`
   - Deliver
   - Add a short handover note (Task description)
   - Complete the task

2) Return pickup
   - Open the `Pickup Returns` task
   - Complete the task (no photo required)

3) Return drop-off at warehouse
   - Open the `Return drop-off at warehouse` task
   - Attach `Warehouse Drop-off Photo`
   - Complete the task

No driver access to:
- Stock Entry
- Sales Invoice
- Surgery Case workflows

---

## 11) Automated debt threshold task (directors)
Doc 12 includes debt threshold alerting, but this is a **shared** automation used across multiple flows.

Implementation rule:
- Implement debt automation once (Doc 09A section 9), and reuse it.

Checklist:
1) Confirm `Customer.debt_threshold_amd` exists (Doc 04A).
2) Confirm the **Scheduled Server Script** from Doc 09A is enabled and running hourly.
3) Confirm it creates/updates exactly one open `Debt Collection` task per Customer when thresholds are exceeded.

---

## 12) Returns Team operating procedure (with automation)
When the driver returns to the warehouse:
1) Open the returned package.
2) Count unused returned items.
3) Open the relevant `Surgery Case`.
4) Fill `Case Items.returned_qty` for each line.
5) If a tool/instrument did not return or is damaged:
   - increment `lost_damaged_qty` on the tool line, and
   - optionally record the serial in `tool_serial_exceptions`.
5) Optional: scan returned barcodes into `returned_scan_log`.
6) Use the workflow action to move the case to `Returns Verification`.
7) Open the draft return Stock Entries and select returned serials/batches where required.
8) Submit the return Stock Entries.
9) Use the workflow action to move the case to `Returns Received`.

Expected system behavior:
- The system auto-creates return Stock Entries as drafts.
- Returns Team submits them after selecting serials/batches.

Next:
1) Use the workflow action to move the case to `Usage Derived`.
2) Confirm Used Qty is computed in the Case Items grid.
3) Confirm Consumption Stock Entry exists (stock reduced from the client location warehouse for not-returned quantities).

---

## 13) Permanent on-site sets (alternative model)
Some client locations keep a surgery set permanently on-site. Doc 12 requires that you still maintain location-truth in the stock ledger.

Implementation rule:
- Permanent on-site sets are represented as stock in the client location warehouse under `Clients - WH`.

### 13.1 Initial placement (one-time)
Goal: place the baseline stock into the client location warehouse.

1) Create Stock Entry (Material Transfer):
   - From Warehouse: `Main - WH`
   - To Warehouse: `Delivery In-Transit - WH`
   - Include the items/qty being placed
2) Submit.
3) Create Stock Entry (Material Transfer):
   - From Warehouse: `Delivery In-Transit - WH`
   - To Warehouse: the client location warehouse
4) Submit.

### 13.2 Replenishment cycle (repeat after usage)
1) After surgery usage, Returns/Warehouse posts a Stock Entry (Material Issue) from the client location warehouse for the used/missing quantities.
2) Accounting invoices the used quantities (standard selling documents).
3) Warehouse replenishes stock back into the client location warehouse using the same staging pattern:
   - `Main - WH` → `Delivery In-Transit - WH` → client location warehouse.

---

## 14) Implementation validation checklist
### 14.1 Workflow / permissions
- Users cannot jump statuses
- Each team sees only their allowed workflow actions
- Case cannot move to `Dispatched` unless dispatch Stock Entry is submitted
- Case cannot move to `Returns Received` unless return Stock Entries are submitted

### 14.2 Task controls
- Dispatch/Pickup tasks can be assigned to a specific delivery person
- Delivery task cannot be completed without a Warehouse Pickup Photo
- Return drop-off at warehouse task cannot be completed without a Warehouse Drop-off Photo

### 14.3 Stock control
- Drivers cannot access Stock Entry
- Returns team can backdate Stock Entry to pickup time

### 14.4 End-to-end test
Run one test case:
- Create Surgery Case
- Move to Dispatch Picking; confirm draft dispatch Stock Entry is created
- Select serials/batches on dispatch Stock Entry and submit; move to Dispatched
- Complete the Delivery task (with Warehouse Pickup Photo), then move case to Delivered and confirm delivery Stock Entry posts into the Client Location Warehouse
- Schedule pickup (move to `Return Pickup Scheduled`) and confirm:
  - Pickup Returns task is created and assigned
  - Return drop-off at warehouse task is created and assigned
- Complete Pickup Returns task (no photo required), move case to Return Pickup In Transit
- Complete Return drop-off at warehouse task (with Warehouse Drop-off Photo)
- Receive returns: move to Returns Verification; confirm draft return Stock Entries exist
- Select returned serials/batches and submit return Stock Entries; move to Returns Received
- Derive usage
- Confirm Consumption Stock Entry was created/submitted
- Invoice used items (draft)
- Try to close case with a missing serial tool that is not recorded in Tool Serial Exceptions: it must be blocked
- Record missing serial(s) in Tool Serial Exceptions and close case: it must succeed

### 14.5 Debt automation test
- Set a customer debt threshold (`debt_threshold_amd`)
- Create unpaid invoices above threshold
- Confirm a single director debt-collection Task is created
- Change debt amount and confirm the same Task is updated
