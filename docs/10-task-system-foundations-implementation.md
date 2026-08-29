# Doc 10A — Task System Foundations (Implementation / ERPNext Setup Guide)

> **Major revision (2026-08):** The task system was significantly refactored. Key changes from the original design below:
> - **Acceptance model**: Tasks must be explicitly accepted before editing/completing (section 6 rewritten).
> - **Lock model**: Only the accepted user can edit; others see read-only.
> - **Team mapping unification**: All role/team mappings are now stored in `Task Access Policy` records (not hardcoded in scripts). See section 6A.
> - **Telegram notifications**: Assignment changes trigger Telegram messages to affected users.
> - **Diagnostic logging**: All server scripts emit tagged logs (`[Policy]`, `[Accept]`, `[List]`, `[Dispatch]`, `[Lock]`, `[Gates]`, `[OtherFlow]`, `[TgAssign]`, `[TgStatus]`); client scripts emit `[TaskAccept]`, `[TaskLock]`, `[TaskAuto]`, `[TaskPack]`, `[TaskToggle]`.
> - **Photo requirements**: See **Doc 18 — Photo System** for current authoritative rules.
> - **Other: Entry / Other: Processing**: New task kinds for ad-hoc workflows.
> - The script code in section 6.1 is **obsolete** — see section 6A for the current architecture.

## 1) Purpose
This is a **step-by-step setup guide** to implement the operational rules defined in:
- **Doc 10 — Task System Foundations (Operational)**

This guide covers:
- Standardizing Task fields (Task Kind + reference links)
- Driver-friendly permissions
- Mandatory attachment enforcement for:
  - `Delivery` (Warehouse Pickup Photo)
  - `Return drop-off at warehouse` (Warehouse Drop-off Photo)
- Capturing `completed_at` timestamps
- Basic patterns for “stage gates” (blocking a workflow step until required tasks are completed)

Non-goals:
- This guide does not implement every business workflow (selling, surgery sets, procurement). It only provides reusable Task-system building blocks.

---

## 2) Prerequisites / access
You should do this as a user with:
- `System Manager`
- `Stock Manager` (optional; only needed if you will also touch stock permissions)

You will need access to:
- `Customize Form`
- `Role` + `Role Permission Manager`
- `Server Script`

---

## 3) Add standard fields on `Task`
Doc 10 requires the same Task system to support multiple operational processes.

### 3.1 Add `task_kind` (required)
1) Open `Customize Form`.
2) Select DocType: `Task`.
3) Add a custom field:
   - Label: `Task Kind`
   - Fieldname: `task_kind`
   - Fieldtype: `Select`
   - Options (one per line, exactly):
     - Order accepting *(legacy, do not use for new tasks)*
     - Order entry
     - Pack / prepare items
     - Dispatch picking / hand-off
     - Delivery
     - Return Call
     - Return to warehouse (aborted delivery / cancelled order)
     - Pickup Returns
     - Return drop-off at warehouse
     - Returns processing / verification
     - Returns restocking
     - Invoice preparation / create invoice
     - Debt Collection
     - Distribute Payment
     - Payment Received
     - Discount Approval
     - Purchase Approval
     - Write-off Approval
     - Account Details: Entry
     - Account Details: Processing
     - Other
     - Other: Entry
     - Other: Processing
     - Debt Closure Approval
4) Save.

### 3.2 Add standard “link back” fields (recommended)
These fields let one task represent a real operational unit of work and support reporting.

In `Customize Form` → `Task`, add custom fields (if missing):
- `dispatch_group_id` (Data) — Label: `Dispatch Group ID`
- `customer` (Link → `Customer`) — Label: `Customer / Hospital`
- `surgery_case` (Link → `Surgery Case`) — Label: `Surgery Case`
- `sales_order` (Link → `Sales Order`) — Label: `Sales Order`
- `sales_invoice` (Link → `Sales Invoice`) — Label: `Sales Invoice`
- `driver_handover_note` (Small Text) — Label: `Driver Handover Note`

Notes:
- Keep fields optional. Different task kinds will use different links.
- For “always tasks”, your operational automation should populate the relevant link fields.

