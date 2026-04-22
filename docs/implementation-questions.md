# Implementation Questions (Data Required to Fully Configure the System)

## Doc 03 / Doc 03A — Roles, Permissions, and Task Visibility

1) Staff/user list (by team)
- Question: What is the full list of staff who will have system access at go-live, and which team are they in?
- Data needed (per person): full name, login/username, team (Order Entry / Inventory / Delivery / Returns / Accounting / Directors), and whether they are a driver vs coordinator.

2) Driver role separation
- Question: Do we want a separate “Delivery Driver” role in addition to the Delivery team role?
- Current answer: Not finalized (recommended as optional).

Recommendation:
- Yes: create a separate `Delivery Driver` role with access to `Task` + attachments only (no Stock/Accounting permissions).

3) Task visibility map (policy access)
- Question: For each team, which task queues should they be able to see?
- Data needed: which of these task queues are visible per team:
  - Order entry
  - Pack / prepare items
  - Dispatch picking / hand-off
  - Delivery
  - Pickup Returns
  - Return drop-off at warehouse
  - Returns processing / verification
  - Invoice preparation / create invoice
  - Debt Collection
  - Discount Approval
  - Purchase Approval
  - Write-off Approval

4) Optional cross-visibility (explicit confirmations)
- Question: Should drivers see packing status tasks (read-only) to know when an order is ready?
- Current answer: Optional.

5) Returns team early visibility
- Question: Should the returns team see upcoming pickups/drop-offs so they can prepare for inbound returns?
- Current answer: Recommended baseline says “yes”, but confirm.

6) Task reassignment authority
- Question: See Doc 10 / Doc 10A — “Reassignment authority and audit note”.
- Current answer: Recommended: only coordinators/directors reassign.

7) Task creation discipline
- Question: See Doc 10 / Doc 10A — “Invisible tasks prevention rule” + “Visibility policy (Task Access Policy) structure”.
- Current answer: Not explicitly confirmed.

Recommendation:
- Enforce: every operational Task must have `task_kind` + `task_access_policy` set (preferably set by automation, not by users).
- Block saving/submitting Tasks without `task_access_policy` except for System Manager corrections.

8) Exact role catalog (names + whether any extra roles are needed)
- Question: Are these the final go-live roles (exact names), and do we need any additional ones?
- Data needed:
  - Confirm the five team roles:
    - `Ops - Order Accepting`
    - `Ops - Inventory`
    - `Ops - Delivery`
    - `Ops - Accounting`
    - `Ops - Directors`
  - Confirm whether we will create and use the optional role:
    - `Delivery Driver`
  - Confirm whether Delivery Coordinators need a separate role name (or they are simply users with `Ops - Delivery`).

9) Canonical Task Kind strings (exact spelling)
- Question: See Doc 10 / Doc 10A — “Task Kind catalog (canonical list and stability)”.

10) Task Access Policy structure (one-per-kind vs grouping)
- Question: See Doc 10 / Doc 10A — “Visibility policy (Task Access Policy) structure”.
- Current answer: Recommended one-per-kind.

11) Per-user Task Access Policy grants (concrete records)
- Question: See Doc 10 / Doc 10A — “Policy grants dataset (User Permission records)”.

12) Apply-user-permission filtering scope
- Question: For which operational roles should Task visibility be filtered by user-permissions?
- Current answer: Recommended enabling it for each operational role you want to restrict.

13) Completed task edit/correction policy
- Question: Should completed tasks ever be editable, and if yes, by whom and under what rules?
- Current answer: Recommended: only Directors/Coordinators for explicit corrections.

14) Maintenance rule for new Task Kinds
- Question: Who is responsible for maintaining the system when a new Task Kind is introduced?
- Data needed:
  - confirm the governance owner (name/role)
  - ensure they maintain the items defined in Doc 10 / Doc 10A (task kind catalog, policies, grants, completion enforcement)

---

## Doc 04 / Doc 04A — Customers (Hospitals) and Doctors

1) Hospital master list (go-live dataset)
- Question: What is the full list of hospitals we will transact with at go-live?
- Data needed (per hospital):
  - hospital legal/market name
  - hospital code (unique and stable)
  - whether it participates in surgery cases (if not all do)
  - billing identity notes (if special)

2) Hospital code scheme
- Question: What is the final hospital code format and numbering scheme?
- Data needed:
  - pattern (example: `H001`, `H002`, ...)
  - whether any existing codes must be preserved
  - how we handle newly added hospitals after go-live (next number rule)

3) Branch policy (when to create separate hospital records)
- Question: When a hospital has branches/locations, do we create separate records or keep one?
- Data needed:
  - list of hospitals with branches
  - for each branch: does it require separate billing/receivables and/or separate operational identity?

Recommendation:
- Keep **one** Customer per legal/billing entity.
- Create a **separate** Customer only if the branch has separate receivables/billing identity or must be treated as a distinct operational counterparty.

4) Debt threshold values per hospital
- Question: What is the debt threshold (AMD) for each hospital at go-live?
- Data needed:
  - threshold value per hospital (even if temporarily very high)
  - who owns future changes to thresholds

5) Hospital governance: who can create/edit hospitals
- Question: Who is allowed to create a new hospital record, and who is allowed to edit hospital master data after it is active?
- Data needed:
  - role(s) or named people who can create/edit
  - what the order-entry team does during a busy shift when a new hospital appears (create provisional vs request creation)

6) Hospital required fields (data completeness)
- Question: Which fields are mandatory at go-live for each hospital?
- Data needed (minimum recommended by Doc 04/04A):
  - hospital code
  - debt threshold (AMD)
  - payment behavior / terms note (most are credit)

7) Hospital contacts and addresses
- Question: Do we maintain hospital branches/contacts/addresses inside the hospital record (instead of making separate hospital records)?
- Data needed:
  - minimum required contact fields (phone, contact person)
  - whether multiple addresses must be tracked per hospital

Recommendation:
- Track multiple addresses/contacts under the same Customer record; do not create separate Customers just for multiple locations.

8) Doctor master list (go-live dataset)
- Question: Do we preload doctors at go-live, and if yes, what is the initial doctor list?
- Data needed (per doctor):
  - canonical doctor name
  - alternate spellings (if any)
  - (optional) known hospitals where they work

9) Doctor naming rules and de-duplication rules
- Question: What is the canonical naming format and how do we prevent duplicates?
- Data needed:
  - canonical format (example: `Last Name First Name (Initial)`)
  - whether we store alternate spellings in a dedicated field vs notes
  - who is responsible for periodic cleanup/merge of duplicates

10) Doctor ↔ hospital relationship (how strict)
- Question: Do we require linking doctors to hospitals, or is it optional?
- Current answer: Recommended optional (should not block saving a doctor).
- Data needed:
  - whether the relationship is used only for reporting, or also for validation/search filtering

11) Quick-add policy for doctors
- Question: What is the rule for creating doctors quickly during order entry, and who reviews provisional doctor records?
- Data needed:
  - which roles can quick-add
  - review cadence (daily/weekly)
  - designated owner for doctor data quality

12) Where we capture doctor on documents
- Question: Where should “Doctor” be selectable (surgery cases, sales orders, sales invoices)?
- Current answer: Doctor is optional everywhere; record it when known.
- Data needed:
  - confirm whether we add the optional Doctor field on Sales Order
  - confirm whether we add the optional Doctor field on Sales Invoice

13) Hospital warehouse linkage completeness
- Question: For every hospital record, do we confirm there is a matching hospital stock location (warehouse) created?
- Data needed:
  - confirm we use the same canonical scope rule as in Doc 05 / Doc 05A — “Hospital warehouse creation scope”
  - confirmation approach: for each hospital in the master list, verify a matching hospital warehouse exists under `Hospitals - WH`
  - who is responsible for creating it and verifying naming consistency

---

## Doc 05 / Doc 05A — Warehouses and Stock Rules

1) Warehouse tree (exact records)
- Question: Confirm the exact warehouse tree we will create at go-live (and which are group vs leaf).
- Data needed (record list):
  - `Main - WH` (leaf)
  - `Delivery In-Transit - WH` (leaf)
  - `Hospitals - WH` (group)
  - `Return Pickup In-Transit - WH` (leaf)
  - `Returns - WH` (leaf)
  - One hospital warehouse per hospital under `Hospitals - WH` (leaf)

