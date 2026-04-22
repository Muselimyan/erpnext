# Doc 07A — Suppliers and Procurement (Basic P2P) (Implementation / ERPNext Setup Guide)

## 1) Purpose
This is a **step-by-step setup guide** to implement the operational rules defined in:
- **Doc 07 — Suppliers and Procurement (Basic P2P) (Operational)**

This guide covers:
- Supplier master data setup (how to create clean Supplier records)
- Basic procurement flow configuration and operating procedure:
  - Purchase Order → Purchase Receipt → Purchase Invoice
- Director approval enforcement for Purchase Orders (POs)
- Governance controls so purchasing remains explainable and auditable

Non-goals:
- This guide does not implement international shipment/import tracking (Doc 07.1).
- This guide does not define reorder thresholds (Doc 08).

---

## 2) Prerequisites (must be done first)
Do not start Doc 07A until these are done:

- Doc 03A — Roles and permissions are configured.
- Doc 05A — Warehouse tree exists, and `Main - WH` exists.
- Doc 06A — Item catalog exists, and each purchasable Item (including each variant) is created.
- Doc 10A — Task system exists, including:
  - `task_kind` field on `Task`
  - `Task Access Policy` DocType + `task_access_policy` field on `Task`
  - baseline Task permissions

Also confirm Task visibility for approvals:
- Directors must be able to see Tasks with `Task Kind` = `Purchase Approval`.
- If you restrict Task visibility using Task Access Policies, Directors must have User Permission access to the `Purchase Approval` policy (Doc 03A / Doc 10A).

You should do Doc 07A as a user with:
- `System Manager`
- `Stock Manager`
- `Accounts Manager` (or equivalent accounting admin role)

---

## 3) Roles and permissions (procurement separation of duties)
Doc 07 requires separation of duties:
- Purchasing team prepares Draft PO.
- Directors approve/reject.
- Warehouse receives.
- Accounting invoices.

### 3.1 Create the procurement role (if missing)
If you do not already have a purchasing role, create one.

1) Open `Role`.
2) Click `New`.
3) Role Name: `Ops - Purchasing`
4) Save.

### 3.2 Permission setup (Role Permission Manager)
Configure permissions so users can only do the steps they own.

1) Open `Role Permission Manager`.
2) Configure at minimum the following DocTypes.

For DocType: `Purchase Order`
- `Ops - Purchasing`:
  - Read, Write, Create, Submit
  - Cancel: OFF
- `Ops - Directors`:
  - Read
  - Submit: OFF
  - Cancel: ON (Directors can cancel as a governance action)

For DocType: `Purchase Receipt`
- `Ops - Inventory` (or your warehouse role):
  - Read, Write, Create, Submit
  - Cancel: OFF

For DocType: `Purchase Invoice`
- `Ops - Accounting`:
  - Read, Write, Create, Submit
  - Cancel: OFF

For DocType: `Supplier`
- `Ops - Purchasing`:
  - Read, Write, Create
- `Ops - Accounting`:
  - Read

Save after each DocType.

Operational note:
- Director approval is enforced by a scripted gate (section 6). Directors do not need `Submit` permission on `Purchase Order`.

---

## 4) Configure foundational buying master data
### 4.1 Ensure currencies exist
Doc 07 assumption:
- Purchase currency is mostly `USD`, sometimes `EUR`.

1) Use global search to open `Currency`.
2) Confirm these exist:
   - `USD`
   - `EUR`
3) If missing, create them.

### 4.2 Payment terms templates (recommended)
Doc 07 assumption:
- Most purchasing is prepayment (often 100% in advance).

Create these templates so users select terms consistently.

1) Open `Payment Terms Template`.
2) Create `Prepayment 100%`:
   - Payment Term lines:
     - Description: `100% Advance`
     - Due Date Based On: `Days After Invoice Date`
     - Credit Days: `0`
     - Invoice Portion: `100`
