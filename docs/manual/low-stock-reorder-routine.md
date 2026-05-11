# Low-Stock Check and Reorder Routine

**Purpose:** Daily/weekly routine for the Purchasing team to check what is low in stock, decide what to order, and build Draft Purchase Orders ready for director approval. This is the operational bridge between ERPNext's reorder signals and the formal purchase flow (Doc 07).

**Estimated time:**
- Daily quick check: 10–20 minutes
- Weekly deep review: 30–90 minutes

**Use case:** The Purchasing team opens the reorder list, identifies which items are below threshold, groups them by supplier, builds one PO per supplier, and hands them to the Director for approval.

**Prerequisites:**
- Items have reorder thresholds set (Item → Reorder Levels table)
- Each item has exactly one supplier set in the Item Supplier table
- Purchase flow (Doc 07A) is live — PO approval scripts are in place

---

## Roles

| Step | Task | Role |
|---|---|---|
| 1–4 | Check reorder list, build Draft POs | `Ops - Purchasing` |
| 5 | Approve POs | `Ops - Directors` |
| 6 | Submit and send POs | `Ops - Purchasing` |

For the approval and submission steps, follow the **Purchase Walkthrough** (`purchase-walkthrough.md`) from Step 2 onward.

---

## Step 1 — Open the reorder list

**Login as:** `Ops - Purchasing`

1. Use the search bar (top of screen) to open **Reorder Report** or navigate to:
   - **Stock** → **Reports** → **Itemwise Recommended Reorder Level**
   - Alternatively: **Stock** → **Reports** → **Stock Projected Qty** (gives a broader view including open POs)

The primary tool for daily reorder decisions is **Itemwise Recommended Reorder Level** or the built-in **Stock → Reorder** tool. Use whichever your team has been configured to use.

**What each column means:**

| Column | Meaning |
|---|---|
| Item Code / Name | The item |
| Warehouse | The warehouse being evaluated (should be `Main - Inmed`) |
| Current Stock | How many units are physically in `Main - Inmed` right now |
| Reorder Level (Min) | The threshold below which reordering is triggered |
| Reorder Qty | The suggested quantity to order |
| Supplier | The assigned supplier for this item |

---

## Step 2 — Interpret what you see

**Items to act on today:**
- Any item where **Current Stock ≤ Reorder Level** — this is the reorder signal
- Items marked as needed for upcoming surgery cases (check with the Order team)

**Do not confuse company-owned stock elsewhere with available-to-sell stock:**
- Stock in `Delivery In-Transit - Inmed`, `Returns - Inmed`, `Return Pickup In-Transit - Inmed`, or any client location warehouse is **not available for new dispatch**
- Only `Main - Inmed` stock can be picked for new orders

**For import items (longer lead times):**
- Start the reorder process earlier — lead times can be 4–8 weeks
- Target coverage: 2–3 months of expected demand

**For fast-moving local items:**
- Target coverage: roughly 1 month of expected demand

**For expiry-tracked items:**
- Check whether existing stock expires soon
- If a large portion expires within the lead time window, treat the usable qty as lower than the current stock number

---

## Step 3 — Group items by supplier

Because each item has exactly one supplier, you can always group the reorder list by supplier to build one PO per supplier.

1. In the report, use the **Group By Supplier** filter or sort by the Supplier column.
2. For each supplier with items below threshold, note:
   - Which items need to be ordered
   - Suggested quantities (adjust based on your judgment and coverage targets)
   - Whether there is already an open PO for this supplier (if so, check if quantities can be added to it — only if it is still in Draft and not yet approved)

**Rule: one PO = one supplier.** Do not put items from different suppliers on the same PO.

---

## Step 4 — Build Draft Purchase Orders

For each supplier that needs a PO:

**Login as:** `Ops - Purchasing`

1. Open **Purchase Order** and click **New**.
2. Fill in the header:
   - **Supplier:** the supplier for this batch of items
   - **Schedule Date:** your best estimate of when goods will arrive (based on usual lead time)
   - **Purchase Reason:** `Reorder (Doc 08)`
   - **Requested By:** your own user name
   - **Currency:** defaults from the supplier record (confirm it is correct — usually `USD` or `EUR`)
3. In the **Items** table, add one row per item to order:
   - **Item Code:** select the item
   - **Qty:** the quantity you are ordering
     - For Min/Max items: order up to Max − Current Stock
     - For ROP items: order the standard reorder quantity
     - Adjust upward if you expect higher demand soon (e.g. upcoming surgeries)
   - **UOM:** confirm the buying unit (e.g. `Box`, `Nos`) — must match the packaging you receive
   - **Rate:** the latest known supplier price per unit
4. Attach supporting evidence if available — a recent price list, email confirmation, or proforma invoice.
5. Click **Save** (leave as Draft).

Repeat for each supplier.

**✅ Expected:**
- One Draft PO per supplier
- `Director Approval Status` = `Pending` on each

---

## Step 5 — Request director approval

Follow **Steps 2 and 3 of the Purchase Walkthrough** (`purchase-walkthrough.md`):
- Create a **Purchase Approval task** for each PO
- Assign to the appropriate Director
- Director reviews, sets Approval Outcome, and completes the task

---

## Step 6 — Submit and send after approval

Once a PO is approved:
- Follow **Step 5 of the Purchase Walkthrough** to submit and send the PO to the supplier

---

## Weekly deep review — additional checks

Once a week, go beyond the immediate reorder signals:

### Check slow movers drifting below threshold
Some items move slowly but eventually hit the threshold — catch them before they become urgent.

### Review items recently used in surgery cases
After a surgery case is closed and stock is consumed, check if the used items have dipped below threshold. The standard reorder report will show this automatically, but it is worth a deliberate scan after any large surgery case week.

### Check items currently at client locations
Items dispatched to a client but not yet returned (awaiting return, in transit) are company-owned but not usable. If you expect a high return rate for an item, factor that into your reorder decision — you may not need to buy as much.

Open **Stock Balance** report → filter by warehouse `Clients - Inmed` (group) to see what is out with clients.

### Review and adjust thresholds (purchasing lead only)
If an item's reorder threshold no longer reflects reality (demand has increased, lead times have changed):
1. Open the **Item** record
2. Go to the **Reorder Levels** tab
3. Adjust the Reorder Level (Min) and/or Reorder Qty values
4. Save

Threshold changes must be traceable — note the reason in the Item's Notes or in a comment.

---

## Reference — reorder quantity guidelines

| Item type | Suggested target stock coverage | Notes |
|---|---|---|
| Fast-moving consumables (local supplier) | ~1 month | Short lead times; reorder often in smaller quantities |
| Imported implants / instruments | 2–3 months | Long lead times (4–8 weeks); order ahead |
| Variant families (sized items) | Per variant, not total | Each size is a separate SKU; check each variant |
| Expiry-tracked items | Include expiry buffer | Do not over-buy items with short shelf life |

---

## Common issues

| Symptom | Likely cause |
|---|---|
| Item not appearing on reorder report | Reorder Level not set on the Item → open Item → Reorder Levels tab and add a row |
| Supplier column blank on reorder report | Item Supplier table is empty → open Item → Purchasing tab and add the supplier |
| Cannot add item to PO (supplier mismatch error) | Item's default supplier does not match the PO's Supplier field |
| PO shows supplier A but item belongs to supplier B | Each item must have exactly one supplier; fix the Item Supplier table |
| Stock shows in `Main - Inmed` but items cannot be picked | Check if there are pending Dispatch Cases consuming that stock — confirm with the Inventory team |