2) Company suffix behavior for warehouse names
- Question: Will we accept ERPNext’s automatic company suffix on warehouse names (recommended), and what is the company abbreviation?
- Data needed:
  - company abbreviation value (as it will appear in names)
  - confirmation that staff training/search will use the visible base name

Recommendation:
- Accept the automatic company suffix (ERPNext standard) and keep company abbreviation short/stable.

3) Hospital warehouse creation scope
- Question: Which hospitals require a hospital warehouse at go-live?
- Data needed:
  - from the hospital master list (Doc 04 / Doc 04A), for each hospital: flag whether it needs a hospital warehouse (`yes/no`) and why (surgery flow / pending-return flow)
  - confirm whether standard-sales-only hospitals should have a hospital warehouse (default recommended: no)

4) Warehouse ownership/responsibility map (operational control)
- Question: Who is the responsible owner team for stock accuracy in each warehouse?
- Data needed (confirm or adjust):
  - `Main - WH`: Inventory team
  - `Delivery In-Transit - WH`: Delivery coordination (with Inventory correctness on packing)
  - Hospital warehouses: shared Ops responsibility (Delivery + Returns)
  - `Return Pickup In-Transit - WH`: Delivery team
  - `Returns - WH`: Returns/Inventory team

5) “Stuck in transit” definition
- Question: What does “too long” mean for stock sitting in in-transit warehouses?
- Data needed:
  - time threshold for `Delivery In-Transit - WH`
  - time threshold for `Return Pickup In-Transit - WH`
  - who is responsible for investigating and how escalation happens

Recommendation:
- `Delivery In-Transit - WH`: threshold = 24 hours (or “end of business day” if dispatch is same-day).
- `Return Pickup In-Transit - WH`: threshold = 24 hours.
- Escalation owner: Delivery Coordinator first; if unresolved next day → Ops lead / Directors.

6) Returns processing control (“only Returns Team moves stock out of Returns”)
- Question: Do we enforce that only the Returns Team can move stock out of `Returns - WH`?
- Current answer: Recommended.
- Data needed:
  - confirm yes/no
  - which role(s)/users are considered “Returns Team” for this purpose

7) Negative stock policy
- Question: Do we allow negative stock at go-live?
- Current answer: Recommended to keep negative stock disabled.
- Data needed:
  - confirm yes/no
  - if allowed: under what circumstances and who approves exceptions

8) Backdating policy (who can backdate and how far)
- Question: What is the controlled policy for backdated stock postings?
- Data needed:
  - which roles/users can backdate stock entries
  - maximum backdating window (hours/days)
  - whether backdating requires a mandatory reason/comment

Recommendation:
- Allow backdating only for Stock/Returns owners (no drivers).
- Default maximum window: 14 days.
- Require a mandatory reason/comment for any backdated posting.

9) Posting time truth rule for return pickups
- Question: When return pickup happens at time T but stock posting happens later, do we always backdate the pickup-related stock movement to time T?
- Current answer: Recommended/required by the operational model.
- Data needed:
  - confirm yes/no
  - who verifies that posting time matches pickup time

10) Stock movement guardrails (group warehouses)
- Question: How do we prevent stock transactions on group warehouses (like `Hospitals - WH`)?
- Data needed:
  - confirm “no transacting on group warehouses” is enforced by training only, or by permissions/validations

Recommendation:
- Enforce with permissions/validations (not training-only): prevent selecting group warehouses in Stock Entry via role restrictions and/or a validation script.

11) Initial stock loading method and scope
- Question: How will opening stock be loaded at go-live, and for which warehouses?
- Data needed:
  - method (e.g., opening stock entry / stock reconciliation approach)
  - which warehouse(s) will have opening stock (normally `Main - WH`)
  - whether any hospital warehouses start non-empty (usually should be empty at go-live)

Recommendation:
- Load opening stock only into `Main - WH`.
- Keep all hospital warehouses and in-transit warehouses empty at go-live.

12) Routine checks (operational discipline)
- Question: What is the daily/weekly routine to investigate quantities left in in-transit warehouses?
- Data needed:
  - frequency (daily/weekly)
  - responsible owner
  - what report/view is used
  - escalation steps if unresolved

---

## Doc 06 / Doc 06A — Item Catalog, Variants, and UOMs

1) Item Group (category) tree — exact structure
- Question: What is the final Item Group tree we will create at go-live?
- Data needed:
  - top-level groups (confirm which ones are used):
    - `Implants`
    - `Instruments / Tools`
    - `Consumables / Disposables`
    - `Accessories / Parts`
    - `Services / Non-Stock` (only if needed)
  - full list of sub-groups (specialty/product family)
  - maximum depth rule (confirm the target “2–4 clicks to family”)

2) Category depth and navigation rule (explicit)
- Question: What is the maximum allowed depth for the Item Group tree?
- Current answer: Target 2–4 clicks to reach the correct family.
- Data needed:
  - confirm the max depth number (example: max 4 levels)
  - who can create new groups and under what governance

Recommendation:
- Set max depth to 4 levels.
- Only Inventory/Purchasing lead (or Directors) can create new Item Groups.

3) Item master dataset — exact fields required per item/variant
- Question: What fields must be present for every sellable item at go-live?
- Data needed (minimum per item/variant):
  - Item Code (existing SKU/internal code; stable)
  - Item Name (human name)
  - Item Group (category)
  - Stock UOM
  - Sales UOM (if different)
  - Purchase UOM (if different)
  - Supplier (exactly one)
  - Tracking flags (none vs batch/expiry vs serial)
  - Barcode(s) (if using scanning)

4) Item Code strategy (SKU mapping)
- Question: Confirm the Item Code policy at go-live.
- Current answer: Keep Item Codes stable and compatible with existing SKUs.
- Data needed:
  - authoritative source of existing SKUs (export/file)
  - policy for items that do not have an existing SKU
  - whether you want an “old code” reference field if codes change later

5) Variant families list (which product families become templates)
- Question: Which product families will be modeled as variants (templates + variants) vs standalone items?
- Data needed:
  - list of variant-heavy families (e.g., screws, plates, nails, drill bits)
  - for each family: which attributes define a variant (diameter, length, angle, side, etc.)

6) Variant attribute catalog
- Question: What is the final list of Item Attributes we will create?
- Data needed (per attribute):
  - attribute name (include unit in name where applicable, e.g., `Diameter (mm)`)
  - allowed values list (finite, controlled)
  - whether values are numeric-like strings (e.g., `3.5`) or formatted (e.g., `3.5mm`)

7) Variant value lists (the big dataset)
- Question: What are the allowed values per attribute for go-live?
- Data needed:
  - the value tables for each attribute (diameters, lengths, angles, etc.)
  - any “do not stock” values (allowed but not kept in stock) vs truly not allowed

8) UOM master list
- Question: What UOMs do we need at go-live (avoid duplicates)?
- Data needed:
  - confirm which UOMs are used: `Nos`, `Box`, `Pack`, `Set`, `Pair` (and any others)
  - confirm preferred naming (e.g., `Nos` vs `PCS`)

9) UOM conversions (pack sizes)
- Question: For which items do we need conversions (buy in box, sell in piece)?
- Data needed (per converted item):
  - purchase UOM, stock UOM, sales UOM
  - exact conversion ratio
  - governance: who can change conversions

10) Pack-breaking classification (per category/item)
- Question: Which categories/items are `Never break packs` vs `Pack-breakable`?
- Current answer: Not finalized; tracked as open.
- Data needed:
  - the explicit list of pack-breakable categories/items
  - for each: the standard conversion policy that will be enforced

11) Quantity format rule
- Question: Do we allow fractional quantities for any items/UOMs?
- Current answer: Prefer integer quantities.
- Data needed:
  - confirm “no fractions” as a hard rule, or list the exceptions

12) Tracking policy per item (batch/expiry/serial)
- Question: For each item/variant, what tracking is required?
- Current answer: implants/consumables use batch+expiry where applicable; tools use serial where applicable.
- Data needed:
  - list of items requiring batch tracking
  - list of items requiring expiry tracking (subset of batch items)
  - list of items requiring serial tracking

13) Barcode dataset and scanning scope
- Question: Which operations will be barcode-first at go-live (receiving, picking, both)?
- Current answer: Barcode-first where possible.
- Data needed:
  - which items must have barcodes entered before go-live (high-volume and high-risk)
  - for each item: barcode value(s) (unit pack, outer carton, etc.)
  - policy for duplicates (a barcode must resolve to exactly one item/variant)

