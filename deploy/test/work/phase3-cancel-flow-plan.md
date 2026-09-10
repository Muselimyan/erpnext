# Phase 3 — Dispatch Case Cancel Flow — Detailed Plan

**Created:** 2026-09-09
**Status:** Design review needed — open questions marked with ❓
**Prerequisite:** Phase 2 fully deployed (done 2026-09-09)
**Related docs:**
- `docs/16-unified-dispatch-flow.md` — no cancel section exists yet
- `deploy/test/work/dispatch-flow-redesign-v4-implementation-status.md` — Phase 3 listed as not started

---

## 1. Problem Statement

Currently there is no way to cancel a Dispatch Case after it has been created. If an order is entered incorrectly, the customer cancels, or items are unavailable, operators have no structured workflow to:

1. Stop the dispatch process
2. Reverse any stock movements that already happened
3. Clean up downstream tasks (Pack, Delivery, etc.)
4. Record why the cancellation occurred

The only workaround today is manual intervention by administrators.

---

## 2. Current State Audit (2026-09-09)

### What already exists

| Item | State | Location |
|---|---|---|
| `Dispatch Cancel Restock` in TFV_DISPATCH_FLOW_KINDS | Present | `Task-Field-Visibility.js` line 156 |
| `Cancelled` status checks in server scripts | Present (filter exclusions) | `Task-after-save-dispatch-flow.py`, `dispatch_task_accept.py`, etc. |
| `Cancelled` status checks in client scripts | Present (button hiding) | `Task-Action Buttons.js` lines 339, 399, 408 |
| `Cancelled` in Telegram notification map | Present | `Telegram Task Status Update.py` line 16, 43 |
| `Return to warehouse (aborted delivery / cancelled order)` task kind | Present | `task_kind` options + Task Access Policy |

### What does NOT exist

| Item | Notes |
|---|---|
| `Cancelled` in Dispatch Case `status` options | Currently 14 states: Draft through Closed. No Cancelled. |
| `Dispatch Cancel Restock` in `task_kind` options | 25 kinds listed, none cancel-related |
| Task Access Policy for `Dispatch Cancel Restock` | 26 policies exist, none for cancel |
| Cancel API script (`dispatch_case_cancel.py`) | Not created |
| Cancel button on any Task/DC form | Not added |
| Cancel flow handler in `Task-after-save-dispatch-flow.py` | Not present |
| DC cancel fields | No `cancellation_reason`, `cancelled_by`, `cancelled_at`, `cancel_restock_stock_entry` |
| Doc 16 cancel section | No design documentation |

---

## 3. Design Decisions Required

### ❓ Q1: Who can trigger cancellation?

Options:
- **A)** Only Directors / Administrators
- **B)** The user who accepted the current active task (Order Entry, Pack, etc.)
- **C)** Any user with the originating role (e.g., Order Accepting can cancel during Order Entry phase)
- **D)** Role-based per state (e.g., Order roles can cancel in Draft/Confirmed, only Directors after Packed)

**Recommendation:** Option D — the further along the flow, the more authority needed.

| DC State | Who can cancel |
|---|---|
| Draft, Awaiting Approval | Accepted user on active task, or Directors |
| Confirmed, Packed | Directors only (items may be physically prepared) |
| In Transit or later | Directors only (items physically moved) |
| Delivered or later | Cannot cancel (use return flow instead) |
| Closed | Cannot cancel |

### ❓ Q2: From which states can a DC be cancelled?

Options:
- **A)** Only `Draft` (before submission) — simplest, no stock reversal needed
- **B)** `Draft` + `Awaiting Approval` + `Confirmed` — pre-packing only
- **C)** Up through `Packed` — requires reversing dispatch SE
- **D)** Up through `In Transit` — requires reversing dispatch + delivery SEs
- **E)** Up through `Delivered` — overlaps with return flow

**Recommendation:** Option C or D. After `Delivered`, the return flow already handles this. The boundary depends on whether you want to support "driver turn around" scenarios.

### ❓ Q3: What happens to active tasks when DC is cancelled?

