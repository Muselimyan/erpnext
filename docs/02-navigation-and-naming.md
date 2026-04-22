# Doc 02 — Navigation & Naming Conventions (Operational)

## 1) Purpose
This document defines a simple, consistent way to:
- Navigate ERPNext quickly
- Name master data consistently (so search, reporting, and training are easy)

Goals:
- Make ERPNext usable for new staff with minimal confusion
- Ensure every name is searchable and unique enough
- Keep operational data clean so reporting works

Non-goals:
- This doc does not explain how to configure ERPNext.
- This doc does not define detailed business workflows.

---

## 2) General principles
- **Consistency over perfection**
  - A simple consistent rule beats a complex “perfect” system.
- **Names must be searchable**
  - Use meaningful words and stable identifiers.
- **Avoid renaming later**
  - Renaming breaks habits and can confuse users. Decide the pattern once.
- **Prefer short but unambiguous**
  - Don’t write essays in names, but include enough to avoid duplicates.

---

## 3) How to navigate ERPNext (mental model)
ERPNext screens you will use most:
- **List view**: search + filter + group (this is where managers spend most time)
- **Form view**: open one record and edit
- **Reports**: pre-built or custom reports
- **Workspace**: a “home page” with shortcuts

Navigation rules:
- Use the global search bar to jump to DocTypes (example: type `Task`, `Customer`, `Item`).
- When you find a useful list filter, save it (naming guidance below).
- Use Workspaces as shortcuts for teams (Directors, Delivery, Inventory, Accounting).

---

## 4) Naming conventions (global rules)
These apply everywhere unless a section overrides them.

### 4.1 Language
- Use one language consistently for system names.
- If your team works in Armenian daily but ERPNext is English, choose one:
  - Option A: English names everywhere
  - Option B: Armenian names everywhere

Rule:
- Do not mix languages inside the same naming category.

### 4.2 Separators and formatting
- Use ` — ` (space dash space) to separate concepts in a title.
- Use ` - ` inside warehouse names only (because ERPNext default warehouse naming uses ` - WH`).
- Avoid special characters except dash and parentheses.

### 4.3 Codes
If you use codes (recommended for clients):
- Keep them short and stable.
- Example patterns:
  - `D001`, `D002`, ... (doctor clients)
  - `H001`, `H002`, ... (hospital clients)

---

## 5) Company
Rule:
- Use your legal company name.

---

## 6) Warehouses
Warehouse names must support:
- fast picking (humans can recognize them)
- clean reporting (you can filter/group by type)

### 6.1 Global warehouse naming
Use the ERPNext standard suffix:
- ` - WH`

Recommended top-level structure:
- `Main - WH`
- `Clients - WH`
- `Delivery In-Transit - WH`
- `Return Pickup In-Transit - WH`
- `Returns - WH`

### 6.2 Client location warehouses
Rule:
- One warehouse per **client location group** (doctor + hospital + branch) under `Clients - WH`.

Operational note:
- Client location warehouses may contain company-owned stock for:
  - surgery cases (pending return/usage reconciliation)
  - permanent on-site surgery sets (consignment-like)

Recommended naming pattern:
- `<Doctor Code> — <Doctor Name> @ <Hospital Code> — <Hospital/Branch Name> - WH`

If the client is a hospital (no named doctor):
- `<Hospital Code> — <Hospital/Branch Name> - WH`

Examples:
- `D014 — Dr. S. Mkrtchyan @ H021 — Shengavit Clinic (Branch 2) - WH`
- `D014 — Dr. S. Mkrtchyan @ H014 — Erebouni Medical Center - WH`
- `H021 — Shengavit Clinic (Branch 2) - WH`

---

## 7) Customers (Clients)
Rule:
- Customer name must match the name used in conversation and invoices.

Recommended naming pattern:
- `<Client Code> — <Client Name>`

If a client has multiple locations:
- Treat each location as a separate Customer only if they need separate billing/receivables identity.

---

## 8) Items
Item naming must support:
- quick picking
- low mistake rate
- variant clarity

### 8.1 Base naming pattern
Recommended pattern:
- `<Brand> — <Item Name> — <Key Spec>`

Examples:
- `Stryker — Bone Screw — 3.5mm`
- `Medtronic — Drill Bit — 2.0mm`

### 8.2 Variants
Rule:
- The distinguishing attribute must be in the Item Name (or Variant attributes).

If you use variants:
- Variant attributes should match what users naturally say (size, length, angle).

---

## 9) Surgery Set naming
This section defines names for surgery-set records so they are searchable.

### 9.1 Surgery Set Type
Recommended pattern:
- `<Specialty> — <Set Name> — v<Version>`

Examples:
- `Ortho — ACL Set — v1`
- `Neuro — Spine Set — v2`

Rule:
- If you change the composition significantly, bump the version.

### 9.2 Surgery Case
Recommended pattern for the human-readable title/subject fields:
- `<Client Code> — <Client Name> — <Date>`

Rule:
- Include the client.
- Include a date.

---

## 10) Tasks
Task naming must support:
- directors TV wallboard
- filtering/grouping
- fast scanning

### 10.1 Task subjects
Use the Subject patterns from Doc 10.

Rule:
- Always include at least one searchable identifier:
  - Surgery Case ID, Sales Order ID, Dispatch Group ID, or Hospital name.

### 10.2 Saved Task views (filters)
Recommended pattern:
- `<Team> — <Queue Name>`

Examples:
- `Delivery — Open Tasks`
- `Inventory — Open Tasks`
- `Directors — Wallboard (All Open)`

Rule:
- If it will be used by multiple people, save it as a shared view.

---

## 11) Users
Rule:
- Use real names for real people.

For shared/service users (rare):
- Use an explicit label:
  - `Directors TV`

---

## 12) Acceptance criteria
- New staff can find Tasks, Customers, Items, and Warehouses quickly by searching.
- Client location warehouses and customer names match and are consistently coded.
- Task subjects and saved views are consistent and usable for daily operations.
