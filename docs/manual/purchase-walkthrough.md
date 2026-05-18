# Purchase Flow Walkthrough — PO → Receipt → LCV → Invoice

**Purpose:** Step-by-step guide for recording a complete purchase cycle: from creating the Purchase Order through director approval, receiving goods, computing landed cost, and recording the supplier invoice. Run this any time you are making a purchase from a supplier.

**Estimated time:** 30–60 minutes (spread across multiple days for international shipments)

**Use case:** InMED orders items from a supplier (domestic or import), receives them into the warehouse, computes the true landed cost including freight and import duty, and records the supplier invoice for payables.

**Prerequisites:**
- The Supplier record already exists (Doc 07A — Suppliers and Procurement)
- The Items you are ordering already exist in the catalog with correct supplier assignment (Doc 06A)
- Director users exist and can see `Purchase Approval` tasks
- For import items: `hs_code` and `import_tax_rate` are filled on each Item
- The purchasing test user can search for and open `Purchase Order`
- The purchasing test user can select the intended Supplier. Current known suppliers are `ZMD` and `CHUNLI`.
- The intended Supplier has its Default Currency filled. If currency does not auto-fill, stop and fix the Supplier record before continuing.
- If supplier payment terms are required for the test, use the existing `Payment Terms Template` records: `Prepayment 100%` or `Prepayment 50/50`.
- The director test user can search for and open `Task`
- The inventory test user can search for and open `Purchase Receipt`
- The accounting test user can search for and open `Payment Entry`, `Landed Cost Voucher`, and `Purchase Invoice`

---

## Roles used in this flow

| Step | Task | Logged-in role |
|---|---|---|
| 1 | Create Draft Purchase Order | `Ops - Purchasing` |
| 2 | Create Purchase Approval task | `Ops - Purchasing` |
| 3 | Approve (or reject) PO | `Ops - Directors` |
| 4 | *(If prepayment)* Create advance Payment Entry | `Ops - Accounting` |
| 5 | Submit PO and send to supplier | `Ops - Purchasing` |
| 6 | Create Purchase Receipt when goods arrive | `Ops - Inventory` |
| 7 | Create Landed Cost Voucher (imports only) | `Ops - Accounting` |
| 8 | Create Purchase Invoice | `Ops - Accounting` |
| 9 | *(If prepaid)* Allocate advance to invoice | `Ops - Accounting` |

---

## Step 1 — Create a Draft Purchase Order

**Login as:** `Ops - Purchasing`

1. Search for `Purchase Order`, open the **Purchase Order** list, and click **New**.
   - If you do not see the **Purchase Order** DocType, or you can open it but cannot click **New** or **Save**, stop here: the test user is missing Purchase Order permissions. Ask a System Manager to check permissions for `Ops - Purchasing`.
2. Fill in the header:
   - **Supplier:** select exactly one supplier, such as `ZMD` or `CHUNLI` for current testing (do not mix suppliers on one PO)
   - **Schedule Date:** your best estimate of when goods will arrive
   - **Purchase Reason:** choose the reason — `Reorder (Doc 08)`, `Ad-hoc demand`, `Replacement`, or `Emergency`
   - **Requested By:** select the person requesting this purchase
   - **Currency:** should default from Supplier (usually `USD` or `EUR`) — if it stays blank or wrong, stop and fix the Supplier record before continuing
