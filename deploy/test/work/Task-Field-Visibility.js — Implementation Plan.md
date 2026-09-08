---
agent: devin-local
session: lean-lipstick
created: 2026-09-02T22:12:25Z
---
# Task-Field-Visibility.js — Implementation Plan

Implement a new centralized client script `Task-Field-Visibility.js` that is the single source of truth for all field/section show/hide logic on the Task form, then migrate visibility calls out of existing scripts phase by phase.

---

## Principles

1. **All custom fields hidden=1 by default** (schema). No `depends_on` for visibility.
2. **One script** (`Task-Field-Visibility.js`) calls `frm.toggle_display()` to reveal fields per `task_kind`.
3. Other scripts **never** call `toggle_display`, `set_df_property("hidden")`, or DOM `.hide()/.show()` for field visibility purposes.
4. Other scripts keep their behavioral responsibilities (buttons, scanning, photos, locking, etc.).
5. Runs on `refresh` and `task_kind` change. Runs early (no setTimeout for visibility).
6. **Deploy as a batch.** Phase 0+1 deploys together. Phases 2–7 should ideally deploy in the same session to eliminate the coexistence window where old scripts fight TFV.
7. **DOM exceptions:** Activity/Timeline and photo gallery containers are NOT Frappe fields — they have no fieldname and cannot use `toggle_display`. TFV uses targeted jQuery `.hide()` for these two cases only. This is the acknowledged exception to principle #3.

---

## Phase 0: Skeleton — New Script + Infra

**Goal:** Create `Task-Field-Visibility.js` with the complete visibility map and deploy it. No other scripts modified. The new script runs in parallel with existing scripts — fields may get toggled twice (once by new, once by old), but nothing breaks since both agree on what should be visible.

### Files

- **CREATE:** `deploy/test/work/client/Task-Field-Visibility.js`
- **CREATE:** `deploy/test/scripts/deploy-field-visibility.ps1`

### Script structure

