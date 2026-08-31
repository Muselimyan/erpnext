# 20 — Custom Buttons and Actions

**Date:** 2026-08-31
**Status:** Current (post-audit consolidation)
**Related:** `docs/custom-controls-audit.md` (full audit), `deploy/test/work/client/Task-Action Buttons.js` (source of truth for Task actions)

---

## 1. Architecture Overview

### Problem we solved

Before consolidation, Task action buttons (Accept, Complete, Create DC, Save) were created by **4+ separate scripts** independently. This caused:

- Duplicate buttons appearing on the same form
- Race conditions between scripts rendering the same control
- Mobile and desktop diverging on which buttons were shown
- No single place to reason about "what actions are available in this state?"

### Current design

All Task action buttons are now owned by **one script**: `Task-Action Buttons.js`. It is the single source of truth for what actions appear and when.

| Layer | Script | Responsibility |
|---|---|---|
| **Task actions** | `Task-Action Buttons.js` | Accept, Complete, Create DC, Open DC, Products dropdown, mobile sub-header, mobile bottom floating buttons, desktop header buttons |
| **Task UI cleanup** | `Task-Accept Start.js` | Field visibility, sidebar hiding, mobile CSS, menu cleanup. No buttons. |
| **Global mobile nav** | `Global-Mobile Back Button List.js` | Global mobile sub-header (Back + Refresh) on every non-Task page. Task list toggle filters. |
| **Old global back** | `Global-Mobile Back Button.js` | **Disabled.** Replaced by the global sub-header above. |

### Rendering flow

```
form.refresh
  └─ Task-Action Buttons.js → refresh(frm)
       ├─ tab_dashboard_comments(frm)     — info banners
       ├─ tab_render_subheader(frm)       — mobile: Back, Refresh, Products, Open DC
       ├─ tab_render_bottom_actions(frm)  — mobile: floating Accept / Complete / Create DC
       └─ tab_render_desktop_buttons(frm) — desktop: header custom buttons
```

Every render starts by removing stale controls (`$("#task-subheader").remove()`, `$("#task-bottom-actions").remove()`, Frappe clears custom buttons on refresh). Then it computes the valid action set from current state and renders only what applies.

---

## 2. Action Buttons — Complete Reference

### 2.1 Accept / Start Task

| Property | Value |
|---|---|
| **Where** | Mobile: floating bottom bar. Desktop: header custom button (primary). |
| **Condition** | Status is Open or Working. Task not accepted by current user. |
| **Behavior** | If form is dirty or new → save first, then call API. Otherwise call API directly. |
| **Server API** | `dispatch_task_accept` |
| **After success** | `frm.reload_doc()` — form refreshes to show accepted state, buttons re-render. |
| **Error handling** | `frappe.call` with `freeze: true`. Errors shown by Frappe's standard dialog. |

### 2.2 Complete

| Property | Value |
|---|---|
| **Where** | Mobile: green floating button at bottom-right. Desktop: header custom button. |
| **Condition** | Task is accepted by current user (or admin). Status is not Completed/Cancelled. Not a new task. |
| **Behavior** | Sets `status = "Completed"` and `completed_on` on the local doc, then saves everything in one call. |
| **Server call** | `frappe.call({ method: "frappe.desk.form.save.savedocs" })` — calls the save endpoint directly instead of `frm.save()`. |
| **Why not `frm.save()`** | `frm.save()` has two problems: (1) its promise does not reliably reject on server validation errors (`frappe.throw`), leaving the button stuck on "Completing..."; (2) its argument signature varies across Frappe versions, causing `toTitle` crashes. |
| **After success** | `frm.reload_doc()` — clean server state loaded, buttons re-render for completed status. |
| **After error** | Restores original `status` and `completed_on` on the local doc. Restores button text to "Complete" and re-enables it. Instant — no timeout. |
| **Freeze** | `freeze: true, freeze_message: "Completing..."` — prevents double-clicks and gives visual feedback. |

