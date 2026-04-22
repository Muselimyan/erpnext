# Doc 06A — Item Catalog, Variants, and UOMs (Implementation / ERPNext Setup Guide)

## 1) Purpose
This is a step-by-step guide to implement:
- **Doc 06 — Item Catalog and Variants (Operational)**

It covers:
- Item Groups
- UOMs and UOM conversions (pack sizes)
- Item Attributes + Variant templates
- Creating Items and Variants
- Enabling tracking:
  - Batch + expiry (implants/consumables where applicable)
  - Serial (tools/instruments where applicable)
- Validation checklist

Non-goals:
- This guide does not implement reordering rules (Doc 08).
- This guide does not implement selling workflows (Doc 09) or surgery-case workflows (Doc 12).

---

## 2) Prerequisites / access
Do this as a user with:
- `System Manager`
- `Stock Manager`

Prerequisite:
- Complete Doc 03A first so the operational roles exist (this doc uses those role names in the permissions section).

You will use:
- `Customize Form`
- `Server Script`
- `Stock Settings`
- `Item Group`
- `UOM`
- `Item Attribute`
- `Item`
- `Supplier`
- `Batch`
- `Serial No`

---

## 3) Create Item Groups (category tree)
Goal:
- A stable browsing structure and reporting categories.

Steps:
1) Open `Item Group`.
2) Create top-level groups (names are examples; keep consistent with Doc 06):
   - `Implants`
   - `Instruments / Tools`
   - `Consumables / Disposables`
   - `Accessories / Parts`
   - `Services / Non-Stock` (only if needed)
3) Under each, create sub-groups by specialty/product family as required.

Validation:
- A user can find an item family in 2–4 clicks.

---

## 4) Create UOMs
Goal:
- UOMs match how you physically count, buy, and sell.

### 4.1 Create standard UOMs
Steps:
1) Open `UOM`.
2) Ensure you have:
   - `Nos` (piece)
   - `Box`
   - `Pack`
   - `Set` (optional)
   - `Pair` (optional)

Note:
- If you already have these, do not create duplicates.

### 4.2 Decide whether you need UOM conversions
Doc 06 decision:
- Pack-breaking happens sometimes.
- For data quality, every item must be classified as either:
  - never break packs, or
  - pack-breakable

Rule (critical):
- If an item is batch-tracked and/or expiry-tracked, do not model “Box” and “Single” as separate Items.
- Use one Item identity and implement pack-breaking using UOM conversion.

### 4.3 Implement the single-Item + UOM conversion model (required for batch/expiry-tracked items)
Use this model when:
- You buy in `Box` but track/sell in `Nos`, and
- the item is batch-tracked and/or expiry-tracked.

Example policy:
- Stock UOM = `Nos`
- Purchase UOM = `Box`
- Conversion: `1 Box = 10 Nos`

Steps:
1) Open `Item`.
2) Create (or open) the item.
3) Set:
   - Stock UOM: `Nos`
4) In the UOMs table (on the Item), add rows:
   - UOM: `Nos` — Conversion Factor: `1`
   - UOM: `Box` — Conversion Factor: `10`
5) Save.

Operational rule:
- Receiving can be done in `Box` but the stock ledger will reflect `Nos`.
- Batch/expiry traceability stays on the one Item identity.

### 4.4 Implement the two-Item + repack model (allowed only for non-tracked items)
Use this model only when:
- the item has no batch tracking and no serial tracking, and
- you truly operate with two different “sellable units” as separate products.

Steps:
1) Create two items:
   - Item A: the box item (Stock UOM = `Box`)
   - Item B: the single item (Stock UOM = `Nos`)
2) When you physically break a box into pieces, create a `Stock Entry` of type `Repack`:
   - Consume Item A quantity (boxes)
   - Produce Item B quantity (pieces)
3) Save and Submit.

Operational note:
- Do not use this approach for traceable implants/consumables.

### 4.5 Add `pack_breaking_policy` on `Item` (required)
Goal:
- Force every item to be explicitly classified as either pack-breakable or never-break.

Steps:
1) Open `Customize Form`.
2) Select DocType: `Item`.
3) Add a Custom Field:
   - Label: `Pack Breaking Policy`
   - Fieldname: `pack_breaking_policy`
   - Fieldtype: `Select`
   - Options (one per line, exactly):
     - Never break packs
     - Pack-breakable
   - Required: ON
4) Save.

Go-live policy (recommended default):
- If `Has Batch No` = ON and/or `Has Expiry Date` = ON:
  - `Pack Breaking Policy` must be `Pack-breakable` and you must use the single-Item + UOM conversion model.
- If the item has no tracking:
  - Default to `Never break packs` unless you have an explicitly approved exception.

---

## 5) Create Item Attributes (for variants)
Goal:
- Build controlled variant dimensions (size, length, angle).

Steps:
1) Open `Item Attribute`.
2) Create attributes (examples):
   - `Diameter (mm)`
   - `Length (mm)`
   - `Angle (deg)`
   - `Side` (Left/Right)
   - `Material` (optional)
