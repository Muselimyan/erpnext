# Go-Live Action Plan

Distilled from `migration-notes.md`. Only open items are listed here. Items that are completed or that have been formally superseded are omitted.

Last updated: 2026-06-01

---

## Legend

- 🔴 **Blocker** — system will fail or produce wrong data without this
- 🟡 **Pre-go-live** — must be done before first real transaction; not a hard crash but operationally broken
- 🟢 **Post-go-live** — can be deferred; will not block the first sale

---

## 1. Real Users & Role Assignments

| # | Item | Priority | Why |
|---|---|---|---|
| 1.1 | Replace the 7 `@example.com` sample users with real staff emails + secure passwords | 🔴 | Sample accounts have known credentials; leaving them open is a security risk |
| 1.2 | Assign staff to **all** operational roles: `Ops - Order Accepting`, `Ops - Inventory`, `Ops - Returns`, `Ops - Delivery`, `Ops - Accounting`, `Ops - Directors`, `Delivery Driver`, `Ops - Order Creating`, `Ops - Finance` | 🔴 | The Task governance script enforces owning-team edit rights — tasks will be uneditable if no real users are in the correct roles |
| 1.3 | Assign staff to `Ops - Purchasing` and `Ops - Purchasing Lead` | 🟡 | Required before any Purchase Order is created |
| 1.4 | Create `director.tv@internal` user with `Directors TV` role + strong password | 🟢 | Needed for the TV wallboard only; not blocking sales |
| 1.5 | Verify `server_script_enabled = 1` after every bench restart or Frappe upgrade | 🔴 | All gates (dispatch, debt, discount approval etc.) run as Server Scripts — if disabled, all gates silently disappear |

**Don't do:** Do not assign the `System Manager` role to daily operational staff. Directors bypass all task ownership checks when they have `System Manager` — use only `Ops - Directors`.

---

## 2. Master Data — Customers

| # | Item | Priority | Why |
|---|---|---|---|
| 2.1 | Delete test record **`Test Doctor ASCII`** (code `TEST01`) from Customer list | 🟡 | Stale test data; will appear in reports and dropdowns |
| 2.2 | Set real `debt_threshold_amd` on all 146 customers (currently all `0`) | 🔴 | The hourly debt-collection scheduler only fires when threshold > 0. At 0, no debt escalation tasks will ever be created |
| 2.3 | Uncheck `Is Provisional` for clients validated by Accounting/Directors | 🟡 | Provisional flag is a governance marker — leaving it set signals the client record is not yet signed off |
| 2.4 | New clients: continue doctor codes from `D146`, hospital codes from `H002` | 🟢 | Naming consistency; no system impact if skipped temporarily |

---

## 3. Master Data — Items & Stock

| # | Item | Priority | Why |
|---|---|---|---|
| 3.1 | **Set batch/serial/expiry tracking flags on Item masters before posting any stock transaction for that item** | 🔴 | ERPNext cannot add tracking retroactively once a stock ledger entry exists for an item. Wrong flag = permanent data quality problem |
| 3.2 | Populate `Standard Selling` and `Standard Buying` price lists | 🔴 | Sales Orders cannot be priced correctly without a price list. The discount-approval gate checks against `price_list_rate` — if 0, all orders look like they have 100% discount |
| 3.3 | **[Decision needed] D1 — Item Group hierarchy**: current structure is brand-first (`ZMD → zmd screws`); Doc 06 recommends type-first (`Implants → Screws`) | 🟡 | Affects report grouping and Item filters. Requires moving all 246 items. Awaiting explicit decision before acting |
| 3.4 | **[Decision needed] D2 — Item naming**: current names are bare spec strings; Doc 06 recommends `<Brand> — <Name> — <Spec>` format | 🟢 | Cosmetic; does not affect system function. Awaiting decision |
| 3.5 | Add more values to Item Attributes (`Diameter (mm)`, `Length (mm)`, etc.) as new product lines arrive | 🟢 | Infrastructure for future variant templates only |

**Don't do:** Do not bulk-set batch/serial flags on all 246 items at once without explicit confirmation per item group. Setting `has_serial_no = 1` on a consumable (screw) is wrong — it would require a serial number on every single piece.

---

## 4. Role Permissions (Manual — Role Permission Manager)

These cannot be set via the REST API and were not deployed by any script. Go to: **ERPNext → Role Permission Manager** for each DocType below.

