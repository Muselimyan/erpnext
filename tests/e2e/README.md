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

# API regression layer
npx playwright test --project=api --workers=1 --reporter=line

# Browser smoke layer, desktop and mobile
npx playwright test --project=desktop --project=mobile --workers=1 --reporter=line

# Full no-return flow through invoice gate
npx playwright test --project=e2e --workers=1 --reporter=line

# Full suite
npx playwright test --workers=1 --reporter=line
```

## Current Passing Baseline

Last verified against `https://test.erpnext.am`:

```text
npx tsc --noEmit
npx playwright test --workers=1 --reporter=line
19 passed
```

## Implemented Scope

- API tests for Dispatch Case lifecycle checks, task invariants, discount behavior, and completion gates.
- Browser smoke tests for Task form button state, duplicate buttons, clipping, field visibility/editability, console errors, and network failures on desktop and mobile.
- Full no-return workflow through Order Entry, Pack, Delivery, and Invoice Preparation gate.

## Known Current Limits

- The full E2E path stops at the Invoice Preparation gate and verifies that completion is blocked until a submitted Sales Invoice exists.
- It does not yet submit a Sales Invoice, complete Debt Collection, create a Payment Entry, or verify final Dispatch Case `Closed` status.
- Return Call, Return Pickup, Returns Inspection, and used-quantity invoicing are not yet covered by the full E2E path.
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
