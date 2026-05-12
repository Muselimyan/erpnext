# New Item Setup Walkthrough

**Purpose:** Step-by-step guide for adding a new product to the ERPNext item catalog so it is ready for purchasing, receiving, and dispatch. Run this whenever a new product line is introduced or a new variant family is needed.

**Estimated time:** 15–45 minutes depending on whether variants are needed

**Use case:** InMED sources a new implant, instrument, or consumable. Before it can be purchased or dispatched, it must exist in the system with the correct tracking settings, UOM, supplier, and price.

**Prerequisites:**
- The Item Group for this product category already exists
- The Supplier record already exists
- You know whether the item is sold in the same unit it is received in, or if boxes must be broken into singles

---

## Roles

| Task | Role |
|---|---|
| All setup steps | `Ops - Inventory` or `System Manager` |
| Setting selling price | `Ops - Accounting` or `Ops - Inventory` |

---

## Decision before you start

Answer these questions before creating the item:

**1. Does a variant family (template) already exist for this product type?**
- If yes (e.g. a bone screw family already exists) → create a new variant from the template (go to Step 4)
- If no → create a standalone item or a new template (Steps 1–3)

**2. Is this product tracked by batch/expiry, serial number, or nothing?**

| Product type | Tracking |
|---|---|
| Implants, biologics, consumables with expiry | Batch + Expiry (`Has Batch No` + `Has Expiry Date`) |
| Instruments, tools, high-value equipment | Serial (`Has Serial No`) |
| Bulk screws, simple disposables | None (moving average valuation) |

**3. Is it purchased in boxes but counted/sold as singles?**
- If yes and it is batch/expiry tracked → use the single-Item + UOM conversion model (Pack Breaking Policy = `Pack-breakable`)
- If no → Pack Breaking Policy = `Never break packs`

---

## Step 1 — Create the Item

**Login as:** `Ops - Inventory`

1. Open **Item** and click **New**.
2. Fill in the core fields:
   - **Item Code:** use the internal SKU (must be stable — do not change after it is used in transactions)
   - **Item Name:** follow the naming convention: `[Brand] — [Product Name] — [Key Spec]`
     - Example: `Stryker — Bone Screw — 3.5mm x 20mm`
   - **Item Group:** select the correct category (e.g. `Implants`, `Instruments / Tools`, `Consumables / Disposables`)
   - **Stock UOM:** the unit you physically count and pick (usually `Nos` for implants/instruments; `Box` for bulk consumables that are never broken)
   - **Pack Breaking Policy:** `Pack-breakable` or `Never break packs` (required field — see decision above)
3. Click **Save** (keep as Draft while filling the remaining sections below).

---

## Step 2 — Set tracking flags

On the same Item form, scroll to the **Inventory** section:

**For batch + expiry tracked items (implants, consumables):**
- Check **Has Batch No** ✓
- Check **Has Expiry Date** ✓ *(only if the item has a regulatory/clinical expiry date)*
- Leave **Has Serial No** unchecked

**For serial tracked items (instruments, tools):**
- Check **Has Serial No** ✓
- Leave **Has Batch No** and **Has Expiry Date** unchecked

**For non-tracked items (bulk screws, gloves, etc.):**
- Leave all three unchecked

---

## Step 3 — Set UOM conversions (only for pack-breakable items)

*Skip this step if Pack Breaking Policy = `Never break packs`.*

If you buy in `Box` but stock/sell in `Nos`:

1. Still on the Item form, scroll to the **UOM Conversions** table.
2. Add rows:
   - UOM: `Nos` — Conversion Factor: `1`
   - UOM: `Box` — Conversion Factor: `[number of pieces per box, e.g. 10]`
3. Confirm the **Stock UOM** is `Nos` (the smaller unit).
4. Click **Save**.

This means: on Purchase Receipts you can enter `2 Box` and ERPNext will book `20 Nos` into stock.

---

## Step 4 — Set the supplier

Every item must have exactly one supplier (Doc 07 policy).

1. On the Item form, scroll to the **Purchasing** tab or the **Supplier** section.
2. In the **Supplier** table, click **Add Row**:
   - **Supplier:** select the supplier for this item
3. Click **Save**.

