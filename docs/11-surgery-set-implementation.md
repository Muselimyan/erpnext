# Doc 11A — Surgery Set Setup (Implementation Guide)

## 1) Purpose
This document is a **step-by-step “click-by-click” setup guide** for a new ERPNext user to configure everything required by **Doc 11 — Surgery Set Model**.

Scope of this implementation doc:
- Warehouses (including delivery/return staging warehouses)
- Hospital Customers
- Custom DocTypes:
  - `Doctor`
  - `Surgery Set Type`
  - `Surgery Set Type Item` (child table)
- Creating master data records (doctors, set types)
- Basic validation checks

Out of scope here:
- The full operational workflow (dispatch, pickup, invoicing, tasks) — that is covered in Doc 12+.

---

## 2) Prerequisites / permissions
You must be logged in as a user with at least:
- `System Manager`
- `Stock Manager` (for warehouses)
- `Accounts Manager` (only if you also set payment terms)

To create **custom DocTypes**, you may also need:
- `Administrator` access, and
- access to the `DocType` list (depends on how your ERPNext is configured).

---

## 3) Naming conventions (use consistently)
These names are referenced in later docs and reports.

### 3.1 Warehouses
Create warehouses with the following names:
- `Main - WH`
- `Delivery In-Transit - WH`
- `Hospitals - WH` (group only)
- `HOSP - <Hospital Short Name> - WH` (one per hospital)
- `Return Pickup In-Transit - WH`
- `Returns - WH`

Rules:
- **Never** create a warehouse per delivery person.
- `Hospitals - WH` must be a **group** warehouse and should not be used for transactions.

### 3.2 Hospital short name
Decide a short name for each hospital (examples: `ARABKIR`, `Erebuni`, `Nairi`).

This short name is used only for warehouse naming:
- `HOSP - ARABKIR - WH`

---

## 4) How to create Warehouses (WH)
ERPNext can be navigated in two ways:
- Use the global search (Awesomebar): type the DocType name (example: `Warehouse`) and open it.
- Use the module pages (example: Stock module).

### 4.1 Create `Main - WH`
1) Open the `Warehouse` list.
2) Click `New`.
3) Fill the fields:
   - `Warehouse Name`: `Main - WH`
   - `Company`: select your company
   - `Parent Warehouse`: (top-level / `All Warehouses`)
   - `Is Group`: unchecked
4) Click `Save`.

### 4.2 Create the staging warehouses (`Delivery In-Transit - WH`, `Return Pickup In-Transit - WH`, `Returns - WH`)
Repeat the same steps as 4.1 for each warehouse:
- `Delivery In-Transit - WH`
- `Return Pickup In-Transit - WH`
- `Returns - WH`

Tips:
- Keep these as **normal** warehouses (not groups).
- These warehouses represent temporary/staging stock locations.

### 4.3 Create `Hospitals - WH` (group)
1) Open the `Warehouse` list.
2) Click `New`.
3) Set:
   - `Warehouse Name`: `Hospitals - WH`
   - `Company`: select your company
   - `Parent Warehouse`: (top-level / `All Warehouses`)
   - `Is Group`: checked
4) Click `Save`.

### 4.4 Create a hospital warehouse (`HOSP - <Hospital Short Name> - WH`)
Repeat these steps for each hospital customer.

1) Open `Warehouse`.
2) Click `New`.
3) Set:
   - `Warehouse Name`: `HOSP - <Hospital Short Name> - WH`
   - `Company`: select your company
   - `Parent Warehouse`: `Hospitals - WH`
   - `Is Group`: unchecked
4) Click `Save`.

Validation:
- Open `Hospitals - WH` and confirm you see the hospital warehouse under it.

---

## 5) How to create a Hospital Customer
Each hospital must exist as a `Customer`.

### 5.1 Create a Customer record
1) Open the `Customer` list.
2) Click `New`.
3) Fill (minimum recommended):
   - `Customer Name`: hospital official name
   - `Customer Type`: `Company`
   - `Customer Group`: (choose your standard group, for example `Commercial`)
   - `Territory`: (choose your standard territory)
4) Optional but recommended:
   - Set a contact phone number and address (via the contact/address sections on the customer).
5) Click `Save`.

### 5.2 (Optional) Set payment terms / credit behavior
Only do this if you already use Payment Terms in your accounting setup.

1) Open `Payment Terms Template`.
2) Create a template (example: `30 Days`), if not already created.
3) Go back to the hospital `Customer` and set the default payment terms (if your system uses this).

