# Doc 09A — Selling: Standard Orders (No Return Expected) (Implementation / ERPNext Setup Guide)

## 1) Purpose
This is a **step-by-step ERPNext setup guide** to implement the operational rules defined in:
- **Doc 09 — Selling: Standard Orders (No Return Expected) (Operational)**

This guide implements:
- Standard Sales flow: Sales Order → dispatch staging → delivery → Sales Invoice → Payment
- The required warehouse rules:
  - standard sales uses `Main - WH` and `Delivery In-Transit - WH` only
  - standard sales must not use client location warehouses (`Clients - WH`)
- Discount approvals (director hard gate before delivery)
- Prepaid orders (payment confirmation gate before dispatch)
- Debt threshold escalation (Debt Collection task for directors)
- “Distribute Payment” tasks for director oversight after receiving money

---

## 2) Prerequisites (must be done first)
Do not start Doc 09A until these are done:

- Doc 03A — roles and permissions exist.
- Doc 04A — Customer debt threshold field exists:
  - `Customer.debt_threshold_amd`
  - optional Sales Order / Sales Invoice context fields:
    - `hospital`, `hospital_branch`, `doctor_name`
- Doc 05A — warehouses exist:
  - `Main - WH`
  - `Delivery In-Transit - WH`
  - `Returns - WH` (needed for aborted deliveries / cancellations in transit)
- Doc 06A — item tracking is correct (batch/expiry/serial where required) and FEFO warning exists.
- Doc 10A — Task system exists with Task Kinds and Task Access Policies, including:
  - `Discount Approval`
  - `Debt Collection`
  - `Distribute Payment`
  - `Delivery`
  - `Return drop-off at warehouse`
  - `Returns processing / verification`

Also confirm approval fields exist on `Task` (if you already did Doc 07A, these already exist):
- `approval_outcome` (Select: `Approved` / `Rejected`)
- `approval_note` (Small Text)

You should do Doc 09A as a user with:
- `System Manager`
- `Stock Manager`
- `Accounts Manager`

---

## 3) Roles and permissions (who can do what)
Doc 09 separation-of-duties:
- Order team creates Sales Orders.
- Inventory/dispatch posts stock staging and delivery stock issue.
- Accounting creates Sales Invoices and records payments.
- Directors approve discounts and handle debt escalation.

### 3.1 Role checklist (names used in these docs)
Confirm these roles exist (Doc 03A):
- `Ops - Order Accepting`
- `Ops - Inventory`
- `Ops - Delivery`
- `Ops - Accounting`
- `Ops - Directors`
- `Delivery Driver`

### 3.2 Permission baseline (Role Permission Manager)
1) Open `Role Permission Manager`.
2) Configure these DocTypes (minimum):

For DocType: `Sales Order`
- `Ops - Order Accepting`:
  - Read, Write, Create
  - Submit: ON
  - Cancel: ON
- `Ops - Accounting`:
  - Read
- `Ops - Directors`:
  - Read
  - Cancel: ON

For DocType: `Stock Entry`
- `Ops - Inventory` and/or `Ops - Delivery`:
  - Read, Write, Create, Submit
- `Delivery Driver`:
  - No access

For DocType: `Delivery Note`
- `Ops - Inventory` and/or `Ops - Delivery`:
  - Read, Write, Create, Submit
- `Delivery Driver`:
  - No access

For DocType: `Sales Invoice`
- `Ops - Accounting`:
  - Read, Write, Create, Submit

For DocType: `Payment Entry`
- `Ops - Accounting`:
  - Read, Write, Create, Submit

Notes:
- Drivers must only work with `Task` and attachments (Doc 03).

---

## 4) Pricing setup (base prices + price overrides)
Doc 09 pricing model:
- Base price comes from a standard selling price list.
- Negotiated client special prices are maintained as a Price Override List.
- Discounts are ad-hoc deviations and require director approval.

### 4.1 Create the base selling price list (required)
1) Open `Price List`.
2) Click `New`.
3) Create:
   - Price List Name: `Standard Selling`
   - Selling: ON
   - Currency: `AMD`
