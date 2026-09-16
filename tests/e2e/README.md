# ERPNext Playwright Regression Tests

Automated regression tests for the ERPNext customization on the test environment.

## Safety

These tests are only allowed to run against `https://test.erpnext.am`.

The safety guard rejects production (`https://erpnext.am`), unknown hosts, and non-HTTPS URLs before API calls or browser navigation.

Do not commit `.env.local`, session files, screenshots, traces, reports, or generated artifacts.

## Setup

Install dependencies from this directory:

```powershell
npm install
```

Create `tests/e2e/.env.local` from `.env.example` and fill in:

```text
BASE_URL=https://test.erpnext.am
API_KEY=...
API_SECRET=...
USER_ORDER_ACCEPTING=...
PASS_ORDER_ACCEPTING=...
USER_ORDER_CREATING=...
PASS_ORDER_CREATING=...
USER_INVENTORY=...
PASS_INVENTORY=...
USER_DELIVERY=...
PASS_DELIVERY=...
USER_RETURNS=...
PASS_RETURNS=...
USER_ACCOUNTING=...
PASS_ACCOUNTING=...
USER_FINANCE=...
PASS_FINANCE=...
USER_DIRECTORS=...
PASS_DIRECTORS=...
```

## Commands

Run from `tests/e2e`.

```powershell
# Type-check
npx tsc --noEmit

# List discovered tests
npx playwright test --list

# API regression layer: current behavior, should stay green
npx playwright test --project=api --workers=1 --reporter=line

# API audit layer: business-contract/config/gate checks; non-blocking gap list
npx playwright test --project=api-audit --workers=1 --reporter=line

# Browser smoke layer, desktop and mobile
npx playwright test --project=desktop --project=mobile --workers=1 --reporter=line

# Full no-return flow through invoice gate
npx playwright test --project=e2e --workers=1 --reporter=line

# Full suite
npx playwright test --workers=1 --reporter=line
```

## Current Passing Baseline

Last verified against `https://test.erpnext.am` on 2026-09-16:

```text
npx tsc --noEmit
passed

npx playwright test --project=api --workers=1 --reporter=line
27 passed

npx playwright test --project=desktop --project=mobile --workers=1 --reporter=line
284 passed, 5 skipped

npx playwright test --project=e2e --workers=1 --reporter=line
2 passed

npx playwright test --project=api-audit --workers=1 --reporter=line
270 passed, 139 skipped

npx playwright test --project=e2e-audit --workers=1 --reporter=line
1 passed, 3 skipped
```

Current discovered scope after adding read-only preflight, policy matrices, report/workspace checks, metadata/config checks, browser smoke matrices, full workflow probes, and audit coverage: 731 tests across 43 files.

Known skips and audit-only gaps are tracked in `AUDIT-GAPS.md`.

The `api` and `e2e` projects exclude `@audit` tests and are blocking current-behavior regression layers. The `api-audit` and `e2e-audit` projects run `@audit` tests for desired business-contract/config/gate checks that may expose environment gaps without blocking the regression baseline.

## Implemented Scope

