# Group 11 — Dispatch Financial Tail

> **Scope.** Everything after goods reach the client: consumption, invoicing, tender pricing, receivables, payment recording, debt collection, closure, profit, and the reports built on them.
>
> **Excludes.** Dispatch Case operational flow — task chain, packing, scanning, returns, stock movement, cancel flow. See `group-1-dispatch-case-lifecycle.md`.
>
> **How to read this.** §1 is how the system works now — the model you need in your head before changing anything. §2 records that **nothing in this group is open**, and where the items that moved have gone. §3 is what will cost you a day if you do not know it.
>
> **State.** A1–A9 are all closed or moved. 243 checks pass across 18 verification scripts covering this group and Group 1. The two things that would most change the picture are both deferred and both outside this group: profit has no trustworthy cost basis until purchasing runs (item 4), and a paid invoice still cannot be corrected (item 1b).

---

## 1. How it works now

### 1.1 Money lives in the ledger, not on the case

The Dispatch Case holds operational state and two convenience figures (`total_invoice_amount`, `outstanding_amount`). It does **not** hold a private copy of the receivables position. There is no stored prepaid amount, no advance-payments table, no running paid total.

Outstanding is read from `Sales Invoice.outstanding_amount`. An advance is a submitted, unallocated Payment Entry.

**A customer's debt has exactly one definition**, used by every consumer — the two schedulers, the collector's panel and the Director's threshold report:

```
net receivable = unpaid submitted invoices − UNTAGGED unallocated credit
```

Credit carrying a `dispatch_case` is earmarked and does **not** offset anything else, because `task_commit_invoice` will not spend it elsewhere either (§1.4). If you add a sixth consumer, use this formula — RestrictedPython forces it to be copied, so each copy carries a `keep in sync` header and the verification asserts they agree.

`Dispatch Case.sales_invoice` exists but is a **pointer for humans only**. Every piece of logic resolves the invoice by querying `Sales Invoice.dispatch_case`, because that link survives Cancel + Amend and the pointer does not.

### 1.2 Pricing is resolved on the server, at order entry

`task_add_dispatch_product` decides the price. The client cannot supply one — whatever it sends is discarded.

| Order | Source |
|---|---|
| 1 | Active `Tender Agreement` for this hospital, matching item, `tender_price > 0` |
| 2 | `Item Price` on `Standard Selling` **for this customer** |
| 3 | `Item Price` on `Standard Selling`, no customer |
| 4 | Refuse — the item cannot be ordered |

A tender-priced item **cannot be discounted**; the endpoint refuses. `discount_pct` on any other item is the sole deviation route and triggers Director approval.

The same chain is used by `task_apply_template`, which **refuses the whole template** if any line is unpriced — a kit applied half-priced is worse than one refused.

**No item priced at zero may participate in the flow.** The quantity that matters everywhere is the effective rate:

```
effective_rate = unit_price × (1 − discount_pct / 100)
```

- `0 ≤ discount_pct < 100`, enforced on add and on update. 100% is not a discount but a giveaway, and it produced a line that could be neither invoiced nor written off.
- `Dispatch-Case-before-submit` refuses any line whose effective rate is zero. **This is the backstop and the only price gate that cannot be stepped around** — the order-entry gate is skipped once a case is submitted, and Discount Approval re-submits without re-checking.
- `unit_price` and `discount_pct` are **not editable after submit**. Nothing in the flow writes them post-submit; both product endpoints are hard-gated to `docstatus = 0`.
- Both invoice paths — commit and nothing-to-invoice — test the effective rate, so they cannot disagree about what is billable.

Two client scripts that wrote prices in the browser (`Dispatch Case-Products Button`, `Dispatch Case-Template Auto Fill`) are **disabled**. They are not to be revived without routing through the server: resolving prices in JavaScript duplicates business logic, and a second implementation of pricing is how the two definitions of "billable" drifted apart in the first place.

### 1.3 Invoicing is one deliberate action

No draft invoice is ever auto-created. The Invoice Preparation task offers two actions, both requiring the accepter:

**`task_commit_invoice`** builds and submits in one step:

- Lines are `case_items` rows with `used_qty > 0`, at `unit_price × (1 − discount_pct/100)`. Lost/damaged is **not** billed here.
- Refuses if any used row prices to zero, and refuses if nothing is billable.
- Sets `hospital` and `doctor_name` from the Customer (`hospital = customer` when `client_kind = Hospital`, else the customer's `hospital`).
- Applies `Armenia Tax - Inmed` and `Net 30`, **and expands the tax template's rows explicitly** — setting `taxes_and_charges` alone does not populate them.
- Consumes unallocated customer credit, then submits.

**`task_close_case_nothing_to_invoice`** is the alternative when the client returned everything unused. Requires a reason, refuses if anything is billable or any invoice exists, appends the reason to case notes, sets the case `Closed`.

**Idempotency.** At most one non-cancelled Sales Invoice per case *with `source_task` empty*. That empty field is the convention meaning "the used-items invoice". A lost/damaged invoice raised from a Write-off Approval stamps its task in `source_task` and is therefore invisible to the guard, so both can legitimately exist. **Any new code that creates an invoice must respect this convention or it will consume the used-items slot.**

### 1.4 Advance credit is allocated by intent, not by age alone

Payment Entries carry `dispatch_case` (what the money was for) and `source_task` (where it was recorded). At commit time the invoice consumes credit in this order:

1. credit tagged to **this** case
2. untagged general credit, oldest first

Credit tagged to a **different** case is deliberately left alone. ERPNext's own `set_advances()` is not used, because it pulls every unallocated advance the customer holds and would silently spend case A's money on case B's invoice.

**If allocation fails, the whole commit fails.** No invoice is submitted and the case stays retryable. The alternative — carrying on and billing the full amount — leaves a client who has already paid being chased for the money, which is worse than no invoice because it looks finished.

This earmarking rule is also what the debt definition in §1.1 follows. The two must not diverge: allocation refusing to spend tagged credit while debt measurement counts it as an offset is how risk gets under-reported.

### 1.5 Payments

Two routes, both producing **submitted** Payment Entries:

| Route | Task kind | Allocation |
|---|---|---|
| Against outstanding invoices | `Debt Collection` | FIFO by invoice posting date, oldest first |
| Money received with no invoice yet | `Payment Received` | None — a submitted **unallocated** advance |

The collection route refuses an amount larger than the total outstanding, and refuses entirely if there are no open invoices — it directs the user to the advance route instead. So overpayment never exists as an allocation remainder; it exists as unallocated credit.

### 1.6 Debt work is episodic

A `Debt Collection` task is **one attempt at collecting**, not a standing record of what is owed. `Scheduled-debt-collection-episodes` (daily) raises one when:

- an invoice is overdue by more than 3 days — **gross**, see below, or
- **net** receivable (§1.1) exceeds `Customer.debt_threshold_amd`, or
- a previous episode's `collection_follow_up_date` has arrived, or
- a previous episode closed with no follow-up date and 7 days have passed.

**The overdue trigger is deliberately gross.** An invoice 40 days past due deserves attention even when credit elsewhere covers it. But in that case telephoning is the wrong first action — the money is already in hand and wants allocating — so the episode description leads with how much untagged credit the client is holding. There is no "applied the credit" outcome yet; that is `deferred-workstreams.md` item 8.

**One open episode per customer.** Completing one requires `collection_outcome`; choosing `Promised` requires a future follow-up date, which is what schedules the next episode.

`Debt Alert` is a separate, Director-facing tripwire raised hourly on the same net figure. It must not record payments.

The `custom_debt_panel` field renders live data from the `task_debt_panel` API — unpaid invoices, unallocated credit, payment history. Nothing is stored on the task.

### 1.7 Closure is a ledger event

Nothing in the task flow closes a Dispatch Case. `Payment Entry-after-submit-debt-closure-check` fires when any customer Receive payment is submitted: if that customer now has **no** submitted invoice with outstanding above zero, every case of theirs in `Payment Pending` or `Invoice Pending` whose invoices are all settled is set to `Closed`, and **one** `Debt Closure Approval` task is raised for the Director with the profit figure attached.

**A settlement always raises the approval, even when it closes no case** — the account reaching zero is what warrants Director review, and the approval is also where profit is recorded. When nothing closed, the description says so in words rather than showing a profit figure; a stored zero cannot express "not computed", so the text has to.

The only other route to `Closed` is `task_close_case_nothing_to_invoice`.

### 1.8 Tender agreements

Priced at order entry (§1.2), enforced at invoice submit, consumed after submit, reversed on cancel:

| Stage | Script | Behaviour |
|---|---|---|
| Order entry | `task_add_dispatch_product` / `task_update_dispatch_product` | **Refuses two active tenders on one item**, naming both, before the order exists. Previously the last one scanned won, non-deterministically, and the clash only surfaced at invoice submit |
| Submit | `Sales-Invoice-before-submit-tender-validation` | Refuses if two active tenders match one item; refuses `qty > won − supplied`; refuses a rate that differs from `tender_price` to 2dp |
| After submit | `Sales-Invoice-after-submit-tender-update` | Increments `supplied_quantity`, recomputes `remaining_quantity`, writes audit rows into the invoice's `tender_fulfillments` |
| Cancel | `Sales-Invoice-on-cancel-tender-reversal` | Walks `tender_fulfillments` and gives the quantity back. **Never throws** — it runs in After Cancel, where a throw rolls back the cancellation, so a missing tender or deleted item row is logged and skipped rather than making the invoice uncancellable |
| Any save | `Tender-Agreement-before-save` | Recomputes `remaining_quantity`; derives `status` from `valid_from`/`valid_to` against today. `Closed` is sticky |

---

## 2. Open work

**Nothing in this group is open.** A1–A9 are closed or have moved to the workstream that owns them. The IDs are kept because other audits cite them.

| ID | Position |
|---|---|
| **A1** | Moved — `deferred-workstreams.md` item 4 (purchasing and landed cost) |
| **A2** | **Closed**, 9/9 — allocation failure aborts the commit |
| **A3** | **Closed**, 20/20 — no item priced at zero can enter the flow |
| **A4** | Moved — `deferred-workstreams.md` item 1b (bundled with cancel flow) |
| **A5** | Moved — `deferred-workstreams.md` item 6 (API harness runs as Administrator) |
| **A6** | Moved — `group-10-reports-workspaces-config-audit.md` (reports and workspaces) |
| **A7** | **Closed**, 14/14 — one definition of debt |
| **A8** | **Closed**, 13/13 — Debt Alert dedupe and assignment |
| **A9** | **Closed**, 19/19 — five smaller defects |

The behaviour that resulted is described in §1, which is where to read it. What follows is the short version of what changed and why, so the reasoning survives without having to read the commits.

**A2 — advance-allocation failure aborts the commit.** The block used to swallow its exception, so a failed allocation submitted the invoice at full value while the client's money sat unallocated — a client who had already paid, chased for the full amount, with a log line as the only trace. Verification also pins the allocation *order*.

**A3 — no zero-priced item in the flow.** The original finding was a disagreement between two invoice paths; it turned out to be the last of **nine** ways a zero price got in or survived. Rows could be created with no price by a template applier and two client scripts — one of which read `Item.standard_rate`, a field populated on no items, so it produced a zero-priced row every time it was used. `discount_pct` was unbounded. Nothing checked price at submit, and the order-entry gate checked `unit_price` rather than the effective rate, so a line at 1000 with a 100% discount passed. Prices could be zeroed *after* submit. And the two consumers disagreed in both directions: a zero-priced consumed row closed with no invoice (silent revenue loss), while a 100%-discount row was refused by both paths (an unfinishable task).

> Also closed here: the last validation bypass. `ignore_validate_update_after_submit` suppressed Frappe's submitted-document check on **every** field at four endpoints. Checking what those endpoints actually write settled it — nine of ten fields were already `allow_on_submit` and exactly one was not, so the flag was covering for `lost_damaged_presence`, which was corrected instead. `ignore_mandatory` in `task_create_dispatch_case` was reviewed and **kept**: it creates the empty shell an order is built into, often before the customer is known.

**A7 — one definition of debt.** Five consumers computed it five ways, disagreeing on gross-vs-net and on which ledger. All now use the formula in §1.1. Measured before changing anything: gross and net disagreed for 3 of 6 customers with a position, one showing gross **2,340,000** against a net of **zero**. The earmarked-credit half of the rule changes no verdict today and is **preventive, not remedial** — said plainly rather than oversold.

**A8 — Debt Alert.** A cancelled alert was treated as open, so the next hourly run refilled and reassigned it, silently undoing the Director's cancellation. And `custom_assigned_to` was never set, so every alert read as unassigned to anything that asks the application who owns it.

**A9 — five smaller defects, two of which were one chain.** The tender loop had no `break` and no `order_by`, so with two active tenders the last scanned won, non-deterministically; the collision surfaced only at invoice submit, and that throw stranded a draft the idempotency guard then matched, telling the user to cancel something that cannot be cancelled. Also: the tender reversal could make an invoice permanently uncancellable by throwing inside After Cancel; a settlement that closed no case raised no Director review at all; and the debt panel issued up to 51 queries per load.

## 3. Traps — read before changing this area

Not bugs. Properties that cost a day each if you do not know them.

| | |
|---|---|
| **`Before Save` never fires for submitted documents** | Frappe runs `before_save` only when `_action == "save"`; a submitted save is `update_after_submit`. A Dispatch Case is submitted for its whole working life, so a guard on `Before Save` misses almost everything. Hence **two** DC access-control scripts, a draft one and a submitted twin. **Change one, change the other** |
| **`SYSTEM_FIELDS` is default-deny** | The access-control gates allow a save touching only listed fields. Add a field that server code writes and forget to register it, and housekeeping fails loudly — intended. When a field stops having a legitimate system writer, remove it, or you have left a hole |
| **Saving a Server Script does not prove it runs** | The compile check does not cover the full RestrictedPython policy. A script can deploy cleanly and throw on first execution. For a Scheduler Event that means it looks deployed and silently never runs. Always execute what you deploy |
| **Augmented assignment to a subscript is forbidden** | `d[k] += 1` and `d[k]["x"] += 1` both fail under RestrictedPython. Read into a local, modify, write back |
| **Two `before_save` scripts have no defined order** | Do not let one set a field another gates on. Make each correct independently |
| **Deploy scripts must handle UTF-8 both ways** | PowerShell 5.1 reads BOM-less files as ANSI and mis-decodes responses as Latin-1 — corrupting script bodies on upload and producing false `DIFFERS` in Check mode. `group-11-financial-tail/*.ps1` and `group-1-dispatch-operational/*.ps1` are correct; **everything under `deploy/test/scripts/` still has both bugs** |
| **Setting `taxes_and_charges` does not create the tax rows** | The template has to be expanded manually. Miss it and the invoice submits at net total with no VAT and no error |
| **An empty `source_task` on a Sales Invoice is meaningful** | It means "the used-items invoice for this case", of which there may be one. Any new invoice-creating path must stamp `source_task` or it will consume that slot and break idempotency |
| **`Dispatch Case.sales_invoice` is not authoritative** | It goes stale on Cancel + Amend, because the amendment is a new document. Resolve invoices by querying `Sales Invoice.dispatch_case` |
| **Order entry refuses unpriced items** | Correct, but a missing `Item Price` now blocks work rather than silently producing a zero-value invoice |
| **The cancel flow has no mechanism yet** | Bulk-cancelling tasks needs to write `status` on tasks the user does not own, and `status` cannot go on `SYSTEM_FIELDS` because it is the primary user-editable transition. Group 1 D11 |
| **The debt formula exists in four places** | RestrictedPython has no module system. Each copy carries a `keep in sync` header; `a7-verify-one-debt-definition.py` asserts they agree. Change one, change all four |
| **A workspace cannot be saved while any Link is dead** | Frappe validates every row, so one shortcut pointing at a deleted report blocks *unrelated* edits to that workspace. This is why dangling shortcuts are blocking rather than cosmetic |
| **`bench console` has no request boundary** | A `submit()` that sets `docstatus = 1` then fails its GL posting leaves the row visible for the rest of the session; a real request rolls it back. Use a savepoint when testing failure paths, or correct code looks broken |
| **Non-ASCII in a double-quoted string in a `.ps1` is a syntax error** | PowerShell 5.1 reads BOM-less files as ANSI. Several report and workspace names here contain em-dashes; build them with `[char]0x2014` |

The last three are general and are written up in full in `AGENTS.md`.

### Symptoms a user can report

Only two symptoms in this area still have an open cause, and both are deferred:

| Symptom | Item |
|---|---|
| "Profit on this case looks far too high" | A1 — `deferred-workstreams.md` item 4. Cost comes from a buying price list, and a missing price counts as zero cost |
| "We over-billed a client who has already paid and I cannot fix it" | A4 — `deferred-workstreams.md` item 1b. No credit note path exists |

Everything below **should no longer occur.** Listed so that a recurrence is recognised as a regression rather than filed as a known issue:

| Symptom | Was |
|---|---|
| "The client paid in advance but the invoice shows the full amount" | A2 — allocation failure is now fatal to the commit |
| "The client returned goods, we consumed them, and billed nothing" | A3 — a zero-priced row cannot exist, and nothing-to-invoice tests the effective rate |
| "This order went through but now the invoice is refused" | A9 — duplicate tenders are refused at order entry |
| "I cannot create the invoice and I cannot close the case either" | A9 — a stranded draft is cleared and the commit retried |
| "The Director sees no alert but Finance is chasing this customer" | A7 — one definition, asserted to agree across all consumers |
| "A cancelled Debt Alert keeps coming back" | A8 — dedupe now excludes Cancelled |
| "This Debt Alert looks assigned to nobody" | A8 — `custom_assigned_to` is set |
| "I cannot cancel this invoice and the error is about a tender" | A9 — the reversal no longer throws |
| "The client settled up and nobody reviewed it" | A9 — a settlement always raises the approval |

---

## 4. Go-live prerequisites

Data and configuration, not code.

1. **Close or cancel every legacy open `Debt Collection` task.** One open episode per customer is the rule, so a leftover task suppresses real collection for that customer indefinitely.
2. **Resolve legacy open `Debt Closure Approval` tasks.** They may assert closures that never happened.
3. **Submit or cancel draft customer Payment Entries.** A draft produces no GL entries, so the money is invisible to everything here.
4. **Triage cases stuck in `Invoice Pending`.** Each needs an invoice committed or an explicit nothing-to-invoice close.
5. **Populate `Item Price` on `Standard Selling` for every orderable item.** Order entry now refuses an unpriced item.
6. **Reconcile the stock data.** 372 Stock Entries carry warehouse-less rows — 172 posted nothing, **200 posted one-sidedly and are real ledger damage**. 13 items sit at negative stock in `Main - Inmed`, and with `allow_negative_stock` now off, any operation touching them fails. Group 1 D10. **Whether production carries equivalents has not been examined** — the defect was not test-specific.
7. **Verify the Armenia VAT template and Net 30 terms exist and are correct.** Both are looked up by name and skipped silently if absent.

---

## 5. Finding-ID map

Other audits cite these. Current position only.

| ID | Where it stands |
|---|---|
| C1, C2, G1, G2, G3, G4, G5, G6, G8, G10, G11, G12, G13, G14, G15, G16 | Closed |
| C3, C4 | Group 2 — split Delivery photo rule, module-level `get_doc_before_save()` |
| G7 | Closed by Group 1 D1 |
| G9 | **A1** — deferred, `deferred-workstreams.md` item 4 |
| G17 | **A6** — moved to `group-10-reports-workspaces-config-audit.md` |
| R13 | **A4** — deferred, `deferred-workstreams.md` item 1b |

---

## 6. Where the implementation lives

| | |
|---|---|
| Invoicing | `task_commit_invoice.py`, `task_close_case_nothing_to_invoice.py` |
| Pricing | `task_add_dispatch_product.py` |
| Payments | `Task-before-save-payment-recording.py`, `Task-after-save-advance-payment.py` |
| Closure and profit | `Payment Entry-after-submit-debt-closure-check.py` |
| Debt scheduling | `Scheduled-debt-collection-episodes.py` (daily), `Scheduled-debt-collection.py` (hourly) |
| Debt panel | `task_debt_panel.py`, `Task-Debt-Panel.js` |
| Tenders | `Sales-Invoice-before-submit-tender-validation.py`, `-after-submit-tender-update.py`, `-on-cancel-tender-reversal.py`, `Tender-Agreement-before-save.py` |
| The one debt definition | Duplicated in `Scheduled-debt-collection.py` (canonical, with the long comment), `Scheduled-debt-collection-episodes.py`, `task_debt_panel.py`, and the `RPT - Clients Exceeding Debt Threshold` SQL. **Change one, change all four**, then re-run `a7-verify-one-debt-definition.py`, which asserts they agree |
| Deploy and verification | `deploy/test/deploy/group-11-financial-tail/` — one `wN-*.ps1` per workstream with a paired `wN-verify-*.py`, plus `a2-*` and `a7-*`. The `a1-probe-*` and `a7-probe-*` scripts are read-only and re-runnable |
| Architectural rules | `AGENTS.md` — including the console-savepoint, `.ps1` non-ASCII and workspace dead-link traps this group discovered |
| Flow specification | `docs/16-unified-dispatch-flow.md` §4.3, §6.9–6.12 |
| Cost and valuation | `docs/17-purchase-cost-and-valuation.md` — the authority A1 must satisfy |
| Pricing architecture | `docs/09-standard-selling-flow.md` §6.1, §7 |
| Go-live testing | `docs/14-go-live-checklist.md` §9.1 — **run as the owning role, not as Administrator** |

### Two documents disagree with the code

- **`docs/16` §8** still says advance Payment Entries are "left as draft for Accounting review". §6.12 of the same document, and the code, say submitted. §8 is wrong.
- **`docs/15a`** claims all 26 required reports exist. Four do not — see A6.
