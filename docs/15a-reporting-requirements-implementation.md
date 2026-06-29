# Doc 15A â€” Reporting Requirements: Implementation Status and Build Plan

**References:** Doc 15 â€” Reporting and Functions Requirements Review  
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
| âœ… EXISTS | In prod â€” no action needed |
| âš ï¸ PARTIAL | In prod but scope is narrower than Doc 15 requires â€” needs extension |
| ðŸ”§ NATIVE | Provided by ERPNext out-of-the-box â€” needs only manual configuration (no code) |
| âŒ MISSING | Does not exist â€” must be built |
| ðŸš« NEW SCOPE | Out of original go-live plan â€” schedule separately |

---

## 1. Summary Scorecard

| Status | Count |
|---|---|
| âœ… EXISTS (deployed or pre-existing) | 26 |
| âš ï¸ PARTIAL (needs implementation-ready follow-up) | 0 |
| ðŸ”§ NATIVE (ERPNext config, no code needed) | 0 |
| âŒ MISSING (ready for implementation plan) | 0 |
| **Total** | **26** |

---

## 2. Full Status Table â€” All 26 Reports

| Doc 15 Â§ | Report / Function | Prod report name (if any) | Status |
|---|---|---|---|
| Â§5.1 | Stock Balance â€” Multi-Select | `RPT â€” Stock â€” Balance Multi-Select` | âœ… EXISTS |
| Â§5.2 | Stock Balance â€” Batch and Expiry | `RPT â€” Stock â€” Batch and Expiry Balance` | âœ… EXISTS |
| Â§5.3 | Stock â€” Expirable / Non-Expirable / Expired | `RPT â€” Stock â€” Expiry Classification` | âœ… EXISTS |
| Â§5.4 | Stock Entry â€” By Day/Period | `RPT â€” Stock â€” Entries by Period` | âœ… EXISTS |
| Â§5.5 | Stock Movement â€” Warehouse to Warehouse | `RPT â€” Stock â€” Warehouse Movement` | âœ… EXISTS |
| Â§5.6 | Item List â€” Sort and Classify | `RPT â€” Item â€” Sort and Classify` | âœ… EXISTS |
| Â§6.1 | Sales â€” Sold Items Detail | `RPT â€” Sales â€” Sold Items Detail` | âœ… EXISTS |
| Â§6.2 | Accounting â€” Sales Documents and Payments | `RPT â€” Accounting â€” Sales Documents and Payments` | âœ… EXISTS |
| Â§6.3 | Accounting â€” Unpaid Debts | `RPT â€” Receivables â€” Unpaid Invoices (Aging)` | âœ… EXISTS |
| Â§6.4 | Accounting â€” Debt Status Board | `RPT â€” Accounting â€” Debt Status Board` | âœ… EXISTS |
| Â§6.5 | Accounting â€” Income by Period | `RPT â€” Accounting â€” Income by Period` | âœ… EXISTS |
| Â§6.6 | Function â€” Return/Refund Money | `RPT â€” Returns â€” Refund Queue` + standard ERPNext return/refund documents | âœ… EXISTS |
| Â§7.1 | Purchasing â€” Norm/Reorder Requirement | `RPT â€” Purchasing â€” Norm and Reorder` | âœ… EXISTS |
| Â§7.2 | Item â€” Nomenclature and Prices | `RPT â€” Item â€” Nomenclature and Prices` | âœ… EXISTS |
| Â§8.1 | Statistics â€” Top Products and Doctors | `RPT â€” Sales â€” Top Products` + `RPT â€” Sales â€” Top Customers` | âœ… EXISTS |
| Â§8.2 | Workspace â€” Tasks by Urgency | `doc15_task_auto_escalation` + `Dispatch â€” Task Queues` workspace | âœ… EXISTS |
| Â§8.3 | Statistics â€” Sales Comparative Periods | `RPT â€” Sales â€” Comparative Periods` | âœ… EXISTS |
| Â§8.4 | Management â€” Global Statistics Dashboard | `RPT â€” KPI â€” Daily Dashboard`, `RPT â€” KPI â€” Weekly Dashboard`, `RPT â€” KPI â€” Monthly Income and Profit` + dashboard charts | âœ… EXISTS |
| Â§9.1 | Stock â€” Slow-Moving Products | `RPT â€” Stock â€” Slow-Moving Products` | âœ… EXISTS |
| Â§9.2 | Stock â€” Near Expiry Value at Risk | `RPT â€” Stock â€” Near Expiry Value at Risk` | âœ… EXISTS |
| Â§9.3 | Data Quality â€” Missing Tracking Setup | `RPT â€” Data Quality â€” Tracked Items Missing Identifiers` | âœ… EXISTS |
| Â§9.4 | Sales â€” Discount and Manual Price Changes | `RPT â€” Pricing â€” Sales Orders With Manual Rate Edits` | âœ… EXISTS |
| Â§9.5 | Operations â€” Documents Missing Doctor/Hospital | `RPT â€” Data Quality â€” Missing Doctor or Hospital` | âœ… EXISTS |
| Â§9.6 | Stock â€” Negative or Impossible Stock | `RPT â€” Data Quality â€” Negative Stock` | âœ… EXISTS |
| Â§9.7 | Accounting â€” Unallocated Payments | `RPT â€” Receivables â€” Unallocated Advances` | âœ… EXISTS |
| Â§9.8 | Purchasing â€” Supplier Performance | `RPT â€” Purchasing â€” Supplier Performance` | âœ… EXISTS |

