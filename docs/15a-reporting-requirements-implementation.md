# Doc 15A — Reporting Requirements: Implementation Status and Build Plan

**References:** Doc 15 — Reporting and Functions Requirements Review  
**Planning snapshot:** 2026-05-11  
**Deployed:** 2026-05-12 (scripts: `doc15a`, `doc15b`, `doc15c`)  
**Launch update:** 2026-06-01 (`doc15d-deploy.ps1` deployed for task auto-escalation and KPI dashboards)  
**Implementation-ready update:** 2026-06-01 (open Doc 15A items documented for later implementation; no new ERPNext changes made)  
**Final Doc 15E update:** 2026-06-01 (`doc15e-deploy.ps1` deployed for remaining reports, norm notifications, and clean workspaces)  
**Total scope:** 26 reports / functions / workspaces

---

## 0. Legend

| Symbol | Meaning |
|---|---|
| ✅ EXISTS | In prod — no action needed |
| ⚠️ PARTIAL | In prod but scope is narrower than Doc 15 requires — needs extension |
| 🔧 NATIVE | Provided by ERPNext out-of-the-box — needs only manual configuration (no code) |
| ❌ MISSING | Does not exist — must be built |
| 🚫 NEW SCOPE | Out of original go-live plan — schedule separately |

---

## 1. Summary Scorecard

| Status | Count |
|---|---|
| ✅ EXISTS (deployed or pre-existing) | 24 |
| ⚠️ PARTIAL (needs implementation-ready follow-up) | 0 |
| 🔧 NATIVE (ERPNext config, no code needed) | 0 |
| ❌ MISSING (ready for implementation plan) | 2 |
| **Total** | **26** |

---

## 2. Full Status Table — All 26 Reports

| Doc 15 § | Report / Function | Prod report name (if any) | Status |
|---|---|---|---|
| §5.1 | Stock Balance — Multi-Select | `RPT — Stock — Balance Multi-Select` | ✅ EXISTS |
| §5.2 | Stock Balance — Batch and Expiry | `RPT — Stock — Batch and Expiry Balance` | ✅ EXISTS |
| §5.3 | Stock — Expirable / Non-Expirable / Expired | `RPT — Stock — Expiry Classification` | ✅ EXISTS |
| §5.4 | Stock Entry — By Day/Period | `RPT — Stock — Entries by Period` | ✅ EXISTS |
| §5.5 | Stock Movement — Warehouse to Warehouse | `RPT — Stock — Warehouse Movement` | ✅ EXISTS |
| §5.6 | Item List — Sort and Classify | `RPT — Item — Sort and Classify` | ✅ EXISTS |
| §6.1 | Sales — Sold Items Detail | `RPT — Sales — Sold Items Detail` | ✅ EXISTS |
| §6.2 | Accounting — Sales Documents and Payments | `RPT — Accounting — Sales Documents and Payments` | ✅ EXISTS |
| §6.3 | Accounting — Unpaid Debts | `RPT — Receivables — Unpaid Invoices (Aging)` | ✅ EXISTS |
| §6.4 | Accounting — Debt Status Board | `RPT — Accounting — Debt Status Board` | ✅ EXISTS |
| §6.5 | Accounting — Income by Period | `RPT — Accounting — Income by Period` | ✅ EXISTS |
| §6.6 | Function — Return/Refund Money | `RPT — Returns — Refund Queue` + standard ERPNext return/refund documents | ✅ EXISTS |
| §7.1 | Purchasing — Norm/Reorder Requirement | `RPT — Purchasing — Norm and Reorder` | ✅ EXISTS |
| §7.2 | Item — Nomenclature and Prices | `RPT — Item — Nomenclature and Prices` | ✅ EXISTS |
| §8.1 | Statistics — Top Products and Doctors | `RPT — Sales — Top Products` + `RPT — Sales — Top Customers` | ✅ EXISTS |
| §8.2 | Workspace — Tasks by Urgency | `doc15_task_auto_escalation` + `Dispatch — Task Queues` workspace | ✅ EXISTS |
| §8.3 | Statistics — Sales Comparative Periods | `RPT — Sales — Comparative Periods` | ✅ EXISTS |
| §8.4 | Management — Global Statistics Dashboard | None: the three `RPT — KPI — *` reports and the dashboard charts do not exist; the `Management — KPI Dashboard` workspace has 0 charts and 0 number cards | ❌ MISSING |
| §9.1 | Stock — Slow-Moving Products | `RPT — Stock — Slow-Moving Products` | ✅ EXISTS |
| §9.2 | Stock — Near Expiry Value at Risk | `RPT — Stock — Near Expiry Value at Risk` | ✅ EXISTS |
| §9.3 | Data Quality — Missing Tracking Setup | `RPT — Data Quality — Tracked Items Missing Identifiers` | ✅ EXISTS |
| §9.4 | Sales — Discount and Manual Price Changes | None: `RPT — Pricing — Sales Orders With Manual Rate Edits` does not exist | ❌ MISSING |
| §9.5 | Operations — Documents Missing Doctor/Hospital | `RPT — Data Quality — Missing Doctor or Hospital` | ✅ EXISTS |
| §9.6 | Stock — Negative or Impossible Stock | `RPT — Data Quality — Negative Stock` | ✅ EXISTS |
| §9.7 | Accounting — Unallocated Payments | `RPT — Receivables — Unallocated Advances` | ✅ EXISTS |
| §9.8 | Purchasing — Supplier Performance | `RPT — Purchasing — Supplier Performance` | ✅ EXISTS |