| DocType | Role | Needed permissions |
|---|---|---|
| `Dispatch Case` | `Ops - Order Creating` | Read, Write, Create, Submit |
| `Dispatch Case` | `Ops - Order Accepting` | Read |
| `Dispatch Case` | `Ops - Accounting`, `Ops - Inventory`, `Ops - Returns`, `Delivery Driver` | Read |
| `Dispatch Case` | `Ops - Directors` | Read, Cancel |
| `Stock Entry` | `Ops - Inventory`, `Ops - Delivery`, `Ops - Returns` | Read, Write, Create, Submit |
| `Stock Entry` | `Delivery Driver` | No access |
| `Sales Invoice` | `Ops - Accounting` | Read, Write, Create, Submit, Cancel |
| `Payment Entry` | `Ops - Accounting` | Read, Write, Create, Submit, Cancel |
| `Payment Entry` | `Ops - Finance` | Read, Write, Create, Submit, Cancel |
| `Task` | `Ops - Finance` | Read, Write (own tasks — enforced by Task governance script) |
| `Sales Invoice` | `Ops - Finance` | Read |
| `Item`, `Item Group`, `Item Attribute`, `UOM` | `Ops - Inventory`, `Ops - Directors` | Write, Create (others: Read only) |
| `Workspace: Ops — Reporting Pack` | `Ops - Order Accepting`, `Ops - Inventory`, `Accounting`, `Director` | Read / accessible |
| `Workspace: Management - KPI Dashboard` | `Ops - Directors` | Read / accessible |
| `Workspace: Dispatch - Task Queues` | Operational roles | Read / accessible |

**Don't do:** Do not grant `System Manager` to Accounting staff to work around permission issues — this bypasses all governance scripts.

---

## 5. Reorder Thresholds

| # | Item | Priority | Why |
|---|---|---|---|
| 5.1 | Set `Reorder Level` and `Reorder Qty` on items that need reorder management | 🟡 | Without thresholds, the `Stock Reorder` tool produces no output and purchasing has no signal |
| 5.2 | Always use `Main - Inmed` as the reorder warehouse | 🔴 | Scripts and reports are hard-coded to `Main - Inmed`; reorders to any other warehouse will bypass all gates |
| 5.3 | Fill `Reorder Change Reason` when editing thresholds | 🟡 | The governance script (`Item-before-save-reorder-governance`) hard-blocks saves without a reason — Purchasing Leads will be stuck otherwise |

---

## 6. Saved Views & Reports to Create Manually

These cannot be deployed via the REST API (per-user saved views) or require ERPNext UI clicks:

| View name | DocType / Report | Filters to apply | Who uses it |
|---|---|---|---|
| `Stock Balance — Main - Inmed` | Stock Balance (built-in) | Warehouse = `Main - Inmed` | Purchasing, Ops |
| `Items — Active Stock` | Item list | Disabled = No, Is Stock Item = Yes | Purchasing |
| `Reorder — Main - Inmed` | Stock Reorder tool | Warehouse = `Main - Inmed` | Purchasing Lead |
| `Price Overrides — by Client` | Item Price list | Price List = Standard Selling, Customer ≠ blank | Accounting, Directors |
| `Collection Sets — Readiness` | Collection Set list | (all active, used as Dispatch Case templates) | Ops - Inventory |
| Directors wallboard Task views (5) | Task list | per role / status filters | Directors TV |
| Dispatch Case state views | Dispatch Case list | `status` = Confirmed / Packed / In Transit / Awaiting Return Pickup / Return In Transit / Invoice Pending | Ops leads |
| Task queue views | Task list | per `task_kind` + status not Completed/Cancelled | per team |

**Workaround already in place:** `Dispatch - Task Queues` now contains shared Task and Dispatch Case shortcuts, and `Management - KPI Dashboard` contains clean KPI/report links. Per-user saved views are optional usability polish only.

---

## 6.1 Docs 15/16/17 Implementation Status

| Area | Status | Remaining before launch |
|---|---|---|
| Doc 15A reporting requirements | ✅ 26/26 reports/functions/workspaces deployed or existing | Validate report outputs after smoke transactions and Standard Buying prices |
| Doc 15E backlog | ✅ Deployed: item reports, return/refund queue, norm scheduler, management/dispatch workspaces | Open reports/workspaces and confirm permissions/results |
| Doc 16 Dispatch Case | ✅ Core implementation deployed; `unit_price` optional | Run no-return and return-expected end-to-end smoke tests |
| Doc 16B gaps | ✅ No core implementation gap remains | Sign off smoke tests |
| Doc 17/17A purchasing costing | ✅ Technical deployment complete | Populate HS codes/import tax rates/Standard Buying prices and run PR → LCV → PI smoke test |

---

## 7. Smoke Tests (Pre-Go-Live)

Run these in the staging environment or on the first real test case. Sign off each before first real transaction.