14) One supplier per item — mapping dataset
- Question: What is the supplier assignment per item/variant?
- Current answer: Exactly one supplier per item.
- Data needed:
  - supplier list (must exist)
  - item → supplier mapping for all items/variants

15) Item governance (who can create/change items)
- Question: Who is allowed to create new items, create variants, and change UOM/tracking flags?
- Data needed:
  - role(s)/names with create/write permissions
  - policy for deprecating/disabling items instead of deleting

16) Data import approach (bulk creation)
- Question: What is the authoritative source file(s) for initial catalog creation?
- Data needed:
  - item list export format (Excel/CSV)
  - who will own cleanup of duplicates and naming consistency

---

## Doc 07 — Suppliers and Procurement (Basic P2P)

1) Supplier master list (go-live dataset)
- Question: What is the full list of suppliers we buy from at go-live?
- Data needed (per supplier):
  - legal name (who issues invoices)
  - brand/trade name (if different)
  - country
  - primary contacts (name + email/phone)
  - any notes that affect ordering (MOQ, lead time, ordering channel)

2) Duplicate supplier rule (legal entities vs brand)
- Question: When a brand has multiple legal entities (e.g., “Europe” vs “GmbH”), do we model them as separate suppliers?
- Data needed:
  - which brands have multiple legal entities you pay
  - the rule for when to split vs keep one

Recommendation:
- Split suppliers by legal entity **only if** payments/invoices are issued by different legal entities (different bank account / invoice issuer / tax identity).
- If it is only a “brand” difference with the same invoice issuer, keep one Supplier.

3) Default purchase currency per supplier
- Question: What is the default purchase currency for each supplier?
- Current answer: mostly USD, sometimes EUR.
- Data needed:
  - supplier → default currency mapping
  - whether any supplier uses AMD or other currencies

4) Exchange rate source/process
- Question: How do we decide exchange rates for USD/EUR purchases (for accounting in AMD)?
- Data needed:
  - rate source (manual entry vs a chosen reference)
  - who is responsible for entering/approving the rate
  - whether you require the same rate across the whole document date

Recommendation:
- Use a single rate per document date (consistent across the document).
- Enter the rate manually by Accounting (with a consistent external reference like Central Bank rate), and allow Directors to override only with a reason.

5) Payment terms per supplier (operational defaults)
- Question: What are the typical payment terms per supplier?
- Current answer: mostly prepayment (commonly 100% advance); sometimes partial; rarely after receipt.
- Data needed:
  - supplier → payment terms default
  - whether partial payments are common for specific suppliers
  - whether any supplier allows post-receipt payments routinely

6) Prepayment handling method (implementation choice)
- Question: How will we record and track supplier prepayments in the system?
- Data needed:
  - whether prepayments are linked to POs, invoices, or both
  - who is allowed to create/submit payments
  - what evidence/attachment is required (bank transfer confirmation)

Recommendation:
- Record prepayments as Supplier advance payments (Payment Entry) and link to the eventual Purchase Invoice when available.
- Require attachment of bank transfer proof on the payment record.

7) Purchase approval rule details
- Question: Are all purchase orders approved by directors, or are there thresholds (amount/category/supplier) where approval differs?
- Current answer: director approval is required.
- Data needed:
  - confirm “always directors” vs threshold rules
  - list of director approvers and backup approver

8) PO change-after-approval policy (“minor edits”)
- Question: Do we allow any “minor edits” after approval without re-approval?
- Current answer: recommended re-approval for any change, unless you define a minor-edit policy.
- Data needed:
  - confirm strict re-approval vs minor-edit exception
  - if exception: define exactly which fields are allowed (e.g., notes) and which are not (qty/price/items)

9) Purchase Order identifiers and attachments
- Question: What references must be captured on the PO for auditability?
- Data needed:
  - who requested the PO (person/team)
  - justification reason (reorder vs ad-hoc vs replacement)
  - whether you attach proforma invoice / quotation / email thread

10) Receiving process ownership
- Question: Who is allowed to create/submit purchase receipts (receiving)?
- Data needed:
  - roles/users allowed
  - whether receiving always goes to `Main - WH` at go-live (current: yes)

11) Partial delivery behavior
- Question: When deliveries are partial, do we keep POs open by default until closed/cancelled?
- Data needed:
  - who decides to close/cancel remaining quantities
  - expected lead-time for “open remainder” before escalation

12) Batch/expiry/serial capture at receipt (data completeness)
- Question: For tracked items, what is the minimum required capture at receiving?
- Data needed:
  - which item categories require batch + expiry
  - which require serial
  - whether receipt is blocked if tracking data is missing

Recommendation:
- Block submission of receiving documents if required batch/expiry/serial info is missing for tracked items.

13) Supplier invoice entry rules
- Question: What exact supplier invoice data must accounting capture?
- Data needed:
  - supplier invoice number requirement
  - invoice date requirement
  - currency and exchange rate handling
  - whether invoice can be entered before receipt (allowed operationally)

14) Three-way match tolerance policy
- Question: What mismatches are acceptable between PO vs receipt vs invoice, and what must be escalated?
- Data needed:
  - acceptable variance rules (if any)
  - required escalation owner (Purchasing Lead vs Directors)
  - how credit notes/corrections are handled when mismatches occur

Recommendation:
- Start strict at go-live: no quantity or item mismatches allowed without Director approval.
- Escalation owner: Purchasing Lead first; Directors for approvals.

15) Supplier substitutions policy
- Question: If a supplier ships a different product than ordered, what is the policy?
- Current answer: do not silently accept as equivalent; treat as different item or reject/return.
- Data needed:
  - confirm strict policy
  - whether any substitutions are allowed at go-live (and if yes, list them)

16) Damaged/short shelf-life inbound exceptions
- Question: If received goods are damaged or have short shelf life, what is the operational handling?
- Data needed:
  - who can accept/reject
  - whether we need a temporary holding location/process (even if “no quarantine” is the default)

Recommendation:
- Do not mix questionable items into `Main - WH`.
- If this happens more than rarely, create a simple quarantine/hold warehouse; otherwise treat as an exception with Director approval + mandatory note + photos.

17) Returns to supplier (rare exception)
- Question: If we must return goods to a supplier, what minimum information must be tracked?
- Data needed:
  - who initiates and approves
  - required documentation to attach
  - whether we need a designated “return-to-supplier” stock location/process (or treat as manual exception)

Recommendation:
- Treat as an exception at go-live (no dedicated warehouse) but require:
  - Director approval
  - supplier RMA/reference (if any)
  - attached photos + supplier communication

---

## Doc 08 — Reorder System (Low Stock → PO per Supplier)

1) Reorder scope: which items participate
- Question: Which items/variants are included in reorder monitoring at go-live?
- Data needed:
  - confirm whether all stock items are included
  - list of exclusions (special order only, non-stock/service items, discontinued)

Recommendation:
- Include all Stock Items except discontinued and true non-stock/service items.
- Exclude special-order-only items explicitly (flagged list).

2) Category policy: threshold style per category
- Question: For each top-level category (and key sub-categories), which threshold style do we use?
- Current answer: Suggested: Min/Max for fast-moving consumables; ROP for specialized/implants.
- Data needed:
  - category → threshold style mapping:
    - Min/Max, or
    - Reorder Point (ROP) + Reorder Quantity

3) Threshold dataset per item/variant (the core go-live dataset)
- Question: What are the initial reorder parameters per purchasable item/variant?
- Data needed (per item/variant, depending on the chosen style):
  - Min and Max, or
  - Reorder Point and Reorder Quantity
  - and a “criticality” tag (optional but recommended)

4) Threshold coverage target per category
- Question: What coverage target do we aim for by category/supplier type?
- Current answer: Fast movers ~1 month; imports/longer lead time ~2–3 months.
- Data needed:
  - confirm these as defaults
  - list of categories/items that should deviate (very critical vs very expensive/slow)

5) Supplier lead time dataset
- Question: What lead time should we assume per supplier (or supplier class) for reorder planning?
- Data needed:
  - supplier → typical lead time (days/weeks)
  - supplier → variability risk (stable vs unstable)
  - any suppliers with MOQs or ordering cycles

