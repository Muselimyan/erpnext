# Doc 12 — Surgery Set Operational Workflow (End-to-End)

## 1) Purpose
Define the day-to-day operational workflow for **surgery set/box** cases from request → dispatch → usage → return pickup → returns receiving → invoicing.

This doc primarily describes the **per-surgery case** model (a `Surgery Case` is created, dispatched, returned, usage is derived on return).

It also supports a second model used by some client locations:
- **Permanent on-site surgery sets** (consignment-like): a complete set is kept at the client location at all times; after surgeries the client sends replenishment orders to restore the set; there is no per-surgery return pickup.

This doc focuses on:
- Which ERPNext documents you create at each step
- Which warehouses stock must move through
- Which tasks must exist and what they must contain
- How to guarantee accurate usage and invoicing.
  - In the per-surgery case model: **Delivered = Used + Returned** (with exact quantities)

This doc assumes the master data and model from:
- Doc 11 — Surgery Set Model

Operational note (important):
- A single client request/order may include:
  - multiple individual items
  - multiple surgery sets (multiple cases)
- Individual items may also be returned using the same return pickup logistics.

Recommended practice:
- Use one shared `Dispatch Group ID` for everything that goes out together on one delivery trip.
- Keep each surgery set in a separately labeled package (label includes Surgery Case ID) so returns can be allocated back correctly.

---

## 2) Core rules (must always be true)
### 2.1 Inventory location truth
- If items are physically at a client location (doctor or hospital) and still company-owned, they must be in the correct client location warehouse.
  - Example (doctor at hospital/branch): `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital/Branch Name> - WH`
  - Example (hospital client, no named doctor): `<Hospital Code> — <Hospital/Branch Name> - WH`

### 2.2 In-transit staging
- Outgoing dispatch staging warehouse: `Delivery In-Transit - WH`
- Return pickup staging warehouse: `Return Pickup In-Transit - WH`
- Do **not** create a warehouse per delivery person.

Important:
- Delivery trips can include both standard items and surgery cases; staging warehouses are used for both.

### 2.3 Reconciliation
For the per-surgery case model, for each surgery case and each item line:
- `Delivered Qty = Used Qty + Returned Qty + Lost/Damaged Qty`

For permanent on-site sets:
- The client replenishment order should represent the used/missing quantities that must be restored.

### 2.4 Usage is identified on return
This is the baseline rule for the per-surgery case workflow.

- When a client calls to schedule a return pickup, they typically do **not** provide usage quantities.
- Usage is identified when the package returns and is checked at `Returns - WH` (or `Main - WH`).

For permanent on-site sets:
- Usage is identified from the replenishment request/order (the client orders what was used/missing to restore the set).
- Traceability still matters: for batch/expiry items, usage posting must select the correct batch numbers that were consumed.

### 2.5 Capturing hospital + doctor context (no separate master)
Operational reality:
- Most clients are doctors (the doctor is the `Customer`).
- Some clients are hospitals (no named doctor).

Rule:
- Do not maintain a separate `Doctor` DocType for go-live.
- Capture optional context on operational documents:
  - `Hospital` (optional link to a hospital Customer)
  - `Doctor Name` (optional free text, used when the client is a hospital)

### 2.6 Serial + batch + expiry tracking (enforced where required)
Some items must be traceable:
- **Tools / instruments**: track by **Serial Number** where the instrument has a serial.
- **Implants / consumables**: track by **Batch (Lot)**, and store **Expiry Date** on the batch where applicable.

Operational meaning:
- Stock movements for tracked items must record the actual **serial numbers** and/or **batch numbers** that physically moved.
- Optional scan logs on the Surgery Case can still exist as evidence, but the **stock ledger is the source of truth** for recalls and accountability.

FEFO rule (critical):
- For expiry-tracked items, batch selection must follow **FEFO** (First-Expiry-First-Out).
- If a user selects a fresher batch while an older-expiring batch is available in `Main - WH`, the system must alert.

