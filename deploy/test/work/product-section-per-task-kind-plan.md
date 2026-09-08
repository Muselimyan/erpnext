# Fix Product Section Per Task Kind — Phased Plan

Redesign the product section so each task kind sees only what it can act on, then add an inline Order Entry items editor, then clean up dead fields.

---

## Phase A — The Fix (deploy immediately)

**Goal:** Order Entry stops showing scan fields, packing labels, and wrong buttons. All other task kinds unaffected.

### A1. TFV — New `__scan_product__` rule (Task-Field-Visibility.js)

Add scan-only classification:

```javascript
var TFV_SCAN_PRODUCT_KINDS = [
    "Pack / prepare items",
    "Returns processing / verification"
];

function tfv_is_scan_product_task(frm) {
    return TFV_SCAN_PRODUCT_KINDS.indexOf(frm.doc.task_kind) !== -1
        && !!frm.doc.dispatch_case;
}
```

Change scan field rules:
```
"custom_task_scan_barcode":     "__scan_product__",  // was "__product__"
"custom_task_scan_qty":         "__scan_product__",  // was "__product__"
"custom_task_scan_result":      "__scan_product__",  // was "__product__"
```

Hide add fields (temporary — Phase C deletes them):
```
"custom_task_add_item_code":    "__never__",  // was "__add_product__"
"custom_task_add_qty":          "__never__",  // was "__add_product__"
"custom_task_add_batch_no":     "__never__",  // was "__add_product__"
"custom_task_add_unit_price":   "__never__",  // was "__add_product__"
```

Add `__scan_product__` evaluation in `tfv_apply`:
```javascript
} else if (rule === "__scan_product__") {
    var is_scan = tfv_is_scan_product_task(frm);
    visible = is_scan;
    reason = "__scan_product__ (is_scan=" + is_scan + ")";
}
```

Remove `is_add` variable (no fields use `__add_product__` anymore).

### A2. TFV — Dynamic labels/descriptions (Task-Field-Visibility.js)

At end of `tfv_apply`:

```javascript
if (kind === "Order entry") {
    frm.set_df_property("dispatch_case", "label", "Dispatch Case");
    frm.set_df_property("dispatch_case", "description",
        "Auto-created on task acceptance. Products you add are stored here.");
    frm.set_df_property("custom_product_work_section", "label", "Products");
} else if (kind === "Pack / prepare items") {
    frm.set_df_property("dispatch_case", "label", "Dispatch Case / Packing Items");
    frm.set_df_property("dispatch_case", "description",
        "Open to view batch/LOT, expiry, scanned qty, FEFO warnings, and packing problems.");
    frm.set_df_property("custom_product_work_section", "label", "Products / Packing");
} else if (kind === "Returns processing / verification") {
    frm.set_df_property("dispatch_case", "label", "Dispatch Case");
    frm.set_df_property("dispatch_case", "description",
        "Open to view product rows and return quantities.");
    frm.set_df_property("custom_product_work_section", "label", "Products / Returns");
} else if (is_dispatch) {
    frm.set_df_property("dispatch_case", "label", "Dispatch Case");
    frm.set_df_property("dispatch_case", "description", "");
    frm.set_df_property("custom_product_work_section", "label", "Products / Dispatch Work");
}
```

### A3. Remove all product header buttons (Task-Product Work Area.js)

Delete the button block in the `refresh` event handler (lines 637-647):
```javascript
// DELETE entirely:
if (!frm.is_new() && is_product_task) {
    frm.add_custom_button(__("Add Selected Product"), ...);
    frm.add_custom_button(__("Refresh Products"), ...);
    frm.add_custom_button(__("Scan Product Barcode"), ...);
}
```

### A4. Remove mobile product dropdown (Task-Action Buttons.js)

Delete the product dropdown block in `tab_render_subheader` (lines 274-289):
```javascript
// DELETE entirely:
if (!frm.is_new() && tab_is_product_task(frm) && tab_can_act(frm)) {
    var prodDrop = $(...);
    // ... entire product dropdown ...
    right.append(prodDrop);
}
```

### A5. Dashboard comment — suppress for Order Entry (Task-Action Buttons.js)

In `tab_dashboard_comments`:
```javascript
// Before:
if (frm.doc.dispatch_case) {

// After:
if (frm.doc.dispatch_case && frm.doc.task_kind !== "Order entry") {
```

### A6. Context-appropriate empty messages (Task-Product Work Area.js)

In `task_product_work_area_refresh`, update the no-DC and no-rows messages:

No DC:
```javascript
if (!frm.doc.dispatch_case) {
    if (frm.doc.task_kind === "Order entry") {
        task_product_work_area_empty(frm,
            "Accept this task to auto-create a Dispatch Case, then add products.", "info");
    } else {
        task_product_work_area_empty(frm, "No Dispatch Case linked yet.", "warning");
    }
    frm.set_value("custom_task_product_warning", "");
    return;
}
```