4) Save.

### 4.2 Populate base item prices (sample data for testing)
1) Open `Item Price`.
2) Create base prices in `Standard Selling`:

Sample prices:
- Item Code: `IMP-001` Price List: `Standard Selling` Rate: `20000`
- Item Code: `TOOL-001` Price List: `Standard Selling` Rate: `90000`
- Item Code: `CONS-001` Price List: `Standard Selling` Rate: `15000`

Save each.

### 4.3 Create the Price Override List (client special prices)
Implementation decision:
- Use ERPNext `Item Price` records with **Customer filled** as the canonical override list.

1) Open `Item Price`.
2) Click `New`.
3) Create a client override example:
   - Item Code: `IMP-001`
   - Price List: `Standard Selling`
   - Customer: `D001 — Dr. Example` (sample)
   - Rate: `18000`
4) Save.

### 4.4 Create a fast lookup view for price overrides (required)
1) Open `Item Price` list.
2) Add filters:
   - Price List = `Standard Selling`
   - Customer is set (not empty)
3) Add columns:
   - Customer
   - Item Code
   - Item Name
   - Rate
4) Save the view as: `Price Overrides — by Client`.

---

## 5) Sales Order fields required by Doc 09
### 5.1 Add prepaid fields on `Sales Order` (required)
1) Open `Customize Form`.
2) Select DocType: `Sales Order`.
3) Add custom fields:

- Label: `Is Prepaid`
  - Fieldname: `is_prepaid`
  - Fieldtype: `Check`
  - Default: Unchecked

- Label: `Prepayment Required Amount (AMD)`
  - Fieldname: `prepayment_required_amount_amd`
  - Fieldtype: `Currency`
  - Depends On: `eval:doc.is_prepaid==1`
  - Mandatory Depends On: `eval:doc.is_prepaid==1`

- Label: `Prepayment Payment Entry`
  - Fieldname: `prepayment_payment_entry`
  - Fieldtype: `Link`
  - Options: `Payment Entry`
  - Depends On: `eval:doc.is_prepaid==1`

4) Save.

### 5.2 Add discount approval fields on `Sales Order` (required)
In the same `Customize Form` → `Sales Order`, add:

- Label: `Discount Approval Status`
  - Fieldname: `discount_approval_status`
  - Fieldtype: `Select`
  - Options (one per line):
    - Not Required
    - Pending
    - Approved
    - Rejected
  - Default: `Not Required`
  - Read Only: ON

- Label: `Discount Approval Task`
  - Fieldname: `discount_approval_task`
  - Fieldtype: `Link`
  - Options: `Task`
  - Read Only: ON

- Label: `Discount Approval Note`
  - Fieldname: `discount_approval_note`
  - Fieldtype: `Small Text`
  - Read Only: ON

- Label: `Manual Pricing Reason`
  - Fieldname: `manual_pricing_reason`
  - Fieldtype: `Small Text`

4) Save.

Operational rule implemented later by scripts:
- If any discount exists, the system sets status to `Pending` and creates/maintains a `Discount Approval` task.

---

## 6) Task fields needed for standard sales gates
Doc 09 requires:
- Delivery driver attaches Warehouse Pickup Photo before leaving `Main - WH`.
- For aborted deliveries / cancellations in transit, driver must attach warehouse drop-off photo.

### 6.1 Add Task attachment fields (required)
1) Open `Customize Form`.
2) Select DocType: `Task`.
3) Add fields:

- Label: `Warehouse Pickup Photo`
  - Fieldname: `warehouse_pickup_photo`
  - Fieldtype: `Attach`

- Label: `Warehouse Drop-off Photo`
  - Fieldname: `warehouse_dropoff_photo`
  - Fieldtype: `Attach`

4) Save.

### 6.2 Add a Payment Entry link on Task (required for Distribute Payment tasks)
1) Open `Customize Form`.
2) Select DocType: `Task`.
3) Add field:

- Label: `Payment Entry`
  - Fieldname: `payment_entry`
  - Fieldtype: `Link`
  - Options: `Payment Entry`

4) Save.

### 6.3 Add approval outcome fields on Task (required for approvals)
Doc 09 uses Director-owned approval tasks (Discount Approval).

If your `Task` DocType does not already have approval fields:

1) Open `Customize Form`.
2) Select DocType: `Task`.
3) Add fields:

- Label: `Approval Outcome`
  - Fieldname: `approval_outcome`
  - Fieldtype: `Select`
  - Options (one per line):
    - Approved
    - Rejected

- Label: `Approval Note`
  - Fieldname: `approval_note`
  - Fieldtype: `Small Text`

4) Save.

---

## 7) Stock movement implementation for standard sales (required)
Doc 09 stock rule:
- Stage outgoing packages into `Delivery In-Transit - WH` before driver leaves.
- Delivery completion removes stock from company-owned warehouses.

Implementation decision (go-live safe):
- Use **two steps**:
  1) `Stock Entry (Material Transfer)` to stage:
     - `Main - WH` → `Delivery In-Transit - WH`
  2) `Delivery Note` to deliver:
     - source warehouse = `Delivery In-Transit - WH`

### 7.1 Create a custom field to link staging Stock Entry to a Sales Order
1) Open `Customize Form`.
2) Select DocType: `Stock Entry`.
3) Add a field:

- Label: `Sales Order`
  - Fieldname: `sales_order`
  - Fieldtype: `Link`
  - Options: `Sales Order`

4) Save.

### 7.2 Dispatch staging procedure (Inventory / Delivery coordinator)
1) Ensure a Sales Order exists and is submitted.
2) Create a `Delivery` Task for the driver:
   - Task Kind: `Delivery`
   - Link fields:
     - Sales Order = your Sales Order
     - Customer = the Customer
   - Assigned To: the driver
   - Task Access Policy: `Delivery`
3) Driver arrives at warehouse and attaches `Warehouse Pickup Photo` to that Delivery Task.
4) Create Stock Entry:
   1) Open `Stock Entry` → `New`.
   2) Stock Entry Type: `Material Transfer`.
   3) Set:
      - From Warehouse: `Main - WH`
      - To Warehouse: `Delivery In-Transit - WH`
      - Sales Order: select the Sales Order
   4) Add items exactly matching what will be delivered.
   5) For tracked items: select batch/serials correctly.
   6) Save.
   7) Submit.

Expected result:
- Stock is visible in `Delivery In-Transit - WH`.

### 7.3 Delivery completion procedure (Inventory / Delivery coordinator)
1) Open the Sales Order.
2) Click `Create` → `Delivery Note`.
3) On Delivery Note:
   - Set Warehouse = `Delivery In-Transit - WH`
4) Ensure item quantities match staged stock.
5) Save.
6) Submit.

## 8) Automation and governance (Server Scripts)
These scripts implement Doc 09 gates and escalation tasks.

### 8.2 Server Script: create/maintain Discount Approval task + set status on Sales Order
Policy implemented:
- Any discount requires director approval.
- Approval is a hard gate before dispatch/delivery.

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - Script Type: `DocType Event`
   - Reference DocType: `Sales Order`
   - DocType Event: `Before Save`
4) Paste:

