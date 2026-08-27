# Group 9: UI/UX and Mobile — Audit Findings

> **Audited**: 2026-08-27
> **Scripts analyzed**: 5 client, 1 server (897 lines total)
> **Scope**: All deployed scripts whose primary purpose is mobile layout, navigation, responsive behavior, task list filtering, or visual presentation fixes — as opposed to business logic.

---

## Summary

| Metric | Value |
|---|---|
| Scripts analyzed | 6 (5 client + 1 server API) |
| Total lines of code | 897 (798 JS + 99 Python) |
| Currently enabled | All 6 |
| Documentation coverage | **0%** — none of these scripts are described in any numbered doc, implementation doc, or manual |
| Findings | 14 |
| Critical | 2 |
| High | 3 |
| Medium | 5 |
| Low | 4 |

---

## Script-by-Script Analysis

### Script 1: `Global-Mobile Back Button.js`

- **File**: `deploy/test/work/client/Global-Mobile Back Button.js`
- **Schema record**: Client Script, DocType = Task, View = Form, Enabled = 1
- **Created**: 2026-07-10, **Modified**: 2026-07-31
- **Lines**: 55 (excluding header comments)

#### What it does

Adds a floating circular back button (blue, 56×56px, fixed bottom-left) on mobile devices (screen width ≤ 768px) when the user is on a Task Form view. The button calls `history.back()` if browser history exists, otherwise navigates to the Task list. It is hidden on "home" routes (`/app`, `/app/home`, `/app/desk`, etc.).

The script attaches global event listeners (`popstate`, `hashchange`, `resize`, `click`, `frappe.router.on('change')`) to re-evaluate visibility on navigation changes. A guard flag (`window._backBtnWired`) prevents duplicate listener attachment.

#### Technical details

- **Trigger**: `frappe.ui.form.on('Task', { refresh })` — only fires when a Task form loads. The back button is therefore **not created until the first Task form visit** in a session.
- **Element ID**: `mobile-back-btn` — shared with the List view script (Script 2). Both scripts create/manage the same DOM element.
- **Guard mechanism**: `window._mobileBackInterval` — set to a string sentinel `'global-mobile-back-button-stable'` after first run. This interacts with the List script's use of the same variable (see Script 2).
- **Mobile detection**: `window.innerWidth <= 768` — checked once at build time and on each event. No CSS media query; pure JS.

#### Concerns

1. The `click` event listener on `document` fires `buildMobileBackButton` twice (200ms and 600ms delay) on **every click anywhere on the page**. This is a performance concern — every tap on a mobile device triggers two additional DOM-check cycles.
2. The `history.back()` fallback when `window.history.length > 1` can navigate to external sites if the user entered ERPNext directly from a link. The `frappe.set_route('List', 'Task')` fallback only triggers when `history.length <= 1`, which is rare in practice.
3. Touch feedback (`scale(0.9)` / `scale(1)`) uses inline style setting without cleanup — if the user drags away from the button, the `touchend` may not fire on the element, leaving it visually stuck at 0.9 scale until next render.

---

### Script 2: `Global-Mobile Back Button List.js`

- **File**: `deploy/test/work/client/Global-Mobile Back Button List.js`
- **Schema record**: Client Script, DocType = Task, View = List, Enabled = 1
- **Created**: 2026-07-08, **Modified**: 2026-07-21
- **Lines**: 137

#### What it does

This script performs **three distinct functions** bundled into one file:

**Function A — Global mobile CSS (lines 7–23):**
Injects a `<style>` tag (`#mobile-global-css`) on mobile (≤ 768px) that:
- Compacts `.page-actions` buttons (smaller padding, font-size 11px, no wrapping).
- Forces `image-orientation: from-image` on all `<img>` elements (fixes EXIF rotation on mobile browsers).
- Removes the "Menu" tooltip from the `...` button by stripping `title`, `data-original-title`, and `data-bs-original-title` attributes. Re-runs on every route change.

**Function B — Mobile back button (lines 26–48):**
A second implementation of the same back button as Script 1, using `setInterval(ensureBackBtn, 300)` instead of event listeners. Creates the same `#mobile-back-btn` element with identical styling. Unlike Script 1, this one:
- Uses `setInterval` at 300ms (perpetual polling).
- Does NOT have the `frappe.set_route('List', 'Task')` fallback — just calls `history.back()`.
- Runs as an IIFE outside any Frappe event handler, so it activates on **any page load** where the Task List script is loaded.

