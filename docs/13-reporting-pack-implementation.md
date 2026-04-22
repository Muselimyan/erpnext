# Doc 13A — Reporting Pack (Implementation / ERPNext Setup Guide)

## 1) Purpose
This is a **step-by-step ERPNext setup guide** to implement the reporting pack defined in:
- **Doc 13 — Reporting Pack (Operational)**

This guide configures:
- Saved Reports (built-in ERPNext reports with saved filters)
- Query Reports (SQL-based reports) where the built-in reports are not sufficient
- Saved list views for operational queues (Tasks, Surgery Cases)
- One workspace page that groups the reporting pack for daily use

Non-goals:
- This guide does not redesign operations. It only implements visibility into the workflows defined in Docs 05–12.

---

## 2) Prerequisites / access
Do not start Doc 13A until these are done:
- Doc 03A — roles exist (`Ops - ...`) and baseline permissions are in place.
- Doc 04A — unified client model exists (`Customer` + `debt_threshold_amd`).
- Doc 05A — warehouse tree exists:
  - `Main - WH`
  - `Delivery In-Transit - WH`
  - `Return Pickup In-Transit - WH`
  - `Returns - WH`
  - `Clients - WH` group + client-location leaf warehouses
- Doc 06A — item tracking flags are correct (serial/batch/expiry) + FEFO warning is implemented.
- Doc 08A — reorder setup exists (reorder levels on Items + reorder list views).
- Doc 09A — debt threshold automation exists (scheduled script) + Distribute Payment task automation exists.
- Doc 10A — Task system exists (Task Kind, Task Access Policy, mandatory photo enforcement).
- Doc 11A — Surgery Set Type templates exist.
- Doc 12A — Surgery Case workflow exists (stock moves + tasks + usage/invoice links).

You should do Doc 13A as a user with:
- `System Manager`
- `Report Manager`
- `Workspace Manager`

---

## 3) Reporting setup rules (fixed decisions)
To keep the system consistent across teams, use these fixed naming rules.

### 3.1 Naming conventions (required)
- Saved Reports created in this doc: prefix with `RPT — `
- Saved list views created in this doc: prefix with `VIEW — `
- Workspace: `Ops — Reporting Pack`

Important: do not rename views created by earlier implementation docs.
These names are already used elsewhere and must remain stable:
- Doc 08A: `Stock Balance — Main - WH` (saved Stock Balance report)
- Doc 09A: `Price Overrides — by Client` (Item Price saved list view)
- Doc 11A: `Surgery Set Types — Readiness` (Surgery Set Type saved list view)

Examples:
- `RPT — Stock — Delivery In-Transit - WH`
- `VIEW — Tasks — Debt Collection (Open)`

### 3.2 What type of “report” you are building
ERPNext has 3 different mechanisms you will use:

1) Saved built-in report
- You open a standard ERPNext report (example: `Stock Balance`) and save it with filters.

2) Query Report (SQL)
- You create a `Report` with type `Query Report`.
- This is required when you need:
  - aging calculations
  - joins (tasks ↔ customers ↔ invoices)
  - “stuck” checks based on last movement dates

3) Saved list view
- You open a DocType list (example: `Task` list), apply filters/columns, and save the view.

---

## 4) Create the reporting workspace (required)
Goal: a novice user can open one place and find the reporting pack.

Steps:
1) Open `Workspace`.
2) Click `New`.
3) Fill:
   - Title: `Ops — Reporting Pack`
   - Module: `ERPNext`
   - Public: ON
4) Save.

Then add shortcuts (you will add these after creating the reports in section 5):
- `RPT — Stock — Delivery In-Transit - WH`
- `RPT — Stock — Return Pickup In-Transit - WH`
- `RPT — Stock — Returns - WH`
- `RPT — Stock — Client Locations (All)`
- `RPT — Ops — Driver Task Queue (Derived)`
- `RPT — Surgery Cases — Aging (Open)`
- `RPT — Receivables — Unpaid Invoices (Aging)`
- `RPT — Receivables — Unallocated Advances`
- `RPT — Risk — Debt Threshold Exceeded`
- `VIEW — Tasks — Debt Collection (Open)`
- `VIEW — Tasks — Distribute Payment (Open)`
- `VIEW — Tasks — Return to warehouse (Open)`
- `VIEW — Tasks — Discount Approval (Open)`
- `VIEW — Tasks — Purchase Approval (Open)`
- `VIEW — Tasks — Write-off Approval (Open)`
- `Price Overrides — by Client`
- `Surgery Set Types — Readiness`