---

## 3. Phase 1 â€” Must-Have Operational Visibility

**Status: âœ… All Phase 1 reports deployed 2026-05-12 (`doc15a-deploy.ps1`)**

### 3.1 Stock Balance â€” Multi-Select (Â§5.1)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Stock â€” Balance Multi-Select` â€” deployed 2026-05-12 |
| Filters | â€” | Warehouse, Item Code, Item Group, Brand |
| Roles | â€” | All Ops roles + Directors |

### 3.2 Stock Balance â€” Batch and Expiry (Â§5.2)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Stock â€” Batch and Expiry Balance` â€” new report deployed 2026-05-12 |
| Approach | â€” | New report (not extension of existing); CASE-based `expiry_status` column: Expired / Near Expiry (â‰¤30d) / Valid / No Expiry |
| Filters | â€” | Warehouse, Item Code, Item Group |
| Roles | â€” | Inventory, Returns, Directors |

### 3.3 Stock â€” Expirable / Non-Expirable / Expired (Â§5.3)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Stock â€” Expiry Classification` â€” deployed 2026-05-12 |
| Filters | â€” | Item Group, Expiry Tracking (Expirable / Non-Expirable) |
| Roles | â€” | Inventory, Purchasing, Directors |

### 3.4 Stock Entry â€” By Day/Period (Â§5.4)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Stock â€” Entries by Period` â€” deployed 2026-05-12 |
| Filters | â€” | From Date, To Date, Warehouse, Item Code, Item Group, Entry Type |
| Columns | â€” | Includes `dispatch_group_id` as Dispatch Case identifier; `surgery_case` column removed |
| Roles | â€” | All Ops roles + Directors |

### 3.5 Stock Movement â€” Warehouse to Warehouse (Â§5.5)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Stock â€” Warehouse Movement` â€” deployed 2026-05-12 |
| Filters | â€” | From Date, To Date, From Warehouse, To Warehouse, Item Code, Dispatch Case |
| Notes | â€” | Dispatch Case filter uses `se.dispatch_group_id` (Data field on Stock Entry, deployed by Doc 16A); `surgery_case` column removed |
| Roles | â€” | Inventory, Order Accepting, Returns, Delivery Driver, Directors |

### 3.6 Sales â€” Sold Items Detail (Â§6.1)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Sales â€” Sold Items Detail` â€” new report deployed 2026-05-12 |
| Columns | â€” | Full set: customer, hospital, doctor, payment status, qty, selling price, buying price, gross profit, batch, serial, sales order |
| Note | â€” | `surgery_case` column removed; no `dispatch_case` field exists on Sales Invoice |
| Buying cost | â€” | Joined from `tabItem Price` (`price_list = 'Standard Buying'`). Returns 0 until Standard Buying prices populated. |
| Access | â€” | **Directors only** â€” profit column |

### 3.7 Accounting â€” Unpaid Debts (Â§6.3)

| Item | Status | Notes |
|---|---|---|
| Existing report | âœ… EXISTS | `RPT â€” Receivables â€” Unpaid Invoices (Aging)` adequate for Â§6.3 core requirement |
| Notes | â€” | Covers unpaid/overdue aging. Phone/task link columns identified as minor gaps â€” deferred. |
| Access | â€” | Accounting + Directors |

