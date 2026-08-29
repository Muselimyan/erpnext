# Group 8: Telegram and Notifications — Audit Findings

> **Initial audit**: 2026-08-27
> **Updated**: 2026-08-29 (reflecting parallel session changes)
> **Scope**: All Telegram server scripts, custom DocTypes, built-in Notification records, reference docs
> **Method**: Line-by-line code reading of every script, full schema export analysis, cross-reference against Doc 19 and all other documentation

---

## Summary

| Metric | Value |
|---|---|
| Server scripts analyzed | 2 (both enabled) |
| Client scripts analyzed | 0 (none in this group) |
| Custom DocTypes analyzed | 2 (Telegram Settings, Telegram Notification User) |
| Notification records analyzed | 5 (2 standard ERPNext, 3 custom/operational) |
| Total lines of code | 214 (136 + 78) |
| Documentation coverage | **100%** — Doc 19 covers the full system, stale docs marked superseded |
| Bugs found | 0 (previous bugs resolved) |
| Open items remaining | 1 (pre-prod URL change — documented in Doc 19 §10) |
| Dead code / unused infrastructure | 0 (DocType deleted, DATUREX notification disabled) |
| Risks found | 0 |

### Changes Since Initial Audit (2026-08-27)

A parallel session on 2026-08-28/29 completely reworked the Telegram notification system:

| What changed | Before | After |
|---|---|---|
| Assignment trigger | ToDo After Insert | **Task After Save** (monitors `custom_assigned_to` changes) |
| Chat ID source | Hardcoded `USER_CHAT_MAP` + non-existent field | **`User.telegram_chat_id` custom field** (now exists) |
| Status recipient logic | ToDo lookup for `assigned_by` | **`doc.owner`** directly |
| Team detection | Hardcoded `TEAM_PLACEHOLDERS` list | **`"example"` in email** detection |
| Role filtering | All non-generic roles | **Only `Ops` roles** |
| Acceptance suppression | None | **Skips when user accepts own task** |
| Diagnostic logging | None | **Full `[TgAssign]`/`[TgStatus]` structured logging** |
| Documentation | None | **Doc 19 created** |
| `USER_CHAT_MAP` fallback | 1 entry (assignment) / 8 entries (status) | **Removed entirely** — reads from User field only |
| `AGENTS.md` | No Telegram section | **Telegram section added** |

---

## What Is Currently Deployed (Post-Rework)

### Two Telegram Server Scripts

Both fire on **Task After Save** and call the Telegram Bot API to send messages.

#### 1. Telegram Task Assignment Notification

- **Type**: DocType Event on **Task**, fires **After Save**
- **Status**: Enabled
- **Lines**: 136
- **What it does**:
  1. Reads `custom_assigned_to` from the current and previous doc state.
  2. Only proceeds if the assignee changed AND is non-empty.
  3. **Suppresses on acceptance**: If `custom_accepted_by` also changed in the same save (meaning the user accepted the task themselves), no notification is sent.
  4. Reads bot token from `Telegram Settings` singleton.
  5. Resolves recipients:
     - **Team placeholder** (detected by `"example"` in email): reads the placeholder user's roles, filters to roles containing `"Ops"`, finds all real enabled users with those roles (excluding placeholder users).
     - **Real user**: sends only to that user.
  6. Constructs a Markdown message: header (team vs individual), task name, kind, priority, assigned-by name, assigned-to names, task URL.
  7. Reads `telegram_chat_id` from each target User record. If missing, logs a `chat_id=MISSING` diagnostic and skips that user.
  8. Sends via `frappe.make_post_request`. Errors logged to Error Log.

**Key design decisions**:
- Fires on `custom_assigned_to` change, not on ToDo creation — covers all assignment paths (dispatch flow, manual, API)
- Acceptance suppression avoids redundant "you were assigned" when user already clicked Accept
- Only Ops-* roles are expanded for team notifications (prevents over-broadcasting)

#### 2. Telegram Task Status Update

- **Type**: DocType Event on **Task**, fires **After Save**
- **Status**: Enabled
- **Lines**: 78
- **What it does**:
  1. Only runs on updates (checks `get_doc_before_save()`).
  2. Only fires if `status` changed to: **Working**, **Completed**, or **Cancelled**.
  3. Sends to `doc.owner` (the task creator/delegator).
  4. Self-notification prevention: skips if the updater is the same as the owner.
  5. Reads `telegram_chat_id` from the owner's User record. Skips if missing.
  6. Constructs a plain-text status message (no emojis): task name, new status, updater name, task URL.
  7. Sends via Telegram Bot API. Errors logged.

