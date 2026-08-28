# 16 — Unified Dispatch Flow

## 1. Overview

All order types — standard sales and surgery cases — are handled through a single unified workflow called the **Dispatch Case**. Every team member works primarily from their task inbox. Order Creation creates, submits, and links the Dispatch Case. Inventory prepares products from the Pack task. Barcode/Product Work Area behavior is optional/future until tracking is re-enabled. Returns may open the Dispatch Case or use the task return summary to record returned quantities.

The Dispatch Case is the coordinator record. It holds item quantities, links to all generated stock entries and invoices, and tracks state. Field teams never need to understand its internals.

Stock Entries are created and submitted automatically by server scripts when task states change. Finance never touches ERPNext Payment Entry forms — those are auto-created in the background from task data.

---

## 2. Core Concepts

### 2.1 Dispatch Case

The Dispatch Case replaces both the Sales Order and the Surgery Case. It is the single coordinator record for every delivery operation regardless of type.

Key behavioral difference based on the **Return Expected** flag:
- **Return Expected = No** — after delivery is confirmed, all dispatched items are treated as sold. Invoice is created automatically for full quantities. No returns workflow.
- **Return Expected = Yes** — after delivery, the flow pauses waiting for the client to call about returning items. Returned quantities are inspected and recorded. Invoice covers only the used portion.

### 2.2 Team User Pattern

For each role there is a dedicated **team user** in ERPNext named after that role (e.g., `Delivery Team`, `Inventory Team`). Every person who holds the corresponding role can see tasks assigned to the team user in their own inbox. When someone picks up a task, they click **Accept / Start Task**. The task records the accepting user and becomes workable for that user. The Accept button disappears for the user who accepted it, while users who have not accepted still see their own Accept button. Default assignment for all auto-created tasks is the team user, unless the creating person explicitly assigns to an individual.

### 2.3 Task-Driven Principle

Every state change in a Dispatch Case is triggered by a task completion or state change. Users complete tasks with the red **Complete Task** button near the Status field. Completing a task causes a server script to:
1. Advance the Dispatch Case to the next state
2. Auto-submit any required Stock Entry, Payment Entry, or other downstream document
3. Create the next task in the chain

---

## 3. Roles and Team Users

| Role | Team User | Responsibilities |
|---|---|---|
| `Ops - Order Accepting` | Order Acceptance Team | Receives client calls/messages; creates Order entry tasks |
| `Ops - Order Creating` | Order Creation Team | Picks up Order entry tasks; creates and submits Dispatch Cases |
| `Ops - Directors` | Directors Team | Approves or rejects discount approval tasks |
| `Ops - Inventory` | Inventory Team | Packs shipments; batch/serial tracking is temporarily disabled until barcode tracking is re-enabled |
| `Delivery Driver` | Delivery Team | Picks up and delivers; handles return pickups |
| `Ops - Returns` | Returns Team | Coordinates return pickups; inspects and records returned items; restocks |
| `Ops - Accounting` | Accounting Team | Reviews and submits auto-created invoices |
| `Ops - Finance` | Finance Team | Records incoming payments; manages debt collection per customer |

---

## 4. Dispatch Case DocType

### 4.1 Header Fields

| Field | Type | Description |
|---|---|---|
| `customer` | Link → Customer | The client/doctor receiving the dispatch |
| `client_location_warehouse` | Link → Warehouse | Client-side warehouse for returnable items |
| `return_expected` | Checkbox | Whether items are expected to come back |
| `surgery_date` | Date | For surgery cases; optional for standard sales |
| `surgery_set_type` | Link → Collection Set | Optional template; populates Case Items when selected |
| `status` | Select | Current state (see Section 10) |
| `order_entry_task` | Link → Task | The originating Order entry task |
| `discount_approval_task` | Link → Task | Director approval task (if discount present) |
| `discount_approval_status` | Select | Pending / Approved / Rejected |

### 4.2 Case Items Table

