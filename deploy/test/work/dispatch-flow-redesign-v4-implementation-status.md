# Dispatch Flow Redesign v4 — Implementation Status

**Plan:** `plan-92e19be24c1dcf3f.md` (session: defiant-termite, 2026-09-02)
**Audited:** 2026-09-08
**Source:** `C:\Users\Vahe\.devin\plans\plan-92e19be24c1dcf3f.md`

---

## Executive Summary

The plan defined 3 phases: **Order Entry Redesign**, **DC Form Cleanup**, and **Cancel Flow**. Phase 1 is fully implemented (server scripts, client scripts, schema). Phase 2 is partially implemented (property setters done, version history and script cleanup not done). Phase 3 is not implemented at all.

| Phase | Status | Completion |
|---|---|---|
| Phase 1 — Order Entry Redesign | **Mostly complete** | ~95% |
| Phase 2 — DC Form Cleanup | **Partial** | ~45% |
| Phase 3 — Cancel Flow | **Not started** | 0% |

---

## Phase 1: Order Entry Redesign

### Server Scripts

| Plan Item | Script | Status | Notes |
|---|---|---|---|
| Auto-create Draft DC on accept | `dispatch_task_accept.py` | **Done** | Creates DC with status Draft, links via `order_entry_task`, copies customer |
| Order Entry field sync to DC | `Task-before-save-dispatch-gates.py` | **Done** | Syncs `order_return_expected`, `order_client_location_warehouse`, `order_surgery_date`, `customer` |
| Completion gate with discount detection | `Task-before-save-dispatch-gates.py` | **Done** | Validates items exist, validates warehouse when return expected, detects discounts, auto-submits or sets Awaiting Approval |
| DC docstatus guard | `Task-before-save-dispatch-gates.py` | **Done** | Skips completion gate if DC already submitted (docstatus=1) |
| Remove discount detection from DC before_save | `Dispatch-Case-before-save.py` | **Done** | Only `used_qty` calculation remains; comment documents the move |
| Pack task creation guard | `Task-after-save-dispatch-flow.py` | **Done** | Only creates Pack if DC docstatus=1 after Order Entry completion |
| Discount Approval completion handler | `Task-after-save-dispatch-flow.py` | **Done** | Approved: submits DC + creates Pack. Rejected: reverts to Draft + creates new Order Entry |
| Template auto-fill API | `task_apply_template.py` | **Done** | Loads Surgical Kit Template into DC case_items, clears existing items first |
| `ignore_validate_update_after_submit` hardening | 4 scripts + 1 existing | **Done** | Added to `task_mark_items_packed_batch.py`, `task_mark_item_packed.py`, `task_update_return_item_quantities.py`, `Task-after-save-advance-payment.py`. Already existed in `dispatch_case_packing_scan.py` |
| Keep `task_create_dispatch_case.py` as fallback | `task_create_dispatch_case.py` | **Done** | Still enabled for legacy tasks without auto-created DC |

### Client Scripts

| Plan Item | Script | Status | Notes |
|---|---|---|---|
| "View DC" link (replacing "Open Dispatch Case") | `Task-Action Buttons.js` | **Done** | Mobile sub-header + desktop header both show "View DC" |
| "Create DC" kept as fallback | `Task-Action Buttons.js` | **Done** | Auto-hidden for new tasks (DC auto-created on accept), visible for legacy tasks |
| Order entry in product-task kinds | `Task-Product Work Area.js` | **Done** | "Order entry" in `task_product_work_area_is_product_task` kinds array |
| Order-entry renderer | `Task-Product Work Area.js` | **Done** | `task_product_work_area_render_order_entry()` renders items with qty/price/discount/batch columns |
| Template `order_template` handler | `Task-Product Work Area.js` | **Done** | `onchange` handler calls `task_apply_template` API, reloads form |
| Field visibility for Order Entry fields | `Task-Field-Visibility.js` | **Done** | Maps `order_return_expected`, `order_client_location_warehouse`, `order_surgery_date`, `order_template` to Order entry kind |
| Field visibility delegation | `Task-Accept Start.js` | **Done** | All visibility logic moved to `Task-Field-Visibility.js`; Accept Start only handles mobile/layout cosmetics |

### Schema Changes

| Plan Item | Location | Status | Notes |
|---|---|---|---|
| `order_return_expected` (Check) | `custom-fields.json` line 5757 | **Done** | `hidden: 1`, revealed by Task-Field-Visibility.js |
| `order_client_location_warehouse` (Link → Warehouse) | `custom-fields.json` line 5808 | **Done** | `hidden: 1`, revealed when `order_return_expected` is checked |
| `order_surgery_date` (Date) | `custom-fields.json` line 5860 | **Done** | `hidden: 1`, revealed for Order entry |
| `order_template` (Link → Surgical Kit Template) | `custom-fields.json` line 5911 | **Done** | `hidden: 1`, revealed for Order entry |

### Phase 1 Gap

- Client-side discount confirmation dialog (plan §2.7.E) — not verified whether the `frappe.confirm()` dialog is in `Task-Action Buttons.js` before completing an Order Entry task with discounted items.

---

## Phase 2: DC Form Cleanup

### Property Setters (`allow_on_submit = 1`)

**Dispatch Case parent fields:**

| Field | Status | Location |
|---|---|---|
| `customer` | **Done** | `property-setters.json` line 2309 |
| `return_expected` | **Done** | `property-setters.json` line 2343 |
| `client_location_warehouse` | **Done** | `property-setters.json` line 2326 |
| `notes` | **Done** | `property-setters.json` line 2394 |
| `case_items` | **Done** | `property-setters.json` line 2986 |

**Dispatch Case Item child fields:**

