# Dispatch Flow Redesign v4 — Implementation Status

**Plan:** `plan-92e19be24c1dcf3f.md` (session: defiant-termite, 2026-09-02)
**Audited:** 2026-09-09 (updated after Phase 2 deployment)
**Source plans:**
- v4 redesign: `C:\Users\Vahe\.devin\plans\plan-92e19be24c1dcf3f.md`
- Packing cleanup: `C:\Users\Vahe\.devin\plans\plan-93c3694240f4a2eb.md`

---

## Executive Summary

The v4 plan defined 3 phases. Phase 1 is complete. Phase 2 (all sub-phases) is fully deployed to Test as of 2026-09-09. Phase 3 (cancel flow) is not started and requires design decisions before implementation — see `deploy/test/work/phase3-cancel-flow-plan.md`.

| Phase | Status | Completion |
|---|---|---|
| Phase 1 — Order Entry Redesign | **Complete** | ~95% |
| Phase 2 — DC Form Cleanup | **Deployed** (2026-09-09) | 100% |
| Phase 2b — Packing Field Cleanup | **Deployed** | 100% |
| Phase 2c — Product Area Redesign | **Deployed** | 100% |
| Phase 2d — Scan visibility fix | **Deployed** | 100% |
| Phase 3 — Cancel Flow | **Not started** — plan written, needs design review | 0% |

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

## Phase 2: DC Form Cleanup — Deployed (2026-09-09)

**Deploy script:** `deploy/test/scripts/deploy-phase2-dc-cleanup.ps1`

### Property Setters (`allow_on_submit = 1`) — Done

**DC parent fields (all done):** `customer`, `return_expected`, `client_location_warehouse`, `notes`, `case_items`, plus additional: `surgery_date`, `surgery_set_type`, `order_entry_task`, `discount_approval_task`, `discount_approval_status`, `pack_task`, `total_paid_amount`, `outstanding_amount`.

**DC Item child fields (all done):** `item_code`, `item_name`, `dispatched_qty`, `unit_price`, `batch_no`, `serial_no`, `returned_qty`, `lost_damaged_qty`, `used_qty`, `custom_scanned_qty`, `discount_pct`.

`discount_pct` `allow_on_submit` created (verified in exported `property-setters.json` line 3467).

### Version History — Done

`track_changes = 1` on Dispatch Case (verified in exported `custom-doctypes.json` line 952).

### Dead Field Cleanup — Done

`allow_items_edit` custom field on Dispatch Case — deleted. Was only used by the removed lock logic in `Dispatch Case-Form.js`.

### DC Client Script Cleanup — Done

| Script | Action | Status |
|---|---|---|
| `Dispatch Case-Form.js` | **SIMPLIFIED** | Removed `allow_items_edit`, hardcoded `APPROVER_EMAILS`, lock/unlock. Kept: reqd removal, field hiding, mobile cleanup, `return_expected` styling. Deploy Step 4. |
| `Dispatch Case-Lock Submitted.js` | **DISABLED** | Conflicts with `allow_on_submit` model. Server-side `Dispatch-Case-before-save-lock-submitted.py` is the authoritative lock. Deploy Step 5. |
| `Dispatch Case-Packing Scan.js` | **DELETED** | Phase 2b (already deployed) |
| `Dispatch Case-Packing Problem Alerts.js` | **DELETED** | Phase 2b (already deployed) |
| `Dispatch Case-Simplify for Order Creation.js` | **KEEP** | Useful for Order Creating role navigating DC directly |
| `Dispatch Case-Products Button.js` | **KEEP** | Useful for Director corrections on DC |
| `Dispatch Case-Template Auto Fill.js` | **KEEP** | Useful for Director corrections on DC |
| `Dispatch Case-Item Code String Guard.js` | **KEEP** | Defensive string coercion, low cost |
| `Dispatch Case Item-Auto Fill Item Name.js` | **KEEP** | Auto-fetch item_name, useful |
| `Dispatch Case-Price Visibility.js` | **KEEP** | Role-based price hiding |
| `Dispatch Case-Photo-Galleries.js` | **KEEP** | Read-only photo display |

---

## Phase 2b: Packing Field Cleanup — Deployed

**Plan:** `plan-93c3694240f4a2eb.md` (session: salty-hero, 2026-09-08)
**Deploy script:** `deploy/test/scripts/deploy-packing-field-cleanup.ps1`

This plan removes 12 derived/dead custom fields, deletes 3 scripts, and updates 9 scripts. The completion gate replaces the packing-status validation; `custom_scanned_qty` vs `dispatched_qty` is the only check needed.

### Schema: Delete 12 Custom Fields — DONE

All 12 custom fields deleted (5 on Dispatch Case Item, 7 on Dispatch Case). 2 property setters deleted. `custom_scanned_qty.insert_after` fixed to `dispatched_qty`. Verified absent from exported `custom-fields.json`.

### Scripts: Delete 3 — DONE

All 3 scripts deleted: `Dispatch Case-packing-problem-alerts.py` (server), `Dispatch Case-Packing Problem Alerts.js` (client), `Dispatch Case-Packing Scan.js` (client).

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

## Phase 2c: Product Area Redesign — Deployed

**Deploy script:** `deploy/test/scripts/deploy-product-area-redesign.ps1`

Deleted 2 Task custom fields (`custom_product_work_column`, `custom_task_product_warning`). Cleaned stale `field_order` Property Setter (removed 7 ghost/deleted entries). Updated 3 client scripts. Product table now full-width. DC/customer headers removed from all renderers.

## Phase 2d: Scan Visibility Fix — Deployed

**Root cause:** `Task-Account Details UI Cleanup.js` toggled scan/product fields visible for all non-Account-Details tasks (including Order Entry), overriding TFV with repeated setTimeout at 200/800/1600/3000ms.

**Fix:** Removed all TFV-owned field toggles from Account Details script. Added AGENTS.md rule: only TFV may toggle visibility of `TFV_KIND_MAP` fields.

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

### A. Phase 3 (Cancel Flow) — not started, requires design decisions

1. Review and approve `deploy/test/work/phase3-cancel-flow-plan.md`
2. Resolve open design questions (who can cancel, at which states, stock reversal rules)
3. Implement per the approved plan

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
| `Dispatch Case-Form.js` | **SIMPLIFIED** — removed allow_items_edit/approvers/lock | v4 Phase 2 (deployed 2026-09-09) |
| `Dispatch Case-Lock Submitted.js` | **DISABLED** — conflicts with allow_on_submit | v4 Phase 2 (deployed 2026-09-09) |
| `Dispatch Case-Packing Scan.js` | **DELETED** | Packing cleanup (deployed) |
| `Dispatch Case-Packing Problem Alerts.js` | **DELETED** | Packing cleanup (deployed) |

### Schema (`deploy/test/schema/`)

| File | Change | Plan |
|---|---|---|
| `custom-fields.json` | 4 Task fields added; 12 DC/DCI fields deleted; 2 Task fields deleted; `allow_items_edit` deleted | v4 Phase 1 + Packing + Product Area + Phase 2 |
| `property-setters.json` | 10+ `allow_on_submit` setters incl. `discount_pct`; 2 packing setters deleted | v4 Phase 2 + Packing |
| `custom-doctypes.json` | `track_changes = 1`; `Cancelled` status not added | v4 Phase 2 + Phase 3 |