### 3.8 Accounting â€” Sales Documents and Payments (Â§6.2)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Accounting â€” Sales Documents and Payments` â€” deployed 2026-05-12 |
| Filters | â€” | Customer, From Date, To Date, Payment Status |
| Access | â€” | Accounting + Directors |

### 3.9 Item â€” Nomenclature and Prices (Â§7.2)

| Item | Status | Notes |
|---|---|---|
| Custom report | âœ… DEPLOYED | `RPT â€” Item â€” Nomenclature and Prices` deployed by `doc15e-deploy.ps1` |
| Required data | â€” | Item Code/REF, Item Name, Brand, Item Group, Supplier, Standard Buying Price, Last Purchase Price, Standard Selling Price, Currency, UOM, Has Batch No, Has Serial No, Has Expiry Date |
| Filters | â€” | Item Group, Brand, Supplier, Disabled, Has Stock |
| Access | â€” | **Directors only** by default because it contains buying prices; accountants may be added later if approved |
| Follow-up | â€” | Buying price and import-tax usefulness depends on Standard Buying prices, HS codes, and import tax rates being populated |

---

## 4. Phase 2 â€” Management and Purchasing Control

**Status: âœ… Phase 2 query reports deployed 2026-05-12 (`doc15b-deploy.ps1`); Doc 15E follow-up automation/workspace polish deployed 2026-06-01 (`doc15e-deploy.ps1`).**

### 4.1 Purchasing â€” Norm/Reorder Requirement (Â§7.1)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Purchasing â€” Norm and Reorder` â€” deployed 2026-05-12 |
| Custom field | âœ… DEPLOYED | `buffer_percentage` (Float, default 0.20) on `Item Reorder` â€” deployed by `doc15a-deploy.ps1` |
| Scheduled Script | âœ… DEPLOYED | Daily notification script `doc15_norm_reorder_daily_notifications` deployed by `doc15e-deploy.ps1` |
| Filters | â€” | Analysis Period (days, default 30), Item Group, Warehouse |
| Columns | â€” | current stock, avg daily usage, norm 30d, norm 60d, reorder status (Below Reorder Level / Below 30d Norm / OK) |
| Notes | â€” | `buffer_percentage` defaults to 0.20 when null. One-click PO creation remains planned as later implementation. |
| Follow-up | â€” | Smoke test scheduler output with real below-reorder items; one-click PO creation remains later optional enhancement |
| Roles | â€” | Purchasing + Directors |

### 4.2 Accounting â€” Income by Period (Â§6.5)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Accounting â€” Income by Period` â€” deployed 2026-05-12 |
| Grouping | â€” | Monthly (`%Y-%m`); shows invoice count, customer count, net sales, gross sales, collected amount |
| Filters | â€” | From Date, To Date, Customer, Item Group |
| Access | â€” | **Directors only** |

### 4.3 Accounting â€” Debt Status Board (Â§6.4)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Accounting â€” Debt Status Board` â€” new report deployed 2026-05-12 |
| Columns | â€” | customer, invoice, posting date, due date, grand total, outstanding, paid amount, status, overdue days |
| Filters | â€” | Customer, From Date, To Date, Status (Unpaid / Partly Paid / Paid / Overdue) |
| Access | â€” | Accounting + Directors |

### 4.4 Statistics â€” Top Products and Doctors (Â§8.1)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | Two reports deployed 2026-05-12: `RPT â€” Sales â€” Top Products` and `RPT â€” Sales â€” Top Customers` |
| Top Products | â€” | Grouped by `item_code`; ranked by total amount; limit 100 |
| Top Customers | â€” | Grouped by `customer`; includes customer_group; ranked by total amount; limit 100 |
| Filters | â€” | From Date, To Date, Item Group, Customer (products) / Customer Group (customers) |
| Roles | â€” | All Ops + Directors (no profit column) |

### 4.5 Workspace â€” Tasks by Urgency (Â§8.2)

