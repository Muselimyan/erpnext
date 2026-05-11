# Doc 15 — Standard Sale Workflow: Gap Analysis *(Historical — Superseded by Doc 16)*

> **⚠️ SUPERSEDED.** This document identified the task-automation gaps in the old Sales Order–based standard sale flow (Doc 09) and the Surgery Case flow (Doc 12). All gaps described here were resolved by the deployment of the **Unified Dispatch Flow (Doc 16)**, which introduced the `Dispatch Case` DocType with a fully automated task chain covering both the no-return and return-expected paths. This document is retained for historical reference only.

---

## (What Exists vs. What Is Required)

**Date:** 2026-05-10
**Scope:** Standard sale end-to-end (Doc 09 flow) — task automation completeness vs. the stated requirement that "after order creation, teams only mark tasks as done."

---

## 1) The Stated Requirement (What You Expect)

Your intent, as described:

> 1. Order team creates a Sales Order. The system **automatically** creates:
>    - 1.1 A task for directors to approve if a manual discount is present → once approved, proceeds to 1.2.
>    - 1.2 A task for inventory team to pack the items.
> 2. Inventory team packs, marks task complete → system **automatically** creates task for delivery team.
> 3. Delivery team picks and delivers. Marks task complete.
>
> The only things people do after step 1 are: mark a task as completed (or working in between). All logistics happen via tasks. No one has to manually create tasks for others.

---

## 2) How to Read This Document

Each section below states:
- **Designed** — what the requirements (Doc 09, Doc 10) say must happen
- **Deployed** — what the server scripts / deploy scripts actually do (verified from `deploy/schema/server-scripts.json`, `deploy/doc09a-deploy.ps1`, `deploy/doc12a-deploy.ps1`, `deploy/doc10a-deploy.ps1`)
- **Gap** — the difference

---

## 3) Standard Sale — Detailed Step-by-Step Status

### Step 1 — Order team creates Sales Order

| Sub-step | Designed | Deployed | Status |
|---|---|---|---|
| SO created with items, customer, optional hospital/doctor | Yes | Yes — form fields exist (`hospital`, `doctor_name`, etc.) | ✓ |
| If line discount or manual rate override exists → auto-create Discount Approval task for directors | Yes | Yes — `Sales Order-before-save-discount-approval` script (enabled) | ✓ |
| If discount → dispatch is blocked until task is Approved | Yes | Yes — `Stock Entry-before-submit-dispatch-gate` checks `discount_approval_status` | ✓ |
| Director marks Discount Approval task as Completed → outcome written back to SO | Yes | Yes — `Task-before-save-discount-approval-writeback` script (enabled) | ✓ |
| If no discount → no approval task needed, SO is ready immediately | Yes | Yes — script sets status to `Not Required` | ✓ |
| **After approval (or no discount): system auto-creates "Pack / prepare items" task for inventory team** | **Yes** | **NO — nothing is created. No script does this.** | **❌ MISSING** |

**Summary of Step 1:**
The discount approval lane is fully implemented and works. The automatic handoff to inventory (Pack task creation) does **not** exist. After an SO is saved — whether it needs approval or not — the inventory team receives no automatic task. Someone must manually create it.

---

### Step 2 — Inventory team packs the items

| Sub-step | Designed | Deployed | Status |
|---|---|---|---|
| Inventory team receives a "Pack / prepare items" task linked to the SO | Yes | NO — task must be created manually | ❌ MISSING |
| Inventory team marks Pack task as Completed | Yes | Yes — task governance script enforces only `Ops - Inventory` can complete `Pack / prepare items` tasks | ✓ (governance exists, task creation is missing) |
| When Pack task is Completed → system auto-creates "Delivery" task for delivery team | Yes | **NO — nothing is triggered.** | ❌ MISSING |

---

### Step 3 — Dispatch hand-off (coordinator + driver)

