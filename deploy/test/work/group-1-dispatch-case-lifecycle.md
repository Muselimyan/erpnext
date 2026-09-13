# Group 1: Dispatch Case Lifecycle

> **Scope:** Test server only. All deployed scripts, schema, and client code for the Dispatch Case operational flow.
> **Evidence:** Code in `deploy/test/work/`, schema in `deploy/test/schema/`.
> **Excludes:** Financial-tail items (invoicing, payments, pricing, profit, debt closure, outstanding calculation, `allow_on_submit` gaps, stock validation bypass, acceptance-rule conflicts) — those are in **Group 11**.

---

## 0. Summary

| # | Finding | Severity |
|---|---------|----------|
| ACT-01 | `create_se()` no idempotency — duplicate Stock Entries on retry | Medium |
| ACT-02 | `create_invoice()` no idempotency — duplicate Sales Invoices on retry | Medium |
| ACT-03 | Packing/returns/scan APIs match ANY active task on the DC, not the specific task kind | Medium |
| ACT-04 | No completion gate for Returns Restocking | Medium |
| ACT-05 | Cancel flow not implemented (Phase 3 — 0%) | Medium |
| ACT-06 | Product APIs don't validate DC status — items can be added to a Packed/Delivered DC via API | Medium |
| ACT-07 | `task_apply_template` unguarded at API level — can replace items on a submitted/packed DC | Medium |
| ACT-08 | `tab_can_act()` admin exemption contradicts TFE and AGENTS.md invariant | Medium |
| ACT-09 | Packing/returns APIs lack operational role checks (only acceptance check) | Medium |
| ACT-10 | Return quantity updates use array index, not row name — wrong item updated if rows reorder | Medium |
| ACT-11 | Corrupted UTF-8 in Discount Approval task subject | Low |
| ACT-12 | `pwa_pending_item_code` never cleared after successful scan — stale item reuse risk | Low |
| ACT-13 | Direct DC submission without Order Entry task creates no Pack task | Low |
| ACT-14 | Stale deleted files in `deploy/test/work/` | Low |
| ACT-15 | Dead `task_kind` options in schema | Low |
| ACT-16 | Legacy attach fields still in DC schema | Low |
| ACT-17 | Stale property setter for removed field `surgery_set_type` | Low |
| ACT-18 | `Task-Account Details UI Cleanup.js` enabled/disabled discrepancy between work file and server | Low |
| VERIFY-01 | `Return Call` Task Access Policy has correct `allowed_roles` | Needs Check |
| VERIFY-02 | `Surgical Kit Template` records exist; `Collection Set` loading is fully dead | Needs Check |
| VERIFY-03 | No orphan Stock Entries from duplicate SE creation | Needs Check |

---

## 1. Script Inventory

### Server Scripts (Dispatch Case lifecycle — 16 active)

| # | File | Type | DocType | Event |
|---|------|------|---------|-------|
| S1 | `Dispatch-Case-before-save.py` | DocType Event | Dispatch Case | Before Save |
| S2 | `Dispatch-Case-before-save-lock-submitted.py` | DocType Event | Dispatch Case | Before Save |
| S3 | `Dispatch-Case-before-submit.py` | DocType Event | Dispatch Case | Before Submit |
| S4 | `Dispatch-Case-after-save.py` | DocType Event | Dispatch Case | After Save |
| S5 | `Task-after-save-dispatch-flow.py` | DocType Event | Task | After Save |
| S6 | `Task-before-save-dispatch-gates.py` | DocType Event | Task | Before Save |
| S7 | `dispatch_task_accept.py` | API | — | — |
| S8 | `dispatch_case_packing_scan.py` | API | — | — |
| S9 | `task_create_dispatch_case.py` | API | — | — |
| S10 | `task_add_dispatch_product.py` | API | — | — |
| S11 | `task_update_dispatch_product.py` | API | — | — |
| S12 | `task_remove_dispatch_product.py` | API | — | — |
| S13 | `task_apply_template.py` | API | — | — |
| S14 | `task_mark_item_packed.py` | API | — | — |
| S15 | `task_mark_items_packed_batch.py` | API | — | — |
| S16 | `task_update_return_item_quantities.py` | API | — | — |

