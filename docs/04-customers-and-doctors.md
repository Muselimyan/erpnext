# Doc 04 — Master Data: Customers (Clients) (Operational)

## 1) Purpose
This document defines the operational rules for:
- Client master data (modeled as `Customer`)
- Capturing doctor + hospital + branch context without a separate Doctor master
- Mapping physical stock locations to warehouses using doctor-hospital-branch groups

It focuses on:
- Naming and coding
- Duplicate prevention
- Which fields are mandatory vs optional
- Ownership and governance (who can create/edit)
- Reporting implications

Non-goals:
- This document does not provide step-by-step ERPNext configuration.

---

## 2) Why master data quality matters
Clients are referenced everywhere:
- Sales Orders and Sales Invoices
- Surgery Cases (Doc 12)
- Per-client stock tracking and “company-owned at client location” visibility (Doc 05)
- Debt thresholds and director alerts (requirements)

If the same client exists multiple times (duplicates), then:
- your sales history splits across multiple records
- your debt and threshold controls become unreliable
- your operational reporting becomes misleading

---

## 3) Entities and what they represent
### 3.1 Clients are Customers
Decision (requirements + Doc 11/12 alignment):
- Every client you deliver to / bill is represented as a `Customer`.
  - In your reality, most clients are **doctors**.
  - A smaller number of clients are **hospitals** (where there is no named doctor).

Operational meaning:
- The client is the billing and receivables identity.
- Company-owned stock at the client location is tracked via a **client location warehouse** (Doc 05) and operational workflows (Doc 12).
  - This includes surgery cases and permanent on-site surgery sets (Doc 11).

### 3.2 No separate Doctor master
Decision:
- Do not maintain a separate doctor master record for go-live.

Operational meaning:
- If the client is a doctor, the doctor identity is the Customer.
- If the client is a hospital, you can still capture the doctor name on transactions as free text.

### 3.3 Client Location Groups (doctor + hospital + branch) are warehouses
Decision (new requirement):
- Each (doctor + hospital + hospital branch) group is a distinct physical location for company-owned stock and must have its own warehouse under `Clients - WH`.

Operational meaning:
- One client (doctor) can have multiple location warehouses (one per hospital/branch they operate at).
- Receivables and debt thresholds remain client-based (Customer), not warehouse-based.

---

## 4) Client master data rules (Customer)
### 4.1 Canonical client identity
A client should have:
- One canonical `Customer` record.
- One stable client code used for:
  - identifying the doctor/hospital portion of client location warehouse naming
  - searching
  - reporting filters

### 4.2 Naming and coding rules
Naming conventions reference Doc 02.

Recommended customer naming pattern:
- Customer Name (display): `<Client Code> — <Client Name>`

Examples:
- `D001 — Dr. A. Petrosyan`
- `H001 — Erebuni MC`

Rules:
- Client code must be stable.
- Do not change codes casually.
- If the client changes branding/name, keep the code and update only the descriptive name.

### 4.3 Branches and complex customers
Rule:
- Create separate Customer records only if they truly need separate:
  - billing/receivables
  - debt threshold
  - and/or operational identity

If a client has multiple locations:
- Do not create separate Customer records just because the same doctor operates in multiple hospitals/branches.
- Keep one Customer record and create separate **Client Location Group warehouses** for each doctor-hospital-branch combination.

### 4.4 Required fields (operational)
Minimum operational requirements:
- Official name (as known in the market)
- Client code (stored consistently and shown in the Customer Name)
- Payment terms behavior (most are credit)

Debt control requirement (from requirements):
- Every client should have a defined debt threshold (even if temporarily large).

### 4.5 Governance and ownership
Rules:
- Only authorized staff should create new clients.
- Once a client is active (has transactions), edits should be controlled.

Operational control:
- If a new client appears during a busy shift, the system must still support continuing work.
  - The recommended policy is:
    - order team can create a placeholder client only if the governance team approves later
    - or order team must request creation (depends on your capacity)

---

## 5) Capturing doctor + hospital context (no separate master)
This section replaces the old “separate doctor master” approach.

Rule:
- If you work directly with a doctor, the doctor is the `Customer`.

Additional data you may still want:
- Hospital context (where the surgery happens / where the delivery is going)
- Hospital branch context (which branch/location of the hospital)
- Doctor name (when the client is a hospital)

Recommended approach:
- Add optional fields on operational documents (Sales Order, Sales Invoice, Surgery Case):
  - `Hospital` (Link → Customer)
  - `Hospital Branch` (free text or controlled select)
  - `Doctor Name` (free text)

Governance note:
- Hospital records can be created only when needed.
- Avoid turning hospital into a required field everywhere; keep operations unblocked.

---

## 6) Linking rules (where hospital/doctor context must be recorded)
### 6.1 Surgery cases
Doc 12 uses:
- Client recorded on the Surgery Case
- Hospital + branch context recorded (required when the client is a doctor and the location warehouse is derived from doctor + hospital + branch)
- Optional doctor name recorded when the client is a hospital

Operational intent:
- The surgery case becomes the authoritative operational record for:
  - what was dispatched/returned/used
  - who/where it was for

### 6.2 Standard sales documents
Requirements require:
-- Sales Order: hospital context optional.
-- Sales Invoice: hospital context optional.

Operational rule:
- Hospital is always optional. Record it when it adds operational/reporting value.
- Hospital Branch is always optional for standard sales.

---

## 7) Reporting implications (what becomes possible)
If the rules above are followed, you can reliably report:

Client-level:
- Sales history per client
- Unpaid invoices and current debt per client
- Client debt threshold exceedances (director alerts)

Location-level (company-owned stock tracking):
- Stock currently at each doctor-hospital-branch location (derived from the corresponding location warehouse)

Optional hospital-level (when the Hospital field is filled):
- Sales history by hospital
- Operational WIP by hospital

---

## 8) Invariants and acceptance criteria
### 8.1 Invariants
- Every client has exactly one Customer record.
- Every active doctor-hospital-branch location used for company-owned stock tracking has:
  - exactly one location warehouse under `Clients - WH` (Doc 05)
- Creating a client under time pressure must not permanently degrade reporting quality (provisional + review process exists).

### 8.2 Acceptance criteria
- Staff can search and find a client quickly using code or name.
- Staff can choose the correct location warehouse for a doctor quickly (hospital + branch selection is not ambiguous).
- Reporting is consistent:
  - client debt is not split across duplicate Customers
