# 21 — Product Section Architecture

**Date:** 2026-09
**Status:** Current (deployed to test, Phases A/B/C + packing field cleanup complete)
**Related:** `docs/16-unified-dispatch-flow.md` (Dispatch Case data model), `docs/20-custom-buttons-and-actions.md` (action buttons), `deploy/test/work/product-section-per-task-kind-plan.md` (original phased plan)

---

## 1. Overview

The product section on the Task form displays Dispatch Case item rows and provides task-specific controls for managing them. Each task kind sees only the product data and actions appropriate to its role:

| Task Kind | Product Section Behavior |
|---|---|
| **Order entry** | Inline editable table: add, edit, remove products |
| **Pack / prepare items** | Packing table with scan fields and per-row packed checkboxes |
| **Returns processing / verification** | Returns table with scan fields and returned-qty inputs |
| **Returns restocking** | Read-only restocking summary (returned rows only) |
| **Invoice preparation** | Read-only invoice summary (used/damaged rows only) |
| **Other dispatch tasks** | Read-only packing-style table |
| **Non-product tasks** | Section hidden entirely |

There are **no product buttons** in the page header or mobile sub-header. All product controls are colocated with the product table inside `custom_task_product_summary`.

---

## 2. Architecture

### 2.1 Rendering Surface

All product UI renders into a single HTML field: `custom_task_product_summary` (Custom Field, type HTML). The field is a Frappe "summary" field — its `$wrapper` is replaced entirely on each refresh. This is the same mechanism used by Pack checkboxes, Returns quantity inputs, and the Order Entry inline editor.

### 2.2 Visibility Control

**Task-Field-Visibility.js** (TFV) is the single source of truth for which fields are visible on which task kinds. It owns:

- `tfv_is_product_task(frm)` — authoritative classification for whether a task shows the product section. Returns `true` for Pack, Returns processing, and Order Entry (when DC is linked).
- `tfv_is_scan_product_task(frm)` — returns `true` only for Pack and Returns processing (when DC is linked). Controls scan field visibility.
- `TFV_KIND_MAP` — field-to-rule mapping. Product-related rules:
  - `"__product__"` — visible when `tfv_is_product_task(frm)` (section, summary, warning)
  - `"__scan_product__"` — visible when `tfv_is_scan_product_task(frm)` (scan barcode, scan qty, scan result)
- Dynamic labels/descriptions per task kind (dispatch_case label, product section label)

**No other script should toggle product field visibility.** TFV runs on `refresh`, `task_kind`, `dispatch_case`, and `order_return_expected` events.

### 2.3 Product Work Area Script

**Task-Product Work Area.js** (PWA) is responsible for:

1. **Fetching DC data** — calls `frappe.client.get` for the linked Dispatch Case
2. **Routing** — dispatches to the correct renderer based on `task_kind`
3. **Rendering** — builds HTML tables with interactive controls per task kind
4. **Server API calls** — add, update, remove products; packing scan; returns toggle
5. **Scan flow** — barcode lookup, GS1 LOT parsing, packing scan orchestration

PWA uses `tfv_is_product_task(frm)` from TFV (no local duplicate).

### 2.4 Data Model

Products live in Dispatch Case → `case_items` (child table). The Task form never stores product data — it always reads from the DC. Key columns:

| Column | Set by | Editable from Task |
|---|---|---|
| `item_code` | Order Entry (add) | No (read-only after add) |
| `item_name` | Server (auto-filled from Item) | No |
| `dispatched_qty` | Order Entry (inline edit) | Yes (Order Entry only) |
| `unit_price` | Order Entry (inline edit) | Yes (Order Entry only) |
| `discount_pct` | Order Entry (inline edit) | Yes (Order Entry only) |
| `batch_no` | Order Entry (inline edit) or Pack scan | Yes (Order Entry inline, Pack via scan) |
| `custom_scanned_qty` | Pack scan/checkbox API | No (server-set) |
| `custom_last_scanned_barcode` | Pack scan API | No (server-set, audit trail) |
| `custom_last_scan_at` | Pack scan API | No (server-set, audit trail) |
| `custom_last_scanned_by` | Pack scan API | No (server-set, audit trail) |
| `custom_fefo_warning` | Pack scan API | No (server-set, batch expiry check) |
| `returned_qty` | Returns processing | No (Returns only) |
| `lost_damaged_qty` | Returns processing | No (Returns only) |
| `used_qty` | Server (dispatched - returned - lost) | No (server-set) |

> **Removed fields (packing cleanup, 2026-09):** `custom_packing_status`, `custom_remaining_qty`, `custom_scan_note`, `custom_problem_reason`, `custom_problem_alert_sent` — all were either derived from `dispatched_qty` + `custom_scanned_qty` or never written by any code. Packing status is now computed client-side from quantities. Remaining qty is computed as `max(dispatched - scanned, 0)`.
>
> **Removed DC-level fields:** `custom_packing_scan_barcode/qty/result`, `custom_packing_last_warning`, `custom_packing_problem_status/summary`, `custom_problem_alert_sent` — DC scan was redundant with Task scan; problem alert system fired during normal packing and was replaced by the completion gate.

