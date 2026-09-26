# Deferred Workstreams

> Work that was identified, understood, and deliberately **not** done — each with the reason, the blocker, and what is needed to start.
>
> This is not a backlog of "nice to have". Every item here was found while fixing something else, and each was deferred for a stated reason rather than forgotten. Two of them carry real business consequence.
>
> **Source:** Group 1 dispatch remediation (D1–D9, 2026-09-22/23). Group 11's own open items are cross-referenced, not duplicated.

---

## 1. Undoing things — cancel flow, and credit notes / refunds

**Deferred by decision, own workstream. Two halves of one problem, bundled deliberately.**

"Undo before the invoice" and "undo after the invoice" are the same user need at two stages. They share the approval pattern, the stock-return question and the tender-reversal question. Doing them apart risks two different answers to *who may undo what*, so they are one item.

---

### 1a. Cancel flow — there is no way to cancel an order

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

**Design written: `deploy/test/work/cancel-flow-design.md`** (2026-09-25). Six decisions marked for review; everything else is a recommendation with its reasoning. `phase3-cancel-flow-plan.md` is superseded and carries a banner saying why.

The shape it landed on: cancel is available until the goods reach a client, which means **no invoice can ever exist at cancel time** (verified, 0 of 1,104 in-band cases) — so cancellation never touches billing, payments, credit notes or tender consumption. `Packed` and `In Transit` hold stock in the same warehouse because `Picked Up` moves nothing, so one reversal rule covers both, using the `Return to warehouse (aborted delivery / cancelled order)` kind that was retained for it. The "invoice already submitted" case is 1b below.

---

### 1b. Credit notes and refunds — a paid invoice cannot be corrected

Cancel + Amend works while an invoice is unpaid. Once a payment is allocated it does not: ERPNext will not cancel an invoice with submitted payment references without unwinding them first. There is no credit note path and no refund path.

**The design is already decided and recorded — only the mechanism is missing.**

- `docs/15a` §6.6 marks "Function — Return/Refund Money" as satisfied by *"`RPT — Returns — Refund Queue` + **standard ERPNext return/refund documents**"*.
- `RPT - Returns - Refund Queue` is **deployed and already queries native credit notes** — `where si.docstatus = 1 and si.is_return = 1`, selecting `si.return_against`. It has nothing to show because nothing creates them.
- `docs/manual/debt-collection-and-payment.md` already instructs staff that a disputed invoice is resolved by "a **Credit Note** … or an explicit write-off (requires Director approval)".

So the reporting layer and the staff manual both assume native credit notes exist. This aligns with the ERPNext-native rule in `AGENTS.md` with no tension: native documents (`Sales Invoice` with `is_return = 1`; a `Pay` Payment Entry for cash back), custom orchestration.

#### Decisions already taken

| | |
|---|---|
| Authority | **Directors**, mirroring Write-off Approval — same class of decision, and the manual already says Directors are involved. `docs/implementation-questions.md` (~L877) had left the approval owner open |
| Shape | A `Refund / Credit Approval` task kind + Task Access Policy, outcome Select, idempotency on `source_task` — the Write-off Approval skeleton, which is proven |
| Scope of credit | **Per-line partial**, because the driver is usually a disputed subset. Whole-invoice-only would push people back to manual edits |
| Cash vs credit | **Credit note first**, cash refund as an explicit second outcome on the same approval. Most cases resolve by offsetting the next invoice |

#### THE BLOCKER — read this before writing any code

**The tender scripts are blind to credit notes, and shipping A4 without fixing them silently destroys tender entitlement.**

No server script anywhere references `is_return` or `return_against` — verified across all of `deploy/test/work`. All three tender scripts skip non-positive quantities:

| Script | Line | Guard |
|---|---|---|
| `Sales-Invoice-before-submit-tender-validation.py` | 22 | `if not item_code or qty <= 0: continue` |
| `Sales-Invoice-after-submit-tender-update.py` | 24 | `if not item_code or qty <= 0: continue` |
| `Sales-Invoice-on-cancel-tender-reversal.py` | 14 | `if … or qty <= 0: continue` |