- API preflight tests for environment safety, configured credentials, Task Access Policy records, policy default team users, operational reports, and operational workspaces.
- API master-data/config tests for required warehouses, custom DocTypes, operational roles, required operational fields, Dispatch Case submit settings, Task `task_kind` metadata, and required Server Script/Client Script records.
- API Task Access Policy matrix tests for dispatch-chain policy-role/team mappings, non-dispatch policies, Role records, and Task `task_kind` options.
- API Task Access Policy depth matrix tests for role mappings, enabled default team users, and team naming/context checks across dispatch, finance, returns, purchasing, approval, Other, Account Details, and debt-alert task kinds.
- API report/workspace metadata tests for reporting pack reports, duplicate/deferred report pairs, workspace shortcuts, and the current KPI dashboard skeleton state.
- API tests for Dispatch Case lifecycle checks, task invariants, discount behavior, and completion gates.
- API Task lock/security depth tests for pre-acceptance workflow mutation rejection, completed-task mutation rejection, reassignment acceptance reset, simultaneous reassignment/completion rejection, and cancelled-task acceptance rejection.
- API Packing/Product Work Area tests for linked Pack task creation, single-item packing, batch packing, invalid packed index payloads, malformed payload rejection, Pack completion gates, pickup photo gate, and Delivery task creation after valid Pack completion.
- API Dispatch workflow edge-case tests for non-Order Entry Dispatch Case rejection, unaccepted Order Entry rejection, completion-before-case gate, Pack completion gates, Delivery status transition gate, invalid product quantity, invalid packed index, and malformed packed-index payloads.
- API Dispatch workflow gate depth tests for Pack acceptance/proof/item gates, Delivery delivered-status gate, Invoice submitted-link gate, and pre-invoice delivery sequencing.
- API Payments/Debt/Tender tests for policy-role/team configuration, payment/debt/tender DocType fields, payment method and amount metadata, Payment Received/Debt Collection/Debt Closure task creation, payment validation gates, and finance report metadata.
- API Purchasing/Reorder/Supplier tests for purchasing roles, core purchasing DocTypes, PO/PR/PI/Item/Item Reorder/Item Price fields, purchasing reports, purchasing server scripts, Purchase Approval policy, supplier fixture readiness, buying price readiness, and reorder threshold governance metadata.
- API Returns workflow tests for return-expected delivery branching, Return Call/Pickup Returns/Returns processing policy configuration, scheduling gates, return quantity API rejection cases, return quantity updates, inspection gate probes, and return stock entry metadata.
- API Item/Stock/Warehouse Governance tests for operational warehouses, Item/Warehouse/Stock Entry/Bin/Batch/Item Group metadata, stock reports, item/stock governance scripts, temporary tracking-disabled state, future Batch metadata, Stock Entry movement fields, Bin readiness, and Customer stock-governance fields.
- API Permission/Negative Security Matrix tests for blocked-role task acceptance, acceptance-lock gates, generic REST completion/reassignment bypass attempts, delivery/payment pre-acceptance gates, Dispatch Case creation gates, and add-product lock checks.
- API Report Content/Filter tests for operational reports running through `frappe.desk.query_report.run`, expected column families, metadata role rows, and stock/finance/purchasing report groups.
- API Report Metadata Depth tests for operational report module/ref_doctype/report_type/role metadata and query-runner column metadata across dispatch, accounting, receivables, risk, stock, purchasing, returns, and item-classification reports.
- API Client/Server Script Static Safety tests for critical script text presence, RestrictedPython blocked primitive scans, TFV/TFE ownership markers, acceptance-lock markers, Telegram Settings token sourcing, and Task visibility/editability owner discovery.
- API Script Ownership Depth tests for client/server script body markers, ownership boundaries, Task/Dispatch/Telegram/Purchasing script signatures, and RestrictedPython high-risk primitive avoidance.
- API Surgical Kit Template tests for template DocTypes, template/item selection fields, item-selection client scripts, template auto-fill markers, product button markers, fixture readiness, child item metadata, and Dispatch Case template selector metadata.
- API Purchase Approval workflow tests for draft PO creation, director approval submit gate, Purchase Approval required links/outcomes, approved/rejected writeback, and approved draft edit reset behavior.
- API Payment/Debt workflow gate tests for Payment Received structural validity, missing customer rejection, Debt Collection acceptance lock, Debt Closure Approval outcome gates, director-gated closure policy, and Payment Entry/Sales Invoice/Dispatch Case payment metadata.
- API Data Quality/Master Data integrity tests for stock item UOM/group readiness, customer client-code uniqueness when assigned, operational warehouse leaf/enabled state, buying/selling price item links, policy team users, open task assignment/policy links, submitted Dispatch Case coordinator links, and negative-stock report runnability.
- Browser smoke tests for Task form button state, duplicate buttons, clipping, field visibility/editability, console errors, and network failures on desktop and mobile.
- Browser desk list navigation smoke tests for core operational DocType list route loading, list shell visibility, expected text markers, horizontal overflow checks, console health, and server-error network checks across desktop/mobile.
- Browser master/transaction form load smoke tests for existing Customer, Item, Warehouse, Supplier, Purchase Order, Purchase Receipt, Sales Invoice, Payment Entry, Dispatch Case, and Task record route health across desktop/mobile.
- Browser report click-through smoke tests for operational report filter/result shells, refresh/run controls, route health, expected report content text, console health, and server-error network checks across desktop/mobile.
- Browser report route interaction smoke tests for report route/title reachability, fresh-context stability, console health, and server-error network checks across desktop/mobile.
- Browser role-permission smoke tests for task-kind/role field visibility, pre-accept read-only state, hidden completion controls, other-role accepted-task lock behavior, director approval lock behavior, console health, and server-error network checks across desktop/mobile.
- Browser Barcode/Product Work Area UI smoke tests for Order Entry product controls, barcode/search probes, Pack product area markers, packing checkbox/dashboard reachability, pickup photo control geometry, Returns processing quantity markers, and compact/detailed toggle geometry across desktop/mobile.
- Browser Dispatch Case item-selection smoke tests for item table markers, Add Items by Category button geometry, Search Add Item button geometry, and Surgical Kit Template selector reachability across desktop/mobile.
- Browser task UI matrix tests for representative operational task kinds across desktop and mobile, covering form load health, title visibility, duplicate buttons, visible button bounding boxes, console errors, and server-error network responses.
- Browser report/workspace smoke tests for core operational reports and custom workspaces across desktop and mobile, covering page load health, title visibility, expected shortcut labels, console errors, and server-error network responses.
- Browser workspace navigation smoke tests for shortcut visibility/usability, shortcut geometry, report-route navigation, reload persistence, horizontal overflow checks, console health, and server-error network checks across desktop/mobile.
- Browser mobile/layout geometry tests for back button behavior, primary task button visibility/text/size, long subject layout, Delivery controls, Pack product area reachability, pickup photo button label, viewport containment, and horizontal overflow.
- Browser Task field matrix tests for representative task kinds across desktop/mobile, covering visible/hidden workflow fields, unaccepted read-only behavior, accepted Order Entry action state, and completed-task lock UI.
- Browser task-state depth tests for unaccepted task button/read-only behavior across operational task kinds and completed task lock behavior for directly completable task fixtures across desktop/mobile.
- Browser returns smoke tests for Return Call, Pickup Returns, Returns processing, and Returns restocking task load health across desktop/mobile.
- Full no-return workflow through Order Entry, Pack, Delivery, and Invoice Preparation gate.
- Full return-expected workflow through Order Entry, Pack, Delivery, Return Call gate, return quantity reconciliation probe, and Return Call scheduling gate.

