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

Group 3 covers 8 server scripts (7 enabled, 1 disabled), 1 client script, 2 custom DocTypes, 16 reports, and associated custom fields and property setters. The functional scope is: debt collection automation, payment recording, payment distribution, advance/prepaid payments, invoice generation, tender agreement tracking, and financial field visibility.

### Critical Findings

| # | Finding | Severity | Confidence |
|---|---------|----------|------------|
| B-01 | Payment Entry created without invoice references — accounting ledger never reconciles against specific invoices | **CRITICAL** | High (code-proven) |
| B-02 | `Distribute Payment` script is DISABLED — the documented physical-payment control step does not exist in production | **HIGH** | High (schema-proven) |
| B-03 | Advance payment `prepaid_amount` overwrites instead of accumulating on Dispatch Case | **HIGH** | High (code-proven) |
| B-04 | Tender Agreement `supplied_quantity` deducted from ALL matching tenders for same customer — double-counting | **HIGH** | High (code-proven) |
| B-05 | Tender quantities are never reversed on invoice cancellation | **HIGH** | High (code-proven, no cancellation handler exists) |
| B-06 | Tender `Closed` status is overridden by auto-status logic on save | **MEDIUM** | High (code-proven) |
| B-07 | Debt Closure profit calculation only considers one invoice, not all invoices on the task | **MEDIUM** | High (code-proven) |
| B-08 | Two independent debt task creation paths (scheduler vs dispatch flow) with different assignees and different data | **MEDIUM** | High (code-proven) |
| B-09 | Hardcoded user emails in debt closure approval — maintenance risk | **LOW** | High (code-proven) |
| B-10 | Financial field visibility is client-side only — no server-side enforcement | **MEDIUM** | High (code-proven) |
| B-11 | FIFO payment allocation sorts by invoice name, not invoice date | **LOW** | High (code-proven) |
| B-12 | `paid_to` account hardcoded as "Cash - Inmed" regardless of payment method | **MEDIUM** | High (code-proven) |
| B-13 | `frappe.db.commit()` inside loop in tender update script breaks transaction boundary | **MEDIUM** | High (code-proven) |

### Documentation Gaps

| # | Gap | Confidence |
|---|-----|------------|
| D-01 | Debt Closure Approval task kind not documented in any numbered doc | High |
| D-02 | Scheduled debt collection (GL-based) not documented — only dispatch-flow debt task is described | High |
| D-03 | Tender Agreement system has no numbered document (only deployment summary) | High |
| D-04 | Manual says Distribute Payment tasks are created — they are not (script disabled) | High |
| D-05 | Manual says Payment Entries are auto-submitted — advance payment script does NOT submit | Medium |
| D-06 | Cancellation manual says "Debt Collection task outstanding balance will increase back" — no script implements this | High |

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
| S1 | Scheduled-debt-collection | Scheduler Event | — | — | **Yes** | 123 | GL-based debt threshold check; creates/updates Debt Collection tasks for directors |
| S2 | Task-before-save-payment-recording | DocType Event | Task | Before Save | **Yes** | 70 | Records payment on Debt Collection task; creates Payment Entry; FIFO allocation |
| S3 | Task-after-save-debt-closure | DocType Event | Task | After Save | **Yes** | 101 | Creates Debt Closure Approval task; calculates case profit on closure approval |
| S4 | Task-after-save-advance-payment | DocType Event | Task | After Save | **Yes** | 36 | Creates advance Payment Entry on Payment Received task completion |
| S5 | Payment Entry-after-submit-distribute-payment | DocType Event | Payment Entry | After Submit | **No** | 83 | Would create Distribute Payment tasks (DISABLED) |
| S6 | Sales-Invoice-after-submit-tender-update | DocType Event | Sales Invoice | After Submit | **Yes** | 25 | Updates Tender Agreement supplied/remaining quantities |
| S7 | Tender-Agreement-before-save | DocType Event | Tender Agreement | Before Save | **Yes** | 22 | Recalculates remaining qty; auto-sets status by date range |

### Cross-Reference Server Script (Group 1)

| # | Schema Name | Script Type | DocType | Event | Enabled | Lines | Financial Functions |
|---|-------------|-------------|---------|-------|---------|-------|---------------------|
| X1 | Task-after-save-dispatch-flow | DocType Event | Task | After Save | **Yes** | 289 | `create_invoice()`, `create_or_update_debt_task()`, outstanding calculation, prepaid deduction |

### Client Scripts

| # | Schema Name | DocType | View | Enabled | Lines | Purpose |
|---|-------------|---------|------|---------|-------|---------|
| C1 | Dispatch Case-Price Visibility | Dispatch Case | Form | **Yes** | 72 | Hides financial fields from non-financial roles |

### Metadata Verification

All script names, types, events, and disabled states were verified against `deploy/test/schema/server-scripts.json`. No discrepancies found between extracted files and schema metadata.

---

## 4. Script-by-Script Deep Analysis

### S1 — Scheduled-debt-collection.py

**Schema name:** `Scheduled-debt-collection`
**Type:** Scheduler Event | **Enabled:** Yes | **Lines:** 123

#### Behavior Summary

1. Resolves the default company from Global Defaults (fallback: first Company record).
2. Finds all enabled users with `Ops - Directors` role. Filters out `Administrator` and `Guest`. Sorts alphabetically. Takes the **first** as `assigned_director`.
3. Iterates all non-disabled Customers that have `debt_threshold_amd > 0`.
4. Calculates **net receivable** per customer via direct GL Entry query: `SUM(debit - credit)` where `is_cancelled = 0`, filtered by company and party.
5. If `debt > threshold`:
   - Looks for an existing non-Completed Debt Collection task for that customer.
   - If found: updates it with current debt and threshold values.
   - If not found: creates a new task with `task_kind = "Debt Collection"`, `task_access_policy = "Debt Collection"`, assigned to the first director.
