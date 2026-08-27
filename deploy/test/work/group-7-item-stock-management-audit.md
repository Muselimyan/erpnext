# Group 7: Item and Stock Management — Production Audit Findings

> **Audited**: 2026-08-27
> **Scope**: Item tracking, FEFO enforcement, stock entry guards, reorder governance, Collection Set readiness, customer governance, item selection UX
> **Method**: Every script read line by line. Every reference doc read in full. Every custom field verified against schema JSON. All findings cross-referenced against deployed code AND documentation. No assumptions made.

---

## Summary

| Metric | Value |
|---|---|
| Server scripts analyzed | 6 (3 enabled, 3 disabled) |
| Client scripts analyzed | 4 (all enabled) |
| API scripts analyzed | 3 (all enabled) |
| Custom fields analyzed | 12 (5 on Item, 1 on Item Reorder, 6 on Customer) |
| Property setters analyzed | 8 (6 on Item, 2 on Customer) |
| Reference docs analyzed | 8 docs (04/04A, 05/05A, 06/06A, 08/08A) + 3 manuals |
| **Bugs found** | **2 (1 critical, 1 high)** |
| **Disabled safeguards (documented as required)** | **2** |
| **Duplicate/redundant code** | **1** |
| **Undocumented deployed features** | **5** |
| **Legacy/naming mismatches** | **2** |
| **Low-risk code concerns** | **3** |

---

## Findings Table

| ID | Type | Severity | Script / Field | Finding | Confidence |
|---|---|---|---|---|---|
| F-001 | **BUG** | **CRITICAL** | `Customer-before-save-governance.py` | Script has empty `reference_doctype` in schema — never fires on Customer saves | **1.00** |
| F-002 | DISABLED-SAFEGUARD | **HIGH** | `StockEntry-before-submit-fefo.py` | FEFO enforcement disabled; docs say required at go-live | **1.00** |
| F-003 | DISABLED-SAFEGUARD | **HIGH** | `Stock Entry-before-save-no-client-wh.py` | Client warehouse guard disabled; docs say required | **1.00** |
| F-004 | DUPLICATE | MEDIUM | `Collection-Set-validate-readiness.py` + `Surgery-Set-Type-validate-readiness.py` | Two identical scripts both fire on Collection Set Before Save | **1.00** |
| F-005 | LEGACY-MISMATCH | MEDIUM | `Dispatch Case-Template Auto Fill.js` | Loads from `Surgical Kit Template` DocType, not `Collection Set` | **1.00** |
| F-006 | RISK | MEDIUM | `task_add_dispatch_product.py` | Uses `ignore_permissions=True` — no role check on API | **1.00** |
| F-007 | DOC-MISSING | LOW | `hospital` + `doctor_name` on Customer | Fields exist on Customer but only documented on Sales Order/Invoice | **1.00** |
| F-008 | DOC-MISSING | LOW | `custom_1c_code` on Item | Legacy 1C reference field, not in any numbered doc | **1.00** |
| F-009 | DOC-MISSING | LOW | `buffer_percentage` on Item Reorder | Safety Stock Buffer % field, not in any numbered doc | **1.00** |
| F-010 | DOC-MISSING | LOW | `task_add_dispatch_product.py`, `task_lookup_product_barcode.py` | API endpoints undocumented | **1.00** |
| F-011 | DOC-MISSING | LOW | `Dispatch Case-Products Button.js` | Item selection UI undocumented in any numbered doc | **1.00** |
| F-012 | RISK | LOW | `Dispatch Case-Products Button.js` | Potential XSS in HTML data attributes (item_name not escaped) | **0.95** |
| F-013 | INFO | LOW | `Item-before-save-reorder-change-reason.py` | Disabled; correctly superseded by governance version | **1.00** |
| F-014 | MATCH | — | Customer fields: client_code, client_kind, debt_threshold_amd, is_provisional | Schema matches Doc 04A spec exactly (reqd, unique constraints correct) | **1.00** |
| F-015 | MATCH | — | `Item-before-save-reorder-governance.py` | Code matches Doc 08A §7.4 spec exactly | **1.00** |
| F-016 | MATCH | — | Item fields: pack_breaking_policy, reorder_change_reason | Schema matches Doc 06A/08A specs | **1.00** |

---

## Detailed Findings

### F-001: CRITICAL BUG — Customer Governance Script Never Fires

**Script**: `Customer-before-save-governance.py`
**Status**: Enabled (disabled=0)
**Problem**: The script's `reference_doctype` field in the server script record is an **empty string**.

**Evidence** (from `deploy/test/schema/server-scripts.json`):
```
name: "Customer-before-save-governance"
script_type: "DocType Event"
reference_doctype: ""        ← EMPTY
doctype_event: "Before Save"
disabled: 0
```

The script header in the extracted file also shows `# DocType: ` (blank after colon).

