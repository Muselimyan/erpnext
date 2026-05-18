# New Customer / Client Onboarding Walkthrough

**Purpose:** Step-by-step guide for registering a new client (doctor or hospital) in the system so they can be used on Dispatch Cases, sales invoices, and debt tracking. Run this every time a new client relationship starts.

**Estimated time:** 15–30 minutes

**Use case:** A new doctor or hospital starts using InMED's products. Before any Dispatch Case can be created for them, their Customer record, client location warehouse, and credit threshold must exist.

**What this test proves:** Order, inventory, accounting, and director roles can prepare a customer so sales, surgery cases, debt tracking, and client-location stock flows can work.

**ERPNext screens used:** `Customer`, `Warehouse`, `Dispatch Case`.

**Pass condition:** Customer exists with unique client code and debt threshold, is reviewed as non-provisional, and the client location warehouse exists under `Clients - Inmed`.

**Prerequisites:**
- The `Clients - Inmed` group warehouse already exists (created once during go-live)
- You know the client's full name, type (doctor or hospital), debt threshold, and the hospital location they work at (for doctors)

---

## Roles used in this flow

| Step | Task | Logged-in role |
|---|---|---|
| 1 | Create Customer record | `Ops - Order Accepting` or `Ops - Order Creating` |
| 2 | Create client location warehouse | `Ops - Inventory` (or `System Manager`) |
| 3 | Mark client as non-provisional after review | `Ops - Accounting` or `Ops - Directors` |

---

## Step 1 — Create the Customer record

**Login as:** `Ops - Order Accepting` or `Ops - Order Creating`

All clients — whether doctors or hospitals — are recorded as **Customer** records in ERPNext.

**Why this matters:** Dispatch Cases, Sales Invoices, debt tracking, and reports all depend on the Customer record. If the client code or debt threshold is wrong, later testing will be confusing.

1. Search for `Customer`, open the **Customer** list, and click **New**.
   - If you do not see the **Customer** DocType, or you can open it but cannot click **New** or **Save**, stop here: the test user is missing Customer permissions. Ask a System Manager to check permissions for `Ops - Order Accepting` / `Ops - Order Creating`, or test this setup step with a System Manager user.
2. Fill in:
   - **Customer Name:** follow the naming convention:
     - For a doctor: `D### — Dr. [Full Name]` — e.g. `D017 — Dr. A. Petrosyan`
     - For a hospital: `H### — [Hospital Name]` — e.g. `H003 — Muratsan Hospital`
   - **Client Code:** the code part only — e.g. `D017` or `H003`
     - Codes must be unique; check the existing list before picking the next number
     - Doctor codes start with `D`, hospital codes start with `H`
   - **Client Kind:** select `Doctor` or `Hospital`
   - **Debt Threshold (AMD):** the maximum outstanding balance allowed before director escalation
     - Ask the director team if you are unsure of the threshold; do not leave it at 0
   - **Is Provisional:** leave **checked** ← new clients always start as provisional
   - **Customer Group:** `Individual` for doctors, or the appropriate group for hospitals
   - **Territory:** `Armenia` (default)
3. Click **Save**.

**✅ Expected:**
- Customer saved with `Is Provisional = Yes`
- Client Code appears and is unique

**❌ Should NOT happen:**
- Error "Client Code is required" → fill the Client Code field
- Error "Value already exists for client_code" → this code is taken; pick the next available number

---

## Step 2 — Create the client location warehouse

**Login as:** `Ops - Inventory` (or `System Manager`)

This warehouse is required for **any Dispatch Case where Return Expected = Yes** (surgery cases, equipment loans). It represents company-owned stock physically sitting at the client's location.

**Why this matters:** Return-expected flows move company-owned stock from `Main - Inmed` to the client's location and then back. Without the client warehouse, surgery/loan testing cannot represent where the stock physically is.

For clients who will only ever receive standard sales (no returns), this warehouse is still recommended to create proactively — it is needed the moment a surgery case is ever dispatched to them.

### Warehouse naming pattern

```
[Doctor Code] — [Doctor Name] @ [Hospital Code] — [Hospital Name] / [Branch] - Inmed
```

Examples:
- `D017 — Dr. A. Petrosyan @ H003 — Muratsan Hospital / Main - Inmed`
- `H003 — Muratsan Hospital / Main - Inmed` *(for a hospital-only client with no specific doctor)*