```python
import json

import frappe

DIRECTOR_ROLE = "Ops - Directors"

def assign_single_owner(task_name, user):
    # Doc 10: one accountable owner.
    # Use direct DB updates so assignment works even when Task edits are restricted by Doc 10A.
    frappe.db.set_value("Task", task_name, "_assign", json.dumps([user]), update_modified=False)

    # Cancel any other open ToDo assignments for this Task.
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

    # Ensure an open ToDo exists for the assignee.
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
    # If staff directly edits Rate, it can diverge from price_list_rate in a way
    # that is NOT explained by discount_percentage.
    price_list_rate = float(row.get("price_list_rate") or 0)
    discount_pct = float(row.get("discount_percentage") or 0)
    rate = float(row.get("rate") or 0)

    expected = price_list_rate * (1 - (discount_pct / 100.0))

    # Allow small rounding differences.
    return abs(rate - expected) > 0.01

def has_discount(doc):
    # Go-live rule: do not use header-level additional discount.
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

    # If discount is removed, cancel any open Discount Approval tasks linked to this Sales Order.
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
        # Use db updates (not Task.save) to avoid being blocked by Doc 10A team-edit enforcement.
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

    return

# Discount/manual pricing exists.
# Preserve Approved/Rejected if the discount terms are unchanged.
if before and before.get("discount_approval_status") in ("Approved", "Rejected"):
    before_sig = discount_signature(before)
    after_sig = discount_signature(doc)

    if before_sig == after_sig:
        doc.discount_approval_status = before.discount_approval_status
        doc.discount_approval_task = before.discount_approval_task
        doc.discount_approval_note = before.discount_approval_note
        return

# Otherwise: discount terms were introduced or changed, so approval is required.
doc.discount_approval_status = "Pending"
doc.discount_approval_task = None
doc.discount_approval_note = None

# If discount exists, ensure exactly 1 open Discount Approval task exists for this Sales Order.

# Manual pricing governance:
# - Only Accounting/Directors may do manual rate override.
# - Manual pricing requires a reason.
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
    return

subject = f"Discount Approval — SO {doc.name}"

task = frappe.new_doc("Task")
task.subject = subject
task.status = "Open"
task.task_kind = "Discount Approval"

# Task visibility (Doc 10A pattern)
task.task_access_policy = "Discount Approval"

# Link-back fields
# These fields exist if you implemented Doc 10A.
task.sales_order = doc.name
task.customer = doc.customer

task.insert(ignore_permissions=True)

# Assign to exactly one director (Doc 10: one accountable owner)
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

assigned_director = director_users[0]
assign_single_owner(task.name, assigned_director)

doc.discount_approval_task = task.name
```

5) Save.

### 8.3 Server Script: when Discount Approval task is completed, write result to Sales Order
1) Open `Server Script`.
2) Click `New`.
3) Set:
   - Script Type: `DocType Event`
   - Reference DocType: `Task`
   - DocType Event: `Before Save`
4) Paste:

```python
before = doc.get_doc_before_save()
before_status = before.status if before else None

is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

if not is_becoming_completed:
    return

if doc.task_kind != "Discount Approval":
    return

if not doc.sales_order:
    frappe.throw("Discount Approval task must be linked to a Sales Order.")

# Requires these Task fields (created in Doc 07A):
# - approval_outcome: Approved/Rejected
# - approval_note: free text
if doc.approval_outcome not in ("Approved", "Rejected"):
    frappe.throw("Approval Outcome must be set to Approved or Rejected before completing the task.")

so = frappe.get_doc("Sales Order", doc.sales_order)

so.discount_approval_status = doc.approval_outcome
so.discount_approval_note = doc.approval_note
so.discount_approval_task = doc.name

so.save(ignore_permissions=True)
```

5) Save.

### 8.4 Server Script: block dispatch staging if discount approval is missing/rejected
This blocks the stock staging step (`Main - WH` → `Delivery In-Transit - WH`).

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - Script Type: `DocType Event`
   - Reference DocType: `Stock Entry`
   - DocType Event: `Before Submit`
4) Paste:

```python
# This gate only applies to dispatch staging into Delivery In-Transit.
if doc.stock_entry_type != "Material Transfer":
    return

MAIN_WH = "Main - WH"
DELIVERY_IN_TRANSIT_WH = "Delivery In-Transit - WH"

to_wh = doc.get("to_warehouse")
from_wh = doc.get("from_warehouse")

row_targets = [(r.get("s_warehouse"), r.get("t_warehouse")) for r in (doc.get("items") or [])]

is_dispatch_staging = (
    (from_wh == MAIN_WH and to_wh == DELIVERY_IN_TRANSIT_WH)
    or any((s == MAIN_WH and t == DELIVERY_IN_TRANSIT_WH) for (s, t) in row_targets)
)

if not is_dispatch_staging:
    return

if not doc.sales_order:
    frappe.throw("Dispatch staging Stock Entry must be linked to a Sales Order.")

so = frappe.get_doc("Sales Order", doc.sales_order)

# Block if discount approval is pending/rejected.
if so.discount_approval_status in ("Pending", "Rejected"):
    frappe.throw(
        "Discount approval is required before dispatch staging. "
        "Complete the Discount Approval task (Approved) or remove the discount."
    )

# Warehouse pickup photo gate (Doc 09)
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

# Prepaid gate
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
```

