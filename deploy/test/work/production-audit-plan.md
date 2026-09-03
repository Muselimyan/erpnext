# Production Audit Plan — Scripts vs Documentation Analysis

> **Purpose**: Systematic audit of all deployed ERPNext customizations (server scripts, client scripts, custom fields, custom DocTypes, reports, workspaces) against the documentation set. Each group is designed to be analyzed in a **separate, parallel session** with no cross-session dependencies.
>
> **Accuracy rule**: Every finding must be verified against the actual deployed code and the actual documentation text. No assumptions. No guessing. If something is unclear, flag it as "NEEDS VERIFICATION" rather than making an assumption.
>
> **Created**: 2026-08-27

---

## 1. Inventory Summary

| Artifact | Count | Notes |
|---|---|---|
| Server scripts | 62 total (52 enabled, 10 disabled) | Python: DocType Event, API, Scheduler |
| Client scripts | 39 total (37 enabled, 2 disabled) | JavaScript: Form, List, Workspace |
| Custom DocTypes | 19 | 7 parent, 11 child tables, 1 singleton |
| Custom fields | 137 | Across 21 standard DocTypes; 62 on Task alone |
| Property setters | 209 | Field visibility/label/default overrides |
| Reports | 49 | All Query Reports, all enabled |
| Workspaces | 22 | 3 custom operational + 19 standard |
| Notifications | 5 | 2 enabled, 3 disabled |
| Role profiles | 6 | |
| Workflows | 1 | |
| Print formats | 1 | |
| **Total script lines** | **8,156** | 4,730 JS + 3,426 Python |

### Source of Truth

All deployed artifacts were extracted from the **test instance** (mirror of prod) into:
- `deploy/test/work/server/*.py` — 59 server script files (62 in schema; 3 are embedded in schema JSON but may have different file extraction)
- `deploy/test/work/client/*.js` — 39 client script files
- `deploy/test/schema/*.json` — 11 schema export files (custom fields, DocTypes, property setters, reports, workspaces, etc.)

### Documentation Set

Located in `docs/`. Key docs by area:
- **Active/current**: Docs 02–08, 10, 10.1, 13, 14, 15, 15a, 16, 16a, 16b, 17, 17a
- **Superseded** (retained for reference): Docs 09, 09a, 11, 11a, 12, 12a
- **Manuals**: 19 walkthrough/procedure documents under `docs/manual/`
- **Misc**: migration notes, go-live plans, barcode docs, infrastructure docs

---

## 2. Functional Area Groups

### Group 1: Dispatch Case Lifecycle
**Priority: HIGHEST — core business flow**

This is the central operational flow. Dispatch Case replaced Sales Order + Surgery Case as the single coordinator record for all client deliveries. This group covers the Dispatch Case DocType itself, its state machine, stock entry automation, invoice generation, and the task chain that drives the flow.

#### Server Scripts (10 enabled, 1 disabled)

| # | Script | Type | DocType | Event | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|---|
| 1 | `Dispatch-Case-before-save.py` | DocType Event | Dispatch Case | Before Save | Yes | 18 | Calculates `used_qty` from dispatched/returned/lost; sets status to "Awaiting Approval" if discounts exist |
| 2 | `Dispatch-Case-before-save-lock-submitted.py` | DocType Event | Dispatch Case | Before Save | Yes | 20 | Locks submitted DCs — only Directors/System Manager/Administrator can edit |
| 3 | `Dispatch-Case-before-submit.py` | DocType Event | Dispatch Case | Before Submit | Yes | 13 | Validates at least one item exists; updates status from Draft to Confirmed |
| 4 | `Dispatch-Case-after-save.py` | DocType Event | Dispatch Case | After Save | Yes | 36 | Creates Discount Approval task when DC enters "Awaiting Approval" |
| 5 | `Task-after-save-dispatch-flow.py` | DocType Event | Task | After Save | Yes | 268 | **MAIN ORCHESTRATOR** — creates stock entries for all warehouse transfers, generates Sales Invoices, creates Debt Collection tasks, chains to next task on completion |
| 6 | `Task-before-save-dispatch-gates.py` | DocType Event | Task | Before Save | Yes | 118 | Enforces workflow gates: requires acceptance, validates status transitions (Picked Up→Delivered), requires photos/packing before completion |
| 7 | `Task-before-save-pack-complete-creates-delivery-task.py` | DocType Event | Task | Before Save | Yes | 74 | When Pack task completes, auto-creates Delivery task assigned to first available driver |
| 8 | `Delivery Note-before-submit-delivery-gate.py` | DocType Event | Delivery Note | Before Submit | Yes | 24 | Delivery gate: validates warehouse, discount approval, prepayment for Sales Order-based deliveries |
| 9 | `task_create_dispatch_case.py` | API | — | — | Yes | 29 | API: creates a new Dispatch Case linked to a task |
| 10 | `task_update_return_item_quantities.py` | API | — | — | Yes | 40 | API: updates returned/lost/used quantities on a DC item during returns |
| 11 | `Stock Entry-before-submit-dispatch-gate.py` | DocType Event | Stock Entry | Before Submit | **DISABLED** | 49 | Validates Sales Order linkage, discount approval, delivery photo, prepayment on dispatch staging transfers |

#### Client Scripts (7 enabled)