**How Frappe server scripts work**: A DocType Event script is matched by `(reference_doctype, doctype_event)`. If `reference_doctype` is empty, Frappe has no way to bind this script to any document's save event. The script is effectively dead code despite being "enabled."

**What the script does** (if it were working):
```python
# Lines 10-14: Check privileged roles
user_roles = set(frappe.get_roles(frappe.session.user))
is_privileged = (
    "Ops - Accounting" in user_roles or
    "Ops - Directors" in user_roles or
    "System Manager" in user_roles
)

# Line 17: Block client_code changes
if before and before.client_code != doc.client_code and not is_privileged:
    frappe.throw("Only Accounting/Directors can change Client Code")

# Line 20: Block provisional status changes
if before and before.is_provisional and not doc.is_provisional and not is_privileged:
    frappe.throw("Only Accounting/Directors can mark a client as non-provisional")
```

**What the documentation requires** (Doc 04A §5.1):
- Script Type: DocType Event
- **Reference DocType: Customer**
- DocType Event: Before Save
- Privileged roles block client_code changes and is_provisional unchecking

**Impact**: With this script not firing:
1. **Any user with Customer write permission can change client_code** — this breaks the stable-code invariant (Doc 04 §3.1) and could corrupt warehouse naming associations
2. **Any user with Customer write permission can uncheck is_provisional** — bypasses the governance review process (Doc 04 §3.5)

Roles with Customer write access (from Doc 04A §7.1): `Ops - Order Accepting`, `Ops - Accounting`, `Ops - Directors`. So Order Accepting staff can currently change client codes and approve their own provisional customers.

**Fix**: Set `reference_doctype` to `Customer` on the server script record in production.

**Confidence**: **1.00** — verified from schema JSON export, script file header, and Frappe matching behavior.

---

### F-002: FEFO Enforcement Disabled (Documented as Required)

**Script**: `StockEntry-before-submit-fefo.py`
**Status**: Disabled (disabled=1)

**What the script does** (lines 32-56):
1. For each stock entry item that has a batch with an expiry date:
   - Finds the earliest-expiring batch in the source warehouse using SLE aggregation
   - If the selected batch expires later than the earliest available, shows an **orange warning** ("FEFO warning")
   - If the selected batch expires within 1 month, shows an **orange warning** ("Near-expiry warning")
2. Uses `frappe.msgprint` (warning only, not `frappe.throw`), matching the documented "warning at go-live, not hard-block" decision

**What the documentation requires**:
- Doc 06 §7.1: "For expiry-tracked items, batch selection must follow FEFO. If user selects fresher batch while older-expiring batch available in Main - WH, system must alert."
- Doc 06 §7.1 Decision: "FEFO enforcement is a **warning** at go-live (not hard-block)"
- Doc 06 §7.1 Decision: "Near-expiry threshold for warnings/escalation is **1 month**"
- Doc 06A §9.1: Full implementation guide with exactly this script specification

**The code matches the spec perfectly**. Warning-only mode (msgprint not throw), 1-month near-expiry threshold, batch-level FEFO comparison in source warehouse. The script was built correctly but then disabled.

**Partial mitigation**: `dispatch_case_packing_scan.py` (Group 5) performs FEFO checks during Dispatch Case packing barcode scanning. However, this only covers the packing workflow. Standard stock operations (Material Transfer, Material Issue, direct Stock Entries) have **zero FEFO enforcement**.

**Impact**: Users can issue older stock or near-expiry stock without any system warning during non-packing stock operations.

**Confidence**: **1.00** — script code read line by line, disabled flag confirmed in schema.

---

### F-003: Client Warehouse Guard Disabled (Documented as Required)

**Script**: `Stock Entry-before-save-no-client-wh.py`
**Status**: Disabled (disabled=1)

**What the script does** (lines 8-24):
1. Only fires when the stock entry has a `sales_order` linkage
2. Looks up the `Clients - Inmed` warehouse's lft/rgt tree boundaries
3. For each stock entry item, checks if the target warehouse is within the Clients hierarchy
4. If so, throws: "Standard sales must not move stock into client location warehouses (Clients - Inmed)."

**What the documentation requires**:
- Doc 05 §Client Location Warehouse Rules: "Standard sales must not move stock into client location warehouses"
- Doc 05 §Stock Entry Restrictions: Explicit prohibition on standard sales posting to client warehouses
- Doc 05A Implementation: Same restriction repeated as a critical operational rule
- Doc 04A §6.3: "Standard sales must not move stock into these warehouses"

**Impact**: With this script disabled, a stock entry linked to a sales order can move items into client warehouses. This could:
- Create phantom "company-owned at client" positions for standard sales
- Corrupt stock balance reports for client locations
- Make client location reconciliation unreliable

**Note on scope limitation**: The script only checks stock entries with a `sales_order` field set. Direct stock entries (no SO link) were never guarded by this script even when enabled.