5) Save.

### 8.5 Server Script: block staging into client location warehouses (required)
Doc 09 rule:
- Standard sales must never move stock into `Clients - WH`.

This script blocks Stock Entries that try to move standard sales staging into any warehouse under `Clients - WH`.

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - Script Type: `DocType Event`
   - Reference DocType: `Stock Entry`
   - DocType Event: `Validate`
4) Paste:

```python
CLIENTS_ROOT = "Clients - WH"

# Only enforce if the document is linked to a Sales Order.
if not doc.get("sales_order"):
    return

root = frappe.get_doc("Warehouse", CLIENTS_ROOT)
root_lft = int(root.lft)
root_rgt = int(root.rgt)

# Block any movement that targets a client location warehouse.
for row in (doc.items or []):
    wh = row.t_warehouse or doc.get("to_warehouse")
    if not wh:
        continue

    is_client_wh = frappe.db.exists(
        "Warehouse",
        {"name": wh, "lft": [">=", root_lft], "rgt": ["<=", root_rgt]},
    )

    if is_client_wh:
        frappe.throw("Standard sales must not move stock into client location warehouses (Clients - WH).")
```

5) Save.

### 8.6 Server Script: enforce Delivery Note issues only from `Delivery In-Transit - WH`
Doc 09 rule:
- Standard delivery completion must remove stock from company-owned warehouses.

Implementation decision:
- For standard sales, Delivery Notes must always issue from `Delivery In-Transit - WH`.

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - Script Type: `DocType Event`
   - Reference DocType: `Delivery Note`
   - DocType Event: `Before Submit`
4) Paste:

```python
DELIVERY_IN_TRANSIT_WH = "Delivery In-Transit - WH"

for row in (doc.items or []):
    if row.warehouse != DELIVERY_IN_TRANSIT_WH:
        frappe.throw(
            f"Standard sales Delivery Note must issue from {DELIVERY_IN_TRANSIT_WH}. Row warehouse is {row.warehouse or 'not set'}."
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
```

5) Save.

### 8.7 Server Script: require Warehouse Drop-off Photo to complete `Return drop-off at warehouse` tasks
Doc 09 rule:
- If a delivery is aborted / cancelled in transit, the driver must provide photo evidence at warehouse drop-off.

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - Script Type: `DocType Event`
   - Reference DocType: `Task`
   - DocType Event: `Before Save`
4) Paste:

```python
import frappe
from frappe.utils import now_datetime

before = doc.get_doc_before_save()
before_status = before.status if before else None

is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

if not is_becoming_completed:
    return

if doc.task_kind != "Return drop-off at warehouse":
    return

if not doc.warehouse_dropoff_photo:
    frappe.throw("Warehouse Drop-off Photo is required to complete this task.")

if not doc.completed_at:
    doc.completed_at = now_datetime()
```

5) Save.

---

## 9) Debt threshold escalation (Debt Collection tasks)
Doc 09 rule:
- When a client exceeds its debt threshold, a director-owned Debt Collection task must exist and reflect current debt.
- Exceedance does not automatically block delivery.

Implementation decision:
- Use a **Scheduled Server Script** that runs periodically (hourly).

### 9.1 Add Task fields used by the debt task (recommended)
1) Open `Customize Form`.
2) DocType: `Task`.
3) Add fields:

- Label: `Current Debt (AMD)`
  - Fieldname: `current_debt_amd`
  - Fieldtype: `Currency`

