# ERPNext Browser Automation Testing Plan

## 1) Purpose

This document defines the proposed browser-based regression testing system for ERPNext.

Goal: after a serious change is deployed to the **test** environment, run automated browser checks that behave like real users and report whether important workflows still work.

The automation must be able to answer questions such as:

- Is this page reachable?
- Is this screen searchable from ERPNext Desk?
- Is this button visible?
- Is this button enabled or disabled?
- What text/value is inside this field?
- Did clicking this button work?
- Did a dialog/error appear?
- Did the browser console show errors?
- Did any network request fail?
- Did a workflow end in the expected state?
- Did the right task/user/role see the right controls?
- Did a field stay read-only when it should be locked?
- Did generated Stock Entries, Sales Invoices, Payment Entries, and Tasks appear as expected?

This is a local documentation/specification file only. Implementation requires separate explicit approval.

---

## 2) Current decisions

| Topic | Decision |
|---|---|
| First architecture | Discuss with colleague. Spec should support Playwright-first, Chrome-extension-first, or hybrid, but recommendation remains Playwright-first. |
| Browser visibility | **Visible browser** for the first version. User should be able to watch actions happening. |
| Test data strategy | Still needs discussion. Recommended: existing master data + fresh E2E transaction records. |
| Login strategy | Still needs discussion. Recommended: support both saved sessions and local credentials outside git. |
| First exact scenario | Not chosen yet. Exact test scenarios/test kinds will be written later and should not block core automation design. |
| Test user choice | Automation should discover/select an enabled non-example user with the exact required role. Extra roles are acceptable, but Administrator/System Manager should not be used for role/lock tests. |
| Customer choice | Automation may automatically use any suitable customer on the test environment. |
| Item choice | Use an existing item with stock in `Main - Inmed` if available; if all items have zero stock, stock-changing scenarios need a setup/precondition decision. |
| Stock/accounting changes | Allowed on `https://test.erpnext.am` only: Dispatch Cases, Stock Entries, Sales Invoices, Payment Entries, Tasks. |
| Cleanup strategy | Still needs discussion with colleague; cleanup safety also needs discussion. |
| Desktop/mobile | Configurable with confirmation: desktop only, mobile only, or both. |
| UI strictness | Strict/full checks: visible/enabled/disabled/text/value/layout/size where important. |
| Report output | Full report: JSON + HTML + screenshots + console logs + network failures + trace/video where useful. |
| First suite size | Leave for later. Build core logic first, exact scenario suite later. |
| Purchase flow | Do **not** include purchase/supplier flow in first implementation. Add later. |
| Discount approval | Include both approved and rejected paths when discount tests are added. |
| Photo gates | Include both Pack photo gate and Return drop-off photo gate when photo tests are added. |
| Failure behavior | Continue remaining tests and report all failures, but stop on dangerous/data-changing failures that could corrupt the run. |
| Artifact folder | Use new eye-catching local folder: `ERPNext-Automation-Reports/`. |
| Dependencies | Discuss/ask again before installing Playwright/Node dependencies. |
| Initial implementation scope | Discuss with colleague: core-only, core + tiny smoke test, or core + Task inspection scenario. |
| Production rule | First version must completely refuse `https://erpnext.am`. |

---

## 3) Non-negotiable safety rules

### 3.1 Environment allowlist

The first version must run only against:

```text
https://test.erpnext.am
```

It must refuse to run against:

```text
https://erpnext.am
```

The refusal must happen before login, before navigation, and before any write/action.

### 3.2 Server operation rule

Before any future server operation, deployment, bench command, docker command, export, restore, cache clear, migration, or script touching test/prod environments, read:

```text
docs/infrastructure-test-vs-prod-environments.md
```

This browser automation plan itself does not authorize any server operation.

### 3.3 No credentials in committed files

Do not duplicate passwords, API secrets, tokens, or test credentials in this document or committed automation code.

Allowed later:

```text
.env.local
local browser session storage
Devin/secret manager
Windows credential store
```

Not allowed:

```text
committed credentials
credentials in screenshots/logs/reports
hardcoded production credentials
```

### 3.4 Test-only data-changing actions