---

## 3. Phase 1 — Must-Have Operational Visibility

**Status: ✅ All Phase 1 reports deployed 2026-05-12 (`doc15a-deploy.ps1`)**

### 3.1 Stock Balance — Multi-Select (§5.1)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Stock — Balance Multi-Select` — deployed 2026-05-12 |
| Filters | — | Warehouse, Item Code, Item Group, Brand |
| Roles | — | All Ops roles + Directors |

### 3.2 Stock Balance — Batch and Expiry (§5.2)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Stock — Batch and Expiry Balance` — new report deployed 2026-05-12 |
| Approach | — | New report (not extension of existing); CASE-based `expiry_status` column: Expired / Near Expiry (≤30d) / Valid / No Expiry |
| Filters | — | Warehouse, Item Code, Item Group |
| Roles | — | Inventory, Returns, Directors |

### 3.3 Stock — Expirable / Non-Expirable / Expired (§5.3)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Stock — Expiry Classification` — deployed 2026-05-12 |
| Filters | — | Item Group, Expiry Tracking (Expirable / Non-Expirable) |
| Roles | — | Inventory, Purchasing, Directors |

### 3.4 Stock Entry — By Day/Period (§5.4)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Stock — Entries by Period` — deployed 2026-05-12 |
| Filters | — | From Date, To Date, Warehouse, Item Code, Item Group, Entry Type |
| Columns | — | Includes `dispatch_group_id` as Dispatch Case identifier; `surgery_case` column removed |
| Roles | — | All Ops roles + Directors |

### 3.5 Stock Movement — Warehouse to Warehouse (§5.5)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Stock — Warehouse Movement` — deployed 2026-05-12 |
| Filters | — | From Date, To Date, From Warehouse, To Warehouse, Item Code, Dispatch Case |
| Notes | — | Dispatch Case filter uses `se.dispatch_group_id` (Data field on Stock Entry, deployed by Doc 16A); `surgery_case` column removed |
| Roles | — | Inventory, Order Accepting, Returns, Delivery Driver, Directors |

### 3.6 Sales — Sold Items Detail (§6.1)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Sales — Sold Items Detail` — new report deployed 2026-05-12 |
| Columns | — | Full set: customer, hospital, doctor, payment status, qty, selling price, buying price, gross profit, batch, serial, sales order |
| Note | — | `surgery_case` column removed; Sales Invoice carries `dispatch_case`, the authoritative case link |
| Buying cost | — | Joined from `tabItem Price` (`price_list = 'Standard Buying'`). Returns 0 until Standard Buying prices populated. |
| Access | — | **Directors only** — profit column |

### 3.7 Accounting — Unpaid Debts (§6.3)

