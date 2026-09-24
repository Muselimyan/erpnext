# Group 11 — Dispatch Financial Tail

> **Scope.** Everything after goods reach the client: consumption, invoicing, tender pricing, receivables, payment recording, debt collection, closure, profit, and the reports built on them.
>
> **Excludes.** Dispatch Case operational flow — task chain, packing, scanning, returns, stock movement, cancel flow. See `group-1-dispatch-case-lifecycle.md`.
>
> **How to read this.** §1 is how the system works now — the model you need in your head before changing anything. §2 is what is open. §3 is what will cost you a day if you do not know it. Nothing here describes how things used to be.

---

## 1. How it works now

### 1.1 Money lives in the ledger, not on the case

The Dispatch Case holds operational state and two convenience figures (`total_invoice_amount`, `outstanding_amount`). It does **not** hold a private copy of the receivables position. There is no stored prepaid amount, no advance-payments table, no running paid total.

Outstanding is read from `Sales Invoice.outstanding_amount`. An advance is a submitted, unallocated Payment Entry. A customer's debt is the GL, or the sum of unpaid invoices, depending on the question — see the caveat in §2.4.

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

### 1.5 Payments

Two routes, both producing **submitted** Payment Entries:

| Route | Task kind | Allocation |
|---|---|---|
| Against outstanding invoices | `Debt Collection` | FIFO by invoice posting date, oldest first |
| Money received with no invoice yet | `Payment Received` | None — a submitted **unallocated** advance |

The collection route refuses an amount larger than the total outstanding, and refuses entirely if there are no open invoices — it directs the user to the advance route instead. So overpayment never exists as an allocation remainder; it exists as unallocated credit.

### 1.6 Debt work is episodic

A `Debt Collection` task is **one attempt at collecting**, not a standing record of what is owed. `Scheduled-debt-collection-episodes` (daily) raises one when:

- an invoice is overdue by more than 3 days, or
- summed invoice outstanding exceeds `Customer.debt_threshold_amd`, or
- a previous episode's `collection_follow_up_date` has arrived, or
- a previous episode closed with no follow-up date and 7 days have passed.

**One open episode per customer.** Completing one requires `collection_outcome`; choosing `Promised` requires a future follow-up date, which is what schedules the next episode.

`Debt Alert` is a separate, Director-facing tripwire raised hourly against the GL. It must not record payments.

The `custom_debt_panel` field renders live data from the `task_debt_panel` API — unpaid invoices, unallocated credit, payment history. Nothing is stored on the task.

### 1.7 Closure is a ledger event

Nothing in the task flow closes a Dispatch Case. `Payment Entry-after-submit-debt-closure-check` fires when any customer Receive payment is submitted: if that customer now has **no** submitted invoice with outstanding above zero, every case of theirs in `Payment Pending` or `Invoice Pending` whose invoices are all settled is set to `Closed`, and **one** `Debt Closure Approval` task is raised for the Director with the profit figure attached.

The only other route to `Closed` is `task_close_case_nothing_to_invoice`.

### 1.8 Tender agreements

Priced at order entry (§1.2), enforced at invoice submit, consumed after submit, reversed on cancel:

| Stage | Script | Behaviour |
|---|---|---|
| Submit | `Sales-Invoice-before-submit-tender-validation` | Refuses if two active tenders match one item; refuses `qty > won − supplied`; refuses a rate that differs from `tender_price` to 2dp |
| After submit | `Sales-Invoice-after-submit-tender-update` | Increments `supplied_quantity`, recomputes `remaining_quantity`, writes audit rows into the invoice's `tender_fulfillments` |
| Cancel | `Sales-Invoice-on-cancel-tender-reversal` | Walks `tender_fulfillments` and gives the quantity back |
| Any save | `Tender-Agreement-before-save` | Recomputes `remaining_quantity`; derives `status` from `valid_from`/`valid_to` against today. `Closed` is sticky |

---

## 2. Open work

Ordered by consequence.

### A1 — Profit is costed from a price list — **moved to `deferred-workstreams.md`**

Not a swap, and not doable inside this group. Measured on test:

| | |
|---|---|
| Invoice lines with `incoming_rate` populated | **0 of 55** |
| Invoices with `update_stock = 1` | 0 of 8 |
| Invoice lines linked to a Delivery Note | 0 |
| Submitted Purchase Receipts | **0** |
| Submitted Landed Cost Vouchers | **0** |

The intended fix — cost from `Sales Invoice Item.incoming_rate` — **cannot work as stated.** Dispatch invoices carry `update_stock = 0` and no Delivery Note, so ERPNext has no stock transaction to derive a cost from and never populates the field.

The number it would supply is not landed cost anyway. With zero Purchase Receipts and zero Landed Cost Vouchers, valuation is simply whatever stock was received at. Doc 17's premise — cost = `(purchase price + all landed charges) / received quantity` — **describes a process that is not running.** Valuation and the Standard Buying price currently agree to a median of 0.0% precisely because neither carries any landed cost.