The automation may create or submit records only on test:

```text
Dispatch Case
Task
Stock Entry triggered by scripts
Sales Invoice
Payment Entry
File/photo attachments
```

It must never perform these actions on production in the first version.

### 3.5 No System Manager for permission tests

For role/lock/permission tests, automation must use ordinary role users, not Administrator/System Manager, because Administrator/System Manager bypasses important checks.

System Manager may only be used for setup/diagnostic checks that explicitly require admin access.

---

## 4) Plain explanation of Playwright

Playwright is a browser automation tool.

It can open Chrome/Chromium, visit ERPNext pages, log in, click buttons, fill fields, check text, inspect whether controls are visible/enabled/disabled, capture console errors, capture screenshots, and create reports.

It is not a Chrome extension. It is more like a remote control for a browser.

For regression testing, Playwright is usually stronger than a Chrome extension because it is repeatable, scriptable, and designed for automated tests.

---

## 5) Architecture options

The final architecture choice still needs colleague discussion. The core design should keep the browser-control layer abstract enough that we can implement Playwright first and optionally add a Chrome extension later.

### 5.1 Option A — Playwright first

```text
Devin/User
  -> local command
  -> Playwright runner
  -> visible Chrome/Chromium
  -> https://test.erpnext.am
  -> reports in ERPNext-Automation-Reports/
```

Best for:

- repeatable regression tests
- screenshots
- console/network capture
- trace/video
- CI-like reporting
- strict checks

Recommended first implementation.

### 5.2 Option B — Chrome extension first

```text
Devin/User
  -> local bridge
  -> Chrome extension
  -> already-open Chrome tab
  -> https://test.erpnext.am
  -> reports in ERPNext-Automation-Reports/
```

Best for:

- live/manual browser assistance
- selecting elements from the real page
- recording manual clicks into draft tests
- controlling an already-open browser tab

Higher complexity for reliable regression tests.

### 5.3 Option C — Hybrid

```text
Playwright = regression runner
Chrome extension = live inspector/recorder/manual helper
MCP/local bridge = lets Devin talk to either one
```

Best long-term design.

### 5.4 Recommended practical path

```text
Phase 1: Playwright test runner core
Phase 2: Business workflow regression tests
Phase 3: Devin/MCP bridge
Phase 4: Optional Chrome extension
```

Even if the colleague decides differently, the core concepts stay the same:

```text
BrowserDriver
ScenarioRunner
ERPNext/Frappe UI helpers
Role/session manager
Data selector/fixture manager
Assertion engine
Artifact/report writer
Safety guard
```

---

## 6) Core modules to implement later

Implementation should be modular so exact test scenarios can be added later without rewriting the engine.

### 6.1 Safety guard

Responsibilities:

- enforce base URL allowlist
- reject production URL
- print target environment in every report
- prevent accidental data-changing actions if target is not test
- categorize dangerous actions

Required checks:

```text
baseUrl must equal https://test.erpnext.am
hostname must equal test.erpnext.am
https://erpnext.am must be rejected
unknown host must be rejected
```

### 6.2 Browser driver

Responsibilities:

- launch visible browser
- optionally emulate desktop or mobile viewport
- navigate to pages
- click/fill/select/upload
- read field values
- inspect visible/enabled/disabled/read-only state
- capture screenshots
- capture video/trace if enabled
- capture console and network events

The first version should run visible browser mode.

### 6.3 ERPNext/Frappe UI helper layer

ERPNext/Frappe UI is dynamic, so tests should not rely only on fragile raw CSS selectors.

Needed helper actions:

```text
openDesk()
searchAwesomebar(text)
openDoctypeList(doctype)
openNewDoc(doctype)
openExistingDoc(doctype, name)
waitForFrappeReady()
waitForFormLoaded(doctype)
waitForSaveComplete()
readDeskAlertMessages()
readDialogText()
closeDialog()
clickPrimaryButton(text)
clickCustomButton(text)
clickToolbarButton(text)
getFieldValue(fieldname)
setFieldValue(fieldname, value)
isFieldVisible(fieldname)
isFieldEditable(fieldname)
isFieldReadOnly(fieldname)
isButtonVisible(text)
isButtonEnabled(text)
readCurrentRoute()
readCurrentDoctype()
readCurrentDocname()
```

