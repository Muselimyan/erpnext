# ERPNext Regression Testing Plan

## 1. Purpose

Automated regression testing for the ERPNext customization. After a change is deployed to the **test** environment, run automated checks that behave like real users and report whether important workflows still work.

The system has three testing layers:

| Layer | What it tests | How it runs | Speed |
|---|---|---|---|
| **Layer 1 — API** | Server-side business logic: task creation, dispatch case state transitions, stock entry generation, invoice creation, payment recording | HTTP calls, no browser | Seconds |
| **Layer 2 — Browser smoke** | Client-side UI state: button visibility, duplicate buttons, button clipping, field visibility/editability by role and task state, console errors, network failures | Browser opened against specific pre-created task states | Minutes |
| **Layer 3 — Full E2E** | End-to-end workflow proof: complete dispatch flow with real role-based logins, task accepts, completes, and all generated downstream records | Browser with role switching, triggered manually | Minutes |

Layer 1 catches the majority of regressions (server script changes breaking downstream logic). Layer 2 catches client script regressions (buttons disappearing, appearing when they shouldn't, or rendering half-visible). Layer 3 proves the entire chain works together.

---

## 2. Technology

**Playwright (TypeScript).** Single tool for all three layers.

- Layer 1 uses Playwright's built-in `APIRequestContext` for HTTP calls without launching a browser.
- Layers 2 and 3 use Playwright's browser automation with Chromium.
- One `package.json`, one test runner, one report format.

Dependencies must be approved before installation.

---

## 3. Safety Rules

### 3.1 Environment

Tests run only against `https://test.erpnext.am`. The safety guard rejects `https://erpnext.am` and any unknown hostname before login, before navigation, and before any action.

### 3.2 No credentials in committed files

Credentials are stored in `.env.local` (gitignored). No passwords, API secrets, or tokens in committed code, screenshots, logs, or reports.

### 3.3 Test-only data changes

The automation may create or submit these record types on test only:

- Task
- Dispatch Case
- Stock Entry (triggered by server scripts)
- Sales Invoice
- Payment Entry
- File/photo attachments

### 3.4 No System Manager for permission tests

Role/lock/permission tests use ordinary role users. Administrator/System Manager is only used for setup or diagnostic checks that explicitly require admin access.

### 3.5 Server operation rule

Before any server operation, read `docs/infrastructure-test-vs-prod-environments.md`. This testing plan does not authorize any server operation.

---

## 4. Authentication

### 4.1 API tests (Layer 1)

Token-based authentication using API key/secret. No CSRF token needed. An API user must exist on `test.erpnext.am` (create one if needed).

### 4.2 Browser tests (Layers 2, 3)

Local credentials from `.env.local`. One username/password pair per operational role. Login once per role at the start of a run, cache the session, reuse it for subsequent tests with that role. Role switching loads a different cached session (~100ms, no re-login).

### 4.3 Credential structure

```
tests/e2e/.env.local     (gitignored, real credentials)
tests/e2e/.env.example   (committed, shows structure)
```

Required credentials:

- `BASE_URL`, `API_KEY`, `API_SECRET`
- One `USER_*` / `PASS_*` pair per role: Order Accepting, Order Creating, Inventory, Delivery, Returns, Accounting, Finance, Directors

---

## 5. Test Data

### 5.1 Strategy

Use existing master data. Create fresh transaction records per run.

**Existing (reused):** Customers, Items, Warehouses, Users and roles.

**Created fresh per run:** Tasks, Dispatch Cases, Stock Entries, Sales Invoices, Payment Entries, File/photo attachments.

### 5.2 Dedicated test items

A small set of items exists specifically for testing, with stock pre-loaded in `Main - Inmed`. These items are permanent on the test environment and replenished if stock runs out.

### 5.3 Cleanup

Keep all created records. The test environment is disposable. Created records are tracked in a run manifest for reference. Manual cleanup when the environment gets cluttered.

### 5.4 User selection

Tests use enabled non-example users with the required role. Extra roles are acceptable. Team-placeholder users are not used for login. If a suitable user doesn't exist for a role, create one on the test environment.

---

## 6. Viewports

All browser tests (Layers 2 and 3) run at **both desktop and mobile** viewports. There must be no functional difference between desktop and mobile — same buttons, same fields, same behavior. The viewport only changes which rendering path is used (header buttons vs floating bottom bar).

- Desktop: `1280x720`
- Mobile: `375x812`

---

## 7. Layer 1 — API Regression Tests

Pure HTTP tests. No browser. Tests call the same API methods the UI calls where available, and use generic REST only for direct document setup/state checks that are intentionally part of the invariant being tested.

### 7.1 Dispatch Case no-return lifecycle

1. Create Order Entry task — verify task exists, status=Open, assigned to team user
2. Accept task — verify `custom_accepted_by` set, status=Working
3. Create Dispatch Case — verify DC created, `return_expected=0`
4. Add items — verify DC items table populated
5. Complete Order Entry — verify Pack task auto-created, DC status advances
6. Accept Pack task, upload required photo, mark case item indices packed through `task_mark_items_packed_batch`, then complete Pack task — verify Delivery task is created
7. Set `delivery_status=Picked Up`
8. Set `delivery_status=Delivered` — verify Invoice Preparation task is created

### 7.2 Dispatch Case return-expected lifecycle

Same chain as 7.1 but with `return_expected=Yes`. The current first implementation verifies that a return-expected API-created case can progress through Order Entry, Pack, Delivery, and Invoice Preparation creation. Return Call, Return Pickup, Returns Inspection, and used-quantity invoicing are later enhancements for a deeper return-path suite.

### 7.3 Discount approval gate

- DC with discount > 0 — verify DC stays in Awaiting Approval
- Discount Approval task created for Directors team
- Approve — verify DC moves to Confirmed, Pack task created
- Reject — verify DC stays blocked

### 7.4 Task system invariants

- Non-accepted user cannot complete task (API rejects)
- Completed task cannot be re-completed
- Task kind drives correct Task Access Policy lookup
- Generic API reassignment by a non-accepted/API user is blocked by the task lock
- Duplicate DC creation from same task is idempotent and returns the existing Dispatch Case

### 7.5 Completion gates

- Pack completion without photo is rejected (when gate is active)
- Delivery status cannot skip from Todo to Delivered
- Return Pickup completion requires drop-off photo (when gate is active)

---

## 8. Layer 2 — Browser Smoke Tests

Open a browser, navigate to specific task states, check what the user sees. Each test is independent. Test data is created via API before opening the browser.

### 8.1 Button state matrix

For each combination of task kind, status, and acceptance state, verify the correct buttons are present:

| State | Accept | Complete | Create DC | Open DC |
|---|---|---|---|---|
| Open, unaccepted, Order entry, no DC | visible | hidden | hidden | hidden |
| Working, accepted by me, Order entry, no DC | hidden | visible | visible | hidden |
| Working, accepted by me, Order entry, has DC | hidden | visible | hidden | visible |
| Working, accepted by other user | hidden | hidden | hidden | visible (if DC) |
| Completed | hidden | hidden | hidden | visible (if DC) |
| Pack task, accepted by me | hidden | visible | hidden | visible |
| Delivery task, accepted by me | hidden | visible | hidden | visible |

### 8.2 Duplicate button detection

Count each action button on the page. Expect exactly 0 or 1, never 2+:

- Accept / Start Task
- Complete
- Create Dispatch Case
- Open DC / View DC
- Mobile Back / Refresh controls

### 8.3 Button clipping detection

For every visible button, verify it has a valid bounding box: not outside the viewport, not squished to zero/tiny dimensions. This catches buttons that render half-visible due to indentation or CSS overflow.

### 8.4 Field visibility by task kind

Verify the correct fields are shown/hidden per task kind (per `TFV_KIND_MAP` rules):

- Product section visible/hidden
- Scan fields visible/hidden
- Payment fields visible/hidden
- Approval fields visible/hidden
- Dispatch Case link visible/hidden

### 8.5 Field editability by state

- Unaccepted task: key fields read-only
- Accepted task: editable fields per `TFE_EDIT_MAP`
- Completed task: everything read-only
- Customer field: editable only on Order entry

### 8.6 Console and network health

On every page load, capture `console.error` and failed `/api/` network requests. Fail on unexpected errors.

---

## 9. Layer 3 — Full Happy Path

One comprehensive test, triggered manually or as part of the full project run. The first implementation proves the no-return Dispatch Case chain through Delivery and verifies the Invoice Preparation gate.

### 9.1 No-return dispatch flow

```
Step 1: Login as Ops - Order Accepting
  Create Order Entry task, assign to Order Creation team

Step 2: Login as Ops - Order Creating
  Accept task, create Dispatch Case, add items, complete task

Step 3: Login as Ops - Inventory
  Accept Pack task, upload test photo, complete task

Step 4: Login as Delivery Driver
  Accept Delivery task, set Picked Up, set Delivered

Step 5: Login as Ops - Accounting
  Accept Invoice Preparation task, verify the Sales Invoice submission gate blocks completion until a submitted Sales Invoice exists

Future extension:
  Submit/verify Sales Invoice, complete Invoice Preparation, create Debt Collection, record payment, and verify DC status = Closed
```

At each step: screenshot, console log capture, network error capture. On failure: stop, save full state, report which step failed and why.

---

## 10. Failure Policy

Continue after non-dangerous failures (missing button, wrong visibility, assertion mismatch). Report all failures.

Stop the current scenario on dangerous failures:

- Wrong environment detected
- Login as wrong role
- Dispatch Case partially submitted in wrong state
- Payment recorded with wrong amount
- Browser lost session during a data-changing step

---

## 11. Reports

Playwright artifacts go to `ERPNext-Automation-Reports/test-results/` (gitignored). Failure artifacts can include screenshots, traces, and `error-context.md` files. Secrets, auth headers, and cookies are excluded from committed files and should not be copied into reports.

---

## 12. Running Tests

```bash
# Type-check the test suite
npx tsc --noEmit

# Layer 1 — API tests, no browser
npx playwright test --project=api --workers=1 --reporter=line

# Layer 2 — browser smoke tests
npx playwright test --project=desktop --project=mobile --workers=1 --reporter=line

# Layer 3 — full no-return path through invoice gate
npx playwright test --project=e2e --workers=1 --reporter=line

# All layers
npx playwright test --workers=1 --reporter=line

# Mobile only / Desktop only
npx playwright test --project=mobile --workers=1 --reporter=line
npx playwright test --project=desktop --workers=1 --reporter=line
```

---

## 13. Scope

### 13.1 First implementation

- Dispatch Case no-return lifecycle (Layer 1)
- Dispatch Case return-expected lifecycle (Layer 1)
- Discount approval gate (Layer 1)
- Task system invariants (Layer 1)
- Completion gates (Layer 1)
- Task button state matrix — desktop + mobile (Layer 2)
- Duplicate button detection — desktop + mobile (Layer 2)
- Button clipping detection — desktop + mobile (Layer 2)
- Field visibility by task kind (Layer 2)
- Field editability by state (Layer 2)
- Console and network health (Layer 2)
- Full no-return dispatch path through Delivery and Invoice Preparation gate (Layer 3)

### 13.2 Later

- Extend no-return Layer 3 path through submitted Sales Invoice, Debt Collection, Payment Entry, and DC Closed
- Return-expected happy path (Layer 3)
- Purchase flow (PO, Purchase Receipt, LCV, Purchase Invoice)
- Photo gate enforcement detail tests
- Report/workspace smoke tests
- Telegram notification verification
- Tender agreement flow
