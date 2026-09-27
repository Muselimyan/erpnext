# Doc 10 — Task System Foundations (Operational)

## 1) Purpose
This document defines how your company uses **ERPNext Tasks** to run operations.

Goals:
- Ensure every operational step has a clear **owner**.
- Make work measurable and auditable (who did what, when).
- Keep the driver experience simple (tasks only, minimal ERPNext knowledge).
- Standardize **task types**, **statuses**, **assignment rules**, and **mandatory attachments**.

Non-goals:
- This doc does **not** describe scripts, server automation, or configuration steps (those belong in implementation docs like Doc 12A).

---

## 2) Core principles
- **One task = one accountable owner**
  - A task must be assigned to a specific person (a `User`), not “the whole team”.
- **Tasks drive stage-gates**
  - If a workflow step requires proof or completion, the related Task must be completed before the case/order can move forward.
- **Tasks are mandatory for every operational stage**
  - Your company policy is “always tasks”: each stage is tracked by a Task, owned by a specific team/person.
- **Idempotent task creation** (operational expectation)
  - The same workflow step should not create duplicate tasks.
  - If a task already exists, it should be updated (not duplicated).
- **Auditability over convenience**
  - Don’t delete tasks. If something is no longer needed, set it to `Cancelled` with a note.

---

## 3) Standard task fields (operational requirements)
These are the minimum fields each operational Task must have, regardless of type:
- **Subject**: must clearly identify the work.
- **Status**: use the standardized meanings in this doc.
- **Assigned To**: one responsible `User`.
- **Reference links** (where applicable): link to the operational record that the task is for.

Recommended additional fields (used across multiple processes):
- **Task Kind**: a controlled classification of tasks (examples below).
- **Dispatch Case**: links the task to the operational order record.
- **Customer/Client**: used for debt collection and logistics.
- **Driver handover**: recorded in the Task description (example: who the package was handed to).

---

## 4) Task kinds (catalog)
Task Kind is a classification that drives:
- what must be attached
- which roles can complete the task
- what workflow step is gated by the task

You should keep the list short and stable.

Rule:
- Every operational stage has a Task Kind and a Task.
- Each Task Kind has a default owning team.

### 4.1 Order entry
Purpose:
- Track inbound requests that must be entered into ERPNext (when work starts outside ERPNext: phone/WhatsApp/email).

Primary owner:
- Order accepting team

Typical links:
- Customer/Client
- Related reference (free text) and the Dispatch Case, which is created automatically when the task is accepted

Attachments:
- Optional (example: screenshot of message)

Completion definition:
- The request is entered into ERPNext and linked.

### 4.2 Pack / prepare items
Purpose:
- Assign packing of items/sets to a specific warehouse/preparing person.

Primary owner:
- Inventory team

Typical links:
- `Dispatch Case` (the operational order record)

Attachments:
- **Warehouse Pickup Photo** (required) — photo taken at Main - Inmed after packing, before the driver leaves. See Doc 18.

Completion definition:
- Items are packed, a photo is attached, and the task is ready for delivery.

### 4.4 Delivery
Purpose:
- Assign a delivery trip to a specific driver.

Primary owner:
- Delivery team

Typical links:
- `Dispatch Case`

