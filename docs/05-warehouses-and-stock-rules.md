# Doc 05 — Inventory Foundation: Warehouses, Stock Rules (Operational)

## 1) Purpose
This document defines:
- The warehouse structure (what each warehouse means in real life)
- The stock movement rules that must always be followed
- The invariants that keep stock reporting accurate

Goals:
- Ensure you can always answer:
  - what is in the main warehouse
  - what is physically at each client location (when company-owned)
  - what is currently “in transit”
  - what is pending returns processing
- Prevent “silent” stock movements that bypass accountability.

Non-goals:
- This doc does not explain ERPNext configuration steps.
- Step-by-step implementations belong in implementation docs.

---

## 2) Core principles (read this first)
- **Warehouse = physical location + responsibility**
  - Each leaf warehouse must correspond to a real physical place and a responsible team.

- **The stock ledger is the source of truth**
  - For tracked items (serial/batch/expiry), the stock ledger must match reality.

- **No per-driver warehouses**
  - Drivers are tracked via assignments and tasks, not warehouses.

- **No transacting on group warehouses**
  - Parent/group warehouses exist only for organization and reporting.

Practical meaning:
- If a warehouse is a “group”, it is like a folder.
- Only “leaf” warehouses should ever contain stock.

---

## 3) Warehouse tree (recommended)
Naming conventions are defined in Doc 02.

Rule:
- Your day-to-day operations should only use the leaf warehouses in section 3.1.

### 3.1 Top-level structure
Recommended leaf warehouses:
- `Main - WH`
  - Your sellable stock location.

- `Delivery In-Transit - WH`
  - Outgoing staging.
  - Meaning: physically packed and handed to delivery team / driver, but not yet delivered.

- `Clients - WH` (group only)
  - Parent group for all client location warehouses.

- `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital/Branch Name> - WH` (one per doctor-hospital-branch group)
  - Meaning: stock physically at that client location group **when it is still company-owned** (surgery sets, consignment-like flows, pending return/usage workflows).

Alternative (if the client is a hospital with no named doctor):
- `<Hospital Code> — <Hospital/Branch Name> - WH`

- `Return Pickup In-Transit - WH`
  - Incoming staging.
  - Meaning: physically picked up from a client location, with driver, not yet received/verified by warehouse.

- `Returns - WH`
  - Returns receiving / verification area.
  - Meaning: physically returned and inside your building, but still in the “returns processing” zone (counting, verification, cleaning, repack).

### 3.2 Client location warehouses (important clarification)
The client location warehouse concept exists to support company-owned stock that is physically at a client location group:
- surgery-set cases (Doc 11/12)
- permanent on-site surgery sets (consignment-like baseline stock kept at the client location)

Operational rule:
- If an item is physically at a client location and is still considered company-owned, it must be in that client location warehouse in ERPNext.

Note:
- Items that are sold outright (ownership transferred) should not remain in a client location warehouse on your books.
- The standard-selling docs will define the chosen approach for normal sales.

Operational simplification:
- Client location warehouses are primarily for:
  - surgery cases
  - permanent on-site sets (consignment-like)
- Normal sales should not create long-lived “company-owned at client” positions.

Policy:
- Client location warehouses are used for company-owned at-client stock only (surgery cases and permanent on-site sets).
- Standard sales must not move stock into client location warehouses.

---

## 4) Warehouse responsibility boundaries
This section defines who is responsible for stock accuracy in each warehouse.

Rule:
- Every warehouse must have a named owner team. If nobody owns a warehouse, stock accuracy will drift.

- `Main - WH`
  - Owner: Inventory team
  - Expected behavior:
    - receiving
    - storage
    - picking
    - cycle counts

- `Delivery In-Transit - WH`
  - Owner: Delivery team (coordination), but inventory team must ensure correct packing.
  - Expected behavior:
    - short-lived stock location
    - stock exists here only between dispatch and delivery

Control:
- If stock remains here for “too long”, it indicates a stuck delivery workflow, not a stock problem.

- Client location warehouses
  - Owner: Operations (delivery + returns) as a shared responsibility
  - Expected behavior:
    - stock here is tracked per client location group
    - stock here is either:
      - pending return/usage reconciliation for surgery cases, or
      - baseline “permanent set” stock kept at a client location (consignment-like)

- `Return Pickup In-Transit - WH`
  - Owner: Delivery team
  - Expected behavior:
    - stock exists here only between pickup and warehouse receipt

Control:
- If stock remains here for “too long”, it indicates a stuck pickup workflow.

- `Returns - WH`
  - Owner: Returns team / Inventory team
  - Expected behavior:
    - counting/verification happens here
    - discrepancies are detected here

---

## 5) Tracking rules (serial, batch, expiry)
These rules apply across all warehouses.

### 5.1 Tools / instruments (serial-tracked where applicable)
- If an instrument has a serial number and you choose to track it, then:
  - every movement must record the serial numbers that moved.

Operational control:
- You must not close a surgery case until every dispatched serial-tracked tool is accounted for:
  - returned, or
  - explicitly recorded as missing/damaged (per Doc 12).

### 5.2 Implants / consumables (batch-tracked where applicable)
- If an item is batch-tracked:
  - every movement must record the batch numbers that moved.
- If expiry is relevant:
  - expiry date is stored on the batch.

FEFO rule (critical):
- For expiry-tracked items, batch selection must follow **FEFO** (First-Expiry-First-Out).
- If a user selects a fresher batch while an older-expiring batch is available in `Main - WH`, the system must alert.

Business reason:
- Recall and traceability is based on stock movements by batch/serial.


## 6) Allowed stock movement patterns (the “only correct paths”)
This section is the heart of the document.