---

## 4) Add mandatory photo fields + completion timestamp
Doc 10 requires mandatory photo evidence for:
- outgoing warehouse pickup (`Delivery`)
- incoming warehouse drop-off (`Return drop-off at warehouse`)

Doc 10 also requires that Task completion time is captured.

### 4.1 Add fields
In `Customize Form` → `Task`, add:
- ~~`warehouse_pickup_photo`~~ — REMOVED (see Doc 18: photos use File records now)
- ~~`warehouse_dropoff_photo`~~ — REMOVED (see Doc 18: photos use File records now)
- `completed_at` (Datetime) — Label: `Completed At` — Read Only

Save.

---

## 5) Permissions (Role Permission Manager)
The goal is that drivers only work with Tasks and attachments.

### 5.1 Drivers (minimum)
In `Role Permission Manager`:

For DocType: `Task`
- Ensure the driver role (example: `Delivery Driver`) has:
  - Read
  - Write

For DocTypes drivers must NOT touch:
- `Stock Entry`
- `Sales Invoice`
- `Surgery Case` (optional: you can allow read-only later)

Attachment permissions:
- Confirm drivers can add attachments to Tasks (ERPNext typically allows this via File permissions + role settings).

### 5.1A How to assign exactly one Task owner (required operational rule)
Doc 10 requires “one task = one accountable owner”.

Important ERPNext behavior:
- You must `Save` a new Task once before you can assign it.
- The governance script in section 6 enforces that a Task cannot be moved to `Working` or `Completed` unless it has exactly one assignee.

When creating or reviewing any operational Task:
1) Open the Task.
2) In the top-right menu, click `Assign`.
3) In the Assign dialog:
   - Select exactly one user.
   - Click `Add`.
4) If there is already more than one assignee:
   - Remove extra assignees so only one remains.

Expected result:
- In the Task, the `Assigned To` indicator shows exactly one person.

### 5.2 Team-based access control (who can see/complete which tasks)
Doc 10 defines the operational policy for:
- which users can **see** which Task Kinds (via Task Access Policies)
- which users can **complete** which Task Kinds (owning team enforcement)

This section implements those decisions in ERPNext.

### 5.3 Create standard roles for task ownership (recommended)
Create roles that represent your teams:
- `Ops - Order Accepting`
- `Ops - Order Creating`
- `Ops - Inventory`
- `Ops - Returns`
- `Ops - Delivery`
- `Ops - Accounting`
- `Ops - Finance`
- `Ops - Directors`
- `Delivery Driver`

Then ensure each user has exactly the role(s) for their team.

Note:
- Drivers should have `Delivery Driver`.
- Dispatch coordinators should have `Ops - Delivery`.
- Finance team handles debt collection, payments.
- Directors/coordinators typically need `Ops - Directors` for override access.

### 5.4 Implement Task Access Policies (visibility)
Doc 10 requires that each Task Kind is assigned a **Task Access Policy**, and each worker is granted access to one or more policies.

#### 5.4.1 Create the master DocType: `Task Access Policy`
1) Open `DocType`.
2) Click `New`.
3) Set:
   - `Name`: `Task Access Policy`
   - Ensure `Is Child Table` is unchecked
   - Set `Autoname` = `field:policy_name`
4) Add fields:
   - `policy_name` (Data) → Req → Unique
   - `notes` (Small Text) → optional
5) Save.

Create records (one per Task Kind). Current list:
- Order entry
- Pack / prepare items
- Dispatch picking / hand-off
- Delivery
- Return Call
- Return to warehouse (aborted delivery / cancelled order)
- Pickup Returns
- Return drop-off at warehouse
- Returns processing / verification
- Returns restocking
- Invoice preparation / create invoice
- Debt Collection
- Distribute Payment
- Payment Received
- Discount Approval
- Purchase Approval
- Write-off Approval
- Account Details: Entry
- Account Details: Processing
- Other
- Other: Entry
- Other: Processing
- Debt Closure Approval

Each record now also stores `default_team_user` and `allowed_roles` (see section 6A).

