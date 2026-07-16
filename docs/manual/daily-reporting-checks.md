# Daily Reporting Checks — Morning Routine by Role

**Purpose:** Reference card for each role's daily checks in ERPNext. Run these every morning (or at the start of each shift) to catch problems early and keep operations moving.

**How to use this guide:** Find your role section. Work through the checks in order. Each item tells you what to look for and what action to take if something looks wrong.

---

## Directors

**Goal:** See what is stuck, what is risky, and what needs your decision today.

### Check 1 — Pending approvals
*Time: 2–5 minutes*

Search for `Task` and open the **Task** list, filter: **Status = Open**, then check each approval type:

- **Task Kind = Discount Approval** — Dispatch Cases waiting for your approval on discounted pricing. Act on these first: an unapproved case is blocking the whole dispatch chain.
- **Task Kind = Purchase Approval** — Purchase Orders waiting for approval. Check supplier, quantities, and reason before approving.
- **Task Kind = Write-off Approval** — Stock write-off requests from the Inventory team.

**Action if found:** Open each task → review the linked document → set Approval Outcome + Note → complete.

---

### Check 2 — Clients over debt threshold
*Time: 3–5 minutes*

Search for `Accounts Receivable` and open the **Accounts Receivable** report (Accounts → Reports → Accounts Receivable):
- Filter by Party Type = Customer
- Sort by Outstanding Amount descending
- Compare each client's outstanding balance against their `Debt Threshold (AMD)` on their Customer record

Any client where `Outstanding Amount > Debt Threshold` needs attention — contact the Finance team or escalate collection.

---

### Check 3 — Stuck Dispatch Cases (operational WIP)
*Time: 3–5 minutes*

Search for `Dispatch Case` and open the **Dispatch Case** list. Filter: **Status ≠ Closed, Status ≠ Cancelled**. Sort by creation date ascending (oldest first).

Watch for cases sitting in the same status for longer than expected:

| Status | Normal duration | Red flag |
|---|---|---|
| `Confirmed` (Pack task not done) | Hours to 1 day | > 1 day |
| `Packed` (Delivery not started) | Hours | > 1 day |
| `In Transit` (Delivery not completed) | Same day | > 1–2 days |
| `Awaiting Return Pickup` | Days to weeks | > agreed pickup date |
| `Invoice Pending` (Invoice not submitted) | 1–2 days | > 3 days |
| `Payment Pending` | Per terms | > threshold |

**Action if found:** Check the linked tasks for that case — find the task that is still Open and escalate to the responsible team.

---

### Check 4 — Pending Distribute Payment tasks
*Time: 1–2 minutes*

Search for `Task` and open the **Task** list, filter: **Task Kind = Distribute Payment**, **Status = Open**.

These tasks represent received client payments that still need physical handling (cash deposited, transfer confirmed). Each one should be completed promptly by the Finance team.

**Action if backlog is growing:** Prompt the Finance team to clear these.

---

### Check 5 — Open Debt Collection tasks summary
*Time: 2–3 minutes*

Search for `Task` and open the **Task** list, filter: **Task Kind = Debt Collection**, **Status = Open**.

Review how many clients have active collection tasks and what the outstanding balances are. Focus on:
- Clients with the highest outstanding amounts
- Clients where the balance has not moved in the last week

---

## Ops — Inventory

**Goal:** See what is moving, what is stuck in transit, and what needs to be restocked or written off.

### Check 1 — Delivery in-transit (outgoing)
*Time: 2 minutes*

Search for `Stock Balance` and open the **Stock Balance** report (Stock → Reports → Stock Balance):
- Filter Warehouse: `Delivery In-Transit - Inmed`

Any items showing here are packed and with delivery, not yet delivered. Items sitting here more than 1–2 days are a problem.

**Action if stuck items found:** Check the Delivery task for the corresponding Dispatch Case — the driver may not have updated the delivery status.

---

### Check 2 — Return pickup in-transit (incoming)
*Time: 2 minutes*

Same Stock Balance report:
- Filter Warehouse: `Return Pickup In-Transit - Inmed`

Items here are picked up from clients but not yet dropped off at the warehouse. Should be zero or minimal at the start of the day.

**Action if items stuck:** Check the Return Pickup task — the driver may not have completed the drop-off step.

---

### Check 3 — Returns backlog
*Time: 2 minutes*

Same Stock Balance report:
- Filter Warehouse: `Returns - Inmed`

Items here are returned to the warehouse but not yet inspected/processed. This is work waiting for the Returns team. A growing backlog here means the Returns team is behind.

**Action if backlog growing:** Alert the Returns team lead; this directly holds up invoice creation for the corresponding cases.

---

### Check 4 — Pack tasks queue
*Time: 1 minute*

Search for `Task` and open the **Task** list, filter: **Task Kind = Pack / prepare items**, **Status = Open**.

Each open Pack task corresponds to a Dispatch Case in `Confirmed` status waiting to be packed. Work through these in priority order (check surgery date on the linked case).

---

### Check 5 — Near-expiry stock risk
*Time: 2–3 minutes, weekly or when prompted*

Search for `Batch-Wise Balance History` and open the **Batch-Wise Balance History** report (Stock → Reports → Batch-Wise Balance History):
- Filter Warehouse: `Main - Inmed`
- Review batches with expiry dates within the next 30 days

