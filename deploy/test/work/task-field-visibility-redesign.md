# Task Field Visibility Redesign

**Goal:** All custom fields hidden by default on the server. One centralized client script reveals the right fields per task_kind. No DOM surgery. No depends_on for visibility. Clear separation: server = data + validation, client = presentation.

**Approach:** Server sets `hidden=1` on every custom field. Client reads task_kind and state, then calls `frm.toggle_display()` to reveal the correct set. Fields that are not revealed stay hidden — so a new task kind starts with a clean form.

**Status:** Investigation in progress. Each field section below will be filled in with current behavior, proposed behavior, and open questions.

---

## How to read each field section

```
## fieldname — Label
- **Type:** fieldtype | **Options:** (for Select/Link)
- **Current hidden:** 0 or 1 | **Current depends_on:** expression or none
- **Current client script overrides:** which scripts touch this field's visibility
- **Current server-side usage:** which server scripts read/write/validate this field
- **Visible for task kinds (current):** list
- **Visible for task kinds (proposed):** TO DECIDE
- **Approach:** visibility-only / needs behavioral logic / needs server-side check
- **Decision:** TO DECIDE — client visibility, server visibility, or both?
- **Notes:**
```

---

## Table of Contents

0. [Centralized Task Creation API (`task_create`)](#0-centralized-task-creation-api)
1. [Core Identity](#1-core-identity) — subject, task_kind, completed_at
2. [Assignment and Ownership](#2-assignment-and-ownership) — assigned_to, accepted_by, accepted_at
3. [Customer / Entity](#3-customer--entity) — customer
4. [Dispatch Case](#4-dispatch-case) — dispatch_case, dispatch_group_id
5. [Status Selects](#5-status-selects) — dc_status, payment_status, etc.
6. [Approval](#6-approval) — approval fields, purchase_order
7. [Invoice and Sales](#7-invoice-and-sales) — sales_invoice, sales_order
8. [Payment and Debt](#8-payment-and-debt) — payment_entry, current_debt_amd, etc.
9. [Returns](#9-returns) — return_pickup_driver, scheduled_return_date, next_task_assign_to
10. [Other-Task Fields](#10-other-task-fields) — ~~Other~~ removed, Other: Entry/Processing
11. [Driver / Handover](#11-driver--handover) — ~~driver_handover_note~~ REMOVED
12. [Photo Fields](#12-photo-fields) — photo gallery, account photos
13. [~~Surgery Case~~](#13-surgery-case) — ALREADY DELETED
14. [Product Work Section](#14-product-work-section--centralized) — CENTRALIZED (section, summary, ~~product_lines~~ REMOVED)
15. [Barcode Scanning](#15-barcode-scanning--centralized) — CENTRALIZED (scan fields; Pack + Returns only)
16. [Manual Product Add](#16-manual-product-add--centralized) — CENTRALIZED (add fields; Order entry only)
17. [~~Account Details~~](#17-account-details--remove-entirely) — REMOVE ENTIRELY (use Other: Entry/Processing instead)
18. [Standard Frappe Fields (modified)](#18-standard-frappe-fields-modified)

---

## 0. Centralized Task Creation API

### Goal

One API Server Script (`task_create`) that ALL programmatic task creation goes through. Handles subject defaulting, policy lookup, assignment, duplicate prevention. For manually created tasks (Order entry, Account Details: Entry, Other: Entry), a unified before-save script handles subject defaulting.

### Current state — creation scattered across 7 scripts

| # | Script | Creates | Pattern | After redesign |
|---|---|---|---|---|
| 1 | `Task-after-save-dispatch-flow.py` | Pack, Delivery, Return Call, Pickup Returns, Returns proc., Restocking, Invoice prep, Order entry (rejected discount) | Nested `make_task()` | **MODIFY** — call `task_create` API instead of inline `make_task()` |
| 2 | `Dispatch-Case-after-save.py` | Discount Approval | Inline `frappe.get_doc({...})` | **MODIFY** — call `task_create` API |
| 3 | `Task-after-save-debt-closure.py` | Debt Closure Approval | Inline `frappe.get_doc({...})` | **MODIFY** — call `task_create` API |
| 4 | `Task-after-save-account-details-processing.py` | Acct Det. Processing | Inline `frappe.new_doc("Task")` | **DELETE** — Account Details workflow removed (§17), use Other: Entry/Processing instead |
| 5 | `Task-after-save-other-processing.py` | Other: Processing | Inline `frappe.new_doc("Task")` | **MODIFY** — call `task_create` API |
| 6 | `Payment Entry-after-submit-distribute-payment.py` | Distribute Payment | Inline `frappe.new_doc("Task")` | **MODIFY** — call `task_create` API |
| 7 | `Scheduled-debt-collection.py` | Debt Collection | Inline `frappe.new_doc("Task")` | **MODIFY** — call `task_create` API |

### Current state — subject defaulting in 3 places

| # | Script | What it does | After redesign |
|---|---|---|---|
| 1 | `Task-before-save-auto-subject.py` | If subject empty, set to sequential 5-digit number (e.g., `00142`) | **DELETE** — absorbed into unified before-save subject logic |
| 2 | `Task-Other Entry Default Subject.py` | If Other: Entry/Processing with blank subject, set to kind name | **DELETE** — absorbed into unified before-save subject logic |
| 3 | `Task-Accept Start.js:135-143` | Client-side: reqd=0, hide for Order entry, auto-set to task name | **MODIFY** — remove all subject logic from this script |

### Proposed: `task_create` API Server Script

**Type:** API
**Name:** `task_create`
**Callable as:** `frappe.call("task_create", args)`

**Parameters:**

| Param | Type | Required | Description |
|---|---|---|---|
| `kind` | string | yes | Task kind (e.g., "Pack / prepare items") |
| `subject` | string | no | If blank, auto-generated from kind + customer |
| `customer` | string | no | Customer name |
| `dispatch_case` | string | no | Dispatch Case name |
| `assigned_to` | string | no | If blank, looked up from Task Access Policy default team |
| `source_task` | string | no | Parent task name — checks `custom_next_task_assign_to` for override |
| `description` | string | no | Task description |
| `extra_fields` | dict | no | Any additional field values (e.g., `delivery_status`, `pickup_status`, `sales_invoice`, etc.) |

**Logic:**

```
1. Duplicate check: if dispatch_case provided, check for existing active task
   with same kind + DC. If found, return existing task name (skip creation).

2. Subject default: if no subject provided:
   - If customer: "{kind} - {customer}"
   - Else: "{kind}"

3. Policy lookup: read Task Access Policy for this kind.
   - Set task_access_policy = kind
   - If no assigned_to provided: use policy.default_team_user

4. Assignment override: if source_task provided, check its
   custom_next_task_assign_to. If set, use that instead.

5. Create task:
   - subject, task_kind, task_access_policy, customer, dispatch_case
   - custom_assigned_to = resolved assignee
   - description
   - Any extra_fields
   - status = "Open"
   - insert(ignore_permissions=True)

6. Return: { "task_name": new_task.name, "created": True }
   (or { "task_name": existing, "created": False } if duplicate)
```

### Proposed: unified before-save subject defaulting

Replaces `Task-before-save-auto-subject.py` and `Task-Other Entry Default Subject.py`.

Lives in an existing before-save script (e.g., `Task-before-save-policy.py`) or a new dedicated one.

```
if not doc.subject or doc.subject in ("New Task",):
    if doc.customer:
        doc.subject = (doc.task_kind or "Task") + " - " + str(doc.customer)
    elif doc.task_kind:
        doc.subject = doc.task_kind
    else:
        # Last resort: sequential number (existing fallback)
        result = frappe.db.sql(...)
        doc.subject = str(int(max_num) + 1).zfill(5)
```

This runs for ALL tasks — manually created and programmatically created. The `task_create` API sets subject before insert, so this before-save acts as the safety net.

### Subject patterns after redesign

| Creation method | Subject set by | Example |
|---|---|---|
| Manual (Order entry) | Before-save default (if user left blank) | `Order entry - Medline LLC` |
| Manual (Order entry) | User typed it | `Urgent order for Dr. Smith` |
| Dispatch flow (Pack) | `task_create` API caller | `Pack: Medline LLC (DC-2026-00144)` |
| Dispatch flow (Delivery) | `task_create` API caller | `Deliver: Medline LLC (DC-2026-00144)` |
| Debt Collection | `task_create` API caller | `Debt Collection - Medline LLC` |
| Account Details: Processing | `task_create` API caller | `Account Details: Processing` or custom subject |
| Other: Processing | `task_create` API caller | `Other: Processing` |
| Any task, subject still empty at save | Before-save safety net | `Order entry` or `00143` |

### Scripts impact summary

| Script | Action | What changes |
|---|---|---|
| **NEW: `task_create` API** | **CREATE** | Centralized task creation API |
| `Task-before-save-auto-subject.py` | **DELETE** | Logic absorbed into unified before-save |
| `Task-Other Entry Default Subject.py` | **DELETE** | Logic absorbed into unified before-save |
| `Task-Accept Start.js` | **MODIFY** | Remove lines 135-143 (all subject logic) |
| `Task-Header Long Subject Fix.js` | **ALREADY DISABLED** | No further action |
| `Task-Mobile Form Layout Fix.js` | **ALREADY DISABLED** | No further action |
| `Task-Account Details UI Cleanup.js` | **MODIFY** | Remove subject reqd/visibility lines |
| `Task-Other UI Cleanup.js` | **MODIFY** | Remove subject reqd/visibility lines |
| `Task-after-save-dispatch-flow.py` | **MODIFY** | Replace `make_task()` with `frappe.call("task_create", ...)` |
| `Dispatch-Case-after-save.py` | **MODIFY** | Replace inline creation with `frappe.call("task_create", ...)` |
| `Task-after-save-debt-closure.py` | **MODIFY** | Replace inline creation with `frappe.call("task_create", ...)` |
| `Task-after-save-account-details-processing.py` | **MODIFY** | Replace inline creation with `frappe.call("task_create", ...)` |
| `Task-after-save-other-processing.py` | **MODIFY** | Replace inline creation with `frappe.call("task_create", ...)` |
| `Payment Entry-after-submit-distribute-payment.py` | **MODIFY** | Replace inline creation with `frappe.call("task_create", ...)` |
| `Scheduled-debt-collection.py` | **MODIFY** | Replace inline creation with `frappe.call("task_create", ...)` |
| `Task-before-save-policy.py` (or new) | **MODIFY** | Add unified subject defaulting |

### Open questions

1. Should `task_create` also handle file attachment copying (used by Account Details and Other flows)?
2. Should `task_create` also set `depends_on` relationships (used by Other: Processing)?
3. The dispatch flow's `make_task` also returns the existing task name on duplicate — the API preserves this. But some callers need to know if the task was new or existing (to update DC fields). The `created` boolean handles this.
4. Some creation sites set extra fields after creation (e.g., `exp_end_date` on Return Call from `scheduled_return_date`). The `extra_fields` dict param handles this.

---

## 1. Core Identity

### 1.1 subject — Subject

- **Type:** Data (standard Frappe field, not custom)
- **Current hidden:** 0 | **Current depends_on:** none
- **Current property setter:** reqd=0
- **Current client script overrides:**
  - `Task-Accept Start.js:135` — reqd=0 always
  - `Task-Accept Start.js:140` — hidden for Order entry
  - `Task-Accept Start.js:142` — auto-set to task name for Order entry if empty
  - `Task-Header Long Subject Fix.js:41-46` — force visible always (DISABLED by header unification)
  - `Task-Mobile Form Layout Fix.js:194-198,266-279` — force visible on mobile, then re-hide for Pack (DISABLED by header unification)
  - `Task-Account Details UI Cleanup.js:54-55` — shown, reqd=0 for Account Details
  - `Task-Other UI Cleanup.js:34` — shown, reqd=0 for Other
- **Current server-side usage:** Read by after-save scripts to set subject on downstream tasks. Auto-subject script sets 5-digit number if blank.
- **Visible for task kinds (current):** All except Order entry (hidden). Pack mobile was hidden (now disabled).
- **Visible for task kinds (proposed):** ALL task kinds. Always visible, always editable.
- **Approach:** DECIDED. No client visibility logic needed. Subject is a standard Frappe field — leave hidden=0, reqd=0 (property setter already set). Server before-save handles defaulting if blank. Client script does NOT touch this field at all.
- **Decision:** ALWAYS VISIBLE. Server-side auto-population if blank. Editable by user.

**What changes:**

| Script | Action | Lines affected |
|---|---|---|
| `Task-Accept Start.js` | **MODIFY** | Remove lines 135 (reqd=0), 140-143 (hide + auto-set for Order entry) |
| `Task-Account Details UI Cleanup.js` | **MODIFY** | Remove lines 54-55 (show + reqd=0 for Account Details) |
| `Task-Other UI Cleanup.js` | **MODIFY** | Remove line 34 (show + reqd=0 for Other) |
| `Task-Header Long Subject Fix.js` | **ALREADY DISABLED** | No action (was force-show) |
| `Task-Mobile Form Layout Fix.js` | **ALREADY DISABLED** | No action (was hide for Pack mobile) |
| `Task-before-save-auto-subject.py` | **DELETE** | Absorbed into unified before-save (see Section 0) |
| `Task-Other Entry Default Subject.py` | **DELETE** | Absorbed into unified before-save (see Section 0) |

**Net result:** Zero client scripts touch subject. Server before-save auto-populates if blank. User can type whatever they want. Header title always reflects the subject value.

---

### 1.2 task_kind — Task Kind

- **Type:** Select (custom)
- **Current hidden:** 0 | **Current depends_on:** none
- **Options:** Order accepting, Order entry, Pack / prepare items, Dispatch picking / hand-off, Delivery, Return Call, Return to warehouse (aborted delivery / cancelled order), Pickup Returns, Return drop-off at warehouse, Returns processing / verification, Returns restocking, Invoice preparation / create invoice, Debt Collection, Distribute Payment, Payment Received, Discount Approval, Purchase Approval, Write-off Approval, Account Details: Entry, Account Details: Processing, Other, Other: Entry, Other: Processing, Debt Closure Approval
- **Current client script overrides:**
  - `Task-Mobile Form Layout Fix.js:253` — hidden for Pack on mobile (DISABLED)
  - `Task-Accept Start.js:161` — auto-replace "Order accepting" with "Order entry" on new tasks
- **Current server-side usage:** Read by every server script. Drives Task Access Policy lookup. Never written after creation (except the Order accepting auto-replace on unsaved new tasks).
- **Visible for task kinds (current):** All (was hidden for Pack on mobile, now disabled)
- **Visible for task kinds (proposed):** ALL task kinds. Always visible.
- **Approach:** DECIDED. Visible everywhere, editable on new task, read-only after first save.
- **Decision:** DECIDED
  - **Visible** on all task kinds — no hiding.
  - **Editable** only on new (unsaved) tasks — user selects the kind before first save.
  - **Read-only after first save** — enforced both client-side and server-side.
  - "Order accepting" → "Order entry" auto-replace on new tasks: keep as-is (fires before first save, so compatible with the lock).
  - Manually created kinds: Order entry, Account Details: Entry, Other: Entry, Other — user selects on creation.
  - Programmatically created kinds: `task_create` API sets kind during insert — already locked after that.

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Client** | Read-only after save | `if (!frm.is_new()) frm.set_df_property("task_kind", "read_only", 1);` in centralized visibility script |
| **Server** | Reject changes after creation | `if not doc.is_new() and doc.has_value_changed("task_kind"): frappe.throw("Task Kind cannot be changed after creation.")` in before-save script |

**What changes:**

| Script | Action | Detail |
|---|---|---|
| `Task-Accept Start.js:161-162` | **KEEP** | "Order accepting" → "Order entry" on `frm.is_new()` — fires before lock |
| `Task-Mobile Form Layout Fix.js` | **ALREADY DISABLED** | Was hiding task_kind for Pack on mobile |
| Centralized visibility script (new) | **ADD** | `read_only=1` when `!frm.is_new()` |
| Before-save script (existing) | **ADD** | Server-side guard rejecting task_kind changes on saved docs |

**Notes:** No admin escape hatch. Task kind is an architectural invariant — it drives policy lookup, field visibility, completion gates, and dispatch flow branching. Changing it on a saved task would break all of these. If a task was created with the wrong kind, cancel it and create a new one.

---

### 1.3 task_access_policy — Task Access Policy

- **Type:** Link → Task Access Policy (custom)
- **Current hidden:** 1 | **Current depends_on:** none
- **Current client script overrides:** none
- **Current server-side usage:** Auto-set from task_kind by before-save-policy script. Read for role checks.
- **Visible for task kinds (current):** None (always hidden)
- **Visible for task kinds (proposed):** None (internal field, keep hidden)
- **Approach:** No change needed
- **Decision:** KEEP HIDDEN — internal field
- **Notes:** —

---

### 1.4 completed_at — Completed At

- **Type:** Datetime (custom)
- **Current hidden:** 0 | **Current depends_on:** none
- **Current client script overrides:**
  - `Task-Mobile Form Layout Fix.js:253` — hidden for Pack on mobile (DISABLED)
- **Current server-side usage:** Set to now() when task becomes Completed (before-save-policy script).
- **Visible for task kinds (current):** All (was hidden for Pack on mobile, now disabled)
- **Visible for task kinds (proposed):** Completed tasks only. Hidden on all non-completed tasks.
- **Approach:** DECIDED. Client visibility based on status, not task kind. Read-only for everyone except admin.
- **Decision:** DECIDED
  - **Hidden** when status is NOT Completed (Open, Working, Overdue, Cancelled).
  - **Visible + read-only** when status is Completed — for all task kinds, all users.
  - **Editable** only for System Manager (admin escape hatch for timestamp corrections).
  - Server sets value automatically on completion — users never need to type it.

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Default hidden — centralized script reveals it |
| **Client** | Show on Completed | `frm.toggle_display("completed_at", frm.doc.status === "Completed");` |
| **Client** | Read-only unless admin | `frm.set_df_property("completed_at", "read_only", !frappe.user.has_role("System Manager"));` |
| **Server** | Auto-set | Already handled by before-save-policy — sets `completed_at = now()` on completion |

**What changes:**

| Script | Action | Detail |
|---|---|---|
| `Task-Mobile Form Layout Fix.js` | **ALREADY DISABLED** | Was hiding for Pack on mobile |
| Schema (`custom-fields.json`) | **MODIFY** | Set hidden=1 |
| Centralized visibility script (new) | **ADD** | Show when Completed, read-only unless admin |

**Notes:** No task-kind condition needed — this is purely status-driven. Same behavior for Order entry, Delivery, Debt Collection, etc.

---

## 2. Assignment and Ownership

### 2.1 custom_assigned_to — Assigned To (merges old accepted_by)

- **Type:** Link → User (custom)
- **Current hidden:** 0 | **Current depends_on:** none
- **Current label (schema):** "Assign To"
- **Current client script overrides:**
  - `Task-Accept Start.js:113` — label changed to "Assign To" (redundant, same as schema)
  - `Task-Mobile Form Layout Fix.js:253` — hidden for Pack on mobile (DISABLED)
- **Current server-side usage:** Read/written by policy script for assignment. Synced to `_assign`. Default set to policy.default_team_user.
- **Visible for task kinds (current):** All (was hidden for Pack on mobile, now disabled)
- **Visible for task kinds (proposed):** ALL task kinds
- **Approach:** DECIDED. This field becomes the single source of truth for both ownership and locking. `custom_accepted_by` (old section 2.3) is removed.
- **Decision:** DECIDED

  **New model (replaces assign + accept two-step):**
  - One field: `custom_assigned_to`. No separate acceptance field or step.
  - **Team placeholder** (e.g. `packing.team@example.com`): task is in the team queue, nobody owns it, nobody can edit. Any team member can click "Accept" which sets `assigned_to = themselves`.
  - **Real user**: that user owns the task and can edit/complete it immediately. No accept step needed.
  - **Lock rule**: `assigned_to === frappe.session.user || is_admin`. That's it.
  - **Accept button**: shown when `assigned_to` is NOT the current user. Clicking it sets `assigned_to = current_user`. Effectively "assign to me."
  - **Admin reassigns to Jane**: Jane can work immediately. No accept ceremony required.

  **Label:** Change from "Assign To" to **"Assigned To"**.

  **What this replaces:**

  | Old concept | Old fields | New | |
  |---|---|---|---|
  | Assignment (routing) | `custom_assigned_to` | `custom_assigned_to` | Kept |
  | Acceptance (ownership) | `custom_accepted_by` | `custom_assigned_to` | Merged — assignment IS ownership |
  | Acceptance timestamp | `custom_accepted_at` | See section 2.4 | Needs decision |
  | Lock check (client) | `accepted_by === me` | `assigned_to === me` | Simplified |
  | Lock check (server) | `not accepted_by` | `assigned_to is team placeholder or empty` | Simplified |

**Implementation — scripts that reference `custom_accepted_by` and must change:**

| Script | Current usage | Change |
|---|---|---|
| `Task-Lock Unaccepted.js` | `frm.doc.custom_accepted_by === frappe.session.user` | Replace with `frm.doc.custom_assigned_to === frappe.session.user` |
| `Task-Action Buttons.js` | `tab_is_accepted()` checks `custom_accepted_by` | Check `custom_assigned_to === frappe.session.user` |
| `Task-Accept Start.js` | References `custom_accepted_by` | Update or remove |
| `dispatch_task_accept` API | Sets `custom_accepted_by = user` | Just set `custom_assigned_to = user` (already does this too) |
| `Task-before-save-dispatch-gates.py:20` | `not doc.custom_accepted_by` | Check `assigned_to` is empty or is a team placeholder |
| `Task-before-save-dispatch-gates.py:38` | `not accepted_by` on completion | Same — check `assigned_to` is a real user |
| `Task-before-save-policy.py` | References `custom_accepted_by` | Update to use `custom_assigned_to` for lock checks |
| `Task-Auto Reload.js` | May reference acceptance state | Check and update |

**Schema changes:**
- `custom_accepted_by`: set hidden=1, stop writing to it. Eventually remove the field. (Or keep as deprecated read-only for historical data.)
- `custom_assigned_to`: rename label to "Assigned To"
- Remove client script label override in `Task-Accept Start.js:113`

- **Notes:** This is a significant refactor touching many scripts. Should be done as a dedicated task, not mixed with the visibility redesign. But the decision is made — one field, no accept step.

---

### ~~2.2~~ 2.2 custom_next_task_assign_to — Next Task: Assign To

- **Type:** Link → User (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:["Order entry","Pack / prepare items","Delivery","Return Call","Other: Entry","Other: Processing","Returns processing / verification"].includes(doc.task_kind)`
- **Current client script overrides:**
  - `Task-Accept Start.js:117-121` — shown for dispatch kinds + Account Details: Entry, hidden for others
  - `Task-Accept Start.js:124` — force shown for Account Details: Entry
  - `Task-Delivery UI Fix.js:20-21` — force shown for Delivery
  - `Task-Inspect Returns Next Assign Visible.js:21-22` — force shown for Returns processing
  - `Task-Other UI Cleanup.js:39` — shown for Other kinds (conditionally)
- **Current server-side usage:** Read by after-save scripts to set custom_assigned_to on downstream tasks.
- **Visible for task kinds (current):** Order entry, Pack, Delivery, Return Call, Other: Entry, Other: Processing, Returns proc., Account Details: Entry, Invoice prep (via dispatch array), Discount Approval (via dispatch array)
- **Visible for task kinds (proposed):** 9 kinds that create downstream tasks AND read this field
- **Approach:** DECIDED. Centralized visibility by task_kind. All existing overrides removed.
- **Decision:** DECIDED

  Show ONLY for task kinds whose after-save script creates a downstream task AND reads `custom_next_task_assign_to` to assign it:

  | # | Task kind | Creates on completion/status change | Script |
  |---|---|---|---|
  | 1 | **Order entry** | Pack / prepare items | dispatch-flow:215 |
  | 2 | **Pack / prepare items** | Delivery | dispatch-flow:223 |
  | 3 | **Delivery** | Invoice prep OR Return Call | dispatch-flow:194/197 |
  | 4 | **Return Call** | Pickup Returns | dispatch-flow:232 |
  | 5 | **Pickup Returns** | Returns proc. / verification | dispatch-flow:209 |
  | 6 | **Returns proc. / verification** | Invoice prep + Returns restocking | dispatch-flow:245/251 |
  | 7 | **Discount Approval** | Pack (approved) or Order entry (rejected) | dispatch-flow:280/283 |
  | 8 | **Account Details: Entry** | Account Details: Processing | account-details:47 |
  | 9 | **Other: Entry** | Other: Processing | other-processing:26 |

  **Hidden for all other task kinds** — they either create no downstream tasks, or create them without reading this field:
  - Invoice prep creates Debt Collection but assigns from policy default (dispatch-flow:166)
  - Debt Collection creates Debt Closure Approval but uses hardcoded user whitelist (debt-closure:67)
  - All remaining kinds create nothing: Dispatch picking, Return drop-off, Returns restocking, Distribute Payment, Payment Received, Debt Closure Approval, Purchase Approval, Write-off Approval, Account Details: Processing, Other: Processing, Other, Order accepting, Return to warehouse

**Bugs in current implementation:**

| Bug | Detail |
|---|---|
| **Other: Processing shows it** | CF depends_on includes Other: Processing, but it creates NO downstream task. Should be hidden. |
| **Invoice prep shows it** | Accept Start dispatch array includes Invoice prep, but dispatch-flow does NOT read next_assign for Debt Collection creation. Should be hidden. |
| **Pickup Returns hidden** | NOT in CF depends_on, NOT in any client override. But dispatch-flow:209 DOES read next_assign. Should be visible. |
| **Discount Approval partially shown** | Not in CF depends_on. Shown only via Accept Start dispatch array (fragile). Should be in the canonical list. |
| **Account Details: Entry shown by hack** | Not in CF depends_on. Shown by Accept Start:124 force-override. Should be in the canonical list. |

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Remove depends_on. Set hidden=1. Centralized script reveals. |
| **Client** | Show for 9 kinds | `var NEXT_ASSIGN_KINDS = ["Order entry", "Pack / prepare items", "Delivery", "Return Call", "Pickup Returns", "Returns processing / verification", "Discount Approval", "Account Details: Entry", "Other: Entry"]; frm.toggle_display("custom_next_task_assign_to", NEXT_ASSIGN_KINDS.indexOf(frm.doc.task_kind) !== -1);` |

**What changes:**

| Script | Action | Detail |
|---|---|---|
| Schema (`custom-fields.json`) | **MODIFY** | Set hidden=1, remove depends_on |
| `Task-Accept Start.js:117-124` | **REMOVE** | next_task_assign_to show/hide logic |
| `Task-Delivery UI Fix.js` | **DISABLE** | Entire script exists only for this field |
| `Task-Inspect Returns Next Assign Visible.js` | **DISABLE** | Entire script exists only for this field |
| `Task-Other UI Cleanup.js:39` | **REMOVE** | next_task_assign_to toggle |
| Centralized visibility script (new) | **ADD** | Single toggle with 9-kind list |

- **Notes:** Label change: **"Next Task: Assign To" → "Next Task: Assigned To"** for consistency with field 2.1. Fix in custom field schema and remove the client script label override (`Task-Accept Start.js:114`).

---

### 2.3 ~~custom_accepted_by~~ — REMOVED (merged into 2.1)

- **Decision:** DEPRECATED. Merged into `custom_assigned_to` (section 2.1).
- **Migration:** Set `hidden=1` in schema. Stop writing to it in all scripts. The `dispatch_task_accept` API already sets `custom_assigned_to` — just remove the `custom_accepted_by` write. All lock checks switch to `custom_assigned_to`. Keep the field in the database for historical records but never display or write it again.
- **Notes:** See section 2.1 for the full merged design. The old two-step model (assign then accept) is replaced by: assignment IS ownership. If `assigned_to` is a real user, they own it. If it's a team placeholder, nobody owns it yet.

---

### 2.4 ~~custom_accepted_at~~ — REMOVED (no longer needed)

- **Decision:** REMOVE. With the merge of accepted_by into assigned_to (section 2.1), there is no separate acceptance event to timestamp. Assignment time is tracked by Frappe's built-in Version history.
- **Migration:** Set `hidden=1` in schema. Stop writing to it. Remove the client script hide in `Task-Accept Start.js:151`. Keep in database for historical records.

---

## 3. Customer / Entity

### 3.1 customer — Customer

- **Type:** Link → Customer (custom)
- **Current hidden:** 0 | **Current depends_on:** none
- **Current client script overrides:**
  - `Task-Mobile Form Layout Fix.js:260` — hidden for Pack on mobile when empty (DISABLED)
- **Current server-side usage:** Read by completion gates (Order entry requires customer). Passed to downstream tasks and Dispatch Case.
- **Visible for task kinds (current):** All
- **Visible for task kinds (proposed):** Dispatch flow task kinds (always) + any task that already has a customer value.
- **Approach:** DECIDED. Visibility based on task kind + field value. Editability based on task kind.
- **Decision:** DECIDED
  - **Visible** on all dispatch flow task kinds — always, even if empty (Order entry needs to select one).
  - **Visible** on non-dispatch kinds IF customer has a value (e.g., Debt Collection, Account Details tasks that inherited a customer).
  - **Hidden** on non-dispatch kinds when customer is empty (e.g., new Purchase Approval with no customer).
  - **Editable** only on Order entry (user selects the customer).
  - **Read-only** on all other dispatch flow kinds (customer was set at creation by `task_create` API, not user-editable).
  - **Read-only** on non-dispatch kinds that show it (informational only).

**Dispatch flow task kinds (for this field):**

Order entry, Pack / prepare items, Dispatch picking / hand-off, Delivery, Return Call, Return to warehouse, Pickup Returns, Return drop-off at warehouse, Returns processing / verification, Returns restocking, Invoice preparation / create invoice, Discount Approval, Debt Collection, Distribute Payment, Payment Received, Debt Closure Approval

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Default hidden — centralized script reveals it |
| **Client** | Show for dispatch kinds | `frm.toggle_display("customer", is_dispatch_kind \|\| !!frm.doc.customer);` |
| **Client** | Editable only on Order entry | `frm.set_df_property("customer", "read_only", frm.doc.task_kind !== "Order entry");` |

**What changes:**

| Script | Action | Detail |
|---|---|---|
| `Task-Mobile Form Layout Fix.js` | **ALREADY DISABLED** | Was hiding for Pack on mobile when empty |
| Schema (`custom-fields.json`) | **MODIFY** | Set hidden=1 |
| Centralized visibility script (new) | **ADD** | Show for dispatch kinds or when has value; read-only except Order entry |

**Notes:** Almost all task kinds involve a customer. The few that might not (Purchase Approval, Write-off Approval) still show it if the value was set at creation. The `|| !!frm.doc.customer` fallback ensures no data is silently hidden.

---

### 3.2 custom_account_details_subject — Subject (Account Details)

- **Type:** Data (custom)
- **Current hidden:** 0 | **Current depends_on:** none
- **Current client script overrides:** none
- **Current server-side usage:** Read by after-save-account-details-processing to set subject on downstream task.
- **Visible for task kinds (current):** ALL (no depends_on, no client hiding)
- **Visible for task kinds (proposed):** Account Details: Entry, Account Details: Processing only
- **Approach:** Visibility only
- **Decision:** TO DECIDE
- **Notes:** BUG — this field is visible on every task kind. It has no depends_on or client script hiding it. Should be restricted to Account Details kinds.

---

## 4. Dispatch Case

### 4.1 dispatch_case — Dispatch Case / Packing Items

- **Type:** Link → Dispatch Case (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Pack / prepare items" || doc.task_kind=="Dispatch picking / hand-off" || doc.task_kind=="Delivery" || doc.task_kind=="Pickup Returns" || doc.task_kind=="Return drop-off at warehouse" || doc.task_kind=="Returns processing / verification" || doc.task_kind=="Returns restocking" || doc.task_kind=="Invoice preparation / create invoice" || doc.task_kind=="Discount Approval"`
- **Current property setters:** label="Dispatch Case / Packing Items", bold=1, in_list_view=1, description set
- **Current client script overrides:** none (Action Buttons reads it for button logic, doesn't toggle visibility)
- **Current server-side usage:** Read by every dispatch gate and flow script. Written by task_create_dispatch_case API.
- **Visible for task kinds (current):** 9 dispatch kinds + blank task_kind
- **Visible for task kinds (proposed):** ALWAYS HIDDEN in form body. Navigation handled by "Open DC" button.
- **Approach:** DECIDED. Field stays in schema (server scripts need it), but hidden from form body on all task kinds.
- **Decision:** DECIDED
  - **Hidden** on all task kinds in the form body.
  - Navigation to the Dispatch Case is already handled by:
    - Mobile sub-header: "Open DC" button (`Task-Action Buttons.js:268`)
    - Desktop header: "Open Dispatch Case" custom button (`Task-Action Buttons.js:350`)
  - Both buttons already check `frm.doc.dispatch_case` — they show only when a DC exists.
  - The Link field in the body was redundant — it just duplicated the button navigation.
  - Field keeps `in_list_view=1` (property setter) so it still appears in Task list view.

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Set hidden=1, remove depends_on |
| **Client** | No action needed | Field stays hidden. "Open DC" buttons already handle navigation. |

**What changes:**

| Script | Action | Detail |
|---|---|---|
| Schema (`custom-fields.json`) | **MODIFY** | Set hidden=1, remove depends_on expression |
| Property setter | **KEEP** | `in_list_view=1` stays (visible in list, not in form) |
| `Task-Action Buttons.js` | **NO CHANGE** | "Open DC" buttons already exist and work |

**Notes:** The field value is still set by `task_create` API and read by server scripts. Only the form-body visibility changes. Keep `in_list_view=1` so the DC link is still visible in the Task list.

---

### 4.2 dispatch_case_status — Dispatch Case Status

- **Type:** Data (custom)
- **Current hidden:** 0 | **Current depends_on:** same as dispatch_case (9 dispatch kinds + blank)
- **Current client script overrides:** none
- **Current server-side usage:** Written by before-save gates from Dispatch Case.status
- **Visible for task kinds (current):** Same 9 dispatch kinds as dispatch_case
- **Visible for task kinds (proposed):** ALWAYS HIDDEN. DC status is visible on the Dispatch Case form itself.
- **Approach:** DECIDED. Same as dispatch_case (4.1) — hidden in form body.
- **Decision:** DECIDED
  - **Hidden** on all task kinds. Users navigate to the DC via "Open DC" button to see its status.
  - Field stays in schema — server scripts write it during before-save gates.

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Set hidden=1, remove depends_on |

**What changes:**

| Script | Action | Detail |
|---|---|---|
| Schema (`custom-fields.json`) | **MODIFY** | Set hidden=1, remove depends_on expression |

---

### 4.3 dispatch_group_id — Dispatch Group ID

- **Type:** Data (custom)
- **Current hidden:** 1 | **Current depends_on:** none
- **Current client script overrides:** none
- **Current server-side usage:** Internal grouping identifier
- **Visible for task kinds (current):** None (hidden=1)
- **Visible for task kinds (proposed):** None (internal)
- **Approach:** No change
- **Decision:** KEEP HIDDEN — internal field
- **Notes:** —

---

## 5. Status Selects

### 5.1 delivery_status — Delivery Status

- **Type:** Select (custom) | **Options:** Todo, Picked Up, Delivered
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Delivery"`
- **Current client script overrides:** none
- **Current server-side usage:**
  - `before-save-gates:84` — enforces Todo→Picked Up→Delivered order (no skipping)
  - `before-save-gates:88` — blocks completion unless delivery_status=Delivered
  - `before-save-gates:92` — **auto-completes** task when set to Delivered
  - `after-save-flow:182` — Picked Up → sets DC status to "In Transit"
  - `after-save-flow:186` — Delivered → creates Stock Entry, sets DC status, creates Invoice or Return Call task
- **Visible for task kinds (current):** Delivery only
- **Visible for task kinds (proposed):** ALWAYS HIDDEN. Replaced by action buttons.
- **Approach:** DECIDED. Hide the dropdown. Replace with a button-driven state machine. Server logic unchanged.
- **Decision:** DECIDED
  - **Hidden** on all task kinds, including Delivery. The field exists but is never shown in the form.
  - **Replaced by action buttons** in `Task-Action Buttons.js`:

  | delivery_status | Button shown | Button action |
  |---|---|---|
  | `Todo` | **"Picked Up"** (instead of Complete) | Sets `delivery_status = "Picked Up"`, saves |
  | `Picked Up` | **"Delivered"** (instead of Complete) | Sets `delivery_status = "Delivered"`, saves → server auto-completes |
  | (Completed) | None | Task is done |

  - **No server changes needed.** The buttons just set the field value and save — the same thing the user was doing manually with the dropdown. All server gates and triggers fire exactly as before:
    - `ds_changing` detected in before-save → gates still enforce order
    - `ds_changed` detected in after-save → Stock Entries, DC status updates, downstream tasks all fire
    - Auto-complete on Delivered (line 92) still fires
  - **The Complete button is suppressed** for Delivery tasks — it was already dead (gates throw "cannot complete until Delivered", and setting Delivered auto-completes anyway).

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Set hidden=1, remove depends_on |
| **Client** | Buttons replace dropdown | In `Task-Action Buttons.js`: if task_kind is Delivery and not completed, show state-appropriate button instead of Complete |

**Button implementation sketch:**

```javascript
// Inside mobile bottom-actions and desktop header button logic
if (frm.doc.task_kind === "Delivery" && frm.doc.status !== "Completed") {
    if (frm.doc.delivery_status === "Todo" || !frm.doc.delivery_status) {
        // Show "Picked Up" button
        btn.text("Picked Up").on("click", function() {
            frm.set_value("delivery_status", "Picked Up");
            frm.save();
        });
    } else if (frm.doc.delivery_status === "Picked Up") {
        // Show "Delivered" button (this triggers auto-complete on server)
        btn.text("Delivered").on("click", function() {
            frm.set_value("delivery_status", "Delivered");
            frm.save();
        });
    }
    // Do NOT show generic "Complete" button for Delivery
}
```

**What changes:**

| Script | Action | Detail |
|---|---|---|
| Schema (`custom-fields.json`) | **MODIFY** | Set hidden=1, remove depends_on |
| `Task-Action Buttons.js` | **MODIFY** | Add Delivery button states; suppress Complete for Delivery |
| `Task-Delivery UI Fix.js` | **DISABLE/DELETE** | Only existed for next_assign visibility (already decided in 2.2) |
| Server scripts | **NO CHANGE** | All gates and triggers unchanged |

**Notes:** Photo gate for Delivery (before-save-policy:78) only fires for non-DC tasks. For DC tasks, the photo check is in the photo system. Both still work — the server sees `status = "Completed"` (set by auto-complete) and runs all gates.

---

### 5.2 pickup_status — Pickup Status

- **Type:** Select (custom) | **Options:** Todo, Picked Up, Returned to Warehouse
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Pickup Returns"`
- **Current client script overrides:** none
- **Current server-side usage:**
  - `before-save-gates:96` — enforces Todo→Picked Up→Returned to Warehouse order
  - `before-save-gates:100` — blocks completion unless pickup_status=Returned to Warehouse
  - `before-save-gates:104` — **auto-completes** task when set to Returned to Warehouse
  - `after-save-flow:200` — Picked Up → Stock Entry (client warehouse→return transit), DC status "Return In Transit"
  - `after-save-flow:206` — Returned to Warehouse → Stock Entry (transit→return warehouse), DC status "Returns Received", creates Returns processing task
- **Visible for task kinds (current):** Pickup Returns only
- **Visible for task kinds (proposed):** ALWAYS HIDDEN. Replaced by action buttons. Same pattern as delivery_status.
- **Approach:** DECIDED. Identical approach to 5.1 — button-driven state machine.
- **Decision:** DECIDED
  - **Hidden** on all task kinds, including Pickup Returns.
  - **Replaced by action buttons:**

  | pickup_status | Button shown | Button action |
  |---|---|---|
  | `Todo` | **"Picked Up"** | Sets `pickup_status = "Picked Up"`, saves |
  | `Picked Up` | **"Returned to WH"** | Sets `pickup_status = "Returned to Warehouse"`, saves → server auto-completes |
  | (Completed) | None | Task is done |

  - **No server changes needed.** Same reasoning as 5.1 — buttons set field, save, server does the rest.
  - **Complete button suppressed** for Pickup Returns — same as Delivery.

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Set hidden=1, remove depends_on |
| **Client** | Buttons replace dropdown | In `Task-Action Buttons.js`: if task_kind is Pickup Returns and not completed, show state-appropriate button instead of Complete |

**What changes:**

| Script | Action | Detail |
|---|---|---|
| Schema (`custom-fields.json`) | **MODIFY** | Set hidden=1, remove depends_on |
| `Task-Action Buttons.js` | **MODIFY** | Add Pickup Returns button states; suppress Complete for Pickup Returns |
| Server scripts | **NO CHANGE** | All gates and triggers unchanged |

**Notes:** Same pattern as Delivery. Both status fields become hidden state-machine drivers with button-only UI.

---

## 6. Approval

### 6.1 purchase_order — Purchase Order

- **Type:** Link → Purchase Order (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Purchase Approval"`
- **Current client script overrides:** none
- **Current server-side usage:** Required on completion by `Task-purchase-approval-writeback.py`. Outcome written back to the linked PO.
- **Visible for task kinds (current):** Purchase Approval only
- **Visible for task kinds (proposed):** Purchase Approval only
- **Approach:** DECIDED. Move to centralized visibility. Single task kind.
- **Decision:** DECIDED
  - **Hidden** by default (schema hidden=1, remove depends_on).
  - **Shown** by centralized script for Purchase Approval only.
  - No downstream task created. No `custom_next_task_assign_to` needed.
  - Task created manually by Ops - Purchasing (no automation).

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Set hidden=1, remove depends_on |
| **Client** | Show for Purchase Approval | `frm.toggle_display("purchase_order", frm.doc.task_kind === "Purchase Approval");` |

---

### 6.2 approval_outcome — Approval Outcome

- **Type:** Select (custom) | **Options:** Approved, Rejected
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Purchase Approval" || doc.task_kind=="Discount Approval" || doc.task_kind=="Write-off Approval"`
- **Current client script overrides:** none
- **Current server-side usage:** Read by gates (Discount Approval must set outcome to complete). Read by after-save flow to branch on Approved vs Rejected. Written back to PO by purchase-approval-writeback.
- **Visible for task kinds (current):** Purchase Approval, Discount Approval, Write-off Approval
- **Visible for task kinds (proposed):** All 4 approval kinds, but ONLY after completion.
- **Approach:** DECIDED. Field is never shown as a dropdown. It's set by Approve/Reject buttons and shown read-only after completion.
- **Decision:** DECIDED

  **New model — button-driven approval (same pattern as delivery_status/pickup_status):**

  The user never interacts with the `approval_outcome` field directly. Instead:

  | State | Buttons shown | What they do |
  |---|---|---|
  | Open/Working, not completed | Left: **Reject** / Right: **Approve** | Sets `approval_outcome`, saves → server auto-completes or completes via button |
  | Completed | None (task is done) | `approval_outcome` shown read-only as confirmation |

  **Applies to ALL 4 approval kinds:**
  - Purchase Approval
  - Discount Approval
  - Write-off Approval
  - **Debt Closure Approval** (NEW — currently has no approve/reject. Adding it.)

  **Field visibility:**
  - **Hidden** by default (schema hidden=1, remove depends_on).
  - **Shown read-only** by centralized script only when `status === "Completed"` AND `task_kind` is one of the 4 approval kinds.
  - `frm.toggle_display("approval_outcome", frm.doc.status === "Completed" && APPROVAL_KINDS.indexOf(frm.doc.task_kind) !== -1);`
  - `frm.set_df_property("approval_outcome", "read_only", 1);` — always read-only, buttons are the only input.

  **Button implementation sketch:**

  ```javascript
  var APPROVAL_KINDS = [
      "Purchase Approval", "Discount Approval",
      "Write-off Approval", "Debt Closure Approval"
  ];

  if (APPROVAL_KINDS.indexOf(frm.doc.task_kind) !== -1
      && frm.doc.status !== "Completed") {
      // Left button: Reject (secondary/danger style)
      reject_btn.text("Reject").on("click", function() {
          frm.set_value("approval_outcome", "Rejected");
          // complete the task
      });
      // Right button: Approve (primary style)
      approve_btn.text("Approve").on("click", function() {
          frm.set_value("approval_outcome", "Approved");
          // complete the task
      });
      // Do NOT show generic "Complete" button for approval kinds
  }
  ```

  **Debt Closure Approval — what changes:**
  - Currently: no approve/reject, just complete (gated by hardcoded user whitelist)
  - New: Director sees Approve/Reject buttons. Outcome is recorded.
  - The profit calculation in `Task-after-save-debt-closure.py` fires on completion regardless of outcome.
  - Server gate for Debt Closure should be updated: require `approval_outcome` to be set (like Discount Approval gate).
  - The hardcoded user whitelist should be replaced with role-based check from Task Access Policy.

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Set hidden=1, remove depends_on |
| **Client** | Approve/Reject buttons | In `Task-Action Buttons.js`: for all 4 approval kinds, show Reject (left) and Approve (right) instead of Complete |
| **Client** | Show read-only after completion | `frm.toggle_display` when Completed + approval kind |
| **Server** | Gate for all 4 kinds | Require `approval_outcome` in ("Approved", "Rejected") before completion. Currently only Discount and Purchase do this. Add for Write-off and Debt Closure. |

**What changes:**

| Script | Action | Detail |
|---|---|---|
| Schema (`custom-fields.json`) | **MODIFY** | Set hidden=1, remove depends_on, add Debt Closure Approval to logic |
| `Task-Action Buttons.js` | **MODIFY** | Add Approve/Reject button pair for all 4 approval kinds; suppress Complete |
| `Task-before-save-dispatch-gates.py` | **MODIFY** | Add approval_outcome validation for Write-off Approval and Debt Closure Approval (match existing Discount Approval gate) |
| `Task-after-save-debt-closure.py` | **MODIFY** | Replace hardcoded user whitelist with role-based check from Task Access Policy |
| `Task-purchase-approval-writeback.py` | **NO CHANGE** | Already validates approval_outcome |
| Centralized visibility script | **ADD** | Show field read-only when Completed + approval kind |

---

### 6.3 ~~approval_note~~ — REMOVED (use Description instead)

- **Type:** Small Text (custom)
- **Current hidden:** 0 | **Current depends_on:** same as approval_outcome
- **Current server-side usage:** Written to `po.director_approval_note` by purchase-approval-writeback.
- **Decision:** REMOVE.
  - The standard Task `description` field already exists and is suitable for approval notes/reasons.
  - Directors should write their reasoning in `description` before clicking Approve/Reject.
  - `Task-purchase-approval-writeback.py` must be updated to read `doc.description` instead of `doc.approval_note`.
  - Schema: set hidden=1, remove depends_on. Eventually delete the field.
  - Remove from `Task-Lock Unaccepted.js` editable_fields list.

---

## 7. Invoice and Sales

### 7.1 sales_invoice — Sales Invoice

- **Type:** Link → Sales Invoice (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Invoice preparation / create invoice" || doc.task_kind=="Debt Collection" || doc.task_kind=="Payment Received" || doc.task_kind=="Distribute Payment" || doc.task_kind=="Returns processing / verification"`
- **Current client script overrides:** none
- **Current server-side usage:**
  - `before-save-gates:131` — Invoice prep completion reads SI from DC (NOT from this field)
  - `after-save-flow:155,162` — Debt Collection task gets SI set at creation
  - `after-save-debt-closure:44` — Debt Closure Approval gets SI copied from Debt Collection
  - `after-save-debt-closure:85` — Debt Closure reads SI for profit calculation
- **Visible for task kinds (current):** Invoice prep, Debt Collection, Payment Received, Distribute Payment, Returns proc.
- **Visible for task kinds (proposed):** Show only when field has a value. Hidden when empty.
- **Approach:** DECIDED. Value-based visibility, not kind-based. Read-only always.
- **Decision:** DECIDED
  - **Hidden** by default (schema hidden=1, remove depends_on).
  - **Shown** by centralized script when the field has a value: `frm.toggle_display("sales_invoice", !!frm.doc.sales_invoice);`
  - **Read-only always** — set by server scripts at creation, never user-editable.
  - This automatically shows it on Debt Collection and Debt Closure Approval (where it's populated), and hides it on Invoice prep, Payment Received, Distribute Payment, Returns proc. (where it's always empty).
  - If any future task kind gets an SI value, it will automatically show — no code change needed.

**Why value-based instead of kind-based:**

| Task kind in current depends_on | Actually has a value? | Should show? |
|---|---|---|
| Invoice prep | NO — reads SI from DC, not from task | No |
| Debt Collection | YES — set at creation | Yes |
| Payment Received | NO — never set | No |
| Distribute Payment | NO — never set | No |
| Returns proc. | NO — never set | No |
| Debt Closure Approval | YES — copied from Debt Collection | Yes (not even in current depends_on!) |

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Set hidden=1, remove depends_on |
| **Client** | Show when has value | `frm.toggle_display("sales_invoice", !!frm.doc.sales_invoice);` |
| **Client** | Always read-only | `frm.set_df_property("sales_invoice", "read_only", 1);` |

---

### 7.2 payment_entry — Payment Entry

- **Type:** Link → Payment Entry (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Payment Received" || doc.task_kind=="Distribute Payment" || doc.task_kind=="Debt Collection"`
- **Current client script overrides:** none
- **Current server-side usage:**
  - `Payment Entry-after-submit:78` — Distribute Payment task gets PE set at creation
  - `Payment Entry-after-submit:66` — used for duplicate check on Distribute Payment
  - `after-save-debt-closure:45` — Debt Closure Approval gets first PE copied from payment_history
- **Visible for task kinds (current):** Payment Received, Distribute Payment, Debt Collection
- **Visible for task kinds (proposed):** Show only when field has a value. Hidden when empty.
- **Approach:** DECIDED. Value-based visibility, not kind-based. Read-only always. Same pattern as sales_invoice.
- **Decision:** DECIDED
  - **Hidden** by default (schema hidden=1, remove depends_on).
  - **Shown** by centralized script when the field has a value: `frm.toggle_display("payment_entry", !!frm.doc.payment_entry);`
  - **Read-only always** — set by server scripts at creation, never user-editable.
  - This automatically shows it on Distribute Payment and Debt Closure Approval (where it's populated), and hides it on Debt Collection (PEs live in payment_history child table, not this field) and Payment Received (never set).

**Why value-based instead of kind-based:**

| Task kind in current depends_on | Actually has a value? | Should show? |
|---|---|---|
| Payment Received | NO — never set | No |
| Distribute Payment | YES — set at creation by PE after-submit | Yes |
| Debt Collection | NO — PEs are in payment_history child table | No |
| Debt Closure Approval | YES — copied from first payment_history row | Yes (not even in current depends_on!) |

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Set hidden=1, remove depends_on |
| **Client** | Show when has value | `frm.toggle_display("payment_entry", !!frm.doc.payment_entry);` |
| **Client** | Always read-only | `frm.set_df_property("payment_entry", "read_only", 1);` |

---

## 8. Payment and Debt

### 8.1 current_debt_amd — Current Debt (AMD)

- **Type:** Currency (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Debt Collection"`
- **Visible for task kinds (current):** Debt Collection only
- **Visible for task kinds (proposed):** TO DECIDE
- **Notes:** —

---

### 8.2 debt_threshold_amd — Debt Threshold (AMD)

- **Type:** Currency (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Debt Collection"`
- **Visible for task kinds (current):** Debt Collection only
- **Visible for task kinds (proposed):** TO DECIDE
- **Notes:** —

---

### 8.3 new_payment_amount — New Payment Amount

- **Type:** Currency (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Payment Received" || doc.task_kind=="Debt Collection"`
- **Current client script overrides:**
  - `Task-Lock Unaccepted.js:41-46` — explicitly unlocked for accepted user
- **Visible for task kinds (current):** Payment Received, Debt Collection
- **Visible for task kinds (proposed):** TO DECIDE
- **Notes:** —

---

### 8.4 payment_method_dc — Payment Method

- **Type:** Select (custom) | **Options:** (blank), Cash, Bank Transfer, Card
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Payment Received" || doc.task_kind=="Debt Collection"`
- **Current client script overrides:**
  - `Task-Lock Unaccepted.js:41-46` — explicitly unlocked for accepted user
- **Visible for task kinds (current):** Payment Received, Debt Collection
- **Visible for task kinds (proposed):** TO DECIDE
- **Notes:** —

---

### 8.5 payment_reference_dc — Payment Reference

- **Type:** Data (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Payment Received" || doc.task_kind=="Debt Collection"`
- **Current client script overrides:**
  - `Task-Lock Unaccepted.js:41-46` — explicitly unlocked for accepted user
- **Visible for task kinds (current):** Payment Received, Debt Collection
- **Visible for task kinds (proposed):** TO DECIDE
- **Notes:** —

---

### 8.6 total_outstanding — Total Outstanding

- **Type:** Currency (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Debt Collection" || doc.task_kind=="Distribute Payment"`
- **Visible for task kinds (current):** Debt Collection, Distribute Payment
- **Visible for task kinds (proposed):** TO DECIDE
- **Notes:** —

---

### 8.7 custom_case_profit — Case Profit

- **Type:** Currency (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:doc.task_kind === "Debt Closure Approval"`
- **Visible for task kinds (current):** Debt Closure Approval only
- **Visible for task kinds (proposed):** TO DECIDE
- **Notes:** —

---

### 8.8 custom_total_amount_paid — Total Amount Paid

- **Type:** Currency (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:doc.task_kind === "Debt Closure Approval"`
- **Visible for task kinds (current):** Debt Closure Approval only
- **Visible for task kinds (proposed):** TO DECIDE
- **Notes:** —

---

### 8.9 available_advance_credit — Available Advance Credit

- **Type:** Currency (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Debt Collection" || doc.task_kind=="Distribute Payment"`
- **Visible for task kinds (current):** Debt Collection, Distribute Payment
- **Visible for task kinds (proposed):** TO DECIDE
- **Notes:** —

---

### 8.10 open_invoices — Open Invoices

- **Type:** Table → Debt Collection Invoice (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Debt Collection" || doc.task_kind=="Distribute Payment"`
- **Visible for task kinds (current):** Debt Collection, Distribute Payment
- **Visible for task kinds (proposed):** TO DECIDE
- **Notes:** Child table.

---

### 8.11 payment_history — Payment History

- **Type:** Table → Debt Collection Payment (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Debt Collection" || doc.task_kind=="Distribute Payment"`
- **Visible for task kinds (current):** Debt Collection, Distribute Payment
- **Visible for task kinds (proposed):** TO DECIDE
- **Notes:** Child table.

---

## 9. Returns

### 9.1 return_pickup_driver — Return Pickup Driver

- **Type:** Link → User (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Pickup Returns" || doc.task_kind=="Return drop-off at warehouse"`
- **Current client script overrides:**
  - `Task-Lock Unaccepted.js:41-46` — explicitly unlocked for accepted user
- **Visible for task kinds (current):** Pickup Returns, Return drop-off at warehouse
- **Visible for task kinds (proposed):** Return Call, Pickup Returns, Return drop-off at warehouse
- **Approach:** DECIDED. Move to centralized visibility.
- **Decision:** DECIDED
  - **Hidden** by default (schema hidden=1, remove depends_on).
  - **Shown** by centralized script for return-flow kinds:
    - **Return Call** — user sets the driver here (dispatches to Pickup Returns)
    - **Pickup Returns** — read-only, shows who was assigned as driver
    - **Return drop-off at warehouse** — read-only, informational
  - **Editable** on Return Call only. **Read-only** on Pickup Returns and Return drop-off.

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Set hidden=1, remove depends_on |
| **Client** | Show for 3 return kinds | `var RETURN_DRIVER_KINDS = ["Return Call", "Pickup Returns", "Return drop-off at warehouse"]; frm.toggle_display("return_pickup_driver", RETURN_DRIVER_KINDS.indexOf(frm.doc.task_kind) !== -1);` |
| **Client** | Editable on Return Call only | `frm.set_df_property("return_pickup_driver", "read_only", frm.doc.task_kind !== "Return Call");` |

---

### 9.2 scheduled_return_date — Scheduled Return Date

- **Type:** Date (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:!doc.task_kind || doc.task_kind=="Pickup Returns" || doc.task_kind=="Return drop-off at warehouse"`
- **Current client script overrides:** none
- **Current server-side usage:**
  - `after-save-flow:233-234` — Read on **Return Call** completion. Sets `exp_end_date` on the created Pickup Returns task.
- **Visible for task kinds (current):** Pickup Returns, Return drop-off at warehouse
- **Visible for task kinds (proposed):** Return Call, Pickup Returns, Return drop-off at warehouse (same as 9.1)
- **Approach:** DECIDED. Move to centralized visibility. Same return-flow kinds as 9.1.
- **Decision:** DECIDED
  - **Hidden** by default (schema hidden=1, remove depends_on).
  - **Shown** by centralized script for the same 3 return-flow kinds as `return_pickup_driver`.
  - **Editable** on Return Call only (user sets the pickup date).
  - **Read-only** on Pickup Returns and Return drop-off (informational).
  - **Bug fix:** Current depends_on is missing Return Call — the task kind where the user actually fills this in.

**Implementation:**

| Layer | What | How |
|---|---|---|
| **Schema** | hidden=1 | Set hidden=1, remove depends_on |
| **Client** | Show for 3 return kinds | Same `RETURN_DRIVER_KINDS` array as 9.1 — reuse in centralized script |
| **Client** | Editable on Return Call only | `frm.set_df_property("scheduled_return_date", "read_only", frm.doc.task_kind !== "Return Call");` |

---

## 10. ~~Other-Task Fields~~ — REMOVED (plain "Other" kind retired)

### 10.1 ~~other_items~~ — REMOVED

- **Decision:** REMOVE. The plain "Other" task kind is retired. `Other: Entry` / `Other: Processing` replace it.
- **Migration:** Remove `other_items` from custom fields. Delete the `Task Other Item` child DocType. Remove "Other" from `task_kind` Select options. Remove the `Other` Task Access Policy. Any existing tasks with `task_kind == "Other"` should be migrated or cancelled before removal.

### 10.2 ~~other_budget~~ — REMOVED

- **Decision:** REMOVE. Same as 10.1.

### 10.3 ~~other_supplier~~ — REMOVED

- **Decision:** REMOVE. Same as 10.1.

**What changes:**

| Item | Action |
|---|---|
| `task_kind` Select | Remove "Other" option |
| Task Access Policy "Other" | Delete |
| Custom field `other_items` | Delete |
| Custom field `other_budget` | Delete |
| Custom field `other_supplier` | Delete |
| Child DocType `Task Other Item` | Delete |
| `Task-Other UI Cleanup.js` | Remove all `other_items`/`other_budget`/`other_supplier` hide logic (now dead code) |
| `Task-Other UI Cleanup.js` | Remove `doc.task_kind=='Other'` branches (only Entry/Processing remain) |
| `custom-fields.json` depends_on | Remove all `doc.task_kind=='Other'` expressions |

**Notes:** The `Other: Entry` / `Other: Processing` pair fully replaces plain `Other`. They use description + photos instead of checklist fields. Documented in `docs/22-other-entry-processing-workflow.md`.

---

## 11. Driver / Handover

### 11.1 ~~driver_handover_note~~ — REMOVED (use Description instead)

- **Type:** Small Text (custom)
- **Current hidden:** 1 | **Current depends_on:** `eval:doc.task_kind != "Order entry"`
- **Current client script overrides:**
  - `Task-Lock Unaccepted.js:41-46` — explicitly unlocked for accepted user
- **Current server-side usage:** None found (not read or validated by any server script)
- **Visible for task kinds (current):** NONE — hidden=1 overrides depends_on (dead field)
- **Decision:** REMOVE. Use the standard Task **Description** field instead.

  The field was already dead (hidden=1 overrides depends_on, no server script reads it). Drivers should write handover details in Description.

  **Task Description behavior:**
  - **Collapsible by default** — does not take up screen space until the user expands it.
  - **In the DC flow:** when a Dispatch Case is created from Order entry, the description is attached to the DC. Downstream tasks (Pack, Delivery, etc.) receive an expanded description with DC context. So any handover note written in the Order entry description propagates through the chain.
  - **On Delivery/Pickup tasks:** the driver can expand Description and add handover details directly.

  **Migration:** Delete the custom field. Remove from `Task-Lock Unaccepted.js` editable_fields list. No data migration needed — the field was never visible and no server script writes to it.

---

## 12. Photo Fields

### 12.1 ~~warehouse_pickup_photo~~, ~~custom_delivery_photo~~, ~~warehouse_dropoff_photo~~ — ALREADY DELETED

- **Decision:** Already removed from test schema. Cleanup stale references only.
- **Current state:** Not defined in test `custom-fields.json`. Still listed in `field_order` (property-setters.json) and used as `insert_after` anchor for `driver_handover_note` (also being removed — see 11.1). Doc 18 confirms: "Legacy fields deleted from the Task DocType."
- **Replaced by:** `Task-Photo-System.js` gallery system — stores photos as `File` records attached to the Task, renders custom HTML gallery. Server gates use `task_has_image()` which checks `File` records.

  **Stale references to clean up:**

  | Item | What to fix |
  |---|---|
  | `field_order` in property-setters.json | Remove the 3 deleted fieldnames |
  | `driver_handover_note.insert_after` | Points to `warehouse_dropoff_photo` — field is also being deleted (11.1), so moot |
  | `Task-Accept Start.js:49-54` | Hides labels "Warehouse Pickup Photo" / "Warehouse Drop-off Photo" by text — dead code, remove |

---

### 12.2 custom_account_photos — Photos (Account Details)

- **Type:** Table → Account Detail Attachment (custom)
- **Current hidden:** 0 | **Current depends_on:** `eval:doc.task_kind === "Account details"` (WRONG — no such kind)
- **Current client script overrides:**
  - `Task-Accept Start.js:37` — shown for Account Details: Entry
  - `Task-Account Details UI Cleanup.js:50` — shown for Account Details
  - `Task-Account Details UI Cleanup.js:121-124` — hides native table, replaces with custom photo box
- **Current server-side usage:** Rows + File attachments copied from Entry to Processing task by `Task-after-save-account-details-processing.py:42-80`
- **Visible for task kinds (current):** Account Details: Entry and Processing (via client scripts only — depends_on never matches)
- **Decision:** TO DECIDE — depends on whether photo system is in scope of this redesign
- **Notes:**
  - **Bug:** depends_on references `"Account details"` which doesn't exist. Only works because client scripts force it.
  - The native table control is hidden by DOM surgery and replaced with a custom photo box. This is complex behavioral UI, not just field visibility.
  - If centralizing: fix depends_on or remove it, move show/hide to centralized script.

---

### 12.3 Photo gallery visibility — CENTRALIZE

The `Task-Photo-System.js` gallery currently decides internally which task kinds get a gallery:

| Task kind | Gallery | Required? |
|---|---|---|
| Pack / prepare items | Warehouse Pickup Photos | Yes — completion gate |
| Pickup Returns | Warehouse Drop-off Photos | Yes — "Returned to WH" gate |
| Returns proc. / verification | Pack / Prepare Photos (read-only) | No |
| Other: Entry / Processing | Task Photos | No |
| All other kinds | No gallery | — |

**Decision:** Gallery visibility should also be driven by the centralized visibility script, not decided internally by `Task-Photo-System.js`. The centralized script should tell the photo system which gallery to render (if any) based on `task_kind`. This keeps one source of truth for what appears on each task kind.

**Proposed approach:**
- Centralized visibility script defines a `PHOTO_GALLERY_CONFIG` map (task_kind → gallery key + label + editable flag).
- `Task-Photo-System.js` reads from that config instead of having its own `getTaskPhotoConfig()` switch statement.
- The centralized script can also control whether the gallery container is shown/hidden, same as any other field.

---

## 13. ~~Surgery Case~~ — ALREADY DELETED (legacy, replaced by Dispatch Case)

### 13.1 ~~surgery_case~~ — ALREADY DELETED

- **Type:** Link → Surgery Case (was custom on Task in prod, hidden=1)
- **Current state (test):** Not defined in `custom-fields.json`. Only stale references remain in `field_order` and `reports.json` SQL queries.
- **Current state (prod):** Exists as hidden custom field. Surgery Case DocType still exists in prod but is unused.
- **Decision:** ALREADY GONE on test. Clean up stale references.

  The Surgery Case model was superseded by the Unified Dispatch Flow (Doc 16). `Dispatch Case` with `return_expected = Yes` replaces `Surgery Case`. All tasks now link via `dispatch_case`, not `surgery_case`.

  **Stale references to clean up:**

  | Item | What to fix |
  |---|---|
  | `field_order` in property-setters.json | Remove `surgery_case` |
  | `Stock Entry-dispatch_group_id.insert_after` | Points to `surgery_case` — repoint to another field |
  | `reports.json` SQL queries (lines 2817, 2959) | Reference `tabSurgery Case` / `t.surgery_case` — will fail, rewrite or remove |
  | Prod: `Task-surgery_case`, `Stock Entry-surgery_case`, `Sales Invoice-surgery_case` | Remove when prod is cleaned up |
  | Prod: `Surgery Case` DocType | Remove when prod is cleaned up |

---

### 13.2 ~~custom_select_surgical_kit_template~~ — DELETE from Task, KEEP on Dispatch Case

- **Type:** Link → Surgical Kit Template (was custom on Task in prod, hidden=1)
- **Current state (test):** Not defined on Task. Exists on **Dispatch Case** (actively used by `Dispatch Case-Template Auto Fill.js`).
- **Current state (prod):** Exists on Task as hidden custom field. Never used by any script on Task.
- **Decision on Task:** DELETE. Clean up stale references.
- **Decision on Dispatch Case:** KEEP. But centralize its visibility:
  - **Visible** only when Dispatch Case is in Draft (before submission). This is when the user selects items.
  - **Hidden** after submission — the template was already applied, showing it is misleading.
  - Visibility should be managed by a centralized Dispatch Case visibility script (same pattern as Task centralization).

  **Stale Task references to clean up:**

  | Item | What to fix |
  |---|---|
  | `field_order` in property-setters.json | Remove `custom_select_surgical_kit_template` from Task field order |
  | `dispatch_case.insert_after` | Points to `custom_select_surgical_kit_template` on Task — repoint to another field |
  | Prod: `Task-custom_select_surgical_kit_template` | Remove when prod is cleaned up |

---

## 14. Product Work Section — CENTRALIZED

> **Architecture:** All 13 product-work fields are purely client-side UI controls. No server script reads or writes any of them. All real product data lives on `Dispatch Case.case_items`. These fields are input forms that call server APIs (`task_add_dispatch_product`, `task_lookup_product_barcode`, `dispatch_case_packing_scan`) which write to the DC.

### Master visibility rule

One toggle on the section break controls everything inside it:

```javascript
var PRODUCT_EDIT_KINDS = [
    "Pack / prepare items",
    "Returns processing / verification"
];
// Order entry gets product UI via dispatch_case link (after DC is created)
var is_product_task = PRODUCT_EDIT_KINDS.indexOf(frm.doc.task_kind) !== -1
    || (frm.doc.task_kind === "Order entry" && !!frm.doc.dispatch_case);

// Section toggle — shows summary + scan/add area for product kinds only
frm.toggle_display("custom_product_work_section", is_product_task);

// Scan fields: Pack + Returns only (scan to identify/verify items)
var is_scan_task = (frm.doc.task_kind === "Pack / prepare items")
    || (frm.doc.task_kind === "Returns processing / verification");
frm.toggle_display("custom_task_scan_barcode", is_scan_task);
frm.toggle_display("custom_task_scan_qty", is_scan_task);
frm.toggle_display("custom_task_scan_result", is_scan_task);

// Manual add fields: Order entry only (add items to DC)
var is_add_task = (frm.doc.task_kind === "Order entry" && !!frm.doc.dispatch_case);
frm.toggle_display("custom_task_add_item_code", is_add_task);
frm.toggle_display("custom_task_add_qty", is_add_task);
frm.toggle_display("custom_task_add_batch_no", is_add_task);
frm.toggle_display("custom_task_add_unit_price", is_add_task);
```

This replaces ALL per-field hiding in 5 separate scripts.

**Only 3 kinds see the product work section, each with different controls:**

| Task kind | Summary | Scan | Manual add | What they do |
|---|---|---|---|---|
| **Pack / prepare items** | Yes (packing checkboxes) | Yes | **No** | Scan barcode → verify packed. Tick checkboxes. Cannot add/remove items. |
| **Returns proc.** | Yes (return qty inputs) | Yes | **No** | Scan barcode → identify product. Fill in returned/lost qty. Cannot add/remove items. |
| **Order entry** (with DC) | Yes (item list) | **No** | Yes | Pick product, set qty/batch/price, add to DC. |

**Key constraint:** Pack and Returns workers cannot add or remove items from the DC table — they can only edit their own columns (packing status for Pack, returned_qty/lost_damaged_qty for Returns).

**All other kinds** (Delivery, Pickup Returns, Return drop-off, Restocking, Invoice prep, Discount Approval, Dispatch picking) see no product section. They can view items on the DC page via "Open DC".

### 14.1 custom_product_work_section — Products / Dispatch Work (Section Break)

- **Type:** Section Break (custom)
- **Current hidden:** 0 | **Current depends_on:** none
- **Visible for task kinds (proposed):** Pack, Returns processing, Order entry (with DC only)
- **Decision:** DECIDED
  - **Hidden** by default (schema hidden=1).
  - **Shown** by centralized script using `is_product_task` (see master rule above).
  - Hiding this section hides ALL child fields (14.2, 14.3) automatically.

### 14.2 custom_task_product_summary — Product Summary (HTML)

- **Type:** HTML (custom, read_only=1)
- **Decision:** DECIDED — inherits visibility from parent section. No individual toggle needed.
- **Notes:** Populated by `Task-Product Work Area.js` from `Dispatch Case.case_items`. Read-only always.

### 14.3 custom_product_lines — DEAD TABLE, REMOVE

- **Type:** Table → Task Product Line (custom)
- **Decision:** DECIDED — **REMOVE**
  - This table is **never populated** by any active code. No scan, no add, no server script writes to it.
  - The product summary HTML renders from `Dispatch Case.case_items`, not from this table.
  - The only code touching it is `Task Product Line-Item Code String Guard.js` (string coercion on validate) — also dead.
  - **Migration:** Set hidden=1 in schema. Delete the custom field once confirmed no data exists. Delete `Task Product Line-Item Code String Guard.js`.

---

## 15. Barcode Scanning — CENTRALIZED

Scan fields live inside `custom_product_work_section` (section 14), NOT inside `custom_barcode_section`. The scan fields are the left column of the product work section layout.

**Scan is for Pack + Returns only.** Order entry does NOT get scan — users add items manually via the right-column fields (section 16).

> **Note on `custom_barcode_section`:** Despite its name, this section break only wraps the dead `custom_product_lines` table (14.3). It is NOT the barcode scanning section. It is deleted along with `custom_product_lines`.

### 15.1 ~~custom_barcode_section~~ — DEAD SECTION, REMOVE

- **Type:** Section Break (custom), label "Barcode Scanning (Optional)"
- **Decision:** DECIDED — **REMOVE** along with `custom_product_lines` (14.3).
  - This section only contains the dead `custom_product_lines` table.
  - The actual scan fields (15.2–15.4) are inside `custom_product_work_section`, not here.
  - Delete this section break from schema.

### 15.2 custom_task_scan_barcode — Scan Product Barcode

- **Type:** Data (custom)
- **Current depends_on:** `eval:doc.task_kind !== "Debt Collection"` — **REMOVE**
- **Parent section:** `custom_product_work_section` (14.1)
- **Decision:** DECIDED
  - **Visible** for Pack + Returns only (`is_scan_task`). Hidden for Order entry and all others.
  - **Editable** only for accepted users.
  - Replaces per-field toggles in `Task-Accept Start.js`, `Task-Account Details UI Cleanup.js`, `Task-Other UI Cleanup.js`, `Task-Lock Unaccepted.js`.
  - **Remove autofocus.** Currently `Task-Product Work Area.js` calls `task_product_work_area_focus_scan()` on refresh, which auto-focuses and clears this input every time the Task form loads. This is disruptive — it steals focus from whatever the user intended to do. Autofocus should only happen when the user explicitly initiates a scan action (e.g. clicks "Scan Product Barcode" button), not on form load.

### 15.3 custom_task_scan_qty — Scan Qty

- **Type:** Float (custom, default=1)
- **Decision:** DECIDED — same as 15.2. Visible for Pack + Returns only. Editable for accepted users.

### 15.4 custom_task_scan_result — Last Scan Result

- **Type:** Small Text (custom, read_only=1)
- **Decision:** DECIDED — same as 15.2. Visible for Pack + Returns only. Always read-only (set by scan logic).

---

## 16. Manual Product Add — CENTRALIZED

Manual add fields are the right column of `custom_product_work_section` (section 14). They let the user pick a product, set qty/batch/price, and add it to the Dispatch Case.

**Manual add is for Order entry only.** Pack and Returns workers cannot add or remove items — they can only edit their own columns (packing status for Pack, returned_qty/lost_damaged_qty for Returns).

### 16.1 custom_product_work_column — (Column Break)

- **Type:** Column Break (custom)
- **Parent section:** `custom_product_work_section` (14.1)
- **Decision:** DECIDED — inherits visibility from parent section. Layout element, no individual toggle.

### 16.2 custom_task_product_warning — Product Work Warning

- **Type:** Small Text (custom, read_only=1)
- **Parent section:** `custom_product_work_section` (14.1)
- **Decision:** DECIDED — inherits visibility from parent section. Always read-only. Populated by `Task-Product Work Area.js` from DC's `custom_packing_last_warning` / `custom_packing_problem_summary`. Shown for all 3 product kinds (Pack, Returns, Order entry).

### 16.3 custom_task_add_item_code — Choose Product

- **Type:** Link → Item (custom)
- **Decision:** DECIDED — **visible for Order entry only** (`is_add_task`). Hidden for Pack and Returns. Editable for accepted users.

### 16.4 custom_task_add_qty — Product Qty

- **Type:** Float (custom, default=1)
- **Decision:** DECIDED — same as 16.3. Order entry only.

### 16.5 custom_task_add_batch_no — Batch / LOT

- **Type:** Link → Batch (custom)
- **Decision:** DECIDED — same as 16.3. Order entry only. Mobile: keep visible (the old mobile-hide in `Task-Accept Start.js:151` is removed — users may need to select a batch on mobile).

### 16.6 custom_task_add_unit_price — Unit Price

- **Type:** Currency (custom)
- **Decision:** DECIDED — same as 16.5. Order entry only.

---

### Product Work — scripts impact summary

| Script | Action | Detail |
|---|---|---|
| `Order entry - barcode scanning section - hide.js` | **DELETE** | DOM surgery script. Entirely replaced by centralized section toggle. |
| `Task-Account Details UI Cleanup.js` | **MODIFY** | Remove all product/scan field hiding (lines 29–47, 62, 83–86). Section toggle handles it. |
| `Task-Other UI Cleanup.js` | **MODIFY** | Remove all product/scan field hiding (lines 38, 40, 43–45). Section toggle handles it. |
| `Task-Accept Start.js` | **MODIFY** | Remove scan/add field hiding for Account Details (lines 15–22). Remove mobile batch/price hide (line 151). |
| `Task-Lock Unaccepted.js` | **MODIFY** | Remove per-field scan/add read_only toggles (lines 34–45). Centralized script handles editable state. |
| `Task Product Line-Item Code String Guard.js` | **DELETE** | Only consumer of dead `custom_product_lines` table. |
| `Task-Packing Checkboxes.js` | **ALREADY DISABLED** | Duplicate of Product Work Area. |
| `Task-Dispatch Packing Usability.js` | **ALREADY DISABLED** | Legacy. |
| `Task-Create Dispatch Case Items.js` | **ALREADY DISABLED** | Legacy. |
| `Task-Product Lines Display.js` | **ALREADY DISABLED** | Legacy. |
| Schema (`custom-fields.json`) | **MODIFY** | Set hidden=1 on remaining 10 fields. Remove all depends_on expressions. |
| Schema (`custom-fields.json`) | **DELETE** | Remove `custom_product_lines` field, `custom_barcode_section` section break, and `Task Product Line` child DocType. |

---

## 17. ~~Account Details~~ — REMOVE ENTIRELY

> **Decision:** Remove the Account Details workflow from the system. The Account Details: Entry / Processing pair is architecturally identical to Other: Entry / Processing — both are two-step Entry → Processing workflows with manual creation, photo attachment, description propagation, and assignment handoff. There is no reason to maintain a parallel implementation. Users should use **Other: Entry / Other: Processing** instead, which already supports subject, description, customer, photos (via `Task-Photo-System.js`), and `custom_next_task_assign_to`.

### What to delete

| Item | Type | Action |
|---|---|---|
| `custom_account_details_section` | Section Break | **DELETE** from schema |
| `custom_account_photos` | Table → Account Detail Attachment | **DELETE** from schema |
| `custom_account_details_entry_task` | Link → Task | **DELETE** from schema |
| `custom_account_details_subject` | Data | **DELETE** from schema |
| `Account Detail Attachment` | Child DocType | **DELETE** |
| `Task-Account Details UI Cleanup.js` | Client Script (294 lines) | **DELETE** |
| `Task-after-save-account-details-processing.py` | Server Script | **DELETE** |
| Task Access Policy `Account Details: Entry` | Record | **DELETE** |
| Task Access Policy `Account Details: Processing` | Record | **DELETE** |
| `task_kind` options | Select values | **REMOVE** `Account Details: Entry` and `Account Details: Processing` |

### Why

- The Account Details pair duplicates Other: Entry/Processing with more bugs and complexity.
- Its custom photo gallery (294-line DOM surgery with 4 cascading timeouts) duplicates `Task-Photo-System.js`.
- `custom_account_details_subject` is broken — never filled, so Processing tasks always get the generic default.
- `custom_account_photos` child table is redundant — the gallery uses File records, not child rows, yet the server copies both.
- The `depends_on` on `custom_account_photos` references `"Account details"` (a kind that doesn't exist) — has been broken since the kinds were renamed to `Account Details: Entry` / `Account Details: Processing`.
- `custom_account_details_section` is permanently hidden with a fake `depends_on` (`"__never_show_account_details_documents__"`).

### Migration

1. Complete or cancel any existing `Account Details: Entry` / `Account Details: Processing` tasks.
2. Delete all items listed above.
3. Instruct users to create **Other: Entry** tasks for document/photo intake work.
4. If the accounting team needs a distinct default assignment, add a note in the Other: Entry task description or adjust the Task Access Policy for Other: Processing.

---

## 18. Standard Frappe Fields (modified by property setters)

These are NOT custom fields but their behavior is modified.

### 18.1 status — Status — ALWAYS HIDDEN (centralized)

- **Type:** Select (standard)
- **Property setter options:** Open, Working, Overdue, Completed, Cancelled
- **Current client script overrides:**
  - `Task-Accept Start.js:33` — shown for Account Details: Entry
  - `Task-Other UI Cleanup.js:19,38` — shown for Other
  - `Task-Account Details UI Cleanup.js:118-119` — shown for Account Details
- **Decision:** DECIDED — **Always hidden.** Status is managed by the system (server scripts set it on acceptance, completion, etc.). Users should not see or edit it directly — they interact through action buttons. The defensive show-for-certain-kinds overrides are unnecessary and should be removed.
  - Set hidden=1 via property setter.
  - Remove all client script `toggle_display("status", ...)` calls.
  - Centralized script enforces hidden state.

---

### 18.2 priority — Priority — ALWAYS HIDDEN (centralized)

- **Type:** Select (standard)
- **Current client script overrides:**
  - Same scripts as status — shown explicitly for Account Details and Other
- **Decision:** DECIDED — **Always hidden.** Priority is not used in InMED's operational workflow — tasks are driven by kind, ownership, and stage gates, not priority levels. The explicit show overrides are unnecessary.
  - Set hidden=1 via property setter.
  - Remove all client script `toggle_display("priority", ...)` calls.
  - Centralized script enforces hidden state.

---

### 18.3 Permanently hidden standard fields — CENTRALIZE

These are hidden via property setters and have no client script overrides:

| Field | Why hidden |
|---|---|
| project | Not used in InMED workflow |
| issue | Not used |
| type | Not used |
| color | Not used |
| is_group | Not used (in_list_view also set to 0) |
| task_weight | Not used |
| parent_task | Not used |
| is_template | Not used |

**Decision:** DECIDED — **Keep hidden. Centralize enforcement.** Property setters already hide these, but the centralized visibility script should also enforce hidden state as the single source of truth. This prevents any other script from accidentally revealing them.

---

## Summary: Fields that need decisions

### Already decided (internal, keep hidden=1)

- task_access_policy, dispatch_group_id, custom_accepted_by, custom_account_details_entry_task, custom_account_details_section, 8 standard Frappe fields

### Clean single-kind fields (straightforward visibility)

- delivery_status (Delivery), pickup_status (Pickup Returns), purchase_order (Purchase Approval)

### Fields with known bugs to fix

| Field | Bug |
|---|---|
| custom_account_photos | depends_on uses wrong name "Account details" |
| custom_account_details_subject | No depends_on — visible on ALL kinds |
| driver_handover_note | hidden=1 kills depends_on — dead field or needs fix |
| custom_account_details_section | Fake depends_on with nonsense value |

### Fields with major visibility gaps (visible where irrelevant)

| Field group | Currently visible on | Should probably be restricted to |
|---|---|---|
| Product work section (14 fields) | All except Acct Details, Other | Dispatch kinds + Order entry? |
| Barcode scanning (4 fields) | All except Debt Collection, Acct Details, Other | Same as product section? |

### Fields needing behavioral investigation

| Field | Why |
|---|---|
| custom_account_photos | Has custom photo box replacement (DOM surgery) |
| subject | Auto-set for Order entry, behavioral component |
| task_kind | Should it be editable after creation? |
| custom_next_task_assign_to | 4 conflicting visibility mechanisms |

### Architectural decision: separate visibility script

**DECIDED — Option B.** A new standalone client script `Task-Field-Visibility.js`.

- Single responsibility: one script owns all field/section show/hide logic based on `task_kind`.
- `Task-Action Buttons.js` keeps its responsibility (buttons + mobile CSS).
- Other scripts (`Task-Product Work Area.js`, `Task-Photo-System.js`, etc.) handle their own rendering/behavior but do NOT toggle field visibility — they check whether they're visible and act accordingly.
- The visibility script runs on `refresh` and `task_kind` change. It is the only place that calls `frm.toggle_display()` for task-kind-driven visibility.
