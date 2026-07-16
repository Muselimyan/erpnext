# Dispatch Case — Surgery / Return Case Walkthrough (v2 - Updated)

> **📌 This is the CURRENT working version** reflecting the actual deployed system. Barcode/batch/serial tracking is temporarily disabled operationally and is documented only as future/optional behavior.  
> The original `surgery-case-walkthrough.md` is kept as a reference of the initial design vision.  
> **Use this v2 document for testing and update only this file going forward.**

**Purpose:** Step-by-step test script to verify the complete unified dispatch flow for a return-expected case (surgery sets, equipment loans, or any dispatch where items are expected to come back). Covers all 14 states. Run as a smoke test after deployment or after any server script changes.

**Estimated time:** 45–60 minutes

**Use case:** Items are dispatched to a client location (e.g. a hospital), used in part, and the remainder is returned. Invoice covers only the used portion.

**Prerequisites:**
- At least one Customer exists
- At least one **Collection Set** exists with at least one item (optional — you can fill items manually)
- Stock of those items is available in `Main - Inmed`
- A **Client Location Warehouse** exists linked to the test customer
- Users exist for each role below

---

## Roles used in this test

| Step | State | Logged-in role |
|---|---|---|
| 1 | Create Order entry task | `Ops - Order Accepting` |
| 2 | Create and submit Dispatch Case | `Ops - Order Creating` |
| 2a | *(Discount approval — if applicable)* | `Ops - Directors` |
| 3 | Complete Pack task (prepare products) | `Ops - Inventory` |
| 4 | Delivery task — Picked Up | `Delivery Driver` |
| 5 | Delivery task — Delivered | `Delivery Driver` |
| 6 | Return Call task — schedule pickup | `Ops - Returns` |
| 7 | Return Pickup task — Picked Up | `Delivery Driver` |
| 8 | Return Pickup task — Returned to Warehouse | `Delivery Driver` |
| 9 | Returns Inspection task | `Ops - Returns` |
| 10 | Restock task *(parallel)* | `Ops - Returns` |
| 11 | Invoice Preparation task | `Ops - Accounting` |
| 12 | Debt Collection task | `Ops - Finance` |

---

## Step 1 — Create an Order entry task

**Login as:** `Ops - Order Accepting`

1. Search for `Task`, open the **Task** list, and click **New**.
2. Fill in:
   - **Task Kind:** `Order entry`
   - **Subject:** `Order: [Customer name] — [brief description, e.g. Surgery set Dr. Smith 15/06]`
   - **Customer:** select the test customer
   - **Description:** note the items, quantities, surgery date, and any special instructions
   - **Assigned To:** `order.creation.team@example.com` (Order Creation Team)
3. In the **Product Lines** table, add the items for this order:
   - Click **Add Row**
   - Select **Item Name** (or enter **Item Code**)
   - Enter **Qty** (quantity needed)
   - Select **Warehouse** (default: `Main - Inmed`)
   - Repeat for each item
4. Click **Save**.

**✅ Expected:**
- Task saved with Status `Open`
- Product lines table shows all items with available quantities

---

## Step 2 — Create the Dispatch Case and complete Order Entry

**Login as:** `Ops - Order Creating`

1. Open your Order entry task from Step 1.
2. Click **Accept / Start Task**.
   - The button is visible to every user who has not already accepted this task.
   - After you accept it, the button disappears for you because the task is already accepted by your user.
3. Open a new tab: search for `Dispatch Case` and click **New**.
4. Fill in:
   - **Customer:** select the test customer
   - **Return Expected:** **checked** — critical for this scenario
   - **Client Location Warehouse:** select the client's warehouse (e.g. `Dr. Smith WH - Inmed`)
   - **Surgery Date:** the surgery/delivery date
5. In the **Case Items** table, verify or add items:
   - **Item Code:** search by any visible text, such as item code, item name, description, item group, or customer code
   - **Dispatched Qty:** enter the quantity needed
   - **Unit Price:** enter or verify the selling price
   - **Discount %:** leave `0` unless director approval is required