A credit note carries **negative** quantities. So on crediting a tender invoice: validation passes trivially, `supplied_quantity` is **not** given back, and `tender_fulfillments` stays empty so the on-cancel path has nothing to reverse either.

Because the validator refuses `qty > won − supplied`, **the hospital's remaining tender entitlement shrinks with every credit note and cannot be recovered except by editing the tender by hand.** Not a live bug today — nothing creates credit notes. It becomes one on the day this ships.

#### Two behaviours to verify on test, not reason about

1. **Does a credit note reduce the original invoice's `outstanding_amount`?** ERPNext reduces the *party* balance, but whether it nets against the specific `return_against` invoice without an explicit Payment Reconciliation is version-dependent. This decides whether a credited case can ever reach `outstanding <= 0`.
2. **Nothing re-evaluates closure after a credit note.** `Payment Entry-after-submit-debt-closure-check` fires only on a Payment Entry submit with `payment_type = "Receive"`. A credit note is a Sales Invoice; a refund is a `Pay` entry. Neither triggers it, so a case resolved entirely by credit note plausibly sits in `Payment Pending` forever.

#### One report bug to fix at the same time

`RPT - Returns - Refund Queue` joins `dc.sales_invoice = si.return_against OR dc.sales_invoice = si.name`. `Dispatch Case.sales_invoice` is the stale convenience pointer — by definition wrong after Cancel + Amend. It should join `si.dispatch_case`. This work will be its first real consumer, so fix it before it has rows.

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

## 4. Purchasing and landed cost — and therefore profit

**Deferred. Group 11 A1 depends entirely on this.**

### What it is

No purchasing process is running. Measured on test: **zero submitted Purchase Receipts, zero Landed Cost Vouchers.** Stock arrived some other way, so its valuation is whatever it was received at, with no freight, duty or import tax in it.

Doc 17 is the specification for this and §2.1 is unambiguous: cost = `(purchase price + all landed charges) / received quantity`, and *"This is the authoritative cost price. Do not maintain a separate 'cost price' field elsewhere."* That process is not running.

### Why it blocks profit

Group 11 A1 — profit costed from the `Standard Buying` price list instead of actual cost — looks like a one-line swap to `Sales Invoice Item.incoming_rate`. It is not, for two independent reasons:

1. **The field is empty.** 0 of 55 invoice lines have it. Dispatch invoices carry `update_stock = 0` and no Delivery Note, so ERPNext has no stock transaction to derive a cost from.
2. **The number would be wrong anyway.** Without landed cost vouchers, valuation is just the purchase price. On test it agrees with the Standard Buying price to a median of **0.0%** — the two "different" bases are currently the same number, because neither includes any landed cost.

So fixing A1 first would mean building a custom cost lookup to produce a figure that is still wrong. Under the ERPNext-native rule in `AGENTS.md`, the answer is not a better custom calculation — it is to make the standard mechanism reachable.

### What is needed to start

- Are imports actually being received through Purchase Receipts, or entered some other way?
- Is anyone capturing freight, duty and import tax per shipment today, even on paper?
- Should dispatch invoices be linked to a stock document so ERPNext can cost them natively, or is a valuation lookup at invoice time acceptable?

The third question is the design decision. Everything else follows from it.

### Worth doing before then, cheaply

The current profit figure treats a missing buying price as **zero cost — a 100% margin** — and only prints a warning. It should refuse to produce a number it cannot compute. That is independent of all of the above.

---

## 5. Stock data cleanup

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

## 6. The API test suite cannot see permission defects

**Deferred. Structural rather than a bug — the suite is incapable of finding this class of defect, so its passing says nothing about it.**

### What it is

`tests/e2e/src/config.ts` supplies a single `API_KEY` / `API_SECRET` belonging to **Administrator**, and every Layer 1 API test uses it. Privileged users are exempt from the access-control gates, so a test driving an endpoint as Administrator **cannot fail on a permission defect** — the gate it should be exercising never runs.

Several defects have shipped through that blind spot, and the pattern is always the same: a green suite, and a gate nothing touched.

### Why it is not hard

The hard part already exists. `tests/e2e/src/auth.ts` establishes per-role browser sessions for eight `e2e.*` users. Only the **API** layer is Administrator-only.