| Field | Status | Location |
|---|---|---|
| `item_code` | **Done** | `property-setters.json` line 2785 |
| `item_name` | **Done** | `property-setters.json` line 2802 |
| `dispatched_qty` | **Done** | `property-setters.json` line 2819 |
| `unit_price` | **Done** | `property-setters.json` line 2870 |
| `batch_no` | **Done** | `property-setters.json` line 2853 |
| `discount_pct` | **NOT DONE** | Only has `permlevel` setter (line 3412), no `allow_on_submit` |

### Version History

| Plan Item | Status | Notes |
|---|---|---|
| Set `track_changes = 1` on Dispatch Case | **NOT DONE** | Still `0` at `custom-doctypes.json` line 952 |

### Script Cleanup / Disabling

All 7 scripts planned for disabling are **still enabled** (`Enabled: 1`):

| Script | Planned Action | Current Status |
|---|---|---|
| `Dispatch Case-Form.js` | SIMPLIFY (remove `allow_items_edit`, hardcoded approvers, lock/unlock) | **Not simplified** — `allow_items_edit`, hardcoded approver emails, custom lock/unlock all still present |
| `Dispatch Case-Simplify for Order Creation.js` | DISABLE | **Still enabled** |
| `Dispatch Case-Lock Submitted.js` | DISABLE | **Still enabled** |
| `Dispatch Case-Products Button.js` | DISABLE | **Still enabled** |
| `Dispatch Case-Packing Scan.js` | DISABLE | **Still enabled** |
| `Dispatch Case-Template Auto Fill.js` | DISABLE | **Still enabled** |
| `Dispatch Case-Item Code String Guard.js` | DISABLE | **Still enabled** |
| `Dispatch Case Item-Auto Fill Item Name.js` | DISABLE | **Still enabled** |

Scripts planned to KEEP (no action needed):

| Script | Status |
|---|---|
| `Dispatch Case-Price Visibility.js` | Kept (enabled) |
| `Dispatch Case-Packing Problem Alerts.js` | Kept (enabled) |
| `Dispatch Case-Photo-Galleries.js` | Kept (enabled) |

---

## Phase 3: Cancel Flow — Not Implemented

None of the Phase 3 items have been implemented:

| Plan Item | Status |
|---|---|
| Cancel API script (`dispatch_case_cancel.py`) | **Not created** |
| "Cancel Dispatch" button on Task form | **Not added** to `Task-Action Buttons.js` |
| Cancel flow handlers in `Task-after-save-dispatch-flow.py` | **Not present** — no "Dispatch Cancel Restock" or "Return to warehouse" completion handlers |
| DC cancellation fields (`cancellation_reason`, `cancelled_by`, `cancelled_at`, `cancel_restock_stock_entry`) | **Not in schema** |
| `Cancelled` status option on Dispatch Case | **Not added** to DC status field |
| `Dispatch Cancel Restock` task kind | **Not added** to `task_kind` options |
| Task Access Policy records for cancel kinds | **Not created** |

Note: `docs/16a-unified-dispatch-flow-implementation.md` explicitly states (line 1325): _"Cancellation / error handling — these scripts do not implement cancellation flows... Those use the existing `Return to warehouse (aborted delivery / cancelled order)` task kind and are handled separately."_

---

## Remaining Work Summary

### Must-do to complete Phase 2

1. Add `allow_on_submit` property setter for `Dispatch Case Item-discount_pct`
2. Set `track_changes = 1` on Dispatch Case DocType
3. Simplify `Dispatch Case-Form.js` (remove `allow_items_edit`, hardcoded approvers, custom lock/unlock)
4. Disable 7 DC client scripts (set `Enabled: 0`)

### Must-do to complete Phase 3

1. Create 4 cancellation custom fields on Dispatch Case
2. Add `Cancelled` to DC status options
3. Add `Dispatch Cancel Restock` to `task_kind` options
4. Create Task Access Policy records for the 2 cancel task kinds
5. Create `dispatch_case_cancel.py` server script
6. Add "Cancel Dispatch" button to `Task-Action Buttons.js`
7. Add cancel completion handlers to `Task-after-save-dispatch-flow.py`

---

## Files Modified by This Plan (for reference)

### Server Scripts (`deploy/test/work/server/`)

| File | Change Type |
|---|---|
| `dispatch_task_accept.py` | Modified — auto-create DC |
| `Task-before-save-dispatch-gates.py` | Modified — field sync + completion gate |
| `Task-after-save-dispatch-flow.py` | Modified — Pack guard + Discount Approval handler |
| `Dispatch-Case-before-save.py` | Modified — removed discount detection |
| `task_apply_template.py` | Created — template auto-fill API |
| `task_mark_items_packed_batch.py` | Modified — added `ignore_validate_update_after_submit` |
| `task_mark_item_packed.py` | Modified — added `ignore_validate_update_after_submit` |
| `task_update_return_item_quantities.py` | Modified — added `ignore_validate_update_after_submit` |
| `Task-after-save-advance-payment.py` | Modified — added `ignore_validate_update_after_submit` |

### Client Scripts (`deploy/test/work/client/`)

| File | Change Type |
|---|---|
| `Task-Action Buttons.js` | Modified — "View DC" link, DC fallback kept |
| `Task-Product Work Area.js` | Modified — Order entry renderer + template handler |
| `Task-Field-Visibility.js` | Modified — Order Entry field mappings |
| `Task-Accept Start.js` | Modified — delegated visibility to Field-Visibility.js |

### Schema (`deploy/test/schema/`)

| File | Change |
|---|---|
| `custom-fields.json` | 4 new Task fields added |
| `property-setters.json` | 10 of 11 `allow_on_submit` setters added |
