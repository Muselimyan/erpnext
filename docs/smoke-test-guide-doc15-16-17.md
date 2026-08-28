# Smoke Test Guide — Docs 15, 16, 17

**Created:** 2026-06-01  
**Purpose:** Use this as the exact step-by-step guide for checking the remaining launch readiness after Doc 15E / Doc 16 / Doc 17A deployment.

## Important correction about names

The first Doc 15E deployment created some records with corrupted dash characters, visible as `â` in ERPNext. I corrected this by deploying ASCII-name versions.

Use these exact ERPNext names from now on:

| Type | Exact name to search in ERPNext |
|---|---|
| Report | `RPT - Item - Sort and Classify` |
| Report | `RPT - Item - Nomenclature and Prices` |
| Report | `RPT - Returns - Refund Queue` |
| Workspace | `Management - KPI Dashboard` |
| Workspace | `Dispatch - Task Queues` |
| Server Script | `doc15_norm_reorder_daily_notifications` |

Do not search for the old em-dash names such as `RPT — Item — Sort and Classify`. In this ERPNext site, use the normal hyphen names above.

---

## 1. What I already fixed

I corrected and redeployed Doc 15E with normal hyphen names.

Final deploy check confirmed these exist:

- `RPT - Item - Sort and Classify`
- `RPT - Item - Nomenclature and Prices`
- `RPT - Returns - Refund Queue`
- `doc15_norm_reorder_daily_notifications`
- `Management - KPI Dashboard`
- `Dispatch - Task Queues`

The older corrupted records may still exist, for example names containing `â`. Ignore them for now. They are not the names you should use for testing.

---

## 2. First check: Doc 15E reports and workspaces

### 2.1 Check Item Sort report

1. In ERPNext search bar, search exactly:
   - `RPT - Item - Sort and Classify`
2. Open the report.
3. Set filters if needed:
   - `Disabled` = `0`
   - `Sort By` = `Qty Ascending`
4. Click **Refresh**.
5. Pass condition:
   - Report opens without permission error.
   - Report shows item rows.
   - Columns include item code/name/group, total qty, main warehouse qty, selling price, buying price.

If buying price is `0`, that is not a software bug if `Standard Buying` prices are not populated yet.

### 2.2 Check Nomenclature and Prices report

1. In ERPNext search bar, search exactly:
   - `RPT - Item - Nomenclature and Prices`
2. Open the report.
3. Set `Disabled` = `0`.
4. Click **Refresh**.
5. Pass condition:
   - Report opens.
   - It shows item identity, group, brand, UOM, tracking flags, selling price, buying price, HS code, import tax rate.

Expected possible gaps:

- `standard_buying_price` can be `0` until Standard Buying prices are added.
- `hs_code` can be empty until HS codes are populated.
- `import_tax_rate` can be empty/0 until import tax rates are populated.

### 2.3 Check Return/Refund Queue report

1. In ERPNext search bar, search exactly:
   - `RPT - Returns - Refund Queue`
2. Open the report.
3. Click **Refresh**.
4. Pass condition:
   - Report opens without SQL or permission error.
   - It may show no rows if there are no submitted return Sales Invoices / credit notes yet. Empty is OK.

### 2.4 Check Management workspace

1. In ERPNext search bar, search exactly:
   - `Management - KPI Dashboard`
2. Open the workspace.
3. Pass condition:
   - Workspace opens.
   - It contains links to the Doc 15E reports.

Note: I removed KPI chart links from this new workspace because the older KPI records also used corrupted dash names. This workspace is now safe and self-contained.

### 2.5 Check Dispatch workspace

1. In ERPNext search bar, search exactly:
   - `Dispatch - Task Queues`
2. Open the workspace.
3. Click each shortcut:
   - `VIEW: Pack Tasks`
   - `VIEW: Delivery Tasks`
   - `VIEW: Return Pickup Tasks`
   - `VIEW: Returns Inspection Tasks`
   - `VIEW: Restock Tasks`
   - `VIEW: Invoice Tasks`
   - `VIEW: Debt Collection Tasks`
   - `VIEW: Payment Received Tasks`
   - `VIEW: Distribute Payment Tasks`
   - `VIEW: All Dispatch Cases`
   - `Urgent Tasks`
   - `Overdue Tasks`