**Function C — Task List toggle filters + server API (lines 50–141):**
Overrides `frappe.listview_settings['Task'].onload` to:
- Add a mobile Refresh button (↻) to the list top bar.
- Render a toggle bar with three checkboxes: "My Tasks" (default on), "Open Tasks" (default on), "Completed" (default off).
- On toggle change, calls the `task_list_filtered` server API with the toggle state.
- Receives back an array of Task names, clears all filters, and sets `name IN [returned names]` as the filter.
- On load, clears any stale filters and applies the default toggle state after 500ms.

#### Technical details

- **Back button duplication**: Both Script 1 (Form) and Script 2 (List) create `#mobile-back-btn`. They share the same `window._mobileBackInterval` variable but use it differently — Script 1 sets it to a string, Script 2 sets it to a `setInterval` handle. If Script 2 loads first (typical — list before form), `_mobileBackInterval` becomes an interval ID (number). When Script 1 loads later, it calls `clearInterval(window._mobileBackInterval)` which cancels Script 2's polling, then sets it to the string sentinel. This means **whichever script loads second wins** control of the back button.
- **Toggle filter state**: `TOGGLE_STATE` is a local variable, not persisted. Navigating away and back resets toggles to defaults (My Tasks on, Open on, Completed off).
- **API call architecture**: The client calls `task_list_filtered`, receives up to 500 task names, then sets them as a `name IN [...]` filter. This means the URL bar / standard Frappe filters are **replaced** — the user cannot combine toggle filters with standard ERPNext filters.
- **`_origOnload` chaining**: The script saves and chains any existing `frappe.listview_settings['Task'].onload`. This is correct for avoiding conflicts with other scripts that set list view behavior.

#### Concerns

1. The `setInterval(ensureBackBtn, 300)` runs **forever** — 3.3 times per second, every second, for the entire browser session. This is a continuous performance cost.
2. The toggle filter system bypasses ERPNext's native list filtering entirely. Users cannot save filter presets or combine with standard URL-based filters.
3. `console.log("[TaskToggle] ...")` statements are left in production code (lines 102, 112).

---

### Script 3: `Task-Mobile Form Layout Fix.js`

- **File**: `deploy/test/work/client/Task-Mobile Form Layout Fix.js`
- **Schema record**: Client Script, DocType = Task, View = Form, Enabled = 1
- **Created**: 2026-08-24, **Modified**: 2026-08-25
- **Lines**: 534

#### What it does

The largest client script in the entire deployment. It performs extensive mobile-specific modifications to the Task form, with special treatment for "Pack / prepare items" tasks. The script has 8 named functions:

**`task_mobile_scroll_to_top` (lines 24–32):**
Scrolls to top of page when navigating to a new Task on mobile. Uses a guard (`_task_mobile_last_scroll_doc`) to avoid re-scrolling on refresh of the same task.

**`task_mobile_form_layout_fix` (lines 34–212):**
The main function. Injects a large `<style>` block (`#task-mobile-form-layout-fix-style`, ~190 lines of CSS) that:
- Makes tab lists horizontally scrollable instead of wrapping.
- Forces the `subject` field to be visible.
- Adds 92px bottom padding to the form page (space for the back button).
- For "Pack" tasks specifically (`body.task-mobile-pack-clean`): hides the title area, compacts action buttons to 38×38px icon-only, hides the back button, reduces grid/table font sizes, enlarges checkboxes to 22×22px for touch targets, and adds touch-friendly scrolling.

Also performs JS-level changes:
- Forces `subject` field visible and not required.
- Adds a `title` attribute to the page head title text.
- For Pack tasks: calls `task_mobile_pack_cleanup` and `task_mobile_pack_photo_button`.

**`task_mobile_pack_cleanup` (lines 214–287):**
For Pack tasks on mobile:
- Hides the physical back button DOM element.
- Removes stale style tags from other scripts.
- Builds a compact summary banner showing subject, dispatch case, status, and customer.
- Hides metadata fields: `completed_at`, `task_kind`, `custom_assigned_to`, `custom_accepted_at`, `accepted_at`.
- Conditionally hides `customer` (if empty) and `subject` (always, replaced by summary banner).
- Ensures `dispatch_case` and product line fields remain visible.

**`task_mobile_pack_photo_button` (lines 289–341):**
Adds a "+ Add Pickup Photos" or "+ Add Drop-off Photos" button based on task_kind:
- "Pack / prepare items" → `warehouse_pickup_photo` field, "+ Add Pickup Photos" button.
- "Pickup Returns" → `warehouse_dropoff_photo` field, "+ Add Drop-off Photos" button.

