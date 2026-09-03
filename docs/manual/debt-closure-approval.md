# Debt Closure Approval Walkthrough

**Purpose:** Use this manual to review and approve a fully paid Debt Collection task, confirm the payment history, and understand how profit is calculated after the debt is closed.

**Who uses this:** `Ops - Directors`

**ERPNext screens to confirm first:** `Task`, `Sales Invoice`, `Dispatch Case`, `Item Price`

---

## When this task is created

A **Debt Closure Approval** task is created automatically when a **Debt Collection** task becomes `Completed`.

This happens after the customer's tracked outstanding invoices are fully paid in the Debt Collection task.

The approval task copies:
- customer;
- paid invoices from the Debt Collection Open Invoices table;
- payment history;
- payment entry references;
- total amount paid.

---

## Approver configuration

Debt Closure Approval approvers are controlled by **Task Access Policy**, not hardcoded user emails.

Configuration record:

```text
Task Access Policy: Debt Closure Approval
Default Team User: directors.team@example.com
Allowed Roles: Ops - Directors
```

To change who can approve later, update the users/roles behind this policy instead of editing server scripts.

---

## Step 1 — Open the Debt Closure Approval task

**Login as:** a user allowed by the `Debt Closure Approval` Task Access Policy

1. Search for `Task`.
2. Filter:
   - **Task Kind:** `Debt Closure Approval`
   - **Status:** `Open`
3. Open the relevant task.

---

## Step 2 — Review payment evidence

Before completing the task, confirm:

1. Customer is correct.
2. Open Invoices table shows the invoices that were paid.
3. Each invoice has `outstanding_amount = 0` or is otherwise confirmed as settled.
4. Payment History rows match the money received.
5. Payment Entry references are correct.

---

## Step 3 — Complete the approval task

When an approved Director completes the task:

1. The script reads all Sales Invoices in the task's Open Invoices table.
2. It calculates profit for each invoice item:

```text
profit = (selling rate × quantity) - (Standard Buying rate × quantity)
```

3. It sums all invoice profits into the task's **Case Profit** / `custom_case_profit` field.
4. It writes each Dispatch Case's own invoice profit to that Dispatch Case's `profit` field.

If multiple invoices/Dispatch Cases are included in one Debt Closure Approval, each invoice is included in the total.

---

## Standard Buying price requirement

Profit uses `Item Price` records from the **Standard Buying** price list.

If an item has no Standard Buying price:
- buying cost is treated as 0 for that item;
- the script shows a warning;
- the profit may be overstated.

Before relying on profit numbers, Directors/Accounting should confirm important items have Standard Buying prices.

---

## Example

| Invoice | Dispatch Case | Calculated Profit |
|---|---|---:|
| INV-001 | DC-001 | 40,000 |
| INV-002 | DC-002 | 25,000 |

Expected result after approval:

```text
Debt Closure Approval custom_case_profit = 65,000
DC-001 profit = 40,000
DC-002 profit = 25,000
```

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Profit looks too high | Missing Standard Buying price caused buying cost to be treated as 0 |
| Only one Dispatch Case profit changed | Check whether the Open Invoices table has Dispatch Case links on every row |
| No profit calculated | The task has no Sales Invoice links in Open Invoices or main Sales Invoice field |
| User cannot complete approval | User is not Administrator and does not have a role allowed by the `Debt Closure Approval` Task Access Policy |
