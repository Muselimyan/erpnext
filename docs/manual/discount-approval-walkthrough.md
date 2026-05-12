# Discount Approval Walkthrough

**Purpose:** Focused guide for the discount approval sub-flow that occurs whenever a Dispatch Case contains a line item with a Discount % greater than zero. This is a reference for the Order Creation team and Directors. The full dispatch flows are documented separately in `standard-sale-walkthrough.md` and `surgery-case-walkthrough.md`.

**Estimated time:** 5–15 minutes

**Use case:** A customer negotiates a lower price. The Order Creation team enters the discount on the Dispatch Case. The system blocks the case from proceeding until a Director explicitly approves or rejects the discount.

---

## Roles

| Step | Task | Role |
|---|---|---|
| 1 | Enter discount on Dispatch Case and save | `Ops - Order Creating` |
| 2 | Review and approve or reject | `Ops - Directors` |
| 3a | If approved: submit the Dispatch Case | `Ops - Order Creating` |
| 3b | If rejected: revise pricing and re-save | `Ops - Order Creating` |

---

## How the discount gate works

When a Dispatch Case is **Saved** with any Case Item row where `Discount % > 0`:
- The case status moves to **`Awaiting Approval`**
- A **Discount Approval task** is automatically created and assigned to the Directors team
- The case cannot be submitted until the Director completes the task as `Approved`

When **Discount % = 0** on all rows:
- No approval task is created
- The case can be submitted immediately after save

---

## Step 1 — Enter the discount on the Dispatch Case

**Login as:** `Ops - Order Creating`

1. Open (or create) the **Dispatch Case** as normal.
2. In the **Case Items** table, for the item(s) with a negotiated discount:
   - Fill in **Discount %** — e.g. `15` for a 15% discount
   - The **Net Price** (effective selling price) will calculate automatically
3. Click **Save**.

**✅ Expected after Save with Discount % > 0:**
- Case status = `Awaiting Approval`
- A **Discount Approval** task is auto-created (you will see a message or can find it in the Task list)
- The Submit button is disabled until approval is complete

**✅ Expected after Save with Discount % = 0:**
- No approval task created
- Case status = `Draft`
- You can submit immediately

---

## Step 2 — Director reviews and decides

**Login as:** `Ops - Directors`

1. Open the **Task** list, filter: **Task Kind = Discount Approval**, **Status = Open**.
2. Open the Discount Approval task for the relevant case.
3. Click the **Dispatch Case** link on the task to open and review:
   - Which items have a discount
   - What the discount percentage is
   - The customer and any notes from the Order team
4. Return to the task. Set **Approval Outcome**:
   - `Approved` — the discount is accepted; the case can proceed
   - `Rejected` — the discount is not accepted; pricing must be revised
5. Fill in **Approval Note** — always record why (e.g. "Approved — hospital account volume deal" or "Rejected — exceeds the 10% max policy").
6. Set Task **Status** to `Completed` and click **Save**.

---

## Step 3a — If Approved: submit the Dispatch Case

**Login as:** `Ops - Order Creating`

1. Open the **Dispatch Case** (status should now be `Draft` — the approval unlocked it).
2. Confirm the case items still look correct.
3. Click **Submit**.

**✅ Expected:**
- Case status → `Confirmed`
- Pack task auto-created for the Inventory team
- Normal dispatch flow continues (see `standard-sale-walkthrough.md` or `surgery-case-walkthrough.md`)

---

## Step 3b — If Rejected: revise pricing

**Login as:** `Ops - Order Creating`

1. Open the **Dispatch Case** — its status remains `Draft`.
2. A new **Order entry task** has been auto-created and assigned to the Order Creation Team with a note indicating the discount was rejected. Check that task for the Director's reason.
3. On the Dispatch Case, update the **Case Items** table:
   - Reduce or remove the `Discount %` as directed
   - Alternatively, adjust the `Unit Price` directly
4. Click **Save**.

**After revising:**
- If `Discount % > 0` still remains on any row → a new Discount Approval task is automatically created and the process repeats from Step 2
- If all rows now have `Discount % = 0` → no new approval task; you can submit immediately

---

## Multiple rounds of revision

There is no limit on how many times pricing can be revised and re-approved. Each save with a non-zero discount creates a fresh approval task. The Director will see only the most recent task (earlier tasks for the same case will have been superseded).

---

## What the Director sees on the Discount Approval task

The task contains:
- **Dispatch Case** link — opens the full case with all items and their discount %
- **Customer** — who the case is for
- **Description** — any notes the Order team added when creating the case
- **Approval Outcome** field — where the Director records the decision
- **Approval Note** field — where the Director explains the decision

The Director does not need to edit the Dispatch Case directly — only the task.

---

## Quick reference

```
Dispatch Case saved with Discount % > 0
  └─► Status = Awaiting Approval
  └─► Discount Approval task auto-created → assigned to Directors
        ├─► Approved
        │     └─► Case status unlocked → Order Creating submits
        │           └─► Status = Confirmed → Pack task created → normal flow
        └─► Rejected
              └─► Case stays Draft
              └─► New Order entry task auto-created → "Revise pricing"
                    └─► Order Creating adjusts Discount % or Unit Price
                          └─► Save again → repeat approval if discount still present
                          └─► Save again → submit immediately if all discounts = 0
```

---

## Common issues

| Symptom | Likely cause |
|---|---|
| Submit button disabled even after Director approved | Task was completed but `Approval Outcome` was not set before completing — Director must reopen the task, set Approval Outcome = Approved, and complete it again |
| Discount Approval task not appearing for Director | Task Access Policy for `Discount Approval` is not configured for `Ops - Directors` — check with System Manager |
| Case stays `Awaiting Approval` after approval | Server script `Task-after-save-dispatch-flow` is disabled or has an error — check Server Scripts |
| Case shows `Awaiting Approval` but discount is 0 | Case was saved with a discount earlier; after removing the discount, save again — this should move it back to `Draft` if no other approval trigger is active |