Options:
- **A)** Auto-cancel all open tasks linked to this DC (set status = Cancelled)
- **B)** Auto-cancel open tasks + create a "Dispatch Cancel Restock" task if stock was moved
- **C)** Leave tasks open but show a banner; require manual cancellation

**Recommendation:** Option B — cleanest. The cancel script auto-cancels open tasks and creates a restock task only when stock reversal is needed.

### ❓ Q4: Stock reversal approach

When cancelling a DC that has already moved stock:

| DC State at Cancel | Stock Entries to Reverse | Restock Task? |
|---|---|---|
| Draft / Awaiting Approval | None (no SE exists) | No |
| Confirmed | None (Pack not done yet) | No |
| Packed | Reverse: Main WH ← Delivery In-Transit | Yes |
| In Transit | Reverse: Main WH ← Delivery In-Transit (driver returns box) | Yes |

**Option A — Auto-create reversal SEs:**
The cancel script creates and submits Material Transfer SEs to move items back. A `Dispatch Cancel Restock` task is created for Inventory team to physically receive and shelve the returned items.

**Option B — Manual reversal via task:**
The cancel script only creates the `Dispatch Cancel Restock` task. The Inventory team creates the reversal SE when they physically receive items back.

**Recommendation:** Option A for Packed (items haven't left the building — auto-reverse is safe). Option B for In Transit (items are with the driver — need physical confirmation before reversing stock).

### ❓ Q5: Invoice / Payment handling on cancel

| Scenario | What happens |
|---|---|
| No invoice exists | Nothing to do |
| Draft invoice exists | Auto-cancel the draft SI |
| Submitted invoice exists | ❓ Auto-cancel SI? Or leave for manual? |
| Payments received against invoice | ❓ This is complex — credit notes, refunds, etc. |

**Recommendation:** For the initial implementation, only allow cancellation before an invoice is submitted (states up to `Packed` / `In Transit`). If an invoice exists and is submitted, block cancellation and require the return flow instead. This avoids the credit note / refund complexity.

### ❓ Q6: Cancel from Task or Dispatch Case form?

**Option A — Task form button:**
A "Cancel Dispatch" button appears on the active task (Order Entry, Pack, etc.) for authorized users. This fits the Task-first principle. The button calls the cancel API.

**Option B — Dispatch Case form button:**
A "Cancel" button on the DC form itself. More natural for Directors who may browse DCs directly.

**Option C — Both:**
Button on both forms, same API behind them.

**Recommendation:** Option C. Directors often browse DCs directly. The Task button is convenient for the accepted user.

### ❓ Q7: Cancellation reason

- **Required or optional?** Recommendation: Required. Important for audit trail.
- **Free text or select list?** Recommendation: Select + free text. Common reasons as options (Customer cancelled, Items unavailable, Duplicate order, Error in order, Other) plus a free-text notes field.

---

## 4. Proposed Implementation (pending design approval)

The implementation below assumes the recommended answers to each design question. Adjust after review.

### 4.1 Schema Changes

#### A. Add `Cancelled` to DC status options

Current options (14):
```
Draft\nAwaiting Approval\nConfirmed\nPacked\nIn Transit\nDelivered\nAwaiting Return Pickup\nReturn Pickup Scheduled\nReturn In Transit\nReturns Received\nInvoice Pending\nInvoiced\nPayment Pending\nClosed
```

New options (15) — add `Cancelled` at the end:
```
Draft\nAwaiting Approval\nConfirmed\nPacked\nIn Transit\nDelivered\nAwaiting Return Pickup\nReturn Pickup Scheduled\nReturn In Transit\nReturns Received\nInvoice Pending\nInvoiced\nPayment Pending\nClosed\nCancelled
```

#### B. Add `Dispatch Cancel Restock` to task_kind options

Add `Dispatch Cancel Restock` to the Select options on `Task.task_kind`.

#### C. New custom fields on Dispatch Case

| Field | Type | Insert After | Notes |
|---|---|---|---|
| `cancellation_reason` | Select | `status` | Options: `Customer cancelled\nItems unavailable\nDuplicate order\nError in order\nOther` |
| `cancellation_notes` | Small Text | `cancellation_reason` | Free-text details |
| `cancelled_by` | Data | `cancellation_notes` | User who triggered cancel |
| `cancelled_at` | Datetime | `cancelled_by` | When cancel occurred |
| `cancel_restock_stock_entry` | Link → Stock Entry | `cancelled_at` | Reversal SE (if any) |

All fields should have `hidden: 1` by default, revealed conditionally (only when DC status = Cancelled, or via a DC-side client script).

#### D. New Task Access Policy

| Policy Name | Default Team User | Allowed Roles |
|---|---|---|
| `Dispatch Cancel Restock` | `inventory.team@example.com` | `Ops - Inventory` |

### 4.2 Server Scripts

#### A. Cancel API: `dispatch_case_cancel.py`

**Type:** API (`frappe.whitelist`)
**Called by:** Task form button or DC form button

**Parameters:**
- `dispatch_case` (required) — the DC name
- `reason` (required) — cancellation reason (Select value)
- `notes` (optional) — free-text notes

**Logic:**

```
1. Load the Dispatch Case
2. Validate:
   a. DC exists and is not already Cancelled or Closed
   b. DC status is in the allowed-cancel states (Draft, Awaiting Approval, Confirmed, Packed, In Transit)
   c. No submitted Sales Invoice exists for this DC
   d. Current user has permission (role-based per Q1 decision)
3. Record cancellation:
   a. Set DC.cancellation_reason = reason
   b. Set DC.cancellation_notes = notes
   c. Set DC.cancelled_by = frappe.session.user
   d. Set DC.cancelled_at = now()
4. Stock reversal (if DC is Packed or In Transit):
   a. Read the dispatch_stock_entry items
   b. Create a Material Transfer SE: Delivery In-Transit → Main WH
   c. Submit the SE
   d. Set DC.cancel_restock_stock_entry = new SE name
5. Cancel open tasks:
   a. Find all Tasks where dispatch_case = this DC and status not in (Completed, Cancelled)
   b. Set each task.status = "Cancelled" and save
6. Cancel draft documents:
   a. If DC has a draft Sales Invoice → cancel it
   b. If DC has draft Payment Entries → cancel them
7. Set DC.status = "Cancelled"
8. Save the DC (with flags.ignore_permissions if needed for docstatus handling)
9. Create restock task (if stock was reversed):
   a. Create Task with task_kind = "Dispatch Cancel Restock"
   b. Set dispatch_case, customer, subject
   c. Assign to Inventory team (from Task Access Policy)
10. Return success with summary
```

**RestrictedPython notes:**
- No imports needed — all `frappe.*` calls
- No sibling function calls — all logic must be inline or nested
- No underscore-prefixed variables

#### B. Update `Task-before-save-dispatch-gates.py`

Add a gate: if a task's linked DC is Cancelled, block completion with a clear error message.

```python
# Near the top of the dispatch gates, after loading DC:
if dc_doc.status == "Cancelled":
    frappe.throw("This Dispatch Case has been cancelled. Task cannot be completed.")
```

#### C. Update `Task-after-save-dispatch-flow.py` (optional)

If `Dispatch Cancel Restock` tasks need completion handling (e.g., confirming items were physically reshelved), add a handler:

```python
if doc.task_kind == "Dispatch Cancel Restock" and doc.status == "Completed":
    # Optionally: create the reversal SE here instead of in the cancel API
    # Or: just log completion, no further action needed
    pass
```

Whether the restock task completion does anything depends on Q4 (auto vs manual reversal).

### 4.3 Client Scripts

#### A. Cancel button on Task form — `Task-Action Buttons.js`

Add a "Cancel Dispatch" button for tasks linked to a DC, visible when:
- Task has a `dispatch_case`
- DC status is in cancellable states
- User has appropriate role
- Task is not already Completed or Cancelled

```javascript
// In tab_render_desktop_buttons and tab_render_bottom_actions:
if (frm.doc.dispatch_case && !isCompleted && !isCancelled) {
    // Check DC status via frappe.xcall or cached value
    // Show "Cancel Dispatch" button (red/danger color)
    // On click: show dialog with reason select + notes textarea
    // Call dispatch_case_cancel API
    // On success: reload
}
```

**UX flow:**
1. User clicks "Cancel Dispatch" button
2. Dialog appears with:
   - Reason dropdown (required): Customer cancelled / Items unavailable / Duplicate / Error / Other
   - Notes textarea (optional)
   - Confirm / Cancel buttons
3. On confirm: calls API, shows freeze message "Cancelling dispatch..."
4. On success: reloads task (which will now show as Cancelled)

#### B. Cancel button on DC form (optional) — new or extend `Dispatch Case-Form.js`

For Directors browsing DCs directly:

```javascript
// In Dispatch Case-Form.js refresh:
if (frm.doc.status !== "Cancelled" && frm.doc.status !== "Closed") {
    // Check user role
    // Add "Cancel Dispatch" button to header
    // Same dialog + API call as Task button
}
```

#### C. TFV updates — `Task-Field-Visibility.js`

Already has `Dispatch Cancel Restock` in `TFV_DISPATCH_FLOW_KINDS`. May need:
- Add cancel-specific fields to `TFV_KIND_MAP` if any are visible on the restock task
- No changes needed if the restock task only shows dispatch_case + customer + description (already covered by `__dispatch_or_value__` rules)

### 4.4 Deploy Script: `deploy-phase3-cancel-flow.ps1`

Steps:
1. Add `Cancelled` to DC `status` field options
2. Add `Dispatch Cancel Restock` to `task_kind` options
3. Create 5 new DC custom fields (cancellation_reason, cancellation_notes, cancelled_by, cancelled_at, cancel_restock_stock_entry)
4. Create Task Access Policy for `Dispatch Cancel Restock`
5. Push `dispatch_case_cancel.py` server script
6. Push updated `Task-before-save-dispatch-gates.py`
7. Push updated `Task-Action Buttons.js`
8. Push updated `Dispatch Case-Form.js` (if DC button added)
9. Clear cache

---

## 5. Implementation Order

| Step | What | Dependencies | Estimate |
|---|---|---|---|
| 1 | Resolve design questions (Q1–Q7) | User review | — |
| 2 | Write Doc 16 cancel section | Design decisions | Quick |
| 3 | Schema: DC status + task_kind + fields + policy | Design decisions | Quick |
| 4 | Server: `dispatch_case_cancel.py` | Schema deployed | Medium — main logic |
| 5 | Server: Update gates to check DC Cancelled | Cancel API working | Quick |
| 6 | Client: Cancel button on Task form | Cancel API working | Medium — dialog UX |
| 7 | Client: Cancel button on DC form (optional) | Cancel API working | Quick |
| 8 | Deploy script | All source ready | Quick |
| 9 | Smoke test on Test | Deployed | Manual |

Steps 4–7 can be developed in parallel once schema is deployed.

---

## 6. Edge Cases and Risks

### 6.1 Race conditions

- **Two users cancel simultaneously:** The cancel API must be idempotent. If DC is already Cancelled, return success without double-processing.
- **Task completion racing cancel:** The gates script should block completion of tasks whose DC is Cancelled. Add the check early in the gates flow.
- **Cancel during Pack:** If the packer is mid-scan and the DC gets cancelled, their next scan/save should fail with a clear "DC has been cancelled" message.

### 6.2 Stock Entry reversal failures

- **Insufficient stock in In-Transit warehouse:** If stock was manually moved out of the In-Transit warehouse (shouldn't happen but could), the reversal SE will fail. The cancel API should catch this and report which items couldn't be reversed.
- **Batch/serial mismatch:** The reversal SE must use the same batch/serial numbers as the original dispatch SE. Read them from the original SE items.

### 6.3 Docstatus complications

Dispatch Case is `is_submittable = 1`. If the DC is already submitted (docstatus=1), changing its status to Cancelled via `db.set_value` works, but `save()` will trigger the server-side submitted-document lock (`Dispatch-Case-before-save-lock-submitted.py`). The cancel API must either:
- Use `flags.ignore_permissions` + `flags.ignore_validate_update_after_submit`
- Or bypass the lock by checking for the cancel operation specifically in the lock script

### 6.4 Telegram notifications

The Telegram Task Status Update script already maps `Cancelled` to a notification. When tasks are auto-cancelled by the cancel API, each task save will trigger a Telegram notification. Consider whether this is desired or if bulk-cancel should suppress notifications.

### 6.5 Discount Approval in progress

If a Discount Approval task is active (DC in `Awaiting Approval`), cancellation should also cancel the approval task. The cancel API's "cancel all open tasks" step handles this, but the approval task's completion handler in `Task-after-save-dispatch-flow.py` should also check if the DC was cancelled before proceeding.

---

## 7. Testing Checklist

After implementation, verify on Test:

- [ ] Cancel a Draft DC (no SE, no tasks beyond Order Entry)
- [ ] Cancel a Confirmed DC (Pack task exists but not started)
- [ ] Cancel a Packed DC (dispatch SE exists) — verify reversal SE created
- [ ] Cancel an In Transit DC (if allowed) — verify reversal SE
- [ ] Attempt cancel on Delivered DC — should be blocked
- [ ] Attempt cancel on Closed DC — should be blocked
- [ ] Attempt cancel on already-Cancelled DC — should be idempotent
- [ ] Cancel with active Discount Approval — approval task should be cancelled
- [ ] Cancel while packer has task open — next save should fail with clear message
- [ ] Verify Telegram notifications fire (or are appropriately suppressed)
- [ ] Verify restock task is created with correct assignment
- [ ] Complete the restock task — verify it completes cleanly
- [ ] Verify the DC shows cancellation fields (reason, notes, who, when)
- [ ] Verify no orphaned stock in In-Transit warehouse after cancel

---

## 8. Files That Will Be Modified

### New files

| File | Type | Purpose |
|---|---|---|
| `deploy/test/work/server/dispatch_case_cancel.py` | Server Script (API) | Cancel API |
| `deploy/test/scripts/deploy-phase3-cancel-flow.ps1` | Deploy script | Phase 3 deployment |

### Modified files

| File | Change |
|---|---|
| `deploy/test/work/server/Task-before-save-dispatch-gates.py` | Add DC Cancelled check |
| `deploy/test/work/server/Task-after-save-dispatch-flow.py` | Add Discount Approval cancelled-DC check; optionally add Dispatch Cancel Restock handler |
| `deploy/test/work/client/Task-Action Buttons.js` | Add Cancel Dispatch button + dialog |
| `deploy/test/work/client/Dispatch Case-Form.js` | Optionally add Cancel button for Directors |
| `docs/16-unified-dispatch-flow.md` | Add Section 13: Cancel Flow |
| `deploy/test/work/dispatch-flow-redesign-v4-implementation-status.md` | Update Phase 3 status |

### Schema changes (via deploy script)

| Target | Change |
|---|---|
| Dispatch Case `status` field | Add `Cancelled` option |
| Task `task_kind` field | Add `Dispatch Cancel Restock` option |
| Dispatch Case custom fields | Add 5 new fields |
| Task Access Policy | Create `Dispatch Cancel Restock` record |

---

## 9. Summary of What Needs Your Decision

Before any code is written:

1. **Q1 — Who can cancel?** Recommendation: Role-based per state (see table in §3)
2. **Q2 — Cancellable states?** Recommendation: Draft through In Transit (not Delivered+)
3. **Q3 — What happens to open tasks?** Recommendation: Auto-cancel + create restock if stock moved
4. **Q4 — Stock reversal?** Recommendation: Auto-reverse for Packed, manual-confirm for In Transit
5. **Q5 — Invoice/Payment handling?** Recommendation: Block cancel if submitted invoice exists
6. **Q6 — Cancel from where?** Recommendation: Both Task and DC forms
7. **Q7 — Cancellation reason?** Recommendation: Required Select + optional free-text notes
