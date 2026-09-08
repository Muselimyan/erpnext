# Dispatch Flow Redesign v4 — Implementation Status

**Plan:** `plan-92e19be24c1dcf3f.md` (session: defiant-termite, 2026-09-02)
**Audited:** 2026-09-08 (full re-audit from scratch)
**Source plans:**
- v4 redesign: `C:\Users\Vahe\.devin\plans\plan-92e19be24c1dcf3f.md`
- Packing cleanup: `C:\Users\Vahe\.devin\plans\plan-93c3694240f4a2eb.md`

---

## Executive Summary

The v4 plan defined 3 phases. Phase 1 is complete. Phase 2 is split between two work streams (v4 cleanup + packing field cleanup) — the script-level work is mostly done but schema changes and script deletion/disabling remain. Phase 3 is not started. A separate **Product Area Redesign** removes 2 dead Task fields (`custom_product_work_column`, `custom_task_product_warning`).

| Phase | Status | Completion |
|---|---|---|
| Phase 1 — Order Entry Redesign | **Complete** | ~95% |
| Phase 2 — DC Form Cleanup | **In progress** | ~55% |
| Phase 2b — Packing Field Cleanup | **Scripts updated, deletion pending** | ~60% |
| Phase 2c — Product Area Redesign | **Source ready, deploy pending** | ~80% |
| Phase 3 — Cancel Flow | **Not started** | 0% |

---

## Phase 1: Order Entry Redesign — Complete

### Server Scripts — All Done

| Plan Item | Script | Status |
|---|---|---|
| Auto-create Draft DC on accept | `dispatch_task_accept.py` | **Done** — creates DC Draft, links via `order_entry_task`, copies customer |
| Order Entry field sync to DC | `Task-before-save-dispatch-gates.py` | **Done** — syncs `order_return_expected`, `order_client_location_warehouse`, `order_surgery_date`, `customer` |
| Completion gate with discount detection | `Task-before-save-dispatch-gates.py` | **Done** — validates items, warehouse when return expected, detects discounts, auto-submits or Awaiting Approval |
| DC docstatus guard | `Task-before-save-dispatch-gates.py` | **Done** — skips if DC already submitted |
| Remove discount detection from DC before_save | `Dispatch-Case-before-save.py` | **Done** — only `used_qty` calc remains |
| Pack task creation guard | `Task-after-save-dispatch-flow.py` | **Done** — Pack only if DC docstatus=1 |
| Discount Approval completion handler | `Task-after-save-dispatch-flow.py` | **Done** — Approved: submits DC + Pack. Rejected: Draft + new Order Entry |
| Template auto-fill API | `task_apply_template.py` | **Done** — created |
| `ignore_validate_update_after_submit` hardening | 5 scripts | **Done** — `task_mark_items_packed_batch.py`, `task_mark_item_packed.py`, `task_update_return_item_quantities.py`, `Task-after-save-advance-payment.py`, `dispatch_case_packing_scan.py` |
| Keep `task_create_dispatch_case.py` as fallback | `task_create_dispatch_case.py` | **Done** — still enabled |

### Client Scripts — All Done

| Plan Item | Script | Status |
|---|---|---|
| "View DC" link | `Task-Action Buttons.js` | **Done** — mobile + desktop |
| "Create DC" fallback | `Task-Action Buttons.js` | **Done** — hidden when DC auto-created |
| Order entry in product kinds | `Task-Product Work Area.js` | **Done** |
| Order-entry renderer | `Task-Product Work Area.js` | **Done** — `task_product_work_area_render_order_entry()` |
| Template handler | `Task-Product Work Area.js` | **Done** — `order_template` onchange |
| Field visibility | `Task-Field-Visibility.js` | **Done** — single source of truth |
| Visibility delegation | `Task-Accept Start.js` | **Done** — only mobile/layout cosmetics |

### Schema — All Done

