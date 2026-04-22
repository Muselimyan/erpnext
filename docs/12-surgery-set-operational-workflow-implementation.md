# Doc 12A — Surgery Set Workflow (Implementation / ERPNext Setup Guide)

## 1) Purpose
This is a **step-by-step setup guide** to implement the workflow described in **Doc 12 — Surgery Set Operational Workflow**.

This implementation guide configures:
- Custom DocTypes needed for the workflow (`Surgery Case` and its child table)
- Workflow (role-based, sequential; no status jumps)
- Task linking + assignment to a specific delivery person
- Mandatory pickup photo enforcement
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

### 3.1.1 (Optional) Create the child table: `Surgery Case Serial Exception`
If you want strict tool accountability, you need a place to record “this serial did not come back, and why”.

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
   - `hospital` (Link) → Options: `Customer` → Req
   - `hospital_warehouse` (Link) → Options: `Warehouse` → Req
   - `doctor` (Link) → Options: `Doctor` → Req
   - `surgery_date` (Date) → Req
   - `surgery_set_type` (Link) → Options: `Surgery Set Type` → Req
   - `dispatch_group_id` (Data) → optional
   - `delivery_person` (Link) → Options: `User` → optional
   - `return_pickup_delivery_person` (Link) → Options: `User` → optional
   - `notes` (Small Text) → optional

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

Optional fields for strict tool return (serial accountability):
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
- Dispatched Qty is only editable in `Draft`.
- Returned Qty is only editable by Returns Team during the returns receiving step.

Implementation approach:
- Use `Client Script` on `Surgery Case` to set fields read-only based on workflow state.

Minimum locking behavior (recommended):
- If `workflow_state != "Draft"` then make `case_items.dispatched_qty` read-only.
- If `workflow_state` is not `Returns Verification` or `Returns Received` then make `case_items.returned_qty` read-only.

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
    const is_draft = frm.doc.workflow_state === 'Draft';
    const can_edit_returns = ['Returns Verification', 'Returns Received'].includes(frm.doc.workflow_state);

    // Lock dispatch qty after Draft
    frm.fields_dict.case_items.grid.update_docfield_property('dispatched_qty', 'read_only', !is_draft);

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
Create roles so permissions and workflow transitions can be controlled.

Suggested roles:
- `Surgery Case - Order`
- `Surgery Case - Preparing`
- `Surgery Case - Delivery Coordinator`
- `Surgery Case - Returns`
- `Surgery Case - Accounting`
- `Delivery Driver`

Create roles:
1) Open `Role`.
2) Click `New`.
3) Create each role above.

---

## 7) Permissions (Role Permission Manager)
### 7.1 Surgery Case permissions
1) Open `Role Permission Manager`.
2) Select DocType: `Surgery Case`.
3) Grant permissions by role (typical starting point):
   - `Surgery Case - Order`: Read, Write, Create
   - `Surgery Case - Preparing`: Read, Write
   - `Surgery Case - Delivery Coordinator`: Read, Write
   - `Surgery Case - Returns`: Read, Write
   - `Surgery Case - Accounting`: Read, Write
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
- Draft → Preparing (Allowed Role: `Surgery Case - Order`)
- Preparing → Dispatch Picking (Allowed Role: `Surgery Case - Preparing`)
- Dispatch Picking → Dispatched (Allowed Role: `Surgery Case - Preparing`)
- Dispatched → Delivered (Allowed Role: `Surgery Case - Delivery Coordinator`)
- Delivered → Return Pickup Scheduled (Allowed Role: `Surgery Case - Order`)
- Return Pickup Scheduled → Return Pickup In Transit (Allowed Role: `Surgery Case - Delivery Coordinator`)
- Return Pickup In Transit → Returns Verification (Allowed Role: `Surgery Case - Returns`)
- Returns Verification → Returns Received (Allowed Role: `Surgery Case - Returns`)
- Returns Received → Usage Derived (Allowed Role: `Surgery Case - Returns`)
- Usage Derived → Invoiced (Allowed Role: `Surgery Case - Accounting`)
- Invoiced → Closed (Allowed Role: `Surgery Case - Order` or `Surgery Case - Accounting`)

Validation:
- Log in as a user from each team and verify they only see the workflow actions intended for them.