---

## 3. Server APIs

| API | Purpose | Called by |
|---|---|---|
| `task_add_dispatch_product` | Add a new item row to DC | Order Entry inline editor (+Add button) |
| `task_update_dispatch_product` | Update qty/price/discount/batch on existing row | Order Entry inline editor (debounced auto-save) |
| `task_remove_dispatch_product` | Remove a row from DC | Order Entry inline editor (x Remove button) |
| `task_lookup_product_barcode` | Look up Item from barcode | Pack/Returns scan flow |
| `dispatch_case_packing_scan` | Record scanned qty, check FEFO | Pack scan flow (Task-level only; DC-level scan UI removed) |
| `task_mark_item_packed` | Toggle single row packed/unpacked | Pack checkbox toggle |
| `task_mark_items_packed_batch` | Toggle all rows packed/unpacked | Pack/Returns batch toggle |

All API scripts live in `deploy/test/work/server/` and follow RestrictedPython constraints (see `AGENTS.md`).

---

## 4. Order Entry — Inline Editor

### 4.1 Behavior

When an accepted Order Entry task has a linked DC, the product section renders an inline editable table:

- **Existing rows**: editable `<input>` for qty, price, discount%, batch. Read-only item name. Red x remove button.
- **Add row** (bottom): Frappe Link control for item search (autocomplete), qty/price/discount/batch inputs, blue + Add button.
- **Empty state** (0 rows): shows the add row so the user can immediately start adding products.

### 4.2 Editability Check

```javascript
var is_editable = !frm.is_new()
    && frm.doc.task_kind === "Order entry"
    && frm.doc.dispatch_case
    && frm.doc.status !== "Completed"
    && frm.doc.custom_accepted_by === frappe.session.user;
```

When not editable (completed task, different user, etc.), a read-only table is shown instead.

### 4.3 Auto-save

Inline edits use debounced auto-save (800ms). When the user stops typing in any editable cell, the entire row is sent to `task_update_dispatch_product`. No save-on-blur.

### 4.4 Add Flow

1. User selects an item via the Frappe Link control (autocomplete search)
2. Price auto-fills from Item's `standard_rate`
3. User clicks + Add
4. `task_add_dispatch_product` is called
5. On success, the product table re-renders (new row appears, add row clears)

### 4.5 Remove Flow

1. User clicks x on a row
2. Confirmation dialog appears
3. `task_remove_dispatch_product` is called
4. On success, the product table re-renders

### 4.6 Re-render Behavior

The product summary is fully replaced on every refresh. Triggers include:
- Initial form load
- `frm.reload_doc()` (manual or auto-reload)
- `dispatch_case` field change
- `task_kind` field change
- After add/remove/template-apply callbacks

Auto-reload (from `Task-Auto Reload.js`) is **not blocked**. If another user changes the Task while an inline edit is in progress, the reload proceeds and the uncommitted edit may be lost. This is acceptable — debounced saves fire within 800ms, and stale-data conflicts are worse than losing a keystroke.

---

## 5. Pack — Scan Flow

### 5.1 Barcode Types

| Barcode prefix | Type | What happens |
|---|---|---|
| `]C111` | GS1 LOT/expiry | Parsed for LOT number and expiry date |
| (other) | REF / product barcode | Looked up via `task_lookup_product_barcode` |

### 5.2 Two-Step Scan (items with batch tracking)

1. **REF scan** → identifies item → stored in JS variable `pwa_pending_item_code`
2. **LOT scan** (via popup dialog or direct scan field) → captures batch/expiry → calls `task_packing_scan` with both item and batch

For items without batch tracking, the REF scan alone triggers `task_packing_scan`.

### 5.3 Scan State

The temporary item code from REF barcode scanning is stored in a **JavaScript module variable** (`pwa_pending_item_code`), not a Frappe field. This was refactored in Phase C — previously it used `custom_task_add_item_code` which has been deleted from the schema.

### 5.4 Packing Table

The Pack renderer shows each DC item row with:
- Item name, dispatched qty, scanned qty, remaining qty (computed as `max(dispatched - scanned, 0)`)
- Packed checkbox (toggles `custom_scanned_qty` between 0 and dispatched_qty)
- Batch/LOT, expiry, FEFO warnings
- Color coding: green (fully scanned), orange (partial), gray (not started)
- Status is computed client-side: `Complete` (scanned >= dispatched), `Partial` (scanned > 0), `Pending` (scanned == 0)

### 5.5 Completion Gate