---

## 5) Implement the Doc 13 report pack (step-by-step)
Each subsection below corresponds to Doc 13 sections 4.1–4.13.

### 5.1 RPT — Stock — Client Locations (All) (Doc 13 §4.1)
Question it answers:
- “What company-owned stock is physically at client locations right now?”

Primary truth:
- `Bin` (current stock by item + warehouse)

Steps:
1) Open `Report`.
2) Click `New`.
3) Set:
   - Report Name: `RPT — Stock — Client Locations (All)`
   - Report Type: `Query Report`
   - Ref DocType: `Bin`
4) In `Query`, paste:

```sql
select
  b.warehouse as client_location_warehouse,
  b.item_code,
  i.item_name,
  i.item_group,
  b.actual_qty
from `tabBin` b
join `tabWarehouse` w on w.name = b.warehouse
join `tabItem` i on i.name = b.item_code
where
  w.parent_warehouse = 'Clients - WH'
  and w.is_group = 0
  and b.actual_qty > 0
  and (%(client_location_warehouse)s is null or %(client_location_warehouse)s = '' or b.warehouse = %(client_location_warehouse)s)
  and (%(item_group)s is null or %(item_group)s = '' or i.item_group = %(item_group)s)
  and (%(item_code)s is null or %(item_code)s = '' or b.item_code = %(item_code)s)
order by b.warehouse, i.item_group, b.item_code;
```

5) In `Filters`, add exactly:
   - Label: `Client Location Warehouse`
     - Fieldname: `client_location_warehouse`
     - Fieldtype: `Link`
     - Options: `Warehouse`
   - Label: `Item Group`
     - Fieldname: `item_group`
     - Fieldtype: `Link`
     - Options: `Item Group`
   - Label: `Item Code`
     - Fieldname: `item_code`
     - Fieldtype: `Link`
     - Options: `Item`
6) Save.

Daily use:
- Use it to quickly see which client locations have company-owned stock.
- Drill down by filtering `Item Group`.

Validation:
- If you have any open Surgery Case that is in `Delivered` or later, you must see stock in that case’s `client_location_warehouse`.

---

### 5.2 RPT — Stock — Delivery In-Transit - WH (Doc 13 §4.2)
Steps:
1) Open `Report` → `New`.
2) Set:
   - Report Name: `RPT — Stock — Delivery In-Transit - WH`
   - Report Type: `Query Report`
   - Ref DocType: `Bin`
3) Query:

```sql
select
  b.item_code,
  i.item_name,
  i.item_group,
  b.actual_qty
from `tabBin` b
join `tabItem` i on i.name = b.item_code
where
  b.warehouse = 'Delivery In-Transit - WH'
  and b.actual_qty > 0
order by i.item_group, b.item_code;
```

4) Save.

Interpretation rule:
- Anything here is physically “outgoing / on the road” (Doc 05 + Doc 13).

---

### 5.3 RPT — Stock — Return Pickup In-Transit - WH (Doc 13 §4.3)
Create the same as 5.2, but with `b.warehouse = 'Return Pickup In-Transit - WH'`.

Save as:
- `RPT — Stock — Return Pickup In-Transit - WH`

---

### 5.4 RPT — Stock — Returns - WH (Doc 13 §4.4)
Create the same as 5.2, but with `b.warehouse = 'Returns - WH'`.

Save as:
- `RPT — Stock — Returns - WH`

Interpretation rule:
- Anything here is not sellable yet. It is a returns processing workload queue.

---

### 5.5 RPT — Ops — Driver Task Queue (Derived) (Doc 13 §4.5)
Doc 13 rule:
- Stock is still stored by warehouse.
- “By person” is derived from Task assignment discipline.

This report answers:
- “Which driver has which open delivery/pickup/drop-off tasks right now?”

Steps:
1) Open `Report` → `New`.
2) Set:
   - Report Name: `RPT — Ops — Driver Task Queue (Derived)`
   - Report Type: `Query Report`
   - Ref DocType: `Task`
3) Query:

```sql
select
  json_unquote(json_extract(t._assign, '$[0]')) as assigned_to,
  t.name as task,
  t.task_kind,
  t.status,
  t.customer,
  t.surgery_case,
  t.sales_order,
  t.sales_invoice,
  t.dispatch_group_id,
  t.subject,
  t.modified
from `tabTask` t
where
  t.status not in ('Completed', 'Cancelled')
  and t.task_kind in ('Delivery', 'Pickup Returns', 'Return drop-off at warehouse')
  and (
    %(assigned_to)s is null
    or %(assigned_to)s = ''
    or t._assign like concat('%', %(assigned_to)s, '%')
  )
order by assigned_to, t.modified asc;
```

4) Filters:
   - Label: `Assigned To`
     - Fieldname: `assigned_to`
     - Fieldtype: `Link`
     - Options: `User`
5) Save.

How to use it daily:
1) Use this report to identify the driver and the operational unit (`dispatch_group_id`, `surgery_case`, `sales_order`).
2) Then use the stock-in-transit reports (sections 5.2–5.4) to see which items are physically in transit.

---

### 5.6 RPT — Stock — In-Transit Stuck (Age Check) (Doc 13 §5.1)
Goal:
- Identify stock that is still in an in-transit warehouse and hasn’t moved recently.

Important note:
- Stock “age” is derived from the latest `Stock Ledger Entry` posting date for that item in that warehouse.

Steps:
1) Open `Report` → `New`.
2) Set:
   - Report Name: `RPT — Stock — In-Transit Stuck (Age Check)`
   - Report Type: `Query Report`
   - Ref DocType: `Stock Ledger Entry`
3) Query:

```sql
select
  b.warehouse,
  b.item_code,
  i.item_name,
  b.actual_qty,
  x.last_movement_date,
  datediff(curdate(), x.last_movement_date) as days_since_last_movement
from `tabBin` b
join `tabItem` i on i.name = b.item_code
join (
  select
    warehouse,
    item_code,
    max(posting_date) as last_movement_date
  from `tabStock Ledger Entry`
  where
    is_cancelled = 0
    and warehouse in ('Delivery In-Transit - WH', 'Return Pickup In-Transit - WH')
  group by warehouse, item_code
) x on x.warehouse = b.warehouse and x.item_code = b.item_code
where
  b.warehouse in ('Delivery In-Transit - WH', 'Return Pickup In-Transit - WH')
  and b.actual_qty > 0
  and datediff(curdate(), x.last_movement_date) >= %(min_days)s
order by days_since_last_movement desc, b.warehouse, b.item_code;
```

4) Filters:
   - Label: `Min Days`
     - Fieldname: `min_days`
     - Fieldtype: `Int`
     - Default: `1`
5) Save.

Daily use:
- Directors + Ops leads review this once per day.

---

### 5.7 VIEW — Surgery Cases — Aging by State (Doc 13 §4.6)
Doc 13 requires operational WIP visibility by state.

Implementation approach:
- Use **Saved list views** on `Surgery Case`.

Create these 4 list views (required):

#### 5.7.1 VIEW — Surgery Cases — Delivered (Awaiting Pickup)
1) Open `Surgery Case` list.
2) Filters:
   - Workflow State = `Delivered`
3) Columns:
   - Name
   - Client
   - Hospital
   - Hospital Branch
   - Surgery Date
   - Delivery Person
   - Return Pickup Delivery Person
   - Modified
4) Save view as: `VIEW — Surgery Cases — Delivered (Awaiting Pickup)`

#### 5.7.2 VIEW — Surgery Cases — Return Pickup In Transit
Filters:
- Workflow State = `Return Pickup In Transit`

Save as:
- `VIEW — Surgery Cases — Return Pickup In Transit`

#### 5.7.3 VIEW — Surgery Cases — Returns Received (Awaiting Usage)
Filters:
- Workflow State = `Returns Received`

Save as:
- `VIEW — Surgery Cases — Returns Received (Awaiting Usage)`

#### 5.7.4 VIEW — Surgery Cases — Usage Derived (Awaiting Invoice)
Filters:
- Workflow State = `Usage Derived`

Save as:
- `VIEW — Surgery Cases — Usage Derived (Awaiting Invoice)`

---

### 5.8 RPT — Surgery Cases — Aging (Open) (Doc 13 §4.6)
Goal:
- Show open cases with an explicit “age” number.