6. Click **Save**.
7. Click **Save**, then **Submit** on the Dispatch Case.
8. Go back to the Order entry task and link the **Dispatch Case** field to this case.
9. If a blue **Save** button appears near the Status field, click **Save** first.
10. Click the red **Complete Task** button near the Status field.

**✅ Expected after submitting the Dispatch Case and completing the Order Entry task:**
- Dispatch Case Status = `Confirmed`
- Pack task auto-created for Inventory Team
- Case receives autoname `DC-YYYY-NNNNN`

**❌ Should NOT happen:**
- Error `Submit the Dispatch Case before completing the Order entry task.` → open the linked Dispatch Case and click **Submit** first.
- Error `Link a Dispatch Case before completing the Order entry task.` → link the Dispatch Case field on the Order entry task.
- Status stuck at `Awaiting Approval` → discount % > 0 was found; go to Step 2a below.

---

## Step 2a — Discount approval (only if Discount % > 0)

**Login as:** `Ops - Directors`

1. Search for `Task` and open the **Task** list, filter: **Task Kind = Discount Approval**, **Status = Open**.
2. Open the Discount Approval task for your case.
3. Set **Approval Outcome** to `Approved`.
4. If a blue **Save** button appears near the Status field, click **Save** first.
5. Click the red **Complete Task** button near the Status field.

**✅ Expected:** Dispatch Case status changes to `Confirmed`, Pack task auto-created.

**On Rejection:** Dispatch Case stays `Draft`. A new `Order entry` task is auto-created for Order Creation Team. Order Creation person revises pricing on the Dispatch Case, saves again.

---

## Step 3 — Complete the Pack task (prepare products)

**Login as:** `Ops - Inventory`

### 3.1 Accept the Pack task

1. Search for `Task` and open the **Task** list.
2. Filter: **Task Kind = Pack / prepare items**, **Status = Open**.
3. Find `Pack: DC-YYYY-NNNNN — [Customer]`.
4. Click **Accept / Start Task** button.

**✅ Expected:**
- Task is accepted by your user and becomes editable for you
- The Accept button disappears for your user after acceptance
- Other users who have not accepted the task can still see their own Accept button
- Task status is `Working` or remains active until completion

### 3.2 Prepare products

5. On the Pack task form, review the product information for the linked Dispatch Case.
6. Physically prepare the products from `Main - Inmed`.
7. Barcode/batch/serial tracking is **temporarily disabled for now**, so completion should not require Batch No, Serial No, or Expiry Date.

**✅ Expected during preparation:**
- Products are prepared according to the Dispatch Case item rows
- No Batch No / Serial No mandatory error should appear while completing the task

**Optional / future barcode workflow:**
- The Task Product Work Area and barcode scanning workflow may be used later when barcode tracking is re-enabled.
- FEFO should remain warning-only, not blocking, when barcode tracking is active again.

### 3.3 Complete the Pack task

8. When products are prepared, return to the Task form.
9. If a blue **Save** button appears near the Status field, click **Save** first.
10. Click the red **Complete Task** button near the Status field.

**✅ Expected:**
- **Dispatch Stock Entry** auto-created and submitted: `Main - Inmed → Delivery In-Transit - Inmed`
- Dispatch Case status changes to `Packed`
- Delivery task auto-created for Delivery Team

**❌ Should NOT happen:**
- Error "Batch No required" or "Serial No required" — batch/serial requirements are temporarily disabled for now.

---

## Step 4 — Delivery task: Mark as Picked Up

**Login as:** `Delivery Driver`

1. Search for `Task` and open the **Task** list, filter: **Task Kind = Delivery**, **Status = Open**.
2. Find `Deliver: DC-YYYY-NNNNN`.
3. Set **Delivery Status** to `Picked Up` and Save.

**✅ Expected:**
- Dispatch Case status changes to `In Transit`
- No Stock Entry fires at this stage (items already in Delivery In-Transit)

