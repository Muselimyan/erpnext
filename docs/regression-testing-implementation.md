# ERPNext Regression Testing — Implementation Plan

**References:** `docs/erpnext-browser-automation-testing-plan.md` (decisions), `docs/infrastructure-test-vs-prod-environments.md` (environment safety)

---

## Governance — No Fixes Without Explicit Approval

**This test suite is for DETECTION and REPORTING only.**

When regression tests discover bugs, broken buttons, missing fields, clipped controls, failed workflows, or any other issue on `test.erpnext.am` or `erpnext.am`:

1. **Do NOT fix the issue.** Do not edit client scripts, server scripts, deploy scripts, Property Setters, Custom Fields, or any other configuration on either environment.
2. **Report it.** Write the finding into `docs/regression-test-findings.md` with: what failed, which test caught it, screenshot/evidence, and the suspected root cause.
3. **Wait for Vahe's explicit approval** before making any change. No exceptions — not even "obvious one-liners" or "safe rollbacks."

This applies to:
- Bugs found during test development
- Bugs found during test runs
- Bugs found while investigating test failures
- Environment configuration issues
- Data inconsistencies on the test site

The regression test findings document (`docs/regression-test-findings.md`) is the single intake point. Vahe reviews it and decides what gets fixed, when, and by whom.

---

## Phase 1 — Setup and Infrastructure

### 1.1 Project scaffolding

Create `tests/e2e/` with this structure:

```
tests/e2e/
  package.json
  tsconfig.json
  playwright.config.ts
  .env.example
  src/
    config.ts
    safety.ts
    frappe-api.ts
    frappe-ui.ts
    auth.ts
    manifest.ts
    capture.ts
    reports.ts
    assertions.ts
    types.ts
  tests/
    setup/
      global-setup.ts
    api/
      (Phase 2)
    smoke/
      (Phase 3)
    e2e/
      (Phase 4)
  fixtures/
    sample-photo.png
  sessions/
ERPNext-Automation-Reports/
  .gitkeep
```

**package.json** — Dependencies: `@playwright/test`, `dotenv`. Dev dependencies: `typescript`, `@types/node`. No other libraries.

**tsconfig.json** — Strict mode, target ES2020, module NodeNext. Only compiles `src/` and `tests/`.

**playwright.config.ts** — Five projects:

| Project | Test match | Browser | Viewport | Notes |
|---|---|---|---|---|
| `setup` | `tests/setup/global-setup.ts` | none | none | Validates environment, creates sessions |
| `api` | `tests/api/**/*.spec.ts` | none | none | Uses `request` fixture only. Depends on `setup` |
| `desktop` | `tests/smoke/**/*.spec.ts` | Chromium | 1280x720 | Depends on `setup` |
| `mobile` | `tests/smoke/**/*.spec.ts` | Chromium | 375x812 | Depends on `setup` |
| `e2e` | `tests/e2e/**/*.spec.ts` | Chromium | both | Headed. Depends on `setup` |

Config settings:
- `fullyParallel: false` — dispatch flow tests are sequential
- `retries: 0` — regression tests must be deterministic, no retry masking
- `screenshot: 'only-on-failure'` for smoke, `'on'` for e2e
- `trace: 'retain-on-failure'`
- `baseURL` from `process.env.BASE_URL`
- `outputDir` points to `ERPNext-Automation-Reports/`

**.gitignore** — The project root has no `.gitignore`. Create one covering:

```
tests/e2e/.env.local
tests/e2e/sessions/
tests/e2e/node_modules/
ERPNext-Automation-Reports/
test-results/
```

**.env.example** — Committed, shows structure with empty values. Contains: `BASE_URL`, `API_KEY`, `API_SECRET`, and `USER_*`/`PASS_*` pairs for each role.

---

### 1.2 Environment safety guard

**File: `src/safety.ts`**

Single function `validateEnvironment(baseUrl)`:
- Parse URL
- If hostname is `erpnext.am` → throw with `REFUSED: production URL`
- If hostname is not `test.erpnext.am` → throw with `REFUSED: unknown host`
- Return validated URL

Called in two places:
1. **Global setup** (`tests/setup/global-setup.ts`) — fails the entire run immediately if environment is wrong
2. **Frappe API client constructor** — every API client instance re-validates, so no test can accidentally use a wrong URL even if global setup is bypassed

---

### 1.3 Test environment prerequisites

These are one-time manual/semi-automated setup steps on `test.erpnext.am`, not code that runs per test.

#### 1.3.1 API user

An API user already exists on test. The existing key/secret from `deploy/test/export.ps1` can be reused for initial development. This user has admin-level access, which is sufficient for Layer 1 API tests (server logic verification).

For role-specific rejection tests (e.g., "user without Ops - Inventory role cannot accept a Pack task"), we will need per-role API keys. This is a Phase 2 concern — Layer 1 happy-path tests work fine with the admin API user.

#### 1.3.2 Role users for browser login

Layer 2 and 3 require browser login as specific role users. Need one enabled user per role:

| Role | Purpose |
|---|---|
| Ops - Order Accepting | Accept order entry tasks |
| Ops - Order Creating | Create DCs, add items, complete order entry |
| Ops - Inventory | Accept and complete Pack tasks |
| Delivery Driver | Accept delivery, set Picked Up / Delivered |
| Ops - Returns | Returns inspection and restocking |
| Ops - Accounting | Invoice preparation |
| Ops - Finance | Debt collection and payment recording |
| Ops - Directors | Discount approval, debt closure approval |

Action: Query `test.erpnext.am` for existing enabled users with these roles. For any missing role, create a test user. Record usernames and set known passwords. Store in `.env.local`.

Users must NOT be:
- Administrator or System Manager (bypasses permission checks)
- Team placeholder users like `order.creation.team@example.com` (login disabled)
- Example/sample users

#### 1.3.3 Dedicated test items

Create 3-5 items specifically for testing:

- **E2E-TEST-ITEM-001** through **E2E-TEST-ITEM-005**
- Must be: enabled, stock item, no batch/serial requirement
- Must have a selling price in the default price list
- Must have stock in `Main - Inmed` (create via Material Receipt Stock Entry)
- Load ~100 qty each so tests can run many times before replenishment

These items are permanent on test. If stock runs out, replenish with another Material Receipt.

#### 1.3.4 Dedicated test customer

Identify or create one customer for testing:

- Enabled
- Has a linked client-location warehouse under `Clients - Inmed` (needed for return-expected tests)
- Not a real production customer name (to avoid confusion)

---

### 1.4 Core utilities

#### 1.4.1 Config loader — `src/config.ts`

Loads `.env.local` via `dotenv`, exports typed config object. Validates all required env vars are present at startup. Exports:

```
baseUrl: string
apiKey: string
apiSecret: string
roles: Map<RoleName, { user: string, password: string }>
```

Fails fast with a clear error if any required variable is missing.

#### 1.4.2 Frappe API client — `src/frappe-api.ts`

Wraps Playwright's `APIRequestContext` with Frappe-specific patterns. This is the workhorse for Layer 1 and for Layer 2/3 test data setup.

**Constructor:** Takes `baseUrl`, `apiKey`, `apiSecret`. Validates environment (safety guard). Sets `Authorization: token {key}:{secret}` header.

**Core methods:**

| Method | HTTP | Path | Returns | Notes |
|---|---|---|---|---|
| `getDoc(doctype, name)` | GET | `/api/resource/{doctype}/{name}` | Unwrapped `.data` | Single document with all fields |
| `getList(doctype, opts)` | GET | `/api/resource/{doctype}` | Unwrapped `.data` array | `opts`: filters, fields, limit, order_by |
| `createDoc(doctype, fields)` | POST | `/api/resource/{doctype}` | Created document | For creating Tasks, etc. |
| `updateDoc(doctype, name, fields)` | PUT | `/api/resource/{doctype}/{name}` | Updated document | For field updates |
| `callMethod(method, data)` | POST | `/api/method/{method}` | Unwrapped `.message` | For custom API scripts |
| `saveDoc(doc)` | POST | `/api/method/frappe.client.save` | Saved document | Triggers before_save/after_save chain |

**Frappe response handling:**
- Resource endpoints (GET/POST/PUT on `/api/resource/`) return `{ "data": { ... } }`
- Method endpoints (POST on `/api/method/`) return `{ "message": { ... } }`
- The client unwraps these automatically — callers get the inner object

**Error handling:**
- Non-2xx responses: parse body, extract `_server_messages` or `exc` field, throw typed error with the server message text
- `frappe.throw()` from server scripts produces HTTP 417 or 500 with the thrown message in `_server_messages` (JSON-encoded string inside a JSON array)
- The error type should distinguish validation errors (expected in negative tests) from unexpected failures

**Encoding:** All request bodies encoded as UTF-8. This is critical — Frappe rejects non-UTF-8 bodies with `HTTP 417 DataError: Invalid request body` when non-ASCII characters are involved.

**Convenience methods for project APIs:**

| Method | Calls | Parameters |
|---|---|---|
| `acceptTask(taskName)` | `dispatch_task_accept` | `{ task_name }` |
| `createDispatchCase(taskName)` | `task_create_dispatch_case` | `{ task_name }` |
| `addProduct(taskName, itemCode, qty, unitPrice?)` | `task_add_dispatch_product` | `{ task_name, item_code, qty, unit_price }` |
| `markItemPacked(caseName, itemIdx, packed)` | `task_mark_item_packed` | `{ case_name, item_idx, packed }` |
| `markItemsPackedBatch(caseName, packed)` | `task_mark_items_packed_batch` | `{ case_name, packed }` |

These are thin wrappers around `callMethod` that provide parameter names and return types.

#### 1.4.3 Auth and session management — `src/auth.ts`

**`frappeLogin(page, user, password)`** — Navigate to `/login`, fill `#login_email` and `#login_password`, click `.btn-login`, wait for URL to contain `/app`. Timeout 15s. Throws on login failure (wrong credentials, disabled user).

**`createAllSessions(browser, config)`** — Iterates over all configured role credentials, logs in as each user, saves `storageState` to `sessions/{role}.json`. Called once during global setup. Returns a map of role → session file path.

**`asRole(browser, role)`** — Creates a new browser context loaded from the saved session file for that role. Returns the context. Caller is responsible for closing it.

Session files are stored in `tests/e2e/sessions/` (gitignored). They contain cookies and localStorage. They are recreated at the start of every test run (global setup), so stale sessions are never a problem.

#### 1.4.4 Frappe UI helpers — `src/frappe-ui.ts`

Browser-side helpers for Layers 2 and 3. These are the patterns that handle Frappe's dynamic SPA rendering.

**`waitForFrappeFormReady(page, doctype)`** — Wait for `window.cur_frm` to be initialized with the correct doctype, a loaded document, and rendered fields. Timeout 15s. This is the single most important helper — every browser test on a Task form starts with this.

**`waitForSaveComplete(page)`** — After triggering a save, wait for the Frappe "Saved" indicator or page reload. Watches for both success and error dialogs.

**`getFieldValue(page, fieldname)`** — Evaluates `cur_frm.doc[fieldname]` in the browser context.

**`isFieldVisible(page, fieldname)`** — Checks if the `[data-fieldname="{fieldname}"]` element is visible and not hidden by `display:none` or Frappe's `hidden` df property.

**`isFieldReadOnly(page, fieldname)`** — Evaluates `cur_frm.fields_dict[fieldname].df.read_only` in browser context.

**`readDialogText(page)`** — If a Frappe modal dialog is open (`.modal.show`), return its body text. Returns null if no dialog.

**`closeDialog(page)`** — Click the dialog's close button or primary action.

**Selectors reference (from actual deployed scripts):**

Desktop buttons:
- Accept: `.page-head .custom-actions .btn:has-text("Accept / Start Task")`
- Complete: `.page-head .custom-actions .btn:has-text("Complete")`
- Create DC: `.page-head .custom-actions .btn:has-text("Create Dispatch Case")`
- View DC: `.page-head .custom-actions .btn:has-text("View DC")`

Mobile buttons:
- Accept: `#task-bottom-actions button:has-text("Accept / Start Task")`
- Complete: `#task-bottom-actions button:has-text("Complete")`
- Create DC: `#task-bottom-actions button:has-text("Create Dispatch Case")`
- View DC: `#task-subheader .btn:has-text("View DC")`
- Back: `#task-subheader button` (first, contains `←`)
- Refresh: `#task-subheader button` (second, contains `↻`)