| # | Script | DocType | View | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|
| 1 | `Dispatch Case-Form.js` | Dispatch Case | Form | Yes | 98 | Hides fields, implements item edit lock by role, loads Collection Set items |
| 2 | `Dispatch Case-Lock Submitted.js` | Dispatch Case | Form | Yes | 5 | Client-side lock for submitted DCs (mirrors server-side) |
| 3 | `Dispatch Case-Simplify for Order Creation.js` | Dispatch Case | Form | Yes | 111 | Hides task/stock/photo/packing fields for Order Creation team |
| 4 | `Surgery-Case-field-locking.js` | Surgery Case | Form | Yes | 16 | Locks qty fields by Surgery Case workflow state |
| 5 | `SO-customer-autofill.js` | Sales Order | Form | Yes | 26 | Auto-fills hospital/doctor_name on Sales Order by customer type |
| 6 | `Task-Create Dispatch Case Items.js` | Task | Form | Yes | 71 | Buttons to create/open Dispatch Case from various task kinds |
| 7 | `Task-Product Lines Display.js` | Task | Form | **No (DISABLED)** | 76 | Superseded by #6; had hardcoded wrong warehouse |

#### Custom DocTypes (4)

- `Dispatch Case` (submittable) — the coordinator record
- `Dispatch Case Item` (child table) — items with dispatched/returned/lost/used qty
- `Debt Collection Invoice` (child table) — open invoices on Debt Collection tasks
- `Debt Collection Payment` (child table) — payment history on Debt Collection tasks

#### Custom Fields

- 10 on `Dispatch Case`: allow_items_edit, packing fields (6), profit, select_surgical_kit_template
- 10 on `Dispatch Case Item`: packing status/scan fields (8), fefo_warning, remaining_qty
- 3 on `Stock Entry`: dispatch_group_id, sales_order, surgery_case

#### Reference Docs

- `16-unified-dispatch-flow.md` — operational spec (14 states, task chain, stock entries)
- `16a-unified-dispatch-flow-implementation.md` — implementation guide
- `16b-unified-dispatch-flow-gap-analysis.md` — gap analysis
- `manual/standard-sale-walkthrough.md` — no-return smoke test
- `manual/surgery-case-walkthrough-v2.md` — return-expected smoke test
- `manual/discount-approval-walkthrough.md` — discount sub-flow

#### Known Concerns (to investigate)

- `Surgery-Case-before-save.py` (255 lines, **ENABLED**) — full Surgery Case workflow orchestrator. Docs say Surgery Case is superseded by Dispatch Case. Is this still actively used? Does it conflict with `Task-after-save-dispatch-flow.py`?
- `Surgery-Case-field-locking.js` and `SO-customer-autofill.js` — client scripts for superseded DocTypes, still enabled
- `Stock Entry-before-submit-dispatch-gate.py` — disabled but docs (16a) describe it as part of the flow. Was it replaced by logic inside `Task-after-save-dispatch-flow.py`?
- `Delivery Note-before-submit-delivery-gate.py` — operates on Delivery Note, but Dispatch Case flow uses Stock Entries not Delivery Notes. Is this dead code?
- `Dispatch-Case-after-save.py` creates discount approval — but `Dispatch-Case-before-save.py` also sets "Awaiting Approval". Potential race condition or double-trigger?

---

### Group 2: Task System and Gates
**Priority: HIGH — every flow depends on this**

The Task system underpins all operations. Every workflow step creates/completes tasks. This group covers task creation, acceptance, locking, role-based access, status enforcement, and the task chain mechanics.

#### Server Scripts (9 enabled, 4 disabled)

| # | Script | Type | DocType | Event | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|---|
| 1 | `Task-before-save-policy.py` | DocType Event | Task | Before Save | Yes | 84 | Enforces role-based access by task_kind; validates task_access_policy; sets completed_at |
| 2 | `Task-before-save-lock-completed.py` | DocType Event | Task | Before Save | Yes | 9 | Blocks all modifications to Completed tasks |
| 3 | `Task-before-save-lock-unaccepted.py` | DocType Event | Task | Before Save | Yes | 34 | Requires acceptance before editing; resets acceptance on reassignment |
| 4 | `Task-before-save-auto-subject.py` | DocType Event | Task | Before Save | Yes | 10 | Auto-generates 5-digit numeric subject if missing |
| 5 | `Task-Account Details Default Assignment.py` | DocType Event | Task | Before Save | Yes | 29 | Default subject + assignment for "Account details" tasks |
| 6 | `Task-Other Entry Default Subject.py` | DocType Event | Task | Before Save | Yes | 12 | Default subject for "Other: Entry/Processing" tasks |
| 7 | `Task-after-save-account-details-processing.py` | DocType Event | Task | After Save | Yes | 73 | Account Details: Entry → Processing task chain with attachment copy |
| 8 | `Task-after-save-other-processing.py` | DocType Event | Task | After Save | Yes | 44 | Other: Entry → Processing task chain with attachment copy |
| 9 | `dispatch_task_accept.py` | API | — | — | Yes | 74 | API: role-based task acceptance with assignment + ToDo creation |
| 10 | `dispatch_task_queue_backfill.py` | API | — | — | Yes | 52 | API: backfills team_queue_role/status for existing tasks |
| 11 | `doc15_task_auto_escalation.py` | Scheduler | — | — | Yes | 64 | Scheduler: escalates overdue tasks to directors (1 day urgent, 3 days normal) |
| 12 | `Task-after-insert-assign.py` | DocType Event | Task | After Insert | **DISABLED** | 18 | Auto-assigns from custom_assign_to field |
| 13 | `Task-dispatch-queue-integration.py` | DocType Event | Task | After Save | **DISABLED** | 45 | Maps task kinds to team roles |
| 14 | `Task-team-queue-notify.py` | DocType Event | Task | After Save | **DISABLED** | 71 | Team queue ToDo notifications |
| 15 | `Task-before-save-return-dropoff-photo.py` | DocType Event | Task | Before Save | **DISABLED** | 15 | Requires warehouse dropoff photo for return drop-off tasks |

