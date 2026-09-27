# Doc 14 — Go-Live Readiness Checklist (Functional)

## 1) Purpose
This document is a functional readiness checklist for go-live.

It answers:
- “Are we operationally safe to start using ERPNext with real transactions?”
- “Can we run the day without breaking stock accuracy, traceability, or receivables control?”

Outputs:
- Minimum viable setup checklist
- End-to-end test scenarios checklist

Non-goals:
- This doc does not cover infrastructure (domain/SSL/backups/email/VPS) or performance tuning.
- This doc does not provide ERPNext click-path implementation steps.

---

## 2) How to use this checklist
- Run this checklist in a short go-live meeting with:
  - Operations lead (inventory + delivery)
  - Accounting lead
  - Purchasing lead
  - Director representative
- Treat every checkbox as:
  - `Pass` (ready)
  - `Fail` (must fix before go-live)
  - `Defer` (explicitly accepted risk, with owner + date)

Operational rule:
- If you defer something, write down:
  - why you accept the risk
  - what monitoring/report will detect issues early (Doc 13)

---

## 3) Go / No-Go criteria (minimum)
Go-live is allowed only if:
- You can run **one complete Dispatch Case (no-return path)** end-to-end: Order entry task → Dispatch Case (`return_expected = No`) submit → Pack → Delivery (Picked Up → Delivered) → Invoice Preparation (Create & Submit Invoice) → Payment Pending → Closed when the customer's account settles, with correct stock movements and all Stock Entries auto-submitted.
- You can run **one complete Dispatch Case (return-expected path)** end-to-end: Order entry task → Dispatch Case (`return_expected = Yes`) submit → Pack → Delivery → Return Call → Return Pickup → Returns Inspection → Invoice Preparation → Payment Pending → Closed when the customer's account settles, with batch/serial temporarily disabled and `dispatched = used + returned` reconciliation.
- If any client location uses a permanent on-site set model, you can run **one complete permanent set replenishment cycle** end-to-end (usage posting → invoice used → replenish stock into the correct client location warehouse).
- Directors can see:
  - open approvals (discounts, purchase approvals)
  - clients above debt threshold
  - clients holding unallocated advance credit
- Finance (`Ops - Finance`) can see open Debt Collection tasks per customer.
- Purchasing can see a reorder list grouped by supplier (even if thresholds are basic initially).

---

## 4) Master data readiness
### 4.1 Company naming and conventions
- Naming conventions from Doc 02 are understood by the team.
- Users know how to search by:
  - client code
  - item brand/spec

### 4.2 Clients (Customers)
- Every active client has exactly one canonical Customer record.
- Customer naming matches `<Client Code> — <Client Name>` (Doc 02 / Doc 04).
- Each client has a defined debt threshold value.

### 4.3 Optional hospital/doctor context
- Hospital is optional and does not block order entry.
- Doctor Name is optional and does not block order entry.

### 4.4 Items and variants
- Item naming is consistent (Doc 02 / Doc 06).
- Variant families are represented consistently (attributes are controlled).
- Each purchasable variant is represented as its own item identity.

### 4.5 UOM / pack-size sanity
- Stock UOM matches how the warehouse counts (Doc 06).
- Any pack-breaking behavior is either:
  - explicitly defined per item/category, or
  - deferred with an explicit “never break packs at go-live” rule.
 - For pack-breakable items where you buy boxes and sell singles:
  - UOM conversion policy is defined and tested (Doc 06 / Doc 07)

### 4.6 Supplier link invariant
- Every active item has exactly one supplier assigned (Doc 06 / Doc 07).

---

## 5) Warehouse and stock integrity readiness
### 5.1 Warehouse tree exists and matches the operational model (Doc 05)
- `Main - Inmed` exists and is used as sellable stock.
- `Delivery In-Transit - Inmed` exists.
- `Return Pickup In-Transit - Inmed` exists.
- `Returns - Inmed` exists.
- `Clients - Inmed` exists as group only.
- Each active client location group has its own leaf warehouse under `Clients - Inmed`.

### 5.2 Stock movement invariants understood by staff
- Staff understands the allowed movement patterns (Doc 05 section 6).
- Staff understands that all dispatch/delivery/return/consumption stock movements are managed automatically by the Dispatch Case flow (Doc 16); no manual Stock Entries are needed for these movements.
- Staff understands that client location warehouses are used only for company-owned at-client stock (Dispatch Case return-expected path and/or permanent on-site sets).

