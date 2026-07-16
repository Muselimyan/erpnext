# Doc 16A — Unified Dispatch Flow (Implementation / ERPNext Setup Guide)

> **Status note — historical setup guide:** This document contains original implementation/setup snippets and may include outdated embedded server-script examples. For current deployed workflow behavior, use `docs/16-unified-dispatch-flow.md` and `docs/manual/surgery-case-walkthrough-v2.md`. Do not treat embedded code snippets in this file as the current live source of truth without comparing them to deployed scripts.

## 1) Purpose

This is a **step-by-step setup guide** to implement the workflow described in:
- **Doc 16 — Unified Dispatch Flow**

This guide covers:
- Creating/updating roles and team users
- Adding new Task Kind options
- Adding custom fields on `Task` for multi-state delivery, payment recording, and case linking
- Creating the `Dispatch Case` custom DocType with all child tables
- Creating child DocTypes for Debt Collection task payment tracking
- All server scripts that drive automation (SE creation, task chaining, discount detection, payment entry creation)
- Permissions per role
- Workspace shortcuts (task inbox views)

Prerequisites from earlier docs are listed in Section 2.

---

## 2) Prerequisites / access

Do **not** start Doc 16A until these are done:
- **Doc 03A** — Ops roles exist (`Ops - Order Accepting`, `Ops - Inventory`, `Ops - Returns`, `Ops - Accounting`, `Ops - Directors`, `Delivery Driver`)
- **Doc 05A** — Warehouse model exists:
  - `Main - Inmed`
  - `Delivery In-Transit - Inmed`
  - `Return Pickup In-Transit - Inmed`
  - `Returns - Inmed`
  - Client-location leaf warehouses under `Clients - Inmed`
- **Doc 06A** — Item tracking configured (serial / batch / expiry, FEFO warning)
- **Doc 10A** — Task system exists (`task_kind` field, `Task Access Policy`, single-owner enforcement)
- **Doc 11A** — `Collection Set` templates exist (used as item templates for Dispatch Case)

You need access to:
- `System Manager` role
- `Accounts Manager` role
- `DocType` (create custom DocTypes)
- `Customize Form` (add custom fields)
- `Server Script`
- `Role Permission Manager`
- `User` (create team users)

---

## 3) Roles and Team Users

### 3.1 Create new roles (if not already present)

1) Open `Role` (search in Awesomebar).
2) Create the following roles if missing:

| Role name | Description |
|---|---|
| `Ops - Order Creating` | Creates Dispatch Cases from Order entry tasks |
| `Ops - Finance` | Records payments; manages debt collection |

All other roles from the table below should already exist from Doc 03A. Verify:

| Role | Must exist from |
|---|---|
| `Ops - Order Accepting` | Doc 03A |
| `Ops - Inventory` | Doc 03A |
| `Ops - Returns` | Doc 03A |
| `Ops - Accounting` | Doc 03A |
| `Ops - Directors` | Doc 03A |
| `Delivery Driver` | Doc 03A |

### 3.2 Create team users (one per role)

For each role create a dedicated **team user** in ERPNext. This user acts as the default task assignee for that team. Individual team members then reassign tasks to themselves.

1) Open `User`.
2) Create the following users:

| Full Name | Email (example) | Role to assign |
|---|---|---|
| Order Acceptance Team | team-order-accept@internal | `Ops - Order Accepting` |
| Order Creation Team | team-order-create@internal | `Ops - Order Creating` |
| Inventory Team | team-inventory@internal | `Ops - Inventory` |
| Delivery Team | team-delivery@internal | `Delivery Driver` |
| Returns Team | team-returns@internal | `Ops - Returns` |
| Accounting Team | team-accounting@internal | `Ops - Accounting` |
| Finance Team | team-finance@internal | `Ops - Finance` |
| Directors Team | team-directors@internal | `Ops - Directors` |

3) For each team user:
   - Set a strong password.
   - Assign exactly the one role listed above.
   - These users are **never used to log in** — they exist only as assignment targets.

---

## 4) Update `task_kind` options

Two new task kinds must be added that do not exist yet.

1) Open `Customize Form`.
2) Select DocType: `Task`.
3) Find the `task_kind` field (fieldname: `task_kind`).
4) Edit its **Options** — add these two lines at the end (keep all existing options):
   ```
   Payment Received
   Returns restocking
   ```
5) Save.

Full options list after update (order matters for display):
```
Order entry
Pack / prepare items
Dispatch picking / hand-off
Delivery
Return to warehouse (aborted delivery / cancelled order)
Pickup Returns
Return drop-off at warehouse
Returns processing / verification
Returns restocking
Invoice preparation / create invoice
Debt Collection
Distribute Payment
Payment Received
Discount Approval
Purchase Approval
Write-off Approval
```

Also update the `Task Access Policy` records (Doc 10A section 5.4.1) to add:
- `Payment Received`
- `Returns restocking`

---

## 5) New custom fields on `Task`

Open `Customize Form` → `Task`. Add the following fields (in addition to any already added by Doc 10A).

### 5.1 Dispatch Case link
- Label: `Dispatch Case`
- Fieldname: `dispatch_case`
- Fieldtype: `Link`
- Options: `Dispatch Case`
- In List View: Yes
- In Standard Filter: Yes

### 5.2 Delivery status (for multi-state Delivery task)
- Label: `Delivery Status`
- Fieldname: `delivery_status`
- Fieldtype: `Select`
- Options (one per line):
  ```
  Todo
  Picked Up
  Delivered
  ```
- Default: `Todo`
- Read Only: No (drivers update this)

### 5.3 Pickup status (for multi-state Return Pickup task)
- Label: `Pickup Status`
- Fieldname: `pickup_status`
- Fieldtype: `Select`
- Options (one per line):
  ```
  Todo
  Picked Up
  Returned to Warehouse
  ```
- Default: `Todo`

### 5.4 Return pickup driver assignment
- Label: `Return Pickup Driver`
- Fieldname: `return_pickup_driver`
- Fieldtype: `Link`
- Options: `User`

### 5.5 Scheduled return date
- Label: `Scheduled Return Date`
- Fieldname: `scheduled_return_date`
- Fieldtype: `Date`

### 5.6 Approval outcome (for Discount Approval task)
- Label: `Approval Outcome`
- Fieldname: `approval_outcome`
- Fieldtype: `Select`
- Options (one per line):
  ```
  
  Approved
  Rejected
  ```
- Default: *(blank)*

### 5.7 Delivery photo (written by driver, also saved to Dispatch Case)
- Label: `Delivery Photo`
- Fieldname: `delivery_photo`
- Fieldtype: `Attach`

### 5.8 Handover note
- Label: `Handover Note`
- Fieldname: `handover_note`
- Fieldtype: `Small Text`

### 5.9 Payment recording fields (for Debt Collection task)

Add a **Section Break** with label `Record Payment`, then:

- Label: `New Payment Amount`
- Fieldname: `new_payment_amount`
- Fieldtype: `Currency`

- Label: `Payment Method`
- Fieldname: `payment_method`
- Fieldtype: `Select`
- Options:
  ```
  
  Cash
  Bank Transfer
  Card
  ```

- Label: `Payment Reference`
- Fieldname: `payment_reference`
- Fieldtype: `Data`

### 5.10 Payment summary fields (read-only, on Debt Collection task)

- Label: `Total Outstanding`
- Fieldname: `total_outstanding`
- Fieldtype: `Currency`
- Read Only: Yes

- Label: `Available Advance Credit`
- Fieldname: `available_advance_credit`
- Fieldtype: `Currency`
- Read Only: Yes

**Save** `Customize Form` after adding all fields above.

---

## 6) Create Dispatch Case child DocTypes

### 6.1 Create `Dispatch Case Item` child table

1) Open `DocType` → `New`.
2) Set:
   - Name: `Dispatch Case Item`
   - Check `Is Child Table`
3) Add fields in this order:

| Fieldname | Label | Fieldtype | Options / Notes |
|---|---|---|---|
| `item_code` | Item Code | Link | Item — Req — In List View |
| `item_name` | Item Name | Data | Read Only — fetched from Item |
| `dispatched_qty` | Dispatched Qty | Float | Req — In List View |
| `serial_no` | Serial No | Small Text | Filled by Inventory at Pack step |
| `batch_no` | Batch No | Link | Batch — Filled by Inventory at Pack step |
| `unit_price` | Unit Price | Currency | Optional |
| `discount_pct` | Discount % | Percent | Default 0 |
| `returned_qty` | Returned Qty | Float | Default 0 — filled by Returns team |
| `lost_damaged_qty` | Lost / Damaged Qty | Float | Default 0 — filled by Returns team |
| `used_qty` | Used Qty | Float | Read Only — auto-computed |

4) Save.

### 6.2 Create `Debt Collection Invoice` child table (open invoices list on task)

1) Open `DocType` → `New`.
2) Set:
   - Name: `Debt Collection Invoice`
   - Check `Is Child Table`
3) Add fields:

| Fieldname | Label | Fieldtype | Notes |
|---|---|---|---|
| `dispatch_case` | Dispatch Case | Link → `Dispatch Case` | Read Only |
| `sales_invoice` | Sales Invoice | Link → `Sales Invoice` | Read Only |
| `invoice_amount` | Invoice Amount | Currency | Read Only |
| `paid_amount` | Paid Amount | Currency | Read Only |
| `outstanding_amount` | Outstanding | Currency | Read Only |
| `allocated_now` | Allocate Now | Currency | Editable — Finance fills for FIFO override |

4) Save.

### 6.3 Create `Debt Collection Payment` child table (payment history log)

1) Open `DocType` → `New`.
2) Set:
   - Name: `Debt Collection Payment`
   - Check `Is Child Table`
3) Add fields:

| Fieldname | Label | Fieldtype | Notes |
|---|---|---|---|
| `payment_date` | Payment Date | Datetime | Read Only — auto-set |
| `amount` | Amount | Currency | Read Only |
| `method` | Method | Select | Cash / Bank Transfer / Card — Read Only |
| `reference` | Reference | Data | Read Only |
| `payment_entry` | Payment Entry | Link → `Payment Entry` | Read Only — auto-linked |

4) Save.

### 6.4 Add child tables to `Task` via Customize Form

1) Open `Customize Form` → `Task`.
2) Add a **Section Break**: label `Debt Collection — Invoices`.
3) Add field:
   - Label: `Open Invoices`
   - Fieldname: `open_invoices`
   - Fieldtype: `Table`
   - Options: `Debt Collection Invoice`
   - Read Only: No (Finance edits `allocated_now` column)
4) Add a **Section Break**: label `Debt Collection — Payment History`.
5) Add field:
   - Label: `Payment History`
   - Fieldname: `payment_history`
   - Fieldtype: `Table`
   - Options: `Debt Collection Payment`
   - Read Only: Yes
6) Save.

---

## 7) Create the `Dispatch Case` parent DocType

1) Open `DocType` → `New`.
2) Set:
   - Name: `Dispatch Case`
   - Is Child Table: **unchecked**
   - Autoname: `DC-.YYYY.-.#####` (e.g., DC-2026-00001)
   - Title Field: `customer`
3) Add fields in this order:

**Section: Basic Info**

| Fieldname | Label | Fieldtype | Notes |
|---|---|---|---|
| `customer` | Customer | Link → `Customer` | Req |
| `client_location_warehouse` | Client Location Warehouse | Link → `Warehouse` | Req |
| `return_expected` | Return Expected | Check | Default 0 |
| `surgery_date` | Surgery / Delivery Date | Date | Optional |
| `surgery_set_type` | Item Template | Link → `Collection Set` | Optional |
| `status` | Status | Select | See options below — Read Only (set by scripts) |
| `notes` | Notes | Small Text | Optional |

`status` options (one per line):
```
Draft
Awaiting Approval
Confirmed
Packed
In Transit
Delivered
Awaiting Return Pickup
Return Pickup Scheduled
Return In Transit
Returns Received
Invoice Pending
Invoiced
Payment Pending
Closed
```

**Section: Items**

| Fieldname | Label | Fieldtype | Notes |
|---|---|---|---|
| `case_items` | Case Items | Table → `Dispatch Case Item` | Req |

**Section: Linked Tasks**

| Fieldname | Label | Fieldtype | Notes |
|---|---|---|---|
| `order_entry_task` | Order Entry Task | Link → `Task` | Read Only |
| `discount_approval_task` | Discount Approval Task | Link → `Task` | Read Only |
| `discount_approval_status` | Discount Approval Status | Select | Options: Pending / Approved / Rejected — Read Only |
| `pack_task` | Pack Task | Link → `Task` | Read Only |
| `delivery_task` | Delivery Task | Link → `Task` | Read Only |
| `return_waiting_task` | Return Waiting Task | Link → `Task` | Read Only |
| `return_pickup_task` | Return Pickup Task | Link → `Task` | Read Only |
| `returns_inspection_task` | Returns Inspection Task | Link → `Task` | Read Only |
| `restock_task` | Restock Task | Link → `Task` | Read Only |
| `invoice_task` | Invoice Task | Link → `Task` | Read Only |

**Section: Linked Stock Entries**

| Fieldname | Label | Fieldtype | Notes |
|---|---|---|---|
| `dispatch_stock_entry` | Dispatch SE (Main → In-Transit) | Link → `Stock Entry` | Read Only |
| `delivery_stock_entry` | Delivery SE (In-Transit → Client WH) | Link → `Stock Entry` | Read Only |
| `consumption_stock_entry` | Consumption SE (Client WH → out) | Link → `Stock Entry` | Read Only |
| `return_pickup_stock_entry` | Return Pickup SE (Client → In-Transit) | Link → `Stock Entry` | Read Only |
| `return_receive_stock_entry` | Return Receive SE (In-Transit → Returns) | Link → `Stock Entry` | Read Only |
| `restock_stock_entry` | Restock SE (Returns → Main) | Link → `Stock Entry` | Read Only |