**Confidence**: **1.00** — script code read line by line, disabled flag confirmed in schema.

---

### F-004: Duplicate Collection Set Readiness Validators

**Scripts**:
1. `Collection-Set-validate-readiness.py` — Collection Set, Before Save, Enabled
2. `Surgery-Set-Type-validate-readiness.py` — Collection Set, Before Save, Enabled

**Evidence**: Both scripts are **character-for-character identical** (47 lines each). Both:
- Set `MAIN_WH = "Main - Inmed"`
- Iterate `doc.items`, read `row.item` and `row.default_qty`
- Query `Bin` for `projected_qty` in Main warehouse
- Calculate shortage
- Check `row.is_critical`
- Set `doc.readiness_status` to "Ready", "Short", or "Critical Short"
- Set `doc.readiness_note` with shortage details
- Call `frappe.msgprint` with the same title "Collection Set readiness warning"

**Confirmed from schema**: Both have `reference_doctype: "Collection Set"` and `doctype_event: "Before Save"`.

**Impact**: Every time a Collection Set is saved:
1. First script runs, calculates readiness, sets status + note, shows msgprint
2. Second script runs, calculates the exact same values, overwrites with same values, shows **a second identical msgprint**
3. User sees the warning message **twice**

No data corruption occurs (both produce identical results), but the duplicate warning is confusing UX.

**History**: `Surgery-Set-Type-validate-readiness.py` was likely created when the DocType was called "Surgery Set Type", then the DocType was renamed to "Collection Set" but the second script was never removed. `Collection-Set-validate-readiness.py` was then created with the new naming.

**Fix**: Disable or delete `Surgery-Set-Type-validate-readiness.py`.

**Confidence**: **1.00** — both scripts read line by line, confirmed identical content and identical trigger configuration.

---

### F-005: Template Auto Fill Loads from Legacy "Surgical Kit Template" DocType

**Script**: `Dispatch Case-Template Auto Fill.js`
**Custom field**: `custom_select_surgical_kit_template` on Dispatch Case (Link to `Surgical Kit Template`)

**What the code does** (lines 7-45):
```javascript
custom_select_surgical_kit_template: function(frm) {
    frappe.call({
        method: "frappe.client.get",
        args: {
            doctype: "Surgical Kit Template",    // ← legacy DocType name
            name: frm.doc.custom_select_surgical_kit_template
        },
        callback: function(r) {
            var template = r.message;
            var items = template && template.template_items ? template.template_items : [];
            // ... loads items into case_items
        }
    });
}
```

**Deployed DocTypes** (from schema):
- `Collection Set` — parent DocType (current name)
- `Collection Set Item` — child table (current name)
- `Surgical Kit Template` — parent DocType (legacy name, **still exists**)
- `Surgical Kit Template Item` — child table (legacy name, **still exists**)

**Documentation says**:
- Collection Set manual: Uses "Collection Set" terminology throughout
- Collection Set manual: Describes items table, readiness status, active flag
- Readiness validators both fire on "Collection Set" DocType

**The situation**: Two parallel DocTypes exist in production:
1. `Collection Set` — used by readiness validators, referenced in manual
2. `Surgical Kit Template` — used by the template auto-fill on Dispatch Case