| Item | Status | Notes |
|---|---|---|
| Task views | âœ… DEPLOYED | Clean workspace `Dispatch â€” Task Queues` deployed by `doc15e-deploy.ps1` with Dispatch Case task shortcuts and urgency links |
| Required views | â€” | My open tasks, All urgent tasks, Overdue tasks, Debt collection tasks, Delivery tasks, Return tasks, Approval tasks, Purchase/reorder tasks |
| Required columns | â€” | Task, Task Kind, Status, Priority, Due Date, Assigned To, Customer, Related Dispatch Case, Age days open |
| Urgency colors | â€” | Red = overdue/blocker; yellow/orange = due today or high priority; green = normal/open; grey = waiting/on hold |
| Auto-escalation | âœ… DEPLOYED | Scheduled Server Script `doc15_task_auto_escalation` deployed by `doc15d-deploy.ps1` |
| Follow-up | â€” | Users should smoke test that shortcuts open the expected filtered Task/Dispatch Case lists |

### 4.6 Item List â€” Sort and Classify (Â§5.6)

| Item | Status | Notes |
|---|---|---|
| Custom report | âœ… DEPLOYED | `RPT â€” Item â€” Sort and Classify` deployed by `doc15e-deploy.ps1` |
| Required views | â€” | Qty ascending, qty descending, alphabetical A-Z, alphabetical Z-A, low stock first |
| Required columns | â€” | Item Code, Item Name, Item Group, Brand, Total Qty, Main Warehouse Qty, UOM, Selling Price, Buying Price |
| Filters | â€” | Item Group, Brand, Warehouse, Has Stock, Disabled |
| Access | â€” | If buying price is included, restrict to Directors; create a staff-safe version without buying price if needed |
| Follow-up | â€” | Buying price columns depend on Standard Buying item prices being populated |

---

## 5. Phase 3 â€” Advanced Analytics and Automation

**Status: âœ… Phase 3 Query Reports deployed 2026-05-12 (`doc15c-deploy.ps1`). KPI dashboard items deployed 2026-06-01 (`doc15d-deploy.ps1`). Return/refund queue deployed 2026-06-01 (`doc15e-deploy.ps1`).**

### 5.1 Statistics â€” Sales Comparative Periods (Â§8.3)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Sales â€” Comparative Periods` â€” deployed 2026-05-12 |
| Filters | â€” | Period 1 From/To, Period 2 From/To, Item Group, Customer |
| Columns | â€” | p1_qty, p1_amount, p2_qty, p2_amount, change_amount |
| Roles | â€” | **Directors only** |

### 5.2 Management â€” Global Statistics Dashboard (Â§8.4)

| Item | Status | Notes |
|---|---|---|
| Daily Dashboard | âœ… DEPLOYED | KPI Query Report and Dashboard Chart deployed by `doc15d-deploy.ps1` |
| Weekly Dashboard | âœ… DEPLOYED | KPI Query Report and Dashboard Chart deployed by `doc15d-deploy.ps1` |
| Monthly Income/Profit | âœ… DEPLOYED | KPI Query Report and Dashboard Chart deployed by `doc15d-deploy.ps1` |
| Remaining polish | âœ… DEPLOYED | Clean `Management â€” KPI Dashboard` workspace deployed by `doc15e-deploy.ps1`; legacy `Ops â€” Reporting Pack` left unchanged |
| Notes | â€” | Workspace update was skipped during Doc 15D deploy because existing workspace contains legacy encoded report links; KPI reports can be opened by ERPNext search |
| Follow-up | â€” | Directors should open the new workspace and confirm KPI links/charts are visible |

### 5.3 Function â€” Return/Refund Money (Â§6.6)

| Item | Status | Notes |
|---|---|---|
| Process | âœ… DEPLOYED | `RPT â€” Returns â€” Refund Queue` deployed by `doc15e-deploy.ps1`; uses standard ERPNext credit note/refund documents |
| Business rule | âœ… DECIDED | Refund happens only after physical stock return and verification. Damaged products are treated as used/customer responsibility; opened/expired products are case-by-case; partial refunds are allowed. |
| ERPNext documents | â€” | Use standard Sales Return / Credit Note where invoice reversal is needed; use Payment Entry refund where cash/bank refund is needed; use Stock Entry / return flow for returned goods; use Task for approval/execution tracking |
| Required queue columns | â€” | Customer, Original Sales Order/Invoice, Dispatch Case, Cancellation Reason, Amount to Refund, Refund Status, Payment Entry/Credit Note, Stock Return Status, Approved By, Created By |
| Implementation | âœ… DEPLOYED | Queue report deployed; task-based approval can use existing Task/Dispatch queue process without a new custom accounting document |
| Access | â€” | Directors approve; Accounting executes refund/payment documents; Returns/Inventory verifies stock; Sales/Office can request |
| Follow-up | â€” | Accounting/Returns should smoke test one real or test credit note/refund scenario |