**Section: Invoice and Payment**

| Fieldname | Label | Fieldtype | Notes |
|---|---|---|---|
| `sales_invoice` | Sales Invoice | Link → `Sales Invoice` | Read Only |
| `prepaid_amount` | Prepaid Amount | Currency | Default 0 |
| `prepaid_payment_entry` | Prepaid Payment Entry | Link → `Payment Entry` | Read Only |
| `total_invoice_amount` | Invoice Amount | Currency | Read Only — auto-filled from Sales Invoice |
| `total_paid_amount` | Total Paid | Currency | Read Only — tracked from Payment Entries |
| `outstanding_amount` | Outstanding | Currency | Read Only — auto-computed |

**Section: Photos**

| Fieldname | Label | Fieldtype | Notes |
|---|---|---|---|
| `delivery_photo` | Delivery Photo | Attach | Read Only — copied from Delivery task |
| `return_dropoff_photo` | Return Drop-off Photo | Attach | Read Only — copied from Return Pickup task |

4) Save.

### 7.1 Add "Load from Template" button on Dispatch Case

1) Open `Customize Form` → `Dispatch Case`.
2) Add a `Button` field just above the `case_items` table:
   - Label: `Load from Template`
   - Fieldname: `load_from_template_btn`
   - Fieldtype: `Button`
3) Save.
4) Create a **Client Script** on `Dispatch Case` (Form):

```javascript
frappe.ui.form.on('Dispatch Case', {
    load_from_template_btn: function(frm) {
        if (!frm.doc.surgery_set_type) {
            frappe.msgprint('Please select an Item Template first.');
            return;
        }
        frappe.call({
            method: 'frappe.client.get',
            args: { doctype: 'Collection Set', name: frm.doc.surgery_set_type },
            callback: function(r) {
                if (!r.message) return;
                frm.clear_table('case_items');
                (r.message.items || []).forEach(function(row) {
                    let new_row = frm.add_child('case_items');
                    new_row.item_code = row.item;
                    new_row.dispatched_qty = row.qty || 1;
                    new_row.unit_price = row.rate || 0;
                });
                frm.refresh_field('case_items');
            }
        });
    }
});
```

Note: Adjust `r.message.items`, `row.item`, `row.qty`, and `row.rate` field names to match the actual `Collection Set` child table field names from Doc 11A.

---

## 8) Permissions

### 8.1 Dispatch Case

Open `Role Permission Manager` → `Dispatch Case`.

| Role | Read | Write | Create | Delete | Submit | Cancel |
|---|---|---|---|---|---|---|
| `Ops - Order Creating` | ✅ | ✅ | ✅ | | ✅ | |
| `Ops - Inventory` | ✅ | ✅ | | | | |
| `Ops - Returns` | ✅ | ✅ | | | | |
| `Ops - Accounting` | ✅ | | | | | |
| `Ops - Finance` | ✅ | | | | | |
| `Ops - Directors` | ✅ | ✅ | ✅ | | ✅ | ✅ |
| `System Manager` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

Notes:
- `Ops - Inventory` needs Write only to fill `serial_no` / `batch_no` in Case Items.
- `Ops - Returns` needs Write only to fill `returned_qty` / `lost_damaged_qty` in Case Items.
- `Ops - Accounting` needs Read only to verify invoice amounts match.
- `Delivery Driver` does **not** need access to `Dispatch Case`.

### 8.2 Task (update existing)

Ensure the new roles have Task permissions:

| Role | Read | Write | Create |
|---|---|---|---|
| `Ops - Order Creating` | ✅ | ✅ | ✅ |
| `Ops - Finance` | ✅ | ✅ | ✅ |

### 8.3 Task Access Policy — assign to users

Open `User Permission`. For each real user, grant `Task Access Policy` records matching their role:

| Role | Allowed Task Access Policies |
|---|---|
| `Ops - Order Accepting` | Order entry |
| `Ops - Order Creating` | Order entry, Discount Approval |
| `Ops - Inventory` | Pack / prepare items |
| `Delivery Driver` | Delivery, Pickup Returns |
| `Ops - Returns` | Pickup Returns, Returns processing / verification, Returns restocking |
| `Ops - Accounting` | Invoice preparation / create invoice |
| `Ops - Finance` | Debt Collection, Distribute Payment, Payment Received |
| `Ops - Directors` | All policies |

Also grant `Ops - Order Creating` the `Order entry` policy so they can see the Order entry tasks they're picking up.

---

## 9) Server Scripts

### Script 9.1 — Dispatch Case: Before Save

**Trigger:** DocType Event → `Dispatch Case` → `Before Save`

This script:
- Auto-computes `used_qty` for each Case Items row
- Validates `used_qty >= 0` (prevents data entry errors)
- Detects discount and sets status to `Awaiting Approval`
- Creates a `Discount Approval` task if needed

```python
import frappe

def _run():
    # 1. Compute used_qty for each item row
    for row in (doc.case_items or []):
        dispatched = row.dispatched_qty or 0
        returned = row.returned_qty or 0
        lost = row.lost_damaged_qty or 0
        row.used_qty = dispatched - returned - lost
        if row.used_qty < 0:
            frappe.throw(
                f"Row {row.idx}: used_qty cannot be negative "
                f"(dispatched={dispatched}, returned={returned}, lost={lost})."
            )

    # 2. Discount detection — only when case is in Draft
    if doc.status == "Draft":
        has_discount = any((row.discount_pct or 0) > 0 for row in (doc.case_items or []))
        if has_discount:
            doc.status = "Awaiting Approval"
            doc.discount_approval_status = "Pending"
            # Create Discount Approval task if not already exists
            existing = frappe.db.exists(
                "Task",
                {"dispatch_case": doc.name, "task_kind": "Discount Approval",
                 "status": ["not in", ["Completed", "Cancelled"]]}
            )
            if not existing:
                t = frappe.get_doc({
                    "doctype": "Task",
                    "subject": f"Discount Approval: {doc.name} — {doc.customer}",
                    "task_kind": "Discount Approval",
                    "task_access_policy": "Discount Approval",
                    "dispatch_case": doc.name,
                    "customer": doc.customer,
                    "description": (
                        "Review discounted items and approve or reject.\n"
                        + "\n".join(
                            f"- {r.item_code} x{r.dispatched_qty}: "
                            f"{r.unit_price} AMD ({r.discount_pct}% discount)"
                            for r in doc.case_items if (r.discount_pct or 0) > 0
                        )
                    ),
                    "_assign": frappe.json.dumps(["team-directors@internal"]),
                })
                t.insert(ignore_permissions=True)
                doc.discount_approval_task = t.name

_run()
```

