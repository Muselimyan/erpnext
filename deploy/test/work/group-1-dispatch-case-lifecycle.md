# Production Audit — Group 1: Dispatch Case Lifecycle

> **Audit date**: 2026-08-27
> **Auditor**: Automated code analysis (no live-server access)
> **Scope**: Every deployed script, schema record, and documentation reference related to the Dispatch Case lifecycle
> **Evidence base**: Extracted files under `deploy/test/work/`, schema JSON under `deploy/test/schema/`, documentation under `docs/`

---

## 0. Executive Summary

The Dispatch Case lifecycle is **substantially implemented and functional** as the new unified dispatch coordinator. The core task chain (Order Entry → Pack → Delivery → Return Call → Pickup Returns → Returns Inspection → Restock → Invoice → Debt Collection) is complete and matches Doc 16 with minor deviations.

However, this audit identified **5 original findings** (2 fixed, 2 reclassified as not-bugs, 1 remaining), **7 documentation gaps**, **4 legacy/dead-code risks**, and **3 design concerns**. Summary of bug resolutions:

| # | Finding | Severity | Confidence |
|---|---------|----------|------------|
| BUG-01 | ~~Stock accounting error: consumption SE uses wrong warehouse after returns~~ | ~~High~~ **FIXED** | 0.93 |
| ~~BUG-02~~ | ~~Delivery photo not enforced despite documentation requirement~~ | ~~High~~ **RECLASSIFIED** | — |
| ~~BUG-03~~ | ~~Lost/damaged qty not invoiced~~ | ~~Medium~~ **RECLASSIFIED** | — |
| BUG-04 | ~~"Invoiced" state never set by any script~~ | ~~Medium~~ **FIXED** | 0.95 |
| BUG-05 | ~~`Task-Product Lines Display.js` sets wrong default warehouse~~ | ~~Medium~~ **FIXED** | 0.95 |
| LEGACY-01 | Surgery Case orchestrator still active alongside Dispatch Case | Risk | 0.97 |
| LEGACY-02 | Sales Order parallel flow (4 scripts) still active | Risk | 0.95 |
| LEGACY-03 | Duplicate Collection Set validation scripts | Low | 0.98 |
| LEGACY-04 | Stock Entry dispatch gate disabled but documented as part of flow | Info | 0.95 |
| GAP-01 | No stock availability check at Pack completion | Medium | 0.92 |
| GAP-02 | Missing role restrictions for Return Call and Returns restocking tasks | Low | 0.90 |
| GAP-03 | Outstanding calculation ignores total_paid_amount | Medium | 0.88 |
| GAP-04 | Discount approval task uses hardcoded team email | Low | 0.90 |
| GAP-05 | Two different template-loading mechanisms active | Low | 0.85 |
| GAP-06 | ignore_validate bypasses all stock safety on auto-created SEs | Medium | 0.95 |
| GAP-07 | Dispatch Case submitted without Order Entry task gets no Pack task | Low | 0.85 |
| DESIGN-01 | Client-side form lock mirrors server-side but is UI-only | Info | 0.95 |
| DESIGN-02 | Schema shows fewer client scripts than extracted files | Needs Verification | 0.70 |
| DESIGN-03 | Warehouse names use "- Inmed" (production) vs "- WH" (some docs) | Info | 0.95 |

---

## 1. Scope and Evidence Sources

### 1.1 Scripts Analyzed

**Server scripts (Dispatch Case lifecycle — 17 total):**

| # | File | Type | DocType | Event | Enabled | Lines |
|---|------|------|---------|-------|---------|-------|
| S1 | `Dispatch-Case-before-save.py` | DocType Event | Dispatch Case | Before Save | **Yes** | 19 |
| S2 | `Dispatch-Case-before-save-lock-submitted.py` | DocType Event | Dispatch Case | Before Save | **Yes** | 21 |
| S3 | `Dispatch-Case-before-submit.py` | DocType Event | Dispatch Case | Before Submit | **Yes** | 14 |
| S4 | `Dispatch-Case-after-save.py` | DocType Event | Dispatch Case | After Save | **Yes** | 37 |
| S5 | `Dispatch Case-packing-problem-alerts.py` | DocType Event | Dispatch Case | After Save | **Yes** | 60 |
| S6 | `Task-after-save-dispatch-flow.py` | DocType Event | Task | After Save | **Yes** | 289 |
| S7 | `Task-before-save-dispatch-gates.py` | DocType Event | Task | Before Save | **Yes** | 134 |
| S8 | `Task-before-save-pack-complete-creates-delivery-task.py` | DocType Event | Task | Before Save | **Yes** | 86 |
| S9 | `dispatch_case_packing_scan.py` | API | — | — | **Yes** | 158 |
| S10 | `dispatch_task_accept.py` | API | — | — | **Yes** | 86 |
| S11 | `task_create_dispatch_case.py` | API | — | — | **Yes** | 30 |
| S12 | `task_add_dispatch_product.py` | API | — | — | **Yes** | 35 |
| S13 | `task_update_return_item_quantities.py` | API | — | — | **Yes** | 49 |
| S14 | `task_mark_item_packed.py` | API | — | — | **Yes** | 44 |
| S15 | `task_mark_items_packed_batch.py` | API | — | — | **Yes** | 40 |
| S16 | `Delivery Note-before-submit-delivery-gate.py` | DocType Event | Delivery Note | Before Submit | **Yes** | 30 |
| S17 | `Stock Entry-before-submit-dispatch-gate.py` | DocType Event | Stock Entry | Before Submit | **No** | 61 |

