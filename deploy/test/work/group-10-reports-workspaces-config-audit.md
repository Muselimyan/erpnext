# Group 10: Reports, Workspaces, and Configuration — Audit Findings

> **Scope**: 49 reports, 22 workspaces, 209 property setters, 1 workflow, 1 print format, 6 role profiles, 5 notifications, 1 client script (Workspace.js).
>
> **Sources**: `deploy/test/schema/*.json` (all 11 files), `deploy/test/work/client/Workspace.js`
>
> **Reference docs**: 13 (Reporting Pack), 13A (Reporting Pack Implementation), 15 (Reporting Requirements Review), 15A (Reporting Requirements Implementation), 03/03A (Roles), docs-overview.md
>
> **Analyzed**: 2026-08-27

---

## Executive Summary

| Metric | Value |
|---|---|
| Reports analyzed | 49 |
| Reports documented and matching | 38 |
| Reports duplicated (same purpose, two copies) | 8 (4 duplicate pairs) |
| Reports referencing superseded DocTypes | 1 |
| Reports documented but missing from prod | 3 (KPI dashboards) |
| Workspaces analyzed | 22 (3 custom, 19 standard) |
| Workspace shortcuts vs doc spec mismatches | 8 |
| Property setters analyzed | 209 (156 system-generated, 53 custom/intentional) |
| Property setters undocumented | 53 (all custom ones) |
| Workflow deployed on superseded DocType | 1 (Surgery Case Workflow — active!) |
| Role profiles for InMED custom roles | 0 (all 6 are ERPNext defaults) |
| Notifications for InMED operations | 0 (all 5 are system/ERPNext defaults) |
| Print formats relevant to InMED | 0 (IRS 1099 is US tax form) |
| Findings total | 29 |
| Critical | 0 |
| High | 5 |
| Medium | 14 |
| Low | 10 |

---

## 1. Reports — Complete Inventory

### 1.1 Report-to-Documentation Mapping

Every report deployed in production, mapped to its documentation source. Confidence scores indicate certainty of the mapping.

#### Stock Reports (16)

| # | Report Name | Ref DocType | Doc Source | Status | Confidence |
|---|---|---|---|---|---|
| 1 | RPT - Stock - Client Locations (All) | Bin | Doc 13 §4.1, Doc 13A | Match | 95% |
| 2 | RPT - Stock - Delivery In-Transit | Bin | Doc 13 §4.2, Doc 13A | Match | 95% |
| 3 | RPT - Stock - Delivery In-Transit - Inmed | Bin | Undocumented | Company-specific variant of #2 | 85% |
| 4 | RPT - Stock - Return Pickup In-Transit | Bin | Doc 13 §4.3, Doc 13A | Match | 95% |
| 5 | RPT - Stock - Return Pickup In-Transit - Inmed | Bin | Undocumented | Company-specific variant of #4 | 85% |
| 6 | RPT - Stock - Returns | Bin | Doc 13 §4.4, Doc 13A | Match | 95% |
| 7 | RPT - Stock - Returns - Inmed | Bin | Undocumented | Company-specific variant of #6 | 85% |
| 8 | RPT - Stock - In-Transit Stuck (Age Check) | Stock Ledger Entry | Doc 13A | Match | 95% |
| 9 | RPT - Stock - Balance Multi-Select | Bin | Doc 15 §5.1, Doc 15A | Match | 95% |
| 10 | RPT - Stock - Batch and Expiry Balance | Stock Ledger Entry | Doc 15 §5.2, Doc 15A | Match | 95% |
| 11 | RPT - Stock - Expiry Classification | Item | Doc 15 §5.3, Doc 15A | Match | 95% |
| 12 | RPT - Stock - Entries by Period | Stock Entry | Doc 15 §5.4, Doc 15A | Match | 95% |
| 13 | RPT - Stock - Warehouse Movement | Stock Entry | Doc 15 §5.5, Doc 15A | Match | 95% |
| 14 | RPT - Stock - Near Expiry (Main - Inmed) | Stock Ledger Entry | Doc 13 §4.13, Doc 13A | Match | 95% |
| 15 | RPT - Stock - Near Expiry Value at Risk | Stock Ledger Entry | Doc 15 §9.2, Doc 15A | Match | 95% |
| 16 | RPT - Stock - Slow-Moving Products | Bin | Doc 15 §9.1, Doc 15A | Match | 95% |

#### Sales Reports (8)

| # | Report Name | Ref DocType | Doc Source | Status | Confidence |
|---|---|---|---|---|---|
| 17 | RPT - Sales - Sold Items Detail | Sales Invoice | Doc 15 §6.1, Doc 15A | Match | 95% |
| 18 | RPT - Sales - History by Client | Sales Invoice | Doc 13 §4.10, Doc 13A | Match | 95% |
| 19 | RPT - Sales - Top Customers | Sales Invoice | Doc 15 §8.1, Doc 15A | Match | 95% |
| 20 | RPT - Sales - Top Products | Sales Invoice | Doc 15 §8.1, Doc 15A | Match | 95% |
| 21 | RPT - Sales - Comparative Periods | Sales Invoice | Doc 15 §8.3, Doc 15A | Match | 95% |
| 22 | RPT - Price Override List | Item Price | Doc 13 §4.10A | Match | 90% |
| 23 | RPT - Pricing - Sales Orders With Manual Rate Edits | Sales Order | Doc 13A, Doc 15 §9.4 | Match | 90% |
| 24 | RPT - Items by Delivery Person | Task | Doc 13 §4.5 | Match | 90% |

#### Accounting / Debt Reports (8)

| # | Report Name | Ref DocType | Doc Source | Status | Confidence |
|---|---|---|---|---|---|
| 25 | RPT - Accounting - Debt Status Board | Sales Invoice | Doc 15 §6.4, Doc 15A | Match | 95% |
| 26 | RPT - Accounting - Income by Period | Sales Invoice | Doc 15 §6.5, Doc 15A | Match | 95% |
| 27 | RPT - Accounting - Sales Documents and Payments | Sales Invoice | Doc 15 §6.2, Doc 15A | Match | 95% |
| 28 | RPT - Receivables - Unpaid Invoices (Aging) | Sales Invoice | Doc 13 §4.7, Doc 13A | Match | 95% |
| 29 | RPT - Receivables - Unallocated Advances | Payment Entry | Doc 13 §4.7A, Doc 13A | Match | 95% |
| 30 | RPT - Risk - Debt Threshold Exceeded | Customer | Doc 13 §4.8, Doc 13A | Match | 95% |
| 31 | RPT - Clients Exceeding Debt Threshold | Customer | Doc 13 §4.8 | **DUPLICATE** of #30 | 95% |
| 32 | RPT - Unallocated Customer Advances | Payment Entry | Doc 13 §4.7A | **DUPLICATE** of #29 | 95% |

#### Dispatch / Operations Reports (5)

| # | Report Name | Ref DocType | Doc Source | Status | Confidence |
|---|---|---|---|---|---|
| 33 | RPT - Dispatch Cases - Aging (Open) | Dispatch Case | Doc 13 §4.6, Doc 13A | Match | 95% |
| 34 | RPT - Dispatch Case Aging | Dispatch Case | Doc 13 §4.6 | **DUPLICATE** of #33 | 95% |
| 35 | RPT - Ops - Driver Task Queue (Derived) | Task | Doc 13 §4.5, Doc 13A | Match | 95% |
| 36 | RPT - Ops - Client Stock With No Open Cases | Warehouse | Doc 13A | Match | 90% |
| 37 | RPT - Surgery Cases - Aging (Open) | Surgery Case | (superseded) | **LEGACY** | 95% |

#### Purchasing Reports (4)

| # | Report Name | Ref DocType | Doc Source | Status | Confidence |
|---|---|---|---|---|---|
| 38 | RPT - Purchasing - Norm and Reorder | Item | Doc 15 §7.1, Doc 15A | Match | 95% |
| 39 | RPT - Purchasing - Supplier Performance | Purchase Order | Doc 15 §9.8, Doc 15A | Match | 95% |
| 40 | RPT - Item - Nomenclature and Prices | Item | Doc 15 §7.2, Doc 15A | Match | 95% |
| 41 | RPT - Item - Sort and Classify | Item | Doc 15 §5.6, Doc 15A | Match | 95% |

#### Prepaid / Returns Reports (4)

| # | Report Name | Ref DocType | Doc Source | Status | Confidence |
|---|---|---|---|---|---|
| 42 | RPT - Ops - Prepaid Orders Awaiting Delivery | Sales Order | Doc 13 §4.7B, Doc 13A | Match | 90% |
| 43 | RPT - Prepaid Orders Awaiting Delivery | Dispatch Case | Doc 13 §4.7B | **DUPLICATE** of #42 (different DocType!) | 90% |
| 44 | RPT - Returns - Refund Queue | Sales Invoice | Doc 15 §6.6, Doc 15A | Match | 90% |
| 45 | RPT - Collection Set Readiness | Item | Doc 13 §4.12 | Match | 90% |