Fields: `[data-fieldname="{name}"]`

#### 1.4.5 Assertions — `src/assertions.ts`

**`assertNoDuplicateButtons(page, viewport)`** — For desktop: count each button text inside `.page-head`. For mobile: count inside `#task-bottom-actions` and `#task-subheader`. Fail if any button text appears more than once within its zone. Also cross-check that desktop-only buttons don't appear in the mobile zone and vice versa.

**`assertButtonFullyVisible(page, buttonText)`** — Get the button's `boundingBox()`. Fail if null, if any edge is outside the viewport, or if width/height is under 20px.

**`assertButtonState(page, buttonText, expected, viewport)`** — Check that a button is in the expected state (visible, hidden, enabled, disabled) at the given viewport. Uses the correct selector zone (desktop vs mobile).

**`assertFieldVisible(page, fieldname, expected)`** — Verify field matches expected visible/hidden state.

**`assertFieldReadOnly(page, fieldname, expected)`** — Verify field matches expected editable/read-only state.

**`assertNoConsoleErrors(errors, allowlist?)`** — Given collected console errors, fail if any are not in the allowlist. The allowlist handles known benign messages.

#### 1.4.6 Run manifest — `src/manifest.ts`

Tracks every ERPNext record created during a test run.

**`track(doctype, name, purpose)`** — Adds a record to the manifest. Called by test code after creating Tasks, Dispatch Cases, etc.

**`save(runDir)`** — Writes `run-manifest.json` to the run's output directory.

The manifest includes: `runId`, `baseUrl`, `environment`, `startTime`, `endTime`, and the full list of created records with their doctype, name, and purpose.

#### 1.4.7 Console and network capture — `src/capture.ts`

**`attachConsoleCapture(page)`** — Listens for `console.error`, `console.warning`, `pageerror` events. Collects entries with: type, text, URL, timestamp. Returns the collector array (passed to assertions and reports later).

**`attachNetworkCapture(page)`** — Listens for `requestfailed` events on URLs containing `/api/`. Collects: URL, method, failure reason, timestamp. Also optionally captures non-2xx responses on `/api/method/` and `/api/resource/` calls.

Both collectors exclude sensitive data (auth headers, cookies, request bodies containing passwords).

#### 1.4.8 Report writer — `src/reports.ts`

Creates a timestamped directory under `ERPNext-Automation-Reports/`:

```
ERPNext-Automation-Reports/
  2026-09-15_14-30-00_api-dispatch/
    report.json
    report.html
    run-manifest.json
    console.jsonl
    network.jsonl
    screenshots/
```

**`report.json`** — Machine-readable: scenario name, environment, status, duration, step results with pass/fail/skip, summary counts.

**`report.html`** — Human-readable: pass/fail banner, step timeline, inline screenshots for failures, console error summary, network error summary, list of created records. Self-contained single HTML file (CSS inline, screenshots base64-embedded or linked).

**`console.jsonl` / `network.jsonl`** — One JSON object per line, from the capture collectors.

#### 1.4.9 Types — `src/types.ts`

Shared TypeScript interfaces for:

- `TestConfig` (env vars)
- `RoleCredentials` (user + password per role)
- `FrappeDoc` (generic document with `name`, `doctype`, and arbitrary fields)
- `FrappeListResponse`, `FrappeMethodResponse`
- `FrappeError` (parsed server error with message and status code)
- `ManifestRecord` (doctype, name, purpose)
- `RunManifest`
- `StepResult` (name, status, expected, actual, screenshot path, duration)
- `TestReport`

#### 1.4.10 Global setup — `tests/setup/global-setup.ts`

Runs before all test projects. Steps:

1. Load config from `.env.local`
2. Validate environment (safety guard)
3. Verify API access: `GET /api/method/frappe.auth.get_logged_user` — fail if it doesn't return the expected user
4. Create browser sessions for all configured roles (login + save storageState)
5. Log summary: environment, roles available, session status

If any step fails, the entire test run is aborted with a clear error message

---

## Phase 2 — Layer 1: API Regression Tests

All tests use token auth via the Frappe API client (1.4.2). No browser.

**Completing a task via API:** The dispatch workflow depends on `Before Save` and `After Save` Server Scripts. To trigger the full chain, tests must use `POST /api/method/frappe.client.save` with the complete doc (not `PUT /api/resource/Task/{name}` which may not trigger Server Scripts consistently). Pattern: GET the doc → modify fields → POST frappe.client.save.

**Warehouse constants** (from `Task-after-save-dispatch-flow.py`):

```
Main - Inmed                    (source for dispatch)
Delivery In-Transit - Inmed     (pack → delivery handoff)
Return Pickup In-Transit - Inmed
Returns - Inmed
```

---

### 2.1 Dispatch Case no-return lifecycle

One sequential test with named steps. Each step depends on the previous.

**Setup:** Identify a test customer and 2 test items with stock in `Main - Inmed`.

#### Step 1 — Create Order Entry task

API: `POST /api/resource/Task`

```
{ subject: "E2E no-return test", task_kind: "Order entry",
  task_access_policy: "Order entry", customer: <test_customer> }
```

Assert:
- Task exists with status `Open`
- `dispatch_case` is empty (not yet created)
- Track task name in manifest

#### Step 2 — Accept task

API: `POST /api/method/dispatch_task_accept` with `{ task_name }`

Assert on response:
- `ok: true`
- `status: "Working"`
- `assigned_to` equals API session user
- `dispatch_case` is non-empty (auto-created for Order entry)

Assert on task (re-fetch):
- `status = "Working"`
- `custom_accepted_by` = session user
- `custom_accepted_at` is set

Assert on Dispatch Case (fetch by name from response):
- Exists with `status = "Draft"`, `docstatus = 0`
- `customer` matches test customer
- `order_entry_task` = task name
- Track DC name in manifest

#### Step 3 — Add products

API: Call `task_add_dispatch_product` twice:

```
{ task_name, item_code: "E2E-TEST-ITEM-001", qty: 2, unit_price: 1000 }
{ task_name, item_code: "E2E-TEST-ITEM-002", qty: 1, unit_price: 500 }
```

Assert after each call: `ok: true`

Assert on DC (re-fetch):
- `case_items` has 2 rows
- Row 0: `item_code = "E2E-TEST-ITEM-001"`, `dispatched_qty = 2`, `unit_price = 1000`
- Row 1: `item_code = "E2E-TEST-ITEM-002"`, `dispatched_qty = 1`, `unit_price = 500`

#### Step 4 — Complete Order Entry

API: GET task doc → set `status = "Completed"` → `frappe.client.save`

Before-save gates (server verifies automatically):
- DC has items ✓
- Customer set ✓
- No discount (`discount_pct = 0`) → DC gets submitted (`docstatus = 1`)

Assert on DC:
- `docstatus = 1` (submitted)

Assert on new Pack task (query: `dispatch_case = <dc>, task_kind = "Pack / prepare items"`):
- Exists with `status = "Open"`
- `dispatch_case` = DC name
- `customer` = test customer
- Track Pack task name in manifest

#### Step 5 — Accept Pack task, upload photo, mark items packed

API sequence:
1. `dispatch_task_accept` with Pack task name
2. Upload test photo: `POST /api/method/upload_file` (multipart) with `doctype=Task`, `docname=<pack_task>`, and a sample PNG from `fixtures/sample-photo.png`
3. `task_mark_items_packed_batch` with `{ case_name: <dc>, packed_indices: [0, 1] }`

Assert after photo upload:
- File record exists: `attached_to_doctype = "Task"`, `attached_to_name = <pack_task>`

Assert after batch pack:
- `ok: true`, `packed: 2`
- DC items: both rows have `custom_scanned_qty >= dispatched_qty`

#### Step 6 — Complete Pack task

API: GET Pack task → set `status = "Completed"` → `frappe.client.save`

Assert on DC:
- `status = "Packed"`
- `dispatch_stock_entry` is set

Assert on Stock Entry (fetch `dispatch_stock_entry`):
- `docstatus = 1` (submitted)
- Items transfer from `Main - Inmed` to `Delivery In-Transit - Inmed`
- Item codes and quantities match DC case_items

Assert on new Delivery task (query: `dispatch_case = <dc>, task_kind = "Delivery"`):
- Exists with `status = "Open"`
- Track in manifest

#### Step 7 — Accept Delivery, set Picked Up

API:
1. `dispatch_task_accept` with Delivery task
2. GET Delivery task → set `delivery_status = "Picked Up"` → `frappe.client.save`

Assert on DC:
- `status = "In Transit"`

#### Step 8 — Set Delivered

API: GET Delivery task → set `delivery_status = "Delivered"` → `frappe.client.save`

The before-save gate auto-sets `status = "Completed"` when `delivery_status = "Delivered"`.

Assert on Delivery task:
- `status = "Completed"` (auto-set by gate)

Assert on DC:
- `status = "Invoice Pending"`
- `delivery_stock_entry` is set (SE: `Delivery In-Transit` → client warehouse)
- `consumption_stock_entry` is set (SE: client warehouse → Material Issue)
- `sales_invoice` is set

Assert on Sales Invoice (fetch by DC `sales_invoice`):
- `docstatus = 0` (draft, not yet submitted)
- `customer` = test customer
- Items match: `E2E-TEST-ITEM-001` qty 2 rate 1000, `E2E-TEST-ITEM-002` qty 1 rate 500

Assert on Invoice Preparation task (query: `dispatch_case = <dc>, task_kind = "Invoice preparation / create invoice"`):
- Exists with `status = "Open"`
- Track in manifest

#### Step 9 — Submit Sales Invoice

The Invoice Preparation gate requires a submitted SI. Submit it before completing the task.

API: `POST /api/method/frappe.client.submit` with the SI doc

Assert: SI `docstatus = 1`

#### Step 10 — Complete Invoice Preparation

API:
1. `dispatch_task_accept` with Invoice Preparation task
2. GET task → set `status = "Completed"` → `frappe.client.save`

Assert on DC:
- `status = "Payment Pending"` (because outstanding > 0)
- `total_invoice_amount` = 2500 (2×1000 + 1×500)
- `outstanding_amount` = 2500 (no prepayment)

Assert on Debt Collection task (query: `customer = <test_customer>, task_kind = "Debt Collection"`):
- Exists
- `total_outstanding = 2500`
- `open_invoices` child table has 1 row with correct SI name and amounts
- Track in manifest

#### Step 11 — Record payment

API:
1. `dispatch_task_accept` with Debt Collection task
2. GET task → set `new_payment_amount = 2500`, `payment_method_dc = "Cash"`, `payment_reference_dc = "E2E-TEST-REF"` → `frappe.client.save`

The before-save payment recording script:
- Creates and submits a Payment Entry
- Allocates payment across open_invoices
- Sets `total_outstanding = 0` → auto-sets `status = "Completed"`

Assert on Debt Collection task (re-fetch):
- `status = "Completed"`
- `total_outstanding = 0`
- `new_payment_amount = 0` (cleared by script)
- `payment_history` has 1 row with amount=2500, method="Cash"

Assert on Payment Entry (from `payment_history[0].payment_entry`):
- `docstatus = 1` (submitted)
- `payment_type = "Receive"`
- `party = <test_customer>`
- `paid_amount = 2500`
- Track in manifest

Assert on Debt Closure Approval task (query: `customer = <test_customer>, task_kind = "Debt Closure Approval"`):
- Exists (created by after-save)
- Track in manifest

**Note:** The DC remains at `status = "Payment Pending"` after payment. The Debt Closure Approval calculates profit but does not change DC status to "Closed". The only path to "Closed" is when Invoice Preparation completes with outstanding <= 0 (i.e., fully prepaid). This is the current server-side behavior — the test verifies it accurately.

---

### 2.2 Dispatch Case return-expected lifecycle

One sequential test. Shares steps 1–7 with 2.1 (through Picked Up) but with `return_expected = 1`.

#### Setup differences from 2.1

- Set `order_return_expected = 1` on the Order entry task before completing
- Set `order_client_location_warehouse` to a warehouse under `Clients - Inmed` (required when return_expected is checked)
- The before-save gate syncs these to the DC

