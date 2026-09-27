# Dispatch Case — Cancellation Flow — Design

> **Status.** Design agreed, nothing implemented. All six decisions settled — see §9. Supersedes `phase3-cancel-flow-plan.md` (2026-09-09), which is kept for its Q1–Q7 framing but is stale in several places: it assumes an `Invoiced` status that no longer exists, a `Dispatch Cancel Restock` task kind that was never created, and a pre-returns-rework stock model.
>
> **The short version.** Cancel is available until the goods reach the client — which means no invoice can ever exist at cancel time, so cancellation never touches billing, credit notes or tender consumption. If the goods have left the building they come back through the **existing return chain**, reusing `Returns restocking` unchanged. New code is one API, one task handler, one status and four fields.

---

## 1. Why this is the most-needed missing action

Measured on test:

| | |
|---|---|
| Dispatch Cases total | 1,309 |
| **In a state where cancelling would be the right answer** | **1,104** (Draft 625, Confirmed 424, Packed 54, In Transit 1) |
| Open tasks on those cases | 1,004 |
| Stock parked in `Delivery In-Transit` | 15 items, 116 units |

Those 1,104 cases have no route to an end state. They are not stuck because of a bug; they are stuck because **finishing is the only exit the system offers.** An order entered by mistake has to be walked all the way to Closed, or left open forever.

It is also the escape hatch the acceptance model was designed around. Completing a task is reserved to the person who accepted it, with **no override for anyone** — deliberately, so the record of who did the work stays truthful. `Task-before-save-access-control.py:177` says so in as many words: *"Cancellation remains available as the escape hatch for stuck tasks."* That escape hatch does not exist.

---

## 2. The one question that decides the whole design

**Where is the stock?** Everything else follows from that. Mapped from the actual `create_se` calls in `Task-after-save-dispatch-flow.py`:

| Dispatch Case status | Where the goods physically are | Reversal needed |
|---|---|---|
| Draft | Main warehouse — nothing has moved | **None** |
| Awaiting Approval | Main warehouse | **None** |
| Confirmed | Main warehouse — Pack has not run | **None** |
| Packed | `Delivery In-Transit` — a packed box in the building | **Yes** |
| In Transit | `Delivery In-Transit` — the same box, now in a vehicle | **Yes** |
| Delivered | At the client's site | Not a cancellation — see §3 |
| Awaiting Return Pickup … Closed | At the client, or in the returns chain | Not a cancellation |

**Two findings that make this simple:**

1. **`Picked Up` moves no stock.** It only sets the status to `In Transit` (`Task-after-save-dispatch-flow.py:211-212`). So **Packed and In Transit are the same stock position**, and one reversal rule covers both. The previous plan proposed two different mechanisms for these two states; there is no need.

2. **No invoice can exist before `Delivered`.** An Invoice Preparation task is only created when a delivery completes with no return expected, or when returns inspection completes — both at or after `Delivered`. Verified on test: of 1,104 cases in the cancellable band, **0 have an invoice, submitted or draft.**

That second point is the one that keeps this small. Because no invoice can exist, cancellation never has to deal with **billing, payments against an invoice, credit notes, VAT reversal, or tender consumption** (tender `supplied_quantity` is only incremented on invoice submit). All of that lives in the credit-note workstream (`deferred-workstreams.md` item 1b) and none of it is reachable from here.

---

## 3. When cancellation is available

**Cancel is available until the goods reach the client. After that it is a return, not a cancellation.**

| States | Cancel? |
|---|---|
| Draft, Awaiting Approval, Confirmed, Packed, In Transit | **Yes** |
| Delivered and everything after | **No** — the return flow already handles goods at a client, and a billed sale is corrected with a credit note |
| Cancelled, Closed | **No** — already terminal |

This is not an arbitrary line. It is the point where three things change at once: the goods pass out of our control, an invoice becomes possible, and the existing returns machinery takes over. Drawing it anywhere else means cancellation and returns overlap and both get more complicated.

**Refusals must say what to do instead**, not just "no":

- at `Delivered` or later, no return expected → *"These goods have been delivered and consumed. Raise a credit note against the invoice."*
- at `Delivered` or later, return expected → *"These goods are with the client. Use the return flow — Return Call, then Pickup Returns."*
- at `Closed` → *"This case is closed. A correction after closure is a credit note."*

---

## 4. What cancellation does

One API — `dispatch_case_cancel` — taking `dispatch_case`, `reason`, `notes`.

### 4.1 Refuse early

