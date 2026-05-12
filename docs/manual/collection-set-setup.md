# Collection Set Setup and Maintenance

**Purpose:** Guide for creating and maintaining Collection Set records — the item templates loaded via the "Load from Template" button on Dispatch Cases. Every surgery/return-expected case can be pre-filled from a template instead of entered line by line.

**Estimated time:** 15–30 minutes per new template

**Use case:** InMED delivers a predefined set of instruments and implants to a surgery. Rather than adding each item manually to every Dispatch Case, the Order Creation team loads a Collection Set template that pre-fills all the expected items and quantities. This guide covers how to create and update those templates.

**Prerequisites:**
- All items in the template already exist in the Item catalog (`new-item-setup.md`)
- The `Collection Set` DocType exists in ERPNext (set up during go-live, Doc 11A)

---

## Roles

| Task | Role |
|---|---|
| Create / update Collection Sets | `Ops - Inventory` |
| Load template on a Dispatch Case | `Ops - Order Creating` |
| Review readiness warnings | `Ops - Inventory`, `Ops - Directors` |

---

## Understanding Collection Sets

A Collection Set is a **reusable template** — a list of items and default quantities that represents a standard delivery set (e.g. "Ortho Basic Set", "Spine Set A", "ENT Kit"). It is not a stock item itself; it is just a list.

When the Order Creation team clicks **Load from Template** on a Dispatch Case, the template's items and quantities are copied into the Dispatch Case Items table. The Order Creation person can then adjust quantities, add items, remove items, and set prices — the template is a starting point, not a constraint.

A Collection Set also shows a **Readiness Status** — the system checks whether `Main - Inmed` has enough stock to fill the template right now:
- `Ready` — all items have enough projected stock
- `Short` — some items are below the required quantity
- `Critical Short` — items marked as critical are short

---

## Step 1 — Create a new Collection Set

**Login as:** `Ops - Inventory`

1. Open **Collection Set** (use the search bar) and click **New**.
2. Fill in the header:
   - **Set Name:** a clear, descriptive name — e.g. `Ortho Basic Set`, `Spine Fusion Set — Large`, `ENT Endoscopy Kit`
   - **Set Code:** a short internal code for quick reference — e.g. `ORTHO-BASIC`, `SPINE-LG`, `ENT-ENDO` (optional but recommended)
   - **Is Active:** leave **checked** — inactive templates do not appear in the Dispatch Case template picker
   - **Notes:** any relevant operational notes (e.g. "Used for Dr. Petrosyan's standard procedures" or "Includes items for femur fracture repair")
3. Do not save yet — proceed to adding items.

---

## Step 2 — Add items to the template

In the **Items** table, add one row per item that belongs in this set:

For each row, fill in:
- **Item:** select the Item Code from the catalog
- **Default Qty:** the standard quantity included in this set (e.g. `1` for a tool, `5` for screws)
- **UOM:** leave blank to use the item's default Stock UOM, or specify if this set uses a different unit
- **Group:** categorize the item within the set — `Tools / Instruments`, `Screws`, `Nails`, `Plates` (helps the packing team organize the physical box)
- **Return Behavior:**
  - `Expected Return (Tools)` — instruments that always come back (serial-tracked tools, drills, etc.)
  - `May Be Used (Implants)` — consumables/implants that may be fully used and not returned
- **Is Critical:** check this for items where a shortage would block the surgery entirely (e.g. the primary implant). Used to escalate the Readiness Status to `Critical Short`.
- **Notes:** any item-specific packing instructions (e.g. "Always sterilize before dispatch", "Check serial number against service log")

Click **Save** when all items are entered.

**✅ Expected after Save:**
- The **Readiness Status** field auto-updates: `Ready`, `Short`, or `Critical Short`
- If any item is short, a warning popup lists which items are missing and by how much
- The Readiness Status is based on projected stock in `Main - Inmed` at the time of saving

---

## Step 3 — Verify the template on a Dispatch Case

Before using the template in production, test it on a draft Dispatch Case:

**Login as:** `Ops - Order Creating`

1. Open a new **Dispatch Case** (or an existing Draft).
2. Set **Return Expected** = checked (Collection Sets are typically used for return-expected cases, but work for any case type).
3. In the **Item Template** field, select your new Collection Set.
4. Click **Load from Template** (or the field trigger auto-loads when a template is selected).
5. Confirm the **Case Items** table is populated with the correct items and default quantities.
6. Verify:
   - Item codes are correct
   - Quantities match the template defaults
   - No unexpected items appear
7. Do **not** submit this test — just confirm the load worked, then discard or cancel the draft.

---

## Updating an existing Collection Set

When a product line changes (new item replaces an old one, quantities are revised, item added to the set):

**Login as:** `Ops - Inventory`

1. Open the **Collection Set** record.
2. Make your changes:
   - **Add a new item:** click Add Row in the Items table
   - **Remove an item:** delete the row (use the row-level delete button)
   - **Change default qty:** edit the Default Qty field on the relevant row
   - **Retire an item from the set:** delete the row or reduce qty to 0
3. Click **Save**.

**Important:** Updating a template does **not** affect any Dispatch Cases that were already created from it. Only new cases created after the update will use the new template definition.

---

## Deactivating a Collection Set

If a set is no longer used (discontinued procedure, replaced by a newer template):

1. Open the Collection Set.
2. Uncheck **Is Active**.
3. Click **Save**.

The template will no longer appear in the Dispatch Case template picker. Existing cases created from it are not affected.

Do **not** delete Collection Sets — they may be referenced in historical Dispatch Cases.

---

## Checking readiness before dispatch season

Before a period of heavy surgical activity (e.g. a week with many scheduled surgeries):

1. Open the **Collection Set** list.
2. Check the **Readiness Status** column for each active template.
3. Any template showing `Short` or `Critical Short` needs purchasing attention.
4. For short items: cross-reference with the **Reorder List** (see `low-stock-reorder-routine.md`) and initiate a Purchase Order if needed.

---

## Common issues

| Symptom | Likely cause |
|---|---|
| Template does not appear in Dispatch Case dropdown | `Is Active` is unchecked — open the template and check it |
| "Load from Template" adds wrong quantities | Template default quantities are outdated — update the Collection Set Items table |
| Readiness Status shows `Short` even though stock looks fine | Check that items are in `Main - Inmed` specifically — stock in transit or at client locations does not count |
| An item added to the template is not available in the Item picker | Item does not exist in the catalog — create it first (`new-item-setup.md`) |
| Template saved with no Readiness Status | Readiness automation script may be disabled — check with System Manager |
