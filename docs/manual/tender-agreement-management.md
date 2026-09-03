# Tender Agreement Management Walkthrough

**Purpose:** Use this manual to create, maintain, and test hospital Tender Agreements, and to understand how Sales Invoice submission updates tender fulfillment.

**Who uses this:** `Ops - Accounting`, `Ops - Directors`; `Ops - Order Creating` may read tender information.

**ERPNext screens to confirm first:** `Tender Agreement`, `Sales Invoice`, `Customer`, `Item`

---

## Core rule

For one hospital/customer, the same item must not be present in more than one active Tender Agreement at the same time.

Valid:

```text
Hospital A / Tender 1 / Item X
Hospital A / Tender 2 / Item Y
```

Invalid:

```text
Hospital A / Tender 1 / Item X
Hospital A / Tender 2 / Item X
```

If duplicate active tenders exist for the same hospital and item, Sales Invoice submit is stopped so tender quantities cannot be double-counted.

---

## Step 1 — Create a Tender Agreement

**Login as:** `Ops - Accounting` or `Ops - Directors`

1. Search for `Tender Agreement`.
2. Click **New**.
3. Fill:
   - **Tender Name**
   - **Hospital** — Customer linked to this tender
   - **Valid From**
   - **Valid To**
   - **Status**
4. Add rows in the Items table:
   - **Item Code**
   - **Tender Price**
   - **Won Quantity**
5. Save.

**Expected after Save:**
- `remaining_quantity = won_quantity - supplied_quantity` for each row.
- Status is recalculated from dates unless the tender is manually Closed.
- `Draft` means the tender is not active yet; it can automatically become `Active` when today's date reaches the valid date range.
- If a tender is manually set to `Closed`, it stays Closed on later saves; the date-based auto-status logic must not reopen it.

---

## Step 2 — Before using a tender item on invoice

Before submitting an invoice with tender-priced items, confirm:

1. There is only one active Tender Agreement for the hospital/item.
2. The tender row has enough remaining quantity.
3. The Sales Invoice customer is the same hospital Customer used in the Tender Agreement **Hospital** field. Tenders are hospital-only; they do not apply to doctor/client-only Customer records.

---

## Step 3 — Submit Sales Invoice

When a Sales Invoice is submitted:

- For each invoice item, the system searches active Tender Agreements for the same hospital/customer.
- If no active tender row matches the item, no tender quantity is updated for that item.
- If exactly one active tender row matches, the invoice item rate must equal the tender row's `tender_price` before submit can continue.
- If the rate matches, the invoice quantity is added to `supplied_quantity` after submit.
- `remaining_quantity` is recalculated.
- If more than one active tender row matches the same hospital/item, submit is stopped with a duplicate-tender message.
- If invoice quantity is greater than remaining tender quantity, submit is stopped with an over-supply message so Accounting/Directors can decide what to change.
- If invoice rate differs from `tender_price`, submit is stopped so the tender price cannot be bypassed.

---

## Over-supply decision workflow

If invoice submit stops because the tender does not have enough remaining quantity, review with Accounting/Director.

Common decisions:

| Situation | Possible action |
|---|---|
| Invoice quantity is wrong | Correct the Sales Invoice quantity |
| Tender won quantity is wrong or extended | Update the Tender Agreement won quantity, then submit again |
| Wrong tender is active | Close/expire the wrong tender, then submit again |
| Sale is not under tender | Remove/adjust tender pricing/business handling before submit |

Do not allow tender remaining quantity to silently go negative.

---

## Duplicate active tender workflow

If invoice submit stops because the same hospital/item exists in multiple active tenders:

1. Open the listed Tender Agreements.
2. Decide which one is the valid active tender for that item.
3. Close or expire the duplicate/old tender, or move the item to the correct agreement.
4. Submit the Sales Invoice again.

---

## Transaction safety

Tender fulfillment updates must be part of the Sales Invoice submit transaction. The tender update script must not manually call `frappe.db.commit()`.

This prevents partial updates where a tender changes but the invoice submit later fails.

---

## Cancellation reversal

When a Sales Invoice submit updates tender quantities, the invoice records a read-only **Tender Fulfillments** audit table:

| Field | Meaning |
|---|---|
| Tender Agreement | Which tender was updated |
| Item Code | Which item consumed tender quantity |
| Quantity | Quantity added to tender supplied quantity |
| Sales Invoice Item | Internal invoice item row reference |
| Applied At | Timestamp of the tender update |

If the Sales Invoice is later cancelled, the cancellation script reads this table and subtracts the exact recorded quantities from the same Tender Agreement rows.

Expected result after cancellation:

```text
Tender supplied_quantity decreases by the invoice quantity
Tender remaining_quantity increases back by the invoice quantity
```

This avoids guessing which tender to reverse if the tender later expires, closes, or another tender is created.
