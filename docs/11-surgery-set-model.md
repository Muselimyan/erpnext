# Doc 11 — Surgery Set Model (How sets are represented)

## 1) Purpose
Define a model for surgery sets/boxes that guarantees:
- Exact item/quantity tracking for:
  - dispatched to client location
  - currently at client location (company-owned: pending return or permanent set)
  - returned unused
  - consumed (must be invoiced)
- Clean visibility: “what items are in which client location right now”
- A structure that can support task/workflow automation (Doc 12+)

This document defines **data model and inventory representation**. The operational steps (dispatch/return/invoice/tasks) are in Doc 12.

## 2) Confirmed constraints
- Currency: AMD
- No VAT/taxes for now
- Batch/Lot numbers exist for many items
- Some items have expiry dates
- For instruments (tools), serial numbers exist for many items and serial tracking must be enforced in the stock ledger where available
- No delivery van warehouses
- Returned unused items go straight back to sellable stock
- Must track exact quantities
- Clients in scope for this flow: ~50

Implication:
- Soft barcode/serial “logs” can still exist as operational evidence, but **the stock ledger becomes the source of truth** for:
  - which serial numbers were dispatched / returned
  - which batches (lots) were delivered / returned
  - which batches were consumed (net consumption)

## 3) Core modeling principle
### 3.1 Client-level stock locations (recommended baseline)
To always know what is physically at each client location, represent those items as stock in ERPNext at a warehouse for that client.

**Invariant**
- If an item is physically at a client location (doctor or hospital) and is still company-owned, then the item quantity must exist in ERPNext in the correct client location warehouse.
  - Example (doctor at hospital/branch): `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital/Branch Name> - WH`
  - Example (hospital client, no named doctor): `<Hospital Code> — <Hospital/Branch Name> - WH`

This avoids custom reporting logic and makes standard stock reports accurate.

### 3.2 Capturing doctor + hospital context (no separate master)
Operational reality:
- Most clients are doctors (the doctor is the `Customer`).
- Some clients are hospitals (no named doctor).

Decision:
- Do not maintain a separate doctor master record for go-live.
- Capture optional context on transactions (Doc 04):
  - `Hospital` (optional link to a hospital Customer)
  - `Doctor Name` (optional free text, used when the client is a hospital)

### 3.3 Permanent client on-site surgery sets (new requirement)
Some client locations keep a complete surgery set on-site at all times.

Operational meaning:
- The set is always physically at the client location.
- You do not expect a “return pickup” per surgery.
- You still want to know (in ERPNext) what company-owned stock is at that client location.
- After surgeries, the client sends a replenishment order (what was used/missing) to make the set complete again.

Model principle:
- The on-site set is represented as stock in the client location warehouse.
- Usage reduces stock from the client location warehouse.
- Replenishment restores stock back into the client location warehouse.

This model is compatible with the same Item tracking rules (serial tools, batch/expiry implants).

## 4) Entities (what exists in the system)
### 4.1 Warehouses
Create a simple structure:
- `Main - WH`
- `Delivery In-Transit - WH` (outgoing staging)
- `Clients - WH` (group)
  - `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital/Branch Name> - WH` (one per doctor-hospital-branch group)
- `Return Pickup In-Transit - WH` (incoming staging)
- `Returns - WH`

Notes
- Do not transact on the group warehouse `Clients - WH`.
- Returns go directly back to sellable stock (via `Returns - WH` or directly to `Main - WH`, depending on how you prefer to operationalize returns in Doc 12).
- Do not create a warehouse per delivery person; while items are in an in-transit warehouse, “who has it” is tracked via assignment records and derived in reporting.

### 4.2 Customers (Clients)
Each client location you deliver to / bill is a Customer.

Recommended minimum fields:
- Customer Name (official)
- Short Name / Code (for warehouse naming)
- Payment terms (credit)

## 5) What is a “Surgery Set” in ERPNext?
### 5.1 The set is NOT a single stock item
A surgery set/box is a **collection of normal items**.

**Decision**
- Do not model the box as a single “set item” with hidden components.
- The box contents must be explicit item rows so you can track exact delivered/returned/used quantities.

