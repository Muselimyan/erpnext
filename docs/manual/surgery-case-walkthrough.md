# Dispatch Case — Surgery / Return Case Walkthrough

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
| 3 | Complete Pack task | `Ops - Inventory` |
| 4 | Delivery task — Picked Up | `Delivery Driver` |
| 5 | Delivery task — Delivered | `Delivery Driver` |
| 6 | Return Waiting task — schedule pickup | `Ops - Returns` |
| 7 | Return Pickup task — Picked Up | `Delivery Driver` |
| 8 | Return Pickup task — Returned to Warehouse | `Delivery Driver` |
| 9 | Returns Inspection task | `Ops - Returns` |
| 10 | Restock task *(parallel)* | `Ops - Returns` |
| 11 | Invoice Preparation task | `Ops - Accounting` |
| 12 | Debt Collection task | `Ops - Finance` |

---

## Step 1 — Create an Order entry task

**Login as:** `Ops - Order Accepting`

1. Open the **Task** list and click **New**.
2. Fill in:
   - **Task Kind:** `Order entry`
   - **Subject:** `Order: [Customer name] — [brief description, e.g. Surgery set Dr. Smith 15/06]`
   - **Customer:** select the test customer
   - **Description:** note the items, quantities, surgery date, and any special instructions
   - **Assigned To:** `order.creation.team@example.com` (Order Creation Team)
3. Click **Save**.

**✅ Expected:**
- Task saved with Status `Open`

---

## Step 2 — Create and submit the Dispatch Case

**Login as:** `Ops - Order Creating`

1. Open your Order entry task. Open a new tab: search for `Dispatch Case` and click **New**.
2. Fill in:
   - **Customer:** select the test customer
   - **Return Expected:** **checked** ← critical for this scenario
   - **Client Location Warehouse:** select the client's warehouse (e.g. `Dr. Smith WH - Inmed`)
   - **Surgery Date:** the surgery/delivery date
   - **Item Template (Collection Set):** select if applicable — click **Load from Template** to auto-fill Case Items
3. In the **Case Items** table, verify or add items:
   - **Item Code, Dispatched Qty, Unit Price** — fill for each item
   - **Discount %:** `0` for the no-discount scenario (see Step 2a if discount needed)
4. Click **Save**, then **Submit**.

**✅ Expected after Save:**
- Status = `Draft`

**✅ Expected after Submit:**
- Status = `Confirmed`
- Pack task auto-created for Inventory Team
- Case receives autoname `DC-YYYY-NNNNN`

5. Back on the Order entry task: link the **Dispatch Case** field → change Status to `Completed` → Save.

---

## Step 2a — Discount approval (only if Discount % > 0)

**Login as:** `Ops - Directors`

1. Task list → **Task Kind = Discount Approval**, Status = `Open` → open the task for your case.
2. Set **Approval Outcome** to `Approved`. Change Status to `Completed` → Save.

**✅ Expected:** Dispatch Case status → `Confirmed`, Pack task auto-created.

**On Rejection:** Dispatch Case stays `Draft`. A new `Order entry` task is auto-created for Order Creation Team. Order Creation person revises pricing on the Dispatch Case, saves again.

---

## Step 3 — Complete the Pack task

**Login as:** `Ops - Inventory`

1. Task list → **Task Kind = Pack / prepare items**, Status = `Open` → find `Pack: DC-YYYY-NNNNN — [Customer]`.
2. Open the linked Dispatch Case. In **Case Items**:
   - Fill `serial_no` for each serial-tracked item
   - Fill `batch_no` for each batch-tracked item (FEFO: select earliest-expiry batch)
   - Save the Dispatch Case.
3. Back on the task: Status → `Completed` → Save.

**✅ Expected:**
- **Dispatch Stock Entry** auto-created and submitted: `Main - Inmed → Delivery In-Transit - Inmed`
- Dispatch Case status → `Packed`
- Delivery task auto-created for Delivery Team

**❌ Should NOT happen:**
- Error "Serial No required" → fill `serial_no` on the Case Item row first
- Error "Batch No required" → fill `batch_no` first

---

## Step 4 — Delivery task: Mark as Picked Up

**Login as:** `Delivery Driver`

1. Task list → **Task Kind = Delivery**, Status = `Open` → find `Deliver: DC-YYYY-NNNNN`.
2. Set **Delivery Status** to `Picked Up` → Save.

**✅ Expected:**
- Dispatch Case status → `In Transit`
- No Stock Entry fires at this stage (items already in Delivery In-Transit)

---