| Sub-step | Designed | Deployed | Status |
|---|---|---|---|
| Delivery task must exist and be linked to the SO before staging stock | Yes | Yes — `Stock Entry-before-submit-dispatch-gate` blocks staging if no Delivery task exists for the SO | ✓ (gate exists) |
| Delivery task is **auto-created** for the driver | Yes | **NO — must be created manually by coordinator** | ❌ MISSING |
| Driver attaches Warehouse Pickup Photo to the Delivery task | Yes | Yes — `Task-before-save-policy` blocks completing a `Delivery` task without `warehouse_pickup_photo` | ✓ |
| Stock staging (Main → Delivery In-Transit) blocked if Delivery task has no photo | Yes | Yes — `Stock Entry-before-submit-dispatch-gate` checks this | ✓ |
| Stock staging blocked if no SO link | Yes | Yes | ✓ |
| Stock staging blocked if discount not approved | Yes | Yes | ✓ |
| Stock staging blocked if prepaid conditions not met | Yes | Yes | ✓ |
| Standard sales cannot stage into client location warehouses (Clients - Inmed) | Yes | Yes — `Stock Entry-before-save-no-client-wh` (enabled) | ✓ |
| FEFO warning when selecting a fresher batch while older-expiry batch is available | Yes | Yes — `StockEntry-before-submit-fefo` (enabled) | ✓ |

---

### Step 4 — Delivery (driver delivers)

| Sub-step | Designed | Deployed | Status |
|---|---|---|---|
| Driver marks Delivery task as Completed | Yes | Yes — task governance enforces correct team + photo requirement | ✓ |
| Driver records a handover note on the task | Yes | Yes — `driver_handover_note` field exists on Task | ✓ |
| Delivery Note issued from `Delivery In-Transit - Inmed` | Yes | Yes — `Delivery Note-before-submit-delivery-gate` blocks any other source warehouse | ✓ |
| Delivery Note blocked if discount not approved | Yes | Yes | ✓ |
| Delivery Note blocked if prepaid not confirmed | Yes | Yes | ✓ |
| After Delivery task Completed → system auto-creates next task (none required here for standard sale) | N/A | N/A | — |

---

### Step 5 — Sales Invoice (accounting)

| Sub-step | Designed | Deployed | Status |
|---|---|---|---|
| Accounting team creates Sales Invoice after delivery | Yes | Yes — permissions exist for `Ops - Accounting` | ✓ |
| Invoice must not re-price (must use SO prices) | Yes | ERPNext native behavior | ✓ |
| Invoice must not use `Update Stock` | Yes | `Purchase Invoice-before-submit-no-update-stock` blocks this on purchase side; no equivalent script on sales side (but `Update Stock` is normally off for Sales Invoice) | ⚠️ no explicit server-side block on Sales Invoice |

---

### Step 6 — Payment and escalation

| Sub-step | Designed | Deployed | Status |
|---|---|---|---|
| Payment Entry submitted → auto-create "Distribute Payment" task for directors | Yes | Yes — `Payment Entry-after-submit-distribute-payment` (enabled) | ✓ |
| Hourly scheduler: if client debt > threshold → auto-create/update "Debt Collection" task for directors | Yes | Yes — `Scheduled-debt-collection` (enabled, runs hourly) | ✓ |
| Debt collection fires only if `debt_threshold_amd > 0` on Customer | Yes | Yes — script skips customers with threshold = 0 | ✓ |

---

### Cancelled delivery (goods in transit, order cancelled)

| Sub-step | Designed | Deployed | Status |
|---|---|---|---|
| Return drop-off photo required to complete "Return drop-off at warehouse" task | Yes | **Partially.** `Task-before-save-return-dropoff-photo` script is **DISABLED** (`disabled: 1`). However, the replacement `Task-before-save-policy` script (from Doc 10A) DOES enforce the photo requirement (lines that check `task_kind == "Return drop-off at warehouse"` and `warehouse_dropoff_photo`). Net result: enforcement is **active** via the policy script. | ✓ (via policy script) |

---

## 4) Surgery Case — Status for Comparison

Since the user mentioned "complete standard sale" specifically, here is a brief comparison showing what the Surgery Case flow actually has that standard sales lacks.

