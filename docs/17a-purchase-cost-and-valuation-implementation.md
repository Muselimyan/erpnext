# Doc 17A — Purchase Flow with Costing and Valuation (Implementation)

## 1. Purpose

Step-by-step ERPNext setup guide for the operational rules defined in **Doc 17 — Purchase Flow with Costing and Valuation**.

This guide covers:
- Verifying company-level valuation settings
- Adding `hs_code` and `import_tax_rate` custom fields to Item
- Operating procedure for Purchase Receipt with batch/serial assignment
- Operating procedure for Landed Cost Voucher (LCV) with import duty pre-fill
- Client script to auto-populate import duty on LCV from Item fields
- Operating procedure for Purchase Invoice

---

## 2. Current Production State (Snapshot: 2026-05-11)

**Legend: ✅ EXISTS — ⚠️ NEEDS UPDATE — ❌ MISSING**

### 2.1 Company / Global Settings

| Setting | Expected | Prod State | Status |
|---|---|---|---|
| Valuation Method | FIFO | FIFO | ✅ EXISTS |
| Perpetual Inventory | Enabled | Enabled | ✅ EXISTS |
| Default Currency | AMD | AMD | ✅ EXISTS |

### 2.2 Price Lists

| Price List | Currency | Buying | Selling | Status |
|---|---|---|---|---|
| Standard Buying | AMD | Yes | No | ✅ EXISTS |
| Standard Selling | AMD | No | Yes | ✅ EXISTS |
| Item Prices populated | — | — | 0 records in Standard Buying | ❌ MISSING (operational) |

### 2.3 Custom Fields

| DocType | Fieldname | Label | Status |
|---|---|---|---|
| Item | `hs_code` | HS Code | ✅ DEPLOYED 2026-05-11 |
| Item | `import_tax_rate` | Import Tax Rate (%) | ✅ DEPLOYED 2026-05-11 |
| Purchase Receipt Item | `custom_expiry_date` | Expiry Date | ✅ EXISTS |

### 2.4 Server Scripts (purchase-related)

| Script name | Trigger | Purpose | Status |
|---|---|---|---|
| `Purchase Order-before-submit-director-approval` | PO → Before Submit | Blocks submit without `Approved` director status | ✅ DEPLOYED 2026-05-11 |
| `Purchase Order-before-save-clear-approval` | PO → Before Save | Resets approval if PO is edited after approval | ✅ DEPLOYED 2026-05-11 |
| `Purchase Order-validate-one-supplier` | PO → Before Save | Prevents mixing suppliers on one PO | ✅ DEPLOYED 2026-05-11 |
| `Purchase Receipt-before-submit-main-inmed-expiry` | PR → Before Submit | Enforces Main warehouse; enforces batch+expiry for expiry-tracked items | ✅ DEPLOYED 2026-05-11 |
| `Purchase Invoice-before-submit-no-update-stock` | PI → Before Submit | Blocks PI from updating stock (stock must come from PR only) | ✅ DEPLOYED 2026-05-11 |
| `Task-purchase-approval-writeback` | Task → Before Save | Writes approval outcome back to PO when Director completes Purchase Approval task | ✅ DEPLOYED 2026-05-11 |
| LCV client script (import duty pre-fill) | LCV → Form | Pre-fills import duty charge from Item `import_tax_rate` | ✅ DEPLOYED 2026-05-11 |

### 2.5 Client Scripts

| Script name | DocType | Purpose | Status |
|---|---|---|---|
| GS1 Barcode Parser | Purchase Receipt | Scans GS1 barcodes on receiving | ✅ EXISTS |
| LCV import duty filler | Landed Cost Voucher | Pre-fills import tax charge | ✅ DEPLOYED 2026-05-11 |

### 2.6 Item Tracking State (246 items as of snapshot)

| Tracking type | Count | Notes |
|---|---|---|
| Batch-tracked | 2 | Both are also expiry-tracked |
| Serial-tracked | 0 | No serial items exist yet |
| No tracking (Moving Average fallback) | 244 | Bulk screws, implants, consumables |

---

## 3. Prerequisites

Before performing the steps below, confirm:

- Doc 07A is done — PO approval flow is live.
- Doc 06A is done — Item catalog exists.
- You are logged in as `System Manager` or `Administrator`.

---

## 4. Step 1 — Verify Company Valuation Settings

This is already correct in prod. Verify to confirm nothing has changed.

1. Open **Stock Settings** → confirm `Valuation Method = FIFO`.
2. Open **Company** → `InMED` → confirm `Valuation Method = FIFO` and `Enable Perpetual Inventory = checked`.

No changes required. ✅

---

## 5. Step 2 — Add Custom Fields to Item

Two fields must be added to the **Item** DocType for import tax tracking.

### 5.1 `hs_code` — HS Code

| Property | Value |
|---|---|
| DocType | Item |
| Label | HS Code |
| Fieldname | `hs_code` |
| Field Type | Data |
| Insert After | `brand` (or any visible field in the Purchasing tab) |
| Mandatory | No |
| Read Only | No |

Steps:
1. Open **Customize Form** → select DocType: `Item`.
2. Click **Add Row** in the fields table.
3. Set properties as above.
4. Click **Update**.

### 5.2 `import_tax_rate` — Import Tax Rate

| Property | Value |
|---|---|
| DocType | Item |
| Label | Import Tax Rate (%) |
| Fieldname | `import_tax_rate` |
| Field Type | Float |
| Insert After | `hs_code` |
| Mandatory | No |
| Read Only | No |
| Description | Fixed import tax rate for this item's HS code. Used to pre-fill LCV import duty. |

Steps:
1. Open **Customize Form** → select DocType: `Item`.
2. Click **Add Row** in the fields table.
3. Set properties as above.
4. Click **Update**.

**After creation:** populate `hs_code` and `import_tax_rate` on all imported items as master data maintenance.

---

## 6. Step 3 — LCV Client Script (Import Duty Pre-fill)

This client script fires when a Landed Cost Voucher is opened or when purchase receipts are added to it. It calculates the expected import duty from each item's `import_tax_rate` and inserts it as a pre-filled charge row.

The user confirms or overrides the amount before submitting.

### 6.1 Create the Client Script

1. Open **Client Script** → New.
2. Set:
   - **Name:** `LCV-import-duty-prefill`
   - **DocType:** `Landed Cost Voucher`
   - **View:** Form
   - **Enabled:** Yes

3. Paste the following script:

```javascript
frappe.ui.form.on('Landed Cost Voucher', {
    refresh: function(frm) {
        if (frm.doc.docstatus === 0) {
            frm.add_custom_button(__('Pre-fill Import Duty'), function() {
                prefill_import_duty(frm);
            });
        }
    }
});

function prefill_import_duty(frm) {
    if (!frm.doc.purchase_receipts || frm.doc.purchase_receipts.length === 0) {
        frappe.msgprint(__('Add at least one Purchase Receipt first.'));
        return;
    }

    // Collect all item_codes from the items table (populated after adding receipts)
    let items = frm.doc.items || [];
    if (items.length === 0) {
        frappe.msgprint(__('No items loaded. Save the LCV after adding receipts, then try again.'));
        return;
    }

    // Fetch import_tax_rate for each unique item
    let item_codes = [...new Set(items.map(r => r.item_code).filter(Boolean))];
    frappe.call({
        method: 'frappe.client.get_list',
        args: {
            doctype: 'Item',
            filters: [['item_code', 'in', item_codes]],
            fields: ['item_code', 'import_tax_rate'],
            limit_page_length: 500
        },
        callback: function(r) {
            if (!r.message) return;

            let rate_map = {};
            r.message.forEach(function(row) {
                rate_map[row.item_code] = flt(row.import_tax_rate) || 0;
            });

            // Calculate total import duty = sum(item_amount * import_tax_rate / 100)
            let total_duty = 0;
            items.forEach(function(row) {
                let rate = rate_map[row.item_code] || 0;
                total_duty += flt(row.amount) * rate / 100;
            });

            total_duty = Math.round(total_duty * 100) / 100;

            if (total_duty <= 0) {
                frappe.msgprint(__('No import tax rates found on items. Set import_tax_rate on Item records first.'));
                return;
            }

            // Remove existing Import Duty row if present, then add new one
            let taxes = frm.doc.taxes || [];
            let existing_idx = taxes.findIndex(r => r.description === 'Import Duty');
            if (existing_idx >= 0) {
                frm.get_field('taxes').grid.grid_rows[existing_idx].remove();
            }

            let row = frm.add_child('taxes');
            row.description = 'Import Duty';
            row.amount = total_duty;
            row.expense_account = '';  // Accounting team fills this in
            frm.refresh_field('taxes');

            frappe.msgprint(
                __('Import Duty pre-filled: {0} AMD. Please set the Expense Account and confirm the amount.', [total_duty])
            );
        }
    });
}
```