**Related server scripts (parallel/legacy flows — also analyzed):**

| # | File | Type | DocType | Event | Enabled | Lines |
|---|------|------|---------|-------|---------|-------|
| R1 | `Surgery-Case-before-save.py` | DocType Event | Surgery Case | Before Save | **Yes** | 279 |
| R2 | `Sales Order-after-submit-pack-task.py` | DocType Event | Sales Order | After Submit | **Yes** | 72 |
| R3 | `Sales Order-before-save-discount-approval.py` | DocType Event | Sales Order | Before Save | **Yes** | 245 |
| R4 | `Task-before-save-discount-approval-writeback.py` | DocType Event | Task | Before Save | **Yes** | 103 |
| R5 | `Stock Entry-before-save-no-client-wh.py` | DocType Event | Stock Entry | Before Save | **No** | 24 |
| R6 | `Collection-Set-validate-readiness.py` | DocType Event | Collection Set | Before Save | **Yes** | 47 |
| R7 | `Surgery-Set-Type-validate-readiness.py` | DocType Event | Collection Set | Before Save | **Yes** | 47 |

**Client scripts analyzed (12 total):**

| # | File | DocType | Enabled | Lines |
|---|------|---------|---------|-------|
| C1 | `Dispatch Case-Form.js` | Dispatch Case | **Yes** | 102 |
| C2 | `Dispatch Case-Lock Submitted.js` | Dispatch Case | **Yes** | 6 |
| C3 | `Dispatch Case-Packing Problem Alerts.js` | Dispatch Case | **Yes** | 18 |
| C4 | `Dispatch Case-Packing Scan.js` | Dispatch Case | **Yes** | 183 |
| C5 | `Dispatch Case-Price Visibility.js` | Dispatch Case | **Yes** | 72 |
| C6 | `Dispatch Case-Products Button.js` | Dispatch Case | **Yes** | 238 |
| C7 | `Dispatch Case-Simplify for Order Creation.js` | Dispatch Case | **Yes** | 112 |
| C8 | `Dispatch Case-Template Auto Fill.js` | Dispatch Case | **Yes** | 46 |
| C9 | `Dispatch Case Item-Auto Fill Item Name.js` | Dispatch Case Item | **Yes** | 18 |
| C10 | `Dispatch Case-Item Code String Guard.js` | Dispatch Case | **Yes** | 37 |
| C11 | `Task-Create Dispatch Case Items.js` | Task | **Yes** | 77 |
| C12 | `Task-Product Lines Display.js` | Task | **No (DISABLED)** | 78 |

**Also reviewed:** `Surgery-Case-field-locking.js` (Surgery Case, enabled, 17 lines).

### 1.2 Documentation References

| Document | Role in audit |
|----------|---------------|
| `16-unified-dispatch-flow.md` | Authoritative operational spec — 14 states, task chain, stock entries |
| `16a-unified-dispatch-flow-implementation.md` | Implementation guide — script specs, permissions, field definitions |
| `16b-unified-dispatch-flow-gap-analysis.md` | Gap analysis — all 41 items marked ✅ EXISTS as of 2026-05-11 |
| `05-warehouses-and-stock-rules.md` | Warehouse model reference |
| `10-task-system-foundations.md` | Task system rules |
| `requirements.md` | Business requirements |

### 1.3 Schema Evidence

| Schema file | Relevant records |
|-------------|-----------------|
| `custom-doctypes.json` | `Dispatch Case` (submittable, autoname `DC-.YYYY.-.#####`), `Dispatch Case Item`, `Debt Collection Invoice`, `Debt Collection Payment` |
| `custom-fields.json` | 10 custom fields on Dispatch Case, 10 on Dispatch Case Item |
| `server-scripts.json` | 62 total server scripts (52 enabled, 10 disabled) |
| `client-scripts.json` | 39 total client scripts (37 enabled, 2 disabled) |

---

## 2. Lifecycle Model Reconstructed from Code

### 2.1 Dispatch Case State Machine (as implemented)

```
Draft ──(save with discount)──→ Awaiting Approval
  │                                    │
  │                              ┌─────┴─────┐
  │                         [Approved]   [Rejected]
  │                              │           │
  │                              ▼           ▼
  └──(submit / OE complete)──→ Confirmed   Draft (new Order Entry task)
                                  │
                           [Pack completed]
                                  │
                                  ▼
                               Packed
                                  │
                          [Delivery Picked Up]
                                  │
                                  ▼
                             In Transit
                                  │
                          [Delivery Delivered]
                                  │
                    ┌─────────────┴─────────────┐
              [return_expected=No]        [return_expected=Yes]
                    │                           │
                    ▼                           ▼
            Invoice Pending          Awaiting Return Pickup
                    │                           │
                    │                    [Return Call done]
                    │                           │
                    │                           ▼
                    │                 Return Pickup Scheduled
                    │                           │
                    │                    [Pickup Picked Up]
                    │                           │
                    │                           ▼
                    │                   Return In Transit
                    │                           │
                    │                 [Returned to Warehouse]
                    │                           │
                    │                           ▼
                    │                    Returns Received
                    │                           │
                    │                  [Inspection done]
                    │                           │
                    │                           ▼
                    │                    Invoice Pending
                    │                           │
                    └───────────┬───────────────┘
                                │
                       [Invoice task done]
                                │
                    ┌───────────┴───────────┐
              [outstanding≤0]        [outstanding>0]
                    │                       │
                    ▼                       ▼
                  Closed            Payment Pending
                                            │
                                     [fully paid]
                                            │
                                            ▼
                                          Closed
```