6) “Committed demand” definition (what reduces net availability)
- Question: Which business documents/states count as committed demand for reorder math?
- Data needed:
  - whether open Sales Orders count (and which statuses)
  - whether surgery cases “Preparing/Dispatched” reserve stock (and which statuses)
  - whether draft documents count (usually no)

Recommendation:
- Count submitted Sales Orders not yet delivered as committed demand.
- Count Surgery Cases once they leave `Draft` (Preparing/Dispatch Picking/Dispatched) as committed demand.
- Do not count drafts.

7) “Expected inbound supply” definition (what increases net availability with inbound)
- Question: When do we consider supply as expected inbound?
- Data needed:
  - do we count approved POs as inbound (current: yes conceptually)
  - do we only count submitted/sent POs?
  - how we treat partial receipts (remaining quantity still inbound)

Recommendation:
- Count approved/submitted POs as expected inbound.
- Treat partially received POs as still inbound for the remaining quantity.

8) Warehouse/stock scope used in reorder math
- Question: Which stock locations count as sellable on-hand, and which are informational-only?
- Current answer: Sellable on-hand primarily in `Main - WH`; hospital/returns/in-transit are informational only.
- Data needed:
  - confirm this rule as strict
  - list of any exceptions (items that can be quickly pulled back from hospital stock)

9) Expiry-aware buying rules (for expiry-tracked items)
- Question: What is the expiry risk policy used during buying decisions?
- Data needed:
  - what counts as “expiring soon” (days/months)
  - whether buyers should exclude expiring-soon quantities from “available”
  - who approves over-buy that increases expiry/write-off risk

Recommendation:
- Define “expiring soon” = 6 months.
- Exclude expiring-soon quantities from “available” for reorder decisions.
- Directors approve any over-buy that would raise expiry/write-off risk.

10) Variant family reorder depth
- Question: For high-variant families (sizes/lengths), how many variants get explicit thresholds at go-live?
- Data needed:
  - list of variant families
  - per family: which variants are “core/most-used” and must have thresholds
  - policy for low-usage variants (order on demand vs small safety)

11) Surgery-case critical items list
- Question: Which items/variants are “surgery critical” and require higher service levels?
- Data needed:
  - list of critical items/variants
  - any “never out of stock” policy items

12) Governance: who can change thresholds and how we record reasons
- Question: How do we record changes to thresholds (who/when/why)?
- Current answer: Purchasing Leads own threshold changes.
- Data needed:
  - confirm the role(s)/names
  - where the reason is recorded (notes field, change log process)
  - whether directors must approve large threshold increases (optional)

13) Buyer operating cadence
- Question: What is the expected purchasing routine?
- Current answer: daily quick check + weekly deep review.
- Data needed:
  - who does the daily check
  - who does the weekly review
  - what time window (daily)
  - what constitutes “actionable today” vs “monitor only”

14) Emergency ordering policy
- Question: When an item is urgently needed, do we have any emergency override to director approval, or is director approval always required?
- Data needed:
  - confirm “always director approval” vs emergency override
  - if override exists: who can trigger it and what documentation is required

Recommendation:
- Keep director approval always required at go-live; allow “verbal approval” only if it is recorded in the PO notes with approver name.

15) Pull-back policy for stock that is ‘somewhere else’
- Question: In urgent cases, do we allow pulling back company-owned stock from hospitals/returns/in-transit to satisfy demand?
- Data needed:
  - confirm allowed/not allowed
  - who approves
  - how it is made explicit and traceable operationally

Recommendation:
- Allowed only with Delivery/Returns coordinator approval and explicit Stock Entry movement back to `Main - WH`.
- Do not “virtually allocate” hospital stock to new orders without physically moving it.

16) Reorder list output format
- Question: What should the reorder list show per item so decisions are explainable?
- Data needed (columns/fields):
  - sellable on-hand
  - committed demand
  - net available
  - threshold values (Min/Max or ROP/Qty)
  - expected inbound
  - supplier
  - suggested order quantity

---

## Doc 09 — Selling: Standard Orders (No Return Expected)

1) Customer payment terms dataset (standard sales)
- Question: What are the standard payment terms per hospital (credit days / typical behavior)?
- Data needed (per hospital or per group):
  - payment terms label
  - typical due days
  - whether partial payments are common

2) Partial payments and batched receipts (operational policy)
- Question: When a client pays one amount that does not map cleanly to invoice numbers, what is the policy?
- Data needed:
  - allocation SLA (same day vs weekly)
  - default allocation rule (oldest-first vs client-instructed)
  - who can allocate and who can change allocations after initial posting
  - whether long-lived advances/prepayments are allowed (and maximum time window if not)

3) Pricing model (price lists)
- Question: What is the pricing model at go-live?
- Data needed:
  - do you use one global base price list or multiple?
  - do you need client-specific price overrides (special prices) and how will you model them (tier vs per-client-per-item)?
  - if destination hospital affects price when the billing customer is a doctor: confirm yes/no and provide the rule
  - which items have fixed prices vs negotiated prices
  - who is allowed to change prices and how often

Recommendation:
- Start with one global base price list in AMD.
- Add a controlled **Price Override List** for negotiated/special prices (client-specific), instead of relying on manual rate edits.
- Use discount approval for truly ad-hoc discounts (not for long-lived negotiated pricing).

4) Price list dataset (go-live data)
- Question: What is the initial price list data source?
- Data needed:
  - authoritative file/export (Excel/CSV)
  - currency (AMD)
  - effective date policy (single go-live date vs history)

4.1) Price override dataset (go-live data)
- Question: What is the initial list of negotiated/special prices?
- Data needed:
  - which clients have overrides
  - for each override: client, item, special rate, and (optional) validity dates
  - whether overrides are allowed to be defined at a tier/group level (and the tier definitions)

5) Discount policy rulebook
- Question: What discount rules apply before a director approval is required?
- Current answer: Discount approval is a hard gate before delivery when required.
- Data needed:
  - thresholds (e.g., discount % or amount) that trigger approval
  - who can request/apply discounts
  - whether any “always-allowed” discounts exist

6) Discount approval evidence
- Question: Do we require a note/reason on every discount approval/rejection?
- Data needed:
  - mandatory reason yes/no
  - minimum reason format (free text vs predefined reasons)

Recommendation:
- Yes: require a reason for both approve and reject.
- Use free text at go-live; add predefined reasons later if needed.

7) Delivery proof policy (standard deliveries)
- Question: Do we require proof of delivery (photo/signature) for standard deliveries?
- Current answer: Optional policy (not required unless you choose it).
- Data needed:
  - option chosen: none / selective / always
  - if selective: which cases require proof (high value, new customers, disputes)

8) “Delivery completion” definition
- Question: What exactly counts as delivery completion in operations?
- Data needed:
  - is completion based on driver confirmation only, or coordinator confirmation too?
  - do we require any attachments (if proof policy is enabled)

9) Stock staging timing rule
- Question: What is the strict rule for when stock must be staged into `Delivery In-Transit - WH`?
- Current answer: Must be staged before the driver leaves.
- Data needed:
  - do we allow staging earlier (day before) and how do we prevent “stuck staging”?
  - who is responsible for clearing stale staging

10) In-transit aging thresholds (sales)
- Question: For standard sales, do we use the same “stuck in transit” threshold as Doc 05 / Doc 05A — “Stuck in transit definition”, or a different one?
- Data needed:
  - confirm same threshold vs provide a different threshold for standard sales
  - escalation owner (delivery coordinator vs inventory manager)

11) Invoicing timing
- Question: Do we always invoice after delivery, or are there cases where we invoice earlier?
- Current answer: Deliver first, invoice after delivery (baseline).
- Data needed:
  - confirm baseline
  - list of exceptions (if any)

11.1) Upfront payments (prepaid orders delivered later)
- Question: When a client pays upfront, do you require issuing a Sales Invoice immediately, or can you treat it as a customer advance and invoice after delivery?
- Data needed:
  - whether a Sales Invoice must be issued at payment time (legal/process requirement)
  - whether deposits/partial prepayments are allowed (or prepaid = 100% paid)
  - whether dispatch must be blocked until payment is recorded for prepaid orders

Recommendation:
- Minimal-change approach: record upfront money as a customer advance (Payment Entry), deliver later, then invoice after delivery and allocate the advance so the invoice becomes Paid immediately.