All 4 new Task custom fields exist in `custom-fields.json` (`hidden: 1`, revealed by `Task-Field-Visibility.js`):
- `order_return_expected` (Check)
- `order_client_location_warehouse` (Link → Warehouse)
- `order_surgery_date` (Date)
- `order_template` (Link → Surgical Kit Template)

### Phase 1 Minor Gap

- Client-side discount confirmation dialog (plan §2.7.E) — not verified whether `frappe.confirm()` fires before completing Order Entry with discounted items.

---

## Phase 2: DC Form Cleanup — In Progress

### Property Setters (`allow_on_submit = 1`) — Mostly Done

**DC parent fields (all done):** `customer`, `return_expected`, `client_location_warehouse`, `notes`, `case_items`, plus additional: `surgery_date`, `surgery_set_type`, `order_entry_task`, `discount_approval_task`, `discount_approval_status`, `pack_task`, `total_paid_amount`, `outstanding_amount`.

**DC Item child fields:**

| Field | Status |
|---|---|
| `item_code` | **Done** |
| `item_name` | **Done** |
| `dispatched_qty` | **Done** |
| `unit_price` | **Done** |
| `batch_no` | **Done** |
| `serial_no` | **Done** |
| `returned_qty` | **Done** |
| `lost_damaged_qty` | **Done** |
| `used_qty` | **Done** |
| `custom_scanned_qty` | **Done** |
| `discount_pct` | **NOT DONE** — only has `permlevel` setter, no `allow_on_submit` |

### Version History — Not Done

| Plan Item | Status |
|---|---|
| `track_changes = 1` on Dispatch Case | **NOT DONE** — still `0` at `custom-doctypes.json` line 952 |

### DC Client Script Cleanup — Not Done

The v4 plan listed 7 scripts to disable and 1 to simplify. **None have been disabled or simplified.** However, the packing cleanup plan (Phase 2b) supersedes 2 of these — they will be **deleted** rather than disabled.

| Script | v4 Plan | Packing Plan | Current |
|---|---|---|---|
| `Dispatch Case-Form.js` | SIMPLIFY | — | **Still has** `allow_items_edit`, hardcoded approvers, lock/unlock |
| `Dispatch Case-Simplify for Order Creation.js` | DISABLE | — | **Enabled** (but already cleaned of packing field refs) |
| `Dispatch Case-Lock Submitted.js` | DISABLE | — | **Enabled** |
| `Dispatch Case-Products Button.js` | DISABLE | — | **Enabled** |
| `Dispatch Case-Template Auto Fill.js` | DISABLE | — | **Enabled** |
| `Dispatch Case-Item Code String Guard.js` | DISABLE | — | **Enabled** |
| `Dispatch Case Item-Auto Fill Item Name.js` | DISABLE | — | **Enabled** |
| `Dispatch Case-Packing Scan.js` | DISABLE | **DELETE** | **Enabled** (superseded by packing cleanup) |
| `Dispatch Case-Packing Problem Alerts.js` | KEEP | **DELETE** | **Enabled** (v4 said KEEP, packing plan says DELETE) |
| `Dispatch Case-Price Visibility.js` | KEEP | — | **Enabled** (correct) |
| `Dispatch Case-Photo-Galleries.js` | KEEP | — | **Enabled** (correct) |

---

## Phase 2b: Packing Field Cleanup — Scripts Updated, Schema Pending

**Plan:** `plan-93c3694240f4a2eb.md` (session: salty-hero, 2026-09-08)
**Deploy script:** `deploy/test/scripts/deploy-packing-field-cleanup.ps1`

This plan removes 12 derived/dead custom fields, deletes 3 scripts, and updates 9 scripts. The completion gate replaces the packing-status validation; `custom_scanned_qty` vs `dispatched_qty` is the only check needed.

### Schema: Delete 12 Custom Fields — NOT DONE

**Dispatch Case Item (5 fields to delete):**

| Field | Reason | Currently in schema? |
|---|---|---|
| `custom_packing_status` | Derived from quantities | Yes — still exists |
| `custom_remaining_qty` | Derived (`dispatched - scanned`) | Yes — still exists |
| `custom_scan_note` | Never written by any code | Yes — still exists |
| `custom_problem_reason` | Never written by any code | Yes — still exists |
| `custom_problem_alert_sent` | Dead alert system | Yes — still exists |

