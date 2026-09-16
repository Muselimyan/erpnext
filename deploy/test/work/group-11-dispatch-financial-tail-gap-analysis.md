# Group 11 — Dispatch Financial Tail

> **Scope.** Everything after goods physically reach the client: consumption posting, Sales Invoice creation, receivables, payment recording, debt closure, profit, and the reports built on them.
>
> **Excludes.** Dispatch Case operational flow (task chain, packing, scanning, returns handling, cancel flow) — see **Group 1**.
>
> **The rebuild is done and deployed to test** (W1–W11, 58 automated checks). This
> document is now two things: **§A–§C are the work that remains and the things
> that will bite you** — read those. **§0 onward is the archive**: the original
> analysis, kept because it explains why each change was made and because its
> finding IDs (C*, G*) are referenced from other audits.
>
> Original finding IDs are unchanged. The old §7 Recommendations table (R1–R14)
> has been replaced by §C's traceability map, because every row in it was either
> delivered or deliberately dropped, and a table of "Not started" statuses for
> completed work is worse than no table.

---

## §A. Open work

Ordered by consequence, not effort. Each entry says where to start.

### A1 — Profit is computed from a list price, not from cost · **known wrong**

`Payment Entry-after-submit-debt-closure-check` values cost as
`Item Price` on the `Standard Buying` list. Doc 17 makes the **landed-cost
valuation rate** authoritative, and ERPNext already exposes exactly the right
number per line as `Sales Invoice Item.incoming_rate`.

So every profit figure the system reports is wrong by whatever the difference
between list buying price and landed cost happens to be — freight, duty and
import tax are simply absent. Where no `Standard Buying` price exists at all,
cost is taken as zero and profit equals revenue; the task raises a warning, but
the number is still written.

**Start at:** the profit block in
`deploy/test/work/server/Payment Entry-after-submit-debt-closure-check.py`.
Swap the `Item Price` lookup for `incoming_rate` on the invoice line. Compare
against ERPNext's own Gross Profit report for the same invoice before trusting
it. Note **A2 must land first** — `incoming_rate` is only meaningful once stock
is actually valued.

### A2 — Stock validation is bypassed, so consumption can post nothing · **G7**

The consumption Stock Entries are submitted with `ignore_validate`,
`ignore_stock_validation` and `allow_zero_valuation_rate`. Together these mean a
Material Issue can be submitted that moves nothing, values nothing, and produces
no ledger entries — silently.

`client_location_warehouse` is also not required when a client-location movement
occurs, so a no-return case with a blank warehouse posts a warehouse-less row
rather than being refused.

This is the root of A1: with `allow_zero_valuation_rate`, consuming un-valued
stock succeeds instead of failing loudly, so nothing ever forces the valuation
data to be correct.

**Start at:** `create_se` in `Task-after-save-dispatch-flow.py`. Remove the
bypasses, require the warehouse at Order Entry, and raise a blocker task on
failure rather than submitting an empty entry. **This needs a data migration
first** — on test there were 18 inert Material Issues, −218 units of negative
stock in `Main - Inmed`, and 3 cases with `client_location_warehouse` set to
`Main - Inmed`. Reversing the order makes submissions fail on historical data.

### A3 — Lost and damaged items have no resolution path · **G12**

`lost_damaged_qty` is captured at returns inspection and then nothing happens to
it. It is deliberately **not** invoiced — charging a client for damage is a human
decision — but there is also no write-off, no replacement path, and no GL
consequence. The stock sits in `Returns - Inmed` indefinitely.

**Start at:** the returns-inspection completion branch in
`Task-after-save-dispatch-flow.py`. A `Write-off Approval` task with
invoice / write-off / replace outcomes, each with its own stock and GL posting.
The task kind already exists.

### A4 — A paid invoice cannot be corrected in-system · **R13**

Cancel + Amend works for an unpaid invoice and is the documented remedy. Once a
payment is allocated, it does not: ERPNext will not cancel an invoice with
submitted payment references without unwinding them first. There is no credit
note path and no refund path.

This has not bitten yet because the volume is low, but it is the obvious next
gap — and VAT treatment may make a credit note legally required rather than
merely convenient.

**Start at:** a credit note (`Sales Invoice` with `is_return = 1`) plus a refund
Payment Entry, behind Director approval. Decide whether it is task-driven like
the rest of the flow or an Accounting-only action on the native form.

### A5 — The Playwright harness cannot see permission defects · **W12**

`tests/e2e/src/config.ts` supplies a single `API_KEY`/`API_SECRET` belonging to
**Administrator**, and every Layer 1 API test uses it. Privileged users are
exempt from the access-control gates, so that suite is **structurally incapable**
of detecting C1, D2, or the `Ops - Finance` permission gap — all three of which
shipped and passed earlier smoke tests for exactly this reason.

Per-role browser sessions already exist (`auth.ts`, eight role users in config).
Only the API layer is Administrator-only.

**Start at:** issue per-user API tokens for the eight `e2e.*` users and add a
`createApiBundleAsRole(role)` helper, or drive API calls through the per-role
session cookies `auth.ts` already produces. Until then, any permission test must
be a UI test via `asRole('accounting')`.

The 58 checks in `deploy/test/deploy/group-11-financial-tail/w*-verify-*.py`
already cover this ground as real non-privileged users, via `bench console`, and
roll back. They are not in CI.

### A6 — Reporting and notifications · **G17**

Deliberately left until the figures underneath were trustworthy, which they now
mostly are. Group 10 holds the detail: duplicate report pairs, broken shortcuts,
dead task VIEWs, unbuilt KPI reports. Telegram money notifications (invoice
submitted, payment received, threshold breached) are still disabled.

Do **A1** first. Reports built on the current profit basis would only render a
wrong number more attractively.

---

## §B. Traps — read before changing this area

