# Group 6: Legacy and Superseded Code — Production Audit

> **Audited by**: Devin (2026-08-27)
> **Scope**: All scripts, DocTypes, workflows, and schema artifacts that predate the unified Dispatch Case flow (Doc 16) or that exist as disabled/abandoned code in production.
> **Method**: Every script read line by line. Every field and DocType verified against schema exports. Every doc reference verified against the actual document text. No assumptions.

---

## Executive Summary

Production contains a **fully operational parallel workflow system** alongside the current Dispatch Case architecture. The Surgery Case system — 12 workflow states, a 255-line orchestrator script, a dedicated Frappe Workflow, client scripts, and 3 custom DocTypes — is **active and enabled** despite the documentation (Doc 16, docs-overview.md) declaring it superseded.

Additionally, production has **two duplicate template DocTypes** (`Collection Set` and `Surgical Kit Template`) with different scripts targeting each one, **two identical readiness validation scripts** that both fire on every Collection Set save, **two dangerous API scripts** that can silently disable batch/expiry tracking across all items, and **6 disabled scripts** in various states of replacement.

| Category | Count | Severity |
|---|---|---|
| Active legacy systems that should be sunset | 3 findings | HIGH |
| Duplicate/redundant code | 3 findings | MEDIUM |
| Dead/misregistered code | 2 findings | LOW |
| Dangerous utility APIs | 2 findings | HIGH |
| Disabled scripts (assessed) | 6 findings | LOW |
| **Total findings** | **16** | |

---

## 1. Scripts Analyzed

### 1.1 Enabled Server Scripts (4)

#### S1: `Surgery-Case-before-save.py`
- **Schema**: DocType Event | Surgery Case | Before Save | Disabled: 0
- **Lines**: 279
- **What it does**: Complete Surgery Case workflow orchestrator. Contains a `run_script(doc)` function that:
  - Defines 4 warehouse constants: `Main - Inmed`, `Delivery In-Transit - Inmed`, `Return Pickup In-Transit - Inmed`, `Returns - Inmed`
  - Contains `make_transfer()` helper that creates Stock Entry (Material Transfer) with optional posting datetime, batch, serial, and links to surgery_case/dispatch_group_id
  - Contains `make_task()` helper that creates Task with task_kind, task_access_policy, surgery_case link, customer, dispatch_group_id, and _assign
  - **Draft state**: Auto-loads template items from `Collection Set` (via `surgery_set_type` field) into `case_items` child table. Shows non-blocking stock shortage warning using `actual_qty` from Bin.
  - **Any non-Draft state**: Requires `client_location_warehouse` to be set.
  - **Delivery task creation**: When `delivery_person` is set and state is past Dispatch Picking, creates a Delivery task (idempotent — checks `delivery_task` is empty).
  - **Return task creation**: When `return_pickup_delivery_person` is set in Return Pickup Scheduled state, creates both "Pickup Returns" and "Return drop-off at warehouse" tasks (idempotent).
  - **Preparing → Dispatch Picking**: Hard stock gate — checks `actual_qty` in Main WH, throws if insufficient. Creates draft Stock Entry (Main → Delivery In-Transit), stores name in `dispatch_stock_entry`.
  - **Dispatch Picking → Dispatched**: Validates dispatch Stock Entry exists and is submitted (docstatus=1).
  - **Dispatched → Delivered**: Validates Delivery Task is Completed. Copies items from dispatch Stock Entry (preserving batch/serial), creates delivery Stock Entry (Delivery In-Transit → Client WH), submits it immediately, stores name in `delivery_stock_entry`.
  - **Return Pickup Scheduled → Return Pickup In Transit**: Validates Pickup Returns task is Completed.
  - **Return Pickup In Transit → Returns Verification**: Validates Return drop-off task is Completed. Creates two draft return Stock Entries: (1) Client WH → Return Pickup In-Transit (backdated to pickup completion time), (2) Return Pickup In-Transit → Returns WH (current time). Stores both names.
  - **Returns Verification → Returns Received**: Validates both return Stock Entries are submitted.
  - **Returns Received → Usage Derived**: Computes `used_qty = dispatched - returned - lost_damaged` for each item (throws if negative). Creates and submits a Material Issue consumption Stock Entry from Client WH, handling batch allocation (subtracts returned from dispatched per batch key) and serial number accountability (checks Tool Serial Exceptions for missing serials).
  - **Usage Derived → Invoiced**: Creates draft Sales Invoice with customer, hospital/branch/doctor fields, and items from case_items where used_qty > 0.
  - **Invoiced → Closed**: Serial accountability gate — blocks close if any dispatched serial-tracked items are missing from returns AND not recorded in Tool Serial Exceptions.

#### S2: `Surgery-Set-Type-validate-readiness.py`
- **Schema**: DocType Event | Collection Set | Before Save | Disabled: 0
- **Lines**: 47
- **What it does**: Checks projected stock in `Main - Inmed` for each item in the Collection Set's `items` child table. Sets `readiness_status` to "Critical Short" (if any `is_critical` item is short), "Short" (if any item is short), or "Ready". Writes details to `readiness_note`. Shows `frappe.msgprint` warning for shortages.
- **Identical to**: `Collection-Set-validate-readiness.py` (character-for-character match — verified by reading both files). Both fire on `Collection Set` Before Save. Both are enabled.