3. In the **Items** table, add rows:
   - **Item Code:** select the item (only items whose supplier matches this PO's supplier)
   - **Qty:** the quantity you intend to order
   - **UOM:** confirm it matches the buying unit (e.g. `Nos`, `Box`)
   - **Rate:** the agreed supplier price per unit
4. Attach the supplier quotation or proforma invoice (required):
   - Click the paperclip / attachment icon → upload PDF or image
5. Click **Save** (leave as Draft — do not submit yet).

**✅ Expected:**
- PO saved in Draft state
- `Director Approval Status` = `Pending` (auto-set)

**❌ Should NOT happen:**
- Error "Item X supplier is Y but PO supplier is Z" → the item's default supplier does not match this PO's supplier; use the correct supplier or create a separate PO

---

## Step 2 — Create the Purchase Approval task

**Login as:** `Ops - Purchasing`

1. Search for `Task`, open the **Task** list, and click **New**.
2. Fill in:
   - **Subject:** `Purchase Approval — [PO name, e.g. PO-2026-00042]`
   - **Task Kind:** `Purchase Approval`
   - **Purchase Order:** link to the PO you just created
   - **Assigned To:** the Director who will approve this purchase
   - **Description:** include the reason for the purchase, urgency, and any relevant context (e.g. "Low stock on Item X — surgery scheduled in 2 weeks")
3. Click **Save**.

**✅ Expected:**
- Task saved with Status `Open`, assigned to the Director

---

## Step 3 — Director approves or rejects the PO

**Login as:** `Ops - Directors`

1. Search for `Task` and open the **Task** list, filter: **Task Kind = Purchase Approval**, **Status = Open**.
2. Open the task for this PO.
3. Review the linked Purchase Order (click the `Purchase Order` link to open and review items, quantities, and prices).
4. Set **Approval Outcome**:
   - `Approved` — purchase can proceed
   - `Rejected` — purchase must not proceed; provide a reason
5. Fill in **Approval Note** — always explain the decision (required operationally).
6. Change Task **Status** to `Completed` and Save.

**✅ Expected after Approved:**
- On the Purchase Order: `Director Approval Status` = `Approved`, `Director Approved By` and `Director Approved At` are filled

**On Rejection:**
- On the Purchase Order: `Director Approval Status` = `Rejected`
- The Purchasing team must not proceed; they must either cancel the PO or revise and re-request approval
- If the PO is revised after rejection: any edits to items, quantities, or pricing will clear the approval status back to `Pending`, and a new approval task must be created

**Note — PO edited after approval:**
- If the Purchasing team edits the PO (items, qty, rate, supplier, or reason) after the Director has approved it, approval is automatically cleared back to `Pending`
- A new Purchase Approval task must be created before submission

---

## Step 4 — (Prepayment) Create advance Payment Entry

**Login as:** `Ops - Accounting`

*Skip this step if you are paying after receipt.*

Current policy: most suppliers require 100% advance payment before shipping.

1. Confirm the PO's `Director Approval Status` = `Approved` before sending any payment.
2. Search for `Payment Entry`, open the **Payment Entry** list, and click **New**.
3. Fill in:
   - **Payment Type:** `Pay`
   - **Party Type:** `Supplier`
   - **Party:** select the supplier
   - **Paid Amount:** the advance amount (in the payment currency)
   - **Reference No / Remarks:** include the PO number (e.g. `Advance for PO-2026-00042`)
4. Attach the bank transfer confirmation (required).
5. Click **Submit**.

*When the Purchase Invoice is created later (Step 8), you will allocate this advance against it (Step 9).*

---

## Step 5 — Submit and send the PO to the supplier

**Login as:** `Ops - Purchasing`

1. Open the Purchase Order.
2. Confirm `Director Approval Status` = `Approved`.
3. Click **Submit**.
4. Send the PO to the supplier:
   - Use the **Email** button or click **Print** → save as PDF and send via your usual channel
   - The sent document must match the approved PO exactly

**✅ Expected:**
- PO submitted
- If submission fails with "Director approval is required" → approval step was skipped or approval was cleared; complete Step 3 again

---

## Step 6 — Receive goods (Purchase Receipt)

**Login as:** `Ops - Inventory`

Goods have physically arrived at the warehouse.

1. Open the submitted **Purchase Order**.
2. Click **Create** → **Purchase Receipt**.
3. On the Purchase Receipt:
   - **Set Warehouse:** `Main - Inmed` (all rows must land here)
4. For each item row, enter the **actual received quantity** — this may be less than the PO qty if the delivery is partial. Do not force the qty to match the PO.
5. For **batch-tracked items** (items that have a batch number):
   - Click the **Batch No** field on the row
   - Either select an existing batch or create a new one:
     - Batch name: use the supplier's printed lot/batch code if available; otherwise use internal series `LOT-YYYY-#####`
     - **Expiry Date on the Batch must be set** (required for items that track expiry)
6. For **serial-tracked items**:
   - Enter all serial numbers in the **Serial No** field on the row (one per line)
7. Click **Save**, then click **Submit**.

**✅ Expected:**
- Stock increases in `Main - Inmed` for the received quantities
- For partial delivery: the PO still shows outstanding (undelivered) quantity

**❌ Should NOT happen:**
- Error "Receiving must be into Main - Inmed" → check that the Set Warehouse field is set to `Main - Inmed`
- Error "Batch No is missing" → fill the Batch No field before submitting
- Error "Batch must have Expiry Date" → open the Batch record and enter the expiry date, then return to the receipt

**Partial delivery note:**
- Submit the receipt for what arrived
- The PO remains open for the remaining quantity
- When the next shipment arrives, repeat from Step 6 (create another Purchase Receipt from the same PO)

---

## Step 7 — Create Landed Cost Voucher (imports only)

**Login as:** `Ops - Accounting`

*Skip this step for purely local purchases with no freight or import charges.*

For import purchases, you must record all charges beyond the supplier price to compute the true unit cost.

1. Search for `Landed Cost Voucher`, open the **Landed Cost Voucher** list, and click **New**.
2. In the **Purchase Receipts** table, click **Add Row**:
   - **Receipt Document Type:** `Purchase Receipt`
   - **Receipt Document:** select the Purchase Receipt from Step 6
   - Click the **Fetch Items from Purchase Receipts** button — the Items table will auto-populate
3. In the **Charges** table, add one row per charge type:

   **Transportation / Freight:**
   - **Charge Type:** `Actual`
   - **Description:** `Freight / Transportation`
   - **Amount:** the freight cost (in whatever currency you paid)
   - **Currency:** the freight currency
   - **Exchange Rate:** the rate on the day of this transaction
   - **Distribution Method:** `By Qty` for homogeneous items; `By Amount` if items have very different unit prices

   **Import Duty:**
   - **Charge Type:** `Actual`
   - **Description:** `Import Duty`
   - **Amount:** *this should be pre-filled automatically* — the system reads `import_tax_rate` from each item and computes the duty
   - Confirm the pre-filled amount against your customs declaration; adjust if needed
   - **Currency:** `AMD` (typically; match what you paid the customs authority)

   **Other fees (if any):**
   - Add separate rows for customs clearance fees, brokerage, port fees, etc.

4. Click **Save**, review the **Items** table to see how charges are distributed per item line and the resulting Valuation Rate adjustment.
5. Click **Submit**.

**✅ Expected after Submit:**
- Valuation Rate of each item in the linked receipt is recalculated upward
- New Valuation Rate = (supplier price + distributed charges) / received qty
- Stock ledger records the adjustment entries
- All subsequent sales/consumption from this batch use the landed cost rate

**❌ Should NOT happen:**
- LCV linked to a different receipt than the one for this shipment → double-check the Receipt Document field

---

## Step 8 — Create Purchase Invoice

**Login as:** `Ops - Accounting`

1. Search for `Purchase Receipt`, open the **Purchase Receipt** list, and open the Purchase Receipt from Step 6.
2. Click **Create** → **Purchase Invoice**.
3. On the Purchase Invoice:
   - Enter the **Supplier Invoice No** (from the supplier's paper/PDF invoice)
   - Enter the **Supplier Invoice Date**
   - Confirm `Update Stock` is **unchecked** ← critical
   - Verify item quantities and rates match what was billed (they should match the receipt by default)
4. Click **Save**, then **Submit**.

**✅ Expected:**
- Payable entry created for the supplier
- `Update Stock` must remain unchecked — stock was already updated by the Purchase Receipt

**❌ Should NOT happen:**
- Error "Do not use Purchase Invoice to update stock" → uncheck `Update Stock` before submitting

**If invoice arrives before goods:**
- Create the Purchase Invoice directly (New → fill Supplier, link to PO if available, enter invoice number and date, ensure Update Stock = OFF, Submit)
- When goods later arrive, proceed with Step 6 as normal

---

## Step 9 — Allocate prepayment to the invoice (if applicable)

**Login as:** `Ops - Accounting`

*Skip if payment was not prepaid.*

1. Open the submitted **Purchase Invoice**.
2. Click **Get Outstanding Invoices** or use the **Payment Entry** allocation form.
3. Select the outstanding advance Payment Entry created in Step 4.
4. Allocate the advance amount against this invoice.
5. Save the allocation.

**✅ Expected:**
- Invoice outstanding balance reduces by the advance amount
- If advance = invoice total: invoice is fully paid
- If advance > invoice total: the excess remains as a credit on the supplier account for the next invoice

---

## Final state check

After completing all steps, verify:

| Document | Expected state |
|---|---|
| Purchase Order | Submitted, all qty received (or partially open if partial delivery) |
| Purchase Receipt | Submitted, stock increased in `Main - Inmed` |
| Landed Cost Voucher | Submitted (imports only), Valuation Rate updated |
| Purchase Invoice | Submitted, payable created |
| Payment Entry (if prepaid) | Submitted, allocated against the invoice |

To confirm stock entered correctly:
- Open **Stock Ledger** and filter by the item(s) received
- Confirm quantities increased in `Main - Inmed` at the time of the Purchase Receipt

---

## Common failure modes

| Symptom | Likely cause |
|---|---|
| "Director approval required" when submitting PO | Approval task not completed, or PO was edited after approval (which clears it) |
| "Item X supplier is Y but PO supplier is Z" | The item's default supplier in the Item master does not match the selected PO supplier |
| "Receiving must be into Main - Inmed" | Set Warehouse on the Purchase Receipt is set to a different warehouse |
| "Batch must have Expiry Date" | The batch was created without an expiry date; open the Batch record and set the expiry |
| "Do not use Purchase Invoice to update stock" | `Update Stock` checkbox is checked on the Purchase Invoice; uncheck it |
| Import duty not auto-filled on LCV | `hs_code` or `import_tax_rate` is missing on the Item master; fill those fields |
| Stock did not increase after Purchase Receipt | Check that the receipt was submitted (not just saved as Draft) |

---

## Quick reference — document chain

```
Draft Purchase Order (Ops - Purchasing)
  └─► Purchase Approval task (Director)
        └─► [Rejected: PO cancelled or revised]
        └─► [Approved: PO submitted and sent to supplier]
              └─► [Prepayment: Payment Entry (Accounting)]
              └─► Purchase Receipt — goods arrive (Inventory)
                    └─► Landed Cost Voucher — import charges (Accounting)
                    └─► Purchase Invoice — supplier bill (Accounting)
                          └─► [Allocate prepayment against invoice]
```
