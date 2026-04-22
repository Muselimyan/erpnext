# Doc 13 — Reporting Pack (Operational)

## 1) Purpose
This document defines the “how to see everything” reporting pack: the minimum set of views that let you run operations and management.

It focuses on:
- What question each view answers
- Which data source is the primary truth (stock ledger vs tasks vs invoices)
- How to interpret the results
- What red flags mean (process problems, not “just reporting”)

Non-goals:
- This doc does not provide ERPNext click-paths or report-building steps.
- This doc does not define new workflows; it explains how to observe the workflows defined in other docs.

---

## 2) Reporting principles (so reports stay trustworthy)
- **One question → one primary truth**
  - Stock location questions: stock ledger / stock balance
  - Work execution questions: Tasks
  - Receivables questions: Sales Invoices / payment entries

- **Warehouses represent responsibility** (Doc 05)
  - If stock is in a warehouse, that warehouse’s owner team is responsible for it.

- **In-transit stock must be short-lived**
  - If stock stays in `Delivery In-Transit - WH` or `Return Pickup In-Transit - WH` for “too long”, the workflow is stuck.

- **Tracked items must remain traceable end-to-end**
  - For batch/serial items, missing identifiers are not “data noise”; they break recall/accountability.

- **Reporting must support investigation**
  - A good report is not only a number; it is a list you can drill into (which documents/cases/items caused the result).

---

## 3) Audience and operating rhythm
### 3.1 Directors (daily)
Directors should be able to answer:
- What work is stuck?
- Which clients are risky (debt threshold exceeded)?
- Which approvals are pending (discounts, purchasing)?
- Which paid invoices still require payment distribution?

### 3.2 Operations leads (daily)
Operations should be able to answer:
- What is in transit right now?
- What company-owned stock is sitting at client locations (surgery flow and/or permanent sets)?
- What is waiting in `Returns - WH` to be processed?
- Which surgery set templates are currently short on inventory?

### 3.3 Purchasing leads (daily/weekly)
Purchasing should be able to answer:
- What is low stock?
- What to order per supplier?
- What was ordered but not yet received?

### 3.4 Accounting (daily/weekly)
Accounting should be able to answer:
- What is delivered but not yet invoiced?
- What is invoiced but unpaid?
- What is aging and needs collection attention?

---

## 4) Report pack (the minimum set)
Each subsection below follows the same structure:
- What it answers
- Primary truth
- How to view / filter
- Interpretation
- Red flags + what they usually mean

---

## 4.1 Items currently at each client location (pending return / company-owned)
What it answers:
- “What company-owned stock is physically at Client X right now?”

Primary truth:
- Stock Balance for the relevant client location warehouse

How to view / filter:
- Filter by one client location warehouse (not the group `Clients - WH`).
- Optionally filter by Item Group (implants vs instruments) for operational review.

Interpretation:
- Any quantity here is company-owned stock physically at the client location.
- It may represent either:
  - surgery cases pending return/usage reconciliation (Doc 12), and/or
  - permanent on-site surgery sets (baseline on-site sets) (Doc 11).

Red flags:
- Large/old quantities at a client location with no active surgery cases and no permanent-set policy
- Serial-tracked tools sitting at a client location long after expected return

What it usually means:
- Missing pickup scheduling
- Case not closed
- Stock movement not posted

---

## 4.2 Items currently in delivery transit (outgoing)
What it answers:
- “What is packed and handed to delivery, but not yet delivered?”

Primary truth:
- Stock Balance for `Delivery In-Transit - WH`

How to view / filter:
- Filter to the `Delivery In-Transit - WH` warehouse.
- Group by Item for a quick risk scan.

Interpretation:
- This is the authoritative “on the road” staging location (Doc 05).

Red flags:
- Items stuck here overnight / multiple days

Additional red flag (cancellations):
- Items in `Delivery In-Transit - WH` where the related Sales Order is cancelled
  - usually means an aborted delivery package was not returned through the returns checkpoint.

What it usually means:
- Delivery task not completed
- Wrong posting timing
- Stock moved but delivery did not happen

---

## 4.3 Items currently in return pickup transit (incoming)
What it answers:
- “What was picked up from client locations and is currently with delivery, not yet received/verified at warehouse?”

Primary truth:
- Stock Balance for `Return Pickup In-Transit - WH`

Interpretation:
- This location should be short-lived. It represents physical packages in the delivery chain.

Red flags:
- Items stuck here for too long

What it usually means:
- Pickup completed but drop-off not done
- Returns processing not started

---

## 4.4 Items waiting for returns processing (backlog)
What it answers:
- “How much work is sitting in returns processing right now?”

Primary truth:
- Stock Balance for `Returns - WH`

Interpretation:
- This is not sellable stock yet; it is “returned but not checked”.

Red flags:
- High volume for long periods

What it usually means:
- Returns team capacity bottleneck
- Pickup scheduling misaligned with warehouse capacity

---

## 4.5 Items currently with each delivery person (derived view)
What it answers:
- “Which driver currently has what?”