The button opens `frappe.ui.FileUploader` with:
- Image-only restriction (`allowed_file_types: ['image/*']`).
- Max 5 attachments per task (checks existing count first via API).
- On success, sets the first uploaded photo URL into the relevant field and triggers a save.

**`task_mobile_cleanup_other_photo_buttons` (lines 343–352):**
Ensures only the correct photo button is shown (Pack vs Pickup Returns), removing the other.

**`task_mobile_photo_config` (lines 354–363):**
Returns configuration object based on task_kind, mapping to the correct field and button IDs.

**`task_mobile_photo_preview` (lines 365–441):**
Fetches all File attachments for the current Task, filters to images only, and renders a thumbnail grid (76×76px thumbnails with cover fit). Each thumbnail is clickable to open fullscreen preview.

**`task_photo_fullscreen_preview` (lines 443–528):**
A complete fullscreen photo viewer with:
- Pinch-to-zoom (multi-touch pointer events).
- Drag-to-pan.
- Mouse wheel zoom.
- Zoom in/out/reset/close buttons.
- Scale range: 0.5× to 6×.
- Pan clamping to keep the image visible.
This is a ~85-line standalone photo viewer component embedded in a client script.

**`task_mobile_set_photo_field` (lines 530–555):**
Sets the photo URL into the appropriate Task field (`warehouse_pickup_photo` or `warehouse_dropoff_photo`). If the field control exists in the form, uses `frm.set_value` + save. If not (field not rendered), falls back to `frappe.client.set_value` direct API call.

#### Execution pattern

The `refresh` handler calls `task_mobile_form_layout_fix` **7 times** at staggered intervals: immediately, 250ms, 900ms, 1800ms, 2800ms, 4500ms, and 7000ms. This brute-force approach compensates for Frappe's asynchronous rendering — the CSS and DOM manipulations may be undone by Frappe's own rendering pipeline, so the script re-applies them repeatedly.

The `after_save` handler also re-applies at 500ms and 800ms.

#### Concerns

1. **7 repeated calls on every refresh** is a brute-force workaround for framework timing issues. The 7-second total window means the form may "flash" between styled and unstyled states.
2. The fullscreen photo viewer (85 lines) is a substantial UI component with no tests and no documentation. It handles complex multi-touch pointer events that could behave differently across browser versions.
3. The 5-photo limit is hardcoded with no configuration — not documented as a business rule anywhere.
4. `task_mobile_set_photo_field` has a fallback path using `frappe.client.set_value` that bypasses all server-side validation (before_save hooks). This could set a photo field without triggering the normal save pipeline.
5. The summary banner in `task_mobile_pack_cleanup` reads `dispatch_case_status` OR `custom_dispatch_case_status` (line 232) — a defensive check suggesting the field name was changed at some point, but both variants are still checked.

---

### Script 4: `Task-Header Long Subject Fix.js`

- **File**: `deploy/test/work/client/Task-Header Long Subject Fix.js`
- **Schema record**: Client Script, DocType = Task, View = Form, Enabled = 1
- **Created**: 2026-07-17, **Modified**: 2026-08-24
- **Lines**: 45

#### What it does

Forces the Task `subject` field to always be visible on the form, counteracting ERPNext's default behavior of hiding the subject field and showing it only in the page header title.

Injects CSS (`#task-subject-field-visibility-fix`) that:
- Forces `[data-fieldname="subject"]` and its wrappers to `display: block; visibility: visible`.
- Hides any `.task-visible-subject-banner` element (a now-removed earlier approach).

Also uses Frappe API calls to:
- `frm.toggle_display('subject', true)` — Frappe's standard show/hide.
- `frm.set_df_property('subject', 'hidden', 0)` — overrides any property setter.
- jQuery: removes `.task-visible-subject-banner` and force-shows the subject control.

Runs on `refresh` (3 times: immediate, 250ms, 900ms) and on `subject` field change.

#### Why it exists

ERPNext v16 moves the `subject` field content into the page header bar. For Tasks with long subjects (e.g., "Pack: DC-00045 — Hospital XYZ — Dr. Smith"), this truncates the subject. The field itself becomes hidden, making it impossible to read or edit the full subject. This script reverses that behavior.

Also removes a style tag `#task-header-long-subject-fix` (line 19) — cleaning up a predecessor version of itself.

