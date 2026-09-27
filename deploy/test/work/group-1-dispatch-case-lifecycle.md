# Group 1 — Dispatch Case Lifecycle

> **Scope.** Test server only. Dispatch Case operational flow: task chain, packing, scanning, returns, stock movement, access control.
>
> **Excludes.** Financial tail — invoicing, payments, pricing basis, debt episodes, closure. See **Group 11**.
>
> **State.** D1–D6 deployed and verified 2026-09-22/23, against a schema export taken after the work (`export.ps1`). This document covers **what is still open**. Implementation, deploy and verification scripts are in `deploy/test/deploy/group-1-dispatch-operational/`.

---

## 1. Open work

### D7 — Two dead Dispatch Case fields — **DONE, VERIFIED**

`delivery_photo` and `return_dropoff_photo` deleted. DocType went from 34 fields to 32; surviving field order asserted identical before the write, and re-read afterwards to confirm. Full prior definition snapshotted to `snapshots/d7-dispatch-case-doctype-before-*.json` for rollback.

**`photo_section` was deliberately kept.** It looks equally dead once the two fields go, but it is the mount point `Dispatch Case-Photo-Galleries.js` inserts the galleries into, and `Dispatch Case-Simplify for Order Creation.js` hides it during order entry. The gallery script copes with the section being empty — it falls back to appending to the section wrapper — so an empty section is fine; deleting it would have moved the galleries somewhere uncontrolled.

### D8 — the `_assign` sync in `Task-before-save-policy` cannot work

**Established from Frappe's own source and field definitions, not from the state of existing records.** An earlier version of this entry cited "3,232 tasks with an empty column" as though it were evidence; it is not — the test data is junk and proves nothing about the code. That number has been removed.

What the framework says (`d8-assign-mechanism.py`):

| Probe | Result |
|---|---|
| `_assign` is a defined DocField on Task | **No** — it is a framework column |
| `_assign` in `frappe.model.optional_fields` | **Yes** |
| `_assign` in `Document.get_valid_columns()` | **No** |
| Fresh task with `custom_assigned_to` set → `_assign` in DB | `null` |
| Same task, `custom_assigned_to` in DB | persisted correctly |
| After `frappe.desk.form.assign_to.add()` → `_assign` in DB | `["e2e.returns@test.erpnext.am"]` |

`get_valid_columns()` is the set of columns a document write emits. `_assign` is excluded from it, so **`doc.set("_assign", ...)` can never reach the database** — not a bug in the sync, a category error about what that field is. Frappe treats `_assign` as framework-managed and expects `assign_to.add()` to maintain it, which the probe confirms works.

Two consequences:

- The sync line in `Task-before-save-policy` is **dead as far as the database is concerned**. `make_task` works only because it uses `frappe.db.set_value` *after* insert, which bypasses the document layer.
- **It is not dead in memory, and that matters.** `doc.set()` still attaches the value to the in-memory object, and D3's role check reads it there — proven by `d3-verify`, where check 2 refused a wrong-role task, which it can only do when it sees exactly one assignee. **Deleting the line would silently disable the role check.** It looks like dead code and is load-bearing.

#### Why the sync exists, and what actually breaks

`_assign` is what the **Task list view** filters on. `Global-Mobile Back Button List.js` builds its toggles from it:

```js
if (ts.my_tasks)  orFilters.push(["Task", "_assign", "like", "%" + safeUser + "%"]);
// team view:
orFilters.push(["Task", "_assign", "is", "not set"]);
orFilters.push(["Task", "_assign", "like", "%" + teamPlaceholder + "%"]);
```

So `_assign` is how a person **finds** their work — and therefore how they reach a task in order to accept it. That is what the sync was for.

**The user-visible consequence is real, not cosmetic.** A task assigned to a person but created outside the dispatch flow has an empty `_assign`, so it does **not** appear under "My Tasks". It falls into the team pool instead, looking unassigned when it is not. The main flow escapes this only because `make_task` writes the field separately with `frappe.db.set_value` after insert — tasks created any other way do not get that.

**Start at:** decide whether the Task form should use Frappe's own mechanism (`assign_to.add()`, which also creates the ToDo that drives notifications) or keep `custom_assigned_to` as the single source of truth and have the list view filter on that instead of `_assign`. Either is defensible; the present state — a sync that cannot work, a list view depending on it, and a permission gate quietly depending on its in-memory side effect — is not.