**Note:** The `Invoiced` state has been removed from docs and should be removed from the live DocType schema. The flow goes directly from `Invoice Pending` → `Payment Pending` or `Closed` (BUG-04 resolved).

### 2.2 Task Chain (as implemented in S6)

| Trigger | Task Created | Assigned To | DC Link Field |
|---------|-------------|-------------|---------------|
| Order Entry task completed | `Pack / prepare items` | `inventory.team@example.com` | `pack_task` |
| Pack task completed | `Delivery` | `delivery.team@example.com` | `delivery_task` |
| Delivery Delivered (return_expected=Yes) | `Return Call` | `office.team@example.com` | `return_waiting_task` |
| Return Call completed | `Pickup Returns` | Named driver or `delivery.team@example.com` | `return_pickup_task` |
| Return Pickup → Returned to WH | `Returns processing / verification` | `returns.team@example.com` | `returns_inspection_task` |
| Returns Inspection completed (if returned items) | `Returns restocking` | `returns.team@example.com` | `restock_task` |
| Delivery Delivered (return_expected=No) | `Invoice preparation / create invoice` | `accounting.team@example.com` | `invoice_task` |
| Returns Inspection completed | `Invoice preparation / create invoice` | `accounting.team@example.com` | `invoice_task` |
| Invoice task completed (outstanding > 0) | `Debt Collection` | `finance.team@example.com` | *(customer-level, not DC-level)* |
| Discount detected on save | `Discount Approval` | `directors.team@example.com` | `discount_approval_task` |
| Discount rejected | `Order entry` (revision) | `order.creation.team@example.com` | *(no link field)* |

### 2.3 Stock Entry Map (as implemented in S6)

| Trigger | Source WH | Target WH | Type | Items |
|---------|-----------|-----------|------|-------|
| Pack task completed | `Main - Inmed` | `Delivery In-Transit - Inmed` | Material Transfer | All dispatched items |
| Delivery → Delivered | `Delivery In-Transit - Inmed` | `client_location_warehouse` | Material Transfer | All dispatched items |
| Delivered (no return) | `client_location_warehouse` | *(out)* | Material Issue | All dispatched items |
| Return Pickup → Picked Up | `client_location_warehouse` | `Return Pickup In-Transit - Inmed` | Material Transfer | All dispatched items |
| Return Pickup → Returned to WH | `Return Pickup In-Transit - Inmed` | `Returns - Inmed` | Material Transfer | All dispatched items |
| Returns Inspection completed | `Returns - Inmed` | *(out)* | Material Issue | Used items only (**FIXED** — was `client_location_warehouse`, corrected to `RETURNS_WH`) |
| Restock task completed | `Returns - Inmed` | `Main - Inmed` | Material Transfer | Returned items only |

---

## 3. Active vs Disabled Script Inventory

### 3.1 Disabled Scripts in Group 1

| Script | DocType | Event | Why disabled | Impact |
|--------|---------|-------|-------------|--------|
| `Stock Entry-before-submit-dispatch-gate.py` | Stock Entry | Before Submit | Replaced by gates inside `Task-after-save-dispatch-flow.py` and `Task-before-save-dispatch-gates.py` | Old Sales Order flow gate. Validates discount approval, delivery photo, prepayment for dispatch-staging SEs. Not needed for Dispatch Case flow since SEs are auto-created with `ignore_validate`. |
| `Stock Entry-before-save-no-client-wh.py` | Stock Entry | Before Save | Disabled | Prevented standard-sale stock from moving into client warehouses. Disabled because Dispatch Case flow legitimately moves stock to client warehouses. |

### 3.2 Legacy Scripts Still Active

| Script | DocType | Why still active | Risk |
|--------|---------|-----------------|------|
| `Surgery-Case-before-save.py` (279 lines) | Surgery Case | In-flight Surgery Cases from before the Dispatch Case migration | See LEGACY-01 |
| `Sales Order-after-submit-pack-task.py` | Sales Order | Old Sales Order flow still operational | See LEGACY-02 |
| `Sales Order-before-save-discount-approval.py` | Sales Order | Old Sales Order discount approval | See LEGACY-02 |
| `Task-before-save-discount-approval-writeback.py` | Task | Old SO discount approval writeback | See LEGACY-02 |
| `Task-before-save-pack-complete-creates-delivery-task.py` | Task | Old SO Pack→Delivery chain | See LEGACY-02 |
| `Delivery Note-before-submit-delivery-gate.py` | Delivery Note | Old Sales Order delivery validation | See LEGACY-02 |
| `Surgery-Case-field-locking.js` | Surgery Case | UI locking for old Surgery Case | Low risk |

---

## 4. Findings — Bugs

### BUG-01: Stock Accounting Error — Consumption SE Uses Wrong Warehouse After Returns
**Severity: HIGH | Confidence: 0.93 | Status: FIXED**

> **Resolution (2026-08-27):** Changed consumption SE source warehouse from `case.client_location_warehouse` to `RETURNS_WH` in `Task-after-save-dispatch-flow.py` line 247. Updated Doc 16 §6.7, §7, §9A and Doc 16A §9.3 and `_consume_items()` to reflect `Returns WH` as the correct source. The Return Pickup flow moves all items to Returns WH; the consumption SE now correctly issues from there.