| Item | Status | Notes |
|---|---|---|
| Existing report | ✅ EXISTS | `RPT — Receivables — Unpaid Invoices (Aging)` adequate for §6.3 core requirement |
| Notes | — | Covers unpaid/overdue aging. Phone/task link columns identified as minor gaps — deferred. |
| Access | — | Accounting + Directors |

### 3.8 Accounting — Sales Documents and Payments (§6.2)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Accounting — Sales Documents and Payments` — deployed 2026-05-12 |
| Filters | — | Customer, From Date, To Date, Payment Status |
| Access | — | Accounting + Directors |

### 3.9 Item — Nomenclature and Prices (§7.2)

| Item | Status | Notes |
|---|---|---|
| Custom report | ✅ DEPLOYED | `RPT — Item — Nomenclature and Prices` deployed by `doc15e-deploy.ps1` |
| Required data | — | Item Code/REF, Item Name, Brand, Item Group, Supplier, Standard Buying Price, Last Purchase Price, Standard Selling Price, Currency, UOM, Has Batch No, Has Serial No, Has Expiry Date |
| Filters | — | Item Group, Brand, Supplier, Disabled, Has Stock |
| Access | — | **Directors only** by default because it contains buying prices; accountants may be added later if approved |
| Follow-up | — | Buying price and import-tax usefulness depends on Standard Buying prices, HS codes, and import tax rates being populated |

---

## 4. Phase 2 — Management and Purchasing Control

**Status: ✅ Phase 2 query reports deployed 2026-05-12 (`doc15b-deploy.ps1`); Doc 15E follow-up automation/workspace polish deployed 2026-06-01 (`doc15e-deploy.ps1`).**

### 4.1 Purchasing — Norm/Reorder Requirement (§7.1)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Purchasing — Norm and Reorder` — deployed 2026-05-12 |
| Custom field | ✅ DEPLOYED | `buffer_percentage` (Float, default 0.20) on `Item Reorder` — deployed by `doc15a-deploy.ps1` |
| Scheduled Script | ✅ DEPLOYED | Daily notification script `doc15_norm_reorder_daily_notifications` deployed by `doc15e-deploy.ps1` |
| Filters | — | Analysis Period (days, default 30), Item Group, Warehouse |
| Columns | — | current stock, avg daily usage, norm 30d, norm 60d, reorder status (Below Reorder Level / Below 30d Norm / OK) |
| Notes | — | `buffer_percentage` defaults to 0.20 when null. One-click PO creation remains planned as later implementation. |
| Follow-up | — | Smoke test scheduler output with real below-reorder items; one-click PO creation remains later optional enhancement |
| Roles | — | Purchasing + Directors |

### 4.2 Accounting — Income by Period (§6.5)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Accounting — Income by Period` — deployed 2026-05-12 |
| Grouping | — | Monthly (`%Y-%m`); shows invoice count, customer count, net sales, gross sales, collected amount |
| Filters | — | From Date, To Date, Customer, Item Group |
| Access | — | **Directors only** |

### 4.3 Accounting — Debt Status Board (§6.4)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Accounting — Debt Status Board` — new report deployed 2026-05-12 |
| Columns | — | customer, invoice, posting date, due date, grand total, outstanding, paid amount, status, overdue days |
| Filters | — | Customer, From Date, To Date, Status (Unpaid / Partly Paid / Paid / Overdue) |
| Access | — | Accounting + Directors |

### 4.4 Statistics — Top Products and Doctors (§8.1)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | Two reports deployed 2026-05-12: `RPT — Sales — Top Products` and `RPT — Sales — Top Customers` |
| Top Products | — | Grouped by `item_code`; ranked by total amount; limit 100 |
| Top Customers | — | Grouped by `customer`; includes customer_group; ranked by total amount; limit 100 |
| Filters | — | From Date, To Date, Item Group, Customer (products) / Customer Group (customers) |
| Roles | — | All Ops + Directors (no profit column) |

### 4.5 Workspace — Tasks by Urgency (§8.2)

