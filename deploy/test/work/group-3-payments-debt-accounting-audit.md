# Group 3 — Payments, Debt, and Accounting: Production Audit

**Audit date:** 2026-07-20
**Auditor:** AI Assistant (Devin)
**Scope:** Static analysis of all deployed scripts, schema metadata, and documentation for the Payments, Debt, and Accounting functional group.
**Evidence source:** Extracted TestBed artifacts under `deploy/test/work/` representing production deployment per user confirmation. Schema from `deploy/test/schema/`.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Scope and Evidence Reviewed](#2-scope-and-evidence-reviewed)
3. [Script Inventory](#3-script-inventory)
4. [Script-by-Script Deep Analysis](#4-script-by-script-deep-analysis)
5. [Cross-Script Dependency Map](#5-cross-script-dependency-map)
6. [Documentation vs Production Comparison Matrix](#6-documentation-vs-production-comparison-matrix)
7. [Bug and Risk Register](#7-bug-and-risk-register)
8. [Reports, Custom Fields, and Supporting Artifacts](#8-reports-custom-fields-and-supporting-artifacts)
9. [Questions Requiring Live Smoke Testing](#9-questions-requiring-live-smoke-testing)
10. [Recommendations](#10-recommendations)

---

## 1. Executive Summary

Group 3 covers 10 server scripts after the local B-05 and tender-price-validation additions (8 original server scripts: 7 enabled and 1 disabled, plus 1 locally added cancellation script and 1 locally added tender validation script), 1 client script, 3 custom DocTypes after local B-03/B-05 additions, 16 reports, and associated custom fields and property setters. The functional scope is: debt collection automation, payment recording, payment distribution, advance/prepaid payments, invoice generation, tender agreement tracking, and financial field visibility.

### Critical Findings

| # | Finding | Severity | Confidence |
|---|---------|----------|------------|
| B-01 | Payment Entry created without invoice references — **LOCALLY CORRECTED** in extracted script: allocations are preserved and written as Sales Invoice references on the Payment Entry | **CRITICAL — fixed locally, pending deployment/testing** | High (code-proven) |
| B-02 | `Distribute Payment` script is DISABLED — **INTENTIONALLY OUT OF ACTIVE FLOW**; do not enable unless business flow is changed later | **Not active / deferred** | High (schema-proven, user decision) |
| B-03 | Advance payment `prepaid_amount` overwrites instead of accumulating on Dispatch Case — **LOCALLY CORRECTED** with Dispatch Case advance-payment child-table audit trail and recalculated prepaid total | **HIGH — fixed locally, pending deployment/testing** | High (code-proven) |
| B-04 | Tender Agreement `supplied_quantity` deducted from ALL matching tenders for same customer — **LOCALLY CORRECTED**: one active tender per hospital/item is enforced and over-supply stops invoice submit with review message | **HIGH — fixed locally, pending deployment/testing** | High (code-proven) |
| B-05 | Tender quantities were never reversed on invoice cancellation — **LOCALLY CORRECTED** with Sales Invoice tender fulfillment audit trail and On Cancel reversal script | **HIGH — fixed locally, pending deployment/testing** | High (code-proven) |
| B-06 | Tender `Closed` status was overridden by auto-status logic on save — **LOCALLY CORRECTED** so manual `Closed` status is preserved | **MEDIUM — fixed locally, pending deployment/testing** | High (code-proven) |
| B-07 | Debt Closure profit calculation only considered one invoice — **LOCALLY CORRECTED** to calculate total profit across all linked Open Invoices and write per-Dispatch Case profit | **MEDIUM — fixed locally, pending deployment/testing** | High (code-proven) |
| B-08 | Scheduler and dispatch flow both created/updated `Debt Collection` with different assignees/data — **LOCALLY CORRECTED** by separating scheduler alerts into `Debt Alert` | **MEDIUM — fixed locally, pending deployment/testing** | High (code-proven) |
| B-09 | Hardcoded user emails in debt closure approval — **LOCALLY CORRECTED** to use `Debt Closure Approval` Task Access Policy for assignment and completion permission | **LOW — fixed locally, pending deployment/testing** | High (code-proven) |
| B-10 | Financial field visibility is client-side only — no server-side enforcement; **deferred for business/security discussion** with proposed direction documented | **MEDIUM — discussion required / no code change yet** | High (code-proven) |
| B-11 | FIFO payment allocation sorted by invoice name, not invoice date — **LOCALLY CORRECTED** to sort by Sales Invoice posting date with invoice name tie-breaker | **LOW — fixed locally, pending deployment/testing** | High (code-proven) |
| B-12 | `paid_to` account hardcoded as "Cash - Inmed" regardless of payment method — **LOCALLY CORRECTED** with Cash/Bank Transfer/Card account mapping | **MEDIUM — fixed locally, pending deployment/testing** | High (code-proven) |
| B-13 | `frappe.db.commit()` inside loop in tender update script breaks transaction boundary — **LOCALLY CORRECTED** by removing manual commits and leaving tender updates inside Sales Invoice submit transaction | **MEDIUM — fixed locally, pending deployment/testing** | High (code-proven) |

### Documentation Gaps

| # | Gap | Confidence |
|---|-----|------------|
| D-01 | Debt Closure Approval task kind was not documented — **COMPLETED LOCALLY** in Doc 16 and linked `docs/manual/debt-closure-approval.md` | High |
| D-02 | Scheduled debt collection / GL-based threshold alert was not documented correctly — **COMPLETED LOCALLY** with Doc 16 Debt Alert section, linked `docs/manual/debt-alert.md`, and stale Debt Collection wording corrected to Debt Alert | High |
| D-03 | Tender Agreement system had no operational manual — **COMPLETED LOCALLY** with linked `docs/manual/tender-agreement-management.md` covering duplicate active tenders, over-supply blocking, cancellation reversal, Closed status preservation, and transaction safety | High |
| D-04 | Manual/docs mentioned Distribute Payment as active while B-02 is intentionally disabled — **COMPLETED LOCALLY** to consistently mark it disabled/deferred pending final keep/delete decision | High |
| D-05 | Payment Entry submit behavior was ambiguous in docs — **COMPLETED LOCALLY**: Debt Collection Payment Entries auto-submit, while advance Payment Entries intentionally remain draft for Accounting review/submission | Medium |
| D-06 | Cancellation manual said Payment Entry cancellation automatically restores Debt Collection/case state, but no script implements this — **COMPLETED LOCALLY** by documenting current manual-review behavior | High |

### Local Correction Progress

| Date | Items | Local change | Deployment status |
|---|---|---|---|
| 2026-08-28 | B-01, B-11 | `Task-before-save-payment-recording.py` now requires every payable Open Invoices row to have a linked Sales Invoice, allocates payments by Sales Invoice posting date, preserves allocation amounts before clearing `allocated_now`, and writes those allocations as Sales Invoice references on the generated Payment Entry. Doc 16 and the debt collection manual were updated to describe this exact behavior. | Local only — not deployed; requires later test/prod deployment and accounting verification |
| 2026-09-02 | B-02 | Marked `Distribute Payment` as intentionally disabled/out of active flow. No code change; do not enable unless the business flow is explicitly changed later. | Decision recorded only |
| 2026-09-03 | B-02/D-04 | Confirmed the unused `Payment Entry-after-submit-distribute-payment` Server Script is already disabled in local metadata/schema. Updated central/manual/implementation documentation so Distribute Payment is shown as disabled/deferred pending final keep/delete decision with the colleague. | Local documentation only; script remains disabled, not deleted |
| 2026-09-02 | B-03 | `Task-after-save-advance-payment.py` now appends each linked-case advance to a Dispatch Case `advance_payments` child table, recalculates `prepaid_amount` from all child rows, and keeps `prepaid_payment_entry` as latest-entry quick reference. Added TEST deployment script to create the child table/custom field and update the server script later. Doc 16 and the customer advance payment manual updated to describe the audit trail and accumulated total. | Local only — not deployed; requires later test/prod deployment and accounting verification |
| 2026-09-02 | B-04, B-13 | `Sales-Invoice-after-submit-tender-update.py` now updates at most one active tender row per hospital/item, stops submit when duplicate active tender rows exist, stops submit on over-supply for Accounting/Director review, and removes manual `frappe.db.commit()`. Added TEST deployment script and tender management manual. | Local only — not deployed; requires later test/prod deployment and tender smoke testing; over-supply policy should be reviewed with colleague |
| 2026-09-03 | Tender price/status | Added `Sales-Invoice-before-submit-tender-validation.py` to block tender invoice submit when the invoice rate does not match `Tender Agreement Item.tender_price`. Confirmed business rule: tenders are hospital-only, so matching remains `Sales Invoice.customer == Tender Agreement.hospital`. Updated `Tender-Agreement-before-save.py` so only `Closed` is preserved; `Draft` now auto-transitions by valid dates. | Local only — not deployed; requires later test/prod deployment and tender price/status smoke testing |
| 2026-09-03 | D-03 | Completed Tender Agreement documentation coverage with `docs/manual/tender-agreement-management.md` and index/overview links. Manual covers create/update workflow, duplicate active tender handling, over-supply blocking, cancellation reversal from tender fulfillment audit rows, Closed status preservation, date-based Draft/Active/Expired status, hospital-only matching, tender price enforcement, and transaction safety. | Local documentation only; tender behavior pending deployment/testing with B-04/B-05/B-06/B-13 and tender price/status validation |
| 2026-09-02 | B-05 | Tender fulfillment now writes a Sales Invoice `tender_fulfillments` child-table audit trail on submit. New `Sales-Invoice-on-cancel-tender-reversal.py` reverses exactly those recorded tender quantities on invoice cancellation. Added TEST deployment script for the child DocType/custom field and cancel script. | Local only — not deployed; requires later test/prod deployment and cancellation smoke testing |
| 2026-09-02 | B-06 | `Tender-Agreement-before-save.py` now preserves manually Closed tenders by skipping date-based auto-status when `status in ("Draft", "Closed")`. Tender manual updated to document that Closed stays Closed. | Local only — not deployed; requires later test/prod deployment and tender status smoke testing |
| 2026-09-03 | B-07 | `Task-after-save-debt-closure.py` now calculates Debt Closure Approval profit across all unique Sales Invoices in `open_invoices`, sums total profit into `custom_case_profit`, and writes each linked Dispatch Case's own profit. Added TEST deployment script and linked Debt Closure Approval manual. | Local only — not deployed; requires later test/prod deployment and multi-invoice debt-closure smoke testing |
| 2026-09-03 | B-08 | `Scheduled-debt-collection.py` now creates/updates Director `Debt Alert` tasks instead of Finance `Debt Collection` tasks. Dispatch flow remains responsible for `Debt Collection` with Open Invoices/payment recording. Added TEST deployment script to add the `Debt Alert` task kind/policy and updated Doc 16 plus debt alert/manual docs. | Local only — not deployed; requires later test/prod deployment and scheduler/debt-flow smoke testing |
| 2026-09-03 | D-02 | Completed documentation cleanup for scheduled GL-based debt threshold alerts: requirements, docs overview, migration notes, Doc 16, and debt alert manual now consistently describe Director `Debt Alert` tasks rather than Finance `Debt Collection` tasks for threshold alerts. | Local documentation only; behavior pending deployment/testing with B-08 |
| 2026-09-03 | B-09 | `Task-after-save-debt-closure.py` and `Task-before-save-dispatch-gates.py` now use the `Debt Closure Approval` Task Access Policy instead of hardcoded approver emails. Approval task assignment uses the policy default team user; completion permission uses the policy allowed roles. Added TEST deployment script and updated Debt Closure Approval documentation. | Local only — not deployed; requires later test/prod deployment and approval-policy smoke testing |
| 2026-09-03 | B-10 | Deferred by business decision for later discussion. Recommended direction documented: use Frappe field permissions/permlevels for server-side protection, keep client-side hiding only as UI convenience, include `profit`, and decide whether `Ops - Order Creating` should retain price/discount access. | No code change; discussion required before implementation |
| 2026-09-03 | B-12 | `Task-before-save-payment-recording.py` and `Task-after-save-advance-payment.py` now map `paid_to` by payment method: Cash → `Cash - Inmed`, Bank Transfer/Card → `Bank - Inmed`. Added TEST deployment script with account existence checks and updated payment manuals/Doc 16. | Local only — not deployed; requires later test/prod deployment and Payment Entry GL/account smoke testing |
| 2026-09-03 | D-05 | Clarified Payment Entry submission behavior in Doc 16 and audit: Debt Collection payments are auto-submitted by the script because they are invoice-allocated; customer advance Payment Entries are intentionally left as draft for Accounting review/submission. | Local documentation only; no code change |
| 2026-09-03 | D-06 | Corrected the cancellation manual to state current behavior: cancelling a client Payment Entry does not automatically restore Debt Collection outstanding balances and does not automatically re-open closed Dispatch Cases; Accounting/System Manager must manually review/correct task/case state before re-recording payment. | Local documentation only; no code change |
| 2026-09-03 | FIFO/lost-damaged/reports/SO prepaid | Clarified current local behavior: automatic FIFO only with no manual override; lost/damaged quantities are not auto-invoiced and remain manual-review/deferred; duplicate reports are classified official vs legacy/deferred; Sales Order prepaid fields are legacy/deferred and should not be deleted pending colleague review. | Local documentation/audit cleanup only; no deletion |

---

## 2. Scope and Evidence Reviewed

### Scripts Analyzed (8 server + 1 client)

| File | Full path |
|------|-----------|
| `Scheduled-debt-collection.py` | `deploy/test/work/server/Scheduled-debt-collection.py` |
| `Task-before-save-payment-recording.py` | `deploy/test/work/server/Task-before-save-payment-recording.py` |
| `Task-after-save-debt-closure.py` | `deploy/test/work/server/Task-after-save-debt-closure.py` |
| `Task-after-save-advance-payment.py` | `deploy/test/work/server/Task-after-save-advance-payment.py` |
| `Payment Entry-after-submit-distribute-payment.py` | `deploy/test/work/server/Payment Entry-after-submit-distribute-payment.py` |
| `Sales-Invoice-after-submit-tender-update.py` | `deploy/test/work/server/Sales-Invoice-after-submit-tender-update.py` |
| `Sales-Invoice-before-submit-tender-validation.py` | `deploy/test/work/server/Sales-Invoice-before-submit-tender-validation.py` |
| `Sales-Invoice-on-cancel-tender-reversal.py` | `deploy/test/work/server/Sales-Invoice-on-cancel-tender-reversal.py` |
| `Tender-Agreement-before-save.py` | `deploy/test/work/server/Tender-Agreement-before-save.py` |
| `Dispatch Case-Price Visibility.js` | `deploy/test/work/client/Dispatch Case-Price Visibility.js` |

### Cross-reference Script (Group 1, financial logic)

| File | Full path |
|------|-----------|
| `Task-after-save-dispatch-flow.py` | `deploy/test/work/server/Task-after-save-dispatch-flow.py` |

### Schema Files Inspected

- `deploy/test/schema/server-scripts.json` — script metadata verification
- `deploy/test/schema/custom-fields.json` — custom field definitions
- `deploy/test/schema/custom-doctypes.json` — Tender Agreement DocType
- `deploy/test/schema/reports.json` — report inventory
- `deploy/test/schema/notifications.json` — notification definitions
- `deploy/test/schema/property-setters.json` — field visibility/behavior overrides

### Documentation Files Reviewed

| Document | Path |
|----------|------|
| Requirements (authoritative) | `docs/requirements.md` §6.6, §6.6.1, §6.6.2, §7.4 |
| Unified Dispatch Flow | `docs/16-unified-dispatch-flow.md` §6.9–§6.12, §8, §10, §11 |
| Debt Collection Manual | `docs/manual/debt-collection-and-payment.md` |
| Customer Advance Payment Manual | `docs/manual/customer-advance-payment.md` |
| Tender Agreement Manual | `docs/manual/tender-agreement-management.md` |
| Supplier Prepayment Manual | `docs/manual/supplier-prepayment-allocation.md` |
| Cancellation Manual | `docs/manual/cancellation-and-corrections.md` |
| Daily Reporting Checks | `docs/manual/daily-reporting-checks.md` |
| Deployment Summary (June 17) | `docs/DEPLOYMENT-SUMMARY-2026-06-17.md` |
| Docs Overview | `docs/docs-overview.md` |
| Production Audit Plan | `deploy/test/work/production-audit-plan.md` |

---

## 3. Script Inventory

### Server Scripts

| # | Schema Name | Script Type | DocType | Event | Enabled | Lines | Purpose |
|---|-------------|-------------|---------|-------|---------|-------|---------|
| S1 | Scheduled-debt-collection | Scheduler Event | — | — | **Yes** | 111 | GL-based debt threshold check; creates/updates Director Debt Alert tasks |
| S2 | Task-before-save-payment-recording | DocType Event | Task | Before Save | **Yes** | 83 | Records payment on Debt Collection task; maps paid_to by payment method; requires linked invoices for payable rows; creates Payment Entry with Sales Invoice references; FIFO allocation by invoice posting date |
| S3 | Task-after-save-debt-closure | DocType Event | Task | After Save | **Yes** | 117 | Creates Debt Closure Approval task using policy-controlled assignment; calculates multi-invoice profit on closure approval |
| S4 | Task-after-save-advance-payment | DocType Event | Task | After Save | **Yes** | 53 | Creates advance Payment Entry on Payment Received task completion with paid_to mapped by payment method; records linked-case advances in child-table audit trail and recalculates prepaid total |
| S5 | Payment Entry-after-submit-distribute-payment | DocType Event | Payment Entry | After Submit | **No** | 83 | Would create Distribute Payment tasks (DISABLED) |
| S6 | Sales-Invoice-after-submit-tender-update | DocType Event | Sales Invoice | After Submit | **Yes** | 70 | Updates Tender Agreement supplied/remaining quantities and writes tender fulfillment audit rows |
| S9 | Sales-Invoice-before-submit-tender-validation | DocType Event | Sales Invoice | Before Submit | **Yes** | 56 | Validates hospital-only active tender matching, duplicate tenders, over-supply, and exact tender price before invoice submit |
| S7 | Tender-Agreement-before-save | DocType Event | Tender Agreement | Before Save | **Yes** | 22 | Recalculates remaining qty; auto-sets Draft/Active/Expired by date while preserving manual Closed status |
| S8 | Sales-Invoice-on-cancel-tender-reversal | DocType Event | Sales Invoice | On Cancel | **Yes** | 33 | Reverses tender supplied quantities from Sales Invoice tender fulfillment audit rows |

### Cross-Reference Server Script (Group 1)

| # | Schema Name | Script Type | DocType | Event | Enabled | Lines | Financial Functions |
|---|-------------|-------------|---------|-------|---------|-------|---------------------|
| X1 | Task-after-save-dispatch-flow | DocType Event | Task | After Save | **Yes** | 289 | `create_invoice()`, `create_or_update_debt_task()`, outstanding calculation, prepaid deduction |

### Client Scripts

| # | Schema Name | DocType | View | Enabled | Lines | Purpose |
|---|-------------|---------|------|---------|-------|---------|
| C1 | Dispatch Case-Price Visibility | Dispatch Case | Form | **Yes** | 72 | Hides financial fields from non-financial roles |

### Metadata Verification

Original deployed script names, types, events, and disabled states were verified against `deploy/test/schema/server-scripts.json`. Locally added/fixed scripts are tracked in `deploy/test/work/server/` and matching deployment helpers; they will appear in schema only after deployment/export.

---

## 4. Script-by-Script Deep Analysis

### S1 — Scheduled-debt-collection.py

**Schema name:** `Scheduled-debt-collection`
**Type:** Scheduler Event | **Enabled:** Yes | **Lines:** 111

#### Behavior Summary

1. Resolves the default company from Global Defaults (fallback: first Company record).
2. Reads the `Debt Alert` Task Access Policy and uses its `default_team_user` as the assignment target.
3. Iterates all non-disabled Customers that have `debt_threshold_amd > 0`.
4. Calculates **net receivable** per customer via direct GL Entry query: `SUM(debit - credit)` where `is_cancelled = 0`, filtered by company and party.
5. If `debt > threshold`:
   - Looks for an existing non-Completed Debt Alert task for that customer.
   - If found: updates it with current debt and threshold values.
   - If not found: creates a new task with `task_kind = "Debt Alert"`, `task_access_policy = "Debt Alert"`, assigned to the policy default team user.
6. Sets `current_debt_amd`, `debt_threshold_amd`, and a text `description` on the alert task.

#### Fields Read

| Field | DocType | Purpose |
|-------|---------|---------|
| `default_company` | Global Defaults | Company resolution |
| `default_team_user` | Task Access Policy | Debt Alert assignment target |
| `disabled`, `customer_name`, `debt_threshold_amd` | Customer | Threshold check |
| `debit`, `credit`, `is_cancelled`, `party`, `party_type` | GL Entry | Net receivable calculation |
| `task_kind`, `customer`, `status` | Task | Duplicate check |

#### Fields Written

| Field | DocType | Purpose |
|-------|---------|---------|
| `subject`, `status`, `task_kind`, `task_access_policy`, `customer` | Task | New task creation |
| `current_debt_amd`, `debt_threshold_amd`, `description` | Task | Debt tracking |
| `_assign` | Task | Debt Alert policy default team assignment |
| `status`, `allocated_to`, `reference_type`, `reference_name`, `description`, `assigned_by` | ToDo | Assignment tracking |

#### Trigger Conditions

Runs on scheduler (frequency not visible in extracted script — set in ERPNext scheduler configuration, typically hourly or daily).

#### Idempotency

**Good.** If an existing non-Completed Debt Alert task exists, it updates rather than creating a duplicate. The update only writes current_debt_amd, debt_threshold_amd, and description — no destructive side effects. It no longer touches Finance Debt Collection tasks.

#### Error Handling

**Minimal.** No try/except blocks. If GL query fails or a customer record is corrupt, the entire scheduler run would fail silently (ERPNext logs the error but the scheduler continues for other events).

#### Security / Permissions

Uses `ignore_permissions=True` for task creation and ToDo management. Appropriate for a system-level scheduler.

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S1-F01 | **Debt calculation uses GL Entry (net receivable)**. This correctly includes the effect of all payment entries, credit notes, and journal entries. Matches requirements §6.6.2 recommendation for net receivable. | **Matches requirements** | High |
| S1-F02 | **LOCALLY CORRECTED:** Assignment now comes from the `Debt Alert` Task Access Policy `default_team_user` instead of the first director alphabetically. | B-08 fixed locally, pending deployment/testing | High |
| S1-F03 | **LOCALLY CORRECTED:** Scheduler no longer creates incomplete Finance Debt Collection tasks. It creates Director Debt Alert tasks, which intentionally do not contain `open_invoices`. | B-08 fixed locally, pending deployment/testing | High |
| S1-F04 | **LOCALLY CORRECTED:** Scheduler and dispatch flow now use separate task kinds: `Debt Alert` for Director threshold visibility and `Debt Collection` for Finance payment workflow. | B-08 fixed locally, pending deployment/testing | High |
| S1-F05 | **Skips customers with threshold <= 0.** Safe. All 193 customers verified to have thresholds set per deployment summary. | Correct | High |
| S1-F06 | **LOCALLY CORRECTED:** Scheduler subject now uses `Debt Alert - {customer_name}`, clearly separate from dispatch-flow `Debt Collection: {customer_name}`. | B-08 fixed locally, pending deployment/testing | High |
| S1-F07 | **Does not set `status = "Open"` on existing tasks.** If a task was in "Working" or another intermediate status, the scheduler updates its debt fields but leaves its status unchanged. Correct behavior — doesn't disrupt ongoing work. | Correct | High |

---

### S2 — Task-before-save-payment-recording.py

**Schema name:** `Task-before-save-payment-recording`
**Type:** DocType Event — Before Save | **Enabled:** Yes | **Lines:** 83

#### Behavior Summary

1. Only acts on `task_kind == "Debt Collection"`.
2. Only acts when `new_payment_amount > 0`.
3. **Idempotency guard:** Compares current `new_payment_amount` with previous save value. Only fires on change.
4. Takes payment amount, method (default "Cash"), reference.
5. Validates that every payable `open_invoices` row has a linked Sales Invoice before allocation can proceed.
6. **FIFO allocation:** Sorts `open_invoices` by the linked Sales Invoice posting date, with invoice name as a tie-breaker. Allocates payment to rows in order until amount is exhausted.
7. Stores the exact Sales Invoice allocation amounts before clearing the temporary `allocated_now` field.
8. Updates each row: increments `paid_amount`, decrements `outstanding_amount`, **zeroes `allocated_now`**.
9. Recalculates `total_outstanding`.
10. Appends to `payment_history` child table.
11. Creates a Payment Entry (type: Receive, party: Customer) with `paid_to` mapped by payment method: Cash → `Cash - Inmed`, Bank Transfer/Card → `Bank - Inmed`.
12. Adds Sales Invoice reference rows to the PE using the preserved allocation amounts.
13. Submits the PE immediately.
14. Links PE name to the payment_history row.
15. Resets input fields.
16. If `total_outstanding <= 0`, auto-sets `doc.status = "Completed"`.

#### **BUG B-01: Payment Entry created WITHOUT invoice references** (CRITICAL — LOCALLY CORRECTED)

**Original issue:** the script had a logical ordering error: it zeroed `allocated_now` after applying the payment to the Debt Collection task rows, then later tried to use `allocated_now` to build Payment Entry invoice references. Because `allocated_now` was already 0, the Payment Entry was created without Sales Invoice reference rows and ERPNext treated the receipt as unallocated customer credit.

**Impact before local correction:**
- ERPNext's GL entries showed the payment as unallocated — Sales Invoices could remain "Unpaid" in the accounting ledger even though the Debt Collection task showed them as paid.
- Accounts Receivable reports could show invoices as outstanding after payment.
- The task's internal tracking (`open_invoices`) could diverge from ERPNext's accounting allocation.
- Financial reports depending on invoice allocation could become unreliable.

**Local correction applied:** `Task-before-save-payment-recording.py` now blocks payment recording if any payable Open Invoices row has no linked Sales Invoice, stores the exact Sales Invoice allocation amounts in an `allocations` list before clearing `allocated_now`, then uses that preserved list to append Payment Entry `references` rows. The same local correction also addresses B-11 by sorting FIFO allocation by Sales Invoice posting date with invoice name as a tie-breaker.

**Status:** Fixed in local extracted script and current documentation. Pending deployment and live/test accounting verification.

#### Other Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S2-F01 | **B-01** (above) — PE previously had no invoice references; locally corrected to require linked Sales Invoices for payable rows, preserve allocations, and append Sales Invoice references to the Payment Entry. | **FIXED LOCALLY — pending deployment/testing** | High |
| S2-F02 | **B-11** — FIFO previously sorted by `sales_invoice` name. Locally corrected to sort by linked Sales Invoice posting date, with invoice name as a tie-breaker. | **FIXED LOCALLY — pending deployment/testing** | High |
| S2-F03 | **PE auto-submitted** for Debt Collection payments. This is now documented as intentional because these Payment Entries are invoice-allocated from the Debt Collection Open Invoices table. | Matches clarified Doc 16 behavior | High |
| S2-F04 | **LOCALLY CORRECTED:** `paid_to` now maps by payment method: Cash → `Cash - Inmed`, Bank Transfer/Card → `Bank - Inmed`. | **B-12 fixed locally, pending deployment/testing** | High |
| S2-F05 | **Company hardcoded as `"InMED"`.** Correct for this single-company deployment, but not portable. | Accepted deviation | High |
| S2-F06 | **No Distribute Payment task created after payment.** This matches the current decision: S5 remains disabled and Distribute Payment is out of active flow. | **B-02 — intentionally disabled/deferred** | High |
| S2-F07 | **Auto-completion when outstanding reaches 0.** Matches Doc 16 §6.10 ("Task auto-completes"). Correct. | Matches documentation | High |

---

### S3 — Task-after-save-debt-closure.py

**Schema name:** `Task-after-save-debt-closure`
**Type:** DocType Event — After Save | **Enabled:** Yes | **Lines:** 117

#### Behavior Summary — Part 1: Debt Collection → Debt Closure Approval

When a **Debt Collection** task transitions to `Completed`:

1. Sums `paid_amount` across all `open_invoices` rows.
2. Collects invoice names and payment entry names.
3. Builds a text description with customer, total paid, invoices, PEs, and payment history.
4. Creates a new Task with `task_kind = "Debt Closure Approval"`.
5. Copies `payment_history` and `open_invoices` child table rows to the new task.
6. Assigns to the default team user from the `Debt Closure Approval` Task Access Policy.

#### Behavior Summary — Part 2: Debt Closure Approval → Profit Calculation

When a **Debt Closure Approval** task transitions to `Completed`:

1. **Permission check:** Administrator or a user with a role allowed by the `Debt Closure Approval` Task Access Policy can complete.
2. Reads all unique linked Sales Invoices from the task's `open_invoices` child table, falling back to `doc.sales_invoice` only if the table has no invoice links.
3. For each item in each invoice, calculates `profit = (selling_rate × qty) - (buying_rate × qty)`.
4. Buying rate sourced from Item Price with `price_list = "Standard Buying"`.
5. Sets `custom_case_profit` on the task to the total profit across all included invoices.
6. Sets each linked Dispatch Case's `profit` to that Dispatch Case's own invoice profit.
7. Warns if any items have missing Standard Buying prices.

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S3-F01 | **LOCALLY CORRECTED:** Debt Closure Approval assignment and completion permission now read from the `Debt Closure Approval` Task Access Policy instead of hardcoded email addresses. | **B-09 fixed locally, pending deployment/testing** | High |
| S3-F02 | **LOCALLY CORRECTED:** Replaced stale named-user error text with a policy-based error message. | **B-09 fixed locally, pending deployment/testing** | High |
| S3-F03 | **LOCALLY CORRECTED:** Profit now uses all unique Sales Invoices in `open_invoices`, with a fallback to `doc.sales_invoice` only when no invoice rows exist. | **B-07 fixed locally, pending deployment/testing** | High |
| S3-F04 | **Profit = selling − Standard Buying price.** Does not account for landed costs, actual purchase prices, exchange rate variances, or item-specific cost. This is a rough margin estimate, not accounting profit. | Accepted limitation — documented deployment summary lists it as requiring Standard Buying prices | Medium |
| S3-F05 | **LOCALLY CORRECTED:** Dispatch Case profit is written per linked Dispatch Case from that Dispatch Case's own invoice profit, instead of only the first/singular case. | **B-07 fixed locally, pending deployment/testing** | High |
| S3-F06 | **LOCALLY CORRECTED:** Debt Closure Approval is now documented in Doc 16 and `docs/manual/debt-closure-approval.md`. | **D-01 locally covered** | High |
| S3-F07 | **LOCALLY CORRECTED:** Debt Closure Approval assignment now goes to the Task Access Policy default team user instead of the first two hardcoded users. | **B-09 fixed locally, pending deployment/testing** | High |

---

### S4 — Task-after-save-advance-payment.py

**Schema name:** `Task-after-save-advance-payment`
**Type:** DocType Event — After Save | **Enabled:** Yes | **Lines:** 53

#### Behavior Summary

1. Only acts on `task_kind == "Payment Received"` transitioning to `Completed`.
2. Only acts when `new_payment_amount > 0`.
3. Creates Payment Entry (Receive, Customer, no invoice references — correct for an advance) with `paid_to` mapped by payment method: Cash → `Cash - Inmed`, Bank Transfer/Card → `Bank - Inmed`.
4. **Inserts but does NOT submit** the PE.
5. If `dispatch_case` is linked, appends the advance to the Dispatch Case `advance_payments` child table, recalculates `prepaid_amount` from all advance rows, and stores the latest PE in `prepaid_payment_entry` for quick reference.
6. If an existing non-completed Debt Collection task exists for this customer, adds the payment amount to `available_advance_credit`.

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S4-F01 | **Advance PE intentionally not submitted** — only `pe.insert()`, no `pe.submit()`. Advance Payment Entries have no invoice references and are left as draft for Accounting review/submission. | Matches clarified Doc 16/manual behavior | High |
| S4-F02 | **LOCALLY CORRECTED:** `prepaid_amount` is recalculated from all Dispatch Case `advance_payments` child rows, so multiple partial advances accumulate correctly. | **B-03 fixed locally, pending deployment/testing** | High |
| S4-F03 | **LOCALLY CORRECTED:** every linked-case advance now has its own child-row audit trail with amount, method, reference, Payment Entry, and source task. `prepaid_payment_entry` remains latest-entry quick reference only. | **B-03 fixed locally, pending deployment/testing** | High |
| S4-F04 | **`available_advance_credit` correctly accumulates** (line 47-48: `current_credit + doc.new_payment_amount`). Good. But this field is on the Debt Collection task. If no Debt Collection task exists yet, the credit is tracked on the dispatch case only when a case is linked; unlinked advances remain only on the draft PE. | Partial implementation | High |
| S4-F05 | **LOCALLY CORRECTED:** advance Payment Entry `paid_to` now uses the same method mapping as Debt Collection payments: Cash → `Cash - Inmed`, Bank Transfer/Card → `Bank - Inmed`. | **B-12 fixed locally, pending deployment/testing** | High |
| S4-F06 | **No guard against multiple completions.** The `is_completing` check prevents re-firing on subsequent saves of an already-Completed task. Correct. | Correct | High |

---

### S5 — Payment Entry-after-submit-distribute-payment.py

**Schema name:** `Payment Entry-after-submit-distribute-payment`
**Type:** DocType Event — After Submit | **Enabled:** **No (DISABLED)** | **Lines:** 83

#### Behavior Summary (if enabled)

1. Only acts on `party_type == "Customer"` and `payment_type == "Receive"`.
2. Finds directors with `Ops - Directors` role (same pattern as S1).
3. Checks for existing non-completed Distribute Payment tasks for this PE.
4. If none: creates a new task with `task_kind = "Distribute Payment"`, assigns to first director.

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S5-F01 | **DISABLED in production.** No Distribute Payment tasks are created. This is now accepted as intentional: Distribute Payment is out of the active flow. | **B-02 — intentionally disabled/deferred** | High |
| S5-F02 | **If ever re-enabled, assigns to Directors.** Doc 16 §6.11 says "Default assignee: Finance Team." This remains only a latent issue if the feature is reintroduced. | Deferred / latent | High |
| S5-F03 | **LOCALLY CORRECTED:** central flow, implementation docs, reporting docs, and finance manuals now describe Distribute Payment as disabled/deferred, not active, and record that the final keep/delete decision is pending colleague review. | **D-04 locally covered** | High |
| S5-F04 | **Requirements §6.6.2** states: "the internal Distribute Payment control step is created per payment receipt." Current business decision is not to include this step in the active flow. | Deferred requirement / not active | High |

---

### S6 — Sales-Invoice-after-submit-tender-update.py

**Schema name:** `Sales-Invoice-after-submit-tender-update`
**Type:** DocType Event — After Submit | **Enabled:** Yes | **Lines:** 70

#### Behavior Summary

1. Only acts when `doc.docstatus == 1` (submitted).
2. Gets active Tender Agreements where `hospital == doc.customer`, ordered by `valid_to`, `valid_from`, then name.
3. For each invoice item, finds active tender rows with the same `item_code`.
4. If zero matches: no tender update for that item.
5. If one match: checks remaining quantity, increments `supplied_quantity`, recalculates `remaining_quantity`, saves the tender, and records a Sales Invoice `tender_fulfillments` audit row.
6. If more than one match: stops invoice submit because only one active tender per hospital/item is allowed.
7. If invoice quantity exceeds remaining tender quantity: stops invoice submit with an Accounting/Director review message.
8. Does not call `frappe.db.commit()`; tender updates stay inside the Sales Invoice submit transaction.
9. The audit rows allow the cancellation script to reverse exactly the same tender rows later.

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S6-F01 | **LOCALLY CORRECTED:** Multiple-tender double-counting is prevented. If a hospital/item appears in more than one active tender, Sales Invoice submit stops with a clear duplicate-tender message. | **B-04 fixed locally, pending deployment/testing** | High |
| S6-F02 | **LOCALLY CORRECTED:** Sales Invoice submit now writes `tender_fulfillments` audit rows so the On Cancel script can reverse the exact tender quantities. | **B-05 fixed locally, pending deployment/testing** | High |
| S6-F03 | **LOCALLY CORRECTED:** over-supply now stops Sales Invoice submit with a review message when invoice quantity exceeds remaining tender quantity. User decision: this should act as a blocking warning so Accounting/Directors can decide what to change. | **Control added; review with colleague** | High |
| S6-F04 | **LOCALLY CORRECTED:** manual `frappe.db.commit()` was removed. Tender updates now stay inside the Sales Invoice submit transaction. | **B-13 fixed locally, pending deployment/testing** | High |
| S6-F05 | **Hospital-only tender matching confirmed.** Tender Agreements are only for hospitals, so invoice tender matching intentionally uses `Sales Invoice.customer == Tender Agreement.hospital`. Doctor/client-only Customer records are not tender customers. | Business rule confirmed | High |
| S6-F06 | **LOCALLY CORRECTED:** `tender_price` is now enforced by `Sales-Invoice-before-submit-tender-validation.py` before Sales Invoice submit. If an active tender row matches the hospital/item, the invoice row rate must equal the tender price. | Tender price validation added locally, pending deployment/testing | High |

---

### S9 — Sales-Invoice-before-submit-tender-validation.py

**Schema name:** `Sales-Invoice-before-submit-tender-validation`
**Type:** DocType Event — Before Submit | **Enabled:** Yes | **Lines:** 56

#### Behavior Summary

1. Uses `Sales Invoice.customer` as the tender hospital because tenders are hospital-only by business rule.
2. Loads active Tender Agreements for that hospital.
3. For each invoice item, finds matching tender rows by `item_code`.
4. Stops submit if more than one active tender row matches the same hospital/item.
5. Stops submit if invoice quantity exceeds remaining tender quantity.
6. Stops submit if invoice row rate differs from the matching tender row's `tender_price`.
7. Does not update tender quantities; the After Submit tender update script remains responsible for transactional fulfillment updates and audit rows.

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S9-F01 | **LOCALLY ADDED:** tender price is enforced before submit, so tender-covered invoice rows cannot bypass `Tender Agreement Item.tender_price`. | Tender price gap fixed locally, pending deployment/testing | High |
| S9-F02 | **Hospital-only matching confirmed:** matching by `doc.customer` is correct because tenders are only for hospital Customer records. | Business rule confirmed | High |
| S9-F03 | **Before Submit validation is safer than After Submit-only validation.** Price, duplicate, and over-supply errors stop before fulfillment quantities are updated. | Correct design | High |

---

### S8 — Sales-Invoice-on-cancel-tender-reversal.py

**Schema name:** `Sales-Invoice-on-cancel-tender-reversal`
**Type:** DocType Event — On Cancel | **Enabled:** Yes | **Lines:** 33

#### Behavior Summary

1. Only acts when Sales Invoice is cancelled (`doc.docstatus == 2`).
2. Reads the invoice's `tender_fulfillments` child table.
3. For each recorded fulfillment row, opens the exact Tender Agreement saved at invoice submit time.
4. Finds the recorded item row and subtracts the recorded quantity from `supplied_quantity`.
5. Recalculates `remaining_quantity` and saves the Tender Agreement.
6. Throws an error if the recorded tender/item can no longer be found, avoiding silent incorrect reversal.

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S8-F01 | **LOCALLY ADDED:** B-05 cancellation reversal is implemented from Sales Invoice tender fulfillment audit rows, so reversal does not depend on the tender still being Active. | **B-05 fixed locally, pending deployment/testing** | High |
| S8-F02 | Uses `max(supplied - qty, 0)` to avoid negative supplied quantity if data was manually changed before cancellation. This is conservative; smoke testing should confirm whether a hard error is preferred if supplied quantity is already lower than the reversal quantity. | Safety behavior — test/confirm | Medium |

---

### S7 — Tender-Agreement-before-save.py

**Schema name:** `Tender-Agreement-before-save`
**Type:** DocType Event — Before Save | **Enabled:** Yes | **Lines:** 22

#### Behavior Summary

1. Recalculates `remaining_quantity = won_quantity - supplied_quantity` for each item row.
2. Auto-sets status based on date range:
   - If status is already "Closed": skip auto-status to preserve manual closure.
   - If `today < valid_from`: status → "Draft".
   - If `valid_from <= today <= valid_to`: status → "Active".
   - If `today > valid_to`: status → "Expired".

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S7-F01 | **LOCALLY CORRECTED:** manually Closed tenders are no longer reopened by date-based auto-status logic; S7 skips status auto-update when `doc.status in ("Draft", "Closed")`. | **B-06 fixed locally, pending deployment/testing** | High |
| S7-F02 | **LOCALLY CORRECTED:** only manual `Closed` status is preserved. `Draft` now participates in date-based status logic, so a future-dated tender can auto-transition to `Active` when the valid date range begins. | Draft status behavior fixed locally, pending deployment/testing | High |
| S7-F03 | **Remaining quantity recalculation is correct** and runs on every save regardless of status. | Correct | High |

---

### X1 — Task-after-save-dispatch-flow.py (Cross-Reference)

This script belongs to Group 1 but contains critical financial logic.

#### Financial Functions

**`create_invoice(c)` (lines 122–141):**
- Creates draft Sales Invoice from Dispatch Case items.
- Uses `used_qty` if populated, otherwise `dispatched_qty`.
- Rate = `unit_price * (1 - discount_pct / 100)`.
- Does NOT include `lost_damaged_qty` in billing. Doc 16 §9A explicitly notes: "this policy is not yet implemented in the deployed script."
- Does NOT submit the invoice — leaves as draft.
- Links invoice to Dispatch Case.

**`create_or_update_debt_task(c, outstanding, inv_name)` (lines 143–173):**
- Assigns to `FINANCE_TEAM` (`finance.team@example.com`).
- One task per customer (checks existing non-completed).
- Populates `open_invoices` child table with per-DC invoice data.
- Recalculates `total_outstanding`.

**Invoice Preparation Completed handler (lines 267–278):**
- `outstanding = grand_total - prepaid_amount`
- If outstanding <= 0: case → Closed.
- If outstanding > 0: case → Payment Pending, creates/updates debt task.

#### Cross-Reference Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| X1-F01 | **LOCALLY CORRECTED:** Scheduler no longer uses the same task kind as dispatch-flow Finance debt tasks. `Debt Alert` and `Debt Collection` are separate, so a Director alert can no longer capture a Finance payment task. | **B-08 fixed locally, pending deployment/testing** | High |
| X1-F02 | **LOCALLY CORRECTED:** Scheduler subject now uses `Debt Alert - {name}` while dispatch flow keeps `Debt Collection: {name}`. | **B-08 fixed locally, pending deployment/testing** | High |
| X1-F03 | **Outstanding = `grand_total - prepaid_amount`.** This is a DC-local calculation for Finance payment workflow. The scheduled GL-based debt check now writes separate `Debt Alert` tasks for Director threshold visibility. | Design choice — documented separation | High |
| X1-F04 | **Invoice left as draft.** The Accounting team must submit it via the Invoice Preparation task. This is correct per Doc 16 §6.9. | Matches documentation | High |
| X1-F05 | **`lost_damaged_qty` not billed.** Doc 16 §9A confirms this is a pending implementation step. | Known gap — documented | High |

---

### C1 — Dispatch Case-Price Visibility.js

**Schema name:** `Dispatch Case-Price Visibility`
**Type:** Client Script — Form | **Enabled:** Yes | **Lines:** 72

#### Behavior Summary

On Dispatch Case form refresh, checks if user has any of: `Ops - Accounting`, `Ops - Finance`, `Ops - Directors`, `System Manager`. If not:

1. Hides the `payment_section` section break.
2. Hides individual fields: `sales_invoice`, `prepaid_amount`, `prepaid_payment_entry`, `total_invoice_amount`, `total_paid_amount`, `outstanding_amount`.
3. Hides `unit_price` and `discount_pct` columns in the `case_items` grid.
4. Also hides in the child row detail view (`form_render` event).

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| C1-F01 | **Client-side only.** The form data including all hidden fields is still sent to the browser. A non-financial user could see prices via browser dev tools, API calls, or reports. | **BUG B-10** | High |
| C1-F02 | **`profit` field on Dispatch Case not hidden.** The debt-closure script sets `profit` on the DC, but this client script doesn't hide it. Non-financial users can see profit data. | Oversight | Medium |
| C1-F03 | **`total_paid_amount` in hide list.** This field exists in the hide list but no script currently writes to it. It may always be empty/zero. | Dead reference — harmless | Low |
| C1-F04 | **Roles match Doc 16 §12 visibility rules.** The financial roles listed match the documented access model. | Matches documentation | High |
| C1-F05 | **`Ops - Order Creating` role can see `unit_price` and `discount_pct`** in the Dispatch Case form (they're not in the financial roles list). This is correct — Order Creating needs to set prices when creating the case. | Correct per design | High |

#### B-10 Deferred Discussion Direction

No B-10 code change was made in this pass. The recommended future fix is to protect financial fields with Frappe field permissions/permlevels instead of relying only on client-side hiding or a custom response-sanitizing Server Script.

Recommended protected Dispatch Case fields:
- `sales_invoice`
- `prepaid_amount`
- `prepaid_payment_entry`
- `total_invoice_amount`
- `total_paid_amount`
- `outstanding_amount`
- `profit`

Recommended protected Dispatch Case Item fields:
- `unit_price`
- `discount_pct`

Recommended implementation direction for later discussion:
1. Set these fields to a higher permlevel such as permlevel 1.
2. Grant permlevel 1 access only to selected financial/operational roles.
3. Keep `Dispatch Case-Price Visibility.js` as a UI convenience, and update it to hide `profit` too.
4. Decide before implementation whether `Ops - Order Creating` should have permlevel 1 access so they can continue entering unit prices and discounts during case creation.

Open discussion question: should `Ops - Order Creating` be included with `Ops - Accounting`, `Ops - Finance`, `Ops - Directors`, and `System Manager` for financial Dispatch Case field access?

---

## 5. Cross-Script Dependency Map

### Payment Flow Sequence

```
                          ┌─────────────────────────────────────┐
                          │   Dispatch Case Lifecycle (X1)      │
                          │                                     │
                          │  Invoice Prep task completed        │
                          │  → outstanding = total - prepaid    │
                          │  → if > 0: create/update Debt Task  │
                          │    (assigned to FINANCE_TEAM)       │
                          └───────────┬─────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Debt Collection Task                          │
│                                                                 │
│  Created by: X1 (dispatch flow) OR S1 (scheduler)              │
│  Assignment: Finance                                            │
│                                                                 │
│  Finance fills: new_payment_amount + method + reference → Save │
│                                                                 │
│  S2 fires (Before Save):                                       │
│    → FIFO allocation across open_invoices by posting date       │
│    → Creates PE with Sales Invoice references                   │
│    → PE auto-submitted                                         │
│    → If outstanding=0: task auto-completes                     │
│                                                                 │
│  S5 would fire (DISABLED):                                     │
│    → Would create Distribute Payment task                      │
│                                                                 │
│  S3 fires (After Save, on completion):                         │
│    → Creates Debt Closure Approval task                        │
│    → Assigns from Debt Closure Approval policy                 │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│              Debt Closure Approval Task                         │
│                                                                 │
│  S3 fires (After Save, on completion):                         │
│    → Permission check from Task Access Policy                  │
│    → Profit calculation across all linked Open Invoices         │
│    → Sets total task profit and per-Dispatch Case profit        │
└─────────────────────────────────────────────────────────────────┘
```

### Advance Payment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              Payment Received Task                              │
│                                                                 │
│  Created by: Finance manually                                  │
│                                                                 │
│  S4 fires (After Save, on completion):                         │
│    → Creates PE (draft, NOT submitted)                         │
│    → Appends advance row and recalculates prepaid_amount       │
│    → Adds to Debt Collection available_advance_credit           │
└─────────────────────────────────────────────────────────────────┘
```

### Scheduler Flow (Independent)

```
┌─────────────────────────────────────────────────────────────────┐
│        Scheduled-debt-collection (S1)                          │
│                                                                 │
│  Runs periodically                                             │
│  → GL-based net receivable per customer                        │
│  → If debt > threshold: create/update Debt Alert task          │
│    assigned from the Debt Alert Task Access Policy             │
│  → Does NOT populate open_invoices table                       │
│    because payment recording remains in Debt Collection        │
└─────────────────────────────────────────────────────────────────┘
```

### Tender Flow

```
┌────────────────────────────────────┐       ┌──────────────────────────────┐
│  Tender Agreement saved (S7)       │       │  Sales Invoice submitted (S6)│
│  → Recalculate remaining_qty      │       │  → Find active tenders       │
│  → Auto-set status by date        │       │  → Deduct supplied_qty       │
│  → Preserve Closed (B-06 fixed)   │       │  → Write fulfillment audit  │
└────────────────────────────────────┘       │  → B-04/B-05 fixed locally │
                                             │  → B-13 fixed locally      │
                                             └──────────────────────────────┘
```

### Script Execution Order for Task Save

Multiple scripts fire on Task save. ERPNext executes them in this order for the **same event**:

**Before Save:** S2 (`Task-before-save-payment-recording`)
**After Save:** S3 (`Task-after-save-debt-closure`), S4 (`Task-after-save-advance-payment`), X1 (`Task-after-save-dispatch-flow`)

All three After Save scripts check `task_kind` first, so they don't interfere when different task kinds are saved. However:

- If a **Debt Collection** task is completed: S2 runs first (Before Save, but amount was already recorded), then S3 fires (After Save) and creates the Debt Closure Approval task.
- If the same save somehow triggers both S3 and X1 (unlikely given task_kind guards), execution order matters. ERPNext processes server scripts in creation order — the exact ordering depends on which script was created first.

---

## 6. Documentation vs Production Comparison Matrix

| # | Feature | Documentation Says | Production Does | Match? | Classification | Confidence |
|---|---------|-------------------|-----------------|--------|---------------|------------|
| 1 | Debt threshold alerts | Directors are alerted via separate `Debt Alert` tasks (Doc 16 §6.10B, `docs/manual/debt-alert.md`) | **Locally corrected:** scheduler creates/updates `Debt Alert` tasks for Directors | **Yes — pending deployment/testing** | B-08 fixed locally; D-02 locally covered | High |
| 2 | Debt calculation basis | Net receivable: outstanding minus advances (req §6.6.2 recommended) | Scheduler uses GL Entry (debit-credit), which includes advances | **Yes** | Match | High |
| 3 | Debt Collection task per customer | One active Finance payment task per customer (Doc 16 §6.10) | Dispatch flow enforces one active `Debt Collection`; scheduler no longer touches this task kind | **Yes — pending deployment/testing** | B-08 fixed locally | High |
| 4 | Debt Collection assignment | Finance Team (Doc 16 §6.10) | **Locally corrected:** dispatch flow owns `Debt Collection`; scheduler assigns separate `Debt Alert` from policy | **Yes — pending deployment/testing** | B-08 fixed locally | High |
| 5 | Open invoices table on Debt task | Shows all outstanding invoices on Finance `Debt Collection` tasks (Doc 16 §6.10) | **Locally corrected:** only dispatch-flow `Debt Collection` contains Open Invoices; scheduler `Debt Alert` intentionally does not | **Yes — pending deployment/testing** | B-08 fixed locally | High |
| 6 | FIFO payment allocation | Oldest invoices first (req §6.6.2, manual Step 2) | **Locally corrected:** automatic FIFO now sorts by Sales Invoice posting date with invoice name as tie-breaker | **Yes — pending deployment/testing** | B-11 fixed locally | High |
| 7 | FIFO override (manual allocation) | Current docs now state automatic FIFO only | Automatic FIFO only; manual override is not supported in current Group 3 flow | **Yes** | Documented current behavior; no code change needed | High |
| 8 | Payment Entry auto-created | Auto-created with specified allocation (Doc 16 §6.10, §8) | **Locally corrected:** PE now receives Sales Invoice reference rows with preserved allocated amounts | **Yes — pending deployment/testing** | B-01 fixed locally | High |
| 9 | Payment Entry submit behavior | Doc 16 §8 now distinguishes invoice payments from advances | Debt Collection PE: auto-submitted. Advance PE: draft for Accounting review/submission | **Yes** | D-05 clarified/completed locally | High |
| 10 | Distribute Payment task | Docs now state disabled/deferred pending final keep/delete decision; requirements still mention original control step | Script DISABLED — intentionally out of active flow | **N/A — deferred** | B-02 decision recorded; D-04 locally corrected | High |
| 11 | Distribute Payment assigned to Finance | Doc 16 §6.11 says Finance if re-enabled | Script has latent Director assignment but is disabled/out of active flow | **N/A — deferred** | Latent only if re-enabled later; delete or redesign before any re-enable | High |
| 12 | Advance payment (no invoice) | Customer advance PE, no invoice link (Doc 16 §6.12) | Correct — PE has no references | **Yes** | Match | High |
| 13 | Advance updates DC prepaid_amount | Amount noted on case (Doc 16 §6.12) | **Locally corrected:** linked-case advances append to `advance_payments`; `prepaid_amount` is recalculated from all rows | **Yes — pending deployment/testing** | B-03 fixed locally | High |
| 14 | Advance updates Debt Collection credit | Reflected on Debt Collection task (Doc 16 §6.12) | Adds to `available_advance_credit` | **Yes** | Match | High |
| 15 | Outstanding = 0 → case Closed | Doc 16 §6.9, §6.10, manual Step 5 | Implemented in X1 (line 274-275) | **Yes** | Match | High |
| 16 | Debt Closure Approval | Locally documented in Doc 16 and `docs/manual/debt-closure-approval.md` | Task created on Debt Collection completion (S3) | **Yes — pending deployment/testing** | D-01 locally covered | High |
| 17 | Profit calculation | Locally documented in `docs/manual/debt-closure-approval.md` | **Locally corrected:** calculated on Debt Closure Approval completion across all linked Open Invoices, with per-Dispatch Case profit writeback | **Yes — pending deployment/testing** | B-07 fixed locally; D-01 locally covered | High |
| 18 | Tender qty auto-update | SI submission updates tender supplied/remaining (deployment summary) | Implemented in S6 | **Yes** | Match | High |
| 18A | Tender price enforcement | Tender-covered invoice items must use `Tender Agreement Item.tender_price` | **Locally corrected:** Before Submit validation stops submit if invoice rate differs from tender price | **Yes — pending deployment/testing** | Tender price validation added locally | High |
| 19 | Tender over-supply warning | System blocks submit if tender quantity exceeds remaining | **Locally corrected:** Before Submit validation stops submit with review message if invoice qty exceeds remaining tender qty | **Yes — pending deployment/testing** | Control added; review with colleague | High |
| 20 | Tender cancellation reversal | Tender manual documents exact fulfillment reversal | **Locally corrected:** Sales Invoice cancellation reverses exact rows from `tender_fulfillments` audit table | **Yes — pending deployment/testing** | B-05 fixed locally | High |
| 21 | Tender status auto-set | Auto-updates Draft/Active/Expired by dates while preserving manual Closed | **Locally corrected:** only Closed is preserved; Draft now auto-transitions by dates | **Yes — pending deployment/testing** | B-06 plus Draft status confusion fixed locally | High |
| 22 | Financial field visibility | Non-financial roles cannot see prices (Doc 16 §12) | Client-side hiding only; no server enforcement yet | **Discussion required** | B-10 deferred; recommended field-permission/permlevel direction documented in C1 section | High |
| 23 | PE cancellation re-opens task | Cancellation manual now states no automatic Debt Collection/case restoration exists | No script handles PE cancellation events | **Yes** | D-06 clarified/completed locally; manual review required | High |
| 24 | Scheduled debt check | Documented in Doc 16 §6.10B and `docs/manual/debt-alert.md` | Runs via scheduler, uses GL entries, creates/updates Debt Alert tasks | **Yes — pending deployment/testing** | D-02 completed locally | High |
| 25 | Tender system documentation | Operational tender manual should exist and be linked | **Locally corrected:** `docs/manual/tender-agreement-management.md` created and linked from manuals index/docs overview | **Yes — pending smoke test** | D-03 locally covered | High |
| 26 | Lost/damaged billing | Current docs state lost/damaged quantities are not auto-invoiced and require manual review/resolution | Current invoice creation bills `used_qty` only | **Yes** | Documented current behavior; automatic lost/damaged billing deferred | High |
| 27 | Unallocated advance recording | Req §6.6.2 — record as customer advance | Advance PE created without invoice refs — correct | **Yes** | Match | High |
| 28 | No time limit for advances | Req §6.6.2 | No expiry logic implemented — correct | **Yes** | Match | High |

---

## 7. Bug and Risk Register

### Critical

| ID | Title | Script | Impact | Confidence | Evidence |
|----|-------|--------|--------|------------|----------|
| **B-01** | Payment Entry created without invoice references | S2 payment allocation / PE reference creation | **Fixed locally:** payable rows must have linked Sales Invoices, allocations are preserved before `allocated_now` is cleared, and Sales Invoice references are appended to the Payment Entry. Pending deployment/testing. | **High** | Local script now validates invoice links, builds an `allocations` list, and uses it for PE `references`. |

### High

| ID | Title | Script | Impact | Confidence | Evidence |
|----|-------|--------|--------|------------|----------|
| **B-02** | Distribute Payment intentionally disabled/out of active flow | S5 | No code fix needed now. Do not enable unless business flow is explicitly changed later. Central/manual docs now mark it disabled/deferred pending final keep/delete decision. | **Deferred / not active** | Schema/local file: `disabled: 1`; D-04 locally corrected |
| **B-03** | Advance prepaid_amount overwrites — locally corrected | S4 lines 31-44 | Linked-case advances now append to `advance_payments`, `prepaid_amount` is recalculated from all rows, and `prepaid_payment_entry` remains latest-entry quick reference. | **Fixed locally, pending deployment/testing** | Code: child-row append plus sum recalculation |
| **B-04** | Tender double-counts across multiple active tenders — locally corrected | S6 lines 18-70 | Duplicate active tender rows for the same hospital/item now stop Sales Invoice submit; exactly one match updates once; over-supply stops with review message. | **Fixed locally, pending deployment/testing** | Code: duplicate/over-supply guards and single-match update |
| **B-05** | No tender reversal on invoice cancellation — locally corrected | S6 + S8 | Sales Invoice submit records exact tender fulfillment rows; Sales Invoice cancel subtracts those quantities from the same Tender Agreements. | **Fixed locally, pending deployment/testing** | Code: `tender_fulfillments` audit rows plus On Cancel reversal script |

### Medium

| ID | Title | Script | Impact | Confidence | Evidence |
|----|-------|--------|--------|------------|----------|
| **B-06** | Tender "Closed" status overridden on save — locally corrected | S7 lines 14-22 | Manually Closed tenders now stay Closed on later saves; date-based auto-status still applies to non-Draft/non-Closed statuses. | **Fixed locally, pending deployment/testing** | Code: `doc.status in ("Draft", "Closed")` skips auto-status |
| **B-07** | Profit calculation only used one invoice — locally corrected | S3 lines 85-116 | Multi-invoice Debt Closure Approval now sums profit across all unique Open Invoices and writes each linked Dispatch Case's own profit. | **Fixed locally, pending deployment/testing** | Code: iterates `doc.open_invoices`, sums `total_profit`, writes `dispatch_case_profit` |
| **B-08** | Dual debt task creation paths with different assignees/data — locally corrected | S1 + X1 | Scheduler now creates/updates separate Director `Debt Alert` tasks; dispatch flow remains the only producer of Finance `Debt Collection` tasks with invoice detail. | **Fixed locally, pending deployment/testing** | Code: S1 uses `DEBT_ALERT_KIND`; X1 remains `Debt Collection` |
| **B-10** | Financial visibility client-side only — deferred for discussion | C1 | Non-financial users can access price/payment/profit data via API, reports, dev tools because fields are only hidden in the browser. | **Discussion required / no code change yet** | Recommended direction documented: Frappe field permissions/permlevels, include `profit`, decide `Ops - Order Creating` access |
| **B-12** | `paid_to` hardcoded as "Cash - Inmed" — locally corrected | S2 + S4 | Debt Collection and advance Payment Entries now post to `Cash - Inmed` for Cash and `Bank - Inmed` for Bank Transfer/Card. | **Fixed locally, pending deployment/testing** | Code: `paid_to_account` method mapping in both scripts |
| **B-13** | `frappe.db.commit()` inside loop in tender update — locally corrected | S6 | Manual commit removed; tender saves stay inside the Sales Invoice submit transaction. | **Fixed locally, pending deployment/testing** | Code: no `frappe.db.commit()` in S6 |

### Low

| ID | Title | Script | Impact | Confidence | Evidence |
|----|-------|--------|--------|------------|----------|
| **B-09** | Hardcoded user emails in debt closure — locally corrected | S3 + Task-before-save-dispatch-gates | Approver assignment and completion permission now use `Debt Closure Approval` Task Access Policy; team/user changes no longer require script edits. | **Fixed locally, pending deployment/testing** | Code: no `APPROVED_USERS` list; policy default team and allowed roles drive behavior |
| **B-11** | FIFO sorts by invoice name not date | S2 payment allocation sort | **Fixed locally:** automatic FIFO now sorts by linked Sales Invoice posting date, then invoice name as a tie-breaker. Pending deployment/testing. | **High** | Local script now fetches Sales Invoice `posting_date` / `creation` and sorts by date. |

---

## 8. Reports, Custom Fields, and Supporting Artifacts

### 8.1 Reports Relevant to Group 3

16 reports were found in the schema. Notable observations:

| Observation | Reports Affected | Concern |
|------------|-----------------|---------|
| **Report pair classified** | `RPT - Clients Exceeding Debt Threshold` vs `RPT — Risk — Debt Threshold Exceeded` | Official report should be `RPT — Risk — Debt Threshold Exceeded` because it uses GL Entry net receivable, matching the Debt Alert scheduler. The older invoice-minus-advance report should be treated as legacy/deferred pending colleague review. |
| **Report pair classified** | `RPT - Unallocated Customer Advances` vs `RPT — Receivables — Unallocated Advances` | Official report should be `RPT — Receivables — Unallocated Advances` because it calculates unallocated amount from submitted Payment Entry references. The older direct `unallocated_amount` report should be treated as legacy/deferred pending colleague review. |
| **Report pair classified** | `RPT - Prepaid Orders Awaiting Delivery` vs `RPT — Ops — Prepaid Orders Awaiting Delivery` | Official current-flow report should be Dispatch Case based, because current advance handling writes to Dispatch Case advance fields. Any Sales Order prepaid report/field usage is legacy/deferred pending colleague review. |
| **All enabled** | All 16 reports | None are disabled. Good. |
| **All Query Reports** | All 16 | Custom SQL — queries not inspectable from schema alone. Require live testing. |
| **B-01 report impact locally corrected** | Debt Status Board, Unpaid Invoices, Unallocated Advances | Local S2 now writes Sales Invoice references on Debt Collection Payment Entries. Reports should align after deployment/testing; older data may still need review if it was created before the fix. |

### 8.2 Custom Fields Relevant to Group 3

#### On Customer

| Fieldname | Type | Purpose |
|-----------|------|---------|
| `debt_threshold_amd` | Currency | Per-customer debt threshold in AMD. Used by S1. |
| `is_provisional` | Check | Provisional customer flag. Not used by any Group 3 script. |

#### On Task (payment/debt related)

| Fieldname | Type | Purpose | Used By |
|-----------|------|---------|---------|
| `task_kind` | Select | Categorizes task type. Options include: Debt Alert, Debt Collection, Distribute Payment, Payment Received, Invoice preparation / create invoice, Debt Closure Approval, and others. | All scripts |
| `payment_entry` | Link → PE | Links to Payment Entry. | S5, S3 |
| `current_debt_amd` | Currency | Current debt amount. | S1 |
| `debt_threshold_amd` | Currency | Customer's threshold (copied to task). | S1 |
| `sales_invoice` | Link → SI | Links to Sales Invoice. | S3, X1 |

Note: The task also has `new_payment_amount`, `payment_method_dc`, `payment_reference_dc`, `open_invoices`, `payment_history`, `total_outstanding`, `available_advance_credit`, `custom_total_amount_paid`, `custom_case_profit`, `dispatch_case`, `customer` — these are used by Group 3 scripts but were not all surfaced in the custom-fields scan. They likely exist as custom fields defined at deployment time or are child table fields.

#### On Sales Invoice

| Fieldname | Type | Purpose |
|-----------|------|---------|
| `hospital` | Link → Customer | Hospital context. Used by S6 for tender matching. |
| `hospital_branch` | Data | Branch context. |
| `doctor_name` | Data | Doctor context. |
| `surgery_case` | Link → Surgery Case | Legacy link (Surgery Case DocType, pre-Dispatch Case). |
| `tender_fulfillments` | Table → Sales Invoice Tender Fulfillment | Local B-05 audit trail recording which tender rows were updated on Sales Invoice submit, used for exact cancellation reversal. |

#### On Sales Order (legacy/deferred prepayment tracking — do not delete yet)

| Fieldname | Type | Purpose |
|-----------|------|---------|
| `is_prepaid` | Check | Legacy/deferred Sales Order prepayment flag. |
| `prepayment_required_amount_amd` | Currency | Legacy/deferred required advance amount. |
| `prepayment_payment_entry` | Link → PE | Legacy/deferred link to advance PE. |

Note: These Sales Order fields are NOT used by any active Group 3 script. Current advance payment handling uses Payment Received tasks and Dispatch Case `advance_payments` / `prepaid_amount` fields. Keep the Sales Order fields for now, but treat them as legacy/deferred pending colleague review; do not delete until that decision is made.

### 8.3 Custom DocTypes

#### Tender Agreement

- **Naming:** By `tender_name` field (user-entered, unique).
- **Not submittable** — uses status field instead of docstatus.
- **Fields:** tender_name, hospital (Customer link), valid_from, valid_to, status (Draft/Active/Expired/Closed), items (child table), notes.
- **Permissions:** Accounting can CRUD. Directors can CRUD + Delete. System Manager full access. Order Creating can read only.
- **No workflow** attached.
- **Locally documented** in `docs/manual/tender-agreement-management.md` and linked documentation indexes.

#### Tender Agreement Item

- **Child table** of Tender Agreement.
- **Fields:** item_code, item_name (fetched), tender_price, won_quantity, supplied_quantity, remaining_quantity (read-only).
- **`tender_price` is locally enforced** by `Sales-Invoice-before-submit-tender-validation.py` before Sales Invoice submit when the hospital/item matches one active tender row.

#### Sales Invoice Tender Fulfillment

- **Child table** of Sales Invoice, added locally for B-05.
- **Fields:** tender_agreement, item_code, quantity, sales_invoice_item, applied_at.
- **Purpose:** records the exact tender quantity updates made when a Sales Invoice is submitted so cancellation can reverse the same Tender Agreement rows later without guessing by current tender status.

### 8.4 Property Setters

44 property setters on Task control field visibility based on `task_kind`. Key payment-relevant ones:

- `payment_entry`, `current_debt_amd`, `debt_threshold_amd`: visibility depends on task_kind formula (shown only for relevant task kinds).
- `sales_invoice`: visibility depends on task_kind formula.
- Standard ERPNext fields hidden: `project`, `issue`, `type`, `color`, `is_group`, `task_weight`, `parent_task`, `is_template`, `task_access_policy`.

16 property setters on Sales Invoice mostly control display formatting (print format, section visibility). No financial logic impact.

2 property setters on Customer: hide naming_series field. No financial impact.

No property setters on Payment Entry.

### 8.5 Notifications

No Group 3-specific notifications found. The 5 deployed notifications are:
1. Fiscal year auto-creation (email to Accounts roles)
2. Material Request receipt (email to owner)
3. Error Log (email to System Manager)
4. Upcoming renewals (daily, System Manager)
5. Milestone (Task date-based, to assignees)

None of these notify Finance or Directors about payment events. The Telegram notification system (Group 8) may cover some of these — to be analyzed in that group's audit.

---

## 9. Questions Requiring Live Smoke Testing

These findings cannot be fully resolved by static analysis alone:

| # | Question | Why Static Analysis Is Insufficient | Priority |
|---|----------|-------------------------------------|----------|
| Q-01 | Does the PE without invoice references actually cause AR discrepancy? | Need to submit a real PE and check the Accounts Receivable report. | Critical |
| Q-02 | What is the scheduler frequency for S1? | Not visible in extracted files. Set in ERPNext admin UI. | High |
| Q-03 | Do any existing Debt Collection tasks have both scheduler-set and dispatch-flow-set data? | Need to query Task list in production. | High |
| Q-04 | Do existing Tender Agreements transition correctly after the local status fix? | Need live/test data to confirm Closed remains Closed and Draft/Active/Expired follow dates after deployment. | Medium |
| Q-05 | Do legacy/deferred duplicate reports still appear in user workspaces or confuse users? | Official/legacy report classification is documented locally; UI/report-list cleanup should be reviewed with colleague before disabling anything. | Medium |
| Q-06 | Should legacy/deferred Sales Order prepaid fields be hidden from forms after colleague review? | Current active Group 3 flow uses Dispatch Case advance fields; Sales Order prepaid fields are kept, not deleted, pending review. | Low |
| Q-07 | Does the locally corrected S6 tender update remain fully transactional during Sales Invoice submit? | Need smoke test after deployment. | Medium |
| Q-08 | How many customers currently have multiple active tenders for the same item? | Need to query data before/after deployment because duplicates will now stop invoice submit. | Medium |
| Q-09 | Does Payment Entry cancellation follow the documented manual-review workflow? | D-06 is documentation-correct locally: no automatic Debt Collection/case restoration exists. Live users should confirm the manual correction workflow is acceptable. | High |
| Q-10 | Is the `available_advance_credit` field displayed on the Debt Collection task form? Does Finance use it? | Need to check UI. | Medium |

---

## 10. Recommendations

### Critical — Fix Before Go-Live

| # | Action | Bug/Gap | Effort |
|---|--------|---------|--------|
| R-01 | **Completed locally:** PE invoice references now use preserved allocation amounts before `allocated_now` is cleared. | B-01 | Done locally; deploy/test later |
| R-02 | **Completed locally:** Distribute Payment remains disabled/out of active flow, and central/manual docs now describe it as disabled/deferred pending final keep/delete decision. Do not enable S5 before redesign or deletion decision. | B-02, D-04 | Done locally; final keep/delete decision later |
| R-03 | **Completed locally:** Dispatch Case linked advances now use `advance_payments` child-table audit trail; `prepaid_amount` is recalculated from all rows and `prepaid_payment_entry` is latest-entry quick reference. | B-03 | Done locally; deploy/test later |

### High — Fix Soon After Go-Live

| # | Action | Bug/Gap | Effort |
|---|--------|---------|--------|
| R-04 | **Completed locally:** S6 requires at most one active tender row per hospital/item and stops invoice submit on duplicates. | B-04 | Done locally; deploy/test later |
| R-05 | **Completed locally:** added Sales Invoice tender fulfillment audit trail and `Sales-Invoice-on-cancel-tender-reversal.py` On Cancel reversal script. | B-05 | Done locally; deploy/test later |
| R-06 | **Completed locally:** S7 now preserves manually Closed tenders with `if doc.status in ("Draft", "Closed")`. | B-06 | Done locally; deploy/test later |
| R-07 | **Completed locally:** S2 and S4 map payment method to `paid_to`: Cash → `Cash - Inmed`, Bank Transfer/Card → `Bank - Inmed`. | B-12 | Done locally; deploy/test later |
| R-08 | **Completed locally:** removed manual `frappe.db.commit()` from S6. Tender updates now rely on the Sales Invoice submit transaction. | B-13 | Done locally; deploy/test later |
| R-09 | **Completed locally:** Debt Closure Approval is documented in Doc 16 and linked `docs/manual/debt-closure-approval.md`. | D-01 | Done locally |
| R-10 | **Completed locally:** scheduled GL-based debt checks are documented as Director `Debt Alert` tasks in Doc 16 and `docs/manual/debt-alert.md`. | D-02 | Done locally |

### Medium — Plan For Next Iteration

| # | Action | Bug/Gap | Effort |
|---|--------|---------|--------|
| R-11 | **Completed locally:** S3 iterates all unique Sales Invoices in `open_invoices`, sums total approval profit, and sets each linked Dispatch Case's own profit. | B-07 | Done locally; deploy/test later |
| R-12 | **Completed locally:** scheduler and dispatch flow now use separate task kinds: `Debt Alert` for Director threshold monitoring and `Debt Collection` for Finance payment recording. | B-08 | Done locally; deploy/test later |
| R-13 | **Deferred discussion item:** recommended direction is Frappe field permissions/permlevels for Dispatch Case financial fields and Dispatch Case Item price/discount fields, with client script retained only as UI convenience. Decide whether `Ops - Order Creating` should keep price/discount access before implementation. | B-10 | Discussion required before code change |
| R-14 | **Completed locally:** Debt Closure Approval assignment and completion permission now use Task Access Policy instead of hardcoded user emails. | B-09 | Done locally; deploy/test later |
| R-15 | **Completed locally:** created `docs/manual/tender-agreement-management.md` and linked it from manuals index/docs overview. | D-03 | Done locally |
| R-16 | **Completed locally:** tender validation now stops Sales Invoice submit when invoice quantity exceeds remaining tender quantity or invoice rate differs from `tender_price`. | S6-F03, S9-F01 | Done locally; review policy with colleague |
| R-17 | **Completed locally for now:** duplicate/overlapping reports are classified as official vs legacy/deferred in this audit. Do not delete reports; review with colleague before any UI disable/removal decision. | §8.1 | Documentation/classification done locally |
| R-18 | **Completed locally:** FIFO sort now uses Sales Invoice posting date, with invoice name as tie-breaker; current flow is documented as automatic FIFO only with no manual override. | B-11 | Done locally; deploy/test later |
| R-19 | **Completed locally:** cancellation manual now reflects actual behavior: no automatic Payment Entry cancellation reversal exists, so Accounting/System Manager must manually review/correct Debt Collection and Dispatch Case state. | D-06 | Done locally; future automatic handler would be separate feature |
| R-20 | **Deferred by decision:** Sales Order prepaid fields are legacy/deferred and should not be deleted now. Keep them for colleague review; hide/disable later only after explicit decision. | §8.2 | Deferred; do not delete |

---

## Appendix A: Confidence Scale

| Level | Meaning |
|-------|---------|
| **High** | Directly proven by code logic, schema metadata, or documentation text. No ambiguity. |
| **Medium** | Strongly indicated by evidence but depends on runtime behavior, configuration, or business context that cannot be verified statically. |
| **Low** | Plausible concern based on code patterns, but requires production data or live testing to confirm impact. |

## Appendix B: Evidence Index

| Finding | Primary Evidence Location |
|---------|--------------------------|
| B-01 | `deploy/test/work/server/Task-before-save-payment-recording.py` lines 22-44 and 64-70 — local fix validates linked invoices, preserves allocations, and appends PE references |
| B-02 | `deploy/test/schema/server-scripts.json` — `disabled: 1` for `Payment Entry-after-submit-distribute-payment` |
| B-03 | `deploy/test/work/server/Task-after-save-advance-payment.py` lines 31-44; `deploy/test/deploy/group-3-payments-debt-accounting/deploy-b03-advance-payment-audit-trail.ps1` creates `Dispatch Case Advance Payment` and `Dispatch Case-advance_payments` |
| B-04 | `deploy/test/work/server/Sales-Invoice-after-submit-tender-update.py` lines 18-70; `deploy/test/deploy/group-3-payments-debt-accounting/deploy-b04-b13-tender-update-controls.ps1`; `docs/manual/tender-agreement-management.md` |
| B-05 | `deploy/test/work/server/Sales-Invoice-after-submit-tender-update.py` lines 57-70; `deploy/test/work/server/Sales-Invoice-on-cancel-tender-reversal.py`; `deploy/test/deploy/group-3-payments-debt-accounting/deploy-b05-tender-cancellation-reversal.ps1`; `docs/manual/tender-agreement-management.md` |
| B-06 | `deploy/test/work/server/Tender-Agreement-before-save.py` lines 14-22; `deploy/test/deploy/group-3-payments-debt-accounting/deploy-b06-tender-closed-status-preservation.ps1`; `docs/manual/tender-agreement-management.md` |
| B-07 | `deploy/test/work/server/Task-after-save-debt-closure.py` lines 85-116; `deploy/test/deploy/group-3-payments-debt-accounting/deploy-b07-debt-closure-multi-invoice-profit.ps1`; `docs/manual/debt-closure-approval.md` |
| B-08 | `deploy/test/work/server/Scheduled-debt-collection.py` lines 8 and 64-111; `deploy/test/work/server/Task-after-save-dispatch-flow.py` lines 148-178; `deploy/test/deploy/group-3-payments-debt-accounting/deploy-b08-separate-debt-alert-from-collection.ps1`; `docs/manual/debt-alert.md` |
| B-09 | `deploy/test/work/server/Task-after-save-debt-closure.py` lines 14, 35-41, 60-83; `deploy/test/work/server/Task-before-save-dispatch-gates.py` lines 142-148; `deploy/test/deploy/group-3-payments-debt-accounting/deploy-b09-debt-closure-policy-approvers.ps1`; `docs/manual/debt-closure-approval.md` |
| B-10 | `deploy/test/work/client/Dispatch Case-Price Visibility.js` — no matching server script |
| B-11 | `deploy/test/work/server/Task-before-save-payment-recording.py` lines 22-29 — local fix sorts FIFO by Sales Invoice posting date |
| B-12 | `deploy/test/work/server/Task-before-save-payment-recording.py` lines 19-23 and 64-65; `deploy/test/work/server/Task-after-save-advance-payment.py` lines 16-20 and 30-32; `deploy/test/deploy/group-3-payments-debt-accounting/deploy-b12-payment-method-paid-to-account.ps1`; `docs/manual/debt-collection-and-payment.md`; `docs/manual/customer-advance-payment.md`; `docs/16-unified-dispatch-flow.md` |
| B-13 | `deploy/test/work/server/Sales-Invoice-after-submit-tender-update.py` — manual `frappe.db.commit()` removed; `deploy/test/deploy/group-3-payments-debt-accounting/deploy-b04-b13-tender-update-controls.ps1` |
| D-01 | `docs/16-unified-dispatch-flow.md` Task 6.10A and §11; `docs/manual/debt-closure-approval.md` |
| D-02 | `docs/16-unified-dispatch-flow.md` Task 6.10B and §11; `docs/manual/debt-alert.md` |
| D-03 | `docs/docs-overview.md` — "no numbered doc exists for Tender Agreements" |
| D-04 | `docs/16-unified-dispatch-flow.md`; `docs/16a-unified-dispatch-flow-implementation.md`; `docs/09-standard-selling-flow.md`; `docs/09-standard-selling-flow-implementation.md`; `docs/12-surgery-set-operational-workflow.md`; `docs/13-reporting-pack.md`; `docs/14-go-live-checklist.md`; `docs/manual/debt-collection-and-payment.md`; `docs/manual/daily-reporting-checks.md`; `docs/manual/standard-sale-walkthrough.md`; `docs/manual/surgery-case-walkthrough.md`; `docs/manual/surgery-case-walkthrough-v2.md` now state Distribute Payment is disabled/deferred |
| D-05 | `docs/16-unified-dispatch-flow.md` §8; `docs/manual/customer-advance-payment.md`; `deploy/test/work/server/Task-after-save-advance-payment.py` intentionally uses `insert()` only for draft advance Payment Entries |
| D-06 | `docs/manual/cancellation-and-corrections.md` "Payment Entry — cancellation" section now documents manual review/correction because no automatic Payment Entry cancellation reversal script exists |

---

*End of Group 3 Audit Report*