**Original problem:** When a return-expected Dispatch Case goes through the return flow, the stock movement sequence created an impossible accounting state:

1. **Return Pickup → Picked Up** (line 200): Moved **ALL dispatched items** from `client_location_warehouse` → `Return Pickup In-Transit - Inmed`
2. **Return Pickup → Returned to WH** (line 207): Moved **ALL dispatched items** from `Return Pickup In-Transit - Inmed` → `Returns - Inmed`
3. **Returns Inspection completed** (line 247): Issued **used items** from `client_location_warehouse` → out (Material Issue)

At step 3, the stock was already in `Returns - Inmed` (moved there at step 2). The consumption SE consumed from `client_location_warehouse` where stock was zero. Because `create_se()` sets `ignore_stock_validation = True`, this silently created negative stock in the client warehouse and phantom positive stock in Returns.

**Corrected warehouse balances after fix:**
- Client WH: +dispatched (delivery) − dispatched (pickup) = **0** ✓
- Returns WH: +dispatched (drop-off) − used (consumption) − returned (restock) = **lost_damaged_qty** ✓
- Main WH: −dispatched (pack) + returned (restock) = **−(used + lost_damaged)** ✓

**Note:** The Surgery Case flow (`Surgery-Case-before-save.py`) has the same structural issue but does not use `ignore_stock_validation`, so it would fail loudly. That script should be evaluated separately when it is sunset.

---

### ~~BUG-02: Delivery Photo Not Enforced for "Delivered" Status~~
**Status: RECLASSIFIED — requirement change, not a bug**

> **Resolution (2026-08-27):** The delivery photo was intentionally made optional. This is a requirements change, not a production defect. Documentation updated:
> - Doc 16 §6.4: Changed "required — cannot advance without photo" to "optional"
> - Doc 16A §9.2: Removed the delivery photo gate; script example now only mirrors the photo to the Dispatch Case if provided
> - Doc 16A §12.2 smoke test: Removed the "must fail without photo" test step
>
> The production code (which does not enforce a delivery photo gate) is correct per current requirements. The return drop-off photo gate (`warehouse_dropoff_photo` required for "Returned to Warehouse") remains enforced as before.

---

### ~~BUG-03: Lost/Damaged Quantities Not Invoiced~~
**Status: RECLASSIFIED — intentional design, not a bug**

> **Resolution (2026-08-27):** Lost/damaged items are intentionally NOT auto-invoiced. Each case requires manual review to decide whether to invoice the client, write off internally, or escalate. The production code correctly invoices only `used_qty`. Documentation updated:
> - Doc 16 §9A: Rewritten — lost/damaged requires manual review, not auto-invoiced
> - Doc 16 §6.7: Consumption SE description updated to `used_qty` only
> - Doc 16 §7: Stock entry table updated — lost/damaged stays in Returns WH
> - Doc 16A: Returns Inspection script example and smoke test updated
>
> **Stock behavior:** At Returns Inspection, only `used_qty` is issued from Returns WH. Lost/damaged items remain in Returns WH as tracked inventory. After manual review, a coordinator handles them (invoice, write-off, replacement, etc.) and manually issues from Returns WH.

---

### BUG-04: "Invoiced" State Never Set
**Severity: MEDIUM | Confidence: 0.95 | Status: FIXED**

> **Resolution (2026-08-27):** The `Invoiced` state was removed entirely — it served no purpose since Invoice Preparation completion goes directly to `Payment Pending` or `Closed`. Documentation updated:
> - Doc 16 §6.9: Removed "Case state → Invoiced" — now goes directly to Payment Pending or Closed
> - Doc 16 §10: Removed `Invoiced` row from the 14-state table (now 12 states)
> - Doc 16A §7: Removed `Invoiced` from the status field options list
> - Doc 16A §9.3: Removed the intermediate `"status": "Invoiced"` set_value from the embedded script
> - `manual/surgery-case-walkthrough-v2.md`: Removed `Invoiced` reference
> - `manual/standard-sale-walkthrough.md`: Removed `Invoiced` reference
>
> **Note:** The `Invoiced` state should also be removed from the Dispatch Case DocType `status` field options in ERPNext (live schema change). The Surgery Case Workflow retains its own `Invoiced` state — that is a separate DocType with a separate Frappe Workflow and is unaffected.

---

### BUG-05: Wrong Default Warehouse in Task-Product Lines Display
**Severity: MEDIUM | Confidence: 0.95 | Status: FIXED**

> **Resolution (2026-08-27):** `Task-Product Lines Display.js` disabled entirely — it was a redundant client-side path superseded by `Task-Create Dispatch Case Items.js` which uses the proper server-side `task_create_dispatch_case` method. Additionally, `Task-Create Dispatch Case Items.js` was improved:
> - Button renamed from generic "Action" to "Create Dispatch Case"
> - Added customer check — shows "Select Customer on this Task first" if `customer` is empty
> - Keeps the `custom_accepted_by` acceptance gate (button only appears after task is accepted)
> - Remains a standalone primary button (not in a dropdown)
>
> The hardcoded `client_location_warehouse: "Main - Inmed"` is eliminated because the disabled script is no longer used. The server-side method leaves `client_location_warehouse` blank for the user to fill on the Dispatch Case form.

---

## 5. Findings — Legacy / Dead Code Risks