#### Data Quality Reports (3)

| # | Report Name | Ref DocType | Doc Source | Status | Confidence |
|---|---|---|---|---|---|
| 46 | RPT - Data Quality - Missing Doctor or Hospital | Sales Invoice | Doc 15 §9.5, Doc 15A | Match | 95% |
| 47 | RPT - Data Quality - Negative Stock | Bin | Doc 15 §9.6, Doc 15A | Match | 95% |
| 48 | RPT - Data Quality - Tracked Items Missing Identifiers | Stock Entry | Doc 13A, Doc 15 §9.3, Doc 15A | Match | 95% |

#### Low Stock (1)

| # | Report Name | Ref DocType | Doc Source | Status | Confidence |
|---|---|---|---|---|---|
| 49 | RPT - Low Stock by Supplier | Item | Doc 13 §4.11 | Match | 90% |

### 1.2 Duplicate Report Pairs

Four pairs of reports serve the same purpose. In each case, one was created during the Doc 13A deployment (2026-05-08 to 2026-05-18), and the other during the Doc 15A/expanded deployment (2026-06-16). The newer version typically has broader role access and sometimes references a different DocType.

| Pair | Report A (older) | Report B (newer) | Difference |
|---|---|---|---|
| 1 | RPT - Risk - Debt Threshold Exceeded (2026-05-08) | RPT - Clients Exceeding Debt Threshold (2026-06-16) | B has a more detailed SQL (includes Net Debt and Excess Amount calculations); B has broader roles. Both active. |
| 2 | RPT - Receivables - Unallocated Advances (2026-05-08) | RPT - Unallocated Customer Advances (2026-06-16) | B appears to be a re-deployment with expanded roles. Both active. |
| 3 | RPT - Dispatch Cases - Aging (Open) (2026-05-12) | RPT - Dispatch Case Aging (2026-06-16) | B has a longer query (1248 chars vs 326 chars) suggesting richer columns. Both active. |
| 4 | RPT - Ops - Prepaid Orders Awaiting Delivery (2026-05-08, ref: Sales Order) | RPT - Prepaid Orders Awaiting Delivery (2026-06-16, ref: Dispatch Case) | B references Dispatch Case instead of Sales Order — reflecting the architectural shift from SO to DC. The older one may be stale. |

### 1.3 Reports Documented But Missing from Production

Doc 15A claims these exist, but they are **not present** in the 49 deployed reports:

| Report | Doc Source | Status | Confidence |
|---|---|---|---|
| RPT - KPI - Daily Dashboard | Doc 15 §8.4, Doc 15A | **MISSING** | 95% — searched all 49 report names, no match |
| RPT - KPI - Weekly Dashboard | Doc 15 §8.4, Doc 15A | **MISSING** | 95% |
| RPT - KPI - Monthly Income and Profit | Doc 15 §8.4, Doc 15A | **MISSING** | 95% |

These may have been implemented as dashboard charts or workspace number cards rather than Query Reports. However, the Management - KPI Dashboard workspace has **zero charts and zero number cards** — only 3 shortcut links to other reports. So these are genuinely missing or were removed after Doc 15A was written.

### 1.4 Company-Specific Report Variants ("-Inmed" Suffix)

Three reports have company-specific variants with " - Inmed" appended. These are narrower versions that filter to the InMED company's specific warehouse names:

| Generic Report | Company-Specific Variant | Warehouse Filtered |
|---|---|---|
| RPT - Stock - Delivery In-Transit | RPT - Stock - Delivery In-Transit - Inmed | "Delivery In-Transit - Inmed" |
| RPT - Stock - Return Pickup In-Transit | RPT - Stock - Return Pickup In-Transit - Inmed | "Return Pickup In-Transit - Inmed" |
| RPT - Stock - Returns | RPT - Stock - Returns - Inmed | "Returns - Inmed" |

These are not duplicates — they serve different purposes (generic vs company-scoped). The generic versions use a warehouse parameter; the Inmed versions hardcode the warehouse. Both are valid. However, the Inmed variants are **not documented** in any numbered doc.

### 1.5 Report Role Access Summary

Most reports share a broad role set. Notable restrictions:

| Access Pattern | Reports | Roles |
|---|---|---|
| Directors + System Manager only | Income by Period, Comparative Periods, Item Sort and Classify | Ops - Directors, System Manager |
| Accounting + Directors | Debt Status Board, Sales Documents and Payments | Ops - Accounting, Ops - Directors, System Manager |
| Accounting only | Unpaid Invoices (Aging), Unallocated Advances, History by Client | Ops - Accounting, System Manager |
| Purchasing restricted | Norm and Reorder, Supplier Performance | Ops - Purchasing, Ops - Directors, System Manager |
| Broad access (nearly all roles) | Most stock, dispatch, and risk reports | All operational roles |

Two role names appear in report permissions that are **not in the requirements docs**: `Ops - Purchasing Lead` and `Ops - Finance`. Doc 03 defines `Ops - Purchasing` and mentions Finance Team but the exact role name `Ops - Finance` is never formally specified. `Ops - Purchasing Lead` is not mentioned at all.

**Confidence**: 80% — These roles may have been created as operational decisions not yet documented.

---

## 2. Workspaces — Complete Analysis

### 2.1 Custom Operational Workspaces (3)

#### Dispatch - Task Queues

**Purpose**: Central operational workspace for dispatch team task management.

**Deployed shortcuts (12)**:
1. VIEW: Pack Tasks → Task List (task_kind = "Pack / prepare items", not Completed/Cancelled)
2. VIEW: Delivery Tasks → Task List (task_kind = "Delivery")
3. VIEW: Return Pickup Tasks → Task List (task_kind = "Pickup Returns")
4. VIEW: Returns Inspection Tasks → Task List (task_kind = "Returns processing / verification")
5. VIEW: Restock Tasks → Task List (task_kind = "Returns restocking")
6. VIEW: Invoice Tasks → Task List (task_kind = "Invoice preparation / create invoice")
7. VIEW: Debt Collection Tasks → Task List (task_kind = "Debt Collection")
8. VIEW: Payment Received Tasks → Task List (task_kind = "Payment Received")
9. VIEW: Distribute Payment Tasks → Task List (task_kind = "Distribute Payment")
10. All Dispatch Cases → Dispatch Case List
11. All Urgent Tasks → Task List (priority = "Urgent")
12. Overdue Tasks → Task List (status = "Overdue")

**Doc comparison**: Doc 15 §8.2 specifies a "Tasks by Urgency" workspace. The Dispatch - Task Queues workspace partially matches, providing per-task-kind queues plus urgent/overdue views. Doc 15 also specifies color coding (red/orange/green/grey) which cannot be implemented via workspace shortcuts alone.

**Missing vs doc**: Doc 15 mentions "My open tasks" and "Approval tasks (discount, purchase, write-off)" views that are NOT in this workspace (they appear in the Ops - Reporting Pack instead).

**Confidence**: 85% — The workspace matches the overall intent but deviates in structure from the doc spec.

#### Management - KPI Dashboard

**Purpose**: Director/management-level KPI overview.

**Deployed shortcuts (3 only)**:
1. Item Sort and Classify → RPT - Item - Sort and Classify
2. Item Nomenclature and Prices → RPT - Item - Nomenclature and Prices
3. Returns Refund Queue → RPT - Returns - Refund Queue

**Charts**: 0
**Number cards**: 0

**Doc comparison**: Doc 15 §8.4 specifies a "Global Statistics Dashboard" with multiple widgets: stock value by item group, top 10 products, top 10 revenue, slow-moving, expired/near-expiry value at risk, receivables total, monthly income trend, sales by segment, inventory turnover. Doc 15A marks "RPT - KPI - Daily Dashboard", "RPT - KPI - Weekly Dashboard", and "RPT - KPI - Monthly Income and Profit" as EXISTS.

**Reality**: The workspace is a **skeleton** — 3 unrelated report shortcuts, no charts, no number cards. The KPI dashboard described in the docs does not exist in production.

**Confidence**: 95% — This is verifiable from the schema. The workspace has zero charts and zero number cards.

#### Ops - Reporting Pack

**Purpose**: Central reporting workspace for operational teams.