Steps:
1) Open `Report` → `New`.
2) Set:
   - Report Name: `RPT — Surgery Cases — Aging (Open)`
   - Report Type: `Query Report`
   - Ref DocType: `Surgery Case`
3) Query:

```sql
select
  sc.name as surgery_case,
  sc.workflow_state,
  sc.client,
  sc.hospital,
  sc.hospital_branch,
  sc.surgery_date,
  sc.delivery_person,
  sc.return_pickup_delivery_person,
  sc.modified,
  datediff(curdate(), date(sc.modified)) as age_days
from `tabSurgery Case` sc
where
  sc.workflow_state not in ('Closed')
  and (%(min_age_days)s is null or datediff(curdate(), date(sc.modified)) >= %(min_age_days)s)
order by age_days desc, sc.modified asc;
```

4) Filters:
   - Label: `Min Age Days`
     - Fieldname: `min_age_days`
     - Fieldtype: `Int`
     - Default: `0`
5) Save.

---

### 5.9 RPT — Receivables — Unpaid Invoices (Aging) (Doc 13 §4.7)
Steps:
1) Open `Report` → `New`.
2) Set:
   - Report Name: `RPT — Receivables — Unpaid Invoices (Aging)`
   - Report Type: `Query Report`
   - Ref DocType: `Sales Invoice`
3) Query:

```sql
select
  si.customer,
  si.name as sales_invoice,
  si.posting_date,
  si.due_date,
  si.status,
  si.outstanding_amount,
  datediff(curdate(), si.posting_date) as age_days,
  datediff(curdate(), si.due_date) as overdue_days
from `tabSales Invoice` si
where
  si.docstatus = 1
  and si.outstanding_amount > 0
  and (%(customer)s is null or %(customer)s = '' or si.customer = %(customer)s)
  and (%(from_date)s is null or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or si.posting_date <= %(to_date)s)
order by si.customer, overdue_days desc, age_days desc;
```

4) Filters:
   - Customer (Link → Customer) fieldname `customer`
   - From Date (Date) fieldname `from_date`
   - To Date (Date) fieldname `to_date`
5) Save.

---

### 5.10 RPT — Receivables — Unallocated Advances (Doc 13 §4.7A)
Goal:
- List customer receipts that still have unallocated balance.

Steps:
1) Open `Report` → `New`.
2) Set:
   - Report Name: `RPT — Receivables — Unallocated Advances`
   - Report Type: `Query Report`
   - Ref DocType: `Payment Entry`
3) Query:

```sql
select
  pe.party as customer,
  pe.name as payment_entry,
  pe.posting_date,
  pe.paid_amount,
  coalesce(sum(per.allocated_amount), 0) as allocated_amount,
  (pe.paid_amount - coalesce(sum(per.allocated_amount), 0)) as unallocated_amount
from `tabPayment Entry` pe
left join `tabPayment Entry Reference` per
  on per.parent = pe.name
  and per.reference_doctype = 'Sales Invoice'
where
  pe.docstatus = 1
  and pe.party_type = 'Customer'
  and pe.payment_type = 'Receive'
  and (%(customer)s is null or %(customer)s = '' or pe.party = %(customer)s)
group by pe.name
having unallocated_amount > 0.0001
order by pe.party, pe.posting_date desc;
```

4) Filters:
   - Customer (Link → Customer) fieldname `customer`
5) Save.

Operational rule reminder (Doc 13):
- This is client credit and must be considered when evaluating net debt.

---

### 5.11 RPT — Ops — Prepaid Orders Awaiting Delivery (Doc 13 §4.7B)
Required operating rule (go-live decision):
- When Accounting receives prepaid money intended for a specific Sales Order, they must allocate that Payment Entry against the Sales Order (Payment Entry Reference row to `Sales Order`).

Step-by-step (how Accounting records prepaid money so reporting works):
1) Create `Payment Entry` (Receive, Party Type = Customer, Party = client).
2) In `References`, add a row:
   - Reference Doctype: `Sales Order`
   - Reference Name: select the target Sales Order
   - Allocated Amount: the prepaid amount received
3) Submit the Payment Entry.

Steps:
1) Open `Report` → `New`.
2) Set:
   - Report Name: `RPT — Ops — Prepaid Orders Awaiting Delivery`
   - Report Type: `Query Report`
   - Ref DocType: `Sales Order`