Control rule:
- The system should block closing a case until all dispatched serial-tracked tools are either:
  - returned (same serials), or
  - explicitly marked missing/damaged.

### 2.7 Stock availability policy (allow Draft, allow partial)
- You may create/save Surgery Cases in `Draft` even if stock is currently insufficient.
- The workflow must allow partial fulfillment of the Surgery Set Type template when stock is insufficient:
  - dispatch whatever is available
  - skip missing items
  - show a clear warning that some items were missing (including which items and missing quantities)

Additional gate due to serial/batch tracking:
- For serial/batch-tracked items, you must not consider a case “dispatched” until the dispatch Stock Entry is submitted with the actual serials/batches selected.



---

## 3) Roles / teams in this workflow
- **Order Team**: creates the case, coordinates client/hospital/doctor/date
- **Preparing Team**: prepares and packs the set (picking)
- **Delivery Team**: dispatch + delivery confirmation + return pickup
- **Returns Team**: receives and validates returned items
- **Accounting Team**: invoices used items and tracks receivables
- **Director Team**: approvals (discounts, purchasing, and monitoring receivable thresholds)

---

## 4) Records and documents used
### 4.1 Custom operational record (authoritative)
Create and use a custom DocType (recommended): **`Surgery Case`**.

Why:
- A single “case” needs to carry:
  - client location and optional hospital/doctor context
  - surgery date
  - set type (template)
  - dispatched quantities (planned at Step 0)
  - returned quantities (entered at returns receiving)
  - used quantities (computed)
  - status tracking and ownership

Minimum fields on `Surgery Case`:
- Client (Link → Customer)
- Hospital (Link → Customer)
- Hospital Branch (Data)
- Client Location Warehouse (Link → Warehouse) (derived from client + hospital + branch)
- Hospital (Link → Customer) (optional)
- Doctor Name (Data) (optional)
- Surgery Date (Date)
- Surgery Set Type (Link → Surgery Set Type)
- Status (Select)
- Delivery Person (Link → User)
- Return Pickup Delivery Person (Link → User)
- Notes

Recommended additional fields (to support “one order can contain multiple sets/items”):
- Dispatch Group ID (Data) (one ID shared across multiple Surgery Cases delivered together)
- Delivery Task (Link → Task) (optional)
- Return Pickup Task (Link → Task) (optional)

Recommended fields for soft barcode scanning (optional):
- Packed Scan Log (Long Text)
- Returned Scan Log (Long Text)

Recommended fields to link generated documents (so automation is idempotent and traceable):
- Dispatch Stock Entry (Link → Stock Entry)
- Delivery Stock Entry (Link → Stock Entry)
- Return Pickup Stock Entry (Link → Stock Entry)
- Return Receive Stock Entry (Link → Stock Entry)
- Consumption Stock Entry (Link → Stock Entry) (for used/consumed items, if you keep invoices batch-less)
- Sales Invoice (Link → Sales Invoice)

Minimum child tables on `Surgery Case`:
- **Case Items** (one unified items grid):
  - Item
  - Dispatched Qty
  - Returned Qty
  - Lost/Damaged Qty (optional)
  - Used Qty (computed, read-only)

This doc describes workflow assuming `Surgery Case` exists.

Permanent on-site sets note:
- If a client location keeps a set on-site, you may not create a `Surgery Case` per surgery.
- The operational truth becomes:
  - stock ledger position in the client location warehouse (what company-owned stock is at the client location)
  - consumption posting for used quantities
  - sales invoice for the used quantities (financial)
  - replenishment stock transfer into the client location warehouse

When a single client request includes standard items + one or more surgery cases:
- Standard items are handled using the standard selling documents (Sales Order / Invoice) defined in the selling docs.
- Surgery sets are handled using `Surgery Case`.
- Both are tied together operationally via:
  - shared `Dispatch Group ID`
  - shared delivery / pickup Tasks