Clarification (based on your operations):
- A “surgery box” is not always a fixed kit.
- The box is composed of multiple logical groups:
  - **Returnable tools/instruments** (expected to return 100%, strict accountability)
  - **Implants/consumables** (some used, some returned)
- The exact composition can vary per surgery case based on the clinical request (example: only certain sizes).

### 5.2 Set Type vs Set Instance
- **Surgery Set Type**: the template definition of a set (what it usually contains)
- **Surgery Set Instance / Case**: a specific surgery event for a specific client location/date (with optional hospital/doctor context)

Doc 11 defines the Set Type template. Doc 12 defines the Case/Instance workflow and documents.

## 6) Custom DocType: `Surgery Set Type`
### 6.1 Purpose
A reusable template that helps the preparing team build the box consistently.

### 6.2 Fields (minimum)
Create a custom DocType: `Surgery Set Type`

Header fields:
- `set_name` (Data) — required
- `set_code` (Data) — optional but recommended for naming/series
- `is_active` (Check) — default 1
- `notes` (Small Text) — optional

Child table: `Surgery Set Type Item`
- `item` (Link → Item) — required
- `default_qty` (Float) — required
- `uom` (Link → UOM) — optional (usually derived from item)
- `is_optional` (Check) — optional

Recommended additional fields (to support the new reality without forcing a fixed kit):
- `group` (Select) — optional. Example options:
  - Tools / Instruments
  - Screws
  - Nails
  - Plates
- `return_behavior` (Select) — optional:
  - Expected Return (Tools)
  - May Be Used (Implants)
- `is_critical` (Check) — optional (if checked, shortages should produce stronger warnings; at go-live this is not a hard-block)
- `notes` (Small Text) — optional (packing hints)

Behavior
- This DocType is a **template only**.
- Actual dispatched quantities are decided per case (Doc 12).

Template shortage rule:
- If there is not enough stock to fill the template fully, the case can still proceed with a partial set:
  - missing items are skipped (or quantities reduced)
  - the user sees a clear warning listing missing items and missing quantities

Template readiness visibility (recommended):
- In the Surgery Set Type list, it should be possible to see which templates are currently not fully fillable from inventory.

Important:
- Because doctors may request “only sizes X/Y/Z”, the template should load a *suggested* list, but the case can remove or add items.
- For size-based products (screws/plates/nails), use **Item Variants** so “size selection” is selecting the correct variant item codes.

### 6.3 Acceptance criteria
- A user can open a Set Type and see the default item list.
- Preparing team can use it as a checklist to prepare a box.
- If a template is short, the system supports preparing a partial set and shows a warning listing missing items.



## 7) Inventory representation for a surgery set case (model-level)
For each surgery case, inventory movements must result in correct stock positions:

- When dispatching the box:
  - stock moves from `Main - WH` to `Delivery In-Transit - WH`
  - then from `Delivery In-Transit - WH` to the correct client location warehouse
- When unused items return:
  - stock moves from the client location warehouse to `Return Pickup In-Transit - WH`
  - then from `Return Pickup In-Transit - WH` back to `Returns - WH` (or `Main - WH`)
- When items are consumed and invoiced:
  - stock must be reduced from the client location warehouse as part of the sales transaction

### 7.1 Inventory representation for permanent client on-site sets (model-level)
For client locations that keep a permanent set on-site:

- The set stock is already in the client location warehouse before a surgery.
- After usage, the client location warehouse stock is reduced for the used quantities.
- A replenishment delivery restores stock back into the client location warehouse.

Operational note:
- The financial charging mechanism for replenishment can still be implemented using the standard selling documents (Sales Order / Sales Invoice), but stock ownership and location remain governed by the client location warehouse model.

### 7.2 Tracking rules (Serial vs Batch vs Expiry)
To satisfy recall and accountability requirements, define item-level tracking rules.

#### A) Returnable tools / instruments
Model tools as stock items with **Serial Numbers** wherever the instrument has a unique identity.