### 5.4 Stock â€” Slow-Moving Products (Â§9.1)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Stock â€” Slow-Moving Products` â€” deployed 2026-05-12 |
| Filter | â€” | Min Days Without Sale (default 30), Item Group |
| Logic | â€” | Items with current stock + no outbound SLE voucher (Sales Invoice / Delivery Note) in last N days |
| Roles | â€” | Inventory, Purchasing, Directors |

### 5.5 Stock â€” Near Expiry Value at Risk (Â§9.2)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Stock â€” Near Expiry Value at Risk` â€” new report deployed 2026-05-12 |
| Approach | â€” | New report (not extension of existing); multi-warehouse; joins `tabItem Price` for buying cost |
| Columns | â€” | warehouse, batch, expiry date, days to expiry, qty, buying price, value at risk |
| Notes | â€” | `value_at_risk` shows 0 until Standard Buying prices populated |
| Roles | â€” | Inventory, Accounting, Directors |

### 5.6 Purchasing â€” Supplier Performance (Â§9.8)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Purchasing â€” Supplier Performance` â€” deployed 2026-05-12 |
| Columns | â€” | supplier, PO, order date, expected date, order value, received %, first receipt date, delay days |
| Filters | â€” | Supplier, From Date, To Date |
| Roles | â€” | Purchasing + Directors |

---

## 6. Phase 4 â€” Data Quality and Controls

**Status: âœ… All Phase 4 reports deployed or pre-existing as of 2026-05-12.**

### 6.1 Data Quality â€” Missing Tracking Setup (Â§9.3)

| Item | Status | Notes |
|---|---|---|
| Report | âœ… EXISTS | `RPT â€” Data Quality â€” Tracked Items Missing Identifiers` covers items missing batch/serial/expiry setup |
| Action | â€” | None â€” review at go-live to confirm it covers all Doc 15 Â§9.3 columns |

### 6.2 Sales â€” Discount and Manual Price Changes (Â§9.4)

| Item | Status | Notes |
|---|---|---|
| Report | âœ… EXISTS | `RPT â€” Pricing â€” Sales Orders With Manual Rate Edits` covers manual rate deviations |
| Gaps | â€” | Check whether it shows "Approved By" column as required by Â§9.4 |
| Action | â€” | Minor review; extend if "Approved By" or "Discount %" column is missing |
| Access | â€” | **Directors only** |

### 6.3 Operations â€” Documents Missing Doctor/Hospital (Â§9.5)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Data Quality â€” Missing Doctor or Hospital` â€” deployed 2026-05-12 |
| Logic | â€” | Submitted invoices where both `hospital` and `doctor_name` fields are null/empty |
| Filters | â€” | From Date, To Date |
| Note | â€” | `surgery_case` column removed; shows: invoice, date, customer, grand total, status |
| Roles | â€” | Order Creating, Accounting, Directors |

### 6.4 Stock â€” Negative or Impossible Stock (Â§9.6)

| Item | Status | Notes |
|---|---|---|
| Query Report | âœ… DEPLOYED | `RPT â€” Data Quality â€” Negative Stock` â€” deployed 2026-05-12 |
| Logic | â€” | `tabBin WHERE actual_qty < 0`; shows warehouse, item, actual qty, reserved qty, projected qty |
| Roles | â€” | Inventory, Directors |

### 6.5 Accounting â€” Unallocated Payments (Â§9.7)

| Item | Status | Notes |
|---|---|---|
| Report | âœ… EXISTS | `RPT â€” Receivables â€” Unallocated Advances` covers this exactly |
| Action | â€” | None |

---

## 7. New Scope Items (Not in Any Current Plan)

These were identified in Doc 15 but are outside the original go-live action plan. Track separately.

