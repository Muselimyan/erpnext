# New Supplier Setup Walkthrough

**Purpose:** Step-by-step guide for registering a new supplier so they are ready to receive a Purchase Order. Run this every time InMED begins working with a new supplier. This is the operational pair to `new-item-setup.md` and `new-customer-onboarding.md`.

**Estimated time:** 10–20 minutes

**Use case:** A new manufacturer or distributor is identified. Before a Purchase Order can be created for them, their Supplier record, contact, currency, and payment terms must exist — and the items they supply must be linked to them.

**Prerequisites:**
- You know the supplier's legal name, country, invoicing currency (USD or EUR), and payment terms
- You have a contact person's name and email at the supplier
- The items they supply already exist in the Item catalog (or you are creating them in parallel — see `new-item-setup.md`)

---

## Roles

| Task | Role |
|---|---|
| Create and maintain Supplier record | `Ops - Purchasing` |
| Set payment terms (if non-standard) | `Ops - Purchasing` + `Ops - Accounting` review |
| Link items to supplier | `Ops - Inventory` or `Ops - Purchasing` |

---

## Rule: one Supplier record per real supplier entity

Do not create duplicate Supplier records for the same company. Before creating a new record, search the Supplier list to confirm the supplier does not already exist under a slightly different name spelling.

---

## Step 1 — Create the Supplier record

**Login as:** `Ops - Purchasing`

1. Open **Supplier** and click **New**.
2. Fill in the required fields:
   - **Supplier Name:** the legal or commonly used trade name — e.g. `Medtronic Europe GmbH`, `Stryker EMEA`, `ABC Medical Distribution LLC`
     - Use the full legal name, not an abbreviation — abbreviations can be added in Notes
   - **Supplier Group:** select the correct group:
     - `Manufacturers` — the original product maker
     - `Distributors` — an intermediary who consolidates multiple brands
     - `Local Vendors` — local Armenian suppliers
   - **Country:** the country where the supplier is legally based or invoices from
   - **Default Currency:** `USD` or `EUR` — this is the currency used on Purchase Orders and invoices from this supplier
     - Most international suppliers use `USD`; European suppliers often use `EUR`
     - If the supplier invoices in AMD, use `AMD`
   - **Default Payment Terms Template:** select the standard terms for this supplier:
     - `Prepayment 100%` — full advance before shipment (most common for international suppliers)
     - `Prepayment 50/50` — 50% advance, 50% after receipt
     - Leave blank if terms are negotiated case-by-case (set on each PO)
3. Fill in **Notes:** include anything operationally useful:
   - How orders are confirmed (email, portal, phone)
   - Lead time range (e.g. "Typically 4–6 weeks from confirmation")
   - Any special instructions (e.g. "All orders need a written proforma invoice before payment")
4. Click **Save**.

---

## Step 2 — Add a contact person

At least one contact must be recorded so the purchasing team knows who to email for orders and confirmations.

1. On the saved Supplier form, find the **Contacts** section (or use the **Add Contact** button at the top).
2. Click **New Contact** or **Add Contact**.
3. Fill in:
   - **First Name / Last Name:** the contact's full name
   - **Email:** primary email for purchase order correspondence
   - **Phone:** direct number (optional but recommended)
   - **Designation:** their role at the supplier (e.g. `Sales Manager`, `Account Executive`)
4. Click **Save**.

If the supplier has multiple contacts (e.g. a sales contact and a finance/invoicing contact), add both.

---

## Step 3 — Verify payment terms

Good payment terms setup prevents errors when a PO is created.

1. Confirm the **Default Payment Terms Template** on the Supplier record matches the agreed terms.
2. If the supplier has unique terms not covered by existing templates:
   - Open **Payment Terms Template** and check if a matching template exists
   - If not: ask `Ops - Accounting` to create a new template, then set it on the Supplier
3. The payment terms set on the Supplier will auto-fill on new Purchase Orders for this supplier. They can be overridden per-PO if needed.

---

## Step 4 — Link items to this supplier

Every item sourced from this supplier must have the supplier set in its **Item Supplier table**. This is the "one item → one supplier" policy.

**Login as:** `Ops - Inventory` or `Ops - Purchasing`

For each item supplied by this supplier:

1. Open the **Item** record.
2. Go to the **Purchasing** tab (or **Supplier** section on the Item form).
3. In the **Supplier** table:
   - If the table is empty: click **Add Row** → set Supplier = this new supplier
   - If another supplier is already listed: this item was previously sourced elsewhere — confirm the switch is intentional before replacing
4. Click **Save** on the Item.

Repeat for every item this supplier provides, including all variants in a variant family (each variant must be linked individually — template-level supplier assignment is not inherited).

**Tip:** If there are many items to link, you can use Data Import (ask System Manager) to bulk-update the Item Supplier table.

---

## Step 5 — Verify the supplier is ready for a Purchase Order

Run this quick check before creating the first PO for this supplier:

| Check | How to verify |
|---|---|
| Supplier record exists and is not a duplicate | Search Supplier list — confirm only one record for this entity |
| Currency is set | Open Supplier → confirm Default Currency is filled |
| Payment terms are set | Open Supplier → confirm Default Payment Terms Template |
| At least one contact is linked | Open Supplier → Contacts section shows at least one contact |
| Items are linked to this supplier | Open each item → Supplier table → confirm supplier appears |

---

## Step 6 — Create the first Purchase Order (optional — verify end-to-end)

To confirm everything works:

1. Follow **Step 1 of the Purchase Walkthrough** (`purchase-walkthrough.md`) to create a Draft PO.
2. Set **Supplier** = this new supplier.
3. Confirm:
   - Currency auto-fills correctly from the supplier
   - Payment terms auto-fill correctly
   - Items from this supplier are selectable in the Items table
4. Save (do not submit — this is just a verification).

If anything does not look right (wrong currency, missing items in the dropdown), go back and fix the Supplier or Item records before creating a real PO.

---

## Adding a new contact to an existing supplier

If a new contact joins the supplier side (account manager changes, new finance contact):

1. Open the **Supplier** record.
2. Go to the **Contacts** section.
3. Add a new Contact (same as Step 2 above).
4. Optionally mark the old contact as inactive if they have left.

---

## Common issues

| Symptom | Likely cause |
|---|---|
| Currency does not auto-fill on new PO | `Default Currency` not set on Supplier — open Supplier and fill it |
| Payment terms do not auto-fill on new PO | `Default Payment Terms Template` not set on Supplier — fill it |
| Item not selectable on PO for this supplier | Item Supplier table not set to this supplier — open Item → Purchasing tab and add supplier |
| Duplicate supplier was accidentally created | Merge the two using System Manager → Merge DocType action; then clean up Item links |
| Supplier record not visible to Purchasing team | Role Permission Manager — `Ops - Purchasing` must have Read + Create on `Supplier` DocType |