3) For each attribute:
   - Add the allowed values (finite list).

Validation:
- Values are not free-typed during item creation.

---

## 6) Create Item Variant templates
Goal:
- Create an Item Template for each product family that has many variants.

Example: Screws
1) Open `Item`.
2) Click `New`.
3) Create an Item Template:
   - Item Code: a stable template code (example: `SCREW-BONE-3.5MM-TPL`)
   - Item Name: a clear template name (example: `Stryker — Bone Screw — Template`)
   - Item Group: appropriate category
   - Has Variants: ON
4) In the Variant section:
   - Add the Item Attributes to use (example: Diameter + Length).
5) Save.

Repeat:
- One template per variant-heavy family (plates, nails, drill bits, etc.).

---

## 7) Create Items (standalone) and Variants
### 7.1 Create standalone items
Use for products that should not be variants.

Steps:
1) Open `Item`.
2) Click `New`.
3) Set:
   - Item Code: use your existing internal SKU/code (keep stable)
   - Item Name (per Doc 02): `<Brand> — <Item Name> — <Key Spec>`
   - Item Group
   - Stock UOM
   - Pack Breaking Policy
4) Save.

Deprecation rule (required):
- Do not delete items that were used in transactions.
- To stop using an item, set `Disabled` = ON.

### 7.1.2 Sample items for go-live training (recommended)
Create these three items so you can test receiving, picking, tracking, and pack-breaking rules end-to-end.

Sample Item A (implant / traceable, pack-breakable with conversion):
- Item Code: `IMP-001`
- Item Name: `Stryker — Bone Screw — 3.5mm`
- Item Group: `Implants`
- Stock UOM: `Nos`
- Pack Breaking Policy: `Pack-breakable`
- Tracking:
  - `Has Batch No`: ON
  - `Has Expiry Date`: ON
- UOM conversion (UOMs table):
  - `Nos` = 1
  - `Box` = 10

Sample Item B (tool / serial-tracked):
- Item Code: `TOOL-001`
- Item Name: `Medtronic — Drill Bit — 2.0mm`
- Item Group: `Instruments / Tools`
- Stock UOM: `Nos`
- Pack Breaking Policy: `Never break packs`
- Tracking:
  - `Has Serial No`: ON

Sample Item C (consumable / non-tracked, never break):
- Item Code: `CONS-001`
- Item Name: `Generic — Gloves — Size M`
- Item Group: `Consumables / Disposables`
- Stock UOM: `Box`
- Pack Breaking Policy: `Never break packs`
- Tracking: none

Stock Settings requirement (recommended before bulk import):
1) Open `Stock Settings`.
2) Set `Item Naming By` = `Item Code`.
3) Save.

### 7.1.3 Barcodes (recommended)
If you want barcode-first operations:
1) On the Item, add the barcode value(s) so scanning can identify the item/variant.
2) If multiple barcodes exist (unit pack vs outer carton), store all relevant ones.

### 7.2 Create variants from templates
Steps:
1) Open the Item Template.
2) Use the variant creation action.
3) Select the attribute values (example: Diameter = 3.5mm, Length = 20mm).
4) Save the variant.

Validation:
- Variant Item Name and/or variant attributes clearly identify the product.

---

## 8) Supplier-per-item setup
Confirmed policy:
- Each item has exactly one supplier.

Steps (baseline):
1) Ensure the supplier exists in `Supplier`.
2) Open an Item.
3) In the Suppliers section, add exactly one Supplier.
4) Save.

Validation:
- Each variant item has its supplier assigned (do not assume template assignment covers all variants).

---

## 9) Tracking configuration (Batch/Expiry and Serial)
This implements your confirmed tracking policy.

### 9.1 Batch + Expiry (implants/consumables where applicable)
For items that require lot/expiry traceability:
1) Open the Item.
2) Enable:
   - `Has Batch No`: ON
   - `Has Expiry Date`: ON (only if the item is expiry-sensitive)
3) Save.

Receiving rule:
- On `Purchase Receipt` / `Purchase Invoice` receiving, you must create/select the `Batch` and record:
  - Batch No
  - Expiry Date (when applicable)

Operational validation:
- When you receive the item, you can record batch and expiry.
- When you move stock for surgery cases, you can select the batch used.

FEFO + near-expiry decisions (Doc 06):
- FEFO enforcement is a warning at go-live (not a hard-block).
- Near-expiry warning threshold is 1 month.

Implementation (recommended): FEFO + near-expiry warning on Stock Entry
This script warns when a user selects a fresher batch while an older-expiring batch exists in the same source warehouse.

Steps:
1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Stock Entry`
   - `DocType Event`: `Before Submit`
4) Paste this script:

```python
import frappe
from frappe.utils import today, add_months, getdate