### 5.3 Tracking readiness (serial / batch / expiry)
- For serial-tracked items:
  - serials are recorded on every movement.
- For batch/expiry items:
  - batch is recorded on every movement
  - expiry is stored on the batch where applicable.
  - FEFO is followed for expiry-tracked items (earliest expiry issued first)

---

## 6) Roles, permissions, and separation-of-duties readiness
(Alignment: Doc 03 / Doc 10)

- Drivers cannot post stock (no Stock Entry posting by drivers).
- Inventory/Returns teams can do the required stock movements.
- Accounting can create/submit invoices and record payments.
- Directors can approve discounts and purchase approvals.

Operational check:
- Wrong-team users cannot complete tasks they do not own.

---

## 7) Workflow gates and approvals readiness
### 7.1 Discounts
- Discount approval is a hard gate **before Pack task creation** (Doc 16). A Dispatch Case with Discount % > 0 stays in `Awaiting Approval` status until a Director approves the Discount Approval task; only then does the case transition to `Confirmed` and the Pack task is auto-created.

### 7.2 Purchasing approvals
- Purchase orders require director approval before being sent/submitted (Doc 07).

### 7.3 Debt threshold escalation
- Debt threshold exceedance triggers/updates a Director Debt Alert task (`Ops - Directors`) (Doc 16 §6.10B).
- Policy confirmed: exceedance does not automatically block delivery. Finance records payments on Debt Collection episode tasks, raised by a scheduler when an invoice is overdue, the threshold is breached, or a promised follow-up date arrives.

---

## 8) Reporting readiness (must be usable on day 1)
(Alignment: Doc 13)

Confirm you can answer:
- Stock at Main vs in transit vs in returns backlog
- Items currently at each client location (Dispatch Case return-expected path)
- Items currently assigned to each driver (derived from Tasks) while stock is in the in-transit warehouses
- Unpaid invoices per client and aging
- Unallocated customer advances (payments received but not yet allocated)
- Prepaid orders awaiting delivery (clients paid upfront but delivery is still pending)
- Clients exceeding debt threshold
- Open Debt Collection tasks
- Low stock list grouped by supplier
- Surgical Kit Template readiness (templates short on inventory). `RPT - Collection Set Readiness` does not run and cannot be repaired as written (Group 10 F-032)

Red-flag readiness:
- You have at least one “stuck workflow” detector:
  - stock in transit warehouses for too long
  - backlog in `Returns - Inmed`

---

## 9) End-to-end functional test scenarios
Run these tests using a small controlled set of test records.

### 9.1 Scenario A — Dispatch Case: no-return path
Pass criteria:
- Create an **Order entry task** for Client A, assign to Order Creation Team (`order.creation.team@...`).
- `Ops - Order Creating` creates and submits a **Dispatch Case** (`return_expected = No`, 2–3 items).
  - Confirm Pack task auto-created for Inventory team. Case status = `Confirmed`.
- `Ops - Inventory` opens the Pack task. Fill `serial_no`/`batch_no` for tracked items on the Case Items table. Complete Pack task.
  - Confirm Dispatch Stock Entry auto-submitted: `Main - Inmed → Delivery In-Transit - Inmed`.
  - Confirm Delivery task auto-created for Delivery team. Case status = `Packed`.
- `Delivery Driver` sets Delivery Status to `Picked Up` on the Delivery task.
  - Confirm case status → `In Transit`.
- `Delivery Driver` fills Driver Handover Note, sets Delivery Status to `Delivered`.
  - Confirm Delivery Stock Entry auto-submitted (to internal consumption path since no-return).
  - Confirm Consumption Stock Entry auto-submitted.
  - Confirm the Invoice Preparation task is auto-created. Case status → `Invoice Pending`. No invoice exists yet.
- `Ops - Accounting` completes the Invoice Preparation task with **Create & Submit Invoice**: confirm the invoice is submitted for the used quantities, with `Update Stock = No` and correct prices.
  - If anything is outstanding, case status → `Payment Pending`. No Debt Collection task is created at this point; one is raised later if the invoice becomes overdue (Doc 16, Task 6.10).