The Pack task cannot be completed unless all DC item rows have `custom_scanned_qty >= dispatched_qty`. This is enforced by `Task-before-save-dispatch-gates.py` (Before Save on Task). No stored status field is checked — the gate compares quantities directly.

---

## 6. Returns Processing

The Returns renderer shows each DC item row with:
- Item name, dispatched qty
- Returned qty input (editable inline)
- Lost/damaged qty input (editable inline)
- Mobile: compact card view with expand/collapse per row
- Desktop: full table with all columns

---

## 7. Labels and Descriptions

TFV applies task-specific labels dynamically:

| Task Kind | Section Label | Dispatch Case Label | Dispatch Case Description |
|---|---|---|---|
| Order entry | "Products" | "Dispatch Case" | "Auto-created on task acceptance. Products you add are stored here." |
| Pack / prepare items | "Products / Packing" | "Dispatch Case / Packing Items" | "Open to view batch/LOT, expiry, scanned qty, FEFO warnings, and packing problems." |
| Returns processing | "Products / Returns" | "Dispatch Case" | "Open to view product rows and return quantities." |
| Other dispatch | "Products / Dispatch Work" | "Dispatch Case" | (empty) |

---

## 8. Empty State Messages

| Condition | Order Entry | Other Tasks |
|---|---|---|
| No DC linked | "Accept this task to auto-create a Dispatch Case, then add products." (info) | "No Dispatch Case linked yet." (warning) |
| DC exists, 0 rows | Shows editor with add row + "No products yet. Use the row below to add items." | "No product rows in Dispatch Case." (warning) |

---

## 9. File Inventory

| File | Responsibility |
|---|---|
| `client/Task-Field-Visibility.js` | Visibility rules, product/scan classification, dynamic labels |
| `client/Task-Field-Editability.js` | Editability rules (`tfe_can_edit`, `TFE_EDIT_MAP`). No admin exemption. |
| `client/Task-Product Work Area.js` | Product rendering, inline editor, scan flow, packing checkboxes. Checks `tfe_can_edit`. |
| `client/Task-Action Buttons.js` | Action bar (no product controls — View DC button only) |
| `server/task_add_dispatch_product.py` | Add item row to DC (acceptance check) |
| `server/task_update_dispatch_product.py` | Update existing row in DC (acceptance check) |
| `server/task_remove_dispatch_product.py` | Remove row from DC (acceptance check) |
| `server/task_lookup_product_barcode.py` | Barcode → Item lookup |
| `server/dispatch_case_packing_scan.py` | Record scanned qty for packing (acceptance check) |
| `server/task_mark_item_packed.py` | Toggle single row packed/unpacked (acceptance check) |
| `server/task_mark_items_packed_batch.py` | Toggle all rows packed/unpacked (acceptance check) |
| `server/task_update_return_item_quantities.py` | Update return quantities (acceptance check) |
| `server/task_apply_template.py` | Apply surgical kit template to DC (acceptance check) |

---

## 10. Design Decisions

### 10.1 No header buttons

Product controls belong near the product table, not in the page header. The header is for task-level actions (Accept, Complete, Create DC). This was decided in Phase A after reviewing the UX problems caused by separated controls.

### 10.2 Single product-task classifier

`tfv_is_product_task` in TFV is the single authoritative source. Previous duplicates (`task_product_work_area_is_product_task` in PWA, `tab_is_product_task` in Action Buttons) were deleted in Phase C.

### 10.3 No save-on-blur

Inline edits use debounced auto-save only. Save-on-blur was explicitly rejected because it would fire on every tab-between-fields interaction.

### 10.4 Auto-reload not blocked

When another user/process changes the Task, auto-reload proceeds normally. An in-progress edit that hasn't reached the 800ms debounce timer may be lost. This is acceptable to prevent stale-data conflicts.

### 10.5 Scan state in JS variable

Pack scan flow stores the pending item code in `pwa_pending_item_code` (a module-level JS variable) instead of a Frappe field. This avoids unnecessary server round-trips and form dirtying during the two-step scan.

### 10.6 Editability via TFE (added 2026-09)

All product section controls respect `tfe_can_edit(frm)` from `Task-Field-Editability.js`. If the current user has not accepted the task, or if the task is completed/cancelled:
- Order Entry: read-only table (no inputs, no add row, no remove buttons)
- Pack: checkboxes rendered with `disabled` attribute
- Returns: qty inputs and checkboxes rendered with `disabled` attribute
- Scan flow: blocked at entry point with error message
- Template apply: blocked, field cleared

**No admin exemption.** `accepted_by === session.user` is the only check. Server APIs also enforce this — calling `task_mark_item_packed` etc. without being the accepted user returns an error.

This replaced `Task-Lock Unaccepted.js` (which used setTimeout(700ms) and couldn't lock product HTML controls) and `Task-Lock Completed.js`.
