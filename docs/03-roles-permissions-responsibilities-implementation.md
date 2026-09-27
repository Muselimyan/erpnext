# Doc 03A — Roles, Permissions, and Team Responsibilities (Implementation / ERPNext Setup Guide)

## 1) Purpose
This is a step-by-step guide to implement:
- **Doc 03 — Roles, Permissions, and Team Responsibilities (Operational)**

It covers:
- Creating roles
- Assigning roles to users
- Applying Role Permissions (what each role can read/write)
- Implementing Task visibility using **Task Access Policies**
- A smoke-test checklist to confirm it works

---

## 2) Prerequisites / access
Do this as a user with:
- `System Manager`

You will use:
- `Customize Form`
- `Server Script`
- `DocType`
- `Role`
- `User`
- `Role Permission Manager`
- `User Permission`
- `Task` (list and form)

---

## 3) Create roles (team roles + special roles)
Doc 03 assumes you have a small set of stable roles.

### 3.1 Create the team ownership roles
Create these roles:
- `Ops - Order Accepting`
- `Ops - Order Creating`
- `Ops - Inventory`
- `Ops - Returns`
- `Ops - Delivery`
- `Ops - Accounting`
- `Ops - Finance`
- `Ops - Purchasing`
- `Ops - Purchasing Lead`
- `Ops - Directors`

Steps (repeat for each role):
1) Open `Role`.
2) Click `New`.
3) Enter the role name exactly.
4) Save.

### 3.2 Create the driver execution role (if you want it separate)
Recommended role:
- `Delivery Driver`

Reason:
- Many companies want drivers to have “driver UI permissions” but still be considered part of `Ops - Delivery` for task ownership.

Decision (recommended for Doc 03 separation-of-duties):
- Use **two distinct roles** for the Delivery Team:
  - `Delivery Driver` (driver execution)
  - `Ops - Delivery` (dispatch coordination)
- Drivers get only `Delivery Driver`.
- Dispatch coordinators get `Ops - Delivery`.

---

## 4) Assign roles to users
### 4.1 Decide the role package per person
Recommended baseline:
- A driver:
  - `Delivery Driver`
- A delivery coordinator:
  - `Ops - Delivery`
- A warehouse/preparing worker:
  - `Ops - Inventory`
- A returns worker:
  - `Ops - Returns`
- An order-entry clerk:
  - `Ops - Order Creating`
- An accountant:
  - `Ops - Accounting`
- A finance worker:
  - `Ops - Finance`
- A director:
  - `Ops - Directors`

If one person does multiple jobs:
- Example: if the same warehouse worker also does returns processing, assign both:
  - `Ops - Inventory`
  - `Ops - Returns`

Rule:
- Keep roles minimal. Do not give extra roles “just in case”.

### 4.2 Assign roles
Steps:
1) Open `User`.
2) Open a user.
3) In Roles, add the required roles.
4) Save.

Sample data (recommended for initial setup + training):
- Create these users (email can be internal/non-real if you are in a test environment):
  - `order.team@example.com` → `Ops - Order Accepting`
  - `inventory.team@example.com` → `Ops - Inventory`
  - `returns.team@example.com` → `Ops - Returns`
  - `dispatch.coordinator@example.com` → `Ops - Delivery`
  - `driver.01@example.com` → `Delivery Driver`
  - `accounting.team@example.com` → `Ops - Accounting`
  - `director.01@example.com` → `Ops - Directors`

---

## 5) Role Permission Manager (what each role can do)
Important:
- These permissions control what a user can do *in general*.
- Task visibility per Task Kind is implemented separately using **Task Access Policies** (section 6).

### 5.1 Configure permissions for `Task`
Goal:
- Operations users can work with Tasks.
- Drivers can complete their tasks and add attachments.

Steps:
1) Open `Role Permission Manager`.
2) Select DocType: `Task`.
3) Set permissions per role:

Recommended baseline:
- `Delivery Driver`
  - Read: ON
  - Write: ON
- `Ops - Order Accepting`
  - Read: ON
  - Write: ON
- `Ops - Inventory`
  - Read: ON
  - Write: ON
- `Ops - Returns`
  - Read: ON
  - Write: ON
- `Ops - Delivery`
  - Read: ON
  - Write: ON
- `Ops - Accounting`
  - Read: ON
  - Write: ON
- `Ops - Directors`
  - Read: ON
  - Write: ON

4) Save.

Note:
- Edit/complete restrictions are enforced by the Task server-side validations in this doc (section 6.6).

### 5.2 Block drivers from stock and accounting documents
Goal:
- Drivers must not create/submit stock or invoices.

Steps:
1) In `Role Permission Manager`, check these DocTypes:
   - `Stock Entry`
   - `Sales Invoice`
   - `Payment Entry`
   - `Sales Order`