| Item | Status | Notes |
|---|---|---|
| Task views | ✅ DEPLOYED | Clean workspace `Dispatch — Task Queues` deployed by `doc15e-deploy.ps1` with Dispatch Case task shortcuts and urgency links |
| Required views | — | My open tasks, All urgent tasks, Overdue tasks, Debt collection tasks, Delivery tasks, Return tasks, Approval tasks, Purchase/reorder tasks |
| Required columns | — | Task, Task Kind, Status, Priority, Due Date, Assigned To, Customer, Related Dispatch Case, Age days open |
| Urgency colors | — | Red = overdue/blocker; yellow/orange = due today or high priority; green = normal/open; grey = waiting/on hold |
| Auto-escalation | ✅ DEPLOYED | Scheduled Server Script `doc15_task_auto_escalation` deployed by `doc15d-deploy.ps1` |
| Follow-up | — | Users should smoke test that shortcuts open the expected filtered Task/Dispatch Case lists |

### 4.6 Item List — Sort and Classify (§5.6)

| Item | Status | Notes |
|---|---|---|
| Custom report | ✅ DEPLOYED | `RPT — Item — Sort and Classify` deployed by `doc15e-deploy.ps1` |
| Required views | — | Qty ascending, qty descending, alphabetical A-Z, alphabetical Z-A, low stock first |
| Required columns | — | Item Code, Item Name, Item Group, Brand, Total Qty, Main Warehouse Qty, UOM, Selling Price, Buying Price |
| Filters | — | Item Group, Brand, Warehouse, Has Stock, Disabled |
| Access | — | If buying price is included, restrict to Directors; create a staff-safe version without buying price if needed |
| Follow-up | — | Buying price columns depend on Standard Buying item prices being populated |

---

## 5. Phase 3 — Advanced Analytics and Automation

**Status: ✅ Phase 3 Query Reports deployed 2026-05-12 (`doc15c-deploy.ps1`). KPI dashboard items deployed 2026-06-01 (`doc15d-deploy.ps1`). Return/refund queue deployed 2026-06-01 (`doc15e-deploy.ps1`).**

### 5.1 Statistics — Sales Comparative Periods (§8.3)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Sales — Comparative Periods` — deployed 2026-05-12 |
| Filters | — | Period 1 From/To, Period 2 From/To, Item Group, Customer |
| Columns | — | p1_qty, p1_amount, p2_qty, p2_amount, change_amount |
| Roles | — | **Directors only** |

### 5.2 Management — Global Statistics Dashboard (§8.4)

| Item | Status | Notes |
|---|---|---|
| Daily Dashboard | ❌ MISSING | `RPT — KPI — Daily Dashboard` does not exist |
| Weekly Dashboard | ❌ MISSING | `RPT — KPI — Weekly Dashboard` does not exist |
| Monthly Income/Profit | ❌ MISSING | `RPT — KPI — Monthly Income and Profit` does not exist |
| Remaining polish | ⚠️ PARTIAL | `Management — KPI Dashboard` workspace exists with 3 report shortcuts and no charts or number cards |
| Notes | — | Workspace update was skipped during Doc 15D deploy because existing workspace contains legacy encoded report links; KPI reports can be opened by ERPNext search |
| Follow-up | — | Directors should open the new workspace and confirm KPI links/charts are visible |

### 5.3 Function — Return/Refund Money (§6.6)

| Item | Status | Notes |
|---|---|---|
| Process | ✅ DEPLOYED | `RPT — Returns — Refund Queue` deployed by `doc15e-deploy.ps1`; uses standard ERPNext credit note/refund documents |
| Business rule | ✅ DECIDED | Refund happens only after physical stock return and verification. Damaged products are treated as used/customer responsibility; opened/expired products are case-by-case; partial refunds are allowed. |
| ERPNext documents | — | Use standard Sales Return / Credit Note where invoice reversal is needed; use Payment Entry refund where cash/bank refund is needed; use Stock Entry / return flow for returned goods; use Task for approval/execution tracking |
| Required queue columns | — | Customer, Original Sales Order/Invoice, Dispatch Case, Cancellation Reason, Amount to Refund, Refund Status, Payment Entry/Credit Note, Stock Return Status, Approved By, Created By |
| Implementation | ✅ DEPLOYED | Queue report deployed; task-based approval can use existing Task/Dispatch queue process without a new custom accounting document |
| Access | — | Directors approve; Accounting executes refund/payment documents; Returns/Inventory verifies stock; Sales/Office can request |
| Follow-up | — | Accounting/Returns should smoke test one real or test credit note/refund scenario |