12) Partial delivery handling
- Question: If a delivery is partial, how do we operationally represent the remainder?
- Data needed:
  - whether the remaining quantity stays open on the order
  - whether invoice is split (invoice delivered only)
  - who decides cancel vs later delivery

Recommendation:
- Keep remaining qty open on the Sales Order.
- Invoice only delivered quantities.
- Cancel remainder only with coordinator/director approval + reason.

12) Order edits and cancellations (governance)
- Question: Who can edit/cancel standard sales orders and under what conditions?
- Data needed:
  - roles/users allowed
  - what changes require director review (if any)
  - required cancellation reason policy

Recommendation:
- Before staging/dispatch: Order Team can edit.
- After staging/dispatch: only Directors/Coordinators can amend/cancel, with mandatory reason.

12.1) Cancellation redirect flows (stock + tasks)
- Question: When an order is cancelled at different stages, what are the exact redirect rules?
- Data needed:
  - if cancelled after packing but before staging: do we require any special task updates (cancel packing vs reopen stock picking), or is cancelling the order + tasks enough?
  - if cancelled after staging/in transit: do we require a `Return to warehouse` task and a drop-off photo?
  - whether aborted-delivery packages must always go through `Returns - WH` before returning to `Main - WH`

Recommendation:
- Use a stage-dependent redirect matrix as defined in Doc 09.
- For cancellations after dispatch staging: require a driver return-to-warehouse step with photo evidence, then returns verification before items re-enter `Main - WH`.

13) Backdating exceptions (sales)
- Question: For standard sales documents, do we apply the same backdating policy as Doc 05 / Doc 05A — “Backdating policy (who can backdate and how far)”, or do we need sales-specific exceptions?
- Current answer: Backdating should be controlled and reviewable.
- Data needed:
  - confirm the same backdating window and roles apply
  - if sales differs: list the exception(s) and approval owner

14) Standard-sales returns (rare) — minimum policy
- Question: If a customer returns items after a standard sale, what is the minimum supported policy at go-live?
- Current answer: Treat as an exception workflow; ensure stock re-enters through controlled verification.
- Data needed:
  - do we allow returns only before invoicing, or also after invoicing?
  - if after invoicing: credit note/adjustment policy and approval owner
  - where returned stock goes first (e.g., `Returns - WH` for verification)

15) Mandatory fields on Sales Order / Sales Invoice
- Question: What fields must be mandatory for standard sales documents at go-live?
- Data needed:
  - confirm the doctor capture policy matches Doc 04 / Doc 04A — “Where we capture doctor on documents” and Doc 11/12 decisions (doctor optional vs required on Surgery Case)
  - confirm delivery date/time requirement on orders
  - any additional mandatory fields (salesperson, department, cost center)

16) Document numbering series
- Question: What numbering/series do you want for Sales Orders, Delivery/issue steps, and Sales Invoices?
- Data needed:
  - desired prefixes/format
  - whether numbering restarts yearly

17) Receivables visibility and follow-up
- Question: Who owns receivables follow-up for overdue invoices, and what is the escalation rule?
- Data needed:
  - accounting owner(s)
  - when it escalates to directors (beyond the debt threshold rule)

---

## Doc 10 / Doc 10A — Task System Foundations

1) Task Kind catalog (canonical list and stability)
- Question: Confirm the final Task Kind list (exact spelling) and commit to keeping it stable.
- Data needed:
  - confirm the canonical list:
    - `Order entry`
    - `Pack / prepare items`
    - `Dispatch picking / hand-off`
    - `Delivery`
    - `Pickup Returns`
    - `Return drop-off at warehouse`
    - `Returns processing / verification`
    - `Invoice preparation / create invoice`
    - `Debt Collection`
    - `Discount Approval`
    - `Purchase Approval`
    - `Write-off Approval`
  - confirm who is allowed to introduce a new Task Kind (governance owner)

2) Task status model (labels)
- Question: What exact statuses do you want to use, and which label do you choose for the “waiting for check” state?
- Current answer: Use consistent meanings; choose `Pending Review` or `Pending`.
- Data needed:
  - confirm the allowed statuses at go-live:
    - `Open`
    - `Working`
    - `Pending Review` or `Pending` (choose one)
    - `Completed`
    - `Cancelled`

3) Cancellation reason policy
- Question: When a task is cancelled, do we require a reason (mandatory) and where is it recorded?
- Data needed:
  - mandatory reason yes/no
  - field to store it (description/notes/custom field)

Recommendation:
- Require a cancellation reason (mandatory) stored in Task description/notes.

4) Mandatory Task fields (data completeness)
- Question: Which fields must be mandatory for all operational tasks?
- Current answer: Subject, Status, Assigned To, reference links where applicable.
- Data needed:
  - confirm “Assigned To is always required” vs allow unassigned tasks
  - confirm whether `task_kind` is required on every task (recommended: yes)

5) Standard link-back fields (records we will add to Task)
- Question: Confirm which link-back fields we must add to `Task` and which are required per Task Kind.
- Data needed (fields from Doc 10A):
  - `task_kind`
  - `dispatch_group_id`
  - `customer` (hospital)
  - `surgery_case`
  - `sales_order`
  - `sales_invoice`
  - `task_access_policy`
  - `pickup_photo`
  - `completed_at`

6) Dispatch Group ID format
- Question: What is the format for `Dispatch Group ID` and who generates it?
- Data needed:
  - format/pattern (example: date + driver + sequence)
  - uniqueness rule
  - when it is created (at dispatch planning vs at stock staging)

7) Attachment requirements per Task Kind
- Question: Which Task Kinds require mandatory attachments at go-live?
- Current answer: `Pickup Returns` requires a photo; `Delivery` proof is optional.
- Data needed:
  - confirm `Pickup Returns` photo is mandatory
  - decide whether any other tasks require photos/attachments (damage evidence, delivery proof)

8) Completion timestamp
- Question: Do we capture `completed_at` automatically when status becomes `Completed`?
- Current answer: Recommended yes.
- Data needed:
  - confirm yes/no
  - timezone/clock source assumptions (server time vs user time)

9) Assignment rules
- Question: Do we enforce “one task = one owner” for all operational tasks?
- Current answer: Yes.
- Data needed:
  - confirm no “team-owned tasks” at go-live
  - if exceptions exist: list them

10) Reassignment authority and audit note
- Question: Who can reassign tasks, and do we require a reassignment note?
- Current answer: Recommended: only coordinators/directors reassign; add a short note.
- Data needed:
  - exact roles/users allowed to reassign
  - mandatory reassignment reason yes/no

11) Visibility policy (Task Access Policy) structure
- Question: Do we create one Task Access Policy per Task Kind (recommended), and do we make `task_access_policy` read-only (set by automation)?
- Data needed:
  - confirm one-per-kind vs grouping
  - confirm read-only field vs editable

12) Policy grants dataset (User Permission records)
- Question: Which users get access to which Task Access Policies?
- Data needed:
  - user → list of policies mapping (including any “TV/dashboard” user)
  - confirm directors/coordinators see all policies

13) “Invisible tasks” prevention rule
- Question: What is the rule if a task is created without a `task_access_policy`?
- Data needed:
  - confirm “disallowed” (must always be set)
  - who monitors for tasks missing policy and fixes them

Recommendation:
- Disallow: block saving/submitting operational tasks without `task_access_policy`.
- Monitoring owner: Delivery Coordinator (for delivery/pickup), Returns Lead (for returns tasks), Accounting lead (for invoicing/debt tasks).

14) Team ownership completion enforcement
- Question: Confirm the mapping Task Kind → required role for completing tasks.
- Data needed:
  - confirm the final mapping (Doc 10A example) and role names used
  - confirm whether directors/coordinators are exempt for corrections

15) Read-only behavior for non-owning teams (strictness)
- Question: If someone can see a task (for visibility), should it still be editable or fully read-only?
- Data needed:
  - confirm “block only completion” vs “block all edits except owning team”
  - list of exemptions (directors/coordinators)

Recommendation:
- Block all edits except owning team; Directors/Coordinators can override for corrections.

16) Stage gates mapping per workflow
- Question: For each workflow, which tasks must be completed before the upstream document can move to the next stage?
- Current answer: Doc 10 lists baseline gates.
- Data needed:
  - per workflow (standard sales, surgery cases, procurement approvals):
    - stage → required Task Kind(s)
  - confirm whether `Return drop-off at warehouse` is used as a separate gate or merged into `Pickup Returns`