So the prerequisite is the purchasing side: Purchase Receipts and Landed Cost Vouchers actually being raised. That is doc 17's subject and a separate workstream.

**What remains worth doing here, and is small:** the current figure treats a missing buying price as **zero cost — 100% margin** — and only warns. Refusing to produce a figure it cannot compute beats publishing a confident wrong one.

Probe: `deploy/test/deploy/group-11-financial-tail/a1-probe-cost-basis.py` (read-only, re-runnable).

### A2 — Advance-allocation failure aborts the commit — **CLOSED, 9/9**

The allocation block no longer swallows its exception. If allocation fails, the commit fails, nothing is submitted, and the case stays retryable. Previously the invoice submitted at full value while the client's money sat unallocated, and the only trace was a log line.

Verified as a real accounting user, failure induced by a stale `unallocated_amount` causing a genuine ERPNext refusal:

```
1 commit succeeded                        PASS   ACC-SINV-2026-00166
2 case-tagged credit consumed first       PASS   this-case PE left 0.0
3 OTHER case's credit untouched           PASS   other-case PE left 5000.0
1 outstanding reduced by the advance      PASS   grand=12000 applied=5123 outstanding=6877
4 allocation failure raised an error      PASS   Debit and Credit not equal...
4 NO submitted invoice left behind        PASS   0 submitted invoice(s) found
5 case has no full-value invoice to chase PASS   submitted=[]
```

> **Writing a test in this area? Read the savepoint comment in `a2-verify-allocation-abort.py` first.** `bench console` has no request boundary, so a `submit()` that sets `docstatus = 1` and then fails its GL posting leaves that row visible for the rest of the session. A real HTTP request rolls it back. Without an explicit savepoint the harness reports a submitted invoice that cannot exist in production, and correct code looks broken.

### A3 — A consumed item priced at zero can be written off silently

The two invoice paths disagree about what "billable" means:

| Path | Test |
|---|---|
| `task_commit_invoice` | `used_qty > 0` and computed rate `> 0`, else **throw** |
| `task_close_case_nothing_to_invoice` | billable = `used_qty > 0` **and** `unit_price > 0` |

A row with `used_qty > 0` and `unit_price = 0` therefore cannot be invoiced — and also does not count as billable, so the case **can** be closed as nothing-to-invoice. Goods consumed by the client, no invoice, no record of a loss.

Server-side pricing makes new zero-price rows hard to create, which is what keeps this narrow. It is still an inconsistency between two guards that are meant to be complementary.

**Start at:** make both use the same definition of billable, and have the nothing-to-invoice path refuse a consumed row at any price.

### A4 — A paid invoice cannot be corrected

Cancel + Amend works while an invoice is unpaid. Once a payment is allocated it does not: ERPNext will not cancel an invoice with submitted payment references without unwinding them first. There is no credit note path and no refund path.

Low volume so far. VAT treatment may make a credit note legally required rather than merely convenient.

**Start at:** a credit note (`Sales Invoice` with `is_return = 1`) plus a refund Payment Entry, behind Director approval. Decide whether it is task-driven like the rest of the flow or an Accounting-only action on the native form. Interacts with the cancel flow (Group 1 D11).

### A5 — The test harness cannot see permission defects

`tests/e2e/src/config.ts` supplies a single `API_KEY`/`API_SECRET` belonging to **Administrator**, and every Layer 1 API test uses it. Privileged users are exempt from the access-control gates, so that suite is **structurally incapable** of detecting this class of defect — and several have shipped through the blind spot.

Per-role browser sessions already exist (`auth.ts`, eight `e2e.*` users). Only the API layer is Administrator-only.

**Start at:** issue per-user API tokens for the eight role users and add a `createApiBundleAsRole(role)` helper, or drive API calls through the per-role session cookies `auth.ts` already produces.

Working reference in the meantime: `deploy/test/deploy/group-11-financial-tail/w*-verify-*.py` and `deploy/test/deploy/group-1-dispatch-operational/*-verify-*.py` run as real non-privileged users via `bench console` and roll back. They are not in CI.

### A6 — Reporting

Three defects, all in deployed configuration rather than code.

**Required reports that do not exist.** Doc 15a claims all 26 required reports exist. Four do not:

- `RPT — KPI — Daily Dashboard`
- `RPT — KPI — Weekly Dashboard`
- `RPT — KPI — Monthly Income and Profit`
- `RPT — Pricing — Sales Orders With Manual Rate Edits`

The `Management - KPI Dashboard` workspace exists and contains **no KPI reports** — its three shortcuts are Item Sort and Classify, Item Nomenclature and Prices, and Returns Refund Queue.

**Nothing reports on profit.** No report reads `Task.custom_case_profit` or computes margin. Fix A1 first; a report over a wrong number is worse than no report.

**Duplicate pairs**, same subject under two naming conventions:

| | |
|---|---|
| `RPT - Dispatch Case Aging` | `RPT — Dispatch Cases — Aging (Open)` |
| `RPT - Unallocated Customer Advances` | `RPT — Receivables — Unallocated Advances` |
| `RPT - Clients Exceeding Debt Threshold` | `RPT — Risk — Debt Threshold Exceeded` |
| `RPT — Stock — Delivery In-Transit` | `RPT — Stock — Delivery In-Transit - Inmed` |
| `RPT — Stock — Return Pickup In-Transit` | `RPT — Stock — Return Pickup In-Transit - Inmed` |
| `RPT — Stock — Returns` | `RPT — Stock — Returns - Inmed` |

**Dangling and stale shortcuts** in `Ops — Reporting Pack`:

- "Prepaid Orders Awaiting Delivery" → `RPT — Ops — Prepaid Orders Awaiting Delivery`. The report is named `RPT - Prepaid Orders Awaiting Delivery`. Broken.
- "Manual Rate Edits" → a report that does not exist.
- "VIEW: Distribute Payment Tasks" — in **both** `Ops — Reporting Pack` and `Dispatch - Task Queues`. That task kind is retired.

**Telegram money notifications are disabled.** Both scripts. Invoice submitted, payment received, threshold breached — none of them notify.

**Do A1 before any of this.**

### A7 — The two debt schedulers measure debt differently

| | Basis | Raises |
|---|---|---|
| `Scheduled-debt-collection` (hourly) | **GL net receivable** — `sum(debit − credit)` on GL Entry | `Debt Alert` |
| `Scheduled-debt-collection-episodes` (daily) | **Sum of invoice `outstanding_amount`** | `Debt Collection` |

GL net receivable is reduced by unallocated credit; summed invoice outstanding is not. So a customer holding a large advance against unpaid invoices is "not in debt" to one scheduler and "in debt" to the other, and can receive a collection episode while the Director sees no alert, or the reverse.

Both readings are defensible. Having two is not.

**Start at:** decide which question each task kind is answering, and make both use that basis. The debt panel already computes `net_receivable = outstanding − unallocated_credit`, which is the third definition in play.

### A8 — Debt Alert has two defects the other schedulers do not

1. **Cancelled alerts are resurrected.** The dedupe filter is `status != "Completed"`, so a **Cancelled** Debt Alert counts as existing: the scheduler updates its figures and reassigns it rather than raising a fresh one. Everything else in the flow uses `not in ["Completed", "Cancelled"]`.
2. **`custom_assigned_to` is never set.** It writes `_assign` and creates a ToDo, but not the field AGENTS.md designates the single source of truth for assignment. Anything reading `custom_assigned_to` sees these tasks as unassigned.

Both are one-line fixes in `Scheduled-debt-collection.py`.

### A9 — Smaller items

| | |
|---|---|
| **A failed submit strands a draft invoice** | If `si.submit()` throws — the tender validator is the likely cause — the inserted draft remains and still trips the idempotency guard. The user cannot retry until someone cancels or deletes it by hand |
| **Add-product picks a tender arbitrarily** | `task_add_dispatch_product` loops all active tenders and the **last** match wins, silently. The invoice validator refuses when two match. So order entry succeeds and invoicing then deadlocks — the failure surfaces at the wrong end of the flow |
| **Cancel can be blocked by tender data** | `Sales-Invoice-on-cancel-tender-reversal` throws if a tender item row has been deleted, making the invoice un-cancellable |
| **Settlement with no matching case raises no approval** | If a payment clears the account but closes no case — all already closed, or none in a qualifying status — no Debt Closure Approval is raised. Deliberate, but it means some settlements get no Director review |
| **N+1 in the debt panel** | `task_debt_panel` issues one `Payment Entry Reference` query per payment row, up to 50 per call |

---

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

### Symptoms a user can report

| Symptom | Item |
|---|---|
| "Profit on this case looks far too high" | A1 |
| "The client paid in advance but the invoice shows the full amount" | A2 |
| "I cannot create the invoice and I cannot close the case either" | A9, stranded draft |
| "This order went through but now the invoice is refused" | A9, arbitrary tender pick |
| "We over-billed a client who has already paid and I cannot fix it" | A4 |
| "The Director sees no alert but Finance is chasing this customer" | A7 |
| "Which of these two debt reports is the right one?" | A6 |

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
| G9 | Open — **A1** |
| G17 | Open — **A6** |
| R13 | Open — **A4** |

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
| Deploy and verification | `deploy/test/deploy/group-11-financial-tail/` — one `wN-*.ps1` per workstream, each with a `wN-verify-*.py` |
| Architectural rules | `AGENTS.md` |
| Flow specification | `docs/16-unified-dispatch-flow.md` §4.3, §6.9–6.12 |
| Cost and valuation | `docs/17-purchase-cost-and-valuation.md` — the authority A1 must satisfy |
| Pricing architecture | `docs/09-standard-selling-flow.md` §6.1, §7 |
| Go-live testing | `docs/14-go-live-checklist.md` §9.1 — **run as the owning role, not as Administrator** |

### Two documents disagree with the code

- **`docs/16` §8** still says advance Payment Entries are "left as draft for Accounting review". §6.12 of the same document, and the code, say submitted. §8 is wrong.
- **`docs/15a`** claims all 26 required reports exist. Four do not — see A6.
