# Task Form Header & Layout Customization Audit

**Date:** 2026-08-31  
**Scope:** All client scripts in `deploy/test/work/client/` that affect the page header, sub-header, navigation bars, summary cards, or CSS layout of Task form pages.

---

## Quick Reference: What Each Task Kind Sees

| Task Kind | Frappe Title Bar | Sub-Header Bar | Summary Card | Subject in Body | Bottom Actions | Special CSS |
|-----------|-----------------|----------------|--------------|-----------------|----------------|-------------|
| **Order Entry** | Visible (task name + status) | Back + Refresh | None | Hidden | Accept / Complete | None |
| **Pack / Prepare Items** | **HIDDEN** (title + buttons) | Back + Refresh + Products + Open DC | **Yes** (name, DC, status, customer) | Hidden | Accept / Complete | ~50 special rules |
| **Delivery** | Visible (wrapped buttons) | Back + Refresh + Open DC | None | Visible | Accept / Complete | Button wrap CSS |
| **Dispatch picking / hand-off** | Visible | Back + Refresh + Products + Open DC | None | Visible | Accept / Complete | None |
| **Pickup Returns** | Visible | Back + Refresh + Products + Open DC | None | Visible | Accept / Complete | None |
| **Returns processing** | Visible | Back + Refresh + Products + Open DC | None | Visible | Accept / Complete | None |
| **Returns restocking** | Visible | Back + Refresh + Products + Open DC | None | Visible | Accept / Complete | None |
| **Invoice preparation** | Visible | Back + Refresh + Products + Open DC | None | Visible | Accept / Complete | None |
| **Return Call** | Visible | Back + Refresh | None | Visible | Accept / Complete | None |
| **Debt Collection** | Visible | Back + Refresh | None | Visible | Accept / Complete | None |
| **Debt Closure Approval** | Visible | Back + Refresh | None | Visible | Accept / Complete | None |
| **Discount Approval** | Visible | Back + Refresh + Products + Open DC | None | Visible | Accept / Complete | None |
| **Purchase Approval** | Visible | Back + Refresh | None | Visible | Accept / Complete | None |
| **Write-off Approval** | Visible | Back + Refresh | None | Visible | Accept / Complete | None |
| **Account Details: Entry** | Visible | Back + Refresh | None | Visible (not req'd) | Accept / Complete | Photos box |
| **Account Details: Processing** | Visible | Back + Refresh | None | Visible (not req'd) | Accept / Complete | Photos box |
| **Other: Entry** | Visible | Back + Refresh | None | Visible ("Task Name") | Accept / Complete | None |
| **Other: Processing** | Visible | Back + Refresh | None | Visible ("Task Name") | Accept / Complete | None |

> All mobile-only. Desktop always uses standard Frappe header + `frm.add_custom_button()`.

---

## Scripts That Modify Header/Layout (Ranked by Impact)

### 1. Task-Mobile Form Layout Fix (`Task-Mobile Form Layout Fix.js`)
**Enabled: Yes | Scope: Pack tasks only (mobile)**

The **most aggressive** header modifier. Only activates for `task_kind === 'Pack / prepare items'`.

**What it does:**
- Adds `task-mobile-pack-clean` class to `<body>`
- **Hides** `.page-head .title-area` and `.page-head .title-text` (display:none)
- Squeezes all header buttons to 38x38px icon-only squares
- Hides `#mobile-back-btn` (the old floating circle)
- Creates a **summary card** (`.task-mobile-pack-summary`) at top of form body with:
  - Task name (bold, 16px)
  - Dispatch Case + Status + Customer (muted, 12px)
- Hides subject field with `display:none !important`
- Hides: completed_at, task_kind, custom_assigned_to, custom_accepted_at
- CSS: `#task-mobile-form-layout-fix-style` (~100 rules)

**This is the primary cause of the Pack task's unique header appearance.**

### 2. Task-Action Buttons (`Task-Action Buttons.js`)
**Enabled: Yes | Scope: All tasks (mobile)**

**What it does to header area:**
- Injects `#task-subheader` bar after `.page-head` with:
  - Left: Back (arrow) + Refresh buttons
  - Right: Products dropdown + Open DC button (contextual)
- Injects `#task-bottom-actions` floating bar at bottom with:
  - Accept / Start Task button (if not accepted)
  - Create Dispatch Case button (if needed)
  - Complete button (if accepted)
- Desktop: adds buttons via `frm.add_custom_button()` to standard header

### 3. Task-Accept Start (`Task-Accept Start.js`)
**Enabled: Yes | Scope: All tasks (mobile)**

**What it does to header area:**
- Injects CSS `#task-mobile-hide-desktop-custom-actions` that hides `.custom-actions` and `.actions-btn-group` on mobile
- Hides "Menu" text label from the "..." dropdown
- Filters dropdown menu items (hides Toggle Sidebar, Email, Reload, Delete, Duplicate, etc.)
- Hides sidebar items: Assign, Tags, Share, Like
- Hides Activity/Timesheet dashboard

### 4. Task-Delivery UI Fix (`Task-Delivery UI Fix.js`)
**Enabled: Yes | Scope: Delivery tasks only (mobile)**

**What it does to header area:**
- Injects CSS `#task-delivery-ui-fix-css`:
  - `.page-actions` flex-wraps with row-gap
  - Buttons get smaller (11px font, 46vw max-width)
  - `.page-head-content` flex-wraps
  - `.title-area` min-width:0, max-width:100%

### 5. Global-Mobile Back Button List (`Global-Mobile Back Button List.js`)
**Enabled: Yes | Scope: All non-Task pages (mobile)**

**What it does to header area:**
- Creates `#mobile-global-subheader` (Back + Refresh) for non-Task pages
- **Explicitly skips** Task form pages (Task-Action Buttons handles those)
- Injects `#mobile-global-css`:
  - `.page-actions` gap/wrapping
  - Hides `#mobile-global-subheader` on Task forms
  - Hides `#mobile-back-btn` on Task forms

### 6. Task-Header Long Subject Fix (`Task-Header Long Subject Fix.js`)
**Enabled: Yes | Scope: All tasks**

Does NOT modify the header directly. Ensures the subject field is visible in the form body (not the title bar). Removes any `.task-visible-subject-banner`.

### 7. Order entry - barcode scanning section - hide (`Order entry - barcode scanning section - hide.js`)
**Enabled: Yes | Scope: All tasks**

Does NOT modify the header. Renames section headers in the form body and rearranges columns. E.g., "Barcode Scanning (Optional)" -> "Task Status & Priority" for Order Entry.

### 8. Task-Account Details UI Cleanup (`Task-Account Details UI Cleanup.js`)
**Enabled: Yes | Scope: Account Details tasks**

Hides "Actions" and "Products / Dispatch Work" buttons from the header dropdowns. Does not modify header structure.

### 9. Task-Other UI Cleanup (`Task-Other UI Cleanup.js`)
**Enabled: Yes | Scope: Other: Entry/Processing tasks**

Does NOT modify the header directly. Renames section "Status and Priority", relabels subject as "Task Name".

---

## CSS Injection Chain (Header-Related)

When a Task form loads on mobile, these style blocks are injected in order:

1. `#mobile-global-css` (Global-Mobile Back Button List) -- always present
2. `#task-mobile-hide-desktop-custom-actions` (Task-Accept Start) -- hides custom-actions
3. `#task-mobile-form-layout-fix-style` (Task-Mobile Form Layout Fix) -- Pack-only rules
4. `#task-delivery-ui-fix-css` (Task-Delivery UI Fix) -- Delivery-only rules
5. `#task-subject-field-visibility-fix` (Task-Header Long Subject Fix) -- subject field

**On a Pack task, all 5 are active.** The Pack-specific rules override general rules via the `body.task-mobile-pack-clean` selector prefix.

---

## DOM Injection Points (Header Area)

After the scripts run, the DOM from top to bottom looks like:

```
.page-head                              <- Frappe default (hidden title on Pack)
  .page-head-content
    .title-area                         <- HIDDEN on Pack tasks
    .page-actions
      .standard-actions                 <- Save button (if applicable)
      .custom-actions                   <- HIDDEN on mobile (all tasks)
      .menu-btn-group                   <- "..." menu (filtered items)

#task-subheader                         <- Injected by Task-Action Buttons
  [<- Back] [Refresh]    [Products v] [Open DC]

.task-mobile-pack-summary               <- Injected by Task-Mobile Form Layout Fix (Pack only)
  Task name (bold)
  DC | Status | Customer (muted)

.form-layout                            <- Standard Frappe form body
  ...fields...

#task-bottom-actions                    <- Injected by Task-Action Buttons
  [Accept / Start Task]   [Complete]
```

For **non-Pack tasks**, the `.task-mobile-pack-summary` is absent and `.title-area` is visible.

---

## Identified Inconsistencies

1. **Pack vs. Everything Else**: Pack tasks completely hide the title bar and replace it with a summary card. No other task kind does this.

2. **Order Entry subject hidden, others shown**: Order Entry hides the subject field in the form body (relies on Frappe title bar). Other tasks show subject in form body.

3. **Delivery gets special button wrapping**: Delivery tasks get their own CSS for button wrapping. Other dispatch flow tasks with similar button counts don't.

4. **Sub-header bar contents vary silently**: The "Products" dropdown and "Open DC" button only appear for certain task kinds, but there's no visual indication why some tasks have more sub-header buttons than others.

5. **Summary card metadata varies**: The Pack summary card shows DC + Status + Customer. There's no equivalent info display for other task kinds on mobile.

---

## Unification Options

### Option A: "Pack Header Everywhere" -- Minimal Header + Summary Card for All Tasks

Extend the Pack task's approach (hide title area, show summary card) to all task kinds.

- Remove `is_pack_task` gate in `Task-Mobile Form Layout Fix`
- Summary card shows task name + status + assigned_to + customer (where applicable)
- All tasks get the same compact header on mobile
- Desktop keeps standard Frappe header

**Pros**: Most consistent mobile UX. Pack tasks already prove it works.  
**Cons**: More work. Users of non-Pack tasks may not like losing the Frappe title.

### Option B: "Standard Header Everywhere" -- Remove Pack's Special Treatment

Remove the Pack task's title-hiding behavior. Let all tasks use the standard Frappe header.

- Remove Pack-specific CSS rules that hide `.title-area` and `.title-text`
- Remove the `.task-mobile-pack-summary` card
- Keep sub-header bar and bottom floating actions
- Unify `Task-Mobile Form Layout Fix` to apply to ALL tasks (tabs scrolling, form padding)

**Pros**: Simplest. All tasks look the same in the header. Less CSS.  
**Cons**: Pack tasks lose the summary card. Title may be cramped on mobile.

### Option C: "Unified Task Header Component" -- New Shared Header Layout

Create a single script (`Task-Unified Header`) that owns all header behavior for ALL task kinds.

- Replaces header code from: Mobile Form Layout Fix, Action Buttons (sub-header), Accept Start (CSS hiding), Delivery UI Fix (CSS wrapping)
- On mobile, for ALL tasks: Frappe title bar + sub-header + optional info row + bottom actions
- On desktop: standard Frappe header + custom buttons
- CSS consolidated into one `<style>` block

**Pros**: Clean separation. One script owns header. Easy to maintain.  
**Cons**: Most work. Careful migration needed.

### Option D: "Two-Tier Header" -- Standard Header + Universal Info Bar

Keep Frappe header as-is for all tasks. Add a universal info bar below it.

- Keep `Task-Action Buttons` sub-header for all tasks
- Add universal info bar below sub-header for ALL tasks: task name (bold) + status badge + customer + DC link
- Remove Pack's title-hiding behavior
- Remove `Task-Delivery UI Fix`

**Pros**: All tasks get the same info bar. No task-kind-specific header hacks. Incremental.  
**Cons**: Adds one more bar to the mobile header stack.

### Recommendation

**Option D** is the most practical near-term improvement:
1. Remove Pack-specific header hiding from `Task-Mobile Form Layout Fix`
2. Generalize the summary card into a universal info row in the `Task-Action Buttons` sub-header
3. Remove `Task-Delivery UI Fix` (button-wrapping becomes unnecessary)
4. Result: All tasks get identical header structure

This reduces 4 competing header scripts to 2 (Frappe default + Task-Action Buttons).