#### Client Scripts (13 enabled, 1 disabled)

| # | Script | DocType | View | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|
| 1 | `Task-Accept Start.js` | Task | Form | Yes | 495 | Task acceptance UI, mobile rendering, task-kind-specific adjustments |
| 2 | `Task-Account Details UI Cleanup.js` | Task | Form | Yes | 273 | UI customization for Account Details tasks |
| 3 | `Task-Auto Reload.js` | Task | Form | Yes | 31 | Auto-reload on external changes |
| 4 | `Task-Dispatch Packing Usability.js` | Task | Form | Yes | 32 | DC linkage comments + Accept button |
| 5 | `Task-Inspect Returns Next Assign Visible.js` | Task | Form | Yes | 24 | Makes next_task_assign_to visible for Returns tasks |
| 6 | `Task-List Toggle Filters.js` | Task | List | Yes | 75 | My Tasks / Open Tasks / Completed toggles |
| 7 | `Task-Lock Completed.js` | Task | Form | Yes | 5 | Client-side completed lock |
| 8 | `Task-Lock Unaccepted.js` | Task | Form | Yes | 62 | Client-side lock until accepted |
| 9 | `Task-Other UI Cleanup.js` | Task | Form | Yes | 174 | UI for "Other" task kinds with photo rendering |
| 10 | `Task-Team Queue.js` | Task | Form | Yes | 64 | Quick Entry simplification for order entry |
| 11 | `Order entry - barcode scanning section - hide.js` | Task | Form | Yes | 310 | Hides barcode/photo/product fields by task_kind |
| 12 | `Task - Load Surgical Kit Template.js` | Task | Form | Yes | 33 | Loads Collection Set items (possible duplicate of DC template load) |
| 13 | `Global-Mobile Back Button List.js` | Task | List | Yes | 130 | Mobile back button + list toggle filters |
| 14 | `Task-Hide Sidebar Assignment.js` | Task | Form | **DISABLED** | 51 | Hides assignment UI elements |

#### Custom DocTypes (3)

- `Task Access Policy` — controls visibility per task_kind
- `Task Product Line` (child table) — product lines on tasks
- `Task Other Item` (child table) — items for "Other" tasks

#### Custom Fields on Task (62 fields)

See full list in Section 1 inventory. Key groups:
- Core workflow: task_kind, task_access_policy, completed_at, dispatch_case, customer, dispatch_group_id
- Acceptance/queue: custom_accepted_at, custom_accepted_by, custom_is_team_queue_task, custom_team_queue_role, custom_team_queue_status, custom_team_notified, custom_assigned_to
- Delivery/returns: delivery_status, pickup_status, warehouse_pickup_photo, warehouse_dropoff_photo, driver_handover_note, return_pickup_driver, scheduled_return_date
- Payments/debt: current_debt_amd, debt_threshold_amd, total_outstanding, available_advance_credit, new_payment_amount, payment_method_dc, payment_reference_dc, custom_total_amount_paid, payment_entry, open_invoices, payment_history
- Approval: approval_outcome, approval_note, purchase_order, sales_order, sales_invoice, surgery_case
- Product work: custom_product_lines, custom_product_work_section, custom_product_work_column, custom_task_add_item_code, custom_task_add_qty, custom_task_add_unit_price, custom_task_add_batch_no, custom_task_scan_barcode, custom_task_scan_qty, custom_task_scan_result, custom_task_product_summary, custom_task_product_warning
- Account details: custom_account_details_section, custom_account_details_subject, custom_account_photos, custom_account_details_entry_task, custom_delivery_photo, custom_next_task_assign_to, custom_barcode_section, custom_select_surgical_kit_template, custom_case_profit
- Other tasks: other_budget, other_supplier, other_items
- Legacy: dispatch_case_status

#### Property Setters on Task: 44

#### Reference Docs

- `10-task-system-foundations.md` — operational spec
- `10-task-system-foundations-implementation.md` — implementation guide
- `10.1-directors-task-dashboard.md` — TV wallboard spec
- `10.1-directors-task-dashboard-implementation.md` — TV wallboard implementation
- `03-roles-permissions-responsibilities.md` — role definitions
- `03-roles-permissions-responsibilities-implementation.md` — role implementation

#### Known Concerns (to investigate)

- 62 custom fields on Task vs ~25 documented in Docs 10/10a. The rest (product work area, account details, team queue, packing, "Other" task kind) appear to be post-documentation additions.
- 4 disabled scripts (auto-assign, queue integration, queue notify, return photo). Were they replaced by new logic or intentionally turned off? Return photo enforcement is documented as **required** in Doc 10.
- `Task - Load Surgical Kit Template.js` may duplicate functionality in `Dispatch Case-Template Auto Fill.js`.
- "Account Details" and "Other" task kinds have extensive code but no numbered doc. Are they documented anywhere?
- 44 property setters on Task — field visibility/label changes that may conflict with or override documentation expectations.

---

### Group 3: Payments, Debt, and Accounting
**Priority: HIGH — financial accuracy**

Covers debt collection automation, payment recording, payment distribution, advance payments, invoice generation, and tender agreements.

#### Server Scripts (4 enabled, 1 disabled)