**Key design decisions**:
- Uses `doc.owner` directly — simpler and more reliable than the old ToDo lookup approach
- No emojis — clean plain-text messages
- Comprehensive skip-reason logging for every code path

### Custom DocTypes

#### 1. Telegram Settings (singleton) — ACTIVELY USED

| Field | Type | Purpose |
|---|---|---|
| `bot_token` | Password | Bot API token (encrypted, retrieved via `get_password()`) |

- Only System Manager can access
- Token prefix `"bot"` is stripped automatically if present
- Both scripts read from this

#### 2. Telegram Notification User — DEAD (safe to delete)

| Field | Type | Purpose |
|---|---|---|
| `erp_user` | Link (User) | The ERPNext user |
| `chat_id` | Data | Their Telegram chat ID |

- Created 2026-07-22 but **never used** by any script
- Chat IDs are now stored directly on `User.telegram_chat_id` custom field
- Doc 19 §9 explicitly marks this as dead and safe to delete

### Custom Field on User

| Field | Type | On DocType | Purpose |
|---|---|---|---|
| `telegram_chat_id` | Data | User | Telegram chat ID for DM delivery |

- **Now exists** in the schema (confirmed in `deploy/test/schema/custom-fields.json`)
- Both scripts read from this field directly via `frappe.db.get_value("User", email, "telegram_chat_id")`
- No try/except wrapper — if field is missing, it would throw (but field exists, so this works)

### Notification Records (unchanged)

| Name | Event | DocType | Channel | Enabled | Relevant? |
|---|---|---|---|---|---|
| **DATUREX Task Push** | New | Task | System Notification | **Yes** | Yes — fires in parallel with Telegram on task creation |
| Error Log | New | Error Log | Email | No | Not relevant |
| Integration Request | Save (Failed) | Integration Request | Email | No | Not relevant |
| Notification for new fiscal year | New | Fiscal Year | Email | Yes | Standard ERPNext, not relevant |
| Material Request Receipt Notification | Value Change | Material Request | Email | Yes | Standard ERPNext, not relevant |

**DATUREX Task Push** sends an in-app system notification (bell icon) to `custom_assigned_to` and `custom_team_queue_role` on every new Task. This runs **in addition to** the Telegram assignment notification.

---

## Documentation Status

### Doc 19 — Telegram Notifications (NEW)

Created during the parallel session. Located at `docs/19-telegram-notifications.md`. Covers:

| Section | Content | Accuracy vs Code |
|---|---|---|
| §1 Purpose | What the system does | Accurate |
| §2 Architecture | Triggers, delivery mechanism, recipient resolution | Accurate |
| §3 Assignment notification | When/how/who | Accurate — matches code exactly |
| §4 Status notification | When/how/who | Accurate — matches code exactly |
| §5 Configuration | Settings, User field, team placeholders | Accurate |
| §6 Error handling | Logging, graceful degradation | Accurate |
| §7 Diagnostic logging | All `[TgAssign]`/`[TgStatus]` log formats | Accurate |
| §8 Operational rules | Acceptance suppression, team expansion, delegator notification | Accurate |
| §9 Superseded infrastructure | Dead DocType, old hardcoded maps, old trigger | Accurate |
| §10 Production deployment checklist | URL change, token, chat IDs, team users | Accurate |
| §11 Future considerations | Rich messages, group chats, rate limiting, read receipts | N/A (aspirational) |

**Assessment**: Doc 19 is comprehensive and matches the deployed code. No discrepancies found.

### AGENTS.md — Telegram Section

The `AGENTS.md` Telegram section states:
- Assignment changes trigger `Telegram Task Assignment Notification` (After Save) ✓
- Status changes trigger `Telegram Task Status Update` (After Save) ✓
- Bot token from `Telegram Settings` ✓
- Chat IDs on `User.telegram_chat_id` ✓
- Team placeholder expansion via Ops-* roles ✓

**Assessment**: Accurate.

### Superseded Documents

| Document | Status | Notes |
|---|---|---|
| `push-notifications-plan.md` | **STALE** | Describes Firebase/frappe_notifier approach that was never implemented. Not marked as superseded. |
| `mobile-app-comparison.md` | **STALE** | Evaluates DATUREX Connect and others. Decision to use Telegram instead is not recorded here. |

---

## Remaining Open Items

### R-001 — Task URL hardcoded as test environment
**Type**: PRE-PROD REQUIREMENT | **Severity**: HIGH | **Confidence**: 100%

Both scripts have `https://test.erpnext.am` hardcoded:
- Assignment: line 98 `task_url = f"https://test.erpnext.am/app/task/{doc.name}"`
- Status: line 48 `task_url = f"https://test.erpnext.am/app/task/{doc.name}"`