Validation:
- Confirm you can search and select the hospital in a Sales Order.

---

## 6) Create the `Doctor` custom DocType
Doctors must be selectable from a list and support quick-add.

### 6.1 Create the `Doctor` DocType
1) Open `DocType` list.
2) Click `New`.
3) Set:
   - `Name`: `Doctor`
   - Ensure it is **not** a child table
4) Add fields (recommended minimum):
   - `doctor_name` (Data) — Label: `Doctor Name` — Req: Yes
   - `phone` (Data) — optional
   - `notes` (Small Text) — optional
5) Add a way to link a doctor to multiple hospitals (recommended):
   - Create a child table DocType `Doctor Hospital` (see 6.2)
   - Add a Table field on `Doctor`:
     - Fieldname: `hospitals`
     - Label: `Hospitals`
     - Type: `Table`
     - Options: `Doctor Hospital`
6) Click `Save`.

### 6.2 Create the `Doctor Hospital` child table (for multi-hospital linking)
1) Open `DocType` list.
2) Click `New`.
3) Set:
   - `Name`: `Doctor Hospital`
   - Check: `Is Child Table`
4) Add fields:
   - `hospital` (Link) — Options: `Customer` — Label: `Hospital` — Req: Yes
5) Click `Save`.

Validation:
- Open the `Doctor` list and confirm `New` works.
- Open any Doctor record and confirm you can add multiple hospitals in the table.

---

## 7) Create the Surgery Set template DocTypes
Doc 11 requires a template DocType (`Surgery Set Type`) and a child table (`Surgery Set Type Item`).

### 7.1 Create child table: `Surgery Set Type Item`
1) Open `DocType` list.
2) Click `New`.
3) Set:
   - `Name`: `Surgery Set Type Item`
   - Check: `Is Child Table`
4) Add fields:
   - `item` (Link) — Options: `Item` — Req: Yes
   - `default_qty` (Float) — Req: Yes
   - `uom` (Link) — Options: `UOM` — optional
   - `is_optional` (Check) — optional
5) Click `Save`.

### 7.2 Create parent DocType: `Surgery Set Type`
1) Open `DocType` list.
2) Click `New`.
3) Set:
   - `Name`: `Surgery Set Type`
   - Ensure it is **not** a child table
4) Add fields:
   - `set_name` (Data) — Req: Yes
   - `set_code` (Data) — optional
   - `is_active` (Check) — default checked
   - `notes` (Small Text) — optional
   - `items` (Table) — Options: `Surgery Set Type Item`
5) Click `Save`.

Validation:
- Open `Surgery Set Type` list.
- Create a new Set Type and confirm you can add multiple item rows.

---

## 8) How to create a Doctor record
1) Open the `Doctor` list.
2) Click `New`.
3) Fill:
   - `Doctor Name`
   - Add one or more hospitals in the `Hospitals` table
4) Click `Save`.

Recommendation:
- Create doctors as soon as you hear a new name.
- Avoid free-text doctor names in orders; always use the Doctor record.

---

## 9) How to create a Surgery Set Type record (template)
1) Open the `Surgery Set Type` list.
2) Click `New`.
3) Fill:
   - `Set Name`
   - `Set Code` (if used)
   - Ensure `Is Active` is checked
4) In the `Items` table, add rows:
   - `Item`
   - `Default Qty`
   - `UOM` (if needed)
   - `Is Optional` (if applicable)
5) Click `Save`.

---

## 10) Setup validation checklist (must pass)
### 10.1 Warehouses
- `Main - WH` exists
- `Delivery In-Transit - WH` exists
- `Return Pickup In-Transit - WH` exists
- `Returns - WH` exists
- `Hospitals - WH` exists and is a **group**
- At least one `HOSP - <Hospital> - WH` exists under `Hospitals - WH`

### 10.2 Masters
- At least 1 hospital `Customer` exists
- `Doctor` DocType exists
- At least 1 `Doctor` record exists and links to one hospital
- `Surgery Set Type` and `Surgery Set Type Item` DocTypes exist
- At least 1 `Surgery Set Type` record exists with multiple items

---

## 11) Notes for the next docs
- Doc 11 only sets up master data and structure.
- Doc 12 will define:
  - the “case” record
  - dispatch and return documents
  - the task workflow and photo requirements
  - how delivery person assignments are recorded and reported