## Known Current Limits

- API audit tests cover desired reports, workspaces, metadata, policy matrices, security gates, purchase approval gates, packing mutation gates, returns gates, and data-quality checks. These are intentionally separated from the blocking `api` regression project because the current test environment does not always expose or enforce every contract.
- The full E2E path stops at the Invoice Preparation gate and verifies that completion is blocked until a submitted Sales Invoice exists.
- It does not yet submit a Sales Invoice, complete Debt Collection, create a Payment Entry, or verify final Dispatch Case `Closed` status.
- Return Pickup, Returns Inspection completion, restocking completion, and used-quantity invoicing are not yet covered by the full E2E path.
- Browser smoke accepted-user checks must be done through browser-session acceptance. API-side acceptance belongs to the API user, not the browser role session.

## Artifacts

Generated Playwright artifacts are written to:

```text
ERPNext-Automation-Reports/test-results/
```

This directory is gitignored and may contain screenshots, traces, and failure context files.

## Custom Report Helpers

`src/reports.ts` and `src/manifest.ts` contain helpers for custom `report.json`, `report.html`, JSONL logs, and `run-manifest.json` output.

These helpers are available for a future richer reporting layer, but they are not wired into the current passing Playwright suite. The current baseline relies on Playwright's built-in artifacts in `ERPNext-Automation-Reports/test-results/`.
