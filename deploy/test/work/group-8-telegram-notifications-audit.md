# Group 8: Telegram and Notifications — Audit Findings

> **Audited**: 2026-08-27
> **Scope**: All Telegram server scripts, custom DocTypes, built-in Notification records, related reference docs, recovery/patch files
> **Method**: Line-by-line code reading of every script, full schema export analysis, cross-reference against all documentation

---

## Summary

| Metric | Value |
|---|---|
| Server scripts analyzed | 2 (both enabled) |
| Client scripts analyzed | 0 (none in this group) |
| Custom DocTypes analyzed | 2 (Telegram Settings, Telegram Notification User) |
| Notification records analyzed | 5 (2 standard ERPNext, 3 custom/operational) |
| Total lines of code | 240 (145 + 95) |
| Documentation coverage | **0%** — no numbered doc, no operational procedure, no design doc |
| Bugs found | 3 |
| Doc gaps found | 5 |
| Dead code / unused infrastructure found | 2 |
| Risks found | 4 |

---

## What Is Actually Deployed

### Two Telegram Server Scripts

Both fire Telegram Bot API HTTP calls to send task-related messages to team members' personal Telegram accounts.

#### 1. Telegram Task Assignment Notification

- **Type**: DocType Event on **ToDo**, fires **After Insert**
- **Status**: Enabled
- **Created**: 2026-07-23 | **Last modified**: 2026-08-24
- **Lines**: 145
- **What it does**:
  1. Fires whenever any ToDo is inserted. Exits immediately if the ToDo is not linked to a Task (`reference_type != "Task"`).
  2. Runs a duplicate-prevention check: queries all ToDos for the same Task + same `allocated_to` user, and skips if this is not the first one.
  3. Reads the bot token from the `Telegram Settings` singleton (Password field, retrieved securely via `get_password`). Strips a leading `"bot"` prefix if present.
  4. Fetches the Task record to get `task_kind` and `priority`.
  5. Determines notification recipients:
     - If the assignee is a **team placeholder** (email ending in `.team@example.com` or in a hardcoded `TEAM_PLACEHOLDERS` list of 9 placeholder addresses), resolves all real users who share a role with that placeholder user, excluding generic roles (`System Manager`, `All`, `Guest`, `Employee`) and excluded users (`Administrator`, `ai-agent@internal.com`).
     - If the assignee is a **real user**, sends to that user only.
  6. Constructs a Markdown-formatted message with: header (individual vs team), task name, task kind, priority (plain text — no emojis), assigned-by name, assigned-to name(s), and a clickable task URL.
  7. For each recipient, attempts to resolve `telegram_chat_id` from the User record (always fails silently — field does not exist), then falls back to a hardcoded `USER_CHAT_MAP` (contains only 1 entry: `levonaghinyan77@gmail.com`).
  8. Sends via `frappe.make_post_request` to Telegram Bot API. Errors are logged to Error Log.

**Hardcoded values**:
- Task URL: `https://test.erpnext.am/app/task/{task_name}` (test environment URL)
- `USER_CHAT_MAP`: 1 entry only
- 9 team placeholder addresses
- 4 excluded roles
- 2 excluded system users

#### 2. Telegram Task Status Update

- **Type**: DocType Event on **Task**, fires **After Save**
- **Status**: Enabled
- **Created**: 2026-07-29 | **Last modified**: 2026-08-06
- **Lines**: 95
- **What it does**:
  1. Only runs on updates (not initial creation) — checks `get_doc_before_save()`.
  2. Only fires when the `status` field changed to one of: `Working`, `Completed`, `Cancelled`.
  3. Determines the notification recipient: looks up the most recent ToDo for this Task to find the `assigned_by` user. Falls back to `doc.owner` if no ToDo exists.
  4. Prevents self-notifications: skips if the status updater is the same user as the assigner.
  5. Reads bot token from `Telegram Settings` (same approach as script 1).
  6. Resolves the assigner's Telegram chat ID: tries `telegram_chat_id` from User record (always fails silently), then falls back to `USER_CHAT_MAP` (contains 8 entries — all team members).
  7. Constructs a Markdown message with emoji status indicators, task name, status, updater name, and a clickable task URL.
  8. Sends via Telegram Bot API. Errors logged to Error Log.