3) Query:

```sql
select
  so.customer,
  so.name as sales_order,
  so.transaction_date,
  so.delivery_date,
  so.grand_total,
  so.per_delivered,
  coalesce(sum(case when pe.name is not null then per.allocated_amount else 0 end), 0) as advance_allocated
from `tabSales Order` so
left join `tabPayment Entry Reference` per
  on per.reference_doctype = 'Sales Order'
  and per.reference_name = so.name
left join `tabPayment Entry` pe
  on pe.name = per.parent
  and pe.docstatus = 1
  and pe.party_type = 'Customer'
  and pe.payment_type = 'Receive'
where
  so.docstatus = 1
  and so.status not in ('Closed', 'Completed')
  and so.per_delivered < 100
  and (%(customer)s is null or %(customer)s = '' or so.customer = %(customer)s)
group by so.name
having advance_allocated > 0
order by so.delivery_date asc, so.transaction_date asc;
```

4) Filters:
   - Customer (Link → Customer) fieldname `customer`
5) Save.

---

### 5.12 RPT — Risk — Debt Threshold Exceeded (Doc 13 §4.8)
Primary truth:
- Net receivable from `GL Entry` (same logic as Doc 09A automation).

Steps:
1) Open `Report` → `New`.
2) Set:
   - Report Name: `RPT — Risk — Debt Threshold Exceeded`
   - Report Type: `Query Report`
   - Ref DocType: `Customer`
3) Query:

```sql
select
  c.name as customer,
  c.customer_name,
  c.debt_threshold_amd,
  coalesce(gl.net_receivable_amd, 0) as net_receivable_amd,
  (coalesce(gl.net_receivable_amd, 0) - coalesce(c.debt_threshold_amd, 0)) as exceeded_by_amd
from `tabCustomer` c
left join (
  select
    party as customer,
    sum(debit - credit) as net_receivable_amd
  from `tabGL Entry`
  where
    is_cancelled = 0
    and party_type = 'Customer'
  group by party
) gl on gl.customer = c.name
where
  c.disabled = 0
  and coalesce(c.debt_threshold_amd, 0) > 0
  and coalesce(gl.net_receivable_amd, 0) > coalesce(c.debt_threshold_amd, 0)
order by exceeded_by_amd desc;
```

4) Save.

---

### 5.13 Task queue views (Doc 13 §4.9–4.9B)
Create these saved Task list views.

#### 5.13.1 VIEW — Tasks — Debt Collection (Open)
1) Open `Task` list.
2) Filters:
   - Task Kind = `Debt Collection`
   - Status not in `Completed, Cancelled`
3) Columns:
   - Subject
   - Customer
   - Current Debt AMD
   - Debt Threshold AMD
   - Assigned To
   - Modified
4) Save as: `VIEW — Tasks — Debt Collection (Open)`

#### 5.13.2 VIEW — Tasks — Distribute Payment (Open)
Filters:
- Task Kind = `Distribute Payment`
- Status not in `Completed, Cancelled`

Save as:
- `VIEW — Tasks — Distribute Payment (Open)`

#### 5.13.3 VIEW — Tasks — Return to warehouse (Open)
Filters:
- Task Kind = `Return to warehouse (aborted delivery / cancelled order)`
- Status not in `Completed, Cancelled`

Save as:
- `VIEW — Tasks — Return to warehouse (Open)`

#### 5.13.4 VIEW — Tasks — Discount Approval (Open)
Filters:
- Task Kind = `Discount Approval`
- Status not in `Completed, Cancelled`

Save as:
- `VIEW — Tasks — Discount Approval (Open)`

#### 5.13.5 VIEW — Tasks — Purchase Approval (Open)
Filters:
- Task Kind = `Purchase Approval`
- Status not in `Completed, Cancelled`

Save as:
- `VIEW — Tasks — Purchase Approval (Open)`

#### 5.13.6 VIEW — Tasks — Write-off Approval (Open)
Filters:
- Task Kind = `Write-off Approval`
- Status not in `Completed, Cancelled`

Save as:
- `VIEW — Tasks — Write-off Approval (Open)`

---