- `Ops - Finance` records payment on a Debt Collection task (amount, method, reference). Save.
  - Confirm the Payment Entry is created and submitted. Outstanding balance decreases.
  - When the customer's account is fully settled: the case → `Closed`, and one `Debt Closure Approval` is raised for Directors.

For expiry-tracked items: confirm earliest-expiry batch is selected at Pack step (FEFO).

Invoice check (**revised by Group 11 W6** — there is no draft invoice to find):
- On the Invoice Preparation task, confirm the preview shows priced lines, net, VAT and total. Use **Create & Submit Invoice**.
- Confirm the invoice is **submitted**, carries 20% VAT (`Armenia Tax - Inmed`), a due date 30 days out (`Net 30`), and `hospital` / `doctor_name` populated from the customer.
- Run the same case as a **fully-returned** case and confirm the task offers **Nothing to Invoice** and closes the case with a reason. This path used to be an unfinishable task.

Payment check (**run these as a plain `Ops - Finance` user, not as Administrator**):
- Record a **partial** payment — confirm outstanding decreases but the case stays open.
- Record a second payment to clear outstanding — confirm the case → `Closed` and one `Debt Closure Approval` is raised.
- Confirm the Debt Collection episode cannot be completed without a `collection_outcome`, and that a `Promised` outcome requires a future follow-up date.
- Confirm an advance recorded on a `Payment Received` task produces a **submitted** Payment Entry with GL entries — not a draft.

> ⚠️ **Run the payment and invoice scenarios as the role that owns the task**,
> never as Administrator or System Manager. Three separate defects in this area
> were invisible to privileged testing and passed earlier smoke tests for
> exactly that reason: an `Ops - Accounting` user could not complete Invoice
> Preparation for a repeat customer; an `Ops - Finance` user could not record a
> payment at all, lacking permission on `Account`; and the Dispatch Case access
> gate did not cover submitted cases. Privileged accounts are exempt from all
> three.

### 9.1a Existing-data prerequisites (Group 11)

If this instance carries data created before the Group 11 rebuild, do these
before the scenarios above, or they will behave oddly:

- **Close or cancel every legacy open `Debt Collection` task.** The
  one-open-episode-per-customer rule treats a leftover task as an episode in
  progress and will decline to raise a real one, silently suppressing collection
  for that customer.
- **Resolve legacy open `Debt Closure Approval` tasks.** They were raised by the
  old task-completion trigger and may assert closures that never happened.
- **Submit or cancel draft customer Payment Entries.** A draft produces no GL
  entries, so the money is invisible to the ledger the new code reads.
- **Triage cases stuck in `Invoice Pending`** — each needs an invoice committed
  or an explicit nothing-to-invoice close.
- **Populate `Item Price` on `Standard Selling` for every orderable item.**
  Order entry now refuses an unpriced item rather than silently pricing it at
  zero, which is correct but will block work where prices are missing.

Full detail: `deploy/test/work/group-11-dispatch-financial-tail-gap-analysis.md`,
"Go-live prerequisites".

### 9.2 Scenario B — Discount approval gate
Pass criteria:
- Create and submit a Dispatch Case with **Discount % > 0** on at least one Case Item.
- Confirm case status = `Awaiting Approval` and a Discount Approval task is auto-created for directors.
- Confirm no Pack task is created while approval is pending.
- Director completes the task with `Approved` outcome.
- Confirm case status → `Confirmed` and Pack task is auto-created.

### 9.2A Scenario B1 — Cancellation redirect (Dispatch Case)
Pass criteria:
- Cancel a Dispatch Case at `Confirmed` status (Pack task exists but not completed).
  - Confirm related open tasks are cancelled.
  - Confirm no Stock Entry exists (Dispatch SE not yet created at this stage).
- Complete Pack task (Dispatch SE created, case = `Packed`), then cancel the Dispatch Case before Delivery is completed.
  - Confirm a `Return to warehouse (aborted delivery / cancelled order)` task is auto-created (for the Delivery accepter when `In Transit`, otherwise for the delivery team), requiring a photo.
  - Confirm stock returns through `Returns - Inmed` and only then back to `Main - Inmed` after Restock task completion.
  - Confirm no stock is left stuck in `Delivery In-Transit - Inmed`.