### Script 9.2 — Task: Before Save (gates + photo enforcement)

**Trigger:** DocType Event → `Task` → `Before Save`

This extends (or replaces) the existing Doc 10A governance script. Add these checks to the existing script's gate section.

```python
import frappe

before = doc.get_doc_before_save()
before_status = before.status if before else None
before_delivery_status = (before.delivery_status if before else None)
before_pickup_status = (before.pickup_status if before else None)

is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")
delivery_advancing = (doc.task_kind == "Delivery" and doc.delivery_status != before_delivery_status)
pickup_advancing = (doc.task_kind == "Pickup Returns" and doc.pickup_status != before_pickup_status)

# --- Gate: Delivery task → "Delivered" requires delivery_photo ---
if delivery_advancing and doc.delivery_status == "Delivered":
    if not doc.delivery_photo:
        frappe.throw("Delivery Photo is required before marking as Delivered.")
    # Mirror photo to Dispatch Case
    if doc.dispatch_case:
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, "delivery_photo", doc.delivery_photo)

# --- Gate: Return Pickup task → "Returned to Warehouse" requires delivery_photo ---
if pickup_advancing and doc.pickup_status == "Returned to Warehouse":
    if not doc.delivery_photo:
        frappe.throw("Drop-off Photo is required before marking as Returned to Warehouse.")
    if doc.dispatch_case:
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, "return_dropoff_photo", doc.delivery_photo)

# --- Gate: Pack task completion requires serial/batch filled on all Case Items ---
if is_becoming_completed and doc.task_kind == "Pack / prepare items":
    if doc.dispatch_case:
        case = frappe.get_doc("Dispatch Case", doc.dispatch_case)
        for row in (case.case_items or []):
            item_doc = frappe.get_doc("Item", row.item_code)
            if item_doc.has_serial_no and not (row.serial_no or "").strip():
                frappe.throw(
                    f"Serial No is required for '{row.item_code}' before completing the Pack task. "
                    f"Open the Dispatch Case and fill it in."
                )
            if item_doc.has_batch_no and not row.batch_no:
                frappe.throw(
                    f"Batch No is required for '{row.item_code}' before completing the Pack task. "
                    f"Open the Dispatch Case and fill it in."
                )

# --- Gate: Returns Inspection completion requires returned_qty filled ---
if is_becoming_completed and doc.task_kind == "Returns processing / verification":
    if doc.dispatch_case:
        case = frappe.get_doc("Dispatch Case", doc.dispatch_case)
        for row in (case.case_items or []):
            if row.returned_qty is None:
                frappe.throw(
                    f"Returned Qty must be filled for all items before completing Returns Inspection. "
                    f"Open the Dispatch Case and fill in returned quantities."
                )

# --- Gate: Invoice Preparation completion requires Sales Invoice submitted ---
if is_becoming_completed and doc.task_kind == "Invoice preparation / create invoice":
    if doc.dispatch_case:
        invoice_name = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "sales_invoice")
        if not invoice_name:
            frappe.throw("No Sales Invoice linked to this Dispatch Case yet.")
        inv_status = frappe.db.get_value("Sales Invoice", invoice_name, "docstatus")
        if inv_status != 1:
            frappe.throw("The Sales Invoice must be submitted before completing this task.")

# --- Gate: Discount Approval task completion requires approval_outcome set ---
if is_becoming_completed and doc.task_kind == "Discount Approval":
    if not doc.approval_outcome:
        frappe.throw("Set Approval Outcome (Approved or Rejected) before completing this task.")
```

### Script 9.3 — Task: After Save (main flow orchestrator)

**Trigger:** DocType Event → `Task` → `After Save`

This is the main automation engine. It fires SEs and creates the next task in the chain.