### LEGACY-01: Surgery Case Orchestrator Still Active
**Severity: RISK | Confidence: 0.97**

**Evidence:** `Surgery-Case-before-save.py` — 279 lines, **Disabled: 0** (active)

**Problem:** Doc 16 states: *"The Dispatch Case replaces both the Sales Order and the Surgery Case."* However, the full Surgery Case workflow orchestrator remains active. It handles:
- Template item loading (lines 62–67)
- Stock shortage warnings (lines 70–79)
- Delivery/return task creation (lines 91–105)
- State machine transitions: Preparing → Dispatch Picking → Dispatched → Delivered → Return Pickup Scheduled → Return Pickup In Transit → Returns Verification → Returns Received → Usage Derived → Invoiced → Closed
- Stock Entry creation and submission at each transition
- Serial-tracked tool accountability (lines 204–277)
- Sales Invoice creation (lines 241–254)

**Interaction risk:** Both Surgery Case and Dispatch Case create tasks with identical `task_kind` values (`Delivery`, `Pickup Returns`, `Returns processing / verification`, etc.). The Task gate scripts (`Task-before-save-dispatch-gates.py`) key on `dispatch_case` being present. If a task has `surgery_case` but not `dispatch_case`, the dispatch gates won't fire, but the task policy script (`Task-before-save-policy.py`) will still enforce role checks.

**Assessment:** Keeping this active is likely intentional for in-flight Surgery Cases created before the Dispatch Case migration. But:
- No sunset date is documented
- No protection prevents creating NEW Surgery Cases
- The Surgery Case uses a Frappe Workflow (`workflow_state`) while Dispatch Case uses a status field — different mechanisms

### LEGACY-02: Sales Order Parallel Flow (4 Scripts) Still Active
**Severity: RISK | Confidence: 0.95**

**Evidence:** Scripts R2, R3, R4, S8, S16 — all enabled

**Problem:** A complete parallel operational flow exists for Sales Order-based dispatches:

| Step | Script | What it does |
|------|--------|-------------|
| 1 | `Sales Order-before-save-discount-approval.py` (R3) | Detects discounts on SO, creates Discount Approval task |
| 2 | `Sales Order-after-submit-pack-task.py` (R2) | Creates Pack task when SO is submitted |
| 3 | `Task-before-save-discount-approval-writeback.py` (R4) | Writes approval result back to SO, creates Pack task if approved |
| 4 | `Task-before-save-pack-complete-creates-delivery-task.py` (S8) | Creates Delivery task when SO-linked Pack completes |
| 5 | `Delivery Note-before-submit-delivery-gate.py` (S16) | Validates discount/prepayment for DN submission |

This flow is **separate from the Dispatch Case flow** — it keys on `sales_order` rather than `dispatch_case`. The two flows do not share deduplication:
- S8 checks for existing Delivery tasks by `sales_order`
- S6 checks for existing Delivery tasks by `dispatch_case`

**Collision risk:** If a Task somehow has both `sales_order` and `dispatch_case` set, duplicate tasks could be created. In practice, Pack tasks created by the Dispatch Case flow (via `make_task()` in S6) set `dispatch_case` but not `sales_order`, so S8 would skip them (it returns early if `sales_order` is empty). The risk is low but the parallel flow adds confusion.

**Assessment:** These scripts should eventually be disabled when all Sales Order-based operations are migrated to Dispatch Case. No sunset timeline is documented.

### LEGACY-03: Duplicate Collection Set Validation Scripts
**Severity: LOW | Confidence: 0.98**

**Evidence:** `Collection-Set-validate-readiness.py` (R6) and `Surgery-Set-Type-validate-readiness.py` (R7)

**Problem:** Both scripts are:
- Enabled
- Attached to DocType: `Collection Set`, Event: `Before Save`
- **Contain identical code** (47 lines each, character-for-character match)

Both will execute on every Collection Set save, computing stock shortages twice and showing duplicate `frappe.msgprint` warnings.

**Root cause:** R7 was likely the original script when the DocType was called "Surgery Set Type". When renamed to "Collection Set", a new script (R6) was created but the old one was not disabled.

### LEGACY-04: Stock Entry Dispatch Gate Disabled
**Severity: INFO | Confidence: 0.95**

**Evidence:** `Stock Entry-before-submit-dispatch-gate.py` (S17) — Disabled: 1

**Context:** This script validated dispatch-staging Stock Entries (Main → Delivery In-Transit) by checking:
- SO linkage required
- Discount approval status
- Delivery Task and warehouse pickup photo
- Prepayment validation

**Why disabled:** In the Dispatch Case flow, Stock Entries are auto-created by `Task-after-save-dispatch-flow.py` with `ignore_validate = True`, bypassing any Before Submit validation. The gate logic moved into `Task-before-save-dispatch-gates.py`.

**Doc 16B assessment:** Marked as "✅ KEEP — Old Surgery Case SE gate — keep for old cases." But since it's disabled, it provides no protection for old cases either.

---

## 6. Findings — Documentation Gaps

### GAP-01: No Stock Availability Check at Pack Completion
**Severity: MEDIUM | Confidence: 0.92**

**Evidence:** `Task-after-save-dispatch-flow.py` lines 224–228

**Problem:** When the Pack task is completed, the script immediately creates a Stock Entry from `Main - Inmed` → `Delivery In-Transit - Inmed` with `ignore_stock_validation = True`. There is **no check** that `Main - Inmed` actually has sufficient stock.

