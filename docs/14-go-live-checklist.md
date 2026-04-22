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
- You can run **one complete standard sale** end-to-end (order → dispatch → delivery → invoice) with correct stock movements.
- You can run **one complete surgery case** end-to-end (dispatch → deliver → return pickup → returns verification → usage derived → invoice used) with correct batch/serial behavior.
- If any client location uses a permanent on-site set model, you can run **one complete permanent set replenishment cycle** end-to-end (usage posting → invoice used → replenish stock into the correct client location warehouse).
- Directors can see:
  - open approvals (discounts, purchase approvals)
  - clients above debt threshold
  - received payments pending payment distribution
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
- `Main - WH` exists and is used as sellable stock.
- `Delivery In-Transit - WH` exists.
- `Return Pickup In-Transit - WH` exists.
- `Returns - WH` exists.
- `Clients - WH` exists as group only.
- Each active client location group has its own leaf warehouse under `Clients - WH`.

### 5.2 Stock movement invariants understood by staff
- Staff understands the allowed movement patterns (Doc 05 section 6).
- Staff understands that standard sales must not move stock into client location warehouses.
- Staff understands that client location warehouses are used only for company-owned at-client stock (surgery cases and/or permanent on-site sets).

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
- Discount approval is a hard gate **before delivery** (Doc 09).

### 7.2 Purchasing approvals
- Purchase orders require director approval before being sent/submitted (Doc 07).

### 7.3 Debt threshold escalation
- Debt threshold exceedance triggers a director-owned Debt Collection task (requirements / Doc 09 / Doc 10).
- Policy confirmed: exceedance does not automatically block delivery; directors review via task.

---

## 8) Reporting readiness (must be usable on day 1)
(Alignment: Doc 13)

Confirm you can answer:
- Stock at Main vs in transit vs in returns backlog
- Items currently at each client location (surgery flow)
- Unpaid invoices per client and aging
- Unallocated customer advances (payments received but not yet allocated)
- Clients exceeding debt threshold
- Open Debt Collection tasks
- Low stock list grouped by supplier
- Surgery Set Type readiness (templates that are short on inventory)

Red-flag readiness:
- You have at least one “stuck workflow” detector:
  - stock in transit warehouses for too long
  - backlog in `Returns - WH`

---

## 9) End-to-end functional test scenarios
Run these tests using a small controlled set of test records.

### 9.1 Scenario A — Standard sale (no return expected)
Pass criteria:
- Create order for Client A with 2–3 items.
- If any item is tracked, the batch/serial identifiers are recorded on the issue movement.
- For expiry-tracked items, confirm the earliest-expiry batch is selected (FEFO) or an alert appears if a fresher batch is chosen while an older-expiring batch is available.
- Stock moves:
  - `Main - WH` → `Delivery In-Transit - WH` → (delivered / leaves company-owned stock)
- Accounting creates Sales Invoice after delivery.

Driver evidence checks:
- Delivery task requires a Warehouse Pickup Photo.
- Delivery task can record a freeform handover note (example: who the package was handed to).

Additional check:
- Record a **partial** payment so the invoice becomes semi-paid (Partly Paid) with an outstanding remainder.
- Record a payment as an **unallocated/advance** amount (no invoice selected), then allocate it later.
- Confirm debt reporting still makes sense (net receivable = invoice outstanding − unallocated advances).
- Confirm a Director-owned `Distribute Payment` task exists for the received payment and can be completed.

Pricing override check (if you have any special-price clients):
- Create a Sales Order for a client with a known price override on one item.
- Confirm the order line uses the override price (or staff can clearly see/apply it from the Price Override List).
- Confirm the Sales Invoice inherits the order price (no silent re-pricing).

