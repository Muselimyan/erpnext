# Dispatch Case — Standard Sale (No Return) Walkthrough

**Purpose:** Step-by-step test script to verify the complete unified dispatch flow for a standard sale (no items expected to return). Run as a smoke test after deployment or after any server script changes.

**Estimated time:** 20–30 minutes

**Use case:** Customer orders items, delivery driver delivers them, all items are consumed/sold. No returns.

**Prerequisites:**
- At least one Customer exists
- At least one Item exists with stock in `Main - Inmed`
- Users exist for each role (or use a single admin account and follow the role instructions)

---

## Roles used in this test

| Step | Task | Logged-in role |
|---|---|---|
| 1 | Create Order entry task | `Ops - Order Accepting` |
| 2 | Create and submit Dispatch Case | `Ops - Order Creating` |
| 3 | *(Discount approval — if applicable)* | `Ops - Directors` |
| 4 | Complete Pack task | `Ops - Inventory` |
| 5 | Complete Delivery task (Picked Up → Delivered) | `Delivery Driver` |
| 6 | Complete Invoice Preparation task | `Ops - Accounting` |
| 7 | Record payment on Debt Collection task | `Ops - Finance` |

---

## Step 1 — Create an Order entry task

**Login as:** `Ops - Order Accepting`

1. Open the **Task** list and click **New**.
2. Fill in:
   - **Task Kind:** `Order entry`
   - **Subject:** `Order: [Customer name] — [brief description]`
   - **Customer:** select the test customer
   - **Description:** note what items and quantities the customer requested
   - **Assigned To:** leave as `order.creation.team@example.com` (Order Creation Team)
3. Click **Save**.

**✅ Expected:**
- Task saved with Status `Open`
- No server scripts fire on Order entry task creation — it's a manual record

---

## Step 2 — Create and submit the Dispatch Case

**Login as:** `Ops - Order Creating`

1. Open your Order entry task from Step 1.
2. Open a new tab: search for `Dispatch Case` and click **New**.
3. Fill in:
   - **Customer:** select the test customer
   - **Return Expected:** **unchecked** ← critical for this scenario
   - **Surgery Date:** optional
   - **Client Location Warehouse:** leave blank (not needed when Return Expected = No)
   - **Notes:** optional
4. In the **Case Items** table, click **Add Row**:
   - **Item Code:** select the test item
   - **Dispatched Qty:** e.g. `2`
   - **Unit Price:** enter the selling price
   - **Discount %:** leave `0` for this scenario
5. Click **Save** (stays in Draft; server script checks for discounts).
6. Click **Submit**.

**✅ Expected after Save:**
- Status = `Draft`
- No Discount Approval task (Discount % is 0)

**✅ Expected after Submit:**
- Status = `Confirmed`
- A **Pack task** is auto-created (check in Step 3)
- The case receives its autoname `DC-YYYY-NNNNN`

**❌ Should NOT happen:**
- Status stuck at `Awaiting Approval` → discount % > 0 was found; go to Step 2a below

7. Go back to the Order entry task. Set **Dispatch Case** field to link to this case. Change Status to `Completed` and Save.

---

## Step 2a — Discount approval (only if Discount % > 0)

**Login as:** `Ops - Directors`

1. Open the **Task** list and filter: **Task Kind = Discount Approval**, **Status = Open**.
2. Open the Discount Approval task for your case.
3. Review the discount. Set **Approval Outcome** to `Approved`.
4. Change Status to `Completed` and Save.

**✅ Expected:**
- Dispatch Case status → `Confirmed`
- Pack task auto-created

**On Rejection:**
- Dispatch Case stays `Draft`
- A new `Order entry` task is created for the Order Creation Team with note "Discount rejected — revise pricing."
- Order Creation person opens the Dispatch Case, adjusts prices, saves again (new approval task fires if discount still present)

---

## Step 3 — Verify Pack task and complete it

**Login as:** `Ops - Inventory`

1. Open the **Task** list, filter: **Task Kind = Pack / prepare items**, **Status = Open**.
2. Find the task with Subject `Pack: DC-YYYY-NNNNN — [Customer]`.

**✅ Expected task fields:**
- Task Kind = `Pack / prepare items`
- Dispatch Case linked = your case
- Status = `Open`

3. Open the linked Dispatch Case. In the **Case Items** table:
   - For each **serial-tracked** item: fill in `serial_no`
   - For each **batch-tracked** item: fill in `batch_no` (select earliest-expiry batch — FEFO)
   - Save the Dispatch Case.
4. Back on the task, change **Status** to `Completed` and Save.

**✅ Expected after completing Pack task:**
- **Dispatch Stock Entry** auto-created and submitted: `Main - Inmed → Delivery In-Transit - Inmed`
- Dispatch Case status → `Packed`
- A **Delivery task** is auto-created