1. Case exists; status is in the cancellable band (§3), with the redirecting message if not.
2. Not already `Cancelled` — idempotent, and says so rather than doing it twice.
3. Caller is authorised (§6).
4. Reason supplied.
5. **Defensive:** no submitted invoice. This cannot happen in the cancellable band, and that is exactly why it is worth asserting — if it ever fires, an assumption this design rests on has broken, and failing loudly beats cancelling a billed case.

### 4.2 Record why

`cancellation_reason` (Select), `cancellation_notes` (Small Text), `cancelled_by`, `cancelled_at`. A reason is **required**; this is the one field that explains the case's whole existence afterwards.

Suggested reasons: `Customer cancelled` · `Surgery cancelled or postponed` · `Items unavailable` · `Duplicate order` · `Entered in error` · `Other`.

`Surgery cancelled or postponed` is added because for this business it is likely the single most common cause, and lumping it under "Customer cancelled" would hide that.

### 4.3 Close the open tasks

Every task on the case with status not in (`Completed`, `Cancelled`) → `Cancelled`.

**Written with `frappe.db.set_value`, deliberately.** Three reasons:

- It is the only way to write `status` on a task the caller does not own. This is the mechanism gap recorded in Group 1 D11 and Group 11: `status` cannot be added to a gate's `SYSTEM_FIELDS` allow-list, because it is *the* primary field a user edits — allowing it would disable ownership checking on the field that matters most.
- It skips the completion gates, **which is correct**. Those gates enforce the rules for *finishing work* — record an outcome, attach a photo, set a follow-up date. A cancelled task has not been finished and must not be asked to satisfy them.
- Precedent exists in the codebase: `dispatch_task_accept.py:39-42` cancels competing ToDos this way, and `Payment Entry-after-submit-debt-closure-check.py` sets Dispatch Case status this way.

**Consequence worth stating:** `frappe.db.set_value` fires no document events, so `Telegram Task Status Update` will **not** send one message per cancelled task. Given a case can carry several open tasks, that avoids a burst of notifications — but it also means assignees are not told. Recommendation: **one notification about the case being cancelled**, naming the reason, rather than N about tasks. ❓**Q3**

### 4.4 Release any advance credit tagged to the case

**This is the hole the previous plan missed, and it loses customers' money.**

A `Payment Received` task can raise an advance at any time, including while the case is still Draft, and that Payment Entry carries `dispatch_case`. Two rules established in the financial-tail work then combine badly:

- `task_commit_invoice` will not spend credit tagged to one case on another — deliberately, it is earmarked.
- A7 made every debt figure net of **untagged** credit only, so tagged credit does not reduce what the client appears to owe.

So a cancelled case holding tagged credit **strands that money permanently**. The invoice that would have consumed it will never exist, nothing else may touch it, and it does not even offset the client's other debt. The client has paid us and the system shows them owing full price.

**On cancel, clear `dispatch_case` on every submitted, unallocated Receive Payment Entry tagged to this case.** The money becomes general credit: available to the next invoice, and immediately counted in the client's net position. Record it in the cancellation notes so the trail survives.

Measured on test: 0 such payments exist today, so this is **preventive** — but it is reachable the first time anyone takes a deposit for an order that is later called off, which for surgical kits is an ordinary event.

### 4.5 Delete a draft invoice if one somehow exists

Cannot happen in the band. One line, and it prevents a stranded draft blocking anything later.

### 4.6 Bring the goods back, if they left — reusing the existing return chain

If the status is `Packed` or `In Transit`, the goods are in `Delivery In-Transit` and a **physical action** is required. Stock moves when that action happens, not when the cancellation is recorded — the same principle the rest of the flow follows.

**Two tasks, because two different people do two different things**, which is exactly how the existing return chain already works:

| Step | Task | Who | Stock |
|---|---|---|---|
| 1 | `Return to warehouse (aborted delivery / cancelled order)` | Driver / Ops - Delivery | `Delivery In-Transit` → `Returns` |
| 2 | `Returns restocking` | Ops - Returns | `Returns` → `Main` |

**Step 2 needs no new code at all.** Checked against the deployed handler:

```python
if is_completing and doc.task_kind == "Returns restocking":
    case.reload()
    r = returned_items(case)
    if r:
        se = create_se(RETURNS_WH, MAIN_WH, r)
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, "restock_stock_entry", ...)
```

Three properties make it reusable as-is:

- It **sets no status**, so completing it on a cancelled case does not un-cancel it.
- It already **requires a photo** (`Task-before-save-dispatch-gates.py`) — the record that the units were physically shelved.
- It moves whatever `returned_items()` returns, which is rows with `returned_qty > 0`.
- Its valuation behaviour is already verified — the D1 check asserts a restock leaves Main's moving average unchanged.