Steps 1–7 are identical except the DC has `return_expected = 1`.

#### Step 8 — Set Delivered (return-expected)

API: GET Delivery task → set `delivery_status = "Delivered"` → `frappe.client.save`

Assert on DC:
- `status = "Awaiting Return Pickup"` (not Invoice Pending)
- `delivery_stock_entry` is set (SE: `Delivery In-Transit` → client warehouse)
- No `consumption_stock_entry` (not consumed yet)
- No `sales_invoice` (not invoiced yet)

Assert on Return Call task (query: `dispatch_case = <dc>, task_kind = "Return Call"`):
- Exists with `status = "Open"`
- Track in manifest

#### Step 9 — Complete Return Call

API:
1. `dispatch_task_accept`
2. Optionally set `return_pickup_driver` and `scheduled_return_date`
3. GET → set `status = "Completed"` → `frappe.client.save`

Assert on DC:
- `status = "Return Pickup Scheduled"`

Assert on Pickup Returns task (query: `dispatch_case = <dc>, task_kind = "Pickup Returns"`):
- Exists
- If `return_pickup_driver` was set, task is assigned to that user
- Track in manifest

#### Step 10 — Accept Pickup Returns, set Picked Up

API:
1. `dispatch_task_accept` with Pickup Returns task
2. GET → set `pickup_status = "Picked Up"` → `frappe.client.save`

Assert on DC:
- `status = "Return In Transit"`
- `return_pickup_stock_entry` is set (SE: client warehouse → `Return Pickup In-Transit - Inmed`)

#### Step 11 — Upload drop-off photo, set Returned to Warehouse

Before-save gate requires a photo before Returned to Warehouse.

API:
1. Upload photo to Pickup Returns task (same pattern as Pack photo)
2. GET → set `pickup_status = "Returned to Warehouse"` → `frappe.client.save`

Gate auto-sets `status = "Completed"`.

Assert on DC:
- `status = "Returns Received"`
- `return_receive_stock_entry` is set (SE: `Return Pickup In-Transit` → `Returns - Inmed`)

Assert on Returns Inspection task (query: `dispatch_case = <dc>, task_kind = "Returns processing / verification"`):
- Exists
- Track in manifest

#### Step 12 — Fill returned quantities, complete Returns Inspection

Before completing, every `case_items` row must have `returned_qty` filled. Use `task_mark_items_packed_batch` with `task_kind = "Returns processing / verification"` to set returned quantities (this API handles returns mode).

API:
1. `dispatch_task_accept` with Returns Inspection task
2. `task_mark_items_packed_batch` with `{ case_name: <dc>, packed_indices: [0], task_kind: "Returns processing / verification" }`
   This marks item 0 as returned (`returned_qty = dispatched_qty`), item 1 as used (`returned_qty = 0`)
3. Manually set `returned_qty` on remaining rows if needed via `PUT /api/resource/Dispatch Case/<dc>` (update case_items)
4. GET task → set `status = "Completed"` → `frappe.client.save`

Assert on DC:
- `status = "Invoice Pending"`
- `consumption_stock_entry` is set (SE: `Returns - Inmed` → Material Issue, for used items only)
- `sales_invoice` is set

Assert on Sales Invoice:
- Items reflect **used qty**, not dispatched qty
- Item 0: qty = 0 (returned), Item 1: qty = 1 (used) — or whatever the reconciliation produces

Assert on Invoice Preparation task: exists
Assert on Returns Restocking task (query: `task_kind = "Returns restocking"`): exists if any `returned_qty > 0`

#### Step 13 — Complete Returns Restocking

API:
1. `dispatch_task_accept`
2. GET → set `status = "Completed"` → `frappe.client.save`

Assert on DC:
- `restock_stock_entry` is set (SE: `Returns - Inmed` → `Main - Inmed`, for returned items)

#### Steps 14–16 — Invoice Preparation, Debt Collection, Debt Closure

Same as steps 9–11 of the no-return lifecycle (2.1). Submit SI, complete Invoice Prep, record payment.

---

### 2.3 Discount approval gate

Two tests: approve path and reject path.

#### Setup (shared)

1. Create Order Entry task with customer
2. Accept task
3. Add items **with discount**: `task_add_dispatch_product` with `discount_pct: 10`
4. Complete Order Entry

#### Assertions after Order Entry completion (both paths)

The before-save gate detects `discount_pct > 0`:
- DC `status = "Awaiting Approval"`, `discount_approval_status = "Pending"`
- DC `docstatus = 0` (NOT submitted — discount blocks submission)
- **No Pack task created** (after-save checks `docstatus == 1`, which is false)
- Discount Approval task created (query: `dispatch_case = <dc>, task_kind = "Discount Approval"`)

#### Test A — Approve

1. Accept Discount Approval task
2. GET → set `approval_outcome = "Approved"`, `status = "Completed"` → `frappe.client.save`

Assert:
- DC `docstatus = 1` (submitted by after-save)
- DC `status = "Confirmed"` (set by after-save before submit)
- DC `discount_approval_status = "Approved"`
- Pack task created (query: `task_kind = "Pack / prepare items"`)

#### Test B — Reject

1. Accept Discount Approval task
2. GET → set `approval_outcome = "Rejected"`, `status = "Completed"` → `frappe.client.save`

Assert:
- DC `status = "Draft"` (reset by after-save)
- DC `discount_approval_status = "Rejected"`
- DC `docstatus = 0` (not submitted)
- **No Pack task** (query returns empty)
- New Order Entry task created (query: `dispatch_case = <dc>, task_kind = "Order entry", status != "Completed"`)

---

### 2.4 Task system invariants

Independent tests. Each creates its own task for isolation.

#### Test: Save without acceptance is blocked

1. Create task (status = Open)
2. GET task → modify any field → `frappe.client.save`
3. Expect HTTP error with message: `"You must Accept this task before making any changes or completing it."`

#### Test: Complete without acceptance is blocked

1. Create task
2. GET task → set `status = "Completed"` → `frappe.client.save`
3. Expect error: `"You must accept this task before completing it. Click Accept / Start Task first."`

#### Test: Complete by non-accepted user is blocked

This requires two different API users. If only one API user is available, this test is deferred to Layer 2/3 (browser-based role testing).

If testable:
1. Accept task as User A
2. Attempt complete as User B
3. Expect error: `"Only the user who accepted this task (User A) can complete it."`

#### Test: Accept with wrong role is blocked

Requires an API user that lacks the required role. If the admin API user is used (which has all roles), this test must be deferred to browser tests.

If testable:
1. Create task with `task_kind` that requires a specific role
2. Accept as a user without that role
3. Expect error: `"You are not allowed to accept this task kind. Required role: ..."`

#### Test: Simultaneous reassign and complete is blocked

1. Create and accept task
2. GET task → set `status = "Completed"` AND `custom_assigned_to = "<different_user>"` → `frappe.client.save`
3. Expect error: `"You cannot reassign and complete a task at the same time."`

#### Test: Duplicate DC creation returns existing

1. Create Order Entry task, accept (auto-creates DC)
2. Call `task_create_dispatch_case` with same task
3. Assert response: `{ ok: true, created: false, dispatch_case: "<existing_dc_name>" }`
4. Verify only one DC exists for this task

#### Test: Task Access Policy is source of truth

1. Query `Task Access Policy` records via API
2. For each policy: verify `name` matches a valid `task_kind`, verify `allowed_roles` is non-empty, verify `default_team_user` is set
3. This is a data integrity check, not a workflow test

---

### 2.5 Completion gates

Each test creates a task in the required state, then attempts an invalid completion. All expect HTTP errors.

#### Test: Pack without photo

1. Create Order Entry → accept → add items → complete (creates Pack task)
2. Accept Pack task
3. Mark items packed via `task_mark_items_packed_batch`
4. **Do NOT upload a photo**
5. Attempt complete
6. Expect error: `"At least one photo is required before completing the Pack / prepare items task."`

#### Test: Pack with unpacked items

1. Same setup, but DO upload a photo
2. **Do NOT mark items as packed** (skip `task_mark_items_packed_batch`)
3. Attempt complete
4. Expect error: `"All items must be packed before completing this task. Not packed: ..."` with item codes listed

#### Test: Delivery status skip (Todo → Delivered)

1. Create Order Entry → complete → Pack → complete (creates Delivery task)
2. Accept Delivery task
3. GET → set `delivery_status = "Delivered"` (skipping "Picked Up") → save
4. Expect error: `"Delivery status must be changed to 'Picked Up' and saved before it can be marked as 'Delivered'."`

#### Test: Delivery complete without Delivered status

1. Accept Delivery task
2. GET → set `status = "Completed"` (delivery_status still "Todo") → save
3. Expect error: `"Delivery task cannot be completed until delivery status is 'Delivered'."`

#### Test: Pickup Returns status skip (Todo → Returned to Warehouse)

1. Advance through return-expected flow to Pickup Returns task
2. Accept, then set `pickup_status = "Returned to Warehouse"` (skipping "Picked Up")
3. Expect error: `"Pickup status must be changed to 'Picked Up' and saved before it can be marked as 'Returned to Warehouse'."`

#### Test: Pickup Returns without drop-off photo

1. Accept Pickup Returns, set `pickup_status = "Picked Up"`, save
2. Set `pickup_status = "Returned to Warehouse"` without uploading photo
3. Expect error: `"At least one photo is required before marking Returned to Warehouse."`

#### Test: Returns Inspection without returned_qty

1. Advance through return-expected flow to Returns Inspection task
2. Accept task
3. Leave `returned_qty` null on case_items rows
4. Attempt complete
5. Expect error: `"Fill returned_qty for ALL items in Dispatch Case before completing."`

#### Test: Invoice Preparation without submitted SI

1. Advance to Invoice Preparation task (draft SI exists)
2. Accept task
3. Attempt complete **without submitting the SI first**
4. Expect error: `"Submit the Sales Invoice before completing this task."`

#### Test: Discount Approval without outcome

1. Create discounted order → Discount Approval task created
2. Accept Discount Approval
3. Attempt complete without setting `approval_outcome`
4. Expect error: `"Set Approval Outcome (Approved or Rejected) before completing."`

#### Test: Order Entry without items

1. Create Order Entry, accept, create DC (but add no items)
2. Attempt complete
3. Expect error: `"Add at least one product before completing."`

#### Test: Order Entry without customer

1. Create Order Entry **without customer**, accept, add items
2. Attempt complete
3. Expect error: `"Select a Customer before completing the order."`

#### Test: Order Entry return_expected without warehouse

1. Create Order Entry with customer, accept, add items
2. Set `order_return_expected = 1` but leave `order_client_location_warehouse` empty
3. Attempt complete
4. Expect error: `"Client Location Warehouse is required when Return Expected is checked."`

---

### 2.6 Test execution dependencies

The lifecycle tests (2.1, 2.2) are sequential — each step depends on the previous. They are structured as single test files with `test.step()` for each phase.

The invariant tests (2.4) and gate tests (2.5) are independent — each creates its own task. They can run in parallel.

Some gate tests (2.5) require advancing through the workflow to a specific state. To avoid duplicating the full lifecycle setup, the test infrastructure provides a **state factory** — a helper that rapidly creates a task at any desired state using API calls:

```
createTaskAtState("pack-accepted")     → Order Entry completed, Pack task accepted
createTaskAtState("delivery-accepted") → Pack completed, Delivery task accepted
createTaskAtState("pickup-accepted")   → Delivery delivered (return), Pickup Returns accepted
createTaskAtState("inspection-accepted") → Pickup returned, Returns Inspection accepted
createTaskAtState("invoice-accepted")  → Inspection completed, Invoice Preparation accepted
```

This factory is built from the same API calls used in the lifecycle tests, but packaged as a reusable setup function. It runs in seconds (pure API, no browser)

---

## Phase 3 — Layer 2: Browser Smoke Tests

All tests run at **both** viewports via Playwright projects — same test files, different config:
- Desktop: `1280×720`
- Mobile: `375×812`

Tests are assertion-only — they navigate to a pre-created task, inspect the DOM, and verify. No clicking Accept/Complete/Create DC in the browser (that is Layer 3). Test data is created via the Frappe API client before the browser opens.

---