| # | Script | Type | DocType | Event | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|---|
| 1 | `Scheduled-debt-collection.py` | Scheduler | — | — | Yes | 106 | Checks customer debt vs thresholds; creates/updates Debt Collection tasks |
| 2 | `Task-before-save-payment-recording.py` | DocType Event | Task | Before Save | Yes | 69 | Records payment on Debt Collection: creates Payment Entry, allocates to invoices, auto-completes if paid |
| 3 | `Task-after-save-debt-closure.py` | DocType Event | Task | After Save | Yes | 94 | Creates Debt Closure Approval task; calculates case profit on closure |
| 4 | `Task-after-save-advance-payment.py` | DocType Event | Task | After Save | Yes | 35 | Payment Received task: creates Payment Entry, updates DC prepaid amount |
| 5 | `Payment Entry-after-submit-distribute-payment.py` | DocType Event | Payment Entry | After Submit | **DISABLED** | 71 | Creates "Distribute Payment" task on payment submit |

#### Client Scripts (1 enabled)

| # | Script | DocType | View | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|
| 1 | `Dispatch Case-Price Visibility.js` | Dispatch Case | Form | Yes | 70 | Hides price/payment fields from non-financial roles |

#### Server Scripts (Tender/Invoice — also in this group) (2 enabled)

| # | Script | Type | DocType | Event | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|---|
| 6 | `Sales-Invoice-after-submit-tender-update.py` | DocType Event | Sales Invoice | After Submit | Yes | 24 | Updates Tender Agreement quantities when SI submitted |
| 7 | `Tender-Agreement-before-save.py` | DocType Event | Tender Agreement | Before Save | Yes | 21 | Calculates remaining qty; auto-sets status by date range |

#### Custom DocTypes (1)

- `Tender Agreement` + `Tender Agreement Item` (child table) — hospital pricing agreements

#### Custom Fields

- 4 on `Sales Invoice`: doctor_name, hospital, hospital_branch, surgery_case
- Payment-related fields on Task: see Group 2 custom fields list

#### Reference Docs

- `manual/debt-collection-and-payment.md` — payment recording guide
- `manual/supplier-prepayment-allocation.md` — advance payment guide
- `requirements.md` §6.6 — credit sales, debt thresholds, partial payments
- `DEPLOYMENT-SUMMARY-2026-06-17.md` — tender agreement deployment
- `docs-overview.md` — no numbered doc exists for Tender Agreements

#### Known Concerns (to investigate)

- `Payment Entry-after-submit-distribute-payment.py` is **DISABLED** but Doc 16 describes "Distribute Payment" task creation. How is this handled now? Is it in `Task-after-save-dispatch-flow.py` instead?
- Tender Agreement system has no numbered documentation (only deployment summary). Needs documentation gap assessment.
- `Task-after-save-debt-closure.py` creates "Debt Closure Approval" task and calculates profit. This task kind doesn't appear in the original Doc 10 task kind list. Is it documented?
- Invoice generation is inside `Task-after-save-dispatch-flow.py` (Group 1). The session analyzing Group 3 should cross-reference the invoice logic there.

---

### Group 4: Purchasing Flow
**Priority: MEDIUM**

Covers Purchase Order approval, Purchase Receipt validation, Purchase Invoice guards, Landed Cost Voucher prefill, reorder notifications, and Sales Order discount approval.

#### Server Scripts (7 enabled, 1 disabled)

| # | Script | Type | DocType | Event | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|---|
| 1 | `Purchase Order-before-save-clear-approval.py` | DocType Event | Purchase Order | Before Save | Yes | 37 | Clears director approval if PO is edited after approval |
| 2 | `Purchase Order-before-submit-director-approval.py` | DocType Event | Purchase Order | Before Submit | Yes | 11 | Blocks PO submit unless director_approval_status = "Approved" |
| 3 | `Purchase Receipt-before-submit-main-inmed-expiry.py` | DocType Event | Purchase Receipt | Before Submit | Yes | 21 | Enforces receiving into "Main - Inmed"; validates batch/expiry |
| 4 | `Purchase Invoice-before-submit-no-update-stock.py` | DocType Event | Purchase Invoice | Before Submit | Yes | 8 | Blocks PI from updating stock (must use PR) |
| 5 | `Task-purchase-approval-writeback.py` | DocType Event | Task | Before Save | Yes | 21 | Writes PO approval outcome back to Purchase Order |
| 6 | `Task-before-save-discount-approval-writeback.py` | DocType Event | Task | Before Save | Yes | 88 | Writes SO discount approval back; creates Pack task if approved |
| 7 | `doc15_norm_reorder_daily_notifications.py` | Scheduler | — | — | Yes | 43 | Daily reorder notifications for low-stock items |
| 8 | `Purchase Order-validate-one-supplier.py` | DocType Event | Purchase Order | Before Save | **DISABLED** | 24 | Validates one supplier per PO + item-supplier match |

#### Server Scripts (Sales Order — part of purchasing/discount flow) (2 enabled)

| # | Script | Type | DocType | Event | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|---|
| 9 | `Sales Order-before-save-discount-approval.py` | DocType Event | Sales Order | Before Save | Yes | 197 | Full discount approval workflow: detects discounts, creates approval tasks, enforces pricing reasons |
| 10 | `Sales Order-after-submit-pack-task.py` | DocType Event | Sales Order | After Submit | Yes | 65 | Creates Pack task when SO submitted (if no discount or approved) |

#### Client Scripts (1 enabled)

| # | Script | DocType | View | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|
| 1 | `LCV-import-duty-prefill.js` | Landed Cost Voucher | Form | Yes | 66 | Pre-fills import duty from item import_tax_rate |

#### Custom Fields

- 7 on `Purchase Order`: director_approval_status, director_approval_note, director_approval_task, director_approved_at, director_approved_by, purchase_reason, requested_by
- 10 on `Sales Order`: discount fields, hospital/doctor fields, prepaid fields
- 5 on `Item`: custom_1c_code, hs_code, import_tax_rate, pack_breaking_policy, reorder_change_reason
- 4 on `Purchase Receipt`: barcode override fields
- 3 on `Purchase Receipt Item`: custom_expiry_date, custom_production_date, custom_scanned_gs1_barcode

