# Project Rules

## Mandatory: No Changes Without Approval

**NEVER implement or edit any code until the user explicitly approves.** When the user shares a crash log, error, or bug report:

1. Investigate the issue thoroughly.
2. Propose a solution with clear explanation.
3. **STOP and wait for the user's explicit approval before making any changes.**

This applies to ALL changes — client scripts, server scripts, deploy scripts, configuration. No exceptions. Investigate and propose first, implement only after approval.

---

## Use ERPNext's own features. Do not diverge without a stated reason

**If a standard ERPNext or Frappe feature satisfies the requirement, use it. Do not write a custom implementation of something the platform already does.**

Before building anything in this area — a document, a calculation, a status flow, a report, an allocation rule — check whether ERPNext already provides it. Credit notes, advance allocation, payment references, aging reports, gross profit, stock valuation, return flows and approval workflows all exist natively.

Custom code costs more than it looks. It has to be maintained, it does not benefit from upstream fixes, it breaks on upgrade, and it will not match what an accountant or a new developer expects to find. A custom reimplementation is also usually *worse* than the native one, because the native one has had years of edge cases beaten out of it.

### When divergence IS justified

Only two reasons:

1. **The native behaviour is wrong for this domain.** Example: `task_commit_invoice` does not use ERPNext's `set_advances()`, because that pulls *every* unallocated advance a customer holds and would spend money earmarked for case A on case B's invoice. This project tags credit with intent, and the native helper cannot see that tag. Divergence justified, and the reason is written in the code.

2. **The native feature cannot be reached from where the data is.** Example: dispatch invoices carry `update_stock = 0` and no Delivery Note, so ERPNext has no stock transaction to derive a cost from and `Sales Invoice Item.incoming_rate` is empty. This does not license a hand-rolled cost lookup — it means the *linkage* is the problem to fix.

### The rule when you do diverge

- State the reason in a comment at the divergence point, naming the native feature you rejected and why.
- Record it in the relevant group document, so the next person knows it was a decision and not an oversight.
- Prefer using native **documents** with custom **orchestration** over inventing new documents. Creating a standard `Sales Invoice` from a task is not divergence; inventing an "Invoice Record" doctype would be.

### Counter-example from this project

Profit on the Debt Closure Approval task is computed by hand from a buying price list. ERPNext already has a Gross Profit report built on valuation. That is divergence with no stated reason, it produces a *worse* number than the native one (a missing price silently becomes 100% margin), and it now has to be unwound. Do not add more of these.

---

## No Client-Side Patching of Layout

**NEVER use client-side JavaScript to patch, override, or fix layout issues after page load.** This includes:

- Setting CSS `width`, `max-width`, `display`, or column classes via jQuery/JS after form render
- Using `$wrapper.css(...)` or `.closest(...).css(...)` to override Frappe's rendered layout
- Injecting `<style>` tags to compensate for structural field-order or column-break issues

Layout problems (wrong column width, section width, field positioning) must be fixed **structurally** — by correcting the `field_order` Property Setter, moving Column Breaks, or adjusting Custom Field definitions. The rendered layout must be correct from the server response, not patched after load.

