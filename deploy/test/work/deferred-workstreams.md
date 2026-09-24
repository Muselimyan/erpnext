# Deferred Workstreams

> Work that was identified, understood, and deliberately **not** done — each with the reason, the blocker, and what is needed to start.
>
> This is not a backlog of "nice to have". Every item here was found while fixing something else, and each was deferred for a stated reason rather than forgotten. Two of them carry real business consequence.
>
> **Source:** Group 1 dispatch remediation (D1–D9, 2026-09-22/23). Group 11's own open items are cross-referenced, not duplicated.

---

## 1. Cancel flow — there is no way to cancel an order

**Deferred by decision, own workstream.**

### What it is

A Dispatch Case cannot be cancelled. `Cancelled` is not one of its statuses, there is no cancel handler, and ERPNext's own cancel just marks the record cancelled without reversing anything — leaving stock sitting in a transit warehouse with nothing pointing at it.

### Why it matters

Surgeries get cancelled and orders get raised in error. Today the only options are to push the case all the way through a flow that no longer reflects reality, or have an administrator edit the data directly.

It also interacts with the acceptance model. Completing a task is reserved to the person who accepted it, with no override — deliberately, so the record of who did the work stays honest. **Cancellation was meant to be the escape hatch for a stuck task, and it does not exist.** So a genuinely stuck task has no clean resolution at all.

### The evidence of the gap

77 cases on test currently hold stock in transit warehouses and cannot move — 61 have no client warehouse recorded, 15 point at the main warehouse by mistake. They were stuck before any of this work and they are stuck after it. There is no in-system way to dispose of them.

### What blocks it

Not a coding problem — a design one. Group 11 identified the specific mechanism gap: cancelling in bulk means writing `status` on tasks the current user does not own, and `status` cannot be added to the system-fields allow-list because it is *the* primary field a user edits. That mechanism does not exist yet.

### Related decision already taken

The task kind `Return to warehouse (aborted delivery / cancelled order)` was **deliberately kept** when its siblings were retired, because it is literally the aborted-delivery return and is the most likely thing this flow will use.

### To start

Design doc exists: `deploy/test/work/phase3-cancel-flow-plan.md`. The open questions are what happens to stock already in transit, and what happens when an invoice has already been submitted (that becomes a credit note, not a reversal — Group 11 A4).

---

## 2. Batch, serial and expiry tracking is switched off

**Deferred by decision, own workstream. Highest business consequence of anything on this list.**

### What it is

Batch, serial and expiry tracking is disabled on **every** item. Two API utilities did it and both are still deployed and callable:

- `disable_all_item_batch_serial_for_now` — clears the three flags on all items
- `perm_disable_batch_expiry_dbset` — the same for a named list

The name of the first one says what it was: a pre-launch expedient that never got undone.

### Why it matters

For a medical device distributor, batch and expiry **are** the traceability mechanism. If a manufacturer recalls a batch of implants, the question is "which hospitals received units from that batch" — and today the system cannot answer it.

### Why it is not a switch

Two things collide:

1. With batch tracking on, ERPNext requires a batch on every stock movement. No batch, no movement.
2. Packers get the batch by scanning — but only GS1 barcodes carry a batch and expiry. A plain barcode is just a product code.

So enabling it blindly means a packer scanning a plain barcode is refused and cannot finish. **Packing stops.** That is why it needs a plan.

### What is needed to start

- What proportion of stock carries GS1 barcodes?
- When an item does not, what should the packer do — read the batch off the box and key it in, or is that unrealistic at the pace they work?
- Enable per-item, or globally?

That answer decides the shape of the work. The two utilities should be retired as part of the same change, otherwise the override can be silently re-applied.

### Note for whoever picks this up

`create_se` is now strict — it was made strict in D1, and that is what makes this interaction bite. Before D1 a missing batch would have slipped through along with everything else.

---

## 3. The assignment model — two fields, one of which cannot work

**Open. Needs a decision, not urgent, but do not let anyone "tidy" it.**

### What it is

Who a task is assigned to is recorded in two places: `custom_assigned_to`, which the team built, and `_assign`, which is ERPNext's own. The code tries to copy the first into the second on every save.

**It cannot work.** Established from Frappe's source, not from inspecting records: `_assign` is a framework-managed field excluded from `Document.get_valid_columns()`, so a normal document write can never persist it. Frappe expects `assign_to.add()` to maintain it.

### What actually breaks

`_assign` is what the Task **list view** filters on to build the "My Tasks" and team-queue toggles. So it is how a person *finds* their work — and therefore how they reach a task in order to accept it.

