# Cancellation and Correction Procedures

**Purpose:** Guide for all roles on what to do when a submitted document needs to be corrected or reversed. Covers which documents can be cancelled, who can cancel, the mandatory order to cancel chained documents, and the rule that every cancellation must have a written reason.

**Key principle:** ERPNext does not allow editing submitted documents. To correct a mistake, you must cancel the document (and any documents that depend on it) and re-create it correctly. Never delete documents — cancel them.

---

## General rules (apply to all cancellations)

1. **Cancel in reverse order** — always cancel the most dependent document first. If you try to cancel a document that has downstream documents still active, ERPNext will block you.
2. **Never delete submitted documents** — cancellation creates an audit trail; deletion destroys it. If ERPNext allows deletion, do not use it on any operational document.
3. **Always write the reason** — when cancelling, fill in the cancellation reason/remarks field before confirming. This is mandatory for governance.
4. **Get Director visibility on significant cancellations** — for anything that affects stock balances, payables, or receivables, a Director should be informed even if their approval is not technically required.
5. **Check linked documents before cancelling** — open the document and look at the linked/fetched documents section to see what depends on it.

---

## Who can cancel what

| Document | Who can cancel |
|---|---|
| Purchase Order | `Ops - Directors` (governance decision) |
| Purchase Receipt | `Ops - Inventory` + Director visibility |
| Purchase Invoice | `Ops - Accounting` + Director visibility |
| Landed Cost Voucher | `Ops - Accounting` |
| Payment Entry (supplier) | `Ops - Accounting` |
| Payment Entry (customer) | `Ops - Finance` + Director visibility |
| Sales Invoice | `Ops - Accounting` |
| Stock Entry (any type) | `Ops - Inventory` + Director visibility |
| Dispatch Case | `System Manager` only (complex linked document) |

**When in doubt: stop and ask System Manager before cancelling anything that has stock or financial impacts.**

---

## Cancellation chains by flow

### Purchase flow

The purchase document chain is:
```
Purchase Order
  └─► Purchase Receipt (adds stock)
        └─► Landed Cost Voucher (adjusts valuation)
        └─► Purchase Invoice (creates payable)
              └─► Payment Entry (records payment)
```

Cancel in this order (most dependent first):
1. **Payment Entry** — cancel if the advance or invoice payment has not yet been bank-confirmed and you need to undo it
2. **Purchase Invoice** — cancel before cancelling the Purchase Receipt
3. **Landed Cost Voucher** — cancel before cancelling the Purchase Receipt
4. **Purchase Receipt** — cancelling this reverses the stock increase; the PO will show quantities as not yet received again
5. **Purchase Order** — can be cancelled only if no receipts are linked, or after all receipts and invoices are cancelled

**Typical scenario — wrong quantity received:**
1. Cancel the Purchase Invoice (Accounting)
2. Cancel the Landed Cost Voucher if one was submitted (Accounting)
3. Cancel the Purchase Receipt (Inventory)
4. Create a new Purchase Receipt with the correct quantity
5. Re-create the LCV and Purchase Invoice

**Typical scenario — wrong item on PO:**
1. Cancel all downstream documents in order (Invoice → LCV → Receipt)
2. Cancel the Purchase Order (Director)
3. Create a new PO with the correct items, get approval, and proceed

---

### Dispatch Case flow

The Dispatch Case creates a chain of automatically submitted documents. The full chain for a return-expected (surgery) case is:

```
Dispatch Case
  ├─► Dispatch Stock Entry (Main → Delivery In-Transit)
  ├─► Delivery Stock Entry (Delivery In-Transit → Client WH)
  ├─► Return Pickup Stock Entry (Client WH → Return Pickup In-Transit)
  ├─► Return Receive Stock Entry (Return Pickup In-Transit → Returns)
  ├─► Consumption Stock Entry (Client WH → Material Issue)
  ├─► Restock Stock Entry (Returns → Main)
  └─► Sales Invoice
        └─► Payment Entry
```

**Important: cancelling individual stock entries without cancelling the Dispatch Case is dangerous — it will leave the case in an inconsistent state. Always involve System Manager for Dispatch Case corrections.**

**Most common correction — wrong invoice amount or quantities:**
1. Cancel the Payment Entry (if any was allocated to this invoice)
2. Cancel the Sales Invoice
3. Open the Dispatch Case — correct the `used_qty` or quantities on the Case Items
4. Save the Dispatch Case — a new draft Sales Invoice will be auto-created
5. Re-submit the invoice via the Invoice Preparation task

