# Doc 15A — Reporting Requirements: Implementation Status and Build Plan

**References:** Doc 15 — Reporting and Functions Requirements Review  
**Planning snapshot:** 2026-05-11  
**Deployed:** 2026-05-12 (all three scripts: `doc15a`, `doc15b`, `doc15c`)  
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
| ✅ EXISTS (deployed or pre-existing) | 21 |
| ⚠️ PARTIAL (task auto-escalation not yet built) | 1 |
| 🔧 NATIVE (ERPNext config, no code needed) | 2 |
| 🚫 NEW SCOPE (deferred — global dashboard) | 1 |
| ❌ MISSING (deferred — return/refund function) | 1 |
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
| §5.6 | Item List — Sort and Classify | — (ERPNext Item list) | 🔧 NATIVE |
| §6.1 | Sales — Sold Items Detail | `RPT — Sales — Sold Items Detail` | ✅ EXISTS |
| §6.2 | Accounting — Sales Documents and Payments | `RPT — Accounting — Sales Documents and Payments` | ✅ EXISTS |
| §6.3 | Accounting — Unpaid Debts | `RPT — Receivables — Unpaid Invoices (Aging)` | ✅ EXISTS |
| §6.4 | Accounting — Debt Status Board | `RPT — Accounting — Debt Status Board` | ✅ EXISTS |
| §6.5 | Accounting — Income by Period | `RPT — Accounting — Income by Period` | ✅ EXISTS |
| §6.6 | Function — Return/Refund Money | — | ❌ MISSING |
| §7.1 | Purchasing — Norm/Reorder Requirement | `RPT — Purchasing — Norm and Reorder` | ✅ EXISTS |
| §7.2 | Item — Nomenclature and Prices | — (ERPNext Item + Item Price list) | 🔧 NATIVE |
| §8.1 | Statistics — Top Products and Doctors | `RPT — Sales — Top Products` + `RPT — Sales — Top Customers` | ✅ EXISTS |
| §8.2 | Workspace — Tasks by Urgency | `Ops — Reporting Pack` task views (auto-escalation pending) | ⚠️ PARTIAL |
| §8.3 | Statistics — Sales Comparative Periods | `RPT — Sales — Comparative Periods` | ✅ EXISTS |
| §8.4 | Management — Global Statistics Dashboard | — | 🚫 NEW SCOPE |
| §9.1 | Stock — Slow-Moving Products | `RPT — Stock — Slow-Moving Products` | ✅ EXISTS |
| §9.2 | Stock — Near Expiry Value at Risk | `RPT — Stock — Near Expiry Value at Risk` | ✅ EXISTS |
| §9.3 | Data Quality — Missing Tracking Setup | `RPT — Data Quality — Tracked Items Missing Identifiers` | ✅ EXISTS |
| §9.4 | Sales — Discount and Manual Price Changes | `RPT — Pricing — Sales Orders With Manual Rate Edits` | ✅ EXISTS |
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
| Note | — | `surgery_case` column removed; no `dispatch_case` field exists on Sales Invoice |
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
| Custom report | 🔧 NATIVE | No custom code needed — ERPNext Item list + Item Price list provide all columns |
| Action | — | 1) Open Item list; configure visible columns (Item Code, Item Name, Item Group, Brand, UOM, Has Batch, Has Expiry); save as shared view; 2) Open Item Price list filtered to Standard Buying; save as shared view for admins/accountants only |
| Access | — | **Directors only** (contains buying prices) — restrict via Role Permission Manager on `Item Price` |

---

## 4. Phase 2 — Management and Purchasing Control

**Status: ✅ All Phase 2 reports deployed 2026-05-12 (`doc15b-deploy.ps1`)**

### 4.1 Purchasing — Norm/Reorder Requirement (§7.1)