If the sync line is removed, **both** the role check and the list-view filter must be rewritten in the same change.

### D9 — Negative stock — **DONE, VERIFIED**

`Stock Settings.allow_negative_stock` set to **0**. D1 had restored ERPNext's own check, but a check cannot overrule a setting declaring the thing it checks for permitted — so an overdraw still posted. Now refused.

```
SETTING allow_negative_stock is off    PASS   value=0
NORMAL pack still succeeds             PASS   2 SLE, in-rate 6.0
NORMAL pack still carries valuation    PASS   rate 6.0
OVERDRAW is refused                    PASS   999949 units of Item 3146-60300...
```

Existing records deliberately not repaired. The 13 already-negative items in `Main - Inmed` will now **fail** any operation drawing on them. That is the intended behaviour.

### D9b — Batch, serial and expiry tracking are off — **DEFERRED, own workstream**

Tracked separately, like the cancel flow. Too large and too consequential to carry as a Group 1 line item. Recorded here so the reasoning is not lost.

Two API utilities switched tracking off across every Item, and both are still deployed and callable:

- `disable_all_item_batch_serial_for_now` — clears `has_batch_no` / `has_serial_no` / `has_expiry_date` on **all** items
- `perm_disable_batch_expiry_dbset` — the same for a named list

For a medical device distributor this is the most consequential override of the set: **batch and expiry are the recall traceability mechanism.**

**It cannot simply be switched back on.** With batch tracking enabled, the now-strict `create_se` requires `batch_no` on every Stock Entry row, and `dispatch_case_packing_scan` only captures a batch when GS1 parsing succeeds. Any item scanned by a plain barcode, or keyed in by hand, would produce a row with no batch and the movement would be refused — packing would break.

**Needs a plan, not a toggle:** what proportion of stock carries GS1 barcodes, what the fallback is for items that do not, and whether tracking is enabled per-item or globally. Leaving the two utilities callable also means the override can be silently re-applied; they should be retired as part of the same change.

### D10 — 372 pre-existing malformed Stock Entries

Submitted, with warehouse-less rows. Two populations, and the second is worse than the audit originally described:

| Count | Shape | Effect |
|---|---|---|
| 172 | Material Issue, blank source | Posted **nothing** — inert. Exactly matches the 172 SEs with no ledger entry |
| 200 | Material Transfer, one side blank | **Did post.** Stock created or destroyed rather than moved |

D1 stops new ones being created. It does not repair these. Test data is synthetic and deliberately unreconciled, so this is cleanup scope, not a blocker.

### D11 — Cancel flow — **IMPLEMENTED**

A Dispatch Case can be cancelled in `Draft`, `Awaiting Approval`, `Confirmed`, `Packed` or `In Transit`. Specification: `docs/16` §10A. Design: `cancel-flow-design.md`. Verified 62 of 62; full regression 305 of 305.

Two consequences outside the cancel flow itself, both system-wide:

- **`Cancelled` is immutable for every task**, exactly like `Completed`. Before, only the client-side script locked a cancelled task, so a privileged user could reopen one.
- **Six reports had never run**, because a PowerShell backtick-t had corrupted their table names. `RPT - Dispatch Case Aging` was repaired here; the other five are Group 10 F-032.

### D12 — `task_mark_items_packed_batch` has no caller — **RESOLVED: kept, documented**

No enabled client script calls it. **Decision: keep it.** A "tick every item at once" control on the packing screen is still a reasonable thing to want — packing a 40-line surgical kit one checkbox at a time is slow — and the back end is ready for it.

A block comment at the top of the script now records that nothing calls it, why it is retained, how to use it (`mode` plus a JSON list of row names), and that it should be deleted outright if a decision is taken that the bulk control will never be built. It is hardened to the same standard as the endpoints in use, since an entry point with no screen is still reachable by name.

### D13 — `Task-Packing Checkboxes.js` would break if re-enabled

Disabled, and still sends `item_idx` / `packed_indices`. D2 made the server refuse both. If it is ever re-enabled it must be updated first.

**A third caller was missed and has been fixed.** `deploy/test/deploy/group-11-financial-tail/w12-verify-lost-damaged.py` also sent `item_idx`, so D2 broke W12's verification harness. The caller inventory taken for D2 grepped `work/client` and `work/server` but not `deploy/` — a contract change has to be searched for across the whole repository, not just the runtime tree. Fixed to send `row_name`, re-run, 14/14 PASS. Its closing notes also claimed A2 was still open and have been corrected.