**Dispatch Case (7 fields to delete):**

| Field | Reason | Currently in schema? |
|---|---|---|
| `custom_packing_scan_barcode` | DC scan removed | Yes — still exists |
| `custom_packing_scan_qty` | DC scan removed | Yes — still exists |
| `custom_packing_scan_result` | DC scan removed | Yes — still exists |
| `custom_packing_last_warning` | DC scan removed | Yes — still exists |
| `custom_packing_problem_status` | Alert system removed | Yes — still exists |
| `custom_packing_problem_summary` | Alert system removed | Yes — still exists |
| `custom_problem_alert_sent` | Alert system removed | Yes — still exists |

**2 Property Setters to delete:** `custom_packing_status-allow_on_submit`, `custom_remaining_qty-allow_on_submit` — still exist.

**Fix:** `custom_scanned_qty.insert_after` → `dispatched_qty` (currently points to `custom_packing_status` which is being deleted).

### Scripts: Delete 3 — NOT DONE

| Script | Type | Status |
|---|---|---|
| `Dispatch Case-packing-problem-alerts.py` | Server (After Save, DC) | **Still exists and enabled** — only remaining script using cleanup fields |
| `Dispatch Case-Packing Problem Alerts.js` | Client (DC) | **Still exists and enabled** |
| `Dispatch Case-Packing Scan.js` | Client (DC) | **Still exists and enabled** |

### Scripts: Update 6 Server — DONE

All 6 server scripts have already been cleaned of packing-status/remaining-qty references:

| Script | Cleanup | Status |
|---|---|---|
| `task_add_dispatch_product.py` | Removed `custom_scanned_qty=0`, `custom_remaining_qty`, `custom_packing_status` writes | **Done** |
| `task_update_dispatch_product.py` | Removed `custom_remaining_qty` recalc | **Done** |
| `task_mark_item_packed.py` | Simplified to `row.custom_scanned_qty = required_qty if packed else 0` | **Done** |
| `task_mark_items_packed_batch.py` | Same pattern | **Done** |
| `dispatch_case_packing_scan.py` | Removed status/remaining/DC-level field writes | **Done** |
| `Task-before-save-dispatch-gates.py` | Pack gate now uses `scanned_qty < dispatched_qty` instead of status check | **Done** |

### Scripts: Update 3 Client — DONE

| Script | Cleanup | Status |
|---|---|---|
| `Task-Product Work Area.js` | Computes `remaining` inline, removed `custom_problem_reason`/`custom_packing_status` refs, warning lines simplified | **Done** |
| `Dispatch Case-Simplify for Order Creation.js` | Removed all 5 deleted Item fields + 4 deleted DC fields from hide lists | **Done** |
| `Dispatch Case-Form.js` | Removed deleted DC fields from mobile hide list | **Done** |

---

## Phase 2c: Product Area Redesign — Source Ready, Deploy Pending

**Deploy script:** `deploy/test/scripts/deploy-product-area-redesign.ps1`

Removes 2 dead Task custom fields and cleans all references from scripts:

| Field to Delete | Reason |
|---|---|
| `custom_product_work_column` | Column Break — not needed with full-width product table |
| `custom_task_product_warning` | Warning field — no longer written by any script |

**Scripts updated (source files):**
- `Task-Product Work Area.js` — all `frm.set_value("custom_task_product_warning", ...)` calls removed, DC/customer header lines removed from all renderers
- `Task-Field-Visibility.js` — removed `custom_task_product_warning` mapping and column break comment
- `Task-Account Details UI Cleanup.js` — removed both fields from hide lists

**Schema deletion not yet deployed.**

---

## Phase 3: Cancel Flow — Not Started

None of the Phase 3 items have been implemented:

| Plan Item | Status |
|---|---|
| Cancel API script (`dispatch_case_cancel.py`) | **Not created** |
| "Cancel Dispatch" button on Task form | **Not added** |
| Cancel flow handlers in `Task-after-save-dispatch-flow.py` | **Not present** |
| DC cancellation fields (`cancellation_reason`, `cancelled_by`, `cancelled_at`, `cancel_restock_stock_entry`) | **Not in schema** |
| `Cancelled` status option on Dispatch Case | **Not added** |
| `Dispatch Cancel Restock` task kind | **Not added** to `task_kind` options |
| Task Access Policy records for cancel kinds | **Not created** |

Note: `docs/16a-unified-dispatch-flow-implementation.md` states: _"Cancellation / error handling — these scripts do not implement cancellation flows... handled separately."_

---

## Related Work (Deployed, Outside v4 Scope)

These changes support the dispatch flow but were done outside the v4 plan:

| Work | Key Scripts/Docs | Status |
|---|---|---|
| **Task Action Buttons unification** | `Task-Action Buttons.js`, `deploy-header-unification.ps1` | Deployed — single source of truth for Accept/Complete/Create DC/View DC buttons |
| **Product Section Phases A/B/C** | `Task-Product Work Area.js`, `deploy-product-section-phase-{a,b,c}.ps1` | Deployed — inline editing, add/update/remove APIs, per-kind renderers |
| **Field Visibility system** | `Task-Field-Visibility.js`, `deploy-field-visibility.ps1` | Deployed — single source of truth, all other scripts delegate |
| **Photo system** | `Task-Photo-System.js`, `deploy-photo-improvements.ps1` | Deployed — photo galleries, completion gates, Doc 18 |
| **Doc 20** | `docs/20-custom-buttons-and-actions.md` | Written — documents button architecture |
| **Doc 21** | `docs/21-product-section-architecture.md` | Written — documents product section, lists removed packing fields |
| **Order Entry redesign deployment** | `deploy-order-entry-redesign.ps1` | Created — atomic Phase 1 deploy script |

---

## Current System Inventory (2026-09-08)

| Category | Total | Enabled | Disabled |
|---|---|---|---|
| Server scripts | 49 | 45 | 4 |
| Client scripts | 37 | 24 | 13 |

**Disabled server scripts:** `Item-before-save-reorder-change-reason.py`, `Payment Entry-after-submit-distribute-payment.py`, `Purchase Order-validate-one-supplier.py`, `perm_disable_batch_expiry_dbset.py` (still enabled but one-off utility).

**Disabled client scripts:** `Global-Mobile Back Button.js`, `Order entry - barcode scanning section - hide.js`, `Task Product Line-Item Code String Guard.js`, `Task-Account Details UI Cleanup.js`, `Task-Create Dispatch Case Items.js`, `Task-Delivery UI Fix.js`, `Task-Dispatch Packing Usability.js`, `Task-Header Long Subject Fix.js`, `Task-Inspect Returns Next Assign Visible.js`, `Task-Lock Completed.js` (was temporarily disabled?), `Task-Mobile Form Layout Fix.js`, `Task-Packing Checkboxes.js`, `Task-Product Lines Display.js`.

---

## Remaining Work — Ordered by Priority

### A. Deploy pending changes (source ready)

1. **Run `deploy-product-area-redesign.ps1`** — deletes `custom_product_work_column` + `custom_task_product_warning` fields, updates 3 client scripts
2. **Run `deploy-packing-field-cleanup.ps1`** — deletes 12 custom fields, 2 property setters, 3 scripts; updates 6 server + 3 client scripts

### B. Phase 2 schema gaps

3. Add `allow_on_submit` property setter for `Dispatch Case Item-discount_pct`
4. Set `track_changes = 1` on Dispatch Case DocType

### C. Phase 2 DC client script decisions