Each row represents one item in the dispatch. Columns:

| Column | Description |
|---|---|
| `item_code` | Link → Item |
| `item_name` | Auto-filled |
| `dispatched_qty` | Quantity planned for dispatch |
| `serial_no` | Serial number(s) — temporarily not required while serial tracking is disabled |
| `batch_no` | Batch number — temporarily not required while batch tracking is disabled |
| `unit_price` | Price per unit |
| `discount_pct` | Discount percentage (triggers approval if > 0) |
| `returned_qty` | Filled by Returns team at inspection |
| `lost_damaged_qty` | Filled by Returns team at inspection. Billed as a fee at `unit_price`/`discount_pct` (same rate as a used item) — see §9A "Lost/Damaged Billing Policy". |
| `used_qty` | Auto-computed: `dispatched_qty - returned_qty - lost_damaged_qty` |

### 4.3 Payment Fields

| Field | Description |
|---|---|
| `prepaid_amount` | Amount already paid upfront before dispatch |
| `prepaid_payment_entry` | Link to the advance Payment Entry |
| `total_invoice_amount` | Auto-filled from submitted Sales Invoice |
| `total_paid_amount` | Tracked from linked Payment Entries |
| `outstanding_amount` | `total_invoice_amount - total_paid_amount` |

### 4.4 Linked Documents

| Field | Description |
|---|---|
| `dispatch_stock_entry` | SE: Main → Delivery In-Transit |
| `delivery_stock_entry` | SE: Delivery In-Transit → Client WH |
| `consumption_stock_entry` | SE: Client WH → out (Material Issue for used items) |
| `return_pickup_stock_entry` | SE: Client WH → Return Pickup In-Transit |
| `return_receive_stock_entry` | SE: Return Pickup In-Transit → Returns WH |
| `restock_stock_entry` | SE: Returns WH → Main WH |
| `sales_invoice` | The final Sales Invoice |

---

## 5. Item Templates

The Dispatch Case has a **"Load from Template"** button that populates the Case Items table from a Collection Set. The template defines default items and quantities. Templates are used for surgery sets and for any frequently-ordered product bundles.

After loading, the Order Creation person can:
- Adjust quantities
- Add items not in the template
- Remove items
- Set prices and discounts

Templates are not mandatory — the items table can be filled manually.

---

## 6. Full Task Chain

### Task 6.1 — Order Entry (Order Acceptance → Order Creation)

**Kind:** `Order entry`
**Default assignee:** Order Creation Team
**Created by:** Order Acceptance person manually, when a client call or message is received

**Contains:**
- Free text description of what was requested (items, quantities, client, delivery date)
- Any relevant context from the call

**Actions:**
- Order Creation team member clicks **Accept / Start Task**
- Creates a Dispatch Case (see Section 7)
- Adds at least one item row to the Case Items table
- Saves and submits the Dispatch Case
- Links the submitted case to this task
- Clicks the red **Complete Task** button

**Completes when:** Dispatch Case is linked to this task and already submitted. If the case is missing, completion is blocked with `Link a Dispatch Case before completing the Order entry task.` If the case is not submitted, completion is blocked with `Submit the Dispatch Case before completing the Order entry task.`

---

### Task 6.2 — Discount Approval (conditional)

**Kind:** `Discount Approval`
**Default assignee:** Directors Team
**Created by:** server script when Dispatch Case is saved with any item having `discount_pct > 0`

**Condition:** Only created if the Dispatch Case has at least one discounted item. The case stays in `Awaiting Approval` state and cannot be submitted until this task is resolved.

**Contains:**
- Link to the Dispatch Case
- List of discounted items with their prices and discount percentages

**Actions:**
- Director reviews the discount request
- Sets `approval_outcome` on the task to **Approved** or **Rejected**
- Marks task Completed

**On Approved:** Server script submits the Dispatch Case → state becomes `Confirmed` → Pack task created (Task 6.3)

