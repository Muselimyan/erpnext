# F9-001: Mobile UI and Task List Filtering — Deployed Behavior Documentation

> **Created**: 2026-08-29
> **Source**: Production audit, Group 9 (UI/UX and Mobile)
> **Based on**: Actual deployed source files as of 2026-08-29
> **Scripts covered**: 6 (5 client + 1 server API)
> **Total lines of code**: 676 (573 JavaScript + 103 Python)
> **All scripts enabled**: Yes

---

## Important: Audit Discrepancy Notice

The Group 9 audit (`deploy/test/work/group-9-ui-ux-mobile-audit.md`, dated 2026-08-27) reported 897 lines across these scripts. **The scripts were updated after the audit was written.** Schema metadata confirms modifications on 2026-08-28 and 2026-08-29. Specific changes since the audit:

| Script | Audit line count | Actual line count | Key changes |
|---|---|---|---|
| `task_list_filtered.py` | 99 | 103 | Hardcoded `TASK_KIND_ALLOWED_ROLES`, `TEAM_PLACEHOLDERS`, and `ACCOUNT_DETAILS_MY_TASK_USERS` **removed**. Now reads from `Task Access Policy` records at runtime. |
| `Task-Mobile Form Layout Fix.js` | 534 | 284 | Photo upload button, `set_photo_field`, and fullscreen photo viewer functions **removed**. These are now part of the Doc 18 photo system. |
| Other 4 scripts | 264 | 289 | Minor changes; line counts approximately match. |
| **Total** | **897** | **676** | **221 fewer lines** |

**This document is based on the actual deployed code, not the audit's descriptions.** Where the audit's findings have been resolved by code changes, this is noted explicitly.

---

## Table of Contents