6. Sets `current_debt_amd`, `debt_threshold_amd`, and a text `description` on the task.

#### Fields Read

| Field | DocType | Purpose |
|-------|---------|---------|
| `default_company` | Global Defaults | Company resolution |
| `role` | Has Role | Director user discovery |
| `enabled` | User | Filter disabled users |
| `disabled`, `customer_name`, `debt_threshold_amd` | Customer | Threshold check |
| `debit`, `credit`, `is_cancelled`, `party`, `party_type` | GL Entry | Net receivable calculation |
| `task_kind`, `customer`, `status` | Task | Duplicate check |

#### Fields Written

| Field | DocType | Purpose |
|-------|---------|---------|
| `subject`, `status`, `task_kind`, `task_access_policy`, `customer` | Task | New task creation |
| `current_debt_amd`, `debt_threshold_amd`, `description` | Task | Debt tracking |
| `_assign` | Task | Director assignment |
| `status`, `allocated_to`, `reference_type`, `reference_name`, `description`, `assigned_by` | ToDo | Assignment tracking |

#### Trigger Conditions

Runs on scheduler (frequency not visible in extracted script — set in ERPNext scheduler configuration, typically hourly or daily).

#### Idempotency

**Good.** If an existing non-Completed Debt Collection task exists, it updates rather than creating a duplicate. The update only writes current_debt_amd, debt_threshold_amd, and description — no destructive side effects.

#### Error Handling

**Minimal.** No try/except blocks. If GL query fails or a customer record is corrupt, the entire scheduler run would fail silently (ERPNext logs the error but the scheduler continues for other events).

#### Security / Permissions

Uses `ignore_permissions=True` for task creation and ToDo management. Appropriate for a system-level scheduler.

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S1-F01 | **Debt calculation uses GL Entry (net receivable)**. This correctly includes the effect of all payment entries, credit notes, and journal entries. Matches requirements §6.6.2 recommendation for net receivable. | **Matches requirements** | High |
| S1-F02 | **Assignment to first director alphabetically.** Not documented anywhere. If directors are added/removed, the assignment target changes unpredictably. | Undocumented decision | High |
| S1-F03 | **Does not populate `open_invoices` child table.** The dispatch-flow script creates Debt Collection tasks WITH open_invoices. The scheduler creates them WITHOUT. If the scheduler creates a task first, the Finance team sees a task with current_debt_amd but no invoice breakdown. | Design inconsistency | High |
| S1-F04 | **Assigns to Directors.** Doc 16 §6.10 says Debt Collection tasks go to Finance Team. The scheduler sends them to Directors. This appears to be two conceptually different purposes under the same task_kind: (a) director alert for threshold breach vs (b) finance workflow for payment collection. | Doc/prod difference — likely intentional dual-purpose | High |
| S1-F05 | **Skips customers with threshold <= 0.** Safe. All 193 customers verified to have thresholds set per deployment summary. | Correct | High |
| S1-F06 | **Subject format:** `"Debt Collection — {customer_name}"`. Dispatch flow uses `"Debt Collection: {customer_name}"`. Minor inconsistency. | Cosmetic | High |
| S1-F07 | **Does not set `status = "Open"` on existing tasks.** If a task was in "Working" or another intermediate status, the scheduler updates its debt fields but leaves its status unchanged. Correct behavior — doesn't disrupt ongoing work. | Correct | High |

---

### S2 — Task-before-save-payment-recording.py

**Schema name:** `Task-before-save-payment-recording`
**Type:** DocType Event — Before Save | **Enabled:** Yes | **Lines:** 70

#### Behavior Summary

1. Only acts on `task_kind == "Debt Collection"`.
2. Only acts when `new_payment_amount > 0`.
3. **Idempotency guard:** Compares current `new_payment_amount` with previous save value. Only fires on change.
4. Takes payment amount, method (default "Cash"), reference.
5. **FIFO allocation:** Sorts `open_invoices` by `sales_invoice` (alphabetical by name). Allocates payment to rows in order until amount is exhausted.
6. Updates each row: increments `paid_amount`, decrements `outstanding_amount`, **zeroes `allocated_now`**.
7. Recalculates `total_outstanding`.
8. Appends to `payment_history` child table.
9. Creates a Payment Entry (type: Receive, party: Customer).
10. **Attempts** to add invoice references to the PE — but this always fails (see B-01 below).
11. Submits the PE immediately.
12. Links PE name to the payment_history row.
13. Resets input fields.
14. If `total_outstanding <= 0`, auto-sets `doc.status = "Completed"`.

#### **BUG B-01: Payment Entry created WITHOUT invoice references** (CRITICAL)

The script has a logical ordering error:

**Lines 28–33** — Zero out `allocated_now` after applying to paid/outstanding:
```python
for row in doc.open_invoices:
    apply = row.allocated_now or 0
    if apply > 0:
        row.paid_amount = (row.paid_amount or 0) + apply
        row.outstanding_amount = (row.outstanding_amount or 0) - apply
        row.allocated_now = 0          # <-- ZEROED HERE
```

**Lines 54–60** — Try to use `allocated_now` to build PE references:
```python
for row in doc.open_invoices:
    if (row.allocated_now or 0) > 0:   # <-- ALWAYS FALSE
        pe.append("references", {...})
```

Because `allocated_now` was already set to 0 in the first loop, the second loop **never adds any invoice references** to the Payment Entry. Every PE is created as an **unallocated customer advance** regardless of intent.