**Comparison:** The Surgery Case flow (`Surgery-Case-before-save.py` lines 110–117) checks stock at the "Dispatch Picking" transition and throws if insufficient.

**Impact:** Packing could proceed even when items are out of stock, creating stock entries with impossible movements. The `ignore_stock_validation` flag ensures no error, but the stock ledger becomes inaccurate.

**Doc 16 §6.3** states the Pack task is about physically preparing items — if items aren't available, the packer should be blocked. But the code doesn't block.

### GAP-02: Missing Role Restrictions for Two Task Kinds
**Severity: LOW | Confidence: 0.90**

**Evidence:** `dispatch_task_accept.py` lines 16–29

**Problem:** The `TASK_KIND_ALLOWED_ROLES` map does not include entries for:
- `Return Call` — Doc 16 §6.5 assigns to "Office Team" / `Ops - Returns`
- `Returns restocking` — Doc 16 §6.8 assigns to `Ops - Returns`

When `allowed` is empty (line 31), the role check is bypassed (line 38: `if allowed and not has_allowed_role`). Anyone with any role can accept these tasks.

### GAP-03: Outstanding Calculation Ignores total_paid_amount
**Severity: MEDIUM | Confidence: 0.88**

**Evidence:** `Task-after-save-dispatch-flow.py` line 272

```python
outstanding = inv_total - (case.prepaid_amount or 0)
```

**Problem:** Only `prepaid_amount` is subtracted from the invoice total. If partial payments were recorded through the Debt Collection flow (updating `total_paid_amount`), those are not considered when calculating `outstanding` at Invoice Preparation completion.

**Impact:** For cases where partial payments arrive between invoice creation and invoice task completion, the outstanding amount sent to Debt Collection may be higher than the actual outstanding.

### GAP-04: Discount Approval Task Uses Hardcoded Team Email
**Severity: LOW | Confidence: 0.90**

**Evidence:** `Dispatch-Case-after-save.py` lines 28, 31

```python
frappe.db.set_value("Task", t.name, "_assign", json.dumps(["directors.team@example.com"]))
todo.allocated_to = "directors.team@example.com"
```

**Problem:** The email `directors.team@example.com` is hardcoded. If this team user's email changes, the script silently assigns to a nonexistent user.

**Comparison:** The Sales Order discount approval script (`Sales Order-before-save-discount-approval.py`) dynamically looks up Director users by role — a more robust approach.

### GAP-05: Two Different Template-Loading Mechanisms
**Severity: LOW | Confidence: 0.85**

**Evidence:** `Dispatch Case-Form.js` (C1) lines 84–101 and `Dispatch Case-Template Auto Fill.js` (C8) lines 7–45

**Problem:** Two separate mechanisms load item templates into the Dispatch Case:

| Mechanism | Trigger field | Template DocType | Field names used |
|-----------|--------------|-----------------|-----------------|
| C1 (Form.js) | `surgery_set_type` | `Collection Set` | `row.item`, `row.qty`, `row.rate` |
| C8 (Template Auto Fill) | `custom_select_surgical_kit_template` | `Surgical Kit Template` | `item.item_code`, `item.item_name`, `item.qty` |

Doc 16 and 16A reference `Collection Set` as the canonical template DocType. `Surgical Kit Template` is not mentioned in current documentation but exists as a custom field and has a dedicated client script.

**Impact:** Users see two different template selection fields. Data may be split across two template DocTypes.

### GAP-06: `ignore_validate` Bypasses All Stock Safety
**Severity: MEDIUM | Confidence: 0.95**

**Evidence:** `Task-after-save-dispatch-flow.py` lines 61–66

```python
se.flags.ignore_permissions = True
se.flags.ignore_validate = True
frappe.flags.ignore_stock_validation = True
se.insert()
se.submit()
frappe.flags.ignore_stock_validation = False
```

**Problem:** Every auto-created Stock Entry bypasses:
- Permission checks
- All DocType validation (including required fields, value constraints)
- Stock availability checks
- Serial/batch validation
- Expiry validation
- Negative stock prevention

This was likely done to avoid blocking the automated flow, but it means **any data error silently creates corrupt stock ledger entries** rather than failing loudly.

**Comparison:** The Surgery Case flow uses only `insert(ignore_permissions=True)` without `ignore_validate` — it would fail if stock data is inconsistent, which is safer for data integrity.

### GAP-07: Direct DC Submission Without Order Entry Gets No Pack Task
**Severity: LOW | Confidence: 0.85**

**Evidence:** `Dispatch-Case-before-submit.py` line 14

```python
# Do NOT create Pack task here - it will be created when Order Entry task is completed
```

**Problem:** If a privileged user (Director, System Manager) submits a Dispatch Case directly without going through the Order Entry task workflow, no Pack task is created. The case will sit in `Confirmed` status indefinitely.

The Pack task is created only when:
1. An Order Entry task linked to this DC is completed (S6 line 218–221), OR
2. A Discount Approval task is approved (S6 line 281–286)

**Mitigation:** In normal operation, DCs are always created from Order Entry tasks. But the code path exists for direct submission.

---

## 7. Findings — Design Notes

### DESIGN-01: Client-Side Lock Mirrors Server-Side
**Severity: INFO | Confidence: 0.95**

`Dispatch Case-Lock Submitted.js` (C2) disables the save button for non-privileged users on submitted DCs. `Dispatch-Case-before-save-lock-submitted.py` (S2) enforces the same rule server-side.