### Steps

1. Search for `Warehouse`, open the **Warehouse** list, and click **New**.
   - If you do not see the **Warehouse** DocType, or you can open it but cannot click **New** or **Save**, stop here: the test user is missing Warehouse permissions. Ask a System Manager to check Warehouse permissions for `Ops - Inventory`, or test this setup step with a System Manager user.
2. Fill in:
   - **Warehouse Name:** follow the naming pattern above
   - **Parent Warehouse:** `Clients - Inmed` (the top-level group warehouse for all client locations)
   - **Is Group:** leave **unchecked** (this is a leaf/physical warehouse)
   - **Company:** `InMED`
3. Click **Save**.

**✅ Expected:**
- Warehouse saved under `Clients - Inmed`
- Warehouse name matches the naming pattern exactly (this is used in Dispatch Cases)

**Note — multiple branches at the same hospital:**
If a doctor works at more than one hospital branch, create a separate warehouse for each location group. Each warehouse represents a distinct physical place where items can be.

---

## Step 3 — Link the warehouse to the customer (if required by flow)

Some fields on the Dispatch Case let you select the client location warehouse directly. There is no automatic link from Customer → Warehouse in ERPNext's standard setup, so the warehouse is selected manually on each Dispatch Case.

To make the warehouse easy to find:
- Confirm the warehouse naming starts with the client code (e.g. `D017`) — this allows easy filtering in the warehouse picker on the Dispatch Case

---

## Step 4 — Mark client as non-provisional (after review)

**Login as:** `Ops - Accounting` or `Ops - Directors`

New clients start as `Is Provisional = Yes`. This is a control flag that signals the record has not been fully reviewed.

**Why this matters:** This separates quick order entry from final approval of client data. It prevents unreviewed clients from silently becoming permanent master data.

Before the client is used for real transactions in a live setting:
1. Search for `Customer`, open the **Customer** list, and open the customer record.
2. Verify:
   - **Customer Name** follows the naming convention
   - **Client Code** is correct and unique
   - **Debt Threshold (AMD)** is set to an appropriate value (not 0)
   - **Client Kind** matches reality
   - No duplicate customer exists with the same real-world person or entity
3. Uncheck **Is Provisional**.
4. Click **Save**.

**✅ Expected:**
- `Is Provisional` = unchecked
- Customer is now fully active for use in real operations

**Note:** Only `Ops - Accounting`, `Ops - Directors`, or `System Manager` can uncheck `Is Provisional`. If you are on the Order team and see an error when trying to do this, ask Accounting to complete this step.

---

## Step 5 — Verify the setup before first Dispatch Case

Run this quick check before creating the first Dispatch Case for this client:

| Check | How to verify |
|---|---|
| Customer exists | Search for the client in **Customer** list |
| Client Code is set | Search for `Customer`, open the customer record → confirm `client_code` field is filled |
| Debt Threshold > 0 | Search for `Customer`, open the customer record → confirm `debt_threshold_amd` is not 0 |
| Is Provisional = No | Search for `Customer`, open the customer record → confirm checkbox is unchecked |
| Client location warehouse exists | Search in **Warehouse** list, filter by the client code |
| Warehouse is under `Clients - Inmed` | Search for `Warehouse`, open the warehouse record → confirm Parent Warehouse |

---

## Context fields on Dispatch Cases and Invoices

When creating a Dispatch Case or Sales Invoice for this client, you may also fill in optional context fields for reporting:

- **Hospital** — link to the hospital Customer (if the invoiced party is a doctor who works at a specific hospital)
- **Hospital Branch** — free text (e.g. `OR Block 2`)
- **Doctor Name** — free text (if the invoiced party is a hospital and the surgery was performed by a named doctor)

These fields do not affect stock or financial flow — they are for reporting and searchability only.

---

## Common failure modes

| Symptom | Likely cause |
|---|---|
| Cannot uncheck Is Provisional | Logged in as Order team role; ask Accounting/Directors to do it |
| Client Code already exists | Another customer has the same code; check the list and pick the next available number |
| Warehouse not visible in Dispatch Case dropdown | Warehouse is not under `Clients - Inmed`, or company is set incorrectly on the warehouse |
| Debt threshold is 0 | Was left blank during creation; search for `Customer`, open the customer record, and set the correct threshold |