**Impact:**
- ERPNext's GL entries show the payment as unallocated — Sales Invoices remain "Unpaid" in the accounting ledger even though the Debt Collection task shows them as paid.
- Accounts Receivable report shows invoices as outstanding even after payment.
- The task's internal tracking (open_invoices table) diverges from ERPNext's accounting reality.
- Financial reports become unreliable.
- If Standard Buying prices are populated and real transactions begin, this creates a growing accounting discrepancy.

**Confidence:** High — directly proven by code logic. The bug is unambiguous.

**Fix:** Either (a) save the allocation amounts before zeroing, or (b) build the PE references in the first loop before zeroing allocated_now.

#### Other Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S2-F01 | **B-01** (above) — PE has no invoice references | **CRITICAL BUG** | High |
| S2-F02 | **FIFO sorts by `sales_invoice` name (alphabetical), not by invoice date.** Requirements §6.6.2 says "oldest invoices first." ERPNext invoice naming is typically chronological (e.g., `ACC-SINV-2026-00001`), so alphabetical sort on name *likely* matches chronological order. But this is not guaranteed if naming patterns change. | Minor risk — likely functionally correct | Medium |
| S2-F03 | **PE auto-submitted** (line 63: `pe.submit()`). Doc 16 §8 says "The Accounting team submits these auto-created Payment Entries." The script bypasses this review step. | Doc/prod difference — possibly intentional | High |
| S2-F04 | **`paid_to` hardcoded as `"Cash - Inmed"`** regardless of payment method. If payment method is "Bank Transfer" or "Card", the paid_to should be the relevant bank/card account. This causes all customer receipts to post to the Cash account in the GL. | **BUG B-12** | High |
| S2-F05 | **Company hardcoded as `"InMED"`.** Correct for this single-company deployment, but not portable. | Accepted deviation | High |
| S2-F06 | **No Distribute Payment task created after payment.** The disabled script S5 would have created one. The manual describes this step. Without it, there is no tracking of physical payment handling. | **Gap — see B-02** | High |
| S2-F07 | **Auto-completion when outstanding reaches 0.** Matches Doc 16 §6.10 ("Task auto-completes"). Correct. | Matches documentation | High |

---

### S3 — Task-after-save-debt-closure.py

**Schema name:** `Task-after-save-debt-closure`
**Type:** DocType Event — After Save | **Enabled:** Yes | **Lines:** 101

#### Behavior Summary — Part 1: Debt Collection → Debt Closure Approval

When a **Debt Collection** task transitions to `Completed`:

1. Sums `paid_amount` across all `open_invoices` rows.
2. Collects invoice names and payment entry names.
3. Builds a text description with customer, total paid, invoices, PEs, and payment history.
4. Creates a new Task with `task_kind = "Debt Closure Approval"`.
5. Copies `payment_history` and `open_invoices` child table rows to the new task.
6. Assigns to the first 2 users from a **hardcoded** `APPROVED_USERS` list.

#### Behavior Summary — Part 2: Debt Closure Approval → Profit Calculation

When a **Debt Closure Approval** task transitions to `Completed`:

1. **Permission check:** Only `APPROVED_USERS` or Administrator can complete.
2. Gets the linked `sales_invoice`.
3. For each item in the invoice, calculates `profit = (selling_rate × qty) - (buying_rate × qty)`.
4. Buying rate sourced from Item Price with `price_list = "Standard Buying"`.
5. Sets `custom_case_profit` on the task.
6. If `dispatch_case` is linked, sets `profit` on the Dispatch Case.
7. Warns if any items have missing Standard Buying prices.

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S3-F01 | **Hardcoded APPROVED_USERS** (4 email addresses). If team members change, this script must be edited and redeployed. No admin-configurable mechanism. | **BUG B-09** — maintenance risk | High |
| S3-F02 | **Throw message says "Only Norayr, Sevak, or Levon"** but APPROVED_USERS also includes `vahe.muselimyan@gmail.com`. Vahe can complete the task but is not mentioned in the error message shown to other users. | Cosmetic bug | High |
| S3-F03 | **Profit uses only one invoice** (`doc.sales_invoice`). But Debt Collection tasks can track multiple invoices in `open_invoices`. Only the last-linked invoice gets profit calculated. For multi-case customers, profit is incomplete. | **BUG B-07** | High |
| S3-F04 | **Profit = selling − Standard Buying price.** Does not account for landed costs, actual purchase prices, exchange rate variances, or item-specific cost. This is a rough margin estimate, not accounting profit. | Accepted limitation — documented deployment summary lists it as requiring Standard Buying prices | Medium |
| S3-F05 | **Dispatch Case profit set only from first `open_invoices` row's `dispatch_case`** (line 43). If multiple DCs, only first gets profit. | Related to B-07 | High |
| S3-F06 | **"Debt Closure Approval" task kind is undocumented.** Not in Doc 10 task kind list. Not in Doc 16 §11 task kinds reference. | **DOC GAP D-01** | High |
| S3-F07 | **Assignment to first 2 APPROVED_USERS** — currently `ghahramanyann@gmail.com` and `karapetyansev@gmail.com`. This is a hardcoded business decision. | Undocumented decision | High |

---

### S4 — Task-after-save-advance-payment.py

**Schema name:** `Task-after-save-advance-payment`
**Type:** DocType Event — After Save | **Enabled:** Yes | **Lines:** 36

#### Behavior Summary