3) Save.
4) Create `Prepayment 50/50`:
   - Line 1:
     - Description: `50% Advance`
     - Credit Days: `0`
     - Invoice Portion: `50`
   - Line 2:
     - Description: `50% After Receipt`
     - Credit Days: `0`
     - Invoice Portion: `50`
5) Save.

---

## 5) Supplier master data setup (Supplier)
Doc 07 rules:
- One canonical Supplier record per real supplier entity.
- Avoid duplicates.

### 5.1 Create Supplier Groups (recommended)
1) Open `Supplier Group`.
2) Create groups:
   - `Manufacturers`
   - `Distributors`
   - `Local Vendors`
3) Save each.

### 5.2 Create suppliers (step-by-step + sample data)
Create at least 3 Suppliers so you can run end-to-end tests.

#### Supplier A (USD, prepayment)
1) Open `Supplier`.
2) Click `New`.
3) Fill:
   - Supplier Name: `Medtronic Europe GmbH`
   - Supplier Group: `Manufacturers`
   - Country: `Germany`
   - Default Currency: `USD`
   - Default Payment Terms Template: `Prepayment 100%`
   - Notes: `Primary implant supplier. Orders confirmed by email.`
4) Save.
5) Add a Contact (top section `Add Contact`):
   - First Name: `Anna`
   - Last Name: `Schmidt`
   - Email: `anna.schmidt@medtronic.example`
   - Phone: `+49 30 0000 0000`
6) Save.

#### Supplier B (EUR, prepayment)
Create:
- Supplier Name: `Stryker EMEA`
- Supplier Group: `Manufacturers`
- Country: `Netherlands`
- Default Currency: `EUR`
- Default Payment Terms Template: `Prepayment 100%`
- Notes: `Orders via distributor confirmation.`

#### Supplier C (USD, distributor)
Create:
- Supplier Name: `ABC Medical Distribution LLC`
- Supplier Group: `Distributors`
- Country: `UAE`
- Default Currency: `USD`
- Default Payment Terms Template: `Prepayment 50/50`
- Notes: `Often consolidates multiple brands.`

---

## 6) Enforce PO director approval (required)
Doc 07 acceptance criteria:
- Purchase Orders cannot be sent/submitted without explicit director approval record.

Implementation decision (required):
- Use the Task system as the canonical approval record:
  - A `Purchase Approval` task is created for the PO.
  - A Director completes it with `Approved` or `Rejected`.
  - ERPNext blocks PO submission unless approval is `Approved`.

### 6.1 Add required Task fields for procurement approval
You must link the approval task to the PO and capture the approval outcome.

1) Open `Customize Form`.
2) Select DocType: `Task`.
3) Add custom fields (if missing):
   - Label: `Purchase Order`
     - Fieldname: `purchase_order`
     - Fieldtype: `Link`
     - Options: `Purchase Order`
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

### 6.2 Add required fields on Purchase Order
These fields make each purchase explainable and store the canonical approval result.

1) Open `Customize Form`.
2) Select DocType: `Purchase Order`.
3) Add custom fields:
   - Label: `Purchase Reason`
     - Fieldname: `purchase_reason`
     - Fieldtype: `Select`
     - Options (one per line):
       - Reorder (Doc 08)
       - Ad-hoc demand
       - Replacement (damaged/expired/write-off)
       - Emergency
     - Req: ON
   - Label: `Requested By`
     - Fieldname: `requested_by`
     - Fieldtype: `Link`
     - Options: `User`
     - Req: ON
   - Label: `Director Approval Status`
     - Fieldname: `director_approval_status`
     - Fieldtype: `Select`
     - Options (one per line):
       - Pending
       - Approved
       - Rejected
     - Default: `Pending`
     - Read Only: ON
   - Label: `Director Approved By`
     - Fieldname: `director_approved_by`
     - Fieldtype: `Link`
     - Options: `User`
     - Read Only: ON
   - Label: `Director Approved At`
     - Fieldname: `director_approved_at`
     - Fieldtype: `Datetime`
     - Read Only: ON
   - Label: `Director Approval Task`
     - Fieldname: `director_approval_task`
     - Fieldtype: `Link`
     - Options: `Task`
     - Read Only: ON
   - Label: `Director Approval Note`
     - Fieldname: `director_approval_note`
     - Fieldtype: `Small Text`
     - Read Only: ON