4. Pass condition:
   - Each shortcut opens the expected `Task` list or `Dispatch Case` list.
   - Empty lists are OK if there are no test tasks yet.

---

## 3. Dispatch Case smoke test — no return expected

Purpose: verify standard sale / delivery flow.

### Before starting

Use a controlled test customer and controlled test item. Avoid important real stock if possible.

Check these screens are searchable first:

- `Task`
- `Dispatch Case`
- `Stock Entry`
- `Sales Invoice`
- `Payment Entry`
- `Dispatch - Task Queues`

### Steps

1. Search for `Dispatch Case` and open the **Dispatch Case** list.
2. Create a new `Dispatch Case`.
3. Set required header fields.
4. Set `return_expected` = `No`.
5. Add one item row.
6. Important: leave `Unit Price` empty if you want to confirm the new rule.
7. Save.
8. Submit.

Pass condition after submit:

- Submit succeeds even if `Unit Price` is empty.
- Case status should become confirmed / active according to the workflow.
- A packing task should be created.

### Pack step

1. Open `Dispatch - Task Queues`.
2. Click `VIEW: Pack Tasks`.
3. Open the relevant pack task.
4. Complete packing according to the task instructions.
5. If the item is batch/expiry tracked, fill batch/expiry details where required.

Pass condition:

- Pack task completes.
- Incorrect missing batch/serial data should be blocked for tracked items.
- Stock movement should be created/submitted by automation if this step is configured for the selected item/case.

### Delivery step

1. Open `Dispatch - Task Queues`.
2. Click `VIEW: Delivery Tasks`.
3. Open the relevant delivery task.
4. Try completing delivery without the required delivery proof fields.

Pass condition:

- If handover note is required, ERPNext blocks completion until filled. (Delivery photo is not required; see Doc 18.)

Then fill required fields and complete delivery.

Pass condition:

- Delivery task completes.
- Case moves to invoice/accounting stage.

### Invoice / debt step

1. Open `Dispatch - Task Queues`.
2. Click `VIEW: Invoice Tasks`.
3. Open the invoice task.
4. Complete invoice creation.
5. Then check `VIEW: Debt Collection Tasks` if payment is not fully settled.

Pass condition:

- Sales Invoice is created correctly.
- Debt/payment task appears if amount remains outstanding.
- Case can eventually close when paid/settled.

---

## 4. Dispatch Case smoke test — return expected

Purpose: verify surgery/loan/return workflow.

### Before starting

Search first:

- `Dispatch Case`
- `Task`
- `Stock Entry`
- `Sales Invoice`
- `Dispatch - Task Queues`

### Steps

1. Search for `Dispatch Case` and open the **Dispatch Case** list.
2. Create a new `Dispatch Case`.
3. Set `return_expected` = `Yes`.
4. Add test item rows.
5. Save and Submit.

Pass condition:

- Submit succeeds.
- Pack task is created.

### Pack and deliver

1. Open `Dispatch - Task Queues`.
2. Complete `VIEW: Pack Tasks`.
3. Complete `VIEW: Delivery Tasks`.

Pass condition:

- Items move through delivery flow.
- Case reaches waiting-for-return / return expected state.

### Return pickup

1. Open `Dispatch - Task Queues`.
2. Click `VIEW: Return Pickup Tasks`.
3. Open the return pickup task.
4. Try to complete without required return/drop-off photo.

Pass condition:

- ERPNext blocks completion if required photo/proof is missing.

Then attach required proof and complete.

### Returns inspection and restock

1. Open `VIEW: Returns Inspection Tasks`.
2. Enter returned/used/lost/damaged quantities.
3. Complete returns inspection.
4. Open `VIEW: Restock Tasks` if created.
5. Complete restock.

Pass condition:

- `dispatched qty = used qty + returned qty + lost/damaged qty` reconciliation is respected.
- Invoice should be based on used/lost/damaged business rule, not blindly on all dispatched quantity.

### Invoice and close

1. Open `VIEW: Invoice Tasks`.
2. Create/confirm invoice.
3. Open `VIEW: Debt Collection Tasks` if unpaid.
4. Record payment if testing full closure.

Pass condition:

- Case can reach closed state after return, invoice, and payment/debt process.