## Step 5 — Delivery task: Mark as Delivered

**Login as:** `Delivery Driver`

1. Still on the Delivery task (or reopen it).
2. Attach a **delivery photo** (required).
3. Fill **Driver Handover Note** (who received at client location).
4. Set **Delivery Status** to `Delivered` → Save.

**✅ Expected:**
- **Delivery Stock Entry** auto-submitted: `Delivery In-Transit - Inmed → Client Location WH`
- Dispatch Case status → `Awaiting Return Pickup`
- **Return Waiting task** (Kind: `Pickup Returns`) auto-created for Returns Team

**❌ Should NOT happen (gate blocks — correct behavior):**
- Error "Delivery photo is required" → attach photo first
- Error "Handover Note is required" → fill the note first

---

## Step 6 — Return Waiting task: schedule the pickup

**Login as:** `Ops - Returns`

1. Task list → **Task Kind = Pickup Returns**, Status = `Open` → find `Wait for return call: DC-YYYY-NNNNN`.
2. Fill in:
   - **Return Pickup Driver:** select the driver who will collect the items
   - **Scheduled Return Date:** the agreed pickup date
3. Change Status to `Completed` → Save.

**✅ Expected:**
- Dispatch Case status → `Return Pickup Scheduled`
- **Return Pickup task** (Kind: `Pickup Returns`) auto-created, assigned to the named driver, with due date = Scheduled Return Date

---

## Step 7 — Return Pickup task: Mark as Picked Up

**Login as:** `Delivery Driver` (the driver set in Step 6)

1. Task list → **Task Kind = Pickup Returns**, Status = `Open` → find `Pickup Returns: DC-YYYY-NNNNN`.
2. Fill **Driver Handover Note** (who handed items at client location).
3. Set **Pickup Status** to `Picked Up` → Save.

**✅ Expected:**
- **Return Pickup Stock Entry** auto-submitted: `Client Location WH → Return Pickup In-Transit - Inmed`
- Dispatch Case status → `Return In Transit`

---

## Step 8 — Return Pickup task: Mark as Returned to Warehouse

**Login as:** `Delivery Driver`

1. Still on the Return Pickup task.
2. Attach a **drop-off photo** (required — photo of items handed in at the warehouse).
3. Set **Pickup Status** to `Returned to Warehouse` → Save.

**✅ Expected:**
- **Return Receive Stock Entry** auto-submitted: `Return Pickup In-Transit - Inmed → Returns - Inmed`
- Dispatch Case status → `Returns Received`
- **Returns Inspection task** auto-created for Returns Team

**❌ Should NOT happen:**
- Error "Drop-off photo is required" → attach photo first

---

## Step 9 — Complete the Returns Inspection task

**Login as:** `Ops - Returns`

1. Task list → **Task Kind = Returns processing / verification**, Status = `Open` → find `Inspect returns: DC-YYYY-NNNNN`.
2. Open the linked **Dispatch Case**. In **Case Items**, for each item:
   - Fill **Returned Qty** — how many physically came back (can be 0)
   - Fill **Lost / Damaged Qty** — any items missing or damaged
   - `used_qty` is auto-computed: `dispatched_qty - returned_qty - lost_damaged_qty`
3. Save the Dispatch Case.
4. Back on the task: Status → `Completed` → Save.

**✅ Expected:**
- **Consumption Stock Entry** auto-submitted: `Client Location WH → Material Issue` for `used_qty` of each item
- Draft **Sales Invoice** auto-created for used quantities and prices
- Dispatch Case status → `Invoice Pending`
- **Restock task** auto-created for Returns Team (if any `returned_qty > 0`)
- **Invoice Preparation task** auto-created for Accounting Team

**❌ Should NOT happen:**
- Error "Used Qty cannot be negative for item X" → returned + lost/damaged exceeds dispatched; fix the quantities

---

## Step 10 — Complete the Restock task *(runs in parallel with Step 11)*

**Login as:** `Ops - Returns`

1. Task list → **Task Kind = Returns restocking**, Status = `Open` → find `Restock returns: DC-YYYY-NNNNN`.
2. Physically move items from `Returns - Inmed` shelf back to `Main - Inmed` shelf locations.
3. Status → `Completed` → Save.

**✅ Expected:**
- **Restock Stock Entry** auto-submitted: `Returns - Inmed → Main - Inmed` for all items with `returned_qty > 0`

*This task runs in parallel with Invoice Preparation (Step 11). Neither waits for the other.*

---

## Step 11 — Complete the Invoice Preparation task

**Login as:** `Ops - Accounting`