These are not bugs. They are properties of the system that will cost you a day
if you do not know them. All are also recorded in `AGENTS.md`.

| | |
|---|---|
| **`Before Save` never fires for submitted documents** | Frappe runs `before_save` only when `_action == "save"`; a submitted save is `update_after_submit`. A Dispatch Case is submitted for its whole working life, so a guard registered on `Before Save` misses almost everything. This is why there are **two** DC access-control scripts — a draft one and a submitted twin. **Change one, change the other.** |
| **`SYSTEM_FIELDS` is default-deny** | The access-control gates allow a save that touches only fields on their `SYSTEM_FIELDS` list. If you add a field that server code writes and forget to register it, housekeeping starts failing — loudly, which is the intent. Conversely, when a field stops having a legitimate system writer, remove it, or you have left a hole. |
| **Saving a Server Script does not prove it runs** | Frappe's compile check catches syntax errors, not the full RestrictedPython policy. A script can deploy cleanly and throw on first execution. For a Scheduler Event that means it looks deployed and silently never runs — and any test asserting "nothing happened" passes. Always execute what you deploy. |
| **Augmented assignment to a subscript is forbidden** | `d[k] += 1` and `d[k]["x"] += 1` both fail under RestrictedPython. Read into a local, modify, write back. |
| **Two `before_save` scripts have no defined order** | Do not let one set a field another gates on. Payment recording and the collection-outcome gate collided exactly this way; the fix was to make each correct independently. |
| **Deploy scripts must handle UTF-8 in both directions** | PowerShell 5.1 reads BOM-less files as ANSI and mis-decodes responses as Latin-1. This corrupted script bodies on upload and produced false `DIFFERS` in Check mode. The `group-11-financial-tail/*.ps1` scripts are correct; **everything under `deploy/test/scripts/` still has both bugs.** |
| **The Phase 3 cancel flow has no mechanism yet** | Bulk-cancelling tasks needs to write `status` on tasks the user does not own, and `status` cannot go on `SYSTEM_FIELDS` because it is the primary user-editable transition. That mechanism does not exist. See Group 1 ACT-05. |
| **Order entry now refuses unpriced items** | Correct, but it means missing `Item Price` rows block work rather than silently producing a zero-value invoice. Test coverage is ~86% of enabled items. |

---

## §C. Where each original finding ended up

Traceability for the C*/G* IDs referenced by the other group audits. Replaces
the old R1–R14 recommendations table.

| Finding | Outcome | Where it lives now |
|---|---|---|
| **C1** acceptance rule implemented three ways | Fixed, W1 | `Task-before-save-access-control` — one gate per doctype; `ignore_permissions` retired as a business signal |
| **C2** tender validation vs flow pricing deadlock | Unreachable, W7 | Price resolved tender-first when items are added; tender quantity checked at order entry |
| **G1** invoice task permanently uncompletable | Fixed, W6 | `task_close_case_nothing_to_invoice`; gate requires an invoice only when a line is billable |
| **G2** `Closed` unreachable | Fixed, W5 | `Payment Entry-after-submit-debt-closure-check` |
| **G3** advance Payment Entries never submitted | Fixed, W2 | `pe.submit()` in `Task-after-save-advance-payment` |
| **G4** no completion gate on Debt Collection | Fixed, W4 | `collection_outcome` gate in `Task-before-save-dispatch-gates` §A |
| **G5** financial fields bypass the submit contract | Fixed, W9 | `doc.save()` for financial writes; `allow_on_submit` was already granted |
| **G6** outstanding a one-shot snapshot, dead fields | Fixed, W2 + W8 | Read from `Sales Invoice.outstanding_amount`; nine fields deleted |
| **G7** stock validation disabled | **Open — §A2** | — |
| **G8** price from `Item.standard_rate` | Fixed, W7 | `task_add_dispatch_product` / `task_update_dispatch_product` |
| **G9** profit from buying list price | **Open — §A1** | — |
| **G10** no existence guard on Debt Closure Approval | Fixed, W5 | One open approval per customer; profit computed once at creation |
| **G11** no invoice back-link, no clinical metadata | Fixed, W6 | `Sales Invoice.dispatch_case`, `hospital`, `doctor_name` |
| **G12** lost/damaged has no resolution path | **Open — §A3** | — |
| **G13** invoice metadata depends on unasserted defaults | Fixed, W6 | Tax template and Net 30 terms applied explicitly |
| **G17** reporting, workspaces, notifications | **Partly open — §A6** | Prepaid report fixed in W8; rest deferred |
| **R13** credit note / refund path | **Open — §A4** | — |
| **C3/C4** split photo rule, module-level `get_doc_before_save` | Not addressed | Group 2 hygiene items, unchanged |

Three defects found during the work that were not in the original analysis are
in §0 as **N1–N3**.

---

## §0. What shipped (test only)

Nine workstreams deployed to `test.erpnext.am` and verified by 58 automated checks
run as genuinely non-privileged users. Verification scripts live beside the deploy
scripts in `deploy/test/deploy/group-11-financial-tail/` and roll everything back.

| WS | What shipped | Findings closed |
|---|---|---|
| W0 | Pre-deletion snapshot of every field and table later deleted | — |
| W1 | One access-control gate per doctype; `ignore_permissions` retired as a business signal | **C1**, ACT-03, ACT-06/07 |
| W2 | Debt read live from the ledger; 5 Task fields + 2 child doctypes deleted | **G4**, **G6**, G15, G16 |
| W6 | Invoice built, valued and submitted in one action; VAT, Net 30 terms, clinical metadata, `Sales Invoice.dispatch_case` | **G1**, G11, G13, G14, G15 |
| W7 | Prices resolved server-side, tender first; tender quantity checked at order entry | **C2**, G8 |
| W8 | Advances are submitted Payment Entries carrying `dispatch_case` / `source_task`; 4 DC fields + 1 child doctype deleted | **G3**, G17 (prepaid report) |
| W4 | Debt Collection becomes an *episode* of chasing work, with an outcome gate | **G4** |
| W5 | Settlement raised by the ledger, not by task completion; profit computed once | **G2**, **G10** |
| W9 | Submitted-document gate hole closed; financial writes produce version history; `Invoiced` status removed | **G5**, G9 |
| W10 | `AGENTS.md` rules, this document, `Distribute Payment` retired | — |