### 8.4 Automation on workflow transitions (required)
Doc 12 requires that later steps are mostly **workflow/status clicks**, with the system generating documents automatically from what was entered in Step 0.

This section is written for someone new to ERPNext.

### 8.4.1 What gets auto-created (overview)
When users click a workflow action on a Surgery Case, automation will create records.

Target behavior (minimum):
- `Preparing` → `Dispatch Picking`
  - Gate: block if stock is insufficient in `Main - WH`
  - Create Stock Entry as Draft: `Main - WH` → `Delivery In-Transit - WH`
  - Warehouse selects serials/batches (for tracked items) and submits
- `Dispatch Picking` → `Dispatched`
  - Gate: block if dispatch Stock Entry is not submitted
- `Dispatched` → `Delivered`
  - Create + submit Stock Entry: `Delivery In-Transit - WH` → `HOSP - <Hospital> - WH`
  - Must copy the same serials/batches that were submitted on the dispatch Stock Entry
- `Delivered` → `Return Pickup Scheduled`
  - Create (or update) a Pickup Returns Task assigned to the selected return pickup delivery person
- `Return Pickup In Transit` → `Returns Verification`
  - Create Stock Entry #1 as Draft (backdated to pickup time): `HOSP - <Hospital> - WH` → `Return Pickup In-Transit - WH`
  - Create Stock Entry #2 as Draft (receipt time): `Return Pickup In-Transit - WH` → `Returns - WH`
  - Returns Team selects returned serials/batches (for tracked items) and submits
- `Returns Verification` → `Returns Received`
  - Gate: block if return Stock Entries are not submitted
- `Returns Received` → `Usage Derived`
  - Compute Used Qty per line and write into Case Items `used_qty`
  - Create + submit Consumption Stock Entry (Material Issue) from `HOSP - <Hospital> - WH` for the used quantities
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
   - `task_kind` (Select) — Label: `Task Kind` — Options:
     - Delivery
     - Pickup Returns
   - `pickup_photo` (Attach) — Label: `Pickup Photo`
   - `completed_at` (Datetime) — Label: `Completed At` — Read Only
4) Save.

### 8.4.4 Task automation (set completion time + enforce pickup photo)
Create a server-side validation so your process does not depend on drivers remembering rules.

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Task`
   - `DocType Event`: `Before Save`
4) Paste a script that:
   - blocks completion of Pickup Returns tasks without a photo
   - sets `completed_at` the first time a task is completed

Suggested script (adjust fieldnames if you used different ones):
```python
from frappe.utils import now_datetime

before = doc.get_doc_before_save()
before_status = before.status if before else None

is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

if doc.task_kind == "Pickup Returns" and is_becoming_completed:
    if not doc.pickup_photo:
        frappe.throw("Pickup Photo is required to complete this task")

if is_becoming_completed and not doc.completed_at:
    doc.completed_at = now_datetime()