**Known gap (future work):** If the server will reject completion for a known reason (e.g., "attach photo first" for Pack tasks), the Complete button still appears. Ideally the button should be hidden or disabled when prerequisites are not met. See Section 5.

### 2.3 Create Dispatch Case

| Property | Value |
|---|---|
| **Where** | Mobile: blue floating button. Desktop: header custom button (primary). |
| **Condition** | Task accepted by current user. Task kind needs a DC (Order entry or dispatch kinds). No DC linked yet. |
| **Pre-check** | `frm.doc.customer` must be set — shows message if missing. |
| **Behavior** | If form is dirty → save first, then call API. Otherwise call API directly. |
| **Server API** | `task_create_dispatch_case` |
| **After success** | `frm.reload_doc()`. |

### 2.4 Open Dispatch Case

| Property | Value |
|---|---|
| **Where** | Mobile: sub-header button ("Open DC"). Desktop: header custom button. |
| **Condition** | `frm.doc.dispatch_case` exists (any status, any acceptance state). |
| **Behavior** | Routes to `Form/Dispatch Case/{name}`. No server call. |

### 2.5 Products Dropdown (mobile sub-header)

| Property | Value |
|---|---|
| **Where** | Mobile sub-header only. |
| **Condition** | Task is a product task (has DC or task kind is in product kinds list). Accepted by current user. |
| **Items** | Add Selected Product, Refresh Products, Scan Product Barcode. |
| **Behavior** | Each item calls a function from `Task-Product Work Area.js` if it exists. |

---

## 3. Mobile vs Desktop

### Mobile (width <= 768px)

The mobile layout has three custom control zones:

```
┌─────────────────────────────────┐
│  Page Head (Frappe standard)    │
├─────────────────────────────────┤
│  Sub-header: ← ↻ [Products▾] [Open DC] │  ← tab_render_subheader()
├─────────────────────────────────┤
│                                 │
│  Form body                      │
│                                 │
├─────────────────────────────────┤
│  [Create DC]        [Complete]  │  ← tab_render_bottom_actions()
└─────────────────────────────────┘
```

- **Sub-header** (sticky below page-head): Back, Refresh, Products dropdown, Open DC. Always visible on Task forms.
- **Bottom floating bar** (fixed position): Accept, Create DC, Complete. Shown based on state.
- **Desktop header buttons**: Hidden via CSS (`task_mobile_hide_desktop_custom_actions` in `Task-Accept Start.js`).

### Desktop (width > 768px)

- No sub-header.
- No floating bottom bar.
- All action buttons added to Frappe's standard header custom button area via `frm.add_custom_button()`.
- Accept and Create DC styled as `primary`.

### Global mobile navigation

On **non-Task** mobile pages, `Global-Mobile Back Button List.js` injects a sub-header with Back + Refresh below the page-head. This is suppressed on Task forms (CSS rule: `body[data-route^="Form/Task"] #mobile-global-subheader { display: none !important }`).

---

## 4. State Machine

The button set depends on the task's current state. Here is the decision tree:

```
Is it a new (unsaved) task?
  └─ YES → No action buttons.

Is status Completed or Cancelled?
  └─ YES → Desktop: Open DC only (if DC exists).
           Mobile: sub-header only (Back, Refresh, Open DC).

Is the task NOT accepted by the current user?
  └─ YES → Mobile: "Accept / Start Task" floating button.
           Desktop: "Accept / Start Task" primary button.

Is the task accepted by current user (or admin)?
  └─ YES →
       Needs DC and no DC linked?
         └─ Show "Create Dispatch Case"
       Has DC?
         └─ Show "Open DC" (always)
       Is a product task?
         └─ Show Products dropdown (mobile sub-header)
       Always:
         └─ Show "Complete"
```

### After each action