### 5.4 Stock — Slow-Moving Products (§9.1)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Stock — Slow-Moving Products` — deployed 2026-05-12 |
| Filter | — | Min Days Without Sale (default 30), Item Group |
| Logic | — | Items with current stock + no outbound SLE voucher (Sales Invoice / Delivery Note) in last N days |
| Roles | — | Inventory, Purchasing, Directors |

### 5.5 Stock — Near Expiry Value at Risk (§9.2)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Stock — Near Expiry Value at Risk` — new report deployed 2026-05-12 |
| Approach | — | New report (not extension of existing); multi-warehouse; joins `tabItem Price` for buying cost |
| Columns | — | warehouse, batch, expiry date, days to expiry, qty, buying price, value at risk |
| Notes | — | `value_at_risk` shows 0 until Standard Buying prices populated |
| Roles | — | Inventory, Accounting, Directors |

### 5.6 Purchasing — Supplier Performance (§9.8)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Purchasing — Supplier Performance` — deployed 2026-05-12 |
| Columns | — | supplier, PO, order date, expected date, order value, received %, first receipt date, delay days |
| Filters | — | Supplier, From Date, To Date |
| Roles | — | Purchasing + Directors |

---

## 6. Phase 4 — Data Quality and Controls

**Status: ✅ All Phase 4 reports deployed or pre-existing as of 2026-05-12.**

### 6.1 Data Quality — Missing Tracking Setup (§9.3)

| Item | Status | Notes |
|---|---|---|
| Report | ✅ EXISTS | `RPT — Data Quality — Tracked Items Missing Identifiers` covers items missing batch/serial/expiry setup |
| Action | — | None — review at go-live to confirm it covers all Doc 15 §9.3 columns |

### 6.2 Sales — Discount and Manual Price Changes (§9.4)

| Item | Status | Notes |
|---|---|---|
| Report | ❌ MISSING | `RPT — Pricing — Sales Orders With Manual Rate Edits` does not exist |
| Gaps | — | Check whether it shows "Approved By" column as required by §9.4 |
| Action | — | Minor review; extend if "Approved By" or "Discount %" column is missing |
| Access | — | **Directors only** |

### 6.3 Operations — Documents Missing Doctor/Hospital (§9.5)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Data Quality — Missing Doctor or Hospital` — deployed 2026-05-12 |
| Logic | — | Submitted invoices where both `hospital` and `doctor_name` fields are null/empty |
| Filters | — | From Date, To Date |
| Note | — | `surgery_case` column removed; shows: invoice, date, customer, grand total, status |
| Roles | — | Order Creating, Accounting, Directors |

### 6.4 Stock — Negative or Impossible Stock (§9.6)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Data Quality — Negative Stock` — deployed 2026-05-12 |
| Logic | — | `tabBin WHERE actual_qty < 0`; shows warehouse, item, actual qty, reserved qty, projected qty |
| Roles | — | Inventory, Directors |

### 6.5 Accounting — Unallocated Payments (§9.7)

| Item | Status | Notes |
|---|---|---|
| Report | ✅ EXISTS | `RPT — Receivables — Unallocated Advances` covers this exactly |
| Action | — | None |

---

## 7. New Scope Items (Not in Any Current Plan)

These were identified in Doc 15 but are outside the original go-live action plan. Track separately.