```python
import frappe
from frappe.utils import now_datetime, today

def _run():
    before = doc.get_doc_before_save()
    before_status = before.status if before else None
    before_delivery_status = (before.delivery_status if before else None) or "Todo"
    before_pickup_status = (before.pickup_status if before else None) or "Todo"

    is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")
    delivery_status_changed = (
        doc.task_kind == "Delivery" and
        doc.delivery_status != before_delivery_status
    )
    pickup_status_changed = (
        doc.task_kind == "Pickup Returns" and
        doc.pickup_status != before_pickup_status
    )

    if not doc.dispatch_case:
        return

    case = frappe.get_doc("Dispatch Case", doc.dispatch_case)

    # ================================================================
    # DELIVERY task state transitions
    # ================================================================
    if delivery_status_changed and doc.delivery_status == "Picked Up":
        # Update case status — items are now physically with driver
        # (Stock is already in Delivery In-Transit from Pack SE)
        frappe.db.set_value("Dispatch Case", case.name, "status", "In Transit")

    if delivery_status_changed and doc.delivery_status == "Delivered":
        # SE: Delivery In-Transit → Client Location Warehouse
        se = _create_transfer_se(
            case=case,
            source_wh="Delivery In-Transit - Inmed",
            target_wh=case.client_location_warehouse,
            items=_all_case_items(case),
            purpose="Material Transfer",
        )
        frappe.db.set_value("Dispatch Case", case.name, {
            "status": "Delivered",
            "delivery_stock_entry": se.name,
        })
        case.reload()

        if not case.return_expected:
            # No-return path: consume all items, create invoice, create invoice task
            _consume_items(case, [(r.item_code, r.dispatched_qty, r.serial_no, r.batch_no) for r in case.case_items])
            _create_sales_invoice(case)
            frappe.db.set_value("Dispatch Case", case.name, "status", "Invoice Pending")
            _create_task(
                kind="Invoice preparation / create invoice",
                subject=f"Invoice: {case.name} — {case.customer}",
                case=case,
                assignee="team-accounting@internal",
            )
        else:
            # Return path: create Return Waiting task
            frappe.db.set_value("Dispatch Case", case.name, "status", "Awaiting Return Pickup")
            _create_task(
                kind="Pickup Returns",
                subject=f"Wait for return call: {case.name} — {case.customer}",
                case=case,
                assignee="team-returns@internal",
                description=f"Client: {case.customer}\nItems dispatched:\n" +
                    "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items),
                link_field="return_waiting_task",
            )

    # ================================================================
    # RETURN PICKUP task state transitions
    # ================================================================
    if pickup_status_changed and doc.pickup_status == "Picked Up":
        # SE: Client Location Warehouse → Return Pickup In-Transit
        se = _create_transfer_se(
            case=case,
            source_wh=case.client_location_warehouse,
            target_wh="Return Pickup In-Transit - Inmed",
            items=_all_case_items(case),
            purpose="Material Transfer",
        )
        frappe.db.set_value("Dispatch Case", case.name, {
            "status": "Return In Transit",
            "return_pickup_stock_entry": se.name,
        })

    if pickup_status_changed and doc.pickup_status == "Returned to Warehouse":
        # SE: Return Pickup In-Transit → Returns WH
        se = _create_transfer_se(
            case=case,
            source_wh="Return Pickup In-Transit - Inmed",
            target_wh="Returns - Inmed",
            items=_all_case_items(case),
            purpose="Material Transfer",
        )
        frappe.db.set_value("Dispatch Case", case.name, {
            "status": "Returns Received",
            "return_receive_stock_entry": se.name,
        })
        _create_task(
            kind="Returns processing / verification",
            subject=f"Inspect returns: {case.name} — {case.customer}",
            case=case,
            assignee="team-returns@internal",
            description=f"Open the Dispatch Case and fill in returned_qty for each item.",
            link_field="returns_inspection_task",
        )

    # ================================================================
    # PACK task completed
    # ================================================================
    if is_becoming_completed and doc.task_kind == "Pack / prepare items":
        case.reload()
        # SE: Main → Delivery In-Transit
        se = _create_transfer_se(
            case=case,
            source_wh="Main - Inmed",
            target_wh="Delivery In-Transit - Inmed",
            items=_all_case_items(case),
            purpose="Material Transfer",
        )
        frappe.db.set_value("Dispatch Case", case.name, {
            "status": "Packed",
            "dispatch_stock_entry": se.name,
        })
        _create_task(
            kind="Delivery",
            subject=f"Deliver: {case.name} — {case.customer}",
            case=case,
            assignee="team-delivery@internal",
            description=(
                f"Deliver to: {case.customer}\n"
                f"Location warehouse: {case.client_location_warehouse}\n"
                f"Items:\n" +
                "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
            ),
            link_field="delivery_task",
        )

    # ================================================================
    # RETURN WAITING task completed (Return Pickup Scheduled)
    # ================================================================
    if is_becoming_completed and doc.task_kind == "Pickup Returns":
        # Distinguish between "waiting" task (no pickup_status) and "active pickup" task
        case.reload()
        if case.status == "Awaiting Return Pickup":
            driver = doc.return_pickup_driver or "team-delivery@internal"
            frappe.db.set_value("Dispatch Case", case.name, "status", "Return Pickup Scheduled")
            t = _create_task(
                kind="Pickup Returns",
                subject=f"Pickup Returns: {case.name} — {case.customer}",
                case=case,
                assignee=driver,
                description=(
                    f"Pick up from: {case.customer}\n"
                    f"Location: {case.client_location_warehouse}\n"
                    f"Items to collect:\n" +
                    "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
                ),
                link_field="return_pickup_task",
            )
            if doc.scheduled_return_date:
                frappe.db.set_value("Task", t.name, "exp_end_date", doc.scheduled_return_date)

    # ================================================================
    # RETURNS INSPECTION task completed
    # ================================================================
    if is_becoming_completed and doc.task_kind == "Returns processing / verification":
        case.reload()
        # Consume used items: SE from Client WH → out (Material Issue)
        used_items = [
            (r.item_code, r.used_qty, r.serial_no, r.batch_no)
            for r in case.case_items if (r.used_qty or 0) > 0
        ]
        if used_items:
            _consume_items(case, used_items)
        _create_sales_invoice(case)
        frappe.db.set_value("Dispatch Case", case.name, "status", "Invoice Pending")

        # Invoice task for Accounting
        _create_task(
            kind="Invoice preparation / create invoice",
            subject=f"Invoice: {case.name} — {case.customer}",
            case=case,
            assignee="team-accounting@internal",
            link_field="invoice_task",
        )

        # Restock task if any items returned
        returned_items = [r for r in case.case_items if (r.returned_qty or 0) > 0]
        if returned_items:
            _create_task(
                kind="Returns restocking",
                subject=f"Restock returns: {case.name}",
                case=case,
                assignee="team-returns@internal",
                description=(
                    "Move from Returns WH → Main WH:\n" +
                    "\n".join(f"- {r.item_code} x{r.returned_qty}" for r in returned_items)
                ),
                link_field="restock_task",
            )

    # ================================================================
    # RESTOCK task completed
    # ================================================================
    if is_becoming_completed and doc.task_kind == "Returns restocking":
        case.reload()
        returned_items = [
            (r.item_code, r.returned_qty, r.serial_no, r.batch_no)
            for r in case.case_items if (r.returned_qty or 0) > 0
        ]
        se = _create_transfer_se(
            case=case,
            source_wh="Returns - Inmed",
            target_wh="Main - Inmed",
            items=returned_items,
            purpose="Material Transfer",
        )
        frappe.db.set_value("Dispatch Case", case.name, "restock_stock_entry", se.name)

    # ================================================================
    # INVOICE PREPARATION task completed
    # ================================================================
    if is_becoming_completed and doc.task_kind == "Invoice preparation / create invoice":
        case.reload()
        invoice_name = case.sales_invoice
        invoice_total = frappe.db.get_value("Sales Invoice", invoice_name, "grand_total") or 0
        prepaid = case.prepaid_amount or 0
        outstanding = invoice_total - prepaid
        frappe.db.set_value("Dispatch Case", case.name, {
            "status": "Invoiced",
            "total_invoice_amount": invoice_total,
            "outstanding_amount": outstanding,
        })

        if outstanding <= 0:
            frappe.db.set_value("Dispatch Case", case.name, "status", "Closed")
        else:
            frappe.db.set_value("Dispatch Case", case.name, "status", "Payment Pending")
            _create_or_update_debt_collection_task(case, outstanding, invoice_name)

    # ================================================================
    # DISCOUNT APPROVAL task completed
    # ================================================================
    if is_becoming_completed and doc.task_kind == "Discount Approval":
        if doc.approval_outcome == "Approved":
            frappe.db.set_value("Dispatch Case", case.name, {
                "status": "Confirmed",
                "discount_approval_status": "Approved",
            })
            case.reload()
            # Create Pack task
            _create_task(
                kind="Pack / prepare items",
                subject=f"Pack: {case.name} — {case.customer}",
                case=case,
                assignee="team-inventory@internal",
                description=(
                    f"Pack for delivery to: {case.customer}\n"
                    f"Items:\n" +
                    "\n".join(
                        f"- {r.item_code} x{r.dispatched_qty} "
                        f"[serial: {'required' if _item_has_serial(r.item_code) else 'n/a'}]"
                        for r in case.case_items
                    )
                ),
                link_field="pack_task",
            )
        else:  # Rejected
            frappe.db.set_value("Dispatch Case", case.name, {
                "status": "Draft",
                "discount_approval_status": "Rejected",
            })
            _create_task(
                kind="Order entry",
                subject=f"Discount rejected — revise: {case.name} — {case.customer}",
                case=case,
                assignee="team-order-create@internal",
                description="Discount request was rejected by Directors. Please open the Dispatch Case, revise item prices, and save again.",
            )


# ================================================================
# Helper functions
# ================================================================

def _item_has_serial(item_code):
    return frappe.db.get_value("Item", item_code, "has_serial_no") == 1

def _all_case_items(case):
    return [
        (r.item_code, r.dispatched_qty, r.serial_no, r.batch_no)
        for r in case.case_items
    ]

def _create_transfer_se(case, source_wh, target_wh, items, purpose):
    se = frappe.get_doc({
        "doctype": "Stock Entry",
        "stock_entry_type": purpose,
        "purpose": purpose,
        "company": frappe.defaults.get_defaults().get("company"),
        "items": [
            {
                "item_code": item_code,
                "qty": qty,
                "s_warehouse": source_wh,
                "t_warehouse": target_wh,
                "serial_no": serial_no or "",
                "batch_no": batch_no or "",
            }
            for item_code, qty, serial_no, batch_no in items
            if (qty or 0) > 0
        ],
    })
    se.insert(ignore_permissions=True)
    se.submit()
    return se

def _consume_items(case, items):
    se = frappe.get_doc({
        "doctype": "Stock Entry",
        "stock_entry_type": "Material Issue",
        "purpose": "Material Issue",
        "company": frappe.defaults.get_defaults().get("company"),
        "items": [
            {
                "item_code": item_code,
                "qty": qty,
                "s_warehouse": case.client_location_warehouse,
                "serial_no": serial_no or "",
                "batch_no": batch_no or "",
            }
            for item_code, qty, serial_no, batch_no in items
            if (qty or 0) > 0
        ],
    })
    se.insert(ignore_permissions=True)
    se.submit()
    frappe.db.set_value("Dispatch Case", case.name, "consumption_stock_entry", se.name)

def _create_sales_invoice(case):
    si = frappe.get_doc({
        "doctype": "Sales Invoice",
        "customer": case.customer,
        "update_stock": 0,
        "items": [
            {
                "item_code": r.item_code,
                "qty": r.used_qty,
                "rate": r.unit_price * (1 - (r.discount_pct or 0) / 100),
            }
            for r in case.case_items if (r.used_qty or 0) > 0
        ],
    })
    si.insert(ignore_permissions=True)
    frappe.db.set_value("Dispatch Case", case.name, "sales_invoice", si.name)

def _create_task(kind, subject, case, assignee, description="", link_field=None):
    existing = frappe.db.exists(
        "Task",
        {"dispatch_case": case.name, "task_kind": kind,
         "status": ["not in", ["Completed", "Cancelled"]]}
    )
    if existing:
        return frappe.get_doc("Task", existing)
    t = frappe.get_doc({
        "doctype": "Task",
        "subject": subject,
        "task_kind": kind,
        "task_access_policy": kind,
        "dispatch_case": case.name,
        "customer": case.customer,
        "description": description,
        "_assign": frappe.json.dumps([assignee]),
    })
    t.insert(ignore_permissions=True)
    if link_field:
        frappe.db.set_value("Dispatch Case", case.name, link_field, t.name)
    return t

def _create_or_update_debt_collection_task(case, outstanding, invoice_name):
    existing = frappe.db.get_value(
        "Task",
        {"customer": case.customer, "task_kind": "Debt Collection",
         "status": ["not in", ["Completed", "Cancelled"]]},
        "name"
    )
    invoice_row = {
        "dispatch_case": case.name,
        "sales_invoice": invoice_name,
        "invoice_amount": frappe.db.get_value("Sales Invoice", invoice_name, "grand_total") or 0,
        "paid_amount": 0,
        "outstanding_amount": outstanding,
    }
    if existing:
        t = frappe.get_doc("Task", existing)
        t.append("open_invoices", invoice_row)
        t.total_outstanding = sum((r.outstanding_amount or 0) for r in t.open_invoices)
        t.save(ignore_permissions=True)
    else:
        t = frappe.get_doc({
            "doctype": "Task",
            "subject": f"Debt Collection: {case.customer}",
            "task_kind": "Debt Collection",
            "task_access_policy": "Debt Collection",
            "customer": case.customer,
            "total_outstanding": outstanding,
            "open_invoices": [invoice_row],
            "_assign": frappe.json.dumps(["team-finance@internal"]),
        })
        t.insert(ignore_permissions=True)

_run()
```