#### S3: `disable_all_item_batch_serial_for_now.py`
- **Schema**: API | Disabled: 0
- **Lines**: 23
- **What it does**: API endpoint that fetches ALL Item records (no filter, `limit_page_length=0`), iterates through every item, and sets `has_batch_no=0`, `has_serial_no=0`, `has_expiry_date=0` using `frappe.db.set_value` with `update_modified=False`. Commits the transaction. Returns count of items checked and changed.
- **Key detail**: Uses `update_modified=False` — this means changes are invisible in the Item's modification history. No audit trail.
- **Callable via**: `POST /api/method/disable_all_item_batch_serial_for_now` (no special auth beyond being a logged-in user)

#### S4: `perm_disable_batch_expiry_dbset.py`
- **Schema**: API | Disabled: 0
- **Lines**: 26
- **What it does**: API endpoint that accepts a `codes` parameter (comma-separated item codes). For each code, checks if Item exists, then sets `has_batch_no=0` and `has_expiry_date=0` using `frappe.db.set_value` with `update_modified=False`. Returns lists of updated and missing items.
- **Key detail**: Does NOT disable `has_serial_no` (unlike S3). Also uses `update_modified=False`.
- **Callable via**: `POST /api/method/perm_disable_batch_expiry_dbset?codes=ITEM-001,ITEM-002`

### 1.2 Enabled Client Scripts (2)

#### C1: `Surgery-Case-field-locking.js`
- **Schema**: Surgery Case | Form | Enabled: 1
- **Lines**: 17
- **What it does**: On Surgery Case form refresh, reads `workflow_state` and controls field editability:
  - `dispatched_qty`: editable only in Draft, Preparing, Dispatch Picking
  - `returned_qty`: editable only in Return Pickup In Transit, Returns Verification
  - `lost_damaged_qty`: editable only in Return Pickup In Transit, Returns Verification
  - `used_qty`: always read-only (computed by server script)
- **Assessment**: Correctly mirrors the server-side logic in S1. The locking states make sense — you edit dispatch quantities early, return quantities late.

#### C2: `Task - Load Surgical Kit Template.js`
- **Schema**: dt=Task | Form | Enabled: 1
- **Lines**: 39
- **What it does**: The script is **registered for the Task DocType** but contains `frappe.ui.form.on('Dispatch Case', ...)`. It hooks the `surgery_set_type` field change on Dispatch Case, loads a `Collection Set` document, and populates `case_items` child table with `item_code`, `item_name`, `dispatched_qty` from the template.
- **Critical problem**: Because it is registered against `dt=Task`, it only loads when a user opens a Task form. The code inside hooks Dispatch Case events, which will never fire in the Task context. **This script is dead code** — it executes nothing useful.
- **Additional problems in the code itself** (even if it were registered correctly):
  - Tries `template.template_items || template.items` — `template_items` is the `Surgical Kit Template` field name, `items` is the `Collection Set` field name. Since it loads from Collection Set, `template.items` would work, but `template_items` would be undefined (harmless, falls through to `items`).
  - Sets `child.item_code` and `child.item_name` — but Dispatch Case Item uses `item_code` and `item_name`, while Collection Set Item uses `item` (not `item_code`). The fetch from Collection Set returns `item`, not `item_code`, so `item.item_code` would be undefined. The data would not populate correctly.

### 1.3 Disabled Server Scripts (4)

#### D1: `Task-after-insert-assign.py`
- **Schema**: DocType Event | Task | After Insert | Disabled: 1
- **Lines**: 19
- **What it does**: On Task creation, if `custom_assign_to` is set, calls `frappe.desk.form.assign_to.add()` to create an assignment. Catches and logs errors to allow task creation even if assignment fails.
- **Why disabled**: The `frappe.desk.form.assign_to` module is not available in ERPNext Server Script's RestrictedPython sandbox. This script would throw an import error. All current task creation code uses direct `_assign` JSON field writes instead.
- **Replacement**: Task creation in `Surgery-Case-before-save.py` (line 52), `Task-after-save-dispatch-flow.py`, `Sales Order-after-submit-pack-task.py` — all use `t._assign = json.dumps([user])` directly.
- **Status**: Fully superseded. Safe to remove.
- **Confidence**: 0.95

#### D2: `Task-dispatch-queue-integration.py`
- **Schema**: DocType Event | Task | After Save | Disabled: 1
- **Lines**: 46
- **What it does**: Maps 12 task kinds to team roles (e.g., "Order entry" → "Ops - Order Accepting", "Delivery" → "Delivery Driver"). On every Task save, sets `custom_is_team_queue_task=1`, `custom_team_queue_role` to the mapped role, and `custom_team_queue_status` to "Accepted" (if real users assigned) or "Open For Team" (if only team placeholder emails assigned). Uses a hardcoded list of team placeholder emails (e.g., `inventory.team@example.com`, `delivery.team@example.com`).
- **Why disabled**: Replaced by `dispatch_task_queue_backfill.py` (API) for backfilling, and manual field setting in task creation scripts. However, the Group 2 audit notes that `make_task()` in `Task-after-save-dispatch-flow.py` does NOT set team queue fields, creating a **functionality gap** — new tasks created by the dispatch flow do not get their team queue fields populated.
- **Status**: Partially superseded. The backfill API exists but the per-save automation was lost.
- **Confidence**: 0.90