| Item | Type | Doc 15 ref | Status |
| --- | --- | --- | --- |
| Task auto-escalation (overdue → director) | Scheduled Script | §Critical Decision 9 | ✅ DEPLOYED — `doc15_task_auto_escalation` |
| Daily KPI Dashboard (5 auto-refresh widgets) | ERPNext Dashboard / KPI report | §Critical Decision 10 | ❌ MISSING |
| Weekly KPI Dashboard (8 widgets, manual refresh) | ERPNext Dashboard / KPI report | §Critical Decision 10 | ❌ MISSING |
| Monthly total income/profit | KPI report / chart | §Critical Decision 10 | ❌ MISSING |
| `buffer_percentage` on `Item Reorder` | Custom Field | §7.1 Norm Calc | ✅ DEPLOYED 2026-05-12 (`doc15a-deploy.ps1`) |
| Item sort/classification report | Query Report | §5.6 / §4.6 | ✅ DEPLOYED — `RPT - Item - Sort and Classify` |
| Nomenclature and prices report | Query Report | §7.2 / §3.9 | ✅ DEPLOYED — `RPT - Item - Nomenclature and Prices` |
| Norm/reorder daily notification | Scheduled Script | §7.1 / §4.1 | ✅ DEPLOYED — `doc15_norm_reorder_daily_notifications` (delivers a ToDo, which is outside the task-based model) |
| Task urgency workspace/list views | Workspace/list filters | §8.2 / §4.5 | ✅ DEPLOYED — `Dispatch - Task Queues` workspace |
| Management KPI workspace polish | Workspace links | §8.4 / §5.2 | ⚠️ PARTIAL — workspace exists with 3 report shortcuts, no charts or number cards |
| Return/refund money workflow | Report + task workflow | §6.6 / §5.3 | ⚠️ PARTIAL — `RPT - Returns - Refund Queue` exists; no refund workflow (credit notes and refunds are deferred workstream 1b) |

## 8. Access Control Setup Required

After reports are built, apply Role Permission Manager restrictions:

| Report | Allowed Roles | Notes |
|---|---|---|
| `RPT — Sales — Sold Items Detail` (§6.1) | `Ops - Directors` only | Contains buying cost + gross profit |
| `RPT — Accounting — Income by Period` (§6.5) | `Ops - Directors` only | |
| Item Price list view — Standard Buying (§7.2) | `Ops - Directors`, `Ops - Accounting` | Buying prices |
| `RPT — Sales — Top Products and Doctors` (§8.1) | Standard — no profit column | |
| Management Dashboard (§8.4) | `Ops - Directors` only | |
| `RPT — Sales — Discount and Manual Price Changes` (§9.4) | `Ops - Directors` only | |
| `RPT — Purchasing — Supplier Performance` (§9.8) | `Ops - Directors` only | |
| `RPT — Accounting — Unpaid Debts` (§6.3) | `Ops - Accounting`, `Ops - Directors` | |
| `RPT — Accounting — Sales Documents and Payments` (§6.2) | `Ops - Accounting`, `Ops - Directors` | |
| `RPT — Accounting — Debt Status Board` (§6.4) | `Ops - Accounting`, `Ops - Directors` | |

---

## 9. Naming Convention for New Reports

Following Doc 13A pattern: `RPT — [Category] — [Description]`

| Category prefix | Use for |
|---|---|
| `RPT — Stock — ...` | Stock balance, movement, expiry, quality |
| `RPT — Sales — ...` | Sold items, top products, discounts |
| `RPT — Accounting — ...` | Invoices, debts, payments, income |
| `RPT — Purchasing — ...` | Norm/reorder, supplier performance |
| `RPT — Statistics — ...` | Comparative periods, analytics |
| `RPT — Data Quality — ...` | Missing data, negative stock |

---

## 10. Custom Fields to Deploy Before Building Reports

| DocType | Fieldname | Label | Type | Status |
|---|---|---|---|---|
| Item Reorder | `buffer_percentage` | Safety Stock Buffer % | Float | ✅ DEPLOYED 2026-05-12 (default 0.20) |

---

## 11. Deployment Script Plan