#### Concerns

1. **Overlaps with Script 3** (`Task-Mobile Form Layout Fix.js`) which also forces subject visibility (lines 51–61, 195–200). Both scripts inject CSS targeting `[data-fieldname="subject"]` with `display: block; visibility: visible`. The duplication is harmless but indicates the two scripts evolved independently.
2. The `try/catch` on line 18/48 silently swallows all errors — any failure is invisible.

---

### Script 5: `Task-Delivery UI Fix.js`

- **File**: `deploy/test/work/client/Task-Delivery UI Fix.js`
- **Schema record**: Client Script, DocType = Task, View = Form, Enabled = 1
- **Created**: 2026-08-27 (today), **Modified**: 2026-08-27 (today)
- **Lines**: 34

#### What it does

The newest script in the deployment (created today). Applies CSS fixes specifically for the Delivery task kind on mobile.

When `task_kind === "Delivery"`:
- Adds `task-delivery-ui-active` class to `<body>`.
- Forces `custom_next_task_assign_to` field to be visible (unhides it).
- Injects CSS (`#task-delivery-ui-fix-css`) that within `@media(max-width:768px)`:
  - Allows `.page-actions` to wrap with visible overflow.
  - Limits button width to 46vw with normal white-space wrapping.
  - Allows `.page-head-content` to wrap.
  - Constrains `.title-area` to available width.

#### Why it exists

Delivery tasks have multiple action buttons (Accept, Picked Up, Delivered) plus standard ERPNext buttons (Save, Menu). On mobile, these overflow the header bar and become invisible or inaccessible. This script forces them to wrap onto multiple lines.

It also unhides `custom_next_task_assign_to` — a field where the delivery driver can see/set who should handle the next task in the chain (e.g., Return Pickup).

#### Concerns

1. The `custom_next_task_assign_to` field visibility is managed by both this script AND the property setters in the schema. The property setter does NOT have a `depends_on` for `custom_next_task_assign_to`, meaning it should be visible by default. However, other scripts may hide it — this script counteracts that.
2. This script was created **today** — it has had zero production burn-in time. It may need further refinement.

---

### Script 6: `task_list_filtered.py` (Server)

- **File**: `deploy/test/work/server/task_list_filtered.py`
- **Schema record**: Server Script, Type = API, Disabled = 0
- **Created**: 2026-07-14, **Modified**: 2026-07-22
- **Lines**: 99

#### What it does

A server-side API endpoint called by the client-side toggle filters (Script 2). Returns up to 500 Task names matching the filter criteria.

**Inputs** (from `frappe.form_dict`):
- `my_tasks` (0/1) — tasks assigned to the current user.
- `open_tasks` (0/1) — tasks with status not in Completed/Cancelled.
- `completed` (0/1) — tasks with status = Completed.

**Logic**:

1. **Role resolution**: Queries `Has Role` table for the current user's roles.
2. **Task kind filtering**: Uses `TASK_KIND_ALLOWED_ROLES` dictionary to determine which task kinds the user is allowed to see. Only task kinds where the user holds at least one matching role are included.
3. **Toggle logic**:
   - If no toggles are selected: shows all tasks matching the user's allowed kinds (or all tasks for admins).
   - If toggles are selected: builds SQL with OR clauses combining:
     - `my_tasks`: tasks where `_assign LIKE '%user_email%'`. **Special case**: users in `ACCOUNT_DETAILS_MY_TASK_USERS` also see all "Account details" tasks.
     - `open_tasks` / `completed`: status filter (open excludes Completed+Cancelled; completed shows only Completed; both together shows everything except Cancelled).
     - Team availability: includes tasks assigned to no one, to the current user, or to any team placeholder email.
4. **SQL construction**: Builds raw SQL directly (not using Frappe ORM). Returns `SELECT name FROM tabTask WHERE ... ORDER BY modified DESC LIMIT 500`.

#### `TASK_KIND_ALLOWED_ROLES` — Comparison with Documentation

