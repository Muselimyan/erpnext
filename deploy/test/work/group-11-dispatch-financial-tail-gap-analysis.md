# Group 11 — Dispatch Financial Tail

> **Scope.** Everything after goods physically reach the client: consumption posting, Sales Invoice creation, receivables, payment recording, debt closure, profit, and the reports built on them.
>
> **Excludes.** Dispatch Case operational flow — task chain, packing, scanning, returns handling, cancel flow. See **Group 1**.
>
> **State.** The rebuild is done and deployed to test (W1–W11 plus A3, 80 automated checks). This document now covers only **what is still open** and **what will bite you**.
>
> **A2 was closed by Group 1** (D1 + D9, 2026-09-22/23), not by work in this group — stock validation is restored and negative stock is blocked. That unblocks **A1**, which is now the next item here. See `group-1-dispatch-case-lifecycle.md` and `deferred-workstreams.md`.
>
> The original analysis — 18 findings with evidence, the R1–R14 recommendations, the priority bands — has been removed rather than annotated, because a document that is nine-tenths closed work is not readable. It is in git history: `git show 07645d6 -- deploy/test/work/group-11-dispatch-financial-tail-gap-analysis.md`. §4 keeps the finding-ID map, since other audits cite those IDs.

---

## 1. Open work

Ordered by consequence. Each entry names the file to start in.

**Dependency was A2 → A1 → A6.** `incoming_rate` is meaningless until stock is
actually valued, and reports built on a wrong profit basis only present the
error more convincingly.

**A2 closed on 2026-09-22 (Group 1 D1 + D9), so A1 is now unblocked** — transfers
carry valuation and consumption posts real COGS, which is exactly the
precondition `incoming_rate` needed. **A1 is the next thing to do in this
group.** A6 still waits on A1.

### A1 — Profit is computed from a list price, not from cost

`Payment Entry-after-submit-debt-closure-check.py` values cost as `Item Price`
on the `Standard Buying` list. Doc 17 makes the **landed-cost valuation rate**
authoritative, and ERPNext already exposes the right number per line as
`Sales Invoice Item.incoming_rate`.

Three distinct problems:

- Freight, duty and import tax are absent entirely, so every profit figure is wrong by whatever landed cost adds to list price.
- The `or 0` fallback means a line with **no** buying price is treated as free, yielding 100% margin. The task raises a warning; it does not block the write. On test, 38% of invoice lines had no `Standard Buying` price.
- No docstatus check — the old implementation wrote `profit` onto Draft cases with no invoice at all.

**Start at:** the profit block in
`deploy/test/work/server/Payment Entry-after-submit-debt-closure-check.py`.
Swap the `Item Price` lookup for `incoming_rate`, drop the silent zero-cost
fallback in favour of refusing, and compare the result against ERPNext's own
Gross Profit report for the same invoice before trusting it.

### A2 — Stock validation bypassed — **CLOSED, Group 1 D1 + D9 (2026-09-22/23)**

Cut rather than annotated, per this document's own rule. Full analysis in git
history: `git show 07645d6` and `git show e253226`.

**What was wrong.** `create_se` submitted every Stock Entry with
`ignore_validate`, `ignore_stock_validation` and `allow_zero_valuation_rate`.
`ignore_validate` skips `Stock Entry.validate()` wholesale — including
`set_basic_rate` — so every Material Transfer arrived valued at **zero**.
Valuation died at the first hop (`Main → Delivery In-Transit`), consumption
posted zero COGS, and the restock pushed zero-valued stock back into Main,
dragging its moving average down on every returns cycle. That is why A2 was the
root cause of A1: nothing ever forced the valuation data to become correct.

**What was done.** The `strict` parameter and all three bypasses are gone; all
ten call sites are validated. `client_location_warehouse` is now required on
every order rather than only when returns are expected — it was never a returns
field, it is the delivery destination and the consumption source.
`Stock Settings.allow_negative_stock` is off (D9), which was the remaining
residue: removing the bypass restored ERPNext's check but could not overrule a
setting declaring the thing it checks for permitted.

**Verified.** A full returns cycle now leaves Main's valuation untouched
(`6.0 → 6.0`), transfers preserve value (`out 6.0 → in 6.0`), overdraws are
refused, and the end-to-end chain conserves stock exactly: `Main` falls by
`used + lost` and every transit warehouse returns to its starting balance.

**Deliberately not done — read this before trusting historical numbers.** No
data migration. Test data is disposable by decision, so the pre-existing damage
was left in place:

- **372** submitted Stock Entries carry warehouse-less rows, not the 18 this
  document originally estimated. 172 are inert Material Issues that posted
  nothing; **200 are one-sided Material Transfers that did post** — stock created
  out of nowhere or destroyed into it. That second group is real ledger damage,
  not dead paperwork.