**Important for variant items:** this must be set on each variant individually. The template's supplier setting is not inherited automatically by all variants.

---

## Step 5 — Set HS code and import tax rate (for imported items)

*Skip this step for locally sourced items with no import duty.*

1. On the Item form, look for the **HS Code** and **Import Tax Rate (%)** fields (in the Purchasing or Custom section).
2. Fill in:
   - **HS Code:** the harmonized system commodity code for this product's import category
   - **Import Tax Rate (%):** the fixed import duty rate for this HS code (e.g. `10` for 10%)
3. Click **Save**.

These fields are used to auto-fill the import duty charge when creating a Landed Cost Voucher for this item.

---

## Step 6 — Set the selling price

The selling price goes into the **Standard Selling** price list.

1. Open **Item Price** (use global search) and click **New**, or open it from the Item's **Sales** section via the **Sales Price** shortcut.
2. Fill in:
   - **Item Code:** this item
   - **Price List:** `Standard Selling`
   - **Currency:** `AMD`
   - **Rate:** the selling price per Stock UOM unit
3. Click **Save**.

**Note:** Selling price can also be entered directly on each Dispatch Case row (`Unit Price` field). The price list value is only a default that pre-fills the row.

---

## Step 7 — Set reorder threshold (if item should be reordered)

1. On the Item form, scroll to the **Reorder Levels** tab (or section).
2. Click **Add Row**:
   - **Warehouse:** `Main - Inmed`
   - **Reorder Level:** the minimum quantity — when stock drops to or below this number, the item appears on the reorder list
   - **Reorder Qty:** the suggested quantity to order when triggered
   - **Material Request Type:** `Purchase`
3. Click **Save**.

---

## Step 8 — Creating variants from a template

*Only relevant for product families with multiple sizes/configurations (e.g. screws by diameter + length).*

### If the template already exists:
1. Open the **Item Template** (e.g. `SCREW-BONE-3.5MM-TPL`).
2. Click **Create Variants** (button at the top of the form).
3. Select the attribute values for the new variant (e.g. Diameter = `4.0mm`, Length = `25mm`).
4. Click **Create**.
5. Open the newly created variant and complete Steps 2–7 above (tracking, supplier, HS code, price, reorder level).

### If the template does not yet exist:
1. Create the Item as normal (Steps 1–3), but before saving:
   - Check **Has Variants** ✓
   - Add the **Item Attributes** that define the variant dimensions (e.g. `Diameter (mm)`, `Length (mm)`)
2. Save the template.
3. Use **Create Variants** to generate each variant combination.
4. For each variant: complete Steps 2–7.

**Variant naming:** ERPNext appends attribute values to the template code automatically (e.g. `SCREW-BONE-3.5MM-TPL-3.5-20`). Confirm the generated names are readable.

---

## Step 9 — Final verification checklist

Before using the item in a purchase or dispatch:

| Check | How |
|---|---|
| Item saves without error | Open item → confirm no missing required fields |
| Pack Breaking Policy is filled | Visible on item form |
| Tracking flags match intent | `Has Batch No`, `Has Expiry Date`, `Has Serial No` as planned |
| UOM conversion rows exist (if pack-breakable) | Item form → UOM Conversions table |
| Exactly one supplier is linked | Item form → Supplier table |
| HS Code and Import Tax Rate filled (if imported) | Item form → purchasing/custom fields |
| Selling price exists | Item Price list → Standard Selling |
| Reorder threshold set (if applicable) | Item form → Reorder Levels tab |

---

## Common mistakes

| Mistake | Consequence | How to avoid |
|---|---|---|
| Batch/expiry item modelled as two items (Box + Single) | Batch traceability breaks — you cannot track expiry across the repack | Use one item with UOM conversion |
| Pack Breaking Policy left blank | System blocks save (required field) | Always fill it |
| Supplier not set on the variant (only set on template) | PO validation will fail for that variant | Set supplier on each variant |
| Has Expiry Date checked without Has Batch No | Expiry cannot be recorded (expiry lives on the Batch record) | Always enable both together |
| Item Code changed after transactions exist | Breaks historical records | Item Code is permanent; disable the old item and create a new one if needed |