**On Rejected:** Server script creates a new `Order entry` task assigned to the Order Creation Team, linked to the same Dispatch Case, with a note "Discount rejected — please revise pricing." The Dispatch Case remains in `Draft`.

---

### Task 6.3 — Pack / Prepare Items

**Kind:** `Pack / prepare items`
**Default assignee:** Inventory Team
**Created by:** Dispatch Case submission (or discount approval if applicable)

**Contains:**
- Subject: `Pack: [Case ID] — [Customer]`
- Link to Dispatch Case
- Case Items list (items, quantities, descriptions — no prices shown)
- Client Location Warehouse (destination reference)

**Actions:**
- Inventory team member clicks **Accept / Start Task**
- Physically assembles the shipment box according to the items list
- Prepares products physically according to the Dispatch Case item rows
- Saves the Task or Dispatch Case as needed

**Current temporary tracking state:**
- Batch, serial, and expiry requirements are temporarily disabled for all Items.
- The Pack task should not require Batch No, Serial No, or Expiry Date to complete.
- Barcode/Product Work Area behavior is optional/future until tracking is re-enabled.

**Before clicking Complete Task:**
- ✅ Products are physically prepared according to the Dispatch Case item rows

**On Completion:**
- Server script auto-creates and auto-submits **Dispatch Stock Entry**: `Main → Delivery In-Transit`, using the Case Items
- Case state → `Packed`
- **Task 6.4** (Delivery) created for Delivery Team

---

### Task 6.4 — Delivery (multi-state)

**Kind:** `Delivery`
**Default assignee:** Delivery Team
**Created by:** completion of Task 6.3

**Contains:**
- Subject: `Deliver: [Case ID] — [Customer]`
- Client name, delivery address, client location warehouse name
- Items list (descriptions and quantities — no prices)
- Link to Dispatch Case (for reference only)
- `delivery_status` field: `Todo → Picked Up → Delivered`
- ~~Photo attachment field~~ (Doc 18: Delivery tasks have no photos)
- Handover note field (visible when status = `Picked Up`)

**State transitions:**

**Todo → Picked Up** (driver physically picks up the box from the warehouse):
- Driver taps "Mark as Picked Up"
- No Stock Entry fires at this stage.
  *(Stock was already moved from Main → Delivery In-Transit by the Pack task. At Picked Up, items are physically with the driver and remain in Delivery In-Transit.)*
- Case state → `In Transit`
- Handover Note field becomes visible

**Picked Up → Delivered** (driver has handed items to client):
- ~~Driver may attach delivery photo (optional)~~ — **Superseded by Doc 18:** Delivery tasks have no photo requirement or photo field. Photo evidence is on the Pack task.
- Driver fills Handover Note (who received the items)
- Driver taps "Mark as Delivered"
- **SE auto-submitted:** `Delivery In-Transit → Client Location Warehouse`
- Case state → `Delivered`
- ~~If a photo is attached, it is also written to `delivery_photo` field on Dispatch Case~~ (Doc 18: no delivery photo)

**On Delivered — two paths:**

**If `return_expected = No`:**
- Server script auto-submits **Consumption Stock Entry**: `Client Location Warehouse → (Material Issue / out)` for all dispatched items
- Sets `used_qty = dispatched_qty` for all Case Items rows
- Auto-creates draft **Sales Invoice** for full dispatched quantities
- Case state → `Invoice Pending`
- **Task 6.9** (Invoice Preparation) created for Accounting Team

**If `return_expected = Yes`:**
- Case state → `Awaiting Return Pickup`
- **Task 6.5** (`Return Call`) created for the office/returns workflow

---

### Task 6.5 — Return Call (return expected cases only)

**Kind:** `Return Call`
**Default assignee:** Office Team
**Created by:** Delivery task completion when `return_expected = Yes`

**Contains:**
- Subject: `Return call: [Customer] ([Case ID])`
- Client name and contact information
- Items list (what was dispatched — what to expect back)
- Link to Dispatch Case