### 5.14 RPT — Sales — History by Client (Doc 13 §4.10)
Steps:
1) Open `Report` → `New`.
2) Set:
   - Report Name: `RPT — Sales — History by Client`
   - Report Type: `Query Report`
   - Ref DocType: `Sales Invoice`
3) Query:

```sql
select
  si.customer,
  si.hospital,
  si.hospital_branch,
  si.doctor_name,
  si.name as sales_invoice,
  si.posting_date,
  sii.item_code,
  sii.item_name,
  sii.qty,
  sii.rate,
  sii.amount
from `tabSales Invoice` si
join `tabSales Invoice Item` sii on sii.parent = si.name
where
  si.docstatus = 1
  and (%(customer)s is null or %(customer)s = '' or si.customer = %(customer)s)
  and (%(from_date)s is null or si.posting_date >= %(from_date)s)
  and (%(to_date)s is null or si.posting_date <= %(to_date)s)
order by si.customer, si.posting_date desc, si.name desc;
```

4) Filters:
   - Customer (Link → Customer) fieldname `customer`
   - From Date (Date) fieldname `from_date`
   - To Date (Date) fieldname `to_date`
5) Save.

---

### 5.15 Price override list (client special prices) (Doc 13 §4.10A)
Doc 09A implementation decision:
- Price overrides are stored as `Item Price` rows where `Customer` is filled, under price list `Standard Selling`.

Steps:
1) Open `Item Price` list.
2) Filters:
   - Price List = `Standard Selling`
   - Customer is set (not empty)
3) Columns:
   - Customer
   - Item Code
   - Item Name
   - Price List Rate
4) Save view as: `Price Overrides — by Client`

---

### 5.16 Low stock list by supplier (Doc 13 §4.11)
Doc 13 requires this view, but the setup is owned by **Doc 08A**.

Required configuration:
- Complete Doc 08A sections 4–6.

Required deliverables from Doc 08A:
- Saved report: `Stock Balance — Main - WH`
- Reorder tool/view (if your ERPNext has it): `Reorder — Main - WH`

Daily use:
- Purchasing uses `Reorder — Main - WH` and groups/filters by Supplier.

---

### 5.17 Surgery Set Type readiness (Doc 13 §4.12)
Doc 11A already implements readiness warning behavior.

Required deliverable:
- A `Surgery Set Type` list view that shows the readiness signal fields used by your Doc 11A implementation.

Implementation steps:
1) Open `Surgery Set Type` list.
2) Add the readiness columns you created in Doc 11A (example: readiness warning / readiness note).
3) Save view as: `Surgery Set Types — Readiness`.

---

### 5.18 RPT — Stock — Near Expiry (Main - WH) (Doc 13 §4.13)
Goal:
- List batches in `Main - WH` that are within a configurable near-expiry window.

Steps:
1) Open `Report` → `New`.
2) Set:
   - Report Name: `RPT — Stock — Near Expiry (Main - WH)`
   - Report Type: `Query Report`
   - Ref DocType: `Stock Ledger Entry`
3) Query:

```sql
select
  sle.item_code,
  i.item_name,
  sle.batch_no,
  b.expiry_date,
  sum(sle.actual_qty) as qty_in_main_wh,
  datediff(b.expiry_date, curdate()) as days_to_expiry
from `tabStock Ledger Entry` sle
join `tabBatch` b on b.name = sle.batch_no
join `tabItem` i on i.name = sle.item_code
where
  sle.is_cancelled = 0
  and sle.warehouse = 'Main - WH'
  and sle.batch_no is not null
  and sle.batch_no != ''
  and b.expiry_date is not null
  and b.expiry_date <= date_add(curdate(), interval %(near_expiry_days)s day)
group by sle.item_code, sle.batch_no
having qty_in_main_wh > 0
order by b.expiry_date asc, sle.item_code;
```

4) Filters:
   - Label: `Near Expiry Days`
     - Fieldname: `near_expiry_days`
     - Fieldtype: `Int`
     - Default: `30`
5) Save.

---

## 6) Cross-check reports (Doc 13 §5)
These are fast controls to catch broken processes.

### 6.1 RPT — Ops — Client Stock With No Open Cases (Doc 13 §5.3)
Goal:
- List client location warehouses that have stock, but no active Surgery Case referencing that warehouse.

Steps:
1) Create a Query Report:
   - Report Name: `RPT — Ops — Client Stock With No Open Cases`
   - Ref DocType: `Warehouse`