| Task Kind | Doc 10a (documented) | `task_list_filtered.py` (deployed) | Delta |
|---|---|---|---|
| Order entry | `Ops - Order Accepting` | `Ops - Order Accepting`, **`Ops - Order Creating`** | **ADDED: `Ops - Order Creating`** |
| Pack / prepare items | `Ops - Inventory` | `Ops - Inventory` | Match |
| Dispatch picking / hand-off | `Ops - Delivery` | `Ops - Delivery` | Match |
| Delivery | `Delivery Driver`, `Ops - Delivery` | `Delivery Driver`, `Ops - Delivery` | Match |
| Return to warehouse... | `Delivery Driver`, `Ops - Delivery` | `Delivery Driver`, `Ops - Delivery` | Match |
| Pickup Returns | `Delivery Driver`, `Ops - Delivery` | `Delivery Driver`, `Ops - Delivery`, **`Ops - Returns`** | **ADDED: `Ops - Returns`** |
| Return drop-off at warehouse | `Delivery Driver`, `Ops - Delivery` | `Delivery Driver`, `Ops - Delivery` | Match |
| Returns processing / verification | `Ops - Returns`, `Ops - Inventory` | `Ops - Returns`, `Ops - Inventory` | Match |
| Returns restocking | *(not in Doc 10a)* | **`Ops - Returns`** | **ADDED: entire kind** |
| Invoice preparation / create invoice | `Ops - Accounting` | `Ops - Accounting` | Match |
| Debt Collection | `Ops - Directors` | **`Ops - Finance`**, `Ops - Directors` | **ADDED: `Ops - Finance`** |
| Distribute Payment | `Ops - Directors` | **`Ops - Finance`**, `Ops - Directors` | **ADDED: `Ops - Finance`** |
| Payment Received | *(not in Doc 10a)* | **`Ops - Finance`**, **`Ops - Directors`** | **ADDED: entire kind** |
| Discount Approval | `Ops - Directors` | `Ops - Directors` | Match |
| Purchase Approval | `Ops - Directors` | `Ops - Directors` | Match |
| Write-off Approval | `Ops - Directors` | `Ops - Directors` | Match |
| Account details | *(not in Doc 10a)* | **`Ops - Accounting`**, **`Ops - Finance`**, **`Ops - Directors`** | **ADDED: entire kind** |
| Other | *(not in Doc 10a)* | **ALL operational roles** | **ADDED: entire kind** |
| Return Call | *(not in Doc 10a)* | **`Ops - Returns`**, **`Ops - Delivery`** | **ADDED: entire kind** |

**Summary of role mapping drift**: 5 new task kinds added (Returns restocking, Payment Received, Account details, Other, Return Call), and 4 existing kinds have expanded role lists. None of these changes are reflected in Doc 10a.

#### `TEAM_PLACEHOLDERS` list

The script hardcodes 8 team placeholder emails:
```
inventory.team@example.com
delivery.team@example.com
returns.team@example.com
accounting.team@example.com
finance.team@example.com
order.creation.team@example.com
order.team@example.com
directors.team@example.com
```

This matches the documented list in `manual/erpnext-manual-setup-checklist.md` (lines 32–41), **except**:
- `purchasing.team@example.com` is documented but **NOT** in the placeholder list. Tasks assigned to the purchasing team would NOT appear in the "Open Tasks" toggle.
- `driver.01@example.com` is documented as a real user, not a team placeholder — correctly excluded.

#### `ACCOUNT_DETAILS_MY_TASK_USERS` list

Five hardcoded personal email addresses:
```
sahakyan.oli1998@gmail.com
ly.aghayan@gmail.com
levonaghinyan77@gmail.com
ghahramanyann@gmail.com
karapetyansev@gmail.com
```

This list causes these users to see ALL "Account details" tasks in their "My Tasks" filter, regardless of assignment. **This is completely undocumented**. There is no numbered doc, implementation doc, or manual that describes this behavior or lists these users.

#### Concerns

1. **SQL injection risk**: The `safe_user` variable uses `user.replace("'", "''")` for escaping, and `kind_list` uses the same pattern. While this escapes single quotes, it does NOT use parameterized queries. The `TASK_KIND_ALLOWED_ROLES` keys are hardcoded strings (safe), and `user` comes from `frappe.session.user` (server-validated). The `TEAM_PLACEHOLDERS` are hardcoded. So the actual injection surface is minimal, but the pattern is fragile — any future change adding user-supplied input to the SQL would be vulnerable.
2. **500-row limit**: The query returns at most 500 task names. If a user has access to more than 500 tasks, older ones are silently excluded. There is no pagination or "more results" indicator.
3. **Performance**: The `_assign LIKE '%email%'` pattern cannot use an index. On a large Task table, this results in a full table scan for each query.
4. **`ACCOUNT_DETAILS_MY_TASK_USERS`**: Hardcoded user list. When staff changes occur, this script must be manually updated. No admin UI, no configuration DocType, no documentation.
5. **`TEAM_PLACEHOLDERS`**: Also hardcoded. Adding a new team requires script modification.
6. **`allow_guest: 0`**: Correctly requires authentication. Good.

