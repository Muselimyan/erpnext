# Doc 09 — Selling: Standard Orders (No Return Expected) (Operational)

## 1) Purpose
This document defines the operational rules for the **standard sales flow** (normal selling):
- client places an order
- you prepare and deliver
- you invoice
- the client pays later (mostly credit)

It also supports a common variant:
- client pays **upfront** (prepaid), and delivery may happen later when requested.

This flow is **not** the surgery-set flow (Doc 11/12).

Goals:
- Make day-to-day order fulfillment consistent and auditable
- Keep inventory accurate (especially for batch/serial tracked items)
- Keep receivables control visible (debt thresholds + escalation)

Non-goals:
- This doc does not provide ERPNext configuration steps.
- Returns for standard sales are not operationalized here (standard sales assumes “no return expected”).

---

## 2) Key decisions this flow depends on
- **Client location warehouses are not used for standard sales** (Doc 05)
  - Standard sales must not create long-lived “company-owned at client location” positions.
  - Note: some client locations keep permanent on-site surgery sets (consignment-like). Replenishment for those sets is not handled as standard sales; it may move stock into client location warehouses as company-owned stock (see Doc 11).

- **Tracking policy** (requirements):
  - implants/consumables: Batch + Expiry where applicable
  - tools/instruments: Serial where applicable

- **Separation of duties** (Doc 03):
  - drivers do not post stock
  - accounting owns invoicing
  - directors own approvals/escalations

- **Hospital / Doctor Name context is optional** (Doc 04)
  - supported on Sales Orders and Sales Invoices when needed

---

## 3) Roles and ownership (who does what)
### 3.1 Order team (Order Accepting)
- Captures the request from the client
- Confirms items, quantities, price/discount, delivery timing
- Records optional Hospital / Doctor Name context if provided

### 3.2 Inventory / Preparing team
- Packs the items
- Ensures the packed set matches the order
- Ensures correct batch/serial selection where required

### 3.3 Delivery team
- Performs the physical delivery
- Confirms completion of delivery tasks

### 3.4 Accounting
- Creates and submits the Sales Invoice
- Tracks payment status

### 3.5 Directors
- Approve discounts (when needed)
- Handle escalations: debt threshold exceeded → Debt Collection task

---

## 4) Documents and what they mean (operational)
This document uses common ERP concepts; exact configuration is in implementation docs.

- **Sales Order**: the agreed customer request (what to deliver)
- **Delivery / stock issue step**: the point where items leave sellable stock and are physically handed off for delivery
- **Sales Invoice**: what the client owes (accounts receivable truth)
- **Payment**: settlement (full or partial)

Operational rule:
- Do not treat “order created” as “delivered”, and do not treat “invoice created” as “delivered”.

---

## 5) Warehouses and stock movement rules (standard sales)
Standard sales uses only:
- `Main - WH`
- `Delivery In-Transit - WH`

Rules (alignment with Doc 05):
- Outgoing staging is allowed:
  - `Main - WH` → `Delivery In-Transit - WH`
- Standard delivery completion must remove stock from company-owned warehouses.
- Client location warehouses must not be used for standard sales.

Clarification:
- For client locations with permanent on-site sets (Doc 11), replenishment deliveries may move stock into the client location warehouse while remaining company-owned.
- That replenishment model is outside the standard-sales flow described in this document.

Tracking rule:
- If an item requires batch/serial tracking, the stock movement that issues goods must record the correct batch/serials.

---

## 6) End-to-end standard selling flow
### 6.1 Step 0 — Order intake (Order team)
Operational checklist:
- Confirm client (Customer)
- Capture requested items and quantities
- Capture requested delivery time/date
- Capture Hospital / Doctor Name context (optional)
- Confirm whether this order is **prepaid** (client will pay upfront before delivery)
- Confirm pricing (see pricing rules below)
- If a discount is requested/applied, route to approval policy (see Section 7)

Pricing rules (recommended baseline):
- **Base price** comes from your standard selling price list (your default reference rates).
- **Price overrides** apply when a client (doctor/hospital) has a negotiated/special price for a specific item.
  - These overrides must be maintained in an always-referenceable **Price Override List** so staff can quickly verify.