17) Due dates, SLAs, and overdue thresholds
- Question: Do we use Task Due Date / Planned Date, and what is “overdue” per Task Kind?
- Data needed:
  - whether due dates are required for delivery/pickup tasks
  - SLA thresholds per Task Kind (hours/days)
  - who monitors overdue tasks

Recommendation:
- Require due dates for Delivery and Pickup Returns tasks.
- Start with simple SLAs:
  - Delivery: same day
  - Pickup Returns: within 24 hours of scheduling
- Monitor overdue tasks via Delivery Coordinator daily.

18) Idempotency keys (prevent duplicate tasks)
- Question: What combination of fields uniquely identifies “the same task event” so we can update instead of duplicate?
- Data needed (typical):
  - `task_kind` + reference link (example: `surgery_case` or `sales_order`) + status not in (Completed/Cancelled)
  - whether `dispatch_group_id` participates in uniqueness

19) Driver experience scope
- Question: Do drivers see only Tasks, or do they also have read-only access to upstream records (Sales Order / Surgery Case)?
- Data needed:
  - confirm scope
  - if read-only upstream access is allowed: which DocTypes and fields

Recommendation:
- Drivers see Tasks only at go-live.
- If needed later, add read-only access to a minimal delivery summary (address/contact/notes) rather than full documents.

20) Reporting views and dashboard user
- Question: What are the required saved views/dashboards for day-to-day running?
- Data needed:
  - list of required task views (by user, by Task Kind, overdue)
  - overall reporting pack ownership and saved artifacts are defined in Doc 13 — “Go-live reporting pack scope (exact deliverables)”
  - whether you will use a dedicated TV/dashboard user
  - if yes: which task policies the TV user can see

---

## Doc 11 / Doc 11A — Surgery Set Model and Setup

1) Hospitals in scope for surgery-set flow
- Question: From the hospital master list (Doc 04 / Doc 04A), which hospitals participate in the surgery-set flow at go-live?
- Current answer: ~50 (estimate).
- Data needed:
  - for each hospital: flag `uses_surgery_set_flow` (`yes/no`)
  - classify hospitals as surgery-only vs mixed vs not in scope

2) Surgery Set Type list (go-live dataset)
- Question: What are the Surgery Set Types you want to define as templates?
- Data needed (per set type):
  - set name
  - set code (if used)
  - active/inactive flag
  - notes/packing hints

3) Set code / naming scheme
- Question: What is the format for `set_code` (if used), and does it need to be unique and stable?
- Data needed:
  - pattern and examples
  - who is responsible for maintaining set codes

4) Set template items dataset
- Question: For each Surgery Set Type, what is the default item list?
- Data needed (per template line):
  - item (exact Item/Variant)
  - default quantity
  - UOM (only if not derived from item)
  - is_optional flag (if used)

5) Template grouping fields (optional)
- Question: Do we add a grouping field on set template lines (tools vs screws vs plates, etc.)?
- Data needed:
  - confirm yes/no
  - if yes: the allowed group values list (controlled)

Recommendation:
- Yes: add grouping for readability and packing discipline (at least `Tools / Instruments` and `Implants / Consumables`; add more later if needed).

6) Return behavior classification (optional but recommended)
- Question: Do we classify each template line as “Expected Return (Tools)” vs “May Be Used (Implants)”?
- Data needed:
  - confirm yes/no
  - if yes: the exact allowed values
  - whether this classification is required for every line

Recommendation:
- Yes: require a return-behavior classification for every template line.

7) Variant selection policy inside sets
- Question: For size-based products (screws/plates/nails), do we always require selecting the exact variant item (not free-text size)?
- Current answer: Recommended yes.
- Data needed:
  - confirm yes/no
  - list of variant families used in surgery sets

8) Tracking classification per item used in surgery sets
- Question: For every item that can appear in surgery sets, what tracking is required (serial vs batch/expiry vs none)?
- Data needed:
  - reuse the tracking dataset from Doc 06 / Doc 06A — “Tracking policy per item (batch/expiry/serial)”
  - from that dataset: flag which tracked items appear in surgery sets (so we can enforce strict traceability in dispatch/returns)

9) Tool accountability strictness
- Question: For serial-tracked tools, do we enforce “case cannot close until all serials are accounted for (returned or marked missing/damaged)”?
- Current answer: Recommended yes.
- Data needed:
  - confirm yes/no
  - who can mark missing/damaged and what evidence is required

10) Recall reporting granularity
- Question: Do you need recall reporting by hospital only, or by hospital + surgery case?
- Data needed:
  - confirm target level
  - if by case: confirm we must link stock movements to the case consistently (so reporting can group by case)

Recommendation:
- By hospital + surgery case (higher traceability; helps investigations).

11) Returns path after verification
- Question: After items return, do they always go through `Returns - WH` before returning to sellable stock, or can some go directly back to `Main - WH`?
- Current answer: Model supports either; operations must decide.
- Data needed:
  - confirm the standard path
  - list any exceptions (e.g., clean sealed items direct to main)

Recommendation:
- Standardize: all returns go through `Returns - WH` for verification, then move to `Main - WH`.
- Avoid exceptions at go-live to keep accountability simple.

12) Hospital warehouse naming scheme consistency (Doc 11A vs Doc 02/05)
- Question: What is the canonical hospital warehouse naming scheme we will use everywhere?
- Data needed:
  - confirm whether the canonical pattern is:
    - `<Hospital Code> — <Hospital Name> - WH` (Doc 02/05), or
    - `HOSP - <Hospital Short Name> - WH` (Doc 11A)
  - if you keep both concepts: define exactly where each is used (recommended: pick one)

Recommendation:
- Use `<Hospital Code> — <Hospital Name> - WH` everywhere for consistency with the broader warehouse policy.

13) Hospital short name dataset (only if used)
- Question: If we use “Hospital Short Name” anywhere, what is the list per hospital?
- Data needed:
  - hospital → short name mapping
  - format rules (uppercase? Latin only?)

14) Master data dependencies required before set templates can be created
- Question: What must be in place before staff can create Surgery Set Types?
- Data needed:
  - item catalog completeness for set items/variants
  - UOM list
  - hospital list (if templates are hospital-specific)

15) Governance: who can create/edit set templates
- Question: Who is allowed to create and edit Surgery Set Types and their item lists?
- Data needed:
  - role(s)/names
  - change control rule (approval needed for changes? versioning?)

16) Basic customer master fields required by setup steps
- Question: What standard values do we use for Customer fields required in creation screens (Customer Group, Territory), if any?
- Data needed:
  - default Customer Group value
  - default Territory value

17) Doctor required vs optional (Doc 11 vs Doc 12A consistency)
- Question: On `Surgery Case`, is Doctor optional (recommended by Doc 11/Doc 12) or mandatory (Doc 12A currently marks it Req)?
- Data needed:
  - confirm required/optional
  - if optional: define how we handle “unknown doctor” at creation (leave empty vs placeholder Doctor record)
  - if required: confirm quick-add is enabled and define minimum required fields for quick-add

Recommendation:
- Make Doctor optional on `Surgery Case` to avoid blocking urgent case creation.
- If unknown, leave empty; do not use placeholder doctors.

---

## Doc 12 / Doc 12A — Surgery Set Operational Workflow (Surgery Case end-to-end)

1) Surgery Case naming/numbering series
- Question: What numbering/series format should `Surgery Case` use?
- Data needed:
  - prefix (example: `SC-`)
  - whether numbering restarts yearly
  - whether the ID must be readable on printed labels

2) Dispatch Group ID format (shared trip identifier)
- Question: Confirm Surgery Cases use the same `Dispatch Group ID` standard defined in Doc 10 / Doc 10A — “Dispatch Group ID format”.
- Data needed:
  - confirm we do not have a separate Dispatch Group ID format for surgery vs standard deliveries
  - if you want a separate format: provide both formats and define where each is used

3) Packaging/labeling standard (to allocate returns to the correct case)
- Question: What is the physical labeling rule for each packed set/package?
- Data needed:
  - label content (must include Surgery Case ID?)
  - whether labels are printed from ERPNext or handwritten
  - if multiple cases are in one pickup: how packages are kept separable