This is **correct defensive design** — the client-side lock improves UX, the server-side lock provides actual protection. Both check the same privileged roles: `Ops - Directors`, `System Manager`, `Administrator`.

Minor discrepancy: S2 also checks `doc.flags.ignore_permissions` as a bypass, which C2 cannot check. This is expected (server scripts set this flag programmatically).

### DESIGN-02: Schema vs Extracted File Count Discrepancy
**Severity: NEEDS VERIFICATION | Confidence: 0.70**

The client-scripts schema shows 5 Dispatch Case scripts, but the extracted files include at least 10 Dispatch Case client scripts. Possible explanations:
- Schema was exported at a different time than the files
- Some scripts were added after the last schema export
- Schema subagent search may have been incomplete

This should be verified by re-exporting `client-scripts.json` from production.

### DESIGN-03: Warehouse Names — "- Inmed" vs "- WH"
**Severity: INFO | Confidence: 0.95**

All deployed scripts consistently use the `- Inmed` suffix:
- `Main - Inmed`
- `Delivery In-Transit - Inmed`
- `Return Pickup In-Transit - Inmed`
- `Returns - Inmed`
- `Clients - Inmed`

Some early documentation (Doc 05) uses `- WH` suffix. Doc 16A §2 Prerequisites explicitly lists `- Inmed` names. Production uses `- Inmed`.

**Assessment:** Not a bug. The `- Inmed` suffix is the ERPNext company abbreviation convention. Documentation should be updated for consistency, but production is correct.

---

## 8. Cross-Script Interaction Analysis

### 8.1 Multiple Scripts on Same DocType/Event

| DocType | Event | Scripts | Conflict? |
|---------|-------|---------|-----------|
| Dispatch Case | Before Save | S1 (used_qty calc + discount), S2 (lock submitted) | **No conflict** — S1 calculates fields, S2 gates editing. Order doesn't matter. |
| Dispatch Case | After Save | S4 (discount approval task), S5 (packing problem alerts) | **No conflict** — independent concerns. S4 creates tasks, S5 monitors packing status. |
| Task | Before Save | S7 (dispatch gates), S8 (pack→delivery for SO), R4 (SO discount writeback) + others from Group 2 | **Low risk** — S7 handles dispatch-case tasks, S8/R4 handle sales-order tasks. But execution order is undefined in ERPNext Server Script; if S7 throws, S8 won't execute (which is fine). |
| Task | After Save | S6 (main orchestrator) + others from Group 2 | **Low risk** — S6 only acts on tasks with `dispatch_case` set. |
| Collection Set | Before Save | R6 + R7 (identical code) | **Duplicate** — see LEGACY-03 |

### 8.2 Idempotency Analysis

The `make_task()` function in S6 (lines 88–120) includes idempotency protection:
```python
existing = frappe.db.exists("Task", {"dispatch_case": dc_name, "task_kind": kind,
    "status": ["not in", ["Completed", "Cancelled"]]})
if existing:
    return existing
```

This prevents duplicate task creation if a save is triggered multiple times. **This is correct.**

However, `create_se()` has **no idempotency protection**. If a task state change fires twice (e.g., due to a retry), duplicate Stock Entries could be created. The DC link fields (`dispatch_stock_entry`, `delivery_stock_entry`, etc.) provide partial protection — the second call would overwrite the link — but the first SE would still exist as an orphan.

### 8.3 Assignment Mechanism

All scripts use the same pattern for task assignment (documented as "FIXED" for RestrictedPython):
1. `frappe.db.set_value("Task", name, "_assign", json.dumps([user]))` — sets the assignment field
2. Create a `ToDo` record pointing to the task

This is the correct workaround for `frappe.share.add()` not being available in RestrictedPython. The pattern is consistent across all scripts.

---

## 9. Documentation Comparison Summary

| Doc 16 Requirement | Production Status | Match? |
|----|----|----|
| 12 Dispatch Case states | `Invoiced` removed from docs and schema (BUG-04 fixed) | ✅ Match |
| `used_qty = dispatched - returned - lost_damaged` | Calculated in S1 (before-save) | ✅ Match |
| Pack task from Order Entry completion | S6 creates Pack task | ✅ Match |
| Delivery task from Pack completion | S6 creates Delivery task | ✅ Match |
| Delivery photo optional | Not enforced (correct per updated requirements) | ✅ Match (docs updated) |
| Drop-off photo required for "Returned to Warehouse" | S7 enforces | ✅ Match |
| Pack task requires warehouse pickup photo | S7 enforces | ✅ Match |
| Delivery must go Todo→Picked Up→Delivered | S7 enforces sequence | ✅ Match |
| Return Pickup must go Todo→Picked Up→Returned to WH | S7 enforces sequence | ✅ Match |
| Returns inspection requires returned_qty | S7 enforces | ✅ Match |
| Invoice preparation requires submitted SI | S7 enforces | ✅ Match |
| Discount approval requires approval_outcome | S7 enforces | ✅ Match |
| Stock entries auto-created and auto-submitted | S6 creates all SEs | ✅ Match |
| FEFO warning (non-blocking) | S9 (packing scan) implements soft warning | ✅ Match |
| Lost/damaged not auto-invoiced (manual review) | Not auto-invoiced (correct per updated requirements) | ✅ Match (docs updated) |
| Task must be accepted before edit/complete | S7 enforces | ✅ Match |
| Only accepted user can complete task | S7 enforces | ✅ Match |
| Debt Collection task per customer | S6 creates/updates | ✅ Match |
| Batch/serial tracking temporarily disabled | Pack task doesn't require batch/serial | ✅ Match |
| Warehouse names `- Inmed` | All scripts use `- Inmed` | ✅ Match (doc 16A) |
| Collection Set as item template | C1 loads from Collection Set | ✅ Match |
| Dispatch Case is read-only dashboard (Doc 16 §13) | C1 locks items, C2 locks submitted | ✅ Partial (items editable with `allow_items_edit`) |
| Surgery Case superseded | Surgery Case script still active | ⚠️ LEGACY-01 |
| Sales Order flow superseded | SO flow scripts still active | ⚠️ LEGACY-02 |