```
// Name: Task-Field-Visibility
// DocType: Task
// Enabled: 1
// ---
// Single source of truth for Task form field/section visibility.
// Other scripts must NOT toggle field visibility.

// ── Always-hidden fields (internal, legacy, removed) ─────────
var TFV_ALWAYS_HIDDEN = [
    // Internal
    "task_access_policy", "dispatch_group_id",
    "custom_accepted_by", "custom_accepted_at",
    "custom_account_details_entry_task",
    // Legacy/removed/dead
    "driver_handover_note",
    "custom_account_details_section",
    "custom_account_details_subject",
    "custom_account_photos",
    "custom_product_lines",        // dead table, never populated
    // Standard fields
    "status", "priority",
    "project", "issue", "type", "color",
    "is_group", "task_weight", "parent_task", "is_template"
];

// ── Rule types ────────────────────────────────────────────────
// "__all__"             → always visible
// "__never__"           → always hidden
// "__completed__"       → visible only when status === "Completed"
// "__product__"         → visible when tfv_is_product_task(frm)
// "__add_product__"     → visible when Order entry + has dispatch_case
// "__has_value__"       → visible when field has a truthy value (value-based)
// "__dispatch_or_value__" → visible when dispatch flow kind OR field has value
// "__order_return__"    → visible when Order entry + order_return_expected checked
// [array]               → visible when kind is in the array

// ── Visibility map: field → rule ──────────────────────────────
var TFV_KIND_MAP = {
    // §1 Core
    "subject":          "__all__",
    "task_kind":        "__all__",
    "completed_at":     "__completed__",

    // §2 Assignment
    "custom_assigned_to":           "__all__",
    "custom_next_task_assign_to":   ["Order entry", "Pack / prepare items", "Delivery",
                                     "Return Call", "Pickup Returns",
                                     "Returns processing / verification",
                                     "Discount Approval", "Other: Entry"],

    // §3 Customer — show for dispatch kinds OR when has value (§3 redesign doc)
    // Must be visible on new Order entry so user can fill it in
    "customer":         "__dispatch_or_value__",

    // §3b Order Entry fields (Dispatch Redesign v4, §2.3)
    // These 4 fields are created by the dispatch redesign; hidden=1 by default.
    // TFV reveals them for Order entry. Fields don't exist until dispatch
    // redesign schema is deployed — toggle_display is a no-op for missing fields.
    "order_return_expected":            ["Order entry"],
    "order_client_location_warehouse":  "__order_return__",  // Order entry + return_expected checked
    "order_surgery_date":               ["Order entry"],
    "order_template":                   ["Order entry"],

    // §4 Dispatch Case — all dispatch flow kinds including debt/payment chain
    //     + Dispatch Cancel Restock (Dispatch Redesign v4, §4.4)
    "dispatch_case":    ["Order entry", "Pack / prepare items",
                         "Dispatch picking / hand-off", "Delivery",
                         "Return Call",
                         "Return to warehouse (aborted delivery / cancelled order)",
                         "Pickup Returns", "Return drop-off at warehouse",
                         "Returns processing / verification",
                         "Returns restocking",
                         "Invoice preparation / create invoice",
                         "Discount Approval",
                         "Debt Collection", "Distribute Payment",
                         "Payment Received", "Debt Closure Approval",
                         "Dispatch Cancel Restock"],

    // §5 Status dropdowns — always hidden (replaced by buttons)
    "delivery_status":  "__never__",
    "pickup_status":    "__never__",
    "dispatch_case_status": "__never__",

    // §6 Approval — 4 approval kinds (including Debt Closure Approval per redesign §6.2)
    "purchase_order":   ["Purchase Approval"],
    "approval_outcome": ["Purchase Approval", "Discount Approval",
                         "Write-off Approval", "Debt Closure Approval"],
    "approval_note":    ["Purchase Approval", "Discount Approval",
                         "Write-off Approval", "Debt Closure Approval"],

    // §7 Invoice / Sales — value-based (redesign doc: show when has value)
    "sales_invoice":    "__has_value__",

    // §8 Payment / Debt — payment_entry is value-based; rest are kind-based
    "payment_entry":           "__has_value__",
    "current_debt_amd":        ["Debt Collection"],
    "debt_threshold_amd":      ["Debt Collection"],
    "new_payment_amount":      ["Payment Received", "Debt Collection"],
    "payment_method_dc":       ["Payment Received", "Debt Collection"],
    "payment_reference_dc":    ["Payment Received", "Debt Collection"],
    "total_outstanding":       ["Debt Collection", "Distribute Payment",
                                "Debt Closure Approval"],
    "available_advance_credit":["Debt Collection", "Distribute Payment",
                                "Debt Closure Approval"],
    "custom_case_profit":      ["Debt Collection", "Distribute Payment",
                                "Debt Closure Approval"],
    "custom_total_amount_paid":["Debt Collection", "Distribute Payment",
                                "Debt Closure Approval"],
    "open_invoices":           ["Debt Collection", "Distribute Payment",
                                "Debt Closure Approval"],
    "payment_history":         ["Debt Collection", "Distribute Payment",
                                "Debt Closure Approval"],

    // §9 Returns
    "return_pickup_driver":   ["Pickup Returns", "Return drop-off at warehouse",
                               "Return to warehouse (aborted delivery / cancelled order)"],
    "scheduled_return_date":  ["Pickup Returns", "Return drop-off at warehouse"],

    // §10 Other
    "other_items":    ["Other: Entry", "Other: Processing"],
    "other_budget":   ["Other: Entry", "Other: Processing"],
    "other_supplier": ["Other: Entry", "Other: Processing"],

    // §14 Product Work Section (Pack, Returns proc, Order entry with DC)
    "custom_product_work_section":  "__product__",
    "custom_task_product_summary":  "__product__",
    // NOTE: custom_product_work_column is a Column Break — inherits from
    // parent section, do NOT toggle individually (redesign doc §16.1)
    "custom_task_product_warning":  "__product__",

    // §15 Barcode Scanning (same as product)
    "custom_barcode_section":       "__product__",
    "custom_task_scan_barcode":     "__product__",
    "custom_task_scan_qty":         "__product__",
    "custom_task_scan_result":      "__product__",

    // §16 Manual Product Add — Order entry ONLY (not Pack, not Returns)
    // Redesign doc: "Manual add is for Order entry only."
    "custom_task_add_item_code":    "__add_product__",
    "custom_task_add_qty":          "__add_product__",
    "custom_task_add_batch_no":     "__add_product__",
    "custom_task_add_unit_price":   "__add_product__",
};

// ── Photo gallery kinds (consumed by Task-Photo-System.js) ────
var TFV_PHOTO_GALLERY_KINDS = [
    "Pack / prepare items",
    "Pickup Returns",
    "Returns processing / verification",
    "Other: Entry",
    "Other: Processing"
];

// ── Description field behavior (standard field, not custom) ───
// "description" is a Text Editor inside section break "sb_details".
// collapsible is a Section Break property → target sb_details, NOT description.
// For dispatch flow tasks: sb_details collapsible, collapsed when desc empty,
//   expanded when desc has text.
// For all other tasks: sb_details NOT collapsible, always expanded.
// Server scripts that auto-generate descriptions at task creation are OK.
// No client script should auto-edit or auto-focus description.

// ── Activity section ──────────────────────────────────────────
// Hidden on mobile (window.innerWidth <= 768).
// Visible on desktop.
// Currently Task-Accept Start.js hides timeline on mobile (lines 155-157).
// This should move to TFV.

// ── Helper: is this a "product task"? ─────────────────────────
var TFV_PRODUCT_EDIT_KINDS = [
    "Pack / prepare items",
    "Returns processing / verification"
];

function tfv_is_product_task(frm) {
    if (TFV_PRODUCT_EDIT_KINDS.indexOf(frm.doc.task_kind) !== -1) return true;
    if (frm.doc.task_kind === "Order entry" && !!frm.doc.dispatch_case) return true;
    return false;
}

// ── Dispatch flow kinds (description is collapsible for these) ─
var TFV_DISPATCH_FLOW_KINDS = [
    "Order entry", "Pack / prepare items", "Dispatch picking / hand-off",
    "Delivery", "Return Call",
    "Return to warehouse (aborted delivery / cancelled order)",
    "Pickup Returns", "Return drop-off at warehouse",
    "Returns processing / verification", "Returns restocking",
    "Invoice preparation / create invoice",
    "Discount Approval", "Debt Closure Approval",
    "Debt Collection", "Distribute Payment", "Payment Received",
    "Dispatch Cancel Restock"    // Dispatch Redesign v4 §4.4
];

// ── Main visibility function ──────────────────────────────────
function tfv_apply(frm) {
    if (!frm || frm.doctype !== "Task") return;
    var kind = (frm.doc.task_kind || "").trim();
    var is_product = tfv_is_product_task(frm);
    var is_add = (kind === "Order entry" && !!frm.doc.dispatch_case);
    var is_completed = frm.doc.status === "Completed";
    var is_mobile = window.innerWidth <= 768;
    var is_dispatch = TFV_DISPATCH_FLOW_KINDS.indexOf(kind) !== -1;

    // Always-hidden
    TFV_ALWAYS_HIDDEN.forEach(function(f) {
        if (frm.fields_dict[f]) frm.toggle_display(f, false);
    });

    // Per-field visibility
    Object.keys(TFV_KIND_MAP).forEach(function(fieldname) {
        if (!frm.fields_dict[fieldname]) return;
        var rule = TFV_KIND_MAP[fieldname];
        var visible = false;
        if (rule === "__all__")              visible = true;
        else if (rule === "__never__")       visible = false;
        else if (rule === "__completed__")   visible = is_completed;
        else if (rule === "__product__")     visible = is_product;
        else if (rule === "__add_product__") visible = is_add;
        else if (rule === "__has_value__")   visible = !!frm.doc[fieldname];
        else if (rule === "__dispatch_or_value__") visible = is_dispatch || !!frm.doc[fieldname];
        else if (rule === "__order_return__") visible = (kind === "Order entry" && !!frm.doc.order_return_expected);
        else if (Array.isArray(rule))        visible = rule.indexOf(kind) !== -1;
        frm.toggle_display(fieldname, visible);
    });

    // task_kind: read-only after first save
    if (!frm.is_new()) {
        frm.set_df_property("task_kind", "read_only", 1);
    }

    // Description: collapsible for dispatch flow tasks
    // "description" is a Text Editor inside section "sb_details".
    // collapsible is a Section Break property, so target the parent section.
    var sb = frm.fields_dict.sb_details;
    if (sb) {
        var has_text = !!(frm.doc.description || "").trim();
        if (is_dispatch) {
            sb.df.collapsible = 1;
            sb.collapse(!has_text);  // expand if has text, collapse if empty
        } else {
            sb.df.collapsible = 0;
            sb.collapse(false);      // always expanded for non-dispatch
        }
        sb.refresh();
    }

    // Activity/Timeline: hidden on mobile, visible on desktop
    // (DOM exception — Activity is not a Frappe field, see principle #7)
    if (is_mobile) {
        $(frm.wrapper).find(".form-footer .timeline-group, .form-footer .timeline-actions").hide();
        $(frm.wrapper).find(".section-head:contains('Activity')").closest(".form-section").hide();
    }

    // Photo gallery: set flag for Task-Photo-System.js to consume
    // (DOM exception — gallery container is rendered HTML, not a field)
    frm._tfv_show_gallery = TFV_PHOTO_GALLERY_KINDS.indexOf(kind) !== -1;
    if (!frm._tfv_show_gallery) {
        $(frm.wrapper).find('[id^="photo-gallery-host-"]').hide();
    }
}

frappe.ui.form.on("Task", {
    refresh: function(frm) { tfv_apply(frm); },
    task_kind: function(frm) { tfv_apply(frm); },
    dispatch_case: function(frm) { tfv_apply(frm); },
    order_return_expected: function(frm) { tfv_apply(frm); }  // Dispatch Redesign v4 §2.3
});
```