4) Go-live scope: Stock Entries per Surgery Case vs per Dispatch Group
- Question: For go-live, do we create Stock Entries per Surgery Case (simpler) or aggregate per Dispatch Group (more advanced)?
- Data needed:
  - decision for go-live
  - if aggregate: rules for linking multiple cases to one Stock Entry and how case-level batch/serial reporting works

Recommendation:
- Go-live: create Stock Entries per Surgery Case (simpler, clearer audit trail).

5) Hospital → hospital warehouse mapping method (source of truth)
- Question: Where do we store/derive the hospital warehouse used on Surgery Case?
- Data needed:
  - choose one:
    - derived from a strict naming rule, or
    - stored as a Link field on Customer (recommended for reliability)
  - responsible owner for keeping mapping correct

Recommendation:
- Store the hospital warehouse as an explicit Link field on Customer (source of truth), not derived from naming.

6) Final Surgery Case workflow states list
- Question: Are these the exact workflow states at go-live (spelling + order)?
- Data needed:
  - confirm list:
    - Draft
    - Preparing
    - Dispatch Picking
    - Dispatched
    - Delivered
    - Return Pickup Scheduled
    - Return Pickup In Transit
    - Returns Verification
    - Returns Received
    - Usage Derived
    - Invoiced
    - Closed
  - confirm whether you also need `Cancelled` (and who can cancel)

Recommendation:
- Add `Cancelled` (Directors/Coordinators only), to handle cases created by mistake or cancelled before dispatch.

7) Role model for Surgery Case workflow (reuse existing vs new roles)
- Question: Do we reuse the existing ops roles (`Ops - ...`) or create dedicated roles like `Surgery Case - Returns` as Doc 12A suggests?
- Data needed:
  - final role list and exact names
  - mapping: workflow transition → allowed role(s)
  - named users per role (go-live user list)

Recommendation:
- Reuse the existing `Ops - ...` roles for workflow permissions to reduce complexity, and keep a separate `Delivery Driver` role for drivers.

8) Field locking rules (what becomes read-only and when)
- Question: Confirm the locking rules on Case Items so the same data is not entered multiple times.
- Data needed:
  - confirm: `dispatched_qty` editable only in `Draft`
  - confirm: `returned_qty` editable only during returns receiving (which exact states?)
  - confirm whether anyone can override (Directors only?) and what audit trail is required

9) Driver access scope (Tasks-only policy)
- Question: Confirm the driver access scope for surgery cases matches Doc 10 / Doc 10A — “Driver experience scope”.
- Data needed:
  - confirm yes/no
  - if surgery differs from standard: define the extra read-only fields drivers need (and why)

10) Mandatory pickup photo evidence details
- Question: What exactly qualifies as valid pickup photo evidence?
- Data needed:
  - minimum number of photos (1 vs multiple)
  - what the photo must show (package label, hospital stamp, etc.)
  - whether you want:
    - one dedicated Attach field (simple), or
    - allow any Task attachments (more flexible)

Recommendation:
- Minimum 1 photo.
- Use one dedicated Attach field (`pickup_photo`) for enforcement simplicity.

11) Pickup completion timestamp truth source (used for backdating)
- Question: What timestamp do we treat as the authoritative pickup time for backdated stock posting?
- Data needed:
  - choose one:
    - Task completion time (when driver marks Completed)
    - a manual “Pickup Time” field set by coordinator
  - allowed correction policy if the timestamp is wrong

Recommendation:
- Use Task `completed_at` as the pickup truth timestamp; allow correction only by Coordinators/Directors with a mandatory note.

12) Backdating policy for return pickup Stock Entry (Option A)
- Question: Confirm return-pickup backdating follows Doc 05 / Doc 05A — “Backdating policy” + “Posting time truth rule for return pickups”, and specify any stricter rules for pickups.
- Current answer: Option A is intended (driver does Task only; Returns Team posts Stock Entry later with posting date/time set to pickup time).
- Data needed:
  - confirm pickups must be posted at pickup time (time T)
  - confirm the same backdating window/roles apply, or specify a stricter pickup window
  - whether backdating requires a mandatory reason/comment

13) Return Stock Entries design: where serial/batch is captured
- Question: On returns, in which Stock Entry(ies) do we require serial/batch selection, and do we auto-copy details between them?
- Data needed:
  - confirm whether serial/batch must be captured on:
    - hospital → Return Pickup In-Transit, and/or
    - Return Pickup In-Transit → Returns
  - if only one: which one, and whether the other is auto-generated without serial/batch detail

Recommendation:
- Capture serial/batch on the first (hospital → Return Pickup In-Transit) entry, since it is backdated to pickup time.
- The second transfer can be auto-generated and should preserve the same serial/batch where applicable.

14) Consumption posting approach (stock vs invoice)
- Question: Do we post stock consumption via a separate Stock Entry (Material Issue) as Doc 12 recommends, or do we let Sales Invoice update stock?
- Data needed:
  - decision (one must be standard)
  - if separate consumption Stock Entry:
    - who submits it
    - posting time rule
  - if invoice updates stock:
    - do we require batch/serial on invoices (usually heavy)

Recommendation:
- Use a separate Consumption Stock Entry (Material Issue) and set Sales Invoice to not update stock (simplifies invoicing while keeping batch recall via stock ledger).

15) Batch consumption allocation rule
- Question: For batch-tracked items, how do we allocate “used by batch” when consumption is derived as delivered − returned?
- Data needed:
  - confirm strict rule: consume the same batches that were delivered (net of returns)
  - what to do if returns team did not capture batch numbers correctly (block invoicing vs allow manual fix)

Recommendation:
- Strict: block invoicing if batch capture is inconsistent.
- Fix must happen by correcting return batch selection before proceeding.

16) Tool accountability exceptions dataset
- Question: For missing/damaged tools (serial-tracked), do we require recording the exact serial numbers that are missing/damaged?
- Data needed:
  - confirm yes/no
  - if yes: exception types list (Missing/Damaged/etc.) and who can record them
  - whether photo evidence is required for damaged tools

Recommendation:
- Yes: require recording serial numbers for missing/damaged tools.
- Require a photo for damaged tools where possible.

17) Lost/damaged commercial policy
- Question: Are lost/damaged items invoiced to the hospital, written off internally, or escalated for director decision?
- Data needed:
  - policy by category (tools vs implants)
  - who approves charging the hospital
  - required evidence/notes

Recommendation:
- Implants/consumables: invoice the hospital for lost items by default.
- Tools/instruments: escalate to Directors for a decision (case-by-case).

18) Multi-trip return pickups (support requirement)
- Question: Do we need to support a single Surgery Case being returned in multiple pickup trips at go-live?
- Data needed:
  - frequency expectation (rare vs common)
  - if needed: do we model multiple pickup tasks + multiple return stock entries per case (requires a child table of return events)
  - if not needed: confirm “one pickup per case” as a go-live constraint

Recommendation:
- Go-live constraint: one pickup per case.
- If partial returns happen, keep the pickup task open and do not move the case forward until the final pickup is completed.

19) Additional dispatch after initial delivery (edge case policy)
- Question: If extra items are sent later for the same surgery, do we amend the same case or create a new case?
- Data needed:
  - chosen policy
  - who approves/records the change

Recommendation:
- Create a new Surgery Case for additional dispatches (simpler audit + fewer automation edge cases).

20) Debt-threshold automation specifics
- Question: How exactly do we compute “outstanding debt” for threshold comparison?
- Data needed:
  - do we use Customer `Outstanding Amount` as-is, or a custom formula
  - do we include/exclude:
    - draft invoices
    - credit notes
    - customer advances
  - task assignment rule (which director(s) receive it)

Recommendation:
- Use ERPNext outstanding from submitted Sales Invoices (exclude drafts).
- Include credit notes/returns (they reduce debt).
- Subtract customer advances where applicable.

21) Debt Collection task uniqueness/idempotency key
- Question: What uniquely identifies the debt-collection Task so the scheduler updates instead of duplicating?
- Data needed:
  - align with Doc 10 / Doc 10A — “Idempotency keys (prevent duplicate tasks)” (debt task is a Task Kind)
  - choose one:
    - a `customer` Link field on Task + open status, or
    - subject naming convention only

Recommendation:
- Add a `customer` Link field to Task and use it as the idempotency key (one open Debt Collection task per hospital).