#### D3: `Task-team-queue-notify.py`
- **Schema**: DocType Event | Task | After Save | Disabled: 1
- **Lines**: 72
- **What it does**: When a task is saved and not yet assigned to a real user, creates ToDo notifications for all enabled users who have the team role. Sets `custom_team_notified=1` to prevent duplicate notifications. Uses the same task-kind-to-role mapping as D2 (same 12 entries, same placeholder email list, minus `directors.team@example.com`).
- **Why disabled**: Likely disabled because Telegram notifications (separate system) replaced ToDo-based team notifications. However, Telegram notifications only fire on ToDo creation (assignment) and Task status changes — they do NOT cover the "team queue available" use case that this script addresses.
- **Status**: Not fully replaced. The "notify team members about available tasks" functionality is lost.
- **Confidence**: 0.90

#### D4: `Task-before-save-return-dropoff-photo.py`
- **Schema**: DocType Event | Task | Before Save | Disabled: 1
- **Lines**: 19
- **What it does**: When a "Return drop-off at warehouse" task is being completed, requires `warehouse_dropoff_photo` to be attached. Also sets `completed_at` timestamp if missing.
- **Why disabled**: The Group 2 audit confirms this logic was absorbed into `Task-before-save-dispatch-gates.py` (lines 96-118), which now handles photo requirements for multiple task kinds including return drop-off. The `completed_at` timestamp is now set by `Task-before-save-policy.py`.
- **Status**: Fully superseded by dispatch-gates + policy scripts.
- **Confidence**: 0.95

### 1.4 Disabled Client Scripts (2)

#### D5: `Task-Hide Sidebar Assignment.js`
- **Schema**: Task | Form | Enabled: 0
- **Lines**: 52
- **What it does**: Aggressively hides ALL assignment-related UI on Task forms — sidebar assignments, assign_to fields, any field with "assign" in the name. Also auto-assigns to current user on new task creation. Uses jQuery selectors and `setTimeout` hacks to find and hide DOM elements.
- **Why disabled**: Too broad — it hid ALL assignment fields including `custom_assigned_to` and `custom_next_task_assign_to` which operational users need. Replaced by more targeted visibility control in `Task-Accept Start.js` and `Task-Lock Unaccepted.js`.
- **Status**: Fully superseded.
- **Confidence**: 0.90

#### D6: `Dispatch Case-Item Code Toggle.js`
- **Schema**: Dispatch Case | Form | Enabled: 0
- **Lines**: 41
- **What it does**: **DocType mismatch** — registered for Dispatch Case Form but contains `frappe.listview_settings['Task']` code that adds a "Toggle My Custom Filter" button to the Task list view. The button calls `your_app.api.get_filtered_tasks` — a placeholder API path that was never implemented (literal string `your_app.api.get_filtered_tasks`).
- **Why disabled**: This was an early prototype/experiment for task list filtering. It was never completed (the API path is a placeholder). It was registered under the wrong DocType. It has been fully superseded by `task_list_filtered.py` (API) and `Task-List Toggle Filters.js` (client script).
- **Status**: Prototype/dead code. Never worked.
- **Confidence**: 0.98

---

## 2. Legacy DocTypes and Schema

### 2.1 Surgery Case (Active in Production)

**DocType**: `Surgery Case` — custom, non-submittable
**Workflow**: `Surgery Case Workflow` — **IS_ACTIVE: 1**

**12 Workflow States**:

| # | State | doc_status | Allow Edit |
|---|---|---|---|
| 1 | Draft | 0 | Ops - Order Accepting |
| 2 | Preparing | 0 | Ops - Order Accepting |
| 3 | Dispatch Picking | 0 | Ops - Inventory |
| 4 | Dispatched | 0 | Ops - Delivery |
| 5 | Delivered | 0 | Ops - Order Accepting |
| 6 | Return Pickup Scheduled | 0 | Ops - Delivery |
| 7 | Return Pickup In Transit | 0 | Ops - Returns |
| 8 | Returns Verification | 0 | Ops - Returns |
| 9 | Returns Received | 0 | Ops - Returns |
| 10 | Usage Derived | 0 | Ops - Accounting |
| 11 | Invoiced | 0 | Ops - Order Accepting |
| 12 | Closed | 0 | System Manager |

**11 Transitions** (sequential, one direction only — no skip, no backward):
Draft → Preparing → Dispatch Picking → Dispatched → Delivered → Return Pickup Scheduled → Return Pickup In Transit → Returns Verification → Returns Received → Usage Derived → Invoiced → Closed