### Pre-implementation: Completeness verification

Before writing the final script, cross-check ALL 52 Task custom fields from `custom-fields.json` against `TFV_ALWAYS_HIDDEN` + `TFV_KIND_MAP`. Any field not in either list is a bug — it would be permanently hidden after schema change.

**Known task_kind edge cases:**
- `Order accepting` — auto-converted to `Order entry` by Task-Accept Start.js (line 161). No fields needed.
- `Return to warehouse (aborted delivery / cancelled order)` — added to `dispatch_case` and `return_pickup_driver` arrays. Other fields via `__has_value__`. Activated by Dispatch Redesign v4 cancel flow (§4.4B).
- `Dispatch Cancel Restock` — NEW kind from Dispatch Redesign v4 (§4.4A). Only needs `dispatch_case` + `customer` (via `__dispatch_or_value__`) + dispatch description. No product work area — packer clicks through to DC to see items.
- `Account Details: Entry / Processing` — being removed (§17). Until then, only `__all__` fields shown. Intentional.
- `Other` (plain) — being retired. Only `__all__` fields shown. Intentional.
- `Debt Closure Approval` — now in approval, dispatch_case, and debt/payment arrays.

**Fields from Dispatch Redesign v4 (not yet in schema):**
- `order_return_expected`, `order_surgery_date`, `order_template` → `["Order entry"]`
- `order_client_location_warehouse` → `"__order_return__"` (Order entry + return_expected checked)
- These are no-ops in TFV until the fields are created by the dispatch redesign deployment. `frm.fields_dict[fieldname]` returns undefined → `toggle_display` skipped.