### Script 9.4 — Task: Before Save — payment recording on Debt Collection task

**Trigger:** DocType Event → `Task` → `Before Save`

Add this logic to the same Before Save script (Script 9.2), or as a separate script.

```python
import frappe

def _run():
    before = doc.get_doc_before_save()
    before_payment = (before.new_payment_amount if before else None) or 0

    # Only act when a new payment amount is entered (field changed from blank/zero)
    if doc.task_kind != "Debt Collection":
        return
    if not (doc.new_payment_amount or 0) > 0:
        return
    if (doc.new_payment_amount or 0) == before_payment:
        return  # No change

    amount = doc.new_payment_amount
    method = doc.payment_method or "Cash"
    ref = doc.payment_reference or ""

    # FIFO allocation: fill allocated_now from oldest to newest using remaining balance
    remaining = amount
    for row in sorted(doc.open_invoices, key=lambda r: r.sales_invoice):
        to_apply = min(remaining, row.outstanding_amount or 0)
        row.allocated_now = to_apply
        remaining -= to_apply
        if remaining <= 0:
            break

    # Apply allocations: reduce outstanding on each invoice row
    for row in doc.open_invoices:
        apply = row.allocated_now or 0
        if apply > 0:
            row.paid_amount = (row.paid_amount or 0) + apply
            row.outstanding_amount = (row.outstanding_amount or 0) - apply
            row.allocated_now = 0

    doc.total_outstanding = sum((r.outstanding_amount or 0) for r in doc.open_invoices)

    # Log to payment history
    doc.append("payment_history", {
        "payment_date": frappe.utils.now_datetime(),
        "amount": amount,
        "method": method,
        "reference": ref,
    })

    # Schedule Payment Entry creation in after_save (store data in a temp flag)
    doc._pending_payment = {
        "amount": amount,
        "method": method,
        "reference": ref,
        "allocations": [
            {"sales_invoice": r.sales_invoice, "amount": r.paid_amount}
            for r in doc.open_invoices if (r.allocated_now or 0) == 0
            # Note: rows that had allocated_now > 0 have now been zeroed above
            # Recompute: use the payment_history last entry cross-referencing open_invoices
        ],
    }

    # Clear the input fields for next payment
    doc.new_payment_amount = 0
    doc.payment_method = ""
    doc.payment_reference = ""

    # Auto-complete if fully paid
    if doc.total_outstanding <= 0:
        doc.status = "Completed"

_run()
```

### Script 9.5 — Task: After Save — create Payment Entry from Debt Collection task

**Trigger:** DocType Event → `Task` → `After Save`

Add this to the existing After Save script (Script 9.3).