### Client Scripts (Dispatch Case lifecycle — 12 active)

| # | File | DocType | Enabled |
|---|------|---------|---------|
| C1 | `Dispatch Case-Form.js` | Dispatch Case | Yes |
| C2 | `Dispatch Case-Price Visibility.js` | Dispatch Case | Yes |
| C3 | `Dispatch Case-Products Button.js` | Dispatch Case | Yes |
| C4 | `Dispatch Case-Simplify for Order Creation.js` | Dispatch Case | Yes |
| C5 | `Dispatch Case-Template Auto Fill.js` | Dispatch Case | Yes |
| C6 | `Dispatch Case Item-Auto Fill Item Name.js` | Dispatch Case Item | Yes |
| C7 | `Dispatch Case-Item Code String Guard.js` | Dispatch Case | Yes |
| C8 | `Dispatch Case-Photo-Galleries.js` | Dispatch Case | Yes |
| C9 | `Task-Action Buttons.js` | Task | Yes |
| C10 | `Task-Product Work Area.js` | Task | Yes |
| C11 | `Task-Field-Visibility.js` | Task | Yes |
| C12 | `Task-Field-Editability.js` | Task | Yes |

### Disabled / Deleted (no longer in the flow)

All legacy parallel flows removed from test — Surgery Case, Sales Order, Collection Set, Stock Entry gate, Delivery Note gate.

Disabled client scripts absorbed into active ones: `Task-Product Lines Display.js`, `Task-Create Dispatch Case Items.js`, `Task-Dispatch Packing Usability.js`, `Task-Packing Checkboxes.js`, `Task-Lock Completed.js`, `Task-Lock Unaccepted.js`, `Dispatch Case-Lock Submitted.js`.

---

## 2. Lifecycle Model

### 2.1 State Machine