#### Reference Docs

- `07-suppliers-and-procurement-basic.md` + implementation
- `07-suppliers-and-procurement-basic-implementation.md`
- `08-reorder-and-ordering-by-supplier.md` + implementation
- `17-purchase-cost-and-valuation.md` + implementation
- `manual/purchase-walkthrough.md`
- `manual/low-stock-reorder-routine.md`

#### Known Concerns (to investigate)

- `Purchase Order-validate-one-supplier.py` is **DISABLED** but Doc 07a says one-supplier-per-PO is **required**. Why disabled?
- `Sales Order-before-save-discount-approval.py` (197 lines) and `Sales Order-after-submit-pack-task.py` — these operate on Sales Order but Dispatch Case has superseded Sales Order. Are these still needed? Do they conflict with Dispatch Case discount approval?
- `Task-before-save-discount-approval-writeback.py` writes back to Sales Order specifically. Does it also handle Dispatch Case discount approval, or is that a separate path?

---

### Group 5: Packing and Barcode Scanning
**Priority: MEDIUM**

Covers the packing scan system on Dispatch Cases, GS1 barcode parsing on Purchase Receipts, product work area on Tasks, and packing problem alerts.

#### Server Scripts (4 enabled)

| # | Script | Type | DocType | Event | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|---|
| 1 | `dispatch_case_packing_scan.py` | API | — | — | Yes | 139 | Parses barcodes (GS1, item codes), updates scanned qty, checks FEFO |
| 2 | `Dispatch Case-packing-problem-alerts.py` | DocType Event | Dispatch Case | After Save | Yes | 59 | Alerts managers via ToDo when packing problems detected |
| 3 | `task_mark_item_packed.py` | API | — | — | Yes | 36 | Updates packing status for single DC item |
| 4 | `task_mark_items_packed_batch.py` | API | — | — | Yes | 34 | Batch updates packing status for multiple DC items |

#### Client Scripts (5 enabled)

| # | Script | DocType | View | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|
| 1 | `Dispatch Case-Packing Scan.js` | Dispatch Case | Form | Yes | 178 | Barcode scanning UI with visual indicators and FEFO warnings |
| 2 | `Dispatch Case-Packing Problem Alerts.js` | Dispatch Case | Form | Yes | 17 | Dashboard alerts for packing problems |
| 3 | `GS1 Barcode Parser.js` | Purchase Receipt | Form | Yes | 460 | Full GS1 barcode parser: GTIN, LOT, expiry, production date |
| 4 | `Task-Packing Checkboxes.js` | Task | Form | Yes | 358 | Product work area with checkboxes for packing/returns/restocking |
| 5 | `Task-Product Work Area.js` | Task | Form | Yes | 331 | Product scanning, GS1 parsing, product work area refresh |

#### Custom Fields (packing-specific)

- 6 on `Dispatch Case`: packing_scan_barcode, packing_scan_qty, packing_scan_result, packing_problem_status, packing_problem_summary, packing_last_warning
- 8 on `Dispatch Case Item`: scanned_qty, packing_status, last_scan_at, last_scanned_barcode, last_scanned_by, problem_alert_sent, problem_reason, scan_note

#### Reference Docs

- `dispatch-packing-enhancements-plan.md` — packing scan design
- `ERPNext Barcode/IMPLEMENTATION_READY.md` — GS1 barcode readiness
- `ERPNext Barcode/GS1_FULL_WORKING_DRAFT.js` — approved GS1 parser
- `ERPNext Barcode/FIXES_DOCUMENTATION.md` — barcode fix history

#### Known Concerns (to investigate)

- The packing scan system and product work area have **no numbered documentation** (only a plan doc). Extensive code (139 + 178 + 358 + 331 = 1,006 lines of undocumented features).
- `GS1 Barcode Parser.js` (460 lines) — is this the same as `GS1_FULL_WORKING_DRAFT.js` or the older `LIVE_GS1_Client_Script_NOW.js`? Which version is actually deployed?
- `Task-Product Work Area.js` includes its own GS1 parsing. Is this duplicated from the GS1 Barcode Parser or independent?
- FEFO enforcement: `StockEntry-before-submit-fefo.py` is **DISABLED** (see Group 7). The packing scan does FEFO checks, but is there enforcement at stock entry submit time?

---

### Group 6: Legacy and Superseded Code
**Priority: MEDIUM — cleanup and risk assessment**

Code from before Doc 16 (Unified Dispatch Flow) that should be superseded but remains deployed and in some cases **enabled**.

#### Server Scripts (3 enabled, 2 effectively legacy)

| # | Script | Type | DocType | Event | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|---|
| 1 | `Surgery-Case-before-save.py` | DocType Event | Surgery Case | Before Save | **YES (ACTIVE!)** | 255 | Full Surgery Case workflow orchestrator — auto-loads template, creates stock entries and tasks for all state transitions |
| 2 | `Surgery-Set-Type-validate-readiness.py` | DocType Event | Collection Set | Before Save | Yes | 41 | Validates Collection Set readiness (duplicate of `Collection-Set-validate-readiness.py`) |
| 3 | `disable_all_item_batch_serial_for_now.py` | API | — | — | Yes | 22 | Bulk disables batch/serial/expiry on all items |
| 4 | `perm_disable_batch_expiry_dbset.py` | API | — | — | Yes | 23 | API to disable batch/expiry for specific items |

