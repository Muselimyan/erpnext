# ERPNext Implementation Requirements (Medical Supplier, Armenia)

## 1) Background
You are a medical supplier company in Armenia. You purchase products from international suppliers and distribute them to clients (mostly doctors, and a smaller number of hospitals/clinics).

The implementation must support:
- Standard distribution sales (deliver then invoice, mostly on credit)
- Inventory control for a large catalog with many variants
- Procurement + replenishment, including an “auto order list” when stock is low
- A special **surgery set/box** process: deliver a box containing multiple possible items; the client location uses a subset; unused items are returned; invoice only what was used
- A task-driven, cross-team operational workflow with traceability

This requirements file is the authoritative functional scope for the docs that follow.

## 2) In Scope
- ERPNext functional configuration for:
  - Stock / Warehousing
  - Buying (suppliers, POs, receipts, purchase invoices)
  - Selling (customers, delivery, invoices, payments)
  - Accounting receivables basics (credit sales, unpaid invoices)
  - Replenishment / reorder
  - Surgery sets (partial consumption + return)
  - Task/work workflow spanning multiple teams
  - Reporting required for day-to-day operations
- Light customization is allowed when needed for fit (confirmed: **custom DocType for Surgery Set Type**).

## 3) Out of Scope (for now)
- Server/VPS/Docker operations
- DNS/domain/SSL
- Outgoing email setup
- Backup strategy

## 4) Teams / Actors
- **Order Team**
  - Receives client order and creates the operational record in ERPNext
- **Preparing Team (Warehouse Pick/Pack)**
  - Prepares items or surgery set for dispatch
- **Delivery Team**
  - Delivers items/sets to the client location (doctor or hospital)
  - Must attach required photos to Tasks when required (warehouse pickup and warehouse drop-off)
  - Must be able to record a freeform handover note on delivery (example: who the package was handed to)
- **Accounting Team**
  - Issues invoices and tracks receivables
- **Purchasing Team**
  - Reviews reorder list and creates supplier POs
- **Returns Team**
  - Accepts returned items and processes the surgery set replenishment/dismantling logic

## 5) Core Operational Concepts / Glossary
- **Standard Order**: predictable delivery; no partial return expected.
- **Surgery Set (Box)**: a physical box of various items.
- **Surgery Set Type**: the template definition of which items/quantities a set is expected to contain.
- **Set Instance / Surgery Case**: one real event (one dispatch to a client location for a surgery) that results in consumption + return.
- **Client Location Group**: a physical delivery/usage location identity used for stock tracking.
  - Defined as a (Client / Customer) + (optional Hospital) + (Hospital Branch) combination when applicable.
  - Each Client Location Group has its own warehouse under `Clients - WH`.
- **Company-owned at client location**: items physically at a client location that are still owned by the company.
  - This includes both pending-return surgery cases and permanent on-site sets.
- **Delivery In-Transit**: items picked/prepared and handed to a delivery person, but not yet delivered to the client location.
- **Return Pickup In-Transit**: items picked up from a client location for return, but not yet received back into the warehouse/returns processing.

## 6) Confirmed Design Decisions
### 6.1 Inventory location tracking for clients
To know “what items are currently at which client location group” at any time, items that are physically at a client location and still company-owned must be represented as stock in ERPNext at that client location warehouse.

- **Decision**: create one warehouse per **Client Location Group** under a parent warehouse group: `Clients - WH`.
- Stock transfers to/from client location warehouses will be used to represent dispatch and returns.

### 6.2 Surgery set template representation
- **Decision**: implement **Option A** = a **custom DocType** for `Surgery Set Type` containing a child table of items and default quantities.

### 6.3 Ready-to-go set storage
- **Decision**: **no dedicated “Ready Sets” warehouse**.
  - Operationally, sets can be kept physically together, but ERPNext stock remains in the normal warehouse structure.

### 6.4 Tracking granularity
- **Decision**: track **exact items and quantities** delivered, returned, and consumed.

### 6.5 Batch/expiry + delivery vans
- **Decision**: use tracking where required:
  - **Implants / consumables**: track by **Batch (Lot)** and store **Expiry Date** on the batch where applicable.
  - **Tools / instruments**: track by **Serial Number** where the instrument has a serial.
- **Decision**: **no vans/mobile warehouses**.

### 6.5.3 FEFO for expiry-tracked items (critical)
- **Decision**: for items that have expiry dates, stock selection during packing/dispatch/consumption must follow **FEFO** (First-Expiry-First-Out).
- **Decision**: if a user selects a “fresher” batch while an older-expiring batch is available in `Main - WH`, the system must **alert** (so the team does not silently consume fresh stock while old stock expires).

