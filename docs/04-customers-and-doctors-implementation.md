# Doc 04A — Customers (Clients) (Implementation / ERPNext Setup Guide)

## 1) Purpose
This is a step-by-step guide to implement:
- **Doc 04 — Master Data: Customers (Clients) (Operational)**

It covers:
- Client setup as `Customer` (doctors and hospitals)
- Capturing client code and debt threshold
- Capturing hospital + branch + doctor-name context on transactions (without a separate Doctor master)
- Governance controls (provisional clients and edit restrictions)
- Permissions and a smoke-test checklist

Non-goals:
- This doc does not implement automated debt alerts (Doc 12).
- This doc does not implement the standard selling workflow (Doc 09).

---

## 2) Prerequisites / access
Do this as a user with:
- `System Manager`

Prerequisite:
- Complete Doc 03A first so the following roles exist:
  - `Ops - Order Accepting`
  - `Ops - Inventory`
  - `Ops - Returns`
  - `Ops - Delivery`
  - `Ops - Accounting`
  - `Ops - Directors`

You will use:
- `Customize Form`
- `DocType`
- `Role Permission Manager`
- `Server Script`
- `Customer`
- `Data Import` (optional but recommended)


---

## 3) Configure Customer (Client) fields
Doc 04 requires that every client (doctor or hospital) is represented as a single canonical `Customer`.

### 3.1 Add `client_code` on `Customer`
Goal:
- Store the stable client code explicitly (used in naming, searching, and warehouse naming).

Steps:
1) Open `Customize Form`.
2) Select DocType: `Customer`.
3) Add a Custom Field:
   - Label: `Client Code`
   - Fieldname: `client_code`
   - Fieldtype: `Data`
   - Required: ON
   - Unique: ON
4) Save.

Code scheme (sample data):
- Doctors: `D001`, `D002`, ...
- Hospitals: `H001`, `H002`, ...

### 3.2 Add `client_kind` on `Customer`
Goal:
- Mark whether this Customer is a doctor-client or a hospital-client.

Steps:
1) In `Customize Form` → `Customer`, add a Custom Field:
   - Label: `Client Kind`
   - Fieldname: `client_kind`
   - Fieldtype: `Select`
   - Options (one per line, exactly):
     - Doctor
     - Hospital
   - Required: ON
2) Save.

### 3.3 Add `debt_threshold_amd` on `Customer`
Goal:
- Store the per-client debt threshold used for director alerts (requirements).

Steps:
1) In `Customize Form` → `Customer`, add a Custom Field:
   - Label: `Debt Threshold (AMD)`
   - Fieldname: `debt_threshold_amd`
   - Fieldtype: `Currency`
   - Required: ON
2) Save.

### 3.4 Add `is_provisional` on `Customer` (required governance control)
Goal:
- Allow the Order Team to create a client under time pressure, but force a later review.

Steps:
1) In `Customize Form` → `Customer`, add a Custom Field:
   - Label: `Is Provisional`
   - Fieldname: `is_provisional`
   - Fieldtype: `Check`
   - Default: Checked
2) Save.

Operational rule:
- New customers are created as provisional.
- Accounting/Directors review and uncheck `Is Provisional` after validation (duplicate check, code/name correctness).

---

## 4) Add hospital + branch + doctor context fields to sales documents
Doc 04 decision: do not maintain a separate Doctor master.

### 4.1 Add fields to `Sales Order`
Steps:
1) Open `Customize Form`.
2) Select DocType: `Sales Order`.
3) Add custom fields:
   - Label: `Hospital`
     - Fieldname: `hospital`
     - Fieldtype: `Link`
     - Options: `Customer`
     - Required: OFF
   - Label: `Hospital Branch`
     - Fieldname: `hospital_branch`
     - Fieldtype: `Data`
     - Required: OFF
   - Label: `Doctor Name`
     - Fieldname: `doctor_name`
     - Fieldtype: `Data`
     - Required: OFF
4) Save.

Usage rule:
- If Customer is a doctor: optionally fill `Hospital` + `Hospital Branch`.
- If Customer is a hospital: optionally fill `Doctor Name` (free text).

### 4.2 Add fields to `Sales Invoice`
Repeat the same steps for DocType: `Sales Invoice`.

---

## 5) Governance controls (required): prevent unsafe edits
Doc 04 requires controlled edits once a client becomes active.

### 5.1 Customer edit restrictions (Server Script)
Goal:
- Order Team can create provisional customers.
- Only Accounting/Directors can:
  - change `Client Code`
  - uncheck `Is Provisional`

Steps:
1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Customer`
   - `DocType Event`: `Before Save`
4) Paste this script:

```python
import frappe