#### 5.4.2 Add `task_access_policy` field on `Task`
1) Open `Customize Form`.
2) Select DocType: `Task`.
3) Add a custom field:
   - Label: `Task Access Policy`
   - Fieldname: `task_access_policy`
   - Fieldtype: `Link`
   - Options: `Task Access Policy`
   - Recommended: Read Only (set by automation based on `task_kind`)
4) Save.

#### 5.4.3 Grant users access to policies (User Permissions)
To control which tasks each user can see:

1) Open `User Permission`.
2) Create permissions for each user:
   - Allow `Task Access Policy` = the policies they should be able to see.

Examples:
- A driver user:
  - Delivery
  - Pickup Returns
  - Return drop-off at warehouse
  - Pack / prepare items (if you want drivers to see packing tasks)
- Directors/coordinators:
  - All policies

Important:
- If a Task is missing `task_access_policy`, users may not be able to see it.
- To avoid “invisible tasks”, ensure your automation always sets `task_access_policy`.

#### 5.4.4 Enable User Permission filtering on `Task` (required)
If you want Task visibility to actually be restricted by `task_access_policy`, you must enable user-permission checks on the Task DocType.

1) Open `Role Permission Manager`.
2) Select DocType: `Task`.
3) For each operational role that uses Tasks, enable `Apply User Permissions`.
4) Save.

Notes:
- Directors/coordinators can still see everything by granting them User Permissions for all Task Access Policies.
- If you later want a “TV dashboard user” that can see everything, grant that user all policies.

---

## 6) Enforce mandatory attachments + single-owner + team ownership (required)
This section enforces Doc 10’s critical governance rules at the system level:
- `Delivery` cannot be completed without `Warehouse Pickup Photo`
- `Return drop-off at warehouse` cannot be completed without `Warehouse Drop-off Photo`
- `completed_at` is filled when Task becomes `Completed`
- A Task must have exactly 1 owner (assignment)
- A Task may only be completed/edited by its owning team (except Directors/System Manager)
- `task_access_policy` is auto-filled from `task_kind` (so tasks do not become invisible)

### 6.1 Create the Task governance `Server Script`
1) Open `Server Script`.
2) Click `New`.
3) Set:
   - `Script Type`: `DocType Event`
   - `Reference DocType`: `Task`
   - `DocType Event`: `Before Save`
4) Paste the following script:

```python
import json

import frappe
from frappe.utils import now_datetime

before = doc.get_doc_before_save()
before_status = before.status if before else None

is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

DIRECTOR_ROLE = "Ops - Directors"

TASK_KIND_ALLOWED_ROLES = {
    "Order entry": ["Ops - Order Accepting"],
    "Pack / prepare items": ["Ops - Inventory"],
    "Dispatch picking / hand-off": ["Ops - Delivery"],
    "Delivery": ["Delivery Driver", "Ops - Delivery"],
    "Return to warehouse (aborted delivery / cancelled order)": ["Delivery Driver", "Ops - Delivery"],
    "Pickup Returns": ["Delivery Driver", "Ops - Delivery"],
    "Return drop-off at warehouse": ["Delivery Driver", "Ops - Delivery"],
    "Returns processing / verification": ["Ops - Returns", "Ops - Inventory"],
    "Invoice preparation / create invoice": ["Ops - Accounting"],
    "Debt Collection": ["Ops - Directors"],
    "Distribute Payment": ["Ops - Directors"],
    "Discount Approval": ["Ops - Directors"],
    "Purchase Approval": ["Ops - Directors"],
    "Write-off Approval": ["Ops - Directors"],
}

def current_user_roles():
    return set(frappe.get_roles(frappe.session.user) or [])

def has_any_role(user_roles, allowed_roles):
    return any(r in user_roles for r in (allowed_roles or []))

def is_admin_override(user_roles):
    return bool(
        "System Manager" in user_roles
        or DIRECTOR_ROLE in user_roles
        or "Administrator" == frappe.session.user
    )

def get_assigned_users(task_doc):
    try:
        return json.loads(task_doc.get("_assign") or "[]") or []
    except Exception:
        return []

def user_has_allowed_role(user, allowed_roles):
    roles = set(frappe.get_roles(user) or [])
    return has_any_role(roles, allowed_roles)

# Always ensure task_access_policy matches task_kind (Doc 10 visibility model)
if doc.task_kind and not doc.task_access_policy:
    doc.task_access_policy = doc.task_kind

if doc.task_access_policy and not frappe.db.exists("Task Access Policy", doc.task_access_policy):
    frappe.throw(
        f"Task Access Policy '{doc.task_access_policy}' does not exist. Create it (Doc 10A section 5.4.1) so tasks are visible."
    )

user_roles = current_user_roles()
allowed_roles = TASK_KIND_ALLOWED_ROLES.get(doc.task_kind) or []

# Edit enforcement (Doc 10 section 6.1): owning team may edit, Directors/System Manager override.
if before and doc.task_kind and not is_admin_override(user_roles):
    if not has_any_role(user_roles, allowed_roles):
        frappe.throw(
            f"You are not allowed to edit Task Kind '{doc.task_kind}'. Only the owning team can edit it (or Directors/System Manager)."
        )

# Completion enforcement: only owning team may complete, Directors/System Manager override.
if is_becoming_completed and doc.task_kind and not is_admin_override(user_roles):
    if not has_any_role(user_roles, allowed_roles):
        roles_text = ", ".join([f"'{r}'" for r in allowed_roles])
        frappe.throw(f"Only users with roles {roles_text} can complete Task Kind '{doc.task_kind}'.")

# Mandatory attachments — SUPERSEDED by Doc 18
# Photo gates now use task_has_image(doc.name) which checks File records.
# Delivery tasks no longer require photos. Pack and Pickup Returns tasks do.
# See Task-before-save-dispatch-gates.py for current implementation.

# Single-owner enforcement (Doc 10 section 2 + 6)
# Notes:
# - On the very first save of a new task, you may not yet have assignment set.
# - We enforce single-owner once the task moves beyond Open, and always at completion.
assigned_users = get_assigned_users(doc)

if doc.task_kind and doc.status not in ("Cancelled", "Open"):
    if len(assigned_users) != 1:
        frappe.throw("Each operational task must be assigned to exactly 1 user (Doc 10: one accountable owner).")

if doc.task_kind and len(assigned_users) == 1 and allowed_roles:
    owner = assigned_users[0]
    if not user_has_allowed_role(owner, allowed_roles):
        roles_text = ", ".join([f"'{r}'" for r in allowed_roles])
        frappe.throw(
            f"Task Kind '{doc.task_kind}' must be assigned to a user in the owning team. Allowed roles: {roles_text}."
        )

if is_becoming_completed:
    if len(assigned_users) != 1:
        frappe.throw("You must assign exactly 1 owner before completing this task.")

if is_becoming_completed and not doc.completed_at:
    doc.completed_at = now_datetime()
```

### 6.2 Validation (must pass)
1) Create a Task:
   - Task Kind = `Delivery`
   - Assign exactly one driver user (use the `Assign` button)
2) Try to mark it `Completed` without `Warehouse Pickup Photo`:
   - Must fail.
3) Attach `Warehouse Pickup Photo` and complete:
   - Must succeed.
4) Confirm `completed_at` was filled automatically.
5) Create a Task:
   - Task Kind = `Return drop-off at warehouse`
   - Assign exactly one driver user (use the `Assign` button)
6) Try to mark it `Completed` without `Warehouse Drop-off Photo`:
   - Must fail.
7) Attach `Warehouse Drop-off Photo` and complete:
   - Must succeed.
8) Create a Task:
   - Task Kind = `Pack / prepare items`
9) Try to complete it as a user without the `Ops - Inventory` role:
   - Must fail.

---

## 6A) Current implementation architecture (2026-08 refactor)

> This section supersedes the script in 6.1. The old script is kept above for historical reference only.

### Overview of deployed Server Scripts