**Fields (26)**: client, hospital, hospital_branch, client_location_warehouse, doctor_name, surgery_date, surgery_set_type (Link → Collection Set), workflow_state, dispatch_group_id, delivery_person, return_pickup_delivery_person, shortage_note, notes, packed_scan_log, returned_scan_log, dispatch_stock_entry, delivery_stock_entry, return_pickup_stock_entry, return_receive_stock_entry, consumption_stock_entry, sales_invoice, delivery_task, return_pickup_task, return_dropoff_task, case_items (Table → Surgery Case Item), tool_serial_exceptions (Table → Surgery Case Serial Exception)

**Child: Surgery Case Item** — Fields: item, dispatched_qty, returned_qty, lost_damaged_qty, used_qty

**Child: Surgery Case Serial Exception** — Fields: item, serial_no, exception_type (Missing/Damaged/Not Serialized), notes

### 2.2 Surgical Kit Template (Orphaned / Partially Used)

**DocType**: `Surgical Kit Template` — custom, non-submittable, non-table
**Fields**: template_name, describtion (sic — typo in field name), template_items (Table → Surgical Kit Template Item)
**Child: Surgical Kit Template Item** — Fields: item_code (Link → Item), item_name, qty

**Who links to this DocType**:
- `Task.custom_select_surgical_kit_template` — Link → Surgical Kit Template
- `Dispatch Case.custom_select_surgical_kit_template` — Link → Surgical Kit Template
- `Dispatch Case-Template Auto Fill.js` (Group 7) — loads items from Surgical Kit Template into Dispatch Case

**Who does NOT link to this**:
- `Surgery Case.surgery_set_type` links to `Collection Set`, NOT Surgical Kit Template
- `Surgery-Case-before-save.py` loads from `Collection Set`, NOT Surgical Kit Template

### 2.3 Collection Set (Active, Dual-Purpose)

**DocType**: `Collection Set` — custom, non-submittable
**Fields**: set_name, set_code, is_active, notes, readiness_status, readiness_note, items (Table → Collection Set Item)
**Child: Collection Set Item** — Fields: item (Link → Item), default_qty, uom, group (Tools/Instruments, Screws, Nails, Plates), return_behavior (Expected Return (Tools), May Be Used (Implants)), is_optional, is_critical, notes

**Who links to this DocType**:
- `Surgery Case.surgery_set_type` — Link → Collection Set
- `Surgery-Case-before-save.py` — loads items from Collection Set
- `Collection-Set-validate-readiness.py` — validates readiness
- `Surgery-Set-Type-validate-readiness.py` — validates readiness (duplicate)
- `Dispatch Case-Form.js` (Group 1) — loads items via `surgery_set_type` field on Dispatch Case (but this field references Collection Set)

**Comparison with Surgical Kit Template**:

| Aspect | Collection Set | Surgical Kit Template |
|---|---|---|
| Item field name | `item` (Link → Item) | `item_code` (Link → Item) |
| Qty field name | `default_qty` | `qty` |
| Child table fieldname | `items` | `template_items` |
| Has group/return_behavior | Yes | No |
| Has is_critical/is_optional | Yes | No |
| Has readiness status | Yes | No |
| Used by Surgery Case | Yes | No |
| Used by Dispatch Case fields | No (field links to Surgical Kit Template) | Yes |
| Documented in Doc 11 | Yes | No |
| Documented in Doc 16 | Yes (referenced as template source) | No |

---

## 3. Comparison: Surgery Case vs Dispatch Case

### 3.1 State Machine Comparison

| Surgery Case State | Dispatch Case Status | Notes |
|---|---|---|
| Draft | Draft | Same concept |
| Preparing | — | Not in Dispatch Case (DC goes straight to Confirmed) |
| Dispatch Picking | — | Not in Dispatch Case |
| — | Awaiting Approval | Not in Surgery Case (SC has no discount approval) |
| — | Confirmed | Closest to "Preparing" in SC |
| — | Packed | Closest to "Dispatch Picking done" in SC |
| Dispatched | In Transit | Same concept, different name |
| Delivered | Delivered | Same concept |
| — | Awaiting Return | Not in Surgery Case (SC always expects returns) |
| Return Pickup Scheduled | Return Pickup Scheduled | Same concept |
| Return Pickup In Transit | Return In Transit | Same concept, different name |
| Returns Verification | Returned to Warehouse | Different name, SC has more granularity |
| Returns Received | — | Not in Dispatch Case (DC merges verification+receipt) |
| Usage Derived | Inspection Complete | Similar concept |
| — | Restocked | Not in Surgery Case (SC does not restock) |
| Invoiced | Invoiced | Same concept |
| Closed | Closed | Same concept |

### 3.2 Mechanism Comparison

| Aspect | Surgery Case | Dispatch Case |
|---|---|---|
| State management | Frappe Workflow (`workflow_state`) | Custom status field |
| State transitions | Workflow action buttons | Task completion triggers |
| Orchestrator | Single Before Save script (279 lines) | Multiple Task After Save scripts |
| Stock entries created by | The Surgery Case script itself | Task scripts (dispatch-flow.py) |
| Invoice creation | The Surgery Case script itself | Task scripts (dispatch-flow.py) |
| Task creation | The Surgery Case script itself | Task scripts (pack-complete, dispatch-flow.py) |
| Discount approval | None | Built into flow (Awaiting Approval state) |
| Prepayment gate | None | Supported via Sales Order link |
| Template source | Collection Set | Surgical Kit Template |
| Packing scan | Not implemented (only scan log fields) | Full packing scan system |
| Batch/serial handling | Full support (batch allocation, serial accountability) | Temporarily disabled |
| Consumption entry | Yes (Material Issue) | Yes (Material Issue in dispatch-flow.py) |
| Restocking | No | Yes (Returns WH → Main WH) |
| Serial exception tracking | Yes (Surgery Case Serial Exception table) | No equivalent |