**To start:** either issue per-user API tokens for those eight users and add a `createApiBundleAsRole(role)` helper, or drive API calls through the per-role session cookies `auth.ts` already produces — the second reuses what is there.

### What covers the gap meanwhile, and what it does not

`deploy/test/deploy/group-11-financial-tail/*-verify-*.py` and `deploy/test/deploy/group-1-dispatch-operational/*-verify-*.py` run as real non-privileged users through `bench console`, assert on documents, and roll back. As of the A3 work that is **243 checks across 18 scripts**.

They are **not in CI**. They run when someone runs them, so they verify a deployment but do not protect against a later regression — and three times in this work an older harness was found encoding behaviour that had since changed, each time only because someone re-ran it by hand.

---

## 7. Test coverage — the paths not yet driven end to end

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

## 8. "Apply the credit" as a collection outcome

**Small, deferred by decision.**

A7 made every debt figure net of *untagged* credit, and made the episode description say so. But when a client has an overdue invoice **and** untagged credit, the right action is neither "chase" nor "ignore" — it is to **apply the credit**, and there is no way to record that as an outcome.

Today the collector reads the warning in the episode description and has to go allocate manually. That works, but the outcome they then record (`Paid`? `Disputed`?) misrepresents what happened.

**To start:** add an `Applied Credit` option to `Task.collection_outcome`, and an action on the task that allocates available credit against the oldest unpaid invoices — the same FIFO the payment-recording path already uses, minus the new-money step.

Measured on test when A7 landed: 3 of 6 customers with a financial position had gross and net disagreeing, one by **2,340,000 against a net of zero** — a client who would have been telephoned for money already in hand.

---

## 9. Housekeeping — orphan Task Access Policy records

**Trivial, no urgency, recorded so it is not rediscovered.**

Three `Task Access Policy` records survive for task kinds that were retired from the `task_kind` Select:

| Policy | State |
|---|---|
| `Dispatch picking / hand-off` | has a team user and a role |
| `Order accepting` | **no `default_team_user`, no roles** |
| `Account details` | **no `default_team_user`, no roles** |

The last two are the exact shape that broke Return Call before D3: a policy with no allowed roles makes the assignment role-check throw on every save of a task using it. Unreachable today because the kinds no longer exist in the Select, so this is tidy-up, not a defect — but if any of those three kinds is ever reintroduced, the policy must be repopulated first.

---

## 10. `Task-Packing Checkboxes.js`

**Note only, no work unless someone acts.**

Disabled, and still calls the packing endpoints the old way (by row position). D2 made the server refuse that. If it is ever re-enabled it must be updated to send row names first, or it will fail immediately.

---

## Cross-references — Group 11's open items

Not repeated here. See `group-11-dispatch-financial-tail-gap-analysis.md`.

| | |
|---|---|
| **A1** | Profit costed from a buying price list. **Now item 4 above** — it depends on purchasing/landed cost, not on anything in Group 11 |
| **A4** | **Now item 1b above**, bundled with cancel flow |
| **A5** | The e2e API suite runs entirely as Administrator, and privileged users are exempt from the access-control gates — so it is structurally incapable of catching that class of defect. Three have shipped through that blind spot |
| **A6** | Reporting and Telegram money notifications, deferred until the figures underneath were trustworthy. A7 already took the two debt reports and repaired the workspace's dead links |
| **A7** | **CLOSED** — one debt definition across all four consumers, verified 14/14. Item 7 above is its optional follow-on |

---

## If you want an order

1. **Batch/expiry** — the only item here with a regulatory edge, and the one that gets worse the longer it runs untracked.
2. **Cancel flow** — unblocks 77 stuck cases and gives the acceptance model the escape hatch it was designed around.
3. **Purchasing and landed cost** — every profit and margin figure in the system is wrong until this exists, and no amount of work on the reporting side can fix that.
4. **Assignment model** — low urgency, but the trap should be written into any handover before someone trips it.
5. **Remaining end-to-end paths** — cheap now the pattern exists.
6. **Stock cleanup** — test whenever; the production question deserves its own answer sooner.
