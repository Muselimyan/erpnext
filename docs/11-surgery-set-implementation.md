# Doc 11A — Surgery Set Setup (Implementation Guide)

## 1) Purpose
This document is a **step-by-step “click-by-click” setup guide** for a new ERPNext user to configure everything required by **Doc 11 — Surgery Set Model**.

Scope of this implementation doc:
- Confirm required warehouses exist (including delivery/return staging warehouses)
- Confirm client modeling prerequisites (Customers + client-location warehouses under `Clients - WH`)
- Implement the custom DocType:
  - `Surgery Set Type`
  - `Surgery Set Type Item` (child table)
- Create sample `Surgery Set Type` templates
- Add a readiness warning (warning-only) so users see when a template cannot be fully filled from `Main - WH`
- Validation checks

Out of scope here:
- The full operational workflow (dispatch, pickup, invoicing, tasks) — that is covered in Doc 12+.

---

## 2) Prerequisites / permissions
You must be logged in as a user with at least:
- `System Manager`
- `Stock Manager` (for warehouses)
- `Accounts Manager` (not required for Doc 11A; only needed if you also configure accounting defaults)

To create **custom DocTypes**, you may also need:
- `Administrator` access, and
- access to the `DocType` list (depends on how your ERPNext is configured).

---

## 3) Prerequisites checklist (must be done first)
Do not start Doc 11A until these are done:

- Doc 04A — Clients are modeled as `Customer` (no separate Doctor master)
  - `Customer.client_code` exists
  - `Customer.client_kind` exists
  - optional context fields exist on transactions (`hospital`, `hospital_branch`, `doctor_name`)
- Doc 05A — Warehouse model exists and includes:
  - `Main - WH`
  - `Delivery In-Transit - WH`
  - `Clients - WH` (group)
  - client-location leaf warehouses under `Clients - WH`
  - `Return Pickup In-Transit - WH`
  - `Returns - WH`
- Doc 06A — Items are configured with correct tracking:
  - Tools: serial numbers ON where applicable
  - Implants/consumables: batch numbers ON where applicable
  - FEFO warning exists for expiry-tracked items

If any of those are missing, complete those implementation docs first.

Important model rule (Doc 11):
- A surgery set/box is **not** a single stock item.
- It is a collection of normal items.
- `Surgery Set Type` is a **template only**.
- Actual dispatched quantities and batch/serial selection happen per case/workflow in Doc 12.

---

## 4) Confirm required warehouses exist (Doc 11 model)
Doc 11 requires these warehouses:
- `Main - WH`
- `Delivery In-Transit - WH`
- `Clients - WH` (group)
- `Return Pickup In-Transit - WH`
- `Returns - WH`

### 4.1 Verify warehouses
1) Open `Warehouse` list.
2) In the search bar, search and open each warehouse above.
3) For each one, confirm:
   - `Is Group` is OFF for:
     - `Main - WH`
     - `Delivery In-Transit - WH`
     - `Return Pickup In-Transit - WH`
     - `Returns - WH`
   - `Is Group` is ON for:
     - `Clients - WH`

### 4.2 Verify at least one client-location warehouse exists
1) Open `Warehouse` list.
2) Open `Clients - WH`.
3) Confirm you see at least one leaf warehouse under it.

If none exist:
- Stop and complete Doc 04A + Doc 05A (client-location warehouse creation).

---

## 5) Create the Surgery Set template DocTypes
Doc 11 requires a template DocType (`Surgery Set Type`) and a child table (`Surgery Set Type Item`).

### 5.1 Create child table: `Surgery Set Type Item`
1) Open `DocType` list.
2) Click `New`.
3) Set:
   - `Name`: `Surgery Set Type Item`
   - Check: `Is Child Table`
4) Add fields:
   - `item` (Link) — Options: `Item` — Req: Yes
   - `default_qty` (Float) — Req: Yes
   - `uom` (Link) — Options: `UOM` — optional
   - `is_optional` (Check) — optional
   - `group` (Select) — optional — Options (one per line):
     - Tools / Instruments
     - Screws
     - Nails
     - Plates
   - `return_behavior` (Select) — optional — Options (one per line):
     - Expected Return (Tools)
     - May Be Used (Implants)
   - `is_critical` (Check) — optional
   - `notes` (Small Text) — optional
5) Click `Save`.

### 5.2 Create parent DocType: `Surgery Set Type`
1) Open `DocType` list.
2) Click `New`.
3) Set:
   - `Name`: `Surgery Set Type`
   - Ensure it is **not** a child table
   - `Autoname`: `field:set_name`
4) Add fields:
   - `set_name` (Data) — Req: Yes — Unique: Yes
   - `set_code` (Data) — optional
   - `is_active` (Check) — default checked
   - `notes` (Small Text) — optional
   - `readiness_status` (Select) — Read Only — Options (one per line):
     - Ready
     - Short
     - Critical Short
   - `readiness_note` (Small Text) — Read Only
   - `items` (Table) — Options: `Surgery Set Type Item`
5) Click `Save`.

Validation:
- Open `Surgery Set Type` list.
- Create a new Set Type and confirm you can add multiple item rows.

### 5.3 Permissions (Role Permission Manager) for surgery set templates
Goal:
- Inventory team maintains templates.
- Directors can always view and override when needed.
- Drivers do not work with master data.

1) Open `Role Permission Manager`.

For DocType: `Surgery Set Type`
- `Ops - Inventory`:
  - Read, Write, Create
- `Ops - Directors`:
  - Read, Write, Create
- `Ops - Delivery`:
  - Read
- `Delivery Driver`:
  - No access

For DocType: `Surgery Set Type Item`
- It is a child table; permissions follow the parent DocType.