**The mechanic that connects them:** completing step 1 sets `returned_qty = dispatched_qty` on every row. That is not a fudge — for a cancelled order the whole dispatched quantity *is* coming back, and it makes `used_qty = dispatched − returned − lost = 0`, which is also true: nothing was used. Every downstream consumer then behaves correctly without being told about cancellation: nothing is billable, so no invoice is possible, and the restocking handler moves exactly the right quantity.

**Only step 1 is new code**, and it is small — the existing `create_se`, the existing `make_task`, and a photo gate copied from the restocking pattern:

```
Delivery In-Transit → Returns
set returned_qty = dispatched_qty (so used_qty becomes 0)
raise Returns restocking
```

`Return to warehouse (aborted delivery / cancelled order)` already exists with a `task_kind` option and a Task Access Policy (`delivery.team@example.com`; `Delivery Driver`, `Ops - Delivery`) and **no handler anywhere** — retained during the D4–D6 cleanup as "the most likely consumer of the deferred cancel flow". `Dispatch Cancel Restock` from the old plan is dropped.

> **I had recommended one hop straight to `Main`**, on the grounds that these goods never reached a client so routing them through `Returns` would overstate client returns. Reusing the chain is better, and the objection does not survive scrutiny: `RPT — Stock — Returns` reports a **warehouse balance**, and the goods genuinely are sitting in the returns area awaiting shelving. Anything that does need to tell the two apart can filter on the case being `Cancelled`. The two-hop route also matches what `docs/09` §10.2 and the go-live checklist already specify, so the design no longer deviates from either.

### 4.7 Set the status

`status = "Cancelled"` — a new option on the Dispatch Case `status` field, which currently has 13 and none for this.

**`docstatus` is left at 1.** The case is not ERPNext-cancelled. This matches how every other terminal state works here: `Closed` is also `docstatus 1`. In this system `status` is the lifecycle and `docstatus` only records that the document is committed. Setting `docstatus 2` would also fight the Stock Entries, which are separate documents linked by field and would not be reversed by it anyway.

**No new intermediate status** for "cancelled but goods still coming back". The case is administratively dead the moment it is cancelled; the outstanding physical work is visible as an open task, and `RPT — Stock — In-Transit Stuck (Age Check)` already reports transit stock that lingers.

---

## 5. The hole that this creates, and how to close it

**If a gate blocks work on a cancelled case, it blocks the return-to-warehouse task too** — and then the goods can never come back. The previous plan proposed exactly that gate: *"if a task's linked DC is Cancelled, block completion."*

So: **any such gate must exempt `Return to warehouse (aborted delivery / cancelled order)`.** It is the one kind that legitimately runs *after* cancellation.

In fact no blanket gate is needed. Cancellation already cancels every open task, and a cancelled task cannot be completed. The only task that exists afterwards is the return-to-warehouse one, which we want completable. A blanket gate would add nothing and break the one thing that must work.

---

## 6. Who may cancel

Two tiers, on the boundary that already means something — whether the case has been committed to the warehouse:

| States | Who |
|---|---|
| Draft, Awaiting Approval *(pre-submit)* | The user who accepted the Order entry task, **or** Directors |
| Confirmed, Packed, In Transit *(post-submit)* | **Directors only** |

Before submit, nothing has been asked of anyone else — it is the order-taker's own draft and they should be able to abandon it without finding a Director. After submit, the warehouse has been told to pick it, stock may have moved, and someone outside the order desk is affected.

Two tiers rather than the four the old plan proposed, because the extra granularity bought nothing: every post-submit state has the same answer.

> **This changes published procedure.** `docs/manual/cancellation-and-corrections.md` currently tells staff Dispatch Case cancellation is **System Manager only**, via native document cancel. That manual needs rewriting when this ships — it also still describes an auto-created draft invoice, which W6 removed. Flagged so it is not missed.

**Where the button lives:** on the **Dispatch Case form** only — one surface, one API. Directors work case-by-case, and the order-taker can open their own case.

**The button is shown only when the case is actually cancellable**: status in the band of §3, and the caller in the tier above. A button that is absent when it cannot be used is better than one that explains itself in an error dialog afterwards. The server still enforces both conditions — the hidden button is courtesy, not security.

A Task-form button can be added later without touching the API, if the order desk finds the case form awkward.

---

## 7. What cancellation is not

Stated because each of these is a plausible misreading:

- **Not a delete.** The case, its tasks and its stock history all remain. It is a terminal state, not an erasure.
- **Not a way to undo a delivery.** Goods at a client come back through the return flow.
- **Not a way to fix a billed sale.** That is a credit note (`deferred-workstreams.md` item 1b).
- **Not reversible.** No "uncancel". A client who changes their mind gets a new case. Adding a reopen path would mean deciding what happens to the tasks and stock a second time, for a rare event.
- **Not a bulk tool.** One case at a time, with a reason each. A bulk path is a separate design if it is ever wanted; nothing here depends on one.