```

Validation:
- Create a Pickup Returns task.
- Try to mark it Completed without a photo (must fail).
- Attach a photo and complete (must succeed).
- Confirm `completed_at` is filled.

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

# Build dispatch item list from Case Items (Dispatched Qty)
dispatch_items = []
for row in (doc.case_items or []):
    if row.dispatched_qty and row.dispatched_qty > 0:
        dispatch_items.append({"item_code": row.item, "qty": row.dispatched_qty})

returned_items = []
for row in (doc.case_items or []):
    if row.returned_qty and row.returned_qty > 0:
        returned_items.append({"item_code": row.item, "qty": row.returned_qty})

# Ensure delivery/pickup Tasks exist when the coordinator fills assignees
if after_state in ("Dispatched", "Delivered") and doc.delivery_person and not doc.delivery_task:
    t = frappe.new_doc("Task")
    t.subject = f"Deliver — {doc.name}"
    t.task_kind = "Delivery"
    t.surgery_case = doc.name
    if doc.dispatch_group_id:
        t.dispatch_group_id = doc.dispatch_group_id
    t.insert()
    add_assignment({"assign_to": [doc.delivery_person], "doctype": "Task", "name": t.name})
    frappe.db.set_value("Surgery Case", doc.name, "delivery_task", t.name, update_modified=False)

if after_state == "Return Pickup Scheduled" and doc.return_pickup_delivery_person and not doc.return_pickup_task:
    t = frappe.new_doc("Task")
    t.subject = f"Pickup Returns — {doc.name}"
    t.task_kind = "Pickup Returns"
    t.surgery_case = doc.name
    if doc.dispatch_group_id:
        t.dispatch_group_id = doc.dispatch_group_id
    t.insert()
    add_assignment({"assign_to": [doc.return_pickup_delivery_person], "doctype": "Task", "name": t.name})
    frappe.db.set_value("Surgery Case", doc.name, "return_pickup_task", t.name, update_modified=False)

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
        frappe.throw("Insufficient stock in Main - WH:\n" + "\n".join(shortages))

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
                "t_warehouse": doc.hospital_warehouse,
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

# Transition: Return Pickup In Transit -> Returns Verification (draft return Stock Entries)
if before_state == "Return Pickup In Transit" and after_state == "Returns Verification":
    pickup_completed_at = None
    if doc.return_pickup_task:
        pickup_completed_at = frappe.db.get_value("Task", doc.return_pickup_task, "completed_at")

    pickup_dt = pickup_completed_at or now_datetime()
    receipt_dt = now_datetime()

    if not doc.return_pickup_stock_entry:
        se1 = make_material_transfer(returned_items, doc.hospital_warehouse, RETURN_TRANSIT_WH, posting_dt=pickup_dt)
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

    # Recommended: create Consumption Stock Entry (Material Issue) so invoices can remain batch-less.
    # For batch-tracked items: derive used-by-batch = delivered-by-batch − returned-by-batch.
    if not doc.consumption_stock_entry:
        if not doc.delivery_stock_entry or not doc.return_receive_stock_entry:
            frappe.throw("Delivery and Return Stock Entries are required before consumption posting")

        delivered = frappe.get_doc("Stock Entry", doc.delivery_stock_entry)
        returned = frappe.get_doc("Stock Entry", doc.return_receive_stock_entry)

        delivered_by_key = {}
        for it in delivered.items:
            key = (it.item_code, getattr(it, "batch_no", None))
            delivered_by_key[key] = delivered_by_key.get(key, 0) + (it.qty or 0)

        returned_by_key = {}
        for it in returned.items:
            key = (it.item_code, getattr(it, "batch_no", None))
            returned_by_key[key] = returned_by_key.get(key, 0) + (it.qty or 0)

        cons = frappe.new_doc("Stock Entry")
        cons.stock_entry_type = "Material Issue"
        if hasattr(cons, "set_posting_time"):
            cons.set_posting_time = 1
        if hasattr(cons, "posting_date"):
            cons.posting_date = now_datetime().date()
        if hasattr(cons, "posting_time"):
            cons.posting_time = now_datetime().time()

        for row in (doc.case_items or []):
            if not row.used_qty or row.used_qty <= 0:
                continue

            # Batch-tracked items: consume by batch based on delivered-returned.
            used_remaining = row.used_qty
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
                        "s_warehouse": doc.hospital_warehouse,
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
                    "qty": row.used_qty,
                    "s_warehouse": doc.hospital_warehouse,
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
        inv.customer = doc.hospital
        inv.update_stock = 0
        if hasattr(inv, "surgery_case"):
            inv.surgery_case = doc.name
        for row in (doc.case_items or []):
            if row.used_qty and row.used_qty > 0:
                inv.append("items", {
                    "item_code": row.item,
                    "qty": row.used_qty,
                })
        inv.insert()
        doc.sales_invoice = inv.name
```

Notes for beginners:
- The script above is intentionally explicit so you can see which workflow transition creates which records.
- You must adjust any fieldnames if your custom fields differ.
- If you are not comfortable with server scripts, do this in a small custom app.

---

## 9) Task setup (assignment to a specific delivery person)
We use standard ERPNext `Task` to assign work to one person.

### 9.1 Add linking fields to Task (recommended)
1) Open `Customize Form`.
2) Select DocType: `Task`.
3) Add custom fields:
   - `dispatch_group_id` (Data) — Label: `Dispatch Group ID`
   - `surgery_case` (Link → `Surgery Case`) — Label: `Surgery Case` (optional for single-case tasks)
   - `task_kind` (Select) — Label: `Task Kind` — Options:
     - Delivery
     - Pickup Returns