```
Draft ──(OE complete, discount detected)──→ Awaiting Approval
  │                                              │
  │                                    ┌─────────┴─────────┐
  │                               [Approved]          [Rejected]
  │                                    │                   │
  │                                    ▼                   ▼
  └──(OE complete, no discount)──→ Confirmed          Draft (new OE task)
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
                  [no return]                  [return expected]
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

### 2.2 Task Chain (`Task-after-save-dispatch-flow.py`)

| Trigger | Task Created | Default Assignee (from policy) | DC Link Field |
|---------|-------------|-------------------------------|---------------|
| Order Entry completed | `Pack / prepare items` | `inventory.team` | `pack_task` |
| Pack completed | `Delivery` | `delivery.team` | `delivery_task` |
| Delivery Delivered (return expected) | `Return Call` | `office.team` | `return_waiting_task` |
| Return Call completed | `Pickup Returns` | Named driver or `delivery.team` | `return_pickup_task` |
| Pickup → Returned to WH | `Returns processing / verification` | `returns.team` | `returns_inspection_task` |
| Returns Inspection completed (returned items) | `Returns restocking` | `returns.team` | `restock_task` |
| Delivered (no return) OR Inspection completed | `Invoice preparation / create invoice` | `accounting.team` | `invoice_task` |
| Invoice task done (outstanding > 0) | `Debt Collection` | `finance.team` | customer-level |
| Discount detected on OE completion | `Discount Approval` | from Task Access Policy | `discount_approval_task` |
| Discount rejected | `Order entry` (revision) | `order.creation.team` | — |

All team assignments read from `Task Access Policy` at runtime. `custom_next_task_assign_to` on the source task can override the default.

### 2.3 Stock Entry Map

| Trigger | Source WH | Target WH | Type | Items |
|---------|-----------|-----------|------|-------|
| Pack completed | `Main - Inmed` | `Delivery In-Transit - Inmed` | Material Transfer | All dispatched |
| Delivery → Delivered | `Delivery In-Transit - Inmed` | `client_location_warehouse` | Material Transfer | All dispatched |
| Delivered (no return) | `client_location_warehouse` | *(out)* | Material Issue | All dispatched |
| Return Pickup → Picked Up | `client_location_warehouse` | `Return Pickup In-Transit - Inmed` | Material Transfer | All dispatched |
| Return Pickup → Returned to WH | `Return Pickup In-Transit - Inmed` | `Returns - Inmed` | Material Transfer | All dispatched |
| Returns Inspection completed | `Returns - Inmed` | *(out)* | Material Issue | Used items only |
| Restock completed | `Returns - Inmed` | `Main - Inmed` | Material Transfer | Returned items only |

Lost/damaged items intentionally NOT auto-invoiced or auto-consumed. They remain in `Returns - Inmed` for manual review.

### 2.4 Gate Enforcement (`Task-before-save-dispatch-gates.py`)

| Task Kind | Gate | Enforcement |
|-----------|------|-------------|
| All dispatch tasks | Must be accepted before edit/complete | `custom_accepted_by` required |
| All dispatch tasks | Only accepted user can complete | `accepted_by == session.user` |
| All dispatch tasks | Cannot reassign and complete simultaneously | Blocks if `custom_assigned_to` changed |
| Order entry | Must have items and customer | Throws if `case_items` empty or `customer` blank |
| Order entry | Return expected requires client location WH | Throws if `order_client_location_warehouse` blank |
| Order entry (with discounts) | DC set to `Awaiting Approval` | Discount detection at completion |
| Pack / prepare items | Requires attached photo | `task_has_image()` check |
| Pack / prepare items | All items must be fully scanned | `custom_scanned_qty >= dispatched_qty` per row |
| Delivery | Status: Todo → Picked Up → Delivered | Sequence enforced; auto-completes on Delivered |
| Pickup Returns | Status: Todo → Picked Up → Returned to WH | Sequence enforced; requires dropoff photo; auto-completes |
| Returns processing / verification | All rows must have `returned_qty` filled | `returned_qty is None` check |
| Invoice preparation | Submitted Sales Invoice required | `docstatus == 1` check |
| Discount Approval | `approval_outcome` required | Must be set |
| Debt Closure Approval | Role check from Task Access Policy | Only allowed roles can complete |

**Missing gates** (no completion validation exists):
- `Returns restocking` — see ACT-04
- `Debt Collection` — see Group 11 G4

---

## 3. Open Issues

### ACT-01: `create_se()` Has No Idempotency Protection
**Severity: Medium**

`make_task()` checks for an existing active task before creating. `create_se()` does not. If the after-save fires twice (retry, race condition), duplicate Stock Entries are created and submitted. The DC link field gets overwritten, orphaning the first SE.

**Location:** `Task-after-save-dispatch-flow.py` `create_se()` function (lines 33-68), called at lines 187, 191, 202, 207, 223, 244, 260.

**Fix:** Check if the relevant DC SE link field already has a value before creating.

### ACT-02: `create_invoice()` Has No Idempotency Protection
**Severity: Medium**

Same pattern as ACT-01. If the after-save fires twice, two Draft Sales Invoices are created. The second overwrites `case.sales_invoice`, orphaning the first.

**Location:** `Task-after-save-dispatch-flow.py` `create_invoice()` function (lines 127-146), called at lines 193 and 246.

**Fix:** Check if `case.sales_invoice` already has a value before creating.

### ACT-03: Packing/Returns/Scan APIs Match Wrong Task Scope
**Severity: Medium**

`task_mark_item_packed.py`, `task_mark_items_packed_batch.py`, `task_update_return_item_quantities.py`, and `dispatch_case_packing_scan.py` all use this acceptance check:

```python
tfe_tasks = frappe.get_all("Task", filters={
    "dispatch_case": case_name,
    "status": ["not in", ["Completed", "Cancelled"]]
}, fields=["custom_accepted_by"], limit_page_length=1)
```

This matches ANY active task on the DC, not the specific task kind. A user who accepted the Delivery task could mark items as packed (because the Delivery task is linked to the same DC). The `limit_page_length=1` means it picks whichever task the DB returns first.

**Location:** All four files, acceptance check around lines 17-19.

**Fix:** Filter by `task_kind` as well (e.g. `Pack / prepare items` for packing APIs, `Returns processing / verification` for return APIs).

### ACT-04: No Completion Gate for Returns Restocking
**Severity: Medium**

`Task-before-save-dispatch-gates.py` has specific completion gates for Pack, Delivery, Pickup Returns, Returns Inspection, Invoice Prep, Discount Approval, and Debt Closure Approval. There is NO gate for `Returns restocking`. A user can complete the Restock task without any verification, and the SE is created from `Returns - Inmed` → `Main - Inmed` using whatever `returned_items(case)` returns. No data integrity risk, but no process enforcement.

**Location:** `Task-before-save-dispatch-gates.py` — no block for `Returns restocking`.

### ACT-05: Cancel Flow Not Implemented (Phase 3)
**Severity: Medium**

No way to cancel a Dispatch Case mid-lifecycle. Design exists in `deploy/test/work/phase3-cancel-flow-plan.md`, implementation at 0%. Missing:
- `Cancelled` not in DC status options
- No cancel API
- No cancel button on forms
- No `Dispatch Cancel Restock` task kind
- No cancellation fields (`cancellation_reason`, `cancelled_by`, `cancelled_at`)
- No stock reversal logic

**Blocked on:** Design review and approval.

### ACT-06: Product APIs Don't Validate DC Status
**Severity: Medium**

`task_add_dispatch_product.py`, `task_update_dispatch_product.py`, `task_remove_dispatch_product.py` modify DC items regardless of DC status. They check acceptance on the linked task but not the DC lifecycle state. A direct API call could add/modify/remove items on a DC in `Packed`, `In Transit`, or `Delivered` status.

The UI naturally limits this (Product Work Area only renders the editable view for `Order entry` tasks), but the API is unguarded.

**Location:** All three files — no DC status check.

**Fix:** Reject modifications when DC status is not `Draft` or `Awaiting Approval`.

### ACT-07: `task_apply_template` Unguarded at API Level
**Severity: Medium**

`task_apply_template.py` line 22 clears ALL `case_items` (`dc.set("case_items", [])`) and replaces them with template items. It requires an accepted task but does not check DC status, task kind, or whether items have already been operationally moved (packed, dispatched).

The UI has a `frappe.confirm` guard when items exist, but the API does not.

**Location:** `task_apply_template.py` — no DC status or task kind validation.

**Fix:** Reject when DC is submitted or has any SE linked.

### ACT-08: `tab_can_act()` Admin Exemption Contradicts AGENTS/TFE
**Severity: Medium**

`Task-Action Buttons.js` `tab_can_act()` (line 133-136) returns true for `System Manager` / `Administrator`, allowing them to click Complete, Picked Up, Delivered, etc. But `Task-Field-Editability.js` `tfe_can_edit()` (lines 16-22) has NO admin exemption — `accepted_by === session.user` is the only check.

AGENTS.md explicitly states: *"There is no admin exemption — `accepted_by === session.user` is the only check."*

An admin can click action buttons but cannot edit fields. The buttons call `savedocs` directly bypassing the field editability layer, so the action goes through — but it violates the stated invariant.

**Location:** `Task-Action Buttons.js` lines 124-136.

**Fix:** Remove `tab_is_admin()` from `tab_can_act()`.

### ACT-09: Packing/Returns APIs Lack Operational Role Checks
**Severity: Medium**

`task_mark_item_packed.py`, `task_mark_items_packed_batch.py`, `task_update_return_item_quantities.py`, and `dispatch_case_packing_scan.py` check that the caller accepted a related task but do not verify the user has the appropriate operational role (e.g. `Ops - Inventory` for packing, `Ops - Returns` for returns). Any user who accepted any DC-linked task can call these APIs. Overlaps with ACT-03 (wrong task scope).

**Location:** All four files, acceptance check around lines 17-19.

### ACT-10: Return Quantity Updates Use Array Index, Not Row Name
**Severity: Medium**

`task_update_return_item_quantities.py` (and `task_mark_item_packed.py`) use `item_idx` (the array position from the client-side renderer) to identify the row in `case_items`. If server-side rows are reordered (e.g. by another save, template re-application, or item addition), the index addresses the wrong item.

By contrast, `task_update_dispatch_product.py` and `task_remove_dispatch_product.py` use `row_name` (the stable DB identifier).

**Location:** `task_update_return_item_quantities.py` line 9, `task_mark_item_packed.py` line 9.

**Fix:** Use `row.name` instead of array index.

### ACT-11: Corrupted UTF-8 in Discount Approval Subject
**Severity: Low**

`Dispatch-Case-after-save.py` line 17 contains `â€"` (mojibake) instead of `—` (em-dash):
```python
"subject": f"Discount Approval: {doc.name} â€" {doc.customer}",
```