**Most common correction — wrong items on the Dispatch Case (before delivery):**
- If the case is still in `Draft` or `Confirmed` (not yet packed): edit the Case Items, save
- If the case has been packed but not delivered:
  1. Complete the delivery in reverse (this requires System Manager involvement to cancel the Dispatch Stock Entry)
  2. Edit the case
  3. Re-pack

**If the Dispatch Case has gone all the way to `Invoice Pending` or beyond:**
- Do not attempt to cancel the stock entries yourself
- Raise with System Manager — this is a complex multi-document reversal

---

### Sales Invoice — standalone correction

**Typical scenario — invoice was submitted with wrong price:**
1. Cancel the Payment Entry allocated to this invoice (Accounting / Finance)
2. Cancel the Sales Invoice (Accounting)
3. The Dispatch Case will return to a state where a new invoice can be generated — or create a new invoice manually with the correct amount
4. Re-submit and re-allocate

**To create a corrected invoice without full cancellation: use an Amendment**
- ERPNext allows amending a cancelled document — it creates a new draft with the cancelled document's data pre-filled
- Amend, correct the fields, and re-submit
- The amended document retains a link to the cancelled original for audit trail

---

### Payment Entry — cancellation

**Supplier advance paid in error or wrong amount:**
1. Cancel the Payment Entry (Accounting)
2. Verify no Purchase Invoice was already allocated — if it was, de-allocate first
3. Re-create the Payment Entry with correct details

**Client payment recorded in error:**
1. Cancel the Payment Entry (Finance + Director visibility)
2. The Debt Collection task outstanding balance will increase back to its previous state
3. If the case was auto-closed by this payment, it will re-open
4. Re-record the correct payment

---

## Cancelling a document step by step

**Login as:** appropriate role (see table above)

1. Open the document you need to cancel.
2. Confirm it is in `Submitted` state.
3. Click **Cancel** (button at top of form).
4. A dialog will appear asking for a cancellation reason — **fill in the reason clearly** (e.g. "Wrong qty received — re-entering as 45 units not 50", or "Invoice amount incorrect — customer was billed AMD 120,000 instead of AMD 115,000").
5. Confirm cancellation.

**✅ Expected:**
- Document status changes to `Cancelled`
- Linked stock/accounting entries are reversed automatically
- Document is visible in history with `Cancelled` status

**❌ If cancellation is blocked:**
- ERPNext will show which linked document is blocking cancellation
- Cancel that dependent document first, then retry

---

## Amending a cancelled document

Amending creates a corrected version that links back to the cancelled original — the preferred approach when the same document needs to be re-submitted with corrections.

1. Search for the document type you cancelled, open its list, and open the cancelled document.
2. Click **Amend** (button at top).
3. A new Draft is created with the same data.
4. Correct the fields that were wrong.
5. Submit the amended document.

The amended document will show `Amended From: [original document name]` — this is the audit trail.

---

## What NOT to do

| Don't | Why |
|---|---|
| Delete submitted documents | Destroys audit trail; creates ledger inconsistencies |
| Cancel stock entries without cancelling the Dispatch Case | Leaves the case in an inconsistent state — stock and case status will not match |
| Cancel a Purchase Invoice before the LCV | LCV references the receipt; inconsistency in valuation |
| Cancel documents without writing a reason | Makes it impossible to understand what happened later |
| Cancel a Payment Entry that has been bank-confirmed | Requires Director awareness; may need a correcting entry instead |
| Edit item codes or supplier on a live document | Not possible on submitted docs — cancel and re-create |

---

## When to call System Manager

Call `System Manager` for:
- Any Dispatch Case correction beyond the Sales Invoice level
- Any cancellation chain involving more than 3 linked documents
- Any situation where ERPNext blocks cancellation with an unclear error message
- Any case where you need to roll back a case to a previous status (e.g. `Invoice Pending` back to `Returns Received`)
- Any write-off or stock adjustment involving large quantities or high-value items

---

## Common issues

| Symptom | Likely cause and action |
|---|---|
| "Cannot cancel — document is linked to submitted document X" | Cancel document X first, then retry |
| Dispatch Case stuck in wrong status after a partial cancellation | System Manager needed — case state is inconsistent |
| Stock ledger shows negative quantity after cancellation | A receipt or stock entry was cancelled without cancelling the downstream issues first — System Manager needed |
| Payment Entry cancelled but Debt Collection task still shows old (lower) outstanding | Outstanding field on task is updated by automation — may need System Manager to trigger a recalculation |
| Invoice cancelled but Dispatch Case does not return to `Invoice Pending` | Check that the invoice cancellation completed successfully; System Manager can manually update case status if needed |