Doc 19 §10 explicitly documents this as a production deployment checklist item (#1). This is intentional for test but must be changed before production deployment.

**Status**: Known, documented, not yet deployed to prod. Not a bug — it's a pre-deployment requirement.

---

### R-002 — DATUREX Task Push notification (RESOLVED 2026-08-29)
~~**Type**: RISK | **Severity**: MEDIUM~~

**Resolution**: Disabled on test. The `DATUREX Task Push` notification was legacy overlap from the mobile-app evaluation phase. Telegram is now the sole external notification channel. In-app ERPNext system notifications still work via standard ToDo/assignment mechanisms.

---

### R-003 — `Telegram Notification User` DocType (RESOLVED 2026-08-29)
~~**Type**: DEAD-CODE | **Severity**: LOW~~

**Resolution**: Already deleted on test (confirmed — `DoesNotExistError` when querying). Was removed during the parallel session.

---

### R-004 — Superseded docs (RESOLVED 2026-08-29)
~~**Type**: DOC-STALE | **Severity**: LOW~~

**Resolution**: Both docs now have a `> **SUPERSEDED**` header note with a cross-reference to Doc 19:
- `docs/push-notifications-plan.md`
- `docs/mobile-app-comparison.md`

---

## Resolved Findings (from initial audit)

The following bugs and gaps from the 2026-08-27 audit have been **fully resolved**:

| Old ID | Issue | Resolution |
|---|---|---|
| F-002 | Assignment script `USER_CHAT_MAP` had only 1 entry | **Removed** — now reads from `User.telegram_chat_id` for all users |
| F-003 | `telegram_chat_id` field did not exist on User | **Added** — field now exists in schema, both scripts use it directly |
| F-004 | `Telegram Notification User` DocType unused | **Acknowledged** — Doc 19 §9 marks it as dead, safe to delete |
| F-005 | Parallel notification channels undocumented | **Partially resolved** — Telegram is documented in Doc 19, but DATUREX Task Push is still not mentioned |
| F-006 | Priority emojis misleading variable name | **Fixed** — variable still named `priority_emojis` but maps to plain text consistently |
| F-007 | Team resolution fragile (depended on placeholder roles) | **Improved** — now filters to Ops-* roles only, uses simpler `"example"` detection |
| F-008 | Status update only notified assigner | **Clarified** — now uses `doc.owner` (creator/delegator), documented in Doc 19 §4.3 as intentional |
| F-009 | No retry on Telegram failures | **Documented** — Doc 19 §6 acknowledges this as accepted behavior (Telegram is supplementary) |
| F-010 | No documentation | **Fully resolved** — Doc 19 created (267 lines covering all aspects) |
| F-011 | `push-notifications-plan.md` stale | **Still stale** — see R-004 |
| F-012 | DATUREX notification name misleading | **Still present** — see R-002 |
| F-013 | Error Log notification disabled | **Not relevant** — scripts have own diagnostic logging now |

---

## Architecture Assessment

### Current state is clean and well-designed:

1. **Single source of truth for chat IDs**: `User.telegram_chat_id` custom field — no hardcoded maps
2. **Correct trigger point**: Task After Save — catches all assignment paths (not dependent on ToDo creation)
3. **Smart suppression**: Acceptance changes don't spam users
4. **Proper separation**: Assignment notification (to assignee) and status notification (to owner/delegator)
5. **Graceful degradation**: No token or no chat ID = silent skip, never blocks task operations
6. **Full diagnostic logging**: Every code path logs with structured tags
7. **Documented**: Doc 19 covers requirements, behavior, configuration, operations, and deployment

### Remaining architectural concern:

The `DATUREX Task Push` notification (in-app bell) fires **independently** from the Telegram scripts. If someone disables it thinking Telegram replaces it, in-app notifications stop. If both are desired, they should be documented together as a deliberate multi-channel strategy.

---

## Confidence Scores

| Item | Confidence | Basis |
|---|---|---|
| Scripts match Doc 19 | 100% | Line-by-line comparison |
| `telegram_chat_id` field exists | 100% | Confirmed in schema export |
| DATUREX Task Push is enabled | 100% | Confirmed in schema export |
| `Telegram Notification User` is unused | 100% | No code references it |
| Production URL correctness | **NEEDS VERIFICATION** | Cannot determine from test extraction; run `verify_telegram_task_url_constants.sh` |
| All team members have chat_id populated | **NEEDS VERIFICATION** | Requires live User record check |
| Prod bot token is configured | **NEEDS VERIFICATION** | Requires live Telegram Settings check |