| Item | Status | Notes |
|---|---|---|
| Query Report | ✅ DEPLOYED | `RPT — Purchasing — Norm and Reorder` — deployed 2026-05-12 |
| Custom field | ✅ DEPLOYED | `buffer_percentage` (Float, default 0.20) on `Item Reorder` — deployed by `doc15a-deploy.ps1` |
| Scheduled Script | 🚫 NEW SCOPE | Daily auto-recalculation deferred — report is on-demand only for now |
| Filters | — | Analysis Period (days, default 30), Item Group, Warehouse |
| Columns | — | current stock, avg daily usage, norm 30d, norm 60d, reorder status (Below Reorder Level / Below 30d Norm / OK) |
| Notes | — | `buffer_percentage` defaults to 0.20 when null. One-click PO creation deferred to Phase 3. |
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
| Task views | ⚠️ PARTIAL | `Ops — Reporting Pack` workspace has 6 task kind shortcuts — adequate for now |
| Action remaining | — | Named saved views (My Tasks, All Urgent, Overdue) are manual per-user steps |
| Auto-escalation | 🚫 NEW SCOPE | Scheduled Script to assign overdue tasks to director — deferred, not scripted |

### 4.6 Item List — Sort and Classify (§5.6)

| Item | Status | Notes |
|---|---|---|
| Custom report | 🔧 NATIVE | ERPNext Item list view — configure columns, apply sort, save as shared shortcuts |
| Action | — | Create 4 saved Item list shortcuts: by qty asc / desc, alphabetical A-Z / Z-A. Add to workspace. ~15 min setup. |

---

## 5. Phase 3 — Advanced Analytics and Automation

**Status: ✅ All Phase 3 Query Reports deployed 2026-05-12 (`doc15c-deploy.ps1`). Dashboard and function items remain deferred.**

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
| Daily Dashboard | ❌ MISSING 🚫 NEW SCOPE | ERPNext Dashboard object — 5 number card KPIs, auto-refresh |
| Weekly Dashboard | ❌ MISSING 🚫 NEW SCOPE | ERPNext Dashboard object — 8 chart/table widgets, manual refresh |
| Notes | — | Requires most Phase 1/2 reports to be built first as data sources |

### 5.3 Function — Return/Refund Money (§6.6)

| Item | Status | Notes |
|---|---|---|
| Process | ❌ MISSING | No dedicated return/refund task queue or workspace built — deferred |
| Notes | — | Refund document type (Credit Note vs Payment Entry) still TBD per §10.6. No unblocking dependency on other reports. Schedule as separate small implementation. |

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
| Report | ✅ EXISTS | `RPT — Pricing — Sales Orders With Manual Rate Edits` covers manual rate deviations |
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
| Task auto-escalation (overdue → director) | Scheduled Script | §Critical Decision 9 | 🚫 NEW SCOPE — not scripted |
| Daily KPI Dashboard (5 auto-refresh widgets) | ERPNext Dashboard object | §Critical Decision 10 | 🚫 NEW SCOPE — not scripted |
| Weekly KPI Dashboard (8 widgets, manual refresh) | ERPNext Dashboard object | §Critical Decision 10 | 🚫 NEW SCOPE — not scripted |
| `buffer_percentage` on `Item Reorder` | Custom Field | §7.1 Norm Calc | ✅ DEPLOYED 2026-05-12 (`doc15a-deploy.ps1`) |

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

---

## 12. Post-Deployment Notes and Dependencies

1. **Standard Buying Price list populated** — profit/buying cost columns in all reports depend on `Item Price` records in `Standard Buying` price list. Currently 0 records (see Doc 17A §2.2). Planned before go-live — no action needed now, but profit reports will return empty costs until done.
2. **Batch and serial tracking per item** — some items have it, some don't. Reports will show batch/LOT/serial/expiry data where configured and blank where not. This is expected — no action needed.
3. **Doctor/hospital on sales documents** — no custom field needed. Doctor and hospital are standard ERPNext Customers. §6.1 and §8.1 filter/group by `customer`; §9.5 checks for invoices where customer has no parent group. No new field required.
4. **Dispatch Case link on Stock Entry** — ✅ already deployed. `dispatch_group_id` (Data) field on Stock Entry stores the Dispatch Case name. The `§5.5 Movement` report will join on `tabStock Entry.dispatch_group_id = tabDispatch Case.name`. No action needed.