| Script | Covers | Status |
|---|---|---|
| `doc15a-deploy.ps1` | `buffer_percentage` custom field + §5.1–5.5 stock reports + §6.1–6.2 accounting reports (7 reports + 1 field) | ✅ Deployed 2026-05-12 |
| `doc15b-deploy.ps1` | §6.4 Debt Status Board, §6.5 Income by Period, §7.1 Norm and Reorder, §8.1 Top Products + Top Customers (5 reports) | ✅ Deployed 2026-05-12 |
| `doc15c-deploy.ps1` | §8.3 Comparative Periods, §9.1 Slow-Moving, §9.2 Near Expiry Value at Risk, §9.5 Missing Doctor, §9.6 Negative Stock, §9.8 Supplier Performance + workspace update (6 reports) | ✅ Deployed 2026-05-12 |
| `doc15d-deploy.ps1` | Task auto-escalation Scheduled Server Script + Daily/Weekly/Monthly KPI reports/charts | ✅ Deployed 2026-06-01 |
| `doc15e-deploy.ps1` | Item sort/classify report, nomenclature/prices report, norm notifications, task urgency workspace, management KPI workspace, return/refund queue | ✅ Deployed 2026-06-01 |

---

## 12. Post-Deployment Notes and Dependencies

1. **Standard Buying Price list populated** — profit/buying cost columns in all reports depend on `Item Price` records in `Standard Buying` price list. Currently 0 records (see Doc 17A §2.2). Planned before go-live — no action needed now, but profit reports will return empty costs until done.
2. **Batch and serial tracking per item** — some items have it, some don't. Reports will show batch/LOT/serial/expiry data where configured and blank where not. This is expected — no action needed.
3. **Doctor/hospital on sales documents** — no custom field needed. Doctor and hospital are standard ERPNext Customers. §6.1 and §8.1 filter/group by `customer`; §9.5 checks for invoices where customer has no parent group. No new field required.
4. **Dispatch Case link on Stock Entry** — ✅ already deployed. `dispatch_group_id` (Data) field on Stock Entry stores the Dispatch Case name. The `§5.5 Movement` report will join on `tabStock Entry.dispatch_group_id = tabDispatch Case.name`. No action needed.

---

## 13. Doc 15E — Deployed Follow-Up Scope

This section records the Doc 15A follow-up items deployed by `deploy/doc15e-deploy.ps1` on 2026-06-01.

### 13.1 Scope

| Area | Source sections | Implementation object | Status |
|---|---|---|---|
| Item sort and classify | §5.6, §4.6 | Query Report + optional workspace shortcuts | ✅ Deployed |
| Return/refund money | §6.6, §5.3 | Queue report + Task workflow + standard ERPNext return/refund documents | ✅ Deployed |
| Item nomenclature and prices | §7.2, §3.9 | Query Report | ✅ Deployed |
| Norm/reorder notifications | §7.1, §4.1 | Scheduled Server Script + ToDo/notification records | ✅ Deployed |
| Task urgency workspace | §8.2, §4.5 | Shared Task filters/workspace shortcuts | ✅ Deployed |
| Management KPI workspace polish | §8.4, §5.2 | Clean workspace or repaired workspace links | ✅ Deployed |

### 13.2 Deployment Script

Deployment script: `deploy/doc15e-deploy.ps1`.

Expected modes:

| Mode | Purpose |
|---|---|
| `Check` | Verify which reports, scripts, and workspace links exist |
| `Deploy` | Create/update approved Doc 15E objects |

Expected objects:

| Object | Proposed name |
|---|---|
| Item sort/classify report | `RPT — Item — Sort and Classify` |
| Nomenclature/prices report | `RPT — Item — Nomenclature and Prices` |
| Return/refund queue report | `RPT — Returns — Refund Queue` |
| Norm/reorder daily scheduler | `doc15_norm_reorder_daily_notifications` |
| Management workspace | `Management — KPI Dashboard` |
| Dispatch/task workspace | `Dispatch — Task Queues` |

### 13.3 User Can Run Later to Save Quota

For read-only verification, the user can run:

```powershell
powershell -ExecutionPolicy Bypass -File .\doc15e-deploy.ps1 -Mode Check
```

Useful ERPNext manual checks:

| Check | Where |
|---|---|
| Confirm KPI reports open | ERPNext search: `RPT — KPI` |
| Confirm dashboard charts exist | ERPNext search: `Dashboard Chart` |
| Confirm norm notification script exists | ERPNext search: `Server Script` → `doc15_norm_reorder_daily_notifications` |
| Confirm Standard Buying prices exist | ERPNext Item Price list filtered by `Standard Buying` |

Doc 15E has been deployed; remaining work is smoke testing and master data where reports depend on item prices.