1. Only acts on `task_kind == "Payment Received"` transitioning to `Completed`.
2. Only acts when `new_payment_amount > 0`.
3. Creates Payment Entry (Receive, Customer, no invoice references — correct for an advance).
4. **Inserts but does NOT submit** the PE.
5. If `dispatch_case` is linked, **overwrites** `prepaid_amount` and `prepaid_payment_entry` on the Dispatch Case.
6. If an existing non-completed Debt Collection task exists for this customer, adds the payment amount to `available_advance_credit`.

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S4-F01 | **PE not submitted** — only `pe.insert()`, no `pe.submit()`. Compare with S2 which auto-submits. Doc 16 §8 says Accounting submits auto-created PEs. This appears to be intentionally leaving the PE as draft for Accounting review. But it's inconsistent with S2. | Inconsistency — possibly intentional | High |
| S4-F02 | **`prepaid_amount` OVERWRITES instead of accumulating** (line 32: `{"prepaid_amount": doc.new_payment_amount, ...}`). If a customer makes two partial advance payments for the same Dispatch Case, the second one replaces the first. Requirements §6.6.2 explicitly allow partial upfront payments. | **BUG B-03** | High |
| S4-F03 | **`prepaid_payment_entry` also overwrites.** Same issue — only the last PE link is kept. Previous PE link is lost. | Related to B-03 | High |
| S4-F04 | **`available_advance_credit` correctly accumulates** (line 35-36: `current_credit + doc.new_payment_amount`). Good. But this field is on the Debt Collection task. If no Debt Collection task exists yet, the credit is not tracked centrally — it's only on the draft PE and the DC's prepaid_amount. | Partial implementation | High |
| S4-F05 | **`paid_to` hardcoded as `"Cash - Inmed"`.** Same issue as S2-F04. | **BUG B-12** | High |
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
| S5-F01 | **DISABLED in production.** No Distribute Payment tasks are created. This contradicts multiple documentation sources. | **BUG B-02** | High |
| S5-F02 | **Even if enabled, assigns to Directors.** Doc 16 §6.11 says "Default assignee: Finance Team." The script would assign to the wrong role. | Bug (latent — only relevant if script is re-enabled) | High |
| S5-F03 | **Doc references describing this feature as active:** (1) Doc 16 §6.11 entire section. (2) Manual `debt-collection-and-payment.md` Steps 3 and 6. (3) Manual `daily-reporting-checks.md` Directors Check 4. (4) Quick reference flowchart in manual. All describe Distribute Payment as an active part of the flow. | **DOC GAP D-04** | High |
| S5-F04 | **Requirements §6.6.2** states: "the internal Distribute Payment control step is created per payment receipt." This requirement is currently NOT met. | Requirements violation | High |

---

### S6 — Sales-Invoice-after-submit-tender-update.py

**Schema name:** `Sales-Invoice-after-submit-tender-update`
**Type:** DocType Event — After Submit | **Enabled:** Yes | **Lines:** 25

#### Behavior Summary

1. Only acts when `doc.docstatus == 1` (submitted).
2. Gets active Tender Agreements where `hospital == doc.customer`.
3. For each invoice item, iterates all matching tenders.
4. If `tender_item.item_code == item_code`: increments `supplied_quantity`, recalculates `remaining_quantity`.
5. Saves the tender and **calls `frappe.db.commit()` inside the loop**.

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S6-F01 | **Multiple-tender double-counting.** If a customer has 2+ active tenders containing the same item, the script deducts the full invoice qty from EACH tender. Example: Customer has Tender A (item X, won=100) and Tender B (item X, won=50). Invoice has item X qty=10. After submission: Tender A supplied=10, Tender B supplied=10. Both tenders think they supplied 10 units, but only 10 were actually sold. | **BUG B-04** | High |
| S6-F02 | **No cancellation handler.** If a Sales Invoice is cancelled, `supplied_quantity` is never decremented. Tender tracking becomes permanently inflated. The only fix would be manual editing of the Tender Agreement. | **BUG B-05** | High |
| S6-F03 | **No over-supply warning.** Deployment summary says "System warns if quantity exceeds remaining tender quantity." The script does not implement any warning. `remaining_quantity` silently goes negative. | Doc/prod difference | High |
| S6-F04 | **`frappe.db.commit()` inside loop** (line 25). This commits the transaction for each tender independently, breaking atomicity. If the script errors mid-way (e.g., on the 2nd tender of 3), the 1st tender is already committed but the 3rd is not. Also, this commits within the Sales Invoice's own transaction, which can cause data integrity issues if the invoice submission later fails for another reason. | **BUG B-13** | High |
| S6-F05 | **Customer matching assumes invoice customer IS the hospital.** Tender Agreement has `hospital` field linking to Customer. For doctor-clients who operate at a hospital, the invoice's `customer` is the doctor, not the hospital. The tender would not match. Whether this is a bug depends on business intent — if tenders are only for hospital-type customers, it's correct. | Needs business clarification | Medium |
| S6-F06 | **`tender_price` field exists on Tender Agreement Item but is never used by this script.** The script only updates quantities. Tender pricing is not enforced at invoice submission — the invoice can have any rate. | Feature gap — per deployment summary, "Accountant can choose between tender price or standard price" | Medium |

---

### S7 — Tender-Agreement-before-save.py

**Schema name:** `Tender-Agreement-before-save`
**Type:** DocType Event — Before Save | **Enabled:** Yes | **Lines:** 22

#### Behavior Summary

1. Recalculates `remaining_quantity = won_quantity - supplied_quantity` for each item row.
2. Auto-sets status based on date range:
   - If status is already "Draft": skip auto-status.
   - If `today < valid_from`: status → "Draft".
   - If `valid_from <= today <= valid_to`: status → "Active".
   - If `today > valid_to`: status → "Expired".

#### Findings

