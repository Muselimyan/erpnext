# Dispatch Case — Cancellation Flow — Design

> **Status.** Implemented on test (Group 1 D11). Deploy: `deploy/test/deploy/group-1-dispatch-operational/d11-cancel-flow.ps1`. Verification: `d11-verify-cancel-flow.py`, 62 of 62. The full regression set passes, 305 of 305 across 19 suites. The flow specification is `docs/16` §10A.
>
> **In one paragraph.** A Dispatch Case can be cancelled until its goods reach the client. Before that point no invoice exists, so cancellation never involves billing, credit notes or tender quantities. If the goods have left Main, they come back through the existing returns chain: inspection records what actually came back, losses go to Write-off Approval, and restocking returns the rest to Main. `Cancelled` is a final state for the case and for every task on it.

---

## 1. Where the stock is decides everything

Taken from the `create_se` calls in `Task-after-save-dispatch-flow.py`:

| Status | Goods are | Needs a physical return |
|---|---|---|
| Draft | in Main | No |
| Awaiting Approval | in Main | No |
| Confirmed | in Main — books unchanged until Pack completes | No |
| Packed | in `Delivery In-Transit` — packed, in the building | **Yes** |
| In Transit | in `Delivery In-Transit` — the same box, in a vehicle | **Yes** |
| Delivered onwards | at the client, or in the returns chain | Not cancellable |

**`Picked Up` moves no stock.** It only sets the status (`Task-after-save-dispatch-flow.py:211-212`). So `Packed` and `In Transit` are the same stock position, and one return rule covers both.

**The flow creates no invoice before `Delivered`.** Invoice Preparation is raised only when a delivery completes with no return expected, or when returns inspection completes, and both happen at or after `Delivered`. Nothing *enforces* this, though: someone could create a Sales Invoice by hand and link it to an earlier case. So cancellation checks for an invoice rather than assuming there isn't one (§4.1).

## 2. When cancellation is available

| Status | Cancellable |
|---|---|
| Draft, Awaiting Approval, Confirmed, Packed, In Transit | **Yes** |
| Delivered and everything after | **No** |
| Cancelled, Closed | **No** — already final |

The line sits at the one point where three things change together: the goods leave our control, an invoice becomes possible, and the returns flow takes over. Put the line anywhere else and cancellation overlaps the returns flow.

A refusal says what to do instead:

| Situation | Message |
|---|---|
| Delivered or later, no return expected | *"These goods have been delivered and consumed. A correction is a credit note against the invoice."* |
| Delivered or later, return expected | *"These goods are with the client. Use the return flow — Return Call, then Pickup Returns."* |
| Closed | *"This case is closed. A correction after closure is a credit note."* |
| Already Cancelled | *"This case was cancelled on {date} by {user}: {reason}."* |

## 3. Who may cancel

| Status | Who |
|---|---|
| Draft, Awaiting Approval *(before submit)* | The user who accepted the case's Order entry task, **or** `Ops - Directors` |
| Confirmed, Packed, In Transit *(after submit)* | **`Ops - Directors` only** |

Before submit, only the order-taker's own work is affected, and they should be able to abandon it without finding a Director. After submit, the warehouse has been told to act and stock may have moved.

**The order-taker is identified through `Dispatch Case.order_entry_task` → that task's `custom_accepted_by`**, not by looking for "an open task held by the caller", which is how every other endpoint in the flow checks. In `Awaiting Approval` the Order entry task is already *Completed*, so the usual check would wrongly refuse the one person entitled to cancel.

**The button** is on the Dispatch Case form only. It appears only when the case is cancellable **and** the current user is allowed to cancel it. The server enforces both conditions regardless; hiding the button is a convenience for the user, not the protection.

## 4. What cancellation does

One API, `dispatch_case_cancel`, taking `dispatch_case`, `reason` and `notes`. Steps, in order:

### 4.1 Lock, then refuse early

1. **Lock the case row** (`SELECT … FOR UPDATE`) before reading anything. This serialises cancellation against any other request that is changing the same case. Without it, a Pack completing at the same moment could move the stock *after* cancellation had decided nothing needed bringing back, leaving goods stuck in transit with no task to return them.
2. Status is in the cancellable range (§2); otherwise refuse with the matching message.
3. The caller is authorised (§3).
4. A reason is supplied; if the reason is `Other`, a note is required too.
5. **No Sales Invoice exists for the case, in any state.** The flow never creates one this early, which is exactly why it is worth checking: if one exists, someone made it by hand, it is their work, and cancellation refuses rather than deleting it.