**Actions:**
- Returns team monitors for client call confirming items are ready for pickup
- When client calls, fills in the `return_pickup_driver` field (who will go pick up)
- Fills `scheduled_return_date`

**On Completion:**
- Case state → `Return Pickup Scheduled`
- **Task 6.6** (Return Pickup) created for the named driver, with `scheduled_return_date` as due date

---

### Task 6.6 — Return Pickup (multi-state)

**Kind:** `Pickup Returns`
**Default assignee:** Named driver from Task 6.5 (or Delivery Team if unassigned)
**Created by:** completion of Task 6.5

**Contains:**
- Subject: `Pickup Returns: [Case ID] — [Customer]`
- Client name, pickup location (client location warehouse address)
- Items list (what to collect)
- `pickup_status` field: `Todo → Picked Up → Returned to Warehouse`
- Photo attachment field (visible when status = `Picked Up`)
- Handover note field (who handed the items at client location)

**State transitions:**

**Todo → Picked Up** (driver collects items from client location):
- Driver taps "Mark as Picked Up"
- Fills Handover Note (who handed the items over)
- **SE auto-submitted:** `Client Location Warehouse → Return Pickup In-Transit`
- Case state → `Return In Transit`

**Picked Up → Returned to Warehouse** (driver delivers items to company warehouse):
- Driver attaches drop-off photo (required — cannot advance without photo)
- Driver taps "Mark as Returned to Warehouse"
- **SE auto-submitted:** `Return Pickup In-Transit → Returns WH`
- Case state → `Returns Received`
- ~~Photo is also written to `return_dropoff_photo` field on Dispatch Case~~ (Doc 18: DC shows photos via live gallery from Task)
- **Task 6.7** (Returns Inspection) created for Returns Team

---

### Task 6.7 — Returns Inspection

**Kind:** `Returns processing / verification`
**Default assignee:** Returns Team
**Created by:** Return Pickup task completion

**Contains:**
- Subject: `Inspect returns: [Case ID] — [Customer]`
- Link to Dispatch Case (must be opened to fill quantities)
- Items list with `dispatched_qty` per item (for reference)

**Actions:**
- Returns team member opens the linked Dispatch Case
- In the Case Items table, fills in for each item:
  - `returned_qty` — how many physically came back
  - `lost_damaged_qty` — any missing or damaged
- Saves the Dispatch Case (system auto-computes `used_qty = dispatched_qty - returned_qty - lost_damaged_qty`)

**Before marking Completed:**
- ✅ All Case Items rows have `returned_qty` filled (can be 0)
- ✅ `used_qty ≥ 0` for all rows (system validates — negative means data error)

**On Completion:**
- Server script auto-submits **Consumption Stock Entry**: `Returns WH → (Material Issue / out)` for `used_qty` of each item (all items were moved to Returns WH by the Return Pickup flow; used items are written off from there). Lost/damaged items remain in Returns WH pending manual review (see §9A).
- Auto-creates draft **Sales Invoice** for `used_qty` only — lost/damaged quantities are not auto-invoiced
- Case state → `Invoice Pending`
- **Task 6.8** (Restock) created for Returns Team (if any items have `returned_qty > 0`)
- **Task 6.9** (Invoice Preparation) created for Accounting Team

---

### Task 6.8 — Restock Returned Items

**Kind:** `Returns restocking`
**Default assignee:** Returns Team
**Created by:** completion of Task 6.7 (only if at least one item has `returned_qty > 0`)

**Contains:**
- Subject: `Restock returns: [Case ID]`
- Items list with `returned_qty` per item (what to put back on shelves)
- Source: Returns WH → destination: Main WH

**Actions:**
- Returns team member physically moves items from Returns WH back to Main shelf locations

**On Completion:**
- **SE auto-submitted:** `Returns WH → Main WH` for all items with `returned_qty > 0`