4. Click **Save**.

### 6.2 How It Works in Practice

When Accounting opens a new Landed Cost Voucher:
1. Add the Purchase Receipt(s) → click **Get Items from Purchase Receipts**.
2. Click the **Pre-fill Import Duty** button (top of form).
3. The script calculates `sum(item_amount × import_tax_rate / 100)` across all items.
4. An `Import Duty` row is inserted in the Taxes/Charges table with the pre-calculated amount.
5. User sets the **Expense Account** on that row (e.g., `Import Duty - Inmed`).
6. User confirms or overrides the amount if the actual duty differs.
7. Add other charges (freight, etc.) manually.
8. Submit.

---

## 7. Step 4 — Batch Naming Series (Optional)

If you want system-generated batch numbers (for items without supplier lot codes):

1. Open **Stock Settings**.
2. Set **Batch Identification** = `Based on Item**.
3. Or define a naming series in **Naming Series** DocType: prefix `LOT-.YYYY.-#####`.

For items where the supplier provides a lot number printed on packaging, leave batch naming as manual and enter the supplier's lot code at receiving.

No mandatory setup required — this is an operational preference per item. ✅

---

## 8. Operating Procedure — Purchase Receipt

This is the step where items physically enter `Main - Inmed`.

### 8.1 Who: `Ops - Inventory` (Purchasing team)

### 8.2 Steps

1. Open **Purchase Receipt** → New (or create from the Purchase Order via **Create → Purchase Receipt**).
2. Verify:
   - **Supplier** matches the PO.
   - **Posting Date** = physical arrival date.
   - All item rows are in warehouse `Main - Inmed`.
3. For each item:
   - Enter **Received Qty** (what physically arrived — may differ from ordered qty).
   - For **batch-tracked items** (`has_batch_no = Yes`):
     - Enter **Batch No** = supplier's lot code, or create a new batch using the naming series.
     - Ensure the batch record has **Expiry Date** set (enforced by server script on submit).
   - For **non-tracked items** (the majority, 244 items): no extra fields needed.
4. Click **Submit**.

**Gate enforced by `Purchase Receipt-before-submit-main-inmed-expiry`:**
- Blocks submit if any row is not in `Main - Inmed`.
- Blocks submit if a batch-tracked+expiry-tracked item has no Batch No or batch has no Expiry Date.

---

## 9. Operating Procedure — Landed Cost Voucher

This is the step where transport, import duty, and other charges are added to the shipment cost.

### 9.1 Who: `Ops - Accounting`

### 9.2 When to Create

Create an LCV for **every import purchase** that has charges beyond the supplier price.  
Skip LCV only for local purchases (Armenian supplier, no freight, no import duties) with confirmed zero additional charges.

### 9.3 Steps

1. Open **Landed Cost Voucher** → New.
2. **Purchase Receipts table**: click **Add Row** → select the Purchase Receipt(s) for this shipment.
3. Click **Get Items from Purchase Receipts** — the Items table populates with all received lines.
4. **Charges table**: click **Pre-fill Import Duty** button.
   - The script calculates import duty from each item's `import_tax_rate` and pre-fills one row.
   - Set the **Expense Account** for that row.
   - Confirm or override the amount.
5. Add additional charge rows manually for each other cost type:

   | Charge | Distribution | Currency | Notes |
   |---|---|---|---|
   | Freight / Transportation | By Qty or By Amount | USD, EUR, or AMD | Enter exchange rate for non-AMD |
   | Customs Clearance / Brokerage | By Amount | AMD | Usually AMD |
   | Other (port fees, etc.) | By Amount | Any | Add as needed |