Preferred selector order:

```text
1. Frappe fieldname: [data-fieldname="..."]
2. Accessible role/text where stable
3. Frappe form metadata if available from window.cur_frm
4. Stable custom IDs from project scripts
5. CSS selector only as last resort
```

### 6.4 Role/session manager

Automation should choose users by role.

Required behavior:

- know which roles are needed for a scenario step
- select a non-admin test user with that role
- avoid Administrator/System Manager for role/lock tests
- support multiple saved sessions, one per user/role
- optionally support username/password login if credentials are configured outside git

The implementation should allow configuration like:

```json
{
  "roles": {
    "Ops - Order Accepting": { "user": "..." },
    "Ops - Order Creating": { "user": "..." },
    "Ops - Inventory": { "user": "..." },
    "Delivery Driver": { "user": "..." },
    "Ops - Returns": { "user": "..." },
    "Ops - Accounting": { "user": "..." },
    "Ops - Finance": { "user": "..." },
    "Ops - Directors": { "user": "..." }
  }
}
```

Decision: automation should discover/select an enabled non-example user with the required role. A configured preferred mapping may be added later, but it is not required for core logic.

### 6.5 Test data selector

Responsibilities:

- choose suitable existing Customer
- choose existing Item with stock in `Main - Inmed`
- optionally create fresh transaction records
- ensure records are identifiable as automation-created
- store created record IDs in run manifest

Recommended data pattern:

```text
Use existing master data:
- Customer
- Item with stock
- Warehouse
- Users/Roles

Create fresh transaction data:
- Task
- Dispatch Case
- Sales Invoice via workflow
- Payment Entry via workflow
- File attachments for photo gates
```

Open issue: final test-data strategy and cleanup policy.

### 6.6 Assertion engine

Assertions should be strict/full.

Supported checks:

```text
visible / hidden
text equals / contains
value equals
enabled / disabled
editable / read-only
button exists / missing
field exists / missing
CSS class exists
bounding box size/position for important controls
no duplicate action buttons
no unexpected dialog
expected error dialog appears
current route matches expected
console has no severe errors
network has no failed important requests
record status equals expected
linked generated record exists
```

Strict mode should fail when:

- a required button is missing
- a forbidden button is visible
- a button is enabled when it should be disabled
- a field is editable when it should be read-only
- a required field is hidden
- an important layout/control is duplicated
- console has serious uncaught errors
- critical network request fails

### 6.7 Report writer

Reports go to:

```text
ERPNext-Automation-Reports/
```

Each run should create:

```text
ERPNext-Automation-Reports/
  YYYY-MM-DD_HH-mm-ss_<run-name>/
    report.json
    report.html
    run-manifest.json
    console.jsonl
    network.jsonl
    screenshots/
    dom/
    traces/
    videos/
```

Reports must include:

- run name
- target URL
- environment
- browser mode
- viewport mode
- user/role per step
- created record IDs
- passed/failed/skipped steps
- expected vs actual results
- screenshots for failures and important milestones
- console logs
- network failures
- possible cause analysis section
- related docs/manual section if known
- whether the failure is likely permission, UI, server validation, network, data setup, or automation bug

---

## 7) Proposed local folder structure

Possible structure if/when implementation is approved:

```text
tests/e2e/
  package.json
  playwright.config.ts
  README.md
  .env.example
  src/
    safety.ts
    browser-driver.ts
    frappe-ui.ts
    auth.ts
    role-session-manager.ts
    data-selector.ts
    assertions.ts
    reports.ts
    scenario-runner.ts
    types.ts
  scenarios/
    smoke.spec.ts
    task-accept-complete.spec.ts
    order-entry-task.spec.ts
    dispatch-standard-sale.spec.ts
    dispatch-return-expected.spec.ts
    discount-approval.spec.ts
    photo-gates.spec.ts
  fixtures/
    sample-upload-photo.png
  config/
    test-users.example.json
    scenario-config.example.json
ERPNext-Automation-Reports/
  .gitkeep
```

Notes:

- Real credentials must not be committed.
- Reports/artifacts should normally be ignored by git.
- Example config files can be committed only if they contain no secrets.
- Exact scenario files are placeholders until final test kinds are chosen.

---

## 8) Report/artifact format

### 8.1 `run-manifest.json`

Purpose: track what the automation created/touched.

Example:

```json
{
  "runId": "2026-09-09_15-30-12_task-core",
  "baseUrl": "https://test.erpnext.am",
  "environment": "test",
  "browserMode": "visible",
  "viewport": "desktop",
  "createdRecords": [
    { "doctype": "Task", "name": "TASK-00042", "purpose": "Order entry" },
    { "doctype": "Dispatch Case", "name": "DC-2026-00031", "purpose": "Standard sale" }
  ],
  "users": [
    { "role": "Ops - Order Creating", "user": "configured-later" }
  ]
}
```

### 8.2 `report.json`

Purpose: machine-readable result for Devin analysis.

Example:

```json
{
  "scenario": "task-accept-complete",
  "environment": "test",
  "baseUrl": "https://test.erpnext.am",
  "status": "failed",
  "durationMs": 42130,
  "classification": "ui_state_mismatch",
  "probableCause": "Complete button was rendered before completion prerequisites were satisfied.",
  "steps": [
    {
      "name": "Click Complete",
      "role": "Ops - Inventory",
      "user": "configured-later",
      "status": "failed",
      "expected": "Complete button visible and enabled only after required photo exists",
      "actual": "Complete button visible and enabled before photo upload; server rejected completion",
      "url": "https://test.erpnext.am/app/task/TASK-00042",
      "screenshot": "screenshots/failure.png",
      "domFragment": "dom/failure.html",
      "consoleErrors": [],
      "networkErrors": []
    }
  ],
  "summary": {
    "passed": 12,
    "failed": 1,
    "skipped": 0,
    "consoleErrors": 0,
    "networkErrors": 0,
    "failedAssertions": 1
  }
}
```

### 8.3 `report.html`

Purpose: human-readable review.

Should show:

- pass/fail summary
- screenshots
- step timeline
- errors and dialogs
- console/network summaries
- links to trace/video files
- created ERPNext record names

### 8.4 Console logs

Capture:

```text
console.error
uncaught exceptions
unhandled promise rejections
important warnings if project-specific
```

Known useful tags from project scripts:

```text
[TaskAccept]
[TaskLock]
[TaskAuto]
[TaskPack]
[TaskToggle]
```

### 8.5 Network logs

Capture:

```text
failed requests
non-2xx API responses where relevant
/api/method failures
/api/resource failures
upload_file failures
savedocs failures
```

Do not dump secrets, auth headers, cookies, or full private payloads into reports.

---

## 9) Browser modes

First version decision:

```text
Visible browser only by default.
```

Viewport can be selected with confirmation:

```text
desktop
mobile
both
```

### 9.1 Desktop checks

Desktop should verify:

- Frappe header custom buttons
- standard form layout
- Task action buttons in header
- dialogs
- field visibility/editability

### 9.2 Mobile checks

Mobile should verify:

- Task mobile sub-header
- bottom floating actions
- mobile Back / Refresh controls
- Product dropdown if relevant
- photo gallery mobile behavior
- no duplicate buttons
- important fields not hidden by mobile CSS

Important project context:

- Task action buttons are intended to be owned by `Task-Action Buttons.js`.
- Historical docs/audits mention prior duplicate Accept/mobile controls; tests should catch regressions where duplicate buttons reappear.

---

## 10) Login strategy options

Final login strategy still needs discussion.

### 10.1 Option A: local credentials outside git

Credentials stored in an uncommitted local file, for example:

```text
tests/e2e/.env.local
```

Pros:

- fully automatic
- good for repeated regression runs
- easier multi-role switching

Cons:

- credentials must be protected
- accidental commit risk if ignore rules are wrong

### 10.2 Option B: manual login once, reuse saved session

User logs in manually in visible browser. Automation saves session state locally and reuses it.

Pros:

- avoids storing password initially
- good for early local debugging

Cons:

- sessions expire
- harder for many roles
- not fully automatic

