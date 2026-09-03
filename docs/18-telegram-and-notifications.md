# 18 — Telegram and Task Notifications

## Purpose

Document the active task-notification behavior currently present in the ERPNext customizations. This replaces the earlier mobile-app/Firebase planning documents as the current implementation reference for task notifications.

## Current implementation

The active implementation uses two enabled ERPNext Server Scripts and one enabled ERPNext Notification record:

| Channel | Artifact | Trigger | Recipient model | Purpose |
|---|---|---|---|---|
| Telegram | `Telegram Task Assignment Notification` | `ToDo` After Insert, only when linked to `Task` | ToDo assignee, or real users resolved from a team placeholder user | External phone alert when a task is assigned |
| Telegram | `Telegram Task Status Update` | `Task` After Save, when status changes to `Working`, `Completed`, or `Cancelled` | Most recent task assigner, falling back to task owner | External phone alert that the assigned work started/finished/cancelled |
| ERPNext System Notification | `DATUREX Task Push` | `Task` New | `custom_assigned_to` and `custom_team_queue_role` | In-app bell notification for newly created tasks |

The Telegram scripts call the Telegram Bot API directly. The bot token is stored in the `Telegram Settings` singleton DocType as a Password field.

## Assignment notification behavior

`Telegram Task Assignment Notification` fires when a `ToDo` is inserted for a Task.

Behavior:
1. Ignore non-Task ToDos.
2. Skip duplicate ToDos for the same Task and allocated user.
3. Load the bot token from `Telegram Settings.bot_token`.
4. Load Task details for task kind and priority.
5. Resolve recipients:
   - If the ToDo assignee is a team placeholder user, collect real enabled users who share non-generic roles with that placeholder.
   - If the ToDo assignee is a real enabled user, notify that user only.
6. Build a Telegram Markdown message with task name, task kind, priority, assigning user, resolved assignees, and a Task link.
7. Resolve each recipient's chat ID from the User `telegram_chat_id` field if it exists; otherwise use the script's hardcoded fallback map.
8. Send one Telegram message per resolved recipient.

Team placeholder users currently recognized by the script are the operational placeholder emails ending in `.team@example.com`, including inventory, delivery, returns, accounting, finance, order creation/order, directors, and office placeholders.

## Status update notification behavior

`Telegram Task Status Update` fires when a Task status changes after initial creation.

Behavior:
1. Ignore initial Task creation.
2. Notify only when status changes to `Working`, `Completed`, or `Cancelled`.
3. Determine the assigner from the most recent Task ToDo's `assigned_by`; if no ToDo exists, use the Task owner.
4. Skip self-notifications when the updater is the same as the assigner.
5. Load the bot token from `Telegram Settings.bot_token`.
6. Resolve the assigner's chat ID from the User `telegram_chat_id` field if it exists; otherwise use the script's hardcoded fallback map.
7. Send a Telegram Markdown message containing the new status, updater, and Task link.

This intentionally notifies the assigner only. It does not notify every team member or every stakeholder unless they were the assigner.

## Chat ID storage and maintenance

Current state:
- `Telegram Settings` is active and stores the bot token.
- `Telegram Notification User` exists as a custom DocType with `erp_user` and `chat_id`, but the active scripts do not query it.
- No exported custom field named `telegram_chat_id` exists on User.
- Therefore, the scripts currently rely on hardcoded fallback maps for actual chat ID delivery.

Operational implication:
- Adding or changing a Telegram recipient currently requires a script change and deployment.
- The cleaner future direction is to wire both scripts to `Telegram Notification User` and remove hardcoded chat IDs from the scripts.

## Environment URL behavior

The local test extracted scripts use `https://test.erpnext.am` in Task links, which is expected for the test environment. The local prod schema export should use prod Task links. Any deployment or verification against live prod/test must follow the environment-safety procedure in `docs/infrastructure-test-vs-prod-environments.md` first.

## Error handling

Both Telegram scripts catch send failures and write an Error Log entry. They do not retry failed Telegram API calls. The built-in Error Log email Notification is currently disabled in the exported schema, so Telegram failures are not automatically emailed to administrators.

For the current low-volume use case this is acceptable, but administrators should periodically check Error Log after notification-related changes or enable an appropriate monitoring notification after confirming email behavior.

## Relationship to earlier notification documents

The following documents are historical planning/evaluation references, not the active implementation:
- `mobile-app-comparison.md` evaluated DATUREX Connect and other mobile apps.
- `push-notifications-plan.md` planned Firebase/`frappe_notifier` push notifications and was not implemented.

Current active task notifications are the direct Telegram Bot API scripts plus ERPNext's built-in system notification record described above.

## Open decisions

1. Should hardcoded chat IDs be replaced with `Telegram Notification User` records?
2. Should `DATUREX Task Push` be renamed to a generic in-app Task notification name?
3. Should the Error Log Notification be enabled so Telegram failures surface by email?
4. Should status updates notify only the assigner, or also a role/team/directors for some task kinds?
5. Should team placeholder recipient resolution remain role-based, or become explicit per-team configuration?
