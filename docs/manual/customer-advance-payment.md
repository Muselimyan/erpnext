# Customer Advance Payment Walkthrough

**Purpose:** Use this when a customer pays before the final Sales Invoice exists, either as an upfront payment for a specific Dispatch Case or as advance credit for the customer.

**Who uses this:** `Ops - Finance`

**ERPNext screens to confirm first:** `Task`, `Payment Entry`, `Dispatch Case`

---

## When to use this

Use this flow when money is received before there is a Sales Invoice to allocate against.

Examples:
- customer pays before dispatch is invoiced;
- customer makes a partial upfront payment for a specific Dispatch Case;
- customer sends money to hold as advance credit.

Do not use this for normal invoice payment after the Sales Invoice exists. For invoice debt payment, use `debt-collection-and-payment.md`.

---

## Step 1 — Create or open the Payment Received task

**Login as:** `Ops - Finance`

1. Search for `Task` and open the Task list.
2. Create/open a task with:
   - **Task Kind:** `Payment Received`
   - **Customer:** the paying customer
   - **New Payment Amount:** amount received
   - **Payment Method:** Cash, Bank Transfer, or Card
   - **Payment Reference:** receipt/reference number

The advance Payment Entry posts to the received-money account based on payment method:

| Payment Method | Payment Entry `paid_to` account |
|---|---|
| Cash | Cash - Inmed |
| Bank Transfer | Bank - Inmed |
| Card | Bank - Inmed |
   - **Dispatch Case:** fill this only if the advance belongs to a specific case
3. Confirm the amount and reference are correct.

---

## Step 2 — Complete the Payment Received task

1. Set the task status to **Completed**.
2. Save the task.

**Expected after Save:**
- A draft Customer Receive **Payment Entry** is created with no Sales Invoice reference.
- If a Dispatch Case was linked, the payment is appended to the case's **Advance Payments** table.
- The Dispatch Case **Prepaid Amount** is recalculated from all rows in the Advance Payments table.
- The Dispatch Case **Prepaid Payment Entry** stores the latest Payment Entry as a quick reference.
- If there is an open Debt Collection task for the same customer, its **Available Advance Credit** increases by the payment amount.

---

## Multiple partial advances for one Dispatch Case

Multiple advance payments for the same Dispatch Case must accumulate.

Example:

| Payment | Amount | Expected Dispatch Case Prepaid Amount |
|---|---:|---:|
| First advance | 20,000 | 20,000 |
| Second advance | 15,000 | 35,000 |

The **Advance Payments** table should keep both rows, each linked to its own Payment Entry/source task.

---

## Step 3 — Later invoice/outstanding behavior

When the final Sales Invoice is prepared, the dispatch flow uses:

```text
outstanding = invoice_total - prepaid_amount
```

Because `prepaid_amount` is recalculated from all advance payment rows, the outstanding amount should reflect the full accumulated advance.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Prepaid Amount did not increase | Payment Received task was not completed, or the task was not linked to the Dispatch Case |
| Only latest Payment Entry appears in Prepaid Payment Entry | Correct; this field is only a quick reference. Use Advance Payments table for full history |
| Payment Entry is draft | Expected for advance payments; Accounting should review/submit according to accounting process |
| Available Advance Credit did not increase | There may be no open Debt Collection task for this customer |