| ID | Finding | Classification | Confidence |
|----|---------|---------------|------------|
| S7-F01 | **"Closed" status is overridden on save.** If a user manually sets status to "Closed" (to end a tender early) and saves, the auto-status logic will change it back to "Active" (if within date range) or "Draft"/"Expired". The "Closed" status cannot persist through a save unless the dates also put it outside the active range. | **BUG B-06** | High |
| S7-F02 | **Status "Draft" is used both as initial state and as "before start date" state.** If someone creates a tender with future dates, saves it as "Draft" (default), then the auto-status check at line 14 (`if doc.status == "Draft": pass`) skips the date logic. But if they later change a field and save again when the date is past valid_from, the status is still "Draft" from the first save, so auto-status is skipped again. The tender stays "Draft" forever unless someone manually changes the status first. | Design confusion — needs clarification | Medium |
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
| X1-F01 | **Debt task assignment: Finance Team.** Scheduler (S1) assigns to Directors. Dispatch flow assigns to Finance. Same `task_kind`. If scheduler creates first, the task is assigned to a director. When dispatch flow later finds it and appends an invoice, it doesn't reassign. The director keeps a task that Finance should be working on. | **Part of B-08** | High |
| X1-F02 | **Subject mismatch.** Scheduler: `"Debt Collection — {name}"` (em-dash). Dispatch flow: `"Debt Collection: {name}"` (colon). Minor but could cause confusion in task lists. | Cosmetic | High |
| X1-F03 | **Outstanding = `grand_total - prepaid_amount`.** This is a DC-local calculation, not GL-based. Correct for determining whether a debt task is needed, but it's a parallel truth to the GL-based debt in S1. | Design choice — two tracking mechanisms | High |
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
│  Assignment: Finance (X1) or Director (S1)                     │
│                                                                 │
│  Finance fills: new_payment_amount + method + reference → Save │
│                                                                 │
│  S2 fires (Before Save):                                       │
│    → FIFO allocation across open_invoices                      │
│    → Creates PE (BUG: no invoice refs)                         │
│    → PE auto-submitted                                         │
│    → If outstanding=0: task auto-completes                     │
│                                                                 │
│  S5 would fire (DISABLED):                                     │
│    → Would create Distribute Payment task                      │
│                                                                 │
│  S3 fires (After Save, on completion):                         │
│    → Creates Debt Closure Approval task                        │
│    → Assigns to hardcoded approved users                       │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│              Debt Closure Approval Task                         │
│                                                                 │
│  S3 fires (After Save, on completion):                         │
│    → Permission check (hardcoded users)                        │
│    → Profit calculation from single SI                         │
│    → Sets profit on Dispatch Case                              │
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
│    → Sets DC prepaid_amount (OVERWRITES — BUG B-03)            │
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
│  → If debt > threshold: create/update Debt Collection task     │
│    (assigned to DIRECTOR — different from X1)                  │
│  → Does NOT populate open_invoices table                       │
│  → Conflicts possible with X1-created tasks (B-08)             │
└─────────────────────────────────────────────────────────────────┘
```

### Tender Flow

```
┌────────────────────────────────────┐       ┌──────────────────────────────┐
│  Tender Agreement saved (S7)       │       │  Sales Invoice submitted (S6)│
│  → Recalculate remaining_qty      │       │  → Find active tenders       │
│  → Auto-set status by date        │       │  → Deduct supplied_qty       │
│  → BUG: "Closed" overridden (B-06)│       │  → BUG: double-count (B-04) │
└────────────────────────────────────┘       │  → BUG: no reversal (B-05)  │
                                             │  → BUG: commit in loop(B-13)│
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
| 1 | Debt threshold alerts | Directors must be alerted via Debt Collection task (req §6.6.1) | Scheduler creates Debt Collection tasks for directors | **Yes** | Match | High |
| 2 | Debt calculation basis | Net receivable: outstanding minus advances (req §6.6.2 recommended) | Scheduler uses GL Entry (debit-credit), which includes advances | **Yes** | Match | High |
| 3 | Debt Collection task per customer | One active task per customer (Doc 16 §6.10) | Both scheduler and dispatch flow enforce one-per-customer | **Yes** | Match | High |
| 4 | Debt Collection assignment | Finance Team (Doc 16 §6.10) | Scheduler → Directors; Dispatch flow → Finance Team | **Partial** | Two entry points, two assignees — B-08 | High |
| 5 | Open invoices table on Debt task | Shows all outstanding invoices (Doc 16 §6.10) | Dispatch flow populates it; scheduler does NOT | **Partial** | Scheduler path leaves task without invoice detail | High |
| 6 | FIFO payment allocation | Oldest invoices first (req §6.6.2, manual Step 2) | By invoice name alphabetically (likely chronological) | **Approximate** | B-11 — works if naming is chronological | Medium |
| 7 | FIFO override (manual allocation) | Finance can override (Doc 16 §6.10) | Not implemented — only automatic FIFO | **No** | Feature gap | High |
| 8 | Payment Entry auto-created | Auto-created with specified allocation (Doc 16 §6.10, §8) | PE created but WITHOUT invoice references (B-01) | **No** | CRITICAL BUG | High |
| 9 | PE submitted by Accounting | Accounting team submits (Doc 16 §8) | Debt Collection PE: auto-submitted. Advance PE: draft | **No** | Inconsistency | High |
| 10 | Distribute Payment task | Created per payment (req §6.6.2, Doc 16 §6.11, manual Steps 3/6) | Script DISABLED — no tasks created | **No** | B-02 — requirements violation | High |
| 11 | Distribute Payment assigned to Finance | Doc 16 §6.11 | Script assigns to Directors (but script is disabled anyway) | **No** | Latent bug in disabled code | High |
| 12 | Advance payment (no invoice) | Customer advance PE, no invoice link (Doc 16 §6.12) | Correct — PE has no references | **Yes** | Match | High |
| 13 | Advance updates DC prepaid_amount | Amount noted on case (Doc 16 §6.12) | Set on DC, but OVERWRITES instead of accumulating (B-03) | **Partial** | Bug for multiple partial advances | High |
| 14 | Advance updates Debt Collection credit | Reflected on Debt Collection task (Doc 16 §6.12) | Adds to `available_advance_credit` | **Yes** | Match | High |
| 15 | Outstanding = 0 → case Closed | Doc 16 §6.9, §6.10, manual Step 5 | Implemented in X1 (line 274-275) | **Yes** | Match | High |
| 16 | Debt Closure Approval | Not documented | Task created on Debt Collection completion (S3) | **N/A** | D-01 — undocumented feature | High |
| 17 | Profit calculation | Not in any numbered doc | Calculated on Debt Closure Approval completion (S3) | **N/A** | Undocumented feature | High |
| 18 | Tender qty auto-update | SI submission updates tender supplied/remaining (deployment summary) | Implemented in S6 | **Yes** | Match | High |
| 19 | Tender over-supply warning | "System warns if quantity exceeds remaining" (deployment summary) | Not implemented — no warning | **No** | Doc/prod gap | High |
| 20 | Tender cancellation reversal | Not explicitly documented | Not implemented — quantities permanently consumed | **N/A** | Missing feature (B-05) | High |
| 21 | Tender status auto-set | Auto-updates by dates (deployment summary) | Implemented in S7, but "Closed" is overridden (B-06) | **Partial** | Bug | High |
| 22 | Financial field visibility | Non-financial roles cannot see prices (Doc 16 §12) | Client-side hiding only (B-10) | **Partial** | No server enforcement | High |
| 23 | PE cancellation re-opens task | "Outstanding balance will increase back" (cancellation manual) | No script handles PE cancellation events | **No** | D-06 — documented behavior doesn't exist | High |
| 24 | Scheduled debt check | Not documented in any numbered doc | Runs via scheduler, uses GL entries | **N/A** | D-02 — undocumented mechanism | High |
| 25 | Tender system documentation | "No numbered doc exists" (docs-overview) | Only deployment summary describes it | **N/A** | D-03 — acknowledged gap | High |
| 26 | Lost/damaged billing | Doc 16 §9A — bill at same rate | Not implemented — only `used_qty` invoiced | **No** | Known gap — tracked in doc | High |
| 27 | Unallocated advance recording | Req §6.6.2 — record as customer advance | Advance PE created without invoice refs — correct | **Yes** | Match | High |
| 28 | No time limit for advances | Req §6.6.2 | No expiry logic implemented — correct | **Yes** | Match | High |