22) Delivery proof policy for surgery dispatch (separate from pickup)
- Question: Do we require proof-of-delivery photo/signature for surgery set deliveries?
- Data needed:
  - none / optional / always
  - if required: what evidence and where it is stored (Task attachments vs dedicated field)

Recommendation:
- Optional at go-live; consider enabling for high-value deliveries later.

23) Language/UX for drivers (practical data)
- Question: What device/app flow will drivers use (web browser, ERPNext mobile, etc.) and what constraints exist?
- Data needed:
  - preferred language (EN/RU/AM)
  - typical photo sizes and whether upload limits are a concern
  - whether offline operation is needed (usually no)

---

## Doc 13 — Reporting Pack (Operational)

1) Go-live reporting pack scope (exact deliverables)
- Question: Which views must exist as saved artifacts at go-live (Saved Report / Dashboard / Workspace / Saved Filter), and which can be “run ad-hoc”?
- Data needed:
  - list of required saved artifacts (by name)
  - who owns each artifact (role/person)
  - who can edit each artifact (governance)

2) Report naming conventions
- Question: What naming convention do we use so users can quickly find the correct report?
- Data needed:
  - prefixes per audience (example: `OPS -`, `DIR -`, `ACC -`, `BUY -`)
  - language choice for report titles (EN/RU/AM)

Recommendation:
- Use prefixes `DIR -`, `OPS -`, `ACC -`, `BUY -`.
- Use one language consistently for report titles (recommend EN for technical consistency).

3) Refresh rhythm (manual vs scheduled)
- Question: Which reports must be “real-time”, and which can be refreshed daily/weekly?
- Data needed:
  - per report: target refresh cadence (real-time / hourly / daily / weekly)
  - whether any scheduled snapshots are needed (optional)

Recommendation:
- Treat dashboards/reports as real-time (ERPNext data is live). Add scheduled snapshots only later if you need KPI history.

4) Thresholds used by “red flags” (hard numbers)
- Question: What exact thresholds define “too long” and “stuck” for operational warehouses and cases?
- Data needed:
  - use the same in-transit thresholds defined in Doc 05 / Doc 05A — “Stuck in transit definition”
  - `Returns - WH` backlog threshold (days or qty/value)
  - Surgery Case status aging thresholds (per status bucket)

5) Drill-down requirements (investigation)
- Question: For each report, what must the user be able to click into to investigate root cause?
- Data needed:
  - per report: required drill-down links (Task, Stock Entry, Sales Invoice, Surgery Case)
  - minimum columns required for investigation (document ID, posting date/time, owner, assignee)

6) Access control (who can see what)
- Question: Which roles/users can access each report/dashboard?
- Data needed:
  - mapping: audience (Directors/Ops/Returns/Accounting/Buying/Drivers) → report access
  - whether drivers see any reporting views at all (recommended: none)

Recommendation:
- Drivers: no reporting.
- Ops/Returns: stock/transit/returns backlog.
- Accounting: receivables + invoicing lag.
- Buying: reorder/low-stock.
- Directors: all.

7) Hospital warehouse scope for reporting
- Question: Confirm the authoritative warehouse subtree used for “company-owned at hospitals pending return”.
- Data needed:
  - see Doc 05 / Doc 05A — “Warehouse tree (exact records)” and “Hospital warehouse creation scope”
  - confirm standard sales never move stock into hospital warehouses (already decided; re-confirm for reporting consistency)

8) Items currently at each hospital (pending return)
- Question: What are the default filters and required columns for the “Hospital Stock” view?
- Data needed:
  - default sorting/grouping (by item group? by item code?)
  - whether to show:
    - qty only, or
    - qty + valuation (optional)
  - whether to include batch/serial breakdown (for tools/implants)

9) Items currently in delivery transit (outgoing)
- Question: What is the default display for `Delivery In-Transit - WH` (risk scan)?
- Data needed:
  - group by item vs group by document (Stock Entry)
  - whether to show age (time since posting) and the exact aging buckets

10) Items currently in return pickup transit (incoming)
- Question: What is the default display for `Return Pickup In-Transit - WH` and what must it link to?
- Data needed:
  - required drill-down: pickup task, dispatch group, surgery case(s)
  - age display and thresholds

11) Returns backlog (items waiting in `Returns - WH`)
- Question: How do we measure backlog: by qty, by number of packages/cases, or by value?
- Data needed:
  - chosen backlog metric(s)
  - thresholds for escalation
  - who owns backlog monitoring

Recommendation:
- Track backlog by qty + number of cases.
- Escalate if items remain in `Returns - WH` > 2 business days.

12) Items currently with each delivery person (derived view)
- Question: What is the authoritative “assignment link” used to derive in-transit stock by delivery person?
- Data needed:
  - choose one primary derivation method:
    - Task assignee via `dispatch_group_id`, or
    - fields on Stock Entry, or
    - explicit dispatch assignment record (custom)
  - if multiple tasks exist for the same dispatch group: precedence rule
  - how to handle unassigned in-transit stock (escalation)

Recommendation:
- Use Task assignee via `dispatch_group_id` as the primary derivation method at go-live.

13) Aging of open Surgery Cases (WIP)
- Question: What is the target cycle time per Surgery Case stage, and which stages must be highlighted as overdue?
- Data needed:
  - per workflow state: expected max age (hours/days)
  - definition of “open” (which states count)
  - required columns: hospital, surgery date, current state, last modified, assigned delivery person, next task

14) Unpaid invoices and aging
- Question: What aging buckets do you want for receivables reporting?
- Data needed:
  - bucket definition (example: 0–30, 31–60, 61–90, 90+ days)
  - whether to show by invoice date or due date (if payment terms are configured)
  - who monitors and how often

Recommendation:
- Buckets: 0–30 / 31–60 / 61–90 / 90+.
- Use due date if payment terms are configured; otherwise invoice date.

15) Hospitals exceeding debt threshold
- Question: Confirm the threshold report uses the same “outstanding debt” formula defined in Doc 12 / Doc 12A — “Debt-threshold automation specifics”.
- Data needed:
  - confirm one shared formula across automation + reporting
  - what happens if threshold is empty (ignore vs use company default)

16) Open Debt Collection tasks (one-per-hospital integrity)
- Question: What does the canonical debt task show so directors can act without opening many documents?
- Data needed:
  - required task fields/columns (hospital, current_debt, threshold, last payment date if available)
  - rule for auto-closing tasks (never vs optional auto-close when below threshold)

17) Sales history per hospital and per doctor
- Question: What exact dimensions must be available for sales history analysis?
- Data needed:
  - per hospital: by item, by item group, by month
  - per doctor (when recorded): same breakdowns
  - completeness target for doctor capture (optional field by policy):
    - which hospitals require it most
    - acceptable % missing

18) Low stock list by supplier
- Question: What exact columns and grouping are required for the purchasing view?
- Data needed:
  - reuse the reorder list columns from Doc 08 — “Reorder list output format” (add supplier grouping on top)
  - grouping by supplier must match Doc 06 / Doc 06A — “One supplier per item — mapping dataset” (confirm no exceptions)
  - sellable-on-hand warehouse scope must match Doc 08 — “Warehouse/stock scope used in reorder math” (expected: `Main - WH` only)

19) Cross-check report: in-transit stuck check
- Question: What is the required output list for “stuck in transit” investigation?
- Data needed:
  - include warehouse, item, qty, posting age, linked Stock Entry, linked Task (if any), assigned person
  - escalation owner per warehouse

20) Cross-check report: hospital stock vs open cases
- Question: How do we detect “stock at hospital but no open case” and what are the acceptable exceptions?
- Data needed:
  - definition of “no open case” (which statuses count)
  - acceptable exception list (if any)
  - who owns investigation

Recommendation:
- Treat any stock at hospital with no open case as an exception that must be investigated.
- Allow exceptions only for explicitly approved “loan/consignment-like” situations (if you ever introduce them later).

21) Cross-check report: traceability completeness for tracked items
- Question: Do we want a report that lists Stock Entry rows for serial/batch-tracked items with missing identifiers?
- Data needed:
  - confirm yes/no
  - which document types are in scope (Stock Entry only vs include Purchase Receipt / Delivery Note)
  - who monitors and cadence

Recommendation:
- Yes.
- Start with Stock Entry only.
- Monitor weekly by Inventory/Returns lead.