Attachments:
- None required. Photo evidence is captured at the Pack stage, not Delivery. See Doc 18.
- Optional: delivery proof (if you later decide it's needed)

Completion definition:
- Driver confirms delivery is done.
- Driver records a short handover note (freeform) in the Task description (example: who it was handed to).

### 4.4A Return to warehouse (aborted delivery / cancelled order)
Purpose:
- When a Dispatch Case is cancelled while `Packed` or `In Transit`, bring the goods back from `Delivery In-Transit` to the warehouse. Raised automatically by the Cancel Case action (`docs/16` §10A).

Primary owner:
- Delivery team. When the case was `In Transit`, the task goes to the driver who accepted the Delivery task, because that driver holds the box.

Typical links:
- `Dispatch Case`

Attachments (mandatory):
- **Photo** of the goods being handed back

Completion definition:
- The goods are handed back and a photo is attached. Completion moves them `Delivery In-Transit` → `Returns` and raises Returns processing / verification.

### 4.5 Pickup Returns
Purpose:
- Assign a return pickup trip to a specific driver.

Primary owner:
- Delivery team

Typical links:
- `Dispatch Case`

Attachments:
- None required

Completion definition:
- Driver completed pickup.

### 4.6 Return drop-off at warehouse
Purpose:
- If you want to split “pickup at client location” from “delivered back to your warehouse”, use this task kind.
- If you do not split, then the `Pickup Returns` task covers both pickup and bringing the package back.

Primary owner:
- Delivery team

Typical links:
- `Dispatch Case`
- Optional list of included documents in the description

Attachments (mandatory):
- **Drop-off Photo** (photo taken before handing the package to the Returns Team)

Completion definition:
- Returned packages physically handed to the Returns Team.

### 4.7 Returns processing / verification
Purpose:
- Assign the warehouse/returns team work of opening packages, counting items, and submitting return stock movements.

Primary owner:
- Inventory team

Typical links:
- `Dispatch Case`
- The return `Stock Entry` documents

Attachments:
- Optional (example: photos of damaged tools)

Completion definition:
- Returned quantities are entered, and the return Stock Entries are submitted with the correct returned serials/batches.

### 4.8 Invoice preparation / create invoice
Purpose:
- Assign Accounting the work of invoicing used items after usage is derived.

Primary owner:
- Accounting team

Typical links:
- `Dispatch Case`
- `Sales Invoice` (created and submitted by **Create & Submit Invoice** on this task)

Attachments:
- Optional

Completion definition:
- The invoice has been created and submitted with **Create & Submit Invoice** (`task_commit_invoice`), billing used quantities only; or the case was closed with **Nothing to Invoice**.

### 4.9 Debt Collection
Purpose:
- One collection attempt for a customer with money owed: an episode. At most one is open per customer. Raised by a scheduler when an invoice is overdue, the debt threshold is breached, or a promised follow-up date arrives.

Primary owner:
- Finance team (Directors also have access)

Typical links:
- Customer/Client. Balances are shown live from the ledger (debt panel), not stored on the task.

Attachments:
- None required

Completion definition:
- A `collection_outcome` is recorded. `Promised` requires a future follow-up date, which schedules the next episode.

### 4.9A Debt Alert
Purpose:
- Tell Directors that a client's net debt has exceeded its threshold. Raised hourly; it records the debt at the moment it was raised.

Primary owner:
- Directors

Typical links:
- Customer/Client

Attachments:
- None required

Completion definition:
- Director reviewed it. Payments are never recorded on a Debt Alert.

### 4.11 Approval (optional grouping)
If you later centralize approvals (discount approval, purchase approval, write-off approval), standardize them as Task kinds.

Primary owner:
- Directors

Examples:
- `Discount Approval`
- `Pricing Override Approval` (optional, if you want approvals for special-price changes)
- `Purchase Approval`
- `Write-off Approval`

Attachments:
- Optional, policy-based (example: supplier email, screenshots)

Completion definition:
- Approver explicitly accepted/rejected with a note.

### 4.12 Other / Other: Entry / Other: Processing
Purpose:
- Catch-all for ad-hoc tasks that don't belong to a specific workflow stage.
- `Other: Entry` is used for intake/recording work; `Other: Processing` for follow-up.
- When `Other: Entry` is completed, an `Other: Processing` task is automatically created with the same attachments and description.

Primary owner:
- Office team (accessible by all operational roles)

Attachments:
- Optional

Completion definition:
- As defined by the task creator.

---

## 5) Task statuses (standard meanings)
ERPNext provides Task statuses; use them with consistent meaning.

Meanings:
- **Open**
  - Task exists and is assigned to a team/user but has not yet been accepted.
- **Working**
  - A user has explicitly **accepted** the task and is actively working on it.
- **Completed**
  - Done.
- **Cancelled**
  - No longer needed (must include a short reason in the task description or notes).

Operational rules:
- Don’t use `Completed` as “we tried”. Use `Cancelled` for abandoned work, with a reason.

---

## 6) Assignment, acceptance, and lock model

### 6.1 Default assignment (team placeholders)
When a task is created by automation (dispatch flow, "Other: Entry" chain, etc.):
- It is assigned to the **default team user** for that Task Kind (a placeholder email like `delivery.team@example.com`).
- The task starts in status **Open**.
- Telegram notifications to the team's users exist as server scripts but are currently disabled.

### 6.2 Acceptance (mandatory before editing/completing)
Rules:
- A user must explicitly **accept** a task before they can edit or complete it.
- Acceptance is performed via the "Accept / Start Task" button (calls `dispatch_task_accept` API).
- On acceptance:
  - `custom_accepted_by` and `custom_accepted_at` are set.
  - `custom_assigned_to` and `_assign` are updated to the accepting user.
  - Status changes to **Working**.
  - Existing open ToDos for the team placeholder are cancelled; a new ToDo is created for the accepting user.
- Role check: only users with an allowed role for the task's kind may accept it. Administrators and System Managers bypass this check.

### 6.3 Lock (only the accepted user may edit)
Rules:
- Once a task is accepted, **only the user who accepted it** may edit or complete it.
- Other users (including those with the correct role) see the task as read-only on the client.
- Privileged users (`System Manager`, `Ops - Directors`, the `Administrator` user) may **edit** another user's task to unstick it, but may **never complete** it: completion is reserved to the accepter, with no exemption.
- Completed and Cancelled tasks cannot be edited at all.
- If the task is reassigned, acceptance is reset (status reverts to Open, `custom_accepted_by` is cleared), and the new assignee must accept again.

### 6.4 Team ownership and role enforcement
Rules:
- Each Task Kind has a set of **allowed roles** (stored in the Task Access Policy record).
- Only users with at least one allowed role may accept, edit, or complete that task kind.
- At accept time, the `Administrator` user and `System Manager` bypass the role check. At save time, `System Manager`, `Ops - Directors` and `Administrator` bypass the edit role check. Nobody bypasses completion ownership.
- Enforcement happens at both save time (Server Script) and accept time (API).

### 6.5 Visibility (task list filtering)
Rules:
- The task list API (`task_list_filtered`) shows a user only:
  - Tasks whose kind has a role the user possesses.
  - Tasks assigned to the user or to a team placeholder.
- Administrators see all tasks.
- Toggle filters: "My Tasks", "Open Tasks", "Completed" control the query.

### 6.6 Reassignment
- Reassigning a task (changing `custom_assigned_to`) resets acceptance.
- The new assignee must accept before editing.
- A task cannot be reassigned and completed in the same save.

### 6.7 General rules
- **Exactly one owner** - Each operational task must have one primary assignee.
- **If multiple people must act, create multiple tasks** (driver pickup + returns counting are different responsibilities).
- **No driver stock responsibilities** - Drivers should only be assigned tasks that are driver-friendly.

### 6.8 Task Access Policy (canonical mapping)
The **Task Access Policy** DocType is the single source of truth for:
- **default_team_user**: the team placeholder email assigned when a task is created.
- **allowed_roles**: the child table of roles that may see/accept/edit/complete that task kind.

There is one Task Access Policy record per Task Kind. Scripts read from these records at runtime rather than using hardcoded dictionaries. To change which team owns a task kind or which roles can access it, update the policy record.

> **Superseded:** The old 6.1/6.2 sections describing team ownership enforcement and visibility policy are now implemented via the mechanisms above (sections 6.2-6.5). The old sections described the *intent*; the current implementation uses acceptance + lock + role-filtered list API.

### (Legacy) Team ownership enforcement
Rules:
- A Task must only be assigned to a person from the Task Kind’s owning team.
- Only the Task Kind’s owning team may edit the task (except Directors/Coordinators).
- Only the Task Kind’s owning team may mark that task as `Completed`.
- Task owner reassignment must be possible (operational reality).
- Who is allowed to reassign tasks is a policy decision (decide later), but every reassignment must be explicit and traceable.

Purpose:
- Prevent wrong-team completion (example: Delivery team closing Packing tasks).
- Ensure every Task Kind remains a reliable stage-gate.

### 6.2 Visibility policy (choose one)
Doc 10 requires flexible visibility rules per Task Kind.

Rule:
- Each Task Kind must be assigned a **Task Access Policy**.
- Recommended: create **one Task Access Policy per Task Kind** (most flexible).
- Each worker is granted access to one or more Task Access Policies.
- A user can only see tasks whose Task Access Policy they have access to.

Important:
- Visibility policy controls what users can see.
- Completion is still controlled by team ownership (section 6.1): even if someone can see a task, it does not mean they can complete it.
- Users outside the owning team treat the task as **read-only**.

Example (allowed):
- Drivers can see:
  - their delivery/pickup tasks (and can edit/complete them)
  - packing tasks (read-only)
- Drivers cannot see:
  - director-only tasks (debt collection, approvals)

This is an operational decision. Implementation steps belong in Doc 10A.

---

## 7) Mandatory attachment policy (critical controls)
> **Full photo system specification:** See **Doc 18 — Photo System** for complete rules, field visibility, permission model, upload limits, propagation, and observability.

### 7.1 Pack task pickup photo requirement (outgoing)
Rule:
- A `Pack / prepare items` task cannot be marked **Completed** unless a Warehouse Pickup Photo is attached (photo taken at `Main - Inmed` after packing, before the driver leaves).

Reason:
- This is your operational proof that items were packed and ready for dispatch.

Note: This requirement is on the **Pack** task, not the Delivery task. The Delivery task has no photo requirement.

### 7.2 Return drop-off photo requirement (incoming)
Rule:
- A `Pickup Returns` task cannot advance to "Returned to Warehouse" unless a Drop-off Photo is attached.

Reason:
- This is your operational proof that the package was brought back and handed to the Returns Team.

### 7.3 Delivery photo (not required)
Delivery tasks do not require photos. The driver's job is to deliver; photo evidence is captured at the packing stage (Pack task).
- If you later decide delivery proof is needed, introduce a separate attachment requirement on the Delivery task.

---

## 8) Stage gates (how tasks control workflow)
A “stage gate” is a rule that a document can only move to the next workflow step when required tasks are completed.

Operational rule:
- A stage is not considered complete until its Task is `Completed`.

Required gates for your current model:
- **Pack / prepare gate**
  - Do not allow dispatch/hand-off until the `Pack / prepare items` task is `Completed`.

- **Delivery gate**
  - Do not confirm delivery until the `Delivery` task is `Completed`.

- **Return drop-off gate**
  - Do not start returns processing until the `Return drop-off at warehouse` task is `Completed` and the drop-off photo is attached.

- **Returns processing gate**
  - Do not derive usage / invoice until the `Returns processing / verification` task is `Completed`.

- **Invoice gate**
  - Do not close the case/order until the `Invoice preparation / create invoice` task is `Completed`.

Note:
- Stage gates must be enforced consistently. If users can bypass them, tasks lose meaning.

---

## 9) Task naming conventions (for clarity and search)
Recommended `Subject` patterns:
- **Order entry**: `Enter Order — <Client Name>`
- **Pack / prepare**: `Pack — <Dispatch Case ID>`
- **Delivery**: `Deliver — <Dispatch Case ID>`
- **Pickup Returns**: `Pickup Returns — <Dispatch Case ID>`
- **Returns processing / verification**: `Process Returns — <Dispatch Case ID>`
- **Invoice preparation / create invoice**: `Invoice — <Dispatch Case ID>`
- **Debt Collection**: `Debt Collection — <Client Name>`

Rule:
- Always include a searchable identifier (Dispatch Case ID / Client name).

---

## 10) Reporting expectations (how you will “run the day”)
Minimum daily views you should be able to filter:
- Tasks assigned to me (driver view)
- Open logistics tasks by person (Delivery / Pickup Returns)
- Open debt collection tasks by client
- Overdue tasks (optional)

Recommended dimensions:
- Task Kind
- Assigned To
- Status
- Due Date / Planned Date (if you decide to use them)

---

## 11) Roles and separation of duties (operational)
- **Drivers**
  - Can see and complete assigned tasks.
  - Must not be responsible for stock posting.
- **Coordinators**
  - Assign drivers.
  - Move workflow steps after tasks are completed (where applicable).
- **Warehouse / Returns Team**
  - Do stock posting and serial/batch verification.
- **Directors**
  - Handle escalations (debt, approvals).

---

## 12) Acceptance criteria
- Every key operational step has a Task with a clear owner.
- Pack tasks capture warehouse-pickup photo evidence (required for completion).
- Pickup Returns tasks capture warehouse drop-off photo evidence (required before marking Returned to Warehouse).
- Coordinators can see, at any moment:
  - which deliveries/pickups are assigned to which driver
  - which tasks are overdue or stuck
- Tasks are not duplicated for the same event; existing tasks are updated.
