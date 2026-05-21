# ERPNext Operations Testing Manual

**Purpose:** Use this file as the main testing roadmap for the ERPNext setup. It tells you which manual to open, what business process you are testing, which ERPNext screens must be searchable, which role/user should perform the test, and what result proves that the setup works.

**Manual set status:** ✅ Finished for colleague review as of 2026-05-21. Live ERPNext smoke testing and real-user signoff are still separate go-live activities.

## Finished manual files
| File | Status |
|---|---|
| `cancellation-and-corrections.md` | ✅ Finished |
| `collection-set-setup.md` | ✅ Finished |
| `daily-reporting-checks.md` | ✅ Finished |
| `debt-collection-and-payment.md` | ✅ Finished |
| `delivery-driver-guide.md` | ✅ Finished |
| `discount-approval-walkthrough.md` | ✅ Finished |
| `erpnext-manual-setup-checklist.md` | ✅ Finished |
| `low-stock-reorder-routine.md` | ✅ Finished |
| `new-customer-onboarding.md` | ✅ Finished |
| `new-item-setup.md` | ✅ Finished |
| `new-supplier-setup.md` | ✅ Finished |
| `purchase-walkthrough.md` | ✅ Finished |
| `standard-sale-walkthrough.md` | ✅ Finished |
| `stock-adjustment-writeoff.md` | ✅ Finished |
| `supplier-prepayment-allocation.md` | ✅ Finished |
| `surgery-case-walkthrough.md` | ✅ Finished |
| `surgery-set-type-setup.md` | ✅ Finished |

---

## How to use this manual during testing

Do not read every file from top to bottom before starting. Test one business flow at a time.

For each test:

1. Open the manual file shown in the **File** column.
2. Login as a test/example user with the role shown in the **Role/user** column.
3. Search ERPNext for the exact screen names shown in the **ERPNext screens to confirm first** column.
4. If a screen is missing, stop and record it as a permission/setup blocker.
5. Complete the steps in the manual.
6. Compare the result with the **Pass condition** column.

---

## Fast testing order

Use this order to test the new ERPNext setup quickly:

| Order | File | What you are testing | Role/user | ERPNext screens to confirm first | Pass condition |
|---|---|---|---|---|---|
| 1 | `new-supplier-setup.md` | Supplier master data can be created and used for buying | `Ops - Purchasing` | `Supplier`, `Contact`, `Payment Terms Template`, `Item` | Supplier exists, has contact/payment terms, and linked items can be used on a Purchase Order |
| 2 | `new-item-setup.md` | A product can be created with supplier, UOM, tracking, and price | `Ops - Inventory` / `Ops - Accounting` | `Item`, `Item Group`, `UOM`, `Item Price`, `Supplier` | Item saves successfully and is ready for purchase/sale testing |
| 3 | `new-customer-onboarding.md` | Customer and client warehouse can be created | `Ops - Order Creating`, `Ops - Inventory`, `Ops - Accounting` | `Customer`, `Warehouse` | Customer is active/non-provisional and warehouse exists under `Clients - Inmed` |
| 4 | `purchase-walkthrough.md` | Buying flow works end-to-end | `Ops - Purchasing`, `Ops - Directors`, `Ops - Inventory`, `Ops - Accounting` | `Purchase Order`, `Task`, `Purchase Receipt`, `Landed Cost Voucher`, `Purchase Invoice`, `Payment Entry` | Purchase Order is approved, goods are received, landed cost/invoice are recorded |
| 5 | `standard-sale-walkthrough.md` | Simple sale with no return works | `Ops - Order Accepting`, `Ops - Order Creating`, `Ops - Inventory`, `Delivery Driver`, `Ops - Accounting` | `Task`, `Dispatch Case`, `Stock Entry`, `Delivery Note`, `Sales Invoice` | Case moves through delivery and invoicing without return steps |
| 6 | `surgery-case-walkthrough.md` | Full return-expected case works | Order, Inventory, Driver, Returns, Accounting, Finance roles | `Task`, `Dispatch Case`, `Stock Entry`, `Sales Invoice`, `Payment Entry` | Case completes dispatch, return, inspection, restock, invoice, and payment/debt steps |
| 7 | `debt-collection-and-payment.md` | Finance can record customer payment and close debt | `Ops - Finance` | `Task`, `Payment Entry`, `Accounts Receivable`, `Dispatch Case` | Payment reduces outstanding amount and closes the case when fully paid |