**Location:** `Dispatch-Case-after-save.py` line 17.

### ACT-12: `pwa_pending_item_code` Never Cleared After Scan
**Severity: Low**

In `Task-Product Work Area.js`, the global variable `pwa_pending_item_code` is set when a REF barcode is scanned (line 166) but never cleared after a successful GS1 packing scan. If the user scans a GS1 barcode without first scanning a new REF, the stale item code is reused.

**Location:** `Task-Product Work Area.js` line 15, 166.

**Fix:** Clear `pwa_pending_item_code = ""` after a successful packing scan call.

### ACT-13: Direct DC Submission Creates No Pack Task
**Severity: Low**

If a privileged user submits a Dispatch Case directly (bypassing the Order Entry task), no Pack task is created. The DC sits in `Confirmed` indefinitely. In normal operation this path is not reachable — `dispatch_task_accept.py` auto-creates DCs from Order Entry tasks. But the code path exists.

**Location:** `Dispatch-Case-before-submit.py` line 14 (intentional comment).

### ACT-14: Stale Deleted Files in `deploy/test/work/`
**Severity: Low**

These files exist locally but were deleted from the test server:
- `deploy/test/work/client/Dispatch Case-Packing Scan.js`
- `deploy/test/work/client/Dispatch Case-Packing Problem Alerts.js`
- `deploy/test/work/server/Dispatch Case-packing-problem-alerts.py`