### 4.2 Stock movement documents
Use **Stock Entry** for all warehouse-to-warehouse movement stages:
- `Main - WH` → `Delivery In-Transit - WH`
- `Delivery In-Transit - WH` → `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital/Branch Name> - WH`
- `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital/Branch Name> - WH` → `Return Pickup In-Transit - WH`
- `Return Pickup In-Transit - WH` → `Returns - WH` (and optionally to `Main - WH`)

Serial/batch requirement:
- For serial-tracked items, Stock Entry Items must carry the serial numbers.
- For batch-tracked items, Stock Entry Items must carry the batch numbers (and the batch has the expiry date).

Note:
- Stock Entries may be created either:
  - per Surgery Case, or
  - aggregated per delivery trip (recommended) using a shared `Dispatch Group ID`.

### 4.3 Sales documents
Use **Sales Invoice** to invoice **used** items.

Key rule:
- The invoice must only contain the **Used Items** quantities.

Implementation note (recommended to keep invoices batch-less):
- For batch-tracked items, recall and consumption tracking should rely on Stock Entries (delivered/returned/consumed by batch).
- Recommended pattern:
  - Post stock consumption with a Stock Entry (Material Issue) from the client location warehouse for the **used** quantities.
  - Create Sales Invoice as draft for the same used quantities, but treat it as a financial document (stock already handled).

---

## 5) Status model for `Surgery Case`
Recommended statuses (minimum):
1) Draft (created, not yet approved for preparation)
2) Preparing
3) Dispatch Picking (dispatch Stock Entry drafted; serial/batch selection happens here)
4) Dispatched (dispatch Stock Entry submitted; stock is in `Delivery In-Transit - WH`)
5) Delivered (delivery Stock Entry submitted; stock is in client location warehouse)
6) Return Pickup Scheduled
7) Return Pickup In Transit (logistics in progress)
8) Returns Verification (returns counted; return Stock Entries drafted and validated)
9) Returns Received (return Stock Entries submitted; stock is back in `Returns - WH`)
10) Usage Derived
11) Invoiced
12) Closed

Notes:
- Your team may combine some steps, but the stock movement checkpoints must remain correct.

### 5.1 Role-based sequential status changes (no jumps)
Statuses must be enforced through an ERPNext **Workflow** on `Surgery Case`:
- Only the next status transition is allowed (no skipping).
- Transitions are role-based; not everyone can change all statuses.
- In practice this means users do not manually “edit status”; they use workflow actions.

Practical rule:
- For each status transition, there should be a corresponding **Task assigned to a specific person**, so it is always clear who must act next.

Recommended role ownership (minimum):
- Draft → Preparing: Order Team / Coordinator
- Preparing → Dispatch Picking: Preparing Team
- Dispatch Picking → Dispatched: Preparing Team (after warehouse submits the dispatch Stock Entry)
- Dispatched → Delivered: Delivery Coordinator (after confirming delivery)
- Delivered → Return Pickup Scheduled: Coordinator
- Return Pickup Scheduled → Return Pickup In Transit: Delivery Coordinator (after driver completes pickup task)
- Return Pickup In Transit → Returns Verification: Returns Team
- Returns Verification → Returns Received: Returns Team (after return Stock Entries are submitted)
- Returns Received → Usage Derived: Returns Team
- Usage Derived → Invoiced: Accounting Team
- Invoiced → Closed: Coordinator / Accounting

---

## 6) End-to-end workflow (step-by-step)

### Step 0 — Create the Surgery Case (Order Team)
When: as soon as the client requests a surgery set.

Important:
- If an order includes multiple surgery sets, create **one `Surgery Case` per set instance**.
- If the same delivery trip includes both normal items and surgery sets, use a shared `Dispatch Group ID` so the delivery task can cover everything in one trip.