- 13 items remain at negative stock in `Main - Inmed` (−415). With
  `allow_negative_stock` now off, **any operation touching those 13 will fail.**
  That is intended: it is how they get noticed.

Tracked as Group 1 D10. The open question that matters more than the cleanup:
the defect that produced those 200 one-sided transfers ran everywhere, not only
on test, and **production has not been examined.**

### A4 — A paid invoice cannot be corrected in-system

Cancel + Amend is the documented remedy and works while an invoice is unpaid.
Once a payment is allocated it does not: ERPNext will not cancel an invoice with
submitted payment references without unwinding them first. There is no credit
note path and no refund path.

This has not bitten yet because volume is low, but VAT treatment may make a
credit note legally required rather than merely convenient.

**Start at:** a credit note (`Sales Invoice` with `is_return = 1`) plus a refund
Payment Entry, behind Director approval. Decide whether it is task-driven like
the rest of the flow, or an Accounting-only action on the native form.

### A5 — The test harness cannot see permission defects

`tests/e2e/src/config.ts` supplies a single `API_KEY`/`API_SECRET` belonging to
**Administrator**, and every Layer 1 API test uses it. Privileged users are
exempt from the access-control gates, so that suite is **structurally incapable**
of detecting the class of defect that shipped three times in this area — C1, the
admin-completion rule, and the `Ops - Finance` permission gap.

Per-role browser sessions already exist (`auth.ts`, eight `e2e.*` users in
config). Only the API layer is Administrator-only.

**Start at:** issue per-user API tokens for the eight role users and add a
`createApiBundleAsRole(role)` helper, or drive API calls through the per-role
session cookies `auth.ts` already produces. Until then, any permission test must
be a UI test via `asRole('accounting')`.

The 58 checks in `deploy/test/deploy/group-11-financial-tail/w*-verify-*.py`
already cover this ground as real non-privileged users via `bench console`, and
roll back. They are not in CI.

### A6 — Reporting and notifications

Deferred until the figures underneath were trustworthy. Group 10 holds the
detail: duplicate report pairs, broken shortcuts, dead task VIEWs, unbuilt KPI
reports. Telegram money notifications — invoice submitted, payment received,
threshold breached — are still disabled.

Do **A1** first.

---

## 2. Traps — read before changing this area

Not bugs. Properties of the system that cost a day each if you do not know them.
All are also in `AGENTS.md`.

| | |
|---|---|
| **`Before Save` never fires for submitted documents** | Frappe runs `before_save` only when `_action == "save"`; a submitted save is `update_after_submit`. A Dispatch Case is submitted for its whole working life, so a guard on `Before Save` misses almost everything. Hence **two** DC access-control scripts — a draft one and a submitted twin. **Change one, change the other.** |
| **`SYSTEM_FIELDS` is default-deny** | The access-control gates allow a save touching only fields on their `SYSTEM_FIELDS` list. Add a field that server code writes and forget to register it, and housekeeping starts failing — loudly, which is intended. Conversely, when a field stops having a legitimate system writer, remove it, or you have left a hole. |
| **Saving a Server Script does not prove it runs** | Frappe's compile check catches syntax errors, not the full RestrictedPython policy. A script can deploy cleanly and throw on first execution. For a Scheduler Event that means it looks deployed and silently never runs — and any test asserting "nothing happened" passes. Always execute what you deploy. |
| **Augmented assignment to a subscript is forbidden** | `d[k] += 1` and `d[k]["x"] += 1` both fail under RestrictedPython. Read into a local, modify, write back. |
| **Two `before_save` scripts have no defined order** | Do not let one set a field another gates on. Payment recording and the collection-outcome gate collided exactly this way; the fix was to make each correct independently. |
| **Deploy scripts must handle UTF-8 both ways** | PowerShell 5.1 reads BOM-less files as ANSI and mis-decodes responses as Latin-1 — corrupting script bodies on upload and producing false `DIFFERS` in Check mode. `group-11-financial-tail/*.ps1` are correct; **everything under `deploy/test/scripts/` still has both bugs.** |
| **The Phase 3 cancel flow has no mechanism yet** | Bulk-cancelling tasks needs to write `status` on tasks the user does not own, and `status` cannot go on `SYSTEM_FIELDS` because it is the primary user-editable transition. That mechanism does not exist. **Group 1 D11** (was ACT-05 before Group 1 renumbered to the D-series). |
| **Order entry refuses unpriced items** | Correct, but missing `Item Price` rows now block work rather than silently producing a zero-value invoice. Test coverage is ~86% of enabled items. |

### Symptoms a user can still report

| Symptom | Item |
|---|---|
| "Profit on this case looks far too high" | A1 |
| "We over-billed a client who has already paid and I can't fix it" | A4 |
| "Which of these two debt reports is the right one?" | A6 |

---

## 3. Go-live prerequisites