| Script name | Type | Purpose |
|---|---|---|
| `Task-before-save-policy` | Before Save | Reads allowed roles and default team from Task Access Policy. Enforces role checks, auto-assigns default team, syncs `_assign`, photo gates for non-DC tasks, sets `completed_at`. |
| `Task-before-save-lock-unaccepted` | Before Save | Enforces acceptance lock: unaccepted tasks cannot be edited. Resets acceptance on reassignment. |
| `Task-before-save-dispatch-gates` | Before Save | Enforces dispatch-specific gates: acceptance required, photo requirements, delivery status sequencing, pack item verification, invoice submission check, etc. |
| `dispatch_task_accept` | API | Accept endpoint: validates role, cancels old ToDos, sets accepted_by/at, updates assignment, creates new ToDo. |
| `task_list_filtered` | API | Returns filtered task names based on user roles and toggle state (my/open/completed). Reads from policy records. |
| `Task-after-save-dispatch-flow` | After Save | Dispatch Case automation: creates next-step tasks, stock entries, invoices, debt tasks. Uses `team_map` from policies. |
| `Task-after-save-other-processing` | After Save | When "Other: Entry" completes, creates "Other: Processing" task with attachments. |
| `Telegram Task Assignment Notification` | After Save | Sends Telegram messages when assignment changes. Expands team placeholders to real users. |
| `Telegram Task Status Update` | After Save | Sends Telegram status updates to task owner on key status changes. |

### Overview of deployed Client Scripts

| Script name | Purpose |
|---|---|
| `Task-Accept Start` | Renders Accept button and Complete button. Calls `dispatch_task_accept` API. |
| `Task-Lock Unaccepted` | Locks/unlocks form fields based on acceptance status. |
| `Task-Dispatch Packing Usability` | Dispatch Case helper comments, packing-specific UI. |
| `Global-Mobile Back Button List` | Mobile back button, toggle filter bar (My/Open/Completed), calls `task_list_filtered`. |
| `Task-Auto Reload` | Auto-reloads task form when server has newer data. |

### Task Access Policy (single source of truth for mappings)

The `Task Access Policy` DocType stores:
- `policy_name` (= Task Kind name, used as the primary key)
- `default_team_user` (Link to User) — the team placeholder email
- `allowed_roles` (child table: `Task Access Policy Role`) — roles that may access this kind

**All Server Scripts read from these records at runtime.** There are no hardcoded role dictionaries or team constants in any script. To change a mapping, edit the policy record in ERPNext.

Child DocType: `Task Access Policy Role` (istable=1, module=Custom, custom=1)
- Field: `role` (Link to Role, required, in_list_view)

### Canonical team/role mappings (as of 2026-08)

| Task Kind | Default Team User | Allowed Roles |
|---|---|---|
| Order entry | order.creation.team@example.com | Ops - Order Accepting, Ops - Order Creating |
| Pack / prepare items | inventory.team@example.com | Ops - Inventory |
| Dispatch picking / hand-off | delivery.team@example.com | Ops - Delivery |
| Delivery | delivery.team@example.com | Delivery Driver, Ops - Delivery |
| Return Call | office.team@example.com | Ops - Returns, Ops - Order Accepting |
| Return to warehouse... | delivery.team@example.com | Delivery Driver, Ops - Delivery |
| Pickup Returns | delivery.team@example.com | Delivery Driver, Ops - Delivery, Ops - Returns |
| Return drop-off at warehouse | delivery.team@example.com | Delivery Driver, Ops - Delivery |
| Returns processing / verification | returns.team@example.com | Ops - Returns, Ops - Inventory |
| Returns restocking | returns.team@example.com | Ops - Returns |
| Invoice preparation / create invoice | accounting.team@example.com | Ops - Accounting |
| Debt Collection | finance.team@example.com | Ops - Finance, Ops - Directors |
| Distribute Payment | finance.team@example.com | Ops - Finance, Ops - Directors |
| Payment Received | finance.team@example.com | Ops - Finance, Ops - Directors |
| Discount Approval | directors.team@example.com | Ops - Directors |
| Purchase Approval | directors.team@example.com | Ops - Directors |
| Write-off Approval | directors.team@example.com | Ops - Directors |
| Account Details: Entry | accounting.team@example.com | Ops - Accounting, Ops - Finance, Ops - Directors |
| Account Details: Processing | accounting.team@example.com | Ops - Accounting, Ops - Finance, Ops - Directors |
| Other | office.team@example.com | All Ops roles + Delivery Driver |
| Other: Entry | office.team@example.com | All Ops roles + Delivery Driver |
| Other: Processing | office.team@example.com | All Ops roles + Delivery Driver |
| Debt Closure Approval | directors.team@example.com | Ops - Directors |

