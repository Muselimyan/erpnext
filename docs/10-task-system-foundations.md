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
- **Dispatch Group ID**: used when one trip covers multiple documents.
- **Surgery Case**: used for surgery-set operations.
- **Customer/Client**: used for debt collection and logistics.
- **Driver Handover Note**: freeform text for delivery handover details (example: who the package was handed to).

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
- Related reference (free text) and/or the final `Sales Order` / `Surgery Case` once created

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
- `Surgery Case` (for surgery sets)
- `Sales Order` (for normal orders)

Attachments:
- Optional

Completion definition:
- Items are packed and ready for dispatch picking.

### 4.3 Dispatch picking / hand-off (serial/batch selection checkpoint)
Purpose:
- Assign the work of final dispatch verification and stock movement submission.
- For traceable items, this is where serial numbers / batch numbers are selected on the dispatch Stock Entry.

Primary owner:
- Delivery team

Typical links:
- `Surgery Case`
- Draft dispatch `Stock Entry`
- Optional `Dispatch Group ID`

Attachments:
- Optional

Completion definition:
- Dispatch Stock Entry is submitted with correct serials/batches (where applicable).

### 4.4 Delivery
Purpose:
- Assign a delivery trip to a specific driver.

Primary owner:
- Delivery team

Typical links:
- `Dispatch Group ID` (preferred when multiple documents are delivered together)
- or the specific document (example: `Surgery Case`)

Attachments:
- Required at go-live:
  - **Warehouse Pickup Photo** (photo taken at `Main - WH` pickup, after packing, before leaving)
- Optional:
  - delivery proof (if you later decide it’s needed)

Completion definition:
- Driver confirms delivery is done.
- Driver records a short handover note (freeform) in the Task description (example: who it was handed to).

### 4.4A Return to warehouse (aborted delivery / cancelled order)
Purpose:
- When a standard delivery is cancelled after dispatch staging (package already with driver), track the safe return of the package back to the warehouse.

Primary owner:
- Delivery team

Typical links:
- `Dispatch Group ID` (preferred)
- or the specific document (example: `Sales Order`)

Attachments (recommended):
- **Drop-off Photo** (photo taken before handing the package back to Inventory/Returns team)

Completion definition:
- Driver physically returned the package to the warehouse and attached the drop-off photo.

### 4.5 Pickup Returns
Purpose:
- Assign a return pickup trip to a specific driver.

Primary owner:
- Delivery team

Typical links:
- `Dispatch Group ID` (preferred)
- and/or one or more `Surgery Case` references

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
- `Dispatch Group ID`
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
- `Surgery Case`
- Draft return `Stock Entry` documents

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
- `Surgery Case`
- Draft `Sales Invoice`

Attachments:
- Optional

Completion definition:
- Draft invoice is reviewed and submitted (or ready for approval, depending on your policy).

### 4.9 Debt Collection
Purpose:
- Alert directors that a client has exceeded its allowed outstanding debt.

Primary owner:
- Directors

Typical links:
- Customer/Client
- Current outstanding debt amount (in the task description or a field)

Attachments:
- None required

Completion definition:
- Director reviewed and resolved (according to your internal policy).

### 4.10 Distribute Payment
Purpose:
- After a client payment is received, trigger an internal director-controlled step to distribute/assign the received money according to your internal rules.

Primary owner:
- Directors

Typical links:
- Customer/Client
- `Payment Entry`
- Optional: relevant `Sales Invoice` links (if helpful), but the canonical identifier is the payment receipt.

Attachments:
- Optional (policy-based)

Completion definition:
- Director confirms payment distribution is done and records a short note.

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

---

## 5) Task statuses (standard meanings)
ERPNext provides Task statuses; use them with consistent meaning.

Recommended meanings:
- **Open**
  - Task exists and is ready to be started.
- **Working**
  - Assignee is actively working on it.
- **Pending Review / Pending** (choose one consistent label you will use)
  - Work done by assignee, waiting for a coordinator/manager check.
- **Completed**
  - Done and accepted.
- **Cancelled**
  - No longer needed (must include a short reason in the task description or notes).

Operational rule:
- Don’t use `Completed` as “we tried”. Use `Cancelled` for abandoned work, with a reason.

---

## 6) Assignment rules
- **Exactly one owner**
  - Each operational task must have one primary assignee.
- **If multiple people must act, create multiple tasks**
  - Example: driver pickup + returns counting are different responsibilities.
- **Reassignment policy**
  - Reassigning a task is allowed, but the new assignee must be explicit.
  - If a task is reassigned, add a short note (why and when).
- **No driver stock responsibilities**
  - Drivers should only be assigned tasks that are driver-friendly and do not require Stock Entry/Sales knowledge.

### 6.1 Team ownership enforcement (required)
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
### 7.1 Warehouse pickup photo requirement (outgoing)
Rule:
- A `Delivery` task cannot be marked **Completed** unless a Warehouse Pickup Photo is attached.

Reason:
- This is your operational proof that the driver physically took the package from `Main - WH`.

### 7.2 Return drop-off photo requirement (incoming)
Rule:
- A `Return drop-off at warehouse` task cannot be marked **Completed** unless a Drop-off Photo is attached.

Reason:
- This is your operational proof that the package was brought back and handed to the Returns Team.

### 7.3 Delivery proof (optional)
If you later require delivery proof:
- Introduce a separate attachment requirement for `Delivery` tasks.
- Keep it optional until you explicitly decide it’s needed, because it adds driver friction.

---

## 8) Stage gates (how tasks control workflow)
A “stage gate” is a rule that a document can only move to the next workflow step when required tasks are completed.

Operational rule:
- A stage is not considered complete until its Task is `Completed`.

Required gates for your current model:
- **Pack / prepare gate**
  - Do not allow dispatch/hand-off until the `Pack / prepare items` task is `Completed`.

- **Dispatch picking / hand-off gate**
  - Do not allow “dispatched” until the `Dispatch picking / hand-off` task is `Completed`.

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
- **Pack / prepare**: `Pack — <Sales Order ID>` or `Pack — <Surgery Case ID>`
- **Dispatch picking / hand-off**: `Dispatch Picking — <Dispatch Group ID>` or `Dispatch Picking — <Surgery Case ID>`
- **Delivery**: `Deliver — <Dispatch Group ID>` or `Deliver — <Surgery Case ID>`
- **Pickup Returns**: `Pickup Returns — <Dispatch Group ID>` or `Pickup Returns — <Surgery Case ID>`
- **Returns processing / verification**: `Process Returns — <Surgery Case ID>`
- **Invoice preparation / create invoice**: `Invoice — <Surgery Case ID>`
- **Debt Collection**: `Debt Collection — <Client Name>`
- **Distribute Payment**: `Distribute Payment — <Payment Entry ID>`

Rule:
- Always include a searchable identifier (Case ID / Dispatch Group ID / Client name).

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
- Delivery tasks capture warehouse-pickup photo evidence.
- Return drop-off tasks capture warehouse drop-off photo evidence.
- Coordinators can see, at any moment:
  - which deliveries/pickups are assigned to which driver
  - which tasks are overdue or stuck
- Tasks are not duplicated for the same event; existing tasks are updated.