2) Query:

```sql
select
  w.name as client_location_warehouse,
  sum(b.actual_qty) as total_qty
from `tabWarehouse` w
join `tabBin` b on b.warehouse = w.name
left join `tabSurgery Case` sc
  on sc.client_location_warehouse = w.name
  and sc.workflow_state not in ('Closed')
where
  w.parent_warehouse = 'Clients - WH'
  and w.is_group = 0
group by w.name
having
  total_qty > 0
  and count(sc.name) = 0
order by total_qty desc;
```

3) Save.

Interpretation:
- If this list is non-empty, investigate whether:
  - the client location is a permanent on-site set (Doc 11), or
  - stock movement/case closure discipline is broken.

---

### 6.2 RPT — Data Quality — Tracked Items Missing Identifiers (Doc 13 §5.4)
Goal:
- Find submitted Stock Entries where batch/serial identifiers are missing for tracked items.

Steps:
1) Create a Query Report:
   - Report Name: `RPT — Data Quality — Tracked Items Missing Identifiers`
   - Ref DocType: `Stock Entry`
2) Query:

```sql
select
  se.name as stock_entry,
  se.posting_date,
  sed.item_code,
  i.item_name,
  i.has_batch_no,
  i.has_serial_no,
  sed.qty,
  sed.s_warehouse,
  sed.t_warehouse,
  sed.batch_no,
  sed.serial_no
from `tabStock Entry` se
join `tabStock Entry Detail` sed on sed.parent = se.name
join `tabItem` i on i.name = sed.item_code
where
  se.docstatus = 1
  and (
    (i.has_batch_no = 1 and (sed.batch_no is null or sed.batch_no = ''))
    or
    (i.has_serial_no = 1 and (sed.serial_no is null or sed.serial_no = ''))
  )
order by se.posting_date desc, se.name desc;
```

3) Save.

---

### 6.3 RPT — Pricing — Sales Orders With Manual Rate Edits (Doc 13 §5.5)
Goal:
- Periodically review items where the final `rate` differs from `price_list_rate`.

Steps:
1) Create a Query Report:
   - Report Name: `RPT — Pricing — Sales Orders With Manual Rate Edits`
   - Ref DocType: `Sales Order`
2) Query:

```sql
select
  so.customer,
  so.name as sales_order,
  so.transaction_date,
  soi.item_code,
  soi.item_name,
  soi.qty,
  soi.price_list_rate,
  soi.rate,
  (soi.rate - soi.price_list_rate) as rate_diff
from `tabSales Order` so
join `tabSales Order Item` soi on soi.parent = so.name
where
  so.docstatus = 1
  and abs(soi.rate - soi.price_list_rate) > 0.0001
order by so.transaction_date desc, so.name desc;
```

3) Save.

---

## 7) Acceptance criteria (Doc 13 §7)
This is a go-live check that the reporting pack exists and is usable.

### 7.1 Directors (daily)
Confirm Directors can open:
- `VIEW — Tasks — Debt Collection (Open)`
- `VIEW — Tasks — Distribute Payment (Open)`
- `VIEW — Tasks — Discount Approval (Open)`
- `VIEW — Tasks — Purchase Approval (Open)`

### 7.2 Operations leads (daily)
Confirm Ops can open:
- `RPT — Stock — Delivery In-Transit - WH`
- `RPT — Stock — Return Pickup In-Transit - WH`
- `RPT — Stock — Returns - WH`
- `RPT — Stock — Client Locations (All)`
- `RPT — Ops — Driver Task Queue (Derived)`
- Surgery case aging views (section 5.7 + 5.8)

### 7.3 Purchasing leads (daily/weekly)
Confirm Purchasing can open:
- Reorder views from Doc 08A (`Reorder — Main - WH`, `Stock Balance — Main - WH`)

### 7.4 Accounting (daily/weekly)
Confirm Accounting can open:
- `RPT — Receivables — Unpaid Invoices (Aging)`
- `RPT — Receivables — Unallocated Advances`

### 7.5 Reporting supports investigation
Pick 1 red flag and confirm you can drill into source documents:
- Example: stock stuck in `Delivery In-Transit - WH`.
- You must be able to identify:
  - which items
  - which warehouse
  - which operational document(s) / tasks are still open