Expectation:
- In surgery-case mode (Doc 12), these items are dispatched to a client location and must be returned.
- In permanent-set mode (section 3.3), these items may remain at the client location long-term, but they remain company-owned and must be accountable by location (serials in the correct client location warehouse).
- If a serial that should be company-owned cannot be located, it must be explicitly marked as missing/damaged in the operational record that governs the event.

Note:
- Not all tools will be serial-tracked.
- For non-serial tools, you can still enforce return completeness by quantity.

#### B) Implants / consumables with lot numbers and expiry
Model these as stock items with **Batch Numbers**.

Rules:
- Each receipt creates/uses a Batch (Lot).
- The Batch stores the expiry date (where applicable).
- Dispatch and return stock movements record the Batch numbers used.

FEFO rule (critical):
- For expiry-tracked items, batch selection should follow **FEFO** (First-Expiry-First-Out) to reduce expiry losses.

### 7.3 Recall definition (consumed, not merely delivered)
For recalls you care about **consumption** at the client location, not just delivery.

Model rule:
- In the surgery-case model (Doc 12), consumed (by batch) can be derived as:
  - delivered to client location (by batch) − returned unused (by batch)
- In the permanent-set model, consumed must be posted as an explicit stock reduction (consumption) from the client location warehouse with correct batch numbers.

This can be derived from stock movements even if Sales Invoices do not include batch numbers.

Doc 12 will define the exact ERPNext documents used (Delivery Note / Stock Entry / Sales Invoice) and the exact sequence.

## 8) Reporting enabled by this model
Without custom reports, you can answer:
- “What items are currently at Client X?”
  - Stock Balance filtered by the client location warehouse
- “Which clients currently hold Item Y?”
  - Stock Balance filtered by item across `Clients - WH` subtree

You can also answer:
- “What items are currently in delivery transit?”
  - Stock Balance for `Delivery In-Transit - WH`
- “What items are currently in return pickup transit?”
  - Stock Balance for `Return Pickup In-Transit - WH`

With batch/serial tracking enabled, you can also support recall and accountability reporting.

### 8.1 Batch recall reporting (by consumed)
Goal: for a recalled lot/batch, find **which clients/cases consumed it**.

Reporting approach (model-level):
- Filter Stock Ledger / Stock Entry Item by `batch_no`.
- Identify:
  - quantities delivered into the client location warehouse
  - quantities returned out of the client location warehouse
- Compute net consumption (delivered − returned) per client (and per case if you link stock entries to the case).

### 8.2 Tool accountability reporting (by serial)
Goal: know which client location currently holds which instruments and detect missing tools.

Reporting approach (model-level):
- Use serial-level stock reports (serial numbers in which warehouse).
- Anything still in the client location warehouse or `Return Pickup In-Transit - WH` is not yet back.
- Missing serials are those dispatched but not returned and explicitly flagged as missing/damaged in the case workflow.

Per-delivery-person “has what” while in transit is supported by:
- storing the assigned delivery person on the dispatch/pickup assignment records
- deriving reports that group in-transit warehouse quantities by delivery person

## 9) Open decisions (parked for Doc 12)
These are intentionally not finalized here:
- The authoritative “case” record structure (likely a custom DocType like `Surgery Case`)
- How dispatch and returns are represented in ERPNext documents
- How to enforce task workflow and mandatory photo attachment at pickup

Additional operational decisions that belong to Doc 12 (but are impacted by this model):
- For batch/serial items, Stock Entries cannot be fully hands-free: warehouse staff must confirm selected serials/batches before submission.
- Returns must be strict for tools: a case cannot be closed until every dispatched serial is accounted for (returned or marked missing/damaged).


Doc 12 alignment note:
- The recommended case record uses a single unified items grid (Case Items) that carries dispatched qty, returned qty, and computed used qty.

---

## Checklist (Doc 11 complete when)
- Warehouses structure exists (`Main - WH`, `Delivery In-Transit - WH`, `Clients - WH`, per-location WH, `Return Pickup In-Transit - WH`, `Returns - WH`)
- Client Customers exist (at least 1 test client)
- `Surgery Set Type` DocType exists with child table
- Item masters are configured with correct tracking:
  - Tools: serial numbers enabled where applicable
  - Consumables/implants: batch numbers enabled, expiry on batches where applicable