### 3.1 Test data factory

A `beforeAll` hook creates all tasks needed by the smoke suite via API. No browser involved in setup. This runs once per suite execution (not per test).

**Tasks to create** (each at a specific state using the Phase 2 state factory):

| # | Task kind | State | Has DC | Extra state | Purpose |
|---|---|---|---|---|---|
| 1 | Order entry | Open | no | — | Buttons: Accept visible |
| 2 | Order entry | Accepted | yes | — | Buttons: Complete + View DC |
| 3 | Order entry | Accepted | yes | `return_expected=1`, warehouse set | Field visibility: `__order_return__` rule |
| 4 | Order entry | Completed | yes | — | Buttons: View DC only; fields locked |
| 5 | Pack / prepare items | Open | yes | — | Buttons: Accept + View DC |
| 6 | Pack / prepare items | Accepted | yes | — | Buttons: Complete + View DC |
| 7 | Delivery | Accepted | yes | `delivery_status=Todo` | Buttons: "Picked Up" |
| 8 | Delivery | Accepted | yes | `delivery_status=Picked Up` | Buttons: "Delivered" |
| 9 | Delivery | Completed | yes | `delivery_status=Delivered` | Buttons: View DC only |
| 10 | Pickup Returns | Accepted | yes | `pickup_status=Todo` | Buttons: "Picked Up" |
| 11 | Pickup Returns | Accepted | yes | `pickup_status=Picked Up` | Buttons: "Returned to WH" |
| 12 | Return Call | Accepted | yes | — | Buttons: Complete + View DC |
| 13 | Returns processing | Accepted | yes | — | Buttons: Complete + View DC |
| 14 | Returns restocking | Accepted | yes | — | Buttons: Complete + View DC |
| 15 | Invoice preparation | Accepted | yes | — | Buttons: Complete + View DC |
| 16 | Discount Approval | Accepted | yes | — | Buttons: Complete + View DC |
| 17 | Debt Collection | Open | no | — | Buttons: Accept |
| 18 | Debt Collection | Accepted | no | — | Buttons: Complete |
| 19 | Debt Closure Approval | Accepted | yes | — | Buttons: Complete + View DC |
| 20 | Payment Received | Accepted | yes | — | Buttons: Complete + View DC |
| 21 | Other: Entry | Accepted | no | — | Fields: other_items visible |
| 22 | Other: Processing | Accepted | no | — | Fields: other_items visible |
| 23 | Purchase Approval | Accepted | no | — | Fields: purchase_order visible |

All tasks are tracked in the run manifest. Tasks are created using the admin API user (same as Phase 2).

For tests that need to verify the "not accepted" UI state, the browser session must log in as the **same user who will browse** — who is NOT the API user that created the task. This ensures `custom_accepted_by !== session.user`.

For tests that need to verify the "accepted" UI state, the task must be accepted by the same user whose browser session is viewing it. The API `dispatch_task_accept` must be called with that user's API credentials, or the task must be accepted via the admin API user who matches `frappe.session.user`.

---

### 3.2 Assertion helpers

These are implemented in `src/assertions.ts` (Phase 1) and used by all smoke tests. Key viewport-aware selectors:

#### Button zone selectors

| Viewport | Zone | Selector | Contains |
|---|---|---|---|
| Desktop | Header actions | `.page-head .custom-actions` | Accept, Complete, Create DC, primary actions |
| Desktop | Page actions | `.page-head .page-actions` | Frappe standard buttons (Menu, etc.) |
| Mobile | Bottom floating | `#task-bottom-actions` | Accept, Complete, Create DC, primary actions |
| Mobile | Sub-header | `#task-subheader` | Back, Refresh, View DC |

#### Button identification

Buttons have no stable IDs — identify by **text content within zone**:

| Button | Text | Desktop location | Mobile location |
|---|---|---|---|
| Accept | `"Accept / Start Task"` | `.custom-actions` | `#task-bottom-actions` |
| Complete | `"Complete"` | `.custom-actions` | `#task-bottom-actions` |
| Create DC | `"Create Dispatch Case"` | `.custom-actions` | `#task-bottom-actions` |
| View DC | `"View DC"` | `.custom-actions` | `#task-subheader` |
| Picked Up | `"Picked Up"` | `.custom-actions` | `#task-bottom-actions` |
| Delivered | `"Delivered"` | `.custom-actions` | `#task-bottom-actions` |
| Returned to WH | `"Returned to WH"` | `.custom-actions` | `#task-bottom-actions` |
| Back | `"←"` (U+2190) | N/A | `#task-subheader` |
| Refresh | `"↻"` (U+21BB) | N/A | `#task-subheader` |

#### Core assertion functions

**`assertButtonPresent(page, buttonText, viewport)`** — Locate button by text in the correct zone for the viewport. Assert it exists and is visible.

**`assertButtonAbsent(page, buttonText, viewport)`** — Assert no element with that text exists in the zone, OR it exists but is hidden.

**`assertNoDuplicateButtons(page, viewport)`** — Collect all button texts in the zone. Fail if any text appears more than once.

