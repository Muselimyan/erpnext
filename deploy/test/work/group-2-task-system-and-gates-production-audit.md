# Group 2 — Task System and Gates: Production Audit

> **Scope**: Every server script, client script, custom field, property setter, and custom DocType that controls task creation, acceptance, locking, role-based access, status enforcement, assignment, team queues, auto-escalation, and the task-kind-specific flows for Account Details, Other, Discount Approval, Purchase Approval, and Debt Closure.
>
> **Method**: Line-by-line reading of every deployed script file under `deploy/test/work/`, cross-referenced against schema metadata (`deploy/test/schema/*.json`) and documentation (`docs/10*`, `docs/03*`, `docs/16*`).
>
> **Evidence discipline**: Every finding states its evidence basis. "Confirmed from source" means verified in the extracted `.py`/`.js` file. "Confirmed from schema" means verified in the schema JSON. "Inferred" means the conclusion follows logically but runtime confirmation is useful. "Requires runtime validation" means the finding cannot be confirmed without querying the live system.
>
> **Confidence scale**:
> - **0.95–1.00**: Directly confirmed from extracted deployed source and/or schema metadata.
> - **0.80–0.94**: Strongly supported by code and cross-file evidence; runtime/business confirmation still useful.
> - **0.60–0.79**: Plausible interpretation or likely issue requiring targeted validation.
> - **Below 0.60**: Hypothesis/open question — not suitable for remediation without confirmation.
>
> **Date**: 2025-01-XX (analysis performed against test-instance extraction)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Scope and Evidence Sources](#2-scope-and-evidence-sources)
3. [Script Inventory](#3-script-inventory)
4. [Functional Architecture](#4-functional-architecture)
5. [Script-by-Script Analysis: Server Scripts](#5-script-by-script-analysis-server-scripts)
6. [Script-by-Script Analysis: Client Scripts](#6-script-by-script-analysis-client-scripts)
7. [Cross-Script Interaction Analysis](#7-cross-script-interaction-analysis)
8. [Documentation Comparison Matrix](#8-documentation-comparison-matrix)
9. [Bugs and Risks](#9-bugs-and-risks)
10. [Disabled/Legacy Code Assessment](#10-disabledlegacy-code-assessment)
11. [Undocumented Production Decisions](#11-undocumented-production-decisions)
12. [Confidence-Scored Findings Summary](#12-confidence-scored-findings-summary)
13. [Items Requiring Runtime Validation](#13-items-requiring-runtime-validation)
14. [Recommended Next Steps](#14-recommended-next-steps)

---

## 1. Executive Summary

Group 2 contains **15 server scripts** (11 enabled, 4 disabled) and **14 client scripts** (13 enabled, 1 disabled) that together form the operational backbone of the entire ERPNext customization. Every workflow step — from order entry through delivery, returns, invoicing, payment, and approval — depends on the task system working correctly.

### Key Findings

| Category | Count | Severity |
|---|---|---|
| Confirmed production bugs | 4 | HIGH |
| Likely bugs requiring validation | 5 | MEDIUM-HIGH |
| Documentation mismatches | 12 | MEDIUM |
| Undocumented production decisions | 8 | LOW-MEDIUM |
| Disabled/legacy code items | 4 | LOW |
| Duplicate/conflicting implementations | 6 | MEDIUM |
| Missing server-side enforcement | 3 | HIGH |

### Highest-Priority Issues

1. **Assignment validation is fully disabled** (lines 72-83 of `Task-before-save-policy.py`) — the documented rule that "each task must be assigned to exactly 1 user" is commented out. Any number of users (including zero) can be assigned without error. **Confidence: 0.98**

2. **Role mapping drift across 4 scripts** — `dispatch_task_accept.py`, `task_list_filtered.py`, `Task-before-save-policy.py`, and `dispatch_task_queue_backfill.py` each contain their own `TASK_KIND_ALLOWED_ROLES` dict and they are inconsistent. **Confidence: 0.98**

3. **`Task-Account Details Default Assignment.py` uses wrong task_kind string** — script checks `"Account details"` (lowercase d) but the policy script and task_list_filtered use `"Account Details: Entry"` and `"Account Details: Processing"`. The script will never match actual Account Details tasks. **Confidence: 0.95**

4. **`task_list_filtered.py` contains hardcoded user email addresses** — five specific Gmail addresses are hardcoded as `ACCOUNT_DETAILS_MY_TASK_USERS`, creating a maintenance and security concern. **Confidence: 1.00**

5. **Duplicate list-view toggle implementations** — `Task-List Toggle Filters.js` and `Global-Mobile Back Button List.js` both implement toggle filter bars for the Task list view. The two scripts compete: one uses client-side filters, the other calls the `task_list_filtered` API. Last-loaded wins. **Confidence: 0.95**

6. **Payment recording bug** — `Task-before-save-payment-recording.py` allocates payments to `row.allocated_now` then zeros it out, but subsequently tries to use `row.allocated_now > 0` to build Payment Entry references — which will always be 0. The Payment Entry is created with no invoice references. **Confidence: 0.95**

---

## 2. Scope and Evidence Sources

### Scripts Analyzed

| Source | Type | Count |
|---|---|---|
| `deploy/test/work/server/*.py` | Group 2 server scripts | 15 |
| `deploy/test/work/client/*.js` | Group 2 client scripts | 14 |
| Cross-group server scripts read for interaction analysis | 8 |
| Cross-group client scripts read for interaction analysis | 6 |

### Schema Files

| File | Relevant entries |
|---|---|
| `deploy/test/schema/server-scripts.json` | 20 Task-related entries |
| `deploy/test/schema/client-scripts.json` | 23 Task-related entries |
| `deploy/test/schema/custom-fields.json` | 62 fields on Task |
| `deploy/test/schema/property-setters.json` | 44 setters on Task |
| `deploy/test/schema/custom-doctypes.json` | 3 Task-specific DocTypes |

### Documentation

| Document | Relevance |
|---|---|
| `docs/10-task-system-foundations.md` | Primary spec for task kinds, lifecycle, gates |
| `docs/10-task-system-foundations-implementation.md` | Implementation guide with role maps |
| `docs/10.1-directors-task-dashboard.md` | Dashboard filters and TV user |
| `docs/03-roles-permissions-responsibilities.md` | Role definitions and team ownership |
| `docs/03-roles-permissions-responsibilities-implementation.md` | Role implementation |
| `docs/16-unified-dispatch-flow.md` | Dispatch Case task chain, team user pattern |
| `docs/16a-unified-dispatch-flow-implementation.md` | Implementation (noted as potentially stale) |
| `docs/16b-unified-dispatch-flow-gap-analysis.md` | Known gaps as of deployment |

### Audit Plan Discrepancy

The audit plan header states "9 enabled, 4 disabled" server scripts for Group 2. The actual table lists **11 enabled + 4 disabled = 15 total**. The header count is wrong. **Confidence: 1.00**

Additionally, the schema subagent found the schema JSON contains only **2 disabled** Task DocType Event scripts (`Task-after-insert-assign`, `Task-before-save-return-dropoff-photo`) plus 1 disabled API-related script (`Task-dispatch-queue-integration`). The fourth disabled script `Task-team-queue-notify` is confirmed disabled in its source file header but may have a different naming in the schema. This discrepancy requires checking whether the schema extraction captured all scripts. **Confidence: 0.85**

---

## 3. Script Inventory

### Server Scripts — Group 2

| # | Script | Type | Event | Enabled | Lines | File |
|---|---|---|---|---|---|---|
| 1 | `Task-before-save-policy` | DocType Event | Before Save | **Yes** | 85 | `server/Task-before-save-policy.py` |
| 2 | `Task-before-save-lock-completed` | DocType Event | Before Save | **Yes** | 10 | `server/Task-before-save-lock-completed.py` |
| 3 | `Task-before-save-lock-unaccepted` | DocType Event | Before Save | **Yes** | 36 | `server/Task-before-save-lock-unaccepted.py` |
| 4 | `Task-before-save-auto-subject` | DocType Event | Before Save | **Yes** | 11 | `server/Task-before-save-auto-subject.py` |
| 5 | `Task-Account Details Default Assignment` | DocType Event | Before Save | **Yes** | 31 | `server/Task-Account Details Default Assignment.py` |
| 6 | `Task-Other Entry Default Subject` | DocType Event | Before Save | **Yes** | 13 | `server/Task-Other Entry Default Subject.py` |
| 7 | `Task-after-save-account-details-processing` | DocType Event | After Save | **Yes** | 80 | `server/Task-after-save-account-details-processing.py` |
| 8 | `Task-after-save-other-processing` | DocType Event | After Save | **Yes** | 45 | `server/Task-after-save-other-processing.py` |
| 9 | `dispatch_task_accept` | API | — | **Yes** | 86 | `server/dispatch_task_accept.py` |
| 10 | `dispatch_task_queue_backfill` | API | — | **Yes** | 53 | `server/dispatch_task_queue_backfill.py` |
| 11 | `doc15_task_auto_escalation` | Scheduler Event | — | **Yes** | 68 | `server/doc15_task_auto_escalation.py` |
| 12 | `Task-after-insert-assign` | DocType Event | After Insert | **DISABLED** | 19 | `server/Task-after-insert-assign.py` |
| 13 | `Task-dispatch-queue-integration` | DocType Event | After Save | **DISABLED** | 46 | `server/Task-dispatch-queue-integration.py` |
| 14 | `Task-team-queue-notify` | DocType Event | After Save | **DISABLED** | 72 | `server/Task-team-queue-notify.py` |
| 15 | `Task-before-save-return-dropoff-photo` | DocType Event | Before Save | **DISABLED** | 19 | `server/Task-before-save-return-dropoff-photo.py` |

### Cross-Group Server Scripts Analyzed (not in Group 2 but critical for interaction)

| Script | Group | Event | Enabled |
|---|---|---|---|
| `Task-before-save-dispatch-gates` | Group 1 | Before Save | Yes |
| `Task-after-save-dispatch-flow` | Group 1 | After Save | Yes |
| `Task-before-save-pack-complete-creates-delivery-task` | Group 1 | Before Save | Yes |
| `Task-before-save-discount-approval-writeback` | Group 4 | Before Save | Yes |
| `Task-purchase-approval-writeback` | Group 4 | Before Save | Yes |
| `Task-before-save-payment-recording` | Group 3 | Before Save | Yes |
| `Task-after-save-advance-payment` | Group 3 | After Save | Yes |
| `Task-after-save-debt-closure` | Group 3 | After Save | Yes |

### Client Scripts — Group 2

| # | Script | DocType | Enabled | Lines | File |
|---|---|---|---|---|---|
| 1 | `Task-Accept Start` | Task | **Yes** | 509 | `client/Task-Accept Start.js` |
| 2 | `Task-Account Details UI Cleanup` | Task | **Yes** | 284 | `client/Task-Account Details UI Cleanup.js` |
| 3 | `Task-Auto Reload` | Task | **Yes** | 32 | `client/Task-Auto Reload.js` |
| 4 | `Task-Dispatch Packing Usability` | Task | **Yes** | 34 | `client/Task-Dispatch Packing Usability.js` |
| 5 | `Task-Inspect Returns Next Assign Visible` | Task | **Yes** | 26 | `client/Task-Inspect Returns Next Assign Visible.js` |
| 6 | `Task-List Toggle Filters` | Task | **Yes** | 84 | `client/Task-List Toggle Filters.js` |
| 7 | `Task-Lock Completed` | Task | **Yes** | 6 | `client/Task-Lock Completed.js` |
| 8 | `Task-Lock Unaccepted` | Task | **Yes** | 69 | `client/Task-Lock Unaccepted.js` |
| 9 | `Task-Other UI Cleanup` | Task | **Yes** | 176 | `client/Task-Other UI Cleanup.js` |
| 10 | `Task-Team Queue` | Task | **Yes** | 65 | `client/Task-Team Queue.js` |
| 11 | `Order entry - barcode scanning section - hide` | Task | **Yes** | 340 | `client/Order entry - barcode scanning section - hide.js` |
| 12 | `Task - Load Surgical Kit Template` | Task | **Yes** | 39 | `client/Task - Load Surgical Kit Template.js` |
| 13 | `Global-Mobile Back Button List` | Task | **Yes** | 141 | `client/Global-Mobile Back Button List.js` |
| 14 | `Task-Hide Sidebar Assignment` | Task | **DISABLED** | 52 | `client/Task-Hide Sidebar Assignment.js` |

---

## 4. Functional Architecture

### Before Save Execution Order (Server-Side)

All these fire on `Task.before_save` and ERPNext does **not** guarantee execution order among multiple server scripts on the same event. The scripts are:

1. `Task-before-save-lock-completed` — blocks if already Completed
2. `Task-before-save-lock-unaccepted` — blocks if not accepted
3. `Task-before-save-policy` — role enforcement, auto-fills task_access_policy, sets completed_at
4. `Task-before-save-auto-subject` — auto-generates 5-digit subject
5. `Task-Account Details Default Assignment` — default assignment for "Account details" tasks
6. `Task-Other Entry Default Subject` — default subject for Other tasks
7. `Task-before-save-dispatch-gates` (Group 1) — acceptance gates, delivery/pickup state machine, packing/photo validation
8. `Task-before-save-pack-complete-creates-delivery-task` (Group 1) — creates Delivery task on Pack completion
9. `Task-before-save-discount-approval-writeback` (Group 4) — writes back to Sales Order
10. `Task-purchase-approval-writeback` (Group 4) — writes back to Purchase Order
11. `Task-before-save-payment-recording` (Group 3) — creates Payment Entry for Debt Collection

**Risk**: There are **11 enabled Before Save scripts** on the Task DocType. Their relative execution order is undefined by ERPNext's Server Script framework. If script A depends on state set by script B, behavior is fragile. See Section 7 for detailed interaction analysis.

### After Save Execution Order (Server-Side)

1. `Task-after-save-dispatch-flow` (Group 1) — main orchestrator: stock entries, invoice, next task
2. `Task-after-save-account-details-processing` — creates Processing task from Entry
3. `Task-after-save-other-processing` — creates Processing task from Entry
4. `Task-after-save-advance-payment` (Group 3) — creates Payment Entry for advance payment
5. `Task-after-save-debt-closure` (Group 3) — creates Debt Closure Approval task

### Client-Side Script Loading

ERPNext loads all enabled client scripts for a DocType when the form loads. Multiple scripts binding to the same event (e.g., `refresh`) all execute, but the order depends on script loading order. Key overlaps:

- **7 scripts** bind to `frappe.ui.form.on("Task", { refresh: ... })` — all execute on every form refresh
- **3 scripts** bind to `frappe.listview_settings['Task'].onload` — last-loaded overwrites previous

---

## 5. Script-by-Script Analysis: Server Scripts

### 5.1 Task-before-save-policy.py

**File**: `server/Task-before-save-policy.py` | **Lines**: 85 | **Enabled**: Yes | **Event**: Before Save

**Purpose**: Central policy enforcement — role-based access control, task_access_policy validation, mandatory attachments for old-flow tasks, assignment validation (disabled), completed_at timestamp.

**What it does**:
1. **Lines 8-10**: Detects when task is becoming Completed.
2. **Lines 12-33**: Defines `TASK_KIND_ALLOWED_ROLES` mapping — 18 task kinds to allowed roles.
3. **Lines 48-49**: Auto-fills `task_access_policy` from `task_kind` if missing.
4. **Lines 50-51**: Validates that `task_access_policy` exists as a Task Access Policy record.
5. **Lines 54-56**: Blocks editing by users who don't have allowed roles for the task kind.
6. **Lines 57-59**: Blocks completion by users who don't have allowed roles.
7. **Lines 60-69**: Old-flow mandatory photo gates (only for tasks NOT linked to a Dispatch Case).
8. **Lines 72-83**: **COMMENTED OUT** — assignment validation (exactly 1 user, user must have allowed role).
9. **Lines 84-85**: Auto-sets `completed_at` when becoming Completed.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| P-1 | **Assignment validation is fully disabled.** Lines 72-83 are commented out with note "TEMPORARILY DISABLED FOR LAUNCH." Doc 10 requires "each operational task must have exactly 1 assignee." This means tasks can have 0 or N assignees without server-side enforcement. | Production Bug (intentional bypass, still active) | 0.98 |
| P-2 | **Role map includes `"Return Call"` with 5 allowed roles** (line 18), but `dispatch_task_accept.py` does NOT include `"Return Call"` in its role map. Return Call tasks can be edited per policy but cannot be accepted via the API. | Role Mapping Inconsistency | 0.95 |
| P-3 | **Role map includes `"Distribute Payment"` and `"Payment Received"`** (lines 26-27), but `dispatch_task_accept.py` does NOT include these. These task kinds cannot be accepted via the accept API. | Role Mapping Inconsistency | 0.95 |
| P-4 | **`"Other"` task kind allows ALL operational roles** (line 32), including `"Delivery Driver"`. This means any user with any operational role can edit/complete Other tasks, which may be too permissive. | Documentation Gap (no "Other" task kind documented) | 0.90 |
| P-5 | **Old-flow photo gates (lines 60-69) only apply to tasks NOT linked to a Dispatch Case.** For Dispatch Case tasks, photo enforcement is handled by `Task-before-save-dispatch-gates.py` (Group 1). This is an intentional but undocumented split. | Intentional Undocumented Decision | 0.92 |
| P-6 | **`task_access_policy` auto-fill from `task_kind`** (line 49) assumes 1:1 naming. If a Task Access Policy record with the exact name of the task_kind doesn't exist, the save will throw. | Correct but Risky | 0.90 |

### 5.2 Task-before-save-lock-completed.py

**File**: `server/Task-before-save-lock-completed.py` | **Lines**: 10 | **Enabled**: Yes | **Event**: Before Save

**Purpose**: Prevents any modification to a Completed task.

**What it does**: If the task was previously `Completed`, throws an error blocking the save.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| LC-1 | **No exception for System Manager or Administrator.** Even an admin cannot modify a Completed task through the UI. The only workaround would be direct database modification. Doc 10 says "Auditability over convenience — don't delete tasks" but doesn't explicitly prevent admin edits to Completed tasks. | Stricter than documented | 0.95 |
| LC-2 | **No exception for `flags.ignore_permissions`.** Server-side scripts that set `flags.ignore_permissions = True` still cannot modify a Completed task because this script checks `before.status` unconditionally. However, scripts that use `frappe.db.set_value` (direct DB write) bypass this entirely. | Correct but Bypassable | 0.90 |

### 5.3 Task-before-save-lock-unaccepted.py

**File**: `server/Task-before-save-lock-unaccepted.py` | **Lines**: 36 | **Enabled**: Yes | **Event**: Before Save

**Purpose**: (1) Resets acceptance when assignment changes. (2) Requires acceptance before editing. (3) Validates assignment: must be assigned to a User OR a Team, not both.

**What it does**:
1. **Lines 11-20**: If assignment changes (`custom_assigned_to` or `custom_team_queue_role`), resets `custom_accepted_by`, `custom_accepted_at`, and sets status to "Open".
2. **Lines 22-24**: Skips for users with `System Manager` role or `Administrator`.
3. **Lines 26-29**: Validates mutual exclusion: task must be assigned to User XOR Team.
4. **Lines 31-36**: For existing tasks, requires `custom_accepted_by` to be set and to match the current user.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| LU-1 | **Assignment validation is MORE restrictive than `Task-before-save-policy.py`.** Policy script's assignment check is commented out, but this script enforces User XOR Team. However, this script also has an `ignore_permissions` bypass (line 22) — scripts creating tasks with `flags.ignore_permissions = True` skip this validation. This means programmatically-created tasks (from dispatch flow, etc.) can bypass the User XOR Team rule. | Mixed Enforcement | 0.90 |
| LU-2 | **Acceptance reset on reassignment is undocumented.** Doc 10 and Doc 16 don't mention that reassigning a task forces re-acceptance. This is a good safety feature but is not documented. | Undocumented Production Decision | 0.92 |
| LU-3 | **Uses raw SQL for role lookup** (line 23) instead of `frappe.get_all("Has Role", ...)`. Functionally equivalent but less idiomatic. | Code Quality | 0.95 |

### 5.4 Task-before-save-auto-subject.py

**File**: `server/Task-before-save-auto-subject.py` | **Lines**: 11 | **Enabled**: Yes | **Event**: Before Save

**Purpose**: Auto-generates a 5-digit zero-padded numeric subject if the task has no subject.

**What it does**: Queries for the MAX numeric-only 5-digit subject, increments by 1, and sets it as the subject.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| AS-1 | **Not documented.** No documentation mentions auto-generated 5-digit task subjects. The docs assume subjects are manually entered or set by dispatching scripts. | Documentation Gap | 0.95 |
| AS-2 | **Race condition risk.** Two concurrent task saves with no subject could get the same MAX value and generate duplicate subjects. The SQL is not wrapped in a lock. Practically low risk since subjects aren't used as unique keys. | Correct but Risky | 0.80 |
| AS-3 | **Only fires when `subject` is falsy.** Dispatch flow and other scripts always set subjects before insert, so this only affects manually-created tasks with no subject. | Correct | 0.95 |

### 5.5 Task-Account Details Default Assignment.py

**File**: `server/Task-Account Details Default Assignment.py` | **Lines**: 31 | **Enabled**: Yes | **Event**: Before Save

**Purpose**: Sets default subject and assignment for "Account details" tasks. Creates a ToDo for the assignee.

**What it does**:
1. **Line 8**: Checks `task_kind == "Account details"` (note: lowercase 'd').
2. **Lines 9-13**: Sets subject to "Account details", sets `custom_assigned_to`, and writes `_assign` JSON directly.
3. **Lines 15-31**: For existing tasks, creates a ToDo if one doesn't already exist for the assignee.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| AD-1 | **WRONG TASK_KIND STRING.** The script checks for `"Account details"` (lowercase 'd'). But `Task-before-save-policy.py` uses `"Account Details: Entry"` and `"Account Details: Processing"`. The `task_kind` Select field options (from schema) show `"Account Details: Entry"` and `"Account Details: Processing"` — NOT `"Account details"`. This means this script **never fires** for actual Account Details tasks. | **Confirmed Production Bug** | 0.95 |
| AD-2 | **Hardcoded fallback email.** Uses `"accounting.team@example.com"` — this is a team placeholder email. If the task already has a `custom_assigned_to`, it uses that; otherwise falls back to the placeholder. Consistent with the team user pattern in Doc 16. | Undocumented but Consistent | 0.85 |
| AD-3 | **Directly writes `_assign` JSON** (line 13) — this bypasses ERPNext's assignment framework. See Finding P-1 context. Multiple scripts do this as a workaround for RestrictedPython limitations. | Known Workaround | 0.95 |

### 5.6 Task-Other Entry Default Subject.py

**File**: `server/Task-Other Entry Default Subject.py` | **Lines**: 13 | **Enabled**: Yes | **Event**: Before Save

**Purpose**: Sets default subject for "Other: Entry" and "Other: Processing" tasks.

**What it does**: If task_kind is "Other: Entry" or "Other: Processing" and subject is empty or generic ("New Task", "Other"), sets subject to the task_kind name.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| OE-1 | **"Other" task kinds are not documented.** Doc 10, Doc 03, and Doc 16 do not define "Other: Entry" or "Other: Processing" task kinds. These appear to be post-documentation additions. | Documentation Gap | 0.95 |
| OE-2 | **Correct implementation.** The script does what it's supposed to — sets default subjects. No bugs found. | Correct | 0.95 |

### 5.7 Task-after-save-account-details-processing.py

**File**: `server/Task-after-save-account-details-processing.py` | **Lines**: 80 | **Enabled**: Yes | **Event**: After Save

**Purpose**: When an "Account Details: Entry" task is completed, creates an "Account Details: Processing" task with the same data and file attachments.

**What it does**:
1. **Line 8**: Checks `task_kind == "Account Details: Entry"`.
2. **Lines 14-16**: Only fires on first completion, prevents duplicate by checking for existing task linked via `custom_account_details_entry_task`.
3. **Lines 17-19**: Uses `custom_next_task_assign_to` field for assignee override. If the override equals the current assignee, falls back to placeholder.
4. **Lines 23-58**: Creates new task, copies description/priority/customer/dates/photos, creates `_assign` and ToDo.
5. **Lines 60-80**: Copies all File attachments from the Entry task to the Processing task.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| ADP-1 | **"Account Details" flow is entirely undocumented.** This Entry→Processing chain has no corresponding documentation in any numbered doc. | Documentation Gap | 0.95 |
| ADP-2 | **Idempotent — checks for existing task before creating.** Uses `custom_account_details_entry_task` field as a link-back. Correct implementation. | Correct | 0.95 |
| ADP-3 | **Assignee fallback to `accounting.team@example.com`.** If `custom_next_task_assign_to` is not set or equals the current assignee, defaults to the accounting team placeholder. | Undocumented but Consistent | 0.90 |
| ADP-4 | **File copy loop** (lines 60-80) copies all attachments regardless of field. This means any file attached to the Entry task (photos, documents, etc.) gets duplicated. Could lead to storage bloat over time. | Correct but Risky | 0.75 |

### 5.8 Task-after-save-other-processing.py

**File**: `server/Task-after-save-other-processing.py` | **Lines**: 45 | **Enabled**: Yes | **Event**: After Save

**Purpose**: When an "Other: Entry" task is completed, creates an "Other: Processing" task.

**What it does**:
1. **Line 8**: Checks `task_kind == "Other: Entry"` and `status == "Completed"`.
2. **Line 9**: Duplicate check — looks for existing Processing task via `depends_on_tasks` LIKE match.
3. **Lines 10-29**: Creates new task with `custom_is_team_queue_task = 1`, `custom_team_queue_status = "Open For Team"`. Uses `depends_on` parent-child relationship. Respects `custom_next_task_assign_to`.
4. **Lines 30-45**: Copies file attachments.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| OP-1 | **Duplicate check uses fragile LIKE match** (line 9): `depends_on_tasks LIKE "%{doc.name}%"`. If a task name is a substring of another task name, this could produce false positives. Practically unlikely with auto-generated names. | Correct but Fragile | 0.80 |
| OP-2 | **Does NOT check `before_status != "Completed"`** — unlike Account Details processing, this fires every time the task is saved while status is "Completed", not just on first completion. The duplicate check (line 9) prevents creating multiple tasks, but it runs the duplicate check query on every save of a completed Other: Entry task. | Likely Bug (performance, not functional) | 0.85 |
| OP-3 | **Sets `custom_is_team_queue_task = 1` and `custom_team_queue_status = "Open For Team"`.** This is the team queue integration. But the team queue notify script (`Task-team-queue-notify.py`) is DISABLED, so no team members get notified of the new team queue task. | Functionality Gap | 0.90 |

### 5.9 dispatch_task_accept.py

**File**: `server/dispatch_task_accept.py` | **Lines**: 86 | **Enabled**: Yes | **Type**: API

**Purpose**: API endpoint for accepting/starting a task. Validates role, updates assignment, creates ToDo.

**What it does**:
1. **Lines 8-14**: Gets task, validates status is Open or Working.
2. **Lines 16-30**: Defines its own `TASK_KIND_ALLOWED_ROLES` map (13 task kinds — fewer than policy script's 18).
3. **Lines 31-39**: Validates user has required role.
4. **Lines 42-44**: For team-queue tasks, validates user has the team role.
5. **Lines 57-59**: Cancels existing open ToDos.
6. **Lines 62-63**: Direct DB write of `_assign`, then `frappe.db.commit()`.
7. **Lines 66-73**: Reloads task, sets status to "Working", records `custom_accepted_by`, `custom_accepted_at`, `custom_assigned_to`, clears `custom_team_queue_role`.
8. **Lines 76-84**: Creates new ToDo for accepting user.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| DA-1 | **Role map is MISSING 5 task kinds** that exist in `Task-before-save-policy.py`: `"Return to warehouse"`, `"Return Call"`, `"Distribute Payment"`, `"Payment Received"`, `"Account Details: Entry/Processing"`, `"Other"`. Users CANNOT accept these task kinds via the API — the Accept button will fail with "You are not allowed to accept this task kind." | **Confirmed Production Bug** | 0.95 |
| DA-2 | **Explicit `frappe.db.commit()`** on line 63. This is unusual and potentially dangerous — it commits the `_assign` change before the `task.save()` on line 73. If the save fails (e.g., validation error from another Before Save script), the `_assign` is already committed but the acceptance fields are not. This creates an inconsistent state. | **Likely Bug** | 0.85 |
| DA-3 | **Clears `custom_team_queue_role`** (line 71). Once a user accepts, the task is no longer a team queue task. But the team queue status fields (`custom_is_team_queue_task`, `custom_team_queue_status`) are NOT updated by this script. The disabled `Task-dispatch-queue-integration.py` would have handled this. | Partial Implementation | 0.90 |
| DA-4 | **Re-acceptance is explicitly allowed** (comment on line 53: "Re-acceptance allowed — no blocking here"). This means a different user can accept an already-accepted task, overwriting the previous acceptor. Doc 16 says "Accept button disappears for user who accepted it" but doesn't explicitly forbid re-acceptance by others. | Undocumented Production Decision | 0.85 |

### 5.10 dispatch_task_queue_backfill.py

**File**: `server/dispatch_task_queue_backfill.py` | **Lines**: 53 | **Enabled**: Yes | **Type**: API

**Purpose**: One-time/maintenance API to backfill team queue fields on existing dispatch-linked tasks.

**What it does**:
1. Fetches tasks linked to a Dispatch Case that are not Completed/Cancelled/Template, up to a limit (default 200).
2. Maps task_kind to team role using `TASK_KIND_TEAM_ROLE` (12 entries).
3. Sets `custom_is_team_queue_task = 1`, `custom_team_queue_role`, `custom_team_queue_status` based on whether real (non-placeholder) users are assigned.
4. Uses `frappe.db.set_value` for direct writes.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| QB-1 | **Maps `"Delivery"` to `"Delivery Driver"` role** but the policy script maps it to `["Delivery Driver", "Ops - Delivery"]`. This means backfill only considers the Delivery Driver role, not Ops - Delivery coordinators. | Minor Inconsistency | 0.85 |
| QB-2 | **Team placeholder list includes `"directors.team@example.com"`** which is not in the dispatch_task_accept placeholder list. Inconsistent placeholder lists across scripts. | Minor Inconsistency | 0.90 |
| QB-3 | **Not documented.** This utility API has no documentation. | Documentation Gap | 0.95 |

### 5.11 doc15_task_auto_escalation.py

**File**: `server/doc15_task_auto_escalation.py` | **Lines**: 68 | **Enabled**: Yes | **Type**: Scheduler Event

**Purpose**: Automatically escalates overdue tasks to directors by creating ToDo notifications.

**What it does**:
1. **Lines 10-13**: Defines cutoffs: 3 days for normal priority, 1 day for High/Urgent.
2. **Lines 15-20**: Gets all enabled users with `Ops - Directors` role.
3. **Lines 23-27**: Fetches all tasks in open statuses with `exp_end_date` set.
4. **Lines 29-46**: For each overdue task, checks if directors already have open ToDos. If not, creates ToDos for ALL directors AND the task owner.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| AE-1 | **Not documented.** Doc 10.1 mentions "Overdue Tasks" as a filter for the dashboard but does NOT describe automatic escalation with ToDo creation. This is an entirely undocumented feature. | Documentation Gap | 0.95 |
| AE-2 | **Escalates to ALL directors.** Every director gets a ToDo for every overdue task. This could lead to notification fatigue if many tasks are overdue. | Correct but Risky | 0.80 |
| AE-3 | **No de-escalation.** Once a task is escalated, the director ToDos persist even if the task is later completed or the due date is extended. Old ToDos are not cleaned up. | Likely Bug | 0.80 |
| AE-4 | **Only checks tasks with `exp_end_date` set.** Tasks without due dates are never escalated, even if they are long-overdue by modification date. | Intentional Limitation | 0.85 |
| AE-5 | **Open statuses include `"Pending Review"` and `"Overdue"`.** The property setter for Task `status` field shows options: `Open\nWorking\nOverdue\nCompleted\nCancelled`. The script checks for `"Pending Review"` which is NOT in the property setter's options list, meaning tasks in "Pending Review" status should not exist in production. | Stale Code | 0.85 |

### 5.12–5.15 Disabled Scripts

#### Task-after-insert-assign.py (DISABLED)

**Purpose**: Auto-assigns task from `custom_assign_to` field using `frappe.desk.form.assign_to.add`.

**Why disabled**: Uses `from frappe.desk.form.assign_to import add` which is not available in RestrictedPython (ERPNext's server script sandbox). This was replaced by direct `_assign` DB writes and manual ToDo creation throughout the codebase.

**Confidence**: 0.95 — confirmed by the comment "FIXED: Update _assign via db (assign_to module not available in RestrictedPython)" appearing in multiple active scripts.

#### Task-dispatch-queue-integration.py (DISABLED)

**Purpose**: After-save script that maps task kinds to team roles and updates team queue fields on dispatch-linked tasks.

**Why disabled**: Replaced by: (1) `dispatch_task_queue_backfill.py` for bulk backfill, (2) manual team queue field setting in `Task-after-save-dispatch-flow.py`'s `make_task()` function. However, the active `make_task()` function does NOT set team queue fields — it only sets `custom_assigned_to`. This means **team queue fields are not automatically maintained for new tasks created by the dispatch flow**.

**Confidence**: 0.90

#### Task-team-queue-notify.py (DISABLED)

**Purpose**: After-save script that creates ToDo notifications for all team members when a new team queue task is created.

**Why disabled**: Likely disabled during the same period as the queue integration script. Without this, team members do not receive notifications when new tasks enter their queue — they must check the queue manually or rely on the list view.

**Impact**: Team notification for new tasks is broken. Users must actively check their queue.

**Confidence**: 0.90

#### Task-before-save-return-dropoff-photo.py (DISABLED)

**Purpose**: Requires `warehouse_dropoff_photo` before completing "Return drop-off at warehouse" tasks.

**Why disabled**: This enforcement is now handled within `Task-before-save-dispatch-gates.py` (Group 1, lines 93-97) for Dispatch Case-linked tasks. The old-flow version in `Task-before-save-policy.py` (lines 66-69) handles non-Dispatch-Case tasks. So this standalone script is redundant.

**Confidence**: 0.95 — the same check exists in two active scripts.

---

## 6. Script-by-Script Analysis: Client Scripts

### 6.1 Task-Accept Start.js

**File**: `client/Task-Accept Start.js` | **Lines**: 509 | **Enabled**: Yes

**Purpose**: The largest and most complex client script. Handles: (1) Accept/Start button rendering and calling `dispatch_task_accept` API, (2) Mobile UI — back button, menu cleanup, compact action buttons, header overflow, (3) Unified assignment UI — hides team queue fields, shows "Assign To" and "Next Task: Assign To", (4) Sidebar cleanup, (5) Save and Complete buttons near status field, (6) Order entry photo upload, (7) Account Details entry-specific UI.

**Key behaviors**:
- Lines 61-69: Mutual exclusion of `custom_assigned_to` and `custom_team_queue_role` (if one is set, clear the other).
- Lines 71-75: Auto-sets `completed_on` when status changes to Completed.
- Lines 84-89: Calls multiple `task_mobile_*` functions on refresh.
- Lines 177-188: Hides `custom_team_queue_role`, shows `custom_next_task_assign_to` for dispatch workflow task kinds.
- Lines 192-198: Hides sidebar: Assign, Tags, Share, Like sections.
- Lines 236-365: Large block for Save/Complete buttons with error recovery, disabled state management.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| AS-1 | **Accept button calls `dispatch_task_accept` API** (line ~300-310 area). This API is missing role maps for several task kinds (see DA-1). The Accept button will fail for Return Call, Distribute Payment, Payment Received, Account Details, and Other tasks. | Confirmed Bug (flows from DA-1) | 0.95 |
| AS-2 | **Mobile back button creates a `setInterval` at 1000ms** (line 110) that runs forever on every page. This polls the DOM every second. Not a bug but a performance concern on mobile devices. | Code Quality | 0.85 |
| AS-3 | **`completed_on` vs `completed_at` discrepancy.** The client sets `frm.set_value("completed_on", frappe.datetime.get_today())` (line 73) while the server script sets `doc.completed_at = frappe.utils.now_datetime()` (policy.py line 85). These are TWO DIFFERENT FIELDS — `completed_on` is the standard ERPNext Task field (date only), `completed_at` is a custom field (datetime). Both get set on completion, which is correct but redundant. | Correct but Redundant | 0.90 |
| AS-4 | **Hardcoded "Order entry" override** (lines 233-235): If `task_kind` is "Order accepting", it auto-changes to "Order entry". This suggests "Order accepting" was an old task kind name that was renamed. | Intentional Migration Aid | 0.85 |

### 6.2 Task-Lock Completed.js

**File**: `client/Task-Lock Completed.js` | **Lines**: 6 | **Enabled**: Yes

**Purpose**: Client-side mirror of `Task-before-save-lock-completed.py`. Disables save and sets form to read-only for Completed tasks.

**Finding**: Correct implementation. Mirrors server-side. No issues. **Confidence: 0.95**

### 6.3 Task-Lock Unaccepted.js

**File**: `client/Task-Lock Unaccepted.js` | **Lines**: 69 | **Enabled**: Yes

**Purpose**: Client-side mirror of `Task-before-save-lock-unaccepted.py`. Locks form unless user is the acceptor or admin. Re-enables specific operational fields for the accepted user.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| LUC-1 | **700ms delay** (line 24). The lock/unlock is applied with a 700ms setTimeout, meaning the form is briefly editable on load before the lock kicks in. A fast user could start editing before the lock applies. Server-side enforcement prevents actual saves, so this is cosmetic. | UX Issue (not a bug) | 0.85 |
| LUC-2 | **Hides team queue fields** (lines 65-67): `custom_is_team_queue_task`, `custom_team_notified`, `custom_team_queue_status`. These fields are hidden in multiple scripts, creating redundant DOM manipulation. | Code Duplication | 0.90 |

### 6.4 Task-Team Queue.js

**File**: `client/Task-Team Queue.js` | **Lines**: 65 | **Enabled**: Yes

**Purpose**: Overrides the Quick Entry form for Tasks. Instead of the standard form, shows a simplified form with Subject, Products, Customer, Date, and Notes fields. Creates the task with `task_kind = "Order entry"` and `custom_team_queue_role = "Ops - Order Creating"`.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| TQ-1 | **Hardcodes `task_kind = "Order entry"` for all Quick Entry tasks.** Any task created via the "+" button in the list view becomes an Order entry task. This is an intentional design — the Quick Entry is designed for phone/WhatsApp order capture. Not documented. | Undocumented Production Decision | 0.90 |
| TQ-2 | **Uses `frappe.client.save` with JSON doc string.** Bypasses form validation. Subject is optional (auto-generated by `Task-before-save-auto-subject.py`). | Correct | 0.90 |

### 6.5 Task-Dispatch Packing Usability.js

**File**: `client/Task-Dispatch Packing Usability.js` | **Lines**: 34 | **Enabled**: Yes

**Purpose**: (1) Shows a dashboard comment about Dispatch Case item rows. (2) Shows Accept/Start button for unaccepted tasks. (3) Adds "My Team Queue" filter to list view.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| DPU-1 | **Duplicate Accept button.** This script adds an Accept button (lines 18-22) but `Task-Accept Start.js` also adds one, and `Task-Other UI Cleanup.js` adds another for Other tasks. Multiple Accept buttons may appear simultaneously. The first one to render is visible; later duplicates may be hidden by DOM ordering. | **Duplicate Implementation** | 0.90 |
| DPU-2 | **`frappe.listview_settings['Task'].onload` override.** This script sets `.onload` with "My Team Queue" button, but `Task-List Toggle Filters.js` and `Global-Mobile Back Button List.js` also override `.onload`. Only the last-loaded script's onload works (unless they chain via the `_origOnload` pattern). This script does NOT chain. | **Likely Bug — onload clobbering** | 0.85 |

### 6.6 Task-List Toggle Filters.js

**File**: `client/Task-List Toggle Filters.js` | **Lines**: 84 | **Enabled**: Yes

**Purpose**: Adds toggle checkboxes (My Tasks / Open Tasks / Completed) to the Task list view using client-side filters.

**Implementation**: Uses Frappe's `filter_area.add` with standard filters like `_assign LIKE` and `status != 'Completed'`.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| TLF-1 | **Competes with `Global-Mobile Back Button List.js`** which implements the SAME toggle bar but uses the `task_list_filtered` server API instead of client-side filters. Both scripts chain via `_origOnload` / `_taskToggleOrigOnload`, so both execute. But they create TWO toggle bars with different behavior. | **Duplicate Implementation** | 0.95 |
| TLF-2 | **Client-side `_assign LIKE` filter** (line 53) can return incorrect results because `_assign` is a JSON string field. The LIKE pattern `%user@email%` could match partial email addresses. | Minor Risk | 0.75 |

### 6.7 Global-Mobile Back Button List.js

**File**: `client/Global-Mobile Back Button List.js` | **Lines**: 141 | **Enabled**: Yes

**Purpose**: (1) Global mobile CSS and tooltip cleanup. (2) Persistent mobile back button. (3) Mobile list refresh button. (4) Task list toggle filters using `task_list_filtered` API.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| GMB-1 | **Calls `task_list_filtered` API** (line 103) which returns task names, then sets `name IN [...]` filter. For large result sets (up to 500 names), this creates a very large URL query that may exceed browser/server limits. | **Likely Bug** for scale | 0.80 |
| GMB-2 | **Duplicate toggle bar** with `Task-List Toggle Filters.js` (see TLF-1). The API-based approach is more comprehensive (role-based filtering server-side) but conflicts with the client-side approach. | Duplicate Implementation | 0.95 |
| GMB-3 | **`console.log` statements** (lines 102, 113) left in production code. Minor but indicates this was not production-hardened. | Code Quality | 0.95 |
| GMB-4 | **Back button `setInterval` at 300ms** (line 46) — even more aggressive polling than the one in Task-Accept Start.js (1000ms). Both create the same back button; the one with shorter interval will typically win. | Code Duplication / Performance | 0.90 |

### 6.8 Task-Account Details UI Cleanup.js

**File**: `client/Task-Account Details UI Cleanup.js` | **Lines**: 284 | **Enabled**: Yes

**Purpose**: Extensive UI customization for "Account details" task kind — hides product/barcode/photo fields, reorganizes layout, renders photo gallery, adds Accept button for new tasks.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| ADUC-1 | **Checks for `task_kind == "account details"` (lowercase)** (line 28). However, the actual task_kind values in the Select field are "Account Details: Entry" and "Account Details: Processing". This means `is_account_details` on line 28 is always false, and the cleanup code below never executes for actual Account Details tasks. | **Confirmed Production Bug** | 0.95 |
| ADUC-2 | **Runs `setTimeout` at 200ms, 800ms, 1600ms, 3000ms** (lines 15-18) to re-apply cleanup. This is a common pattern across task client scripts to handle late-rendering Frappe form elements. Not a bug but fragile. | Code Quality | 0.85 |

### 6.9 Task-Other UI Cleanup.js

**File**: `client/Task-Other UI Cleanup.js` | **Lines**: 176 | **Enabled**: Yes

**Purpose**: UI customization for "Other: Entry" and "Other: Processing" tasks. Hides product/barcode fields, shows status/priority, renders photo gallery, provides Accept and Complete buttons.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| OUC-1 | **`task_restore_status_priority_complete_all` function** creates a Complete Task button with error recovery (save first, then set Completed, then reload). This duplicates the Complete button logic in `Task-Accept Start.js`. Both may render simultaneously. | Duplicate Implementation | 0.85 |
| OUC-2 | **Photo rendering functions** (`task_other_render_photos`, `task_photo_fullscreen_preview`) are defined in this script but used by other task-kind-specific code too. These should arguably be in a shared utility. | Code Quality | 0.80 |

### 6.10 Task-Hide Sidebar Assignment.js (DISABLED)

**File**: `client/Task-Hide Sidebar Assignment.js` | **Lines**: 52 | **Enabled**: No

**Purpose**: Hides ALL assignment UI (sidebar and form fields). Auto-assigns to current user on new task.

**Why disabled**: The functionality was split across multiple active scripts: `Task-Accept Start.js` hides sidebar assignment sections (lines 192-198), and `Task-Lock Unaccepted.js` hides team queue fields. This script was too aggressive — it hid ALL fields with "assign" in the name, which would hide `custom_assigned_to` and `custom_next_task_assign_to`.

**Confidence**: 0.90

### 6.11 Task - Load Surgical Kit Template.js

**File**: `client/Task - Load Surgical Kit Template.js` | **Lines**: 39 | **Enabled**: Yes

**Purpose**: Loads Collection Set template items into Dispatch Case `case_items` when `surgery_set_type` is selected.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| SKT-1 | **Registered as DocType=Task but operates on Dispatch Case.** This script binds to `frappe.ui.form.on('Dispatch Case', ...)` despite being registered as a Task client script. It will execute when the Dispatch Case form loads (because client scripts are loaded by their registered DocType, but the event bindings are what matter). This is a **misregistration** — it should be registered as a Dispatch Case client script. | **Configuration Bug** | 0.90 |
| SKT-2 | **Audit plan flags this as a potential duplicate** of `Dispatch Case-Template Auto Fill.js` (Group 1). Need to verify if both exist and do the same thing. | Requires Cross-Group Verification | 0.75 |

### 6.12 Order entry - barcode scanning section - hide.js

**File**: `client/Order entry - barcode scanning section - hide.js` | **Lines**: 340 | **Enabled**: Yes

**Purpose**: The most comprehensive layout management script. Controls visibility of barcode/photo/product/team-queue fields for EVERY task kind. Also handles section header renaming (e.g., "Barcode Scanning (Optional)" → "Task Status & Priority" for most kinds) and fetches pack/prepare photo for Delivery tasks.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| BSH-1 | **Covers a "Debt Closure Approval" task kind** (lines 33, 111-112, 138-152) that is NOT in the task_kind Select field options per the schema. This suggests "Debt Closure Approval" was added as a task_kind in production after the schema was extracted, or it's defined differently. The server script `Task-after-save-debt-closure.py` creates tasks with `task_kind = "Debt Closure Approval"`. | Requires Schema Verification | 0.80 |
| BSH-2 | **Extensive DOM manipulation** with label-based matching (lines 35-38 use label strings like "Scan Product Barcode", "Choose Product"). If labels change via property setters, matching breaks silently. | Fragile Implementation | 0.80 |

### 6.13 Task-Inspect Returns Next Assign Visible.js

**File**: `client/Task-Inspect Returns Next Assign Visible.js` | **Lines**: 26 | **Enabled**: Yes

**Purpose**: For "Returns processing / verification" tasks, ensures `custom_next_task_assign_to` field is visible with label "Next Task: Assign To".

**Finding**: Correct but redundant — `Task-Accept Start.js` (line 183) already shows this field for all dispatch workflow task kinds including Returns processing. This script exists as belt-and-suspenders. **Confidence: 0.90**

### 6.14 Task-Auto Reload.js

**File**: `client/Task-Auto Reload.js` | **Lines**: 32 | **Enabled**: Yes

**Purpose**: Auto-reloads the Task form if the server's `modified` timestamp differs from the client's, with a 5-second cooldown.

**Findings**:

| # | Finding | Category | Confidence |
|---|---|---|---|
| AR-1 | **Fires on every `refresh` event**, making an async API call to check `modified`. If the user has unsaved changes, the reload will discard them. The script does not check `frm.is_dirty()` before reloading. | **Likely Bug** — data loss risk | 0.85 |
| AR-2 | **Not documented.** No documentation mentions auto-reload behavior. | Documentation Gap | 0.95 |

---

## 7. Cross-Script Interaction Analysis

### 7.1 Before Save Script Interactions

**Scenario**: User completes a Delivery task on a Dispatch Case.

All 11 enabled Before Save scripts fire. Critical interaction chain:

1. `lock-completed` — checks if PREVIOUSLY completed. Not triggered on first completion.
2. `lock-unaccepted` — checks acceptance. User must be accepted.
3. `policy` — checks role for "Delivery" kind. User must have `Delivery Driver` or `Ops - Delivery`.
4. `dispatch-gates` — checks `delivery_status == "Delivered"`, requires it was "Picked Up" first. Auto-sets `status = "Completed"` if delivery_status changes to "Delivered".
5. `pack-complete-creates-delivery-task` — only fires for Pack completion, skips.
6. `discount-approval-writeback` — only fires for Discount Approval, skips.
7. `purchase-approval-writeback` — only fires for Purchase Approval, skips.
8. `payment-recording` — only fires for Debt Collection, skips.
9. `auto-subject` — subject already set, skips.
10. `Account Details Default Assignment` — wrong task_kind string, skips.
11. `Other Entry Default Subject` — not an Other task, skips.

**Risk**: If `dispatch-gates` fires BEFORE `policy`, the delivery_status validation runs before the role check. If it fires AFTER, the role check runs first. Either order produces correct outcomes in this case because both will block invalid users — but the error message differs. Not a bug, but user experience is unpredictable.

**Confidence**: 0.85

### 7.2 After Save Script Interactions

**Scenario**: User completes a Debt Collection task.

After Save scripts that fire:

1. `dispatch-flow` — only fires if `doc.dispatch_case` is set. Debt Collection tasks MAY have a dispatch_case. If so, no completion handler in dispatch-flow matches "Debt Collection" task_kind, so nothing happens.
2. `debt-closure` — checks for `task_kind == "Debt Collection"` and `is_completing`. Creates a "Debt Closure Approval" task.
3. `account-details-processing` — checks for "Account Details: Entry", skips.
4. `other-processing` — checks for "Other: Entry", skips.
5. `advance-payment` — checks for "Payment Received", skips.

**Risk**: None identified. Only `debt-closure` fires meaningfully. But if future scripts are added, the growing number of After Save scripts all checking `is_completing` creates a maintenance burden.

### 7.3 Client Script Event Conflicts

**Problem: Multiple `frappe.listview_settings['Task'].onload` handlers**

Three scripts set this:
1. `Task-Team Queue.js` — sets `.refresh` handler (not `.onload`), safe.
2. `Task-Dispatch Packing Usability.js` (line 27) — sets `.onload` WITHOUT chaining. This **overwrites** any previously set `.onload`.
3. `Task-List Toggle Filters.js` (line 8) — sets `.onload` WITH chaining via `_taskToggleOrigOnload`.
4. `Global-Mobile Back Button List.js` (line 52) — sets `.onload` WITH chaining via `_origOnload`.

**Result depends on load order**:
- If `Dispatch Packing Usability` loads LAST, it overwrites everything — no toggle bar, no mobile refresh button. Only "My Team Queue" button appears.
- If it loads FIRST, the other two chain after it, and all three onload handlers execute.

ERPNext loads client scripts in database insertion order. Without checking the DB, the exact production behavior is **uncertain**.

**Confidence**: 0.90 that a conflict exists; 0.60 on which scripts actually win.

### 7.4 Duplicate Accept Button Rendering

Four scripts render Accept/Start buttons:
1. `Task-Accept Start.js` — renders in mobile compact actions section
2. `Task-Dispatch Packing Usability.js` — adds via `frm.add_custom_button`
3. `Task-Other UI Cleanup.js` — adds via `frm.add_custom_button` for Other tasks
4. `Task-Account Details UI Cleanup.js` — adds for new Account Details tasks

All four check `frm.doc.custom_accepted_by !== frappe.session.user` before rendering, so they should not appear once accepted. But when NOT accepted, up to 3 Accept buttons may appear simultaneously (Accept Start, Dispatch Packing, and either Other or Account Details depending on task_kind).

**Confidence**: 0.85

---

## 8. Documentation Comparison Matrix

| Feature | Documentation Says | Production Does | Match? | Confidence |
|---|---|---|---|---|
| **Assignment: exactly 1 user** | Doc 10 §6: "Each operational task must have one primary assignee" | Validation is COMMENTED OUT in policy.py lines 72-83 | **MISMATCH** — documented rule not enforced | 0.98 |
| **Acceptance before editing** | Doc 16 §2.2: users must Accept before working | Enforced by `lock-unaccepted.py` and `dispatch-gates.py` | **MATCH** | 0.95 |
| **Completed tasks immutable** | Doc 10 §5: "Auditability over convenience" | Enforced by `lock-completed.py` (no admin override) | **STRICTER** than documented | 0.95 |
| **Role-based completion** | Doc 10A §6.1: specific roles per task kind | Enforced by `policy.py` with modified role map | **PARTIAL MATCH** — role map differs from docs | 0.90 |
| **Photo gate: Delivery** | Doc 10 §7: Warehouse Pickup Photo required for Delivery completion | Split: Dispatch Case tasks checked in `dispatch-gates.py`; old-flow in `policy.py` | **MATCH** (different path than documented but same outcome) | 0.90 |
| **Photo gate: Return drop-off** | Doc 10 §7: Drop-off Photo required for Return drop-off at warehouse | Standalone script DISABLED; enforcement moved to `dispatch-gates.py` for Pickup Returns → Returned to Warehouse | **PARTIAL MATCH** — task kind changed from "Return drop-off" to "Pickup Returns" | 0.85 |
| **Debt Collection: Finance owns** | Doc 03/16: Finance Team owns Debt Collection | Policy.py allows `["Ops - Finance", "Ops - Directors"]` | **MATCH** | 0.90 |
| **Debt Collection: one per customer** | Doc 16 §6.10: one active task per customer | `dispatch-flow.py` `create_or_update_debt_task` checks for existing task | **MATCH** | 0.95 |
| **Auto-escalation** | Not documented | `doc15_task_auto_escalation.py` runs on scheduler, creates director ToDos | **UNDOCUMENTED FEATURE** | 0.95 |
| **Account Details task flow** | Not documented | Full Entry→Processing chain with file copy, next-assignee | **UNDOCUMENTED FEATURE** | 0.95 |
| **Other task flow** | Not documented | Full Entry→Processing chain with team queue, file copy | **UNDOCUMENTED FEATURE** | 0.95 |
| **Task auto-subject** | Not documented | 5-digit numeric auto-generation | **UNDOCUMENTED FEATURE** | 0.95 |
| **Team queue pattern** | Doc 16 §2.2: Team User Pattern with placeholder emails | Implemented via `custom_assigned_to` + `custom_team_queue_role` fields | **MATCH** (implementation details differ from doc description) | 0.85 |
| **Team queue notification** | Not explicitly documented | DISABLED (`Task-team-queue-notify.py`) — no notification sent | **BROKEN** — feature exists but is off | 0.90 |
| **Quick Entry = Order entry** | Not documented | `Task-Team Queue.js` hardcodes Order entry for quick-add | **UNDOCUMENTED FEATURE** | 0.90 |
| **Dispatch picking / hand-off task** | Doc 10 §4.3: defined as a task kind | Not created by any dispatch flow script | **MISMATCH** — documented but never used | 0.90 |

---

## 9. Bugs and Risks

### Confirmed Production Bugs

| ID | Bug | Script | Lines | Impact | Confidence |
|---|---|---|---|---|---|
| BUG-1 | Assignment validation disabled — tasks can have 0 or N assignees | `Task-before-save-policy.py` | 72-83 | Tasks may exist with no owner or multiple owners, breaking accountability | 0.98 |
| BUG-2 | `Task-Account Details Default Assignment.py` uses wrong task_kind string (`"Account details"` vs `"Account Details: Entry"`) — never fires | `Task-Account Details Default Assignment.py` | 8 | Account Details tasks don't get default assignment from this script | 0.95 |
| BUG-3 | `dispatch_task_accept.py` missing 5+ task kinds — Accept button fails for Return Call, Distribute Payment, Payment Received, Account Details, Other | `dispatch_task_accept.py` | 16-30 | Users cannot accept these task kinds via the standard UI flow | 0.95 |
| BUG-4 | Payment recording: allocates to `row.allocated_now`, zeros it out (line 33), then tries to use `row.allocated_now > 0` for PE references (line 55) — always false | `Task-before-save-payment-recording.py` | 28-60 | Payment Entries created without invoice references (unallocated) | 0.95 |

### Likely Bugs Requiring Validation

| ID | Bug | Script | Impact | Confidence |
|---|---|---|---|---|
| LBUG-1 | `dispatch_task_accept.py` does `frappe.db.commit()` before `task.save()` — inconsistent state if save fails | `dispatch_task_accept.py` | _assign updated but acceptance fields not set | 0.85 |
| LBUG-2 | `Task-Auto Reload.js` reloads without checking `frm.is_dirty()` — can discard unsaved user edits | `Task-Auto Reload.js` | User data loss | 0.85 |
| LBUG-3 | Auto-escalation creates ToDos that are never cleaned up when tasks are completed | `doc15_task_auto_escalation.py` | Stale director ToDos accumulate | 0.80 |
| LBUG-4 | Two duplicate toggle-filter implementations compete on the Task list view | `Task-List Toggle Filters.js` + `Global-Mobile Back Button List.js` | Unpredictable list behavior depending on load order | 0.90 |
| LBUG-5 | `Task-Account Details UI Cleanup.js` checks `"account details"` (lowercase) — cleanup never fires | `Task-Account Details UI Cleanup.js` | Account Details UI not cleaned up as intended | 0.95 |

### Risks

| ID | Risk | Description | Confidence |
|---|---|---|---|
| RISK-1 | Before Save script execution order is undefined | 11 Before Save scripts on Task; ERPNext doesn't guarantee order | 0.85 |
| RISK-2 | `_assign` direct DB writes bypass ERPNext assignment framework | Multiple scripts write `_assign` JSON directly, potentially causing `_assign` vs ToDo desync | 0.90 |
| RISK-3 | Hardcoded user emails in `task_list_filtered.py` | 5 Gmail addresses hardcoded as `ACCOUNT_DETAILS_MY_TASK_USERS` (line 41-47) | 1.00 |
| RISK-4 | Team queue notification is disabled | `Task-team-queue-notify.py` is disabled, so new team queue tasks get no notification | 0.90 |
| RISK-5 | `task_list_filtered.py` SQL injection surface | Raw string interpolation for task kinds in SQL (line 68), mitigated by source being hardcoded dict keys | 0.70 |

---

## 10. Disabled/Legacy Code Assessment

| Script | Status | Assessment | Safe to Remove? | Confidence |
|---|---|---|---|---|
| `Task-after-insert-assign.py` | Disabled | Uses `frappe.desk.form.assign_to.add` which doesn't work in RestrictedPython. Replaced by direct `_assign` writes everywhere. | Yes — fully superseded | 0.95 |
| `Task-dispatch-queue-integration.py` | Disabled | Team queue field maintenance on save. Replaced by `dispatch_task_queue_backfill.py` (API) and manual field setting in `make_task()`. However, `make_task()` does NOT set queue fields, so this feature is partially lost. | No — functionality gap remains | 0.90 |
| `Task-team-queue-notify.py` | Disabled | Team notification for new queue tasks. No replacement exists. Disabling it means team members must manually check their queue. | No — should consider re-enabling or replacing | 0.90 |
| `Task-before-save-return-dropoff-photo.py` | Disabled | Photo enforcement for return drop-off. Now handled by `dispatch-gates.py` for Dispatch Case tasks and `policy.py` for old-flow tasks. | Yes — fully superseded | 0.95 |
| `Task-Hide Sidebar Assignment.js` | Disabled | Too aggressive — hid ALL assignment fields. Replaced by surgical hiding in `Task-Accept Start.js` and `Task-Lock Unaccepted.js`. | Yes — fully superseded | 0.90 |

---

## 11. Undocumented Production Decisions

| # | Decision | Evidence | Category | Confidence |
|---|---|---|---|---|
| UD-1 | "Account Details: Entry" → "Account Details: Processing" task chain | `Task-after-save-account-details-processing.py` (80 lines of implemented chain logic) | Post-documentation feature | 0.95 |
| UD-2 | "Other: Entry" → "Other: Processing" task chain | `Task-after-save-other-processing.py` (45 lines) | Post-documentation feature | 0.95 |
| UD-3 | Auto-escalation of overdue tasks to directors | `doc15_task_auto_escalation.py` (68 lines, scheduler) | Post-documentation feature | 0.95 |
| UD-4 | Quick Entry form creates Order entry tasks by default | `Task-Team Queue.js` (65 lines) | UX decision | 0.90 |
| UD-5 | Assignment validation intentionally disabled for launch | Comment in `Task-before-save-policy.py` lines 72-73 | Temporary bypass (still active) | 0.98 |
| UD-6 | Re-acceptance of already-accepted tasks is allowed | Comment in `dispatch_task_accept.py` line 53 | Operational decision | 0.85 |
| UD-7 | Acceptance reset on reassignment | `Task-before-save-lock-unaccepted.py` lines 17-20 | Safety feature | 0.92 |
| UD-8 | "Debt Closure Approval" task kind with hardcoded approver list | `Task-after-save-debt-closure.py` lines 14-19, `Task-before-save-dispatch-gates.py` lines 131-134 | Post-documentation feature | 0.90 |

---

## 12. Confidence-Scored Findings Summary

### Critical (Action Required)

| ID | Finding | Confidence |
|---|---|---|
| BUG-1 | Assignment validation disabled in production | 0.98 |
| BUG-3 | Accept API missing 5+ task kinds | 0.95 |
| BUG-4 | Payment recording PE created without invoice references | 0.95 |
| BUG-2 | Account Details Default Assignment uses wrong task_kind | 0.95 |
| LBUG-5 | Account Details UI Cleanup uses wrong task_kind | 0.95 |

### High (Should Fix)

| ID | Finding | Confidence |
|---|---|---|
| LBUG-4 | Duplicate toggle-filter implementations compete | 0.90 |
| RISK-4 | Team queue notification disabled | 0.90 |
| RISK-2 | `_assign` direct writes may desync with ToDo records | 0.90 |
| DA-3 | Team queue status not updated on acceptance | 0.90 |
| RISK-3 | Hardcoded user emails in task_list_filtered | 1.00 |

### Medium (Should Plan)

| ID | Finding | Confidence |
|---|---|---|
| LBUG-1 | Premature `db.commit()` in dispatch_task_accept | 0.85 |
| LBUG-2 | Auto-reload discards unsaved changes | 0.85 |
| LBUG-3 | Auto-escalation ToDos never cleaned up | 0.80 |
| P-2/P-3 | Role mapping inconsistencies across 4 scripts | 0.95 |
| DPU-2 | List view onload clobbering | 0.85 |

### Low (Document or Monitor)

| ID | Finding | Confidence |
|---|---|---|
| AS-2 | Mobile back button 1000ms/300ms polling | 0.85 |
| ADP-4 | File copy may cause storage bloat | 0.75 |
| AS-3 | `completed_on` / `completed_at` redundancy | 0.90 |

---

## 13. Items Requiring Runtime Validation

| # | Item | What to Check | Method |
|---|---|---|---|
| RV-1 | Which toggle filter bar is actually visible in production? | Open Task list in browser, inspect DOM for toggle bars | Browser inspection |
| RV-2 | Can users actually accept Return Call / Account Details / Other tasks? | Try accepting each task kind as appropriate role | Manual test |
| RV-3 | Are Payment Entries from Debt Collection actually allocated to invoices? | Check existing PEs created by payment recording for `references` table | DB query: `SELECT * FROM tabPayment Entry Reference WHERE parent IN (SELECT name FROM tabPayment Entry WHERE creation > '2025-01-01')` |
| RV-4 | How many tasks have 0 or multiple assignees? | Count tasks with `_assign IS NULL OR _assign = '[]'` vs `_assign` containing 2+ users | DB query |
| RV-5 | Do Account Details tasks get default assignment? | Create an Account Details: Entry task and check if default assignment fires | Manual test |
| RV-6 | Is "Debt Closure Approval" in the task_kind Select options? | Check the Task doctype field options in production | `bench get-doc DocType Task` or browser DevTools |
| RV-7 | Script execution order for Before Save | Add temporary logging to each Before Save script's first line | Temporary server script edit |
| RV-8 | Auto-escalation frequency and ToDo accumulation | Count ToDo records with description LIKE "Auto-escalated%" | DB query |
| RV-9 | `task_list_filtered.py` hardcoded email addresses — are these still valid users? | Check User records for the 5 Gmail addresses | DB query |
| RV-10 | Does `Task - Load Surgical Kit Template.js` actually trigger on Dispatch Case form? | Open Dispatch Case, select surgery_set_type, check if items load | Manual test |

---

## 14. Recommended Next Steps

### Immediate (before next deployment)

1. **Fix BUG-2 and LBUG-5**: Update `Task-Account Details Default Assignment.py` line 8 and `Task-Account Details UI Cleanup.js` line 28 to use correct task_kind strings (`"Account Details: Entry"` / `"Account Details: Processing"`).

2. **Fix BUG-3**: Add missing task kinds to `dispatch_task_accept.py`'s role map: `"Return Call"`, `"Distribute Payment"`, `"Payment Received"`, `"Account Details: Entry"`, `"Account Details: Processing"`, `"Other"`, `"Debt Closure Approval"`, `"Returns restocking"`.

3. **Fix BUG-4**: In `Task-before-save-payment-recording.py`, the PE reference loop (line 54-60) should use the pre-zeroed allocation values, not `row.allocated_now` which was set to 0 on line 33. Store the allocation in a separate variable before zeroing.

4. **Fix LBUG-4**: Remove one of the two duplicate toggle-filter implementations. Recommend keeping `Global-Mobile Back Button List.js` (API-based, more comprehensive) and removing the filter logic from `Task-List Toggle Filters.js`.

### Short-term (within 2 weeks)

5. **Consolidate role maps**: Create a single source of truth for `TASK_KIND_ALLOWED_ROLES` instead of maintaining 4 copies that drift.

6. **Re-evaluate assignment validation**: Decide whether to re-enable the commented-out assignment validation in `policy.py` or formally retire it. If re-enabling, also implement it in `dispatch_task_accept.py`.

7. **Address team queue notification gap**: Either re-enable `Task-team-queue-notify.py` (after fixing for RestrictedPython compatibility) or implement an alternative notification mechanism.

8. **Remove hardcoded emails from `task_list_filtered.py`**: Replace with a role-based or configuration-based approach.

### Medium-term (within 1 month)

9. **Document undocumented features**: Add documentation for Account Details flow, Other flow, auto-escalation, Quick Entry behavior, Debt Closure Approval, and acceptance reset.

10. **Audit `_assign` consistency**: Write a one-time script to verify that `_assign` JSON matches active ToDo records for all open tasks.

11. **Review client script loading**: Verify list view `onload` handlers are not clobbering each other by checking the actual load order in production.

12. **Consider Auto-Reload safety**: Add `frm.is_dirty()` check to `Task-Auto Reload.js` to prevent discarding unsaved changes.

---

*End of Group 2 — Task System and Gates Production Audit*
