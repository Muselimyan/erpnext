# Doc 08A — Reorder System (Low Stock → PO per Supplier) (Implementation / ERPNext Setup Guide)

## 1) Purpose
This is a **step-by-step ERPNext setup guide** to implement the operational rules defined in:
- **Doc 08 — Reorder System (Low Stock → PO per Supplier) (Operational)**

This guide implements:
- Item-level reorder thresholds (including variant items)
- A practical “always-available reorder list” view
- A buyer operating routine (daily + weekly)
- Governance controls for who can change thresholds
- Integration points with:
  - Doc 06 (one item → one supplier, UOM correctness)
  - Doc 07 (PO approval gate and one-supplier-per-PO rules)

Non-goals:
- This guide does not implement shipment/import tracking (Doc 07.1).

---

## 2) Prerequisites (must be done first)
Do not start Doc 08A until these are done:

- Doc 05A — Warehouse tree exists.
  - `Main - WH` exists and is where sellable stock is received.
  - `Clients - WH`, `Returns - WH`, `Return Pickup In-Transit - WH`, `Delivery In-Transit - WH` exist (Doc 05).
- Doc 06A — Item catalog is correct.
  - Each sellable stock item (and each purchasable variant) exists as its own Item.
  - UOM and conversion factors are correct.
  - Tracking flags (batch/expiry/serial) are correct.
- Doc 07A — Suppliers and purchasing controls exist.
  - Each item has exactly one Supplier.
  - PO approval gate exists.
  - Do not mix suppliers on one PO (enforced).

You should do Doc 08A as a user with:
- `System Manager`
- `Stock Manager`

---

## 3) Decide the threshold model per category (fixed defaults)
Doc 08 allows two threshold styles.
To remove reader judgment, use these defaults for go-live:

- **Fast-moving consumables**: Min/Max
- **Implants and specialized items**: ROP + Reorder Quantity

Where to implement:
- ERPNext reorder configuration is typically done via `Item Reorder` (child rows on Item), specifying:
  - Warehouse
  - Warehouse Reorder Level
  - Warehouse Reorder Qty

Operational mapping:
- If using Min/Max:
  - Set `Warehouse Reorder Level` = Min
  - Set `Warehouse Reorder Qty` = Max − Min
- If using ROP + fixed reorder qty:
  - Set `Warehouse Reorder Level` = ROP
  - Set `Warehouse Reorder Qty` = Reorder Quantity

Important operational rule from Doc 08:
- Thresholds must be configured on the **actual purchasable item**.
  - For variants: configure each variant Item, not the template.

---

## 4) Enable and configure reorder per Item (including variants)
### 4.1 Reorder thresholds must be set only for `Main - WH`
Doc 08 rule:
- The reorder list must primarily protect ability to ship from `Main - WH`.
- Hospital/returns/in-transit stock is informational only and must not be counted as available.

Implementation decision (required):
- Configure reorder rows **only** for `Main - WH`.

### 4.2 Step-by-step: set reorder values on an Item
Repeat these steps for every Item you want the reorder list to manage.

1) Open `Item`.
2) Open the target Item (example: `CONS-001`).
3) Scroll to the `Reorder` section (may be called `Item Reorder`).
4) Add a row:
   - Warehouse: `Main - WH`
   - Warehouse Reorder Level: (use the policy below)
   - Warehouse Reorder Qty: (use the policy below)
5) Save.

### 4.3 Sample threshold values (use these for initial setup)
Use these sample values so a novice can fully test the reorder list immediately.

Sample A (fast mover, Min/Max implemented as level + qty):
- Item: `CONS-001` (Gloves Box)
- Style: Min/Max
- Min: 20 boxes
- Max: 60 boxes
- ERPNext fields:
  - Reorder Level = 20
  - Reorder Qty = 40

Sample B (implant, ROP + reorder qty):
- Item: `IMP-001` (Bone Screw)
- Style: ROP
- ROP: 15 nos
- Reorder Qty: 50 nos
- ERPNext fields:
  - Reorder Level = 15
  - Reorder Qty = 50

Sample C (variant family example)
If you have a variant family (example template `SCREW-3.5` with variants by length), you must set reorder per variant:
- `SCREW-3.5-L20`: ROP 10, Qty 30
- `SCREW-3.5-L22`: ROP 8, Qty 20
- `SCREW-3.5-L24`: ROP 6, Qty 20

---

## 5) Create the “Always-Available Reorder List” (ERPNext views)
Doc 08 requirement:
- Purchasing can open a list at any time.
- The list can be grouped/filtered by supplier.

ERPNext implementation approach (go-live safe):
- Use ERPNext’s built-in `Stock Reorder` / `Material Requests` style view where available.
- If that view is not enabled in your instance, use a Saved Report / List View approach:
  - `Item` list filtered to items with reorder configured
  - combine with stock balance reports for Main - WH

Because ERPNext setups vary by version, use this fixed approach that works in all cases:

### 5.1 Create a Saved Report: Stock Balance for `Main - WH`
1) Open report `Stock Balance`.
2) Set filters:
   - Warehouse: `Main - WH`
   - Include UOM: Stock UOM
3) Save the report as: `Stock Balance — Main - WH`.

### 5.2 Create a Saved List View: Items that have reorder configured
1) Open `Item` list.
2) Apply filters:
   - Disabled = No
   - Is Stock Item = Yes
3) Add columns:
   - Item Code
   - Item Name
   - Item Group
   - Default Supplier (if available)
4) Save as: `Items — Active Stock`

Operational note:
- ERPNext does not always expose “items with reorder rows” as a direct filter. If you cannot filter on reorder rows, keep this list as your active stock catalog list, and rely on the Stock Balance report + the Reorder report (next section).