### 10.3 Recommended

Support both:

```text
manual saved sessions for development/debugging
local credentials for reliable automated regression runs
```

Needed decision:

```text
Should implementation include both from the start, or start with saved sessions only?
```

---

## 11) Test data strategy options

Final test data strategy still needs colleague discussion.

### 11.1 Option A: fresh records every run

Automation creates all required records for each run.

Pros:

- repeatable
- independent of old records
- easier failure isolation

Cons:

- creates many records
- needs cleanup/cancel/close strategy
- needs enough stock and master data setup

### 11.2 Option B: existing prepared records only

Automation uses existing test ERPNext records.

Pros:

- simple at first
- less setup
- close to real data

Cons:

- fragile if someone edits/deletes records
- harder to know why failure happened

### 11.3 Option C: existing master data + fresh transaction records

Use existing:

```text
Customer
Item with stock in Main - Inmed
Warehouses
Users/Roles
```

Create fresh:

```text
Task
Dispatch Case
Sales Invoice through workflow
Payment Entry through workflow
File/photo attachments
```

Recommendation:

```text
Option C
```

This matches current user answers best.

---

## 12) Data selection rules

### 12.1 Users

Automation may use any configured user with the required role.

Selection rules:

1. User must be enabled.
2. User must have the exact role needed for the current step.
3. Extra roles are acceptable as long as the required role is present.
4. Do not use example/sample users.
5. Prefer non-admin user.
6. User should not have System Manager unless the test is explicitly admin-only.
7. If multiple users match, choose any suitable non-example user, with optional preference from config later.
8. If no suitable user is found, fail with clear setup error.

Roles expected across dispatch/task tests:

```text
Ops - Order Accepting
Ops - Order Creating
Ops - Inventory
Delivery Driver
Ops - Returns
Ops - Accounting
Ops - Finance
Ops - Directors
Ops - Purchasing later
```

### 12.2 Customer

Automation may use any suitable customer on test.

Selection rules:

1. Customer must be enabled/active if such a field exists.
2. Prefer non-provisional if available.
3. Prefer customer with linked client-location warehouse for return-expected tests.
4. For no-return tests, any safe customer is acceptable.
5. Reports must record the chosen customer.

Decision: automation may pick any suitable customer automatically. A configured preferred customer can be added later as optional convenience, but it is not required for core logic.

### 12.3 Item

First stock-changing tests should use an existing item with stock in:

```text
Main - Inmed
```

Selection rules:

1. Item must be enabled.
2. Item must be stock item.
3. Item must have available stock in `Main - Inmed`.
4. Prefer item without batch/serial requirements while tracking is temporarily disabled operationally.
5. Prefer item with selling price if pricing checks are needed.
6. Reports must record selected item and starting stock.

Open issue: current belief is that all items may have zero quantity. Stock-changing tests require either an existing item with available stock or a separate setup/precondition step to create stock on test. The minimum threshold can be scenario-configurable later.

---

## 13) Failure policy

Current decision:

```text
Continue remaining tests and report all failures, but stop on dangerous/data-changing failures.
```

### 13.1 Continue when safe

Continue after failures like:

```text
button missing
field hidden
assertion mismatch
console warning/error
expected dialog did not appear
network request failed on read-only check
```

### 13.2 Stop the scenario when state may be unsafe

Stop current scenario when:

```text
wrong environment detected
login as wrong role
unexpected production URL
Dispatch Case partially submitted in wrong state
payment recorded with wrong amount/customer
stock movement happened for wrong item/customer
required generated record cannot be found after submit
browser lost session during data-changing step
```

### 13.3 Continue next independent scenario if safe

If one scenario fails after creating test records, next scenarios may continue only if they do not depend on the failed state.

---

## 14) Test categories

Exact test scenarios/test kinds will be written later. Core engine should support these categories.

### 14.1 Smoke/navigation tests

Purpose: confirm ERPNext is generally usable.

Checks:

- login page opens
- user can log in
- Desk loads
- Task list opens
- new Task form opens
- Dispatch Case list opens
- reports/workspaces open where expected
- no severe console errors
- no critical network failures

### 14.2 Task acceptance/lock tests

