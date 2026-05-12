# Stock Adjustment and Write-Off Walkthrough

**Purpose:** Guide for the Inventory team on how to correct stock quantities when the physical count does not match the system, and how to write off items that are damaged, expired, or otherwise unfit for sale. Covers the governance rule requiring director approval before significant write-offs are executed.

**Estimated time:** 15–30 minutes per adjustment

**Use case examples:**
- Physical stock count finds 5 units of an item but the system shows 8 → adjust down by 3
- System shows 0 units but 2 were found on the shelf → adjust up by 2
- A batch of expiry-tracked implants has passed its expiry date → write off from stock
- An instrument was dropped and damaged → remove from sellable inventory

---

## Roles

| Step | Task | Role |
|---|---|---|
| 1 | Identify the discrepancy | `Ops - Inventory` |
| 2 | Get write-off approved (for significant write-offs) | `Ops - Directors` |
| 3 | Execute the Stock Reconciliation or Material Issue | `Ops - Inventory` |

---

## Which document to use — decision guide

| Situation | Document to use |
|---|---|
| Physical count shows a different quantity than the system (up or down) | **Stock Reconciliation** |
| Deliberate removal: damaged, expired, internal use, destruction | **Stock Entry — Material Issue** |

**Rule: never use a Purchase Receipt or Sales Invoice to fix stock counts.** Always use the correct stock document.

---

## Part A — Stock Reconciliation (physical count mismatch)

Use this when a physical count reveals the system quantity is wrong — either too high or too low.

### Step 1 — Document the discrepancy before making changes

Before opening ERPNext, record on paper or in a message:
- Item Code and Name
- Batch No (if batch-tracked)
- Serial No (if serial-tracked)
- Current system quantity
- Physical count quantity
- Reason for the discrepancy (if known — e.g. "unrecorded breakage", "found in back shelf", "counting error")

This record is important for audit and for the Director review.

### Step 2 — Create the Stock Reconciliation

**Login as:** `Ops - Inventory`

1. Open **Stock Reconciliation** and click **New**.
2. Fill in:
   - **Purpose:** `Stock Reconciliation`
   - **Posting Date:** today's date
   - **Warehouse:** `Main - Inmed` (or whichever warehouse is being counted)
3. In the **Items** table, click **Add Row** for each item to adjust:
   - **Item Code:** select the item
   - **Batch No:** required for batch-tracked items — select the specific batch being counted
   - **Serial No:** required for serial-tracked items — enter the serial number
   - **Quantity:** enter the **physical count quantity** (not the adjustment amount — the system computes the difference)
   - The **Current Qty** column will auto-fill with the system quantity; the difference is the adjustment
4. Click **Save** first (do not submit yet).
5. Review the adjustments:
   - Positive difference → system quantity was understated → stock will increase
   - Negative difference → system quantity was overstated → stock will decrease

**For adjustments that decrease stock (negative differences) — go to Step 3 before submitting.**
**For adjustments that increase stock (found items) — you may proceed to submit after Director notification.**

### Step 3 — Director approval for stock decreases

Reducing stock (writing down inventory) has financial and operational consequences. Director visibility is required.

1. Open **Task** and click **New**.
2. Fill in:
   - **Subject:** `Write-off Approval — Stock Recon [date], Item: [Item Code]`
   - **Task Kind:** `Write-off Approval`
   - **Assigned To:** a Director user
   - **Description:** include the item, quantity being removed, batch (if applicable), and the reason
3. Click **Save**.
4. Wait for the Director to review and complete the task as `Approved` before submitting the Stock Reconciliation.

*For small, clearly explainable discrepancies (e.g. 1-unit rounding difference on non-tracked bulk consumables), use your judgment on whether to escalate. For any batch-tracked or serial-tracked items, always get Director approval.*

### Step 4 — Submit the Stock Reconciliation

**Login as:** `Ops - Inventory`

1. Open the saved Stock Reconciliation.
2. Confirm the Director has approved (check the Write-off Approval task is Completed).
3. Click **Submit**.

**✅ Expected:**
- Stock Ledger updated: quantities in the warehouse now match the physical count
- For batch-tracked items: the specific batch balance is adjusted
- Valuation Rate is recalculated based on the new quantity (for Moving Average items)

---

## Part B — Material Issue (deliberate write-off)