### 6.5.1 Delivery and return staging warehouses
- **Decision**: use two staging warehouses:
  - `Delivery In-Transit - WH` (outgoing)
  - `Return Pickup In-Transit - WH` (incoming)

### 6.5.2 Delivery person allocation tracking (no per-driver warehouses)
- **Decision**: when items are in an in-transit warehouse, it must be possible to report which delivery person currently has them.
- **Constraint**: do not create a warehouse per delivery person; allocation will be tracked via delivery assignment/case records and derived in reporting.

### 6.6 Credit sales
- **Decision**: sales are **mostly on credit** (deliver first; invoice later; payment later).

### 6.6.1 Client debt thresholds and director alerts
- **Decision**: the system must track outstanding debt per client (accounts receivable).
- **Decision**: each client may have a different debt threshold.
- **Decision**: directors must be alerted when a client exceeds its threshold.
- **Decision**: the alert must be automated by creating (or updating) a director **Debt Collection** task for that client.

### 6.6.2 Partial payments (“semi-paid” invoices) and batched receipts
- **Decision**: the system must support **partial payments** against Sales Invoices (invoices can be **Partly Paid** until fully settled).
- **Decision**: a single payment receipt may be allocated across **multiple invoices** for the same client.
- **Decision (recommended)**: if a payment is received without a clear invoice allocation, it must be possible to record it as a **customer advance / unallocated payment**, and allocate it later.
- **Decision (recommended)**: client debt for thresholds should be based on **net receivable**:
  - total outstanding invoice amounts
  - minus any unallocated/advance payments (client credit)
- **Decision**: default payment allocation is **oldest invoices first**.
- **Decision**: there is **no time limit** for leaving money as an unallocated advance (it may represent long-lived client credit).
- **Decision**: allocation/adjustment of payment allocations is allowed for **Accounting and Directors**.
- **Decision**: the internal `Distribute Payment` control step is created per **payment receipt**.

Additional requirement (upfront payments / prepaid delivery):
- Some clients pay **before delivery**.
- The system must allow recording an upfront payment as a **customer advance** even if:
  - the invoice does not exist yet, and/or
  - delivery will happen later.
- After delivery, Accounting can create the invoice and allocate the advance so the invoice becomes **Paid** immediately.
- **Decision**: partial upfront payments (deposit model) are allowed.

### 6.7 Currency
- **Decision**: use **AMD** as the system currency.

### 6.8 Taxes / VAT
- **Decision**: taxes/VAT are **not required for now** (may be added later).

### 6.9 Pricing behavior
- **Decision**: mostly **static price lists**, but allow:
  - **occasional discounts** per order, and
  - **price overrides** for specific clients (see 6.9.1).

### 6.9.1 Price overrides by client / hospital (special prices)
- **Decision**: the system must support different selling prices for the same item depending on:
  - the client (Customer).
- **Decision**: destination hospital context does not determine price (hospital is captured for operational/reporting context only).
- **Decision (recommended)**: maintain an always-referenceable **Price Override List** so staff can quickly verify the correct price during order entry.
- **Decision**: overrides are maintained as **per-client-per-item** prices.
- **Decision**: price overrides are **indefinite until changed** (no validity windows at go-live).
- **Decision**: Accounting maintains price overrides; Directors approve changes above a defined threshold.
- **Decision**: manual rate entry is allowed only for Accounting/Directors and requires a short reason when deviating from the override list.
- **Decision**: invoices should take prices from the Sales Order (order is the operational pricing truth), not re-lookup item prices at invoicing time.

### 6.10 Supplier association per item
- **Decision**: ordering team must be able to see low-stock items **grouped/filterable by supplier** to support ordering from supplier A vs supplier B.

### 6.11 Supplier per item
- **Decision**: each item has **one supplier** (no multi-supplier purchasing for the same item).

### 6.12 Buy in boxes, sell singles (pack-breaking)
- **Reality**: some products are purchased in boxes, but are sold/issued as single units.
- **Decision (recommended)**: represent these using a single Item with:
  - Stock UOM = single unit (e.g., `Nos`)
  - Purchase UOM = `Box`
  - a defined conversion factor (`1 Box = N Nos`)
  - This preserves batch/expiry traceability (batch numbers remain on the same Item).
- **Allowed exception**: for non-tracked items where batch/expiry is not required, you may keep separate “Box item” and “Single item” identities and use a controlled repack/conversion stock movement.