4) Save.

### 9.2 Enforce “pickup photo required to complete”
Goal: prevent closing a pickup task without a photo.

Implementation approach:
- Add an Attach field to Task
- Add a validation rule (Server Script recommended) that blocks completion if missing

1) In `Customize Form` → `Task`, add:
   - Field: `pickup_photo` (Attach) — Label: `Pickup Photo`
2) Create the server-side validation described in section **8.4.4**.

Validation:
- Create a Pickup Returns task, try to complete without photo (must fail), then attach photo and complete (must succeed).

---

## 10) Driver experience (minimal ERPNext)
Recommended driver operating procedure:
- Driver only uses:
  - `Task` list filtered to “Assigned to me”
- For pickup:
  - open task
  - attach photo
  - click complete

No driver access to:
- Stock Entry
- Sales Invoice
- Surgery Case workflows

---

## 11) Automated debt threshold task (directors)
Doc 12 requires that debt monitoring is automated:
- if a hospital exceeds its threshold and there is no open task, create one for directors
- if it already exists, update it with the latest debt

### 11.1 Store the debt threshold per hospital
Recommended implementation (simple):
1) Open `Customize Form`.
2) Select DocType: `Customer`.
3) Add a custom field:
   - Label: `Debt Threshold`
   - Fieldname: `debt_threshold`
   - Fieldtype: `Currency`
   - Options: `Company:default_currency` (if your ERPNext version supports it)
4) Save.

Operational rule:
- If the threshold is empty, treat it as “no threshold” or use a company default (choose one policy and apply consistently).

### 11.2 Task structure for debt collection
Use standard `Task` with:
- Subject convention (recommended): `Debt Collection — <Hospital Name>`
- Assigned to: a director user (or a director group policy)
- Status: keep it Open until resolved

Recommended additional Task fields (optional):
- `customer` (Link → Customer)
- `current_debt` (Currency)

### 11.3 Automation method (recommended)
Use a scheduled automation that runs periodically (for example, hourly or daily).

Implementation options:
- **Server Script (Scheduled)**, if enabled in your ERPNext
- A small custom app (more robust; best long-term)

Core logic (behavior):
1) For each hospital Customer with a threshold:
   - compute current outstanding debt
2) If debt exceeds threshold:
   - find an existing open Task for that hospital (by `customer` field or by subject naming convention)
   - if not found, create it and assign to directors
   - if found, update `current_debt` (and description) to the latest value
3) If debt is below threshold:
   - do nothing (or optionally close the task if you want auto-close behavior; define policy)

Validation:
- Set one hospital threshold low for testing.
- Create an unpaid invoice to push the debt above threshold.
- Run the scheduled automation and confirm:
  - a director task is created
  - when debt changes, the existing task is updated (not duplicated)

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
3) Confirm Consumption Stock Entry exists (stock reduced from hospital warehouse for used quantities).

---

## 13) Implementation validation checklist
### 13.1 Workflow / permissions
- Users cannot jump statuses
- Each team sees only their allowed workflow actions
- Case cannot move to `Dispatched` unless dispatch Stock Entry is submitted
- Case cannot move to `Returns Received` unless return Stock Entries are submitted

### 13.2 Task controls
- Dispatch/Pickup tasks can be assigned to a specific delivery person
- Pickup Returns task cannot be completed without a photo

### 13.3 Stock control
- Drivers cannot access Stock Entry
- Returns team can backdate Stock Entry to pickup time

### 13.4 End-to-end test
Run one test case:
- Create Surgery Case
- Move to Dispatch Picking; confirm draft dispatch Stock Entry is created
- Select serials/batches on dispatch Stock Entry and submit; move to Dispatched
- Deliver to hospital WH
- Schedule pickup (move to `Return Pickup Scheduled`) and confirm the pickup Task is created; complete it with a photo
- Receive returns: move to Returns Verification; confirm draft return Stock Entries exist
- Select returned serials/batches and submit return Stock Entries; move to Returns Received
- Derive usage
- Confirm Consumption Stock Entry was created/submitted
- Invoice used items (draft)
- Close case

### 13.5 Debt automation test
- Set a hospital debt threshold
- Create unpaid invoices above threshold
- Confirm a single director debt-collection Task is created
- Change debt amount and confirm the same Task is updated