4) Save.

### 6.3 Server Script: when a Director completes the approval Task, write result to the PO
1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Task`
   - `DocType Event`: `Before Save`
4) Paste:

```python
from frappe.utils import now_datetime

before = doc.get_doc_before_save()
before_status = before.status if before else None

is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

if not is_becoming_completed:
    return

if doc.task_kind != "Purchase Approval":
    return

if not doc.purchase_order:
    frappe.throw("Purchase Approval task must be linked to a Purchase Order.")

if doc.approval_outcome not in ("Approved", "Rejected"):
    frappe.throw("Approval Outcome must be set to Approved or Rejected before completing the task.")

po = frappe.get_doc("Purchase Order", doc.purchase_order)

po.director_approval_status = doc.approval_outcome
po.director_approved_by = doc.modified_by or doc.owner
po.director_approved_at = now_datetime()
po.director_approval_task = doc.name
po.director_approval_note = doc.approval_note

po.save(ignore_permissions=True)
```

5) Save.

### 6.4 Server Script: block PO submission unless approval is Approved
1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Purchase Order`
   - `DocType Event`: `Before Submit`
4) Paste:

```python
if doc.director_approval_status != "Approved":
    frappe.throw(
        "Director approval is required before submitting the Purchase Order. "
        "Create a Purchase Approval task, get it completed as Approved, then submit."
    )
```

5) Save.

### 6.4.1 Server Script: enforce “one PO = one supplier” and “item supplier matches PO supplier”
Doc 07 rule:
- A PO must be per-supplier.
- Each item is owned by exactly one supplier (default policy), so every PO line must match the PO Supplier.

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Purchase Order`
   - `DocType Event`: `Validate`
4) Paste:

```python
if not doc.supplier:
    return

for row in (doc.items or []):
    if not row.item_code:
        continue

    suppliers = frappe.get_all(
        "Item Supplier",
        filters={"parent": row.item_code, "parenttype": "Item"},
        pluck="supplier",
    )

    suppliers = [s for s in (suppliers or []) if s]

    if len(suppliers) != 1:
        frappe.throw(
            f"Item {row.item_code} must have exactly 1 Supplier (Doc 07 policy). Found: {', '.join(suppliers) or 'none'}."
        )

    if suppliers[0] != doc.supplier:
        frappe.throw(
            f"Item {row.item_code} supplier is {suppliers[0]} but PO supplier is {doc.supplier}. Do not mix suppliers on one PO."
        )
```

5) Save.

### 6.5 Server Script: if an approved Draft PO is edited, force re-approval
Doc 07 rule:
- Any change after approval requires re-approval.

This script clears the stored approval fields if the PO is edited after being approved.

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Purchase Order`
   - `DocType Event`: `Before Save`
4) Paste:

```python
before = doc.get_doc_before_save()

if not before:
    return

if doc.docstatus != 0:
    return

was_approved = (before.director_approval_status == "Approved")

if not was_approved:
    return

# Any change after approval requires re-approval.
# This checks a minimal set of fields that represent the purchase intent.
header_changed = (
    (doc.supplier != before.supplier)
    or (doc.currency != before.currency)
    or (doc.transaction_date != before.transaction_date)
    or (doc.purchase_reason != before.purchase_reason)
    or (doc.requested_by != before.requested_by)
)

def normalize_rows(rows):
    out = []
    for r in (rows or []):
        out.append({
            "item_code": r.item_code,
            "uom": r.uom,
            "conversion_factor": r.conversion_factor,
            "qty": float(r.qty or 0),
            "rate": float(r.rate or 0),
            "schedule_date": str(r.schedule_date or ""),
        })
    return out

rows_changed = (normalize_rows(doc.items) != normalize_rows(before.items))

if header_changed or rows_changed:
    doc.director_approval_status = "Pending"
    doc.director_approved_by = None
    doc.director_approved_at = None
    doc.director_approval_task = None
    doc.director_approval_note = None

    frappe.msgprint("PO was edited after director approval. Approval was cleared and must be re-done.")
```