2) For role `Delivery Driver`, ensure:
   - Read/Write/Create are OFF
3) Save.

Practical note:
- If a driver can open these DocTypes by URL or search, you have not restricted permissions correctly.

### 5.3 Minimum permissions for Dispatch Cases (Order team)
Goal:
- Order team can create/update Dispatch Cases. The Dispatch Case is the operational order record; there is no Sales Order step.
- Other teams may read Dispatch Cases if needed, but do not edit. (Editing a Dispatch Case additionally requires holding an accepted task on it; that rule is enforced by the Dispatch Case access-control scripts, not by Role Permission.)

Steps:
1) Open `Role Permission Manager`.
2) Select DocType: `Dispatch Case`.
3) For `Ops - Order Accepting` and `Ops - Order Creating`:
   - Read: ON
   - Write: ON
   - Create: ON
4) For read-only visibility (recommended):
   - `Ops - Inventory`: Read ON, Write/Create OFF
   - `Ops - Returns`: Read ON, Write/Create OFF
   - `Ops - Delivery`: Read ON, Write/Create OFF
   - `Ops - Accounting`: Read ON, Write/Create OFF
   - `Ops - Directors`: Read ON, Write/Create OFF
5) For `Delivery Driver`:
   - Read/Write/Create: OFF
6) Save.

### 5.4 Minimum permissions for Stock Entries (Inventory + Returns)
Goal:
- Inventory/Returns can create and submit Stock Entries.
- Drivers and Order team cannot.

Steps:
1) Open `Role Permission Manager`.
2) Select DocType: `Stock Entry`.
3) For `Ops - Inventory`:
   - Read: ON
   - Write: ON
   - Create: ON
4) For `Ops - Returns`:
   - Read: ON
   - Write: ON
   - Create: ON
5) For `Delivery Driver` and `Ops - Order Accepting`:
   - Read/Write/Create: OFF
6) Save.

### 5.5 Minimum permissions for Sales Invoices and Payment Entries (Accounting)
Goal:
- Accounting can create invoices and record payments.
- Drivers cannot access financial documents.

Steps:
1) Open `Role Permission Manager`.
2) Select DocType: `Sales Invoice`.
3) For `Ops - Accounting`:
   - Read: ON
   - Write: ON
   - Create: ON
4) For `Delivery Driver`:
   - Read/Write/Create: OFF
5) Save.

Then repeat for DocType: `Payment Entry`:
- `Ops - Accounting`: Read/Write/Create ON
- `Ops - Finance`: Read/Write/Create ON (Finance also needs Read on `Account`, `Mode of Payment`, `Cost Center`, `Currency` and `Company`, or Payment Entry validation fails on the `paid_to` account link)
- `Delivery Driver`: Read/Write/Create OFF

---

## 6) Implement Task visibility using Task Access Policies
Doc 10 / Doc 03 require:
- each Task has a `task_access_policy`
- each user has access only to policies they are allowed to see

### 6.0 Ensure `Task` has the required fields (do this first)
This guide assumes Task has these custom fields (they are used by the visibility + enforcement scripts below).

Steps:
1) Open `Customize Form`.
2) Select DocType: `Task`.
3) Add a custom field:
   - Label: `Task Kind`
   - Fieldname: `task_kind`
   - Fieldtype: `Select`
   - Options (one per line, exactly; default `Order entry`):
     - Order entry
     - Pack / prepare items
     - Delivery
     - Return Call
     - Return to warehouse (aborted delivery / cancelled order)
     - Pickup Returns
     - Return drop-off at warehouse
     - Returns processing / verification
     - Returns restocking
     - Invoice preparation / create invoice
     - Debt Collection
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
     - Debt Alert
4) Add a custom field:
   - Label: `Completed At`
   - Fieldname: `completed_at`
   - Fieldtype: `Datetime`
   - Read Only: ON
5) Save.

### 6.1 Create the DocType `Task Access Policy`
Steps:
1) Open `DocType`.
2) Click `New`.
3) Set:
   - `Name`: `Task Access Policy`
   - Ensure `Is Child Table` is unchecked
   - Set `Autoname` = `field:policy_name`
4) Add fields:
   - `policy_name` (Data) → Req → Unique
   - `notes` (Small Text) → optional
   - `default_team_user` (Link → User) → optional; new tasks of this kind are assigned to this team placeholder
   - `allowed_roles` (Table → `Task Access Policy Role`) → the roles allowed to see and work tasks of this kind
   - child DocType `Task Access Policy Role` (Is Child Table = ON) with one field: `role` (Link → Role), Req
5) Save.