---

## 8. Test scenarios this must satisfy

`docs/14-go-live-checklist.md` §9.2A already specifies "Scenario B1 — Cancellation redirect", written before any of this existed. The design satisfies it:

| Checklist expects | Design |
|---|---|
| Cancel at `Confirmed` → related open tasks auto-cancelled, no Stock Entry exists | §4.3, §2 |
| Cancel at `Packed` → return-to-warehouse task auto-created for the driver, drop-off photo required | §4.6 |
| Nothing left in `Delivery In-Transit` | §4.6, on step-1 completion |
| Stock routed via `Returns - Inmed` → `Main - Inmed` on Restock task completion | §4.6 — **matches**, since the design reuses `Returns restocking` |

The design satisfies the checklist without deviation, and it satisfies `docs/09` §10.2 stage (3) as well — driver returns the package, warehouse handover, photo, routed through `Returns` to `Main`. That spec was written for the Sales-Order era and describes exactly the two-role handover the reuse decision produces.

Verification to write alongside the implementation:

1. Cancel from each of the five allowed states.
2. Refuse from `Delivered`, `Returns Received`, `Payment Pending`, `Closed`, each with its redirecting message.
3. Refuse a second cancellation of the same case.
4. All open tasks end `Cancelled`; a case with several open tasks closes all of them.
5. `Packed` cancel → return-to-warehouse task raised, assigned from the policy.
6. That task cannot be completed without a photo, and **can** be completed on a cancelled case.
7. On its completion, `Delivery In-Transit` returns to its starting balance and `Main` is restored.
8. `Confirmed` cancel → **no** Stock Entry is created.
9. Advance credit tagged to the case is released to general credit, and the client's net position changes accordingly.
10. A non-Director cannot cancel a `Confirmed` case; the order-entry accepter **can** cancel their own `Draft`.
11. Stock conservation across a cancel-at-Packed cycle: `Main` ends where it started.

---

## 9. Decisions — all settled

| | Decision |
|---|---|
| **Q1** | **`In Transit` is cancellable.** Same stock position as `Packed`, so it costs nothing, and "the driver is on the road and the surgery was called off" is a real event. The alternative is telling a driver to complete a delivery everyone knows is wrong |
| **Q2** | **Reuse the existing return chain** — `Return to warehouse` then `Returns restocking`, two hops. Only the first step is new code; the second is the deployed handler unchanged, photo gate and verified valuation behaviour included. §4.6 |
| **Q3** | **One message** about the case being cancelled, naming the reason — not one per cancelled task |
| **Q4** | **Dispatch Case form only**, and the button is **hidden unless the case is actually cancellable**. A disabled or absent button is a better answer than an error dialog after the fact |
| **Q5** | Nothing for existing data. Test data is disposable; no migration, no backfill, no bulk tool |
| **Q6** | **Reason is a required Select with the common causes plus `Other`.** When `Other` is chosen the free-text note becomes **required** — "Other" with no explanation records nothing |

Reason list: `Customer cancelled` · `Surgery cancelled or postponed` · `Items unavailable` · `Duplicate order` · `Entered in error` · `Other`. Free-text notes are optional for the named reasons and required for `Other`.

Nothing in this design is now open. It is ready to implement on approval.

---

## 10. What this touches

| | |
|---|---|
| New | `dispatch_case_cancel` API; `Cancelled` on Dispatch Case `status`; four cancellation fields; one handler for `Return to warehouse` completion; one photo gate for it; cancel button + dialog on the Dispatch Case form, shown only when the case is cancellable |
| **Reused unchanged** | **`Returns restocking`** — its handler, its photo gate and its verified valuation behaviour all work on a cancelled case with no modification, because it sets no status and keys off `returned_qty`. The `Return to warehouse` task kind and its Task Access Policy already exist |
| Changed | Nothing in the existing flow scripts. Cancellation is purely additive — which is what makes it safe to add to a system with 243 passing checks |
| Not needed | `Dispatch Cancel Restock` task kind; a new Task Access Policy; an intermediate status; any `docstatus` change; any change to the returns, invoicing or payment code |
| Must be rewritten when this ships | `docs/manual/cancellation-and-corrections.md` — currently says System Manager only, and still describes the auto-created draft invoice that W6 removed |
| Out of scope | Credit notes, refunds, anything after `Delivered` — `deferred-workstreams.md` item 1b |

**The shape of the change, in one line:** one new API, one new task handler, one new status, four new fields — and the entire physical return leg is existing, already-verified code.