5) Save.

---

## 7) Purchasing operating procedure (Draft PO → Approval → Submit → Send)
### 7.1 Create a Draft PO (Ops - Purchasing)
1) Open `Purchase Order`.
2) Click `New`.
3) Fill header:
   - Supplier: choose exactly one supplier
   - Schedule Date: the expected delivery date (best current estimate)
   - Purchase Reason: choose one (required)
   - Requested By: choose the requester (required)
4) Attach supporting documents (required):
   - Supplier quotation / proforma invoice / email thread
5) Add items:
   - Only items that belong to this supplier (Doc 06 one-item → one-supplier)
   - Quantities must follow the packaging/UOM policy (Doc 06)
6) Save (leave as Draft).

Sample PO lines (for testing):
- `IMP-001` Qty `50` UOM `Nos` Rate `25` Currency `USD`
- `TOOL-001` Qty `2` UOM `Nos` Rate `120` Currency `USD`

### 7.2 Create the approval Task (Ops - Purchasing)
1) Open `Task`.
2) Click `New`.
3) Set:
   - Subject: `Purchase Approval — PO <PO-NAME>`
   - Task Kind: `Purchase Approval`
   - Task Access Policy: `Purchase Approval` (if it is not auto-filled)
   - Purchase Order: select your PO
   - Assigned To: a Director user
   - Description: include the reason, urgency, and any context
4) Save.

### 7.3 Director approves or rejects (Ops - Directors)
1) Open the Task.
2) Set `Approval Outcome`:
   - `Approved` or `Rejected`
3) Fill `Approval Note` (required operationally; always explain the decision).
4) Set Task Status = `Completed`.
5) Save.

Expected result:
- The linked Purchase Order now shows:
  - Director Approval Status = Approved/Rejected
  - Director Approved By / At filled

### 7.4 Submit and send the PO (Ops - Purchasing)
1) Open the Purchase Order.
2) Confirm `Director Approval Status` = `Approved`.
3) Click `Submit`.
   - If it fails: approval is missing or was cleared.
4) Send the PO to the supplier:
   - Use `Email` / `Print` PDF functionality.
   - Ensure the sent PDF matches the approved PO.

Rule:
- If you change anything after approval, approval is cleared and must be re-done.

---

## 8) Prepayment (current default policy)
Operational rules:
- No payment is made for a PO that is not approved.
- Proof of payment must be attached.

Procedure (Accounting):
1) Confirm the PO is approved (Director Approval Status = Approved).
2) Open `Payment Entry`.
3) Create a payment:
   - Party Type: `Supplier`
   - Party: your supplier
   - Payment Type: `Pay`
   - Paid Amount: the advance amount
   - Reference: include the PO number in the Payment Entry remarks
4) Attach bank transfer proof (required).
5) Submit.

Later, when the Purchase Invoice exists, allocate the advance payment to that invoice (standard ERPNext advance allocation workflow).

---

## 9) Receiving (Purchase Receipt = physical truth)
Operational rule:
- Stock becomes yours only through receiving.

### 9.0 Server Script: enforce receiving into `Main - WH` and require expiry on expiry-tracked batches
Doc 07 rule:
- Normal receiving destination is `Main - WH`.
- For tracked items, receiving must capture the required tracking data.

This script enforces:
- all receipt rows must land in `Main - WH`
- for items that require expiry date tracking, the selected Batch must have an expiry date

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Purchase Receipt`
   - `DocType Event`: `Before Submit`
4) Paste:

```python
MAIN_WH = "Main - WH"