### 4.2 Record why

New fields on Dispatch Case: `cancellation_reason` (Select, required), `cancellation_notes` (Small Text), `cancelled_by`, `cancelled_at`.

| Reason |
|---|
| Customer cancelled |
| Surgery cancelled or postponed |
| Items unavailable |
| Duplicate order |
| Entered in error |
| Other *(note required)* |

### 4.3 Cancel the open tasks

Every task on the case whose status is not `Completed` or `Cancelled` is set to `Cancelled`, and one line is appended to its description:

> *Cancelled because {case} was cancelled by {user} on {date}: {reason}.*

This line is how the assignee finds out. They see the task in their own task list, marked cancelled, with the reason attached. No ToDos are created or touched.

**On a Pack task that someone has already accepted**, the appended line also says: *"If you pulled items for this order, return them to the shelf."* At `Confirmed` the stock has not moved in the books (it moves only when Pack completes), but a packer may already have taken items off the shelf. No Stock Entry is needed for that, only a person putting the items back.

**The write uses `frappe.db.set_value`, and this is deliberate.**

- It is the only way to change `status` on a task the caller does not own. `status` cannot be added to an access-control script's list of system-managed fields, because it is the main field a user edits; allowing it would switch off the ownership check where it matters most.
- It skips the completion checks, and that is correct. Those checks enforce the rules for *finishing* work (outcome recorded, photo attached, follow-up date set). A cancelled task was not finished and must not be held to them.
- There is precedent: `Payment Entry-after-submit-debt-closure-check.py` sets Dispatch Case status the same way.

**Notification.** Both Telegram scripts are currently disabled, so today the note on each cancelled task *is* the notification. When Telegram is switched back on, cancellation sends **one message about the case**, naming the reason, not one per task. Because `db.set_value` fires no document events, the per-task Telegram trigger would not fire anyway.

### 4.4 Release advance credit tagged to the case

A `Payment Received` task can record an advance at any time, including while the case is still Draft, and that Payment Entry is tagged with the case in `dispatch_case`. Two existing rules then work against the client:

- `task_commit_invoice` will not spend credit tagged to one case on a different case, because that credit is earmarked.
- The debt calculation counts only **untagged** credit, so tagged credit does not reduce what the client appears to owe.

If nothing is done, cancelling such a case **strands the client's money for good**: the invoice that would have used it will never exist, no other invoice is allowed to use it, and it doesn't offset any other debt. The client has paid, and the system shows them owing the full amount.

**So on cancel, `dispatch_case` is cleared on every submitted, unallocated Receive Payment Entry tagged to the case.** That turns the money into general credit: it can be used on the next invoice, and it counts in the client's net position straight away.

`Payment Entry.dispatch_case` is not `allow_on_submit`, so this has to be a `frappe.db.set_value`, and that writes no version record. To keep a record of who moved the money, **a Comment is added to each Payment Entry** (*"Released from {case}, cancelled by {user}: {reason}"*), and the release is listed in the case's cancellation notes. A change to money must leave a trail even when the field write itself can't.

### 4.5 Start the physical return, if needed

`Packed` or `In Transit`: raise the first task of the return chain (§5).
`Draft`, `Awaiting Approval` or `Confirmed`: nothing to raise.

### 4.6 Set the status

`status = "Cancelled"`, a new option on the Dispatch Case `status` field.

**`docstatus` stays at 1**, as it does for `Closed`. In this system `status` carries the lifecycle, and `docstatus` only records that the document is committed.

There is **no in-between status** for "cancelled, goods still coming back". The case is finished administratively as soon as it is cancelled. Any remaining physical work shows up as open return-chain tasks, and `RPT — Stock — In-Transit Stuck (Age Check)` already reports stock left sitting in transit.

## 5. The return chain — reusing the existing one

For `Packed` and `In Transit` cases. It is the existing returns flow from goods arriving back at the warehouse onwards. The only difference is that there's no Return Call step, because nobody needs to phone the client.