**Not done, deliberately:** profit *basis* rework (still Standard Buying list
price rather than landed cost — Doc 17), credit-note / refund path, lost-damaged
resolution task (**G12**), stock-validation bypass removal (**G7**), reporting and
KPI cleanup, Telegram re-enablement. Remaining data cleanup is W11; Playwright
coverage and per-role API auth for the harness is W12.

### Three findings that only appeared once the work started

None of these were in the original analysis. Each was invisible until the code
was exercised as the role that owns it.

| # | Finding |
|---|---|
| **N1** | `Ops - Finance` could not record a payment at all. It had create rights on Payment Entry but **no permission on `Account`**, so validating `paid_to` failed. Every Payment Entry on test was created by a System Manager or Administrator — the Finance payment workflow had never once worked for the role that owns it. Same shape as C1. |
| **N2** | **`Before Save` Server Scripts never fire for submitted documents** (Frappe runs `before_save` only when `_action == "save"`; a submitted save is `update_after_submit`). So neither the W1 gate nor the `lock-submitted` script it replaced had ever guarded a submitted Dispatch Case — and a case is submitted for the whole of packing, delivery and returns. The unguarded half was the larger half. |
| **N3** | Deploy tooling read script bodies as ANSI, corrupting non-ASCII on upload; this is the origin of the mojibake in `Task-after-save-debt-closure` and the Discount Approval task subject. Check mode also reported false `DIFFERS` by decoding responses as Latin-1. **Every deploy script under `deploy/test/scripts/` still has both bugs.** |

All three are recorded as rules in `AGENTS.md`.

### W11 — existing test data is deliberately NOT reconciled

The test database is synthetic: roughly 1,000 Dispatch Cases and 700 debt-kind
tasks, generated by earlier smoke tests and by the e2e suite. Reconciling it has
no value, so it has not been touched. `w11-assess-first-scheduler-run.py` is a
read-only diagnostic that reports the state without changing it.

What that assessment found, as of the W10 deploy:

| | |
|---|---|
| Unpaid submitted invoices | 6 |
| Distinct customers owing | 5 |
| Episodes the scheduler would raise on its first run | **5** |
| Legacy open Debt Collection tasks | **194** |
| Legacy open Debt Closure Approvals | 172 |
| Draft customer Payment Entries | 9 |
| Dispatch Cases in `Invoice Pending` | 151 |
| Dispatch Cases in `Closed` | **0** |

Three of these are worth reading carefully.

**No flood risk.** The episode scheduler iterates every customer holding an
unpaid invoice and has no per-run cap, so the first run was a plausible hazard.
It would raise 5 episodes. No cap has been added — the concern did not survive
measurement, and a limit invented for a problem that does not exist is just
another thing to misconfigure.

**`Closed` = 0 is G2, visible in data.** Across every case ever created on this
instance, the lifecycle's terminal state has never once been reached. W5's
verification proves the new path reaches it; the historical zero is the defect.

**194 open Debt Collection tasks against 5 customers who owe anything.** These
are the perpetual tasks the old model produced — still open, chasing customers
with nothing outstanding. They are also the one piece of legacy data that
affects the *new* code, because the one-open-episode-per-customer dedup rule
will treat a zombie task as an episode in progress and decline to raise a real
one. On test that is harmless. On a real deployment it is not.

### Go-live prerequisites (not performed here)

If this work is promoted beyond test, these must be done to the target data
first. They are data operations, so they are listed rather than scripted.

1. **Close or cancel every legacy open Debt Collection task.** Otherwise the
   dedup rule silently suppresses collection for those customers. Under the new
   model a closed episode is normal and costs nothing — there is no balance
   stored on it to lose.
2. **Resolve the legacy open Debt Closure Approvals.** They were raised by the
   old task-completion trigger and assert closures that may never have happened.
3. **Submit or cancel the draft customer Payment Entries.** A draft produces no
   GL entries, so the money is invisible to the ledger the new code reads.
4. **Triage the `Invoice Pending` cases.** Each needs either an invoice
   committed or an explicit nothing-to-invoice close; the old flow left them
   with an auto-created draft that may no longer exist.
5. **Populate `Item Price` on `Standard Selling` for any item that can be
   ordered.** W7 refuses to add an unpriced item rather than silently defaulting
   to zero, which is correct but will block order entry for gaps. Test coverage
   is ~86% of enabled items.

---

## 1. The three original blockers — all fixed

*Archive. This was the top of the document when the analysis was written; all
three are closed. Live work is in §A.*

Everything else in this document can wait. These three are blockers, and two of them are also prerequisites for the task-native direction (§2).

| # | What | Why it can't wait | Status |
|---|---|---|---|
| **C1** | Three before-save scripts on Task implement the same acceptance rule with three different bypass semantics | An `Ops - Accounting` user **cannot** complete Invoice Preparation for any customer who already has an open Debt Collection task. Repeat hospitals are the normal case. Code-certain. | **Fixed (W1).** Reproduced as `Ops - Accounting` before the fix, passes after. |
| **G1 + C2** | The Invoice Preparation task can become permanently uncompletable, by two independent routes | Both reachable in routine operation: (a) client returned everything unused, (b) item is covered by an active tender. No in-app recovery, not even as Administrator. | **Fixed (W6, W7).** G1 has an explicit close path with a recorded reason; C2 is unreachable — the price *is* the tender price, and over-quantity is caught at order entry. |
| **G5** | Every financial field on Dispatch Case is written via `frappe.db.set_value` on fields declared `allow_on_submit = 0` | No validation, no version history, **no audit trail on any money field**. Becomes critical the moment the underlying document stops being user-visible (§2). | **Fixed (W9).** Financial writes go through `doc.save()` and produce a `Version` row. Note `allow_on_submit` turned out to be already granted via Property Setters, so the premise was half wrong. |