1. Task list → **Task Kind = Invoice preparation / create invoice**, Status = `Open` → find `Invoice: DC-YYYY-NNNNN`.
2. Open the linked draft **Sales Invoice**.
3. Verify:
   - Items and quantities match `used_qty` from Case Items
   - **Update Stock** is **unchecked** (stock moved by Consumption SE)
   - Prices and taxes are correct
4. Click **Submit** on the Sales Invoice.
5. Back on the task: Status → `Completed` → Save.

**✅ Expected:**
- Sales Invoice submitted
- Dispatch Case status → `Invoiced` → `Payment Pending` (if outstanding > 0)
- **Debt Collection task** auto-created or updated for Finance Team
- If fully prepaid: Dispatch Case → `Closed`

**❌ Should NOT happen:**
- Update Stock = checked → uncheck before submitting

---

## Step 12 — Record payment on the Debt Collection task

**Login as:** `Ops - Finance`

1. Task list → **Task Kind = Debt Collection**, Status = `Open` → find the task for your customer.
2. The task shows the **Open Invoices** table (all outstanding invoices for this customer across cases).
3. Fill in the **Record Payment** section:
   - **New Payment Amount:** amount received
   - **Payment Method:** Cash / Bank Transfer / Card
   - **Payment Reference:** transaction ID or receipt number
4. Save the task.

**✅ Expected after Save:**
- **Payment Entry** auto-created (Receive type), allocated FIFO across oldest invoices first
- **Distribute Payment task** auto-created for Finance Team (to handle physical payment actions)
- Outstanding balance on the task decreases

**On full payment (outstanding = 0):**
- Debt Collection task auto-completes
- Dispatch Case status → `Closed`

---

## Final state verification

Open the Dispatch Case `DC-YYYY-NNNNN` and verify:

| Field | Expected value |
|---|---|
| Status | `Closed` |
| Dispatch Stock Entry | Submitted ✓ |
| Delivery Stock Entry | Submitted ✓ |
| Return Pickup Stock Entry | Submitted ✓ |
| Return Receive Stock Entry | Submitted ✓ |
| Consumption Stock Entry | Submitted ✓ |
| Restock Stock Entry | Submitted ✓ |
| Sales Invoice | Submitted ✓ |
| outstanding_amount | 0 |

Go to **Stock Ledger**, filter by the test item:
- `Main - Inmed`: net deduction = `used_qty` (dispatched minus returned) ✓
- `Delivery In-Transit - Inmed`: net zero ✓
- `Client Location WH`: net zero ✓
- `Return Pickup In-Transit - Inmed`: net zero ✓
- `Returns - Inmed`: credit then debit (returned → restocked), net zero ✓

---

## Quick reference — task chain for this path

```
Order entry task (manual)
  └─► Dispatch Case created & submitted
        └─► [Discount Approval task — only if discount > 0]
        └─► Pack task (Inventory)
              └─► Delivery task (Driver) — Todo → Picked Up → Delivered
                    └─► Return Waiting task (Returns) — schedule driver
                          └─► Return Pickup task (Driver) — Todo → Picked Up → Returned to WH
                                └─► Returns Inspection task (Returns)
                                      ├─► Restock task (Returns) ← parallel
                                      └─► Invoice Preparation task (Accounting)
                                            └─► Debt Collection task (Finance)
                                                  └─► Distribute Payment task (Finance)
```

---

## Common failure modes

| Symptom | Likely cause |
|---|---|
| Pack task not created after Submit | Dispatch Case submit script error; check `Dispatch-Case-before-submit` in Server Scripts |
| "Serial No required" on Pack task complete | `serial_no` not filled on Case Item row |
| Delivery SE not auto-submitted on Delivered | `Task-after-save-dispatch-flow` script error or disabled |
| "Delivery photo is required" | Attach photo before setting Delivered |
| Return Waiting task not created | Dispatch Case `return_expected` is unchecked — this is the no-return path |
| "Drop-off photo is required" | Attach photo before setting Returned to Warehouse |
| Returns Inspection task not created after Return Pickup | `Task-after-save-dispatch-flow` script; verify it is enabled |
| "Used Qty negative" on inspection complete | returned + lost/damaged > dispatched; fix Case Item quantities |
| Restock task not created | All items had `returned_qty = 0`; correct if items did come back |
| Invoice Preparation task not created | Returns Inspection task not completed correctly |
| Debt Collection task not created after invoice | Invoice outstanding = 0 (fully prepaid); or `Task-after-save-dispatch-flow` script issue |