**Fields NOT in TFV (confirmed not on Task):**
- `profit` — Dispatch Case field, NOT Task. Excluded.
- `allow_items_edit` — Dispatch Case field. Excluded.
- `purchase_reason`, `requested_by`, `director_approval_*`, `reorder_change_reason` — Purchase Order / Item fields. Excluded.
- `custom_product_work_column` — Column Break, inherits from parent section. NOT individually toggled (redesign doc §16.1).

### Schema changes (bundled — Phase 0+1 deploy together)

Phase 0 and Phase 1 deploy as a single atomic change:

1. **`custom-fields.json`** — For every Task custom field:
   - Set `"hidden": 1`
   - Set `"depends_on": ""`
   - Fields already `hidden=1` with no `depends_on`: no change needed.

2. **`property-setters.json`** — For `status` and `priority`:
   - Add property setters `hidden=1` (if not already present).

3. **`field_order`** in property-setters.json:
   - Remove ghost fields: `warehouse_pickup_photo`, `custom_delivery_photo`, `warehouse_dropoff_photo`, `surgery_case`, `custom_select_surgical_kit_template`.

4. **Deploy script** pushes both TFV script + schema in one operation. Clear cache. Export.

### Verification

1. Deploy to test.
2. Open each task kind. Verify fields appear correctly per the redesign doc.
3. Disable `Task-Field-Visibility.js` temporarily → ALL custom fields should be hidden (proves schema is correct).
4. Re-enable it → back to normal (proves TFV is the sole controller).

---

## Phase 2: Migrate Task-Accept Start.js

**Goal:** Remove all visibility logic from `Task-Accept Start.js`. Keep only non-visibility behavior.

### What to remove

| Lines | What | Why |
|---|---|---|
| 12–58 | `account_details_entry_ui_cleanup()` — hides scan/product fields, shows status/priority/photos, DOM label hiding | Visibility now in TFV. Account Details being removed (§17). |
| 113 | `set_df_property("custom_assigned_to", "label", ...)` | Label set by schema, not per-refresh. |
| 114 | `set_df_property("custom_next_task_assign_to", "label", ...)` | Same. |
| 117–122 | Show/hide `custom_next_task_assign_to` per dispatch kinds | TFV handles this. |
| 123–124 | `account_details_entry_ui_cleanup` + Account Details next_assign override | Account Details removed. |
| 134 | `toggle_display("custom_accepted_by", false)` | TFV always-hidden list. |
| 139–143 | Subject hide for Order entry + auto-set | Subject logic moves to before-save (separate phase). Keep for now as behavioral. |
| 148–158 | Mobile field hiding (accepted_at, batch, price, timeline) | TFV handles field visibility. Timeline hiding is behavioral — keep. |
| 167–175 | `account_details_entry_keep_next_assign_empty()` | Account Details removed. |