**Hardcoded values**:
- Base URL: `https://test.erpnext.am` (test environment URL)
- `USER_CHAT_MAP`: 8 entries (levonaghinyan77, sahakyan.oli1998, vagramyankaren, ly.aghayan, karapetyansev, artursemerjyan91, m.nersisyan93, artakn7)

### Two Custom DocTypes

#### 1. Telegram Settings (singleton)

- **Module**: Integrations
- **Fields**: 1 — `bot_token` (Password type)
- **Permissions**: System Manager only (read, write, create, delete, share, print, email)
- **Used by**: Both scripts — they read the bot token from here
- **Status**: Actively used

#### 2. Telegram Notification User

- **Module**: Core
- **Fields**: 2 — `erp_user` (Link to User, unique) and `chat_id` (Data)
- **Naming rule**: By fieldname (`erp_user`)
- **Permissions**: System Manager only
- **Used by**: **Nothing** — neither script queries this DocType
- **Status**: Dead infrastructure — created 2026-07-22 but never wired into any script

### Five Notification Records

| Name | Event | DocType | Channel | Enabled | Origin | Relevant? |
|---|---|---|---|---|---|---|
| **DATUREX Task Push** | New | Task | System Notification | **Yes** | Custom (created 2026-07-06 by `levonaghinyan77@gmail.com`, modified by `ai-agent@internal.com`) | **Yes — fires in parallel with Telegram** |
| **Error Log** | New | Error Log | Email | **No** | Custom | Partially — monitors Telegram errors |
| **Integration Request** | Save (on Failed) | Integration Request | Email | **No** | Custom | No |
| Notification for new fiscal year | New | Fiscal Year | Email | Yes | Standard ERPNext | No |
| Material Request Receipt Notification | Value Change | Material Request | Email | Yes | Standard ERPNext | No |

**DATUREX Task Push details**:
- Fires on every new Task creation
- Sends a System Notification (in-app notification bell icon) to:
  - Recipient 1: The user in `custom_assigned_to` field
  - Recipient 2: The role in `custom_team_queue_role` field (if set)
- Message: `"Task {{ doc.name }} ({{ doc.task_kind }}) has been created and needs attention."`
- Named after the DATUREX Connect mobile app that was evaluated but not adopted; repurposed as a generic system notification

### No Custom Fields Related to Telegram

The custom fields schema contains no `telegram_chat_id` or similar field on the User DocType or any other DocType. The scripts reference `frappe.db.get_value("User", user_email, "telegram_chat_id")` but this field does not exist.

---

## What Documentation Says

### Numbered Documentation

**No numbered doc (02–17) mentions Telegram, Telegram Bot, chat IDs, or any push/mobile notification system.** The requirements document (`requirements.md`) mentions "alerts" only in the context of debt threshold director alerts (implemented as Task-based automation, not Telegram).

### Evaluation/Plan Documents

Two docs discuss notifications but describe a different approach that was never implemented:

1. **`mobile-app-comparison.md`** (Jul 2026) — Evaluates 6 mobile apps for push notifications. Recommends **DATUREX Connect** as the best fit, with **email notifications** as the immediate short-term solution. Does not mention Telegram as an option.

2. **`push-notifications-plan.md`** (Jul 2026) — Detailed 6-phase plan for Firebase push notifications via `frappe_notifier`. Never executed. Does not mention Telegram.

**Neither document records the decision to use Telegram instead, or explains when/why the approach changed.**

### Deployment/Packing Documents

- `dispatch-packing-enhancements-plan.md` mentions that the system "does not yet send external phone/email notifications" for packing events (line 100). This is accurate — the Telegram scripts only cover task assignment and status changes, not packing alerts.
- `DEPLOYMENT-SUMMARY-2026-06-17.md` does not mention Telegram.

### Recovery/Patch Files

Several files in `deploy/test/readonly-recovery/` and `deploy/prod/scripts/` document Telegram-related operational incidents:

- `telegram-task-assignment-versions.json` — Shows version history of the assignment script with multiple iterations
- `telegram-user-chat-map-recovered.json` — Recovered chat ID mapping from an older version of the script (8 users + 3 commented-out placeholders)
- `telegram-task-assignment-current.py` — An earlier version of the assignment script (132 lines) that uses a different team resolution approach (resolves ALL roles of the assignee user, not just team placeholders)
- `patch_telegram_task_url_constant_prod.sh` / `_v2.sh` — Prod patches to fix the hardcoded URL
- `verify_telegram_task_url_constants.sh` — Verification script to check both environments have correct URLs