Everything below is detail, evidence, and sequencing for these plus 15 lesser findings.

---

## 2. Relationship to the task-native direction

The project's architectural intent is that users operate **only inside Tasks**, with underlying documents updated beneath them by server-side APIs — as already done for Dispatch Case via `task_add_dispatch_product` / `task_update_dispatch_product`, and already done for payments via the Debt Collection task.

Extending that to invoicing and debt changes the priority of three findings from "bugs" to **prerequisites**:

| Finding | Why it blocks task-native |
|---|---|
| **C1** | The pattern *depends on* server APIs writing to documents the user doesn't own. Two of the three gates don't honour `ignore_permissions`, so they punish exactly that mechanism. Adding more cross-document APIs scales the bug. A single sanctioned system-write context is required first. |
| **C2** | In a task-only UI, a `frappe.throw` from a document the user cannot open is a dead end. Tender price must be resolved server-side when items are added, not enforced at invoice submit. |
| **G5** | Task-native trades user-side inspectability for system-side guarantees. Removing the user's ability to open the Dispatch Case while its money fields still have no version history is a net regression. |

**Design decision still open:** whether the Invoice task edits a draft Sales Invoice (mirroring the DC pattern) or edits the Dispatch Case with the invoice generated *and submitted* in one atomic commit. The second removes G1, removes draft-drift, and makes idempotency trivial, at the cost of needing an explicit Accounting escape hatch for genuine edge cases. Not yet decided — see V6.

> **RESOLVED (W6).** The second option was chosen. No draft invoice is created at
> any point: the Invoice Preparation task shows a priced preview and one action
> builds, values and submits the invoice. The escape hatch is
> `task_close_case_nothing_to_invoice`, which closes a case with nothing to bill
> and records a reason on both the case and the task.
>
> Two consequences worth noting, neither anticipated here:
>
> - The commit action and the completion gate had to be reconciled. The closer
>   completes the task via `task.save()`, which tripped the gate demanding a
>   submitted invoice — the same trap, one layer up. The gate now requires an
>   invoice only when a line is actually billable.
> - `Dispatch Case.sales_invoice` could not remain the authoritative link,
>   because Cancel + Amend produces a new document with a new name and strands
>   the case (G11). `Sales Invoice.dispatch_case` is authoritative instead, and
>   because amendments copy custom fields it survives Cancel + Amend with **no
>   special handling at all** — the amend-chain logic originally planned was
>   deleted rather than written.

---

## 3. Symptoms — and which are still live

Business-readable translation. Useful in both directions: for triaging old
support history, and for recognising the three that a user can **still** report.

| Symptom a user would report | Finding | Still possible? |
|---|---|---|
| "I can't finish my invoice task — it says I'm not allowed to edit a Debt Collection task I never opened" | C1 | No — W1 |
| "The invoice task won't close. It says no Sales Invoice is linked and there's nothing I can do" | G1 | No — W6 |
| "The invoice won't submit — it says the rate must equal the tender price" | C2 | No — W7 |
| "This case says Payment Pending but the customer paid months ago" | G2, G6 | No — W5 |
| "The customer paid a deposit but accounting says we never received it" | G3 | No — W2 |
| "Who changed the outstanding amount on this case?" — no answer available | G5 | No — W9 |
| "This report says the client owes us, the ledger says they're in credit" | G3, G6 | No — W2/W8 |
| "I can't record a payment at all — it says insufficient permission for Account" | N1 | No — W2 |
| **"Profit on this case looks far too high"** | G9 | **Yes — §A1.** Cost is a list price, so freight, duty and import tax are missing entirely; where no buying price exists, profit equals revenue |
| **"Nothing tells us what to do with the implant the hospital lost"** | G12 | **Yes — §A3.** Captured at inspection, then nothing happens to it |
| **"We over-billed a client who has already paid and I can't fix it"** | R13 | **Yes — §A4.** Cancel + Amend only works while the invoice is unpaid |
| "Which of these two debt reports is the right one?" | G17 | Partly — §A6. The prepaid report is fixed; duplicates remain |

---

## 4. Evidence discipline

Test data is **not** treated as ground truth — the test instance carries residue from many iterations of buggy deploys. Every finding is classified by what proves it:

| Tag | Meaning |
|---|---|
| **CODE** | Provable from current deployed script logic alone. Reproduces on any environment. |
| **CODE+CFG** | Provable from script logic plus deployed schema / DocType / Task Access Policy configuration (also deployable state, not transactional data). |
| **CFG** | A configuration or master-data gap the code depends on but does not assert. Severity depends on the target environment. |
| **DATA** | Observed on test only. **Not** a conclusion about the code — recorded as corroboration or as cleanup scope. |

Where data contradicted code, **code won** and the data-derived claim was retracted (§8).

**Code authenticity.** Live bodies of all 8 financial Server Scripts were pulled from the test REST API and diffed against `deploy/test/work/server/*.py`: all 8 are code-identical (only a leading blank line and comment re-encoding differ).

---

## 5. Verified flow