Remove from local directory to avoid confusion.

### ACT-15: Dead `task_kind` Options in Schema
**Severity: Low**

Several `task_kind` select options have no dispatch flow integration:
- `Order accepting` — schema default, overridden to `Order entry` by client scripts. No script logic handles it.
- `Dispatch picking / hand-off` — not referenced by any script.

These create confusion in dropdowns and Quick Entry.

**Location:** `custom-fields.json`, `Task-task_kind` options.

### ACT-16: Legacy Attach Fields in DC Schema
**Severity: Low**

`delivery_photo` and `return_dropoff_photo` (Attach, `read_only: 1`) still exist in the DC DocType definition. Hidden by `Dispatch Case-Photo-Galleries.js` but functionally dead — photos are now attached to Tasks, not DCs.

**Location:** `custom-doctypes.json`, Dispatch Case fields.

### ACT-17: Stale Property Setter for Removed Field
**Severity: Low**

`Dispatch Case-surgery_set_type-allow_on_submit` exists in `property-setters.json` but the field `surgery_set_type` is not in the current DC field list. Leftover from Collection Set removal.

**Location:** `property-setters.json`.

### ACT-18: `Task-Account Details UI Cleanup.js` Discrepancy
**Severity: Low**

The local work file header says `Enabled: 0`. The test server schema export (`client-scripts.json`) shows `enabled: 1`. If the old version (before Phase 2d fix) is still running on the server, it could be toggling TFV-owned fields, causing race conditions.

