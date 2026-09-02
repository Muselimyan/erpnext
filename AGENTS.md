# Project Rules

## Mandatory: No Changes Without Approval

**NEVER implement or edit any code until the user explicitly approves.** When the user shares a crash log, error, or bug report:

1. Investigate the issue thoroughly.
2. Propose a solution with clear explanation.
3. **STOP and wait for the user's explicit approval before making any changes.**

This applies to ALL changes — client scripts, server scripts, deploy scripts, configuration. No exceptions. Investigate and propose first, implement only after approval.

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

### Patterns to use instead

- **Regex:** Use `.endswith(tuple)`, `.startswith()`, `in` checks instead of `re`.
- **Helper functions:** Inline them at the call site, or nest them inside the calling function.
- **Constants:** Define at module level (this works), but reference them only from module-level code, not from inside `def` bodies (pass as arguments if needed).
- **Shared logic across scripts:** Duplicate it. Each Server Script is an isolated execution unit; there is no module system.

### Before deploying any server script

Mentally check every `def` body: does it reference anything defined outside that `def`? If so, it will fail. The only names available inside a `def` are: its own locals, its parameters, builtins, and `frappe`.

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
3. Once accepted, **only that user** can edit or complete the task. Others see it read-only.
4. Reassignment resets acceptance (clears `custom_accepted_by`, reverts status to Open).

**Do NOT:**
- Remove the acceptance requirement or bypass the lock without checking admin status.
- Allow task completion without prior acceptance.
- Allow simultaneous reassignment and completion in one save.

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
- Client Scripts: `Task-Accept Start`, `Task-Lock Unaccepted`, `Task-Auto Reload`, `Task-Dispatch Packing Usability`, `Global-Mobile Back Button List`
- Log tags: `[Policy]`, `[Accept]`, `[List]`, `[Dispatch]`, `[Lock]`, `[Gates]`, `[OtherFlow]`, `[TgAssign]`, `[TgStatus]` (server); `[TaskAccept]`, `[TaskLock]`, `[TaskAuto]`, `[TaskPack]`, `[TaskToggle]` (client)

### Deployment model

- Scripts live in `deploy/test/work/server/` and `deploy/test/work/client/` with metadata headers.
- Deploy scripts in `deploy/test/scripts/` push to the test environment only.
- Each script file has a header block (e.g. `# Name:`, `# Type:`, `# ---`) that is stripped before upload.
- After deploying, always clear cache: `docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache`
- After deployment, run `deploy/test/export.ps1` to capture the current state.

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
- `frappe.get_cached_doc` is NOT verified in safe_exec (never observed working in Server Scripts).
- `frappe.make_post_request` works for HTTP calls (used for Telegram API).
- `raise SystemExit` works for early exit in API scripts.