```
Delivery → "Delivered"                       [Task-after-save-dispatch-flow.py:186]
  ├── return_expected = 0 → SE(Transit → client_wh) → SE(client_wh → out, Material Issue)
  │                       → create_invoice() → Task: Invoice preparation
  └── return_expected = 1 → Task: Return Call → Pickup → Task: Returns processing
                            → on completion: SE(Returns → out, used_qty only)
                            → create_invoice() → Task: Invoice preparation (+ Restock task)

Task: Invoice preparation completed          [gate: dispatch-gates.py:162-168 requires SI docstatus=1]
  └── outstanding = SI.grand_total − DC.prepaid_amount      [dispatch-flow.py:269]
        ├── ≤ 0 → DC.status = "Closed"                      [dispatch-flow.py:272]
        └── > 0 → DC.status = "Payment Pending" + Debt Collection task (one per customer)

Task: Debt Collection — Finance enters amount / method / reference
  └── before_save: FIFO allocate → Payment Entry (Receive, insert + submit, with references)
        └── if total_outstanding ≤ 0 → doc.status = "Completed"   [payment-recording.py:86-87]

Task: Debt Collection completed → Task: Debt Closure Approval (Directors)
  └── on completion: profit = Σ(SI rate×qty) − Σ(Item Price[Standard Buying]×qty) → DC.profit

Side flows:
  Task: Payment Received → Payment Entry (insert, NO submit) + DC.advance_payments + prepaid_amount
  Scheduler (Hourly)     → GL net receivable vs Customer.debt_threshold_amd → Debt Alert task
  Payment Entry After Submit → Distribute Payment — disabled=1 (intentional)
```

### Correct by design — do not "fix" these

- Sales Invoice with `update_stock = 0`; stock moved by separate Stock Entries. Clean separation of stock and financial truth.
- Draft invoice auto-created, Accounting reviews and submits; the gate genuinely enforces `docstatus = 1`.
- FIFO allocation by invoice posting date, with `allocations` captured **before** `allocated_now` is zeroed (`payment-recording.py:33-42`) and written as Payment Entry `references`. Earlier audit claims that this is broken are **stale**.
- `paid_to` mapping: Cash → `Cash - Inmed`, Bank Transfer/Card → `Bank - Inmed`.
- `Task Access Policy` as single source of truth; `dispatch_task_accept.py:18-25` reads it at runtime, no hardcoded role map.
- Debt Alert (Director, GL-based, hourly) kept architecturally separate from Debt Collection (Finance, workflow).
- `make_task()`'s existence guard preventing duplicate task creation.
- `tender_fulfillments` correctly declared `allow_on_submit = 1`.
- B-10 field permissions genuinely deployed: `tabCustom DocPerm` carries permlevel-1 and permlevel-2 rows for the correct roles.

---

## 6. Findings

Severity: **S1** corrupts financial records · **S2** blocks or misleads users · **S3** hygiene.

### 6.1 Script conflicts

Defects requiring more than one file to see. This is the class a per-script audit structurally cannot find.

#### C1 — Three implementations of the acceptance rule, three bypass semantics · **CODE+CFG** · S1

All three run on Task `Before Save`, in undefined order:

| Script | Honours `flags.ignore_permissions`? | Admin/SysMgr exempt? |
|---|---|---|
| `Task-before-save-lock-unaccepted.py:11,20` | **Yes** | Yes |
| `Task-before-save-dispatch-gates.py:17-22` | **No guard** | **No** |
| `Task-before-save-policy.py:68-71` | **No guard** | Yes |

`create_or_update_debt_task()` (`dispatch-flow.py:151-157`) sets `t.flags.ignore_permissions = True` and calls `t.save()` on the **existing** Debt Collection task to append a second invoice — expecting the exemption that `lock-unaccepted` provides. But:

- **Throw 1** (`dispatch-gates.py:17-22`) fires whenever the target task has `task_kind` set, is not new, and has no `custom_accepted_by`. No flag guard, no Administrator exemption.
- **Throw 2** (`policy.py:68-71`) fires whenever the **session user** lacks a role in the **target task's** allowed roles. Deployed policy config makes this deterministic: `Invoice preparation / create invoice` → `Ops - Accounting`; `Debt Collection` → `Ops - Finance`, `Ops - Directors`. **Fires regardless of acceptance.**

**Net effect:** for any customer with an existing open Debt Collection task, an `Ops - Accounting` user can never complete Invoice Preparation. The error names a document they never opened. Only Directors and System Managers pass.

*Why this survived a passing smoke test: the group-3 tests were executed by privileged accounts, which `is_admin_override` exempts. Role-gated defects are invisible to privileged testing.*

#### C2 — Tender validation versus flow pricing: guaranteed deadlock · **CODE+CFG** · S1

- `Sales-Invoice-before-submit-tender-validation.py:50-56` throws unless `flt(invoice_rate,2) == flt(tender_price,2)`; `:44-48` throws if `qty > won − supplied`.
- `create_invoice()` (`dispatch-flow.py:136`) sets `rate = unit_price × (1 − discount_pct/100)` with **no tender awareness**.
- The Invoice Preparation gate requires `docstatus = 1`.

Unless the hand-entered price coincidentally matches the tender price to 2 decimals, the invoice cannot be submitted and the task cannot complete. The quantity check can fail even at the correct price. Note this conflict was *introduced* by the group-3 tender-validation fix, which added a blocker in front of a generator it left untouched.

### 6.2 Financial-record defects (S1)

#### G1 — The Invoice Preparation task can become permanently uncompletable · **CODE**

`create_invoice()` returns early without creating anything if no row qualifies:

```python
if qty <= 0: continue
...
if not items_rows:
    return          # dispatch-flow.py:138-139 — DC.sales_invoice never set
```

The caller creates the Invoice Preparation task **unconditionally** afterwards (`:194`, `:248`). The gate then throws forever: *"No Sales Invoice linked to this Dispatch Case yet."* (`dispatch-gates.py:165-166`).