Purpose: protect custom Task acceptance and locking model.

Checks:

- team-assigned task starts Open
- Accept / Start Task visible before acceptance
- Accept / Start Task disappears for accepting user after accept
- task status/user fields update correctly
- non-accepted user sees read-only state
- non-owner cannot complete accepted task
- Complete button appears only according to rules
- completed task loses action buttons
- reassignment resets acceptance when tested later

### 14.3 Task action button tests

Purpose: protect UI/action scripts.

Checks:

- no duplicate Accept buttons
- no duplicate Complete buttons
- no duplicate Create Dispatch Case buttons
- no duplicate mobile back/refresh controls
- correct action buttons shown by task state
- Save button behavior is correct when form is dirty
- Complete button restores state after server validation error

Project docs identify historical risk around duplicate Task buttons and mobile controls, so these should be explicit regression checks.

### 14.4 Standard sale / no-return Dispatch Case

Purpose: full customer dispatch flow without return.

Expected chain:

```text
Order entry task
  -> Dispatch Case return_expected = No
  -> Pack task
  -> Delivery task: Todo -> Picked Up -> Delivered
  -> Invoice Preparation task
  -> Debt Collection task if outstanding > 0
  -> Payment
  -> Closed
```

Expected generated records:

```text
Dispatch Stock Entry
Delivery Stock Entry
Consumption Stock Entry
Sales Invoice
Payment Entry if payment recorded
```

### 14.5 Return-expected Dispatch Case

Purpose: full surgery/loan/return flow.

Expected chain:

```text
Order entry task
  -> Dispatch Case return_expected = Yes
  -> Pack task
  -> Delivery task
  -> Return Call task
  -> Pickup Returns task
  -> Returns Inspection task
  -> Restock task if returned_qty > 0
  -> Invoice Preparation task
  -> Debt Collection task if outstanding > 0
  -> Payment
  -> Closed
```

Key invariant:

```text
dispatched_qty = used_qty + returned_qty + lost_damaged_qty
```

### 14.6 Discount approval tests

Current decision: include both approved and rejected paths when discount tests are added.

Approved path:

```text
Discount % > 0
  -> Discount Approval task created
  -> Director approves
  -> case can proceed
  -> Pack task created
```

Rejected path:

```text
Discount % > 0
  -> Discount Approval task created
  -> Director rejects
  -> case stays/reverts to Draft
  -> new Order entry/revision task created
  -> Order Creating revises pricing
```

### 14.7 Photo gate tests

Current decision: include both Pack and Return drop-off photo gates when photo tests are added.

Pack gate:

```text
Pack / prepare items cannot complete without at least one image File attached.
After upload, completion succeeds.
```

Return drop-off gate:

```text
Pickup Returns cannot move to Returned to Warehouse without at least one image File attached.
After upload, transition succeeds.
```

Also verify:

- upload hidden before acceptance
- upload allowed after acceptance
- galleries show thumbnails
- max 5 photos behavior eventually
- Dispatch Case read-only galleries eventually

### 14.8 Purchase flow tests — later

Current decision:

```text
Do not include purchase/supplier flow in first implementation.
```

Later purchase coverage may include:

```text
Purchase Order
Purchase Approval
Purchase Receipt
Landed Cost Voucher
Purchase Invoice
```

But this is out of first implementation scope.

---

## 15) Important workflow expectations from project docs

### 15.1 Task system

Core rules to test later:

- tasks start assigned to team placeholder with status Open
- user must Accept / Start before edit/complete
- accepted task locks to accepting user
- reassignment resets acceptance
- Task Access Policy is source of truth for roles/team
- no hardcoded role dictionaries in server scripts

### 15.2 Dispatch Case

Core rules to test later:

- Dispatch Case is the coordinator record
- users mainly work from Task inbox
- workflow advances through task completion/status changes
- Stock Entries are created/submitted by server scripts
- no manual Stock Entry forms for operational users
- no manual Dispatch Case workflow buttons for managers

### 15.3 Photos

Core rules to test later:

- File records are source of truth
- Pack requires at least one image to complete
- Delivery requires no photo
- Pickup Returns requires drop-off photo when returning to warehouse
- Returns Inspection sees Pack photos read-only