Upfront payment (prepaid) check (if you support prepaid deliveries):
- Record an upfront payment as a customer advance for Client A.
- Confirm dispatch/delivery for this order can be gated on Accounting confirmation (policy-dependent).
- If you allow partial prepaid (deposit model), record a partial upfront amount and confirm dispatch is still gated on the required upfront amount for that order.
- Deliver the items later.
- Create the Sales Invoice after delivery and allocate the advance so the invoice becomes **Paid** immediately.
- Confirm reporting can show prepaid orders awaiting delivery (Doc 13).

### 9.2 Scenario B — Discount approval gate
Pass criteria:
- Create an order with a discount that requires director approval.
- Confirm the delivery/dispatch step cannot proceed until approval is completed.

### 9.2A Scenario B1 — Cancellation redirect (standard sale)
Pass criteria:
- Cancel an order before packing starts.
  - Confirm all related open logistics tasks are cancelled with a reason.
  - Confirm no stock movement is required.
- Stage a delivery into `Delivery In-Transit - WH`, then cancel the order before delivery completion.
  - Confirm a driver return-to-warehouse task exists and requires a drop-off photo.
  - Confirm stock returns through `Returns - WH` and only then back to `Main - WH` after verification.
  - Confirm reporting highlights no cancelled orders still “stuck” in `Delivery In-Transit - WH`.

### 9.3 Scenario C — Debt threshold escalation (director alert)
Pass criteria:
- Set a client debt threshold.
- Create unpaid invoices to exceed the threshold.
- Confirm a director-owned Debt Collection task exists for the client and reflects current debt.

### 9.4 Scenario D — Basic procurement (PO → receipt → invoice)
Pass criteria:
- Create a draft PO for Supplier A.
- Director approval occurs.
- Receive goods into `Main - WH`.
- If you test a pack-breakable item (buy box, stock/sell single), confirm stock enters correctly using the conversion policy.
- For tracked items, serial/batch/expiry is recorded correctly.
- Accounting creates supplier invoice record.

### 9.5 Scenario E — Reorder list by supplier
Pass criteria:
- At least a few items have thresholds.
- Low stock items appear.
- They can be grouped/filtered by supplier.

### 9.6 Scenario F — Surgery case end-to-end (inventory truth)
Pass criteria (Doc 12 acceptance intent):
- Dispatch stock is staged (and traceable) into `Delivery In-Transit - WH`.
- Delivery moves stock into the correct client location warehouse.
- Return pickup moves stock into `Return Pickup In-Transit - WH`.
- Returns processing moves stock into `Returns - WH`, then to `Main - WH` as appropriate.
- Usage is derived and reconciles:
  - Delivered = Used + Returned (+ Lost/Damaged)
- Sales Invoice includes used quantities only.

Driver evidence checks:
- Delivery task requires a Warehouse Pickup Photo.
- Return drop-off at warehouse task requires a Drop-off Photo.

Template shortage check:
- If you test with a template that is short on stock, the case can still be prepared partially and the system shows a clear warning listing missing items.

### 9.7 Scenario G — Permanent on-site set replenishment (if used)
Pass criteria:
- Place baseline stock into a client location warehouse (company-owned at-client stock).
- Post usage/consumption that reduces stock from the client location warehouse (traceable for batch/serial items where applicable).
- Create Sales Invoice for the used quantities.
- Deliver replenishment stock into the same client location warehouse.

---

## 10) Common go-live failure modes (what to watch for)
- Stock appearing in client location warehouses from standard sales
- Client location warehouse stock with no documented reason (no surgery cases and no permanent-set policy)
- In-transit warehouses accumulating stock without clear owner/task
- Returns backlog growing with no process response
- Duplicate master data (same client multiple times)
- Variant confusion causing wrong-size picks
- Missing serial/batch selection on stock movements
- Issuing fresher expiry batches while older-expiring batches exist in `Main - WH`
- Discounts applied without explicit director approval

---

## 11) Acceptance criteria
- The team can run the minimum test scenarios without manual “fixing” entries afterward.
- Stock locations and reporting views match physical reality.
- Directors have visibility into approvals and credit risk.
- Purchasing can order by supplier with confidence in item–supplier mapping.