```python
import frappe

def _run():
    # Payment Entry creation for Debt Collection task
    if doc.task_kind != "Debt Collection":
        return

    pending = getattr(doc, "_pending_payment", None)
    if not pending or not pending.get("amount"):
        return

    # Create Payment Entry as draft (Accounting will submit)
    pe = frappe.get_doc({
        "doctype": "Payment Entry",
        "payment_type": "Receive",
        "party_type": "Customer",
        "party": doc.customer,
        "paid_amount": pending["amount"],
        "received_amount": pending["amount"],
        "mode_of_payment": pending["method"],
        "reference_no": pending["reference"],
        "reference_date": frappe.utils.today(),
        "company": frappe.defaults.get_defaults().get("company"),
        "paid_to": _get_account_for_method(pending["method"]),
    })
    pe.insert(ignore_permissions=True)

    # Update last payment_history row with payment_entry link
    if doc.payment_history:
        last = doc.payment_history[-1]
        frappe.db.set_value("Debt Collection Payment", last.name, "payment_entry", pe.name)

    # Create Distribute Payment task
    t = frappe.get_doc({
        "doctype": "Task",
        "subject": f"Distribute Payment: {doc.customer} — {pending['amount']} AMD",
        "task_kind": "Distribute Payment",
        "task_access_policy": "Distribute Payment",
        "customer": doc.customer,
        "description": (
            f"Amount: {pending['amount']} AMD\n"
            f"Method: {pending['method']}\n"
            f"Reference: {pending['reference']}\n"
            f"Action: {'Take cash to bank' if pending['method'] == 'Cash' else 'Verify transfer to correct account'}."
        ),
        "_assign": frappe.json.dumps(["team-finance@internal"]),
    })
    t.insert(ignore_permissions=True)

def _get_account_for_method(method):
    # Map payment method to ERPNext account name. Adjust to your chart of accounts.
    mapping = {
        "Cash": "Cash - Inmed",
        "Bank Transfer": "Bank - Inmed",
        "Card": "Bank - Inmed",
    }
    return mapping.get(method, "Cash - Inmed")

_run()
```

### Script 9.6 — Task: After Save — create advance Payment Entry from Payment Received task

**Trigger:** DocType Event → `Task` → `After Save`

Add to the After Save script (Script 9.3).

```python
import frappe

def _run():
    before = doc.get_doc_before_save()
    before_status = before.status if before else None
    is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

    if not (is_becoming_completed and doc.task_kind == "Payment Received"):
        return
    if not (doc.new_payment_amount or 0) > 0:
        return

    pe = frappe.get_doc({
        "doctype": "Payment Entry",
        "payment_type": "Receive",
        "party_type": "Customer",
        "party": doc.customer,
        "paid_amount": doc.new_payment_amount,
        "received_amount": doc.new_payment_amount,
        "mode_of_payment": doc.payment_method or "Cash",
        "reference_no": doc.payment_reference or "",
        "reference_date": frappe.utils.today(),
        "company": frappe.defaults.get_defaults().get("company"),
        # No invoice references = Customer Advance
    })
    pe.insert(ignore_permissions=True)

    # If linked to a Dispatch Case, record prepaid amount there
    if doc.dispatch_case:
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {
            "prepaid_amount": doc.new_payment_amount,
            "prepaid_payment_entry": pe.name,
        })

    # Update any existing Debt Collection task for this customer with available credit
    existing_dc = frappe.db.get_value(
        "Task",
        {"customer": doc.customer, "task_kind": "Debt Collection",
         "status": ["not in", ["Completed", "Cancelled"]]},
        "name"
    )
    if existing_dc:
        dc_task = frappe.get_doc("Task", existing_dc)
        dc_task.available_advance_credit = (
            (dc_task.available_advance_credit or 0) + doc.new_payment_amount
        )
        dc_task.save(ignore_permissions=True)

_run()
```

---

## 10) Dispatch Case submission — create initial Pack task

When no discount is present, submitting the Dispatch Case should directly create the Pack task. This requires a **Before Submit** server script on `Dispatch Case`.

**Trigger:** DocType Event → `Dispatch Case` → `Before Submit`

```python
import frappe

def _run():
    if doc.status not in ("Draft", "Confirmed"):
        frappe.throw("Cannot submit a Dispatch Case that is not in Draft or Confirmed state.")

    # Verify items are present
    if not doc.case_items:
        frappe.throw("Add at least one item before submitting.")

    # Set status to Confirmed if not already (no discount path)
    if doc.status == "Draft":
        doc.status = "Confirmed"

    # Create Pack task
    existing = frappe.db.exists(
        "Task",
        {"dispatch_case": doc.name, "task_kind": "Pack / prepare items",
         "status": ["not in", ["Completed", "Cancelled"]]}
    )
    if not existing:
        t = frappe.get_doc({
            "doctype": "Task",
            "subject": f"Pack: {doc.name} — {doc.customer}",
            "task_kind": "Pack / prepare items",
            "task_access_policy": "Pack / prepare items",
            "dispatch_case": doc.name,
            "customer": doc.customer,
            "description": (
                f"Pack for delivery to: {doc.customer}\n"
                f"Destination: {doc.client_location_warehouse}\n"
                f"Items:\n" +
                "\n".join(
                    f"- {r.item_code} x{r.dispatched_qty}"
                    for r in doc.case_items
                )
            ),
            "_assign": frappe.json.dumps(["team-inventory@internal"]),
        })
        t.insert(ignore_permissions=True)
        doc.pack_task = t.name

_run()
```

---

## 11) Workspace shortcuts

Add these shortcuts to the relevant workspace for each role's task inbox. Use the existing workspace setup pattern from Doc 13A.

### Shortcuts to add

| Label | DocType | Filter | For role |
|---|---|---|---|
| VIEW: My Order Entry Tasks | Task | `task_kind = Order entry, status not in Completed,Cancelled` | Order Accepting / Order Creating |
| VIEW: Pack Tasks | Task | `task_kind = Pack / prepare items, status not in Completed,Cancelled` | Inventory |
| VIEW: Delivery Tasks | Task | `task_kind = Delivery, status not in Completed,Cancelled` | Delivery Driver |
| VIEW: Return Pickup Tasks | Task | `task_kind = Pickup Returns, status not in Completed,Cancelled` | Delivery Driver, Returns |
| VIEW: Returns Inspection Tasks | Task | `task_kind = Returns processing / verification, status not in Completed,Cancelled` | Returns |
| VIEW: Restock Tasks | Task | `task_kind = Returns restocking, status not in Completed,Cancelled` | Returns |
| VIEW: Invoice Tasks | Task | `task_kind = Invoice preparation / create invoice, status not in Completed,Cancelled` | Accounting |
| VIEW: Debt Collection Tasks | Task | `task_kind = Debt Collection, status not in Completed,Cancelled` | Finance |
| VIEW: Payment Received Tasks | Task | `task_kind = Payment Received, status not in Completed,Cancelled` | Finance |
| VIEW: Distribute Payment Tasks | Task | `task_kind = Distribute Payment, status not in Completed,Cancelled` | Finance |
| VIEW: Discount Approval Tasks | Task | `task_kind = Discount Approval, status not in Completed,Cancelled` | Directors |
| VIEW: All Dispatch Cases | Dispatch Case | *(no filter)* | Directors, Coordinators |

