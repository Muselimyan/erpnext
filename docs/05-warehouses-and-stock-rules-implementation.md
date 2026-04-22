# Doc 05A — Warehouses, Stock Rules (Implementation / ERPNext Setup Guide)

## 1) Purpose
This is a step-by-step guide to implement:
- **Doc 05 — Inventory Foundation: Warehouses, Stock Rules (Operational)**

It covers:
- Creating the warehouse tree (group vs leaf)
- Creating the `Clients - WH` group and client location warehouses (doctor + hospital + branch)
- Stock Settings guardrails that protect data quality
- A validation checklist to confirm the structure works

Non-goals:
- This doc does not implement the Surgery Case workflow automation (Doc 12).
- This doc does not implement the standard selling flow (Doc 09).

---

## 2) Prerequisites / access
Do this as a user with:
- `System Manager`
- `Stock Manager`

Prerequisite:
- Complete Doc 03A first so driver restrictions exist (drivers must not be able to post stock).

You will use:
- `Warehouse`
- `Stock Settings`
- Stock reports:
  - `Stock Balance`

---

## 3) Confirm naming conventions (required)
Before creating warehouses, confirm the naming pattern from Doc 02.

Rules:
- All warehouses use the suffix: ` - WH`

Client location warehouse naming patterns (from Doc 05):
- Doctor-client location:
  - `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital Name> / <Branch Name> - WH`
- Hospital-client location (no named doctor):
  - `<Hospital Code> — <Hospital Name> / <Branch Name> - WH`

Important note about ERPNext naming:
- ERPNext often appends the company abbreviation to warehouse names automatically.
- If your company abbreviation appears as an extra suffix, accept it (do not fight the system). Your key goal is that the **visible base name** remains consistent and searchable.

Operational rule (critical):
- Only leaf warehouses should contain stock.
- Do not post any Stock Entry into group warehouses (example: `Clients - WH`).

---

## 4) Create the warehouse tree
Create the warehouses in this order.

### 4.1 Create `Main - WH`
Steps:
1) Open `Warehouse`.
2) Click `New`.
3) Set:
   - Warehouse Name: `Main - WH`
   - Is Group: OFF
4) Save.

Resulting warehouse should display as:
- `Main - WH` (possibly with an additional company suffix)

### 4.2 Create `Delivery In-Transit - WH`
Steps:
1) Open `Warehouse`.
2) Click `New`.
3) Set:
   - Warehouse Name: `Delivery In-Transit - WH`
   - Is Group: OFF
4) Save.

Result:
- `Delivery In-Transit - WH` (possibly with an additional company suffix)

### 4.3 Create `Clients - WH` (group)
Steps:
1) Open `Warehouse`.
2) Click `New`.
3) Set:
   - Warehouse Name: `Clients - WH`
   - Is Group: ON
4) Save.

Result:
- `Clients - WH` (possibly with an additional company suffix)

### 4.4 Create `Return Pickup In-Transit - WH`
Steps:
1) Open `Warehouse`.
2) Click `New`.
3) Set:
   - Warehouse Name: `Return Pickup In-Transit - WH`
   - Is Group: OFF
4) Save.

Result:
- `Return Pickup In-Transit - WH` (possibly with an additional company suffix)

### 4.5 Create `Returns - WH`
Steps:
1) Open `Warehouse`.
2) Click `New`.
3) Set:
   - Warehouse Name: `Returns - WH`
   - Is Group: OFF
4) Save.

Result:
- `Returns - WH` (possibly with an additional company suffix)

---

## 5) Create client location warehouses (doctor + hospital + branch)
You must create one leaf warehouse per distinct physical client location group used for company-owned stock tracking.

Important:
- These warehouses are used for:
  - surgery set workflows (Doc 11/12)
  - permanent on-site sets (consignment-like)
- Standard sales must not move stock into these warehouses.

### 5.1 Create one doctor-client location warehouse (sample)
Sample data used below (matches Doc 04A examples):
- Doctor client: `D001 — Dr. A. Petrosyan`
- Hospital context: `H001 — Erebuni MC`
- Branch: `Main`

Steps:
1) Open `Warehouse`.
2) Click `New`.
3) Set:
   - Warehouse Name: `D001 — Dr. A. Petrosyan @ H001 — Erebuni MC / Main - WH`
   - Parent Warehouse: `Clients - WH`
   - Is Group: OFF
4) Save.

### 5.2 Create a hospital-client location warehouse (sample)
Use this pattern only when the billing client is the hospital (no named doctor as the Customer).

Steps:
1) Open `Warehouse`.
2) Click `New`.
3) Set:
   - Warehouse Name: `H001 — Erebuni MC / Main - WH`
   - Parent Warehouse: `Clients - WH`
   - Is Group: OFF
4) Save.

### 5.3 Repeat for every active location group
Rule:
- If the same doctor operates at 3 hospital branches, that is 3 different leaf warehouses.

---

## 6) Stock Settings guardrails (recommended)
Open `Stock Settings` and review these settings carefully.

### 6.1 Negative stock
Recommended baseline:
- Keep negative stock disabled where possible.

Reason:
- Negative stock hides operational problems and makes warehouse/in-transit reporting unreliable.

### 6.2 Backdating policy
Operational requirement (Doc 05 / Doc 12):
- Return pickups may need postings that reflect the pickup time.

Policy recommendation:
- Allow backdating only for trusted back-office users (Returns Team / Inventory Team).
- Drivers should not be able to post stock entries.

---

## 7) Permissions (high-level)
Goal:
- Only stock users can create/submit stock movements.
- Drivers must not be able to create stock movements.

Implementation anchor:
- Follow the driver restrictions in `03-roles-permissions-responsibilities-implementation.md` section “Block drivers from stock and accounting documents”.

---

## 8) Validation checklist (required)
After creating warehouses:

### 8.1 Tree correctness
- Confirm `Clients - WH` is a group warehouse.
- Confirm all client location warehouses are leaf warehouses.
- Confirm no stock transactions are posted to `Clients - WH`.

Spot-check (required):
- Open each warehouse record and confirm:
  - `Clients - WH` has `Is Group` = ON
  - leaf warehouses (`Main - WH`, `Delivery In-Transit - WH`, `Return Pickup In-Transit - WH`, `Returns - WH`, and each client location warehouse) have `Is Group` = OFF

### 8.2 Report sanity checks
Open `Stock Balance`:
- Filter Warehouse = `Main - WH` and confirm it returns results.
- Filter Warehouse = `Delivery In-Transit - WH` (should normally be near-empty outside active deliveries).
- Filter Warehouse = `Return Pickup In-Transit - WH` (should normally be near-empty outside active pickups).
- Filter Warehouse = `Returns - WH` (should reflect current returns processing workload).
- Filter Warehouse = one client location warehouse (example: `D001 — Dr. A. Petrosyan @ H001 — Erebuni MC / Main - WH`) and confirm it is initially empty.

### 8.3 Operational discipline check
- Confirm there is an agreed daily/weekly routine to investigate any quantities left in either in-transit warehouse.

---

## 9) Acceptance criteria
- The warehouse tree exists exactly as defined in Doc 05.
- You can create a new client location group and consistently add its:
  - Customer records (Doc 04)
  - Client location warehouse under `Clients - WH` (this doc)
- Stock reports cleanly show:
  - what is in main
  - what is in transit
  - what is in returns
  - what is at a given client location (company-owned at client)