---

## 7. Bug and Risk Register

### Critical

| ID | Title | Script | Impact | Confidence | Evidence |
|----|-------|--------|--------|------------|----------|
| **B-01** | Payment Entry created without invoice references | S2 lines 28-33 vs 54-60 | GL ledger never reconciles payments against specific invoices. Accounts Receivable shows invoices as unpaid even after payment. Growing accounting discrepancy. | **High** | Code logic: `allocated_now` is zeroed at line 33, then checked at line 55 — always false. |

### High

| ID | Title | Script | Impact | Confidence | Evidence |
|----|-------|--------|--------|------------|----------|
| **B-02** | Distribute Payment script DISABLED | S5 | Requirements §6.6.2 is violated. Physical payment handling step doesn't exist. Documentation describes it as active. | **High** | Schema: `disabled: 1` |
| **B-03** | Advance prepaid_amount overwrites | S4 line 32 | Second partial advance payment erases record of first. Prepaid amount on DC is wrong. Outstanding calculation at invoice time will be wrong. | **High** | Code: `set_value` with dict replaces value |
| **B-04** | Tender double-counts across multiple active tenders | S6 lines 17-24 | If customer has 2+ active tenders with same item, qty deducted from each. Overstates supply, understates remaining. | **High** | Code: nested loop iterates ALL tenders |
| **B-05** | No tender reversal on invoice cancellation | S6 | Cancelled invoices leave tender quantities permanently inflated. No `After Cancel` or `On Cancel` handler exists. | **High** | No cancellation handler in schema |

### Medium

| ID | Title | Script | Impact | Confidence | Evidence |
|----|-------|--------|--------|------------|----------|
| **B-06** | Tender "Closed" status overridden on save | S7 lines 14-22 | Cannot close a tender early within its date range. Manual status change is lost on next save. | **High** | Code: only "Draft" skips auto-status |
| **B-07** | Profit calculation only uses one invoice | S3 lines 85-99 | Multi-invoice customers get incomplete profit. DC profit may be from wrong invoice. | **High** | Code: `doc.sales_invoice` is singular |
| **B-08** | Dual debt task creation paths with different assignees/data | S1 + X1 | Scheduler creates for Directors without invoice detail. Dispatch flow creates for Finance with invoice detail. If both create, or one creates and the other updates, inconsistent assignment and data. | **High** | Code comparison of both scripts |
| **B-10** | Financial visibility client-side only | C1 | Non-financial users can access price/payment data via API, reports, dev tools. No data leak risk from code — but no enforcement either. | **High** | Code: no server-side permission script |
| **B-12** | `paid_to` hardcoded as "Cash - Inmed" | S2 line 52, S4 line 27 | All customer receipts post to Cash account regardless of payment method. Bank Transfer and Card payments mislabeled in GL. | **High** | Code: hardcoded string |
| **B-13** | `frappe.db.commit()` inside loop in tender update | S6 line 25 | Breaks transaction atomicity. Partial commits if error mid-loop. May cause issues if SI submission itself fails after partial tender updates. | **High** | Code: commit inside for loop |

