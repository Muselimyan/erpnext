# Operations Manual Index

**Purpose:** Master list of all step-by-step operation walkthroughs, ordered by importance. Each entry explains who uses it, how often, and what it covers.

---

## Priority order

### 1 — Purchase walkthrough: PO → Receipt → LCV → Invoice
**File:** `purchase-walkthrough.md`
**Status:** ✅ Written
**Who:** `Ops - Purchasing`, `Ops - Inventory`, `Ops - Directors`, `Ops - Accounting`
**Frequency:** Every time stock is ordered from a supplier
**What it covers:** Creating a draft Purchase Order, submitting for director approval, receiving goods into `Main - Inmed` (with batch/serial/expiry), creating a Landed Cost Voucher for import charges, entering the Purchase Invoice, and allocating prepayments. This is one of the most frequently repeated flows and involves multiple roles handing off to each other.

---

### 2 — New customer / client onboarding
**File:** `new-customer-onboarding.md`
**Status:** ✅ Written
**Who:** `Ops - Order Creating`, `Ops - Inventory` (warehouse creation), `Ops - Directors` (if credit limit requires approval)
**Frequency:** Every time a new doctor or hospital client is added
**What it covers:** Creating the Customer record (with doctor name, hospital, debt threshold, and default selling price list), creating the client location warehouse, linking the warehouse to the customer, and verifying the setup is ready for a Dispatch Case.

---

### 3 — Low-stock check and reorder routine
**File:** `low-stock-reorder-routine.md`
**Status:** ✅ Written
**Who:** `Ops - Purchasing`
**Frequency:** Daily or weekly scan
**What it covers:** How to open the ERPNext reorder report, interpret the reorder list, group items by supplier, build a Draft Purchase Order per supplier, and hand off to the director approval flow (Doc 07). Prevents stockouts and ensures the purchasing team has a repeatable daily routine.

---

### 4 — Standard sale dispatch (no return expected)
**File:** `standard-sale-walkthrough.md`
**Status:** ✅ Written
**Covers:** Full dispatch case from Order entry → Pack → Delivery → Invoice → Payment, where no items come back.

---

### 5 — Surgery case dispatch (return expected)
**File:** `surgery-case-walkthrough.md`
**Status:** ✅ Written
**Covers:** Full dispatch case where items are lent to a client, partially used, and the remainder is returned, inspected, restocked, and invoiced for used quantities only.

---

### 6 — New item setup
**File:** `new-item-setup.md`
**Status:** ✅ Written
**Who:** `Ops - Inventory`, `System Manager`
**Frequency:** Every time a new product is added to the catalog
**What it covers:** Creating an Item (or Item Template + Variants for sized products), setting the correct Item Group, UOM, tracking flags (batch/expiry/serial), HS code and import tax rate, linking to the default supplier (Item Supplier table), and verifying it is ready for purchase and dispatch. Also covers the price list entry for selling price.

---

### 7 — Supplier prepayment and invoice allocation
**File:** `supplier-prepayment-allocation.md`
**Status:** ✅ Written
**Who:** `Ops - Accounting`, `Ops - Finance`
**Frequency:** Every import purchase (most common payment mode is 100% advance)
**What it covers:** Creating a Payment Entry (Pay type) against an approved but not-yet-received PO, attaching bank transfer proof, and later allocating the advance against the Purchase Invoice once it is submitted. Important because the default mode for international suppliers is prepayment and there is no automated flow for this.

---

### 8 — Discount approval flow
**File:** `discount-approval-walkthrough.md`
**Status:** ✅ Written
**Who:** `Ops - Order Creating`, `Ops - Directors`
**Frequency:** Whenever a Dispatch Case is created with a discount
**What it covers:** A focused walkthrough of the discount approval sub-flow that is embedded in both dispatch walkthroughs but is useful as a standalone reference. Covers what triggers the approval task, what the Director does, the approved vs rejected paths, and how to revise pricing after rejection. Useful for training the order creation team.

---

### 9 — Returns and debt collection (standalone finance reference)
**File:** `debt-collection-and-payment.md`
**Status:** ✅ Written
**Who:** `Ops - Finance`
**Frequency:** Daily (finance team processes payments received from clients)
**What it covers:** A focused walkthrough for the Finance team on how to handle the Debt Collection task: recording incoming payments, the FIFO allocation across open invoices, the Distribute Payment task, and what happens when a client fully settles. Extracted from the dispatch walkthroughs for staff who only work the finance side and do not need the full case context.

---

### 10 — Stock adjustment and write-off
**File:** `stock-adjustment-writeoff.md`
**Status:** ✅ Written
**Who:** `Ops - Inventory`, `Ops - Directors` (for approval of write-offs)
**Frequency:** Occasional (physical inventory reconciliation, expired items, damaged goods)
**What it covers:** How to perform a Stock Reconciliation (physical count adjustment), how to create a Material Issue for damaged or expired items, and the governance rule (director visibility / approval) for write-offs. Covers both batch-tracked items (which require batch selection) and non-tracked items.

---

### 11 — Cancellation and correction procedures
**File:** `cancellation-and-corrections.md`
**Status:** ✅ Written
**Who:** All operational roles
**Frequency:** Occasional (when mistakes are made)
**What it covers:** What to do when a submitted document must be corrected — which documents can be cancelled, who can cancel, what to cancel first when documents are chained (e.g. cancelling a Sales Invoice before the Dispatch Case), and the rule that cancelled documents must have a written reason. Prevents staff from guessing and causing ledger inconsistencies.

---

### 12 — Daily reporting checks (stock, outstanding, tasks)
**File:** `daily-reporting-checks.md`
**Status:** ✅ Written
**Who:** Directors, `Ops - Accounting`, `Ops - Finance`, `Ops - Purchasing`
**Frequency:** Daily
**What it covers:** The set of reports each role should check each morning: open tasks by kind, stock levels vs reorder thresholds, unpaid invoices and client debt thresholds, items currently at client locations and in transit, and low-stock-by-supplier list. A "morning routine" reference card for each role.

---

### 13 — Delivery driver guide
**File:** `delivery-driver-guide.md`
**Status:** ✅ Written
**Who:** `Delivery Driver`
**Frequency:** Every delivery and return pickup run
**What it covers:** A focused, simple guide for the Delivery Driver role. How to find delivery tasks, mark as Picked Up, attach the required delivery photo, fill the handover note, mark as Delivered. Then the return pickup flow: finding the Return Pickup task, marking as Picked Up at client, attaching the drop-off photo at warehouse, marking as Returned to Warehouse. Written for a non-technical reader who only works from the task inbox.

---

### 14 — Collection Set setup and maintenance
**File:** `collection-set-setup.md`
**Status:** ✅ Written
**Who:** `Ops - Inventory`, `Ops - Order Creating`
**Frequency:** When a new item collection template is introduced or an existing one needs updating
**What it covers:** Creating a Collection Set (the item template used by the "Load from Template" button on Dispatch Cases), adding default items and quantities, updating templates as product lines change, and verifying the template works correctly on a Dispatch Case. This is the master data behind every surgery/return-expected dispatch case.

---

### 15 — New supplier setup
**File:** `new-supplier-setup.md`
**Status:** ✅ Written
**Who:** `Ops - Purchasing`, `Ops - Accounting`
**Frequency:** Every time a new supplier relationship starts
**What it covers:** Creating a complete Supplier record with legal name, contact person(s), default currency, payment terms, and notes. Setting up the Item ↔ Supplier link for each item sourced from that supplier. Verifying the supplier is ready to receive a Purchase Order. The operational pair to new-item-setup.md and new-customer-onboarding.md.