### 5.4 Create a readiness list view (recommended)
Doc 11 recommends that it is easy to see which templates are not currently fillable.

1) Open `Surgery Set Type` list.
2) Click `List View Settings` (or the three-dot menu) → `Fields` / `Columns`.
3) Ensure these columns are visible:
   - Set Name
   - Set Code
   - Readiness Status
   - Modified
4) Add a filter:
   - Is Active = checked
5) Sort:
   - Sort by `Readiness Status` (so `Critical Short` / `Short` float to the top)
6) Save the view as: `Surgery Set Types — Readiness`.


---

## 6) (Recommended) Add readiness warning automation on `Surgery Set Type`
Doc 11 requires that a Set Type can be used as a practical preparation checklist.

This implementation adds a go-live-safe warning:
- if a template cannot be fully filled from `Main - WH`, the user sees a warning and the set is marked `Short` / `Critical Short`
- this is **warning-only** (does not hard-block)

### 6.1 Create a Server Script for `Surgery Set Type`
1) Open `Server Script`.
2) Click `New`.
3) Set:
   - Script Type: `DocType Event`
   - Reference DocType: `Surgery Set Type`
   - DocType Event: `Validate`
4) Paste:

```python
import frappe

MAIN_WH = "Main - WH"

missing = []
critical_missing = []

for row in (doc.items or []):
    item_code = row.item
    if not item_code:
        continue

    required_qty = float(row.default_qty or 0)
    if required_qty <= 0:
        continue

    bin_row = frappe.db.get_value(
        "Bin",
        {"item_code": item_code, "warehouse": MAIN_WH},
        ["projected_qty"],
        as_dict=True,
    )

    projected = float((bin_row or {}).get("projected_qty") or 0)
    shortage = required_qty - projected

    if shortage > 0:
        line = f"{item_code}: need {required_qty}, projected {projected}, short {shortage}"
        missing.append(line)
        if int(row.is_critical or 0) == 1:
            critical_missing.append(line)

if critical_missing:
    doc.readiness_status = "Critical Short"
    doc.readiness_note = "Critical shortages:\n" + "\n".join(critical_missing)
    frappe.msgprint(doc.readiness_note, title="Surgery Set Type readiness warning")
elif missing:
    doc.readiness_status = "Short"
    doc.readiness_note = "Shortages:\n" + "\n".join(missing)
    frappe.msgprint(doc.readiness_note, title="Surgery Set Type readiness warning")
else:
    doc.readiness_status = "Ready"
    doc.readiness_note = ""
```

5) Save.
6) Submit.

---

## 7) Sample master data (create these so you can test)
### 7.1 Sample Customers (clients)
Doc 11 assumes clients are `Customer` records (Doc 04 model).

Create at least these two sample customers (if you do not already have them):

1) Doctor client (bill-to)
- Customer Name: `D001 — Dr. Example`
- `client_code`: `D001`
- `client_kind`: `Doctor`

2) Hospital context (optional)
- Customer Name: `H001 — Example Hospital`
- `client_code`: `H001`
- `client_kind`: `Hospital`

### 7.2 Sample client-location warehouse
You must have a leaf warehouse under `Clients - WH` for at least one location.

Naming convention decision (implementation):
- Use the same naming style as Doc 05A.
- Example format: `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital/Branch Name> / Main - WH`

Example warehouse name (doctor working at a hospital branch):
- `D001 — Dr. Example @ H001 — Example Hospital / Main - WH`

If this warehouse does not exist:
- create it using the Doc 05A client-location warehouse procedure.

---

## 8) Create a sample `Surgery Set Type` record (template)
### 8.1 Create the template
1) Open `Surgery Set Type` list.
2) Click `New`.
3) Fill:
   - Set Name: `Ortho Basic Set (Sample)`
   - Set Code: `ORTHO-BASIC`
   - Is Active: checked
4) In the `Items` table add sample rows (edit quantities to match your real inventory later):

Sample rows:
- Item: `TOOL-001` Default Qty: `1` Group: `Tools / Instruments` Return Behavior: `Expected Return (Tools)` Is Critical: checked
- Item: `IMP-001` Default Qty: `5` Group: `Plates` Return Behavior: `May Be Used (Implants)` Is Critical: checked
- Item: `CONS-001` Default Qty: `10` Group: `Screws` Return Behavior: `May Be Used (Implants)` Is Critical: unchecked

5) Save.

Expected result:
- `Readiness Status` becomes `Ready`, `Short`, or `Critical Short` based on projected stock in `Main - WH`.

---

## 9) Setup validation checklist (must pass)
### 9.1 Warehouses
- `Main - WH` exists
- `Delivery In-Transit - WH` exists
- `Clients - WH` exists and is a group
- at least one client-location leaf warehouse exists under `Clients - WH`
- `Return Pickup In-Transit - WH` exists
- `Returns - WH` exists

### 9.2 DocTypes
- `Surgery Set Type Item` exists and is a child table
- `Surgery Set Type` exists and has an Items table

### 9.3 Readiness warning automation
- Create a Surgery Set Type where you know one item is out of stock in `Main - WH`
- Save
- Confirm `Readiness Status` becomes `Short` or `Critical Short`
- Confirm a warning popup appears listing missing items

### 9.4 Tracking prerequisites (spot-check)
- Open `Item` → `TOOL-001` and confirm Serial Number tracking matches your policy
- Open `Item` → `IMP-001` and confirm Batch tracking matches your policy

---

## 10) Notes for the next docs
- Doc 11A sets up master data + template structures.
- Doc 12 will define the operational case record and workflows:
  - dispatch into client-location warehouses
  - return pickup and return stock movements
  - usage derivation and invoicing
  - task workflow and photo requirements
  - tool serial accountability rules