---

## 5. Doc 17A purchase costing smoke test

Purpose: verify Purchase Receipt → Landed Cost Voucher → Purchase Invoice with import duty.

### Before starting

Search these exact ERPNext names:

- `Item`
- `Item Price`
- `Purchase Order`
- `Purchase Receipt`
- `Landed Cost Voucher`
- `Purchase Invoice`
- `Stock Ledger`

### Prepare one test item

1. Search for `Item` and open the **Item** list.
2. Open one controlled test item.
3. Confirm fields exist:
   - `HS Code`
   - `Import Tax Rate (%)`
4. Set test values, for example:
   - `HS Code` = `9021.10`
   - `Import Tax Rate (%)` = `12`
5. Save.

### Check Standard Buying price

1. Search for `Item Price` and open the **Item Price** list.
2. Check whether the test item has a price in price list `Standard Buying`.
3. If not, create one test `Item Price` for this item.

Without Standard Buying prices, profit reports and some cost validations may show 0 or incomplete values.

### Purchase flow

1. Search for `Purchase Order` and create a test Purchase Order.
2. Use the test item.
3. Save and follow approval flow if approval blocks submit.
4. Create `Purchase Receipt` from the Purchase Order.
5. Submit the Purchase Receipt.

Pass condition:

- Purchase Receipt submits into `Main - Inmed`.
- If item is batch/expiry tracked, missing batch/expiry should be blocked.

### Landed Cost Voucher

1. Search for `Landed Cost Voucher`.
2. Create a new Landed Cost Voucher.
3. Add the submitted Purchase Receipt.
4. Click **Get Items from Purchase Receipts**.
5. Click **Pre-fill Import Duty**.

Pass condition:

- An import duty row appears in charges.
- Amount should approximately equal item value × import tax rate.

Example:

- Item value = 100,000 AMD
- Import tax rate = 12%
- Expected import duty = 12,000 AMD

Submit the Landed Cost Voucher.

### Verify valuation

1. Search for `Stock Ledger`.
2. Filter by the test item and posting date.
3. Check valuation entries.
4. Search for `Item`, open the test item, and check valuation rate if visible.

Pass condition:

- Landed cost affects valuation.

### Purchase Invoice

1. Search for `Purchase Invoice`.
2. Create Purchase Invoice from the Purchase Receipt / Purchase Order.
3. Confirm `Update Stock` is not enabled.
4. Submit.

Pass condition:

- Purchase Invoice submits.
- If `Update Stock` is enabled, ERPNext should block it.

---

## 6. What remains after these tests

### If all smoke tests pass

You are technically ready for first controlled real transaction, except business decisions/master data below.

### Master data still remaining

These are business/operational tasks, not missing software:

- Populate `Standard Buying` prices if you want profit/margin reports.
- Populate `HS Code` on items if you want complete customs/costing records.
- Populate `Import Tax Rate (%)` on items if you want LCV import duty pre-fill to work broadly.
- Set reorder levels and reorder quantities for items where purchasing wants automatic low-stock signals.
- Decide what to do with example/test users before final go-live.

### If something fails

Record the issue like this:

| Field | Fill this |
|---|---|
| Test section | Example: `Dispatch Case no-return` |
| ERPNext screen | Example: `Dispatch Case` |
| User logged in | Email/username |
| Exact action | Example: Submit Dispatch Case |
| Expected result | Example: Pack task created |
| Actual result | Copy error or describe behavior |
| Screenshot | Attach if possible |

Send that to Cascade/me later and I can debug the exact issue.

---

## 7. Final short checklist

Before first real transaction, confirm:

- [ ] `RPT - Item - Sort and Classify` opens.
- [ ] `RPT - Item - Nomenclature and Prices` opens.
- [ ] `RPT - Returns - Refund Queue` opens.
- [ ] `Management - KPI Dashboard` opens.
- [ ] `Dispatch - Task Queues` opens.
- [ ] Dispatch Case no-return smoke test passed.
- [ ] Dispatch Case return-expected smoke test passed.
- [ ] Purchase Receipt → Landed Cost Voucher → Purchase Invoice smoke test passed.
- [ ] At least one test user from each operational role can open the screens they need.
- [ ] Any failures are recorded with exact error text/screenshots.