### 9.3 Scenario C — Debt threshold escalation (director alert)
Pass criteria:
- Set a client debt threshold.
- Create unpaid invoices to exceed the threshold.
- Confirm a `Debt Alert` task is raised for `Ops - Directors`, and that the client's debt shows live in the debt panel (balances are read from the ledger, not stored on tasks).

### 9.4 Scenario D — Basic procurement (PO → receipt → invoice)
Pass criteria:
- Create a draft PO for Supplier A.
- Director approval occurs.
- Receive goods into `Main - Inmed`.
- If you test a pack-breakable item (buy box, stock/sell single), confirm stock enters correctly using the conversion policy.
- For tracked items, serial/batch/expiry is recorded correctly.
- Accounting creates supplier invoice record.

### 9.5 Scenario E — Reorder list by supplier
Pass criteria:
- At least a few items have thresholds.
- Low stock items appear.
- They can be grouped/filtered by supplier.

### 9.6 Scenario F — Dispatch Case: return-expected path (inventory truth)
Pass criteria (Doc 16 acceptance intent):
- Create and submit a Dispatch Case (`return_expected = Yes`) with a **Client Location Warehouse** set.
- Complete Pack task → Dispatch SE auto-submitted: `Main - Inmed → Delivery In-Transit - Inmed`.
- Driver: Delivery `Delivered` → Delivery SE auto-submitted: `Delivery In-Transit → Client Location WH`. Case → `Awaiting Return Pickup`.
- Returns/office workflow completes Return Call task (sets driver + scheduled date) → Return Pickup task auto-created. Case → `Return Pickup Scheduled`.
- Driver: Return Pickup `Picked Up` → Return Pickup SE auto-submitted: `Client Location WH → Return Pickup In-Transit - Inmed`. Case → `Return In Transit`.
- Driver: attaches drop-off photo, sets Return Pickup `Returned to Warehouse` → Return Receive SE auto-submitted: `Return Pickup In-Transit → Returns - Inmed`. Case → `Returns Received`. Returns Inspection task auto-created.
- Returns team fills `returned_qty` (and `lost_damaged_qty` if any) on Case Items, completes Returns Inspection task.
  - Consumption SE auto-submitted for `used_qty` per item.
  - Restock task auto-created. Invoice Preparation task auto-created. Case → `Invoice Pending`.
- Verify reconciliation: `dispatched_qty = used_qty + returned_qty` for every Case Item.
- Accounting submits Sales Invoice (quantities = `used_qty`, `Update Stock = No`). Completes Invoice Preparation task. Case → `Payment Pending`.
- Returns team completes Restock task → Restock SE auto-submitted: `Returns - Inmed → Main - Inmed`.
- Finance records full payment on Debt Collection task. Case → `Closed`.

Driver evidence checks:
- Pack task: pickup photo required before completion (see Doc 18).
- Pickup Returns task: drop-off photo required before `Returned to Warehouse` (see Doc 18).

Template check:
- If tested with a Surgical Kit Template, confirm applying it from the Order entry task (`task_apply_template`) fills the case items with resolved prices, and refuses the whole template if any line is unpriced.

### 9.7 Scenario G — Permanent on-site set replenishment (if used)
Pass criteria:
- Place baseline stock into a client location warehouse (company-owned at-client stock).
- Post usage/consumption that reduces stock from the client location warehouse (traceable for batch/serial items where applicable).
- Create Sales Invoice for the used quantities.
- Deliver replenishment stock into the same client location warehouse.

---

## 10) Common go-live failure modes (what to watch for)
- Stock appearing in client location warehouses with no open Dispatch Case (return-expected) or permanent-set policy
- In-transit warehouses accumulating stock without a linked Dispatch Case or clear task owner
- Returns backlog growing in `Returns - Inmed` without Restock task completion
- Dispatch Cases stuck in intermediate states (e.g. `Invoice Pending`, `Payment Pending`) for many days
- Duplicate master data (same client multiple times)
- Variant confusion causing wrong-size picks
- Missing serial/batch identifiers on Case Items before Pack task completion
- Issuing fresher expiry batches while older-expiring batches exist in `Main - Inmed`
- Discounts applied without a completed Discount Approval task on the Dispatch Case

---

## 11) Acceptance criteria
- The team can run the minimum test scenarios without manual “fixing” entries afterward.
- Stock locations and reporting views match physical reality.
- Directors have visibility into approvals and credit risk.
- Purchasing can order by supplier with confidence in item–supplier mapping.
