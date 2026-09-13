# Group 11 — Dispatch Financial Tail: Gap Analysis and Redesign

> **Scope.** Everything after goods physically reach the client: consumption posting, Sales Invoice creation, receivables, payment recording, debt closure, profit, and the reports built on them.
>
> **Excludes.** Dispatch Case operational flow (task chain, packing, scanning, returns handling, cancel flow) — see **Group 1**.
>
> **Status.** Analysis and proposal. No code changes made, per project rule "No Changes Without Approval".
>
> **Revision note.** Previously circulated as `docs/23-dispatch-financial-tail-gap-analysis.md`. Renamed to Group 11 to sit alongside the other group audits. **All finding IDs (C*, G*, R*, V*) are unchanged from that revision** — notes made against the old numbering remain valid. The 1–100 importance scores from that revision have been replaced with three priority bands (see §7).

---

## 1. Fix these three first

Everything else in this document can wait. These three are blockers, and two of them are also prerequisites for the task-native direction (§2).

| # | What | Why it can't wait |
|---|---|---|
| **C1** | Three before-save scripts on Task implement the same acceptance rule with three different bypass semantics | An `Ops - Accounting` user **cannot** complete Invoice Preparation for any customer who already has an open Debt Collection task. Repeat hospitals are the normal case. Code-certain. |
| **G1 + C2** | The Invoice Preparation task can become permanently uncompletable, by two independent routes | Both reachable in routine operation: (a) client returned everything unused, (b) item is covered by an active tender. No in-app recovery, not even as Administrator. |
| **G5** | Every financial field on Dispatch Case is written via `frappe.db.set_value` on fields declared `allow_on_submit = 0` | No validation, no version history, **no audit trail on any money field**. Becomes critical the moment the underlying document stops being user-visible (§2). |

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

---

## 3. Symptoms you may already be seeing

Business-readable translation, for triaging against support history rather than waiting on write tests.

| Symptom a user would report | Finding |
|---|---|
| "I can't finish my invoice task — it says I'm not allowed to edit a Debt Collection task I never opened" | C1 |
| "The invoice task won't close. It says no Sales Invoice is linked and there's nothing I can do" | G1 |
| "The invoice won't submit — it says the rate must equal the tender price" | C2 |
| "This case says Payment Pending but the customer paid months ago" | G2, G6 |
| "The customer paid a deposit but accounting says we never received it" | G3 |
| "Who changed the outstanding amount on this case?" — no answer available | G5 |
| "This report says the client owes us, the ledger says they're in credit" | G3, G6 |
| "Profit on this case looks far too high" | G9 |
| "Nothing tells us what to do with the implant the hospital lost" | G12 |
| "Which of these two debt reports is the right one?" | G17 |

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

## 7. Recommendations

Three bands, ordered within each. Effort is relative sizing (S / M / L / XL), not a schedule.

**Acceptance criteria name the role the test must be run as.** The group-3 lesson is that privileged testing hides role-gated defects — several items below are invisible when tested as System Manager or a Director.

### Band 1 — Blockers

