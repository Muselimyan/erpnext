# Doc 19 — Telegram Notifications

## 1) Purpose
Define how the ERPNext task system sends real-time notifications to team members via Telegram:
- When notifications are sent.
- Who receives them.
- What information is included.
- How the system resolves recipients (individual users vs team placeholders).
- Configuration and credential management.

This doc describes **requirements, rules, and current behavior**. Script-level implementation details are in `deploy/test/work/server/`.

---

## 2) Architecture overview

### 2.1 Notification triggers

Two distinct notification types exist:

| Trigger | Event | Script | Fires when... |
|---|---|---|---|
| **Assignment notification** | Task After Save | `Telegram Task Assignment Notification.py` | `custom_assigned_to` changes to a new value |
| **Status notification** | Task After Save | `Telegram Task Status Update.py` | `status` changes to Working, Completed, or Cancelled |

Both scripts fire on the Task DocType's After Save event.

### 2.2 Delivery mechanism

- Messages are sent via the **Telegram Bot API** (`https://api.telegram.org/bot{token}/sendMessage`).
- The bot token is stored in the `Telegram Settings` singleton DocType (Password field, retrieved via `get_password()`).
- Messages use Markdown formatting (`parse_mode: "Markdown"`).
- HTTP calls use `frappe.make_post_request()`.
- Failures are logged to Frappe's Error Log and printed with `[TgAssign]`/`[TgStatus]` diagnostic tags.

### 2.3 Recipient resolution

Each user's Telegram chat ID is stored as a custom field on the User DocType:
- Field: `telegram_chat_id` (Data type, on User)
- If a user has no `telegram_chat_id` set, they will not receive Telegram notifications (silently skipped).

---

## 3) Assignment notification

### 3.1 When it fires

The assignment notification fires when:
- A task is saved (created or updated).
- `custom_assigned_to` has changed (new value differs from previous value).
- The new assignee is not empty.

### 3.2 When it does NOT fire

- **On acceptance**: If the assignment change is due to the user accepting the task (i.e., `custom_accepted_by` also changed in the same save), the notification is suppressed. Rationale: the user who accepted already knows about the task — notifying them is redundant.
- **No assignee**: If `custom_assigned_to` is empty or unchanged.
- **No bot token**: If `Telegram Settings` has no bot token configured.

### 3.3 Recipient resolution (team expansion)

When the assignee is a **team placeholder** (identified by `"example"` in the email address, e.g. `delivery.team@example.com`):
1. The script reads the Ops-* roles assigned to the placeholder user.
2. For each Ops role found, it finds all real (enabled, non-placeholder) users who have that role.
3. Each of those users receives the notification individually.

When the assignee is a **real user**:
- Only that user receives the notification.

Generic roles are excluded from team expansion: `System Manager`, `All`, `Guest`, `Employee`, `Stock User`, `Sales User`, `Purchase User`, `Accounts User`, `Item Manager`.

### 3.4 Message format

```
New Team Task Assigned!          (or "New Task Assigned!" for individual)

*Task:* TASK-2026-00123
*Kind:* Delivery
*Priority:* High
*Assigned By:* Vahe Admin
*Assigned To (Team):* John, Jane, Mike    (or individual name)

Go To Task: https://test.erpnext.am/app/task/TASK-2026-00123
```

### 3.5 URL configuration

The task URL is currently hardcoded in the script:
- Test: `https://test.erpnext.am/app/task/{doc.name}`
- Production: Must be updated to `https://erpnext.am/app/task/{doc.name}` before production deployment.

---

## 4) Status notification

### 4.1 When it fires

The status notification fires when:
- A task is updated (not on initial creation).
- The `status` field changed.
- The new status is one of: **Working**, **Completed**, **Cancelled**.

### 4.2 When it does NOT fire