- **Discounts** are ad-hoc deviations from the applicable base/override price and require director approval (Section 7).

Operational intent:
- During order entry, staff should be able to answer quickly:
  - “Is there a special price for this client?”
  - “If yes, what is the exact price?”
- The Sales Order should carry the final agreed price per line.

Control (recommended):
- The Price Override List must be accessible as a fast lookup (saved list/report) while creating the order.
- If staff manually changes a line rate that does not match base/override pricing:
  - manual rate entry should be allowed only for Accounting/Directors,
  - record a short reason,
  - and treat it as a discount/exception subject to your approval policy.

Outcome:
- The order is ready for packing

### 6.2 Step 1 — Pack / prepare (Inventory / Preparing)
Operational checklist:
- Pick the correct items
- Verify quantities
- For tracked items:
  - choose correct batch (and validate expiry risk)
  - choose correct serials
- For expiry-tracked items:
  - follow FEFO (First-Expiry-First-Out): pick the earliest-expiry batch first
  - if a fresher batch is selected while an older-expiring batch is available in `Main - WH`, the system must alert
- Pack safely and label the package if needed

Outcome:
- Items are ready for dispatch hand-off

### 6.3 Step 2 — Dispatch hand-off checkpoint (Inventory + Delivery coordinator)
Purpose:
- Ensure the system’s “in transit” view matches physical reality.

Operational rules:
- Stock must be staged into `Delivery In-Transit - WH` before the driver leaves (so in-transit reporting is correct).
- Driver does not post stock.
- Driver must attach a Warehouse Pickup Photo on the `Delivery` Task before leaving `Main - WH`.

Prepaid gate (only for prepaid orders):
- Do not stage/dispatch a prepaid order until Accounting confirms the required upfront amount was recorded.
  - Prepaid may be:
    - fully paid upfront, or
    - partially paid (deposit model) if agreed for that order.
  - Recommended mechanism: record the payment as a client advance (Payment Entry) linked/allocatable to this order.

Outcome:
- Shipment is staged and assigned for delivery

### 6.4 Step 3 — Delivery (Delivery team)
Operational checklist:
- Deliver to the client location
- Confirm delivery completion in the workflow
- Record a short handover note (freeform) on the `Delivery` Task (example: who the package was handed to)

Optional policy (not required unless you choose it):
- capture delivery proof (photo/signature)

Outcome:
- Delivery is complete; items are no longer company-owned stock

### 6.5 Step 4 — Invoice preparation / create invoice (Accounting)
Operational rules:
- Standard policy: deliver first, invoice after delivery.
- Invoice must match what was actually delivered.
- Pricing rule:
  - Sales Invoice takes prices from the Sales Order (order is the operational pricing truth).
  - Invoicing must not silently re-price based on the item master.

Prepaid variant (minimal-change approach):
- Upfront payments are recorded before delivery as a client advance.
- After delivery, create the Sales Invoice and allocate the advance so the invoice is immediately **Paid**.

If you require invoicing at payment time (exception):
- Only do this if it is legally/process required.
- Ensure delivery later matches what was invoiced (avoid changes after invoicing), otherwise you will need a correction/credit-note process.

Outcome:
- Sales Invoice is submitted and becomes the receivable truth

### 6.6 Step 5 — Payment collection / receivables
Operational rules:

Definitions (important):
- **Unpaid invoice**: no payment is allocated to it.
- **Semi-paid (Partly Paid) invoice**: some payment is allocated, but an **Outstanding Amount** remains.
- **Advance / unallocated payment**: money received from the client, but not yet allocated to specific invoices.

Clarification (upfront payment / prepaid delivery):
- If a client pays before delivery (and before an invoice exists), record it as an **advance / unallocated payment**.
- This means the client may temporarily have a **credit** balance (net receivable can be negative) until you deliver and invoice.