- Label: `Debt Threshold (AMD)`
  - Fieldname: `debt_threshold_amd`
  - Fieldtype: `Currency`

4) Save.

### 9.2 Scheduled Server Script: create/update Debt Collection tasks
1) Open `Server Script`.
2) Click `New`.
3) Set:
   - Script Type: `Scheduled`
   - Frequency: `Hourly`
4) Paste:

```python
import json

import frappe

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

def get_director_users():
    users = frappe.get_all(
        "Has Role",
        filters={"role": DIRECTOR_ROLE},
        pluck="parent",
    )
    # Remove duplicates
    return sorted(list(set(users or [])))

def get_net_receivable_amd(customer, company):
    # Net receivable = sum(debit - credit) for party ledger.
    # This includes invoices, payments, and advances in GL terms.
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

if not company:
    return

director_users = get_director_users()

if not director_users:
    return

director_users = [
    u
    for u in director_users
    if u not in ("Administrator", "Guest") and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
]

if not director_users:
    return

assigned_director = director_users[0]

customers = frappe.get_all(
    "Customer",
    filters={"disabled": 0},
    fields=["name", "customer_name", "debt_threshold_amd"],
)

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

        # Assign to exactly one director (Doc 10: one accountable owner)
        assign_single_owner(task.name, assigned_director)

    task.current_debt_amd = debt
    task.debt_threshold_amd = threshold
    task.description = f"Client debt exceeded threshold. Current debt: {debt}. Threshold: {threshold}."
    task.save(ignore_permissions=True)
```

5) Save.

---

## 10) Distribute Payment tasks (director oversight)
Doc 09 rule:
- A Director-owned `Distribute Payment` task must be created/maintained for each payment event that requires distribution.

Implementation decision:
- Create the task automatically when a Customer `Payment Entry` is submitted.

### 10.1 Server Script: on Payment Entry submit, create Distribute Payment task
1) Open `Server Script`.
2) Click `New`.
3) Set:
   - Script Type: `DocType Event`
   - Reference DocType: `Payment Entry`
   - DocType Event: `After Submit`
4) Paste:

```python
import json

import frappe

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

# Only for customer receipts
if doc.party_type != "Customer":
    return

if doc.payment_type != "Receive":
    return

director_users = frappe.get_all(
    "Has Role",
    filters={"role": DIRECTOR_ROLE},
    pluck="parent",
)

director_users = sorted(list(set(director_users or [])))

if not director_users:
    return

director_users = [
    u
    for u in director_users
    if u not in ("Administrator", "Guest") and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
]

if not director_users:
    return

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

if existing:
    return

task = frappe.new_doc("Task")
task.subject = f"Distribute Payment — PE {doc.name}"
task.status = "Open"
task.task_kind = "Distribute Payment"
task.task_access_policy = "Distribute Payment"
task.payment_entry = doc.name

task.customer = doc.party

task.insert(ignore_permissions=True)

assign_single_owner(task.name, assigned_director)
```

5) Save.

---

## 11) Standard order operating procedure (end-to-end)
### 11.1 Create Sales Order (Order team)
1) Open `Sales Order` → `New`.
2) Fill:
   - Customer
   - Delivery Date
   - Optional context (if known):
     - Hospital
     - Hospital Branch
     - Doctor Name
   - Selling Price List: `Standard Selling`
3) Add items:
   - Pick items and quantities.
   - Do not use client location warehouses.
4) Pricing:
   - If the client has a negotiated price, confirm it using `Price Overrides — by Client`.
   - If a discount is needed:
     - set per-line `Discount Percentage` (do not use header additional discount)
     - the system will create a Discount Approval task.
5) Prepaid:
   - If prepaid, set `Is Prepaid` = ON.
   - Set `Prepayment Required Amount (AMD)`.
6) Save.
7) Submit.

### 11.2 Discount approval (Directors)
If the order has a discount:
1) Open the `Discount Approval` task.
2) Set:
   - Approval Outcome: Approved / Rejected
   - Approval Note: required