*Note: this task runs in parallel with Task 6.9. Invoice preparation does not wait for restocking.*

---

### Task 6.9 — Invoice Preparation

**Kind:** `Invoice preparation / create invoice`
**Default assignee:** Accounting Team
**Created by:** completion of Task 6.4 (Delivery task, Delivered state — no-return path) or Task 6.7 (return path)

**Contains:**
- Subject: `Invoice: [Case ID] — [Customer]`
- Link to auto-created draft Sales Invoice
- Used quantities summary per item (from Case Items `used_qty`)

**Actions:**
- Accounting team member opens the linked Sales Invoice
- Verifies:
  - Items and quantities match `used_qty` from Case Items
  - `Update Stock` is **unchecked** (stock already moved by Consumption SE)
  - Prices and taxes are correct
  - Payment terms are correct
- Submits the Sales Invoice

**Before marking Completed:**
- ✅ Sales Invoice is `Submitted`

**On Completion:**
- System checks outstanding amount = `invoice_total - prepaid_amount`
- **If outstanding > 0:** Case state → `Payment Pending`; Task 6.10 (Debt Collection) created or updated for Finance Team
- **If outstanding = 0** (fully pre-paid): Case state → `Closed`

---

### Task 6.10 — Debt Collection

**Kind:** `Debt Collection`
**Default assignee:** Finance Team
**Created by:** Invoice submission when outstanding amount > 0

**One active task per customer at any time.** If a Debt Collection task already exists for this customer, the new case's outstanding amount is added to the existing task's running balance rather than creating a new task.

**Contains:**
- Customer name
- **Open invoices table** (per Dispatch Case):
  | Case ID | Invoice | Invoice Amount | Paid | Outstanding |
  |---|---|---|---|---|
  | SC-001 | INV-001 | 1 000 | 0 | 1 000 |
  | SC-002 | INV-002 | 2 000 | 0 | 2 000 |
  | SC-003 | INV-003 | 3 000 | 1 500 | 1 500 |
- **Total outstanding** (sum)
- **Available advance credit** (from any unallocated advance payments)
- **Record Payment** section (see below)

**Recording a payment:**
Finance fills in:
- Amount received
- Payment method (Cash / Bank Transfer / Card)
- Payment reference number (bank transaction ID, receipt number, etc.)

**Allocation (FIFO with override):**
- Default: system auto-allocates to oldest invoices first. Finance sees the proposed allocation and can confirm in one click.
- Override: Finance can expand the allocation table and manually specify how much to apply to each invoice. Any unallocated remainder can be marked as advance credit for future cases.

**Completing the task:**
The Debt Collection task is marked Completed only when total outstanding = 0 for all cases it covers. It can be updated multiple times as partial payments arrive.

**On each payment recorded:**
- Server script auto-creates a draft **Payment Entry** in ERPNext with the specified allocation
- **Task 6.11** (Distribute Payment) created for Finance Team for physical payment handling
- Accounting team submits the auto-created Payment Entry (they never contact Finance about this)

**On full payment (outstanding = 0):**
- Case(s) state → `Closed`
- Task auto-completes

---

### Task 6.11 — Distribute Payment

**Kind:** `Distribute Payment`
**Default assignee:** Finance Team
**Created by:** each time a payment is recorded on the Debt Collection task

**Contains:**
- Amount received
- Payment method
- What to do: take cash to bank / confirm bank transfer to correct account / etc.
- Link to the auto-created Payment Entry (for reference)

**Actions:**
- Finance performs the physical payment action (bank deposit, account transfer, etc.)
- Marks task Completed when done

*This task does not affect the Dispatch Case state.*

---

### Task 6.12 — Payment Received (advance payments)

**Kind:** `Payment Received`
**Default assignee:** Finance Team
**Created by:** Finance manually, when money arrives before any invoice exists

**Contains:**
- Customer name
- Amount received
- Payment method and reference
- Option: "Apply to upcoming case" (link to a specific Dispatch Case) or "Hold as advance credit"