- **On creation**: Initial task creation does not trigger status notifications (even if status is set).
- **Self-notification**: If the user who changed the status is the same as the notification target (`doc.owner`), the notification is suppressed.
- **Non-milestone statuses**: Changes to `Open` or other statuses do not trigger notifications.
- **No bot token**: If `Telegram Settings` has no bot token configured.
- **No chat ID**: If the target user has no `telegram_chat_id` set.

### 4.3 Recipient

The notification is sent to the **task creator** (`doc.owner`) — the person who originally created or delegated the task. This is a single user (not team-expanded).

Rationale: The task creator/delegator wants to know when their delegated work is being started, completed, or cancelled.

### 4.4 Message format

```
Task Status Updated!

*Task:* TASK-2026-00123
*New Status:* Completed
*Updated By:* John Driver

View Task: https://test.erpnext.am/app/task/TASK-2026-00123
```

---

## 5) Configuration

### 5.1 Telegram Settings (singleton DocType)

| Field | Type | Purpose |
|---|---|---|
| `bot_token` | Password | Telegram Bot API token (stored encrypted) |

- Only System Manager can read/write.
- The token is retrieved via `get_password("bot_token")` to avoid plaintext exposure.
- If the token starts with `"bot"` (case-insensitive), the prefix is stripped (Telegram API expects the raw token without "bot" prefix in the URL).

### 5.2 User custom field

| Field | Type | On DocType | Purpose |
|---|---|---|---|
| `telegram_chat_id` | Data | User | The Telegram chat ID for sending DMs to this user |

- Each user who should receive notifications must have their `telegram_chat_id` populated.
- To find a user's chat ID: have them message the bot, then use the Telegram Bot API `getUpdates` endpoint to see the chat ID.
- Users without this field set simply don't receive Telegram notifications (no error, gracefully skipped).

### 5.3 Team placeholder users

Team placeholders are User records with emails like `*.team@example.com`. They serve as assignment targets for team-level task queues. Their roles determine which real users get notified.

Current team placeholders:
- `order.creation.team@example.com`
- `inventory.team@example.com`
- `delivery.team@example.com`
- `returns.team@example.com`
- `accounting.team@example.com`
- `finance.team@example.com`
- `directors.team@example.com`
- `office.team@example.com`

Each placeholder has Ops-* roles that match the real team members. When a task is assigned to a placeholder, the Telegram script expands it to all real users with those roles.

---

## 6) Error handling

- HTTP errors from the Telegram API are caught and logged to Frappe's Error Log (`frappe.log_error()`).
- Each send attempt is logged with `[TgAssign]` or `[TgStatus]` tags for troubleshooting.
- A failed send to one user does not prevent sends to other users in the same batch.
- Missing chat IDs are logged but do not produce error records.

---

## 7) Diagnostic logging

Both scripts emit structured logs using `print()`:

**Assignment script tags:**
```
[TgAssign] 2026-08-29 10:15:00 task=TASK-2026-00123 old=delivery.team@example.com new=john@company.com changed=True
[TgAssign] 2026-08-29 10:15:00 task=TASK-2026-00123 is_team=False target_users=1 users=['john@company.com']
[TgAssign] 2026-08-29 10:15:00 task=TASK-2026-00123 sent_to=john@company.com chat_id=yes
[TgAssign] 2026-08-29 10:15:00 task=TASK-2026-00123 SKIPPED: reason=acceptance
[TgAssign] 2026-08-29 10:15:00 task=TASK-2026-00123 SKIPPED: reason=no_assignee
[TgAssign] 2026-08-29 10:15:00 task=TASK-2026-00123 SKIPPED: reason=no_change
[TgAssign] 2026-08-29 10:15:00 task=TASK-2026-00123 SKIPPED: reason=no_token
[TgAssign] 2026-08-29 10:15:00 task=TASK-2026-00123 sent_to=john@company.com chat_id=MISSING
[TgAssign] 2026-08-29 10:15:00 task=TASK-2026-00123 FAILED: user=john@company.com error=...
```