for row in (doc.items or []):
    if row.warehouse != MAIN_WH:
        frappe.throw(f"Receiving must be into {MAIN_WH}. Row warehouse is {row.warehouse or 'not set'}.")

    if not row.item_code:
        continue

    item = frappe.get_doc("Item", row.item_code)

    requires_expiry = bool(item.get("has_expiry_date"))
    has_batch = bool(item.get("has_batch_no"))

    if requires_expiry and has_batch:
        if not row.batch_no:
            frappe.throw(f"Row for item {row.item_code} requires Batch + Expiry. Batch No is missing.")

        batch = frappe.get_doc("Batch", row.batch_no)
        if not batch.expiry_date:
            frappe.throw(f"Batch {row.batch_no} must have Expiry Date for item {row.item_code}.")
```

5) Save.

### 9.1 Create a Purchase Receipt from the PO (Warehouse)
1) Open the approved Purchase Order.
2) Click `Create` → `Purchase Receipt`.
3) On the Purchase Receipt:
   - Set `Set Warehouse` = `Main - WH`.
4) For each line item:
   - Enter the actual quantity that arrived.
   - For tracked items:
     - Batch/expiry items: create/select Batch and ensure expiry is set on the Batch.
     - Serial items: enter serial numbers.
5) Save.
6) Submit.

Partial delivery rule:
- Receive only what arrived.
- Keep the PO open until remaining quantities arrive or are cancelled.

---

## 10) Supplier invoice entry (Purchase Invoice = financial truth)
Accounting rule:
- The Purchase Invoice is the authoritative payable record.

### 10.0 Server Script: block `Update Stock` on Purchase Invoice (required)
Doc 07 core principle:
- Receiving is the inventory gate.

To enforce that, prevent Purchase Invoices from updating stock.

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Purchase Invoice`
   - `DocType Event`: `Before Submit`
4) Paste:

```python
if doc.get("update_stock"):
    frappe.throw("Do not use Purchase Invoice to update stock. Use Purchase Receipt for receiving (Doc 07 policy).")
```

5) Save.

### 10.1 Preferred: create Invoice from Receipt
1) Open the Purchase Receipt.
2) Click `Create` → `Purchase Invoice`.
3) Enter supplier invoice number and date.
4) Save.
5) Submit.

### 10.2 If invoice arrives before goods (allowed)
1) Open `Purchase Invoice`.
2) Click `New`.
3) Select:
   - Supplier
   - Link to the Purchase Order (if available)
4) Enter invoice number and date.
5) Ensure `Update Stock` is OFF.
6) Save and Submit.

Later, when goods arrive, receiving still happens based on physical reality.

---

## 11) Governance rules (must follow)
- Do not delete purchasing documents.
- If something is wrong, cancel with a written reason.
- Substitutions are exceptions:
  - Do not silently accept a different product as “equivalent”.

---

## 12) Validation checklist (must pass before go-live)
### 12.1 Approval gate
- Try to submit a PO without director approval: submission is blocked.
- Approve the PO via a `Purchase Approval` task: submission succeeds.
- Edit an approved Draft PO: approval fields are cleared and require re-approval.

### 12.1.1 Supplier invariants
- Create a PO for Supplier A, then add an item whose Item master Supplier is Supplier B: saving the PO is blocked.

### 12.2 Three-way truth model
- A submitted PO does not change stock balances.
- A Purchase Receipt increases stock in `Main - WH`.
- A Purchase Invoice does not increase stock unless you explicitly enable `Update Stock`.

Additional enforcement tests:
- Try to submit a Purchase Invoice with `Update Stock` enabled: submission is blocked.

### 12.3 Tracking capture
- Receive a batch+expiry item and confirm expiry exists on the Batch.
- Receive a serial-tracked item and confirm serials are captured.

### 12.3.1 Receiving destination
- Try to submit a Purchase Receipt where a row Warehouse is not `Main - WH`: submission is blocked.

### 12.4 Partial delivery
- Create a PO for Qty 100.
- Receive Qty 40.
- Confirm PO still shows remaining Qty 60 outstanding.