---

## Findings Table

| ID | Type | Severity | Script/Feature | Finding | Evidence | Confidence | Recommendation |
|---|---|---|---|---|---|---|---|
| F9-001 | DOC-MISSING | CRITICAL | All Group 9 scripts | **Zero documentation exists** for any mobile UI, back button, form layout fix, toggle filters, task_list_filtered API, or photo preview features. All 6 scripts (897 lines) are completely undocumented. | Searched all docs/ files for: mobile back button, mobile layout, task_list_filtered, toggle filters, subject field visibility, fullscreen photo, 768px. Zero matches for any of these features. | 100% | Create a new numbered doc (e.g., Doc 18: Mobile UI and Task List Customizations) covering all deployed mobile/UI behavior. |
| F9-002 | DOC-STALE | CRITICAL | `task_list_filtered.py` | **TASK_KIND_ALLOWED_ROLES has drifted** from documentation. 5 new task kinds added (`Returns restocking`, `Payment Received`, `Account details`, `Other`, `Return Call`), and 4 existing kinds have expanded role lists (`Ops - Order Creating` added to Order entry, `Ops - Returns` added to Pickup Returns, `Ops - Finance` added to Debt Collection and Distribute Payment). Doc 10a still shows the original 14-kind mapping. | Compared deployed `TASK_KIND_ALLOWED_ROLES` (lines 8–28 of `task_list_filtered.py`) with Doc 10a lines 262–277. See delta table above. | 100% | Update Doc 10a `TASK_KIND_ALLOWED_ROLES` to match deployed code. Also update `Task-before-save-policy.py` (Group 2) if its mapping also drifts. |
| F9-003 | RISK | HIGH | `task_list_filtered.py` | **Hardcoded user emails** in `ACCOUNT_DETAILS_MY_TASK_USERS` (5 personal Gmail addresses). These users see all "Account details" tasks in their "My Tasks" filter regardless of assignment. This behavior is undocumented and the user list requires manual script edits to maintain. | Lines 41–47 of `task_list_filtered.py`. No documentation found anywhere. | 100% | Either: (a) replace with a role-based check (e.g., users with `Ops - Accounting` role), or (b) move to a configuration DocType, or (c) at minimum document the list and the update procedure. |
| F9-004 | RISK | HIGH | `Global-Mobile Back Button.js` + `Global-Mobile Back Button List.js` | **Duplicate back button implementations**. Two scripts create the same `#mobile-back-btn` element using different strategies (event listeners vs setInterval). They share `window._mobileBackInterval` but assign it different value types (string vs interval ID). The second script to load cancels the first's mechanism. | Script 1 line 11: `window._mobileBackInterval = 'global-mobile-back-button-stable'`; Script 2 line 46: `window._mobileBackInterval = setInterval(ensureBackBtn, 300)`. Both create `#mobile-back-btn`. | 100% | Consolidate into a single back button implementation. The List script's IIFE approach is more reliable (runs on any page) but should use event-driven checks instead of `setInterval`. |
| F9-005 | RISK | HIGH | `Global-Mobile Back Button List.js` | **Perpetual `setInterval` at 300ms** runs for the entire browser session. The `ensureBackBtn` function runs 3.3 times per second, every second, until the tab is closed. Each iteration checks `window.innerWidth`, reads `window.location.href`, and potentially creates/manipulates DOM elements. | Line 46: `window._mobileBackInterval = setInterval(ensureBackBtn, 300)`. No `clearInterval` call exists in this script. | 100% | Replace with event-driven approach (popstate, hashchange, resize, frappe.router.on) like Script 1 uses, or at minimum increase the interval to 2–3 seconds. |
| F9-006 | RISK | MEDIUM | `task_list_filtered.py` | **Missing team placeholder**: `purchasing.team@example.com` is a documented team user (setup checklist line 32) but is NOT in the `TEAM_PLACEHOLDERS` list. Tasks assigned to the purchasing team will not appear in the "Open Tasks" toggle for purchasing team members. | `TEAM_PLACEHOLDERS` (lines 30–38) lists 8 emails. `purchasing.team@example.com` is absent. Setup checklist documents 10 team users including purchasing. | 100% | Add `purchasing.team@example.com` to the `TEAM_PLACEHOLDERS` list. |
| F9-007 | RISK | MEDIUM | `Task-Mobile Form Layout Fix.js` | **`frappe.client.set_value` bypass**: The `task_mobile_set_photo_field` function (lines 540–554) has a fallback path that uses `frappe.client.set_value` to directly write to the Task record, bypassing all `before_save` server scripts. This could set `warehouse_pickup_photo` or `warehouse_dropoff_photo` without triggering validation gates. | Lines 540–554: `frappe.call({ method: 'frappe.client.set_value', args: { doctype: 'Task', name: frm.doc.name, fieldname: config.fieldname, value: url } })`. | 95% | Verify whether this fallback path is reachable in practice (it fires only when `frm.fields_dict[config.fieldname]` is falsy). If reachable, replace with `frm.set_value` + `frm.save()` to ensure server-side validation runs. |
| F9-008 | RISK | MEDIUM | `Task-Mobile Form Layout Fix.js` | **Brute-force re-application pattern**: `task_mobile_form_layout_fix` is called 7 times per refresh at staggered intervals (0, 250, 900, 1800, 2800, 4500, 7000ms). This compensates for Frappe's async rendering but causes visible UI flickering and wastes CPU cycles. | Lines 8–16: seven `setTimeout` calls with increasing delays up to 7 seconds. | 100% | Consider using a MutationObserver to detect when Frappe finishes rendering, then apply fixes once. Alternatively, use fewer retries with a check for whether fixes are already applied. |
| F9-009 | DOC-MISSING | MEDIUM | `Task-Mobile Form Layout Fix.js` | **5-photo attachment limit** is hardcoded as a business rule (line 305: `if (existing >= 5)`) but is not documented anywhere. Photo upload limits are mentioned as an open question in `implementation-questions.md` (line 1452) but never resolved in any doc. | Line 305: `if (existing >= 5) { frappe.msgprint(__('Maximum 5 photos/files can be attached.')); return; }`. | 100% | Document this as a decided business rule, or make it configurable. |
| F9-010 | DOC-MISSING | MEDIUM | `Task-Mobile Form Layout Fix.js` | **Fullscreen photo viewer** (85 lines, pinch-zoom, drag-pan, multi-touch) is a significant UI component with no documentation, no tests, and no design spec. | Lines 443–528: complete standalone viewer with pointer event handling, scale 0.5–6×, pan clamping. | 100% | Document as a deployed feature. Note fragility risk — pointer event handling varies across mobile browsers and OS versions. |
| F9-011 | BUG | LOW | `Task-Header Long Subject Fix.js` + `Task-Mobile Form Layout Fix.js` | **Overlapping subject visibility fixes**. Both scripts inject CSS and JS to force the `subject` field visible. Script 4 also removes a legacy `#task-header-long-subject-fix` style tag. The duplication is functionally harmless but indicates the two scripts were written independently without awareness of each other. | Script 3 lines 51–61 and 195–200 vs Script 4 lines 25–36 — both target `[data-fieldname="subject"]` with `display:block!important; visibility:visible!important`. | 100% | Consolidate subject visibility logic into one script. |
| F9-012 | BUG | LOW | `Global-Mobile Back Button List.js` | **Console.log in production**: Two debug log statements are left in the deployed code. | Line 102: `console.log("[TaskToggle] applyToggleFilter called", TOGGLE_STATE)`. Line 112: `console.log("[TaskToggle] API returned " + names.length + " tasks")`. | 100% | Remove or gate behind a debug flag. |
| F9-013 | BUG | LOW | `task_list_filtered.py` | **500-row silent truncation**: The API returns at most 500 tasks with no indication to the client that results were truncated. Users with access to many task kinds may silently miss older tasks. | Line 113: `LIMIT 500`. No count or "has_more" flag in the response. | 100% | Add a count query or `has_more` flag so the client can inform the user. Or increase the limit, or add pagination. |
| F9-014 | RISK | LOW | `Task-Delivery UI Fix.js` | **Brand-new script** (created 2026-08-27) with zero production burn-in. May need refinement after real-world mobile testing with delivery drivers. | Schema shows creation = modification = 2026-08-27 18:22:12. | 100% | Monitor for issues. No action needed now, but flag for review after 1–2 weeks of production use. |