#### Client Scripts (2 enabled — legacy DocTypes)

| # | Script | DocType | View | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|
| 1 | `Surgery-Case-field-locking.js` | Surgery Case | Form | Yes | 16 | Locks qty fields by Surgery Case workflow state |
| 2 | `Task - Load Surgical Kit Template.js` | Task | Form | Yes | 33 | Loads Collection Set items (may duplicate DC template load) |

#### Disabled Scripts (likely replaced)

| # | Script | Type | Summary | Lines |
|---|---|---|---|---|
| 1 | `Task-after-insert-assign.py` | Server | Auto-assign from custom_assign_to | 18 |
| 2 | `Task-dispatch-queue-integration.py` | Server | Map task kinds to team roles | 45 |
| 3 | `Task-team-queue-notify.py` | Server | Team queue ToDo notifications | 71 |
| 4 | `Task-before-save-return-dropoff-photo.py` | Server | Return dropoff photo requirement | 15 |
| 5 | `Task-Hide Sidebar Assignment.js` | Client | Hide assignment UI | 51 |
| 6 | `Dispatch Case-Item Code Toggle.js` | Client | Filter toggle (mismatched DocType) | 35 |

#### Custom DocTypes (legacy, still deployed)

- `Surgery Case` — superseded by Dispatch Case
- `Surgery Case Item` (child table)
- `Surgery Case Serial Exception` (child table)
- `Surgical Kit Template` + `Surgical Kit Template Item` (child table) — likely renamed to Collection Set
- `Collection Set` + `Collection Set Item` (child table) — the current name

#### Reference Docs

- `09-standard-selling-flow.md` — **SUPERSEDED** by Doc 16
- `11-surgery-set-model.md` — **SUPERSEDED** by Doc 16
- `12-surgery-set-operational-workflow.md` — **SUPERSEDED** by Doc 16

#### Known Concerns (to investigate)

- `Surgery-Case-before-save.py` is **ENABLED** (255 lines!) and hooks Surgery Case Before Save. If anyone creates a Surgery Case, this full workflow orchestrator runs. Does the Dispatch Case flow ever create Surgery Cases? Is this actively used?
- Two readiness validators for Collection Set: `Collection-Set-validate-readiness.py` and `Surgery-Set-Type-validate-readiness.py`. Are these identical? Do they conflict (both fire on Before Save)?
- `disable_all_item_batch_serial_for_now.py` and `perm_disable_batch_expiry_dbset.py` — "for now" implies temporary. Docs 06/06a describe batch/expiry tracking as required. When will tracking be re-enabled?
- `Surgical Kit Template` DocType still exists alongside `Collection Set`. Are both in use? Which one does `custom_select_surgical_kit_template` on Task/DC link to?

---

### Group 7: Item and Stock Management
**Priority: MEDIUM**

Covers item tracking, FEFO enforcement, stock entry guards, reorder governance, Collection Set readiness, and customer governance.

#### Server Scripts (3 enabled, 3 disabled)