1) Create a new `Surgery Case`.
2) Fill:
   - Client (Customer)
   - Hospital
   - Hospital Branch
   - Doctor Name (optional)
   - Surgery Date
   - Surgery Set Type
3) Load the template and decide the **planned dispatch quantities** now (single source of truth):
   - Use the linked `Surgery Set Type` as a suggested checklist.
   - If stock is insufficient to fill the template fully:
     - set Dispatched Qty to what is available
     - omit/skip missing items
     - show a warning listing missing items and missing quantities
   - Fill the **Case Items** table with the exact items/qty you intend to send (Dispatched Qty).
   - If you dispatch items that are not in the template, add them here.
4) System/Operator must ensure the correct Client Location Warehouse is set:
   - `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital/Branch Name> - WH`
5) Set Status = `Draft`.
6) Save.

Outputs:
- A unique Surgery Case ID that will be referenced in all later steps.

Control:
- Hospital and Hospital Branch are required so stock can be posted to the correct location warehouse.
- Doctor Name is optional.

Locking rule (recommended):
- After the case leaves `Draft`, Dispatched Qty must become read-only to everyone.
- Any increase should require returning to `Draft` (or a controlled “Amend” step) so stock documents remain consistent.
- If stock is insufficient at `Dispatch Picking`, a controlled reduction of Dispatched Qty is allowed, but it must produce a clear warning and be traceable.


### Step 1 — Automated debt threshold alert (no manual step)
When: continuously (automated).

Goal:
- No one manually checks debt before each case.
- If a client’s debt exceeds its threshold, the system creates (or updates) a **Debt Collection** task for directors.

Automation behavior:
- If `Outstanding Debt > Threshold` and there is **no open debt-collection task** yet:
  - create a Task for directors.
- If the task already exists:
  - update it with the latest outstanding debt.

Note:
- This is **alerting**, not automatic blocking. Blocking rules (if desired) should be defined separately.


### Step 2 — Prepare the set (Preparing Team)
When: after the case is approved to proceed.

1) Open the `Surgery Case`.
2) Set Status = `Preparing`.
3) Use the linked `Surgery Set Type` as a checklist for packing.
4) Pack exactly what is listed in **Case Items** (Dispatched Qty).
   - If the template was short, missing items are not packed.
5) Optional: scan barcodes into the case’s Packed Scan Log.

Note:
- For serial/batch-tracked items, the authoritative selection of serials/batches happens on the dispatch Stock Entry in Step 3.

Control:
- Every dispatched item must be an ERPNext Item.
- Quantities must be explicit.


### Step 3 — Dispatch picking + submit dispatch Stock Entry (serial/batch selection happens here)
Goal: represent items packed and handed for delivery, with correct serial/batch traceability.

Action (Preparing Team):
1) Click workflow action to move the case to `Dispatch Picking`.

System automation (required):
- Create the dispatch Stock Entry as **Draft**:
  - `Main - WH` → `Delivery In-Transit - WH`
  - Items/Qty copied from the case’s **Case Items** (Dispatched Qty)
  - Linked back to the Surgery Case (and optionally Dispatch Group ID)

Warehouse action (required for traceable items):
1) Open the draft dispatch Stock Entry.
2) Select actual:
   - serial numbers (for serial-tracked tools/instruments)
   - batch numbers (for batch-tracked implants/consumables)
3) Submit the Stock Entry.

FEFO control:
- For expiry-tracked items, batch selection must follow FEFO.
- If a fresher batch is selected while an older-expiring batch is available in `Main - WH`, the system must alert.

Then update the case:
- Click workflow action to move the case to `Dispatched`.

Gates:
- If stock became insufficient after planning (example: another case consumed stock), reduce Dispatched Qty to what is available and show a clear warning listing missing items.
- If the dispatch Stock Entry is not submitted, the case must not be allowed to enter `Dispatched`.