before = doc.get_doc_before_save()
if not before:
    before = None

user_roles = set(frappe.get_roles(frappe.session.user))
is_privileged = ("Ops - Accounting" in user_roles or "Ops - Directors" in user_roles or "System Manager" in user_roles)

# Block Client Code changes unless privileged
if before and before.client_code != doc.client_code and not is_privileged:
    frappe.throw("Only Accounting/Directors can change Client Code")

# Only privileged roles can uncheck Is Provisional
if before and before.is_provisional and not doc.is_provisional and not is_privileged:
    frappe.throw("Only Accounting/Directors can mark a client as non-provisional")
```

5) Save.

---

## 6) Client creation procedure (practical, with sample data)

### 6.1 Create a doctor-client Customer
Steps:
1) Open `Customer`.
2) Click `New`.
3) Fill:
   - Customer Name: `D001 — Dr. A. Petrosyan`
   - Client Code: `D001`
   - Client Kind: `Doctor`
   - Debt Threshold (AMD): `2000000`
   - Is Provisional: Checked
4) Save.

### 6.2 Create a hospital-client Customer
Steps:
1) Open `Customer`.
2) Click `New`.
3) Fill:
   - Customer Name: `H001 — Erebuni MC`
   - Client Code: `H001`
   - Client Kind: `Hospital`
   - Debt Threshold (AMD): `50000000`
   - Is Provisional: Checked
4) Save.

Follow-up (required for surgery/consignment stock tracking):
- Create the doctor-hospital-branch **Client Location Group warehouse** under `Clients - WH` as defined in Doc 05.

### 6.3 Create the client location warehouse (doctor + hospital + branch)
Purpose:
- This is required for company-owned stock at client locations (surgery sets, permanent on-site sets).
- Standard sales must not move stock into these warehouses.

Naming pattern (from Doc 05):
- `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital Name> / <Branch Name> - WH`

Sample warehouse name:
- `D001 — Dr. A. Petrosyan @ H001 — Erebuni MC / Main - WH`

Steps:
1) Open `Warehouse`.
2) Click `New`.
3) Create the group warehouse `Clients - WH` (do this once):
   - Warehouse Name: `Clients - WH`
   - Is Group: ON
   - Save
4) Create the leaf warehouse for the location group:
   - Warehouse Name: `D001 — Dr. A. Petrosyan @ H001 — Erebuni MC / Main - WH`
   - Parent Warehouse: `Clients - WH`
   - Is Group: OFF
5) Save.

---

## 7) Permissions (baseline, aligned with Doc 03)
Goal:
- Most roles can select/read customers.
- Only controlled roles can change master data governance flags.

### 7.1 Customer permissions
Steps:
1) Open `Role Permission Manager`.
2) Select DocType: `Customer`.
3) Set:
   - `Ops - Order Accepting`: Read ON, Write ON, Create ON
   - `Ops - Accounting`: Read ON, Write ON, Create ON
   - `Ops - Directors`: Read ON, Write ON, Create ON
   - `Ops - Inventory`: Read ON
   - `Ops - Returns`: Read ON
   - `Ops - Delivery`: Read ON
   - `Delivery Driver`: Read OFF
4) Save.

Note:
- The Server Script in section 5.1 prevents unsafe edits even if a role has Write.

---

## 8) Data import (recommended for bulk)
For initial go-live:
1) Use `Data Import` for `Customer`.
2) Import with these columns:
   - Customer Name
   - Client Code
   - Client Kind
   - Debt Threshold (AMD)
   - Is Provisional

Sample rows:
- `D001 — Dr. A. Petrosyan`, `D001`, `Doctor`, `2000000`, `1`
- `H001 — Erebuni MC`, `H001`, `Hospital`, `50000000`, `1`

Then do a manual review pass for:
- duplicates
- code/name consistency

---

## 9) Smoke tests (required)
### 9.1 Customer master
- Create a doctor-client Customer.
- Confirm `client_code`, `client_kind`, and `debt_threshold_amd` are required.

### 9.2 Transaction context fields
- Create a Sales Order for doctor-client `D001`.
  - Fill Hospital = `H001 — Erebuni MC`
  - Fill Hospital Branch = `Main`
  - Leave Doctor Name blank
- Create a Sales Invoice for hospital-client `H001`.
  - Fill Doctor Name = `Dr. A. Petrosyan`
  - Leave Hospital blank

### 9.3 Governance enforcement
- As an Order Team user, try to uncheck `Is Provisional` (must fail).
- As an Accounting user, uncheck `Is Provisional` (must succeed).
- As an Order Team user, try to change `Client Code` (must fail).
