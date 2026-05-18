# Supplier Prepayment and Invoice Allocation Walkthrough

**Purpose:** Step-by-step guide for paying a supplier in advance (before goods arrive), and later allocating that advance against the Purchase Invoice once goods are received and invoiced. This is the default payment mode for InMED's international suppliers.

**Estimated time:** 10–15 minutes per payment; 5–10 minutes for allocation

**Use case:** A supplier requires full payment (or partial advance) before shipping. InMED sends the bank transfer, then when goods arrive and are invoiced, the pre-payment is matched against the invoice to zero out the payable balance.

**Prerequisites:**
- The Purchase Order is approved (`Director Approval Status = Approved`) — never pay against an unapproved PO
- The supplier bank details are known
- You have proof of bank transfer (screenshot, SWIFT confirmation, etc.)
- The Supplier record has the correct currency/payment agreement confirmed. Current standard `Payment Terms Template` records are `Prepayment 100%` and `Prepayment 50/50`.

---

## Roles

| Step | Task | Role |
|---|---|---|
| 1–3 | Create and submit advance Payment Entry | `Ops - Accounting` |
| 4 | Allocate advance to Purchase Invoice (after goods arrive) | `Ops - Accounting` |

---

## Part A — Advance Payment (before goods arrive)

### Step 1 — Confirm the PO is approved before paying

**Login as:** `Ops - Accounting`

1. Search for `Purchase Order`, open the **Purchase Order** list, and open the Purchase Order that you are paying for.
2. Confirm:
   - **Director Approval Status** = `Approved`
   - **Status** = `Submitted`
3. Note the PO name (e.g. `PO-2026-00042`) — you will reference it in the payment.

**Rule: Do not send money or create a payment for a PO that is still Draft or not yet Approved.**

---

### Step 2 — Create the Payment Entry

1. Search for `Payment Entry`, open the **Payment Entry** list, and click **New**.
2. Fill in the header:
   - **Payment Type:** `Pay`
   - **Party Type:** `Supplier`
   - **Party:** select the supplier
   - **Paid From:** the InMED bank account you are paying from (e.g. `InMED — USD Bank Account`)
   - **Paid Amount:** the advance amount in the payment currency
   - **Currency:** match the supplier's invoice currency (USD or EUR). If the Supplier record has no Default Currency, confirm the currency with Accounting before submitting payment.
   - **Exchange Rate:** the rate on the day of the transfer (AMD equivalent per 1 USD/EUR)
3. Fill in the **Reference** section:
   - **Cheque / Reference No:** the bank transfer reference number or SWIFT number
   - **Cheque Date:** the date the transfer was sent
   - **Remarks:** include the PO number — e.g. `Advance payment for PO-2026-00042, Supplier: Medtronic`

4. Scroll down to the **References** table (this is where you link the payment to the PO):
   - Click **Add Row**
   - **Reference Document Type:** `Purchase Order`
   - **Reference Document Name:** select the PO (e.g. `PO-2026-00042`)
   - **Allocated Amount:** the advance amount

5. Attach the bank transfer proof:
   - Click the attachment icon ? upload the bank transfer confirmation or SWIFT receipt (required)

6. Click **Save**, then **Submit**.

**? Expected:**
- Payment Entry submitted — a payable credit exists on the supplier account
- The linked PO shows the advance in its payment history

---

### Step 3 — Inform the supplier

After submitting the payment entry, share the bank transfer confirmation with the supplier via your usual channel. The goods will be shipped once the supplier confirms receipt of payment.

---

## Part B — Allocate advance to Purchase Invoice (after goods arrive)

Once the goods have been received (Purchase Receipt submitted) and the Purchase Invoice has been created and submitted, you must link the advance payment to the invoice to clear the outstanding balance.

### Step 4 — Allocate the advance

**Login as:** `Ops - Accounting`

**Option A — From the Purchase Invoice (recommended):**

1. Open the submitted **Purchase Invoice**.
2. Check the **Outstanding Amount** — this should equal the full invoice amount (the advance is not yet matched).
3. Click **Get Outstanding Invoices** or scroll to the **Advance Payments** section.
4. In the advance payments table, you should see the Payment Entry from Step 2 listed.
5. Enter the **Allocated Amount** — usually the full advance if it equals or exceeds the invoice.
6. Click **Save** (on the allocation, not the invoice — the invoice is already submitted).

**Option B — From the Payment Entry:**

1. Search for `Payment Entry`, open the **Payment Entry** list, and open the Payment Entry from Step 2.
2. In the **References** table, click **Add Row** (or edit the existing row):
   - **Reference Document Type:** `Purchase Invoice`
   - **Reference Document Name:** select the Purchase Invoice
   - **Allocated Amount:** the amount to allocate against this invoice
3. Click **Save**.

**? Expected after allocation:**
- Purchase Invoice **Outstanding Amount** decreases by the allocated amount
- If advance = invoice total: invoice shows Outstanding = 0 (fully paid)
- Supplier account payable balance is reduced accordingly

---

## Partial advance scenarios

### Advance is less than invoice total
Example: You paid 50% advance, invoice is for the full amount.

- After allocation: invoice Outstanding = remaining 50%
- Pay the remaining balance by creating a second Payment Entry (Type: `Pay`) for the remaining amount
- Allocate that second payment against the same invoice

### Advance is more than invoice total
Example: You paid $5,000 advance, invoice turns out to be $4,200.

- Allocate $4,200 against the invoice ? invoice is fully paid
- The remaining $800 stays as an unapplied credit on the supplier account
- It will be available to allocate against the next invoice from this supplier

### Multiple receipts on one advance
If the supplier ships in multiple partial deliveries and invoices you separately for each:
- Create a separate Purchase Invoice for each shipment (from its Purchase Receipt)
- Allocate a portion of the advance against each invoice until the advance is fully consumed

---

## Checking supplier balance

To see the current outstanding balance with a supplier at any time:

1. Search for `Accounts Payable` and open the **Accounts Payable** report (Accounts ? Reports ? Accounts Payable)
2. Filter by **Party: Supplier**, select the supplier
3. The report shows outstanding invoices and any unapplied credits

Alternatively: search for `Supplier`, open the **Supplier** list, open the supplier record, then use **Accounting Ledger** to review all transactions chronologically.

---

## Common issues

| Symptom | Likely cause |
|---|---|
| Cannot see the advance in the Purchase Invoice allocation section | Payment Entry was not linked to the supplier or was not submitted; check the Payment Entry status |
| Exchange rate discrepancy between Payment Entry and Invoice | Invoice uses today's rate; Payment Entry used the transfer-day rate — this creates a minor exchange gain/loss entry, which is normal and expected |
| Advance not fully consumed after allocating | Invoice amount < advance amount; remaining credit stays on supplier account for next invoice |
| Payment Entry rejected by accounting | PO was not approved before payment was made — escalate to Director to retrospectively approve or cancel and redo |
| Payment terms are missing on Supplier | `Payment Terms Template` setup is incomplete; ask Accounting/System Manager to create or confirm the correct terms |