5. Simplify `Dispatch Case-Form.js` — remove `allow_items_edit`, hardcoded approvers, custom lock/unlock
6. Decide on remaining 5 DC scripts: disable or keep?
   - `Dispatch Case-Lock Submitted.js` — conflicts with `allow_on_submit` model
   - `Dispatch Case-Products Button.js` — items added via Task; still useful for direct DC editing?
   - `Dispatch Case-Template Auto Fill.js` — template loading moved to Task; still useful for direct DC?
   - `Dispatch Case-Item Code String Guard.js` — defensive; low cost to keep
   - `Dispatch Case Item-Auto Fill Item Name.js` — auto-fetch; low cost to keep
   - `Dispatch Case-Simplify for Order Creation.js` — Order creators use Task now; still useful for cleanup?

### D. Phase 3 (Cancel Flow) — not started, requires design decisions

7. Full cancel flow implementation (see Phase 3 section above)

---

## Files Modified by This Plan (Comprehensive)

### Server Scripts (`deploy/test/work/server/`)

| File | Change Type | Plan |
|---|---|---|
| `dispatch_task_accept.py` | Modified — auto-create DC | v4 Phase 1 |
| `Task-before-save-dispatch-gates.py` | Modified — field sync + completion gate + packing gate fix | v4 Phase 1 + Packing cleanup |
| `Task-after-save-dispatch-flow.py` | Modified — Pack guard + Discount Approval handler | v4 Phase 1 |
| `Dispatch-Case-before-save.py` | Modified — removed discount detection | v4 Phase 1 |
| `task_apply_template.py` | Created — template auto-fill API | v4 Phase 1 |
| `task_mark_items_packed_batch.py` | Modified — `ignore_validate_update_after_submit` + packing cleanup | v4 Phase 1 + Packing cleanup |
| `task_mark_item_packed.py` | Modified — same | v4 Phase 1 + Packing cleanup |
| `task_update_return_item_quantities.py` | Modified — `ignore_validate_update_after_submit` | v4 Phase 1 |
| `Task-after-save-advance-payment.py` | Modified — `ignore_validate_update_after_submit` | v4 Phase 1 |
| `task_add_dispatch_product.py` | Modified — removed packing field writes | Packing cleanup |
| `task_update_dispatch_product.py` | Modified — removed remaining_qty recalc | Packing cleanup |
| `dispatch_case_packing_scan.py` | Modified — removed status/remaining/DC-level writes | Packing cleanup |
| `Dispatch Case-packing-problem-alerts.py` | **To be DELETED** | Packing cleanup |

### Client Scripts (`deploy/test/work/client/`)

| File | Change Type | Plan |
|---|---|---|
| `Task-Action Buttons.js` | Modified — View DC, fallback Create DC | v4 Phase 1 |
| `Task-Product Work Area.js` | Modified — Order entry renderer + template handler + packing cleanup + product area cleanup | v4 Phase 1 + Packing + Product Area |
| `Task-Field-Visibility.js` | Modified — Order Entry fields + product warning removal | v4 Phase 1 + Product Area |
| `Task-Accept Start.js` | Modified — visibility delegation | v4 Phase 1 |
| `Task-Account Details UI Cleanup.js` | Modified — removed dead field refs | Product Area |
| `Dispatch Case-Simplify for Order Creation.js` | Modified — cleaned packing field refs | Packing cleanup |
| `Dispatch Case-Form.js` | Modified — cleaned packing field refs (still needs simplification) | Packing cleanup + v4 Phase 2 |
| `Dispatch Case-Packing Scan.js` | **To be DELETED** | Packing cleanup |
| `Dispatch Case-Packing Problem Alerts.js` | **To be DELETED** | Packing cleanup |

### Schema (`deploy/test/schema/`)

| File | Change | Plan |
|---|---|---|
| `custom-fields.json` | 4 Task fields added; 12 DC/DCI fields pending deletion; 2 Task fields pending deletion | v4 Phase 1 + Packing + Product Area |
| `property-setters.json` | 10+ `allow_on_submit` setters added; 2 packing setters pending deletion; `discount_pct` setter missing | v4 Phase 2 + Packing |
| `custom-doctypes.json` | `track_changes` still 0; `Cancelled` status not added | v4 Phase 2 + Phase 3 |