### 3.3 Key Differences in Stock Logic

**Surgery Case** (S1 lines 173-238):
- Consumption Stock Entry handles batch-by-batch allocation: dispatched batches minus returned batches
- Serial number accountability: dispatched serials minus returned serials, with Tool Serial Exceptions
- Close gate: cannot close if serials are unaccounted for

**Dispatch Case** (per Group 1 audit):
- `Task-after-save-dispatch-flow.py` creates consumption entry with `ignore_stock_validation` flag
- No batch-by-batch allocation logic
- No serial accountability gate at close

---

## 4. Findings

### F-001: Surgery Case System Fully Active in Production
**Type**: RISK | **Severity**: HIGH | **Confidence**: 0.98

**Evidence**:
- `Surgery Case Workflow` — `is_active: 1` (schema: `workflows.json`)
- `Surgery-Case-before-save.py` — `Disabled: 0` (schema: `server-scripts.json`, line 5 of script)
- `Surgery-Case-field-locking.js` — `Enabled: 1` (schema: `client-scripts.json`)
- `Surgery Case` DocType exists with 26 fields and 2 child tables
- 12 workflow states, 11 transitions — all configured

**What this means**: Any user with the `Ops - Order Accepting` role can create a new Surgery Case right now and run it through the entire 12-state workflow. The system will create Stock Entries, Tasks, and Sales Invoices — all completely independent of the Dispatch Case flow.

**What the documentation says**: Doc 16 (line 5 area): "The Dispatch Case replaces both the Sales Order and the Surgery Case." `docs-overview.md` marks Docs 09, 11, 12 as "Superseded by Doc 16."

**The gap**: Documentation says superseded but production says fully operational. There is no documented sunset plan, no protection against creating new Surgery Cases, and no indication of whether existing in-flight Surgery Cases still exist.

**Recommendation**: NEEDS DECISION — either:
- (a) Disable the Surgery Case Workflow and the before-save script if no in-flight cases exist, OR
- (b) Document that Surgery Case remains active for a specific reason, set a sunset date, and add a guard preventing new case creation after that date, OR
- (c) If in-flight cases exist, complete them first, then disable.

**What needs verification (live)**: Query `SELECT name, workflow_state FROM \`tabSurgery Case\` WHERE workflow_state != 'Closed' AND workflow_state != 'Draft'` to check for in-flight cases.

---

### F-002: Two Identical Readiness Validators Fire on Every Collection Set Save
**Type**: BUG | **Severity**: MEDIUM | **Confidence**: 0.99

**Evidence**: I read both files character by character:
- `Collection-Set-validate-readiness.py` — 47 lines, DocType Event, Collection Set, Before Save, Disabled: 0
- `Surgery-Set-Type-validate-readiness.py` — 47 lines, DocType Event, Collection Set, Before Save, Disabled: 0

They are **identical**. Same warehouse constant (`Main - Inmed`), same iteration over `doc.items`, same projected_qty check, same shortage/critical logic, same `readiness_status` and `readiness_note` field writes, same `frappe.msgprint` call.

**What this means**: Every time someone saves a Collection Set, both scripts execute. The readiness check runs twice, and the user sees **two identical warning popups** (one from each script's `frappe.msgprint`). The `readiness_status` and `readiness_note` fields are written twice (second write overwrites first — no functional harm since values are identical, but it's wasted computation).

**Root cause**: `Surgery-Set-Type-validate-readiness` was the original script (name references old "Surgery Set Type" naming). When the DocType was renamed to `Collection Set`, a new script `Collection-Set-validate-readiness` was created with identical logic, but the old one was never disabled.

**Recommendation**: Disable `Surgery-Set-Type-validate-readiness.py`. Keep `Collection-Set-validate-readiness.py` (name matches current DocType).

---

### F-003: Two Template DocTypes Exist — Different Scripts Target Each One
**Type**: RISK | **Severity**: HIGH | **Confidence**: 0.97

**Evidence**:

| DocType | Used By | Field Name | Item Field | Qty Field |
|---|---|---|---|---|
| `Collection Set` | Surgery Case (`.surgery_set_type`), server script S1 | `items` | `item` | `default_qty` |
| `Surgical Kit Template` | Task (`.custom_select_surgical_kit_template`), Dispatch Case (`.custom_select_surgical_kit_template`), `Dispatch Case-Template Auto Fill.js` | `template_items` | `item_code` | `qty` |