### 5.3 Use ERPNext’s Reorder tool (preferred when available)
If your ERPNext has `Stock Reorder` (or similar):
1) Use global search to find `Stock Reorder`.
2) Open it.
3) Filter Warehouse = `Main - WH`.
4) Confirm it lists items based on the reorder rows defined in section 4.

Save a view (if allowed) as: `Reorder — Main - WH`.

---

## 6) Make the reorder list groupable by supplier (required)
Doc 08 assumes:
- One item → one supplier.

Implementation rule:
- Every item included in reorder must have exactly one Supplier.

Setup procedure:
1) Open `Item`.
2) For each item that will have reorder thresholds:
   - Confirm exactly one Supplier is set in the Suppliers table.
3) Save.

Operational shortcut:
- When reviewing reorder items, use the Supplier filter/grouping where available.
- When building POs, always create **one PO per supplier** (Doc 07A).

---

## 7) Governance: who can change reorder thresholds (required)
Doc 08 rule:
- Threshold changes are owned by Purchasing Leads.
- Changes should be traceable.

Implementation decision:
- Use role-based permissions + a mandatory reason field.

### 7.1 Create a role for purchasing lead (if missing)
1) Open `Role`.
2) Create:
   - Role Name: `Ops - Purchasing Lead`
3) Save.

### 7.2 Permissions for changing Item reorder rows
Reorder rows live on the Item master.
To prevent unsafe edits:

1) Open `Role Permission Manager`.
2) DocType: `Item`
3) Permissions baseline:
   - `Ops - Purchasing`:
     - Read: ON
     - Write: OFF
   - `Ops - Purchasing Lead`:
     - Read: ON
     - Write: ON
   - `Ops - Directors`:
     - Read: ON

Save.

### 7.3 Add a required “Reorder Change Reason” field on Item (required)
1) Open `Customize Form`.
2) DocType: `Item`.
3) Add custom fields:
   - Label: `Reorder Change Reason`
   - Fieldname: `reorder_change_reason`
   - Fieldtype: `Small Text`
4) Save.

### 7.4 Server Script: require reason when reorder rows are changed
This enforces traceability.

Important prerequisite (do this once, before creating the script):
1) Open `Customize Form`.
2) Select DocType: `Item`.
3) In the left sidebar field list, find the child table field that represents reorder rows. It is usually one of these:
   - `Reorder` (fieldname often `reorder_levels`)
   - `Item Reorder` (fieldname sometimes `reorder`)
4) Write down the correct fieldname you see in your ERPNext.

1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Item`
   - `DocType Event`: `Before Save`
4) Paste:

```python
before = doc.get_doc_before_save()

if not before:
    return

# Detect change to reorder rows.
# You must use the correct child table fieldname from step 7.4 prerequisite.
# Choose exactly one variant below.

# VARIANT A (most common): reorder child table fieldname is `reorder_levels`

REORDER_FIELDNAME = "reorder_levels"


# VARIANT B (alternative): reorder child table fieldname is `reorder`
# REORDER_FIELDNAME = "reorder"

def normalize(rows):
    out = []
    for r in (rows or []):
        out.append({
            "warehouse": r.warehouse,
            "reorder_level": float(getattr(r, "warehouse_reorder_level", 0) or 0),
            "reorder_qty": float(getattr(r, "warehouse_reorder_qty", 0) or 0),
        })
    return out

before_rows = normalize(before.get(REORDER_FIELDNAME) or [])
after_rows = normalize(doc.get(REORDER_FIELDNAME) or [])

if before_rows != after_rows:
    if not (doc.reorder_change_reason or "").strip():
        frappe.throw("Reorder Change Reason is required when changing reorder thresholds (Doc 08 governance rule).")
```

5) Save.

Operational rule:
- After saving the Item with a reason, clear the reason field manually (optional) or leave it as last change note.

---

## 8) Buyer operating routine (daily + weekly)
### 8.1 Daily quick check (10–20 minutes)
1) Open `Reorder — Main - WH` (or the `Stock Reorder` page).
2) Sort by urgency (below threshold).
3) Focus on:
   - critical fast movers
   - items needed for surgery sets
4) For each supplier you need to order from today:
   - prepare a Draft PO (Doc 07A)
   - create `Purchase Approval` task

### 8.2 Weekly deep review (30–90 minutes)
1) Review items repeatedly below threshold.
2) Review slow movers drifting below threshold.
3) If threshold changes are needed:
   - purchasing lead updates thresholds
   - writes `Reorder Change Reason`

---

## 9) Expiry-aware buying (required operational habit)
Doc 08 rule:
- For expiry-tracked items, quantity alone is not enough.

Procedure:
1) Before ordering an expiry-tracked item, open `Batch-Wise Balance History` (or equivalent) for the item in `Main - WH`.
2) Identify:
   - quantities expiring within the lead-time window
   - quantities expiring within the coverage window
3) If a large quantity expires soon, reduce the suggested order quantity.

---

## 10) Validation checklist (must pass before go-live)
### 10.1 Reorder list visibility
- At any time, a buyer can open the reorder view (or saved report) and see what is low.

### 10.2 Variant correctness
- If a variant family exists, each variant has its own reorder row for `Main - WH`.

### 10.3 Supplier grouping
- Every reorder-managed item has exactly one supplier.
- Buyer can group items by supplier (manually or via view) and prepare one PO per supplier.

### 10.4 Governance
- A non-lead purchasing user cannot edit Item reorder thresholds.
- A purchasing lead can edit thresholds.
- Changing reorder rows without `Reorder Change Reason` is blocked.

### 10.5 Integration with PO approval
- A Draft PO created from reorder suggestions cannot be submitted until a Director completes the `Purchase Approval` task (Doc 07A).