Items in this window need FEFO priority (pick them first for dispatch) or a write-off decision if they cannot be sold in time.

**Action:** Flag near-expiry batches to the Purchasing team so they do not reorder that item until the at-risk batch is consumed.

---

## Ops — Purchasing

**Goal:** See what is low in stock and what needs to be ordered today.

### Check 1 — Reorder list
*Time: 5–10 minutes*

Search for `Itemwise Recommended Reorder Level` and open the **Itemwise Recommended Reorder Level** report (Stock → Reports → Itemwise Recommended Reorder Level):
- Filter Warehouse: `Main - Inmed`

Items where Current Stock ≤ Reorder Level need action. Group by Supplier column to identify which suppliers need a PO today.

**Action:** For each supplier with low-stock items, follow the **Low-Stock Check and Reorder Routine** (`low-stock-reorder-routine.md`).

---

### Check 2 — Open Purchase Orders (ordered but not yet received)
*Time: 2–3 minutes*

Search for `Purchase Order` and open the **Purchase Order** list, filter: **Status = Submitted** (i.e. not fully received).

For each open PO:
- Is the expected delivery date approaching or overdue?
- Has the supplier confirmed shipment?

**Action if overdue:** Contact the supplier for a status update; update the Schedule Date on the PO if needed.

---

### Check 3 — Purchase Approval tasks (pending your action)
*Time: 1 minute*

Search for `Task` and open the **Task** list, filter: **Task Kind = Purchase Approval**, **Status = Open**.

These are your draft POs waiting for Director approval. Follow up with the Director if any have been waiting more than 1 day.

---

## Ops — Accounting

**Goal:** See what is delivered but not yet invoiced, and what invoices are aging without payment.

### Check 1 — Dispatch Cases awaiting invoice
*Time: 3–5 minutes*

Search for `Dispatch Case` and open the **Dispatch Case** list, filter: **Status = Invoice Pending**.

Each case here has an auto-created draft Sales Invoice waiting to be reviewed and submitted.

Search for `Task` and open the **Task** list, filter: **Task Kind = Invoice preparation / create invoice**, **Status = Open** — work through these tasks.

**Action:** Open each task → open the linked draft Sales Invoice → verify quantities and prices → submit. See `standard-sale-walkthrough.md` Step 5 or `surgery-case-walkthrough-v2.md` Step 11 for details.

---

### Check 2 — Accounts Receivable aging
*Time: 3–5 minutes*

Search for `Accounts Receivable` and open the **Accounts Receivable** report (Accounts → Reports → Accounts Receivable):
- Filter Party Type: Customer
- Review the aging buckets: 0–30, 31–60, 61–90, 90+ days

Focus on:
- Invoices in the 60+ day bucket — these need escalation
- Any invoice that appears unpaid but you know the client has paid — check if the Payment Entry has been allocated

---

### Check 3 — Near-expiry stock (cost/write-off risk)
*Time: 2 minutes, weekly*

Check the **Batch-Wise Balance History** for `Main - Inmed` batches expiring within 30 days (same as Inventory check above). The accounting implication is potential write-off expense — flag to Directors if the value is significant.

---

## Ops — Finance

**Goal:** See which clients owe money and process any payments that came in.

### Check 1 — Open Debt Collection tasks
*Time: 3–5 minutes*

Search for `Task` and open the **Task** list, filter: **Task Kind = Debt Collection**, **Status = Open**.

For each task:
- Has any payment come in since last check?
- If yes → record it now (see `debt-collection-and-payment.md`)
- If the outstanding is large and no payment has been received in several days → flag to Directors

---

### Check 2 — Distribute Payment tasks
*Time: 2 minutes*

Search for `Task` and open the **Task** list, filter: **Task Kind = Distribute Payment**, **Status = Open**.

Each task here is a payment that was recorded in the system but the physical action (depositing cash, confirming transfer) has not been confirmed as done. Complete these promptly.

---

### Check 3 — Unallocated customer advances
*Time: 2 minutes, weekly*

Search for `Accounts Receivable` and open the **Accounts Receivable** report and check for clients who have unallocated advances (credit balance). If a client shows as owing money but also has unallocated credit, the credit should be allocated to reduce the net outstanding.

---

## Quick summary table

| Role | Daily checks |
|---|---|
| **Directors** | Pending approvals (Discount / Purchase / Write-off) → clients over debt threshold → stuck Dispatch Cases → Distribute Payment backlog |
| **Ops - Inventory** | Delivery in-transit → Return pickup in-transit → Returns backlog → Pack task queue |
| **Ops - Purchasing** | Reorder list (low stock by supplier) → Open POs not yet received |
| **Ops - Accounting** | Invoice Pending cases → Accounts Receivable aging |
| **Ops - Finance** | Open Debt Collection tasks → Distribute Payment tasks |

---

## Key report locations

| Report | Path in ERPNext |
|---|---|
| Task list (filtered) | Search → Task |
| Stock Balance (by warehouse) | Stock → Reports → Stock Balance |
| Batch-Wise Balance History | Stock → Reports → Batch-Wise Balance History |
| Itemwise Recommended Reorder Level | Stock → Reports → Itemwise Recommended Reorder Level |
| Accounts Receivable | Accounts → Reports → Accounts Receivable |
| Dispatch Case list | Search → Dispatch Case |
| Purchase Order list | Search → Purchase Order |
