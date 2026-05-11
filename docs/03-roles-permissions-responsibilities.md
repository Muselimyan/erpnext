# Doc 03 — Roles, Permissions, and Team Responsibilities (Operational)

## 1) Purpose
This document defines:
- Which team does which work
- Which team owns which Task Kinds
- Who is allowed to see which tasks (via Task Access Policies)
- Separation of duties rules (especially: drivers do not post stock)

Goals:
- Make responsibilities explicit so work does not fall between teams.
- Prevent wrong-team edits/completions.
- Keep the system safe (auditability, recalls, accountability).

Non-goals:
- This doc does not describe ERPNext configuration steps.
- Implementation details are in the implementation docs (Doc 10A, Doc 12A, etc.).

---

## 2) Teams (high-level)
These are the core teams used throughout the docs:

- **Order Accepting / Order Entry Team**
  - Receives requests (phone/WhatsApp/email) and enters them into ERPNext.

- **Inventory / Preparing Team**
  - Packs the requested items/sets in the warehouse.

- **Delivery Team**
  - Dispatch coordination, delivery execution, pickup execution.
  - Includes:
    - drivers (field execution)
    - dispatch coordinators (assignment + operational control)

- **Returns Team**
  - Receives returned packages at the warehouse.
  - Counts/validates returned quantities.
  - Ensures serial/batch accountability.

- **Accounting Team**
  - Creates and submits invoices.
  - Tracks receivables.

- **Directors**
  - Approvals (discounts, purchasing, write-offs).
  - Escalations (debt collection).

---

## 3) Core separation-of-duties rules (must follow)
These rules exist to prevent mistakes and protect auditability.

- **Drivers must not post stock**
  - Drivers only interact with Tasks (and attachments).
  - Drivers do not create/submit Stock Entries.

- **Returns Team is the authoritative “counting” step**
  - In the per-surgery case workflow (Doc 12), used vs returned is determined by warehouse counting on return.
  - If a client does not provide usage quantities, operations still work correctly.

Permanent on-site sets note:
- For client locations with permanent on-site sets (Doc 11), there may be no returns counting step.
- In that model, usage is identified from the replenishment request/order (client orders what was used/missing).

- **Serial/batch accountability is warehouse-owned**
  - For tracked items, the stock ledger is the source of truth.
  - Warehouse staff must ensure serial/batch selection is correct.

- **Accounting owns invoicing**
  - Operations does not “finish” the financial step.

- **Directors own approvals and escalations**
  - Do not spread approvals across many roles.

---

## 4) Role definitions (what each role does)
This section is written for novices: if you hire someone and give them a role, this is what they are responsible for.

### 4.1 Delivery Driver
Purpose:
- Execute deliveries and return pickups.

Can do:
- See assigned delivery/pickup tasks.
- Attach photos to tasks when required (warehouse pickup and warehouse drop-off).
- Complete driver-friendly tasks.

Must not do:
- Stock Entry work
- Accounting work
- Editing tasks owned by other teams

### 4.2 Delivery Coordinator (Dispatch Coordinator)
Purpose:
- Make sure deliveries/pickups happen on time.
- Assign drivers to tasks.

Can do:
- Assign/reassign driver tasks.
- Monitor queues (what is open, overdue, stuck).
- Move workflow steps only after required tasks are completed.

### 4.3 Inventory / Preparing Worker
Purpose:
- Pack and prepare items/sets so they are ready for dispatch.

Can do:
- Complete packing tasks.
- Ensure packed items match what is planned for dispatch.

### 4.4 Returns Worker
Purpose:
- Receive and validate returned items.

Can do:
- Enter returned quantities.
- Validate serial/batch returns.
- Ensure discrepancies (missing/damaged) are recorded and escalated.

Permanent on-site sets note:
- This role may be less involved for client locations that do not do returns.
- However, the same team (or an inventory owner) still owns traceability controls when posting usage/consumption for company-owned stock at client locations.

### 4.5 Accounting
Purpose:
- Invoice used quantities and manage receivables.

Can do:
- Create and submit invoices.
- Trigger and close invoice-related tasks.
- Maintain the Price Override List (negotiated/special client prices) according to governance policy.

### 4.6 Finance Team
Purpose:
- Record incoming payments; manage debt collection per customer.

Can do:
- Record payments on Debt Collection tasks (triggers Payment Entry auto-creation).
- Complete Distribute Payment and Payment Received tasks.
- View Sales Invoices (read).

### 4.7 Order Creating Team
Purpose:
- Create and submit Dispatch Cases from Order entry tasks.

Can do:
- Create and submit Dispatch Case records.
- Complete Order entry tasks.

### 4.8 Directors
Purpose:
- Approvals and escalations.

Can do:
- Approve / reject with notes.
- Monitor debt-collection escalations (Finance team owns task completion; Directors review board).
- Approve special pricing/price override changes when required by policy.