| Step | Task | Who | Stock | Code |
|---|---|---|---|---|
| 1 | `Return to warehouse (aborted delivery / cancelled order)` | Driver | `Delivery In-Transit` → `Returns` | **New handler** |
| 2 | `Returns processing / verification` | Ops - Returns | Records what came back; any lost units move `Returns` → `Lost & Damaged` | Existing, **with one guard** |
| 3 | `Returns restocking` | Ops - Returns | `Returns` → `Main` | Existing, **unchanged** |
| — | `Write-off Approval`, only if something was lost | Ops - Directors | `Lost & Damaged` → written off | Existing, **with one guard** |

### Step 1 — Return to warehouse *(new)*

- **Assignee.** For `In Transit`: **the driver who accepted the Delivery task**, because that driver has the box. For `Packed`: the delivery team pool from the task's Access Policy, because the box is in the building and anyone on the team can hand it over. If the task went to the pool while a particular driver actually held the box, whoever accepted it would be recording a handover they didn't make.
- **Completion requires a photo**, the same check `Returns restocking` already uses.
- **On completion:** `Delivery In-Transit` → `Returns`, then raise `Returns processing / verification`.

The kind already exists with a `task_kind` option and a Task Access Policy (`delivery.team@example.com`; `Delivery Driver`, `Ops - Delivery`), and has never had a handler.

### Step 2 — Inspection *(existing, one guard)*

The inspector records quantities with the existing returns endpoint, exactly as for a normal return. **This is where any shortfall is caught:** a unit that didn't come back is recorded as lost, and the existing handler moves it to `Lost & Damaged` and raises Write-off Approval. Nothing is assumed to have come back; someone counts it.

**The completion check, when the case is `Cancelled`:** every row must satisfy `returned + lost = dispatched`. These goods never reached a client, so nothing can have been *used*. Without this check, any gap would be booked as consumption, as though the client had kept and used the units.

**The guard in the completion handler, when the case is `Cancelled`:** skip setting status to `Invoice Pending` and skip raising Invoice Preparation (`Task-after-save-dispatch-flow.py:311-312`). Without it, completing inspection would move a cancelled case back to `Invoice Pending` and raise an invoice task for an order that was never delivered. The rest of the handler (moving losses, raising Write-off, raising restocking) is correct as it stands and stays as it is.

### Step 3 — Restocking *(existing, unchanged)*

The deployed handler works on a cancelled case with no changes:

- it **sets no status**, so it can't move the case out of `Cancelled`;
- it already **requires a photo**;
- it moves exactly the rows with `returned_qty > 0`, which inspection has just recorded;
- its effect on valuation is already covered by a test: the D1 check confirms a restock leaves Main's moving average unchanged.

### Write-off Approval *(existing, one guard)*

**When the case is `Cancelled`, `Bill Client` is refused and only `Write Off` is allowed.** Cancellation happens before delivery, so the goods never reached the client and the client cannot have caused the loss. Billing them would put an invoice on an order that never became a sale.

## 6. `Cancelled` is final

**For tasks.** `Task-before-save-access-control.py:111` currently makes only *Completed* tasks immutable (`if before_status == "Completed":`). A cancelled task is protected only by the client script, which is a convenience and not an enforcement. As things stand, a Director can reopen a cancelled Pack task and its accepter can then complete it. That would move stock and raise a Delivery task on a cancelled case. **Extend that check to cover `Cancelled`.** This applies to every task in the system, not just the cancel flow; the same gap exists today for Debt Alerts, approvals and everything else.

The tasks in the return chain are unaffected. They are created *after* cancellation as new open tasks, so they can be completed normally.

**For the case.** The Dispatch Case `status` field is already read-only on the form. On the server, both Dispatch Case access-control scripts (the draft one and the submitted twin) get one rule: **a document save may not change `status` to `Cancelled` or away from it.** The cancel API writes with `set_value`, which doesn't run those scripts, so no bypass flag is needed, in line with AGENTS.md's no-bypass-flag rule.

There is no uncancel. A client who changes their mind gets a new case.

## 7. What changes elsewhere