| Item | Type | Doc 15 ref | Status |
| --- | --- | --- | --- |
| Task auto-escalation (overdue â†’ director) | Scheduled Script | Â§Critical Decision 9 | âœ… DEPLOYED â€” `doc15_task_auto_escalation` |
| Daily KPI Dashboard (5 auto-refresh widgets) | ERPNext Dashboard / KPI report | Â§Critical Decision 10 | âœ… DEPLOYED â€” `RPT â€” KPI â€” Daily Dashboard` |
| Weekly KPI Dashboard (8 widgets, manual refresh) | ERPNext Dashboard / KPI report | Â§Critical Decision 10 | âœ… DEPLOYED â€” `RPT â€” KPI â€” Weekly Dashboard` |
| Monthly total income/profit | KPI report / chart | Â§Critical Decision 10 | âœ… DEPLOYED â€” `RPT â€” KPI â€” Monthly Income and Profit` |
| `buffer_percentage` on `Item Reorder` | Custom Field | Â§7.1 Norm Calc | âœ… DEPLOYED 2026-05-12 (`doc15a-deploy.ps1`) |
| Item sort/classification report | Query Report | Â§5.6 / Â§4.6 | âš ï¸ READY TO IMPLEMENT â€” no ERPNext change yet |
| Nomenclature and prices report | Query Report | Â§7.2 / Â§3.9 | âš ï¸ READY TO IMPLEMENT â€” no ERPNext change yet |
| Norm/reorder daily notification | Scheduled Script | Â§7.1 / Â§4.1 | âš ï¸ READY TO IMPLEMENT â€” no ERPNext change yet |
| Task urgency workspace/list views | Workspace/list filters | Â§8.2 / Â§4.5 | âš ï¸ READY TO IMPLEMENT â€” no ERPNext change yet |
| Management KPI workspace polish | Workspace links | Â§8.4 / Â§5.2 | âš ï¸ READY TO IMPLEMENT â€” no ERPNext change yet |
| Return/refund money workflow | Report + task workflow | Â§6.6 / Â§5.3 | âš ï¸ READY TO IMPLEMENT â€” no ERPNext change yet |

## 8. Access Control Setup Required

After reports are built, apply Role Permission Manager restrictions:

| Report | Allowed Roles | Notes |
|---|---|---|
| `RPT â€” Sales â€” Sold Items Detail` (Â§6.1) | `Ops - Directors` only | Contains buying cost + gross profit |
| `RPT â€” Accounting â€” Income by Period` (Â§6.5) | `Ops - Directors` only | |
| Item Price list view â€” Standard Buying (Â§7.2) | `Ops - Directors`, `Ops - Accounting` | Buying prices |
| `RPT â€” Sales â€” Top Products and Doctors` (Â§8.1) | Standard â€” no profit column | |
| Management Dashboard (Â§8.4) | `Ops - Directors` only | |
| `RPT â€” Sales â€” Discount and Manual Price Changes` (Â§9.4) | `Ops - Directors` only | |
| `RPT â€” Purchasing â€” Supplier Performance` (Â§9.8) | `Ops - Directors` only | |
| `RPT â€” Accounting â€” Unpaid Debts` (Â§6.3) | `Ops - Accounting`, `Ops - Directors` | |
| `RPT â€” Accounting â€” Sales Documents and Payments` (Â§6.2) | `Ops - Accounting`, `Ops - Directors` | |
| `RPT â€” Accounting â€” Debt Status Board` (Â§6.4) | `Ops - Accounting`, `Ops - Directors` | |

---

## 9. Naming Convention for New Reports

Following Doc 13A pattern: `RPT â€” [Category] â€” [Description]`

| Category prefix | Use for |
|---|---|
| `RPT â€” Stock â€” ...` | Stock balance, movement, expiry, quality |
| `RPT â€” Sales â€” ...` | Sold items, top products, discounts |
| `RPT â€” Accounting â€” ...` | Invoices, debts, payments, income |
| `RPT â€” Purchasing â€” ...` | Norm/reorder, supplier performance |
| `RPT â€” Statistics â€” ...` | Comparative periods, analytics |
| `RPT â€” Data Quality â€” ...` | Missing data, negative stock |

---

## 10. Custom Fields to Deploy Before Building Reports

| DocType | Fieldname | Label | Type | Status |
|---|---|---|---|---|
| Item Reorder | `buffer_percentage` | Safety Stock Buffer % | Float | âœ… DEPLOYED 2026-05-12 (default 0.20) |

---

## 11. Deployment Script Plan