**Location:** `deploy/test/work/client/Task-Account Details UI Cleanup.js` vs `deploy/test/schema/client-scripts.json`.

**Action:** Verify which version is on the server. If the pre-Phase-2d version, deploy the fixed version. If already fixed, update the work file header to `Enabled: 1`.

---

## 4. Verification Items

| # | Item | How to verify |
|---|------|---------------|
| VERIFY-01 | `Return Call` Task Access Policy has correct `allowed_roles` | Check `Task Access Policy` "Return Call" record on test |
| VERIFY-02 | `Surgical Kit Template` has records; `surgery_set_type` field on DC is dead | Check record count; confirm field is unused |
| VERIFY-03 | No orphan Stock Entries from duplicate SE creation (ACT-01) | Query SEs linked to DCs where DC link fields point to different SEs |

---

## 5. Verified Correct

| Area | Detail |
|------|--------|
| State machine transitions | All 12 used states flow correctly |
| Task chain creation | `make_task()` has idempotency guard |
| Stock entry warehouses | Correct warehouse pairs for all 7 SE types |
| `used_qty` calculation | `dispatched - returned - lost_damaged`, throws on negative |
| Pack photo gate | Required before completion |
| Packing scan completeness | `scanned_qty >= dispatched_qty` for every row |
| Delivery status sequence | `Todo → Picked Up → Delivered` enforced, auto-complete on Delivered |
| Pickup Returns sequence | `Todo → Picked Up → Returned to WH` enforced, dropoff photo required |
| Returns inspection gate | `returned_qty` required for every row |
| Invoice submission gate | `docstatus == 1` required |
| Discount detection | Moved to OE completion gate (correct) |
| Discount Approval flow | Approved → submit DC + create Pack; Rejected → Draft + new OE |
| Template auto-fill | Replaces `case_items` from `Surgical Kit Template` |
| Dynamic policy lookup | All role and team assignments read from `Task Access Policy` at runtime |
| Order Entry field sync | `return_expected`, `client_location_warehouse`, `surgery_date`, `customer` synced to DC |
| Acceptance model | Server-side enforcement in dispatch-gates, lock-unaccepted, and all API scripts |
| Submitted DC lock | `Dispatch-Case-before-save-lock-submitted.py` blocks non-privileged edits; scripts bypass via `flags.ignore_permissions` |
| FEFO warning | Advisory only (non-blocking), as designed |
| Lost/damaged exclusion | Intentionally excluded from auto-invoice and auto-consumption |

---

## 6. Cross-Script Interaction

### Multiple Scripts on Same DocType/Event

| DocType | Event | Scripts | Conflict? |
|---------|-------|---------|-----------|
| Dispatch Case | Before Save | S1 (used_qty calc), S2 (lock submitted) | No — independent |
| Dispatch Case | After Save | S4 (discount approval task) | Single script |
| Task | Before Save | S6 (dispatch gates) + policy + lock scripts | See Group 11 C1 for conflict analysis |
| Task | After Save | S5 (orchestrator) + advance payment + debt closure + telegrams | Each filters by `task_kind` early |

### Idempotency

| Function | Protected? |
|----------|-----------|
| `make_task()` | Yes — checks for existing active task |
| `create_se()` | **No** — ACT-01 |
| `create_invoice()` | **No** — ACT-02 |

---

## 7. Cross-Group Dependencies

| Dependency | Target Group | Notes |
|-----------|-------------|-------|
| Task system gates (policy, lock, acceptance rule conflicts) | Group 2, Group 11 C1 | Group 11 C1 is the critical cross-script conflict |
| Financial tail (invoicing, payments, pricing, outstanding, closure) | Group 11 | 17 gap items + redesign proposals |
| Packing scan and barcode handling | Group 5 | FEFO warnings, scan API |
| Reporting on DC states | Group 10 | Dead status options may affect reports |

---

*End of Group 1 audit.*
