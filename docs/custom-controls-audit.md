# Custom Controls Audit — Test Environment

**Date:** 2026-08-31
**Source of truth:** `deploy/test/schema/` (exported 2026-08-31)
**Scope:** All custom UI controls (buttons, layout changes, field visibility, navigation, CSS injections, inline controls) created by client scripts, custom fields, and property setters. Test environment only.
**Exclusions:** Photo Gallery (`Task-Photo-System`, `Dispatch Case-Photo-Galleries`) — excluded per user request.
**Method:** Analysis of `deploy/test/schema/client-scripts.json` (35 records), `server-scripts.json` (45 records), `custom-fields.json` (117 records), `property-setters.json` (193 records), and work files in `deploy/test/work/client/`.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Script Inventory](#2-script-inventory)
3. [Per-DocType Control Catalog](#3-per-doctype-control-catalog)
4. [Server API Endpoints Called by UI](#4-server-api-endpoints-called-by-ui)
5. [Custom Fields Driving UI](#5-custom-fields-driving-ui)
6. [Mobile vs Desktop Differences](#6-mobile-vs-desktop-differences)
7. [Duplicates and Conflicts](#7-duplicates-and-conflicts)
8. [Misconfigurations](#8-misconfigurations)
9. [Disabled / Stale / Superseded Scripts](#9-disabled--stale--superseded-scripts)
10. [Hardcoded Values](#10-hardcoded-values)
11. [CSS Injections Inventory](#11-css-injections-inventory)
12. [Recommendations](#12-recommendations)

---

## 1. Executive Summary

### Counts (test environment, from schema)

| Category | Total | Enabled | Disabled |
|---|---|---|---|
| Client scripts | 35 | 34 | 1 |
| Server scripts | 45 | 42 | 3 |
| Server Script API endpoints | 11 | 11 | 0 |
| Custom fields on Task | 52 | — | — |
| Custom fields on Dispatch Case | 10 | — | — |
| Custom fields on Dispatch Case Item | 10 | — | — |
| Property setters | 193 | — | — |

### Findings

| # | Finding | Severity | Details |
|---|---------|----------|---------|
| 1 | **Mobile back button created in 3 scripts** — all target `#mobile-back-btn`, race conditions | **MEDIUM** | [Section 7.1](#71-mobile-back-button--triple-implementation) |
| 2 | **Accept / Start Task button created in 4 scripts** — duplicate buttons possible | **MEDIUM** | [Section 7.2](#72-accept-button--quadruple-implementation) |
| 3 | **`Task-Product Lines Display` enabled on server, marked disabled in work file** — superseded script still running | **MEDIUM** | [Section 8.1](#81-task-product-lines-display--enableddisabled-mismatch) |
| 4 | **`Dispatch Case-Item Code String Guard` registered on wrong DocType** — header says DC, code targets Task list (disabled, no harm) | **LOW** | [Section 8.2](#82-dispatch-case-item-code-string-guard--wrong-doctype-registration) |
| 5 | **`custom_account_photos` depends_on uses stale task_kind name** — never shown via depends_on | **LOW** | [Section 8.3](#83-custom_account_photos-depends_on-uses-stale-task-kind) |
| 6 | **4 hardcoded approver email lists** across scripts | **MEDIUM** | [Section 10](#10-hardcoded-values) |
| 7 | **`Task-Accept Start` contains `account_details_entry_ui_cleanup()` function** — misplaced code that also exists in its own script | **MEDIUM** | [Section 7.3](#73-account-details-cleanup--duplicated-across-scripts) |

---

## 2. Script Inventory

This is the definitive list from `client-scripts.json` (35 records). The `enabled` column is what is actually deployed on the test server.

### 2.1 Enabled Client Scripts (34)

| # | Name | DocType | View | Owner | Last Modified |
|---|------|---------|------|-------|---------------|
| 1 | GS1 Barcode Parser | Purchase Receipt | Form | levonaghinyan77 | 2026-05-13 |
| 2 | Dispatch Case-Form | Dispatch Case | Form | ai-agent | 2026-08-27 |
| 3 | LCV-import-duty-prefill | Landed Cost Voucher | Form | ai-agent | 2026-05-11 |
| 4 | Dispatch Case-Packing Scan | Dispatch Case | Form | ai-agent | 2026-06-15 |
| 5 | Task-Accept Start | Task | Form | ai-agent | 2026-08-29 |
| 6 | Task-Team Queue | Task | List | ai-agent | 2026-08-29 |
| 7 | Dispatch Case-Packing Problem Alerts | Dispatch Case | Form | ai-agent | 2026-06-08 |
| 8 | Task-Dispatch Packing Usability | Task | Form | ai-agent | 2026-08-29 |
| 9 | Task-Create Dispatch Case Items | Task | Form | ai-agent | 2026-07-06 |
| 10 | **Task-Product Work Area** | Task | Form | ai-agent | 2026-08-31 |
| 11 | Task-Product Lines Display | Task | Form | ai-agent | 2026-07-21 |
| 12 | Dispatch Case-Price Visibility | Dispatch Case | Form | ai-agent | 2026-06-09 |
| 13 | Dispatch Case-Simplify for Order Creation | Dispatch Case | Form | ai-agent | 2026-08-28 |
| 14 | Dispatch Case-Products Button | Dispatch Case | Form | ai-agent | 2026-07-21 |
| 15 | Dispatch Case Item-Auto Fill Item Name | Dispatch Case Item | Form | ai-agent | 2026-06-11 |
| 16 | Task-Lock Completed | Task | Form | ai-agent | 2026-06-30 |
| 17 | Task-Lock Unaccepted | Task | Form | ai-agent | 2026-08-29 |
| 18 | Dispatch Case-Lock Submitted | Dispatch Case | Form | ai-agent | 2026-06-22 |
| 19 | Task-Auto Reload | Task | Form | ai-agent | 2026-08-29 |
| 20 | Order entry - barcode scanning section - hide | Task | Form | levonaghinyan77 | 2026-08-28 |
| 21 | Workspace | Workspace | Form | levonaghinyan77 | 2026-07-10 |
| 22 | Global-Mobile Back Button List | Task | List | ai-agent | 2026-08-29 |
| 23 | Global-Mobile Back Button | Task | Form | levonaghinyan77 | 2026-07-31 |
| 24 | Dispatch Case-Item Code String Guard | Dispatch Case | Form | Administrator | 2026-07-17 |
| 25 | Task Product Line-Item Code String Guard | Task | Form | Administrator | 2026-07-17 |
| 26 | Task-Header Long Subject Fix | Task | Form | Administrator | 2026-08-24 |
| 27 | Task-Account Details UI Cleanup | Task | Form | ai-agent | 2026-08-29 |
| 28 | Dispatch Case-Template Auto Fill | Dispatch Case | Form | levonaghinyan77 | 2026-07-29 |
| 29 | Task-Other UI Cleanup | Task | Form | ai-agent | 2026-08-29 |
| 30 | Task-Mobile Form Layout Fix | Task | Form | Administrator | 2026-08-28 |
| 31 | Task-Inspect Returns Next Assign Visible | Task | Form | Administrator | 2026-08-25 |
| 32 | Task-Delivery UI Fix | Task | Form | Administrator | 2026-08-27 |
| 33 | Task-Photo-System | Task | Form | Administrator | 2026-08-28 |
| 34 | Dispatch Case-Photo-Galleries | Dispatch Case | Form | Administrator | 2026-08-28 |

> Rows 33-34 are the photo gallery scripts — excluded from the detailed analysis below per user request.
>
> Row 11: `Task-Product Lines Display` is **enabled=1 in schema** but the work file header says `Enabled: 0`. See [Section 8.1](#81-task-product-lines-display--enableddisabled-mismatch).

### 2.2 Disabled Client Scripts (1)

| # | Name | DocType | View | Notes |
|---|------|---------|------|-------|
| 1 | Task-Packing Checkboxes | Task | Form | Merged into `Task-Product Work Area` (2026-08-31). All functions moved to the merged script. |

### 2.3 Scripts Per DocType

| DocType | Form | List | Total |
|---|---|---|---|
| Task | 19 (+ 1 disabled) | 2 | 22 |
| Dispatch Case | 9 | 0 | 9 |
| Dispatch Case Item | 1 | 0 | 1 |
| Purchase Receipt | 1 | 0 | 1 |
| Landed Cost Voucher | 1 | 0 | 1 |
| Workspace | 1 | 0 | 1 |

**Task has 22 client scripts** (19 enabled Form + 2 enabled List + 1 disabled Form). This is high and a root cause of remaining duplication issues.

---

## 3. Per-DocType Control Catalog

### 3.1 Task — Form View

#### A. Buttons

| Button Label | Script(s) | Condition | Calls Server API | Button Group |
|---|---|---|---|---|
| **Accept / Start Task** | `Task-Accept Start` (desktop+mobile), `Task-Dispatch Packing Usability`, `Task-Other UI Cleanup`, `Task-Account Details UI Cleanup` | Not accepted by current user, status Open/Working | `dispatch_task_accept` | primary |
| **Complete Task** | `Task-Accept Start`, `Task-Other UI Cleanup` | Not new, not Completed/Cancelled | — (sets status, saves) | inline near status |
| **Save** | `Task-Accept Start` | Not new, not completed, form dirty | — (frm.save) | inline near status |
| **Create Dispatch Case** | `Task-Create Dispatch Case Items`, `Task-Product Lines Display` (duplicate!) | Order entry, accepted, no DC linked | `task_create_dispatch_case` (new) / `frappe.client.insert` (old) | primary |
| **Open Dispatch Case** | `Task-Create Dispatch Case Items` | Order entry with DC linked | — (routes to DC) | — |
| **Open Dispatch Case / Items** | `Task-Create Dispatch Case Items` | Dispatch work kinds with DC | — (routes to DC) | Dispatch & Packing Work |
| **Create Dispatch Case / Items** | `Task-Create Dispatch Case Items` | Dispatch work kinds without DC | `task_create_dispatch_case` | Dispatch & Packing Work |
| **Add Selected Product** | `Task-Product Work Area` | Product task, not new | `task_add_dispatch_product` | Products / Dispatch Work |
| **Refresh Products** | `Task-Product Work Area` | Product task, not new | — | Products / Dispatch Work |
| **Scan Product Barcode** | `Task-Product Work Area` | Product task, not new | `dispatch_case_packing_scan`, `task_lookup_product_barcode` | Products / Dispatch Work |
| **+ Add Photos** | `Task-Account Details UI Cleanup` | Account Details kinds, accepted | — (file upload) | inline |
| **Mobile Refresh** | `Task-Accept Start` | Mobile only (<= 768px) | — (frm.reload_doc) | page actions |

#### B. Inline Controls (rendered in form body)

| Control | Script | Where Rendered |
|---|---|---|
| **Packing checkboxes table** | `Task-Product Work Area` | `custom_task_product_summary` HTML field |
| **Product summary table** (packing / returns / restocking / invoice views) | `Task-Product Work Area` | `custom_task_product_summary` HTML field |
| **LOT/Expiry scan dialog** | `Task-Product Work Area` | Popup frappe.ui.Dialog |
| **Returns qty inputs** (returned, lost/damaged) | `Task-Product Work Area` | Inline `<input>` in returns view |
| **Mobile compact/detail toggle for returns** | `Task-Product Work Area` | Button + localStorage toggle |
| **Mobile accept button** | `Task-Accept Start` | Full-width blue button at top (mobile) |
| **Mobile compact action squares** | `Task-Accept Start` | Row of 42px square buttons below accept |
| **Pack task summary card** | `Task-Mobile Form Layout Fix` | Top of form (mobile Pack tasks only) |
| **Account photos preview** | `Task-Account Details UI Cleanup` | Below "+ Add Photos" button |
| **Dashboard comment (DC linkage)** | `Task-Dispatch Packing Usability`, `Task-Create Dispatch Case Items` | frm.dashboard comment area |

#### C. Field Visibility Rules (from client scripts)

| Rule | Script | Task Kinds Affected |
|---|---|---|
| Hide barcode/product fields | `Order entry - barcode scanning section - hide` | Order entry, Delivery, Return Call, Pickup Returns, Invoice, Restocking, Debt Collection, Debt Closure |
| Hide Product Lines child table | `Order entry - barcode scanning section - hide` | Pack, Delivery, Return Call, Pickup Returns, Returns Inspection, Invoice, Restocking, Debt Collection, Debt Closure |
| Rename "Barcode Scanning" section header | `Order entry - barcode scanning section - hide` | Per task_kind: "Task Status & Priority", "Debt amount and status", "Total amount paid and profit" |
| Rearrange form columns | `Order entry - barcode scanning section - hide` | Debt Closure = 3-col, Debt Collection = 2-col, others = compact |
| Hide product work section | `Task-Account Details UI Cleanup` | Account Details: Entry/Processing |
| Hide product work section | `Task-Other UI Cleanup` | Other: Entry/Processing |
| Show `custom_next_task_assign_to` | `Task-Inspect Returns Next Assign Visible` | Returns processing / verification |
| Show `custom_next_task_assign_to` | `Task-Delivery UI Fix` | Delivery |
| Show `custom_next_task_assign_to` | `Task-Other UI Cleanup` | Other: Entry (hidden for Other: Processing) |
| Hide sidebar (Assign, Tags, Share, Like) | `Task-Accept Start` | All tasks |
| Hide `custom_accepted_by` | `Task-Accept Start` | All tasks |
| Subject always visible | `Task-Header Long Subject Fix` | All tasks |
| Subject not required | `Task-Accept Start`, `Task-Other UI Cleanup`, `Task-Create Dispatch Case Items` | Various |
| Hide driver_handover_note | `Order entry - barcode scanning section - hide` | All tasks (always hidden) |
| Hide team queue fields for Debt Closure | `Order entry - barcode scanning section - hide` | Debt Closure |
| Hide clutter fields on mobile | `Task-Accept Start` | accepted_at, batch_no, unit_price, help boxes |
| Hide fields for Pack mobile view | `Task-Mobile Form Layout Fix` | completed_at, task_kind, custom_assigned_to, custom_accepted_at, subject |

#### D. Field Visibility Rules (from custom field `depends_on`)

Server-side visibility conditions set on the custom fields themselves:

| Field | Shows Only When |
|---|---|
| `purchase_order` | task_kind == "Purchase Approval" |
| `approval_outcome`, `approval_note` | Purchase/Discount/Write-off Approval |
| `delivery_status` | Delivery |
| `pickup_status` | Pickup Returns |
| `return_pickup_driver`, `scheduled_return_date` | Pickup Returns or Return drop-off |
| `new_payment_amount`, `payment_method_dc`, `payment_reference_dc` | Payment Received or Debt Collection |
| `current_debt_amd`, `debt_threshold_amd` | Debt Collection |
| `total_outstanding`, `available_advance_credit`, `custom_total_amount_paid` | Debt Collection or Distribute Payment |
| `open_invoices`, `payment_history` | Debt Collection or Distribute Payment |
| `dispatch_case`, `dispatch_case_status` | Pack, Dispatch, Delivery, Pickup Returns, Return drop-off, Returns Inspection, Restocking, Invoice, Discount Approval |
| `sales_invoice` | Invoice, Debt Collection, Payment Received, Distribute Payment, Returns Inspection |
| `payment_entry` | Payment Received, Distribute Payment, Debt Collection |
| `custom_case_profit` | Debt Closure Approval |
| `custom_product_lines` | NOT Order entry |
| `custom_task_scan_barcode`, `custom_task_scan_qty`, etc. | NOT Debt Collection |
| `other_items`, `other_budget`, `other_supplier` | Other |
| `custom_next_task_assign_to` | Order entry, Pack, Delivery, Return Call, Other: Entry, Other: Processing, Pickup Returns, Returns processing |
| `custom_account_photos` | **task_kind == "Account details"** (stale — never matches, see [Section 8.3](#83-custom_account_photos-depends_on-uses-stale-task-kind)) |

### 3.2 Task — List View

| Feature | Script |
|---|---|
| Hide name column | `Task-Team Queue` |
| QuickEntryForm override | `Task-Team Queue` |
| Team queue refresh (reload list after accept) | `Task-Team Queue` |
| Task toggle filter (My Tasks / All / Completed) | `Global-Mobile Back Button List` |
| Mobile back button (FAB) | `Global-Mobile Back Button List` |
| Mobile refresh button | `Global-Mobile Back Button List` |
| CSS: page actions sizing | `Global-Mobile Back Button List` |

### 3.3 Dispatch Case — Form View

| Feature | Script |
|---|---|
| Hide customer, client_location_warehouse, notes | `Dispatch Case-Form` |
| Items edit lock (approver emails toggle) | `Dispatch Case-Form` |
| return_expected checkbox orange styling | `Dispatch Case-Form` |
| Mobile: hide scan/tasks/payment/SE sections | `Dispatch Case-Form` |
| Scan Packing Barcode button + row indicators | `Dispatch Case-Packing Scan` |
| Packing problem alert banner | `Dispatch Case-Packing Problem Alerts` |
| Price column hide/show for roles | `Dispatch Case-Price Visibility` |
| Simplify form for Order Creation | `Dispatch Case-Simplify for Order Creation` |
| Products / Packing button group | `Dispatch Case-Products Button` |
| Submitted DC lock | `Dispatch Case-Lock Submitted` |
| Item code string guard (clean whitespace) | `Dispatch Case-Item Code String Guard` |
| Template auto-fill on `custom_select_surgical_kit_template` change | `Dispatch Case-Template Auto Fill` |

### 3.4 Dispatch Case Item — Form View

| Feature | Script |
|---|---|
| Auto-fill item_name from item_code | `Dispatch Case Item-Auto Fill Item Name` |

### 3.5 Purchase Receipt — Form View

| Feature | Script |
|---|---|
| GS1 barcode parsing (scan_barcode → batch, expiry, lot, mfg date) | `GS1 Barcode Parser` |
| Second-scan workflow for items requiring LOT | `GS1 Barcode Parser` |
| FEFO warning popup for short-expiry items | `GS1 Barcode Parser` |

### 3.6 Landed Cost Voucher — Form View

| Feature | Script |
|---|---|
| Pre-fill Import Duty button | `LCV-import-duty-prefill` |

### 3.7 Workspace — Form View

| Feature | Script |
|---|---|
| Mobile workspace simplification (hide sidebar, restyle shortcuts) | `Workspace` |

---

## 4. Server API Endpoints Called by UI

These are Server Script API endpoints (script_type = "API") called by client scripts:

| Endpoint | Server Script Name | Disabled | Called By |
|---|---|---|---|
| `dispatch_task_accept` | dispatch_task_accept | 0 | Task-Accept Start, Task-Dispatch Packing Usability, Task-Other UI Cleanup, Task-Account Details UI Cleanup |
| `task_create_dispatch_case` | task_create_dispatch_case | 0 | Task-Create Dispatch Case Items |
| `task_add_dispatch_product` | task_add_dispatch_product | 0 | Task-Product Work Area |
| `task_lookup_product_barcode` | task_lookup_product_barcode | 0 | Task-Product Work Area |
| `task_mark_item_packed` | task_mark_item_packed | 0 | Task-Product Work Area |
| `task_mark_items_packed_batch` | task_mark_items_packed_batch | 0 | Task-Product Work Area |
| `task_update_return_item_quantities` | task_update_return_item_quantities | 0 | Task-Product Work Area |
| `dispatch_case_packing_scan` | dispatch_case_packing_scan | 0 | Dispatch Case-Packing Scan, Task-Product Work Area |
| `task_list_filtered` | task_list_filtered | 0 | Global-Mobile Back Button List |
| `perm_disable_batch_expiry_dbset` | perm_disable_batch_expiry_dbset | 0 | **No client caller** — admin utility |
| `disable_all_item_batch_serial_for_now` | disable_all_item_batch_serial_for_now | 0 | **No client caller** — admin utility |

> Note: `task_mark_item_packed`, `task_mark_items_packed_batch`, and `task_update_return_item_quantities` were previously only called by `Task-Packing Checkboxes`. After the merge, they are called by `Task-Product Work Area`.

---

## 5. Custom Fields Driving UI

### 5.1 Always-Hidden Fields (hidden=1 in field definition)

| Field | Fieldtype | Purpose |
|---|---|---|
| `task_access_policy` | Link | Internal policy lookup — set by before_save |
| `dispatch_group_id` | Data | Internal grouping — never shown to users |
| `driver_handover_note` | Small Text | Also hidden by client script. Effectively dead. |
| `custom_account_details_section` | Section Break | `depends_on: "__never_show_account_details_documents__"` — permanently hidden |
| `custom_account_details_entry_task` | Link | Internal link — never shown |
| `custom_packing_scan_barcode` (DC) | Data | Hidden, used programmatically by packing scan |

### 5.2 Read-Only Fields (computed/auto-populated)

| Field | Fieldtype | Purpose |
|---|---|---|
| `completed_at` | Datetime | Auto-set by before_save when status -> Completed |
| `custom_accepted_by` | Link (User) | Set by dispatch_task_accept API |
| `custom_accepted_at` | Datetime | Set by dispatch_task_accept API |
| `dispatch_case_status` | Data | Mirrors DC status |
| `custom_case_profit` | Currency | Computed on Debt Closure |
| `custom_total_amount_paid` | Currency | Computed on Debt Collection |
| `total_outstanding` | Currency | Computed |
| `available_advance_credit` | Currency | Computed |
| `custom_task_product_summary` | HTML | Rendered by `Task-Product Work Area` |
| `custom_task_scan_result` | Small Text | Set by scan logic |
| `custom_task_product_warning` | Small Text | Set by product work area |

### 5.3 Notable Dispatch Case Custom Fields

| Field | Type | Purpose |
|---|---|---|
| `custom_packing_problem_status` | Select | No Problem/Problem Open/Problem Reviewed |
| `custom_packing_problem_summary` | Small Text | Read-only summary of packing issues |
| `allow_items_edit` | Check | Approvers toggle to unlock case_items grid |
| `profit` | Currency | Read-only computed profit |
| `custom_select_surgical_kit_template` | Link | Links to Surgical Kit Template for auto-fill |

### 5.4 Notable Dispatch Case Item Custom Fields

| Field | Type | Purpose |
|---|---|---|
| `custom_packing_status` | Select | Pending/Partial/Complete/Over Scanned/Problem |
| `custom_scanned_qty` | Float | Set by packing scan |
| `custom_remaining_qty` | Float | Read-only computed |
| `custom_problem_reason` | Select | Missing Item/Wrong Item/Damaged/Expired/Batch Problem/Qty Shortage/Other |

---

## 6. Mobile vs Desktop Differences

### 6.1 Mobile Detection

All scripts use `window.innerWidth <= 768` for mobile detection. No user-agent sniffing.

### 6.2 Mobile-Only UI Elements

| Element | Script | Description |
|---|---|---|
| **Floating back button** | `Global-Mobile Back Button List`, `Global-Mobile Back Button`, `Task-Accept Start` | Blue 56px FAB at bottom-left |
| **Inline accept button** | `Task-Accept Start` | Full-width blue button at top of form (replaces header button) |
| **Compact action squares** | `Task-Accept Start` | 42px square buttons in a row below accept |
| **List refresh button** | `Global-Mobile Back Button List` | Circular refresh button in page actions |
| **Pack summary card** | `Task-Mobile Form Layout Fix` | Shows subject/DC/status/customer at top |
| **Scroll to top** | `Task-Mobile Form Layout Fix` | Auto-scrolls to top on Pack task load |
| **Returns compact/detail toggle** | `Task-Product Work Area` | Toggle between compact table and card layout (persisted in localStorage) |

### 6.3 Mobile-Hidden Elements

| Hidden on Mobile | Script |
|---|---|
| Desktop header custom buttons | `Task-Accept Start` |
| Timeline/activity section | `Task-Accept Start` |
| Packing scan fields, tasks section, payment section, SE section on DC | `Dispatch Case-Form` |
| accepted_at, batch_no, unit_price, help boxes on Task | `Task-Accept Start` |
| completed_at, task_kind, custom_assigned_to, subject on Pack tasks | `Task-Mobile Form Layout Fix` |

### 6.4 Mobile CSS Injections

| CSS ID | Script | Scope |
|---|---|---|
| `#mobile-global-css` | `Global-Mobile Back Button List` | Page actions sizing, image orientation |
| `#task-accept-start-mobile-css` | `Task-Accept Start` | Form layout, button visibility, section hiding |
| `#task-delivery-ui-fix-css` | `Task-Delivery UI Fix` | Button wrapping for Delivery tasks |
| `#task-subject-field-visibility-fix` | `Task-Header Long Subject Fix` | Subject field always visible |
| `#packing-checklist-css` | `Dispatch Case-Packing Scan` | Row background colors for packing status |
| (inline `<style>`) | `Task-Mobile Form Layout Fix` | Extensive Pack task mobile layout (~100 CSS rules) |

---

## 7. Duplicates and Conflicts

### 7.1 Mobile Back Button — Triple Implementation

| Script | Mechanism | Creates Element |
|---|---|---|
| `Task-Accept Start` | setInterval on form refresh | `#mobile-back-btn` |
| `Global-Mobile Back Button` | Event listeners (popstate, hashchange, resize, click), clears interval, sets `_mobileBackInterval` to string `'global-mobile-back-button-stable'` | `#mobile-back-btn` |
| `Global-Mobile Back Button List` | setInterval(300ms), guards with `if (window._mobileBackInterval) return` | `#mobile-back-btn` |

All three target the same DOM element. The button itself works (since they check for existing `#mobile-back-btn` before creating), but there's unnecessary complexity and race-condition risk from the conflicting interval/event management.

### 7.2 Accept Button — Quadruple Implementation

| Script | Condition | Type |
|---|---|---|
| `Task-Accept Start` | Operational task_kinds, not accepted | Desktop: `frm.add_custom_button` / Mobile: inline HTML |
| `Task-Dispatch Packing Usability` | Not Account Details, not accepted | `frm.add_custom_button` (made primary) |
| `Task-Other UI Cleanup` | Other: Entry/Processing, not accepted | `frm.add_custom_button` (made primary) |
| `Task-Account Details UI Cleanup` | Account Details: Entry/Processing, not accepted | `frm.add_custom_button` (made primary) |

**On Pack tasks**, at least `Task-Accept Start` and `Task-Dispatch Packing Usability` both try to add the button. `Task-Accept Start` checks `!frm.page.btn_primary_dark` to avoid duplicating the inline mobile version, but the `frm.add_custom_button` calls can still duplicate.

### 7.3 Account Details Cleanup — Duplicated Across Scripts

The `Task-Accept Start` script **starts with** `function account_details_entry_ui_cleanup(frm)`. This function also exists in `Task-Account Details UI Cleanup`. The `Task-Accept Start` script appears to have had the Account Details cleanup code concatenated into it — likely an accidental merge.

### 7.4 Complete Task Button — Double Implementation

| Script | Mechanism |
|---|---|
| `Task-Accept Start` | Renders `#complete-task-btn` inline near status field |
| `Task-Other UI Cleanup` | Renders `#complete-task-btn` via `task_restore_status_priority_complete_all` |

Both use the same `id="complete-task-btn"`, so the second one that runs will add a duplicate unless the first already placed one. The `Task-Other UI Cleanup` version also renders for ALL task types (it calls `task_restore_status_priority_complete_all` from the main refresh), not just Other tasks.

### 7.5 `frappe.listview_settings['Task']` — Multiple Overwriters

| Script | What It Does | View |
|---|---|---|
| `Task-Team Queue` | Sets `.hide_name_column`, overrides `.refresh`, defines QuickEntryForm | List |
| `Global-Mobile Back Button List` | Overrides `.onload` with toggle filter + refresh button + mobile back button | List |

The two enabled scripts use different hooks (`.refresh` vs `.onload`) so they don't directly conflict. Both attempt to gracefully preserve existing handlers via `_origRefresh` / `_origOnload` variables.

---

## 8. Misconfigurations

### 8.1 `Task-Product Lines Display` — Enabled/Disabled Mismatch

- **Schema (deployed):** `enabled: 1` (last modified 2026-07-21)
- **Work file header:** `// Enabled: 0 // DISABLED: Superseded by Task-Create Dispatch Case Items.js`

The work file states it's superseded and uses the **wrong** approach (`frappe.client.insert` with hardcoded warehouse `"Main - Inmed"` instead of the server-side `task_create_dispatch_case` API). But it remains **enabled on the test server**, meaning users may see a duplicate "Create Dispatch Case" button from this script alongside the correct one from `Task-Create Dispatch Case Items`.

### 8.2 `Dispatch Case-Item Code String Guard` — Wrong DocType Registration

Note: The previous audit referenced a script called `Dispatch Case-Item Code Toggle`. That script no longer exists in the schema. The current `Dispatch Case-Item Code String Guard` (enabled) is correctly registered on Dispatch Case and performs whitespace cleanup on item_code changes. No misconfiguration.

### 8.3 `custom_account_photos` — depends_on Uses Stale Task Kind

The custom field `custom_account_photos` (Table, label "Photos") has:
```
depends_on: eval:doc.task_kind === "Account details"
```

The actual task_kind options are `"Account Details: Entry"` and `"Account Details: Processing"` (capital D, with colon). The singular `"Account details"` does not exist in the Select options. This field's server-side visibility condition never matches. (The client-side `Task-Account Details UI Cleanup` script handles visibility separately.)

### 8.4 `driver_handover_note` — Double Hidden

This field is:
- `hidden: 1` (in custom field definition)
- Also hidden by `Order entry - barcode scanning section - hide` (client script always hides it)

Redundant but harmless.

### 8.5 `custom_account_details_section` — Permanently Hidden

This Section Break has:
- `hidden: 1`
- `depends_on: eval:doc.task_kind === "__never_show_account_details_documents__"`

The `depends_on` condition is intentionally never true. This section is effectively dead. It was disabled in favor of the client-script-driven Account Details UI.

---

## 9. Disabled / Stale / Superseded Scripts

| Script | Status | Why |
|---|---|---|
| `Task-Packing Checkboxes` | **Disabled** | Merged into `Task-Product Work Area` (2026-08-31). All packing, returns, restocking, and invoice rendering functions moved to the unified script. |
| `Task-Product Lines Display` | **Should be disabled, is enabled** | Superseded by `Task-Create Dispatch Case Items`. Uses wrong approach (client-side insert with hardcoded warehouse). |

---

## 10. Hardcoded Values

### 10.1 Hardcoded Email Lists

| Script | Constant | Emails |
|---|---|---|
| `Dispatch Case-Form` | `APPROVER_EMAILS` | `levonaghinyan77@gmail.com`, `vahe.muselimyan@gmail.com`, `ghahramanyann@gmail.com`, `karapetyansev@gmail.com` |

This should use role-based checks instead of hardcoded emails. The script does fall back to role checks (`Ops - Directors`, `System Manager`), but the email list takes priority.

### 10.2 Hardcoded Warehouse

| Script | Value | Issue |
|---|---|---|
| `Task-Product Lines Display` (enabled!) | `"Main - Inmed"` | Wrong warehouse for `client_location_warehouse` on new Dispatch Case |

### 10.3 Hardcoded CSS Values

Multiple scripts inject CSS with hardcoded breakpoints (`768px`), colors (`#1976d2`, `#e74c3c`), and sizing. Not configurable.

### 10.4 Hardcoded Task Kind Strings

Every layout script contains hardcoded task_kind string comparisons (e.g., `"Pack / prepare items"`, `"Order entry"`). If a task_kind name changes, all scripts must be updated manually.

---

## 11. CSS Injections Inventory

| ID / Type | Script | Scope | Persists? |
|---|---|---|---|
| `#mobile-global-css` | `Global-Mobile Back Button List` | Global page-actions sizing | Yes (once per session) |
| `#task-accept-start-mobile-css` | `Task-Accept Start` | Task form mobile layout | Recreated each refresh |
| `#task-delivery-ui-fix-css` | `Task-Delivery UI Fix` | Delivery task button wrapping | Created once |
| `#task-subject-field-visibility-fix` | `Task-Header Long Subject Fix` | Subject field visibility | Created once |
| `#packing-checklist-css` | `Dispatch Case-Packing Scan` | Row background colors for packing status | Created once |
| inline `<style>` | `Task-Mobile Form Layout Fix` | Extensive Pack task mobile layout (~100 rules) | Recreated each refresh |
| inline via `.css()` | `Dispatch Case-Form` | return_expected checkbox styling | Each refresh |
| inline via `.cssText` | `Global-Mobile Back Button`, `Global-Mobile Back Button List`, `Task-Accept Start` | Mobile back button FAB | Each creation |

**Total: 5 named `<style>` elements + 3 inline CSS injections across 8 scripts.**

---

## 12. Recommendations

### Immediate Actions

1. **Disable `Task-Product Lines Display` on the server** — It's superseded and the work file already marks it disabled. The schema disagrees.

2. **Consolidate Accept button** — Choose one script to own the Accept button. Currently 4 scripts add it with slightly different conditions.

3. **Consolidate mobile back button** — Designate one script as the owner. Remove back-button code from the other two.

### Medium-Term

4. **Replace hardcoded email lists with role checks** — `Dispatch Case-Form` APPROVER_EMAILS.

5. **Fix `custom_account_photos` depends_on** — Update to match actual task_kind values, or remove if client script handles visibility.

6. **Reduce Task client script count** — 22 scripts on one DocType is excessive. Consolidate related scripts:
   - Merge `Task-Accept Start` + `Task-Dispatch Packing Usability` + `Task-Lock Unaccepted` + `Task-Lock Completed` into one "Task Core" script
   - Merge `Global-Mobile Back Button` + `Global-Mobile Back Button List` + `Task-Mobile Form Layout Fix` into one "Task Mobile" script
   - Merge `Task-Other UI Cleanup` + `Task-Account Details UI Cleanup` + `Order entry - barcode scanning section - hide` into one "Task Layout" script

7. **Delete disabled `Task-Packing Checkboxes`** — It's fully merged and no longer needed. Keeping it just adds noise.

### Long-Term

8. **Extract task_kind strings into a config** — Every layout script hardcodes task_kind comparisons. A shared config object would reduce maintenance.

9. **Establish CSS management** — 5+ injected `<style>` elements is fragile. Consider a single CSS client script.

---

*End of audit.*