### 6.1 Outgoing delivery staging (common pattern)
Meaning:
- Before a driver leaves, items are staged in `Delivery In-Transit - WH`.

Allowed move:
- `Main - WH` → `Delivery In-Transit - WH`

### 6.1A Aborted delivery / cancellation after staging (standard sales redirect)
Meaning:
- Items were staged for a standard delivery, but the order was cancelled before delivery completion (package comes back).

Allowed moves (recommended baseline):
1) Return into warehouse control:
   - `Delivery In-Transit - WH` → `Returns - WH`
2) After verification/repack (if needed):
   - `Returns - WH` → `Main - WH`

Operational intent:
- Use `Returns - WH` as the controlled checkpoint to ensure:
  - quantities are correct
  - tracked items (batch/serial) remain correctly recorded
  - you do not silently re-shelve a package with unknown integrity

Operational intent:
- You can report “what is in transit” at any moment.
- You can derive “which driver has what” from assignments + dispatch group references.

Important:
- Staging warehouses may be used for standard deliveries and for surgery cases.
- Client location warehouses are not used for standard deliveries.

### 6.2 Surgery set delivery to client location (Doc 12)
Allowed moves:
1) Dispatch staging:
   - `Main - WH` → `Delivery In-Transit - WH`
2) Delivery completion:
   - `Delivery In-Transit - WH` → `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital/Branch Name> - WH`

Control:
- For tracked items, dispatch must not be considered complete until the dispatch stock movement is submitted with correct serial/batch selection.

### 6.3 Return pickup staging (Doc 12)
Allowed move:
- `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital/Branch Name> - WH` → `Return Pickup In-Transit - WH`

Operational intent:
- Drivers do not count quantities.
- Photo evidence is captured at warehouse drop-off (handoff to Returns Team), not at client pickup.
- Returns team becomes the authoritative counting step.

### 6.4 Return receiving / verification
Allowed moves:
1) Pickup staging to returns zone:
   - `Return Pickup In-Transit - WH` → `Returns - WH`
2) Optional after verification:
   - `Returns - WH` → `Main - WH`

Additional standard-sales return path (rare exception):
- If goods are returned by a client after a standard sale (ownership already transferred), they must still enter through `Returns - WH` for verification before re-entering `Main - WH`.

Why `Returns - WH` exists:
- It creates a clean separation:
  - “returned but not checked”
  - vs “checked and ready for sellable stock”

Additional rule (recommended):
- Only the Returns Team should be allowed to move stock out of `Returns - WH`.

### 6.5 Consumption / usage (surgery sets)
Operational definition:
- Used quantities are the difference:
  - delivered to client location
  - minus returned unused
  - minus explicit lost/damaged

Allowed rule:
- Stock for used quantities must be reduced from the client location warehouse.

Business intent:
- This supports recall-by-consumed quantities.

Important:
- This is not optional for traceable implants.
- If consumption is not posted correctly, your recall-by-consumed reporting becomes unreliable.

### 6.6 Purchase receiving (how stock enters `Main - WH`)
Allowed move:
- Supplier → `Main - WH`

Operational rule:
- All stock that becomes sellable must enter the system into `Main - WH` first (unless you intentionally define a quarantine warehouse later).

### 6.7 Stock corrections (cycle counts, mistakes)
Allowed move:
- Adjustments must only be done with a clear reason and must be reviewable.

Operational rule:
- Stock corrections are the last resort.
- If you frequently correct stock in the same warehouse, it is a process problem (receiving, picking, or returns), not an accounting fix.

---

## 7) What is not allowed (common failure modes)
These are rules that prevent stock from becoming untrustworthy.

- Do not transact on `Clients - WH` (group).
- Do not “fix” problems by posting random receipts/issues without an operational reason.
- Do not bypass the in-transit warehouses when you need in-transit reporting.
- Do not leave stock sitting in in-transit warehouses for long periods.
  - If it happens, it is a stuck workflow that must be investigated.

- Do not backdate postings casually.
  - Backdating should only be used to match physical reality when your operation cannot post in real time (example: return pickup).

---

## 8) Reporting outcomes (why this structure matters)
With this model, you can run the business day-to-day.

### 8.1 Stock at each client location (company-owned at client)
- Stock Balance filtered by one client location warehouse.

### 8.2 In-transit stock
- Stock Balance for:
  - `Delivery In-Transit - WH`
  - `Return Pickup In-Transit - WH`

Operational interpretation:
- Any stock in these warehouses is “work in progress” and must have an owner and a linked task/assignment.

### 8.3 Returns processing workload
- Stock sitting in `Returns - WH` indicates returns waiting for processing.

### 8.4 Recall reporting
- Batch recall (consumed): derived from net movements into/out of client location warehouses.
- Tool accountability: serial numbers by warehouse.

---

## 9) Operational controls and gates (linking stock to tasks)
This connects stock rules to your Task system (Doc 10).

Key gates:
- Do not mark dispatch as complete until the dispatch stock movement is submitted.
- Do not start returns processing until warehouse drop-off photo evidence exists.
- Do not finalize returns until return movements are submitted with correct serial/batch.
- Do not invoice (surgery) until usage is derived and reconciled.

Posting-time rule (important for pickups):
- If the driver picks up returns at time T, but the Returns Team posts the stock movement later:
  - the pickup-related stock movement should reflect time T (so the ledger matches physical reality)
  - this backdating must be controlled by the Returns Team (not drivers)

---

## 10) Acceptance criteria
- At any time, you can state where stock physically is:
  - main
  - in delivery transit
  - at a client location (company-owned)
  - in return pickup transit
  - in returns processing
- Serial- and batch-tracked items have traceability on every movement.
- No stock remains “stuck” in transit warehouses without a visible operational reason/task.
