# Debt Collection and Client Payment Walkthrough

**Purpose:** Standalone guide for the Finance team on how to record payments received from clients, track outstanding balances, and handle the Distribute Payment task. This flow is triggered automatically after a Sales Invoice is submitted for any Dispatch Case with a non-zero outstanding balance.

**Estimated time:** 5–10 minutes per payment recording

**Use case:** A client pays (or partially pays) their outstanding balance. The Finance team records the incoming payment, which is allocated automatically across the client's oldest open invoices first (FIFO). This guide covers the full Finance team routine — from first seeing the Debt Collection task through to the case being fully closed.

**Prerequisites:**
- At least one Sales Invoice has been submitted for the client with an outstanding balance > 0
- The Debt Collection task already exists (it is created automatically when a qualifying invoice is submitted)

---

## Roles

| Step | Task | Role |
|---|---|---|
| 1–5 | Record payment on Debt Collection task | `Ops - Finance` |
| 6 | Handle Distribute Payment task | `Ops - Finance` |

---

## How the Debt Collection task works

- A **Debt Collection task** is auto-created for a customer when a submitted Sales Invoice has an outstanding balance > 0.
- There is **one task per customer** — not one per Dispatch Case. All outstanding invoices for that customer are tracked in a single task.
- When subsequent invoices are submitted for the same customer, they are added to the same Debt Collection task.
- The task shows the complete picture: every open invoice, when it was issued, and the outstanding amount on each.

---

## Step 1 — Find the Debt Collection task

**Login as:** `Ops - Finance`

1. Search for `Task` and open the **Task** list.
2. Filter: **Task Kind = Debt Collection**, **Status = Open**.
3. Find the task for the customer you have received payment from.
   - The task Subject follows the pattern: `Collect payment: [Customer Name]`
4. Open the task.

**What you see on the task:**
- **Open Invoices** table — lists all outstanding Sales Invoices for this customer, with amounts and due dates
- **Outstanding Amount** — total currently owed across all invoices
- **Record Payment** section — where you enter the incoming payment

---

## Step 2 — Record the incoming payment

1. In the **Record Payment** section, fill in:
   - **New Payment Amount:** the amount the client just paid (in AMD)
   - **Payment Method:** `Cash`, `Bank Transfer`, or `Card`
   - **Payment Reference:** the transaction reference number, receipt number, or bank transfer confirmation ID
2. Click **Save**.

**✅ Expected after Save:**
- A **Payment Entry** (type: Receive) is auto-created in ERPNext
- The payment is allocated **FIFO** by Sales Invoice posting date — oldest invoices are paid off first
- Every payable Open Invoices row must have a linked Sales Invoice; if one is missing, the save is blocked until the task is corrected
- The Payment Entry includes reference rows for the Sales Invoice(s) it paid, with the exact allocated amount per invoice
- The **Outstanding Amount** on the task decreases by the paid amount
- A **Distribute Payment task** is auto-created for the Finance team (see Step 3)

**❌ Should NOT happen:**
- Error saving the task with amount > 0 → check that `Payment Method` and `Payment Reference` are filled
- Error saying an Open Invoices row has no Sales Invoice → do not record payment yet; ask Accounting/System Manager to correct the Debt Collection task so each payable row links to a Sales Invoice

---

## Step 3 — Handle the Distribute Payment task

After each payment is recorded, a **Distribute Payment task** is automatically created. This task represents the physical handling of the money (depositing cash, confirming a bank transfer has cleared, etc.).

**Login as:** `Ops - Finance`

1. Search for `Task` and open the **Task** list, filter: **Task Kind = Distribute Payment**, **Status = Open**.
2. Find the task related to this payment.
3. Perform the physical action:
   - **Cash:** count and deposit the cash amount
   - **Bank Transfer:** confirm the transfer has cleared in the bank account
   - **Card:** confirm the card terminal receipt matches
4. Click the red **Complete Task** button near the Status field.

---

## Step 4 — Partial payment scenario

If the client pays less than the full outstanding amount:
- The payment is applied to the oldest invoice(s) first (FIFO by Sales Invoice posting date)
- The generated Payment Entry references the invoice(s) covered by the partial payment
- The Debt Collection task remains **Open** with a reduced outstanding amount
- The invoices that are not yet fully covered remain open
- The next time the client pays, repeat Steps 1–3

**Example:**
- Client owes AMD 800,000 across two invoices: Invoice A (AMD 500,000) and Invoice B (AMD 300,000)
- Client pays AMD 600,000
- FIFO allocation: Invoice A fully paid (AMD 500,000) + AMD 100,000 applied to Invoice B
- Debt Collection task stays open — Outstanding = AMD 200,000 (remaining on Invoice B)

---

## Step 5 — Full payment — case closes automatically

When the total outstanding balance for the customer reaches **zero**:
- The Debt Collection task **auto-completes** (Status → Completed)
- The associated Dispatch Case(s) status → **`Closed`**
- No manual action required to close the task

**How to confirm a case is fully closed:**
1. Search for `Dispatch Case`, open the **Dispatch Case** list, and open the case
2. Confirm Status = `Closed` and `outstanding_amount` = 0
3. Confirm the Sales Invoice shows Paid = full amount, Outstanding = 0

---

## Step 6 — Checking a customer's full outstanding balance

To see everything a client currently owes across all cases and invoices:

1. Search for `Accounts Receivable` and open the **Accounts Receivable** report:
   - Alternative path: **Accounts** → **Reports** → **Accounts Receivable**
2. Filter: **Party Type = Customer**, **Party = [customer name]**
3. The report shows all open Sales Invoices with their outstanding amounts and ages

Alternatively, from the Debt Collection task itself:
- The **Open Invoices** table on the task shows all outstanding invoices for this customer in one view

---

## Step 7 — What to do when a client disputes an amount

If the client disputes an invoice and refuses to pay the full amount:

1. **Do not adjust the invoice yourself.** Sales Invoices are submitted documents — they cannot be edited.
2. Escalate to `Ops - Accounting` and `Ops - Directors`:
   - Either a **Credit Note** (Sales Invoice cancellation/amendment) is issued for the disputed portion
   - Or an explicit write-off is recorded (requires Director approval)
3. Once the accounting adjustment is made and the invoice outstanding is corrected, record the agreed payment as normal.

---

## Quick reference

```
Sales Invoice submitted (outstanding > 0)
  └─► Debt Collection task auto-created for customer (Ops - Finance)
        └─► Finance receives payment → fills amount + method + reference → Save
              └─► Payment Entry (Receive) auto-created — FIFO across open invoices
              └─► Distribute Payment task auto-created → Finance handles physical payment → Complete Task
              └─► [Repeat for each partial payment]
              └─► When outstanding = 0:
                    └─► Debt Collection task auto-completes
                    └─► Dispatch Case → Closed
```

---

## Common issues

| Symptom | Likely cause |
|---|---|
| Debt Collection task not visible in task list | Task Access Policy for `Debt Collection` not granted to this user — ask System Manager |
| Debt Collection task not created after invoice was submitted | Invoice was fully prepaid (outstanding = 0 at submission); or automation script error — check with System Manager |
| Outstanding amount on task does not decrease after recording payment | Payment Entry was not auto-created — check Server Scripts for errors; check the Payment Entry list for the entry |
| Case does not close even though outstanding = 0 | Check that the Dispatch Case's `outstanding_amount` field is being updated by the automation; raise with System Manager |
| Client paid but wrong amount was entered | If Payment Entry is still in Draft — cancel it and redo. If already submitted — create a correcting payment entry (for overpayment: issue a refund; for underpayment: record the remaining balance in the next payment cycle) |