Notes:
- Default approach: one Stock Entry per Surgery Case.
- If you later want one Stock Entry per delivery trip (multiple cases/items), implement it using `Dispatch Group ID`.


### Step 4 — Assign delivery person + delivery task (automated)
Goal: assign the work to a **specific** delivery person (not the whole team).

Action:
1) Dispatch Coordinator selects the delivery person (assignee) and planned time.
2) Clicks the workflow action / button to create the Delivery Task.

System automation (required):
- Create (or update) a Delivery Task assigned to that delivery person.
- Link the task to the Surgery Case (or to Dispatch Group ID if delivering multiple cases together).

Control:
- Delivery Person must be filled, so reporting can group in-transit stock by person.

### Step 5 — Confirm delivery to client location warehouse (driver-friendly)
Goal: drivers should not need detailed ERPNext knowledge.

Driver action (few clicks):
1) Open the assigned delivery Task.
2) Attach the Warehouse Pickup Photo (taken at `Main - WH` pickup, after packing, before leaving).
3) On delivery, record a short handover note (example: who it was handed to).
4) Mark as completed (optionally attach delivery proof photo if you decide later).

Back-office action (Delivery Coordinator):
1) Click the workflow action to move the case to `Delivered`.

System automation (required):
- On transition to `Delivered`, the system creates and submits the delivery Stock Entry:
  - `Delivery In-Transit - WH` → the client location warehouse
  - Items/Qty copied from **Case Items** (Dispatched Qty)
  - Linked back to the Surgery Case (and optionally Dispatch Group ID)

Serial/batch control:
- The delivery Stock Entry must carry the same serial numbers / batch numbers that were submitted on the dispatch Stock Entry.


### Step 6 — Client requests return pickup (no usage provided)
When: client calls and asks you to schedule pickup.

Key point:
- Do not ask for “used quantities” as a required input.
- Usage will be derived when the package returns and is checked by the Returns Team.


### Step 7 — Schedule return pickup task (Coordinator)
Goal: ensure returns are picked up and returned to the warehouse.

Action:
1) Coordinator selects the Return Pickup Delivery Person.
2) Coordinator clicks the workflow action to move the case to `Return Pickup Scheduled`.

System automation (required):
- Create (or update) a `Pickup Returns` Task assigned to that delivery person.
- Link it to what is being picked up:
  - Surgery Case(s) (if known), and/or
  - Dispatch Group ID (recommended)

Additional automation (required):
- Create (or update) a `Return drop-off at warehouse` Task assigned to that delivery person.
- Enforce that return drop-off Tasks cannot be completed without a Drop-off Photo attachment.


### Step 8 — Pickup returns (driver-friendly)
Goal: pickup should be few clicks; driver should not create stock documents.

Driver action (few clicks):
1) Open assigned `Pickup Returns` Task.
2) Mark task completed.

Back-office action (Delivery Coordinator):
- After the driver completes the pickup task, move the case(s) to the next workflow step.

Update the case(s):
- Status = `Return Pickup In Transit`

### Step 8A — Return drop-off at warehouse (driver-friendly)
Goal: capture evidence at the warehouse handoff.

Driver action:
1) Open assigned `Return drop-off at warehouse` Task.
2) Attach the required Drop-off Photo (taken before handing the package to the Returns Team).
3) Mark task completed.


### Step 9 — Receive and count returns (Returns Team)
Goal: receiving is where quantities become known; this is where usage is identified.

Control:
- Returns processing should not start until the `Return drop-off at warehouse` task is completed with a Drop-off Photo.

At the warehouse, open the package and count unused items.

Allocation rule (important):
- If one pickup contains multiple surgery cases, the Returns Team must allocate the returned quantities back to the correct Surgery Case.
- This requires that packages are labeled (Surgery Case ID on the box) or otherwise clearly separated.