Operational rules (recommended baseline):
- Payments may be **partial**.
- A single payment receipt may be allocated across **multiple invoices**.
- If the client paid but did not clearly specify invoices:
  - record the receipt immediately (so the bank/cash position is correct),
  - treat it as an **advance / unallocated payment**,
  - then allocate it later as a separate accounting step.
- Unpaid and semi-paid invoices must remain visible and reportable per client.

Confirmed policy (allocation governance):
- Allocation should be done **same day** when needed for operations (example: an order needs to be created and the flow should start).
- Allocation/adjustment is allowed for **Accounting and Directors**.
- There is **no time limit** for leaving money as an unallocated advance (it may represent long-lived client credit).

Allocation policy (recommended for go-live):
- Default allocation is **oldest invoices first** (FIFO by invoice date / due date), unless the client explicitly requests a different allocation.
- It is allowed that a payment only partially closes an invoice (invoice becomes **Partly Paid**).

Mechanism (ERPNext-native behavior, described operationally):
- Payment receipt is recorded as a **Payment Entry** for the client.
- That Payment Entry can contain one or more **allocation lines** linking it to Sales Invoices with specific allocated amounts.
  - If you allocate less than the invoice total, the invoice remains open as **Partly Paid** with an outstanding remainder.
  - If you allocate across many invoices, each invoice reflects its own remaining outstanding amount.
- If you do not allocate yet, the payment remains as a client **advance/unallocated credit** until allocation is done.

Debt-tracking rule (critical):
- Debt thresholds and director escalation should use **net receivable** per client:
  - total outstanding across invoices
  - minus unallocated advances (client credit)
  - so “Client owes us” remains true even when money came in but hasn’t been allocated yet.

Practical interpretation (why allocation discipline matters):
- **Total debt / credit risk** is about the net receivable (invoices minus advances).
- **Aging and overdue management** is invoice-based.
  - If you leave payments unallocated for too long, invoice aging looks worse than reality and can trigger false escalations.

Outcome:
- Receivable is reduced/cleared

### 6.7 Step 6 — Distribute Payment (Directors)
When: after payment is received and confirmed according to your internal control policy.

Operational intent:
- Payment receipt and payment distribution are separate internal steps.

Operational rule:
- A Director-owned `Distribute Payment` task must be created/maintained for each payment event that requires distribution.

Outcome:
- Directors confirm distribution is done and record a short note.

---

## 7) Discount policy and approvals
Confirmed requirement:
- Order team can apply discounts; Directors must approve discounts.

Clarification (pricing vs discount):
- If a client has a long-lived negotiated price for an item, that should be maintained as a **price override** (special price) and used consistently.
- A **discount** is an ad-hoc deviation from the applicable base/override price and requires explicit approval.

Operational rule:
- Discount approval is an explicit checkpoint.

Confirmed policy:
- If a discount requires approval, it is a hard gate **before delivery**.
- The order must not proceed to dispatch/delivery until the discount is approved (or the discount is removed).

Recommended operational pattern:
- If a discount requires approval, create/maintain a Director-owned `Discount Approval` task linked to the order.

---

## 8) Client debt thresholds and director escalation
Confirmed requirement:
- Each client has a debt threshold.
- Directors must be alerted when outstanding debt exceeds the threshold.
- The alert is implemented operationally as a Director-owned **Debt Collection** task.

Operational intent:
- Debt threshold is an escalation and visibility control.

Operational rule (recommended baseline):
- When a client exceeds its threshold:
  - a Debt Collection task must exist and reflect current outstanding amount
  - teams should not ignore it; it is reviewed by Directors

Confirmed policy:
- Exceeding the threshold does not automatically block new deliveries.
- It triggers director review through the Debt Collection task.

---

## 9) Optional destination context (hospital + doctor)
Rules:
- Hospital is always optional.
- Doctor Name is always optional.
- Record them when they add operational/reporting value.
- Do not block order entry if they are not known.

---

## 10) Exceptions and controls
### 10.1 Partial delivery
- Deliver and invoice only what was delivered.
- Remaining quantities stay as pending until delivered/cancelled.

### 10.2 Cancellation / edits
- Avoid deleting documents; cancel with a reason.
- If an order was already staged for delivery, edits must be handled explicitly (not silently).