**❌ Should NOT happen:**
- Error "Serial No required" → fill in `serial_no` on the Case Item row first
- Error "Batch No required" → fill in `batch_no` on the Case Item row first

---

## Step 4 — Complete the Delivery task (multi-state)

**Login as:** `Delivery Driver`

1. Open the **Task** list, filter: **Task Kind = Delivery**, **Status = Open**.
2. Find the task `Deliver: DC-YYYY-NNNNN — [Customer]`.

### Sub-step 4a — Mark as Picked Up

3. On the task, set **Delivery Status** to `Picked Up` and Save.

**✅ Expected:**
- Dispatch Case status → `In Transit`
- No Stock Entry fires at Picked Up (items are already in Delivery In-Transit from Pack step)

### Sub-step 4b — Mark as Delivered

4. Attach a **delivery photo**: click the attachment icon on the task, upload a photo.
5. Fill in **Driver Handover Note**: note who received the items at the client location.
6. Set **Delivery Status** to `Delivered` and Save.

**✅ Expected after Delivered:**
- **Delivery Stock Entry** auto-submitted: `Delivery In-Transit - Inmed → Client Location WH`
  *(for no-return cases the stock moves all the way through since client location WH is set automatically)*
- **Consumption Stock Entry** auto-submitted: `Client Location WH → Material Issue` (all dispatched items)
- Draft **Sales Invoice** auto-created for full dispatched quantities
- Dispatch Case status → `Invoice Pending`
- **Invoice Preparation task** auto-created for Accounting Team
- `used_qty` on each Case Item row = `dispatched_qty`

**❌ Should NOT happen (gate blocks — correct behavior):**
- Error "Delivery photo is required" if you try to set Delivered without a photo → attach photo first
- Error "Handover Note is required" → fill the note field first

---

## Step 5 — Complete the Invoice Preparation task

**Login as:** `Ops - Accounting`

1. Open the **Task** list, filter: **Task Kind = Invoice preparation / create invoice**, **Status = Open**.
2. Find the task `Invoice: DC-YYYY-NNNNN — [Customer]`.
3. Open the linked **Sales Invoice** (in Draft).
4. Verify:
   - Items and quantities match `used_qty` from the Dispatch Case Items (= dispatched quantities for no-return)
   - **Update Stock** is **unchecked** (stock already moved by the Consumption Stock Entry)
   - Prices are correct
5. Click **Submit** on the Sales Invoice.
6. Back on the task, change **Status** to `Completed` and Save.

**✅ Expected:**
- Sales Invoice submitted
- Dispatch Case status → `Invoiced` (then immediately → `Payment Pending` if outstanding > 0)
- **Debt Collection task** auto-created or updated for Finance Team if outstanding > 0
- If fully prepaid: Dispatch Case → `Closed`

**❌ Should NOT happen:**
- Update Stock = checked on the Sales Invoice → uncheck before submitting

---

## Step 6 — Record payment on the Debt Collection task

**Login as:** `Ops - Finance`

1. Open the **Task** list, filter: **Task Kind = Debt Collection**, **Status = Open**.
2. Find the task for your customer.
3. On the task, fill in the **Record Payment** section:
   - **New Payment Amount:** the amount received
   - **Payment Method:** Cash / Bank Transfer / Card
   - **Payment Reference:** transaction reference number
4. Save the task.

**✅ Expected after Save:**
- A **Payment Entry** (Receive type) is auto-created in ERPNext, allocated FIFO across open invoices
- A **Distribute Payment task** is auto-created for the Finance Team (to handle physical payment)
- Outstanding balance on the task decreases

**On full payment (outstanding = 0):**
- Debt Collection task auto-completes
- Dispatch Case status → `Closed`

---

## Step 7 — Verify final state

**Login as:** any

Open the Dispatch Case `DC-YYYY-NNNNN` and verify:

| Field | Expected value |
|---|---|
| Status | `Closed` |
| Dispatch Stock Entry | Submitted ✓ |
| Delivery Stock Entry | Submitted ✓ |
| Consumption Stock Entry | Submitted ✓ |
| Sales Invoice | Submitted ✓ |
| Case Items — used_qty | = dispatched_qty for all rows |
| outstanding_amount | 0 |

Go to **Stock Ledger** and filter by test item. Confirm the full movement chain:
- Deduction from `Main - Inmed` (Pack SE) ✓
- Addition to `Delivery In-Transit - Inmed` (Pack SE) ✓
- Transfer to Client WH (Delivery SE) ✓
- Material Issue from Client WH (Consumption SE) ✓

---

## Quick reference — task chain for this path

```
Order entry task (manual)
  └─► Dispatch Case created & submitted
        └─► [Discount Approval task — only if discount > 0]
        └─► Pack task (Inventory)
              └─► Delivery task (Driver) — Todo → Picked Up → Delivered
                    └─► Invoice Preparation task (Accounting)
                          └─► Debt Collection task (Finance)  ─► Distribute Payment task
```