---

## Findings

### F-001 — Hardcoded test environment URL in both scripts
**Type**: BUG | **Severity**: HIGH | **Confidence**: 100% (for test), NEEDS VERIFICATION (for prod)

Both extracted scripts contain `https://test.erpnext.am` as the task URL base:
- Assignment script, line 111: `task_url = f"https://test.erpnext.am/app/task/{task_name}"`
- Status update script, line 75: `base_url = "https://test.erpnext.am"`

These scripts were extracted from the test environment, so having test URLs is expected for test. However, the existence of production patch scripts (`patch_telegram_task_url_constant_prod.sh`, `_v2.sh`) indicates this was a real production bug that was patched at least twice.

**Concern**: We cannot verify from static analysis alone whether the production scripts currently have the correct `https://erpnext.am` URL. The `verify_telegram_task_url_constants.sh` script exists to check this, but we don't know if it was run after the last modification (2026-08-24).

**Recommendation**: Run `verify_telegram_task_url_constants.sh` against production to confirm. If URLs are wrong, users clicking the link in Telegram get sent to the test instance instead of production.

---

### F-002 — Assignment script can only notify 1 person via Telegram (chat ID mapping gap)
**Type**: BUG | **Severity**: HIGH | **Confidence**: 100%

The assignment script's `USER_CHAT_MAP` contains only 1 entry:
```python
USER_CHAT_MAP = {
    "levonaghinyan77@gmail.com": "1908277721",
    # Add other team member email: chat_id pairs here
}
```

Meanwhile the status update script has all 8 team members mapped. The `telegram_chat_id` field on User does not exist (see F-003), so the fallback map is the **only** source of chat IDs.

**Result**: When a task is assigned to anyone other than `levonaghinyan77@gmail.com`, the assignment notification is silently lost. The status update notification works for all 8 mapped users.

**Recovery evidence**: The file `telegram-user-chat-map-recovered.json` shows that all 8 chat IDs were present in an earlier version of the assignment script. They were lost during a code restructuring (likely the 2026-08-24 modification that added the TEAM_PLACEHOLDERS logic).

**Recommendation**: Restore the full 8-user `USER_CHAT_MAP` in the assignment script, or better, migrate to using the `Telegram Notification User` DocType.

---

### F-003 — `telegram_chat_id` field does not exist on User DocType
**Type**: BUG | **Severity**: MEDIUM | **Confidence**: 100%

Both scripts contain:
```python
try:
    user_chat_id = frappe.db.get_value("User", user_email, "telegram_chat_id")
except Exception:
    pass
```

The custom fields schema has been fully exported and contains no `telegram_chat_id` field on any DocType. This means:
- Every call to `frappe.db.get_value("User", ..., "telegram_chat_id")` throws an exception
- The exception is silently swallowed by the `except Exception: pass` block
- Execution always falls through to `USER_CHAT_MAP`

This is not a crash bug (the code handles it), but it is a design intent that was never completed. The code was written expecting the field to be added later.

**Recommendation**: Either add a `telegram_chat_id` custom field to the User DocType and populate it for all team members, or remove the dead code path and use the `Telegram Notification User` DocType instead.

---

### F-004 — `Telegram Notification User` DocType is unused dead infrastructure
**Type**: DEAD-CODE | **Severity**: MEDIUM | **Confidence**: 100%

The `Telegram Notification User` DocType was created on 2026-07-22 with two fields:
- `erp_user` (Link to User, unique)
- `chat_id` (Data)

This is exactly the right design for managing user-to-chat-ID mappings dynamically instead of hardcoding them. However:
- Neither Telegram script queries this DocType
- No other script or report references it
- No documentation describes how to use it

It appears this was created as part of the original Telegram integration plan but the scripts were written with hardcoded maps instead, and the DocType was never connected.

**Recommendation**: Wire the scripts to query `Telegram Notification User` for chat IDs instead of hardcoded `USER_CHAT_MAP`. Remove the `USER_CHAT_MAP` entirely. Document the procedure for adding new team members to `Telegram Notification User`.

---

### F-005 — Three parallel notification channels fire on task assignment
**Type**: RISK | **Severity**: MEDIUM | **Confidence**: 100%

When a new Task is created and assigned, up to three notification mechanisms fire simultaneously:

1. **Telegram Bot message** — from `Telegram Task Assignment Notification` server script (via ToDo After Insert)
2. **DATUREX Task Push system notification** — from the `DATUREX Task Push` Notification record (in-app bell icon, triggered on Task New event)
3. **Standard ERPNext email** — if an email notification rule exists for Task assignment (not verified from static analysis)

Channel 1 and 2 are confirmed active from the schema. Whether this is intentional or accidental overlap is unknown — no documentation records the decision.

The DATUREX notification sends to `custom_assigned_to` and `custom_team_queue_role`. The Telegram script sends to `doc.allocated_to` on the ToDo. These are different fields and may resolve to different users, resulting in asymmetric notification delivery.

**Recommendation**: Document the intended notification strategy. If both channels are intentional (Telegram for external push, system notification for in-app), document it. If only one is needed, disable the other.

---

### F-006 — Priority emojis were intentionally removed from assignment script but name is misleading
**Type**: ENHANCEMENT | **Severity**: LOW | **Confidence**: 100%

The assignment script has:
```python
priority_emojis = {
    "Low": "Low",
    "Medium": "Medium",
    "High": "High",
    "Urgent": "Urgent"
}
```

The variable is named `priority_emojis` but maps to plain text. The version history shows emojis were present in earlier versions (e.g. `"🟢 Low"`, `"🔴 High"`, `"🚨 Urgent"`). The status update script still uses emojis.

This is cosmetic but the misleading variable name should be cleaned up.

---

### F-007 — Team placeholder resolution depends on fragile role-assignment structure
**Type**: RISK | **Severity**: MEDIUM | **Confidence**: 95%

The assignment script resolves team placeholder users (like `inventory.team@example.com`) by:
1. Looking up the roles of that placeholder user
2. Finding all real users who share any of those roles (excluding System Manager, All, Guest, Employee)
3. Sending Telegram messages to all of them

This logic depends on:
- Each placeholder user having exactly the right operational roles assigned
- No placeholder user having extra roles that would cause over-broadcasting
- The excluded roles list being maintained if new generic roles are added

If a placeholder user gains an extra operational role, unrelated team members could start receiving notifications. If a role is removed, legitimate team members would stop receiving notifications.

**Cannot verify from static analysis** whether the placeholder users currently have correct role assignments. Requires live environment check.

**Recommendation**: Consider using the `Telegram Notification User` DocType with explicit user-to-chat-ID mappings instead of indirect role resolution. Or at minimum, document the required role assignments for each placeholder user.

---

### F-008 — Status update script only notifies the assigner, not all team members
**Type**: RISK | **Severity**: LOW | **Confidence**: 100%