**On Completion:**
- Server script auto-creates a **Customer Advance Payment Entry** in ERPNext (not linked to any invoice)
- Customer's available advance credit is updated
- If a Debt Collection task exists for this customer, it reflects the credit and reduces the required collection amount
- If a specific Dispatch Case is linked and it has a `prepaid_amount` set, the advance is noted on the case

---

## 7. Stock Entry Movement Summary

| Trigger | From | To | Type |
|---|---|---|---|
| Pack task Completed | Main WH | Delivery In-Transit | Material Transfer |
| Delivery task → Picked Up | *(no SE — items already in Delivery In-Transit)* | | |
| Delivery task → Delivered | Delivery In-Transit | Client Location WH | Material Transfer |
| Delivery Delivered (no return) | Client Location WH | — | Material Issue (Consumption) |
| Return Pickup task → Picked Up | Client Location WH | Return Pickup In-Transit | Material Transfer |
| Return Pickup task → Returned to Warehouse | Return Pickup In-Transit | Returns WH | Material Transfer |
| Returns Inspection Completed | Returns WH | — | Material Issue (`used_qty` only; `lost_damaged_qty` stays in Returns WH for manual review) |
| Restock task Completed | Returns WH | Main WH | Material Transfer |

All SEs are auto-created and auto-submitted by server scripts. No team member ever opens a Stock Entry form.

---

## 8. Payment Entry Auto-Creation

Finance never interacts with ERPNext Payment Entry forms. All Payment Entries are created automatically:

| Trigger | Payment Entry type | Created by |
|---|---|---|
| Payment recorded on Debt Collection task | Receive — allocated to invoices per FIFO/manual | Server script on task save |
| Payment Received task Completed (advance) | Receive — Customer Advance (no invoice link) | Server script on task completion |

The Accounting team submits these auto-created Payment Entries as part of their normal accounting work. They do not contact Finance to do so.

---

## 9. Discount Approval Flow

1. Order Creation person creates Dispatch Case with discounted items and saves (not submits)
2. Server script detects `discount_pct > 0` on any item → creates Discount Approval task for Directors Team → Case state = `Awaiting Approval`
3. **If approved:** Case can be submitted → Pack task created → normal flow continues
4. **If rejected:** New `Order entry` task created for Order Creation Team with note "Discount rejected — revise pricing." Case stays in `Draft`. Order Creation person opens the case, adjusts prices, saves again → new Discount Approval task created.

---

## 9A. Lost/Damaged Policy