6. For each non-AMD charge row: set **Currency** and **Exchange Rate** (rate as of today).
7. Review the **Items table** — ERPNext shows each item's allocated charge share.
8. Click **Submit**.

After submit, ERPNext recalculates the **Valuation Rate** on each batch/item in the linked receipt. The stock ledger records adjustment entries.

### 9.4 Distribution Method Choice

| Use "By Qty" when | Use "By Amount" when |
|---|---|
| Freight is charged per box/unit regardless of item value | Charges are proportional to value (e.g., ad valorem duty) |
| Items in the shipment have similar value | Items have very different unit prices |

---

## 10. Operating Procedure — Purchase Invoice

### 10.1 Who: `Ops - Accounting`

### 10.2 Steps

1. Open **Purchase Invoice** → New (or create from Purchase Receipt via **Create → Purchase Invoice**).
2. Verify:
   - Items and quantities match the supplier's invoice.
   - **Update Stock** is **unchecked** (enforced by server script — will block submit if checked).
3. Set **Bill No** and **Bill Date** from the supplier's invoice.
4. Submit.

**Note:** The Purchase Invoice covers only what the supplier billed. Charges from separate vendors (freight forwarder, customs agent) should be recorded as separate Purchase Invoices against those vendors — they are separate from the supplier PI.

---

## 11. Deploy Script

The two custom fields (§5) should be added via `doc17a-deploy.ps1` for idempotent deployment.

**Status: ✅ Written and deployed — `deploy/doc17a-deploy.ps1`.**

---

## 12. Smoke Test

After completing all steps above:

1. **Verify Item fields exist:**
   - Open any Item → confirm `HS Code` and `Import Tax Rate (%)` fields are visible.
   - Set `hs_code = 9021.10` and `import_tax_rate = 12` on one test item. Save.

2. **Verify Purchase Receipt gate still works:**
   - Create a PR for a batch+expiry item.
   - Try to submit without batch or expiry → should get error.
   - Fill in batch with expiry date → submit succeeds.

3. **Verify LCV pre-fill:**
   - Create a new LCV.
   - Add the Purchase Receipt from step 2.
   - Click **Get Items from Purchase Receipts**.
   - Click **Pre-fill Import Duty**.
   - Confirm: one `Import Duty` row appears in Charges with amount = `(line value × 12%)`.

4. **Verify Valuation Rate update:**
   - After submitting the LCV, open **Stock Ledger** → filter by test item and date.
   - Confirm a valuation adjustment entry appears.
   - Open the Item → check **Valuation Rate** reflects the landed cost (not just supplier price).

5. **Verify Purchase Invoice gate:**
   - Create a PI from the PR.
   - Try to submit with `Update Stock = checked` → should be blocked.
   - Uncheck → submit succeeds.

---

## 13. Summary of Remaining Work

| # | Item | Type | Status |
|---|---|---|---|
| 1 | `Item-hs_code` custom field | Custom Field | ✅ Deployed 2026-05-11 |
| 2 | `Item-import_tax_rate` custom field | Custom Field | ✅ Deployed 2026-05-11 |
| 3 | `LCV-import-duty-prefill` client script | Client Script | ✅ Deployed 2026-05-11 |
| 4 | Populate `hs_code` + `import_tax_rate` on imported items | Master Data | ❌ Operational task (do after item catalog cleanup) |
| 5 | `doc17a-deploy.ps1` deploy script | Deploy Script | ✅ Written and deployed |
| 6 | Standard Buying price list — populate item prices | Master Data | ❌ Operational task |
| — | Valuation method = FIFO | Company setting | ✅ Already done |
| — | Purchase Receipt expiry gate | Server Script | ✅ Already done |
| — | Purchase Invoice no-update-stock gate | Server Script | ✅ Already done |
| — | PO director approval gate | Server Script | ✅ Already done |
| — | GS1 barcode scanner on Purchase Receipt | Client Script | ✅ Already done |
| — | Standard Buying / Standard Selling price lists | Price Lists | ✅ Already done |