A task assigned to a person but created outside the dispatch flow has an empty `_assign` and **does not appear under "My Tasks"**. It drops into the team pool looking unassigned. The main flow escapes this only because `make_task` writes the field separately with `frappe.db.set_value` after insert.

### The trap

There is a line in `Task-before-save-policy` that tries to sync and silently fails. It looks like dead code. **It is load-bearing.** `doc.set()` still attaches the value in memory, and the task-kind role check reads it there — proven, because that check correctly refuses a wrong-role task.

Delete that line as cleanup and **the role check stops working, with nothing failing visibly.**

### The choice

| | |
|---|---|
| Adopt Frappe's mechanism | Use `assign_to.add()`, which also creates the ToDo that drives notifications. More correct; changes how assignment works everywhere |
| Drop `_assign` entirely | Make `custom_assigned_to` the single source of truth and have the list view filter on it instead |

Either is defensible. The present state — a sync that cannot work, a list view depending on it, and a permission gate depending on its in-memory side effect — is not.

**Whichever is chosen, the role check and the list-view filter must be rewritten in the same change.**

---

## 4. Stock data cleanup

**Deferred. Test cleanup is routine; the production question is not.**

### What it is

372 submitted Stock Entries carry rows with a missing warehouse. Two populations, and they are not equally harmless:

| Count | Shape | Effect |
|---|---|---|
| 172 | Material Issue, no source warehouse | Posted **nothing**. Inert paperwork |
| 200 | Material Transfer, one side missing | **Did post.** Stock created out of nowhere or destroyed into nowhere |

Plus 13 items sitting at negative stock in the main warehouse (−415 units).

### Current state

D1 stopped new ones being created. D9 turned off `allow_negative_stock`, so **operations touching those 13 negative items will now fail** — intended, and the reason they get noticed.

None of the existing records were repaired. Test data is disposable by decision.

### The part that is not routine

The bug that produced these ran everywhere, not only on test. **Whether production has equivalents of those 200 one-sided transfers is an open question and has not been looked at.** If it does, that is a stock-valuation problem rather than a tidy-up.

Production code is described as very old and is out of scope for now, but this question should not get lost with it.

---

## 5. Test coverage — the paths not yet driven end to end

**Known gap, lower risk than it was.**

`e2e-full-chain.py` drives one case through the entire chain and passes 45/45, including stock conservation. It covers the **returns-expected path with a partial loss** (10 dispatched → 6 used, 3 returned, 1 damaged).

Not yet covered as full-chain runs:

| Path | Status |
|---|---|
| No-return delivery (goods consumed at the client) | Hops verified in isolation |
| Discount approval — approved | Verified in isolation |
| Discount approval — rejected, case returns to Draft | Verified in isolation |
| Write-off resolution — Bill Client | Verified by the W12 harness |
| Write-off resolution — Write Off | Verified by the W12 harness |

Each hop is proven; what is unproven is the joins between them on those particular routes. That is the same class of gap the main end-to-end test just closed, so the pattern to follow exists.

---

## 6. `Task-Packing Checkboxes.js`

**Note only, no work unless someone acts.**

Disabled, and still calls the packing endpoints the old way (by row position). D2 made the server refuse that. If it is ever re-enabled it must be updated to send row names first, or it will fail immediately.

---

## Cross-references — Group 11's open items

Not repeated here. See `group-11-dispatch-financial-tail-gap-analysis.md`.

| | |
|---|---|
| **A1** | Profit is costed from a buying price list instead of landed cost. **Now unblocked** — its stated dependency was A2, which Group 1 D1 closed |
| **A4** | A paid invoice cannot be corrected in-system. No credit note, no refund path. Interacts with the cancel flow above |
| **A5** | The e2e API suite runs entirely as Administrator, and privileged users are exempt from the access-control gates — so it is structurally incapable of catching that class of defect. Three have shipped through that blind spot |
| **A6** | Reporting and Telegram money notifications, deferred until the figures underneath were trustworthy |

---

## If you want an order

1. **Batch/expiry** — the only item here with a regulatory edge, and the one that gets worse the longer it runs untracked.
2. **Cancel flow** — unblocks 77 stuck cases and gives the acceptance model the escape hatch it was designed around.
3. **Group 11 A1** — newly unblocked, and profit figures are wrong until it lands.
4. **Assignment model** — low urgency, but the trap should be written into any handover before someone trips it.
5. **Remaining end-to-end paths** — cheap now the pattern exists.
6. **Stock cleanup** — test whenever; the production question deserves its own answer sooner.