---

## Step 5 — Delivery task: Mark as Delivered

**Login as:** `Delivery Driver`

1. Still on the Delivery task (or reopen it).
2. Attach a **delivery photo** (required).
3. Fill **Driver Handover Note** (who received at client location).
4. Set **Delivery Status** to `Delivered` and Save.

**✅ Expected:**
- **Delivery Stock Entry** auto-submitted: `Delivery In-Transit - Inmed → Client Location WH`
- Dispatch Case status changes to `Awaiting Return Pickup`
- **Return Call task** (Kind: `Return Call`) auto-created for the office/returns workflow

**❌ Should NOT happen (gate blocks — correct behavior):**
- Error "Delivery photo is required" — attach photo first
- Error "Handover Note is required" — fill the note first

---

## Step 6 — Return Call task: schedule the pickup

**Login as:** `Ops - Returns`

1. Search for `Task` and open the **Task** list, filter: **Task Kind = Return Call**, **Status = Open**.
2. Find `Return call: [Customer] (DC-YYYY-NNNNN)`.
3. Fill in:
   - **Return Pickup Driver:** select the driver who will collect the items
   - **Scheduled Return Date:** the agreed pickup date
4. If a blue **Save** button appears near the Status field, click **Save** first.
5. Click the red **Complete Task** button near the Status field.

**✅ Expected:**
- Dispatch Case status changes to `Return Pickup Scheduled`
- **Return Pickup task** (Kind: `Pickup Returns`) auto-created, assigned to the named driver, with due date = Scheduled Return Date

---

## Step 7 — Return Pickup task: Mark as Picked Up

**Login as:** `Delivery Driver` (the driver set in Step 6)

1. Search for `Task` and open the **Task** list, filter: **Task Kind = Pickup Returns**, **Status = Open**.
2. Find `Pickup Returns: DC-YYYY-NNNNN`.
3. Fill **Driver Handover Note** (who handed items at client location).
4. Set **Pickup Status** to `Picked Up` and Save.

**✅ Expected:**
- **Return Pickup Stock Entry** auto-submitted: `Client Location WH → Return Pickup In-Transit - Inmed`
- Dispatch Case status changes to `Return In Transit`

---

## Step 8 — Return Pickup task: Mark as Returned to Warehouse

**Login as:** `Delivery Driver`

1. Still on the Return Pickup task.
2. Attach a **drop-off photo** (required — photo of items handed in at the warehouse).
3. Set **Pickup Status** to `Returned to Warehouse` and Save.

**✅ Expected:**
- **Return Receive Stock Entry** auto-submitted: `Return Pickup In-Transit - Inmed → Returns - Inmed`
- Dispatch Case status changes to `Returns Received`
- **Returns Inspection task** auto-created for Returns Team

**❌ Should NOT happen:**
- Error "Drop-off photo is required" — attach photo first

---

## Step 9 — Complete the Returns Inspection task

**Login as:** `Ops - Returns`

1. Search for `Task` and open the **Task** list, filter: **Task Kind = Returns processing / verification**, **Status = Open**.
2. Find `Inspect returns: DC-YYYY-NNNNN`.
3. On the task form, scroll to the **Product Summary** section showing all dispatched items.

### Option A: Use checkboxes (quick method)

4. For each item in the Product Summary table:
   - **Check the box** if the item was fully returned by the customer
   - **Uncheck the box** if the item was NOT returned (used/consumed)
   - The "Returned" column will automatically update to match "Dispatched" when checked
   - The "Used" column shows what was consumed (Dispatched - Returned)
5. Click **Save** on the task.

### Option B: Use Dispatch Case inline editing (precise quantities)

4. Click on the linked **Dispatch Case** to open it.
5. In the **Case Items** table, click directly in the cells to edit:
   - **Returned Qty** — how many physically came back (can be 0)
   - **Lost / Damaged Qty** — any items missing or damaged
   - `used_qty` is auto-computed: `dispatched_qty - returned_qty - lost_damaged_qty`