---

## 5) Task ownership model (Task Kind → owning team)
Doc 10 defines “always tasks”: every operational stage must have a Task.

Owning team means:
- Only the owning team may edit the task (except Directors/Coordinators).
- Only the owning team may complete the task.

Task Kind ownership (baseline):
- `Order entry`
  - Owner: Order Accepting team
- `Pack / prepare items`
  - Owner: Inventory / Preparing team
- `Dispatch picking / hand-off`
  - Owner: Delivery team (coordinator)
  - Operational note: the physical picking is done by Inventory; the dispatch checkpoint exists to ensure the dispatch Stock Entry is submitted with correct serials/batches before the delivery trip proceeds.
- `Delivery`
  - Owner: Delivery team (driver completes)
- `Pickup Returns`
  - Owner: Delivery team (driver completes)
- `Return drop-off at warehouse`
  - Owner: Delivery team (driver completes)
- `Returns processing / verification`
  - Owner: Returns / Inventory team
- `Invoice preparation / create invoice`
  - Owner: Accounting
- `Returns restocking`
  - Owner: Returns / Inventory team
- `Debt Collection`
  - Owner: Finance Team (`Ops - Finance`)
- `Distribute Payment`
  - Owner: Finance Team (`Ops - Finance`)
- `Payment Received`
  - Owner: Finance Team (`Ops - Finance`)
- `Discount Approval`, `Purchase Approval`, `Write-off Approval`
  - Owner: Directors

---

## 6) Task visibility model (Task Access Policies)
Doc 10 requires:
- Each Task Kind is assigned a **Task Access Policy**.
- Each worker is granted access to one or more policies.

Operational intent:
- Visibility is controlled by policy.
- Edit/complete is controlled by owning team.

### 6.1 Recommended baseline policy set
Recommended: create one Task Access Policy per Task Kind:
- `Order entry`
- `Pack / prepare items`
- `Dispatch picking / hand-off`
- `Delivery`
- `Pickup Returns`
- `Return drop-off at warehouse`
- `Returns processing / verification`
- `Invoice preparation / create invoice`
- `Returns restocking`
- `Debt Collection`
- `Distribute Payment`
- `Payment Received`
- `Discount Approval`
- `Purchase Approval`
- `Write-off Approval`

### 6.2 Who can see what (recommended baseline)
This is the default recommendation to match your examples:

- **Delivery Driver** can see:
  - `Delivery`
  - `Pickup Returns`
  - `Return drop-off at warehouse`
  - `Pack / prepare items` (optional, if you want drivers to see packing status)

- **Delivery Coordinator** can see:
  - all Delivery-related policies
  - `Pack / prepare items` and `Dispatch picking / hand-off` (to coordinate handoff)

- **Inventory / Preparing Team** can see:
  - `Pack / prepare items`
  - `Dispatch picking / hand-off`
  - `Returns processing / verification`

- **Returns Team** can see:
  - `Returns processing / verification`
  - `Pickup Returns` and `Return drop-off at warehouse` (to know what is expected to arrive)

- **Accounting** can see:
  - `Invoice preparation / create invoice`
  - optionally `Returns processing / verification` (to understand timing dependencies)

- **Finance Team** can see:
  - `Debt Collection`
  - `Distribute Payment`
  - `Payment Received`
  - `Invoice preparation / create invoice` (to understand invoice status for payment)

- **Directors** can see:
  - everything

Rule:
- If a user can see a task but is not the owning team, they treat it as read-only.

---

## 7) Dispatch Case workflow ownership (Doc 16 alignment)

**The Surgery Case workflow (Doc 12) has been replaced by the Dispatch Case workflow (Doc 16). For current role ownership by workflow stage, see Doc 16 §11 (what each role sees daily) and Doc 16 §12 (Task kind → owning team).**

Summary of stage ownership:
- Create case → Order Creating Team (`Ops - Order Creating`)
- Pack / prepare → Inventory Team
- Deliver → Delivery Team (driver completes)
- Returns → Delivery Team (driver), then Returns Team (verification)
- Invoice → Accounting Team
- Debt collection / payment → Finance Team
- Approvals (discount / write-off / purchase) → Directors

---

## 8) Reassignment and override rules
- Reassigning tasks across people is allowed, but it must be explicit and traceable.
- Task owner reassignment must be possible (operational reality).
- Who is allowed to reassign tasks is a policy decision (decide later).
- Completed tasks should not be edited except for explicit corrections by Directors/Coordinators.

---

## 9) Acceptance criteria
- Every operational step has an explicit owner (team + person).
- Drivers only do driver-friendly work (Tasks + attachments).
- Returns Team is the authoritative step for returns counting and serial/batch validation.
- Directors can monitor the entire operation without opening access too broadly for everyone else.