The status update script sends to exactly one person: the assigner (from the most recent ToDo's `assigned_by`, or the task owner). It does not notify:
- Other team members who may be monitoring the task
- Directors who may have escalated or created the task
- The team placeholder role if it was a team task

This may be intentional (to avoid notification spam), but it means that if a director creates a task and the assignee completes it, only the director gets the Telegram update. Other stakeholders don't.

---

### F-009 — No retry mechanism for failed Telegram API calls
**Type**: RISK | **Severity**: LOW | **Confidence**: 100%

Both scripts wrap the Telegram API call in:
```python
try:
    frappe.make_post_request(url, json=payload)
except Exception as e:
    frappe.log_error(...)
```

If the Telegram API is temporarily unavailable (network issue, rate limit, server error), the notification is permanently lost. There is no queuing, retry, or deferred delivery mechanism.

**Note**: The scripts also have `enable_rate_limit: 0` in the schema, so during bulk task creation, many rapid API calls could trigger Telegram's own rate limiting (max ~30 messages/second to different chats).

**Recommendation**: For a low-volume team (8 users), this is unlikely to be a practical problem. If task creation volume grows, consider adding background queueing.

---

### F-010 — No documentation exists for the entire Telegram notification system
**Type**: DOC-MISSING | **Severity**: HIGH | **Confidence**: 100%

The following aspects of the Telegram integration are completely undocumented:

| Aspect | Status |
|---|---|
| Decision to use Telegram instead of DATUREX/Firebase | Not documented |
| Bot name, creation, and token management | Not documented |
| Which events trigger notifications | Not documented |
| Who receives notifications and how recipients are resolved | Not documented |
| How to add/remove a team member from Telegram notifications | Not documented |
| How to change the chat ID for a user | Not documented |
| What happens when the bot token expires or changes | Not documented |
| Known limitation: assignment notifications work for 1 user only | Not documented |
| Known limitation: `Telegram Notification User` DocType is unused | Not documented |
| Relationship between DATUREX system notification and Telegram | Not documented |

The evaluation docs (`mobile-app-comparison.md` and `push-notifications-plan.md`) describe approaches that were **not** implemented. They are now stale and potentially misleading.

**Recommendation**: Create a numbered or titled operational doc covering: architecture, decision rationale, user management procedure, troubleshooting, and limitations. Mark `push-notifications-plan.md` as superseded.

---

### F-011 — `push-notifications-plan.md` is stale and misleading
**Type**: DOC-STALE | **Severity**: MEDIUM | **Confidence**: 100%

This document describes a detailed 6-phase plan for Firebase push notifications via `frappe_notifier`. It was never executed. The actual implementation uses direct Telegram Bot API calls, which is a completely different architecture.

The document also references the wrong mobile app (`ERPNext Workflow` by Midocean), which the companion document (`mobile-app-comparison.md`) already identified as "wrong for this requirement."

Both documents remain in the `docs/` folder without any "superseded" or "not implemented" marker.

---

### F-012 — DATUREX Task Push notification name is misleading
**Type**: ENHANCEMENT | **Severity**: LOW | **Confidence**: 100%

The notification is named "DATUREX Task Push" but has nothing to do with the DATUREX Connect mobile app. It is a standard ERPNext System Notification that shows a bell icon notification in the web UI. It was likely created during the DATUREX evaluation on 2026-07-06 and then kept active when Telegram was chosen instead.

The name should be updated to something like "Task Assignment System Notification" to avoid confusion.

---

### F-013 — Error Log and Integration Request notifications are disabled
**Type**: RISK | **Severity**: LOW | **Confidence**: 100%

Two operational monitoring notifications are disabled:
- **Error Log** (email notification to System Manager on new errors) — disabled
- **Integration Request** (email notification to System Manager on failed integrations) — disabled

When the Telegram scripts fail (F-009), they log to Error Log. But since the Error Log notification is disabled, these failures are not surfaced to administrators unless they manually check the Error Log list.

**Recommendation**: Consider enabling the Error Log notification so Telegram failures (and other system errors) are emailed to administrators.

---

## Correction to the Audit Plan

The original audit plan (`production-audit-plan.md`) contained incorrect notification status information. The correct status is:

| Notification | Plan said | Actual |
|---|---|---|
| DATUREX Task Push | DISABLED | **ENABLED** |
| Error Log | Enabled | **DISABLED** |
| Integration Request | Enabled | **DISABLED** |

---

## Cross-Group Dependencies

| Finding | Related Group | What to check |
|---|---|---|
| F-005 (parallel notifications) | Group 2 (Task System) | The `DATUREX Task Push` notification fires on Task creation. Group 2 should verify whether task creation scripts (e.g. `Task-after-save-dispatch-flow.py`) trigger this notification and what the user experience is. |
| F-001 (hardcoded URL) | All groups | If production scripts have incorrect URLs, this affects all Telegram-linked workflows. Requires live verification. |
| F-007 (team placeholders) | Group 2 (Task System) | Team placeholder users (`*.team@example.com`) are also referenced in `dispatch_task_accept.py` and team queue logic. Role assignments need to be verified holistically. |

---

## Remediation Priority

| Priority | Finding | Action |
|---|---|---|
| 1 (urgent) | F-002 | Restore full USER_CHAT_MAP in assignment script so all team members receive assignment notifications |
| 2 (urgent) | F-001 | Verify production scripts have `https://erpnext.am` URLs |
| 3 (high) | F-010 | Write Telegram integration documentation |
| 4 (high) | F-004 + F-003 | Wire scripts to use `Telegram Notification User` DocType or add `telegram_chat_id` custom field to User |
| 5 (medium) | F-005 | Document the intended multi-channel notification strategy |
| 6 (medium) | F-011 | Mark `push-notifications-plan.md` as superseded |
| 7 (low) | F-012 | Rename DATUREX notification |
| 8 (low) | F-013 | Enable Error Log notification |
| 9 (low) | F-009 | Evaluate retry mechanism need |