The only acceptable client-side visibility changes are:
- `toggle_display` / `set_df_property("hidden", ...)` for field visibility (TFV's job)
- Collapsing sections via Frappe's native `sb.collapse()` API or equivalent
- Adding click handlers for custom collapse behavior on footer elements (Comments, Activity)

---

## Frappe Server Scripts — RestrictedPython Constraints

Frappe Server Scripts run under RestrictedPython (`safe_exec`). The following constraints MUST be followed. Violations cause runtime `NameError`, `SyntaxError`, or `ImportError` with no compile-time warning.

### Hard rules

1. **No underscore-prefixed variables.** `_foo`, `_IMAGE_RE`, `__bar` are all rejected at compile time. Use `foo`, `imageRe`, `bar` instead.

2. **No `import` statements.** `import re`, `from os import path`, etc. are blocked. Use only builtins and the pre-injected `frappe` namespace.

3. **No sibling function calls.** A function defined at module level CANNOT call another function defined at the same level. RestrictedPython compiles each `def` with its own restricted scope that does not include the module namespace.

   Bad (will crash at runtime):
   ```python
   def helper():
       return True

   def main_logic():
       helper()  # NameError: name 'helper' is not defined
   ```

   Good — inline the logic:
   ```python
   def main_logic():
       # helper logic directly here
       pass
   ```

   Good — nest the helper:
   ```python
   def main_logic():
       def helper():
           return True
       helper()  # works
   ```

4. **No double-underscore attribute access.** `obj.__class__`, `obj.__dict__`, etc. are blocked.

5. **No `exec()`, `eval()`, `compile()`, `__import__()`.** All blocked.

6. **No augmented assignment to a subscript.** `d[k] += 1`, `d[k]["x"] += 1`, `lst[0] += 1` all fail with *"Augmented assignment of object items and slices is not allowed"*. Read into a local, modify, write back:

   Bad:
   ```python
   totals[cust]["outstanding"] += amount
   ```

   Good:
   ```python
   entry = totals[cust]
   entry["outstanding"] = entry["outstanding"] + amount
   ```

   Plain assignment to a subscript (`d[k] = v`) is fine — only the augmented form is blocked. Augmented assignment to a plain local (`total += x`) is also fine.

### Saving a Server Script does NOT prove it runs

Frappe's `ServerScript.validate()` calls `check_if_compilable_in_restricted_context()`, so a script with a syntax error will refuse to save. **It does not catch the full RestrictedPython policy.** A script violating rule 6 above saves cleanly and then throws the first time it executes.

This matters most for Scheduler Events, which may not run for hours: a broken scheduler looks deployed and simply never does anything. It also produces false-positive tests — a check asserting "no new task was created" passes trivially when the scheduler crashed on line 1.

**Only execution proves a Server Script works.** After deploying one, run it (for schedulers, `frappe.get_doc("Server Script", name).execute_scheduled_method()` from `bench console`) and assert on the result.

### Patterns to use instead

- **Regex:** Use `.endswith(tuple)`, `.startswith()`, `in` checks instead of `re`.
- **Helper functions:** Inline them at the call site, or nest them inside the calling function.
- **Constants:** Define at module level (this works), but reference them only from module-level code, not from inside `def` bodies (pass as arguments if needed).
- **Shared logic across scripts:** Duplicate it. Each Server Script is an isolated execution unit; there is no module system.

### Before deploying any server script

Mentally check every `def` body: does it reference anything defined outside that `def`? If so, it will fail. The only names available inside a `def` are: its own locals, its parameters, builtins, and `frappe`.

---

## `Before Save` does NOT fire for submitted documents

Frappe's `run_before_save_methods()` runs `validate` and `before_save` **only** when `_action == "save"`. Saving a document with `docstatus = 1` sets `_action = "update_after_submit"`, which runs `before_update_after_submit` instead.

**A Server Script registered on "Before Save" is therefore invisible to every submitted document.** Same for "After Save" versus "After Save (Submitted Document)".

This is easy to get wrong and fails silently — the rule appears to be in place and simply never runs. It is how the "only Directors may edit a submitted Dispatch Case" rule went unenforced for its entire existence, and how the W1 Dispatch Case gate initially covered only draft cases while a Dispatch Case is submitted for the whole of packing, delivery and returns.

Rules:

- A guard on a doctype whose records get **submitted** needs a twin on `Before Save (Submitted Document)`. Because RestrictedPython has no module system, that means a duplicated script — say so in a header comment on both, and keep them in sync.
- When writing a test for such a guard, **make the fixture submitted**. A draft fixture will pass against a gate that does not actually cover the submitted case, which is exactly what happened here.
- Before assuming a rule works, check which event it is registered on.

Current twin pair:
`Dispatch-Case-before-save-access-control` (draft) and
`Dispatch-Case-before-save-submitted-access-control` (submitted).

---

## `bench console` has no request boundary — use a savepoint when testing failure paths

A real HTTP request rolls the whole transaction back when an exception escapes. `bench console` does not: partial writes stay visible for the rest of the session, until you roll back explicitly.

This matters most when testing that something **fails correctly**. `doc.submit()` writes `docstatus = 1` and *then* runs `on_submit` and the GL posting. If the GL posting throws, the console still shows a submitted document — one that could never exist in production, because the request would have rolled it back.

A harness that does not account for this reports a submitted invoice, a posted stock entry or a completed task that the code correctly refused to create, and **working code looks broken**.

Emulate the request boundary:

```python
frappe.db.savepoint("mytest")
try:
    frappe.get_doc("Server Script", "some_api").execute_method()
except Exception as e:
    err = str(e)
    frappe.db.rollback(save_point="mytest")
```

Reference: `deploy/test/deploy/group-11-financial-tail/a2-verify-allocation-abort.py`.

The inverse also holds: a test asserting that something *succeeded* proves nothing about whether it would survive a real request, because the console never commits either. Assert on the documents, not on the absence of an exception.

---

## Deploy scripts must read and write UTF-8 explicitly

Windows PowerShell 5.1 reads BOM-less files as **ANSI**, not UTF-8. `Get-Content -Raw` therefore mangles every non-ASCII character before upload, and `Invoke-RestMethod` mis-decodes non-ASCII in JSON **responses** as Latin-1 when the server declares no charset.

Both directions must be handled, or box-drawing characters, em-dashes and Armenian text are corrupted on the server:

```powershell
# Reading a script file for upload
$raw = Get-Content $Path -Raw -Encoding UTF8

# Reading a document back (for Check mode comparison)
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
$wc.Headers.Add("Authorization", "token $($ApiKey):$($ApiSec)")
$doc = ($wc.DownloadString($uri) | ConvertFrom-Json).data
```

Without the first, uploaded content is corrupted — this is the origin of the mojibake found in `Task-after-save-debt-closure` and in the Discount Approval task subject. Without the second, Check mode reports a false `DIFFERS` for any script containing non-ASCII, and a Check → Deploy loop can ping-pong content indefinitely.

Reference implementation: `deploy/test/deploy/group-11-financial-tail/*.ps1`. Older deploy scripts under `deploy/test/scripts/` have not all been audited for this.

### Corollary: never put a non-ASCII character inside a double-quoted string in a `.ps1`

The same ANSI misread applies to the deploy script's **own source**. A mangled character inside a double-quoted string is not merely corrupt text — it is a **PowerShell syntax error**, and the script dies before its first line runs.

Non-ASCII in *comments* is harmless. In a string it is fatal. Build the character from its code point:

```powershell
$EmDash = [char]0x2014
$DupReport = "RPT $EmDash Risk $EmDash Debt Threshold Exceeded"
```

Many doctype names on this instance (reports, workspaces) contain em-dashes, so this comes up whenever one is referenced by name. Check before running:

```powershell
$t = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
([regex]::Matches($t, '"[^"\r\n]*[^\x00-\x7F][^"\r\n]*"')).Count   # must be 0
```

### A Workspace cannot be saved while any of its Links is dead

Frappe validates **every** Link row on save, so one shortcut pointing at a deleted report makes the whole workspace unsaveable — including edits that have nothing to do with the broken row. `Ops — Reporting Pack` had two such shortcuts and they blocked an unrelated repoint.

This reclassifies dangling shortcuts from cosmetic to blocking. When touching a workspace, validate every `type = "Report"` shortcut against existing Reports first, then repoint what can be repaired and drop what cannot. Reference: section 3 of `deploy/test/deploy/group-11-financial-tail/a7-one-debt-definition.ps1`.

### Back-dating a Sales Invoice requires `set_posting_time = 1`

Without it ERPNext **silently overwrites** the supplied `posting_date` with today. A back-dated `due_date` then fails validation with *"Due Date cannot be before Posting Date"* — an error that points at the due date when the fault is the posting date. Any fixture building an overdue invoice needs the flag.

---

## Task System Architecture (do NOT break these invariants)

### Single source of truth: Task Access Policy

All task-kind role mappings and team assignments are stored in `Task Access Policy` records (DocType). **Never hardcode role dictionaries or team constants in Server Scripts.** Scripts must read from the policy records at runtime:

```python
# Correct: read from policy
policy = frappe.get_doc("Task Access Policy", doc.task_kind)
allowed_roles = [r.role for r in (policy.allowed_roles or [])]
default_team = policy.default_team_user or ""
```

```python
# WRONG: hardcoded map (the old pattern, now removed)
TASK_KIND_ALLOWED_ROLES = {"Order entry": ["Ops - Order Accepting"], ...}
```

### Acceptance and lock model

The task system uses a mandatory acceptance model:
1. Tasks start assigned to a **team placeholder** (e.g. `delivery.team@example.com`) with status **Open**.
2. A user must click "Accept / Start Task" (calls `dispatch_task_accept` API) to take ownership.
3. Once accepted, only that user may **complete** the task. Privileged users may edit it (see below); everyone else sees it read-only.
4. Reassignment resets acceptance (clears `custom_accepted_by`, reverts status to Open).

**Completion is reserved to the accepter, with no exemption at all** — not for Administrator, not for System Manager, not for Ops - Directors. The record of who did the work must stay truthful. Cancellation is the escape hatch for a stuck task.

**Editing** allows a privileged override (`System Manager`, `Ops - Directors`, or the `Administrator` user), because stuck tasks exist and previously nobody could clear them. The form shows an explicit banner when a privileged user is editing someone else's task.

**Do NOT:**
- Remove the acceptance requirement, or grant any exemption to *completion*.
- Allow task completion without prior acceptance.
- Allow simultaneous reassignment and completion in one save.
- Re-introduce `flags.ignore_permissions` as a "this is the system writing" signal — see below.

### One gate per doctype, and no bypass flag

Acceptance, ownership, task-kind role access and completed-task immutability are owned by exactly one script per doctype:

| DocType | Owner |
|---|---|
| Task | `Task-before-save-access-control` |
| Dispatch Case (draft) | `Dispatch-Case-before-save-access-control` |
| Dispatch Case (submitted) | `Dispatch-Case-before-save-submitted-access-control` |

No other script may enforce those rules. Domain rules — photo required, delivery status order, invoice submitted, collection outcome recorded — live in `Task-before-save-dispatch-gates`, which must not contain access control.

**`flags.ignore_permissions` is standard Frappe and means "skip Frappe's DocType permission check". It does not mean "skip our business rules", and must never be read as such.** Three scripts used to read it that way and only one of the five overlapping checks honoured it, which is how an `Ops - Accounting` user came to be blocked from completing Invoice Preparation for any repeat customer.

The gates instead ask **what changed**, not who is writing: a save touching only fields in that gate's `SYSTEM_FIELDS` list is bookkeeping and is allowed; anything else needs ownership. Polarity is **default-deny**, so forgetting to register a new system-managed field makes housekeeping fail loudly rather than silently opening a hole. When a field stops having a legitimate system writer, remove it from the list.

### Work facts belong on the Task; business facts belong in the ledger

A Task is a unit of work. It may store facts about **the work**: who accepted it, when it completed, what the outcome of a collection attempt was, what the caller said.

It must **not** store facts about the business that outlive the work — what a customer owes, which invoices are unpaid, how much has been paid. Those live in Sales Invoices, Payment Entries and the GL, and are read live (see `task_debt_panel`). A second copy always drifts: the deleted `total_outstanding` / `open_invoices` / `payment_history` fields had Dispatch Cases showing millions outstanding against invoices the ledger reported as fully paid.

The same rule applies to the Dispatch Case: it holds operational state, not a private copy of the receivables ledger.

Deliberate exception, documented so it is not "fixed" by mistake: `Task.current_debt_amd` and `Task.debt_threshold_amd` on a **Debt Alert** task record what the debt *was at the moment the alarm was raised*. That is a fact about the alert, not a live balance.

### Key custom fields on Task

| Field | Type | Purpose |
|---|---|---|
| `task_kind` | Select | Classification (drives policy lookup) |
| `task_access_policy` | Link | Points to Task Access Policy (auto-set from task_kind) |
| `custom_assigned_to` | Link (User) | Single source of truth for assignment |
| `custom_accepted_by` | Data | Who accepted this task |
| `custom_accepted_at` | Datetime | When it was accepted |
| `completed_at` | Datetime | Auto-set when task completes |
| `dispatch_case` | Link | Links to Dispatch Case (dispatch flow tasks) |

### Script naming conventions

- Server Scripts: `Task-before-save-*`, `Task-after-save-*`, `dispatch_task_*`, `task_list_*`
- Client Scripts: `Task-Accept Start`, `Task-Field-Editability`, `Task-Auto Reload`, `Task-Dispatch Packing Usability`, `Global-Mobile Back Button List`
- Log tags: `[Policy]`, `[Accept]`, `[List]`, `[Dispatch]`, `[Lock]`, `[Gates]`, `[OtherFlow]`, `[TgAssign]`, `[TgStatus]` (server); `[TaskAccept]`, `[TFE]`, `[TFV]`, `[TaskAuto]`, `[TaskPack]`, `[TaskToggle]` (client)

### Task field visibility — single owner: `Task-Field-Visibility.js`

Field visibility on the Task form is owned exclusively by `Task-Field-Visibility.js` (TFV) via `TFV_KIND_MAP`. **No other client script may call `toggle_display`, `set_df_property('hidden')`, or DOM `.hide()/.show()` on any field listed in `TFV_KIND_MAP`.**

If a new field needs conditional visibility, add it to `TFV_KIND_MAP` with the appropriate rule. Do not add visibility toggles to other scripts — this causes race conditions where setTimeout chains override TFV's correct state.

### Task field editability — single owner: `Task-Field-Editability.js`

Field editability on the Task form is owned exclusively by `Task-Field-Editability.js` (TFE) via `TFE_EDIT_MAP` and the `tfe_can_edit(frm)` gate. **No other client script may call `set_df_property('read_only')`, `frm.set_read_only()`, `frm.disable_save()`, or DOM `.prop('disabled')` for editability purposes.**

- `tfe_can_edit(frm)` returns true when the task is not completed/cancelled **and** either `accepted_by === session.user` or the user is privileged (`System Manager` / `Ops - Directors` / `Administrator`).
- `tfe_can_complete(frm)` returns true **only** for the accepter. No exemption — it mirrors the server gate.
- Other scripts must call these two rather than reimplementing the rule. `Task-Action Buttons.js`, `Task-Photo-System.js` and `Task-Account Details UI Cleanup.js` each used to carry their own copy, and all three granted an admin exemption that this file explicitly disclaimed.
- Work-progress buttons (Complete, Picked Up, Delivered, …) are gated on `tfe_can_complete`, not `tfe_can_edit`: a privileged user may fix data but must not assert that someone else's work was performed.
- `TFE_EDIT_MAP` controls per-field kind-based editability (e.g. `customer` only editable on Order entry).
- Product section controls (PWA renderers) check `tfe_can_edit(frm)` before rendering interactive HTML controls (checkboxes, inputs, buttons).
- Server APIs also validate acceptance; completion has no bypass anywhere.
- Absorbed: `Task-Lock Unaccepted.js` (disabled), `Task-Lock Completed.js` (disabled).

### Deployment model

- Scripts live in `deploy/test/work/server/` and `deploy/test/work/client/` with metadata headers.
- Deploy scripts in `deploy/test/scripts/` and `deploy/test/deploy/<group>/` push to the test environment only.
- Each script file has a header block (e.g. `# Name:`, `# Type:`, `# ---`) that is stripped before upload.
- Every deploy script must support `-Mode Check` (report differences, change nothing) and `-Mode Deploy`. Schema **deletions** should sit behind an additional explicit switch, e.g. `-ConfirmDeletions`.
- **Read source files as UTF-8 and decode responses as UTF-8** — see the dedicated section above. Reference implementation: `deploy/test/deploy/group-11-financial-tail/*.ps1`.
- After deploying, always clear cache: `docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache`
- After deployment, run `deploy/test/export.ps1` to capture the current state.
- Then **execute** what you deployed and assert on the result — saving a Server Script does not prove it runs. The `group-11-financial-tail` folder pairs each `wN-*.ps1` deploy script with a `wN-verify-*.py` script that runs against test via `bench console` and rolls everything back, so no records survive a verification run.

### Telegram notifications

- Assignment changes on Task trigger `Telegram Task Assignment Notification` (After Save).
- Key status changes trigger `Telegram Task Status Update` (After Save).
- Bot token is read from `Telegram Settings` DocType (never hardcode tokens).
- Chat IDs are stored on `User.telegram_chat_id` custom field.
- Team placeholder expansion: finds real users by matching Ops-* roles on the placeholder user.

### RestrictedPython-safe patterns used in this project

- `doc`, `frappe`, `json`, `print` are available inside `def` bodies (injected by safe_exec).
- Module-level code can call module-level functions (but functions cannot call sibling functions).
- `frappe.get_doc`, `frappe.get_all`, `frappe.db.get_value`, `frappe.db.set_value`, `frappe.db.exists`, `frappe.db.sql` are all verified working.
- `frappe.get_meta(doctype)` works, including `.fields` and `.get_field(fieldname)`. Used by the access-control gates to enumerate fields.
- `doc.get_doc_before_save()` and `doc.has_value_changed(fieldname)` work. **Caution:** `has_value_changed` compares child tables by object identity, so it reports every `Table` field as changed on every save. To detect a real child-table change, compare a signature built from the rows (see the access-control gates).
- `doc.set_advances()` and other Document methods are callable, but prefer explicit logic where business rules matter — `set_advances()` consumes every unallocated advance a customer holds, ignoring which case each was paid for.
- `frappe.get_cached_doc` is NOT verified in safe_exec (never observed working in Server Scripts).
- `frappe.make_post_request` works for HTTP calls (used for Telegram API).
- `raise SystemExit` works for early exit in API scripts.
- Scheduler scripts can be run on demand for testing: `frappe.get_doc("Server Script", name).execute_scheduled_method()`. API scripts: `.execute_method()` after populating `frappe.form_dict`.

### Two before_save scripts on one doctype have no defined order

Frappe runs the Server Scripts registered for an event in whatever order it retrieves them. If two scripts both act in `before_save` on the same doctype, **do not rely on one seeing the other's changes**, and do not let one set a field another gates on.

Concretely: `Task-before-save-payment-recording` auto-completes a settled Debt Collection task, while `Task-before-save-dispatch-gates` requires `collection_outcome` before completion. Depending on order, the save would either be refused (losing the payment) or slip past the gate (closing an episode with no record). The fix was to make the outcome part of the same write — `collection_outcome = "Paid"` — so the result is identical either way.

When two scripts must cooperate, make each one's result correct independently.