---

## Cross-Group Dependencies

| Item | This Group | Relevant to Group | Notes |
|---|---|---|---|
| `TASK_KIND_ALLOWED_ROLES` drift | Group 9 (`task_list_filtered.py`) | Group 2 (`Task-before-save-policy.py`) | The policy script in Group 2 has its own copy of this mapping. Compare to determine if they are also out of sync. |
| `TEAM_PLACEHOLDERS` list | Group 9 (`task_list_filtered.py`) | Group 2 (`dispatch_task_accept.py`) | The accept API in Group 2 also has a team placeholder list. Compare to determine if they match. |
| Photo upload + `warehouse_pickup_photo` field | Group 9 (photo button) | Group 1 (dispatch gates require this field) | The photo button sets the field; the dispatch gates in Group 1 enforce its presence. The `set_value` bypass (F9-007) could interact with gate enforcement. |
| Subject visibility fix | Group 9 (Scripts 3, 4) | Group 2 (`Task-before-save-auto-subject.py`) | Auto-subject generation in Group 2 creates 5-digit numeric subjects. The visibility fix ensures users can see and edit these. No conflict, but functionally linked. |
| "Account details" task kind | Group 9 (hardcoded user list) | Group 2 (Task-after-save-account-details-processing.py) | The task processing chain in Group 2 creates and chains Account Details tasks. The visibility of these tasks depends on the hardcoded list in Group 9. |