1. [Script Inventory](#1-script-inventory)
2. [Script 1: Global-Mobile Back Button (Form)](#2-script-1-global-mobile-back-buttonjs)
3. [Script 2: Global-Mobile Back Button List](#3-script-2-global-mobile-back-button-listjs)
4. [Script 3: Task-Mobile Form Layout Fix](#4-script-3-task-mobile-form-layout-fixjs)
5. [Script 4: Task-Header Long Subject Fix](#5-script-4-task-header-long-subject-fixjs)
6. [Script 5: Task-Delivery UI Fix](#6-script-5-task-delivery-ui-fixjs)
7. [Script 6: task_list_filtered (Server API)](#7-script-6-task_list_filteredpy)
8. [Cross-Script Interactions](#8-cross-script-interactions)
9. [Documentation Coverage Assessment](#9-documentation-coverage-assessment)
10. [Known Limitations and Static Risks](#10-known-limitations-and-static-risks)
11. [Open Questions Requiring Business Confirmation](#11-open-questions-requiring-business-confirmation)
12. [Verification Scenarios](#12-verification-scenarios)
13. [Cross-Group Dependencies](#13-cross-group-dependencies)

---

## 1. Script Inventory

### Files and Locations

| # | File | Type | DocType | View | Lines | Schema Modified |
|---|---|---|---|---|---|---|
| 1 | `deploy/test/work/client/Global-Mobile Back Button.js` | Client Script | Task | Form | 62 | 2026-07-31 |
| 2 | `deploy/test/work/client/Global-Mobile Back Button List.js` | Client Script | Task | List | 142 | 2026-08-29 |
| 3 | `deploy/test/work/client/Task-Mobile Form Layout Fix.js` | Client Script | Task | Form | 284 | 2026-08-28 |
| 4 | `deploy/test/work/client/Task-Header Long Subject Fix.js` | Client Script | Task | Form | 49 | 2026-08-24 |
| 5 | `deploy/test/work/client/Task-Delivery UI Fix.js` | Client Script | Task | Form | 36 | 2026-08-27 |
| 6 | `deploy/test/work/server/task_list_filtered.py` | Server Script (API) | — | — | 103 | 2026-08-29 |

### Schema Creation Dates

| Script | Created | Modified |
|---|---|---|
| Global-Mobile Back Button List | 2026-07-08 14:29:41 | 2026-08-29 03:52:39 |
| Global-Mobile Back Button | 2026-07-10 12:37:58 | 2026-07-31 17:31:05 |
| Task-Header Long Subject Fix | 2026-07-17 02:34:25 | 2026-08-24 18:13:05 |
| task_list_filtered | 2026-07-14 12:27:58 | 2026-08-29 03:52:36 |
| Task-Mobile Form Layout Fix | 2026-08-24 12:12:51 | 2026-08-28 19:42:41 |
| Task-Delivery UI Fix | 2026-08-27 18:22:12 | 2026-08-27 18:22:12 |

**Source of schema dates**: `deploy/test/schema/client-scripts.json` and `deploy/test/schema/server-scripts.json`.

### Line Count Methodology

Line counts are total file lines including the 4-line metadata header (`// Name:`, `// DocType:`, `// Enabled:`, `// ---`) present in each client script, and the 6-line header (`# Name:`, `# Type:`, `# DocType:`, `# Event:`, `# Disabled:`, `# ---`) in the server script. These headers are stripped during deployment and do not execute.

---

## 2. Script 1: `Global-Mobile Back Button.js`

**File**: `deploy/test/work/client/Global-Mobile Back Button.js`
**Lines**: 62 (58 executable after header)
**Trigger**: `frappe.ui.form.on('Task', { refresh })`

### Purpose

Adds a floating circular back button on mobile devices when viewing a Task form. The button provides one-tap navigation back to the previous page.

### Behavior — Confirmed from Source Code

#### Back button creation (lines 13–44)

The `buildMobileBackButton()` function:

1. **Checks mobile**: `window.innerWidth <= 768` — JavaScript-only check, no CSS media query.
2. **Checks route**: Determines if the current URL is a "home" page (`/app`, `/app/desk`, `/app/home`, `/app/modules`, etc.). If on a home page or not on mobile, hides the button and returns.
3. **Creates element** (if not already present):
   - Element: `<div>` with `id="mobile-back-btn"`
   - Content: Unicode left arrow `←` (character code 8592)
   - Style: fixed position, bottom-left (20px from edges), 56×56px circle, `#1976d2` blue background, white text, 30px font, `z-index: 99999`, rounded shadow
   - Click handler: calls `history.back()` if `window.history.length > 1`, otherwise calls `frappe.set_route('List', 'Task')`
   - Touch handlers: `touchstart` scales to 0.9, `touchend` scales back to 1.0
4. **Shows element**: sets `display: flex` on the button.

#### Guard and event wiring (lines 8–11, 46–60)

- On each `refresh` event, checks `window._mobileBackInterval` — if it's a non-string truthy value (i.e., a `setInterval` handle from Script 2), calls `clearInterval()` on it. Then sets `window._mobileBackInterval = 'global-mobile-back-button-stable'` (a string sentinel).
- Calls `buildMobileBackButton()` immediately.
- If `window._backBtnWired` is not set, attaches global event listeners:
  - `window` → `popstate`, `hashchange`, `resize`: each calls `buildMobileBackButton()` after 200ms delay
  - `document` → `click`: calls `buildMobileBackButton()` at 200ms and again at 600ms
  - `frappe.router.on('change')`: calls `buildMobileBackButton()` after 200ms (only if `frappe.router.on` exists)
- Sets `window._backBtnWired = true` to prevent duplicate listener attachment.

### DOM Elements Created

| Element | Selector | Created by | Lifetime |
|---|---|---|---|
| Back button | `#mobile-back-btn` | `buildMobileBackButton()` | Persistent in DOM once created; visibility toggled |

### Global State Variables

| Variable | Type | Purpose |
|---|---|---|
| `window._mobileBackInterval` | Set to string `'global-mobile-back-button-stable'` | Sentinel to coordinate with Script 2 |
| `window._backBtnWired` | Boolean | Guard against duplicate event listener attachment |

### Activation Condition

This script only runs when a Task form loads (`frappe.ui.form.on('Task', { refresh })`). **The back button is not created until the first Task form visit in a browser session.** After creation, the global event listeners keep it active across other pages.

---

## 3. Script 2: `Global-Mobile Back Button List.js`

**File**: `deploy/test/work/client/Global-Mobile Back Button List.js`
**Lines**: 142 (138 executable after header)
**Trigger**: Mixed — top-level IIFE + `frappe.listview_settings['Task'].onload`

This script bundles three distinct functional areas into one file.

### Function A: Global Mobile CSS (lines 7–23)

**Activation**: Runs once on initial script load, only on mobile (`window.innerWidth <= 768`).

**What it does**:

1. **Injects `<style id="mobile-global-css">`** with:
   - `@media(max-width:768px)`: Compacts `.page-actions` buttons (gap 2px, padding 4px 6px, font-size 11px, no wrap)
   - `img { image-orientation: from-image !important }`: Fixes EXIF rotation on mobile browsers
2. **Removes "Menu" tooltip** from the `...` button:
   - Function `_removeMenuTooltip()` strips `title`, `data-original-title`, `data-bs-original-title` from `.menu-more-button` elements
   - Runs immediately, again after 500ms, and on every `frappe.router.on('change')` event

**Style element ID**: `mobile-global-css`

### Function B: Mobile Back Button — Polling Implementation (lines 26–48)

**Activation**: Runs once as an IIFE on script load. Not gated to mobile-only — the mobile check is inside the polling function.

**What it does**:

1. **Guard**: If `window._mobileBackInterval` is already set, exits immediately (does not start a second interval).
2. **Defines `ensureBackBtn()`**: Nearly identical to Script 1's `buildMobileBackButton()`, but:
   - Uses `window.location.href` instead of `pathname`/`hash` for route detection
   - Click handler calls `history.back()` only — **no** `frappe.set_route('List', 'Task')` fallback
   - Uses Unicode escape `\u2190` instead of `String.fromCharCode(8592)` (same character)
3. **Starts perpetual polling**: `window._mobileBackInterval = setInterval(ensureBackBtn, 300)` — runs `ensureBackBtn` every 300ms (3.3 times per second), indefinitely.
4. **Calls `ensureBackBtn()` once** immediately.

**DOM Element**: Creates `#mobile-back-btn` — same ID as Script 1.

### Function C: Task List Toggle Filters (lines 50–142)

**Activation**: `frappe.listview_settings['Task'].onload` — fires when the Task list view loads.

**What it does**:

1. **Chains existing onload** (line 51): Saves any existing `frappe.listview_settings['Task'].onload` handler and calls it first.

2. **Mobile Refresh Button** (lines 55–62): On mobile, prepends a small refresh button (`↻`, 28×28px) to `.page-actions`. ID: `mobile-list-refresh`.

3. **Toggle State** (line 65): Initializes `TOGGLE_STATE = { my_tasks: 1, open_tasks: 1, completed: 0 }`. Also stored on `window._taskToggleState`. This state is **not persisted** — navigating away and back resets to defaults.

4. **Toggle Bar Rendering** (lines 68–99, `renderToggleBar()`):
   - Creates a sticky div (`#task-toggle-bar`) with three checkbox toggles: "My Tasks", "Open Tasks", "Completed"
   - Inserts before `.frappe-list` or at top of `.page-body`
   - Each checkbox `change` event updates `TOGGLE_STATE` and calls `applyToggleFilter()`

5. **Filter Application** (lines 101–135, `applyToggleFilter()`):
   - Calls `frappe.call({ method: "task_list_filtered", args: { my_tasks, open_tasks, completed } })`
   - On success: receives array of Task names, clears all existing list filters, then sets `name IN [returned names]` as the filter, then refreshes
   - On error: clears all filters and refreshes
   - Contains two `console.log` statements (lines 102, 112) — debug output left in production

6. **Initial load** (lines 138–141): Clears stale filters, renders toggle bar, applies default toggle filter after 500ms delay.

### DOM Elements Created

| Element | Selector | Created by | Context |
|---|---|---|---|
| Back button | `#mobile-back-btn` | `ensureBackBtn()` (IIFE) | All pages, mobile only |
| Global CSS | `#mobile-global-css` | Top-level code | All pages, mobile only |
| Refresh button | `#mobile-list-refresh` | `onload` | Task list, mobile only |
| Toggle bar | `#task-toggle-bar` | `renderToggleBar()` | Task list, all screens |

### Global State Variables

| Variable | Type | Purpose |
|---|---|---|
| `window._mobileBackInterval` | Set to `setInterval` handle (number) | Polling interval ID |
| `window._taskToggleState` | Object | Reference to current toggle state |
| `window._taskToggleNames` | Array | Last set of task names returned by API |

### API Contract with `task_list_filtered`

**Request**: `frappe.call({ method: "task_list_filtered", args: { my_tasks: 0/1, open_tasks: 0/1, completed: 0/1 } })`

**Response**: `r.message` = Array of Task name strings (up to 500 items).

**Client behavior**: Clears all Frappe list filters → sets `name IN [names]` filter → refreshes list. This **replaces** the standard Frappe filter mechanism — users cannot combine toggle filters with native ERPNext URL-based filters or saved filter presets.

---

## 4. Script 3: `Task-Mobile Form Layout Fix.js`

**File**: `deploy/test/work/client/Task-Mobile Form Layout Fix.js`
**Lines**: 284 (280 executable after header)
**Trigger**: `frappe.ui.form.on('Task', { refresh, after_save })`

### Purpose

Comprehensive mobile-specific layout modifications for the Task form, with special treatment for "Pack / prepare items" tasks. This is the largest client script among the Group 9 scripts.

### Execution Pattern (lines 6–20)

On `refresh`: calls `task_mobile_form_layout_fix(frm)` and `task_mobile_scroll_to_top(frm)` at **seven staggered intervals**: immediately, 250ms, 900ms, 1800ms, 2800ms, 4500ms, 7000ms.

On `after_save`: calls `task_mobile_form_layout_fix(frm)` once after 500ms.

This brute-force pattern compensates for Frappe's asynchronous rendering, which may not have completed when the `refresh` event fires. The function checks its own preconditions on each run, so redundant calls are low-cost but not zero-cost.

### Function: `task_mobile_scroll_to_top` (lines 22–30)

- **Guard**: Only runs on mobile (`window.innerWidth > 768` → exit) and only once per Task document (guards with `frm._task_mobile_last_scroll_doc`).
- **Action**: Scrolls multiple containers to top: `window.scrollTo(0, 0)`, `document.documentElement.scrollTop = 0`, `document.body.scrollTop = 0`, and jQuery scroll on `.main-section, .layout-main-section, .layout-main-section-wrapper, .form-page`.

### Function: `task_mobile_form_layout_fix` (lines 32–209)

**Guard**: `window.innerWidth > 768` → exit (desktop = no-op).

**Pack task detection** (line 34): `is_pack_task = !!(frm.doc.task_kind === 'Pack / prepare items')`. Toggles `body` class `task-mobile-pack-clean` based on this.

**CSS injection** (lines 37–189): Creates `<style id="task-mobile-form-layout-fix-style">` with `@media (max-width: 768px)` rules. Created once (guard by element ID check). The CSS block contains ~150 lines organized into:

#### CSS rules — All Task forms (lines 41–62)

| Rule | Target | Effect |
|---|---|---|
| Scrollable tabs | `.form-tabs-list`, `.form-tabs` | `overflow-x: auto`, `flex-wrap: nowrap`, `white-space: nowrap` |
| Subject visibility | `[data-fieldname="subject"]` and children | `display: block`, `visibility: visible` |
| Subject sizing | `[data-fieldname="subject"] input, textarea` | `min-height: 38px`, `font-size: 15px` |
| Bottom padding | `.form-page` | `padding-bottom: 92px` (space for floating back button) |

#### CSS rules — Pack tasks only (lines 63–187, selector prefix `body.task-mobile-pack-clean`)

| Rule | Target | Effect |
|---|---|---|
| Header overflow | `.page-head`, `.container`, `.page-head-content` | `max-width: 100vw`, `overflow: hidden` |
| Header layout | `.page-head-content` | `display: flex`, `gap: 6px`, `flex-wrap: nowrap` |
| Hide title | `.task-mobile-pack-hidden`, `.title-area`, `.title-text` | `display: none`, `visibility: hidden` |
| Compact actions | `.page-actions .btn`, `.standard-actions .btn`, etc. | Fixed 38×38px, icon-only, `padding: 6px`, text clipped |
| Summary banner | `.task-mobile-pack-summary` | Rounded card (10px radius), `#f8fafc` background, shadow |
| Summary title | `.task-mobile-pack-summary-title` | 16px bold, `overflow-wrap: anywhere` |
| Summary meta | `.task-mobile-pack-summary-meta` | 12px muted color |
| Subject margin | `[data-fieldname="subject"]` | `margin-top: 4px` |
| Reduced labels | `.section-head`, `.control-label` | `font-size: 14px` |
| Control spacing | `.frappe-control` | `margin-bottom: 12px` |
| Hide back button | `#mobile-back-btn`, `.mobile-back-btn`, etc. | `display: none`, `visibility: hidden` |
| Grid fonts | `custom_product_lines`, `custom_task_product_work`, `custom_packing_items`, `.form-grid`, `.grid-body`, `.grid-static-col`, `.grid-row` | `font-size: 13px` |
| Touch scrolling | `.grid-body`, `.form-grid` | `overflow-x: auto`, `-webkit-overflow-scrolling: touch` |
| Grid min-width | `.grid-row`, `.grid-heading-row` | `min-width: 330px` |
| Grid cell sizing | `.grid-static-col` | `min-height: 54px`, `padding: 8px 7px`, word wrap |
| Touch checkboxes | `.grid-static-col input[type="checkbox"]` | `width: 22px`, `height: 22px` |
| Hide grid extras | `.grid-empty`, `.grid-footer` | `display: none` |
| Row padding | `.grid-body .rows` | `padding-bottom: 72px` |

#### JavaScript behavior (lines 192–209)

After CSS injection, the function:

1. **Forces subject visible** (lines 193–198): `frm.toggle_display('subject', true)`, `frm.set_df_property('subject', 'hidden', 0)`, `frm.set_df_property('subject', 'reqd', 0)`. Also uses jQuery to force-show the subject control.
2. **Adds title tooltip** (lines 199–203): Sets a `title` attribute on `.page-head .title-text` so the full text appears on hover/long-press.
3. **Calls `task_mobile_pack_cleanup(frm)`** (line 206) for Pack tasks.

### Function: `task_mobile_pack_cleanup` (lines 211–284)

Only called for Pack tasks on mobile. Performs:

1. **Hides back button** (lines 212–217): Iterates over `#mobile-back-btn`, `.mobile-back-btn`, `.btn-mobile-back`, `[data-mobile-back="1"]` and sets `display: none`, `visibility: hidden` inline.

2. **Removes stale style tags** (lines 219–222): Removes elements with IDs `task-mobile-hide-desktop-custom-actions` and `task-mobile-compact-actions` — cleanup of style tags potentially left by other scripts or older versions.

3. **Builds summary banner** (lines 224–244):
   - Reads `frm.doc.subject`, `frm.doc.dispatch_case`, `frm.doc.dispatch_case_status` (or `custom_dispatch_case_status`), `frm.doc.customer`
   - Finds `.form-layout` or `.layout-main-section` as the insertion target
   - Creates a `<div class="task-mobile-pack-summary">` with:
     - `.task-mobile-pack-summary-title`: shows subject (or "Pack Task" if empty)
     - `.task-mobile-pack-summary-meta`: shows "Dispatch Case: X | Status: Y | Customer: Z"
   - Prepended to the form layout; only created once (checks for existing `.task-mobile-pack-summary`)

4. **Hides metadata fields** (lines 246–255): Adds `task-mobile-pack-hidden` class to controls for: `completed_at`, `task_kind`, `custom_assigned_to`, `custom_accepted_at`, `accepted_at`.

5. **Conditionally hides customer** (lines 257–261): Hides the `customer` field control only if its value is empty.

6. **Hides subject field** (lines 263–280): Hides the `subject` control (replaced by the summary banner title). Also finds labels with text "Subject" and hides their parent controls.

7. **Keeps key fields visible** (lines 282–283): Removes `task-mobile-pack-hidden` from `dispatch_case`, `custom_product_lines`, `custom_task_product_work`, `custom_packing_items`.

### DOM Elements Created

| Element | Selector | Created by | Context |
|---|---|---|---|
| Layout CSS | `#task-mobile-form-layout-fix-style` | `task_mobile_form_layout_fix()` | Task form, mobile only |
| Pack summary banner | `.task-mobile-pack-summary` | `task_mobile_pack_cleanup()` | Pack tasks, mobile only |

### Task Fields Referenced

| Field | How used | Pack task behavior |
|---|---|---|
| `subject` | Forced visible (all tasks); hidden and replaced by summary (Pack) | Hidden, content shown in banner |
| `task_kind` | Read to detect Pack tasks | Hidden |
| `dispatch_case` | Read for summary meta | Kept visible |
| `dispatch_case_status` / `custom_dispatch_case_status` | Read for summary meta | Not directly shown as field |
| `customer` | Read for summary meta | Hidden if empty, shown if populated |
| `completed_at` | Not read | Hidden |
| `custom_assigned_to` | Not read | Hidden |
| `custom_accepted_at` / `accepted_at` | Not read | Hidden |
| `custom_product_lines` | Not directly manipulated | Kept visible |
| `custom_task_product_work` | Not directly manipulated | Kept visible |
| `custom_packing_items` | Not directly manipulated | Kept visible |

---

## 5. Script 4: `Task-Header Long Subject Fix.js`

**File**: `deploy/test/work/client/Task-Header Long Subject Fix.js`
**Lines**: 49 (45 executable after header)
**Trigger**: `frappe.ui.form.on('Task', { refresh, subject })`

### Purpose

Ensures the `subject` field remains visible and editable on the Task form, counteracting ERPNext v16's behavior of moving the subject into the page header bar (where long subjects are truncated).

### Behavior — Confirmed from Source Code

#### Execution pattern (lines 6–15)

- On `refresh`: calls `task_subject_field_visibility_fix(frm)` at 0ms, 250ms, and 900ms
- On `subject` field change: calls `task_subject_field_visibility_fix(frm)` immediately

#### Function: `task_subject_field_visibility_fix` (lines 17–49)

Wrapped in `try/catch` (line 18/48) — all errors silently swallowed.

1. **Removes legacy style** (line 19): Removes `#task-header-long-subject-fix` if present — cleanup of a predecessor version of this script.

2. **Injects CSS** (lines 22–37): Creates `<style id="task-subject-field-visibility-fix">` with:
   - `body[data-route^="Form/Task"] [data-fieldname="subject"]` and children → `display: block`, `visibility: visible`
   - `.task-visible-subject-banner` → `display: none`, `visibility: hidden` (hides any banner another script may have created)

3. **Forces field visible via Frappe API** (lines 40–43): `frm.toggle_display('subject', true)` and `frm.set_df_property('subject', 'hidden', 0)`.

4. **jQuery cleanup** (lines 44–47): Removes any `.task-visible-subject-banner` elements. Force-shows the subject control container.

### DOM Elements Created

| Element | Selector | Created by | Lifetime |
|---|---|---|---|
| Visibility CSS | `#task-subject-field-visibility-fix` | `task_subject_field_visibility_fix()` | Persistent |

### Overlap with Script 3

Both this script and Script 3 (`Task-Mobile Form Layout Fix.js`) inject CSS and use Frappe API to force the `subject` field visible. The duplication is functionally harmless — both set the same properties — but indicates the scripts were developed independently. The CSS selectors are nearly identical:

- **Script 3** (lines 49–54): `body[data-route^="Form/Task"] [data-fieldname="subject"] { display: block !important; visibility: visible !important; }`
- **Script 4** (lines 26–31): `body[data-route^="Form/Task"] [data-fieldname="subject"] { display: block !important; visibility: visible !important; }`

**Key difference**: Script 3 only runs on mobile (`window.innerWidth > 768` early return). Script 4 runs on **all screen sizes** — it is the only script that fixes subject visibility on desktop.

---

## 6. Script 5: `Task-Delivery UI Fix.js`

**File**: `deploy/test/work/client/Task-Delivery UI Fix.js`
**Lines**: 36 (32 executable after header)
**Trigger**: `frappe.ui.form.on('Task', { refresh })`

### Purpose

Applies CSS fixes for Delivery-type tasks on mobile, and ensures the `custom_next_task_assign_to` field is visible.

### Behavior — Confirmed from Source Code

#### Execution pattern (lines 6–12)

On `refresh`: calls `task_delivery_ui_fix_apply(frm)` at 0ms, 300ms, and 900ms.

#### Function: `task_delivery_ui_fix_apply` (lines 14–36)

1. **Detects Delivery tasks** (line 16): `is_delivery = String(frm.doc.task_kind || "").trim() === "Delivery"`.
2. **Toggles body class** (line 17): `document.body.classList.toggle("task-delivery-ui-active", is_delivery)`. Exits if not a Delivery task.
3. **Unhides `custom_next_task_assign_to`** (lines 19–22): If the field exists in `frm.fields_dict`, sets `hidden: 0` and `toggle_display: true`. This field allows the delivery driver to see or specify who handles the next task in the chain.
4. **Injects CSS** (lines 23–35): Creates `<style id="task-delivery-ui-fix-css">` with `@media(max-width:768px)` rules:

| Rule | Target | Effect |
|---|---|---|
| Action wrapping | `.page-actions` | `flex-wrap: wrap`, `justify-content: flex-end`, visible overflow, `row-gap: 4px` |
| Button sizing | `.page-actions .btn` | `max-width: 46vw`, `white-space: normal`, `line-height: 1.15`, compact padding |
| Header wrapping | `.page-head-content` | `flex-wrap: wrap`, visible overflow |
| Title constraint | `.title-area` | `min-width: 0`, `max-width: 100%` |

### Why This Exists

Delivery tasks have multiple action buttons (Accept, Picked Up, Delivered, etc.) plus standard ERPNext buttons (Save, Menu, etc.). On mobile, these overflow the header bar and become invisible or inaccessible. This script forces them to wrap onto multiple lines.

### DOM Elements Created

| Element | Selector | Created by | Context |
|---|---|---|---|
| Delivery CSS | `#task-delivery-ui-fix-css` | `task_delivery_ui_fix_apply()` | Delivery tasks, mobile only |

### Task Fields Referenced

| Field | How used |
|---|---|
| `task_kind` | Read to detect "Delivery" tasks |
| `custom_next_task_assign_to` | Forced visible |

---

## 7. Script 6: `task_list_filtered.py`

**File**: `deploy/test/work/server/task_list_filtered.py`
**Lines**: 103 (97 executable after header)
**Type**: Server Script, API
**API Method**: `task_list_filtered`
**Allow Guest**: No (requires authentication)

### Purpose

Server-side API endpoint that returns a filtered list of Task names based on the current user's roles, their Task Access Policy permissions, and toggle filter state. Called by the client-side toggle filters in Script 2.

### Important: Current Code vs Audit Description

The Group 9 audit described this script as containing hardcoded `TASK_KIND_ALLOWED_ROLES`, `TEAM_PLACEHOLDERS`, and `ACCOUNT_DETAILS_MY_TASK_USERS`. **The current deployed version no longer contains any of these.** It reads role/team mappings from `Task Access Policy` records at runtime, which aligns with the project's architectural rule (see AGENTS.md: "Never hardcode role dictionaries or team constants in Server Scripts").

### API Input Parameters

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `my_tasks` | int (0/1) | 0 | Include tasks assigned to the current user |
| `open_tasks` | int (0/1) | 0 | Include tasks with non-completed, non-cancelled status |
| `completed` | int (0/1) | 0 | Include tasks with status = Completed |

### Processing Logic — Confirmed from Source Code

#### Step 1: User identification (lines 8–16)

```
user = frappe.session.user
role_rows = frappe.get_all("Has Role", filters={"parenttype": "User", "parent": user}, ...)
user_roles = set([r.role for r in role_rows])
is_admin = user == "Administrator" or "System Manager" in user_roles
```

Reads the current user's roles from the `Has Role` child table.

#### Step 2: Task Access Policy lookup (lines 19–47)

```
policies = frappe.get_all("Task Access Policy", fields=["name", "default_team_user"], ...)
all_role_rows = frappe.get_all("Task Access Policy Role", fields=["parent", "role"], ...)
```

Builds a role map: `{ policy_name: [role1, role2, ...] }`.

For each policy:
- If the user is admin, or any of the user's roles match the policy's allowed roles → add to `allowed_kinds`
- If the policy has **no roles defined** → add to `allowed_kinds` (permissive fallback, line 42-43)
- Collects all `default_team_user` values into `team_placeholders`

#### Step 3: Early exit (lines 50–52)

If `allowed_kinds` is empty and user is not admin → returns empty array and exits via `raise SystemExit`.

#### Step 4: SQL construction (lines 54–98)

Builds a raw SQL query with the following logic:

**When no toggles are selected** (`my_tasks == 0 and open_tasks == 0 and completed == 0`):
- Admins: `WHERE 1=1` (all tasks)
- Others: `WHERE task_kind IN (allowed_kinds) OR task_kind IS NULL OR task_kind = ''`

**When toggles are selected**:
- **Status filter**:
  - Both open + completed: `status != 'Cancelled'`
  - Completed only: `status = 'Completed'`
  - Open only (or my_tasks only): `status NOT IN ('Completed', 'Cancelled')`

- **Assignment/team filter** (combined with OR):
  - If `my_tasks`: `_assign LIKE '%user_email%'`
  - If `open_tasks` or `completed`: role-match AND team-availability, where team-availability means: unassigned, assigned to current user, or assigned to any team placeholder

- Final: `WHERE status_condition AND (my_tasks_clause OR team_clause)`

**Result**: `SELECT name FROM tabTask WHERE ... ORDER BY modified DESC LIMIT 500`

#### Step 5: Response (line 103)

`frappe.response["message"] = [r["name"] for r in results]`

Returns a flat array of Task name strings.

### SQL Construction Details

- **Escaping**: Uses `.replace("'", "''")` for user email and kind names. Not parameterized queries, but all inputs are server-controlled (user email from `frappe.session.user`, kind names from database records, team placeholders from database records).
- **`_assign` matching**: Uses `LIKE '%email%'` — cannot use database indexes. On large Task tables, this results in a full table scan per query.
- **Result limit**: Hard limit of 500 rows, ordered by `modified DESC`. No pagination, no `has_more` indicator.

### Logging

Three `print()` statements with `[List]` tag (lines 17, 48, 101):
- User info, toggle state, admin status
- Policy/role counts, allowed kinds count, team placeholder count
- Result count

These appear in Frappe server logs.

---

## 8. Cross-Script Interactions

### 8.1 Back Button Conflict (Scripts 1 + 2)

Both scripts create and manage the same DOM element (`#mobile-back-btn`) using the same global variable (`window._mobileBackInterval`) but with **incompatible strategies**:

| Aspect | Script 1 (Form) | Script 2 (List) |
|---|---|---|
| Strategy | Event-driven (popstate, hashchange, resize, click, router) | Polling (`setInterval` every 300ms) |
| `_mobileBackInterval` value | String: `'global-mobile-back-button-stable'` | Number: interval handle from `setInterval()` |
| `history.back()` fallback | `frappe.set_route('List', 'Task')` when no history | None — always calls `history.back()` |
| Activation | Only after first Task form visit | Immediately on any page where Task List script loads |
| Stops the other | Yes — calls `clearInterval(window._mobileBackInterval)` if it's a number | No — only checks `if (window._mobileBackInterval)` to skip init |

**Interaction sequence** (typical user flow: list → form):
1. User opens Task list → Script 2 loads, starts `setInterval`, `_mobileBackInterval` = interval ID (number)
2. User opens a Task form → Script 1 fires `refresh`, calls `clearInterval(_mobileBackInterval)` (stops Script 2's polling), sets `_mobileBackInterval` = `'global-mobile-back-button-stable'`
3. From this point, Script 1's event-driven approach controls the back button
4. If user navigates back to list, Script 2's `onload` fires but the IIFE guard `if (window._mobileBackInterval) return` is true (string is truthy) — Script 2 does NOT restart polling

**Net result**: Script 1 effectively wins control after first Task form visit. Script 2 controls the back button only before the first form visit.

### 8.2 Subject Visibility Overlap (Scripts 3 + 4)

Both scripts force the `subject` field visible via CSS and Frappe API:

| Script | CSS selector | CSS ID | Frappe API calls | Scope |
|---|---|---|---|---|
| Script 3 | `body[data-route^="Form/Task"] [data-fieldname="subject"]` | `task-mobile-form-layout-fix-style` | `frm.toggle_display`, `frm.set_df_property` | Mobile only |
| Script 4 | `body[data-route^="Form/Task"] [data-fieldname="subject"]` | `task-subject-field-visibility-fix` | `frm.toggle_display`, `frm.set_df_property` | All screens |

The duplication is harmless but indicates independent development. Script 4 is essential for desktop subject visibility; Script 3 adds mobile-specific subject styling (larger font, min-height).

### 8.3 Back Button + Pack Task Layout (Scripts 1/2 + 3)

Script 3 **hides the back button on Pack tasks** via both CSS (`body.task-mobile-pack-clean #mobile-back-btn { display: none !important }`) and JavaScript (`task_mobile_pack_cleanup` directly sets display:none/visibility:hidden on `#mobile-back-btn`). This means:

- On Pack tasks: back button is hidden (by Script 3) regardless of which back button script created it
- On non-Pack tasks: back button is visible (managed by Scripts 1/2)

### 8.4 Delivery UI + Pack Layout (Scripts 5 + 3)

Scripts 5 and 3 target different task kinds — they do not conflict:
- Script 3: `task_kind === 'Pack / prepare items'` → adds `task-mobile-pack-clean` class
- Script 5: `task_kind === "Delivery"` → adds `task-delivery-ui-active` class

Both can inject CSS simultaneously, but their selectors are prefixed with different body classes, so they only activate on their respective task kinds.

### 8.5 Toggle Filters + Server API (Scripts 2 + 6)

Script 2's `applyToggleFilter()` calls Script 6 (`task_list_filtered`). This is the only caller. The contract:

- **Input**: Three integer flags (0/1)
- **Output**: Array of Task name strings (max 500)
- **Client applies**: `name IN [names]` filter on the list view
- **Failure mode**: On API error, clears all filters and refreshes (shows unfiltered list)

---

## 9. Documentation Coverage Assessment

### What IS documented

| Behavior | Where documented | Level of detail |
|---|---|---|
| Toggle filters exist ("My Tasks", "Open Tasks", "Completed") | Doc 10 §6.5 (lines 339–345) | Brief — states the rules but not the implementation |
| `task_list_filtered` API exists | Doc 10A §6A scripts table (line 428) | One-line description |
| `Global-Mobile Back Button List` client script exists | Doc 10A §6A scripts table (line 441) | One-line description |
| Task kind → role mappings | Doc 10A §6A canonical table (lines 456–482) | Full table, current |
| Team placeholder emails | Doc 10A §6A canonical table (lines 456–482) | Full table, current |
| Task Access Policy as single source of truth | Doc 10 §6.8, Doc 10A §6A | Explained |
| Task list filtering by status and kind | Delivery driver guide (lines 11–13, 25, 80) | Basic user instructions |
| Subject naming conventions | Doc 10 §9 (lines 458–471) | Patterns per task kind |
| Photo system (now separate from these scripts) | Doc 18 | Comprehensive |

### What is NOT documented

| Behavior | Scripts | Impact |
|---|---|---|
| Floating mobile back button — visual design, positioning, creation logic | Scripts 1, 2 | Users and maintainers have no reference for intended behavior |
| Two competing back-button implementations and their interaction | Scripts 1, 2 | Maintainer risk — any change to one may break the other |
| 768px mobile breakpoint | All 5 client scripts | No documented rationale for this threshold |
| Perpetual 300ms `setInterval` polling | Script 2 | Performance impact undocumented |
| Task list toggle bar — visual design, sticky positioning, default state | Script 2 | No UI spec or user guide |
| Toggle filters replace native ERPNext filtering | Script 2 | Users cannot combine with standard filters — undocumented limitation |
| 500-row limit on `task_list_filtered` results | Script 6 | Silent data truncation — no user-facing indication |
| Pack task mobile summary banner | Script 3 | No design spec |
| Pack task field visibility rules (which fields hidden, which kept) | Script 3 | No documentation of why specific fields are hidden |
| Pack task action buttons → compact 38×38px icon-only mode | Script 3 | No documentation; button labels lost on mobile |
| Touch-friendly checkbox sizing (22×22px) | Script 3 | No documentation |
| Horizontal-scrollable tab list on mobile | Script 3 | No documentation |
| Subject field force-visible on desktop | Script 4 | Fixes an ERPNext v16 behavior — not documented as a design decision |
| Legacy style tag cleanup (`#task-header-long-subject-fix`) | Script 4 | Historical artifact undocumented |
| Delivery action button wrapping on mobile | Script 5 | No documentation |
| `custom_next_task_assign_to` forced visible on Delivery tasks | Script 5 | Field visibility logic undocumented |
| EXIF image rotation fix (`image-orientation: from-image`) | Script 2 | Applied globally; no documentation |
| Menu tooltip removal on mobile | Script 2 | No documentation |
| Brute-force staggered re-application pattern | Script 3 | Engineering decision undocumented |
| `console.log` debug statements in production | Script 2 | Should be removed or documented as intentional |

---

## 10. Known Limitations and Static Risks

### 10.1 Perpetual `setInterval` Polling — ACTIVE

**Source**: Script 2, line 46
**Code**: `window._mobileBackInterval = setInterval(ensureBackBtn, 300)`

The `ensureBackBtn` function runs 3.3 times per second for the entire browser session. Each iteration:
- Reads `window.innerWidth`
- Reads `window.location.href`
- Performs string operations and DOM lookups

**Impact**: Continuous CPU cost on mobile devices. Low per-call cost but never stops.

**Severity**: Medium (performance)

**Status**: Present in current code. Was noted in audit as F9-005.

### 10.2 Duplicate Back Button Implementations — ACTIVE

**Source**: Scripts 1 and 2
**Details**: See §8.1 above.

**Impact**: Maintainer confusion — modifying one script's back button logic without understanding the other may produce unexpected behavior. The current interaction happens to work (Script 1 wins after first form visit), but this is an emergent behavior, not an explicit design.

**Severity**: Medium (maintainability)

**Status**: Present in current code. Was noted in audit as F9-004.

### 10.3 Toggle Filters Replace Native Filtering — ACTIVE

**Source**: Script 2, lines 118–124

When toggle filters are applied, the client calls `lv.filter_area.clear()` then sets `name IN [names]`. This:
- Removes any user-applied filters
- Prevents combining toggles with standard filters
- Cannot be saved as a filter preset
- Prevents URL-based filter sharing

**Severity**: Medium (usability)

**Status**: Present in current code. Was partially noted in audit as part of F9-001.

### 10.4 500-Row Silent Truncation — ACTIVE

**Source**: Script 6, line 98: `LIMIT 500`

If a user has access to more than 500 tasks matching the toggle criteria, older tasks are silently excluded. No `has_more` flag or count is returned.

**Severity**: Low (data completeness) — 500 is likely sufficient for daily operational use, but becomes a risk as task history grows.

**Status**: Present in current code. Was noted in audit as F9-013.

### 10.5 `_assign LIKE` Full Table Scan — ACTIVE

**Source**: Script 6, lines 76–78, 86

The SQL uses `_assign LIKE '%email%'` which cannot use indexes. As the Task table grows, query performance will degrade.

**Severity**: Low (performance) — acceptable for current task volumes.

**Status**: Present in current code.

### 10.6 `history.back()` May Navigate Outside ERPNext — ACTIVE

**Source**: Script 1, line 33; Script 2, line 39

If the user entered ERPNext directly from an external link and has only one history entry, Script 2's `history.back()` navigates to the external site. Script 1 mitigates this with the `frappe.set_route('List', 'Task')` fallback when `history.length <= 1`, but Script 2 has no such fallback.

**Severity**: Low (usability) — primarily affects users who open ERPNext task links from Telegram notifications.

**Status**: Present in current code.

### 10.7 Brute-Force Re-Application Pattern — ACTIVE

**Source**: Script 3, lines 8–15

Seven `setTimeout` calls at staggered intervals (0–7000ms). Each call re-runs the full layout fix function. While each call is idempotent, this pattern:
- Wastes CPU cycles on redundant DOM operations
- May cause visible UI flickering on slow devices
- Runs for 7 seconds total per Task form load

**Severity**: Low (performance/UX)

**Status**: Present in current code. Was noted in audit as F9-008.

### 10.8 Console.log in Production — ACTIVE

**Source**: Script 2, lines 102, 112

```javascript
console.log('[TaskToggle] filter changed', {...});
console.log('[TaskToggle] loaded', {count: names.length});
```

Debug output visible in browser developer tools.

**Severity**: Low (cosmetic)

**Status**: Present in current code. Was noted in audit as F9-012.

### 10.9 Silent Error Swallowing — ACTIVE

**Source**: Script 4, line 18/48 (`try/catch` with empty catch block)

Any error in `task_subject_field_visibility_fix` is silently swallowed. If the function fails, the subject field may remain hidden with no diagnostic output.

**Severity**: Low (debuggability)

**Status**: Present in current code.

---

## 11. Open Questions Requiring Business Confirmation

These items cannot be resolved through code analysis alone. They require input from the business owner or operational users.

### Q1: Should the back button be present on ALL mobile pages, or only Task-related pages?

**Current behavior**: After first Task list or form visit, the back button appears on every mobile page in the ERPNext session (including non-Task pages like Item, Customer, etc.).

**Question**: Is this the intended design? If so, the "Global" name is appropriate. If not, the button should be scoped to Task-related routes only.

### Q2: Should Pack tasks hide the back button?

**Current behavior**: Script 3 explicitly hides the back button on Pack tasks (both via CSS and JavaScript).

**Question**: Why is the back button hidden specifically on Pack tasks? Is this intentional? Does the warehouse team use the back button differently, or is this to maximize screen space for the packing interface?

### Q3: Is the 500-task limit acceptable for daily operations?

**Current behavior**: Toggle filters return at most 500 tasks. No indication to the user when results are truncated.

**Question**: How many active/recent tasks does a typical user see? If the answer is well under 500, this is acceptable. If users handle high-volume task flows, the limit may need to increase or pagination should be added.

### Q4: Should toggle filter defaults be configurable or persisted?

**Current behavior**: Defaults are always `My Tasks: on, Open: on, Completed: off`. Navigating away resets to defaults.

**Question**: Should the last-used toggle state be remembered (e.g., via localStorage)? Should different roles have different defaults?

### Q5: Is `custom_next_task_assign_to` visibility on Delivery tasks intentional?

**Current behavior**: Script 5 unhides this field specifically for Delivery tasks.

**Question**: Is this field meant to be visible for all Delivery tasks, or only in certain statuses? Should other task kinds also show this field?

### Q6: Is the 768px breakpoint appropriate for all target devices?

**Current behavior**: All scripts use `window.innerWidth <= 768` as the mobile threshold.

**Question**: What devices do operational staff actually use? If any staff use tablets (e.g., iPad at 1024px), they would get the desktop layout. Confirm whether 768px matches the target device fleet.

---

## 12. Verification Scenarios

These scenarios can be used to verify the documented behavior matches actual runtime behavior. They require access to a running ERPNext instance.

### VS-01: Back Button Visibility

| Step | Expected | Script(s) |
|---|---|---|
| Open Task list on mobile (≤768px) | Back button appears (blue circle, bottom-left) | 2 |
| Navigate to `/app` (home) | Back button disappears | 2 |
| Navigate back to Task list | Back button reappears | 2 |
| Open a Task form | Back button remains visible | 1 |
| Open a Pack task form | Back button disappears | 3 |
| Open a non-Pack task form (e.g., Delivery) | Back button reappears | 1 |
| View on desktop (>768px) | Back button never appears | 1, 2 |

### VS-02: Toggle Filters

| Step | Expected | Script(s) |
|---|---|---|
| Open Task list | Toggle bar appears with My Tasks (on), Open (on), Completed (off) | 2 |
| Default load | Shows tasks assigned to me AND open team tasks | 2, 6 |
| Uncheck "My Tasks" | Shows only open team tasks (not personally assigned) | 2, 6 |
| Check "Completed" | Adds completed tasks to results | 2, 6 |
| Uncheck all three | Shows all tasks the user has access to (any status) | 2, 6 |
| Navigate away and return | Toggles reset to defaults | 2 |
| Check browser console | Two `[TaskToggle]` messages per filter change | 2 |

### VS-03: Pack Task Mobile Layout

| Step | Expected | Script(s) |
|---|---|---|
| Open a Pack task on mobile | Title area hidden, summary banner visible | 3 |
| Summary banner | Shows subject, dispatch case, status, customer | 3 |
| Action buttons | Compact 38×38px icon-only buttons | 3 |
| Packing items table | Scrollable horizontally, 13px font, 22×22px checkboxes | 3 |
| Metadata fields | `completed_at`, `task_kind`, `custom_assigned_to`, `custom_accepted_at` hidden | 3 |
| `dispatch_case` field | Visible | 3 |
| Back button | Hidden | 3 |

### VS-04: Delivery Task Mobile Layout

| Step | Expected | Script(s) |
|---|---|---|
| Open a Delivery task on mobile | Action buttons wrap to multiple lines | 5 |
| `custom_next_task_assign_to` field | Visible | 5 |
| Back button | Visible (not hidden like Pack tasks) | 1 |

### VS-05: Subject Field Visibility

| Step | Expected | Script(s) |
|---|---|---|
| Open a Task with a long subject on desktop | Subject field visible as an editable field (not just in header) | 4 |
| Open a Task on mobile | Subject field visible (Script 3 CSS + Script 4 CSS both active) | 3, 4 |
| Open a Pack task on mobile | Subject field hidden (replaced by summary banner) | 3 |

### VS-06: task_list_filtered API

| Step | Expected | Script(s) |
|---|---|---|
| Call API as a user with `Ops - Delivery` role | Returns task names for task kinds where this role is in the policy | 6 |
| Call API as Administrator | Returns tasks regardless of kind | 6 |
| Call with `my_tasks=1` | Returns tasks where `_assign` contains the user's email | 6 |
| Call with `open_tasks=1` | Returns tasks with status not in (Completed, Cancelled) | 6 |
| Call with `completed=1` | Returns tasks with status = Completed | 6 |
| Total matching tasks > 500 | Only 500 returned, ordered by `modified DESC`, no truncation warning | 6 |
| User with no matching Task Access Policy roles | Returns empty array | 6 |

---

## 13. Cross-Group Dependencies

| Item | This Document (Group 9) | Related Group | Dependency |
|---|---|---|---|
| Task Access Policy records | Script 6 reads `Task Access Policy` and `Task Access Policy Role` at runtime | Group 2 (Task System & Gates) | Both Script 6 and the task save/accept scripts rely on the same policy records. Any change to policy records affects both the list filtering and the save/accept enforcement. |
| `_assign` field | Script 6 uses `_assign LIKE` for assignment matching | Group 2 (Task System & Gates) | The `_assign` field is managed by Frappe's ToDo/assignment system and by the task accept API (`dispatch_task_accept`). Changes to assignment logic affect list filtering results. |
| Pack task kind name | Script 3 checks `task_kind === 'Pack / prepare items'` | Group 2 (Task System & Gates) | If the task kind name changes in the `task_kind` Select field, Script 3's detection breaks. |
| Delivery task kind name | Script 5 checks `task_kind === "Delivery"` | Group 2 (Task System & Gates) | Same risk as Pack — hardcoded string match. |
| `dispatch_case` field | Script 3 reads `frm.doc.dispatch_case` for the summary banner | Group 1 (Dispatch Flow) | The banner depends on `dispatch_case` being populated by the dispatch flow automation. |
| Subject auto-generation | Scripts 3 and 4 ensure subject is visible; Script 3 shows it in the Pack summary | Group 2 (`Task-before-save-auto-subject.py`) | The auto-subject script generates the subject content; these scripts ensure it's displayed. |
| `custom_next_task_assign_to` | Script 5 unhides this field for Delivery tasks | Group 1 (Dispatch Flow) | This field is part of the task chaining logic in the dispatch flow. |
| Doc 16a workspace shortcuts | Script 2's toggle filters may coexist with workspace-defined filtered list views | Group 1 (Dispatch Flow) | Doc 16a lines 1339–1359 describe per-kind workspace shortcuts. Whether these coexist with toggle filters needs live verification. |

---

## Appendix A: Complete DOM Element Registry

All DOM elements created by the 6 scripts:

| Element ID / Class | Type | Created by | Scope | Persistence |
|---|---|---|---|---|
| `#mobile-back-btn` | `<div>` | Scripts 1, 2 | All mobile pages | Session-long |
| `#mobile-global-css` | `<style>` | Script 2 | All mobile pages | Session-long |
| `#mobile-list-refresh` | `<button>` | Script 2 | Task list, mobile | Until navigation |
| `#task-toggle-bar` | `<div>` | Script 2 | Task list | Until navigation |
| `#task-mobile-form-layout-fix-style` | `<style>` | Script 3 | Task form, mobile | Session-long |
| `.task-mobile-pack-summary` | `<div>` | Script 3 | Pack task form, mobile | Until navigation |
| `#task-subject-field-visibility-fix` | `<style>` | Script 4 | Task form | Session-long |
| `#task-delivery-ui-fix-css` | `<style>` | Script 5 | Delivery task form, mobile | Session-long |

## Appendix B: Global JavaScript Variables

| Variable | Set by | Type | Purpose |
|---|---|---|---|
| `window._mobileBackInterval` | Scripts 1, 2 | Number (interval ID) or String (sentinel) | Coordinates back button ownership |
| `window._backBtnWired` | Script 1 | Boolean | Prevents duplicate event listener attachment |
| `window._taskToggleState` | Script 2 | Object `{ my_tasks, open_tasks, completed }` | Current toggle filter state |
| `window._taskToggleNames` | Script 2 | Array of strings | Last API response (task names) |
| `frm._task_mobile_last_scroll_doc` | Script 3 | String (Task name) | Prevents re-scrolling on same doc |

## Appendix C: CSS Body Classes

| Class | Set by | Condition | Purpose |
|---|---|---|---|
| `task-mobile-pack-clean` | Script 3 | `task_kind === 'Pack / prepare items'` | Activates Pack-specific CSS rules |
| `task-delivery-ui-active` | Script 5 | `task_kind === "Delivery"` | Activates Delivery-specific CSS rules |

## Appendix D: Audit Findings Status Update

The Group 9 audit (2026-08-27) identified 14 findings. Based on the current code (2026-08-29), their status:

| Audit ID | Description | Current Status | Notes |
|---|---|---|---|
| F9-001 | Zero documentation for all mobile UI code | **PARTIALLY ADDRESSED** | Doc 10 §6.5 documents toggles; Doc 10A lists scripts. Implementation details remain undocumented. This document (F9-001) serves as the detailed reference. |
| F9-002 | TASK_KIND_ALLOWED_ROLES drift from documentation | **RESOLVED** | Script now reads from Task Access Policy records. No hardcoded mapping exists. |
| F9-003 | Hardcoded user emails (ACCOUNT_DETAILS_MY_TASK_USERS) | **RESOLVED** | List removed from current code. |
| F9-004 | Duplicate back button implementations | **STILL PRESENT** | See §10.2 |
| F9-005 | Perpetual 300ms setInterval | **STILL PRESENT** | See §10.1 |
| F9-006 | Missing purchasing.team placeholder | **RESOLVED** | Team placeholders now read from Task Access Policy records. |
| F9-007 | frappe.client.set_value bypass (photo field) | **RESOLVED** | Photo functions removed from this script (now in Doc 18 photo system). |
| F9-008 | Brute-force re-application pattern | **STILL PRESENT** | See §10.7 |
| F9-009 | 5-photo attachment limit undocumented | **RESOLVED** | Photo system now documented in Doc 18 (lines 45–48, 167–170). |
| F9-010 | Fullscreen photo viewer undocumented | **RESOLVED** | Viewer moved to Doc 18 photo system. |
| F9-011 | Overlapping subject visibility fixes | **STILL PRESENT** | See §8.2 |
| F9-012 | Console.log in production | **STILL PRESENT** | See §10.8 |
| F9-013 | 500-row silent truncation | **STILL PRESENT** | See §10.4 |
| F9-014 | Brand-new Delivery UI Fix script | **STILL PRESENT** | Script is 2 days old as of this writing. |