### What to keep

- Mobile CSS injection (lines 69–110) — NOT visibility logic.
- Sidebar hiding (lines 127–132) — NOT field visibility.
- Subject reqd=0 (line 135–138) — behavioral.
- Dashboard hide (line 146) — behavioral.
- Order entry default kind (lines 161–163) — behavioral.
- `task_mobile_hide_desktop_custom_actions()` — CSS, not visibility.

### Coordination with Dispatch Redesign v4

The dispatch redesign also modifies `Task-Accept Start.js` to "show new Order Entry fields, reload form after accept to pick up DC". With TFV deployed:
- **Do NOT add visibility calls** for `order_return_expected`, `order_client_location_warehouse`, `order_surgery_date`, `order_template` in Accept Start. TFV handles those via the kind map.
- **DO add** form reload after accept (so TFV re-runs on refresh, sees the new `dispatch_case`, and reveals Product Work + new fields).
- The dispatch redesign's Accept Start changes are purely behavioral (reload, reqd settings).

### Verification

- Test every task kind on desktop and mobile.
- Verify `custom_next_task_assign_to` shows/hides correctly (now driven by TFV, not this script).
- Verify Account Details tasks still work (until §17 removal).
- After dispatch redesign: verify Order entry accept → reload → TFV reveals Product Work + new fields.

---

## Phase 3: Migrate Task-Other UI Cleanup.js

**Goal:** Remove all visibility logic. Keep only Other-specific behavioral logic (subject defaulting, relabeling).

### What to remove

| Lines | What | Why |
|---|---|---|
| 11, line `task_restore_status_priority_visible` calls | Multiple setTimeout retries to force-show status/priority/barcode | Status+priority now always hidden (§18). Barcode visibility in TFV. |
| 17–27 | `task_restore_status_priority_visible()` | Entire function — was fighting other scripts to show status/priority. |
| 38 | `["status", "priority", "custom_barcode_section"].forEach(...)` show | TFV handles. |
| 40 | Mass-hide of product/scan/other fields | TFV handles. |
| 41–49 | setTimeout DOM surgery to hide product sections by label text | TFV handles. |
| 52–71 | `task_other_force_status_priority_visible()` — moves status/priority controls, renames section | Status/priority removed. No section relabeling needed. |

### What to keep

- Lines 34–37: Subject reqd=0, label="Task Name", default subject for Entry/Processing — behavioral.
- Line 39: `custom_next_task_assign_to` label + show/hide for Processing — REMOVE (TFV handles visibility). Keep label set only if needed. Actually TFV handles it: Other: Entry shows it, Other: Processing doesn't (it's not in the TFV_KIND_MAP for Processing).

### After cleanup

This script becomes very small — just subject defaulting for Other tasks. Consider inlining into a future unified subject script or keeping it.

### Verification

- Open Other: Entry and Other: Processing tasks.
- Verify subject defaulting still works.
- Verify product/scan sections are hidden (by TFV, not this script).
- Verify status/priority are hidden.

---

## Phase 4: Migrate Task-Account Details UI Cleanup.js → DISABLE

**Goal:** Disable this script entirely. Account Details workflow is being removed (§17). Photos use Task-Photo-System.js.

### Action

- Set `Enabled: 0` in the script header.
- Do NOT delete yet — keep for reference until Account Details data is migrated.

### Prerequisites

- Existing Account Details tasks must be completed or cancelled first.
- Task Access Policy records for Account Details: Entry / Processing deleted.
- `task_kind` Select options updated to remove Account Details variants.
- `custom_account_photos`, `custom_account_details_section`, `custom_account_details_entry_task`, `custom_account_details_subject` fields deleted from schema.

### Verification

- Verify no Account Details tasks exist in Open/Working status.
- Verify form loads cleanly without the script.

---

## Phase 5: Migrate Task-Inspect Returns Next Assign Visible.js → DELETE

**Goal:** Delete this script. Its only job is showing `custom_next_task_assign_to` for Returns processing — now handled by TFV.

### Action

- Set `Enabled: 0`.
- Delete from deployment.

### Verification

- Open a Returns processing task.
- Verify `custom_next_task_assign_to` is visible (driven by TFV).

---

## Phase 6: Migrate Task-Lock Unaccepted.js

**Goal:** Remove per-field editable toggles from this script. Keep only the lock/unlock behavioral logic (enable/disable save, gallery mode).

### What to remove

| Lines | What | Why |
|---|---|---|
| 28–46 | Per-field `read_only` toggle + `editable_fields` list | TFV controls visibility. Locking script should do a blanket read_only toggle on all fields, not maintain its own field list. |
| 35 | `driver_handover_note` in editable list | Field removed. |