6. Save the Dispatch Case.
7. Return to the task.

### Complete the task

8. If a blue **Save** button appears near the Status field, click **Save** first.
9. Click the red **Complete Task** button near the Status field.

**✅ Expected:**
- **Consumption Stock Entry** auto-submitted: `Client Location WH → Material Issue` for `used_qty` of each item
- Draft **Sales Invoice** auto-created for used quantities and prices
- Dispatch Case status changes to `Invoice Pending`
- **Restock task** auto-created for Returns Team (if any `returned_qty > 0`)
- **Invoice Preparation task** auto-created for Accounting Team

**❌ Should NOT happen:**
- Error "Used Qty cannot be negative for item X" — returned + lost/damaged exceeds dispatched; fix the quantities

**💡 Tip:** Use checkboxes for simple all-or-nothing returns. Use Dispatch Case inline editing when items were partially returned or damaged.

---

## Step 10 — Complete the Restock task *(runs in parallel with Step 11)*

**Login as:** `Ops - Returns`

1. Search for `Task` and open the **Task** list, filter: **Task Kind = Returns restocking**, **Status = Open**.
2. Find `Restock returns: DC-YYYY-NNNNN`.
3. Physically move items from `Returns - Inmed` shelf back to `Main - Inmed` shelf locations.
4. If a blue **Save** button appears near the Status field, click **Save** first.
5. Click the red **Complete Task** button near the Status field.

**✅ Expected:**
- **Restock Stock Entry** auto-submitted: `Returns - Inmed → Main - Inmed` for all items with `returned_qty > 0`

*This task runs in parallel with Invoice Preparation (Step 11). Neither waits for the other.*

---

## Step 11 — Complete the Invoice Preparation task

**Login as:** `Ops - Accounting`

1. Search for `Task` and open the **Task** list, filter: **Task Kind = Invoice preparation / create invoice**, **Status = Open**.
2. Find `Invoice: DC-YYYY-NNNNN`.
3. Open the linked draft **Sales Invoice**.
4. Verify:
   - Items and quantities match `used_qty` from Case Items
   - **Update Stock** is **unchecked** (stock moved by Consumption SE)
   - Prices and taxes are correct
5. Click **Submit** on the Sales Invoice.
6. Back on the task, if a blue **Save** button appears near the Status field, click **Save** first.
7. Click the red **Complete Task** button near the Status field.

**✅ Expected:**
- Sales Invoice submitted
- Dispatch Case status changes to `Invoiced`, then to `Payment Pending` (if outstanding > 0)
- **Debt Collection task** auto-created or updated for Finance Team
- If fully prepaid: Dispatch Case changes to `Closed`

**❌ Should NOT happen:**
- Update Stock = checked — uncheck before submitting

---

## Step 12 — Record payment on the Debt Collection task

**Login as:** `Ops - Finance`

1. Search for `Task` and open the **Task** list, filter: **Task Kind = Debt Collection**, **Status = Open**.
2. Find the task for your customer.
3. The task shows the **Open Invoices** table (all outstanding invoices for this customer across cases).
4. Fill in the **Record Payment** section:
   - **New Payment Amount:** amount received
   - **Payment Method:** Cash / Bank Transfer / Card
   - **Payment Reference:** transaction ID or receipt number
5. Save the task.

**✅ Expected after Save:**
- **Payment Entry** auto-created (Receive type), allocated FIFO across oldest invoices first
- **Distribute Payment task** auto-created for Finance Team (to handle physical payment actions)
- Outstanding balance on the task decreases

**On full payment (outstanding = 0):**
- Debt Collection task auto-completes
- Dispatch Case status changes to `Closed`

---

## Final state verification

Search for `Dispatch Case`, open `DC-YYYY-NNNNN`, and verify:

| Field | Expected value |
|---|---|
| Status | `Closed` |
| Dispatch Stock Entry | Submitted |
| Delivery Stock Entry | Submitted |
| Return Pickup Stock Entry | Submitted |
| Return Receive Stock Entry | Submitted |
| Consumption Stock Entry | Submitted |
| Restock Stock Entry | Submitted |
| Sales Invoice | Submitted |
| outstanding_amount | 0 |

Search for `Stock Ledger` and open the **Stock Ledger** report, then filter by the test item:
- `Main - Inmed`: net deduction = `used_qty` (dispatched minus returned)
- `Delivery In-Transit - Inmed`: net zero
- `Client Location WH`: net zero
- `Return Pickup In-Transit - Inmed`: net zero
- `Returns - Inmed`: credit then debit (returned then restocked), net zero

---

## Quick reference — task chain for this path

```
Order entry task (manual)
  -> Dispatch Case manually created/linked, then submitted before Order Entry is completed
        -> [Discount Approval task — only if discount > 0]
        -> Pack task (Inventory) — prepare products; barcode tracking temporarily disabled
              -> Delivery task (Driver) — Todo -> Picked Up -> Delivered
                    -> Return Call task (Office/Returns workflow) — schedule driver
                          -> Return Pickup task (Driver) — Todo -> Picked Up -> Returned to WH
                                -> Returns Inspection task (Returns)
                                      -> Restock task (Returns) — parallel
                                      -> Invoice Preparation task (Accounting)
                                            -> Debt Collection task (Finance)
                                                  -> Distribute Payment task (Finance)
```

---

## Common failure modes

| Symptom | Likely cause |
|---|---|
| Pack task not created after Order Entry completion | Linked Dispatch Case was not submitted first, or task completion script failed; check `Task-before-save-dispatch-gates` and `Task-after-save-dispatch-flow` in Server Scripts |
| "Accept / Start Task" button missing | Task client script not deployed; check `Task-Accept Start` |
| "Batch No required" or "Serial No required" on Pack task complete | Batch/serial requirements should be temporarily disabled; verify Item tracking flags are still disabled for now |
| Product Work Area not visible on Task | Optional/future barcode UI is not active or not deployed; not required for current packing completion |
| Scan does not work | Barcode workflow is optional/future while batch/serial tracking is temporarily disabled |
| FEFO warning blocks the scan | FEFO should be warning-only when barcode tracking is re-enabled; check `dispatch_case_packing_scan` script |
| Delivery SE not auto-submitted on Delivered | `Task-after-save-dispatch-flow` script error or disabled |
| "Delivery photo is required" | Attach photo before setting Delivered |
| Return Call task not created | Dispatch Case `return_expected` is unchecked — this is the no-return path |
| "Drop-off photo is required" | Attach photo before setting Returned to Warehouse |
| Returns Inspection task not created after Return Pickup | `Task-after-save-dispatch-flow` script; verify it is enabled |
| "Used Qty negative" on inspection complete | returned + lost/damaged > dispatched; fix Case Item quantities |
| Restock task not created | All items had `returned_qty = 0`; correct if items did come back |
| Invoice Preparation task not created | Returns Inspection task not completed correctly |
| Debt Collection task not created after invoice | Invoice outstanding = 0 (fully prepaid); or `Task-after-save-dispatch-flow` script issue |

---

## Key differences from manual workflow (v1)

**What changed:**
- ✅ **Accept / Start Task** button accepts the task for the current worker and disappears for that worker after acceptance
- ✅ **Blue Save button** appears near the Status field when there are unsaved changes
- ✅ **Complete Task** button is shown near the Status field, saves first, then completes the task
- ✅ **Order Entry completion requires a linked, submitted Dispatch Case**
- ✅ **Item search works by text match** using item code, item name, description, item group, or customer code
- ⚠️ **Barcode, batch, serial, expiry, and FEFO behavior are temporarily disabled operationally** and should be treated as future/optional until tracking is re-enabled

**What stayed the same:**
- All other steps (delivery, returns, invoicing, payment) remain unchanged
- Stock Entry automation triggers remain the same
- Task creation and state transitions are identical