---

## What Production Has vs What Documentation Says

### Production has, documentation does NOT describe:

1. **Floating mobile back button** — fixed-position blue circle (bottom-left) on all mobile pages. No doc.
2. **Task list toggle filters** ("My Tasks" / "Open Tasks" / "Completed") — custom filter bar replacing ERPNext's native list filters. No doc.
3. **`task_list_filtered` server API** — custom SQL-based task filtering with role-based access, team placeholder handling, and hardcoded user exceptions. No doc.
4. **Mobile-specific CSS overhaul** for Task forms — 534 lines of layout fixes including compact headers, touch-friendly checkboxes, scrollable grids, hidden metadata fields. No doc.
5. **Fullscreen photo viewer** with pinch-zoom and drag-pan for attached photos. No doc.
6. **Mobile photo upload button** ("+ Add Pickup Photos" / "+ Add Drop-off Photos") with 5-file limit. No doc.
7. **Pack task summary banner** — compact mobile view showing subject, dispatch case, status, customer when native header is hidden. No doc.
8. **"Account details" task kind special visibility** — hardcoded 5-user list bypassing normal assignment-based filtering. No doc.
9. **"Returns restocking", "Payment Received", "Account details", "Other", "Return Call" task kinds** in the role mapping — 5 kinds that exist in production but not in Doc 10a's TASK_KIND_ALLOWED_ROLES. No doc update.
10. **Expanded role permissions** — `Ops - Order Creating` on Order entry, `Ops - Returns` on Pickup Returns, `Ops - Finance` on Debt Collection/Distribute Payment. No doc update.

### Documentation describes, production does NOT match:

1. **Doc 16a Workspace shortcuts** (lines 1345–1364) describe 12 specific filtered list views (e.g., "VIEW: Pack Tasks", "VIEW: Delivery Tasks"). Production instead uses a single toggle-filter system that combines all task kinds into one view. The documented per-kind workspace shortcuts may or may not exist alongside the toggle system — this needs live verification. **Confidence: 85%** (workspace shortcuts may exist separately from the toggle system; cannot confirm without checking the live workspace configuration).

2. **Doc 10 §6.2 Task Access Policy visibility model** describes a fine-grained visibility system where users can only see tasks whose Task Access Policy they have access to. The `task_list_filtered` API implements a **different** visibility model based on `TASK_KIND_ALLOWED_ROLES` matching against the user's roles, plus `_assign LIKE` matching, plus the `ACCOUNT_DETAILS_MY_TASK_USERS` exception. These are two different access models. **Confidence: 90%** (the Task Access Policy may still be enforced at the DocType permission level by Frappe, with `task_list_filtered` providing an additional filter layer on top).

### Documentation and production agree:

1. **Photo field names** — `warehouse_pickup_photo` and `warehouse_dropoff_photo` match Doc 10a field definitions.
2. **Core task kind names** — the original 14 task kinds in Doc 10a all exist in the deployed role mapping (some with expanded roles).
3. **Team placeholder email naming pattern** — matches documented setup checklist (except the missing `purchasing.team`).
4. **Image-orientation fix** (`from-image`) — not documented but addresses a well-known mobile browser EXIF rotation issue. Standard practice.