| Action | What happens to buttons |
|---|---|
| Accept | `frm.reload_doc()` → refresh fires → buttons re-render for accepted state |
| Complete (success) | `frm.reload_doc()` → refresh fires → no action buttons (completed) |
| Complete (error) | Local status restored → button restored to "Complete" immediately |
| Create DC | `frm.reload_doc()` → refresh fires → "Create DC" replaced by "Open DC" |
| Save (Frappe native) | refresh fires → buttons re-render from current state |

---

## 5. Future Work: Pre-flight Completion Checks

**Current gap:** The Complete button appears whenever the task is accepted and not completed, regardless of whether completion prerequisites are met. The server then rejects with an error (e.g., "Attach photo before completing Pack task").

**Planned approach:** Extend `Task Access Policy` to define completion prerequisites per task kind. The client reads these on form load and only shows Complete when all are met. This keeps the policy DocType as the single source of truth (consistent with how roles and teams are already managed).

Example policy additions:
- Pack / prepare items → require `custom_packing_photos` attachment
- Delivery → require `delivery_status == "Delivered"`
- Returns processing → require all `returned_qty` filled

Until implemented, server-side before_save scripts remain the authoritative gate. The Complete button may appear when completion is not yet possible.

---

## 6. Error Handling Philosophy

### Why `frappe.call(savedocs)` instead of `frm.save()`

| Concern | `frm.save()` | `frappe.call(savedocs)` |
|---|---|---|
| Promise rejection on server error | Unreliable — often silently swallows | N/A — uses callback, not promise |
| Error callback | `on_error` param exists but argument signature varies across versions | `error` callback fires reliably |
| Saves dirty fields + status | Yes | Yes (sends full `frm.doc`) |
| Client-side validation | Runs (required fields, validate trigger) | Skipped (server validates) |
| Button state on error | Could get stuck "Completing..." for 30s+ | Restores immediately |

**Trade-off accepted:** We skip client-side validation. Server-side before_save scripts catch everything the client would have caught. The reliability of instant error recovery outweighs the minor UX difference of server-side vs client-side validation messages.

### Other action buttons

Accept and Create DC use `frappe.call` with dedicated server APIs (`dispatch_task_accept`, `task_create_dispatch_case`). These follow the same reliable pattern: `freeze: true`, `callback` for success, Frappe's built-in error dialog for failures. No client-side state mutation needed because these don't modify the form doc.

---

## 7. Script Inventory (buttons-related only)

| Script | Status | Owns Buttons? | Notes |
|---|---|---|---|
| `Task-Action Buttons.js` | **Enabled** | **Yes — all Task action buttons** | Single source of truth |
| `Task-Accept Start.js` | Enabled | No (stripped in redesign) | Retains UI cleanup, CSS, field visibility |
| `Task-Account Details UI Cleanup.js` | Enabled | No | Account Details field visibility |
| `Task-Other UI Cleanup.js` | Enabled | No | General cleanup |
| `Global-Mobile Back Button List.js` | Enabled | Global Back + Refresh sub-header | Also owns Task list toggle filters |
| `Global-Mobile Back Button.js` | **Disabled** | Was: floating back circle | Replaced by global sub-header |
| `Task-Product Work Area.js` | Enabled | Product add/scan/refresh (called by Action Buttons) | Functions invoked from Products dropdown |
| `Task-Create Dispatch Case Items.js` | **Disabled** | Was: Create DC, Open DC buttons | Absorbed into Action Buttons |
| `Task-Dispatch Packing Usability.js` | **Disabled** | Was: Accept button (duplicate) | Absorbed into Action Buttons |
| `Task-Product Lines Display.js` | **Disabled** | Was: Create DC button (duplicate) | Absorbed into Action Buttons |

---

## 8. Deployment

All button scripts deploy via:
```
powershell -ExecutionPolicy Bypass -File deploy\test\scripts\deploy-task-action-buttons.ps1 -Mode Deploy
```

This script updates all related client scripts and disables absorbed ones. After deployment:
```
docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache
powershell -ExecutionPolicy Bypass -File deploy\test\export.ps1
```

Production deployment uses separate scripts under `deploy/prod/` (not yet created for this redesign).