Primary truth:
- Stock is still stored by warehouse (`Delivery In-Transit - WH`, `Return Pickup In-Transit - WH`).
- “By person” is derived from:
  - dispatch/pickup assignment records and/or tasks linked to the dispatch group/case (Doc 10 / Doc 12).

How to interpret:
- This view is only as good as the discipline of always assigning a delivery person.

Red flags:
- In-transit stock with no linked assignment/person

What it usually means:
- Dispatch/pickup tasks created without assignee
- Missing dispatch grouping discipline

---

## 4.6 Aging of open surgery cases (operational WIP)
What it answers:
- “Which surgery cases are stuck, and where?”

Primary truth:
- Surgery Case list (status) plus task queues (Doc 12 + Doc 10)

Operational breakdown:
- Cases delivered but not return-picked up
- Cases return-picked up but not returns-received
- Cases returns-received but not usage-derived
- Cases usage-derived but not invoiced

Red flags:
- Cases sitting in one status beyond your normal cycle time

What it usually means:
- Missing task completion
- Missing stock movements (dispatch/return/consumption)
- Waiting for usage info (if applicable)

---

## 4.7 Unpaid invoices (per client) and aging
What it answers:
- “How much does Client X owe us, and for how long?”

Primary truth:
- Sales Invoice list + outstanding amounts

How to interpret:
- This view includes:
  - fully unpaid invoices
  - **semi-paid (Partly Paid)** invoices where an outstanding remainder exists
- Outstanding amounts drive credit risk.
- Aging buckets highlight collection urgency.

Important note (batched payments):
- If you record client receipts as unallocated advances first, an invoice may still look fully unpaid even though money has been received.
- Use the unallocated-advances view (section 4.7A) to understand the net debt position.

Red flags:
- Clients accumulating debt without director review

---

## 4.7A Unallocated customer advances (payments received, not yet allocated)
What it answers:
- “We received money from Client X, but which invoices is it paying?”
- “Is the client actually in debt, or do they have credit sitting unallocated?”

Primary truth:
- Customer advance / unallocated payments (Payment Entries not fully allocated to invoices)

Interpretation:
- This is client credit that reduces net debt.
- This credit may be either:
  - temporarily unallocated (allocation will be done later), or
  - intentionally left as long-lived client credit (no fixed time limit).

Red flags:
- Clients above debt threshold while having significant unallocated credit (indicates allocation/reconciliation rules are not being applied consistently)
- Large unallocated credit that does not match any known operational reason (possible data entry or reconciliation issue)

---

## 4.7B Prepaid orders awaiting delivery (upfront paid, not yet fulfilled)
What it answers:
- “Which clients paid upfront but we still haven’t delivered?”
- “Which prepaid orders are at risk of being forgotten/stuck?”

Primary truth (derived):
- Sales Orders not yet delivered/fulfilled
- Payment Entries recorded as client advances

Interpretation:
- This is an operational queue, not a receivables queue.
- If you support prepaid deliveries, you must be able to list:
  - the order
  - the delivery timing promise
  - the amount received (advance)
  - whether the order is fully prepaid or partially prepaid (deposit)
  - any remaining required upfront amount before dispatch (if applicable)
  - whether delivery has happened

Red flags:
- Prepaid orders sitting open beyond the promised delivery date/time
- Large client advances with no matching delivery activity for long periods
- Prepaid orders where required upfront amount is not yet received but dispatch/staging activity has started

---

## 4.8 Clients exceeding their debt threshold
What it answers:
- “Which clients exceeded their allowed outstanding debt?”

Primary truth:
- Customer outstanding debt compared to the client’s threshold value (Doc 04 / requirements)

Interpretation:
- Exceedance triggers director review.

Important note (partial + batched payments):
- Ensure the “outstanding debt” number used for threshold comparison is the **net receivable** for the client:
  - invoice outstanding
  - minus unallocated advances (client credit)

Red flags:
- Threshold exceeded but no visible escalation
- Threshold exceeded while the client has significant unallocated credit (usually means allocation/reconciliation is not being done)

---

## 4.9 Open Debt Collection tasks (per client) with current debt
What it answers:
- “Which debt problems are actively being handled by directors?”

Primary truth:
- Task list filtered to `Debt Collection` task kind (Doc 10)

Interpretation:
- There should be one canonical open task per client that reflects current debt (update rather than create duplicates).

Red flags:
- Multiple open debt tasks for the same client
- Debt tasks that don’t reflect current reality

---

## 4.9A Distribute Payment tasks (received payments pending distribution)
What it answers:
- “Which received payments still require director payment distribution?”

Primary truth:
- Task list filtered to `Distribute Payment` task kind (Doc 10)

Interpretation:
- This queue is internal financial control after receipt.

Red flags:
- Received payments with no distribution task
- Distribution tasks stuck open for long periods

---

## 4.9B Return-to-warehouse tasks (aborted deliveries / cancelled orders)
What it answers:
- “Which cancelled/aborted deliveries still have packages that must be brought back?”