3) Mark Task as Completed.

### 11.3 Dispatch staging (Inventory + Delivery)
Follow section 7.2.

### 11.4 Delivery completion (Inventory + Delivery)
Follow section 7.3.

### 11.5 Sales Invoice (Accounting)
1) Open the Delivery Note.
2) Click `Create` → `Sales Invoice`.
3) Confirm invoice prices match the Sales Order (no re-pricing).
4) Save.
5) Submit.

### 11.6 Payment collection (Accounting)
1) Record payment as `Payment Entry`.
2) If payment is an advance (prepaid before invoice), leave it unallocated until invoice exists.
3) After invoicing, allocate advances to the invoice so the invoice becomes Paid.

---

## 12) Cancellation / aborted delivery handling (required)
Doc 09 requires stage-based handling depending on where the physical goods are.

### 12.1 Cancelled before packing starts
1) Cancel the Sales Order with a short reason.
2) Cancel any open packing/dispatch/delivery Tasks linked to it.

### 12.2 Cancelled after packing but before dispatch staging
1) Cancel the Sales Order with a short reason.
2) Cancel the Delivery Task with reason “Order cancelled before pickup”.
3) Inventory team returns packed items to shelf (no stock movement needed if you never staged).

### 12.3 Cancelled after dispatch staging / while in transit
Meaning:
- Stock is already in `Delivery In-Transit - WH` and physically with delivery.

Operational steps:
1) Cancel the Sales Order with a short reason.
2) Driver brings the package back to warehouse.
3) Create a `Return drop-off at warehouse` task for the driver:
   - Open `Task` → `New`
   - Subject: `Return drop-off — SO <SO-NAME>`
   - Task Kind: `Return drop-off at warehouse`
   - Task Access Policy: `Return drop-off at warehouse`
   - Sales Order: select the cancelled Sales Order
   - Customer: select the same Customer
   - Assigned To: the driver
   - Save
4) Driver attaches `Warehouse Drop-off Photo` on that task.
5) Driver completes the task.
6) Inventory/Returns team creates Stock Entry (Material Transfer) to return stock to warehouse control:
   - From Warehouse: `Delivery In-Transit - WH`
   - To Warehouse: `Returns - WH`
   - Select the correct batch/serials.
7) Returns team verifies the package and re-stocks:
   - Stock Entry (Material Transfer)
     - From Warehouse: `Returns - WH`
     - To Warehouse: `Main - WH`
8) Close/cancel any leftover Tasks linked to the cancelled order.

### 12.4 Cancelled after delivery (true return)
1) Treat as a standard-sales return exception.
2) Ensure stock re-enters through controlled verification (Doc 05 returns principles).
3) Accounting handles credit note/refund according to accounting policy.

---

## 13) Validation checklist (must pass before go-live)
### 13.1 Warehouse rules
- Dispatch staging moves stock only `Main - WH` → `Delivery In-Transit - WH`.
- Standard sales does not move stock into `Clients - WH`.

### 13.2 Discount approval gate
- Create a Sales Order with a line discount.
- Confirm `discount_approval_status` becomes `Pending` and a Discount Approval task is created.
- Try to submit dispatch staging Stock Entry: it is blocked.
- Approve the Discount Approval task.
- Submit dispatch staging Stock Entry: it succeeds.

### 13.3 Prepaid gate
- Create a prepaid Sales Order with required amount.
- Try to stage without linked submitted Payment Entry: it is blocked.
- Link a submitted Payment Entry and stage: it succeeds.

### 13.4 Debt threshold escalation
- Set a low `debt_threshold_amd` for one customer.
- Submit an unpaid Sales Invoice to exceed the threshold.
- Wait for the scheduled script (or trigger it manually by running it once).
- Confirm one open Debt Collection task exists for that customer and shows current debt.

### 13.5 Distribute Payment tasks
- Submit a Customer Payment Entry (Receive).
- Confirm a Distribute Payment task is created and assigned to exactly one director user (the task is still visible to all directors via Task Access Policy).