`used_qty = dispatched − returned − lost` on every DC save (`Dispatch-Case-before-save.py:12`). So the trigger is simply **"the client returned everything unused"** — cancelled surgery, kit returned intact. Routine business. Zombie task, no recovery path, not even as Administrator. Same outcome if the case has zero item rows.

#### G2 — `Closed` is written in one place; nothing else ever closes a case · **CODE**

Grep for `"Closed"` across all 44 enabled server scripts: exactly **two** hits — `dispatch-flow.py:272` (Dispatch Case) and `Tender-Agreement-before-save.py:14` (unrelated doctype).

`Closed` is reachable only at Invoice Preparation completion when `grand_total − prepaid_amount <= 0`, i.e. only when fully prepaid *before* the invoice task completed. Otherwise the case lands in `Payment Pending` and **no code path ever moves it again** — `payment-recording.py` only mutates the Task; `debt-closure.py` only writes profit. The lifecycle's terminal state is unreachable for the normal pay-after-invoice flow.

*DATA: 0 of 270 test cases have ever held `Closed` or `Delivered`; `tabVersion` has no reference to either.*

#### G3 — Advance Payment Entries are never submitted · **CODE**

`Task-after-save-advance-payment.py:35` calls `pe.insert()` with no `pe.submit()`. The sibling script does submit (`payment-recording.py:80-81`). A draft Payment Entry produces no GL entries — yet `DC.prepaid_amount` is written (`:49`) and subtracted from the invoice total (`dispatch-flow.py:269`), and `Task.available_advance_credit` is incremented (`:57`). The workflow grants credit for money the ledger has never seen.

*DATA: the 3 advance PEs on test are `docstatus = 0` with 0 GL rows each.*

#### G4 — No completion gate on Debt Collection · **CODE**

Auto-complete-at-zero lives only in the payment path (`payment-recording.py:86-87`), and that script is skipped entirely unless `new_payment_amount` changed (`:10-16`). `dispatch-gates.py` gates Pack, Delivery, Pickup, Returns, Invoice prep, Discount Approval and Debt Closure Approval — **not** Debt Collection. A user can set status = Completed with debt outstanding, cascading into Debt Closure Approval and profit calculation on unpaid invoices.

*DATA: 2 Completed Debt Collection tasks on test carry 780,000 and 193,050 outstanding (field value and child-table sum agree).*

#### G5 — Financial fields written by bypassing the submit contract · **CODE+CFG**

Dispatch Case is submittable and the flow writes financial state after submit, but the deployed schema declares `allow_on_submit = 0` for every one of those fields:

| Field | `allow_on_submit` | Written after submit by |
|---|---|---|
| `status` | **1** ✔ | `db.set_value` |
| `advance_payments` | **1** ✔ | `case.save()` |
| `sales_invoice` | 0 | `db.set_value` (`dispatch-flow.py:146`) |
| `total_invoice_amount`, `outstanding_amount` | 0 | `db.set_value` (`:270`) |
| `prepaid_amount` | 0 | `case.save()` + `ignore_validate_update_after_submit` (`advance-payment.py:49-53`) |
| `profit` | 0 | `db.set_value` (`debt-closure.py:136`) |
| `*_stock_entry`, `invoice_task` | 0 | `db.set_value` |

`frappe.db.set_value` writes straight to SQL — no validation, no hooks, **no version history**. `advance-payment.py:52` explicitly defeats the immutability check. Any future refactor to `doc.save()` starts throwing.

#### G6 — Outstanding is a one-shot snapshot; two fields are dead · **CODE**

- `outstanding_amount` written once (`dispatch-flow.py:270`), never recomputed. Payments don't touch it.
- Ordering flaw: computed at Invoice Preparation completion. An advance recorded *after* updates `prepaid_amount` but nothing recomputes outstanding.
- `total_paid_amount` — written by **no code**; only reference is a client-side hide list (`Dispatch Case-Price Visibility.js:25`). Dead.
- `available_advance_credit` — written at `advance-payment.py:57`; **read by no server logic**, never decremented, never used in FIFO allocation. Write-only.

#### G7 — No guaranteed client warehouse, and validation is disabled · **CODE**

The Order Entry gate makes the client warehouse conditional (`dispatch-gates.py:73-74` — required only when `return_expected`). On the no-return path it may be blank, and that value is used as a Stock Entry warehouse twice: `t_warehouse = ""` (`:187`) and `s_warehouse = ""` (`:191`).

`create_se` then disables the checks that would catch it (`:62-64`):

```python
se.flags.ignore_permissions = True
se.flags.ignore_validate = True            # skips Stock Entry.validate() wholesale
frappe.flags.ignore_stock_validation = True
```

`ignore_validate = True` is the serious one — missing warehouses, missing quantities and insufficient stock all pass, and the entry submits having posted nothing.

*DATA: 18 submitted Material Issues with 29 warehouse-less rows, 0 SLE and 0 GL each; 13 items at negative stock in `Main - Inmed` (−218 units); 3 legacy cases with `client_location_warehouse = "Main - Inmed"`.*

#### G8 — Price source is `Item.standard_rate`, not the Price List architecture · **CODE**

Doc 09 specifies `Standard Selling` plus customer-specific `Item Price` as the canonical Price Override List. **No dispatch-flow code reads either.** Actual implementation:

- `Task-Product Work Area.js:528-534` auto-fills from `Item.standard_rate`
- `Dispatch Case-Products Button.js:39,134,145-147,226-228` reads/displays `standard_rate`
- `task_add_dispatch_product.py:13` — `float(frappe.form_dict.get("unit_price") or 0)`, **defaults to 0, no validation**
- `task_update_dispatch_product.py:26-27` accepts whatever the client sends
- Nothing gates Dispatch Case submission on `unit_price > 0`