| Test | What to verify |
|---|---|
| **Discount approval gate** | Create Dispatch Case with Discount % > 0 on a Case Item → Discount Approval task auto-created on Submit → Case status = `Awaiting Approval` → Director marks task Completed as Approved → status → `Confirmed` → Pack task auto-created |
| **Pack tracking temporary state** | Complete Pack task without `serial_no`/`batch_no` filled → should not block while batch/serial tracking is temporarily disabled |
| **Delivery gate (no photo)** | Set Delivery Status to `Delivered` on Delivery task without a delivery photo attached → hard block |
| **Delivery gate (no handover note)** | Set Delivery Status to `Delivered` without `Driver Handover Note` filled → hard block |
| **Return drop-off gate** | Set Pickup Status to `Returned to Warehouse` on Return Pickup task without drop-off photo → hard block |
| **Debt threshold escalation** | Set a low `debt_threshold_amd` on a Customer with outstanding invoices → trigger hourly scheduler manually → Debt Collection task appears assigned to Finance team |
| **PO approval gate** | Create draft PO → attempt submit → blocked (status = Pending) → Purchase Approval task → Director approves → PO submits |
| **PO re-approval** | Edit a line on an Approved draft PO → `director_approval_status` resets to Pending |
| **Purchase Receipt gate** | Submit Purchase Receipt with row targeting non-`Main - Inmed` warehouse → hard block |
| **Reorder governance** | Ops - Inventory (not Purchasing Lead) tries to change reorder levels → blocked; Purchasing Lead changes without reason → blocked |
| **Dispatch Case no-return E2E** | Order entry task → Dispatch Case (`return_expected = No`) Submit → Pack → Delivery (Picked Up → Delivered) → Invoice Preparation → Debt Collection → Closed; verify all stock entries auto-submitted and stock ledger correct |
| **Dispatch Case return-expected E2E** | Order entry task → Dispatch Case (`return_expected = Yes`) Submit → Pack → Delivery (Picked Up → Delivered) → Return Call → Return Pickup (Picked Up → Returned to WH) → Returns Inspection → Restock + Invoice Preparation (parallel) → Debt Collection → Closed; verify `dispatched = used + returned` reconciliation |
| **Doc 15 reports/workspaces** | Search for `RPT - Item - Sort and Classify`, `RPT - Item - Nomenclature and Prices`, `RPT - Returns - Refund Queue`, `Management - KPI Dashboard`, and `Dispatch - Task Queues`; confirm they open for intended users |
| **Doc 17A landed-cost flow** | Purchase Receipt → Landed Cost Voucher → click **Pre-fill Import Duty** → Purchase Invoice; confirm import duty appears and valuation updates |

---

## 8. Cleanup

| # | Item | Priority |
|---|---|---|
| 8.1 | Delete stray `Workflow Action Master` record **`TestAction888`** (created during Doc 12A debugging, harmless but untidy) | 🟢 |
| 8.2 | Review existing Tasks in status `Working` / `Completed` with 0 or 2+ assignees — fix or cancel before go-live (the governance script will reject saves on these) | 🟡 |
| 8.3 | Set `purchase_reason` and `requested_by` on any existing **draft** Purchase Orders — these are now required fields and will block saves | 🟡 |

---

## 9. Going-Forward Rules (Don't Break These)

These are architectural decisions baked into server scripts. Breaking them silently corrupts data.

1. **All deliveries must go `Main → Delivery In-Transit → Client Location`.** Never post stock manually from Main to a client warehouse — the Dispatch Case automation manages all stock entries; manual entries bypass the audit trail and break case reconciliation.

2. **All returns must go `Client Location → Return Pickup In-Transit → Returns → Main`.** Do not skip the in-transit step; the Dispatch Case server scripts validate and auto-submit entries at each transition.

3. **Never enable `Update Stock` on a Sales Invoice.** The `Purchase Invoice-before-submit-no-update-stock` script blocks this on Purchase Invoices; the same rule applies on the Sales side — all stock movements are handled automatically by Dispatch Case stock entries, never through an invoice.

4. **Never post stock manually to a client-location warehouse.** Client warehouse stock must always arrive via the Dispatch Case delivery automation (return-expected path). Manual Stock Entries targeting client warehouses bypass the case reconciliation and break `used + returned = dispatched` accounting.

5. **Never bypass the Dispatch Case state machine by manually editing `status`.** The server scripts check state transitions on Before Save/After Save/Before Submit — jumping states directly will skip auto-submitted stock entries and auto-created tasks, leaving the case in an inconsistent state.

6. **Serial/batch tracking flags must be set before the first stock entry for that item.** Once a `Stock Ledger Entry` exists for an item, ERPNext will not allow enabling tracking retroactively. This is a one-way door.

7. **All new client warehouses must be children of `Clients - Inmed`.** The in-transit stuck report and the client-stock-no-open-cases report filter on `parent_warehouse = 'Clients - Inmed'`. Warehouses outside this group will be invisible to those reports.

8. **The `Ops — Reporting Pack` workspace workspace shortcuts link to exact report names** (`RPT — Stock — ...`). Do not rename reports after go-live — you will break every workspace shortcut pointing to them.

---

## 10. Go / No-Go Checklist (Gate for First Real Transaction)

- [ ] All 7 sample users replaced with real staff accounts
- [ ] All operational roles have at least one real user assigned
- [ ] `debt_threshold_amd` set for all active customers
- [ ] Serial/batch/expiry flags set on all item masters (or explicitly deferred per item with written justification)
- [ ] `Standard Selling` price list populated
- [ ] Role Permission Manager entries configured (Section 4 above)
- [ ] All smoke tests (Section 7) passed and signed off
- [ ] Doc 15E reports/workspaces opened and validated by intended users
- [ ] Doc 17A landed-cost smoke test passed
- [ ] `Test Doctor ASCII` test record deleted
- [ ] Draft POs have `purchase_reason` and `requested_by` filled
- [ ] Existing malformed Tasks (0 or 2+ assignees) cleaned up
- [ ] Readiness meeting held with Ops lead, Accounting lead, Purchasing lead, Director