**`assertButtonFullyVisible(page, buttonText, viewport)`** — Get `boundingBox()`. Fail if:
- Box is null (element not rendered)
- `x < 0` or `y < 0` (clipped left/top)
- `x + width > viewportWidth` (clipped right)
- `y + height > viewportHeight` (clipped bottom — BUT mobile bottom bar is fixed-position, so it's allowed to be near the bottom edge)
- `width < 20` or `height < 20` (too small to tap/click)

**`assertFieldVisible(page, fieldname)`** — Check `[data-fieldname="{fieldname}"]` element: `display !== "none"`, not hidden by Frappe's `hidden` df property. Also check parent section is not collapsed/hidden.

**`assertFieldHidden(page, fieldname)`** — Inverse: element has `display: none` or parent section hidden.

**`assertFieldEditable(page, fieldname)`** — Evaluate in browser: `cur_frm.fields_dict["{fieldname}"].df.read_only === 0`. Also check that the input is not `disabled` via DOM.

**`assertFieldReadOnly(page, fieldname)`** — Evaluate in browser: `cur_frm.fields_dict["{fieldname}"].df.read_only === 1`.

**`assertIntroMessage(page, expected)`** — Check `.form-message` text content and color class. `expected` is one of: `null` (no intro), `{ text, color: "green"|"yellow"|"red" }`.

**`assertNoConsoleErrors(collected, allowlist)`** — Given the console capture array, fail if any `console.error` or `pageerror` is not in the allowlist. The allowlist permits known benign messages (e.g., Frappe telemetry, font loading).

**`assertNoFailedRequests(collected)`** — Given the network capture array, fail if any `/api/` request failed (non-2xx or network error).

---

### 3.3 Task button state matrix

One parameterized test. Each row defines the expected button state for a task kind + status + substatus combination. The test navigates to the pre-created task, waits for `cur_frm` to load, then asserts.

#### Desktop button matrix

| # | Task | State | Accept | Complete | Create DC | View DC | Primary label | Notes |
|---|---|---|---|---|---|---|---|---|
| 1 | Order entry, Open | not accepted | **YES** | no | no | no | — | Accept is primary type |
| 2 | Order entry, Accepted | accepted, has DC | no | **YES** | no | **YES** | "Complete" | |
| 3 | Order entry, Completed | completed | no | no | no | **YES** | — | Only View DC |
| 4 | Pack, Open | not accepted, has DC | **YES** | no | no | **YES** | — | |
| 5 | Pack, Accepted | accepted, has DC | no | **YES** | no | **YES** | "Complete" | |
| 6 | Delivery, Accepted ds=Todo | accepted, has DC | no | no | no | **YES** | "Picked Up" | |
| 7 | Delivery, Accepted ds=Picked Up | accepted, has DC | no | no | no | **YES** | "Delivered" | |
| 8 | Delivery, Completed | completed | no | no | no | **YES** | — | |
| 9 | Pickup Returns, Accepted ps=Todo | accepted, has DC | no | no | no | **YES** | "Picked Up" | |
| 10 | Pickup Returns, Accepted ps=Picked Up | accepted, has DC | no | no | no | **YES** | "Returned to WH" | |
| 11 | Return Call, Accepted | accepted, has DC | no | **YES** | no | **YES** | "Complete" | |
| 12 | Returns proc, Accepted | accepted, has DC | no | **YES** | no | **YES** | "Complete" | |
| 13 | Invoice prep, Accepted | accepted, has DC | no | **YES** | no | **YES** | "Complete" | |
| 14 | Discount Approval, Accepted | accepted, has DC | no | **YES** | no | **YES** | "Complete" | |
| 15 | Debt Collection, Open | not accepted, no DC | **YES** | no | no | no | — | |
| 16 | Debt Collection, Accepted | accepted, no DC | no | **YES** | no | no | "Complete" | |
| 17 | Debt Closure, Accepted | accepted, has DC | no | **YES** | no | **YES** | "Complete" | |
| 18 | Payment Received, Accepted | accepted, has DC | no | **YES** | no | **YES** | "Complete" | |

#### Mobile button matrix

Same rows as desktop but verified in mobile zones:

- Accept → `#task-bottom-actions button:has-text("Accept / Start Task")`
- Primary action → `#task-bottom-actions button:has-text("{label}")`
- View DC → `#task-subheader .btn:has-text("View DC")`
- Back → `#task-subheader button` (first, text `←`)
- Refresh → `#task-subheader button` (second, text `↻`)

Additional mobile-only assertions per row:
- `#task-subheader` exists when `!is_new`
- `#task-bottom-actions` does NOT exist when `status === "Completed"` or `"Cancelled"`
- Back and Refresh always present in sub-header

#### Negative assertions (critical for regressions)

For every row, also assert that buttons which should NOT appear are absent:
- Row 1 (Open, not accepted): no Complete, no Create DC, no View DC, no Picked Up, no Delivered
- Row 3 (Completed): no Accept, no Complete, no Create DC, no Picked Up
- Row 6 (Delivery ds=Todo): no Complete, no Accept, no Delivered, no Returned to WH
- etc.

These negative assertions directly catch the user's reported regressions: "some button has disappeared" and "some additional button is there although it should not be."

---

### 3.4 Duplicate button detection

A standalone test that runs on every pre-created task. For each task:

1. Navigate and wait for `cur_frm` ready
2. Collect all button texts in the active zone (desktop or mobile)
3. Assert each text appears at most once

**Desktop:** Collect from `.page-head .custom-actions .btn`.

**Mobile:** Collect from both `#task-bottom-actions button` and `#task-subheader button`. Cross-check: no button text appears in BOTH zones (except if designed to — currently none should).

**Explicitly checked button texts:**
- `"Accept / Start Task"` — must appear 0 or 1 times
- `"Complete"` — must appear 0 or 1 times
- `"Create Dispatch Case"` — must appear 0 or 1 times
- `"View DC"` — must appear 0 or 1 times
- `"Picked Up"` — must appear 0 or 1 times
- `"Delivered"` — must appear 0 or 1 times
- `"Returned to WH"` — must appear 0 or 1 times

Also assert: no orphan elements from disabled scripts:
- `#task-delivery-ui-fix-css` must not exist
- `#task-mobile-form-layout-fix-style` must not exist
- `#task-subject-field-visibility-fix` must not exist
- Body must not have class `task-mobile-pack-clean` or `task-delivery-ui-active`

---

### 3.5 Button clipping detection

For every pre-created task at every viewport:

1. Navigate and wait for `cur_frm` ready
2. Find all visible buttons in the active zone
3. For each button, get `boundingBox()`
4. Assert:
   - Box is non-null
   - `width >= 20` and `height >= 20` (minimum touch/click target)
   - Desktop: `x >= 0`, `x + width <= 1280`, `y >= 0`
   - Mobile bottom actions: buttons are `position: fixed` at bottom — verify `x >= 0`, `x + width <= 375`, `width >= 60` (large enough for finger tap), and buttons don't overlap each other (check for bounding box intersections between siblings)
   - Mobile sub-header: `x >= 0`, `x + width <= 375`

**Overlap detection** (mobile bottom bar): For every pair of buttons in `#task-bottom-actions`, assert their bounding boxes do not intersect. This catches the reported "button is there but is half visible due to some indent" regression.

---

### 3.6 Field visibility by task kind

Parameterized test — one iteration per task kind. For each kind, create a task at the accepted/working state (so fields are in their operational configuration), navigate in the browser, and verify every field in `TFV_KIND_MAP` and `TFV_ALWAYS_HIDDEN`.

#### Verification algorithm

For each field in `TFV_KIND_MAP`:

1. Determine the expected visibility by evaluating the rule against the current task's state:
   - `"__all__"` → visible
   - `"__never__"` → hidden
   - `"__completed__"` → visible only if `status === "Completed"`
   - `"__product__"` → visible if kind is Pack, Returns proc, or (Order entry + has DC)
   - `"__scan_product__"` → visible if kind is Pack or Returns proc, and has DC
   - `"__has_value__"` → visible if the field has a truthy value on this task
   - `"__dispatch_or_value__"` → visible if kind is in `TFV_DISPATCH_FLOW_KINDS` or field has value
   - `"__order_return__"` → visible if kind is Order entry and `return_expected` is checked
   - `[array]` → visible if kind is in the array

2. Check the DOM: `[data-fieldname="{fieldname}"]` element visibility

3. Assert match

For each field in `TFV_ALWAYS_HIDDEN`:
- Assert hidden regardless of task kind

#### Task kinds and their notable field expectations

**Order entry:**
- Visible: `subject`, `task_kind`, `custom_assigned_to`, `custom_next_task_assign_to`, `customer`, `order_return_expected`, `order_surgery_date`, `order_template`, `custom_product_work_section`, `custom_task_product_summary`
- Hidden: `dispatch_case`, `delivery_status`, `pickup_status`, `completed_at`, `sales_invoice` (no value), `payment_entry` (no value), all debt fields, all return fields, all scan fields
- `order_client_location_warehouse`: visible ONLY when `return_expected` is checked → test with task #3

**Pack / prepare items:**
- Visible: `custom_product_work_section`, `custom_task_product_summary`, `custom_task_scan_barcode`, `custom_task_scan_qty`, `custom_task_scan_result`, `custom_next_task_assign_to`
- Hidden: all order-entry fields, all debt fields, `dispatch_case` (View DC button instead)

**Delivery:**
- Visible: `subject`, `task_kind`, `custom_assigned_to`, `custom_next_task_assign_to`, `customer`
- Hidden: `delivery_status` (always `__never__` — replaced by buttons), `pickup_status`, all order fields, all scan fields, all debt fields

**Debt Collection:**
- Visible: `current_debt_amd`, `debt_threshold_amd`, `new_payment_amount`, `payment_method_dc`, `payment_reference_dc`, `total_outstanding`, `available_advance_credit`, `custom_case_profit`, `custom_total_amount_paid`, `open_invoices`, `payment_history`
- Hidden: all order fields, all delivery/pickup fields, all product/scan fields

**Returns processing / verification:**
- Visible: `custom_product_work_section`, `custom_task_product_summary`, `custom_task_scan_barcode`, `custom_task_scan_qty`, `custom_task_scan_result`, `custom_next_task_assign_to`
- Hidden: all debt fields, all order fields

**Other: Entry / Other: Processing:**
- Visible: `other_items`, `other_budget`, `other_supplier`
- Hidden: all dispatch fields, all debt fields, all product/scan fields

**Purchase Approval:**
- Visible: `purchase_order`, `approval_outcome`, `approval_note`
- Hidden: all dispatch fields, all debt fields, all product/scan fields

**Discount Approval:**
- Visible: `approval_outcome`, `approval_note`, `custom_next_task_assign_to`
- Hidden: `purchase_order`, all debt fields, all order-entry fields

#### Completed status test

Run the visibility check on completed tasks (task #4 and #9) to verify:
- `completed_at` IS visible (rule `__completed__`)
- All `__completed__`-rule fields visible
- Other field rules unchanged by completion

#### Product section label test

Verify the dynamic section label set by TFV:
- Order entry → `"Products"`
- Pack → `"Products / Packing"`
- Returns processing → `"Products / Returns"`
- Other dispatch kind → `"Products / Dispatch Work"`

Check via: `cur_frm.fields_dict.custom_product_work_section.df.label`

#### Photo gallery visibility test

For kinds in `TFV_PHOTO_GALLERY_KINDS` (Pack, Pickup Returns, Returns proc, Other: Entry, Other: Processing):
- `frm._tfv_show_gallery` should be `true`
- `[id^="photo-gallery-host-"]` should not be force-hidden

For other kinds:
- `frm._tfv_show_gallery` should be `false`

---

### 3.7 Field editability by state

Parameterized test — for each task kind, verify editability across three states: not-accepted, accepted, and completed.

#### Editability gate (`tfe_can_edit`) verification

| State | `tfe_can_edit` | Save button | Intro message |
|---|---|---|---|
| New task | `true` | enabled | none |
| Open, not accepted | `false` | disabled | yellow: "You must accept this task before you can edit it." |
| Accepted by current user | `true` | enabled | none |
| Completed | `false` | disabled | green: "This task is completed and cannot be modified." |
| Cancelled | `false` | disabled | red: "This task is cancelled and cannot be modified." |

For each state, verify:
1. Save button enabled/disabled (check `frm.page.btn_primary.prop("disabled")` or DOM state)
2. Intro message text and color
3. DOM-level disability: when `!can_edit`, form inputs should have `disabled` attribute and reduced opacity

#### Per-field editability matrix

For each field in `TFE_EDIT_MAP`:

| Rule | Not accepted | Accepted, kind matches | Accepted, kind doesn't match | Completed |
|---|---|---|---|---|
| `"__never__"` | read-only | read-only | read-only | read-only |
| `"__accepted__"` | read-only | editable | editable | read-only |
| `[array]` | read-only | editable (if kind in array) | read-only | read-only |

Fields NOT in `TFE_EDIT_MAP` (unmapped) follow the blanket default: editable when `tfe_can_edit` is true, read-only otherwise.

#### Key fields to verify per kind

**Order entry (accepted):**
- Editable: `customer`, `order_return_expected`, `order_client_location_warehouse`, `order_surgery_date`, `order_template`, `subject`, `description` (unmapped → blanket)
- Locked: `task_kind`, `dispatch_case`, `delivery_status`, `completed_at`

**Pack / prepare items (accepted):**
- Editable: `subject`, `description`, `custom_next_task_assign_to` (unmapped → blanket)
- Locked: `task_kind`, `dispatch_case`, `customer` (kind not in its array)

**Debt Collection (accepted):**
- Editable: `new_payment_amount`, `payment_method_dc`, `payment_reference_dc`
- Locked: `task_kind`, `dispatch_case`, `total_outstanding`, `available_advance_credit`, `custom_case_profit`, `custom_total_amount_paid`, `open_invoices`, `payment_history`

**Discount Approval (accepted):**
- Editable: `approval_outcome`, `approval_note`
- Locked: `task_kind`, all debt display fields

**Not accepted (any kind):**
- ALL fields locked
- DOM inputs disabled, opacity 0.6, pointer-events none
- Grid add-row and remove-rows buttons hidden

#### DOM-level disability assertion

When `tfe_can_edit` is false, verify:
- `$(frm.wrapper).find('input:not(#task-product-summary-wrapper input)')` has `disabled` attribute
- `.btn-attach`, `.btn-open`, `.grid-add-row`, `.grid-remove-rows` are hidden
- `.ql-editor` has `pointer-events: none`

When `tfe_can_edit` is true, verify:
- Inputs are NOT disabled
- Attach/grid buttons are visible

---

### 3.8 Console and network health

For every pre-created task, on initial page load:

#### Console error check

1. Attach console capture before navigation
2. Navigate to `Form/Task/{name}`
3. Wait for `cur_frm` ready
4. Wait additional 2s for async client scripts to finish
5. Collect all `console.error` and `pageerror` events
6. Filter through allowlist:
   - Font loading warnings (benign)
   - Frappe telemetry/analytics (benign)
   - `ResizeObserver loop` (benign Chrome issue)
7. Assert: no remaining errors

#### Network failure check

1. Attach network capture before navigation
2. Navigate and wait for form ready
3. Collect all failed requests (`requestfailed` event) on `/api/` URLs
4. Collect all non-2xx responses on `/api/method/` and `/api/resource/` URLs
5. Assert: no failed API requests on page load

#### TFV/TFE/TAB script load verification

After form load, evaluate in browser:
- `typeof tfv_apply === "function"` → TFV loaded
- `typeof tfe_apply === "function"` → TFE loaded
- `typeof tfe_can_edit === "function"` → TFE gate available
- `typeof tab_can_act === "function"` → TAB loaded

If any returns false, the client scripts failed to load — critical regression.

#### Dashboard comment verification

Based on task state, verify:
- Task with DC + kind !== "Order entry" → blue comment containing "Dispatch Case / Packing Items"
- Task that needs DC but has none → orange comment containing "needs a Dispatch Case"
- Task that doesn't need DC → no dashboard comment

---

### 3.9 Mobile-specific assertions

These only run in the `mobile` project (viewport 375×812).

#### Mobile CSS injection

Assert `#task-mobile-layout-css` style element exists in `<head>` after form load.

#### Mobile scroll-to-top

Navigate to a task form. Assert `window.scrollY === 0` after load (or close to 0).

#### Mobile bottom bar padding

Assert `body[data-route^='Form/Task'] .form-page` has `padding-bottom >= 80px` (prevents content from hiding behind the floating action bar).

#### Mobile sub-header presence

For every non-new task:
- `#task-subheader` exists
- Contains exactly 2 navigation buttons (Back + Refresh) on the left
- Back button contains `←` (U+2190)
- Refresh button contains `↻` (U+21BB)

#### Mobile grid horizontal scroll

If the task has a child table (e.g., `open_invoices` on Debt Collection), verify:
- `.grid-body` or `.form-grid` has `overflow-x: auto`
- Grid rows have `min-width: 330px`

---

### 3.10 Test file organization

```
tests/smoke/
  task-buttons.spec.ts            — 3.3 + 3.4 + 3.5 (button matrix, duplicates, clipping)
  task-field-visibility.spec.ts   — 3.6 (TFV_KIND_MAP verification)
  task-field-editability.spec.ts  — 3.7 (TFE_EDIT_MAP verification)
  task-health.spec.ts             — 3.8 (console, network, script load, dashboard)
  task-mobile.spec.ts             — 3.9 (mobile-only CSS, scroll, padding, subheader)
```

Each file shares the same `beforeAll` test data factory (3.1). The factory creates all 23 tasks once, stores their names in a shared fixture, and all tests reference them by index.

The tests are run by both the `desktop` and `mobile` Playwright projects (except `task-mobile.spec.ts` which has a project filter to run only in `mobile`). Viewport-aware assertion helpers automatically use the correct selectors based on the project config.

---

### 3.11 Regression coverage summary

| User-reported problem | Test that catches it |
|---|---|
| Accept button disappeared | 3.3 rows 1, 4, 5, 15 — assert Accept present |
| Extra button appeared | 3.3 negative assertions — assert buttons absent |
| Duplicate Accept/Complete buttons | 3.4 — count per button text |
| Button half-visible / clipped | 3.5 — bounding box validation |
| Button overlap on mobile | 3.5 — overlap detection between siblings |
| Field visible when it shouldn't be | 3.6 — TFV_KIND_MAP per-kind verification |
| Field hidden when it should be visible | 3.6 — same |
| Field editable when it should be locked | 3.7 — TFE_EDIT_MAP per-kind verification |
| Task form throws console error | 3.8 — console error check |
| API call fails on form load | 3.8 — network failure check |
| Client script didn't load | 3.8 — script load verification |
| Mobile layout broken | 3.9 — CSS injection, padding, scroll |
| Functional difference between mobile and desktop | 3.3 — same matrix verified at both viewports |

---

## Phase 4 — Layer 3: Full E2E Happy Path

Manually triggered. Runs with a **visible browser** so the operator can watch. Data-changing — creates real Tasks, Dispatch Cases, Stock Entries, Sales Invoices, and Payment Entries on `test.erpnext.am`.

### 4.0 Design principles

**Headed + slow motion:** `headless: false`, `slowMo: 250` — the operator sees every click. Optionally configurable via env var `E2E_SLOW_MO`.

**Video + screenshots:** Playwright records full video of each browser context. Additionally, a named screenshot is taken after every major step (accept, complete, status change, payment). All artifacts go to `ERPNext-Automation-Reports/`.

**Stop on failure:** `test.fail.stop = true`. If any step fails, the remaining steps are skipped. The report shows which step broke and includes the screenshot/video up to that point.

**Hybrid browser + API:** The browser handles all user-facing actions: navigation, accepting tasks, clicking action buttons, filling visible form fields, completing tasks. The API handles behind-the-scenes operations that are mechanically complex in the Frappe UI but not the focus of this test: adding products to a DC child table, uploading photos, marking items packed, submitting a Sales Invoice. This makes the test resilient to cosmetic changes in child-table rendering while still proving the full workflow works through the real UI.

**Role switching:** Each workflow step uses a different role user. Playwright creates a new browser context for each role from the saved session state (Phase 1 `auth.ts`). The previous context is closed before the next opens. The operator sees the browser switch users between steps.

**Run command:**

```
npx playwright test --project=e2e --headed
```

The `e2e` project is configured separately from smoke tests: headed, slow motion, full screenshots, video on.

---

### 4.1 No-return dispatch flow

One sequential test with 18 named steps. Total estimated runtime: 3–5 minutes.

#### Roles involved

| Step | Role | User (from `.env.local`) | What they do |
|---|---|---|---|
| 1–4 | Ops - Order | `USER_ORDER` / `PASS_ORDER` | Accept Order Entry, complete |
| 5–7 | Ops - Inventory | `USER_INVENTORY` / `PASS_INVENTORY` | Accept Pack, complete |
| 8–10 | Delivery Driver | `USER_DELIVERY` / `PASS_DELIVERY` | Accept Delivery, Picked Up, Delivered |
| 11–13 | Ops - Accounting | `USER_ACCOUNTING` / `PASS_ACCOUNTING` | Accept Invoice Prep, complete |
| 14–15 | Ops - Finance | `USER_FINANCE` / `PASS_FINANCE` | Accept Debt Collection, record payment |
| 16–17 | Ops - Directors | `USER_DIRECTORS` / `PASS_DIRECTORS` | Accept Debt Closure, approve |
| 18 | — (API) | Admin API key | Final verification |

---

#### Step 1 — Create Order Entry task (API)

**Actor:** Admin API (no browser)

API: Create Task via `POST /api/resource/Task`:
```
subject: "E2E Happy Path — No Return — {timestamp}"
task_kind: "Order entry"
task_access_policy: "Order entry"
customer: <test_customer>
```

Assert: Task created with `status = "Open"`.

Track task name in manifest. Log: `"Created Order Entry task: TASK-XXXXX"`.

---

#### Step 2 — Order user accepts task (Browser)

**Actor:** Ops - Order user

1. Open browser context as Order role
2. Navigate to `Form/Task/{task_name}`
3. Wait for `cur_frm` ready
4. **Screenshot:** "step-02-order-task-open.png"
5. Verify: Accept button is visible, no Complete button
6. Click **"Accept / Start Task"** button
7. Wait for page reload (freeze overlay disappears, `cur_frm.doc.status === "Working"`)
8. **Screenshot:** "step-02-order-task-accepted.png"
9. Verify in browser:
   - Status shows Working
   - View DC button appeared (Order entry auto-creates DC)
   - Product section is visible

Record DC name: evaluate `cur_frm.doc.dispatch_case` in browser.

---

#### Step 3 — Add products (API assist)

**Actor:** Admin API (runs while Order user's browser is still open — API call in background)

Why API: Adding rows to Frappe child tables via browser automation is fragile (dynamic row rendering, scroll, input focus). The E2E test proves the workflow, not the product-addition UX.

API calls (as the same user who accepted, or admin with `ignore_permissions`):
```
task_add_dispatch_product: { task_name, item_code: "E2E-TEST-ITEM-001", qty: 2, unit_price: 1000 }
task_add_dispatch_product: { task_name, item_code: "E2E-TEST-ITEM-002", qty: 1, unit_price: 500 }
```

After adding, refresh the browser: `frm.reload_doc()` via evaluate, or navigate away and back.

Verify in browser: Product section shows 2 items.

---

#### Step 4 — Order user completes task (Browser)

**Actor:** Ops - Order user (same browser context as step 2)

1. Click **"Complete"** button
2. If discount confirmation dialog appears (it shouldn't — test items have `discount_pct = 0`): click confirm
3. Wait for save to complete (freeze overlay disappears)
4. Wait for page reload
5. **Screenshot:** "step-04-order-completed.png"
6. Verify in browser:
   - Task status shows Completed
   - No action buttons (Accept, Complete) visible
   - View DC still visible

7. Click **"View DC"** to verify DC state
8. **Screenshot:** "step-04-dispatch-case.png"
9. Verify on DC form:
   - `docstatus = 1` (submitted)
   - `case_items` shows 2 rows
   - Customer matches

Close Order user browser context.

---

#### Step 5 — Inventory user accepts Pack task (Browser)

**Actor:** Ops - Inventory user

1. Open browser context as Inventory role
2. Find the Pack task — navigate to `List/Task` filtered by `dispatch_case = {dc_name}` and `task_kind = "Pack / prepare items"`. Or query via API first to get the task name, then navigate directly.
3. Navigate to `Form/Task/{pack_task_name}`
4. Wait for `cur_frm` ready
5. **Screenshot:** "step-05-pack-task-open.png"
6. Verify: Accept button visible
7. Click **"Accept / Start Task"**
8. Wait for reload
9. **Screenshot:** "step-05-pack-task-accepted.png"
10. Verify: Complete button visible, View DC visible

---

#### Step 6 — Upload photo and mark items packed (API assist)

**Actor:** Admin API

Why API: Photo upload involves file picker or drag-and-drop — not reliable to automate. Item packing involves barcode scanning UX. Both are tested individually in Layer 2.

API calls:
1. Upload test photo: `POST /api/method/upload_file` (multipart) → attached to Pack task
2. Mark all items packed: `task_mark_items_packed_batch` with `{ case_name, packed_indices: [0, 1] }`

After each, the inventory user's browser can verify by refreshing:
- Photo gallery shows 1 photo
- Product section shows items as packed (green checkmarks or scanned qty matches)

---

#### Step 7 — Inventory user completes Pack task (Browser)

**Actor:** Ops - Inventory user (same context as step 5)

1. Refresh page to pick up photo + packing state
2. Click **"Complete"**
3. Wait for save and reload
4. **Screenshot:** "step-07-pack-completed.png"
5. Verify in browser:
   - Task status = Completed
   - No action buttons

6. Navigate to DC via View DC
7. **Screenshot:** "step-07-dc-packed.png"
8. Verify on DC: `status = "Packed"`

Close Inventory user browser context.

---

#### Step 8 — Delivery user accepts Delivery task (Browser)

**Actor:** Delivery Driver user

1. Open browser context as Delivery role
2. Find Delivery task (query API for task name, or navigate from DC)
3. Navigate to `Form/Task/{delivery_task_name}`
4. Wait for `cur_frm` ready
5. **Screenshot:** "step-08-delivery-open.png"
6. Verify: Accept button visible
7. Click **"Accept / Start Task"**
8. Wait for reload
9. **Screenshot:** "step-08-delivery-accepted.png"
10. Verify: **"Picked Up"** button visible (not "Complete" — Delivery uses multi-state buttons)

---

#### Step 9 — Delivery user clicks "Picked Up" (Browser)

**Actor:** Delivery Driver (same context)

1. Click **"Picked Up"** button
2. Wait for save and reload
3. **Screenshot:** "step-09-delivery-picked-up.png"
4. Verify in browser:
   - `delivery_status` changed (verify via `cur_frm.doc.delivery_status === "Picked Up"`)
   - **"Delivered"** button now visible (replaces "Picked Up")
   - No "Picked Up" button anymore

---

#### Step 10 — Delivery user clicks "Delivered" (Browser)

**Actor:** Delivery Driver (same context)

1. Click **"Delivered"** button
2. Wait for save and reload
3. **Screenshot:** "step-10-delivery-delivered.png"
4. Verify in browser:
   - Task status = Completed (auto-completed by before-save gate)
   - No action buttons
   - `delivery_status = "Delivered"`

5. Navigate to DC via View DC
6. **Screenshot:** "step-10-dc-invoice-pending.png"
7. Verify on DC:
   - `status = "Invoice Pending"`
   - `sales_invoice` is set (draft SI was created)

Close Delivery user browser context.

---

#### Step 11 — Accounting user accepts Invoice Preparation task (Browser)

**Actor:** Ops - Accounting user

1. Open browser context as Accounting role
2. Find Invoice Preparation task (query API or navigate from DC's `invoice_task` field)
3. Navigate to `Form/Task/{invoice_task_name}`
4. Wait for `cur_frm` ready
5. **Screenshot:** "step-11-invoice-prep-open.png"
6. Click **"Accept / Start Task"**
7. Wait for reload
8. **Screenshot:** "step-11-invoice-prep-accepted.png"
9. Verify: Complete button visible

---

#### Step 12 — Submit Sales Invoice (API assist)

**Actor:** Admin API

The invoice was created as a draft by the after-save dispatch flow. The Accounting user would normally review and submit it from the SI form. For E2E reliability, we submit via API.

API:
1. Get DC's `sales_invoice` field
2. `POST /api/method/frappe.client.submit` with the SI doc

Assert: SI `docstatus = 1`.

---

#### Step 13 — Accounting user completes Invoice Preparation (Browser)

**Actor:** Ops - Accounting user (same context as step 11)

1. Refresh page
2. Click **"Complete"**
3. Wait for save and reload
4. **Screenshot:** "step-13-invoice-prep-completed.png"
5. Verify in browser: Task status = Completed

6. Navigate to DC
7. **Screenshot:** "step-13-dc-payment-pending.png"
8. Verify on DC:
   - `status = "Payment Pending"`
   - `total_invoice_amount` is set (2500)
   - `outstanding_amount` > 0

Close Accounting user browser context.

---

#### Step 14 — Finance user accepts Debt Collection task (Browser)

**Actor:** Ops - Finance user

1. Open browser context as Finance role
2. Find Debt Collection task (query API: `task_kind = "Debt Collection"`, `customer = <test_customer>`, `status != "Completed"`)
3. Navigate to `Form/Task/{debt_task_name}`
4. Wait for `cur_frm` ready
5. **Screenshot:** "step-14-debt-collection-open.png"
6. Verify: `total_outstanding` field shows amount, `open_invoices` table has rows
7. Click **"Accept / Start Task"**
8. Wait for reload
9. **Screenshot:** "step-14-debt-collection-accepted.png"
10. Verify: Complete button visible, payment fields editable

---

#### Step 15 — Finance user records payment (Browser)

**Actor:** Ops - Finance user (same context)

This step uses the browser to fill form fields — proving the payment UX works end-to-end.

1. Set `new_payment_amount` field to the outstanding amount (e.g., 2500)
2. Set `payment_method_dc` to "Cash"
3. Set `payment_reference_dc` to "E2E-HAPPY-PATH-REF"
4. **Screenshot:** "step-15-debt-payment-filled.png"
5. Save the form (Ctrl+S or click Save)
6. Wait for save to complete (the before-save script creates a Payment Entry and auto-completes if outstanding = 0)
7. Wait for reload
8. **Screenshot:** "step-15-debt-collection-completed.png"
9. Verify in browser:
   - Task status = Completed (auto-completed because `total_outstanding <= 0`)
   - `total_outstanding = 0`
   - `payment_history` table has 1 row

Close Finance user browser context.

---

#### Step 16 — Directors user accepts Debt Closure Approval (Browser)

**Actor:** Ops - Directors user

1. Open browser context as Directors role
2. Find Debt Closure Approval task (query API: `task_kind = "Debt Closure Approval"`, `customer = <test_customer>`, `status != "Completed"`)
3. Navigate to `Form/Task/{closure_task_name}`
4. Wait for `cur_frm` ready
5. **Screenshot:** "step-16-debt-closure-open.png"
6. Verify: `open_invoices` and `payment_history` tables are visible and populated
7. Click **"Accept / Start Task"**
8. Wait for reload
9. **Screenshot:** "step-16-debt-closure-accepted.png"

---

#### Step 17 — Directors user approves and completes (Browser)

**Actor:** Ops - Directors user (same context)

1. Set `approval_outcome` to "Approved"
2. Click **"Complete"**
3. Wait for save and reload
4. **Screenshot:** "step-17-debt-closure-completed.png"
5. Verify in browser:
   - Task status = Completed
   - `custom_case_profit` is set (profit calculated by after-save)

Close Directors user browser context.

---

#### Step 18 — Final verification (API)

**Actor:** Admin API (no browser)

Comprehensive API-based verification of all records created during the run:

| Record | Assertions |
|---|---|
| Order Entry task | `status = "Completed"` |
| Dispatch Case | `docstatus = 1`, check all status transitions landed correctly |
| Pack task | `status = "Completed"` |
| Delivery task | `status = "Completed"`, `delivery_status = "Delivered"` |
| DC `dispatch_stock_entry` | Exists, `docstatus = 1`, items match |
| DC `delivery_stock_entry` | Exists, `docstatus = 1` |
| DC `consumption_stock_entry` | Exists, `docstatus = 1` |
| Sales Invoice | `docstatus = 1`, `grand_total = 2500` |
| Invoice Prep task | `status = "Completed"` |
| Debt Collection task | `status = "Completed"`, `total_outstanding = 0` |
| Payment Entry | `docstatus = 1`, `paid_amount = 2500` |
| Debt Closure task | `status = "Completed"`, `custom_case_profit` is set |
| DC `profit` field | Is set (calculated by debt closure after-save) |

Write all assertions to the test report. Write the complete run manifest listing every record name.

**Screenshot:** Final summary page (optional — navigate to DC and take a closing screenshot showing the completed state).

---

### 4.2 Return-expected dispatch flow

Same structure as 4.1 but with `return_expected = 1`. Added after 4.1 is stable and passing.

#### Additional roles

| Step | Role | What they do |
|---|---|---|
| 11 | Ops - Office (or Order user) | Accept Return Call, set driver, complete |
| 12–14 | Delivery Driver | Accept Pickup Returns, Picked Up, Returned to WH |
| 15–16 | Ops - Returns | Accept Returns Inspection, fill quantities, complete |
| 17 | Ops - Returns | Accept Returns Restocking, complete |
| 18+ | Same as 4.1 steps 11–17 | Invoice Prep → Payment → Closure |

#### Differences from 4.1

**Step 1:** Set `order_return_expected = 1` and `order_client_location_warehouse` on the Order Entry task.

**Steps 2–10:** Identical to 4.1 (through Delivery Delivered).

**Step 10 outcome:** DC status becomes `"Awaiting Return Pickup"` instead of `"Invoice Pending"`. No Sales Invoice created. A **Return Call** task is created instead of Invoice Prep.

**Step 11 — Return Call (Browser):**
1. Accept Return Call task as Office user
2. Optionally set `return_pickup_driver` and `scheduled_return_date`
3. Complete the task
4. Verify: DC status = "Return Pickup Scheduled", Pickup Returns task created

**Step 12 — Pickup Returns accept (Browser):**
1. Accept as Delivery Driver
2. Click "Picked Up"
3. Verify: DC status = "Return In Transit"

**Step 13 — Upload drop-off photo (API assist):**
Upload photo to Pickup Returns task.

**Step 14 — Returned to Warehouse (Browser):**
1. Click "Returned to WH"
2. Verify: Task auto-completes, DC status = "Returns Received", Returns Inspection task created

**Step 15 — Returns Inspection (Browser + API):**
1. Accept as Returns user
2. API: Use `task_mark_items_packed_batch` with `task_kind = "Returns processing / verification"` to set `returned_qty` on items (item 0: returned, item 1: used)
3. Refresh browser, verify quantities shown
4. Complete in browser
5. Verify: DC status = "Invoice Pending", Sales Invoice created (for used qty only), Invoice Prep + Returns Restocking tasks created

**Step 16 — Returns Restocking (Browser):**
1. Accept as Returns user, complete
2. Verify: `restock_stock_entry` created (Returns WH → Main - Inmed)

**Steps 17–22:** Same as 4.1 steps 11–17 (Invoice Prep → Debt Collection → Debt Closure).

#### Additional final verifications

| Record | Assertions |
|---|---|
| Return Call task | `status = "Completed"` |
| Pickup Returns task | `status = "Completed"`, `pickup_status = "Returned to Warehouse"` |
| Returns Inspection task | `status = "Completed"` |
| Returns Restocking task | `status = "Completed"` |
| DC `return_pickup_stock_entry` | Exists, `docstatus = 1` |
| DC `return_receive_stock_entry` | Exists, `docstatus = 1` |
| DC `restock_stock_entry` | Exists, `docstatus = 1` |
| Sales Invoice | Items reflect used qty, not dispatched qty |

---

### 4.3 Discount approval sub-flow (optional add-on)

Can be combined with either 4.1 or 4.2 by using items with `discount_pct > 0` during Step 3.

#### Modified flow

**Step 4** — Order user completes → gets discount confirmation dialog → confirms.

**Step 4b** — DC status becomes "Awaiting Approval" instead of proceeding to Pack. A **Discount Approval** task is created.

**Step 4c — Directors user approves (Browser):**
1. Open as Directors role
2. Accept Discount Approval task
3. Set `approval_outcome = "Approved"`
4. Complete
5. Verify: DC submitted, status = "Confirmed", Pack task now created

**Steps 5+** — Continue from Pack onward (same as 4.1 step 5).

---

### 4.4 Viewport strategy

The E2E test runs at **one viewport at a time**. The default is desktop (`1280×720`).

To run at mobile viewport: set `E2E_VIEWPORT=mobile` in `.env.local` or pass `--project=e2e-mobile`.

The Playwright config defines two E2E projects:

| Project | Viewport | Headed | Slow motion |
|---|---|---|---|
| `e2e` | 1280×720 | yes | 250ms |
| `e2e-mobile` | 375×812 | yes | 250ms |

Both use the same test files. Assertion helpers automatically adapt selectors based on viewport (desktop buttons in `.custom-actions`, mobile buttons in `#task-bottom-actions`).

Running both viewports sequentially:
```
npx playwright test --project=e2e --headed
npx playwright test --project=e2e-mobile --headed
```

---

### 4.5 Error recovery and partial runs

**On failure:** The test stops immediately. It does NOT try to clean up created records (the test environment is disposable). The report and manifest include all records created up to the failure point, so the operator can inspect them manually.

**Resuming after a fix:** Re-run the entire test. Do not attempt to resume from a mid-point — the state dependencies make partial runs unreliable.

**Known fragile points** (where extra wait time or retry logic may be needed):
- After accepting a task, the page reload can take 2–5s on the test server
- After completing a task that triggers downstream creation (e.g., Order Entry → Pack), the new task may take 1–2s to appear due to server-side processing
- Sales Invoice submission may trigger background jobs (GL entries)

For these, use generous `waitForResponse` or polling waits rather than fixed timeouts.

---

### 4.6 Test file organization

```
tests/e2e/
  happy-path-no-return.spec.ts      — 4.1
  happy-path-return.spec.ts         — 4.2
  happy-path-discount.spec.ts       — 4.3 (optional)
```

Each file is a single `test()` with `test.step()` for each numbered step. The `test.step()` structure ensures the report shows exactly which step failed.

---

### 4.7 Artifacts produced

For a complete no-return run (4.1):

```
ERPNext-Automation-Reports/
  2026-09-15_14-30-00_e2e-no-return/
    report.json
    report.html
    run-manifest.json
    screenshots/
      step-02-order-task-open.png
      step-02-order-task-accepted.png
      step-04-order-completed.png
      step-04-dispatch-case.png
      step-05-pack-task-open.png
      step-05-pack-task-accepted.png
      step-07-pack-completed.png
      step-07-dc-packed.png
      step-08-delivery-open.png
      step-08-delivery-accepted.png
      step-09-delivery-picked-up.png
      step-10-delivery-delivered.png
      step-10-dc-invoice-pending.png
      step-11-invoice-prep-open.png
      step-11-invoice-prep-accepted.png
      step-13-invoice-prep-completed.png
      step-13-dc-payment-pending.png
      step-14-debt-collection-open.png
      step-14-debt-collection-accepted.png
      step-15-debt-payment-filled.png
      step-15-debt-collection-completed.png
      step-16-debt-closure-open.png
      step-16-debt-closure-accepted.png
      step-17-debt-closure-completed.png
    video/
      context-order.webm
      context-inventory.webm
      context-delivery.webm
      context-accounting.webm
      context-finance.webm
      context-directors.webm
```

The report.html includes inline thumbnails of every screenshot in chronological order, making it easy to review the entire flow visually without re-running the test

---

## Phase 5 — Reporting, Commands, Documentation, and Maintenance

### 5.1 Custom HTML report

Playwright ships built-in HTML and JSON reporters. Phase 5 adds a **custom report layer** on top that combines Playwright results with Frappe-specific data (run manifest, DC links, console/network captures) into a single self-contained HTML file.

#### Report structure

```
ERPNext-Automation-Reports/
  2026-09-15_14-30-00_api-smoke/
    index.html              ← custom combined report
    playwright-report/      ← Playwright's built-in HTML report
    run-manifest.json
    console.jsonl
    network.jsonl
    screenshots/
    video/
```

#### index.html sections

**1. Header banner**

| Field | Value |
|---|---|
| Run name | e.g., `api-smoke`, `e2e-no-return`, `smoke-desktop` |
| Environment | `https://test.erpnext.am` (always shown — the operator should never wonder which environment was tested) |
| Timestamp | Start and end time, total duration |
| Result | Large green PASS or red FAIL banner |
| Summary | `23 passed, 0 failed, 0 skipped` |

**2. Step timeline**

Chronological list of every `test.step()` with:
- Step name
- Duration
- Pass/fail icon
- Expandable: screenshot thumbnail (click to enlarge), expected vs actual for assertions that failed, error message and stack trace for failures

For Layer 3 (E2E), the timeline shows the role user for each step: `[Ops - Inventory] Step 7 — Complete Pack task`.

**3. Console error summary**

Table of all `console.error` and `pageerror` events collected during the run. Columns: timestamp, URL, message (truncated to 200 chars, expandable). Empty section with green "No console errors" if clean.

**4. Network failure summary**

Table of failed `/api/` requests. Columns: timestamp, method, URL, status code / failure reason. Empty section with green "No network failures" if clean.

**5. Created records**

Table from `run-manifest.json`. Columns: doctype, name (as clickable link to `https://test.erpnext.am/app/{doctype}/{name}`), purpose. The operator can click any record to inspect it directly on the test site.

**6. Screenshots gallery**

Grid of all screenshots in chronological order. Each thumbnail is captioned with the step name. Click to view full-size. For E2E runs this tells the visual story of the entire workflow.

**7. Link to Playwright report**

"Open detailed Playwright report" link to `playwright-report/index.html` — for trace viewing, retry details, and Playwright's built-in filtering.

#### Implementation

The custom report is generated by a Playwright `reporter` plugin registered in `playwright.config.ts`. It implements the `onEnd` hook, reads the Playwright JSON output, merges it with `run-manifest.json` and the JSONL capture files, and writes `index.html` as a self-contained file (CSS inline, screenshots base64-embedded for portability — or linked for large runs).

**Security:** The report must NOT include:
- API keys or secrets
- User passwords
- Authorization headers from network captures
- Cookie values

The network capture filter (Phase 1, `src/capture.ts`) strips these before writing to JSONL, so the report inherits clean data.

---

### 5.2 Run commands and tags

#### Test tags

Tests are tagged using Playwright's `@tag` annotation in test titles:

| Tag | Meaning | Example |
|---|---|---|
| `@api` | Layer 1 API test | `test("@api dispatch no-return lifecycle", ...)` |
| `@smoke` | Layer 2 browser smoke test | `test("@smoke button state matrix", ...)` |
| `@e2e` | Layer 3 full E2E happy path | `test("@e2e no-return dispatch flow", ...)` |
| `@buttons` | Button-specific smoke test | `test("@smoke @buttons duplicate detection", ...)` |
| `@fields` | Field visibility/editability test | `test("@smoke @fields visibility Order entry", ...)` |
| `@health` | Console/network health check | `test("@smoke @health console errors", ...)` |
| `@gates` | Completion gate negative tests | `test("@api @gates pack without photo", ...)` |
| `@invariants` | System invariant tests | `test("@api @invariants save without acceptance", ...)` |

#### Run commands

**Run everything (API + smoke at both viewports):**
```
npx playwright test
```

**Layer 1 only (fast, no browser):**
```
npx playwright test --grep @api
```

**Layer 2 only (desktop):**
```
npx playwright test --grep @smoke --project=desktop
```

**Layer 2 only (mobile):**
```
npx playwright test --grep @smoke --project=mobile
```

**Layer 2 only (both viewports):**
```
npx playwright test --grep @smoke
```

**Layer 3 E2E (manual, headed, desktop):**
```
npx playwright test --grep @e2e --project=e2e --headed
```

**Layer 3 E2E (manual, headed, mobile):**
```
npx playwright test --grep @e2e --project=e2e-mobile --headed
```

**Specific sub-category:**
```
npx playwright test --grep "@smoke @buttons"
npx playwright test --grep "@api @gates"
npx playwright test --grep "@smoke @fields"
```

**Single test file:**
```
npx playwright test tests/api/dispatch-no-return.spec.ts
npx playwright test tests/smoke/task-buttons.spec.ts --project=mobile
```

**Open last Playwright HTML report:**
```
npx playwright show-report
```

#### Quick-check script

A convenience script `tests/e2e/run-quick-check.ps1` (and `.sh` for Linux) that runs the minimum verification: Layer 1 no-return lifecycle + Layer 2 button matrix at desktop only. Estimated time: 30–60 seconds. Intended for running after every deployment.

```powershell
# run-quick-check.ps1
npx playwright test --grep "@api dispatch no-return" --reporter=list
if ($LASTEXITCODE -ne 0) { exit 1 }
npx playwright test --grep "@smoke @buttons" --project=desktop --reporter=list
exit $LASTEXITCODE
```

#### Full regression script

A script `tests/e2e/run-full-regression.ps1` that runs all three layers sequentially:

```powershell
# run-full-regression.ps1
Write-Host "=== Layer 1: API Tests ===" -ForegroundColor Cyan
npx playwright test --grep @api
if ($LASTEXITCODE -ne 0) { Write-Host "Layer 1 FAILED" -ForegroundColor Red; exit 1 }

Write-Host "=== Layer 2: Smoke Tests (Desktop) ===" -ForegroundColor Cyan
npx playwright test --grep @smoke --project=desktop
if ($LASTEXITCODE -ne 0) { Write-Host "Layer 2 Desktop FAILED" -ForegroundColor Red; exit 1 }

Write-Host "=== Layer 2: Smoke Tests (Mobile) ===" -ForegroundColor Cyan
npx playwright test --grep @smoke --project=mobile
if ($LASTEXITCODE -ne 0) { Write-Host "Layer 2 Mobile FAILED" -ForegroundColor Red; exit 1 }

Write-Host "=== All layers PASSED ===" -ForegroundColor Green
```

Layer 3 is not included in the full regression script — it is always triggered manually.

---

### 5.3 Documentation

#### README.md in `tests/e2e/`

Sections:

**1. Overview**
- What this test suite covers (three layers)
- Link to decisions document and this implementation plan
- Architecture diagram (text-based): API client → test.erpnext.am, Browser → test.erpnext.am

**2. Prerequisites**
- Node.js version requirement
- `npx playwright install chromium` (one-time browser install)
- Access to `https://test.erpnext.am`
- Role users configured (list of required roles from Phase 1.3.2)
- Test items with stock (list of item codes from Phase 1.3.3)

**3. Setup**
- `cd tests/e2e && npm install`
- Copy `.env.example` to `.env.local`
- Fill in credentials (with notes on where to find them)
- Verify setup: `npx playwright test tests/setup/global-setup.ts` (should pass with "Environment validated, N sessions created")

**4. Running tests**
- Quick reference table of all run commands from 5.2
- Explanation of projects (api, desktop, mobile, e2e, e2e-mobile)
- How to run a single test
- How to see verbose output (`--reporter=list`)

**5. Reading reports**
- Where reports are written (`ERPNext-Automation-Reports/`)
- How to open the custom HTML report
- How to open the Playwright HTML report
- What each section of the report means
- How to inspect created records via manifest links

**6. Adding new tests**

Step-by-step guide:

*Adding a new API test:*
1. Create `tests/api/my-test.spec.ts`
2. Use `@api` tag in test title
3. Use `frappeApi` fixture from `src/frappe-api.ts`
4. Track created records with `manifest.track()`
5. Run: `npx playwright test tests/api/my-test.spec.ts`

*Adding a new smoke test:*
1. Create `tests/smoke/my-test.spec.ts`
2. Use `@smoke` tag
3. Add tasks to the data factory if a new state is needed
4. Use assertion helpers from `src/assertions.ts`
5. Test runs at both viewports automatically

*Adding a field to TFV_KIND_MAP / TFE_EDIT_MAP coverage:*
1. Add the field to the expected-state data structure in the relevant test file
2. Map it to the correct rule
3. Run the field tests to verify

*Adding a new task kind:*
1. Add a row to the button state matrix
2. Add a task to the data factory
3. Add the kind's expected fields to the visibility and editability tests
4. If the kind has a completion gate, add a gate test to Phase 2.5

**7. Troubleshooting**

| Problem | Solution |
|---|---|
| `REFUSED: production URL` | `.env.local` has `BASE_URL=https://erpnext.am` — change to `https://test.erpnext.am` |
| `REFUSED: unknown host` | `BASE_URL` is not `https://test.erpnext.am` |
| Login fails for a role | Check the user is enabled on test, password is correct, user has the required role |
| `Task is required` / `Choose Product first` | API call missing required parameter — check the test code |
| `You must accept the task before making changes` | The API call is running as a different user than the one who accepted the task |
| Pack completion fails `photo required` | The `upload_file` call didn't attach the photo correctly — check File records |
| Pack completion fails `not packed` | `task_mark_items_packed_batch` didn't run or didn't cover all indices |
| Test times out waiting for `cur_frm` | The test server may be slow — increase `waitForFrappeFormReady` timeout |
| Smoke test fails with "duplicate button" | A client script regression — the button is being added twice |
| Smoke test fails with "button clipped" | A CSS regression — the button's bounding box is outside the viewport |
| E2E test fails at role switch | The session for that role expired or wasn't created — re-run global setup |
| `HTTP 417 DataError` | Request body encoding issue — ensure UTF-8 (see Phase 1.4.2) |

**8. Environment safety**

Reminder that all tests target `https://test.erpnext.am` ONLY. The safety guard in `src/safety.ts` rejects production and unknown hosts. Never modify the safety guard to allow production.

---

### 5.4 Test data replenishment

Over time, repeated E2E runs consume test item stock (each run creates Stock Entries that move items out of `Main - Inmed`). When stock runs out, Pack tasks will fail to create dispatch Stock Entries.

**Monitoring:** After each run, the manifest tracks which items and quantities were consumed. A post-run check can query remaining stock:

```
GET /api/method/frappe.client.get_list
  doctype: "Bin"
  filters: { item_code: ["in", ["E2E-TEST-ITEM-001", ...]], warehouse: "Main - Inmed" }
  fields: ["item_code", "actual_qty"]
```

If any item's `actual_qty` drops below 20, log a warning in the report.

**Replenishment:** A utility function `replenishTestStock()` in `src/frappe-api.ts` creates a Material Receipt Stock Entry to restore each test item to 100 qty in `Main - Inmed`. This can be called manually or automatically when stock is low.

---

### 5.5 Maintenance guide

When the Inmed customization changes, the tests may need updates. This section maps change types to the tests that need attention.

#### When a new task kind is added

1. Add a `Task Access Policy` record for it (server-side)
2. Add the kind to `TFV_KIND_MAP` in `Task-Field-Visibility.js` (client-side)
3. Add the kind to `TFE_EDIT_MAP` in `Task-Field-Editability.js` if it has kind-specific editability
4. **Tests:**
   - Add a row to the button state matrix (3.3) with expected buttons
   - Add a task to the smoke data factory (3.1) for the new kind
   - Add the kind's expected fields to the visibility test (3.6)
   - Add the kind's expected fields to the editability test (3.7)
   - If the kind has a completion gate, add a gate test (2.5)
   - If the kind is part of the dispatch flow, update the lifecycle tests (2.1/2.2)

#### When a field is added to a task kind

1. Add to `TFV_KIND_MAP` and/or `TFE_EDIT_MAP`
2. **Tests:**
   - Add the field to the visibility expected-state data (3.6)
   - Add the field to the editability expected-state data (3.7)
   - If the field has a completion gate (e.g., required before completing), add a gate test (2.5)

#### When a button is added or removed

1. Update `Task-Action Buttons.js`
2. **Tests:**
   - Update the button state matrix (3.3) — add/remove the button from affected rows
   - Update the duplicate detection list (3.4)
   - If the button is a new primary action (like Picked Up / Delivered), add it to the assertion helpers

#### When a completion gate changes

1. Update `Task-before-save-dispatch-gates.py`
2. **Tests:**
   - Update the gate test (2.5) — change the expected error message or add/remove a gate test
   - If the gate affects the lifecycle flow (e.g., new prerequisite before completion), update the lifecycle test steps (2.1/2.2)

#### When the dispatch flow adds a new task in the chain

1. Update `Task-after-save-dispatch-flow.py`
2. **Tests:**
   - Update the lifecycle test (2.1 or 2.2) — add a step for the new task
   - Update the state factory (2.6) if the new task is a prerequisite for existing states
   - Add the new task kind to the E2E happy path (4.1 or 4.2)

#### When a Stock Entry route changes (warehouse names)

1. Update the warehouse constants in `Task-after-save-dispatch-flow.py`
2. **Tests:**
   - Update the warehouse assertions in the lifecycle tests (2.1/2.2, steps that verify SEs)
   - No change needed for smoke/E2E tests (they don't inspect SE warehouses)

---

### 5.6 Version pinning and dependency management

**Playwright version:** Pin to a specific minor version in `package.json` (e.g., `"@playwright/test": "~1.48.0"`). Playwright releases can change behavior — upgrade deliberately, not automatically.

**Chromium version:** Managed by Playwright's bundled browser. Pinned transitively through the Playwright version.

**Node.js version:** Document the minimum required version (e.g., 18 LTS). Consider adding an `.nvmrc` or `engines` field in `package.json`.

**No other runtime dependencies.** The project uses only `@playwright/test` and `dotenv`. No test frameworks, assertion libraries, or utility packages beyond what Playwright provides. This minimizes supply-chain risk and maintenance burden.

---

## Implementation Order

| Order | What | Depends on | Estimated effort |
|---|---|---|---|
| 1 | Phase 1.1–1.2: scaffolding + safety guard | Dependency approval | Small |
| 2 | Phase 1.3: test environment setup | Access to test.erpnext.am | Small (manual) |
| 3 | Phase 1.4: core utilities | Phase 1.1 | Medium |
| 4 | Phase 2.1: no-return lifecycle API test | Phase 1.3 + 1.4 | Medium |
| 5 | Phase 2.2–2.5: remaining API tests | Phase 2.1 (reuses patterns) | Medium |
| 6 | Phase 2.6: state factory | Phase 2.1 | Small |
| 7 | Phase 3.1–3.2: assertion helpers + data factory | Phase 1.4 + Phase 2.6 | Medium |
| 8 | Phase 3.3–3.5: button tests | Phase 3.1 + 3.2 | Medium |
| 9 | Phase 3.6–3.7: field tests | Phase 3.1 + 3.2 | Medium |
| 10 | Phase 3.8–3.9: health + mobile tests | Phase 3.1 | Small |
| 11 | Phase 4.1: no-return E2E happy path | Phase 2.1 + Phase 3 patterns | Large |
| 12 | Phase 4.2: return-expected E2E | Phase 4.1 stable | Medium |
| 13 | Phase 5.1: custom HTML report | Phases 2–4 producing data | Medium |
| 14 | Phase 5.2–5.3: run commands + README | All above | Small |
| 15 | Phase 5.4–5.6: replenishment, maintenance guide, pinning | All above | Small |
