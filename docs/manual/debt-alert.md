# Debt Alert Walkthrough

**Purpose:** Use this manual to understand Director debt-threshold alerts created by the scheduled debt check.

**Who uses this:** `Ops - Directors`

**ERPNext screens to confirm first:** `Task`, `Customer`, `Accounts Receivable`

---

## What Debt Alert means

A **Debt Alert** is a Director visibility task.

It means:

```text
Customer's net receivable debt is higher than that customer's debt threshold.
```

It is not the same as a Finance **Debt Collection** task.

| Task kind | Owner | Purpose |
|---|---|---|
| Debt Alert | Directors | Threshold/risk visibility from scheduled GL check |
| Debt Collection | Finance | Operational payment recording against specific open invoices |

---

## How it is created

The scheduled debt script runs periodically and checks each enabled Customer with a debt threshold.

For each customer:

1. Calculate net receivable from GL Entry:

```text
sum(debit - credit) for Customer receivable entries
```

2. Compare net receivable to `Customer.debt_threshold_amd`.
3. If debt is above threshold, create or update one open **Debt Alert** task for that customer.
4. Assign the alert to Directors.

---

## What Directors should do

When a Debt Alert appears:

1. Open the task.
2. Review:
   - Current Debt AMD
   - Debt Threshold AMD
   - task description
3. Open Accounts Receivable for the customer if invoice-level detail is needed.
4. Decide whether to:
   - ask Finance for collection follow-up;
   - block or review new dispatches;
   - update the customer debt threshold;
   - leave as monitored risk.

---

## What Directors should not do in Debt Alert

Do not record customer payments from a Debt Alert.

Payments must be recorded from **Debt Collection** tasks because those tasks contain the Open Invoices table and create Payment Entries with invoice references.

---

## Relationship to Debt Collection

Debt Alert is created by scheduler from accounting ledger balances.

Debt Collection is created by dispatch/invoice flow when a submitted invoice has outstanding balance.

They are intentionally separate so:

- Director threshold monitoring does not steal Finance's payment task assignment;
- Finance payment tasks always have Open Invoices rows;
- scheduled alerts do not create incomplete payment workflows.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Customer is over threshold but no Debt Alert exists | Scheduler may not have run yet, threshold is 0, customer is disabled, or script/deploy is missing |
| Debt Alert exists but no Open Invoices table | Correct; use Accounts Receivable for invoice detail or wait for a Finance Debt Collection task |
| Finance cannot record payment from Debt Alert | Correct; payment recording belongs to Debt Collection task |
| Both Debt Alert and Debt Collection exist for same customer | Correct; one is Director risk visibility, the other is Finance payment workflow |