Confirmed policy (who can cancel):
- Directors and Order Team can cancel at all stages.

Cancellation redirect rule (critical):
- Cancellation is allowed at any moment, but the correct handling depends on **where the physical goods are**.
- The goal is to redirect the flow safely without losing stock or leaving “ghost work” (open tasks for a cancelled order).

Stage-based handling (recommended baseline):

1) Cancelled before packing starts
- Meaning:
  - Sales Order exists (or is being created), but no goods were picked/packed.
- Operational actions:
  - Cancel the Sales Order with a short reason.
  - Cancel any open logistics tasks linked to it (Pack/Dispatch/Delivery).
- Stock effect:
  - No stock movement is needed.

2) Cancelled after packing, but before dispatch staging / driver pickup
- Meaning:
  - Items were packed/put aside, but the driver has not picked them up.
- Operational actions:
  - Cancel the Sales Order with a short reason.
  - Cancel the `Delivery` task (if created) with reason “Order cancelled before pickup”.
  - Ensure the packed items are returned to normal shelf locations by the Inventory team.
- Stock effect:
  - If no stock was moved out of `Main - WH` yet, the system stock stays correct.
  - If stock was already staged into `Delivery In-Transit - WH`, treat it as case (3) below.

3) Cancelled after dispatch staging / while in transit (driver has the package)
- Meaning:
  - Goods are already in `Delivery In-Transit - WH` and physically with delivery.
- Operational actions:
  - Cancel the Sales Order with a short reason.
  - Cancel the `Delivery` task with a reason “Delivery aborted / order cancelled in transit”.
  - Create/maintain a return-to-warehouse flow:
    - driver brings the package back,
    - a warehouse handover happens,
    - returns team/inventory verifies and re-stocks.
  - Require a warehouse drop-off photo as evidence on the return-to-warehouse flow.
- Stock effect:
  - The package must re-enter warehouse control via the returns verification pattern (Doc 05).
  - Route: `Delivery In-Transit - WH` → `Returns - WH` → `Main - WH`.

4) Cancelled after delivery (true return)
- Meaning:
  - Ownership already transferred; client wants to return goods.
- Operational actions:
  - Treat it as a standard-sales return exception (see 10.4).
  - Ensure the financial side (credit note/refund) follows your accounting policy.
- Stock effect:
  - Returned goods must enter through a controlled returns receiving/verification step (Doc 05).

Prepaid note:
- If the order was prepaid and then cancelled:
  - leave the received money as client advance (credit) by default.

### 10.3 “We delivered but forgot to record it”
- Treat this as an exception.
- Backdating should be controlled and reviewable (Doc 05 principle).

### 10.4 Standard-sales returns (rare)
Standard sales assumes no return expected.

If a return happens:
- treat it as an exception workflow and ensure stock re-enters through controlled receiving/verification rules (Doc 05 principles).

### 10.5 Client prepaid but delivery happens later
- Treat this as normal if the order is explicitly flagged as prepaid.
- Control intent:
  - do not lose track of prepaid orders waiting for delivery.
  - ensure you can list them as a queue (see Doc 13).

---

## 11) Reporting implications
Minimum reporting outcomes this flow must support:

Operations:
- what is pending packing
- what is staged in `Delivery In-Transit - WH`
- what is delivered today / this week

Accounting:
- what is invoiced
- what is unpaid
- aging by client

Directors:
- clients above debt threshold (Debt Collection tasks)
- discounts pending approval

Optional analytics (when filled):
- sales by hospital
- sales by doctor name (free text)

---

## 13) Acceptance criteria
- Standard sales never moves stock into client location warehouses.
- In-transit visibility is reliable (what left `Main - WH` is visible in `Delivery In-Transit - WH` until delivered).
- Tracked items (batch/serial) are issued with correct identifiers recorded.
- Discounts follow a director approval checkpoint.
- Debt threshold exceedance creates/maintains a director Debt Collection task.
- Orders/invoices can be filtered by Hospital / Doctor Name when provided.