Use this when you are intentionally removing items from stock — expired goods, damaged instruments, items destroyed or lost.

### Step 1 — Get Director approval before writing off

Write-offs reduce inventory value and must be approved before execution.

**Login as:** `Ops - Inventory`

1. Open **Task** and click **New**.
2. Fill in:
   - **Subject:** `Write-off Approval — [reason, e.g. Expired Batch LOT-2024-00012, Item IMP-001]`
   - **Task Kind:** `Write-off Approval`
   - **Assigned To:** a Director user
   - **Description:** include:
     - Item Code and Name
     - Batch No / Serial No (if tracked)
     - Quantity to write off
     - Reason (expired / damaged / lost / other)
     - Current estimated value (optional but useful for the Director)
3. Click **Save**.

**Login as:** `Ops - Directors`

4. Open the task, review the details.
5. Set **Approval Outcome** to `Approved` (or `Rejected`).
6. Fill in **Approval Note** with the reason for the decision.
7. Set Status to `Completed` and Save.

### Step 2 — Create the Stock Entry (Material Issue)

**Login as:** `Ops - Inventory`

Only proceed after Director approval.

1. Open **Stock Entry** and click **New**.
2. Fill in:
   - **Stock Entry Type:** `Material Issue`
   - **Posting Date:** today's date
3. In the **Items** table, click **Add Row**:
   - **Item Code:** the item being written off
   - **Source Warehouse:** `Main - Inmed` (or `Returns - Inmed` if the item came back from a client and is being destroyed)
   - **Qty:** the quantity to write off
   - **Batch No:** required for batch-tracked items — select the specific batch
   - **Serial No:** required for serial-tracked items — enter the serial number(s)
4. In the **Reason / Remarks** field (or the document title): record the write-off reason explicitly — reference the Director approval task name
5. Click **Save**, then **Submit**.

**✅ Expected:**
- Stock decreases in the source warehouse by the written-off quantity
- Stock Ledger shows a Material Issue entry
- For batch-tracked items: that batch's balance decreases (to zero if fully written off)
- Cost of the write-off is posted to the configured expense account (usually a Loss/Write-off account)

---

## Handling specific write-off scenarios

### Expired batch — full batch write-off
1. Create Write-off Approval task (Step B1) — note batch and expiry date
2. After Director approval: Stock Entry → Material Issue → source = `Main - Inmed` → Batch = the expired batch → Qty = full remaining balance of that batch
3. Submit

### Damaged serial item — single unit
1. Create Write-off Approval task mentioning the serial number
2. After Director approval: Stock Entry → Material Issue → item + serial number → Qty = 1
3. Submit

### Items found in `Returns - Inmed` that cannot be restocked
1. Create Write-off Approval task (items returned by client but not fit for resale)
2. After Director approval: Stock Entry → Material Issue → source = `Returns - Inmed` → item + batch/serial → Qty as needed
3. Submit

---

## After the adjustment — verification

Open **Stock Ledger** (Stock → Stock Ledger) and filter by:
- Item Code: the adjusted item
- Warehouse: the warehouse where the adjustment was made
- Date: today

Confirm the adjustment entry appears with the correct quantity and the new balance matches what you physically counted or intended.

---

## Governance summary

| Action | Director approval required? |
|---|---|
| Stock increase (found items, count correction upward) | Notify Director; formal approval recommended for large quantities |
| Stock decrease (count correction downward) | **Yes — Write-off Approval task required** |
| Material Issue — expiry/damage | **Yes — Write-off Approval task required** |
| Material Issue for internal use (small consumables) | Use judgment; document the reason clearly |

**Rule: never submit a stock-decreasing document without a written reason attached or referenced in the document. If in doubt, get Director approval first.**

---

## Common issues

| Symptom | Likely cause |
|---|---|
| Batch No field missing on Stock Reconciliation row | The item has `Has Batch No` enabled — you must specify which batch is being reconciled |
| Qty on Stock Reconciliation not changing after submit | Check that the Posting Date is not in the future or in a locked period |
| Stock Entry submission blocked | Insufficient stock in source warehouse for the Material Issue qty — check current stock balance first |
| Stock Ledger shows the adjustment but stock report does not update | Report may be cached — refresh or rerun the report with today's date |
| Director cannot see the Write-off Approval task | Task Access Policy for `Write-off Approval` not granted to this Director user — check User Permissions with System Manager |