### Stale/legacy policy records (do NOT populate)
- `Order accepting` — superseded by "Order entry"
- `Account details` — superseded by "Account Details: Entry" / "Account Details: Processing"

### Diagnostic logging

All scripts emit structured logs using `print()` (server) or `console.log()` (client). Each tag is grep-able:

**Server tags:** `[Policy]`, `[Accept]`, `[List]`, `[Dispatch]`, `[Lock]`, `[Gates]`, `[OtherFlow]`, `[TgAssign]`, `[TgStatus]`, `[Photo]`

**Client tags:** `[TaskAccept]`, `[TaskLock]`, `[TaskAuto]`, `[TaskPack]`, `[TaskToggle]`

### Deployment

Deploy script: `deploy/test/scripts/deploy-team-mapping-unification.ps1`
- Creates child DocType, adds custom fields, populates policy records, deploys all scripts.
- Supports `-Mode Check` (dry run) and `-Mode Deploy`.

Previous refactor deploy: `deploy/test/scripts/deploy-task-unification.ps1`
- Created team users, Telegram fields, migrated stale data, deployed scripts.

---

## 7) Stage-gate patterns (blocking workflow until tasks are completed)
Doc 10 requires “always tasks” and stage gates.

This section describes step-by-step ways to enforce stage gates in ERPNext.

### 7.1 Implement stage gates in the upstream operational document (recommended)
If your operational record is `Surgery Case`, `Sales Order`, or another custom DocType:

Steps:
1) Identify the workflow transition that must be gated.
2) Decide which Task Kind(s) must be completed before that transition (as defined in Doc 10).
3) In the upstream document’s server-side validation (custom app or Server Script), check:
   - required Task exists, and
   - required Task is `Completed`
4) If the task is missing or not completed, block the transition with `frappe.throw()`.

### 7.2 Implement stage gates using Workflow conditions (optional)
Steps:
1) Add a condition on the Workflow transition.
2) The condition must evaluate to true only when the required task(s) are completed.

Note:
- This can be harder to maintain when conditions depend on other documents (Tasks).

---

## 8) Standard task creation rules (idempotency)
Doc 10 requires that tasks are not duplicated.

Auditability rule (Doc 10):
- Do not delete Tasks.
- If a Task is no longer needed, set `Status` = `Cancelled` and add a short reason in the Description (example: `Cancelled: client rescheduled`).

When implementing task creation (custom app or Server Script), follow these steps:
1) Before creating a task, search for an existing open task with:
   - same `task_kind`
   - same reference link (example: same `surgery_case`)
   - `status` not in (`Completed`, `Cancelled`)
2) If found:
   - update it (assignee, description, due date)
   - do not create a new task
3) If not found:
   - create it
4) If you use strict visibility (Doc 10 Policy B):
   - ensure `task_access_policy` is set before inserting the Task

---

## 9) Testing checklist
- Drivers can:
  - open assigned Tasks
  - attach a photo
  - complete a `Delivery` task only when Warehouse Pickup Photo is attached
  - complete a `Return drop-off at warehouse` task only when Warehouse Drop-off Photo is attached
- Back-office users can:
  - create tasks for any kind
  - reassign tasks
- Idempotency:
  - repeated workflow actions do not create duplicate open tasks for the same event
- Stage gates:
  - workflows cannot progress until the required tasks are completed

Task Access Policy visibility test:
- A driver user cannot see director-only tasks (Debt Collection / Approvals)
- A driver user can see packing tasks if and only if they have permission for the packing policy
- A director/coordinator user can see all task kinds if they have permissions for all policies

Assignment hygiene test:
- There are no tasks in status `Working` or `Completed` with:
  - zero assignees, or
  - more than one assignee