Data operations, not code. Required before this work is promoted beyond test.
Existing test data was deliberately **not** reconciled — it is synthetic, and
`w11-assess-first-scheduler-run.py` reports its state read-only.

1. **Close or cancel every legacy open `Debt Collection` task.** The one-open-episode-per-customer rule treats a leftover task as an episode in progress and declines to raise a real one, silently suppressing collection for that customer. On test: 194 open, against 5 customers who owe anything.
2. **Resolve legacy open `Debt Closure Approval` tasks** (172 on test). They were raised by the old task-completion trigger and may assert closures that never happened.
3. **Submit or cancel draft customer Payment Entries** (9 on test). A draft produces no GL entries, so the money is invisible to the ledger the new code reads.
4. **Triage cases stuck in `Invoice Pending`** (151 on test). Each needs an invoice committed or an explicit nothing-to-invoice close.
5. **Populate `Item Price` on `Standard Selling` for every orderable item.** Order entry now refuses an unpriced item rather than pricing it at zero.
6. **Reconcile the stock data that A2 left behind.** This was written as a prerequisite to removing the validation bypasses. It did not happen that way — the bypasses were removed first and the data was deliberately left, because test data is disposable. So it is now a **consequence**, and a live one: 13 items sit at negative stock in `Main - Inmed` and, with `allow_negative_stock` off, any operation touching them fails. 372 Stock Entries carry warehouse-less rows, 200 of which actually moved stock one-sidedly. Group 1 D10. **Whether production carries equivalents has not been looked at** — the defect that produced them was not test-specific.

One number worth carrying over: across every Dispatch Case ever created on test,
**`Closed` had never once been reached.** That was the defect, not the data.

---

## 4. Finding-ID map

Other group audits cite these IDs. Evidence for the closed ones is in git
history (`git show 07645d6`).

| ID | Outcome |
|---|---|
| **C1** | Fixed W1 — one access-control gate per doctype; `ignore_permissions` retired as a business signal |
| **C2** | Unreachable W7 — price resolved tender-first on add; tender quantity checked at order entry |
| **C3 / C4** | **Not addressed** — Group 2 hygiene: split Delivery photo rule, module-level `get_doc_before_save()` calls |
| **G1** | Fixed W6 — `task_close_case_nothing_to_invoice`; invoice required only when a line is billable |
| **G2** | Fixed W5 — `Payment Entry-after-submit-debt-closure-check` |
| **G3** | Fixed W2 — advance Payment Entries are submitted |
| **G4** | Fixed W4 — `collection_outcome` completion gate |
| **G5** | Fixed W9 — financial writes via `doc.save()`, producing version history |
| **G6** | Fixed W2/W8 — outstanding read from the invoice; nine stored fields deleted |
| **G7** | Fixed — Group 1 D1 closed A2; client warehouse now required on every order |
| **G8** | Fixed W7 — server-side price resolution |
| **G9** | **Open — A1** |
| **G10** | Fixed W5 — one open approval per customer; profit computed once at creation |
| **G11** | Fixed W6 — `Sales Invoice.dispatch_case`, `hospital`, `doctor_name` |
| **G12** | Fixed A3 — lost/damaged segregated, then billed or written off by Director decision |
| **G13** | Fixed W6 — tax template and Net 30 terms applied explicitly |
| **G14** | Fixed W2/W8 — payment creation carries `source_task`; overpayment refused |
| **G15 / G16** | Fixed W2 — debt read live from the ledger |
| **G17** | **Partly open — A6.** Prepaid report fixed in W8; duplicates and KPI reports remain |
| **R13** | **Open — A4** |

Three defects were found during the work that the original analysis had missed.
All three were invisible to privileged testing, which is why they had survived:

- **`Ops - Finance` could not record a payment at all** — it had create rights on `Payment Entry` but no permission on `Account`, so validating `paid_to` failed. Every Payment Entry on test had been created by a System Manager or Administrator. Fixed W2; recorded in `docs/03-roles-permissions-responsibilities.md`.
- **`Before Save` does not fire for submitted documents** — so the Dispatch Case gate, and the `lock-submitted` rule before it, had only ever guarded drafts. Fixed W9; now trap 1 above.
- **Deploy tooling corrupted non-ASCII on upload** — the origin of the mojibake in this repo. Fixed W1; now trap 6 above.

---

## 5. Where the implementation lives

| | |
|---|---|
| Deploy + verification scripts | `deploy/test/deploy/group-11-financial-tail/` — one `wN-*.ps1` per workstream, each paired with a `wN-verify-*.py` that runs via `bench console` as non-privileged users and rolls back |
| Architectural rules | `AGENTS.md` |
| Flow specification | `docs/16-unified-dispatch-flow.md` — §4.3 and §6.9–6.12 are the financial tail |
| Go-live testing | `docs/14-go-live-checklist.md` §9.1 — **run the payment and invoice scenarios as the owning role, not as Administrator** |