**Deployed shortcuts (28)**:
1. Delivery In-Transit Stock → RPT - Stock - Delivery In-Transit - Inmed
2. Return Pickup In-Transit Stock → RPT - Stock - Return Pickup In-Transit - Inmed
3. Returns Backlog → RPT - Stock - Returns - Inmed
4. Client Locations Stock → RPT - Stock - Client Locations (All)
5. In-Transit Stuck Check → RPT - Stock - In-Transit Stuck (Age Check)
6. Client Stock (No Open Cases) → RPT - Ops - Client Stock With No Open Cases
7. Driver Task Queue → RPT - Ops - Driver Task Queue (Derived)
8. Surgery Cases Aging (Open) → RPT - Surgery Cases - Aging (Open)
9. VIEW: Cases Delivered → Surgery Case List
10. VIEW: Cases Pickup In Transit → Surgery Case List
11. VIEW: Cases Returns Received → Surgery Case List
12. VIEW: Cases Usage Derived → Surgery Case List
13. Unpaid Invoices (Aging) → RPT - Receivables - Unpaid Invoices (Aging)
14. Unallocated Advances → RPT - Receivables - Unallocated Advances
15. Prepaid Orders Awaiting Delivery → RPT - Ops - Prepaid Orders Awaiting Delivery
16. Debt Threshold Exceeded → RPT - Risk - Debt Threshold Exceeded
17. VIEW: Debt Collection Tasks → Task List
18. VIEW: Distribute Payment Tasks → Task List
19. VIEW: Return to Warehouse Tasks → Task List
20. VIEW: Discount Approval Tasks → Task List
21. VIEW: Purchase Approval Tasks → Task List
22. VIEW: Write-off Approval Tasks → Task List
23. Sales History by Client → RPT - Sales - History by Client
24. Manual Rate Edits → RPT - Pricing - Sales Orders With Manual Rate Edits
25. Near Expiry Stock → RPT - Stock - Near Expiry (Main - Inmed)
26. Tracked Items Missing Identifiers → RPT - Data Quality - Tracked Items Missing Identifiers
27. Collection Sets Readiness → Collection Set List
28. Price Overrides by Client → Item Price List

**Doc comparison against Doc 13A spec**:

| Doc 13A Specified Shortcut | Deployed? | Notes |
|---|---|---|
| RPT — Stock — Delivery In-Transit | Yes | Uses "-Inmed" variant instead of generic |
| RPT — Stock — Return Pickup In-Transit | Yes | Uses "-Inmed" variant |
| RPT — Stock — Returns | Yes | Uses "-Inmed" variant |
| RPT — Stock — Client Locations (All) | Yes | Exact match |
| RPT — Ops — Driver Task Queue (Derived) | Yes | Exact match |
| RPT — Dispatch Cases — Aging (Open) | **NO** | **Missing** — Surgery Cases Aging used instead |
| RPT — Receivables — Unpaid Invoices (Aging) | Yes | Exact match |
| RPT — Receivables — Unallocated Advances | Yes | Exact match |
| RPT — Risk — Debt Threshold Exceeded | Yes | Exact match |
| VIEW — Tasks — Debt Collection (Open) | Yes | Match |
| VIEW — Tasks — Distribute Payment (Open) | Yes | Match |
| VIEW — Tasks — Return to warehouse (Open) | Yes | Match |
| VIEW — Tasks — Discount Approval (Open) | Yes | Match |
| VIEW — Tasks — Purchase Approval (Open) | Yes | Match |
| VIEW — Tasks — Write-off Approval (Open) | Yes | Match |
| Price Overrides — by Client | Yes | Links to Item Price List |
| Collection Sets — Readiness | Yes | Links to Collection Set List |
| VIEW — Dispatch Cases — Awaiting Return Pickup | **NO** | **Missing** — Surgery Case views used instead |
| VIEW — Dispatch Cases — Return In Transit | **NO** | **Missing** — Surgery Case view used instead |
| VIEW — Dispatch Cases — Returns Received | **NO** | **Missing** — Surgery Case view used instead |
| VIEW — Dispatch Cases — Invoice Pending | **NO** | **Missing** |

**Key issue**: The workspace contains **5 Surgery Case shortcuts** (shortcuts 8-12) instead of the Dispatch Case views specified in Doc 13A. This is because the workspace was originally built for the Surgery Case architecture (Docs 09-12) and was **never updated** when Dispatch Case (Doc 16) superseded Surgery Case. This is a stale deployment.

**Confidence**: 95%

### 2.2 Standard ERPNext Workspaces (19)

All 19 are unmodified ERPNext defaults: Assets, Build, Buying, CRM, ERPNext Settings, Financial Reports, Home, Integrations, Invoicing, Manufacturing, Projects, Quality, Selling, Stock, Subcontracting, Support, Users, Website, Welcome Workspace.

These are not relevant to the audit — they are framework workspaces. However, some contain links to DocTypes that InMED does not use (Manufacturing, Subcontracting, Quality, etc.), which creates UI clutter.

**Confidence**: 95%

### 2.3 Workspace.js Client Script

**File**: `deploy/test/work/client/Workspace.js` (28 lines, enabled)
**DocType**: Workspace, Form view

**What it does**: When the user opens the Home workspace, injects a custom "Task List" icon/shortcut with a blue rounded icon and hover animation. The shortcut navigates to `List/Task`.

**Documentation**: None. This is an undocumented UI enhancement.

**Assessment**: Low-risk. Purely cosmetic. Could break if ERPNext changes Workspace DOM structure in a version upgrade.

**Confidence**: 95%

---

## 3. Property Setters — Complete Analysis

### 3.1 Breakdown by Origin

| Category | Count | Description |
|---|---|---|
| System-generated | 156 | ERPNext setup wizard defaults (naming series, tax_id, print formats, rounded totals, barcodes, etc.) |
| Custom/intentional | 53 | InMED-specific field visibility, depends_on, allow_on_submit, labels, field ordering |

### 3.2 System-Generated Property Setters (156)

These are benign ERPNext defaults. Grouped by purpose:

| Purpose | Count | DocTypes Affected | Example |
|---|---|---|---|
| Naming series hidden/not required | 6 | Supplier, Customer, Item | Supplier-naming_series-hidden=1 |
| Tax ID visibility | 6 | Sales Order, Sales Invoice, Delivery Note | Shown (hidden=0) + print shown (print_hide=0) |
| Rounded total / in_words visibility | 64 | 8 transaction DocTypes | All shown; base_rounded_total print hidden |
| Default print formats (Item Image) | 8 | SO, SI, DN, PO, PI, POS, Quotation, RFQ | e.g. "Sales Order with Item Image" |
| UTM analytics sections shown | 7 | Lead, Quotation, POS, Opportunity, SO, SI, DN | All hidden=0 (shown) |
| Barcode fields shown | 23 | Multiple item/transaction DocTypes | All hidden=0 (shown) |
| Discount account hidden | 3 | Sales Invoice, Sales Invoice Item | Hidden + mandatory_depends_on cleared |
| Commission/sales team shown | 2 | Sales Invoice | commission_section, sales_team_section |
| Packed Item rate read-only | 1 | Packed Item | read_only=1 |
| Item code visible + required | 2 | Item | hidden=0, reqd=1 |
| Purchase Receipt field order | 1 | Purchase Receipt Item | Custom field_order including custom_expiry_date |
| Purchase Receipt prov. expense hidden | 1 | Purchase Receipt | provisional_expense_account hidden |

**Documentation**: None of these are mentioned in the numbered docs. They are implicit setup decisions.

**Assessment**: All are standard ERPNext setup choices. No documentation needed unless the specific visibility decisions (e.g., UTM sections shown, barcodes shown) need to be recorded as configuration policy.

**Confidence**: 95%

### 3.3 Custom/Intentional Property Setters (53)

These are InMED-specific customizations that control the user experience. Grouped by DocType:

#### Task (44 custom setters)

**Hidden fields (9)**:
- `project`, `issue`, `type`, `color`, `is_group`, `task_weight`, `parent_task`, `is_template`, `task_access_policy` — all hidden=1

**Rationale**: Task is repurposed as an operational work item. Standard ERPNext project-management fields are hidden to simplify the form. `task_access_policy` is hidden because it's set automatically by scripts, not by users.

**Documentation**: Doc 10 (Task System Foundations) describes the Task form simplification but does not list the specific fields to be hidden. This is an undocumented implementation decision.

**Confidence**: 90%

**Conditional visibility (depends_on) (19)**:
Every operational field on Task has a `depends_on` expression that shows/hides it based on `task_kind`. Examples:
- `dispatch_case` → shown only for Pack, Delivery, Pickup Returns, Returns processing, etc.
- `delivery_status` → shown only for Delivery tasks
- `pickup_status` → shown only for Pickup Returns tasks
- `purchase_order` → shown only for Purchase Approval tasks
- `approval_outcome` → shown only for Purchase/Discount/Write-off Approval tasks
- `sales_invoice` → shown for Invoice, Debt Collection, Payment Received, etc.
- Payment fields → shown for Payment Received and Debt Collection tasks
- Warehouse photos → shown unconditionally (depends_on cleared to empty)

**Documentation**: Doc 10 describes task_kind-driven visibility conceptually but does not list exact field-to-task_kind mappings. The actual `depends_on` expressions are undocumented.

**Confidence**: 90%

**Label/display customizations (4)**:
- `dispatch_case` label changed to "Dispatch Case / Packing Items"
- `dispatch_case` description set to detailed packing instruction text
- `dispatch_case` bold=1 (emphasized)
- `dispatch_case` in_list_view=1

