# Photo System Deep Analysis

**Date:** 2026-08-27
**Scope:** Every photo-related mechanism across the entire Task system and Dispatch Case lifecycle
**Source:** Static analysis of all deployed client scripts, server scripts, schema fields, property setters, and custom DocTypes

---

## Table of Contents

1. [Photo Field Inventory](#1-photo-field-inventory)
2. [Photo Flows by Task Kind](#2-photo-flows-by-task-kind)
3. [Bug Analysis](#3-bug-analysis)
4. [Correct Behaviors](#4-correct-behaviors)
5. [Architecture Issues](#5-architecture-issues)
6. [Findings Summary Table](#6-findings-summary-table)

---

## 1. Photo Field Inventory

### 1.1 Task Custom Fields (Schema)

| Fieldname | Label | Fieldtype | idx | depends_on | Notes |
|---|---|---|---|---|---|
| `warehouse_pickup_photo` | Warehouse Pickup Photo | Attach | 22 | (none) | Used by Pack and Delivery tasks |
| `custom_delivery_photo` | Delivery Photo | Attach Image | 23 | `eval:doc.task_kind == "Returns processing / verification"` | Populated server-side from Pack task's pickup photo |
| `warehouse_dropoff_photo` | Warehouse Drop-off Photo | Attach | 24 | (none) | Used by Pickup Returns tasks |
| `custom_account_photos` | Photos | Table (→ Account Detail Attachment) | 73 | `eval:doc.task_kind === "Account details"` | **BUG:** depends_on uses `"Account details"` — see Bug #1 |

### 1.2 Account Detail Attachment DocType (child table)

| Fieldname | Label | Fieldtype | idx |
|---|---|---|---|
| `photo` | Photo / Document | Attach Image | 1 |
| `description` | Description | Data | 2 |

This is a custom DocType (`istable: 1`, `editable_grid: 1`, `module: "Projects"`, `custom: 1`). It is the child row type for `custom_account_photos`.

### 1.3 Dispatch Case Fields

| Fieldname | Label | Fieldtype | idx | allow_on_submit |
|---|---|---|---|---|
| `delivery_photo` | Delivery Photo | Attach | 36 | Yes (property setter) |
| `return_dropoff_photo` | Return Drop-off Photo | Attach | 37 | Yes (property setter) |

### 1.4 Field Naming Confusion (Ghost Fields Referenced in Client Code)

Multiple client scripts reference field names that **do not exist** in the schema:

| Referenced name | Scripts that reference it | Exists in schema? |
|---|---|---|
| `custom_warehouse_pickup_photo` | Task-Accept Start.js (line 17) | **NO** |
| `custom_warehouse_drop_off_photo` | Task-Accept Start.js (line 18) | **NO** |
| `custom_warehouse_dropoff_photo` | Task-Accept Start.js (line 19) | **NO** |
| `custom_pickup_photo` | Task-Accept Start.js (line 20) | **NO** |
| `custom_drop_off_photo` | Task-Accept Start.js (line 21) | **NO** |
| `custom_dropoff_photo` | Task-Accept Start.js (line 22) | **NO** |

**Assessment:** These are defensive hide attempts. The actual field names are `warehouse_pickup_photo` and `warehouse_dropoff_photo` (no `custom_` prefix). The `custom_` variants were probably tested at some point or the developer was uncertain of the naming. They don't cause errors (jQuery silently fails on non-existent selectors, `frm.toggle_display` on missing fields is a no-op) but they indicate naming confusion during development.

**Confidence: 0.95** — The schema is authoritative and shows only the non-prefixed versions.

---

## 2. Photo Flows by Task Kind

### 2.1 Order Entry — No Photos (by design)

Order Entry tasks have **no photo upload or display** functionality. This is intentional — Order Entry is a data-entry task (selecting products, quantities, customer) with no physical goods handling that requires photographic evidence.

**Visibility control:** `clean_task_layouts()` in `Order entry - barcode scanning section - hide.js` (lines 65-66) correctly hides `Warehouse Pickup Photo` and `Warehouse Drop-off Photo` for Order Entry tasks.

**Previous state:** An `"+ Add Photos"` button and upload mechanism existed in `Task-Accept Start.js` (`task_mobile_order_entry_photos()` and `window.task_order_entry_add_photos_click()`). These have been **removed** as of 2026-08-27 because Order Entry should not have photos.

**Confidence: 1.00** — Explicit design decision.

---

### 2.2 Pack / Prepare Items Photos

**Upload mechanism:** `task_mobile_pack_photo_button()` in `Task-Mobile Form Layout Fix.js` (lines 289-341)

**Configuration:** `task_mobile_photo_config()` (lines 354-363) returns:
```
{
  button_id: 'task-mobile-pack-add-pickup-photos-btn',
  preview_id: 'task-mobile-pack-photo-preview',
  label: '+ Add Pickup Photos',
  fieldname: 'warehouse_pickup_photo',
  field_label: 'Warehouse Pickup Photo'
}
```

**How it works:**
1. Only runs on mobile (window.innerWidth <= 768).
2. Calls `task_mobile_cleanup_other_photo_buttons()` to remove any Pickup Returns photo buttons/previews.
3. Creates a `"+ Add Pickup Photos"` button.
4. On click:
   a. If new task, saves first.
   b. Calls `frappe.client.get_count` for ALL files attached to this Task.
   c. If >= 5 → blocks.
   d. Opens `frappe.ui.FileUploader` with `max_number_of_files: 5 - existing`.
   e. On success → calls `task_mobile_set_photo_field()` to populate `warehouse_pickup_photo` with the first uploaded URL, then calls `task_mobile_photo_preview()`.
5. Button is anchored after the `warehouse_pickup_photo` field control.

**Photo display (task_mobile_photo_preview, lines 365-441):**
1. Fetches `File` records with `attached_to_doctype: 'Task', attached_to_name: frm.doc.name`.
2. Filters to image extensions.
3. Shows all attached images — this is correct because all images on a Pack task ARE pickup photos. There is no other source of images on this task kind.
4. Auto-sets `warehouse_pickup_photo` field (line 410) to the first image if the field is empty. This is a convenience: it ensures the server-side completion gate passes without the user needing to manually set the Attach field. The guard `if (frm.doc[config.fieldname]) return;` prevents overwriting an existing value. This is correct behavior.
5. Renders 76x76 thumbnails with tap-to-fullscreen.

**Server-side gate (Task-before-save-dispatch-gates.py, lines 67-70):**
```python
if is_completing and doc.task_kind == "Pack / prepare items":
    has_photo = doc.warehouse_pickup_photo or frappe.db.exists("File", {
        "attached_to_doctype": "Task",
        "attached_to_name": doc.name,
        "attached_to_field": "warehouse_pickup_photo"
    })
    if not has_photo:
        frappe.throw("Warehouse Pickup Photo is required before completing...")
```

**Assessment:**
- The photo requirement gate checks BOTH the field value AND a File record with `attached_to_field: "warehouse_pickup_photo"`. This is a belt-and-suspenders approach. Correct.
- The gallery correctly shows all attached images — on a Pack task, all images are pickup photos by definition.
- **ISSUE: Mobile-only** — the photo button and gallery only render on mobile (`window.innerWidth > 768` guard at line 290). Desktop users see only the raw Frappe Attach field, no gallery, no custom upload button.
- **ISSUE: No delete** — users cannot remove a photo from the custom gallery. The Frappe sidebar attachment controls are hidden by `Task-Lock Unaccepted.js` when the task is not accepted by the current user.

**Confidence: 0.97**

---

### 2.3 Delivery Task — No Photos (by design)

Delivery tasks should **NOT** have any photo functionality. The driver picks up packed items and delivers them — no photographic evidence is required on the Delivery task itself.

**Current state (all bugs):**

1. **Client bug:** `clean_task_layouts()` (lines 73-78 of `Order entry - barcode scanning section - hide.js`) currently SHOWS `Warehouse Pickup Photo` for Delivery tasks. This field should be hidden.

2. **Server bug (old-flow gate):** `Task-before-save-policy.py` (lines 62-65) requires `warehouse_pickup_photo` to complete a Delivery task without a dispatch_case. This gate should be removed — Delivery tasks should not require any photo.

3. **Server bug (dispatch flow copy):** `Task-after-save-dispatch-flow.py` (lines 183-184) copies the Delivery task's `warehouse_pickup_photo` to `Dispatch Case.delivery_photo` when delivery status becomes "Delivered". Since Delivery tasks should have no photos, this copy would always be empty. If the Dispatch Case needs a delivery photo, it should source it from the Pack task (which has the actual packing/pickup photos), not from the Delivery task.

**BUG #4 (revised): Delivery tasks should not have photos at all.**
- The `Warehouse Pickup Photo` field is correctly used on Pack tasks (packing photos).
- It was incorrectly shown on Delivery tasks and incorrectly required by the old-flow gate.
- The server-side copy from Delivery task → Dispatch Case `delivery_photo` is dead code if Delivery tasks have no photos.

**Confidence: 1.00** — Explicit design decision confirmed by product owner.

---

### 2.4 Pickup Returns Photos

**Upload mechanism:** `task_mobile_pack_photo_button()` in `Task-Mobile Form Layout Fix.js` (same function as Pack)

**Configuration:** `task_mobile_photo_config()` returns:
```
{
  button_id: 'task-mobile-pickup-returns-add-dropoff-photos-btn',
  preview_id: 'task-mobile-pickup-returns-photo-preview',
  label: '+ Add Drop-off Photos',
  fieldname: 'warehouse_dropoff_photo',
  field_label: 'Warehouse Drop-off Photo'
}
```

**How it works:**
1. Same upload logic as Pack, but targets `warehouse_dropoff_photo`.
2. Same `task_mobile_photo_preview()` renders all attached images — correct, since all images on a Pickup Returns task are drop-off photos.
3. Auto-sets `warehouse_dropoff_photo` to first image if empty (same convenience behavior as Pack).

**Visibility control:** `clean_task_layouts()` (lines 67-71):
- Shows `Warehouse Pickup Photo` → NO (hidden)
- Shows `Warehouse Drop-off Photo` → YES

**Server-side gate (Task-before-save-dispatch-gates.py, lines 93-97):**
When `pickup_status` changes to "Returned to Warehouse":
```python
has_dropoff = doc.warehouse_dropoff_photo or frappe.db.exists("File", {
    "attached_to_doctype": "Task",
    "attached_to_name": doc.name,
    "attached_to_field": "warehouse_dropoff_photo"
})
if not has_dropoff:
    frappe.throw("Drop-off Photo (Warehouse Drop-off Photo) is required...")
```

**Server-side copy (Task-after-save-dispatch-flow.py, lines 204-206):**
```python
if doc.warehouse_dropoff_photo:
    frappe.db.set_value("Dispatch Case", doc.dispatch_case, "return_dropoff_photo", doc.warehouse_dropoff_photo)
```

**Assessment:** This flow is **correctly implemented** for its intended purpose. Same two issues as Pack: mobile-only gallery and no delete button.

**Confidence: 0.97**

---

### 2.5 Returns Processing / Verification Photos

**No upload mechanism.** This task kind does not have its own photo upload. Instead, it DISPLAYS photos from the related Pack task.

**Photo display (fetch_pack_prepare_photo in `Order entry - barcode scanning section - hide.js`, lines 170-250):**

1. Only activates for `"returns processing / verification"` tasks with a `dispatch_case`.
2. Fetches the Pack task for this dispatch case:
   ```javascript
   frappe.client.get_list('Task', {dispatch_case: frm.doc.dispatch_case, task_kind: 'Pack / prepare items'}, ['name', 'warehouse_pickup_photo'])
   ```
3. If found, sets the `"Delivery Photo"` field to the Pack task's `warehouse_pickup_photo` (if empty). **NOTE:** This is a client-side field set that is NOT saved — it only populates the UI.
4. Then fetches ALL files attached to the Pack task and renders them as a gallery titled "Pack / Prepare Photos (N)".
5. Each thumbnail is clickable with fullscreen preview via `window.task_inspect_returns_preview_pack_photo()`.

**Server-side population (Task-after-save-dispatch-flow.py, lines 210-215):**
When a Pickup Returns task reaches "Returned to Warehouse", the server creates a Returns inspection task and copies the Pack task's `warehouse_pickup_photo` to the new task's `custom_delivery_photo`:
```python
pack_photo = frappe.db.get_value("Task", pack_task_name, "warehouse_pickup_photo")
if pack_photo:
    frappe.db.set_value("Task", ret_tid, "custom_delivery_photo", pack_photo, update_modified=False)
```

**Visibility control:** `clean_task_layouts()` (lines 85-86):
- `custom_delivery_photo` is shown ONLY for Inspect Returns.
- Made `read_only: 1`.

**Correct behavior (confirmed by product owner):** The gallery fetches ALL image files attached to the Pack task. This is intentional — the Returns inspector needs to compare what was packed/sent versus what was returned. Showing a live view (not a snapshot) of the Pack task's photos is also correct.

**Implementation notes:**
- The client-side `fetch_pack_prepare_photo()` sets `frm.doc[targetField.df.fieldname]` directly without saving — this is a local-only UI population for display purposes.
- The gallery label "Pack / Prepare Photos" accurately describes the source.
- Non-image attachments on the Pack task are correctly filtered out.

**Confidence: 1.00** — Confirmed correct by design.

---

### 2.6 Account Details Photos

This is the most complex photo implementation. There are THREE separate mechanisms interacting:

#### Mechanism A: `custom_account_photos` Table Field (Schema)

- Field type: `Table` → `Account Detail Attachment` (child DocType with `photo` + `description` fields).
- `depends_on: eval:doc.task_kind === "Account details"` — **BUG #1 (repeated):** The schema condition uses `"Account details"` (lowercase "d") but the actual task kinds are `"Account Details: Entry"` and `"Account Details: Processing"` (uppercase "D", with colon suffix). This means the `depends_on` condition NEVER evaluates to true, and the table field is ALWAYS hidden by Frappe's native conditional display. The client scripts then have to force-show it.

#### Mechanism B: Custom Photo Box (Task-Account Details UI Cleanup.js)

**`task_account_details_ui_cleanup()`** (lines 25-144):
1. Checks if `task_kind.toLowerCase() === "account details"` — this matches NEITHER `"Account Details: Entry"` NOR `"Account Details: Processing"`. It would only match a plain `"Account details"` or `"Account Details"` (case-insensitive).
2. **BUG #7: This function's condition is wrong.** It checks for `"account details"` (no colon, no suffix). But tasks have kinds like `"Account Details: Entry"` and `"Account Details: Processing"`. Unless there are tasks with `task_kind = "Account details"` (no colon), this function NEVER activates for the actual Account Details tasks.

   **Wait — let me re-examine.** The check is `taskKind === "account details"` where `taskKind` is `frm.doc.task_kind.trim().toLowerCase()`. So `"Account Details: Entry".toLowerCase()` = `"account details: entry"` which does NOT equal `"account details"`. This means the entire Account Details UI cleanup — including the photo box — does NOT fire for `Account Details: Entry` or `Account Details: Processing` tasks.

   **However,** `account_details_entry_ui_cleanup()` in `Task-Accept Start.js` (lines 7-59) checks `frm.doc.task_kind !== "Account Details: Entry"` (case-sensitive, with colon). This IS correct for Entry tasks and hides photo fields while showing `custom_account_photos`. But this function only runs for Entry tasks, not Processing tasks.

3. If the condition DID match, it would:
   - Hide the native `custom_account_photos` table control.
   - Create a `#account-details-photos-box-host` div.
   - Render `task_account_details_render_photos_box()`.

**`task_account_details_render_photos_box()`** (lines 178-205):
1. Creates a `"+ Add Photos"` button.
2. On click → opens `frappe.ui.FileUploader` with:
   - **NO `max_number_of_files` restriction** — unlike Order Entry and Other tasks (limited to 5), Account Details has NO upload limit.
   - **NO file count pre-check** — goes straight to the uploader.
3. On success → calls `task_account_details_render_photo_preview()` and `frm.reload_doc()`.

**`task_account_details_render_photo_preview()`** (lines 207-284):
1. Fetches ALL `File` records attached to this Task (not just images from `custom_account_photos`).
2. Filters to image extensions.
3. Renders thumbnails in a gallery labeled "Attached Photos (N)".
4. Uses `normalizeUrl()` to handle private files.

**BUG #8: Shows ALL attached files, not just account detail photos.** The preview fetches `File` records with `attached_to_doctype: 'Task', attached_to_name: frm.doc.name` — this includes ANY file attached to the task, not just those in the `custom_account_photos` child table. If someone attaches a random file via the sidebar, it appears in the "Attached Photos" gallery.

#### Mechanism C: account_details_entry_ui_cleanup (Task-Accept Start.js, lines 7-59)

This function runs for `"Account Details: Entry"` tasks specifically:
1. Hides all warehouse photo fields (including ghost `custom_*` variants).
2. Shows `custom_account_photos` table field.
3. Removes any `#account-details-add-photos-btn`.

**This is the ONLY correctly-conditioned Account Details photo visibility function for Entry tasks.**

#### Server-side Photo Copying (Task-after-save-account-details-processing.py)

When an `Account Details: Entry` task is completed:
1. Creates an `Account Details: Processing` task.
2. **Copies `custom_account_photos` child table rows** (lines 42-44):
   ```python
   if doc.get("custom_account_photos"):
       for row in doc.get("custom_account_photos"):
           new_task.append("custom_account_photos", row.as_dict())
   ```
3. **Also copies ALL file attachments** (lines 60-80):
   ```python
   files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": doc.name}, ...)
   for f in files:
       # Creates new File records attached to the new task
   ```

**BUG #9: Double photo copying.** The child table rows (which contain photo URLs) are copied, AND all File attachments are copied. This means:
- The `custom_account_photos` table will have rows pointing to the original file URLs.
- New `File` records are created pointing to the same file URLs but attached to the new task.
- The photo preview gallery (which reads `File` records) will show these duplicated attachment records.
- If the child table rows and the File records both reference the same photos, the user sees the same photo twice in different UI locations (once in the table, once in the file attachment gallery).

**BUG #10: Processing tasks get NO photo UI.** The `task_account_details_ui_cleanup()` function checks `task_kind.toLowerCase() === "account details"` — this doesn't match `"account details: processing"`. The `account_details_entry_ui_cleanup()` function only fires for Entry tasks. So Processing tasks get:
- The `custom_account_photos` table is hidden by Frappe's `depends_on` (which checks for `"Account details"` — doesn't match `"Account Details: Processing"`).
- No custom photo box is rendered.
- Photos are only visible via the attachment sidebar.

**Confidence: 0.95** for the condition mismatch bugs, **0.85** for the double-copy assessment (depends on whether the child table rows create separate File records or just reference URLs).

---

### 2.7 Other Task Photos

**Upload & display mechanism:** `task_other_render_photos()` in `Task-Other UI Cleanup.js` (lines 139-176)

**How it works:**
1. Activates for `"Other: Entry"` and `"Other: Processing"` tasks.
2. Creates `#other-task-photos-box-host` div anchored after `custom_next_task_assign_to` (fallback: `status`, `priority`).
3. Uses a render token to prevent stale callbacks from overwriting newer renders.
4. Creates a `"+ Add Photos"` button.
5. On click:
   a. Fetches existing File records.
   b. Filters to image extensions.
   c. If images.length >= 5 → blocks with "You can attach up to 5 photos."
   d. Opens `frappe.ui.FileUploader` with `max_number_of_files: 5 - images.length`.
   e. On success → re-renders photos after 500ms delay.
6. Separately fetches and displays all attached image files as a gallery (76x76 thumbnails, tap for fullscreen).

**Photo count logic:**
- The count check happens on the "Add Photos" click, not during display.
- It counts ONLY image files (not all files), using the regex `/\.(png|jpe?g|gif|webp|heic|heif)$/i`.
- The display also limits to `.slice(0, 5)` images.

**BUG #11: Shows ALL attached images, not task-specific photos.** Same issue as Pack/Pickup Returns — the query fetches all `File` records for the task, regardless of how they were attached.

**Server-side photo copying (Task-after-save-other-processing.py, lines 30-45):**
When `Other: Entry` completes → creates `Other: Processing` and copies ALL `File` attachments:
```python
files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": doc.name}, ...)
for f in files:
    nf = frappe.new_doc("File")
    nf.file_url = f.file_url
    nf.attached_to_field = f.attached_to_field  # preserves original field association
    ...
```

**Assessment:** The Other task photo flow is the cleanest implementation. The 5-image limit is properly enforced both on upload and display. The render token prevents stale callback issues. The main problem is the same cross-task contamination as other flows (BUG #11).

**Confidence: 0.95**

---

### 2.8 Disabled Legacy: Return Drop-off Photo Gate

**Script:** `Task-before-save-return-dropoff-photo.py` (DISABLED)

This was a standalone gate that required `warehouse_dropoff_photo` before completing `"Return drop-off at warehouse"` tasks. It is now **disabled** because:
- The same gate logic is implemented in `Task-before-save-dispatch-gates.py` (lines 93-97) for `Pickup Returns` tasks.
- The task kind name changed from `"Return drop-off at warehouse"` to `"Pickup Returns"`.
- The disabled script also sets `completed_at = now_datetime()` which is now handled by `Task-before-save-policy.py` (line 85).

**Assessment:** Correctly disabled. Superseded by the active gate script.

**Confidence: 0.98**

---

## 3. Bug Analysis

### BUG #1: `custom_account_photos` depends_on uses wrong task_kind string
**Severity: HIGH**
**Confidence: 0.98**

**Location:** Schema — `custom_account_photos` field `depends_on: eval:doc.task_kind === "Account details"`

**Problem:** The actual task kinds are `"Account Details: Entry"` and `"Account Details: Processing"`. The condition `=== "Account details"` (no colon, no suffix) never matches. Frappe's native conditional display permanently hides this table field.

**Impact:** The `custom_account_photos` table is never shown by Frappe's built-in mechanism. Client scripts must force-show it. On `Account Details: Processing` tasks, no client script does this, so the table is invisible.

**Fix:** Change to `eval:["Account Details: Entry", "Account Details: Processing"].includes(doc.task_kind)`.

---

### ~~BUG #2~~ RETRACTED: Gallery showing all attached images is correct
**Reclassified: Not a bug**
**Confidence: 1.00**

On Pack tasks, all attached images ARE pickup photos — there is no other source of images on this task kind. Same for Pickup Returns (all images are drop-off photos). The query correctly returns all images for the task. No filtering by `attached_to_field` is needed.

---

### ~~BUG #3~~ RETRACTED: Auto-setting photo field is correct convenience behavior
**Reclassified: Not a bug**
**Confidence: 1.00**

The `task_mobile_set_photo_field()` auto-fills the `warehouse_pickup_photo` (or `warehouse_dropoff_photo`) field with the first attached image if the field is empty. This is a convenience that ensures the server-side completion gate passes without requiring the user to separately set the Attach field. The guard `if (frm.doc[config.fieldname]) return;` prevents overwriting an existing value.

---

### BUG #4: Delivery tasks incorrectly have photo functionality
**Severity: HIGH**
**Confidence: 1.00**

Delivery tasks should not have any photos. Three locations need fixing:

1. **Client:** `clean_task_layouts()` in `Order entry - barcode scanning section - hide.js` (lines 73-78) shows `Warehouse Pickup Photo` for Delivery tasks. Should be hidden.
2. **Server (old-flow gate):** `Task-before-save-policy.py` (lines 62-65) requires `warehouse_pickup_photo` to complete a Delivery task without a dispatch_case. This gate should be removed.
3. **Server (dispatch flow copy):** `Task-after-save-dispatch-flow.py` (lines 183-184) copies the Delivery task's `warehouse_pickup_photo` to `Dispatch Case.delivery_photo`. This is dead code since the field will always be empty.

---

### ~~BUG #5~~ RETRACTED: Returns Inspection showing Pack photos is correct
**Reclassified: Not a bug**
**Confidence: 1.00**

Showing the Pack task's photos on the Returns Inspection task is intentional. The inspector needs to compare what was packed/sent versus what was returned. The live view (not snapshot) behavior is also correct — if the Pack task photos are updated, the inspector always sees the current state.

---

### BUG #6: No photo deletion UI in any custom gallery — FIXED 2026-08-27
**Severity: HIGH**
**Status: FIXED**

**What was wrong:** None of the custom photo galleries had a delete/remove button. Users could not remove incorrectly uploaded photos from the custom UI.

**Fix applied:** Added a red X delete button to each photo thumbnail in all three gallery implementations:
- `Task-Mobile Form Layout Fix.js` — Pack / Pickup Returns gallery
- `Task-Other UI Cleanup.js` — Other task gallery
- `Task-Account Details UI Cleanup.js` — Account Details gallery

The delete button:
1. Confirms with the user ("Remove this photo?")
2. Deletes the `File` record via `frappe.client.delete`
3. Clears the Attach field value (`warehouse_pickup_photo`, `warehouse_dropoff_photo`, `custom_delivery_photo`) if it pointed to the deleted file
4. Reloads the form to refresh the gallery

A shared `window.task_photo_delete_file()` function handles the deletion logic (defined in `Task-Mobile Form Layout Fix.js`).

The Returns Inspection gallery is NOT modified — those are read-only reference photos from the Pack task.

---

### BUG #7: Account Details UI Cleanup condition mismatch
**Severity: HIGH**
**Confidence: 0.97**

**Location:** `task_account_details_ui_cleanup()` in Task-Account Details UI Cleanup.js (line 28)

**Problem:** Checks `taskKind === "account details"` (lowercase, no colon) but actual task kinds are `"Account Details: Entry"` and `"Account Details: Processing"`. The function NEVER fires for these task kinds.

**Impact:** 
- The custom photo box is never rendered via this path for real Account Details tasks.
- The `account_details_entry_ui_cleanup()` in Task-Accept Start.js handles Entry tasks separately (with the correct condition), so Entry tasks partially work.
- Processing tasks get NO custom photo UI at all.

**Related:** This function also hides `custom_account_details_section`, renames section headers, and repositions status/priority — none of this happens for real Account Details tasks.

---

### BUG #8: Account Details photo preview shows ALL task attachments
**Severity: MEDIUM**  
**Confidence: 0.97**

Same as BUG #2 but specifically for Account Details. The `task_account_details_render_photo_preview()` function fetches all `File` records for the task, not just files from `custom_account_photos` rows.

---

### BUG #9: Double photo copying in Account Details flow
**Severity: LOW-MEDIUM**
**Confidence: 0.85**

**Location:** `Task-after-save-account-details-processing.py` lines 42-44 and 60-80

**Problem:** When Entry → Processing, both the child table rows AND all File attachments are copied. If the child table's `Attach Image` fields created File records (which Frappe does for `Attach Image` fields), the same photos end up duplicated:
- Once as child table rows in the new task.
- Once as File attachment records on the new task.

**Impact:** The Processing task may show duplicate photos in the gallery (which reads File records) while the child table also contains the same photos.

**Confidence note:** 0.85 because the exact behavior depends on how Frappe handles `Attach Image` fields in child tables during `new_task.append("custom_account_photos", row.as_dict())` — it may or may not create corresponding File records.

---

### BUG #10: Processing tasks get NO photo UI
**Severity: HIGH**
**Confidence: 0.95**

**Location:** No client script handles photo display for `"Account Details: Processing"` tasks.

**Problem:**
- `task_account_details_ui_cleanup()` doesn't fire (wrong condition — checks `"account details"` not `"account details: processing"`).
- `account_details_entry_ui_cleanup()` only fires for `"Account Details: Entry"`.
- `custom_account_photos` field is hidden by `depends_on` (wrong condition — checks `"Account details"` not `"Account Details: Processing"`).
- The only way to see photos on a Processing task is via the Frappe attachment sidebar.

**Impact:** The processing team cannot see the photos that were copied from the Entry task unless they use the sidebar. This defeats the purpose of the photo copying.

---

### ~~BUG #11~~ RETRACTED: 5-file limit counting all files is correct
**Reclassified: Not a bug**
**Confidence: 1.00**

The 5-file limit counting ALL attached files (not just images) is expected behavior. The total attachment count per task should not exceed 5 regardless of file type.

---

### BUG #12: `task_photo_fullscreen_preview` function is defined THREE times
**Severity: LOW (cosmetic/maintenance)**
**Confidence: 0.99**

**Location:**
1. `Task-Other UI Cleanup.js` lines 92-137
2. `Task-Mobile Form Layout Fix.js` lines 443-528
3. `Task-Accept Start.js` lines (within the script — the back button / photo preview area)

Additionally, `task_inspect_returns_preview_pack_photo()` is a fourth, separate fullscreen viewer defined in `Order entry - barcode scanning section - hide.js` lines 252-340.

**Problem:** Three identical copies of `task_photo_fullscreen_preview()` exist in different scripts. They all create `#task-photo-fullscreen` overlay. If Frappe loads multiple client scripts, the last-loaded definition wins.

**Impact:** Currently harmless because they're identical, but any bug fix must be applied to all three copies. The inspect returns version uses a different overlay ID (`#task-inspect-photo-fullscreen`) which prevents conflicts.

---

### BUG #13: Photo upload buttons are not gated by task acceptance — FIXED 2026-08-27
**Severity: HIGH**
**Status: FIXED**

**What was wrong:** Custom "+ Add Photos" buttons and delete buttons were visible and functional even when the user had NOT accepted the task. `Task-Lock Unaccepted.js` only hid Frappe's native `.btn-attach`, not the custom buttons.

**Fix applied (two layers):**

1. **Primary gate — each photo function checks acceptance before rendering upload/delete buttons:**
   - `task_mobile_pack_photo_button()` in Task-Mobile Form Layout Fix.js — checks `can_edit` before showing upload button; passes flag to `task_mobile_photo_preview()` which skips delete buttons when not accepted
   - `task_other_render_photos()` in Task-Other UI Cleanup.js — only creates upload button and delete buttons when accepted
   - `task_account_details_render_photos_box()` in Task-Account Details UI Cleanup.js — only creates upload button when accepted; passes flag to preview which skips delete buttons
   - `window.task_photo_delete_file()` in Task-Mobile Form Layout Fix.js — guard check at the top refuses deletion if not accepted

2. **Backup safety net — `Task-Lock Unaccepted.js` also hides/shows custom buttons:**
   - Lock branch: hides `.task-photo-delete-btn`, `#task-mobile-pack-add-pickup-photos-btn`, `#task-mobile-pickup-returns-add-dropoff-photos-btn`, `.account-details-add-photos-box`, and Other task upload buttons
   - Unlock branch: shows `.task-photo-delete-btn` and Pack/Pickup Returns upload buttons

The acceptance check is: `is_admin || (custom_accepted_by === current_user)`, matching the existing logic in `Task-Lock Unaccepted.js`.

---

## 4. Correct Behaviors

### 4.1 Server-Side Photo Gates
**Confidence: 0.98**

The following server-side photo requirements are correctly implemented:

| Gate | Script | Condition |
|---|---|---|
| Pack completion requires pickup photo | Task-before-save-dispatch-gates.py:67-70 | Checks field value OR File record |
| Pickup Returns "Returned to Warehouse" requires dropoff photo | Task-before-save-dispatch-gates.py:93-96 | Checks field value OR File record |
| Old-flow Return drop-off requires dropoff photo | Task-before-save-policy.py:66-69 | Only for non-Dispatch Case tasks |

Note: The old-flow Delivery gate (Task-before-save-policy.py:62-65) is now classified as Bug #4 — Delivery tasks should not require photos.

All correct gates use the dual-check pattern: `doc.field_value or frappe.db.exists("File", {...})`. This is robust — even if the field isn't set but a file IS attached to the correct field, the gate passes.

### 4.2 Photo Copy from Pack to Returns Inspection
**Confidence: 0.95**

The server correctly copies the Pack task's `warehouse_pickup_photo` to the Returns Inspection task's `custom_delivery_photo` field (Task-after-save-dispatch-flow.py:210-215). This establishes a reference photo for the inspector.

### 4.3 Photo Copy from Task to Dispatch Case
**Confidence: 0.98**

- Return drop-off photo: `warehouse_dropoff_photo` → `Dispatch Case.return_dropoff_photo` (line 205-206) — correctly triggered by Pickup Returns status transition.

Note: The Delivery task → `Dispatch Case.delivery_photo` copy (line 183-184) is now classified as dead code / Bug #4 since Delivery tasks should not have photos.

### 4.4 Fullscreen Photo Viewer
**Confidence: 0.97**

The fullscreen viewer is well-implemented:
- Pinch-to-zoom with multi-touch support.
- Drag/pan with pointer capture.
- Mouse wheel zoom.
- Zoom in/out/reset buttons.
- Scale clamped between 0.5x and 6x.
- Pan clamped to prevent losing the image.
- Proper pointer event handling.
- Close button.
- Dark overlay background.

### 4.5 Private File URL Handling
**Confidence: 0.95**

The `normalizeUrl()` function correctly handles private files by converting `/private/files/...` URLs to the download API endpoint `/api/method/frappe.utils.file_manager.download_file?file_url=...`. This is implemented consistently across all galleries.

### 4.6 Other Task Photo Flow
**Confidence: 0.93**

The Other task photo implementation is the most robust:
- Render token prevents stale callbacks.
- Image-only count for the 5-photo limit.
- File attachments are correctly copied to Processing tasks.
- Gallery displays only images (filtered by extension).

### 4.7 Dispatch Case Photo Field Visibility (Order Creation)
**Confidence: 0.95**

`Dispatch Case-Simplify for Order Creation.js` correctly hides `delivery_photo` and `return_dropoff_photo` and the entire `photo_section` during order creation, since these photos don't exist yet at that stage.

---

## 5. Architecture Issues

### 5.1 No Centralized Photo Component
**Confidence: 0.99**

There is no shared photo upload/gallery component. Each task kind reimplements:
- Photo upload button creation.
- File count checking.
- Gallery rendering.
- Thumbnail styling.
- Fullscreen preview.

This leads to inconsistencies (different limits, different count methods, different gallery styles) and triple-defined functions.

**Recommendation:** Create a single `task_photo_manager` module with configurable options (field name, limit, image-only counting, etc.) and use it across all task kinds.

### 5.2 File Records vs. Field Values
**Confidence: 0.95**

There is a fundamental mismatch between two photo storage mechanisms:
1. **Attach field values** (`warehouse_pickup_photo`, `warehouse_dropoff_photo`, `custom_delivery_photo`) — store a single URL string on the Task document.
2. **File attachment records** — `File` DocType records with `attached_to_doctype/name/field`.

The galleries display File records. The server gates check Attach fields (with File record fallback). The upload buttons create File records but only sometimes set Attach fields. This creates scenarios where:
- A photo is attached (File record exists) but the field is empty → gate passes via fallback, but the field appears empty in the form.
- The field has a URL but the File record was deleted → field shows a broken link, but gate passes via field check.

### 5.3 Mobile vs. Desktop Asymmetry
**Confidence: 0.98**

The `task_mobile_pack_photo_button()` and `task_mobile_photo_preview()` functions only run when `window.innerWidth <= 768`. Desktop users see only the raw Frappe Attach fields with no gallery, no fullscreen viewer, and no custom upload button. Mobile users get the full photo UX.

Exception: `fetch_pack_prepare_photo()` (Returns Inspection gallery) runs on all screen sizes.

---

## 6. Findings Summary Table

| # | Finding | Type | Severity | Confidence | Affected Task Kinds |
|---|---|---|---|---|---|
| 1 | `custom_account_photos` depends_on wrong task_kind | Bug | HIGH | 0.98 | Account Details: Entry, Processing |
| 2 | ~~Gallery showing all attached images~~ | ~~Not a bug~~ (retracted) | N/A | 1.00 | Pack, Pickup Returns |
| 3 | ~~Auto-set photo field~~ | ~~Not a bug~~ (retracted, correct convenience) | N/A | 1.00 | Pack, Pickup Returns |
| 4 | Delivery tasks incorrectly have photo functionality (3 locations) | Bug | HIGH | 1.00 | Delivery |
| 5 | ~~Returns Inspection shows Pack photos~~ | ~~Not a bug~~ (retracted, correct by design) | N/A | 1.00 | Returns Processing |
| 6 | ~~No photo deletion UI~~ | ~~FIXED~~ (2026-08-27) | N/A | 1.00 | Pack, Pickup Returns, Account Details, Other |
| 7 | Account Details UI Cleanup condition never matches | Bug | HIGH | 0.97 | Account Details: Entry, Processing |
| 8 | Account Details preview shows all task attachments | Bug | MEDIUM | 0.97 | Account Details |
| 9 | Double photo copying (child table + File records) | Bug | LOW-MEDIUM | 0.85 | Account Details |
| 10 | Processing tasks get NO photo UI | Bug | HIGH | 0.95 | Account Details: Processing |
| 11 | ~~5-file limit counts all files~~ | ~~Not a bug~~ (retracted, expected) | N/A | 1.00 | Pack, Pickup Returns |
| 12 | `task_photo_fullscreen_preview` defined 3 times | Code Smell | LOW | 0.99 | All |
| 13 | ~~Photo upload/delete not gated by acceptance~~ | ~~FIXED~~ (2026-08-27) | N/A | 1.00 | Pack, Pickup Returns, Account Details, Other |
| 23 | Ghost field references (`custom_*` variants) | Code Smell | LOW | 0.95 | Account Details: Entry |
| 14 | No centralized photo component | Architecture | MEDIUM | 0.99 | All |
| 15 | Mobile-only photo galleries (desktop gets raw fields) | Bug | HIGH | 0.98 | Pack, Pickup Returns |
| 16 | Server gates correctly use dual-check pattern | Correct | N/A | 0.98 | Pack, Pickup Returns, Delivery, Return drop-off |
| 17 | Photo copy from Pack→Returns and Pickup Returns→Dispatch Case | Correct | N/A | 0.95-0.98 | Returns, Pickup Returns |
| 18 | Fullscreen viewer is well-implemented | Correct | N/A | 0.97 | All |
| 19 | Private file URL normalization works correctly | Correct | N/A | 0.95 | All |
| 20 | Other task photo flow is most robust | Correct | N/A | 0.93 | Other: Entry, Other: Processing |
| 21 | Disabled legacy return-dropoff gate correctly superseded | Correct | N/A | 0.98 | Return drop-off |
| 22 | Order Entry correctly has NO photo functionality | Correct (fixed 2026-08-27) | N/A | 1.00 | Order Entry |

---

## Appendix: File-to-Findings Mapping

| File | Findings Referenced |
|---|---|
| Task-Accept Start.js (lines 7-59) | #1, #7, #13 (Order Entry photo code removed 2026-08-27) |
| Task-Account Details UI Cleanup.js (lines 25-284) | #1, #7, #8, #10 |
| Task-Other UI Cleanup.js (lines 32-176) | #2, #11, #12, #20 |
| Task-Mobile Form Layout Fix.js (lines 289-555) | #2, #3, #11, #12, #15 |
| Order entry - barcode scanning section - hide.js (lines 63-340) | #4 (Delivery photo visibility bug), #5, #6 |
| Task-Lock Unaccepted.js (lines 34-62) | #6 |
| Task-before-save-dispatch-gates.py (lines 67-97) | #16 |
| Task-before-save-policy.py (lines 60-69) | #4 (old-flow Delivery gate should be removed), #16 |
| Task-after-save-dispatch-flow.py (lines 182-215) | #4 (Delivery→DC copy is dead code), #5, #17 |
| Task-after-save-account-details-processing.py (lines 42-80) | #9 |
| Task-after-save-other-processing.py (lines 30-45) | #20 |
| Task-before-save-return-dropoff-photo.py (DISABLED) | #21 |
| Schema: custom-fields.json (warehouse_pickup_photo, custom_delivery_photo, warehouse_dropoff_photo, custom_account_photos) | #1, #4 |
| Schema: custom-doctypes.json (Account Detail Attachment) | #9 |
| Dispatch Case-Simplify for Order Creation.js (lines 53-65) | Correct behavior noted |