| # | Script | Type | DocType | Event | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|---|
| 1 | `Collection-Set-validate-readiness.py` | DocType Event | Collection Set | Before Save | Yes | 41 | Validates stock readiness vs template items |
| 2 | `Item-before-save-reorder-governance.py` | DocType Event | Item | Before Save | Yes | 30 | Requires reorder_change_reason when thresholds change |
| 3 | `Customer-before-save-governance.py` | DocType Event | Customer | Before Save | Yes | 17 | Locks client_code and is_provisional for non-privileged roles |
| 4 | `Item-before-save-reorder-change-reason.py` | DocType Event | Item | Before Save | **DISABLED** | 13 | Earlier version of reorder governance (replaced by #2) |
| 5 | `Stock Entry-before-save-no-client-wh.py` | DocType Event | Stock Entry | Before Save | **DISABLED** | 20 | Prevents standard sales stock entries from going to client warehouses |
| 6 | `StockEntry-before-submit-fefo.py` | DocType Event | Stock Entry | Before Submit | **DISABLED** | 48 | FEFO enforcement: warns on non-earliest-expiry batch selection |

#### Client Scripts (4 enabled)

| # | Script | DocType | View | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|
| 1 | `Dispatch Case Item-Auto Fill Item Name.js` | Dispatch Case Item | Form | Yes | 17 | Auto-fills item_name from Item master |
| 2 | `Dispatch Case-Item Code String Guard.js` | Dispatch Case | Form | Yes | 34 | Ensures item_code/item_name stored as strings |
| 3 | `Dispatch Case-Products Button.js` | Dispatch Case | Form | Yes | 235 | Item selection dialogs by category/search |
| 4 | `Task Product Line-Item Code String Guard.js` | Task | Form | Yes | 31 | String guard for Task Product Lines |

#### API Scripts (item operations)

| # | Script | Lines | Summary |
|---|---|---|---|
| 1 | `task_add_dispatch_product.py` | 34 | API: adds product to DC from task |
| 2 | `task_lookup_product_barcode.py` | 17 | API: item code lookup by barcode |
| 3 | `Dispatch Case-Template Auto Fill.js` | 40 | Loads items from Surgical Kit Template |

#### Custom Fields

- 5 on `Item`: custom_1c_code, hs_code, import_tax_rate, pack_breaking_policy, reorder_change_reason
- 1 on `Item Reorder`: buffer_percentage
- 6 on `Customer`: client_code, client_kind, debt_threshold_amd, doctor_name, hospital, is_provisional

#### Reference Docs

- `04-customers-and-doctors.md` + implementation
- `05-warehouses-and-stock-rules.md` + implementation
- `06-items-variants-uoms.md` + implementation
- `08-reorder-and-ordering-by-supplier.md` + implementation
- `manual/new-customer-onboarding.md`
- `manual/new-item-setup.md`
- `manual/collection-set-setup.md`

#### Known Concerns (to investigate)

- `StockEntry-before-submit-fefo.py` is **DISABLED** — FEFO is documented as a **required** feature (Doc 06, requirement 6.5.3). What replaced it?
- `Stock Entry-before-save-no-client-wh.py` is **DISABLED** — preventing standard sales from going to client warehouses is a documented invariant (Doc 05). Why off?
- `Dispatch Case-Template Auto Fill.js` links to `custom_select_surgical_kit_template` which is a Link to `Surgical Kit Template`, not `Collection Set`. Name mismatch with the current DocType.
- `buffer_percentage` on Item Reorder — not documented in any numbered doc.
- `custom_1c_code` on Item — references legacy 1C system, not documented.

---

### Group 8: Telegram and Notifications
**Priority: LOW**

Covers Telegram integration for task assignment and status notifications.

#### Server Scripts (2 enabled)

| # | Script | Type | DocType | Event | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|---|
| 1 | `Telegram Task Assignment Notification.py` | DocType Event | ToDo | After Insert | Yes | 145 | Sends Telegram message when task is assigned; maps users to chat IDs |
| 2 | `Telegram Task Status Update.py` | DocType Event | Task | After Save | Yes | 95 | Sends Telegram on status change (Working/Completed/Cancelled) |

#### Custom DocTypes (2)

- `Telegram Settings` (singleton) — bot token and configuration
- `Telegram Notification User` — user-to-chat-ID mapping

#### Notifications (from schema)

| Name | Event | DocType | Enabled |
|---|---|---|---|
| DATUREX Task Push | New | Task | **ENABLED** |
| Error Log | New | Error Log | No |
| Integration Request | Save | Integration Request | No |

#### Reference Docs

- `mobile-app-comparison.md` — evaluated DATUREX Connect
- `push-notifications-plan.md` — Firebase push plan

#### Known Concerns (to investigate)

- Telegram integration has **no numbered documentation**. Two active scripts (240 lines total) with hardcoded chat ID mappings.
- DATUREX Task Push notification is disabled — was Telegram chosen instead?
- How are chat IDs maintained? Is there a documented procedure for adding/removing users?
- Error handling: what happens if the Telegram API is unreachable?

---

### Group 9: UI/UX and Mobile
**Priority: LOW**

Covers mobile-specific CSS fixes, back button navigation, form layout adjustments, and workspace customization.

#### Client Scripts (5 enabled)

| # | Script | DocType | View | Enabled | Lines | Summary |
|---|---|---|---|---|---|---|
| 1 | `Global-Mobile Back Button.js` | Task | Form | Yes | 55 | Floating back button for mobile navigation |
| 2 | `Global-Mobile Back Button List.js` | Task | List | Yes | 130 | Mobile back button + task list toggle filters |
| 3 | `Task-Mobile Form Layout Fix.js` | Task | Form | Yes | 534 | Extensive mobile CSS for Task form layout |
| 4 | `Task-Header Long Subject Fix.js` | Task | Form | Yes | 45 | Subject field visibility in header |
| 5 | `Task-Delivery UI Fix.js` | Task | Form | Yes | 34 | CSS fixes for Delivery task action buttons |

#### Server Scripts (1 enabled)

| # | Script | Type | Lines | Summary |
|---|---|---|---|---|
| 1 | `task_list_filtered.py` | API | 99 | Returns filtered task list by role, kind, and status |

#### Reference Docs

- None. All mobile/UI fixes are **undocumented**.

#### Known Concerns (to investigate)

- `Task-Mobile Form Layout Fix.js` is the **largest client script** at 534 lines. All CSS hacks. How fragile is this across ERPNext version upgrades?
- `task_list_filtered.py` is an API that bypasses standard ERPNext list permissions. Does it correctly enforce Task Access Policy visibility?
- No documentation for any mobile UI decisions.

---

### Group 10: Reports, Workspaces, and Property Setters
**Priority: LOW — but large volume**

Covers 49 reports, 22 workspaces, 209 property setters, and 1 workspace client script.

#### Reports (49 — all Query Reports, all enabled)

**Stock reports (16):**
RPT - Stock - Balance Multi-Select, Batch and Expiry Balance, Client Locations (All), Delivery In-Transit (x2), Entries by Period, Expiry Classification, In-Transit Stuck (Age Check), Near Expiry (Main - Inmed), Near Expiry Value at Risk, Return Pickup In-Transit (x2), Returns (x2), Slow-Moving Products, Warehouse Movement

**Sales reports (8):**
RPT - Sales - Comparative Periods, History by Client, Sold Items Detail, Top Customers, Top Products, Documents and Payments, Pricing - Sales Orders With Manual Rate Edits, Price Override List

**Accounting/debt reports (8):**
RPT - Accounting - Debt Status Board, Income by Period, Clients Exceeding Debt Threshold, Risk - Debt Threshold Exceeded, Receivables - Unallocated Advances, Receivables - Unpaid Invoices (Aging), Unallocated Customer Advances, Ops - Prepaid Orders Awaiting Delivery (x2)

**Dispatch/operations reports (5):**
RPT - Dispatch Case Aging, Dispatch Cases - Aging (Open), Surgery Cases - Aging (Open), Items by Delivery Person, Ops - Driver Task Queue (Derived)

**Purchasing reports (4):**
RPT - Purchasing - Norm and Reorder, Supplier Performance, Item - Nomenclature and Prices, Item - Sort and Classify

**Data quality reports (3):**
RPT - Data Quality - Missing Doctor or Hospital, Negative Stock, Tracked Items Missing Identifiers

**Other (5):**
RPT - Collection Set Readiness, Low Stock by Supplier, Ops - Client Stock With No Open Cases, Returns - Refund Queue, Sales - Comparative Periods

#### Workspaces (3 custom operational)

- `Dispatch - Task Queues`
- `Management - KPI Dashboard`
- `Ops - Reporting Pack`

#### Client Scripts (1)

- `Workspace.js` — adds Task List shortcut to Home workspace

#### Property Setters (209 total)

Top DocTypes: Task (44), Dispatch Case (36), Sales Invoice (16), Dispatch Case Item (12), Delivery Note (12), Sales Order (12), Quotation (10), Purchase Receipt (9), Purchase Invoice (9), Purchase Order (9)

#### Reference Docs

- `13-reporting-pack.md` + implementation
- `15-reporting-requirements-review.md` + implementation

#### Known Concerns (to investigate)

- Some reports appear duplicated: "Dispatch Case Aging" vs "Dispatch Cases - Aging (Open)", "Delivery In-Transit" vs "Delivery In-Transit - Inmed", etc. Which are current?
- "Surgery Cases - Aging (Open)" — references superseded Surgery Case DocType. Still valid?
- 209 property setters — major surface area for field visibility/label/default changes not captured in docs. These can silently change what users see.

---

## 3. Session Instructions Template

Each parallel session should follow this protocol:

### Input

1. **This plan document** — for group boundaries, script lists, and known concerns
2. **The work files** — `deploy/test/work/server/*.py` and `deploy/test/work/client/*.js`
3. **The schema exports** — `deploy/test/schema/*.json`
4. **The reference docs** — specific docs listed per group

### Analysis Steps

1. **Read every script in the group line by line.** Do not skim. Understand the exact logic.
2. **Read the reference documentation sections** that describe the same functionality.
3. **For each script, answer:**
   - What does it actually do? (1-3 sentence summary)
   - What documentation describes this behavior? (specific doc + section)
   - Does the code match what the doc says? If not, what's different?
   - Are there any bugs, edge cases, or error handling gaps?
   - Is the script still needed, or is it superseded/dead code?
4. **For each doc section, answer:**
   - Is there deployed code implementing this? Which script(s)?
   - If no code exists, is the feature missing or handled differently?
5. **For disabled scripts, answer:**
   - Why was it likely disabled? (check for replacement logic elsewhere)
   - Should it be re-enabled, removed, or documented as intentionally off?
6. **For custom fields and property setters in the group:**
   - Are they documented?
   - Are they used by the scripts?
   - Are any orphaned (exist but nothing references them)?

### Output

Each session should produce a findings document with these sections:

```markdown
# Group N: [Name] — Audit Findings

## Summary
- Scripts analyzed: X server, Y client
- Custom fields analyzed: Z
- Documentation coverage: A% (N of M behaviors documented)
- Bugs found: N
- Doc gaps found: N
- Dead code found: N

## Findings Table
| ID | Type | Severity | Script/Field | Finding | Evidence | Recommendation |
|---|---|---|---|---|---|---|

Types: BUG, DOC-STALE, DOC-MISSING, DEAD-CODE, RISK, ENHANCEMENT
Severity: CRITICAL, HIGH, MEDIUM, LOW

## Detailed Findings
### F-001: [Title]
...

## Cross-Group Dependencies
Items that need to be checked in another group's session.
```

---

## 4. Cross-Group Dependency Map

Some scripts are shared or interact across groups. Each session should note these but NOT attempt to resolve them — resolution happens in a final consolidation pass.

| Script | Primary Group | Also relevant to |
|---|---|---|
| `Task-after-save-dispatch-flow.py` | Group 1 (Dispatch) | Group 3 (creates invoices, debt tasks) |
| `Task-before-save-dispatch-gates.py` | Group 1 (Dispatch) | Group 2 (task locking logic) |
| `Task-before-save-policy.py` | Group 2 (Tasks) | All groups (enforces access on all task kinds) |
| `Task-before-save-discount-approval-writeback.py` | Group 4 (Purchasing) | Group 1 (Dispatch Case discount flow) |
| `Sales Order-before-save-discount-approval.py` | Group 4 (Purchasing) | Group 6 (Legacy — operates on superseded Sales Order) |
| `Sales Order-after-submit-pack-task.py` | Group 4 (Purchasing) | Group 6 (Legacy — operates on superseded Sales Order) |
| `dispatch_case_packing_scan.py` | Group 5 (Packing) | Group 7 (item lookup, FEFO) |
| `Surgery-Case-before-save.py` | Group 6 (Legacy) | Group 1 (potential conflict with Dispatch Case flow) |

---

## 5. Recommended Execution Order

For parallel sessions, launch Groups 1-4 simultaneously (highest impact). Groups 5-7 can run in the next wave. Groups 8-10 can run last.

**Wave 1 (parallel):**
- Group 1: Dispatch Case Lifecycle
- Group 2: Task System and Gates
- Group 3: Payments, Debt, Accounting
- Group 4: Purchasing Flow

**Wave 2 (parallel):**
- Group 5: Packing and Barcode Scanning
- Group 6: Legacy and Superseded Code
- Group 7: Item and Stock Management

**Wave 3 (parallel):**
- Group 8: Telegram and Notifications
- Group 9: UI/UX and Mobile
- Group 10: Reports, Workspaces, Property Setters

**Wave 4 (sequential — after all above):**
- Consolidation: merge all findings, resolve cross-group dependencies, prioritize remediation