**Status options override (1)**:
- `status` options set to: `Open`, `Working`, `Overdue`, `Completed`, `Cancelled`
- ERPNext default Task status options include additional values. This override simplifies the workflow.

**Documentation**: Doc 10 lists the Task statuses as Open, Working, Completed, Cancelled. `Overdue` is handled by the scheduler (doc15_task_auto_escalation.py). The status override matches the documented design.

**Confidence**: 95%

**Other Task setters (11)**:
- `subject` not required (reqd=0) — subjects are auto-generated by `Task-before-save-auto-subject.py`
- `is_group`, `is_milestone` removed from list view
- `custom_is_team_queue_task`, `custom_team_notified` hidden (internal flags)
- `field_order` — comprehensive reordering of all Task fields
- `show_title_field_in_link` — shows customer name in link fields
- `dispatch_case_status` depends_on — same visibility rules as dispatch_case

#### Dispatch Case (36 custom setters)

**Allow-on-submit (30)**:
Every Dispatch Case field and child table field is set to `allow_on_submit=1`. This permits editing after submission — essential because the Dispatch Case goes through many post-submit state changes (packing, delivery, returns, invoicing).

Fields: customer, client_location_warehouse, return_expected, surgery_date, surgery_set_type, notes, all task link fields (order_entry_task through invoice_task), all stock entry link fields, sales_invoice, prepaid_amount/entry, total_invoice_amount, total_paid_amount, outstanding_amount, delivery_photo, return_dropoff_photo, case_items (child table), and all Dispatch Case Item fields (item_code, item_name, dispatched_qty, serial_no, batch_no, unit_price, returned_qty, lost_damaged_qty, used_qty, scanned_qty, remaining_qty, packing_status).

**Documentation**: Doc 16A mentions that Dispatch Case fields need to be editable post-submit but does not enumerate every field. This is an undocumented implementation detail.

**Confidence**: 90%

**Other Dispatch Case setters (6)**:
- `customer` not required (reqd=0) — allows creating DC before customer is selected
- `client_location_warehouse` not required (reqd=0)
- `search_fields` = "customer,notes,status"
- `title_field` = "customer"
- `show_title_field_in_link` = 1

#### Item (1 custom setter)

- `show_title_field_in_link` = 1

---

## 4. Workflow

### 4.1 Surgery Case Workflow

| Property | Value |
|---|---|
| Name | Surgery Case Workflow |
| DocType | Surgery Case |
| Active | **YES** |
| States | 12 |
| Transitions | 11 |

**States**: Draft → Preparing → Dispatch Picking → Dispatched → Delivered → Return Pickup Scheduled → Return Pickup In Transit → Returns Verification → Returns Received → Usage Derived → Invoiced → Closed

**Transitions** (all linear):
1. Draft → Preparing (Order Accepting)
2. Preparing → Dispatch Picking (Inventory)
3. Dispatch Picking → Dispatched (Inventory)
4. Dispatched → Delivered (Delivery)
5. Delivered → Return Pickup Scheduled (Order Accepting)
6. Return Pickup Scheduled → Return Pickup In Transit (Delivery)
7. Return Pickup In Transit → Returns Verification (Returns)
8. Returns Verification → Returns Received (Returns)
9. Returns Received → Usage Derived (Returns)
10. Usage Derived → Invoiced (Accounting)
11. Invoiced → Closed (Order Accepting)

**Documentation**: Docs 11/12 describe this workflow. However, Docs 11/12 are **superseded** by Doc 16 (Unified Dispatch Flow). The Dispatch Case does NOT use an ERPNext Workflow — it uses a `status` field managed by server scripts.

**Assessment**: This workflow is **active on a superseded DocType**. If anyone creates a Surgery Case (the DocType still exists and is not disabled), this workflow will control its state transitions. The `Surgery-Case-before-save.py` server script (255 lines, **enabled**) also fires on Surgery Case saves and orchestrates stock entries/tasks alongside this workflow. This creates a parallel operational system to Dispatch Case that is actively deployable.

**Confidence**: 95%

---

## 5. Role Profiles

### 5.1 Deployed Role Profiles (6)

| Profile | Roles Included | Source |
|---|---|---|
| System Manager | System Manager | ERPNext default |
| Inventory | Stock User, Stock Manager, Item Manager | ERPNext default |
| Manufacturing | Stock User, Manufacturing User, Manufacturing Manager | ERPNext default |
| Accounts | Accounts User, Accounts Manager | ERPNext default |
| Sales | Sales User, Sales Manager | ERPNext default |
| Purchase | Purchase User, Purchase Manager | ERPNext default |

### 5.2 Missing Role Profiles for InMED Custom Roles

Doc 03 defines 10+ operational roles. **None** of them have role profiles:

| Custom Role | Used In Scripts | Has Profile |
|---|---|---|
| Ops - Order Creating | Yes | **No** |
| Ops - Order Accepting | Yes | **No** |
| Ops - Inventory | Yes | **No** |
| Ops - Delivery | Yes | **No** |
| Ops - Returns | Yes | **No** |
| Ops - Accounting | Yes | **No** |
| Ops - Finance | Yes | **No** |
| Ops - Directors | Yes | **No** |
| Ops - Purchasing | Yes | **No** |
| Ops - Purchasing Lead | Yes (in reports) | **No** |
| Delivery Driver | Yes | **No** |

**Impact**: Without role profiles, user role assignment is done manually role-by-role. This increases onboarding errors — a new warehouse worker needs `Ops - Inventory` plus `Stock User` plus `Stock Manager` plus `Item Manager` assigned individually. Role profiles would bundle these.

**Documentation**: Doc 03A describes which ERPNext system roles each operational role needs, but does not specify creating role profiles for them.

**Confidence**: 90%

---

## 6. Notifications

### 6.1 Deployed Notifications (5)

| # | Name | Event | DocType | Channel | Enabled | Source |
|---|---|---|---|---|---|---|
| 1 | Notification for new fiscal year | New | Fiscal Year | Email | Yes | ERPNext standard |
| 2 | Material Request Receipt Notification | Value Change | Material Request | Email | Yes | ERPNext standard |
| 3 | Error Log | New | Error Log | System | Yes | Custom (monitoring) |
| 4 | Integration Request | Save | Integration Request | System | Yes | Custom (monitoring) |
| 5 | DATUREX Task Push | New | Task | Push | **DISABLED** | Custom |

### 6.2 Assessment

- Notifications #1 and #2 are ERPNext defaults. Not relevant to InMED operations.
- Notifications #3 and #4 are system monitoring. Useful, not documented.
- Notification #5 (DATUREX Task Push) was part of the evaluated DATUREX Connect mobile app integration (see `mobile-app-comparison.md`). It was disabled, likely when the Telegram notification approach was chosen instead.

**No InMED operational notifications exist** in the Notification system. All operational notifications are handled by:
- Telegram server scripts (Group 8 — `Telegram Task Assignment Notification.py`, `Telegram Task Status Update.py`)
- ToDo-based alerts created by server scripts
- Scheduler-based escalations

**Documentation**: Doc 15 mentions notification recipients for norm calculations and task escalations. These are implemented as scheduler scripts + ToDo creation, NOT as Notification records. This architectural decision is undocumented.

**Confidence**: 90%

---

## 7. Print Format

### 7.1 IRS 1099 Form

| Property | Value |
|---|---|
| Name | IRS 1099 Form |
| DocType | Supplier |
| Standard | No (custom) |
| Format | Jinja HTML |
| Disabled | No |

This is a US Internal Revenue Service 1099 tax reporting form. It is completely **irrelevant** to InMED (an Armenian medical supplier). It was likely included in an ERPNext Regional module and auto-created during setup.

**Assessment**: Harmless but unnecessary. Could be disabled or deleted to reduce clutter.

**Confidence**: 95%

---

## 8. Findings Register

### F-001: Management KPI Dashboard is an empty skeleton
- **Type**: DOC-STALE
- **Severity**: HIGH
- **Evidence**: Workspace has 3 unrelated report shortcuts, 0 charts, 0 number cards. Doc 15 §8.4 specifies 10+ dashboard widgets. Doc 15A claims KPI Daily/Weekly/Monthly dashboards "EXISTS".
- **Recommendation**: Either build the KPI dashboard content (charts, number cards) or update Doc 15A to mark these as NOT DEPLOYED. Currently, the documentation overstates what is delivered.
- **Confidence**: 95%

### F-002: Ops Reporting Pack workspace still has Surgery Case views instead of Dispatch Case views
- **Type**: DOC-STALE + RISK
- **Severity**: HIGH
- **Evidence**: Shortcuts 8-12 link to Surgery Case List views (Cases Delivered, Pickup In Transit, Returns Received, Usage Derived). Doc 13A specifies Dispatch Case views (Awaiting Return Pickup, Return In Transit, Returns Received, Invoice Pending). Surgery Case is superseded per docs-overview.md.
- **Recommendation**: Replace Surgery Case shortcuts with Dispatch Case equivalents. If Surgery Case is still used operationally, this must be documented as a deviation from Doc 16.
- **Confidence**: 95%

