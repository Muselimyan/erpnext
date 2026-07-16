# Held-at-Client Items — Design Plan

## Purpose

Today the Dispatch Case model (Doc 16) only recognizes three outcomes for a dispatched item: `Returned`, `Lost/Damaged`, or `Used`. `used_qty` is computed as `dispatched_qty - returned_qty - lost_damaged_qty`, and everything in that bucket is immediately issued out of the client location warehouse via a Consumption Stock Entry and invoiced.

In practice, a clinic sometimes keeps unused items at their location without using them — they are not brought back by the driver, but they were also not consumed. Today this case has no home: if Returns Team records it as `returned_qty`, that's physically false (nothing came back). If they leave it out, it silently becomes `used_qty` — the item gets deducted from the client's stock and invoiced even though it was never used. This also breaks the Doc 11 inventory-truth rule that company-owned stock physically at a client location must remain in that client's warehouse in the stock ledger.

This plan adds a fourth outcome, **Held**, without introducing a new persistent ledger DocType. Held quantity stays in the `client_location_warehouse` (no Stock Entry is posted for it — it simply isn't touched), is excluded from invoicing, and is tracked/resolved through fields on the existing `Dispatch Case Item` rows plus a lightweight follow-up task, mirroring the existing `Debt Collection` task pattern.

## Decisions

| Area | Decision |
|---|---|
| New outcome bucket | `Dispatched = Returned + Used + Lost/Damaged + Held` |
| Persistent ledger DocType | **No.** Outstanding held quantity is computed on demand from `Dispatch Case Item` rows, not maintained in a separate master table. |
| Stock movement for held qty | None — held qty is left in place in `client_location_warehouse`; Consumption SE issue_qty becomes `dispatched - returned - held` |
| Task-scoped display table | One small child DocType (`Held Stock Followup Line`), same pattern as `Debt Collection Invoice` / `Debt Collection Payment` — exists only to render the follow-up task's table, not to persist state |
| Resolution — Used | Stock is deducted **immediately** (Consumption SE) when resolved as Used. Invoice is **deferred** and folded into the customer's next Dispatch Case invoice, with lines clearly labeled as carried over. |
| Resolution — Returned | Immediate standard return Stock Entry chain (`client_location_warehouse → Return Pickup In-Transit → Returns WH`). No invoice implication. |
| Resolution — Lost/Damaged | Immediate write-off from stock **and** billed as a fee at `unit_price`/`discount_pct` — same policy as immediate Lost/Damaged (see "Lost/Damaged billing policy" below). Fee follows the same deferred-invoice mechanic as Used. |
| Lost/Damaged billing policy | Both immediate Lost/Damaged (recorded at Returns Inspection) and held-then-discovered Lost/Damaged bill a fee at the row's normal `unit_price`/`discount_pct` — one consistent policy, no special-casing by timing. Previously this was an undecided gap (see `docs/implementation-questions.md` #17 and `docs/12-surgery-set-operational-workflow.md` §7.3); now resolved. |
| Escape hatch | Manual "Invoice Now" action on the follow-up task, so Accounting can force a standalone invoice for a customer who doesn't place a new order for a long time, instead of the pending-invoice balance sitting forever. |
| Aging follow-up automation | New scheduled script, same pattern as `Scheduled-debt-collection`, creates/updates one open `Held Stock Follow-up` task per customer. |
| Aging threshold configuration | **Per-customer** field on `Customer` (mirrors `debt_threshold_amd`), not a single global constant and not per-item. |
| Auto-offer at next order | When a new Dispatch Case is created for a customer with outstanding held stock, offer to resolve it as part of that case, using the same resolution function as the follow-up task. |
| Serial accountability | Add `Held at Client` as a new value in the existing tool-serial-exception reason enum (alongside Missing / Damaged / Not Serialized) so intentionally-held serial tools are not falsely flagged as lost at the `Invoiced → Closed` close gate. |

## Added `Dispatch Case Item` fields (and legacy `Surgery Case Item`)

| Field | Type | Purpose |
|---|---|---|
| `held_qty` | Float | Set by Returns Team at inspection — quantity the client keeps, not used, not returned |
| `held_serial_no` | Small Text | Which serial(s) are held, for serial-tracked items |
| `held_batch_no` | Link → Batch | Which batch is held, for recall/report display |
| `held_used_qty` | Float, default 0 | Running total of held qty later resolved as Used (supports partial resolution) |
| `held_returned_qty` | Float, default 0 | Running total of held qty later resolved as Returned |
| `held_lost_qty` | Float, default 0 | Running total of held qty later resolved as Lost/Damaged |
| `held_invoiced_qty` | Float, default 0 | How much of `held_used_qty + held_lost_qty` has actually been folded into an invoice so far (both are billable at `unit_price`/`discount_pct` under the same deferred mechanic) |
| `held_resolution_log` | Small Text / Long Text | Append-only audit trail: date, qty, resolution type, reference document, per event |

Formula changes:
```
used_qty = dispatched_qty - returned_qty - lost_damaged_qty - held_qty
```
Consumption Stock Entry issue_qty (at Returns Inspection completion) becomes:
```
issue_qty = dispatched_qty - returned_qty - held_qty   (was: dispatched_qty - returned_qty)
```

"Outstanding held" for a customer/item, computed on demand (not stored):
```
outstanding = held_qty - held_used_qty - held_returned_qty - held_lost_qty
```
Stock Balance on `client_location_warehouse` remains the physical cross-check for this number.

## New Customer field

| Field | Type | Purpose |
|---|---|---|
| `held_stock_threshold_days` | Int | Per-customer aging tolerance before a held item surfaces on a Held Stock Follow-up task (mirrors `debt_threshold_amd`) |

## New Task Kind: `Held Stock Follow-up`

**Default assignee:** Directors Team (same ownership model as the existing `Debt Collection` task — both represent an aging balance owed by/to the company that Directors track)
**Created by:** scheduled server script (mirrors `Scheduled-debt-collection`)

**Contains:**
- Customer name
- Table of outstanding held lines (via `Held Stock Followup Line` child rows, recomputed each run): Dispatch Case, Item, Qty Outstanding, Batch/Serial, Held Since, Age (days)
- Resolution controls per line: mark qty as Used / Returned / Lost-Damaged (supports partial qty)
- "Invoice Now" button (escape hatch) — forces a standalone Sales Invoice for any `(held_used_qty + held_lost_qty) - held_invoiced_qty` balance instead of waiting for the next case

**One active task per customer**, updated with the latest outstanding balance — same rule as the existing `Debt Collection` task (Doc 16, Task 6.10).

**On each resolution recorded:**
- Used → Consumption SE posted immediately from `client_location_warehouse`; `held_used_qty` incremented; invoice deferred to next case (see below)
- Returned → standard return SE chain posted immediately; `held_returned_qty` incremented
- Lost/Damaged → write-off posted immediately from `client_location_warehouse`; `held_lost_qty` incremented; **fee** invoice deferred to next case (same mechanic as Used) or via "Invoice Now"
- Task auto-completes when all its lines reach `held_used_qty + held_returned_qty + held_lost_qty == held_qty`

## Deferred invoicing mechanic

When a held line is resolved as Used, no invoice is created at that moment. Instead:

1. `held_used_qty` (or `held_lost_qty`, for a fee) is incremented; `held_invoiced_qty` is left unchanged, creating a pending balance.
2. At the customer's **next Dispatch Case**, the invoice-creation logic (both the no-return path — Task 6.4 Delivered — and the return path — Task 6.7 Returns Inspection completion) additionally queries all of that customer's Dispatch Case Items where `(held_used_qty + held_lost_qty) > held_invoiced_qty`.
3. Those balances are appended as extra lines on the new draft Sales Invoice (item, qty, unit price/discount carried over from the original row), labeled e.g. `"(carried over — held from DC-0123)"` so Accounting sees the context before submitting (per the existing Task 6.9 review step).
4. `held_invoiced_qty` is updated to match once the invoice is created.

If a customer never places another order, the pending balance is caught instead by the "Invoice Now" escape hatch on the Held Stock Follow-up task.

## Next-order auto-offer

When Order Creation opens a new Dispatch Case for a customer with outstanding held stock (per the same on-demand query used by the follow-up task), the form shows a banner, e.g.:

> "Client already holds Item Y ×3 from DC-0123 (held 12 days) — resolve as Used or Returned as part of this case?"

Accepting calls the same resolution function used by the Held Stock Follow-up task, just triggered from a different entry point.

Important: accepting this offer only appends a line to the new case's **Sales Invoice** at invoice-creation time (or increments the deferred-invoice balance, per the mechanic above). It must **not** add a row to the new case's `Case Items` table — that table drives Pack/Inventory picking and serial/batch verification, and nothing is being freshly dispatched for a resolved held quantity.

## Serial accountability change

The existing tool-serial-exception reason enum (used at the `Invoiced → Closed` close gate to ensure every dispatched serial is accounted for) gains a new value: `Held at Client`. A serial recorded in `held_serial_no` at Returns Inspection satisfies the close gate via this reason instead of being treated as Missing.

## Worker flow after implementation

1. Delivery happens as today (Doc 16, Task 6.4).
2. At Returns Inspection (Task 6.7), Returns Team fills `returned_qty`, `lost_damaged_qty`, and now also `held_qty` (+ `held_serial_no`/`held_batch_no` where relevant) per item.
3. Case closes normally: Consumption SE only covers the true `used_qty`; held quantity is left untouched in `client_location_warehouse`.
4. A scheduled script watches held balances against each customer's `held_stock_threshold_days` and opens/updates a `Held Stock Follow-up` task when a customer crosses their threshold.
5. Returns/Order team calls the client, resolves lines as Used / Returned / Lost-Damaged (fully or partially).
6. Used resolutions post stock immediately but wait for the customer's next case to be invoiced (or use "Invoice Now" if the customer goes idle).
7. When the customer's next Dispatch Case is invoiced, any pending held-usage balance is automatically appended to that invoice.

## Important limitations of this plan

- This is a design plan only — no schema or server-script changes have been made yet.
- Assumes Returns Team can reliably distinguish "client is holding this, will decide later" from "returned" and "lost" at inspection time; no attempt is made to detect this automatically.
- The deferred-invoice mechanic means revenue for held-then-used (or held-then-lost) items is not recognized until the next case exists (mitigated by the manual escape hatch, not fully eliminated).
- `held_resolution_log` is a free-text append-only field, not a structured/queryable table. This is an accepted trade-off to avoid a new ledger DocType — cross-customer reporting on resolution history (e.g. "all resolutions last month") would require parsing this text or building a small structured child table later if that reporting need becomes important.

## Next steps (not yet started)

1. Add the new fields to `Dispatch Case Item` / `Surgery Case Item` schema.
2. Add `held_stock_threshold_days` to `Customer`.
3. Create `Held Stock Followup Line` child DocType.
4. Add `Held Stock Follow-up` to the `task_kind` options and Task Access Policies.
5. Update `Dispatch-Case-before-save` (used_qty formula) and the Returns Inspection completion logic in `Task-after-save-dispatch-flow` (consumption issue_qty, held field handling, lost/damaged invoicing per the policy fix in `docs/12-surgery-set-operational-workflow.md` §7.3 and `docs/16-unified-dispatch-flow.md` Task 6.7).
6. Write the new scheduled script (aging follow-up, mirroring `Scheduled-debt-collection`).
7. Write the resolution function (shared by follow-up task and next-order banner) and the deferred-invoice append logic in both invoice-creation paths.
8. Add `Held at Client` to the serial-exception reason enum.
9. Extend the relevant deploy script (new `held-at-client-items-deploy.ps1`, following the idempotent Check/Deploy pattern used by `doc16a-deploy.ps1`).
10. Add outstanding held balances (per customer/item, held vs pending-invoice vs resolved) to the reporting pack (Doc 13/15), alongside the existing "items currently at client location" reports.