### What to keep

- `frm.enable_save()` / `frm.disable_save()` — behavioral.
- `frm.set_intro(...)` — behavioral.
- Blanket read_only on all fields (lines 28–31, 56–60) — keep but simplify.
- Gallery mode toggle (lines 52, 65) — behavioral.
- DOM enable/disable (lines 49–50, 62–63) — behavioral (but should be simplified later).

### Verification

- Open task as non-accepted user → form locked.
- Accept task → form unlocked.
- Verify specific fields become editable based on TFV visibility (not Lock script's field list).

---

## Phase 7: Migrate Task-Product Work Area.js

**Goal:** Remove autofocus-on-load. Remove any toggle_display calls. Keep scanning/rendering behavior.

### What to remove

| Item | Why |
|---|---|
| `task_product_work_area_focus_scan()` call on refresh (line ~623) | Autofocus on form load is disruptive (§15.2 decision). |
| Any `frm.toggle_display()` calls inside this script | TFV owns visibility. |

### What to keep

- All scanning logic, packing checkboxes, returns rendering, LOT dialog, add-product.
- The `is_product_task` check can remain as a guard (if not product task, skip rendering) — it's not toggling visibility, just skipping work.
- Focus can be triggered by explicit user action (click "Scan Product Barcode" button).

### Coordination with Dispatch Redesign v4

The dispatch redesign also modifies this script to add Order entry as a product-task kind and add an order-entry renderer (`task_product_work_area_render_order_entry()`). These changes are orthogonal to TFV migration:
- TFV migration removes: autofocus, toggle_display calls.
- Dispatch redesign adds: Order entry renderer, Order entry to kinds condition.
- Both can be applied to the same script without conflict.
- **Recommended:** Apply TFV migration first (remove visibility/autofocus), then dispatch redesign (add renderer). Or merge in one pass.

### Verification

- Open a Pack task → scan section visible (by TFV), no autofocus.
- Click "Scan Product Barcode" → focus moves to scan field.
- Scan a barcode → works as before.
- After dispatch redesign: Open accepted Order entry task → Product Work renders with order-entry columns (qty/price/discount/batch).

---

## Phase 3.5: Migrate "Order entry - barcode scanning section - hide.js" → DISABLE

**Goal:** Disable this 140-line script. It is **Enabled: 1** and is one of the largest visibility/DOM surgery offenders.

### What it does (all replaced by TFV)

| Section | What | Replacement |
|---|---|---|
| A. Team Queue fields | Show/hide per kind | TFV (if team queue fields are kept) |
| B. Barcode/product fields | Hide by label text for non-Pack kinds | TFV section toggle |
| E. Driver Handover Note | Always hide | TFV always-hidden + field being removed |
| F. Product Lines table | Show for Order entry, hide for others | TFV (table being removed) |
| G. Activity log | Hide for Return Call | TFV or behavioral |
| H. Section header renaming | "Barcode Scanning" → "Task Status & Priority" / "Debt amount" etc. | Sections no longer repurposed — each section has its own meaning in TFV |
| 2. Column DOM rearrangement | Moves status/priority into barcode section columns | No longer needed — status/priority always hidden, barcode section only shown for product tasks |

### Action

- Set `Enabled: 0`.
- The section header renaming (H) and column rearrangement (2) are the most dangerous DOM surgery in the system — they physically move controls between columns, breaking Frappe's internal field-to-wrapper mapping. Removing this alone fixes multiple UI bugs.

### Note on team queue fields

The script toggles `team_queue_task`, `team_queue_role`, `team_queue_status`, `team_notified`. These fields are NOT defined in test `custom-fields.json` — they only appear as `insert_after` anchors (same ghost pattern as surgery/photo fields). They don't exist on the form, so the toggle calls are no-ops. No action needed in TFV.

---

## Phase 8: Clean up disabled/dead scripts

**Goal:** Formally disable or remove scripts that are already disabled or have become empty after migration.

### Scripts to confirm disabled/deleted

| Script | Status | Action |
|---|---|---|
| `Task-Delivery UI Fix.js` | Already disabled | No change |
| `Task-Header Long Subject Fix.js` | Already disabled | No change |
| `Task-Mobile Form Layout Fix.js` | Already disabled | No change |
| `Task-Dispatch Packing Usability.js` | Already disabled | No change |
| `Task-Create Dispatch Case Items.js` | Already disabled | No change |
| `Task-Packing Checkboxes.js` | Already disabled | No change |
| `Task-Product Lines Display.js` | Already disabled | No change |
| `Task Product Line-Item Code String Guard.js` | Enabled: 1 | **DISABLE** — only consumer of dead `custom_product_lines` table |

### Verification

- Full regression: open one task of every kind, verify form renders correctly.

---

## Phase 9: Schema cleanup — Remove dead fields

**Goal:** Delete fields that are confirmed dead and have no data.

### Fields to remove

| Field | Reason |
|---|---|
| `driver_handover_note` | Removed (§11), no server usage, hidden=1 |
| `custom_product_lines` | Dead table, never populated (§14.3) |
| `custom_account_details_section` | Account Details removed (§17) |
| `custom_account_photos` | Account Details removed (§17) |
| `custom_account_details_entry_task` | Account Details removed (§17) |
| `custom_account_details_subject` | Account Details removed (§17) |

### Prerequisite

- Verify no data exists in these fields on the live test site before deletion.
- `field_order` cleaned up (ghost fields removed in Phase 1).

### Verification

- Export schema after deletion.
- Verify form loads without errors.
- Run full task-kind regression.

---

## Phase Summary

### Deploy batches

| Batch | Phases | What | Risk |
|---|---|---|---|
| **A** | 0+1 | Create TFV + schema hidden=1 + remove depends_on | Medium — single cutover |
| **B** | 2+3+3.5+5+6+7 | Migrate all scripts (remove visibility calls, disable redundant scripts) | Low — removing duplicate logic, TFV is authoritative |
| **C** | 4 | Disable Account Details UI Cleanup (after completing/cancelling AD tasks) | Medium — data dependency |
| **D** | 8+9 | Remove dead scripts + dead schema fields | Low — cleanup |

### Phase dependencies

| Phase | What | Dependencies |
|---|---|---|
| **0+1** | TFV script + schema | None |
| **2** | Migrate Task-Accept Start.js | Batch A |
| **3** | Migrate Task-Other UI Cleanup.js | Batch A |
| **3.5** | Disable "Order entry - barcode scanning section - hide.js" | Batch A |
| **5** | Delete Task-Inspect Returns Next Assign Visible.js | Batch A |
| **6** | Migrate Task-Lock Unaccepted.js | Batch A |
| **7** | Migrate Task-Product Work Area.js + Task-Photo-System.js | Batch A |
| **4** | Disable Task-Account Details UI Cleanup.js | Batch A + AD data migrated |
| **8** | Disable dead scripts | Batch B |
| **9** | Remove dead schema fields | Batch B+C + data verification |

### Cross-plan deployment coordination (Dispatch Redesign v4)

TFV and Dispatch Redesign v4 touch overlapping files. Recommended sequence:

1. **TFV Batch A** — establishes centralized visibility. New dispatch fields/kinds in map are harmless no-ops.
2. **Dispatch Redesign Phase 1** — creates 4 new Task fields (hidden=1), server logic. TFV immediately reveals them for Order entry.
3. **TFV Batch B + Dispatch client changes** — merge script migrations. Accept Start: TFV removes visibility, dispatch adds reload-after-accept. Product Work Area: TFV removes autofocus, dispatch adds Order entry renderer.
4. **Dispatch Redesign Phases 2-3** — DC form cleanup, cancel flow. `Dispatch Cancel Restock` kind created; TFV already handles it.
5. **TFV Batches C+D** — Account Details removal, dead code cleanup.

Alternative: TFV Batch A and Dispatch Phase 1 can deploy simultaneously if coordinated.

---

## Active Task client scripts after all phases

| Script | Responsibility |
|---|---|
| **Task-Field-Visibility.js** (NEW) | All field/section visibility |
| **Task-Action Buttons.js** | Buttons (Accept, Complete, Create DC, Open DC, Delivery/Pickup status buttons), mobile CSS, scroll |
| **Task-Accept Start.js** | Sidebar hiding, subject reqd, dashboard hide, mobile menu cleanup, Order entry kind default |
| **Task-Other UI Cleanup.js** | Subject defaulting for Other tasks (may be absorbed into before-save later) |
| **Task-Lock Unaccepted.js** | Edit locking (enable/disable save, read-only blanket) |
| **Task-Lock Completed.js** | Lock completed tasks |
| **Task-Product Work Area.js** | Product summary rendering, scanning, adding, packing checkboxes |
| **Task-Photo-System.js** | Photo gallery rendering (decides render based on kind, but visibility is TFV) |
| **Task-Auto Reload.js** | Auto-reload on changes |
| **Task-Team Queue.js** | Team queue behavior |

---

## Resolved decisions

1. **Phase 0+1 together.** Deploy TFV script + schema changes (hidden=1, remove depends_on) in one go. Cleaner cutover.
2. **Account Details: complete/cancel existing tasks** before removing the workflow in Phase 4. Devin runs verification query.
3. **"Order entry - barcode scanning section - hide.js"** is Enabled:1 and is a major 140-line DOM surgery script. Added as Phase 3.5 to disable.
4. **Debt/payment fields live in their own section** — NOT inside barcode section. The old "Order entry - barcode scanning section - hide.js" repurposed the barcode section header for Debt Collection/Closure. With TFV, the barcode section is hidden for those kinds. Debt fields are shown by TFV_KIND_MAP in their own natural position in the form layout.
5. **Description field:** Target `sb_details` (the parent Section Break), NOT `description` itself. `collapsible` is a Section Break property — setting it on a Text Editor field would be ignored. For dispatch flow tasks: sb_details collapsible, collapsed when empty, expanded when has text. For all others: not collapsible, always expanded.
6. **Activity/timeline:** Hidden on mobile, visible on desktop. Logic moves from Task-Accept Start.js to TFV. Uses jQuery DOM hide (acknowledged exception — Activity is not a Frappe field).
7. **Photo gallery visibility:** Centralized in TFV. TFV sets `frm._tfv_show_gallery` flag; Photo-System reads it. DOM hide for gallery container (acknowledged exception).
8. **Deploy batching:** Phases 2+3+3.5+5+6+7 should deploy in one batch after Phase 0+1. Phase 4 deferred until AD data migrated. Phase 8+9 together after.
9. **Value-based visibility:** `sales_invoice` and `payment_entry` use `__has_value__` (show when has value, hide when empty). `customer` uses `__dispatch_or_value__` (show for dispatch flow kinds OR when has value) because users need to see the customer field on new Order entry tasks before it's filled. Per redesign doc: value-based auto-covers Debt Closure Approval (which has both SI and PE set at creation) without explicit kind lists.
10. **Manual add fields** (`custom_task_add_*`): `__add_product__` rule — visible ONLY for Order entry with dispatch_case. NOT for Pack or Returns proc. Per redesign doc §16: "Manual add is for Order entry only."
11. **`Debt Closure Approval`** added to: `approval_outcome`, `approval_note`, `dispatch_case`, and all debt/payment field arrays. Was completely missing.
12. **`Return to warehouse (aborted delivery / cancelled order)`** added to: `dispatch_case` and `return_pickup_driver`. Rare kind but must not show a blank form.
13. **Column Break `custom_product_work_column`** removed from TFV_KIND_MAP. Column Breaks inherit visibility from their parent Section Break. Toggling individually is redundant and could cause layout glitches.
14. **`profit`** removed from TFV_KIND_MAP — it's a Dispatch Case field (dt="Dispatch Case"), not a Task field.

### Dispatch Redesign v4 coordination (added 2026-09-07)

15. **4 new Order Entry fields** from Dispatch Redesign v4 (§2.3) added to TFV_KIND_MAP: `order_return_expected` → `["Order entry"]`, `order_surgery_date` → `["Order entry"]`, `order_template` → `["Order entry"]`, `order_client_location_warehouse` → `"__order_return__"`. Fields don't exist yet — TFV skips them safely (`frm.fields_dict[fieldname]` undefined → no-op).
16. **New rule type `__order_return__`** = `kind === "Order entry" && !!frm.doc.order_return_expected`. Triggers TFV re-evaluation on `order_return_expected` change event.
17. **`Dispatch Cancel Restock`** (new task kind from Dispatch Redesign v4 §4.4A) added to `dispatch_case` array and `TFV_DISPATCH_FLOW_KINDS`. Only needs DC link + customer + dispatch description. No product work area — packer clicks through to DC to see item list.
18. **Script modification coordination:** Both TFV and Dispatch Redesign v4 modify `Task-Accept Start.js` and `Task-Product Work Area.js`. TFV changes are visibility-only (remove toggle_display, remove autofocus). Dispatch changes are behavioral (add Order entry renderer, reload after accept). No conflict — changes are orthogonal. Accept Start must NOT add visibility calls for new fields; TFV handles them.
19. **Deployment sequencing:** TFV Batch A can deploy first — new fields/kind in the map are harmless no-ops until schema exists. Dispatch Redesign Phase 1 deploys next (creates fields hidden=1, TFV reveals them). TFV Batch B (script migration) and Dispatch Redesign script changes can be merged or sequenced either way. Alternatively, TFV Batch A + Dispatch Phase 1 can deploy simultaneously.
20. **`Dispatch Cancel Restock` NOT in photo gallery kinds** — restocking doesn't need photo evidence. NOT in `__product__` — no scan/product-add UI needed. Description + DC link is sufficient.