### 15.4 Reports/workspaces

Core smoke checks later:

```text
RPT - Item - Sort and Classify
RPT - Item - Nomenclature and Prices
RPT - Returns - Refund Queue
Management - KPI Dashboard
Dispatch - Task Queues
```

### 15.5 Known disabled/deferred flow

`Distribute Payment` is disabled/deferred.

Tests should assert:

```text
No Distribute Payment task is created after payment recording while the flow remains disabled.
```

Purchase flow is also not first implementation scope.

---

## 16) Chrome extension phase

The Chrome extension, if built later, should not be an unrestricted agent.

It should be a controlled browser companion with allowlisted actions.

Possible features:

```text
inspect current page
select element and report selector/state
record manual click/fill steps
send current DOM/page state to local bridge
receive safe commands from local bridge
highlight what automation will click
```

The extension should still obey:

```text
test.erpnext.am only by default
no prod writes
no credential logging
explicit user confirmation for risky actions
```

---

## 17) Devin/MCP bridge phase

A later phase can expose browser automation tools to Devin using MCP.

Possible tools:

```text
run_scenario(name, viewport)
open_page(path)
get_page_state()
click_button(text)
fill_field(fieldname, value)
select_field(fieldname, value)
assert_visible(target)
assert_enabled(target)
assert_disabled(target)
assert_field_value(fieldname, value)
get_console_errors()
get_network_errors()
get_last_report()
```

This would allow requests like:

```text
Run the Task accept/complete regression tests on test.
Check if the Complete button is visible and enabled.
Open this task and tell me what fields are read-only.
Run mobile checks for Task action buttons.
```

MCP should be later than the core runner unless the colleague decides otherwise.

---

## 18) Implementation approval checklist

Before creating implementation code, confirm:

1. Architecture choice:
   - Playwright first
   - Chrome extension first
   - hybrid together
2. Login strategy:
   - saved sessions only
   - local credentials only
   - both
3. Test data strategy:
   - fresh records
   - existing records
   - existing master data + fresh transaction records
4. Cleanup strategy:
   - keep records
   - cancel/close records
   - periodic manual cleanup
5. Whether dependencies may be installed locally.
6. Whether implementation should create `tests/e2e/` and `ERPNext-Automation-Reports/` folders.
7. Whether first implementation should include only core framework and one tiny smoke example, or core framework only with no scenarios.

Exact business scenario list/test kinds can be decided later.

---

## 19) Colleague discussion questions

This is the short list to discuss with the colleague before implementation. Exact business test scenarios/test kinds can be written later; these questions decide the core mechanism.

### 19.1 Architecture

```text
A. Playwright first
B. Chrome extension first
C. Playwright + Chrome extension together
```

Recommendation: A — Playwright first.

### 19.2 Login strategy

```text
A. Saved manual sessions only
B. Local credentials outside git only
C. Both saved sessions and local credentials
```

Recommendation: C — both.

### 19.3 Test data strategy

```text
A. Fresh records every run
B. Existing records only
C. Existing master data + fresh E2E transaction records
```

Recommendation: C.

### 19.4 Cleanup strategy

After automation creates test records:

```text
A. Keep all E2E records for debugging/audit
B. Cancel/close them when possible
C. Periodically clean old E2E records manually
```

Recommendation: C first, then later maybe B.

### 19.5 Dependency approval

When implementation starts, may we install Playwright/Node dependencies locally?

```text
A. Yes
B. No
C. Ask again before installing
```

Recommendation: C or A, depending on caution level.

### 19.6 Initial implementation scope

For the first build, should it include:

```text
A. Core framework only, no real scenario
B. Core framework + tiny login/navigation smoke scenario
C. Core framework + Task button/page-state inspection scenario
```

Recommendation: B + C if possible.

### 19.7 Stock precondition strategy

Because items may currently have zero stock, what should stock-changing tests do?

```text
A. Do only non-stock smoke/UI checks first; stock scenarios wait until stock exists
B. Add setup step that creates stock on test before stock-changing scenarios
C. Use existing item if stock exists; otherwise skip stock-changing scenarios with clear report
```

