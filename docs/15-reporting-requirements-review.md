# Doc 15 — Reporting and Functions Launch Plan

**Status:** Launch-ready implementation plan — all critical decisions answered.

**Last updated:** 2026-06-01

---

## ✅ CRITICAL DECISIONS — ALL ANSWERED

**All 10 critical questions have been answered. This document is ready to guide report, dashboard, and automation implementation.**

### 🔴 PRIORITY 1 — Decisions Made

1. **Buying cost definition for profit calculation** ✅ ANSWERED
   - **Decision:** Use standard buying price (flexible for future changes)
   - **Special rule:** For expiry-tracked items, use FEFO (First Expired, First Out) cost
   - **Impact:** Affects all profit reports
   - **Note:** Can be changed later if needed

2. **REF number and Item Code strategy** ✅ CONFIRMED
   - **Decision:** REF number = Item Code (confirmed)
   - **Reason:** Products have either REF or model names, both counted as REF
   - **Impact:** Affects all sales reports showing REF numbers

3. **Payment "Approved" status** ✅ RESOLVED — NOT NEEDED
   - **Decision:** No custom "Approved" status required. Payment Entry is only created after bank verification, so ERPNext's standard "Paid" already means verified.
   - **Impact:** No new custom field needed on Sales Invoice — use standard payment status only.