Use these only when the matching situation happens:

- `discount-approval-walkthrough.md` — only when testing discounted Dispatch Cases.
- `supplier-prepayment-allocation.md` — only when testing advance supplier payments.
- `stock-adjustment-writeoff.md` — only when testing stock count corrections, expired goods, or damaged goods.
- `cancellation-and-corrections.md` — only when testing mistakes and corrections.
- `daily-reporting-checks.md` — use after test transactions exist, to confirm reports and task queues.
- `delivery-driver-guide.md` — use for training/testing the Delivery Driver role only.
- `collection-set-setup.md` — use before surgery case testing if Collection Sets are missing or need updates.

---

## Before testing with role users

When a manual says **Login as:** `Ops - Purchasing`, `Ops - Inventory`, or another role, it means login as a test/example user that has that role. The username does not need to match the role name.

Before continuing each flow, confirm that the test user can search for and open the main ERPNext screen named in the step. Search for the exact DocType/report/tool name, such as `Supplier`, `Item`, `Customer`, `Warehouse`, `Purchase Order`, `Task`, or `Stock Balance`.

If the expected screen does not appear in search, stop and record it as a setup/permission blocker. Do not spend time trying to work around it inside the walkthrough. A System Manager should check the user's role assignment, Role Permission Manager settings, and any User Permission restrictions.

Known setup items that may affect testing:

- `Ops - Purchasing` must have access to `Supplier` before `new-supplier-setup.md` can be tested as the purchasing user.
- `Ops - Inventory` must have create/write access to `Item`, `Item Group`, `Item Attribute`, and `UOM` before `new-item-setup.md` can be tested as the inventory user.
- Current ERPNext Supplier Groups are `Distributor`, `Local`, `Raw Material`, `Services`, `Pharmaceutical`, `Hardware`, and `Electrical`. Do not use old documentation names such as `Manufacturers`, `Distributors`, or `Local Vendors` unless those groups are created later.
- Current supplier master data for `ZMD` and `CHUNLI` is ready for purchasing tests: Supplier Group = `Distributor`, Default Currency = `USD`, Payment Terms = `Prepayment 100%`.
- `Payment Terms Template` records `Prepayment 100%` and `Prepayment 50/50` exist.
- Existing item prices may still be empty, so selling/purchase tests may require creating test `Item Price` records first.
- Existing item batch/expiry/serial tracking may not be finalized, so use a controlled test item when testing stock receipt or dispatch.
- The real client warehouse group name is `Clients - Inmed`.

---

## What to write down when something fails

When a test does not work, record the issue in this format:

| Field | What to write |
|---|---|
| Manual file | Example: `new-supplier-setup.md` |
| Step number | Example: Step 1 |
| Logged-in user | Email/username of the test user |
| Expected screen/action | Example: Search `Supplier`, open **Supplier** list, click **New** |
| What actually happened | Example: only supplier performance report appeared |
| Likely category | Permission, missing setup data, script error, unclear manual, or user mistake |
| Next action | Example: System Manager must check `Supplier` permissions for `Ops - Purchasing` |

This prevents testing from becoming confusing. If a permission/setup blocker appears, do not spend time trying random screens.

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
**What it covers:** How to search for `Itemwise Recommended Reorder Level` and open the ERPNext reorder report, interpret the reorder list, group items by supplier, build a Draft Purchase Order per supplier, and hand off to the director approval flow (Doc 07). Prevents stockouts and ensures the purchasing team has a repeatable daily routine.

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