Recommendation: C first, B later if fully reliable stock-changing tests are required.

---

## 20) Detailed remaining open questions and recent answers

### 20.1 Architecture

Should the first version be:

```text
A. Playwright first
B. Chrome extension first
C. Playwright + Chrome extension together
D. Discuss with colleague
```

Current answer: discuss with colleague.

Recommendation: Playwright first, Chrome extension later if needed.

### 20.2 Login strategy

Should implementation start with:

```text
A. Saved manual sessions only
B. Local credentials outside git only
C. Both saved sessions and local credentials
D. Discuss with colleague
```

Recommendation: C.

### 20.3 Test data strategy

Should tests use:

```text
A. Fresh records every run
B. Existing records only
C. Existing master data + fresh E2E transaction records
D. Discuss with colleague
```

Recommendation: C.

### 20.4 Cleanup strategy

After automation creates records, what should happen?

```text
A. Keep all E2E records for debugging/audit
B. Cancel/close them when possible
C. Periodically clean old E2E records manually
D. Discuss with colleague
```

### 20.5 Dependency approval

When implementation starts, may Playwright/Node dependencies be installed locally?

```text
A. Yes
B. No
C. Ask again before installing
D. Discuss with colleague
```

Current answer: discuss/ask again.

### 20.6 User discovery method — answered

Decision:

```text
Automation should find enabled users who have the exact role needed for the test step.
Extra roles are acceptable.
Do not use example/sample users.
Do not use Administrator/System Manager for role/lock tests.
```

Implementation note:

```text
Use ERPNext user/role data if login/API access allows it.
If API discovery is not available yet, the runner may fail with a clear setup error asking for a local non-secret role-to-user mapping.
```

### 20.7 Master-data selection strictness — answered

Decision:

```text
Automation may pick any suitable customer automatically.
Automation should use an existing suitable item, preferably with stock in Main - Inmed.
```

### 20.8 Stock availability / minimum stock threshold — open

Current concern:

```text
User believes all items may currently have zero quantity.
```

This affects full stock-changing tests because Dispatch Case, delivery, return, invoice, and payment tests need available stock or a controlled stock setup step.

Question:

```text
A. First implementation only builds core logic and non-stock smoke/UI checks; stock scenarios wait until stock exists.
B. Add a test setup step that creates stock on test for a chosen item before stock-changing scenarios.
C. Use any existing item if quantity becomes available later; otherwise skip stock-changing scenarios with a clear report.
D. Discuss with colleague.
```

Recommendation: C for core logic, B later if full stock-changing scenarios must run reliably.

### 20.9 Initial implementation scope — open

If exact test scenarios are not chosen yet, should first implementation include:

```text
A. Core framework only, no real scenario
B. Core framework + tiny login/navigation smoke scenario
C. Core framework + Task button/page-state inspection scenario
D. Discuss with colleague
```

Current answer: discuss with colleague.

Recommendation: B or C.

### 20.10 Cleanup safety — open

If cleanup is later automated, is automation allowed to cancel/close/delete E2E records?

```text
A. Delete never; only cancel/close if business-safe
B. Delete only records created by the same run
C. No automated cleanup; manual cleanup only
D. Discuss with colleague
```

Current answer: discuss with colleague.

Recommendation: A or C. Avoid deletion.

---

## 21) What is intentionally not decided yet

These do not block the core architecture if the runner is scenario-driven:

- exact test scenario names
- exact first business flow
- exact pass/fail details for each later test
- exact mobile vs desktop run choice per test run
- exact future purchase-flow scope
- exact Chrome extension features
- exact MCP tool names

These should be added as scenario files/specs after the core is approved.

---

## 22) Definition of ready to implement

This documentation is ready to guide implementation when these minimum items are answered:

```text
1. Architecture choice
2. Login strategy
3. Test data strategy
4. Cleanup strategy
5. Dependency approval
6. Initial implementation scope: core-only or core + tiny smoke scenario
```

If the first implementation includes stock-changing scenarios, also answer:

```text
7. Stock availability/precondition strategy: skip until stock exists, create stock setup on test, or auto-skip with clear report
```

Everything else can be added later as test scenarios.