Primary truth:
- Task list filtered to `Return to warehouse` task kind (Doc 10)

Interpretation:
- This queue should be small and short-lived.

Red flags:
- Return-to-warehouse tasks stuck open for long periods
- Cancelled Sales Orders with no corresponding return-to-warehouse task (package integrity risk)

---

## 4.10 Sales history per client (with optional hospital/doctor context)
What it answers:
- “What did we sell to Client X?”
- “What did we sell by Hospital (when recorded)?”
- “What did we sell by Doctor Name (when recorded)?”

Primary truth:
- Sales Invoice items (financial truth)

Interpretation:
- Optional context reporting is only as complete as data entry discipline (hospital/doctor fields are optional by policy).

Red flags:
- Many invoices missing hospital/doctor context in cases where you expect it

---

## 4.10A Price override list (client special prices)
What it answers:
- “Does Client X have a special price for Item Y?”
- “What are all negotiated/special prices for Client X?”

Primary truth:
- The selling price override records you maintain (your canonical **Price Override List**).

Interpretation:
- This list is used during order entry to quickly confirm whether a client has a special price.
- Pricing truth rule:
  - Sales Invoices inherit prices from Sales Orders.
  - Therefore the operational control point is: ensure Sales Orders use correct base/override prices.
- It should be easy to filter by:
  - Client (Customer)
  - Item
  - Valid-from/valid-to (if you choose to use time validity)

Red flags:
- Many Sales Orders where the price differs from both:
  - the standard base price list, and
  - the client’s override list
  (usually means manual pricing is happening without a controlled record)
- Overrides with no review cadence (prices that are outdated but still being used)

Fast cross-check (recommended):
- Periodically pick a few high-volume items and compare:
  - base price list rate
  - override list rate (if any)
  - actual Sales Order rates used in the last 30 days
  - investigate any unexplained deviations.

---

## 4.11 Low stock list by supplier
What it answers:
- “What do we need to order, grouped by supplier?”

Primary truth:
- Reorder list logic (Doc 08) + one item → one supplier (Doc 06/07)

Interpretation:
- The reorder list must be filterable/groupable by supplier.
- Thresholds vary per category and can be refined per item/variant.

Red flags:
- Low stock items missing supplier assignment
- Variant families where only the template is maintained (variants missing thresholds)

---

## 4.12 Surgery Set Type readiness (templates that are short on inventory)
What it answers:
- “Which surgery set templates can we currently fill from inventory, and which are short?”

Primary truth:
- Template definitions: `Surgery Set Type` item rows (Doc 11)
- Stock availability signal: stock in `Main - WH` (Doc 05)

Interpretation:
- A template is “ready” only if each required item has enough availability to meet the template default quantity.
- If a template is short, operations can still proceed by preparing a partial set (Doc 12), but the shortage should be visible.

Red flags:
- High-volume templates frequently short on stock
- Templates short on the same item repeatedly (indicates reorder threshold issues)



## 4.13 Near-expiry stock risk (Main warehouse)
What it answers:
- “Which expiry-tracked items in `Main - WH` are approaching expiry and require attention?”

Primary truth:
- Batch/expiry-aware stock view (batch numbers with expiry dates) for `Main - WH`.

Interpretation:
- These items represent potential write-off risk and should drive:
  - FEFO discipline in packing/dispatch
  - discount/priority sales decisions if needed

Red flags:
- High quantities inside the near-expiry window
- Items repeatedly expiring while fresher batches are being issued


## 5) Cross-checks (fast controls to catch broken processes)
These are high-value “sanity checks” you can run routinely.

### 5.1 In-transit stuck check
- Any stock in `Delivery In-Transit - WH` or `Return Pickup In-Transit - WH` older than your normal delivery/pickup window must have an owner and a task.

### 5.2 Returns backlog check
- Stock in `Returns - WH` is a workload queue.
- If it grows continuously, returns verification is the bottleneck.

### 5.3 Client stock vs open cases check (surgery flow)
- If a client location warehouse shows significant stock but there are no active/open cases:
  - If the client location uses permanent on-site sets (Doc 11), treat it as normal baseline stock.
  - Otherwise investigate why stock is still company-owned at that client location.

### 5.4 Tracked items traceability check
- For serial/batch tracked items, verify movements always include identifiers.

### 5.5 Pricing override hygiene check (recommended)
- Periodically review:
  - price override list changes (what changed, by whom, why)
  - Sales Orders with manual rate edits (prices not matching base/override)
- Purpose:
  - prevent slow drift into uncontrolled manual pricing
  - keep negotiated pricing explicit and auditable

---

## 7) Acceptance criteria
- Directors can see:
  - open work (tasks)
  - approvals
  - debt risks
- Operations can see:
  - items at each client location
  - in-transit stock
  - returns backlog
- Accounting can see:
  - unpaid invoices and aging
- Purchasing can see:
  - low stock list grouped by supplier
- Reports can be used to identify process breakdowns (not just produce numbers).