---

## 2. What was done

| ID | Change | Verification |
|---|---|---|
| **D1** | `create_se` lost the `strict` parameter and all three bypasses — `ignore_validate`, `ignore_stock_validation`, `allow_zero_valuation_rate`. `client_location_warehouse` now required on **every** order, not only when returns are expected | 7/7 + regression re-run after D3 |
| **D2** | Packing/scan/returns endpoints assert the **task kind**, not just "any accepted task". Rows addressed by `row_name`, not array position. `task_remove_dispatch_product` gained the lifecycle guard its two siblings had | 16/16 |
| **D3** | Assignment invariant re-enabled (all three checks). `office.team@example.com` granted `Ops - Order Accepting` | 8/8 |
| **D4** | Retired `Order accepting` and `Dispatch picking / hand-off`; field default moved to `Order entry` | 3/3 |
| **D5** | Deleted `Dispatch Case.profit` and its allow-list entry in both access-control twins | 2/2 |
| **D6** | `Returns restocking` now requires a photo. Deleted the `surgery_set_type` property setter and the unused `tab_is_admin()`. Corrected a comment that promised a safety net in a disabled script | 7/7 |

### End-to-end — one case through the whole chain, **45/45**

Every workstream above verified its own hop with a seeded fixture — a case placed directly into the state that hop begins from. That proves each hop and says nothing about the joins between them. `e2e-full-chain.py` drives the real sequence in one run, each step performed by the role that performs it, with nothing short-circuited: tasks accepted through `dispatch_task_accept`, products added through `task_add_dispatch_product`, quantities set through `task_update_return_item_quantities`, the invoice raised through `task_commit_invoice`.

Order entry → Pack → Delivery → Return Call → Pickup → Inspection → Restocking → Invoice, with a 10-unit order resolving to 6 used, 3 returned, 1 damaged.

Every seam asserted — each hop must create the next task, and each must move stock to the right warehouse:

```
1 accept auto-creates a Draft Dispatch Case      PASS
1 completing Order entry SUBMITS the case        PASS
2 transfer preserved valuation                   PASS   out 6.0 -> in 6.0
3 stock reached the client warehouse             PASS
5 return transit emptied                         PASS
6 used computed as dispatched - returned - lost  PASS   used=6.0
6 lost/damaged segregated to Lost & Damaged      PASS   0.0 -> 1.0
6 SEAM: Write-off Approval raised for the loss   PASS
7 returned goods went back to Main               PASS   45.0
8 invoice bills the USED quantity only           PASS   invoiced qty=6.0
8 case reached a terminal state                  PASS   Payment Pending
9 CONSERVATION: Main fell by used + lost = 7     PASS   6 used + 1 lost
```

The closing assertion is the one worth keeping: **stock conservation.** Both transit warehouses and the client warehouse return to their starting balances, Lost & Damaged retains exactly the damaged unit, and Main falls by precisely used + lost. A chain that moves stock correctly at every individual hop but loses a unit between two of them passes every other test in this directory and fails that one.

### The two assertions that mattered

```
PACK valuation PRESERVED across transfer    PASS   out 6.0 -> in 6.0
RESTOCK leaves Main valuation unchanged     PASS   6.0 -> 6.0
```

`ignore_validate` skipped `set_basic_rate`, so every Material Transfer arrived valued at **zero** regardless of source value. `Main → Delivery In-Transit` destroyed valuation on the first hop, every later hop inherited zero, consumption posted zero COGS, and the restock pushed zero-valued stock back into Main — dragging its moving average down on every returns cycle, compounding indefinitely. The second assertion is the proof that this is gone.

### Verified confirmed on the current export

| Fact | Value |
|---|---|
| `task_kind` default | `Order entry` |
| Retired kinds present | none |
| Held-back kinds present | both, intentionally |
| Dispatch Case custom fields | `custom_select_surgical_kit_template` only |
| `surgery_set_type` property setters | none |
| Bypasses in deployed flow code | none |
| D3's three checks live | yes |

---

## 3. Traps specific to this area