**What this means**:
- Users maintaining templates must maintain **two separate DocType lists** if they want templates available to both Surgery Cases and Dispatch Cases.
- The field names differ (`item` vs `item_code`, `default_qty` vs `qty`, `items` vs `template_items`), so any script loading from one cannot load from the other without adaptation.
- `Collection Set` has richer metadata (group, return_behavior, is_critical, is_optional) while `Surgical Kit Template` has only basic item/qty/name.
- Doc 16 references `Collection Set` as the template source. Doc 11 defines `Collection Set`. Neither document mentions `Surgical Kit Template`.
- `Surgical Kit Template` has a typo in its description field: `describtion` instead of `description`.

**Documentation says**: Doc 16: "Collection Set templates (Doc 11A)" as the template source. No mention of `Surgical Kit Template` anywhere in current documentation.

**Recommendation**: NEEDS DECISION:
- (a) Migrate all `Surgical Kit Template` data into `Collection Set` records, update the `custom_select_surgical_kit_template` fields on Task and Dispatch Case to link to `Collection Set` instead, update `Dispatch Case-Template Auto Fill.js` to use Collection Set field names, then deprecate `Surgical Kit Template`. OR
- (b) If `Surgical Kit Template` serves a different purpose (simpler templates without group/return_behavior metadata), document that purpose and rename the field for clarity.

**What needs verification (live)**: Count records in each: `SELECT COUNT(*) FROM \`tabCollection Set\`` and `SELECT COUNT(*) FROM \`tabSurgical Kit Template\``. Check if the same items appear in both.

---

### F-004: Dead Client Script — Registered for Wrong DocType
**Type**: DEAD-CODE | **Severity**: LOW | **Confidence**: 0.98

**Evidence**: `Task - Load Surgical Kit Template.js`:
- **Schema registration**: `dt=Task`, `view=Form`, `Enabled=1`
- **Actual code**: `frappe.ui.form.on('Dispatch Case', { surgery_set_type: function(frm) { ... } })`

The script registers an event handler for `Dispatch Case.surgery_set_type` change, but it only loads when a Task form is opened (because `dt=Task`). Since the Task form has no `surgery_set_type` field and never renders Dispatch Case events, the event handler never fires.

Even if it were registered correctly (dt=Dispatch Case):
- It loads from `Collection Set` but tries field `template.template_items || template.items` — `template_items` doesn't exist on Collection Set (that's the `Surgical Kit Template` field name)
- It sets `child.item_code` but Collection Set Item has field `item` not `item_code` — `item.item_code` would be undefined

**Note**: `Dispatch Case-Template Auto Fill.js` (40 lines, Enabled: 1, dt=Dispatch Case, from Group 7) correctly loads from `Surgical Kit Template` using its actual field names. That script is the working version.

**Recommendation**: Disable `Task - Load Surgical Kit Template.js`. It does nothing.

---

### F-005: Bulk Batch/Serial Disable API — No Access Control, No Audit Trail
**Type**: RISK | **Severity**: HIGH | **Confidence**: 0.97

**Evidence**: `disable_all_item_batch_serial_for_now.py`:
- Type: API, Disabled: 0
- Callable by ANY authenticated user via `POST /api/method/disable_all_item_batch_serial_for_now`
- Iterates over ALL items (`limit_page_length=0`)
- Sets `has_batch_no=0`, `has_serial_no=0`, `has_expiry_date=0` on every item that has any of these flags
- Uses `update_modified=False` — changes are invisible in modification history
- Commits directly to database

**What the documentation says**:
- Doc 06 (Items): Batch + Expiry tracking is required for implants/consumables. Serial tracking is required for tools/instruments.
- Doc 16 (line 5): "Barcode/Product Work Area behavior is optional/future until tracking is re-enabled" and (line 43): "batch/serial tracking is temporarily disabled"
- The script name itself says "for_now" — acknowledging this is temporary.

**The risk**: This API can be called at any time by any logged-in user (no role check in the script). If called accidentally or maliciously, it silently disables all tracking across all items with no audit trail. There is no confirmation prompt, no undo mechanism, and no notification.

**Recommendation**:
- (a) Add a role check (at minimum, restrict to System Manager or Administrator)
- (b) Add logging (`frappe.log_error` or `frappe.logger`) when the API is called
- (c) Consider disabling this script entirely — if tracking re-enablement is planned, this API works against that goal
- (d) If kept, rename to remove "for_now" and document the intentional decision

---

### F-006: Targeted Batch/Expiry Disable API — Same Concerns
**Type**: RISK | **Severity**: MEDIUM | **Confidence**: 0.97

**Evidence**: `perm_disable_batch_expiry_dbset.py`:
- Type: API, Disabled: 0
- Callable by ANY authenticated user
- Accepts comma-separated item codes
- Sets `has_batch_no=0`, `has_expiry_date=0` per item
- Uses `update_modified=False`
- Does NOT disable `has_serial_no` (narrower than S3)

**Same concerns as F-005** but with smaller blast radius (targeted items only vs all items). Still no role check, no audit trail.

**Recommendation**: Same as F-005 — add role check and logging, or disable.

---

### F-007: Disabled Prototype Script — Never Worked
**Type**: DEAD-CODE | **Severity**: LOW | **Confidence**: 0.98

**Evidence**: `Dispatch Case-Item Code Toggle.js`:
- Registered for Dispatch Case Form but contains Task list view code
- Calls `your_app.api.get_filtered_tasks` — a literal placeholder API path
- `Enabled: 0`