| ID | Action | Fixes | Effort | Acceptance criteria | Owner | Status |
|---|---|---|---|---|---|---|
| **R1** | Unify the acceptance/permission gate into one script with one bypass contract: system writes bypass via a single agreed mechanism, the role check applies only to the task the *user opened*, and Administrator exemption is decided once and applied uniformly | C1 | M | As a user holding **only `Ops - Accounting`**, complete Invoice Preparation for a customer who already has an *unaccepted* open Debt Collection task. Must succeed, and the second invoice must appear in `open_invoices`. | | Not started |
| **R3** | Turn invoicing into one explicit, idempotent, precondition-checked action: refuse if a non-cancelled invoice exists; if no line qualifies, **do not create the Invoice Preparation task** — route to a "nothing to invoice / close case" outcome; resolve rate tender-first; populate `hospital` / `doctor_name` / `hospital_branch`; add a `dispatch_case` Link on Sales Invoice; set tax and payment-terms templates explicitly | G1, G11, G13, part of C2 | L | As **`Ops - Accounting`**: (a) a case where every item was returned unused produces no zombie task; (b) a tender-covered case submits first time; (c) the invoice carries VAT, a real `due_date`, hospital and doctor. | | Not started |
| **R4** | Server-side price resolution in strict precedence — active Tender Agreement price → customer-specific `Item Price` → `Standard Selling` → refuse. Gate DC submission on every row having a resolved price | C2, G8 | M | As **`Ops - Order Creating`**: adding a tender-covered item yields the tender price without manual entry; a DC with any zero-price row cannot be submitted. | | Not started |
| **R5** | Stop bypassing stock validation: remove `ignore_validate` and `ignore_stock_validation`; require `client_location_warehouse` whenever any client-location movement occurs; drop `allow_zero_valuation_rate` so consuming un-valued stock fails loudly; raise a blocker task on failure instead of submitting an empty entry | G7 | M | A no-return case with a blank client warehouse is refused at Order Entry, not silently posted. Every consumption Stock Entry produces SLE rows. **Requires the migration below.** | | Not started |
| **R5-M** | *Migration, prerequisite to R5:* reconcile the 18 inert Material Issues, the −218 units of negative stock in `Main - Inmed`, and the 3 cases with `client_location_warehouse = "Main - Inmed"` | data | M | Zero negative bins; no submitted Stock Entry with a warehouse-less row. | | Not started |
| **R6** | Call `pe.submit()` in `advance-payment.py`. An advance becomes a submitted unallocated Payment Entry, allocated against the invoice when it exists. Retire `DC.prepaid_amount` as an independent number; derive prepayment from unallocated Payment Entries | G3 | S | As **`Ops - Finance`**: recording an advance produces GL entries immediately, and customer net receivable in the ledger matches the workflow view. | | Not started |
| **R6-M** | *Migration:* resolve the 5 draft customer Payment Entries (submit or cancel, per Accounting) | data | S | No draft `Receive` Payment Entries remain. | | Not started |
| **R7** | Declare `allow_on_submit = 1` on `sales_invoice`, `total_invoice_amount`, `outstanding_amount`, `prepaid_amount`, `profit`, the stock-entry links and `invoice_task`; write them through `doc.save()` | G5 | S | Changing any financial field produces a `tabVersion` row naming the user. | | Not started |

### Band 2 — Should fix

| ID | Action | Fixes | Effort | Acceptance criteria | Owner | Status |
|---|---|---|---|---|---|---|
| **R2** | Make ERPNext the single source of receivables truth. The Debt Collection task stops **storing** balances and becomes a view plus an action: outstanding read live from Sales Invoice / GL at render; `open_invoices` a computed display; only amount / method / reference writable. Delete `total_paid_amount` and `available_advance_credit` | G4, G6, G15, G16 | XL | As **`Ops - Finance`**: the task's outstanding figure always equals the sum of linked Sales Invoice outstanding amounts, with no stored copy. Task cannot be completed while outstanding > 0. | | Not started |
| **R2-M** | *Migration:* reconcile the 3 Completed and 5 Open Debt Collection tasks, including the 2 completed with outstanding debt and the 4 with NULL customer | data | M | No Completed Debt Collection task with non-zero outstanding. | | Not started |
| **R9** | Derive Dispatch Case status on read from the documents that exist; or, as the pragmatic step, add one reconciliation routine on Payment Entry submit that recomputes outstanding and closes at zero. Remove `Invoiced` from the options | G2 | M | A fully paid case reaches `Closed` without manual intervention. | | Not started |
| **R8** | Replace the hand-rolled profit calculation with `Sales Invoice Item.incoming_rate` / ERPNext Gross Profit. Compute per-case figures on read rather than storing them. **Depends on R5.** | G9, G10 | M | Profit for a case matches ERPNext's Gross Profit report for the same invoice; no profit is written to Draft cases. | | Not started |
| **R10** | Move Payment Entry creation out of `before_save` into `after_save` or a whitelisted "Record Payment" endpoint with an idempotency key. Fold into R2 | G14 | S | Recording a payment twice in rapid succession produces one Payment Entry. | | Not started |
| **R11** | Create a `Write-off Approval` task when any row has `lost_damaged_qty > 0`, with invoice / write-off / replace outcomes and matching stock and GL postings | G12 | M | As **`Ops - Returns`**: completing an inspection with a lost item produces a Director-owned task; the stock leaves `Returns - Inmed` only via its resolution. | | Not started |