def get_earliest_expiry_batch(item_code, warehouse):
    row = frappe.db.sql(
        """
        SELECT sle.batch_no, b.expiry_date
        FROM `tabStock Ledger Entry` sle
        INNER JOIN `tabBatch` b ON b.name = sle.batch_no
        WHERE sle.item_code = %s
          AND sle.warehouse = %s
          AND sle.is_cancelled = 0
          AND sle.batch_no IS NOT NULL
          AND b.expiry_date IS NOT NULL
        GROUP BY sle.batch_no, b.expiry_date
        HAVING SUM(sle.actual_qty) > 0
        ORDER BY b.expiry_date ASC
        LIMIT 1
        """,
        (item_code, warehouse),
        as_dict=True,
    )
    return row[0] if row else None

cutoff_date = getdate(add_months(today(), 1))

for d in doc.items:
    if not d.item_code or not d.s_warehouse or not d.batch_no:
        continue

    selected_expiry = frappe.db.get_value("Batch", d.batch_no, "expiry_date")
    if not selected_expiry:
        continue

    selected_expiry = getdate(selected_expiry)

    earliest = get_earliest_expiry_batch(d.item_code, d.s_warehouse)
    earliest_expiry = getdate(earliest.get("expiry_date")) if earliest and earliest.get("expiry_date") else None
    if earliest_expiry and selected_expiry > earliest_expiry:
        frappe.msgprint(
            f"FEFO warning: You selected batch '{d.batch_no}' (expiry {selected_expiry}) but an older-expiring batch '{earliest['batch_no']}' (expiry {earliest['expiry_date']}) is available in '{d.s_warehouse}'.",
            indicator="orange",
        )

    if selected_expiry <= cutoff_date:
        frappe.msgprint(
            f"Near-expiry warning: Batch '{d.batch_no}' expires on {selected_expiry} (<= 1 month).",
            indicator="orange",
        )
```

5) Save.

### 9.2 Serial (tools/instruments where applicable)
For tools/instruments that have serial numbers:
1) Open the Item.
2) Enable:
   - `Has Serial No`: ON
3) Save.

Operational validation:
- When you receive the item, serial numbers can be recorded.
- Stock reports can show which serial is in which warehouse.

---

## 10) Data import approach (recommended)
For large catalogs:
- Use bulk import for:
  - Item Groups
  - Items
  - Item Attributes / Values
  - Variants

Then do a manual review pass for:
- UOM correctness
- Supplier-per-item correctness
- Tracking flags correctness

If you bulk import Items, include these columns at minimum:
- Item Code
- Item Name
- Item Group
- Stock UOM
- Pack Breaking Policy
- Has Batch No
- Has Expiry Date
- Has Serial No

Operational reminder:
- If `Has Batch No` / `Has Expiry Date` is ON and you buy in boxes, you must also configure the item-level UOM conversion (section 4.3). This is typically a manual step after import.

---

## 11) Validation checklist
### 11.1 Searchability
- Users can find items by brand and spec.
- Users can distinguish variants quickly.

### 11.1.1 Barcode readiness (if using scanning)
- Scanning the item barcode resolves to exactly one item/variant.
- Barcodes are present for high-volume and high-risk picking items.

### 11.2 UOM sanity
- Stock UOM matches warehouse counting.
- No item requires fractional picking in normal operations.

If pack-breaking is used:
- Pack-breakable items have a defined conversion and staff use it consistently.

Pack-breaking policy test:
- Confirm every item has `Pack Breaking Policy` filled (field is required).
- Confirm a traceable item (batch/expiry) is not modeled as two separate items (Box vs Nos).

### 11.3 Tracking sanity
- A batch-tracked implant can be received with expiry recorded.
- A serial-tracked tool can be received with serial recorded.

FEFO warning test:
- Create two batches in `Main - WH` for the same item:
  - Batch A expiry sooner
  - Batch B expiry later
- Create a `Stock Entry` that issues/moves stock from `Main - WH`.
- Select Batch B (later expiry) and submit.
- Confirm the FEFO warning appears.

Near-expiry warning test:
- Use a batch with expiry within 1 month.
- Submit a `Stock Entry` using that batch.
- Confirm the near-expiry warning appears.

### 11.4 Supplier rule
- Every item has exactly one supplier.

---

## 11.5 Permissions and governance (required)
Doc 06 requires that Item master data is controlled.

Steps:
1) Open `Role Permission Manager`.
2) For DocType `Item`:
   - `Ops - Inventory`: Read ON, Write ON, Create ON
   - `Ops - Directors`: Read ON, Write ON, Create ON
   - `Ops - Order Accepting`: Read ON
   - `Ops - Accounting`: Read ON
   - `Ops - Returns`: Read ON
   - `Ops - Delivery`: Read ON
   - `Delivery Driver`: Read OFF
3) Save.

Repeat the same pattern for:
- `Item Group`
- `Item Attribute`
- `UOM`

---

## 12) Acceptance criteria
- The catalog supports fast selection of correct variants.
- Items that require traceability are configured for batch/expiry or serial as appropriate.
- The catalog can support reorder-by-supplier reporting later (Doc 08).