**Assessment**: This was an early prototype for Task list filtering. The API path was never replaced with a real endpoint. It was superseded by `task_list_filtered.py` (API) and `Task-List Toggle Filters.js`.

**Recommendation**: Remove entirely. No value in keeping.

---

### F-008: Disabled Task Auto-Assign — Import Error in Sandbox
**Type**: DEAD-CODE | **Severity**: LOW | **Confidence**: 0.95

**Evidence**: `Task-after-insert-assign.py` — tries to `from frappe.desk.form.assign_to import add`. ERPNext Server Scripts run in RestrictedPython where module imports are not allowed. This script would throw an ImportError every time it ran.

All current task creation code uses `t._assign = json.dumps([user])` instead, which works in RestrictedPython.

**Recommendation**: Remove. Cannot work in current environment.

---

### F-009: Disabled Queue Integration — Functionality Gap
**Type**: DOC-MISSING | **Severity**: MEDIUM | **Confidence**: 0.90

**Evidence**: `Task-dispatch-queue-integration.py`:
- Mapped 12 task kinds to team roles
- Set `custom_team_queue_role`, `custom_team_queue_status`, `custom_is_team_queue_task` on every save
- Disabled, replaced by `dispatch_task_queue_backfill.py` (one-time API)

**The gap**: The backfill API populates team queue fields for EXISTING tasks, but new tasks created by `Task-after-save-dispatch-flow.py` do not set these fields. The `make_task()` helper in dispatch-flow.py sets `_assign`, `task_kind`, `task_access_policy` but NOT `custom_team_queue_role` or `custom_team_queue_status`.

**Result**: New dispatch tasks created after the backfill has run will not appear in team queue views unless the backfill is re-run.

**Recommendation**: Either (a) re-enable this script or a simplified version, or (b) add team queue field population to the `make_task()` calls in dispatch-flow.py. Document the decision.

---

### F-010: Disabled Team Queue Notifications — Feature Lost
**Type**: DOC-MISSING | **Severity**: MEDIUM | **Confidence**: 0.90

**Evidence**: `Task-team-queue-notify.py`:
- Created ToDo notifications for all team role members when an unassigned task was available
- Set `custom_team_notified=1` to prevent duplicate notifications
- Disabled — no direct replacement

**What replaced it partially**: Telegram notifications (`Telegram Task Assignment Notification.py`) send notifications when a ToDo is created (i.e., when a task is assigned). But Telegram notifications do NOT fire for "team queue available" events — they fire on assignment, not on availability.

**Result**: When a new task enters the queue for a team role (e.g., "Ops - Inventory"), no notification is sent to team members. They must manually check their queue.

**Recommendation**: Either (a) re-enable with Telegram integration instead of ToDo, or (b) accept that team members must poll their queue and document this as intentional. This is a user experience regression.

---

### F-011: Disabled Return Dropoff Photo Requirement — Absorbed Elsewhere
**Type**: INFO | **Severity**: LOW | **Confidence**: 0.95

**Evidence**: `Task-before-save-return-dropoff-photo.py`:
- Required `warehouse_dropoff_photo` for "Return drop-off at warehouse" task completion
- Set `completed_at` if missing

Per Group 2 audit: This logic is now in `Task-before-save-dispatch-gates.py` (enabled), which handles photo requirements for multiple task kinds. The `completed_at` timestamp is handled by `Task-before-save-policy.py`.

**Recommendation**: Remove. Fully absorbed by existing enabled scripts.

---

### F-012: Disabled Sidebar Hide — Too Aggressive
**Type**: INFO | **Severity**: LOW | **Confidence**: 0.90

**Evidence**: `Task-Hide Sidebar Assignment.js`:
- Hid ALL assignment-related UI via jQuery selectors
- Too broad — hid custom_assigned_to and custom_next_task_assign_to which users need

Per Group 2 audit: Replaced by targeted visibility in `Task-Accept Start.js` and `Task-Lock Unaccepted.js`.

**Recommendation**: Remove. Fully superseded.

---

## 5. Documentation Assessment

### 5.1 Superseded Documentation Status

| Document | docs-overview.md says | Actual Status in Production | Gap |
|---|---|---|---|
| Doc 09 (Standard Selling) | Superseded by Doc 16 | Sales Order scripts STILL ACTIVE (Group 4 audit) | **Production differs from doc status** |
| Doc 11 (Surgery Set Model) | Superseded by Doc 16 | Collection Set DocType active and used by both flows | **Partially still current** — Collection Set is active |
| Doc 12 (Surgery Set Workflow) | Superseded by Doc 16 | Surgery Case system FULLY ACTIVE | **Production differs from doc status** |
| Doc 16 (Unified Dispatch) | Current | Yes, Dispatch Case is current | Match |
| Doc 16 re: batch/serial | "Temporarily disabled" | Two APIs exist to keep it disabled | Match, but no sunset date |

### 5.2 Documentation That Needs Updating