### Band 3 — Later

| ID | Action | Fixes | Effort | Acceptance criteria | Owner | Status |
|---|---|---|---|---|---|---|
| **R12** | Reporting cleanup: resolve the 3 duplicate pairs (keep the GL/reference-based versions), fix the 2 broken shortcuts, remove the 2 dead task VIEWs, either build the 3 KPI reports or delete and relabel the workspace, add one report over `DC.profit`. **Do after R4/R5/R8** — reports built earlier only render wrong numbers more attractively | G17 | M | No duplicate or 404 report links; KPI workspace either populated or removed. | | Not started |
| **R13** | Define the credit-note / refund path: ERPNext credit note (`is_return = 1`) plus refund Payment Entry, with Director approval | — | M | An over-billed submitted invoice can be corrected in-system. | | Not started |
| **R14** | Re-enable money notifications (invoice submitted, payment received, threshold breached) once the figures are trustworthy | G17 | S | Finance/Directors receive Telegram notification for each event. | | Not started |
| **C3/C4** | Consolidate the split Delivery photo rule into one owner; move module-level `get_doc_before_save()` calls inside their `task_kind` filters | C3, C4 | S | One file owns the Delivery photo rule. | | Not started |

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

## 9. Sequencing

Dependency order matters more than the band ratings.

1. **Unblock the flow — R1.** Nothing else can be tested end-to-end by a non-privileged user until this lands.
2. **Stop creating stuck tasks — R3 + R4 together.** Same code path; R4 is the precondition that makes C2 unreachable.
3. **Repair stock and costing, strictly in this order — R5 → R5-M → drop `allow_zero_valuation_rate`.** Reversing it makes submissions fail on historical data.
4. **Trivial correctness — R6 + R6-M, R7.**
5. **Simplify the model — R2 with R2-M, R9, R10.**
6. **Then delete code — R8.**
7. **Presentation last — R11, R12, R13, R14, C3/C4.**

---

## 10. Outstanding verification

| # | Question | Method | Priority |
|---|---|---|---|
| **V1** | Confirm C1 empirically: does an `Ops - Accounting` user completing Invoice Preparation for a customer with an existing open Debt Collection task actually throw? | Controlled write test on TEST **as a non-privileged Accounting user** | Critical |
| **V2** | Confirm G1 empirically: complete a returns inspection where all items were returned unused | Controlled write test on TEST | High |
| **V3** | Is prod's master data configured — item valuation rates, `Item.standard_rate`, default tax template, customer payment terms? **G8 and G13 severity, and therefore the R4 / R3 ratings, are provisional until this is answered.** | Read-only query set against prod — **explicit approval required** | High |
| **V4** | Correct Armenian VAT template and payment terms | Business input | High |
| **V5** | Cleanup scope and disposal decisions for existing bad data (feeds R5-M, R6-M, R2-M) | Business decision with Accounting | Medium |
| **V6** | Task-native invoicing: does the Invoice task edit a draft Sales Invoice, or edit the Dispatch Case with the invoice generated and submitted in one atomic commit? Does Accounting actually want a task-side editor, or a correct pre-filled invoice plus the native form? | Design decision with Accounting — see §2 | High |