| Script | Covers | Status |
|---|---|---|
| `doc15a-deploy.ps1` | `buffer_percentage` custom field + Â§5.1â€“5.5 stock reports + Â§6.1â€“6.2 accounting reports (7 reports + 1 field) | âœ… Deployed 2026-05-12 |
| `doc15b-deploy.ps1` | Â§6.4 Debt Status Board, Â§6.5 Income by Period, Â§7.1 Norm and Reorder, Â§8.1 Top Products + Top Customers (5 reports) | âœ… Deployed 2026-05-12 |
| `doc15c-deploy.ps1` | Â§8.3 Comparative Periods, Â§9.1 Slow-Moving, Â§9.2 Near Expiry Value at Risk, Â§9.5 Missing Doctor, Â§9.6 Negative Stock, Â§9.8 Supplier Performance + workspace update (6 reports) | âœ… Deployed 2026-05-12 |
| `doc15d-deploy.ps1` | Task auto-escalation Scheduled Server Script + Daily/Weekly/Monthly KPI reports/charts | âœ… Deployed 2026-06-01 |
| `doc15e-deploy.ps1` | Item sort/classify report, nomenclature/prices report, norm notifications, task urgency workspace, management KPI workspace, return/refund queue | âœ… Deployed 2026-06-01 |

---

## 12. Post-Deployment Notes and Dependencies

1. **Standard Buying Price list populated** â€” profit/buying cost columns in all reports depend on `Item Price` records in `Standard Buying` price list. Currently 0 records (see Doc 17A Â§2.2). Planned before go-live â€” no action needed now, but profit reports will return empty costs until done.
2. **Batch and serial tracking per item** â€” some items have it, some don't. Reports will show batch/LOT/serial/expiry data where configured and blank where not. This is expected â€” no action needed.
3. **Doctor/hospital on sales documents** â€” no custom field needed. Doctor and hospital are standard ERPNext Customers. Â§6.1 and Â§8.1 filter/group by `customer`; Â§9.5 checks for invoices where customer has no parent group. No new field required.
4. **Dispatch Case link on Stock Entry** â€” âœ… already deployed. `dispatch_group_id` (Data) field on Stock Entry stores the Dispatch Case name. The `Â§5.5 Movement` report will join on `tabStock Entry.dispatch_group_id = tabDispatch Case.name`. No action needed.

---

## 13. Doc 15E â€” Deployed Follow-Up Scope

This section records the Doc 15A follow-up items deployed by `deploy/doc15e-deploy.ps1` on 2026-06-01.

### 13.1 Scope

| Area | Source sections | Implementation object | Status |
|---|---|---|---|
| Item sort and classify | Â§5.6, Â§4.6 | Query Report + optional workspace shortcuts | âœ… Deployed |
| Return/refund money | Â§6.6, Â§5.3 | Queue report + Task workflow + standard ERPNext return/refund documents | âœ… Deployed |
| Item nomenclature and prices | Â§7.2, Â§3.9 | Query Report | âœ… Deployed |
| Norm/reorder notifications | Â§7.1, Â§4.1 | Scheduled Server Script + ToDo/notification records | âœ… Deployed |
| Task urgency workspace | Â§8.2, Â§4.5 | Shared Task filters/workspace shortcuts | âœ… Deployed |
| Management KPI workspace polish | Â§8.4, Â§5.2 | Clean workspace or repaired workspace links | âœ… Deployed |

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
| Item sort/classify report | `RPT â€” Item â€” Sort and Classify` |
| Nomenclature/prices report | `RPT â€” Item â€” Nomenclature and Prices` |
| Return/refund queue report | `RPT â€” Returns â€” Refund Queue` |
| Norm/reorder daily scheduler | `doc15_norm_reorder_daily_notifications` |
| Management workspace | `Management â€” KPI Dashboard` |
| Dispatch/task workspace | `Dispatch â€” Task Queues` |

### 13.3 User Can Run Later to Save Quota

For read-only verification, the user can run:

```powershell
powershell -ExecutionPolicy Bypass -File .\doc15e-deploy.ps1 -Mode Check
```

Useful ERPNext manual checks:

| Check | Where |
|---|---|
| Confirm KPI reports open | ERPNext search: `RPT â€” KPI` |
| Confirm dashboard charts exist | ERPNext search: `Dashboard Chart` |
| Confirm norm notification script exists | ERPNext search: `Server Script` â†’ `doc15_norm_reorder_daily_notifications` |
| Confirm Standard Buying prices exist | ERPNext Item Price list filtered by `Standard Buying` |

Doc 15E has been deployed; remaining work is smoke testing and master data where reports depend on item prices.