The selling price is a client-supplied number defaulted from an item-master field, with no server-side floor and no connection to the price list, tender or override architecture.

*DATA: `standard_rate` is 0 on all 3,265 enabled test items; 94% of submitted DC Item rows have `unit_price = 0`. Master-data condition, not proof about prod — see V3.*

### 6.3 User-blocking and misleading (S2)

#### G9 — Profit uses a buying price list, not landed-cost valuation · **CODE**

`debt-closure.py:125` reads `Item Price` / `Standard Buying`. Three problems: (a) Doc 17 makes the landed-cost *valuation rate* authoritative, and ERPNext already exposes it as `Sales Invoice Item.incoming_rate`; (b) `or 0` fallback yields 100% margin on any line with no price, and the `msgprint` warning does not block the write; (c) `db.set_value` writes to whatever `open_invoices.dispatch_case` contains, with no status or docstatus check.

*DATA: 38% of test invoice lines lack a Standard Buying price; `profit` is set on 2 Draft cases with no invoice.*

#### G10 — No existence guard on Debt Closure Approval creation · **CODE**

`make_task()` checks for an existing open task of the same kind (`dispatch-flow.py:94-97`). `debt-closure.py:45-79` has **no such guard** — every Debt Collection completion inserts a new approval task. Re-opening and re-completing produces duplicates, each writing `profit` on completion. *(Within a single task, profit is recomputed and overwritten, not accumulated — see §8.)*

#### G11 — Sales Invoice has no back-link and no clinical metadata · **CODE+CFG**

`create_invoice()` sets only `customer`, `company`, `currency`, `update_stock`, `items`. It never populates the deployed custom fields `hospital`, `doctor_name`, `hospital_branch`. There is **no `dispatch_case` link** on Sales Invoice, so the relation is one-directional. `DC.sales_invoice` is a single Link, so split invoicing is impossible and a cancelled-then-reissued invoice leaves the case pointing at the cancelled document with the gate refusing completion. Knock-on: `RPT — Data Quality — Missing Doctor or Hospital` flags 100% of dispatch invoices by construction.

#### G12 — Lost/damaged items have no resolution path · **CODE+CFG**

Excluded from the invoice by design. But grep for `Write-off` across all server scripts returns **zero** hits — the string appears only in client-side visibility/editability/action-button lists. A `Write-off Approval` Task Access Policy exists (`directors.team@example.com`) and the `task_kind` option exists; **no code creates one.** Stock stays in `Returns - Inmed` with no task, flag or report.

#### G13 — Invoice metadata depends on master-data defaults the code never asserts · **CFG**

`create_invoice()` sets no `taxes_and_charges` and no `payment_terms_template`. ERPNext's `set_missing_values` applies defaults from Customer Tax Category / `Customer.payment_terms` **if they exist**. A configuration dependency, not a hard code bug — but the code makes no assertion, so a misconfigured environment silently produces zero-VAT invoices with `due_date = posting_date`, making every aging bucket meaningless.

*DATA: 1 tax template with 0 marked `is_default`, 0 customers with tax category, 0 with payment terms → 0 tax rows across 36 invoices. Prod must be checked separately — V3.*

### 6.4 Hygiene (S3)