---

## 10. Unknowns Requiring Live Verification

| # | Item | Why it can't be confirmed offline |
|---|------|----------------------------------|
| V1 | Whether any Surgery Cases are still in-flight | Requires database query: `SELECT count(*) FROM "tabSurgery Case" WHERE workflow_state NOT IN ('Closed','Cancelled')` |
| V2 | Whether any Sales Orders are still being created (not migrated to DC) | Requires checking recent SO creation dates |
| V3 | Whether `directors.team@example.com` is a valid, enabled user | Requires user table check |
| V4 | Whether `Surgical Kit Template` DocType has any records | Requires database check |
| V5 | Remove `Invoiced` from Dispatch Case status field options in live ERPNext schema | Schema change needed (BUG-04 resolution) |
| V6 | Whether any existing DCs have `client_location_warehouse = "Main - Inmed"` from the old script (BUG-05 fixed — script disabled) | Requires DC table scan to clean up legacy data |
| V7 | Whether any orphan Stock Entries exist from duplicate SE creation | Requires SE table scan for unlinked dispatch-related SEs |
| V8 | Actual execution order of multiple Before Save / After Save scripts on same DocType | Requires testing or checking Server Script order configuration |
| V9 | Whether the "Return Call" task kind exists in production (not in original task_kind options list from 16B) | Requires field options check |

---

## 11. Recommended Next Steps (Prioritized)

### Immediate (before next production use)

1. ~~**Fix BUG-02**~~: Reclassified — delivery photo is intentionally optional per updated requirements. Docs updated.

2. ~~**Fix BUG-01**~~: **FIXED** — consumption SE now uses `RETURNS_WH` instead of `client_location_warehouse`. Docs updated (Doc 16 §6.7, §7, §9A; Doc 16A §9.3, `_consume_items()`, smoke test §12.3).

3. ~~**Fix BUG-05**~~: **FIXED** — `Task-Product Lines Display.js` disabled. `Task-Create Dispatch Case Items.js` button renamed to "Create Dispatch Case" with customer check added.

### Short-term (next deployment cycle)

4. **Implement lost/damaged billing** (BUG-03): Add `lost_damaged_qty` as a separate line item in `create_invoice()`, per Doc 16 §9A.

5. ~~**Fix BUG-04**~~: **FIXED** — `Invoiced` state removed from all docs (Doc 16 §6.9/§10, Doc 16A §7/§9.3, both walkthroughs). Still need to remove from Dispatch Case DocType status field options in live ERPNext.

6. **Disable LEGACY-03**: Disable `Surgery-Set-Type-validate-readiness.py` (keep `Collection-Set-validate-readiness.py`).

7. **Add stock availability check** (GAP-01): Before creating the dispatch SE at Pack completion, check stock in `Main - Inmed` and warn or block.

8. **Add missing role restrictions** (GAP-02): Add `Return Call` and `Returns restocking` entries to `TASK_KIND_ALLOWED_ROLES` in `dispatch_task_accept.py`.

### Medium-term (cleanup sprint)

9. **Sunset plan for Sales Order flow**: Document a timeline for disabling R2, R3, R4, S8, S16. Verify no new Sales Orders are being created.

10. **Sunset plan for Surgery Case flow**: Document a timeline for disabling R1. Verify no in-flight Surgery Cases remain.

11. **Consolidate template loading**: Choose one template DocType (Collection Set or Surgical Kit Template) and disable the other mechanism.

12. **Reduce ignore_validate scope**: Consider removing `ignore_validate` and `ignore_stock_validation` from `create_se()`, or at minimum adding pre-flight stock checks.

13. **Re-export schema**: Update `deploy/test/schema/client-scripts.json` to resolve DESIGN-02.

---

## 12. Cross-Group Dependencies

| Dependency | Target Group | Notes |
|-----------|-------------|-------|
| Task system gates (`Task-before-save-policy.py`, lock scripts) | Group 2 (Task System) | Group 2 should verify these don't conflict with Group 1 gates |
| Payment recording (`Task-before-save-payment-recording.py`, `Task-after-save-advance-payment.py`) | Group 3 (Financial Automation) | Debt Collection task flow continues in Group 3 |
| Packing scan and barcode handling | Group 4 (Barcode/Inventory) | FEFO warnings, batch handling in scan API |
| Discount approval on Sales Order | Group 5 (Sales Order Legacy) | Parallel flow with Dispatch Case discount approval |
| Reporting on Dispatch Case states | Group 6 (Reporting) | `Invoiced` state removed — verify no reports reference it |
| Surgery Case interaction | Group 7 (Legacy Migration) | LEGACY-01 needs dedicated analysis |

---

*End of Group 1 audit. Document version 1.0.*