Action (single data entry point):
1) Returns Team fills the **Case Items** table on the Surgery Case (Returned Qty) with counted quantities.
2) Optional: scan returned barcodes into the case’s Returned Scan Log.
3) Returns Team moves the case to `Returns Verification`.

System automation (required):
- Create the return Stock Entries as **Draft**, based on Returned Qty:
  1) client location warehouse → `Return Pickup In-Transit - WH`
     - Posting Date/Time = pickup time (from the pickup Task)
  2) `Return Pickup In-Transit - WH` → `Returns - WH` (or `Main - WH`)
     - Posting Date/Time = receipt time

Returns Team action (required for traceable items):
1) Open the draft return Stock Entries.
2) Confirm actual:
   - returned serial numbers (for serial-tracked tools/instruments)
   - returned batch numbers (for batch-tracked implants/consumables)
3) Submit the return Stock Entries.
4) Move the case to `Returns Received`.

Gates:
- The case must not be allowed to enter `Returns Received` until the return Stock Entries are submitted.

Serial/batch defaults (recommended):
- The system may pre-fill return Stock Entry batch/serial details based on what was delivered for that case, but Returns Team must confirm.

Note:
- This is the only step where quantities are newly entered after Step 0.

Optional (if you use `Returns - WH` as a staging location):
- After checking, move items from `Returns - WH` to `Main - WH` via Stock Entry.


### Step 10 — Derive usage and reconcile (Returns Team)
Goal: enforce the main truth: Delivered = Used + Returned (+ Lost/Damaged).

Action:
1) Returns Team clicks the workflow action to move the case to `Usage Derived`.

System automation (required):
- On transition to `Usage Derived`, the system:
  - computes `Used Qty = Delivered Qty - Returned Qty - Lost/Damaged Qty`
  - writes the computed quantities into **Case Items** (Used Qty)
  - flags discrepancies (if any) for review

Additional automation (recommended for batch recall + invoice simplicity):
- Create and submit a **Consumption Stock Entry** (Material Issue) from the client location warehouse for the **used** quantities.
- For batch-tracked items, the consumption Stock Entry must carry batch numbers derived as:
  - delivered (by batch) − returned (by batch)

FEFO control:
- For expiry-tracked items, consumption posting must follow FEFO-derived batch usage (do not consume fresher batch if older-expiring batch is what was actually used first).

Controls:
- Do not proceed to invoicing until reconciliation is acceptable.


### Step 11 — Create Sales Invoice for used items only (Accounting Team)
Goal: invoice exactly what was used (financial document).

Action:
1) Accounting clicks the workflow action to create the invoice.

System automation (required):
- The system generates a draft Sales Invoice:
  - Customer = client
  - Items/Qty copied from **Case Items** (Used Qty)
  - Hospital / Doctor Name copied from the Surgery Case when present
  - Linked back to the Surgery Case

Recommended stock rule (to keep invoices batch-less):
- Stock reduction should already be handled by the Consumption Stock Entry in Step 10.
- The Sales Invoice is then reviewed/submitted as a financial document.

Accounting finalization:
- Review and submit the invoice.

Update the case:
- Status = `Invoiced`

Receivables / debt control:
- The client’s unpaid balance increases.
- Directors should be alerted if the threshold is exceeded.

### Step 11A — Distribute Payment (Directors)
When: after payment is received and confirmed according to your internal control policy.

Operational rule:
- A Director-owned `Distribute Payment` task must be created/maintained for each payment event that requires distribution.

Note:
- This step is financial-control only. It does not change stock.
- It is not a gate for operational case closure; it may happen long after the case is `Closed`.


### Step 12 — Close the case (Order/Returns/Accounting)
Goal: close only when stock + invoice are correct.

Pre-close checklist:
- Returns received recorded
- Used items invoiced
- Reconciliation matches

Additional strict control for tools:
- All serial-tracked tools dispatched for the case are accounted for as:
  - returned serials, and/or
  - missing/damaged serials (explicitly recorded)

1) Set Status = `Closed`.

