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
- Status is recalculated from dates unless the tender is still Draft.

---

## Step 2 — Before using a tender item on invoice

Before submitting an invoice with tender-priced items, confirm:

1. There is only one active Tender Agreement for the hospital/item.
2. The tender row has enough remaining quantity.
3. The Sales Invoice customer is the same Customer used in the Tender Agreement **Hospital** field.

---

## Step 3 — Submit Sales Invoice

When a Sales Invoice is submitted:

- For each invoice item, the system searches active Tender Agreements for the same hospital/customer.
- If no active tender row matches the item, no tender quantity is updated for that item.
- If exactly one active tender row matches, the invoice quantity is added to `supplied_quantity`.
- `remaining_quantity` is recalculated.
- If more than one active tender row matches the same hospital/item, submit is stopped with a duplicate-tender message.
- If invoice quantity is greater than remaining tender quantity, submit is stopped with an over-supply message so Accounting/Directors can decide what to change.

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

## Known next control

Invoice cancellation reversal is handled separately. If a Sales Invoice that updated tender quantities is later cancelled, tender supplied quantities must be reversed by the cancellation logic once that control is deployed.