### Low

| ID | Title | Script | Impact | Confidence | Evidence |
|----|-------|--------|--------|------------|----------|
| **B-09** | Hardcoded user emails in debt closure | S3 lines 14-18 | Maintenance risk — team changes require code changes. Works for now. | **High** | Code: 4 emails hardcoded |
| **B-11** | FIFO sorts by invoice name not date | S2 line 22 | Likely works correctly if invoice naming is chronological (standard ERPNext behavior). Could fail if naming convention changes. | **Medium** | Code: `sorted(..., key=lambda r: r.sales_invoice)` |

---

## 8. Reports, Custom Fields, and Supporting Artifacts

### 8.1 Reports Relevant to Group 3

16 reports were found in the schema. Notable observations:

| Observation | Reports Affected | Concern |
|------------|-----------------|---------|
| **Apparent duplicates** with different naming conventions | `RPT - Clients Exceeding Debt Threshold` vs `RPT — Risk — Debt Threshold Exceeded` | Same concept, two reports. One uses hyphens, other uses em-dashes. May query the same data differently. |
| **Apparent duplicates** | `RPT - Unallocated Customer Advances` vs `RPT — Receivables — Unallocated Advances` | Same concept. Both are Query Reports on Payment Entry. |
| **Apparent duplicates** | `RPT - Prepaid Orders Awaiting Delivery` (ref: Dispatch Case) vs `RPT — Ops — Prepaid Orders Awaiting Delivery` (ref: Sales Order) | Similar name, different source DocTypes. May show different data. |
| **All enabled** | All 16 reports | None are disabled. Good. |
| **All Query Reports** | All 16 | Custom SQL — queries not inspectable from schema alone. Require live testing. |
| **B-01 impact on reports** | Debt Status Board, Unpaid Invoices, Unallocated Advances | Because PEs lack invoice references, reports querying ERPNext's payment allocation will show incorrect data. Invoices appear unpaid; payments appear unallocated. |

### 8.2 Custom Fields Relevant to Group 3

#### On Customer

| Fieldname | Type | Purpose |
|-----------|------|---------|
| `debt_threshold_amd` | Currency | Per-customer debt threshold in AMD. Used by S1. |
| `is_provisional` | Check | Provisional customer flag. Not used by any Group 3 script. |

#### On Task (payment/debt related)

| Fieldname | Type | Purpose | Used By |
|-----------|------|---------|---------|
| `task_kind` | Select | Categorizes task type. Options include: Debt Collection, Distribute Payment, Payment Received, Invoice preparation / create invoice, Debt Closure Approval, and others. | All scripts |
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

#### On Sales Order (prepayment tracking — not used by Group 3 scripts)

| Fieldname | Type | Purpose |
|-----------|------|---------|
| `is_prepaid` | Check | Marks order as prepaid. |
| `prepayment_required_amount_amd` | Currency | Required advance amount. |
| `prepayment_payment_entry` | Link → PE | Links to advance PE. |

Note: These Sales Order fields are NOT used by any Group 3 script. They appear to be from an earlier design (pre-Dispatch Case) or for a parallel flow. The current advance payment flow uses Dispatch Case fields, not Sales Order fields. These may be dead fields.

### 8.3 Custom DocTypes

#### Tender Agreement

- **Naming:** By `tender_name` field (user-entered, unique).
- **Not submittable** — uses status field instead of docstatus.
- **Fields:** tender_name, hospital (Customer link), valid_from, valid_to, status (Draft/Active/Expired/Closed), items (child table), notes.
- **Permissions:** Accounting can CRUD. Directors can CRUD + Delete. System Manager full access. Order Creating can read only.
- **No workflow** attached.
- **No numbered documentation** — only deployment summary.

#### Tender Agreement Item

- **Child table** of Tender Agreement.
- **Fields:** item_code, item_name (fetched), tender_price, won_quantity, supplied_quantity, remaining_quantity (read-only).
- **`tender_price` is stored but never enforced** — no script checks or applies it during invoicing.

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
| Q-04 | Are any Tender Agreements in "Closed" status currently? Does saving them revert status? | Need to check live data. | Medium |
| Q-05 | Do the duplicate reports (e.g., two debt threshold reports) show the same data? | Need to run both reports and compare. | Medium |
| Q-06 | Are Sales Order prepaid fields (`is_prepaid`, etc.) used anywhere in the UI or other scripts? | Need to search all scripts comprehensively and check UI forms. | Low |
| Q-07 | Does `frappe.db.commit()` inside S6 actually cause issues when invoice submission has other After Submit hooks? | Need to test with real invoice submission. | Medium |
| Q-08 | How many customers currently have multiple active tenders? (B-04 impact) | Need to query production data. | Medium |
| Q-09 | What happens to the Debt Collection task when a PE is cancelled? (D-06) | Need to test cancellation flow. | High |
| Q-10 | Is the `available_advance_credit` field displayed on the Debt Collection task form? Does Finance use it? | Need to check UI. | Medium |

---

## 10. Recommendations

### Critical — Fix Before Go-Live

| # | Action | Bug/Gap | Effort |
|---|--------|---------|--------|
| R-01 | **Fix PE invoice reference bug.** In S2, save allocation amounts before zeroing `allocated_now`, then use saved amounts to build PE references. | B-01 | Small code fix |
| R-02 | **Decide on Distribute Payment.** Either re-enable S5 (fixing the assignment to Finance Team) or remove all documentation references. If removed, update: Doc 16 §6.11, manual §Steps 3/6, daily checks §Check 4, requirements §6.6.2. | B-02, D-04 | Decision + doc update |
| R-03 | **Fix prepaid_amount accumulation.** Change S4 line 32 from overwrite to increment: `prepaid_amount = (current_prepaid or 0) + doc.new_payment_amount`. Also handle `prepaid_payment_entry` as a comma-separated list or separate child table. | B-03 | Small code fix |