| Automation | Surgery Case | Standard Sale |
|---|---|---|
| Auto-create Discount Approval task | N/A (surgery cases don't have SO discounts in the case flow) | ✓ |
| Auto-create Pack task when case moves to Preparing | ❌ Missing | ❌ Missing |
| Set delivery_person on case → auto-create Delivery task | ✓ (`Surgery-Case-before-save` script) | ❌ Missing |
| Draft dispatch Stock Entry auto-created on → Dispatch Picking | ✓ | ❌ Not applicable (manual SE) |
| Gate: dispatch SE must be submitted before → Dispatched | ✓ | Partial (staging gate exists, but no state machine) |
| Gate: Delivery task must be Completed before → Delivered | ✓ | ✓ (gate on Stock Entry dispatch) |
| Delivery Stock Entry auto-submitted on → Delivered | ✓ | ❌ Not applicable (manual Delivery Note) |
| Set return_pickup_delivery_person → auto-create return tasks | ✓ | ❌ Missing |
| Auto-create return Stock Entries on → Returns Verification | ✓ | ❌ Not applicable (no return flow for standard sales) |
| Usage computed + Consumption SE auto-submitted on → Usage Derived | ✓ | N/A |
| Draft Sales Invoice auto-created on → Invoiced | ✓ | ❌ Not applicable (Accounting creates manually) |
| Hourly debt collection scheduler | ✓ | ✓ (shared) |
| Distribute Payment task on payment submit | ✓ | ✓ (shared) |

**Key observation:** Surgery Case has a full state machine with server-side automation at each transition. Standard Sale has **gates** (things you cannot do without prerequisites) but **zero task-creation automation**. The two flows are architecturally asymmetric.

---

## 5) The Two Critical Gaps for Standard Sale

### Gap 1 — No "Pack / prepare items" task auto-created after SO is ready

**Design intent:** When an SO is submitted (and discount is either not required or approved), the inventory team should automatically receive a Pack task.

**Current reality:** Nothing is created. The inventory team has no automatic signal. Someone (order team? coordinator?) must manually navigate to the Task list and create the Pack task.

**Impact:** The entire "tasks flow automatically" model breaks at step 1.2. The ordering team finishes creating the SO and the process stalls until someone manually creates a Pack task.

**What is needed:**
- A server script on `Sales Order` — `After Submit` (or `Before Save` when status changes to `Submitted`) — that:
  - Creates a `Pack / prepare items` task
  - Links it to the SO and Customer
  - Assigns it to a user in `Ops - Inventory` (either first available, or a configurable default, or leaves it open for coordinator to assign)
  - Sets `task_kind = "Pack / prepare items"`, `task_access_policy = "Pack / prepare items"`
  - Is idempotent (does not create a second task if one already exists for this SO)
- If discount approval is still pending at SO submission, the Pack task should either:
  - Not be created yet (created only after approval is granted), or
  - Be created but marked with a note that it cannot start until discount is approved

### Gap 2 — No "Delivery" task auto-created for driver

**Design intent:** After packing is complete, the delivery team should receive a Delivery task automatically.

**Current reality:**
- The dispatch staging gate (`Stock Entry-before-submit-dispatch-gate`) requires a Delivery task to exist with a warehouse pickup photo — **but no script creates it**.
- A coordinator must manually create the Delivery task, assign it to a driver, and the driver must attach the photo. Only then can staging proceed.

**Impact:** There is a hard dependency (dispatch gate requires the task) but zero automation to create the required prerequisite. This creates confusion: staging fails with an error ("Delivery Task is missing"), but the system never told anyone to create one.

**What is needed:**
- A server script on `Task` — `Before Save` — that:
  - When a `Pack / prepare items` task for a given SO transitions to `Completed`:
    - Automatically creates a `Delivery` task linked to the same SO
    - Assigns it to a user in `Ops - Delivery` (or `Delivery Driver`) — either a configurable default or leaves it unassigned for coordinator to fill
    - Sets `task_kind = "Delivery"`, `task_access_policy = "Delivery"`
    - Is idempotent

Alternatively: the coordinator can set a "Delivery Person" field on the SO and that triggers the Delivery task creation (same pattern as Surgery Case uses `delivery_person` field). This is simpler to implement and keeps the "person assignment" human but makes task creation automatic.

---

## 6) Other Observations

### 6.1 Warehouse naming
The deployed server scripts use suffix `- Inmed` (e.g., `Main - Inmed`, `Delivery In-Transit - Inmed`, `Clients - Inmed`) while the requirement docs (Doc 05, Doc 09) use suffix `- WH`. This is consistent throughout the deployed code and is not a bug — just note that the actual ERPNext warehouse names include `Inmed`.

### 6.2 `Sales Invoice update_stock` — no explicit block
Doc 09 policy: stock must move through Stock Entry / Delivery Note, never through an invoice. The purchase side has an explicit script (`Purchase Invoice-before-submit-no-update-stock`) enforcing this. The sales side does not have an equivalent. Low risk (ERPNext default is `update_stock = 0` on Sales Invoice), but the architecture is asymmetric.

### 6.3 `debt_threshold_amd` is currently 0 on all 146 customers
Per `go-live-action-plan.md` section 2.2, all customer debt thresholds are `0`. The scheduler only fires for customers where `threshold > 0`. Until thresholds are set, **no debt escalation tasks will ever be created**.

### 6.4 `Standard Selling` price list must be populated
Per `go-live-action-plan.md` section 3.2, the price list is not yet populated. The discount approval script checks `price_list_rate` — if it is `0` for all items, the `is_manual_rate_override` function will never trigger (the script correctly skips items with `price_list_rate <= 0`). But SO creation will have blank prices, which must be fixed before any real transaction.

### 6.5 Return drop-off photo enforcement
The standalone script `Task-before-save-return-dropoff-photo` is **disabled**. The enforcement is now inside `Task-before-save-policy` (the Doc 10A unified governance script). Net result: enforcement is active. The disabled script is just a leftover artifact from before Doc 10A consolidated everything.

---

## 7) What Needs to Be Built to Match the Stated Requirement

Ordered by priority:

| # | What | Where | Complexity |
|---|---|---|---|
| 1 | Auto-create `Pack / prepare items` task when SO is submitted (and discount either not required or approved) | New server script on `Sales Order`, `After Submit` | Low |
| 2 | When Pack task is `Completed` → auto-create `Delivery` task (or: add a `Delivery Person` field on SO → coordinator sets it → task is auto-created) | New server script on `Task`, `Before Save` | Low–Medium |
| 3 | Populate `Standard Selling` price list before any real transactions | Master data setup | Low (data entry) |
| 4 | Set `debt_threshold_amd` on all 146 active customers | Master data setup | Low (data entry) |
| 5 | Decide: does SO submission block if discount is still Pending? Or is Pack task created with a "wait for approval" note? | Policy decision → then implement | N/A |

---

## 8) Current State Summary

### Standard Sale — what works today

- Discount Approval task auto-created and wired to dispatch gates ✓
- All dispatch gates enforced (no photo, no staging; no approved discount, no staging; no SO link, no staging; prepaid gate) ✓
- Delivery Note source warehouse enforced ✓
- Client warehouse blocked for standard sales ✓
- FEFO warning on batch selection ✓
- Hourly debt collection escalation (once thresholds are set) ✓
- Distribute Payment task on every customer payment receipt ✓
- Task governance (ownership, completion rights, mandatory photos) ✓

### Standard Sale — what does NOT work today

- ❌ No Pack task auto-created after SO is ready
- ❌ No Delivery task auto-created after packing (coordinator must create manually)
- ❌ `debt_threshold_amd = 0` on all customers → debt escalation never fires
- ❌ `Standard Selling` price list is empty → orders have blank prices

### Net verdict for go-live checklist point 3 (run a complete standard sale)

You can run a standard sale today **only if you manually create the Pack and Delivery tasks**. The gates and gates enforcement are all in place. The automated task chain — the core of your "staff only mark tasks, system creates the next ones" model — is **not yet implemented for standard sales**.

The Surgery Case flow is much further along: it has a state machine and auto-creates stock entries and tasks at most transitions. Standard sales needs the same concept applied to the SO-based flow.