| ID | Finding | Tag |
|---|---|---|
| **C3** | Two mandatory-photo gates for Delivery, split by an incidental condition: `policy.py:77-87` enforces a photo only when `not doc.dispatch_case`; `dispatch-gates.py` covers Pack and Pickup drop-off but not Delivery. Doc 16 records this as intentional, but the rule lives in two files keyed off an unrelated field. | CODE |
| **C4** | `Task-after-save-debt-closure.py:10-12` runs `get_doc_before_save()` unconditionally at module level for **every** Task save before the `task_kind` filter. Harmless today; the same pattern in the other three after-save scripts compounds it. | CODE |
| **G14** | Side effects in `before_save`: `payment-recording.py:80-81` inserts *and submits* a Payment Entry and mutates `doc.status` (`:87`), alongside three other order-undefined before-save scripts. C1 demonstrates where this leads. | CODE |
| **G15** | `dispatch-flow.py:150` sets the Debt Collection row's `invoice_amount` to the **net-of-prepayment outstanding**, not the invoice grand total. Mislabeled for any reader or report. | CODE |
| **G16** | Theoretical: `create_or_update_debt_task` looks up by `{"customer": c.customer}`; a falsy customer would collapse all customer-less cases into one debt record. **Low reachability** — `dispatch-gates.py:71-72` requires a customer at Order Entry. Hardening note only. | CODE |
| **G17** | Reporting/workspace configuration: no KPI reports exist (Doc 15A's claim is wrong); `Management - KPI Dashboard` has 0 charts, 0 cards and 3 unrelated shortcuts; 2 broken shortcuts in `Ops — Reporting Pack`; 3 duplicate report pairs (Debt Threshold, Unallocated Advances, Dispatch Aging); dead `VIEW: Distribute Payment` and `VIEW: Write-off Approval` links; nothing reports on `DC.profit`; both Telegram scripts `disabled = 1`; `Dispatch Case-packing-problem-alerts.py` not deployed; `Invoiced` still in the status options. | CFG |

---

## 7. Recommendations — superseded

The original R1–R14 recommendations table lived here, with an Owner and Status
column per row. Every row has since been delivered, deliberately dropped, or
moved to **§A Open work**, so the table was removed rather than left showing
"Not started" against finished work.

**§C** maps each original finding to where it ended up. **§A** is what is left
to do. The acceptance criteria that named a role to test as were the most useful
part of that table, and that idea now lives in docs/14-go-live-checklist.md
§9.1, which instructs the tester to run the payment and invoice scenarios as the
owning role rather than as Administrator.

---
## 8. Retractions and corrections

Recorded so they do not propagate.

| Earlier claim | Correction |
|---|---|
| **"COGS is never posted; `allow_zero_valuation_rate: 1` eliminates it."** | **Retracted as stated.** The flag only *permits* a zero valuation, it does not create one. If an item carries a valuation rate, the Material Issue values normally and posts GL. The real defect is narrower: the flag **suppresses the guard** that would refuse to consume un-valued stock. Zero-COGS on test is a consequence of test items having no valuation — DATA, not a code conclusion. Folded into G7/G9. |
| "Duplicate invoices are being created (14 × 100 AMD)" | **Retracted.** No two cases share an invoice; those 14 belong to 14 distinct cases. The `is_completing` / `ds_changed` guards do prevent re-firing. |
| "Profit is double-counted across repeated closures" | **Retracted.** Within one task profit is recomputed and **overwritten**. The real defect is the missing existence guard — G10. |
| "90% of items lack a buying price → profit ≈ revenue" | Wrong denominator. Invoice-line coverage is the relevant figure (38% of lines on test) and it is DATA. The code defect is the wrong cost basis — G9. |
| "Zero VAT and broken aging are code bugs" | Reclassified to **CFG** (G13). |
| "No Dispatch Case ever reaches Closed" | **Upheld and strengthened** — now proven from code (single write site, no other closing path), not from the 0/270 count. |
| "Debt Collection completable with debt outstanding" | **Upheld** — proven by the absence of any gate. |
| "B-10 field permissions are only staged, not deployed" | **Retracted.** `tabCustom DocPerm` carries correct permlevel-1 and permlevel-2 rows. Genuinely deployed. |
| Group 2 audit: "BUG-3 / BUG-4 still open" | **Stale.** `dispatch_task_accept` reads Task Access Policy; payment recording writes references correctly. |
| Group 10 audit: "Reporting Pack points at superseded Surgery Case"; "Dispatch Case VIEWs / Aging missing"; "`RPT - Pricing - …` built"; "Prepaid Orders duplicate pair" | **All four false** against the deployed test schema. `Surgery Case` DocType does not exist; all four VIEW shortcuts and the Aging shortcut are present; the Pricing report does not exist (broken shortcut); Prepaid Orders is a broken shortcut, not a duplicate. |
| "`tender_fulfillments` post-submit write may throw" | **Retracted.** The field is `allow_on_submit = 1`. |

---

## 9. Sequencing — spent

The original dependency order was followed, with two deviations worth recording.

**W6 and W7 were swapped.** The plan put invoicing before pricing; pricing had to
land first, because resolving the tender price when items are *added* is what
makes the tender validator unreachable at invoice submission. Fixing the invoice
without fixing the price would have left C2 alive.

**W9 shrank and then grew.** It was sized as the risky workstream — converting
`frappe.db.set_value` to `doc.save()` on submitted documents was expected to
surface months of hidden validation errors. It surfaced none: `allow_on_submit`
was already granted on every affected field, and W5 had already delivered the
reconciliation half. Instead it uncovered something larger that was not on any
list — that `Before Save` never fires for submitted documents, so the Dispatch
Case gate had been guarding only drafts. The workstream that looked most
dangerous was cheap; the danger was somewhere nobody had looked.

What remains is in **§A**, and its only hard ordering constraint is that **A2
(stock validation) precedes A1 (profit basis)** — `incoming_rate` means nothing
until stock is actually valued — and that **A1 precedes A6 (reporting)**, since
reports on a wrong profit basis only present the error more convincingly.

---

## 10. Open questions — answered

| # | Question | Answer |
|---|---|---|
| **V1** | Does an `Ops - Accounting` user completing Invoice Preparation for a customer with an open Debt Collection task actually throw? | **Yes, confirmed empirically** as `e2e.accounting@test.erpnext.am` before the fix: *"You must Accept this task before making any changes."* Passes after W1. This is the single most important confirmation in the document — the defect was real, and invisible to privileged testing. |
| **V2** | Confirm G1: complete a returns inspection where everything came back unused | **Confirmed.** The task was uncompletable by anyone, including Administrator. W6 added an explicit close path. |
| **V3** | Is master data configured — valuation rates, `Item.standard_rate`, tax template, payment terms? | **Partly answered, from test.** `Item.standard_rate` is populated on **zero** items, which is why client-supplied prices were almost always 0. `Standard Selling` covers ~86% of enabled items, so server-side resolution works. The `Armenia Tax - Inmed` template existed all along with `is_default = 0`, so nothing ever applied it. No Net 30 term existed; W6 created one. **Prod was never queried** — that still requires explicit approval. |
| **V4** | Correct Armenian VAT template and payment terms | **Settled for now:** VAT 20% via `Armenia Tax - Inmed` → `VAT - Inmed`, and a new `Net 30` term. Both are applied explicitly by `task_commit_invoice` rather than relying on a default. If 30 days is the wrong term commercially, changing the template is enough — no code change. |
| **V5** | Cleanup scope for existing bad data | **Decided: not reconciled.** Test data is synthetic and reconciling it has no value. What matters is that the new code copes with it, which was measured rather than assumed — see §0 "W11". Go-live prerequisites are listed for whatever the target data turns out to be. |
| **V6** | Does the invoice task edit a draft, or commit atomically? | **Resolved: commit atomically.** No draft is created at any point. §2 records the reasoning and the two consequences that were not anticipated — the closer colliding with the completion gate, and `Dispatch Case.sales_invoice` having to stop being the authoritative link. |

One question the original analysis did not think to ask, and should have:

**Which event is each guard registered on?** Two rules in this area had never
executed — the submitted-case restriction, and the Debt Closure Approval role
check that sat inside a `if not doc.dispatch_case` block. Both looked
implemented. Neither ran. Reviewing *what a script says* is not the same as
establishing *that it fires*.