### F-003: Surgery Case Workflow is active on a superseded DocType
- **Type**: RISK
- **Severity**: HIGH
- **Evidence**: `Surgery Case Workflow` has `is_active=1`, 12 states, 11 transitions, and references roles that have real users. `Surgery-Case-before-save.py` (255 lines) is also enabled. If anyone creates a Surgery Case, a full parallel operational system activates.
- **Recommendation**: If Surgery Case is truly superseded, either deactivate the workflow (`is_active=0`) or document that Surgery Case remains an active parallel system.
- **Confidence**: 95%

### F-004: Four duplicate report pairs exist
- **Type**: RISK
- **Severity**: HIGH
- **Evidence**: See §1.2. Debt Threshold, Unallocated Advances, Dispatch Case Aging, and Prepaid Orders each have two reports. Users may see different data depending on which version they open. The Prepaid Orders pair references different DocTypes (Sales Order vs Dispatch Case).
- **Recommendation**: For each pair, determine which version is current. Disable or delete the obsolete one. The Prepaid Orders pair is especially risky — the Sales Order version may show stale data since operations now use Dispatch Case.
- **Confidence**: 95%

### F-005: RPT - Surgery Cases - Aging (Open) references superseded DocType
- **Type**: DEAD-CODE
- **Severity**: HIGH
- **Evidence**: Report references `Surgery Case` DocType. Surgery Case is superseded by Dispatch Case per Doc 16. `RPT - Dispatch Cases - Aging (Open)` already exists as the replacement.
- **Recommendation**: Disable or delete. If Surgery Cases are still used operationally, document why.
- **Confidence**: 95%

### F-006: No role profiles for InMED custom roles
- **Type**: DOC-MISSING
- **Severity**: MEDIUM
- **Evidence**: 11 custom roles used across all scripts. 0 role profiles for them. Only 6 ERPNext default profiles exist. User onboarding requires manual role-by-role assignment.
- **Recommendation**: Create role profiles bundling each custom role with its required system roles (e.g., "InMED - Inventory Worker" = Ops - Inventory + Stock User + Stock Manager + Item Manager). Document in Doc 03A.
- **Confidence**: 90%

### F-007: Roles used in reports but not documented: Ops - Purchasing Lead, Ops - Finance
- **Type**: DOC-MISSING
- **Severity**: MEDIUM
- **Evidence**: `Ops - Purchasing Lead` appears in report permissions for RPT - Low Stock by Supplier and RPT - Collection Set Readiness. `Ops - Finance` appears in multiple report permissions. Neither is defined in Doc 03.
- **Recommendation**: Add both roles to Doc 03 with responsibilities and permissions. Verify these roles actually exist as Role records (not just referenced in report permissions).
- **Confidence**: 80%

### F-008: 53 custom property setters are undocumented
- **Type**: DOC-MISSING
- **Severity**: MEDIUM
- **Evidence**: 44 on Task (field hiding, depends_on expressions, status options, field ordering), 6 on Dispatch Case (allow_on_submit, search/title config), 3 misc. None are described in any numbered doc.
- **Recommendation**: Create a configuration reference document listing all custom property setters with their purpose. This is essential for reproducing the environment from scratch.
- **Confidence**: 90%