No rows (inside the frappe.call callback, before the kind-specific routing):
```javascript
if (!rows.length) {
    if (frm.doc.task_kind === "Order entry") {
        task_product_work_area_empty(frm,
            "No products yet. Open the Dispatch Case to add items.", "info");
    } else {
        task_product_work_area_empty(frm, "No product rows in Dispatch Case.", "warning");
    }
    frm.set_value("custom_task_product_warning", "");
    return;
}
```

### Phase A — Files

| File | Action |
|------|--------|
| `client/Task-Field-Visibility.js` | MODIFY — A1 + A2 |
| `client/Task-Product Work Area.js` | MODIFY — A3 + A6 |
| `client/Task-Action Buttons.js` | MODIFY — A4 + A5 |

### Phase A — Verification

- [ ] Order Entry: no scan fields, no header/mobile buttons, section label "Products", dispatch_case label "Dispatch Case", clean empty messages
- [ ] Order Entry: add fields hidden (temporary — shows blank product area until Phase B adds the inline editor)
- [ ] Pack: scan fields visible, packing table, section "Products / Packing", no buttons
- [ ] Returns: scan fields, returns table, section "Products / Returns", no buttons
- [ ] Delivery/other: unchanged behavior
- [ ] Pack scan flow: still works (add fields hidden but still in schema, scan flow still uses `frm.set_value` internally)

**Note:** After Phase A, Order Entry users can view existing products (read-only table) but cannot add new products from the Task form. They can still add products by opening the DC directly (link is visible). This is a temporary regression — Phase B restores inline add capability with the new editor.

---

## Phase B — Inline Order Items Editor (deploy after Phase A verified)

**Goal:** Order Entry gets a self-contained inline editable table for managing DC items.

### B1. New server APIs

**CREATE `server/task_update_dispatch_product.py`**

Updates editable fields on an existing DC case_item row.

```python
# Name: task_update_dispatch_product
# Type: API
# DocType:
# Event: Before Insert
# Disabled: 0
# ---

case_name = frappe.form_dict.get("case_name")
row_name = frappe.form_dict.get("row_name")
dispatched_qty = frappe.form_dict.get("dispatched_qty")
unit_price = frappe.form_dict.get("unit_price")
discount_pct = frappe.form_dict.get("discount_pct")
batch_no = frappe.form_dict.get("batch_no")

if not case_name or not row_name:
    frappe.throw("case_name and row_name are required.")

case = frappe.get_doc("Dispatch Case", case_name)
found = False
for row in case.case_items:
    if row.name == row_name:
        if dispatched_qty is not None:
            row.dispatched_qty = float(dispatched_qty)
            row.custom_remaining_qty = max(float(dispatched_qty) - float(row.custom_scanned_qty or 0), 0)
        if unit_price is not None:
            row.unit_price = float(unit_price)
        if discount_pct is not None:
            row.discount_pct = float(discount_pct)
        if batch_no is not None:
            row.batch_no = batch_no or None
        found = True
        break

if not found:
    frappe.throw("Row not found in Dispatch Case.")

case.flags.ignore_permissions = True
case.save()
frappe.response["message"] = {"ok": True}
```

**CREATE `server/task_remove_dispatch_product.py`**

Removes a row from DC case_items.

```python
# Name: task_remove_dispatch_product
# Type: API
# DocType:
# Event: Before Insert
# Disabled: 0
# ---

case_name = frappe.form_dict.get("case_name")
row_name = frappe.form_dict.get("row_name")

if not case_name or not row_name:
    frappe.throw("case_name and row_name are required.")

case = frappe.get_doc("Dispatch Case", case_name)
original_count = len(case.case_items)
case.case_items = [r for r in case.case_items if r.name != row_name]

if len(case.case_items) == original_count:
    frappe.throw("Row not found in Dispatch Case.")

case.flags.ignore_permissions = True
case.save()
frappe.response["message"] = {"ok": True, "remaining": len(case.case_items)}
```

**MODIFY `server/task_add_dispatch_product.py`**

Add `discount_pct` parameter:

```python
# Add after unit_price line:
discount_pct = float(frappe.form_dict.get("discount_pct") or 0)

# Add after row.unit_price = unit_price:
row.discount_pct = discount_pct
```

### B2. Rewrite `render_order_entry` as inline editor (Task-Product Work Area.js)

Replace `task_product_work_area_render_order_entry` with a new function that:

1. Renders existing rows with editable `<input>` for qty, price, discount%, batch + read-only item name + × remove button
2. Renders add row at bottom with item picker (Frappe Link control via `make_control`), qty, price, discount, batch inputs, and "+ Add" button
3. Debounced auto-save (800ms) on existing row edits
4. Remove → confirm → API → re-render
5. Add → validate → API → re-render → focus item picker
6. Auto-fills price from `standard_rate` when item selected in add row