Additional decisions (confirmed):
- For doctor-clients, hospital is recorded on transactions as an optional `Hospital` link field (Sales Order, Sales Invoice, Surgery Case).
- For hospital-clients (no named doctor), capture an optional free-text `Doctor Name` on transactions.
- Hospital Branch must be mandatory on Surgery Cases so the system can derive the correct Client Location Group warehouse.
- FEFO enforcement at go-live is a **warning** (not a hard-block).
- Near-expiry threshold for warnings/escalation is **1 month**.
- For pack-breakable items that require batch/expiry traceability, migrate to the single-Item + UOM-conversion model.

### 7) Functional Requirements

### 7.1 Item catalog and variants
- Must support many products and variants (e.g., sizes/versions of the same product).
- Implementation must allow:
  - Organizing items by groups/categories
  - Defining variants in a consistent way
  - Maintaining purchase price and selling price (and later other expenses)

**Acceptance criteria**
- A user can find and select the correct variant quickly during sales and purchase transactions.
- Reporting can be done per item and per variant.

### 7.2 Procurement (international suppliers)
- Must support purchase ordering from suppliers periodically.
- Track buying prices and the procurement flow.
- Procurement must support shipment/import status tracking beyond basic P2P.

**Acceptance criteria**
- Purchasing can create and manage purchase orders.
- Purchase orders can be routed for approval by the Director team.
- Receiving can record what arrived.
- Accounting can record supplier invoices.

### 7.2.2 Procurement shipment/import status workflow
Procurement must support a simple operational status/task pipeline to track international purchases.

Minimum statuses (initial):
- Need to order
- Ordering
- Ordered
- Shipped
- Import
- Accepted to warehouse

**Acceptance criteria**
- Each procurement event can be tracked through the statuses above.
- Ownership is clear per stage (ordering team vs director approval vs warehouse receiving).

### 7.2.1 Ordering from suppliers (always-available reorder list)
- The ordering team must be able to see, at any time, what needs to be ordered (no fixed ordering cycle is defined yet).
- Since each item has one supplier, the ordering team must be able to:
  - view low-stock items
  - group/filter them by supplier
  - prepare purchase orders per supplier
- Purchase orders must follow: Draft → Director Approval → Submitted/Sent to supplier.

**Acceptance criteria**
- Ordering team can open a reorder view and filter it to Supplier A to see exactly what to order from Supplier A.
- For a selected supplier, the system supports creating a draft PO containing the relevant items.
- Director team can approve (or reject) the PO before it is submitted.

### 7.3 Replenishment / “Auto Order List”
- When any item is low on stock, the ordering team must see it in a list/table at any time.
- The system must support:
  - Min/max or reorder point thresholds per item
  - A consolidated reorder view and conversion into a purchasing action
  - Visibility of which supplier each item is purchased from, so purchase orders can be prepared per supplier

**Acceptance criteria**
- At any time, purchasing can open a list of low-stock items.
- Purchasing can filter/group the reorder list by supplier and prepare a purchase order for a selected supplier.

### 7.4 Standard sales flow (no return expected)
Process:
1) Client places an order for one or more items
2) Preparing team prepares items for shipment
3) Delivery delivers to the client location
4) Accounting creates invoice
5) Client pays later (mostly credit)

Supported variant (upfront payment / prepaid delivery):
- Client pays **before delivery**.
- Delivery may happen later when requested.
- Recommended operational mechanism:
  - record the receipt as a **customer advance** when paid,
  - deliver later,
  - create the invoice after delivery and allocate the advance so the invoice becomes **Paid** immediately.

Additional requirement:
- Must be possible to record the destination hospital when needed (optional `Hospital` context on documents, for doctor-clients that operate at a specific hospital).

Discount requirement:
- Order team can apply a discount, but the discount must be approved by Director team.

Pricing override requirement (new):
- When entering an order, staff must be able to see/apply the correct price based on the client.
- The system must support a simple “price lookup / override list” view for:
  - a specific client, and
  - its negotiated/special prices per item.
- Invoicing uses the order’s prices (invoice is not allowed to silently re-price).

Receivables control requirement:
- Must be possible to define a debt threshold per client.
- Directors must be alerted when a client exceeds its threshold.

Receivables payment behavior requirement (new):
- Payments may be **partial** and may be paid as one amount that is allocated across multiple invoices.
- Payments received without clear allocation must be recordable as a **client advance/unallocated** amount and allocated later.
- Reporting must show both:
  - invoice-level outstanding (including partly paid invoices)
  - unallocated advances (so net debt is explainable)