---

## 12) Testing checklist

Work through this checklist in order after completing all setup steps.

### 12.1 Order creation and discount flow

- [ ] Log in as an `Ops - Order Accepting` user
- [ ] Create an `Order entry` task assigned to the Order Creation Team user
- [ ] Log in as an `Ops - Order Creating` user
- [ ] Assign the task to yourself; create a new Dispatch Case with 2 items, one with `discount_pct = 10`
- [ ] Save (not submit) the Dispatch Case
- [ ] Expected: Case status = `Awaiting Approval`; a `Discount Approval` task appears in Directors inbox
- [ ] Log in as `Ops - Directors`; find the Discount Approval task; set `Approval Outcome = Rejected`; complete task
- [ ] Expected: Case status = `Draft`; a new `Order entry` task appears for Order Creation Team with "Discount rejected" note
- [ ] Log in as Order Creating; fix the price (remove discount); save
- [ ] Expected: no new Discount Approval task created (no discount)
- [ ] Submit the Dispatch Case
- [ ] Expected: Case status = `Confirmed`; `Pack / prepare items` task in Inventory inbox

### 12.2 Pack, pickup, and delivery (no return)

- [ ] Log in as `Ops - Inventory`; find the Pack task
- [ ] Attempt to complete without filling serial/batch → must fail with error
- [ ] Open the Dispatch Case link; fill `serial_no` / `batch_no` on all items; save
- [ ] Complete the Pack task
- [ ] Expected: Stock Entry (Main → Delivery In-Transit) submitted; Case status = `Packed`; `Delivery` task in Delivery Team inbox
- [ ] Log in as `Delivery Driver`; find the Delivery task
- [ ] Change `delivery_status` to `Picked Up`; save
- [ ] Expected: Case status = `In Transit`; no SE fires
- [ ] Change `delivery_status` to `Delivered` without attaching a photo → must fail
- [ ] Attach a photo; change to `Delivered`; fill Handover Note; save
- [ ] Expected (if `return_expected = No`): Consumption SE submitted; draft Sales Invoice created; `Invoice preparation` task in Accounting inbox; Case status = `Invoice Pending`
- [ ] Expected: Delivery Photo also appears on the Dispatch Case form

### 12.3 Return flow

- [ ] Create a new Dispatch Case with `return_expected = Yes`; complete through delivery
- [ ] Expected after Delivered: Case status = `Awaiting Return Pickup`; `Pickup Returns` (waiting) task in Returns inbox
- [ ] Log in as `Ops - Returns`; fill `return_pickup_driver` and `scheduled_return_date`; complete the waiting task
- [ ] Expected: Case status = `Return Pickup Scheduled`; `Pickup Returns` (active) task assigned to named driver
- [ ] Log in as driver; change `pickup_status` to `Picked Up`
- [ ] Expected: SE (Client WH → Return Pickup In-Transit) submitted; Case status = `Return In Transit`
- [ ] Change `pickup_status` to `Returned to Warehouse` without photo → must fail
- [ ] Attach photo; change to `Returned to Warehouse`; save
- [ ] Expected: SE (Return Pickup In-Transit → Returns WH) submitted; `Returns Inspection` task created; Case status = `Returns Received`
- [ ] Log in as `Ops - Returns`; find inspection task; attempt to complete without filling `returned_qty` → must fail
- [ ] Open Dispatch Case; fill `returned_qty` and `lost_damaged_qty`; save; confirm `used_qty` is correct
- [ ] Complete the inspection task
- [ ] Expected: Consumption SE submitted for used qty; draft Sales Invoice created for used items; `Invoice preparation` task created; if returned_qty > 0: `Returns restocking` task created
- [ ] Complete the Restock task
- [ ] Expected: SE (Returns WH → Main WH) submitted for returned items

### 12.4 Invoicing and payment

- [ ] Log in as `Ops - Accounting`; find the Invoice task; open the linked draft Sales Invoice
- [ ] Verify `Update Stock` is unchecked; verify quantities match `used_qty` from Case Items
- [ ] Submit the Sales Invoice; complete the task
- [ ] Expected (if prepaid = 0): `Debt Collection` task created/updated in Finance inbox; Case status = `Payment Pending`
- [ ] Log in as `Ops - Finance`; open the Debt Collection task
- [ ] Confirm the open invoices table shows the correct case and outstanding amount
- [ ] Enter a payment amount and payment method; save
- [ ] Expected: FIFO allocation applied; Payment Entry (draft) auto-created; `Distribute Payment` task created; `new_payment_amount` cleared
- [ ] Record a second partial payment; save
- [ ] Expected: payment history grows; outstanding decreases
- [ ] Record final payment covering remaining balance; save
- [ ] Expected: total_outstanding = 0; task auto-completes; Case status = `Closed`

### 12.5 Advance payment

- [ ] Log in as `Ops - Finance`; create a `Payment Received` task manually for a customer
- [ ] Fill customer, amount, payment method; complete the task
- [ ] Expected: advance Payment Entry (draft) created in ERPNext; if a Debt Collection task exists for that customer, its `available_advance_credit` increases

### 12.6 Permissions check

- [ ] A `Delivery Driver` user cannot see Discount Approval tasks or Debt Collection tasks
- [ ] A `Delivery Driver` user cannot open a Dispatch Case (no access)
- [ ] An `Ops - Inventory` user cannot complete a Delivery task (wrong role — task governance blocks it)
- [ ] An `Ops - Finance` user cannot open a Payment Entry form (no permission on Payment Entry DocType)

---

## 13) Important notes for production

1. **Team user emails** — Replace all `team-*@internal` placeholder emails in the server scripts with the actual team user emails you created in Step 3.2.

2. **Account names in payment scripts** — The `_get_account_for_method()` helper uses `Cash - Inmed` and `Bank - Inmed`. Verify these match your actual ERPNext account names.

3. **Collection Set child table field names** — The `Load from Template` client script uses `items`, `item`, `qty`, `rate`. Confirm these match the actual field names in `Collection Set` from Doc 11A.

4. **Stock Entry valuation** — The SE helper does not set `valuation_rate`. ERPNext will use the item's configured rate (FIFO/FEFO moving average). This is correct; do not set manual rates.

5. **idempotency** — All `_create_task()` calls check for existing open tasks before creating a new one. This prevents duplicate tasks if a script re-runs.

6. **Cancellation / error handling** — These scripts do not implement cancellation flows (e.g., aborted deliveries, cancelled orders). Those use the existing `Return to warehouse (aborted delivery / cancelled order)` task kind and are handled separately.