4. **Refund process for damaged/opened/expired products** ✅ ANSWERED
   - **Damaged products:** Count as used (customer's responsibility, no refund)
   - **Opened/expired products:** Decide case-by-case depending on situation
   - **Impact:** Affects refund workflow and accounting

5. **Should refund wait for physical stock verification?** ✅ ANSWERED
   - **Decision:** Yes, refund happens AFTER stock is physically returned and verified
   - **Reason:** 100% certainty of what was returned
   - **Impact:** Prevents fraud, ensures accurate stock and accounting

6. **Norm calculation notification recipients** ✅ ANSWERED
   - **Decision:** Admins and directors receive notifications
   - **Additional:** Information not secret, can be open to everyone (change later if needed)
   - **Impact:** Notification recipients can be expanded

7. **Director-only reports** ✅ ANSWERED
   - **Decision:** 6 reports restricted to directors only (confirmed)
   - **Impact:** Protects sensitive financial and strategic data
   
   **Director-only reports (6):**
   - ✅ Sales — Sold Items Detail (shows profit per sale)
   - ✅ Accounting — Income by Period (shows total income)
   - ✅ Item — Nomenclature and Prices (shows buying prices)
   - ✅ Management — Global Statistics Dashboard (shows all KPIs)
   - ✅ Sales — Discount and Manual Price Changes (control/audit)
   - ✅ Purchasing — Supplier Performance (strategic decisions)
   
   **All other reports (20)** visible to relevant staff based on their roles:
   - Inventory staff: Stock reports
   - Sales staff: Sales documents, customer data
   - Accounting staff: Debt, payment reports
   - Purchasing staff: Norm/reorder reports
   
   **Note:** Can be adjusted later if needed.

8. **Customer-restricted reports** ✅ ANSWERED
   - **Decision:** No restriction - sales staff can see all customers (changed)
   - **Reason:** Operational flexibility
   - **Implementation:** All sales reports show all customers to sales staff
   - **Note:** Can be changed later if customer restriction becomes necessary

9. **Should overdue tasks auto-escalate to directors?** ✅ ANSWERED
   - **Decision:** Yes, auto-escalate with smart rules (Option A confirmed)
   - **Escalation rules:**
     - **Auto-escalate after 3 days overdue** (task assigned to director, original owner still visible)
     - **Immediate escalation for high-priority tasks** (overdue by 1 day)
     - **Weekly summary email** to directors showing all overdue tasks
     - **Original task owner notified** when task is escalated
   - **Benefits:** Directors stay informed, prevents tasks from being forgotten, maintains accountability
   - **Note:** Can be adjusted later if too many escalations occur
   - **Implementation requirement:** Auto-escalation requires a new Scheduled Script in Phase 2.

10. **Which KPIs are most important for daily/weekly review?** ✅ ANSWERED
    - **Decision:** Confirmed KPIs for daily and weekly dashboards
    
    - **DAILY Dashboard (5 KPIs, auto-refresh):**
      - Current stock value at risk (near expiry + expired)
      - Overdue debts total and count
      - Critical stock-outs (norm violations)
      - Pending urgent tasks count
      - Today's sales income total
    
    - **WEEKLY Dashboard (8 KPIs, manual refresh):**
      - Week's total income and profit
      - Top 10 products sold this week
      - Top 5 customers by sales
      - Slow-moving stock value
      - Supplier delivery performance
      - Debt aging analysis (30/60/90 days)
      - Stock turnover ratio
      - Week-over-week sales comparison
    
    - **MONTHLY KPI addition:**
      - Monthly total income
      - Monthly total profit
    
    - **Implementation:** Create 2 separate dashboards plus monthly income/profit KPI widgets
    - **Note:** Final list is approved for launch implementation and can be adjusted later after real usage feedback.
    - **Implementation requirement:** Daily and weekly ERPNext Dashboard objects do not yet exist. Monthly income/profit KPI widgets also need to be created in Phase 2.

---

## ✅ ANSWERED QUESTIONS — Implementation Ready

**These decisions have been made and can be used for implementation.**

### Product Identifiers and Tracking
- **REF number storage:** Item Code (confirmed)
- **LOT number:** Same as ERPNext Batch number (confirmed)
- **Serial numbers:** Required for all items except bulk items and individual items in surgical kits (confirmed)
- **Batch/LOT tracking:** All items should have batch tracking (confirmed)
- **Expiry tracking:** Only items with actual expiry dates (confirmed)

### Financial Definitions
- **Income:** Total sales revenue (all money received from sales)
- **Profit:** Income minus buying cost (net profit)
- **Buying cost:** Standard buying price (subject to team confirmation - see Critical Decisions)
- **Profit reports:** Show total for period (per-item optional but not priority)

### Debt and Payment Rules
- **Debt calculation:** GL net receivable (includes invoices, payments, credits, advances)
- **Unallocated advances:** Reduce debt automatically (net debt approach)
- **Debt reports:** Show net debt (outstanding minus advances minus credits)
- **Payment status flow:** Unpaid → Partly Paid → Paid (Payment Entry created only after bank verification; Paid = verified by definition)

### Doctor and Hospital Data
- **Doctor/Client structure:** Doctor as Customer + client-location warehouse (recommended Option A)
- **Who pays invoices:** Both doctors and hospitals can pay, sometimes client or insurance
- **Debt tracking:** Per hospital (with optional drill-down to see per-doctor debt within hospital)
- **Doctor-specific pricing:** Support hospital-specific pricing (may extend to doctors if needed)
- **Multiple doctors per document:** Yes, must support (rare but needed as backup)
- **Doctor statistics basis:** Sales invoice (confirmed)
- **Missing doctor/hospital data:** Allow missing data (show in data quality report)

### Warehouse and Stock Flow
- **Default warehouse filter:** All warehouses with checkbox to select specific ones
- **Group warehouses:** Automatically include child warehouses (Option B confirmed)
- **Sales reports warehouses:** Show both source and destination warehouses
- **Client returns as "product entry":** Yes, count as incoming stock

### Norm and Reorder
- **Norm calculation:** Automatic based on historical usage
- **Calculation period:** 30/60/90 days user-selectable (confirmed)
- **Usage data source:** Sales usage only (exclude surgery cancellations/returns)
- **Recalculation frequency:** Daily automatic + on-demand button
- **Safety stock buffer:** Yes, with per-item configurable buffer percentage
- **Generated order list:** Stay as recommendation with one-click convert to Purchase Order

### Access Control
- **Cost reports:** Everyone can see
- **Profit reports:** Directors only
- **Buying price:** Directors only (may extend to accountants later)
- **Debt reports:** Admins and accountants only

### Task Urgency
- **Urgency levels:** 3 levels with color coding:
  - Red: Right now (urgent)
  - Yellow: Today
  - Green: Should be done in a few days
- **Task descriptions:** Detailed individual description by office manager each time

### Refund and Return
- **Partial refunds:** Allowed (confirmed)

### Reporting Preferences
- **Ranking criteria:** All criteria available (quantity, sales amount, transactions) - user selects which to use
- **Global statistics:** Several separate reports (not one dashboard)
- **Dashboard refresh:** Auto-refresh (confirmed)

---

## 1) Purpose

This document converts the 20 requested reports/functions into launch-ready implementation specifications for ERPNext.

Goals:
- Remove repetitions and unclear naming.
- Define what each report answers, required filters, columns, and data sources.
- Identify overlaps with existing Doc 13 reporting pack.
- Add useful suggestions based on existing workflow.
- Record final implementation decisions and phase priorities.

Important:
- This is a **separate new document**.
- Existing reporting docs (Doc 13, Doc 13A) should not be changed.
- Implementation can follow the phases defined in this document.

---

## 2) Context from existing ERPNext setup

Current warehouse flow:
- `Main - Inmed` (sellable stock)
- `Delivery In-Transit - Inmed` (packed, on delivery)
- `Return Pickup In-Transit - Inmed` (picked up from client, returning)
- `Returns - Inmed` (returned, awaiting verification)
- `Clients - Inmed` group with client-location warehouses

Current workflows:
- Dispatch Case workflow (Doc 16) links dispatch, delivery, return pickup, return verification, usage derivation, and invoicing.
- Tasks are used for operational queues and approvals.
- Batch/serial/expiry tracking must be configured per item before transactions.
- Payment allocation affects debt reporting.

Consequence:
- Report accuracy depends on correct item tracking, warehouse discipline, payment allocation, and consistent document usage.

---

## 3) Repetitions and overlaps in requested list

| Original items | Overlap | Recommendation |
|---:|---|---|
| 1, 2, 3 | Stock balance with expiry/batch visibility | One base stock report + separate expiry filter report |
| 4, 5 | Product entries and quantity by day | One incoming-stock report with detail/summary modes |
| 8, 9, 18 | Debts, unpaid, paid, partly paid | One receivables/debt pack with status filters |
| 10, 16, 17 | Income, profit, global statistics, sales totals | Separate financial KPI reports sharing definitions |
| 7, 17 | Sold products with warehouse/product/client/lot/expiry | One detailed sold-items report |
| 12, 13 | Norm/reorder and nomenclature/prices | Keep separate but share Item/Price/Supplier data |

---

## 4) Consolidated modules

| Module | Original requests | Audience | Priority |
|---|---:|---|---|
| Stock Balance and Expiry Pack | 1, 2, 3, 4, 5, 6, 20 | Inventory, Ops, Directors | High |
| Sales, Debt, Payment Pack | 7, 8, 9, 10, 17, 18, 19 | Accounting, Directors, Sales | High |
| Purchasing / Norm Pack | 12, 13 | Purchasing, Directors | High |
| Statistics and Analytics Pack | 11, 15, 16 | Directors, Management | Medium |
| Task Workspace | 14 | All teams, Directors | Medium |

---

## 5) Stock Reports (Requests 1-6, 20)

### 5.1 Stock Balance — Multi-Select

**Original request 1:** Momentary balance with ability to choose products and warehouses.

**Answers:** What quantity exists now for selected items in selected warehouses?

**Type:** Query Report

**Filters:**
- Item (multi-select)
- Warehouse (multi-select)
- Item Group
- Brand
- Include child warehouses: yes/no
- Hide zero qty: yes/no

**Columns:** Item Code, Item Name, Item Group, Brand, Warehouse, Actual Qty, Reserved Qty, Projected Qty, UOM

---

### 5.2 Stock Balance — Batch and Expiry

**Original request 2:** Balance with expiry date selection.

**Answers:** Which batches exist now, in which warehouses, when do they expire?

**Type:** Query Report

**Filters:**
- Item (multi-select)
- Warehouse (multi-select)
- Expiry From Date
- Expiry To Date
- Include expired: yes/no
- Near expiry days

**Columns:** Item Code, Item Name, Warehouse, Batch/LOT, Expiry Date, Current Qty, UOM, Days Until Expiry, Status

**Question:** Does "period" mean expiry date range or historical balance as of past date?

---

### 5.3 Stock — Expirable / Non-Expirable / Expired

**Original request 3:** Filter expirable/non-expirable/expired products.

**Answers:** Which products are expiry-tracked, not tracked, or have expired stock?

**Type:** Query Report

**Filters:**
- Product type (one at a time): Expirable / Non-expirable / Expired
- Warehouse (multi-select)
- Item Group
- Brand

**Columns:** Item Code, Item Name, Item Group, Has Batch, Has Expiry, Warehouse, Batch/LOT, Expiry Date, Current Qty, Status

---

### 5.4 Stock Entry — By Day/Period

**Original requests 4, 5:** Product entry by day, quantity per day.

**Answers:** Which items entered inventory on selected date/period and in what quantity?

**Type:** Query Report

**Filters:**
- From Date
- To Date
- Warehouse (multi-select)
- Item (multi-select)
- Entry Type: Purchase Receipt / Stock Entry / Return / All
- Mode: Detail / Summary

**Detail columns:** Posting Date, Time, Voucher Type, Voucher No, Item Code, Item Name, Warehouse, Qty In, UOM, Batch/LOT, Serial No, Supplier

**Summary columns:** Posting Date, Item Code, Item Name, Warehouse, Total Qty In

**Answered:** Client returns count as incoming stock. ✅ See §10.2.

---

### 5.5 Stock Movement — Warehouse to Warehouse

**Original request 6:** Movement of goods from one warehouse to another.

**Answers:** What moved, when, why, by which document?

**Type:** Query Report

**Filters:**
- From Date
- To Date
- Source Warehouse (multi-select)
- Target Warehouse (multi-select)
- Item (multi-select)
- Movement Type: Transfer / Delivery / Return / Consumption / All
- Related Dispatch Case

**Columns:** Posting Date, Time, Stock Entry No, Entry Type, Source Warehouse, Target Warehouse, Item Code, Item Name, Qty, Batch/LOT, Serial No, Related Dispatch Case, Created By, Remarks

---

### 5.6 Item List — Sort and Classify

**Original request 20:** Items sorted by quantity (ascending/descending) and alphabetically.

**Answers:** Quick item list views sorted by different criteria.

**Type:** Saved Item List Views

**Required views:**
- Items by qty ascending
- Items by qty descending
- Items alphabetically A-Z
- Items alphabetically Z-A

**Columns:** Item Code, Item Name, Item Group, Brand, Total Qty, Main Warehouse Qty, UOM, Selling Price, Buying Price

**Suggestion:** Add "low stock first" view (more useful operationally).

---

## 6) Sales, Debt, and Payment Reports (Requests 7-10, 17-19)

### 6.1 Sales — Sold Items Detail

**Original requests 7, 17:** Sold products with warehouse, client, dates, REF, LOT, expiry, buying price, profit, debts.

**Answers:** What was sold, to whom, from which warehouse, with traceability identifiers, costs, and payment status?

**Type:** Query Report

**Filters:**
- From Date
- To Date
- Customer
- Warehouse (multi-select)
- Item (multi-select)
- Item Group
- Doctor
- Hospital
- Sales Invoice
- Payment Status: All / Paid / Unpaid / Partly Paid

**Columns:** Sales Invoice, Invoice Date, Dispatch Case, Customer, Hospital, Doctor, Source Warehouse, Client Warehouse, Item Code, Item Name, REF Number, Batch/LOT, Serial No, Expiry Date, Qty Sold, Selling Rate, Selling Amount, Buying Cost, Gross Profit, Invoice Total, Outstanding Amount, Payment Status

**Color coding:**
- Red: unpaid
- Yellow: partly paid
- Green: fully paid

**Answered:** REF = Item Code (§10.1); buying cost = standard buying price (§10.3); profit = income minus buying cost (§10.3). ✅

---

### 6.2 Accounting — Sales Documents and Payments

**Original request 8:** Sales documentation, debts and payments.

**Answers:** For each sales document, how much was invoiced, paid, unpaid, and which payments are linked?

**Type:** Query Report

**Filters:**
- From Date
- To Date
- Customer
- Sales Invoice
- Payment Status: Unpaid / Partly Paid / Paid / Overdue / All

**Columns:** Customer, Sales Invoice, Invoice Date, Due Date, Grand Total, Paid Amount, Outstanding Amount, Payment Status, Payment Entry, Payment Date, Days Overdue, Linked Sales Order, Linked Dispatch Case

---

### 6.3 Accounting — Unpaid Debts

**Original request 9:** Filter debts that are not paid yet and who should pay.

**Answers:** Who owes us money right now, how urgent is it?

**Type:** Query Report

**Filters:**
- Customer
- Minimum outstanding amount
- Due date from/to
- Aging bucket
- Assigned responsible person

**Columns:** Customer, Customer Name, Sales Invoice, Invoice Date, Due Date, Outstanding Amount, Aging Days, Aging Bucket, Debt Collection Task, Task Owner, Last Payment Date, Customer Contact/Phone

---

### 6.4 Accounting — Debt Status Board

**Original request 18:** Debts with sections: not-paid, paid 100%, paid partly, approved.

**Answers:** What is the payment/debt status of each sales document?

**Type:** Query Report with status filter or dashboard with sections

**Status categories:**
- Unpaid
- Partly Paid
- Paid

**Columns:** Customer, Sales Invoice, Invoice Date, Grand Total, Paid Amount, Outstanding Amount, Payment Status, Debt Collection Task

**Answered:** Uses ERPNext standard payment status (Unpaid / Partly Paid / Paid). "Paid" = bank-verified by definition — Payment Entry is only posted after bank confirmation. No custom field needed. ✅

---

### 6.5 Accounting — Income by Period

**Original request 10:** Income based on selected date or period.

**Answers:** How much income/revenue did we record in selected period?

**Type:** Query Report

**Filters:**
- From Date
- To Date
- Customer
- Item Group
- Warehouse
- Doctor
- Hospital

**Columns:** Date/Period, Customer, Sales Invoice, Net Total, Taxes, Grand Total, Paid Amount, Outstanding Amount

**Answered:** Income = total sales revenue; profit = income minus buying cost. ✅ See §10.3.

---

### 6.6 Function — Return/Refund Money

**Original request 19:** Return money if surgery was cancelled or similar situations.

**Answers:** How do we safely reverse or refund money when surgery/order is cancelled?

**Type:** Business process + workspace/button/report

**Possible ERPNext documents:**
- Credit Note / Return Sales Invoice
- Payment Entry refund
- Sales Order cancellation
- Stock Entry for returned stock
- Task for approval and execution

**Required columns for refund queue:** Customer, Original Sales Order/Invoice, Dispatch Case, Cancellation Reason, Amount to Refund, Refund Status, Payment Entry/Credit Note, Stock Return Status, Approved By, Created By

**Answered:** Refund process fully defined. ✅ See §10.6.

---

## 7) Purchasing and Norm Reports (Requests 12-13)

### 7.1 Purchasing — Norm/Reorder Requirement

**Original request 12:** Norm report showing quantity we should have for selected period to not run out, notify when below norm, create list/order for new products.

**Answers:** What should we buy now to avoid stock-out?

**Type:** Report + notification automation

**Filters:**
- Warehouse
- Item Group
- Supplier
- Planning Period: days/weeks/months
- Include only below norm: yes/no

**Columns:** Item Code, Item Name, Supplier, Warehouse, Current Qty, Reserved Qty, Projected Qty, Minimum Norm/Reorder Level, Recommended Reorder Qty, Average Daily Usage, Days of Stock Remaining, Shortage Qty, Last Purchase Date, Last Purchase Price

**Function requirements:**
- Notify responsible users when stock falls below norm
- Generate purchase/reorder list
- Later phase: optionally create draft Purchase Order from selected rows

**Answered:** Norm calculation fully defined. ✅ See §10.7.

**Suggestion:** Add "critical shortage" flag for items that are completely out of stock or below safety level.

---

### 7.2 Item — Nomenclature and Prices

**Original request 13:** Nomenclature showing product REF-number, name, buying price, selling price.

**Answers:** What is our product catalog with reference numbers and prices?

**Type:** Query Report or saved Item/Item Price view

**Filters:**
- Item Group
- Brand
- Supplier
- Disabled: yes/no
- Has stock: yes/no

**Columns:** Item Code, REF Number, Item Name, Brand, Item Group, Supplier, Standard Buying Price, Last Purchase Price, Standard Selling Price, Currency, UOM, Has Batch No, Has Serial No, Has Expiry Date

**Answered:** REF = Item Code; buying price = standard buying price. ✅ See §10.1 and §10.3.

**Suggestion:** Add "price change history" to track when buying/selling prices were last updated and by whom.

---

## 8) Statistics, Tasks, and Analytics (Requests 11, 14-16)

### 8.1 Statistics — Top Products and Doctors

**Original request 11:** Most purchased products for selected period, and which doctor purchased the most.

**Answers:** Which products sell most, and which doctors/customers generate most purchases?

**Type:** Query Report or dashboard

**Filters:**
- From Date
- To Date
- Customer
- Doctor
- Hospital
- Item Group
- Brand
- Top N (default: 10)

**Top Products columns:** Rank, Item Code, Item Name, Total Qty Sold, Total Sales Amount, Number of Sales Documents, Average Sale Price

**Top Doctors columns:** Rank, Doctor, Customer/Hospital, Total Qty Purchased, Total Sales Amount, Number of Sales Documents, Average Purchase Amount

**Answered:** Doctor = Customer + client-location warehouse. Ranking: all criteria available, user selects. ✅ See §10.5.

**Suggestion:** Add "trending products" showing items with increasing sales compared to previous period.

---

### 8.2 Workspace — Tasks by Urgency

**Original request 14:** Task tab showing all tasks and their urgency using colors.

**Answers:** What tasks are open, who owns them, what is urgent?

**Type:** Workspace with saved Task views and color/priority indicators

**Required views:**
- My open tasks
- All urgent tasks
- Overdue tasks
- Debt collection tasks
- Delivery tasks
- Return tasks
- Approval tasks (discount, purchase, write-off)
- Purchase/reorder tasks

**Columns:** Task, Task Kind, Status, Priority, Due Date, Assigned To, Customer, Related Dispatch Case, Age (days open)

**Urgency color coding:**
- Red: overdue or blocker
- Orange/yellow: due today or high priority
- Green: normal/open
- Grey: waiting/on hold

**Answered:** Urgency levels defined (see Answered Questions). Auto-escalation confirmed. ✅ See Critical Decisions §9.

**Suggestion:** Add task aging alerts (e.g., tasks open > 7 days without update).

---

### 8.3 Statistics — Sales Comparative Periods

**Original request 15:** Compare sales in selected periods.

**Answers:** How did sales change between two selected periods?

**Type:** Query Report or dashboard

**Filters:**
- Period A From Date
- Period A To Date
- Period B From Date
- Period B To Date
- Customer
- Item Group
- Item
- Doctor
- Warehouse

**Columns:** Metric, Period A Value, Period B Value, Difference, Difference %

**Metrics:**
- Sales quantity
- Sales amount
- Number of sales documents
- Average sale amount
- Number of unique customers
- Gross profit (if approved definition exists)

**Suggestion:** Add month-over-month and year-over-year comparison shortcuts.

---

### 8.4 Management — Global Statistics Dashboard

**Original request 16:** Global statistics showing products according to quantity, profit, and income.

**Answers:** What are the global business KPIs for products, stock, sales, income, and profit?

**Type:** Dashboard with multiple widgets/reports

**Suggested widgets:**
- Stock value by item group
- Top 10 products by quantity sold
- Top 10 products by revenue
- Top 10 products by gross profit
- Slow-moving products (no sales in X days)
- Expired/near-expiry stock value at risk
- Current receivables/debt total
- Monthly income trend (last 12 months)
- Sales by customer type/segment
- Inventory turnover ratio

**Answered:** Two separate dashboards (daily auto-refresh + weekly manual). KPIs confirmed. ✅ See Critical Decisions §10.

**Suggestion:** Add "alerts" section showing critical issues: stock-outs, overdue debts, expired stock, stuck deliveries.

---

## 9) Additional Useful Reports (Not Requested but Recommended)

### 9.1 Stock — Slow-Moving Products

**Purpose:** Find products with stock but no sales/movement for long time.

**Why useful:** Helps reduce dead stock and avoid expiry/write-off.

**Filters:** No sale/movement since X days, Warehouse, Item Group, Brand

**Columns:** Item Code, Item Name, Current Qty, Last Sale Date, Last Movement Date, Days Since Last Sale, Stock Value at Risk

---

### 9.2 Stock — Near Expiry Value at Risk

**Purpose:** Show not only near-expiry quantity but estimated money value at risk.

**Why useful:** Helps management decide whether to discount, prioritize usage, or write off.

**Columns:** Item Code, Item Name, Warehouse, Batch/LOT, Expiry Date, Days Until Expiry, Qty, Buying Cost, Selling Price, Value at Risk

---

### 9.3 Data Quality — Missing Tracking Setup

**Purpose:** Find items that should have REF, LOT, serial, batch, or expiry tracking but are missing setup.

**Why useful:** Prevents bad data before it enters transactions.

**Columns:** Item Code, Item Name, Item Group, Has Batch No, Has Serial No, Has Expiry Date, Current Stock, Missing Setup

---

### 9.4 Sales — Discount and Manual Price Changes

**Purpose:** Show where selling prices were manually changed or discounts given.

**Why useful:** Protects margin and creates director visibility.

**Columns:** Sales Order/Invoice, Customer, Item Code, Item Name, Price List Rate, Actual Rate, Discount %, Manual Override, Approved By

**Suggestion:** Link to existing discount approval workflow from Doc 10.

---

### 9.5 Operations — Documents Missing Doctor/Hospital

**Purpose:** Find sales or surgery documents where doctor/hospital context is missing.

**Why useful:** Doctor statistics will be wrong if this data is not entered consistently.

**Columns:** Sales Invoice, Dispatch Case, Customer, Posting Date, Missing Doctor, Missing Hospital, Created By

---

### 9.6 Stock — Negative or Impossible Stock

**Purpose:** Find negative stock, missing batch/serial numbers, impossible quantities.

**Why useful:** Catches operational mistakes early.

**Columns:** Item Code, Warehouse, Actual Qty, Issue Type (negative/missing batch/missing serial/impossible value)

---

### 9.7 Accounting — Unallocated Payments

**Purpose:** Show payments received but not allocated to sales invoices.

**Why useful:** Prevents clients appearing unpaid when money was received but not distributed.

**Columns:** Customer, Payment Entry, Payment Date, Amount, Unallocated Amount, Days Since Payment, Responsible Person

**Note:** This overlaps with existing Doc 13A report `RPT — Receivables — Unallocated Advances`.

---

### 9.8 Purchasing — Supplier Performance

**Purpose:** Track purchase orders, delivery delays, received quantities, supplier reliability.

**Why useful:** Helps purchasing decisions beyond just price.

**Columns:** Supplier, Purchase Order, Order Date, Expected Delivery Date, Actual Delivery Date, Delay Days, Ordered Qty, Received Qty, Fulfillment %, Quality Issues

---

## 10) Implementation Questions — Status and Answers

**Note:** All critical questions have been answered. See "ANSWERED QUESTIONS" section at top for confirmed decisions.

### 10.1 Product identifiers and tracking ✅ ANSWERED

**Answers:**
1. REF number stored in: **Item Code** (confirmed)
2. LOT number: **Same as ERPNext Batch number** (confirmed)
3. Serial numbers required for: **All items except bulk items and individual items in surgical kits** (confirmed)
4. Expiry tracking: **Only items with actual expiry dates** (confirmed)
5. Batch tracking: **All items should have batch tracking** (confirmed)

**Implementation note:** REF number = Item Code may need review with colleague to ensure no confusion when items have both REF and model names.

---

### 10.2 Warehouse and stock flow ✅ ANSWERED

**Answers:**
1. Default warehouse filter: **All warehouses with checkbox to select specific ones** (confirmed)
2. Group warehouses: **Automatically include child warehouses** (confirmed - Option B)
3. Sales reports warehouses: **Both source and destination warehouses** (confirmed)
4. Client returns as "product entry": **Yes, count as incoming stock** (confirmed)

---

### 10.3 Income, profit, and buying price definitions ✅ ANSWERED

**Answers:**
1. "Profit" means: **Net profit after buying cost (Income - Buying cost)** (confirmed)
2. "Income" means: **Total sales revenue (all money received from sales)** (confirmed)
3. Buying cost to use: **Standard buying price + FEFO for expiry-tracked items** (confirmed, flexible for future changes)
4. Profit reports visibility: **Directors only** (confirmed)

---

### 10.4 Debt and payment rules ✅ ANSWERED

**Answers:**
1. Debt calculation: **GL net receivable** (includes invoices, payments, credits, advances) (confirmed)
2. Unallocated advances: **Yes, reduce debt automatically** (net debt approach) (confirmed)
3. Payment verification: **Payment Entry created only after bank confirmation — ERPNext "Paid" status means verified. No separate "Approved" step or custom field needed.** (confirmed)
4. Debt reports show: **Net debt** (outstanding minus advances minus credits) (confirmed)

---

### 10.5 Doctor and hospital data ✅ ANSWERED

**Answers:**
1. Doctor structure: **Doctor as Customer + client-location warehouse** (recommended Option A) (confirmed)
2. Multiple doctors per document: **Yes, must support** (rare but needed as backup) (confirmed)
3. Doctor statistics basis: **Sales invoice** (confirmed)
4. Hospital: **Separate Customer** (both doctors and hospitals can be customers) (confirmed)
5. Missing doctor/hospital data: **Allow missing data** (show in data quality report) (confirmed)

**Additional context:**
- Who pays: Both doctors and hospitals can pay, sometimes client or insurance
- Debt tracking: Per hospital (with optional drill-down to see per-doctor debt within hospital)
- Pricing: Support hospital-specific pricing (may extend to doctors if needed via tender system)

---

### 10.6 Refund and return process ✅ ANSWERED

**Answers:**
1. Partial refunds: **Allowed** (confirmed)
2. Who approves refunds: **Admins** (confirmed)
3. Refund wait for verification: **Yes, refund after physical stock verification** (confirmed)
4. Damaged/opened/expired products: **Damaged=no refund (customer responsibility), Opened/expired=case-by-case** (confirmed)
5. Refund document type: **Use ERPNext standard Credit Note / Return Sales Invoice and Payment Entry refund flow as appropriate for the transaction**

---

### 10.7 Norm and reorder calculation ✅ ANSWERED

**Answers:**
1. Norm calculation: **Automatic based on historical usage** (confirmed)
2. Usage data source: **Sales usage only** (exclude surgery cancellations/returns) (confirmed)
3. Calculation period: **30/60/90 days user-selectable** (confirmed)
4. Notification recipients: **Admins and directors** (confirmed, can be expanded to everyone if needed)
5. Notification frequency: **Daily automatic + on-demand button** (confirmed)
6. Generated order list: **Stay as recommendation with one-click convert to Purchase Order** (confirmed)

**Additional features:**
- Safety stock buffer: Yes, with per-item configurable buffer percentage

---

### 10.8 Access control and visibility ✅ ANSWERED

**Answers:**
1. Cost reports: **Everyone can see** (confirmed)
2. Buying price: **Directors only** (updated decision — may extend to accountants later)
3. Debt reports: **Admins and accountants only** (confirmed)
4. Profit reports: **Directors only** (confirmed — see Critical Decisions §7)
5. Director-only reports: **6 reports restricted to directors** (confirmed - see Critical Decisions section for list)
6. Customer-restricted reports: **No restriction - sales staff can see all customers** (confirmed)

**Additional note:** Users with multiple roles should have access to all functions their roles allow.

---

## 11) Suggested Implementation Phases

### Phase 1 — Must-Have Operational Visibility (High Priority)

**Build first:**
1. Stock Balance — Multi-Select
2. Stock Balance — Batch and Expiry
3. Expirable / Non-Expirable / Expired Products
4. Stock Entry — By Day/Period
5. Stock Movement — Warehouse to Warehouse
6. Sales — Sold Items Detail
7. Accounting — Unpaid Debts
8. Accounting — Sales Documents and Payments
9. Item — Nomenclature and Prices

**Why first:** These reports answer daily operational questions and help catch stock/sales/debt problems quickly.

**Estimated effort:** 2-3 weeks for all 9 reports.

---

### Phase 2 — Management and Purchasing Control (High Priority)

**Build after Phase 1:**
1. Purchasing — Norm/Reorder Requirement with notification
2. Accounting — Income by Period
3. Accounting — Debt Status Board
4. Sales — Statistics by Product and Doctor
5. Workspace — Tasks by Urgency
6. Task Auto-Escalation Scheduled Script
7. Daily Dashboard and Weekly Dashboard
8. Monthly total income/profit KPI widgets
9. Item List — Sort and Classify

**Why second:** These need approved business definitions and require automation or dashboard setup.

**Estimated effort:** 2-3 weeks for all 9 reports/functions.

---

### Phase 3 — Advanced Analytics and Automation (Medium Priority)

**Build later:**
1. Statistics — Sales Comparative Periods
2. Advanced Management — Global Statistics Dashboard improvements
3. Function — Return/Refund Money workflow improvements
4. Stock — Slow-Moving Products
5. Stock — Near Expiry Value at Risk
6. Purchasing — Supplier Performance

**Why later:** These are valuable enhancements that depend on clean historical data and real usage feedback.

**Estimated effort:** 3-4 weeks for all 6 reports/functions.

---

### Phase 4 — Data Quality and Controls (Medium Priority)

**Build when time allows:**
1. Data Quality — Missing Tracking Setup
2. Sales — Discount and Manual Price Changes
3. Operations — Documents Missing Doctor/Hospital
4. Stock — Negative or Impossible Stock
5. Accounting — Unallocated Payments (if not covered by existing Doc 13A report)

**Why later:** These are quality controls that add value but are not blocking daily operations.

**Estimated effort:** 1-2 weeks for all 5 reports.

---

## 12) Final Consolidated Report List

Clean final list without repetitions:

### Stock Reports (7 reports)
1. Stock Balance — Multi-Select
2. Stock Balance — Batch and Expiry
3. Stock — Expirable / Non-Expirable / Expired
4. Stock Entry — By Day/Period
5. Stock Movement — Warehouse to Warehouse
6. Stock — Slow-Moving Products
7. Stock — Near Expiry Value at Risk

### Sales and Accounting Reports (9 reports)
8. Sales — Sold Items Detail
9. Accounting — Sales Documents and Payments
10. Accounting — Unpaid Debts
11. Accounting — Debt Status Board
12. Accounting — Income by Period
13. Sales — Statistics by Product and Doctor
14. Statistics — Sales Comparative Periods
15. Sales — Discount and Manual Price Changes
16. Accounting — Unallocated Payments

### Purchasing Reports (3 reports)
17. Purchasing — Norm/Reorder Requirement
18. Item — Nomenclature and Prices
19. Purchasing — Supplier Performance

### Management and Tasks (3 dashboards/workspaces)
20. Management — Global Statistics Dashboard
21. Workspace — Tasks by Urgency
22. Item List — Sort and Classify Views

### Functions and Processes (1 function)
23. Function — Return/Refund Money

### Data Quality Reports (3 reports)
24. Data Quality — Missing Tracking Setup
25. Operations — Documents Missing Doctor/Hospital
26. Stock — Negative or Impossible Stock

**Total: 26 reports/functions/workspaces**

---

## 13) Launch Execution Steps

### Ready before implementation starts:

1. **Decisions:** All critical reporting, dashboard, access, and automation decisions are answered.

2. **Priority:** Phase 1 and Phase 2 priorities are defined.

3. **KPIs:** Income, profit, buying cost, norm calculation, debt calculation, daily dashboard, weekly dashboard, and monthly KPI definitions are confirmed.

4. **Access control:** Director-only reports and role-based visibility are defined.

5. **Data readiness check:** Verify that REF/LOT/Serial/Expiry/Doctor/Hospital data is being entered consistently in current transactions before relying on reports.

6. **Implementation readiness:** Build custom reports only where ERPNext standard reports are not sufficient.

### Implementation order:

1. Start Phase 1 implementation.
2. Test each report with real data before moving to next report.
3. Start Phase 2 implementation for norm notifications, dashboards, monthly KPIs, and task auto-escalation.
4. Train users on how to use each report.
5. Document report usage in user manual or workflow guide.

---

## 14) Important Reminders

**Report accuracy depends on data quality:**
- If REF/LOT/Serial/Expiry is not entered during transactions, reports cannot show it.
- If doctor/hospital is not entered on sales documents, doctor statistics will be incomplete.
- If payment allocation is not done correctly, debt reports will be wrong.
- If batch/serial tracking is not configured before stock transactions, traceability reports will fail.

**Start small and iterate:**
- Build Phase 1 reports first and get user feedback.
- Refine definitions based on real usage.
- Add Phase 2/3/4 reports only after Phase 1 is working well.

**Don't over-engineer:**
- Use standard ERPNext reports where possible.
- Build custom Query Reports only when standard reports are not sufficient.
- Keep reports simple and focused on answering one clear question.

---

## 15) Implementation Notes Based on Answers

### Doctor/Client/Hospital Setup (Recommended Approach)

**Structure:**
- Create **Customer** records for both doctors and hospitals
- Create **client-location warehouse** for each doctor (e.g., "Dr. Smith Location - Inmed")
- Link warehouse to customer via custom field or naming convention
- Use existing Dispatch Case workflow (Doc 16) which already supports this structure

**Advantages:**
- Supports debt tracking per hospital with drill-down to doctors
- Supports hospital-specific pricing (and doctor-specific if needed)
- Allows both doctors and hospitals to pay invoices
- Supports insurance and client payments
- Clean separation between who (Customer) and where (Warehouse)

**Implementation steps:**
1. Continue using existing Customer structure (already has 146 customers)
2. Ensure each doctor has corresponding client-location warehouse under `Clients - Inmed`
3. Add custom field on Sales Invoice for multiple doctors if needed (rare case backup)
4. Configure Item Price with customer-specific pricing for hospitals/doctors with tenders

---

### Payment Status Implementation

**Decision:** Use ERPNext standard payment status only (Unpaid / Partly Paid / Paid). No custom field needed.

**Reasoning:** Payment Entry is created only after bank verification is confirmed. Therefore "Paid" = verified by definition. The `outstanding_amount` from GL (net receivable approach) provides full debt visibility in reports.

---

### Norm Calculation Implementation Notes

**Calculation logic:**
```
For each item:
1. Get sales quantity for selected period (30/60/90 days)
2. Exclude cancelled dispatch cases (returned stock)
3. Calculate average daily usage = total sales qty / days in period
4. Get user-configured buffer % from the item's `Item Reorder` row for this warehouse (default 20%)
5. Norm = (average daily usage × planning days) × (1 + buffer %)
6. If current stock < norm → flag as "below norm"
```

**Features to implement:**
- Daily automatic recalculation (scheduled job)
- On-demand "Recalculate Now" button
- Per-item buffer % configuration (custom field `buffer_percentage` on `Item Reorder` child table) ✅ *Deployed 2026-05-12 via `doc15a-deploy.ps1`*
- Notification when stock falls below norm
- One-click "Create Purchase Order" from reorder list

---

### Task Urgency Color Coding Implementation

**Urgency levels:**
- **Red (Right Now):** Priority = High OR Due Date = Today OR Overdue
- **Yellow (Today):** Due Date = Today (not yet overdue)
- **Green (Few Days):** Due Date within next 3-7 days

**Implementation:**
- Use ERPNext Priority field (Low/Medium/High)
- Use Due Date field
- Use existing Task `description` field for office manager notes (no custom field needed)
- Color coding in list view using custom script or indicator field

---

### REF Number Display in Reports

**Current setup:**
- REF number = Item Code
- Some items also have model names

**Report implementation:**
- Column name: "REF Number / Item Code"
- Display: Item Code value
- If confusion occurs, add separate "Model Name" column showing item_name or custom field

**Future consideration:** If REF and Item Code need to be separate, add custom field `ref_number` on Item.

---

### GL Net Receivable Debt Calculation (SQL Example)

**Query logic for debt reports:**
```sql
SELECT
  c.name as customer,
  c.customer_name,
  COALESCE(SUM(gle.debit - gle.credit), 0) as net_receivable_amd
FROM `tabCustomer` c
LEFT JOIN `tabGL Entry` gle
  ON gle.party_type = 'Customer'
  AND gle.party = c.name
  AND gle.is_cancelled = 0
WHERE c.disabled = 0
GROUP BY c.name
HAVING net_receivable_amd > 0
ORDER BY net_receivable_amd DESC
```

**This automatically includes:**
- Sales Invoice outstanding amounts (debit)
- Payment Entries (credit)
- Credit Notes (credit)
- Unallocated advances (credit)
- Journal Entries and adjustments

**User sees:** True net debt without manual calculation.

---

### Multi-Role User Access

**Scenario:** User has roles: `Ops - Inventory` + `Ops - Accounting`

**Access:**
- Can see all inventory reports (because `Ops - Inventory` role allows it)
- Can see accounting reports — debt, payments, invoices (because `Ops - Accounting` role allows it)
- Cannot see buying price or profit reports (Directors only — requires `Ops - Directors` role)

**Implementation:** Use ERPNext standard role permissions - no special handling needed.

---

## 16) Quick Reference — Implementation Status

### ✅ ALL QUESTIONS ANSWERED — Ready to Implement

**All 26 reports/functions are ready for implementation. All critical decisions have been made.**

**Stock Reports (7):**
- Stock Balance — Multi-Select
- Stock Balance — Batch and Expiry
- Stock — Expirable / Non-Expirable / Expired
- Stock Entry — By Day/Period
- Stock Movement — Warehouse to Warehouse
- Stock — Slow-Moving Products
- Stock — Near Expiry Value at Risk

**Sales and Accounting Reports (9):**
- Sales — Sold Items Detail (director-only)
- Accounting — Sales Documents and Payments
- Accounting — Unpaid Debts (using GL net receivable)
- Accounting — Debt Status Board
- Accounting — Income by Period (director-only)
- Sales — Statistics by Product and Doctor
- Statistics — Sales Comparative Periods
- Sales — Discount and Manual Price Changes (director-only)
- Accounting — Unallocated Payments

**Purchasing Reports (3):**
- Purchasing — Norm/Reorder Requirement
- Item — Nomenclature and Prices (director-only)
- Purchasing — Supplier Performance (director-only)

**Management and Tasks (3):**
- Management — Global Statistics Dashboard (director-only)
- Workspace — Tasks by Urgency (with 3-level color coding + auto-escalation)
- Item List — Sort and Classify Views

**Functions and Processes (1):**
- Function — Return/Refund Money

**Data Quality Reports (3):**
- Data Quality — Missing Tracking Setup
- Operations — Documents Missing Doctor/Hospital
- Stock — Negative or Impossible Stock

---

### 📋 Key Implementation Details Confirmed

**Financial Definitions:**
- Income = Total sales revenue
- Profit = Income - Buying cost
- Buying cost = Standard buying price + FEFO for expiry items

**Access Control:**
- 6 director-only reports (listed above)
- 20 reports accessible by relevant staff roles
- No customer restrictions (sales staff see all customers)
- Only admins can approve payments

**Automation:**
- Task auto-escalation: 3 days for normal, 1 day for high-priority
- Norm calculation: Daily automatic + on-demand
- Dashboard refresh: Daily auto-refresh, Weekly manual

**Dashboards:**
- Daily Dashboard: 5 KPIs (auto-refresh)
- Weekly Dashboard: 8 KPIs (manual refresh)
- Monthly KPI widgets: total income and total profit

**Launch status:** Ready for implementation.

---