| Where | Change |
|---|---|
| `RPT - Dispatch Case Aging` | Filter changed to `NOT IN ('Closed', 'Cancelled')`; before that it counted cancelled cases as open for ever. Its `FROM` clause was also repaired: the report had **never run**, because a PowerShell backtick-t had turned `` `tabDispatch Case` `` into a TAB character followed by `abDispatch Case`. Five other reports carry the same corruption (Group 10 F-032). |
| `RPT — Dispatch Cases — Aging (Open)` | **Retire it.** It duplicates the report above. It already excludes Cancelled while the other doesn't, so leaving both would give two different answers to one question (Group 10 F-004). Keep the richer report, which has the stage column. Its shortcut in `Ops — Reporting Pack` is repointed in the same change (Group 10 F-030). |
| `Task-before-save-access-control.py` | `Cancelled` becomes immutable (§6) |
| Both Dispatch Case access-control scripts | `status` cannot change to or from `Cancelled` through a document save (§6) |
| `Task-after-save-dispatch-flow.py` | Step 1 handler (new); inspection guard (§5) |
| `Task-before-save-dispatch-gates.py` | Photo check for step 1; `returned + lost = dispatched` on cancelled cases; `Bill Client` refused on cancelled cases |
| `Task-Field-Visibility.js` | Remove the `Dispatch Cancel Restock` entry. That kind was never created. |
| `docs/16-unified-dispatch-flow.md` | Add a cancellation section. It is the flow specification and currently has none. |
| `docs/21-task-kind-field-visibility-matrix.md` | Record the step-1 handler for `Return to warehouse` |
| `docs/manual/cancellation-and-corrections.md` | **Rewrite.** It tells staff cancellation is System Manager only, done through native document cancel, and it still describes an automatically created draft invoice that no longer exists. |

Everything else in the flow is unchanged: invoicing, payments, pricing, the debt calculations, and the returns flow for delivered goods.

## 8. What cancellation is not

- **Not a delete.** The case, its tasks and its stock history all stay.
- **Not a way to undo a delivery.** Goods that reached the client come back through the returns flow.
- **Not a way to correct a billed sale.** That is a credit note, `deferred-workstreams.md` item 1b.
- **Not reversible.** See §6.
- **Not a bulk tool.** One case at a time, with a reason for each.

## 9. Verification

Built the way the rest of the project is: a deploy script with `-Mode Check` / `-Mode Deploy` and `-ConfirmDeletions` for the report retirement and schema changes; verification that runs as non-privileged users through `bench console`, uses savepoints for failure paths, and rolls back; and the full existing regression set re-run afterwards.

1. Cancel from each of the five cancellable states.
2. Refuse from `Delivered`, `Returns Received`, `Payment Pending`, `Closed`, each with the matching message; refuse a second cancellation.
3. Refuse when any Sales Invoice exists for the case, submitted or draft, and leave that invoice untouched.
4. Every open task ends `Cancelled` with the reason in its description; an accepted Pack task also carries the reshelving note.
5. A cancelled task cannot be edited or completed, even by `Ops - Directors`.
6. A document save cannot move a case into or out of `Cancelled`.
7. The order-taker can cancel their own case in `Draft` and in `Awaiting Approval`; a non-Director cannot cancel a `Confirmed` case.
8. Tagged advance credit is released to general credit, with a Comment on each Payment Entry, and the client's net position changes to match.
9. `Confirmed` cancel → no Stock Entry, and no return task.
10. `In Transit` cancel → the return task goes to the Delivery task's accepter; `Packed` cancel → it goes to the team pool.
11. Full chain, everything returned: `Delivery In-Transit` goes back to its starting balance, `Main` is restored, the case stays `Cancelled`, and **no invoice task is raised**.
12. Full chain, one unit short: that unit goes to `Lost & Damaged`, Write-off Approval is raised, `Bill Client` is refused, `Write Off` succeeds, the rest is restocked.
13. Inspection on a cancelled case refuses any row where `returned + lost ≠ dispatched`.
14. `RPT - Dispatch Case Aging` excludes cancelled cases.
15. Stock conservation: after a cancel from `Packed`, `Main` falls by exactly the quantity written off, and by nothing when everything came back.

## 10. Scope of the change

| | |
|---|---|
| **New** | `dispatch_case_cancel` API; `Cancelled` status option; four cancellation fields; step-1 handler and photo check; cancel button and dialog on the Dispatch Case form |
| **Existing, with a guard** | Inspection handler (no invoice or status change on a cancelled case); inspection completion check (nothing used); Write-off Approval (no `Bill Client`) |
| **Existing, unchanged** | `Returns restocking`; the lost-and-damaged move; the `Return to warehouse` kind and its policy |
| **System-wide** | `Cancelled` becomes an immutable, final state for every task |
| **Not needed** | Any new task kind or Task Access Policy; an in-between status; any change to `docstatus`; any ToDo |
| **Out of scope** | Credit notes, refunds, anything after `Delivered` — `deferred-workstreams.md` item 1b |