**Acceptance criteria**
- The system shows:
  - what is pending delivery
  - what has been delivered
  - what is invoiced
  - what is unpaid
- Directors can see which clients have exceeded their debt threshold.
- When a client exceeds its threshold, a director Debt Collection task exists and reflects the current debt.

### 7.5 Surgery set (box) flow: partial consumption + return
High-level requirements:
- A client orders a surgery set for a specific surgery.
- The set is delivered containing a combination of items.
- During surgery, the client location uses whatever is needed.
- Unused items are returned.
- You invoice **only the used items**.
- After return:
  - either replenish the set (if frequently used)
  - or dismantle and put items back into their normal places

**Inventory truth requirement**
- At any moment, it must be possible to know:
  - which items/qty are at which client location pending return
  - which items/qty were consumed vs returned

**Template shortage handling requirement (new)**
- When using a Surgery Set Type template to prepare a case, if there is not enough inventory to fill the template fully, the system must allow preparing a partial set:
  - fill the case with whatever quantities are available
  - skip items that are completely missing
  - show a clear warning that some items were missing (including which items and the missing quantities)

**Template readiness visibility (new)**
- In the Surgery Set Type list, users should be able to see which templates are currently not fully fillable from inventory.
- The system should provide a view/report that indicates per template:
  - whether it is fully fillable
  - which items are short (and by how much)

Decisions:
- Template readiness should be computed from **net availability** (subtract committed demand from open cases/orders).
- When a template is short, always allow proceeding with **warning** (no hard-block at go-live).
- For partially available items, auto-fill the available quantity and show a clear warning.
- Shortage warnings must be recorded both on the Surgery Case and on-screen.
- You may define “critical items”, but at go-live they should only cause stronger warnings (not a hard-block).

**Acceptance criteria**
- The system can produce a correct “items currently at client location” view.
- For each surgery event, you can reconcile:
  - Delivered = Used + Returned (with exact quantities)
- Invoice reflects only used quantities.
- When a template is short, the user can still proceed with a partial set and sees a warning listing missing items.


### 7.6 Task-driven cross-team workflow
The process must be supported by tasks/stages across teams.

Required stages (minimum):
- Order intake (order team)
- Prepare shipment/set (preparing team)
- Deliver to client location (delivery team)
  - **Mandatory**: attach a photo at warehouse pickup (before leaving `Main - WH`)
- If standard order: invoice task (accounting)
- If surgery set:
  - Wait for surgery completion / receive usage info (separate role/team)
  - Pickup returns (delivery team)
    - No client pickup photo requirement
  - Hand off to returns team (delivery → returns)
    - **Mandatory**: attach a photo at warehouse drop-off (before handing the package to the Returns Team)
  - Returns team accepts and processes set
  - Accounting invoices used items

Additional requirement:
- Delivery and pickup tasks must capture the assigned delivery person so the system can report which items are currently with which delivery person while in transit.

**Acceptance criteria**
- Every surgery set case has a clear status and owner at each step.
- Delivery tasks can capture:
  - a Warehouse Pickup Photo (outgoing)
  - a freeform handover note (who the package was handed to)
- Return drop-off tasks cannot be closed without photo evidence.

### 7.7 Reporting requirements
Must support operational reporting, including:
- Items and quantities currently located at each client location (company-owned at client)
- Items and quantities currently in `Delivery In-Transit - WH`, grouped by delivery person (derived from assignment records)
- Items and quantities currently in `Return Pickup In-Transit - WH`, grouped by delivery person (derived from assignment records)
- Sold history per client
- Price override list / price lookup by client
- Prepaid orders awaiting delivery (clients paid upfront but delivery is still pending)
- Unpaid invoices (accounts receivable)
- Unallocated customer advances (payments received but not yet allocated to invoices)
- Clients exceeding their debt threshold
- Open Debt Collection tasks (per client) with current debt
- Low-stock items (reorder list)
- Purchase price, selling price, and other expenses (expense tracking details TBD)

**Acceptance criteria**
- A manager can answer:
  - “What items are at Client X right now?”
  - “Which clients hold Item Y right now?”
  - “What does Client X owe us?”
  - “Which clients are above their debt threshold?”
  - “Which items do we need to reorder this cycle?”

## 8) Data / Volume Assumptions (confirmed)
- Approx clients involved in the surgery set flow: **~50**.

## 9) Future Phase Requirements (not required for initial go-live)
These items are explicitly deferred to a later phase and will be covered by separate documents.

1) Other expenses definition (shipping/customs/overheads) and required cost allocation detail.

---