Previously undecided (see `docs/implementation-questions.md` #17 and `docs/12-surgery-set-operational-workflow.md` §7.3). Now resolved:

- **Stock write-off:** Only `used_qty` is automatically written off from the Returns warehouse at Returns Inspection completion (Task 6.7). Lost/damaged items remain in Returns WH as tracked inventory pending manual resolution.
- **Invoicing:** Lost/damaged quantities are **not auto-invoiced**. Each lost/damaged case requires manual review to decide whether to invoice the client, write off internally, or escalate. The auto-created Sales Invoice covers only `used_qty`.
- **Manual resolution:** After inspection, a coordinator or director reviews the `lost_damaged_qty` on the Dispatch Case and decides the appropriate action (invoice, write-off, replacement, etc.) on a case-by-case basis. Once resolved, the items are manually issued from Returns WH.
- The same policy applies to Lost/Damaged discovered later while a quantity was Held (see `docs/held-at-client-items-plan.md`).

---

## 10. Dispatch Case States

| State | Meaning |
|---|---|
| `Draft` | Created, not yet confirmed |
| `Awaiting Approval` | Has discount; waiting for director approval |
| `Confirmed` | Approved / no discount; Pack task active |
| `Packed` | Pack task done; Delivery task active |
| `In Transit` | Driver picked up the box |
| `Delivered` | Items at client location |
| `Awaiting Return Pickup` | Waiting for client call to schedule return pickup |
| `Return Pickup Scheduled` | Return driver assigned; pickup task active |
| `Return In Transit` | Driver has collected returns, en route to warehouse |
| `Returns Received` | Returns at warehouse; inspection task active |
| `Invoice Pending` | Inspection done; invoice being prepared by Accounting |
| `Payment Pending` | Debt Collection task active |
| `Closed` | Fully paid |

---

## 11. Task Kinds Reference

| Kind | Used for | Role |
|---|---|---|
| `Order entry` | Initial order request; discount rejection follow-up | `Ops - Order Accepting`, `Ops - Order Creating` |
| `Discount Approval` | Director approval of discounted items | `Ops - Directors` |
| `Pack / prepare items` | Packing shipment; batch/serial temporarily disabled | `Ops - Inventory` |
| `Delivery` | Multi-state: pickup + delivery | `Delivery Driver` |
| `Return Call` | Return coordination wait / scheduling | Office/Returns workflow |
| `Pickup Returns` | Multi-state return pickup | `Delivery Driver` |
| `Returns processing / verification` | Inspecting and recording returned quantities | `Ops - Returns` |
| `Returns restocking` | Moving returned items from Returns WH to Main | `Ops - Returns` |
| `Invoice preparation / create invoice` | Reviewing and submitting auto-created invoice | `Ops - Accounting` |
| `Debt Collection` | Tracking and recording customer payments | `Ops - Finance` |
| `Distribute Payment` | Physical payment handling (bank deposit, transfers) | `Ops - Finance` |
| `Payment Received` | Logging advance/upfront payments before invoice | `Ops - Finance` |

New kinds to add (not yet in current `task_kind` field options):
- `Payment Received`
- `Returns restocking`

---

## 12. What Each Role Sees Daily

### `Ops - Order Accepting`
Task inbox only. Creates Order entry tasks when calls/messages arrive. Never opens a Dispatch Case.

### `Ops - Order Creating`
Task inbox. Opens Order entry tasks, creates and submits Dispatch Cases (the only time this role interacts with a Dispatch Case form). Links submitted cases back to tasks.

### `Ops - Directors`
Task inbox. Opens Discount Approval tasks, reviews discounts, marks approved or rejected.

### `Ops - Inventory`
Task inbox (filtered by `Pack / prepare items`). Prepares products according to the linked Dispatch Case. Batch/serial fields are temporarily not required while tracking is disabled. Marks task done. Never opens a Stock Entry.

### `Delivery Driver`
Task inbox (filtered by `Delivery` and `Pickup Returns`). Uses multi-state buttons (Picked Up / Delivered / Returned). Attaches photos. Never opens a Dispatch Case or Stock Entry.

### `Ops - Returns`
Task inbox. For `Return Call` tasks: assigns driver and schedules pickup. For Inspection tasks: opens Dispatch Case to fill returned quantities (the only interaction with the Dispatch Case form for this role). For Restock tasks: marks done when physical restocking complete.

### `Ops - Accounting`
Task inbox. Opens linked draft Sales Invoice, verifies, submits. Also submits auto-created Payment Entries (separate from Finance's task flow). Never opens a Dispatch Case.

### `Ops - Finance`
Task inbox. Records incoming payments on Debt Collection tasks. Creates Payment Received tasks for advances. Handles physical payment distribution via Distribute Payment tasks. Never opens an ERPNext Payment Entry form.

---

## 13. Dispatch Case as Read-Only Dashboard

The Dispatch Case form is a **read-only status overview** for managers and coordinators. It shows:
- Current state and full history
- All linked Stock Entries with their status
- Case Items table with dispatched / returned / used quantities per item
- The currently active task and its assignee
- Payment status: invoice amount, paid amount, outstanding
- Pack pickup photo and return drop-off photo (see Doc 18)

No buttons to click on the form. No workflow transitions to trigger manually.