| | |
|---|---|
| **The Dispatch Case gate is coarse on purpose** | `Dispatch-Case-before-save-submitted-access-control` asks only whether the user holds *any* accepted task on the case. Order entry, packing and returns all legitimately write `case_items`, so the document cannot know which is valid. Kind-specific authority belongs in the endpoint. **Do not "tighten" the DC gate** — D2 fixed this at the right layer |
| **The gates self-heal, which hides assignment problems** | `Task-before-save-policy` (~line 70) auto-assigns the kind's `default_team_user` when `custom_assigned_to` is blank, then re-syncs `_assign`. 23 of 25 policies have a default team, so a task cannot reach the completion check with zero owners. Tests that clear `_assign` and expect a refusal will pass for the wrong reason |
| **A policy's `default_team_user` must hold one of that policy's own `allowed_roles`** | Otherwise every task the flow creates of that kind throws on its first save — the D3 role check has no status guard. `office.team` held **no roles at all** while being default for `Return Call`, which would have broken the returns branch for all new cases. `d3-verify` checks all 25 policies; keep that check |
| **Batch and serial tracking are globally disabled** | `disable_all_item_batch_serial_for_now` clears `has_batch_no` / `has_serial_no` / `has_expiry_date` on every Item. This is why D1's strict mode does not demand batch numbers. If tracking is ever re-enabled — and for implant recall traceability it must be — strict mode will require `batch_no` on every row, and the packing scan only captures it when GS1 parsing succeeds. **That interaction needs designing before batch tracking returns** |
| **Manual packing tick is intended behaviour** | `task_mark_item_packed` sets `custom_scanned_qty` to the full dispatched quantity, so ticking every box satisfies the completion gate with no barcode read. Accepted: the gate's message says "packed", not "scanned". The scan path additionally records `custom_last_scanned_barcode` / `_at` / `_by`, so the two are distinguishable if that is ever wanted |
| **Verification must not run as Administrator** | Privileged users are exempt from the access-control gates, so the Administrator-only e2e API suite is structurally incapable of catching this defect class (Group 11 A5). Every `d*-verify-*.py` here runs as `e2e.*` role users via `bench console` and rolls back |
| **An assertion must read code, not comments** | D1's deploy guard initially refused a correct change because the file mentioned `ignore_validate` in the prose explaining its removal. Strip comments before asserting. The same trap caught a D6 test that matched a misleading sentence quoted verbatim inside its own correction |

---

## 4. Finding-ID map

| Old ID | Outcome |
|---|---|
| ACT-01, ACT-02 | Fixed D2 — kind assertion; explicit `mode` replaces `mytasks[0]` inference |
| ACT-03 | Fixed D2 — lifecycle guard on `task_remove_dispatch_product` |
| ACT-04 | Fixed D6 — `Returns restocking` photo gate |
| ACT-05 | Fixed D1 — client warehouse required on every order |
| ACT-06 | Fixed D1 — all three bypasses removed. Residual: **D9** (`allow_negative_stock`) |
| ACT-07 | Fixed D3 — all three checks enforcing |
| ACT-08 | Fixed D5 — field and both allow-list entries deleted. Report deferred to Group 11 A1 |
| ACT-09 | Fixed D2 — rows addressed by name |
| ACT-10 | Fixed D2 — client sends `row_name`; the stale-scan path is gone with it |
| ACT-11 | **Closed — D11** (cancel flow implemented) |
| ACT-12 | Fixed D4 — two retired, two held back on purpose |
| ACT-13 | Partly fixed D6 — property setter deleted. Two DocFields remain: **D7** |
| ACT-14 | Fixed D6 — header corrected to `Enabled: 1`, matching the server |
| ACT-15 | Fixed D6 — `tab_is_admin()` deleted, comment corrected. `user_has_allowed_role()` **kept**: D3 re-enabled its caller |
| ACT-16 | Group 11 **A1** |
| V-01 | Closed — W12 schema confirmed present |

---

## 5. Where the implementation lives

| | |
|---|---|
| Deploy + verify scripts | `deploy/test/deploy/group-1-dispatch-operational/` — `d0*` are read-only audits; `d1`–`d9` are `.ps1` + paired `-verify-*.py`; `e2e-full-chain.py` is the whole-chain walkthrough |
| Lint the console scripts | `python deploy/test/deploy/group-1-dispatch-operational/_lint.py` — these are piped into IPython, which treats a blank line as end-of-block. A blank line inside the function body **silently truncates the script** and it appears to do nothing. Run this before piping anything |
| Architectural rules | `AGENTS.md` |
| Flow specification | `docs/16-unified-dispatch-flow.md` |
| Task-kind matrix | `docs/21-task-kind-field-visibility-matrix.md` — **needs updating**: its Group A still lists the kinds retired in D4, and its §422 discrepancy list predates TFV/TFE ownership |