### High — Fix Soon After Go-Live

| # | Action | Bug/Gap | Effort |
|---|--------|---------|--------|
| R-04 | **Fix tender double-counting.** In S6, break after the first matching tender for each item, or require items to be unique across active tenders for the same customer. | B-04 | Small code fix |
| R-05 | **Add tender cancellation handler.** Create a new server script on Sales Invoice → After Cancel that reverses the supplied_quantity changes made by S6. | B-05 | New script (~30 lines) |
| R-06 | **Fix tender "Closed" status preservation.** In S7, add `"Closed"` to the skip condition: `if doc.status in ("Draft", "Closed"): pass`. | B-06 | 1-line fix |
| R-07 | **Fix `paid_to` account mapping.** In S2 and S4, map payment method to the correct account: Cash → Cash - Inmed, Bank Transfer → Bank account, Card → Card account. | B-12 | Small code fix |
| R-08 | **Remove `frappe.db.commit()` from S6 loop.** The tender saves already persist changes; the explicit commit is unnecessary and harmful. | B-13 | 1-line removal |
| R-09 | **Document Debt Closure Approval.** Add to Doc 16 §11 task kinds reference and create an operational description in §6 task chain. | D-01 | Doc update |
| R-10 | **Document scheduled debt collection.** Add to requirements or Doc 16 explaining the dual mechanism: scheduler (threshold alerts for directors) vs dispatch flow (invoice tracking for finance). | D-02 | Doc update |

### Medium — Plan For Next Iteration

| # | Action | Bug/Gap | Effort |
|---|--------|---------|--------|
| R-11 | **Fix profit calculation for multi-invoice customers.** In S3, iterate all invoices in `open_invoices` and sum profit across all. Set profit on each linked Dispatch Case. | B-07 | Medium code change |
| R-12 | **Clarify dual debt task paths.** Decide whether the scheduler and dispatch flow should create the same task kind or separate kinds (e.g., "Debt Alert" vs "Debt Collection"). Document the decision. | B-08 | Design decision |
| R-13 | **Add server-side financial field protection.** Create a server script that strips financial fields from API responses for non-financial roles, or use ERPNext's field-level permissions. | B-10 | Medium effort |
| R-14 | **Replace hardcoded user emails.** In S3, use role-based lookup (similar to S1's director lookup) instead of hardcoded emails. | B-09 | Small code fix |
| R-15 | **Create Tender Agreement numbered documentation.** | D-03 | Doc creation |
| R-16 | **Add tender over-supply warning.** Per deployment summary promise. | S6-F03 | Small code addition |
| R-17 | **Clean up duplicate reports.** Consolidate or differentiate the 3 pairs of apparently-duplicate reports. | §8.1 | Investigation + possible removal |
| R-18 | **Fix FIFO sort to use invoice date** instead of invoice name. | B-11 | 1-line fix |
| R-19 | **Add PE cancellation handler** or update cancellation manual to reflect actual behavior. | D-06 | New script or doc fix |
| R-20 | **Investigate Sales Order prepaid fields.** Determine if they are dead fields from pre-Dispatch Case design. If dead, consider removing to avoid confusion. | §8.2 | Investigation |

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
| B-01 | `deploy/test/work/server/Task-before-save-payment-recording.py` lines 28-33 vs 54-60 |
| B-02 | `deploy/test/schema/server-scripts.json` — `disabled: 1` for `Payment Entry-after-submit-distribute-payment` |
| B-03 | `deploy/test/work/server/Task-after-save-advance-payment.py` line 32 |
| B-04 | `deploy/test/work/server/Sales-Invoice-after-submit-tender-update.py` lines 17-24 |
| B-05 | `deploy/test/schema/server-scripts.json` — no After Cancel handler for Sales Invoice |
| B-06 | `deploy/test/work/server/Tender-Agreement-before-save.py` lines 14-22 |
| B-07 | `deploy/test/work/server/Task-after-save-debt-closure.py` lines 85-99 |
| B-08 | `deploy/test/work/server/Scheduled-debt-collection.py` lines 108-118 vs `Task-after-save-dispatch-flow.py` lines 143-173 |
| B-09 | `deploy/test/work/server/Task-after-save-debt-closure.py` lines 14-18 |
| B-10 | `deploy/test/work/client/Dispatch Case-Price Visibility.js` — no matching server script |
| B-11 | `deploy/test/work/server/Task-before-save-payment-recording.py` line 22 |
| B-12 | `deploy/test/work/server/Task-before-save-payment-recording.py` line 52; `Task-after-save-advance-payment.py` line 27 |
| B-13 | `deploy/test/work/server/Sales-Invoice-after-submit-tender-update.py` line 25 |
| D-01 | `docs/16-unified-dispatch-flow.md` §11 — "Debt Closure Approval" not listed |
| D-02 | `docs/16-unified-dispatch-flow.md` — no mention of scheduler-based debt checking |
| D-03 | `docs/docs-overview.md` — "no numbered doc exists for Tender Agreements" |
| D-04 | `docs/manual/debt-collection-and-payment.md` Steps 3/6 vs schema `disabled: 1` |
| D-05 | `deploy/test/work/server/Task-after-save-advance-payment.py` line 30 — `insert()` only |
| D-06 | `docs/manual/cancellation-and-corrections.md` "Payment Entry — cancellation" section |

---

*End of Group 3 Audit Report*