### F-009: Dispatch Case Aging report shortcut missing from Ops Reporting Pack
- **Type**: DOC-STALE
- **Severity**: MEDIUM
- **Evidence**: Doc 13A specifies "RPT — Dispatch Cases — Aging (Open)" as a shortcut. The workspace has Surgery Cases Aging instead. Dispatch Case aging report exists (#33) but is not linked from the primary operational workspace.
- **Recommendation**: Add Dispatch Case aging shortcut. Remove Surgery Case aging shortcut.
- **Confidence**: 95%

### F-010: Notification architecture decision undocumented
- **Type**: DOC-MISSING
- **Severity**: MEDIUM
- **Evidence**: No InMED operational notifications use the ERPNext Notification system. All are implemented via Telegram scripts + ToDo creation + scheduler. Doc 15 mentions notifications but doesn't specify the implementation approach.
- **Recommendation**: Document the architectural decision: "Operational notifications use Telegram bot integration and ToDo-based alerts, not ERPNext Notification records."
- **Confidence**: 90%

### F-011: DATUREX Task Push notification disabled without documented decision
- **Type**: DOC-MISSING
- **Severity**: MEDIUM
- **Evidence**: `DATUREX Task Push` notification exists but is disabled. `mobile-app-comparison.md` evaluated DATUREX Connect. The decision to use Telegram instead is not recorded in a numbered doc.
- **Recommendation**: Document the decision: "DATUREX Connect was evaluated and rejected in favor of Telegram bot notifications."
- **Confidence**: 85%

### F-012: Ops Reporting Pack uses older report versions instead of newer ones
- **Type**: RISK
- **Severity**: MEDIUM
- **Evidence**: The workspace links to `RPT - Risk - Debt Threshold Exceeded` (2026-05-08), `RPT - Receivables - Unallocated Advances` (2026-05-08), and `RPT - Ops - Prepaid Orders Awaiting Delivery` (2026-05-08, ref: Sales Order). Newer versions exist: `RPT - Clients Exceeding Debt Threshold` (2026-06-16), `RPT - Unallocated Customer Advances` (2026-06-16), `RPT - Prepaid Orders Awaiting Delivery` (2026-06-16, ref: Dispatch Case).
- **Recommendation**: Update workspace shortcuts to reference the newer, more complete reports. Then disable the older versions.
- **Confidence**: 85%

### F-013: Three "-Inmed" company-specific report variants are undocumented
- **Type**: DOC-MISSING
- **Severity**: MEDIUM
- **Evidence**: Stock - Delivery In-Transit - Inmed, Stock - Return Pickup In-Transit - Inmed, Stock - Returns - Inmed are hardcoded to company-specific warehouse names but not mentioned in any doc.
- **Recommendation**: Document as "company-scoped convenience reports" in the reporting docs.
- **Confidence**: 85%

### F-014: Task field_order property setter is the de facto Task form layout
- **Type**: DOC-MISSING
- **Severity**: MEDIUM
- **Evidence**: A single property setter defines the complete field ordering for the Task form (80+ fields in specific order). This is the primary determinant of the Task user experience and is not documented anywhere.
- **Recommendation**: Record the field_order in Doc 10A or a new Task form layout document.
- **Confidence**: 90%

### F-015: Dispatch Case allow_on_submit pattern covers 30 fields
- **Type**: DOC-MISSING
- **Severity**: MEDIUM
- **Evidence**: 30 Dispatch Case fields + all child table fields have allow_on_submit=1. This is essential for the post-submit workflow but creates a wide edit surface on submitted documents.
- **Recommendation**: Document which fields are allowed on submit and why. Review whether all 30 are truly needed (e.g., `surgery_date`, `surgery_set_type` may be legacy from Surgery Case).
- **Confidence**: 85%

### F-016: Task status options include "Overdue" which is set by scheduler, not user
- **Type**: ENHANCEMENT
- **Severity**: LOW
- **Evidence**: Task status options are "Open, Working, Overdue, Completed, Cancelled". Overdue is set by `doc15_task_auto_escalation.py` scheduler. Users can manually set status to Overdue, which may not be intended.
- **Recommendation**: Verify whether Overdue should be selectable by users or only set by automation. If automation-only, consider removing from options and using a separate computed field.
- **Confidence**: 75%

### F-017: Standard ERPNext workspaces for unused modules are visible
- **Type**: ENHANCEMENT
- **Severity**: LOW
- **Evidence**: Workspaces for Manufacturing, Subcontracting, Quality, CRM, Website, Support, Projects are all visible. InMED does not use these modules. They add navigation clutter.
- **Recommendation**: Hide unused workspaces (set `is_hidden=1`).
- **Confidence**: 90%

### F-018: IRS 1099 print format is deployed but irrelevant
- **Type**: DEAD-CODE
- **Severity**: LOW
- **Evidence**: US tax form for Supplier. InMED is in Armenia and has no US tax reporting obligations. Likely auto-created by ERPNext Regional module.
- **Recommendation**: Disable or delete. Harmless but adds clutter.
- **Confidence**: 95%

### F-019: Error Log and Integration Request notifications are undocumented monitoring tools
- **Type**: DOC-MISSING
- **Severity**: LOW
- **Evidence**: Two system notifications (Error Log on New, Integration Request on Save) exist as custom monitoring. Not documented.
- **Recommendation**: Document as "system monitoring notifications" in infrastructure or operations runbook.
- **Confidence**: 90%

### F-020: Report role access may have inflated permission lists
- **Type**: RISK
- **Severity**: LOW
- **Evidence**: Several reports (e.g., RPT - Clients Exceeding Debt Threshold) have the same role listed twice (e.g., Ops - Order Accepting appears at idx 1 and again at idx 10). This suggests roles were added in two batches without deduplication.
- **Recommendation**: Deduplicate role assignments. Review each report's role list against Doc 03 access control requirements.
- **Confidence**: 85%

### F-021: Workspace.js is an undocumented UI injection
- **Type**: DOC-MISSING
- **Severity**: LOW
- **Evidence**: Client script injects a "Task List" shortcut icon on the Home workspace via DOM manipulation. Not mentioned in any doc.
- **Recommendation**: Document. Note fragility — DOM manipulation will break if ERPNext changes Workspace layout.
- **Confidence**: 95%

### F-022: Dispatch Case search_fields includes "status" which is not a standard field
- **Type**: RISK
- **Severity**: LOW
- **Evidence**: Property setter `Dispatch Case search_fields = "customer,notes,status"`. The Dispatch Case `status` field is a custom field whose exact name/fieldname needs verification.
- **Recommendation**: Verify that the search_fields reference matches the actual fieldname. If `status` refers to the workflow state rather than a fieldname, the search may silently fail.
- **Confidence**: 70%

### F-023: No Dispatch Case workflow shortcut in workspace for "Awaiting Return Pickup"
- **Type**: DOC-STALE
- **Severity**: LOW
- **Evidence**: Doc 13A specifies VIEW shortcuts for Dispatch Cases in states: Awaiting Return Pickup, Return In Transit, Returns Received, Invoice Pending. None of these exist — Surgery Case views are used instead (see F-002).
- **Recommendation**: Covered by F-002 remediation.
- **Confidence**: 95%

### F-024: RPT - Items by Delivery Person references Task DocType, not Delivery Note
- **Type**: ENHANCEMENT
- **Severity**: LOW
- **Evidence**: This report derives items-per-driver from Task assignments, not from stock/delivery records. This is correct per the architecture (Tasks drive operations) but may confuse users expecting a traditional delivery-note-based report.
- **Recommendation**: No action needed, but add a report description/subtitle explaining the derivation logic.
- **Confidence**: 85%

### F-025: Doc 13A Ops Reporting Pack specified as "Public: ON" but deployed as public=0
- **Type**: DOC-STALE
- **Severity**: LOW
- **Evidence**: Doc 13A spec says `Public: ON` for the Ops Reporting Pack workspace. Deployed value is `public: 0` (private). This means only users who manually navigate to it or have it pinned can see it.
- **Recommendation**: Either set public=1 as documented, or update Doc 13A to reflect that it's intentionally private.
- **Confidence**: 90%

### F-026: "Ops - Order Creating" role referenced in reports but unclear if separate from "Ops - Order Accepting"
- **Type**: DOC-MISSING
- **Severity**: LOW
- **Evidence**: Some reports grant access to both `Ops - Order Accepting` and `Ops - Order Creating` as separate roles. Doc 03 defines both but their distinction is not always clear. Some reports have one, some have both, some have neither.
- **Recommendation**: Clarify in Doc 03 whether these are distinct roles or aliases. Standardize report access accordingly.
- **Confidence**: 75%

### F-027: Dispatch Case title_field set to "customer" — affects link display everywhere
- **Type**: DOC-MISSING
- **Severity**: LOW
- **Evidence**: Property setter `Dispatch Case title_field = customer`. This means everywhere a Dispatch Case link appears, it shows the customer name instead of the DC ID. This is a user experience decision not documented.
- **Recommendation**: Document as an intentional UX decision.
- **Confidence**: 90%

### F-028: Purchase Receipt Item field_order includes custom_expiry_date at the end
- **Type**: DOC-MISSING
- **Severity**: LOW
- **Evidence**: A system-generated property setter reorders Purchase Receipt Item fields, placing `custom_expiry_date` at the end. This may affect form usability for the GS1 barcode scanning workflow.
- **Recommendation**: Verify this field order works correctly with the GS1 Barcode Parser client script (Group 5). Document if intentional.
- **Confidence**: 75%

### F-029: Task "subject" field set to not required (reqd=0) — relies on auto-generation
- **Type**: RISK
- **Severity**: LOW
- **Evidence**: Property setter `Task subject reqd=0`. The `Task-before-save-auto-subject.py` script auto-generates a 5-digit numeric subject when missing. If that script is ever disabled, tasks could be created without subjects, making them hard to identify.
- **Recommendation**: Document the dependency: "Task subject is auto-generated by server script. Do not disable `Task-before-save-auto-subject.py` without making subject required again."
- **Confidence**: 85%

---

## 9. Cross-Group Dependencies

Items that should be verified by other group sessions:

| Finding | Relevant Group | What to Check |
|---|---|---|
| F-003: Surgery Case Workflow active | Group 6 (Legacy) | Is Surgery Case still used operationally? |
| F-005: Surgery Cases Aging report | Group 6 (Legacy) | Are Surgery Cases still being created? |
| F-007: Ops - Finance, Ops - Purchasing Lead roles | Group 2 (Tasks) | Are these roles used in any scripts or Task Access Policies? |
| F-015: Dispatch Case allow_on_submit fields | Group 1 (Dispatch) | Which fields does `Task-after-save-dispatch-flow.py` actually update post-submit? |
| F-016: Task Overdue status | Group 2 (Tasks) | Does any script prevent users from manually setting Overdue? |
| F-022: Dispatch Case search_fields | Group 1 (Dispatch) | What is the actual fieldname for DC status? |
| F-028: Purchase Receipt Item field order | Group 5 (Packing/Barcode) | Does GS1 parser work correctly with this field ordering? |
| F-029: Task subject auto-generation | Group 2 (Tasks) | What happens if auto-subject script is disabled? |

---

## 10. Methodology and Limitations

### Evidence sources
- `deploy/test/schema/reports.json` — 49 records, each inspected for name, ref_doctype, query text, filters, columns, roles, disabled status
- `deploy/test/schema/workspaces.json` — 22 records, each inspected for shortcuts, links, charts, number_cards, module, public, is_hidden
- `deploy/test/schema/property-setters.json` — 209 records, each inspected for doc_type, field_name, property, value, is_system_generated
- `deploy/test/schema/workflows.json` — 1 record (Surgery Case Workflow), all states and transitions inspected
- `deploy/test/schema/role-profiles.json` — 6 records with roles
- `deploy/test/schema/notifications.json` — 5 records with recipients, channels, conditions
- `deploy/test/schema/print-formats.json` — 1 record (IRS 1099)
- `deploy/test/work/client/Workspace.js` — 30 lines, fully read
- Documentation: docs/13-reporting-pack.md, docs/13a-reporting-pack-implementation.md, docs/15-reporting-requirements-review.md, docs/15a-reporting-requirements-implementation.md, docs/03-roles-permissions-responsibilities.md, docs/03a-roles-permissions-implementation.md, docs/docs-overview.md

### Confidence scale
- 95-100%: Directly proven by exported record and documentation comparison
- 80-94%: Strong static evidence with minor interpretation needed
- 60-79%: Plausible interpretation requiring targeted verification
- Below 60%: Weak evidence, not treated as confirmed

### What this analysis cannot determine
- **Runtime correctness**: Whether report SQL queries return correct results depends on actual data. Static inspection can verify SQL syntax and referenced table/field names, but not result accuracy.
- **Actual user experience**: Whether workspace shortcuts resolve correctly depends on runtime ERPNext routing.
- **Permission enforcement**: Whether role-based access actually prevents unauthorized access depends on ERPNext's permission engine and user-role assignments, not just report configuration.
- **Property setter conflicts**: Whether multiple property setters on the same field produce the expected result depends on ERPNext's property setter evaluation order, which is not documented.

---

## Appendix A: Complete Report SQL Query Summary

All 49 reports are Query Reports with SQL in the `query` field. None define explicit `columns` or `filters` child records in the schema export (all have empty arrays for those) — columns are implicitly defined by the SQL SELECT clause and filters by report-level filter child records where present.

| # | Report | Query Length | Has Filters | add_total_row |
|---|---|---|---|---|
| 1 | RPT - Clients Exceeding Debt Threshold | 1330 | No | 0 |
| 2 | RPT - Collection Set Readiness | 1027 | No | 0 |
| 3 | RPT - Dispatch Case Aging | 1248 | No | 0 |
| 4 | RPT - Item - Nomenclature and Prices | 796 | No | 0 |
| 5 | RPT - Item - Sort and Classify | 1426 | No | 0 |
| 6 | RPT - Items by Delivery Person | 1046 | No | 0 |
| 7 | RPT - Low Stock by Supplier | 821 | No | 0 |
| 8 | RPT - Prepaid Orders Awaiting Delivery | 971 | No | 0 |
| 9 | RPT - Price Override List | 866 | No | 0 |
| 10 | RPT - Returns - Refund Queue | 487 | No | 0 |
| 11 | RPT - Unallocated Customer Advances | 549 | No | 0 |
| 12 | RPT - Accounting - Debt Status Board | 467 | Yes (4) | 0 |
| 13 | RPT - Accounting - Income by Period | 685 | Yes (4) | 0 |
| 14 | RPT - Accounting - Sales Documents and Payments | 685 | Yes (4) | 0 |
| 15 | RPT - Data Quality - Missing Doctor or Hospital | 423 | Yes (2) | 0 |
| 16 | RPT - Data Quality - Negative Stock | 239 | No | 0 |
| 17 | RPT - Data Quality - Tracked Items Missing Identifiers | 601 | No | 0 |
| 18 | RPT - Dispatch Cases - Aging (Open) | 326 | Yes (1) | 0 |
| 19 | RPT - Ops - Client Stock With No Open Cases | 427 | No | 0 |
| 20 | RPT - Ops - Driver Task Queue (Derived) | 566 | Yes (1) | 0 |
| 21 | RPT - Ops - Prepaid Orders Awaiting Delivery | 830 | Yes (1) | 0 |
| 22 | RPT - Pricing - Sales Orders With Manual Rate Edits | 417 | No | 0 |
| 23 | RPT - Purchasing - Norm and Reorder | 1278 | Yes (3) | 0 |
| 24 | RPT - Purchasing - Supplier Performance | 835 | Yes (3) | 0 |
| 25 | RPT - Receivables - Unallocated Advances | 645 | Yes (1) | 0 |
| 26 | RPT - Receivables - Unpaid Invoices (Aging) | 575 | Yes (3) | 0 |
| 27 | RPT - Risk - Debt Threshold Exceeded | 659 | No | 0 |
| 28 | RPT - Sales - Comparative Periods | 477 | Yes (6) | 0 |
| 29 | RPT - Sales - History by Client | 616 | Yes (3) | 0 |
| 30 | RPT - Sales - Sold Items Detail | 1256 | Yes (6) | 0 |
| 31 | RPT - Sales - Top Customers | 554 | Yes (4) | 0 |
| 32 | RPT - Sales - Top Products | 556 | Yes (4) | 0 |
| 33 | RPT - Stock - Balance Multi-Select | 563 | Yes (4) | 0 |
| 34 | RPT - Stock - Batch and Expiry Balance | 1003 | Yes (3) | 0 |
| 35 | RPT - Stock - Client Locations (All) | 595 | Yes (3) | 0 |
| 36 | RPT - Stock - Delivery In-Transit | 234 | No | 0 |
| 37 | RPT - Stock - Delivery In-Transit - Inmed | 244 | No | 0 |
| 38 | RPT - Stock - Entries by Period | 828 | Yes (6) | 0 |
| 39 | RPT - Stock - Expiry Classification | 892 | Yes (2) | 0 |
| 40 | RPT - Stock - In-Transit Stuck (Age Check) | 821 | Yes (1) | 0 |
| 41 | RPT - Stock - Near Expiry (Main - Inmed) | 642 | Yes (1) | 0 |
| 42 | RPT - Stock - Near Expiry Value at Risk | 1293 | Yes (3) | 0 |
| 43 | RPT - Stock - Return Pickup In-Transit | 239 | No | 0 |
| 44 | RPT - Stock - Return Pickup In-Transit - Inmed | 249 | No | 0 |
| 45 | RPT - Stock - Returns | 222 | No | 0 |
| 46 | RPT - Stock - Returns - Inmed | 232 | No | 0 |
| 47 | RPT - Stock - Slow-Moving Products | 998 | Yes (2) | 0 |
| 48 | RPT - Stock - Warehouse Movement | 956 | Yes (6) | 0 |
| 49 | RPT - Surgery Cases - Aging (Open) | 404 | Yes (1) | 0 |

## Appendix B: Complete Property Setter Inventory (All 209)

### B.1 System-Generated (is_system_generated = 1) — 156 records

#### Naming Series Hidden/Not Required (6)

| DocType | Field | Property | Value |
|---|---|---|---|
| Supplier | naming_series | reqd | 0 |
| Supplier | naming_series | hidden | 1 |
| Customer | naming_series | reqd | 0 |
| Customer | naming_series | hidden | 1 |
| Item | naming_series | reqd | 0 |
| Item | naming_series | hidden | 1 |

#### Tax ID Visibility (6)

| DocType | Field | Property | Value |
|---|---|---|---|
| Sales Order | tax_id | hidden | 0 |
| Sales Order | tax_id | print_hide | 0 |
| Sales Invoice | tax_id | hidden | 0 |
| Sales Invoice | tax_id | print_hide | 0 |
| Delivery Note | tax_id | hidden | 0 |
| Delivery Note | tax_id | print_hide | 0 |

#### Rounded Total Visibility (40)

Applied to 8 DocTypes (Quotation, Sales Order, Sales Invoice, Delivery Note, Supplier Quotation, Purchase Order, Purchase Invoice, Purchase Receipt), 5 setters each:

| Property Pattern | Value |
|---|---|
| base_rounded_total hidden | 0 (shown) |
| base_rounded_total print_hide | 1 (hidden in print) |
| rounded_total hidden | 0 (shown) |
| rounded_total print_hide | 0 (shown in print) |
| disable_rounded_total default | 0 (enabled) |

#### In Words Visibility (16)

Applied to same 8 DocTypes, 2 setters each:

| Property Pattern | Value |
|---|---|
| in_words hidden | 0 (shown) |
| in_words print_hide | 0 (shown in print) |

#### Default Print Formats (8)

| DocType | Value |
|---|---|
| Sales Order | Sales Order with Item Image |
| Sales Invoice | Sales Invoice with Item Image |
| Delivery Note | Delivery Note with Item Image |
| Purchase Order | Purchase Order with Item Image |
| Purchase Invoice | Purchase Invoice with Item Image |
| POS Invoice | POS Invoice with Item Image |
| Quotation | Quotation with Item Image |
| Request for Quotation | Request for Quotation with Item Image |

#### UTM Analytics Sections Shown (7)

| DocType | Field | Value |
|---|---|---|
| Lead | utm_analytics_section | hidden=0 |
| Quotation | utm_analytics_section | hidden=0 |
| POS Invoice | utm_analytics_section | hidden=0 |
| Opportunity | utm_analytics_section | hidden=0 |
| Sales Order | utm_analytics_section | hidden=0 |
| Sales Invoice | utm_analytics_section | hidden=0 |
| Delivery Note | utm_analytics_section | hidden=0 |

#### Barcode Fields Shown (23)

| DocType | Field | Property | Value |
|---|---|---|---|
| Sales Invoice Item | barcode | hidden | 0 |
| POS Invoice Item | barcode | hidden | 0 |
| Job Card | barcode | hidden | 0 |
| Purchase Receipt Item | barcode | hidden | 0 |
| Item Barcode | barcode | hidden | 0 |
| Stock Reconciliation Item | barcode | hidden | 0 |
| Delivery Note Item | barcode | hidden | 0 |
| Stock Entry Detail | barcode | hidden | 0 |
| Item | barcodes | hidden | 0 |
| POS Invoice | scan_barcode | hidden | 0 |
| Sales Invoice | scan_barcode | hidden | 0 |
| Purchase Invoice | scan_barcode | hidden | 0 |
| Purchase Order | scan_barcode | hidden | 0 |
| Quotation | scan_barcode | hidden | 0 |
| Sales Order | scan_barcode | hidden | 0 |
| Stock Entry | scan_barcode | hidden | 0 |
| Pick List | scan_barcode | hidden | 0 |
| Material Request | scan_barcode | hidden | 0 |
| Purchase Receipt | scan_barcode | hidden | 0 |
| Delivery Note | scan_barcode | hidden | 0 |
| Stock Reconciliation | scan_barcode | hidden | 0 |
| Quotation | base_rounded_total | hidden | 0 |
| Item | item_code | hidden | 0 |

#### Miscellaneous System (6)

| DocType | Field | Property | Value |
|---|---|---|---|
| Packed Item | rate | read_only | 1 |
| Sales Invoice Item | discount_account | hidden | 1 |
| Sales Invoice Item | discount_account | mandatory_depends_on | (empty) |
| Sales Invoice | additional_discount_account | hidden | 1 |
| Sales Invoice | additional_discount_account | mandatory_depends_on | (empty) |
| Sales Invoice | commission_section | hidden | 0 |
| Sales Invoice | sales_team_section | hidden | 0 |
| Item | item_code | reqd | 1 |
| Purchase Receipt | provisional_expense_account | hidden | 1 |
| Purchase Receipt Item | (field_order) | field_order | (80+ fields reordered, includes custom_expiry_date) |

### B.2 Custom/Intentional (is_system_generated = 0) — 53 records

#### Task — Fields Hidden (9)

| Field | Property | Value | Purpose |
|---|---|---|---|
| project | hidden | 1 | Not used (Tasks are Dispatch-driven) |
| issue | hidden | 1 | Not used |
| type | hidden | 1 | Replaced by task_kind |
| color | hidden | 1 | Not needed |
| is_group | hidden | 1 | Tasks are flat, not hierarchical |
| task_weight | hidden | 1 | Not used |
| parent_task | hidden | 1 | Tasks are flat |
| is_template | hidden | 1 | Templates not used |
| task_access_policy | hidden | 1 | Set by scripts automatically |

#### Task — Conditional Visibility (20)

| Field | depends_on Expression | Shown For task_kind Values |
|---|---|---|
| dispatch_case | eval:!doc.task_kind \|\| doc.task_kind=="Pack / prepare items" \|\| ... | Pack, Dispatch picking, Delivery, Pickup Returns, Return drop-off, Returns processing, Returns restocking, Invoice prep, Discount Approval |
| dispatch_case_status | (same as dispatch_case) | Same |
| delivery_status | eval:!doc.task_kind \|\| doc.task_kind=="Delivery" | Delivery only |
| pickup_status | eval:!doc.task_kind \|\| doc.task_kind=="Pickup Returns" | Pickup Returns only |
| return_pickup_driver | eval:... | Pickup Returns, Return drop-off |
| scheduled_return_date | eval:... | Pickup Returns, Return drop-off |
| driver_handover_note | eval:doc.task_kind != "Order entry" | All except Order entry |
| warehouse_pickup_photo | (empty = always) | All |
| warehouse_dropoff_photo | (empty = always) | All |
| purchase_order | eval:... | Purchase Approval only |
| approval_outcome | eval:... | Purchase/Discount/Write-off Approval |
| approval_note | eval:... | Purchase/Discount/Write-off Approval |
| sales_invoice | eval:... | Invoice prep, Debt Collection, Payment Received, Distribute Payment, Returns processing |
| payment_entry | eval:... | Payment Received, Distribute Payment, Debt Collection |
| new_payment_amount | eval:... | Payment Received, Debt Collection |
| payment_method_dc | eval:... | Payment Received, Debt Collection |
| payment_reference_dc | eval:... | Payment Received, Debt Collection |
| current_debt_amd | eval:... | Debt Collection only |
| debt_threshold_amd | eval:... | Debt Collection only |
| total_outstanding | eval:... | Debt Collection, Distribute Payment |
| available_advance_credit | eval:... | Debt Collection, Distribute Payment |
| open_invoices | eval:... | Debt Collection, Distribute Payment |
| payment_history | eval:... | Debt Collection, Distribute Payment |

#### Task — Display and UX (6)

| Field | Property | Value |
|---|---|---|
| dispatch_case | label | "Dispatch Case / Packing Items" |
| dispatch_case | description | "Open this Dispatch Case to view product rows, quantities, batch/LOT, expiry, scanned qty, missing qty, FEFO warnings, and packing problems." |
| dispatch_case | bold | 1 |
| dispatch_case | in_list_view | 1 |
| status | options | "Open\nWorking\nOverdue\nCompleted\nCancelled" |
| subject | reqd | 0 |

#### Task — List View and Layout (5)

| Field/DocType | Property | Value |
|---|---|---|
| is_group | in_list_view | 0 |
| is_milestone | in_list_view | 0 |
| custom_is_team_queue_task | hidden | 1 |
| custom_team_notified | hidden | 1 |
| (Task DocType) | field_order | [80+ fields in custom order] |
| (Task DocType) | show_title_field_in_link | 1 |

#### Dispatch Case — Allow on Submit (30)

All set `allow_on_submit = 1`:

**Parent fields (27)**: customer, client_location_warehouse, return_expected, surgery_date, surgery_set_type, notes, order_entry_task, discount_approval_task, discount_approval_status, pack_task, delivery_task, return_waiting_task, return_pickup_task, returns_inspection_task, restock_task, invoice_task, dispatch_stock_entry, delivery_stock_entry, consumption_stock_entry, return_pickup_stock_entry, return_receive_stock_entry, restock_stock_entry, sales_invoice, prepaid_amount, prepaid_payment_entry, total_invoice_amount, total_paid_amount, outstanding_amount, delivery_photo, return_dropoff_photo, case_items

**Child table fields (10)**: item_code, item_name, dispatched_qty, serial_no, batch_no, unit_price, returned_qty, lost_damaged_qty, used_qty, custom_scanned_qty, custom_remaining_qty, custom_packing_status

#### Dispatch Case — Configuration (6)

| Field/DocType | Property | Value |
|---|---|---|
| customer | reqd | 0 |
| client_location_warehouse | reqd | 0 |
| (Dispatch Case) | search_fields | "customer,notes,status" |
| (Dispatch Case) | title_field | "customer" |
| (Dispatch Case) | show_title_field_in_link | 1 |

#### Item (1)

| Field/DocType | Property | Value |
|---|---|---|
| (Item) | show_title_field_in_link | 1 |

## Appendix C: Workspace Content Summary (All 22)

| # | Workspace | Module | Public | Hidden | Shortcuts | Links | Charts | Cards | Type |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Dispatch - Task Queues | Custom | No | No | 12 | 0 | 0 | 0 | Custom |
| 2 | Management - KPI Dashboard | Custom | No | No | 3 | 0 | 0 | 0 | Custom |
| 3 | Ops - Reporting Pack | Custom | No | No | 28 | 0 | 0 | 0 | Custom |
| 4 | Assets | Assets | Yes | No | 0 | 17 | 1 | 0 | Standard |
| 5 | Build | Core | Yes | No | 2 | 29 | 0 | 0 | Standard |
| 6 | Buying | Buying | Yes | No | 0 | 47 | 1 | 3 | Standard |
| 7 | CRM | CRM | Yes | No | 0 | 20 | 1 | 3 | Standard |
| 8 | ERPNext Settings | ERPNext Integrations | Yes | No | 0 | 17 | 0 | 0 | Standard |
| 9 | Financial Reports | Accounts | Yes | No | 0 | 31 | 0 | 0 | Standard |
| 10 | Home | Setup | Yes | No | 4 | 0 | 0 | 0 | Standard |
| 11 | Integrations | Integrations | Yes | No | 0 | 20 | 0 | 0 | Standard |
| 12 | Invoicing | Accounts | Yes | No | 0 | 54 | 1 | 4 | Standard |
| 13 | Manufacturing | Manufacturing | Yes | No | 0 | 41 | 1 | 3 | Standard |
| 14 | Projects | Projects | Yes | No | 0 | 17 | 1 | 3 | Standard |
| 15 | Quality | Quality Management | Yes | No | 0 | 14 | 1 | 0 | Standard |
| 16 | Selling | Selling | Yes | No | 0 | 57 | 1 | 3 | Standard |
| 17 | Stock | Stock | Yes | No | 0 | 72 | 1 | 3 | Standard |
| 18 | Subcontracting | Subcontracting | Yes | No | 0 | 12 | 1 | 3 | Standard |
| 19 | Support | Support | Yes | No | 0 | 16 | 0 | 0 | Standard |
| 20 | Users | Core | Yes | No | 0 | 7 | 1 | 3 | Standard |
| 21 | Website | Website | Yes | No | 0 | 7 | 1 | 3 | Standard |
| 22 | Welcome Workspace | Core | Yes | No | 0 | 0 | 0 | 0 | Standard |

## Appendix D: Notification Detail

| # | Name | Channel | Event | DocType | Enabled | Recipients |
|---|---|---|---|---|---|---|
| 1 | Notification for new fiscal year | Email | New | Fiscal Year | Yes | Accounts User, Accounts Manager (by role) |
| 2 | Material Request Receipt Notification | Email | Value Change (status) | Material Request | Yes | Owner (by document field) |
| 3 | Error Log | System | New | Error Log | Yes | System Manager (by role) |
| 4 | Integration Request | System | Save | Integration Request | Yes | System Manager (by role) |
| 5 | DATUREX Task Push | Push | New | Task | **No** | (push notification — no role-based recipient) |

## Appendix E: Role Profile Detail

| Profile | Roles |
|---|---|
| System Manager | System Manager |
| Inventory | Stock User, Stock Manager, Item Manager |
| Manufacturing | Stock User, Manufacturing User, Manufacturing Manager |
| Accounts | Accounts User, Accounts Manager |
| Sales | Sales User, Sales Manager |
| Purchase | Purchase User, Purchase Manager |

## Appendix F: Surgery Case Workflow States and Transitions

```
Draft ──[Start Preparing]──> Preparing ──[Move to Dispatch Picking]──> Dispatch Picking
  ──[Mark as Dispatched]──> Dispatched ──[Mark as Delivered]──> Delivered
  ──[Schedule Return Pickup]──> Return Pickup Scheduled ──[Mark Pickup In Transit]──> Return Pickup In Transit
  ──[Start Returns Verification]──> Returns Verification ──[Mark Returns Received]──> Returns Received
  ──[Derive Usage]──> Usage Derived ──[Create Invoice]──> Invoiced ──[Close Case]──> Closed
```

All 12 states use `doc_status=0` (Draft). No state triggers document submission.
No Cancel transition exists — cases cannot be cancelled through the workflow.

---

*End of Group 10 analysis. Document generated from static schema inspection only — no live server access used.*