### 6.2 Add the `task_access_policy` field to `Task`
Steps:
1) Open `Customize Form`.
2) Select DocType: `Task`.
3) Add a custom field:
   - Label: `Task Access Policy`
   - Fieldname: `task_access_policy`
   - Fieldtype: `Link`
   - Options: `Task Access Policy`
   - Set `Read Only` = ON (recommended)
4) Save.

Practical note:
- Your automation should set `task_access_policy` based on Task Kind.
- For smoke tests (section 7), you will set it manually.

### 6.3 Task list visibility is role-based (no User Permissions)
Visibility is controlled by each `Task Access Policy` record's `allowed_roles`: the `task_list_filtered` API returns each user the task kinds whose policy roles intersect the user's roles (System Manager and Administrator see all). A user gains visibility of a kind by holding the right Ops role, not through User Permission records.

### 6.4 Create Task Access Policy records
Recommended: create one record per Task Kind (policy name matches the Task Kind exactly).

Steps:
1) Open `Task Access Policy`.
2) Click `New`.
3) Set `policy_name` to one of the values below.
4) Save.
5) Repeat until all are created.

Create these policies:
- one record per `task_kind` option listed in section 6.0; the policy name must match the Task Kind exactly
- on each record, set `default_team_user` (the team placeholder email) and `allowed_roles`

### 6.5 Grant policy access by role
Set each policy's `allowed_roles` rows so the right Ops roles can see the kind, and give each user the appropriate Ops role(s) (section 4). Visibility follows the role.

### 6.6 Make `task_access_policy` auto-fill from Task Kind (required)
Goal:
- Do not rely on users to manually select `Task Access Policy`.
- Ensure strict visibility does not create “invisible tasks”.

Enforcement is implemented by two live Server Scripts. Do not reimplement it in one script, and never with a hardcoded kind → role map: the mapping is read from the `Task Access Policy` records at runtime.

- `Task-before-save-access-control` (Task / Before Save): completed and cancelled tasks are immutable; a change of assignee resets acceptance; completion is reserved to the accepter with no exemption for any role; edits require the accepter or a privileged user (System Manager, Ops - Directors, Administrator); task-kind role access is read from the policy's `allowed_roles`.
- `Task-before-save-policy` (Task / Before Save): assigns the policy's `default_team_user` when `custom_assigned_to` is empty, syncs `_assign` from `custom_assigned_to`, fills `task_access_policy` from `task_kind`, refuses a Task Kind with no policy record, and stamps `completed_at` on completion.

Baseline access, as set in the `allowed_roles` of the live Task Access Policy records (`deploy/test/data/task-access-policies.csv`):
- `Delivery Driver`: Delivery, Pickup Returns, Return drop-off at warehouse, Return to warehouse (aborted delivery / cancelled order)
- `Ops - Delivery`: Delivery, Pickup Returns, Return drop-off at warehouse, Return to warehouse (aborted delivery / cancelled order)
- `Ops - Inventory`: Pack / prepare items, Returns processing / verification
- `Ops - Returns`: Returns processing / verification, Returns restocking, Return Call, Pickup Returns
- `Ops - Order Accepting`: Order entry, Return Call
- `Ops - Order Creating`: Order entry
- `Ops - Accounting`: Invoice preparation / create invoice, Account Details: Entry, Account Details: Processing
- `Ops - Finance`: Debt Collection, Payment Received, Account Details: Entry, Account Details: Processing
- `Ops - Directors`: Discount Approval, Purchase Approval, Write-off Approval, Debt Closure Approval, Debt Alert, Debt Collection, Payment Received, Account Details: Entry, Account Details: Processing
- Every Ops role except Purchasing, plus `Delivery Driver`: Other, Other: Entry, Other: Processing

---

## 7) Smoke tests (do these before go-live)
### 7.1 Visibility tests
Create one open Task for each Task Kind/policy (or use existing tasks).

Test as:
- a Driver user
- an Inventory user
- a Returns user
- an Accounting user
- a Director user

Expected results:
- Each user only sees tasks in allowed Task Access Policies.
- Directors see all tasks.

### 7.2 Driver restrictions
As a Driver user:
- You can open your assigned delivery/pickup tasks.
- You can attach a photo to a pickup task.
- You cannot access `Stock Entry`.
- You cannot access `Sales Invoice`.

### 7.3 Completion restrictions (team ownership)
This test requires the server script in section 6.6.

As a non-owning team user:
- You cannot complete a task whose Task Kind requires a different team role.

Additional test (Returns team):
- Log in as the Returns user and confirm they can complete `Returns processing / verification`.

---

## 8) Operational maintenance rule
When you add a new Task Kind:
- add a new Task Access Policy (or decide which policy it belongs to)
- update which users should see it (User Permissions)
- set the new policy's `default_team_user` and `allowed_roles`; enforcement reads the policy record at runtime