**Editability check:**
```javascript
var is_editable = !frm.is_new()
    && frm.doc.task_kind === "Order entry"
    && frm.doc.dispatch_case
    && frm.doc.status !== "Completed"
    && frm.doc.custom_accepted_by === frappe.session.user;
```

Not editable → read-only table (no inputs, no add row, no ×).

**Empty state:** Even with 0 rows, render the editor (shows add row). Message above: "No products yet. Use the row below to add items."

Update `task_product_work_area_refresh` so Order Entry always enters the editor path (even with 0 rows):
```javascript
if (is_order_entry_task) {
    task_oe_render_editor(frm, doc, rows);
    return;
}
```

### B3. Spike: test Link control in table cell

Before full implementation, test that this works:
```javascript
frappe.ui.form.make_control({
    df: { fieldtype: "Link", options: "Item", placeholder: "Search item..." },
    parent: some_table_cell_element,
    render_input: true,
    only_input: true
});
```

If it doesn't render correctly (autocomplete dropdown mispositioned, etc.), fallback: plain `<input>` with a search button that opens `frappe.ui.Dialog` with a Link field.

### Phase B — Files

| File | Action |
|------|--------|
| `server/task_update_dispatch_product.py` | CREATE |
| `server/task_remove_dispatch_product.py` | CREATE |
| `server/task_add_dispatch_product.py` | MODIFY |
| `client/Task-Product Work Area.js` | MODIFY — rewrite render_order_entry, update refresh flow |

### Phase B — Verification

- [ ] Order Entry (accepted, with DC): editable table, add row with item picker, × remove buttons
- [ ] Add product → row appears, add row clears, item picker focuses
- [ ] Edit qty/price/discount inline → auto-saves after 800ms
- [ ] Remove product → confirmation → row disappears
- [ ] Template apply still works (calls refresh → editor re-renders)
- [ ] Order Entry (completed / not accepted): read-only table
- [ ] Order Entry (0 rows): shows add row
- [ ] Auto-reload during editing: reload happens, may lose in-progress keystroke (acceptable)
- [ ] Pack/Returns: completely unaffected

---

## Phase C — Cleanup (deploy after Phase B verified)

**Goal:** Remove dead fields from schema, refactor Pack scan, unify `is_product_task`.

### C1. Remove 4 dead Custom Fields from schema

Fields: `custom_task_add_item_code`, `custom_task_add_qty`, `custom_task_add_batch_no`, `custom_task_add_unit_price`

Deploy script:
```python
for fieldname in ["custom_task_add_item_code", "custom_task_add_qty",
                   "custom_task_add_batch_no", "custom_task_add_unit_price"]:
    name = "Task-" + fieldname
    if frappe.db.exists("Custom Field", name):
        frappe.delete_doc("Custom Field", name)
frappe.db.commit()
```

### C2. Refactor Pack scan — JS variable instead of Frappe field (Task-Product Work Area.js)

Add at top:
```javascript
var pwa_pending_item_code = "";
```

Replace in `task_product_work_area_scan`:
- `frm.set_value("custom_task_add_item_code", item_code)` → `pwa_pending_item_code = item_code;`
- `frm.doc.custom_task_add_item_code` reads → `pwa_pending_item_code`
- `!frm.doc.custom_task_add_item_code` checks → `!pwa_pending_item_code`

Delete dead writes:
- `frm.set_value("custom_task_add_batch_no", ...)` — written but never read in Pack flow

### C3. Remove dead code (Task-Product Work Area.js)

- Delete `task_product_work_area_add_product` function (replaced by inline editor)
- Delete `custom_task_add_item_code` event handler (lines 660-668)
- Remove `__add_product__` rule type from TFV (comments + evaluation branch)
- Remove the 4 field entries from `TFV_KIND_MAP` (already `__never__`, now fields don't exist)

### C4. Unify `is_product_task` — single definition

**Task-Product Work Area.js:**
- Delete `task_product_work_area_is_product_task` function
- Replace all calls with `tfv_is_product_task(frm)` (from TFV, already global)

**Task-Action Buttons.js:**
- Delete `tab_is_product_task` function
- Delete `TAB_PRODUCT_KINDS` array
- Replace any remaining calls with `tfv_is_product_task(frm)`

### Phase C — Files

| File | Action |
|------|--------|
| Deploy script | MODIFY — delete Custom Field records |
| `client/Task-Product Work Area.js` | MODIFY — C2 + C3 + C4 |
| `client/Task-Field-Visibility.js` | MODIFY — C3 (remove `__add_product__` remnants) |
| `client/Task-Action Buttons.js` | MODIFY — C4 |

### Phase C — Verification

- [ ] Pack scan flow: REF barcode → JS var captures item → GS1 scan uses it → packing scan succeeds
- [ ] 4 Custom Fields gone from schema (Customize Form → Task)
- [ ] No JS errors from removed fields
- [ ] All task kinds still work as before