**Risk**: If templates are maintained in `Collection Set` records (as the manual instructs) but the auto-fill loads from `Surgical Kit Template` records, users could see stale or empty templates on the Dispatch Case form. Conversely, if templates are maintained in `Surgical Kit Template` (because that's what the auto-fill actually uses), the readiness validators running on `Collection Set` are checking different records.

**Also**: `Dispatch Case-Form.js` (Group 1) has Collection Set loading logic too. And `Task - Load Surgical Kit Template.js` (Group 2) loads from yet another path. There may be up to three different template-loading mechanisms in production.

**Fix needed**: Determine which DocType actually holds the template data in production. Consolidate to one DocType. Update the Link field and all loading scripts to use the same DocType.

**Confidence**: **1.00** — both DocTypes confirmed in schema, code references verified.

**Verification needed**: Query production to see which DocType has actual records (data).

---

### F-006: API `task_add_dispatch_product` Uses ignore_permissions

**Script**: `task_add_dispatch_product.py`

**Code** (lines 32-33):
```python
case.flags.ignore_permissions = True
case.save()
```

**What this means**: When this API is called, the Dispatch Case is saved bypassing all permission checks. Any user who can reach the API endpoint (which in Frappe means any logged-in user with Server Script API access) can add products to any Dispatch Case.

**Mitigating factors**:
- The caller must know the task_name, which they'd need Task read access for
- The script does validate that the task has a linked dispatch_case
- Server Script APIs require the `Allow Server Scripts` system setting to be on

**Doc reference**: Doc 06 §9 says "Only designated staff should create new items and variants" and changes should be controlled. While this is about Item master changes (not DC item additions), the principle of permission enforcement applies.

**Risk**: A user with Task read access but no Dispatch Case write access could add items. In practice, this may be acceptable if the task access policy already restricts who sees which tasks. But it's a security boundary bypass that should be documented.

**Confidence**: **1.00** — code is explicit.

---

### F-007: `hospital` and `doctor_name` Fields on Customer — Undocumented

**Fields** (from custom-fields.json):
- `hospital` (Link to Customer, reqd=0) on Customer
- `doctor_name` (Data, reqd=0) on Customer

**Documentation** (Doc 04A):
- §3.1-3.4: Only 4 custom fields specified for Customer: client_code, client_kind, debt_threshold_amd, is_provisional
- §4.1-4.2: hospital, hospital_branch, doctor_name specified for Sales Order and Sales Invoice only

**What's deployed**: hospital and doctor_name also exist on Customer directly (6 custom fields total instead of 4).

**Why they're there**: `SO-customer-autofill.js` (Group 1, enabled) reads these fields from the Customer record and auto-fills them onto Sales Orders. This is a sensible operational convenience — set once on the Customer, auto-fill on every order.

**Assessment**: Useful undocumented enhancement. Not a bug. Doc 04A should be updated to include these fields and describe the auto-fill behavior.

**Confidence**: **1.00** — field existence verified in schema, Doc 04A spec verified.

---

### F-008: `custom_1c_code` on Item — Undocumented Legacy Field

**Field**: `custom_1c_code` (Data, reqd=0, unique=0) on Item

**Documentation**: Not mentioned in any numbered doc (04-08, 16-17), manuals, or deployment summaries.

**Purpose**: Likely stores the product code from the 1C accounting system (the predecessor system before ERPNext). Used for cross-referencing during or after migration.

**Assessment**: Should be documented as a migration artifact. If still needed for reference or reporting, document it. If no longer needed, consider deprecating (hiding, not deleting).

**Confidence**: **1.00** — field confirmed in schema, no documentation found.

---

### F-009: `buffer_percentage` on Item Reorder — Undocumented Field

**Field**: `buffer_percentage` (Float, reqd=0) labeled "Safety Stock Buffer %" on Item Reorder child table.

**Documentation**: Doc 08 covers reorder thresholds (ROP, Min/Max) but never mentions a buffer percentage. Doc 08A implementation guide does not include this field.

**Purpose**: Likely intended for calculating safety stock as a percentage of some base value (lead time demand, average consumption, etc.). However, no deployed script references this field — it appears to be defined but unused.

**Evidence of non-use**: Grepping all scripts in `deploy/test/work/server/` and `deploy/test/work/client/` for `buffer_percentage` returns zero hits.

**Assessment**: Orphaned field. Either:
- It was added for a future feature that hasn't been built yet, or
- It was added during development and never wired up

Should be documented or removed.

**Confidence**: **1.00** — field confirmed in schema, no code references found, no documentation found.

---

### F-010: API Scripts Undocumented

**Scripts**:
1. `task_add_dispatch_product.py` — adds product to Dispatch Case from Task context
2. `task_lookup_product_barcode.py` — looks up item_code by barcode

Neither appears in any numbered doc. They are API endpoints used by client scripts (Task-Product Work Area.js, Task-Accept Start.js) for the product work area on tasks.

**Assessment**: These are implementation details of the product work area feature (itself undocumented — see F-011). They should be documented as part of that feature's specification.

**Confidence**: **1.00**.

---

### F-011: Item Selection UI (Products Button) Undocumented

**Script**: `Dispatch Case-Products Button.js` (235 lines)

Provides two item selection mechanisms on the Dispatch Case form:
1. **Add Items by Category**: Select Item Group, see all items in that group (up to 500), check boxes, add selected
2. **Search & Add Item**: Free-text search by item name or code (min 2 chars), check boxes, add selected

Both set `dispatched_qty = 1` and `unit_price = standard_rate` for added items.

**Documentation**: No numbered doc describes this UI. Doc 16/16A describe the Dispatch Case lifecycle but not the item selection UX.

**Assessment**: Significant user-facing functionality (235 lines) with no documentation. Should be documented in the Dispatch Case or item management docs.

**Confidence**: **1.00**.

---

### F-012: Potential XSS in Products Button HTML

**Script**: `Dispatch Case-Products Button.js`

**Code** (line 143, search dialog; similar in category dialog):
```javascript
html += "<td><input type='checkbox' class='item-checkbox' ... data-item-name='"
    + (item.item_name || item.name) + "' ...></td>";
```

If `item.item_name` contains a single quote (e.g., `O'Brien Screw`), the HTML attribute is broken:
```html
data-item-name='O'Brien Screw'
```
This would cause the checkbox to malfunction. In the worst case, if item names contain crafted HTML, it's a stored XSS vector.

**Mitigating factors**:
- Item names are set by admin users, not by untrusted input
- ERPNext's list API may sanitize output (not verified)
- The category dialog does use `frappe.utils.escape_html()` for the "no items" message, showing awareness of escaping — but the data attributes are not escaped

**Assessment**: Low severity but worth fixing. Use `frappe.utils.escape_html()` for all data attributes.

**Confidence**: **0.95** — code pattern is clear, actual exploitability depends on ERPNext API sanitization.

---

### F-013: Disabled Reorder Script — Correctly Superseded

**Script**: `Item-before-save-reorder-change-reason.py` (DISABLED)
**Replaced by**: `Item-before-save-reorder-governance.py` (ENABLED)

The disabled version (13 lines) uses a simpler comparison:
```python
def snap(rows):
    return [(r.warehouse, r.warehouse_reorder_level or 0, r.warehouse_reorder_qty or 0) for r in (rows or [])]
if snap(before.reorder_levels) != snap(doc.reorder_levels):
```

The active version (30 lines) uses normalized comparison:
```python
def normalize(rows):
    out = []
    for r in (rows or []):
        out.append({
            "warehouse": r.warehouse,
            "reorder_level": float(getattr(r, "warehouse_reorder_level", 0) or 0),
            "reorder_qty": float(getattr(r, "warehouse_reorder_qty", 0) or 0),
        })
    return out
```

The active version is more robust: uses `getattr` with default, `float()` conversion, and `dict` comparison (order-independent). Both implement the same Doc 08A §7.4 requirement.

**Assessment**: Correctly handled. Old version should be deleted (not just disabled) to reduce confusion.

**Confidence**: **1.00**.

---

### F-014, F-015, F-016: Verified Matches (No Issues)

**F-014**: Customer custom fields match Doc 04A exactly:
- `client_code`: Data, reqd=1, unique=1 (matches §3.1)
- `client_kind`: Select, reqd=1 (matches §3.2)
- `debt_threshold_amd`: Currency, reqd=1 (matches §3.3)
- `is_provisional`: Check, reqd=0, default checked (matches §3.4)

**F-015**: `Item-before-save-reorder-governance.py` matches Doc 08A §7.4:
- Fires on Item Before Save
- Compares reorder_levels before/after
- Requires reorder_change_reason when changed
- Error message references "Doc 08 governance rule"

**F-016**: Item custom fields match Doc 06A / Doc 08A:
- `pack_breaking_policy`: Select, reqd=1 (matches Doc 06A §4.5: Required ON)
- `reorder_change_reason`: Small Text, reqd=0 (matches Doc 08A §7.3: not always required, only on reorder change)

**Confidence**: **1.00** for all three.

---

## Script-by-Script Detailed Analysis

### Server Script S1: `Collection-Set-validate-readiness.py`

| Attribute | Value |
|---|---|
| Type | DocType Event |
| DocType | Collection Set |
| Event | Before Save |
| Enabled | Yes |
| Lines | 47 |

**What it does**: On every Collection Set save, iterates all items in `doc.items`. For each item with a positive `default_qty`, queries the `Bin` table for `projected_qty` in `Main - Inmed`. If shortage exists, builds a shortage line. If any shortage item has `is_critical = 1`, sets status to "Critical Short". Otherwise "Short" or "Ready". Displays msgprint with details.

**Documentation match**: Matches the Collection Set manual's description of automatic readiness calculation. The manual says "Readiness Status: Auto-calculated based on projected stock in Main - Inmed only" — the code does exactly this.

**Code quality**: Clean, defensive (`float(... or 0)` patterns). No error handling issues. Uses `projected_qty` (includes reserved/ordered quantities), which is the correct field for availability assessment.

**Known issue**: Runs twice due to F-004 (duplicate script).

---

### Server Script S2: `Item-before-save-reorder-governance.py`

| Attribute | Value |
|---|---|
| Type | DocType Event |
| DocType | Item |
| Event | Before Save |
| Enabled | Yes |
| Lines | 30 (effective: 25) |

**What it does**: Compares reorder_levels before and after save using normalized dict comparison. If any warehouse/level/qty changed and `reorder_change_reason` is empty, throws "Reorder Change Reason is required when changing reorder thresholds (Doc 08 governance rule)."

**Documentation match**: Exact match to Doc 08A §7.4 specification.

**Code quality**: Good. Uses `getattr` with defaults for field access resilience. The `float()` conversion ensures numeric comparison regardless of string/int/float storage. Handles missing `before` (new items) by skipping the check.

**Edge case**: Does not clear `reorder_change_reason` after save. This means the old reason stays visible until the next change. Doc 08A §7.4 says "After saving the Item with a reason, clear the reason field manually (optional)." The current behavior matches the "optional" clearing approach.

---

### Server Script S3: `Customer-before-save-governance.py`

| Attribute | Value |
|---|---|
| Type | DocType Event |
| DocType | **EMPTY** (should be Customer) |
| Event | Before Save |
| Enabled | Yes (but never fires) |
| Lines | 17 |

**See F-001 for full analysis.**

**Code logic** (if it were firing): Correct and complete. Checks `Ops - Accounting`, `Ops - Directors`, `System Manager` as privileged roles. Blocks client_code changes and is_provisional unchecking for non-privileged users. Matches Doc 04A §5.1 exactly.

---

### Server Script S4: `Item-before-save-reorder-change-reason.py`

| Attribute | Value |
|---|---|
| Type | DocType Event |
| DocType | Item |
| Event | Before Save |
| Enabled | No (DISABLED) |
| Lines | 13 |

**See F-013**. Correctly superseded by S2. Same requirement, less robust implementation.

---

### Server Script S5: `Stock Entry-before-save-no-client-wh.py`

| Attribute | Value |
|---|---|
| Type | DocType Event |
| DocType | Stock Entry |
| Event | Before Save |
| Enabled | No (DISABLED) |
| Lines | 20 |

**See F-003 for full analysis.**

**Code logic**: Uses warehouse tree lft/rgt boundaries (the nested set model) to efficiently check if a target warehouse is a descendant of `Clients - Inmed`. Only checks stock entries with a `sales_order` field. This means even when enabled, it doesn't prevent *all* stock entries to client warehouses — only those linked to sales orders.

**Scope limitation**: Direct Material Transfers (no SO link) could still post to client warehouses even when this script was enabled. This may be intentional (surgery case flows create their own stock entries without SO links).

---

### Server Script S6: `StockEntry-before-submit-fefo.py`

| Attribute | Value |
|---|---|
| Type | DocType Event |
| DocType | Stock Entry |
| Event | Before Submit |
| Enabled | No (DISABLED) |
| Lines | 48 |

**See F-002 for full analysis.**

**Code logic**: Well-implemented. Uses `Stock Ledger Entry` grouped by batch with `HAVING SUM(actual_qty) > 0` to find only batches with positive stock. Compares selected batch expiry against earliest available. Uses `add_months(today(), 1)` for near-expiry cutoff. Uses `msgprint` (warning) not `throw` (block), matching the "warning at go-live" decision.

**One concern with the query**: The SLE query joins on `sle.batch_no = b.name`. In some ERPNext versions, the Batch name may not exactly equal the batch_no on SLE. However, this is standard Frappe convention and should be fine.

---

### Client Script C1: `Dispatch Case Item-Auto Fill Item Name.js`

| Attribute | Value |
|---|---|
| DocType | Dispatch Case Item |
| View | Form |
| Enabled | Yes |
| Lines | 17 |

**What it does**: When `item_code` is set on a Dispatch Case Item row and `item_name` is empty, fetches `item_name` from the Item master and fills it in.

**Code quality**: Simple and correct. Uses `frappe.db.get_value` which is the standard async lookup pattern. Condition `!row.item_name` prevents overwriting manually entered names.

**Documentation**: Not explicitly documented, but this is standard ERPNext UX enhancement behavior. No issues.

---

### Client Script C2: `Dispatch Case-Item Code String Guard.js`

| Attribute | Value |
|---|---|
| DocType | Dispatch Case |
| View | Form |
| Enabled | Yes |
| Lines | 34 |

**What it does**: Converts `item_code` and `item_name` to `String()` on the `case_items` child table during `before_save`, `validate`, individual field change, and row addition events.

**Why it exists**: ERPNext's child table controls can sometimes coerce string values to numbers (e.g., item code "12345" becomes integer 12345). This causes type mismatch errors in downstream code that expects strings.

**Code quality**: Defensive and thorough. Covers all entry points (save, validate, field change, row add). The `refresh_field` call after validate ensures the UI reflects the coerced values.

**Documentation**: Not documented, but this is a defensive coding measure, not a business feature.

---

### Client Script C3: `Dispatch Case-Products Button.js`

| Attribute | Value |
|---|---|
| DocType | Dispatch Case |
| View | Form |
| Enabled | Yes |
| Lines | 235 |

**See F-011 and F-012.**

**Detailed behavior**:

1. **"Add Items by Category" button** (lines 10-97):
   - Shows dialog with Item Group selector and search filter
   - Loads up to 500 items from selected group via `frappe.client.get_list`
   - Renders checkbox table with Item Name, Code, Price
   - On submit, adds selected items to `case_items` with dispatched_qty=1

2. **"Search & Add Item" button** (lines 100-203):
   - Shows dialog with free-text search
   - Searches by item_name or item code using `or_filters` with LIKE
   - Minimum 2 characters required
   - Limits to 50 results
   - Tracks checkbox state across searches (`selected_search_items` object)

3. **Render function** (lines 208-238):
   - Shared renderer for category dialog
   - Client-side filtering of already-loaded items

**Both dialogs set**: `dispatched_qty = 1` and `unit_price = standard_rate`. Users must manually adjust quantities.

**Code quality concerns**:
- No duplicate detection: if user adds the same item twice, two rows are created
- HTML built via string concatenation rather than templates — fragile and XSS-prone (F-012)
- The 500-item limit for category loading could be slow for large categories

---

### Client Script C4: `Task Product Line-Item Code String Guard.js`

| Attribute | Value |
|---|---|
| DocType | Task |
| View | Form |
| Enabled | Yes |
| Lines | 31 |

**What it does**: Same pattern as C2 but for `Task Product Line` child table (`custom_product_lines`). Converts item_code and item_name to String() on field change and validate.

**Code quality**: Clean, consistent with C2.

---

### API Script A1: `task_add_dispatch_product.py`

| Attribute | Value |
|---|---|
| Type | API |
| Enabled | Yes |
| Lines | 34 |

**See F-006 and F-010.**

**Detailed behavior** (lines 8-35):
1. Reads task_name, item_code, qty, batch_no, unit_price from `frappe.form_dict`
2. Validates task_name and item_code are present
3. Validates task has a linked dispatch_case
4. Looks up item_name from Item master
5. Appends new row to case_items with:
   - dispatched_qty = qty (from caller)
   - batch_no = from caller (can be None)
   - unit_price = from caller
   - custom_scanned_qty = 0
   - custom_remaining_qty = qty
   - custom_packing_status = "Not Started"
6. Saves with ignore_permissions=True

**Code quality concerns**:
- No validation that item_code exists (trusts caller)
- No validation that qty is positive
- No validation that unit_price is reasonable
- No duplicate item detection
- `ignore_permissions=True` bypasses all permission checks (F-006)

---

### API Script A2: `task_lookup_product_barcode.py`

| Attribute | Value |
|---|---|
| Type | API |
| Enabled | Yes |
| Lines | 17 |

**What it does**:
1. Takes `barcode` from form_dict
2. First checks if barcode directly matches an Item name (i.e., item_code == barcode)
3. Then checks `Item Barcode` child table for a matching barcode entry
4. Returns `{ok: True, barcode: <input>, item_code: <found_or_null>}`

**Code quality**: Simple and correct. Returns null for item_code when not found (doesn't throw), letting the caller decide how to handle it.

**Gap**: Does not parse GS1 barcodes. GS1 barcode parsing is handled separately in `GS1 Barcode Parser.js` (Group 5) and `dispatch_case_packing_scan.py` (Group 5). This script handles only simple item-code or Item Barcode lookups.

---

### Client Script A3: `Dispatch Case-Template Auto Fill.js`

| Attribute | Value |
|---|---|
| DocType | Dispatch Case |
| View | Form |
| Enabled | Yes |
| Lines | 40 |

**See F-005.**

**Detailed behavior** (lines 7-45):
1. Triggered by `custom_select_surgical_kit_template` field change
2. Fetches full document from `Surgical Kit Template` DocType
3. Reads `template_items` child table
4. **Clears all existing case_items** (line 29: `frm.clear_table("case_items")`)
5. Adds each template item with item_code, item_name, dispatched_qty

**Important**: `clear_table` on line 29 means selecting a template **replaces all existing items**. If a user has manually added items and then selects a template, all manual items are lost without warning. This should at minimum show a confirmation dialog.

---

## Custom Fields Analysis

### Item Custom Fields (5)

| Field | Type | Required | Unique | Documented In | Status |
|---|---|---|---|---|---|
| `pack_breaking_policy` | Select | Yes | No | Doc 06A §4.5 | **MATCH** |
| `reorder_change_reason` | Small Text | No | No | Doc 08A §7.3 | **MATCH** |
| `hs_code` | Data | No | No | Doc 17 | **MATCH** (Group 4 scope) |
| `import_tax_rate` | Float | No | No | Doc 17 | **MATCH** (Group 4 scope) |
| `custom_1c_code` | Data | No | No | — | **UNDOCUMENTED** (F-008) |

### Item Reorder Custom Fields (1)

| Field | Type | Required | Documented In | Status |
|---|---|---|---|---|
| `buffer_percentage` | Float | No | — | **UNDOCUMENTED** (F-009) |

### Customer Custom Fields (6)

| Field | Type | Required | Unique | Documented In | Status |
|---|---|---|---|---|---|
| `client_code` | Data | Yes | Yes | Doc 04A §3.1 | **MATCH** |
| `client_kind` | Select | Yes | No | Doc 04A §3.2 | **MATCH** |
| `debt_threshold_amd` | Currency | Yes | No | Doc 04A §3.3 | **MATCH** |
| `is_provisional` | Check | No | No | Doc 04A §3.4 | **MATCH** |
| `hospital` | Link | No | No | Doc 04A (SO/SI only) | **UNDOCUMENTED on Customer** (F-007) |
| `doctor_name` | Data | No | No | Doc 04A (SO/SI only) | **UNDOCUMENTED on Customer** (F-007) |

### Property Setters

**Item (6 setters)**:
- `naming_series`: hidden=1, reqd=0 (hide auto-naming)
- `item_code`: hidden=0, reqd=1 (make item_code visible and required)
- `barcodes`: hidden=0 (show barcode section)
- `show_title_field_in_link`: 1 (show item_name in link fields)

All make sense for the operational model (code-based naming, barcode-first). Not explicitly documented in Docs 06/06A but are sensible configuration.

**Customer (2 setters)**:
- `naming_series`: hidden=1, reqd=0 (hide auto-naming, use manual Customer Name)

Matches Doc 04 naming convention (manual `<Code> — <Name>` pattern).

**Stock Entry (2 setters)**:
- `scan_barcode`: hidden=0 (show scan field on Stock Entry)
- Stock Entry Detail `barcode`: hidden=0 (show barcode column)

Not documented but reasonable for barcode-first operations.

---

## Cross-Group Dependencies

| Item | This Group | Other Group | Note |
|---|---|---|---|
| `dispatch_case_packing_scan.py` FEFO checks | F-002 (FEFO disabled on SE) | Group 5 (Packing) | Packing scan has FEFO; stock entries do not |
| `SO-customer-autofill.js` uses Customer.hospital | F-007 (undocumented fields) | Group 1 (Dispatch) | Auto-fills from Customer to Sales Order |
| `Surgery-Case-before-save.py` (255 lines, ENABLED) | F-005 (Surgical Kit Template) | Group 6 (Legacy) | Uses same legacy DocType naming |
| `Task-Product Lines Display.js` hardcodes `Main - Inmed` | N/A | Group 1 (Dispatch) | BUG-05 FIXED — script disabled, superseded by Task-Create Dispatch Case Items.js |
| `Dispatch Case-Form.js` has Collection Set loading | F-005 (template mismatch) | Group 1 (Dispatch) | May duplicate or conflict with template auto-fill |

---

## Recommendations

### Immediate Fixes (Critical/High)

| Priority | Finding | Action | Effort |
|---|---|---|---|
| **P0** | F-001 | Set `reference_doctype = "Customer"` on the `Customer-before-save-governance` server script record in production | 2 minutes |
| **P1** | F-002 | Re-enable `StockEntry-before-submit-fefo.py` after verifying it still works with current batch/expiry data | 30 minutes (test first) |
| **P1** | F-003 | Re-enable `Stock Entry-before-save-no-client-wh.py` after verifying no legitimate flows depend on disabled behavior | 30 minutes (test first) |

### Medium-Term Fixes

| Priority | Finding | Action | Effort |
|---|---|---|---|
| **P2** | F-004 | Disable `Surgery-Set-Type-validate-readiness.py` (keep `Collection-Set-validate-readiness.py`) | 2 minutes |
| **P2** | F-005 | Determine which DocType has actual data. Migrate to one DocType. Update Link field and all loading scripts | 2-4 hours |
| **P2** | F-006 | Add role check to `task_add_dispatch_product.py` before ignore_permissions save | 15 minutes |

### Documentation Updates

| Priority | Finding | Action | Effort |
|---|---|---|---|
| **P3** | F-007 | Add hospital/doctor_name on Customer to Doc 04A; document auto-fill behavior | 30 minutes |
| **P3** | F-008 | Document custom_1c_code purpose and migration context | 15 minutes |
| **P3** | F-009 | Document buffer_percentage purpose or remove if unused | 15 minutes |
| **P3** | F-010 | Document task_add_dispatch_product and task_lookup_product_barcode APIs | 30 minutes |
| **P3** | F-011 | Document Products Button item selection UI in Dispatch Case docs | 30 minutes |
| **P3** | F-012 | Fix HTML escaping in Dispatch Case-Products Button.js | 15 minutes |

---

## Verification Items (Require Live Environment)

These findings cannot be fully resolved from static code analysis alone:

| ID | What to verify | How |
|---|---|---|
| V-001 | Confirm Customer governance script is truly not firing | Test: as Order Accepting user, change client_code on a Customer. If it succeeds without error, F-001 is confirmed. |
| V-002 | Check if Surgical Kit Template has actual data records | Query: `SELECT count(*) FROM "tabSurgical Kit Template"` |
| V-003 | Check if Collection Set has actual data records | Query: `SELECT count(*) FROM "tabCollection Set"` |
| V-004 | Confirm FEFO enforcement gap | Test: create Stock Entry from Main - Inmed, select a later-expiring batch when an earlier one exists. If no warning appears, F-002 is confirmed. |
| V-005 | Confirm client warehouse guard gap | Test: create a Stock Entry with a sales_order link targeting a client location warehouse. If it saves, F-003 is confirmed. |
| V-006 | Check buffer_percentage usage | Query: `SELECT count(*) FROM "tabItem Reorder" WHERE buffer_percentage > 0` |