---

## 6A) Permanent on-site sets (alternative operating model)
This section applies only to client locations that keep a complete surgery set on-site at all times.

Key differences vs a Surgery Case:
- No per-surgery dispatch and no return pickup.
- Client location warehouse stock can be long-lived (still company-owned).
- The client orders replenishment after surgeries to restore the set.

### 6A.1 Initial placement of the permanent set (one-time)
Goal: establish the baseline set stock at the client location as company-owned stock.

Stock movement model:
- `Main - WH` → `Delivery In-Transit - WH` → the client location warehouse

### 6A.2 Replenishment cycle (repeat after usage)
Goal: bill for what was used and restore the set stock at the client location.

Operational pattern:
1) Client sends a replenishment order (what was used/missing).
2) Warehouse posts consumption from the client location warehouse for the used quantities.
3) Accounting invoices the used quantities (regular selling documents).
4) Warehouse delivers replenishment stock into the client location warehouse using Stock Entry movements (same staging model as deliveries).

---

## 7) Exceptions / edge cases (define your rule and follow it)
### 7.1 Returns in multiple trips
- Repeat Steps 7–9 for each pickup.
- Returned Items should be the total sum of all received quantities.

### 7.2 Additional items delivered after initial dispatch
Two acceptable approaches (choose one policy and apply consistently):
- Add a second dispatch Stock Entry and add those quantities to Dispatched Items; or
- Require a new Surgery Case (if you want one surgery = one case strictly).

### 7.3 Lost / damaged items
- Record on the case as Lost/Damaged.
- Decide whether you invoice the client for lost/damaged items (policy).

### 7.4 Case cancelled before delivery
- If stock is already in `Delivery In-Transit - WH`, transfer back to `Main - WH`.
- Close case as Cancelled (if you implement a Cancelled status).

### 7.5 Individual (non-surgery-set) item returns
Sometimes clients return individual items (wrong item, extra item, unopened item, etc.).

Logistics (same approach as surgery returns):
- Use the same return pickup Task + staging warehouses.
- Stock moves:
  - client location warehouse → `Return Pickup In-Transit - WH` → `Returns - WH`.

Accounting note:
- The financial document handling (credit note / return invoice logic) will be defined in the standard selling docs, but the pickup/stock movement logistics remain the same.

---

## 8) Operational reporting produced by this workflow
- Items at each client location (company-owned at client): Stock Balance for the relevant client location warehouse
- Items currently in delivery transit: Stock Balance for `Delivery In-Transit - WH`
- Items currently in return pickup transit: Stock Balance for `Return Pickup In-Transit - WH`
- Unpaid invoices per client
- Clients exceeding their debt threshold

Additional reporting enabled by serial/batch tracking:
- Batch recall (consumed): for a recalled batch/lot, list the clients/cases with net consumption > 0
- Tool accountability: list which serial-tracked instruments are currently at each client location / in transit / missing

---

## 9) Acceptance criteria
- For any surgery case, you can list exactly:
  - what was dispatched
  - what was returned
  - what was used
  - what was invoiced
- For any client location with a permanent on-site set, you can see:
  - baseline company-owned stock at that client location
  - stock reductions for usage
  - replenishment deliveries that restore stock
  - invoices representing used quantities
- At any moment, you can answer:
  - “What items are currently at Client X?”
  - “What items are currently in transit and with which delivery person (derived)?”
  - “What does Client X owe us?”
- The system supports reconciliation:
  - Delivered = Used + Returned (+ Lost/Damaged)
- Delivery tasks capture warehouse-pickup photo evidence.
- Return drop-off tasks capture warehouse drop-off photo evidence.

Serial/batch acceptance:
- Dispatch cannot be finalized unless serials/batches are recorded for tracked items.
- Returns cannot be finalized unless returned serials/batches are recorded for tracked items.
- A recall by batch can identify clients/cases with net consumption of that batch.