| Document | What needs to change | Confidence |
|---|---|---|
| `docs-overview.md` | Docs 09, 11, 12 should say "Superseded by Doc 16 but **code remains active in production** — see [sunset plan]" | 0.95 |
| Doc 16 | Should explicitly state whether Surgery Cases can still be created, or add a "Legacy Systems" section | 0.95 |
| No document exists | Surgical Kit Template DocType is undocumented. Either migrate to Collection Set or document its purpose | 0.97 |
| No document exists | The batch/serial disable APIs are undocumented. Need a tracking re-enablement plan | 0.95 |
| No document exists | Team queue feature (fields, status, notifications) is undocumented. It was built, partially disabled, and has a functionality gap | 0.90 |

---

## 6. Summary Table

| ID | Type | Severity | Subject | Confidence | Action Required |
|---|---|---|---|---|---|
| F-001 | RISK | HIGH | Surgery Case system fully active despite being documented as superseded | 0.98 | DECISION: disable or document sunset plan |
| F-002 | BUG | MEDIUM | Two identical readiness validators fire on every Collection Set save (duplicate warnings) | 0.99 | Disable `Surgery-Set-Type-validate-readiness.py` |
| F-003 | RISK | HIGH | Two template DocTypes (Collection Set vs Surgical Kit Template) with inconsistent linking | 0.97 | DECISION: migrate to one DocType |
| F-004 | DEAD-CODE | LOW | `Task - Load Surgical Kit Template.js` registered for wrong DocType, never fires | 0.98 | Disable |
| F-005 | RISK | HIGH | Bulk batch/serial disable API — no role check, no audit trail, callable by any user | 0.97 | Add role check + logging, or disable |
| F-006 | RISK | MEDIUM | Targeted batch/expiry disable API — same concerns as F-005 | 0.97 | Add role check + logging, or disable |
| F-007 | DEAD-CODE | LOW | `Dispatch Case-Item Code Toggle.js` — never-completed prototype with placeholder API | 0.98 | Remove |
| F-008 | DEAD-CODE | LOW | `Task-after-insert-assign.py` — cannot work in RestrictedPython | 0.95 | Remove |
| F-009 | DOC-MISSING | MEDIUM | Team queue field population gap — new tasks don't get queue fields | 0.90 | Fix make_task() or re-enable integration script |
| F-010 | DOC-MISSING | MEDIUM | Team queue notifications lost — no replacement for "task available" alerts | 0.90 | DECISION: re-enable or accept UX regression |
| F-011 | INFO | LOW | Return dropoff photo requirement absorbed by dispatch-gates.py | 0.95 | Remove disabled script |
| F-012 | INFO | LOW | Sidebar hide too aggressive, replaced by targeted visibility | 0.90 | Remove disabled script |

---

## 7. Verification Steps (Require Live Environment)

These items cannot be resolved by static code analysis alone:

| # | Verification | Method | Environment |
|---|---|---|---|
| V-1 | Are there in-flight Surgery Cases (not Draft, not Closed)? | SQL: `SELECT name, workflow_state FROM \`tabSurgery Case\` WHERE workflow_state NOT IN ('Draft','Closed')` | Test first, then Prod |
| V-2 | How many Surgery Cases exist total? How many are Closed? | SQL: `SELECT workflow_state, COUNT(*) FROM \`tabSurgery Case\` GROUP BY workflow_state` | Test first, then Prod |
| V-3 | How many Surgical Kit Template records exist? | SQL: `SELECT COUNT(*) FROM \`tabSurgical Kit Template\`` | Test first, then Prod |
| V-4 | How many Collection Set records exist? | SQL: `SELECT COUNT(*) FROM \`tabCollection Set\`` | Test first, then Prod |
| V-5 | Do the same items appear in both template DocTypes? | Compare item lists | Test first, then Prod |
| V-6 | Has `disable_all_item_batch_serial_for_now` ever been called? | Check error logs, or count items where all three flags are 0 | Test first, then Prod |
| V-7 | Which items currently have batch/serial/expiry enabled? | SQL: `SELECT name, has_batch_no, has_serial_no, has_expiry_date FROM tabItem WHERE has_batch_no=1 OR has_serial_no=1 OR has_expiry_date=1` | Test first, then Prod |
| V-8 | Are team queue fields populated on recent tasks? | SQL: `SELECT name, custom_team_queue_role, custom_team_queue_status FROM tabTask ORDER BY creation DESC LIMIT 20` | Test first, then Prod |

---

## 8. Cross-Group Dependencies

| Finding | Related Group | What the other group should check |
|---|---|---|
| F-001 (Surgery Case active) | Group 1 (Dispatch) | Do Dispatch Case task scripts accidentally act on Surgery Case tasks? (task_kind overlap) |
| F-003 (Dual templates) | Group 7 (Item/Stock) | `Dispatch Case-Template Auto Fill.js` loads from Surgical Kit Template — is this the intended behavior? |
| F-005 (Disable APIs) | Group 5 (Packing/Barcode) | FEFO checks in packing scan rely on batch data. If disable API runs, FEFO becomes meaningless. |
| F-009 (Queue gap) | Group 2 (Tasks) | `dispatch_task_queue_backfill.py` exists but is one-shot. New tasks miss queue fields. |
| F-010 (Notifications lost) | Group 8 (Telegram) | Telegram only notifies on assignment, not on "task available for team". |