**Status script tags:**
```
[TgStatus] 2026-08-29 10:15:00 task=TASK-2026-00123 sent_to=admin@company.com status=Completed
[TgStatus] 2026-08-29 10:15:00 task=TASK-2026-00123 SKIPPED: reason=self_notification user=admin@company.com
[TgStatus] 2026-08-29 10:15:00 task=TASK-2026-00123 SKIPPED: reason=no_chat_id user=admin@company.com
[TgStatus] 2026-08-29 10:15:00 task=TASK-2026-00123 SKIPPED: reason=no_token
[TgStatus] 2026-08-29 10:15:00 task=TASK-2026-00123 status=Open SKIPPED: reason=not_notifiable
[TgStatus] 2026-08-29 10:15:00 task=TASK-2026-00123 FAILED: user=admin@company.com error=...
```

---

## 8) Operational rules

### 8.1 No notification on acceptance
When a user accepts a task (Accept / Start button), the assignment changes from the team placeholder to the accepting user. This does NOT send a notification because:
- The accepting user already knows about the task (they just clicked Accept).
- Sending them a "you were assigned" message would be noise.

### 8.2 Team tasks notify all qualified members
When a new task is assigned to a team placeholder (e.g., via dispatch flow or manual creation):
- All real users who share the team's Ops-* role receive the notification.
- This ensures no task sits unnoticed in a team queue.

### 8.3 Status updates go to the delegator
When a task's status changes to Working/Completed/Cancelled:
- The task creator (delegator) is notified.
- The person who made the change is NOT notified (self-notification prevention).
- This gives managers/coordinators visibility into task progress without checking manually.

### 8.4 Graceful degradation
If Telegram is misconfigured (no token, no chat IDs):
- No errors are thrown to the user.
- Task operations proceed normally.
- Diagnostic logs record the skip reason.
- Telegram is strictly supplementary — it never blocks task workflows.

---

## 9) Superseded infrastructure

The following items existed before the current implementation and are now dead/unused:

| Item | Status | Notes |
|---|---|---|
| `Telegram Notification User` DocType | **Dead** | Created 2026-07-22 but never wired into any script. Chat IDs are now on the User record directly. Safe to delete. |
| Hardcoded `USER_CHAT_MAP` dictionaries | **Removed** | Both scripts previously had hardcoded email→chat_id maps. Now read from `User.telegram_chat_id`. |
| ToDo-based trigger (old assignment script) | **Removed** | The old assignment notification fired on `ToDo After Insert`. Now fires on `Task After Save` — covers all assignment paths (Quick Entry, manual, dispatch flow, accept API). |
| `Task-team-queue-notify.py` (disabled) | **Superseded** | Was supposed to notify on team queue entry. Replaced by the assignment notification which fires for all assignment changes including team assignments. |

---

## 10) Production deployment checklist

Before deploying Telegram notifications to production:

1. **Update task URL** in both scripts: change `test.erpnext.am` → `erpnext.am`.
2. **Verify bot token** is set in `Telegram Settings` on the production site.
3. **Populate `telegram_chat_id`** for all users who should receive notifications.
4. **Verify team placeholder users** exist and have correct Ops-* roles on production.
5. **Test with one user** before enabling for all (set only one user's chat_id, trigger a task assignment, verify message arrives).
6. **Delete `Telegram Notification User` DocType** on production (dead infrastructure, never used).

---

## 11) Future considerations

- **Rich messages**: Consider using Telegram's inline keyboard buttons for quick actions (e.g., "Accept Task" button in the message).
- **Group chats**: For team notifications, a Telegram group per team could reduce individual message volume.
- **Rate limiting**: Telegram has rate limits (~30 messages/second per bot). If task creation bursts happen (e.g., dispatch flow creating 5+ tasks simultaneously), messages may be delayed by Telegram's queue.
- **Read receipts**: Telegram does not provide read receipt callbacks. There is no way to know if a notification was seen.
- **Production URL**: Both scripts have the URL hardcoded. A future improvement could read it from `frappe.utils.get_url()` or a site configuration field.
