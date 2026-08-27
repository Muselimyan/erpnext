# Task Assignment UI — Unified Implementation Plan

## Agreed Design (Final)

### Core Concept: One Box For Assignment

Instead of separate "Assign To (User)" and "Assign To (Team/Role)" fields, we use **one Link-to-User field** that accepts both:
- **Real users** (e.g. `sahakyan.oli1998@gmail.com`)
- **Team placeholder users** (e.g. `inventory.team@example.com`)

Team placeholder users already exist in the system and represent team queues.

### Team Placeholder Users (existing)
| Email | Represents |
|-------|-----------|
| `order.team@example.com` | Ops - Order Accepting |
| `order.creation.team@example.com` | Ops - Order Creating |
| `inventory.team@example.com` | Ops - Inventory |
| `delivery.team@example.com` | Ops - Delivery |
| `returns.team@example.com` | Ops - Returns |
| `accounting.team@example.com` | Ops - Accounting |
| `finance.team@example.com` | Ops - Finance |
| `directors.team@example.com` | Ops - Directors |
| `purchasing.team@example.com` | Ops - Purchasing |
| `office.team@example.com` | Office Team |

---

## Fields

| Field | Type | Visible | Purpose |
|-------|------|---------|---------|
| `custom_assigned_to` | Link (User) | YES | "Assign To" — person OR team placeholder |
| `custom_next_task_assign_to` | Link (User) | Only for dispatch tasks | "Next Task: Assign To" — who gets the next auto-created task |
| `custom_team_queue_role` | Link (Role) | HIDDEN | Deprecated, kept for backward compat |
| `custom_next_task_assign_role` | — | NOT CREATED | Not needed (team placeholders are Users) |

---

## Behavior

### 1. Current Task Assignment
- User sees one clean field: **"Assign To"** (`custom_assigned_to`)
- Can select any real user or any team placeholder
- If a team placeholder is selected → task appears in that team's queue
- If a real user is selected → task is directly assigned to them

### 2. Accept / Start Task
- When a user clicks "Accept / Start Task":
  - `custom_assigned_to` = current user (replacing team placeholder)
  - `custom_accepted_by` = current user
  - `_assign` = [current user]
  - Status = "Working"
- After acceptance, the "Assign To" field still shows who it's assigned to (the acceptor)
- Reassignment IS allowed after acceptance (just change the field)

### 3. Next Task Assignment
- For tasks that auto-create a successor (dispatch workflow), show **"Next Task: Assign To"**
- If set, when the current task completes and auto-creates the next task, that next task will be assigned to the specified user/team
- If empty, the system uses the default team placeholder for that task kind

### 4. Task List Filtering
- Already works via `_assign` field (no changes needed)
- "My Tasks" = `_assign` contains current user
- "Open Tasks" = `_assign` contains a team placeholder that maps to user's role
- Backward compat: old tasks with `custom_team_queue_role` still visible via `_assign`

### 5. Notifications
- When `custom_assigned_to` changes → new ToDo created for the assignee
- If assignee is a team placeholder → ToDos sent to all users with that team's role
- This already works via `Task-team-queue-notify` server script

---

## Task Kinds That Auto-Create Next Tasks

| Current Task Kind | Creates Next | Default Assignee |
|---|---|---|
| Order entry | Pack / prepare items | `inventory.team@example.com` |
| Pack / prepare items | Delivery | `delivery.team@example.com` |
| Delivery (delivered) | Invoice preparation | `accounting.team@example.com` |
| Delivery (return expected) | Return Call | `office.team@example.com` |
| Return Call | Pickup Returns | driver or `delivery.team@example.com` |
| Pickup Returns (returned) | Returns processing | `returns.team@example.com` |
| Returns processing | Returns restocking + Invoice | `returns.team@example.com` / `accounting.team@example.com` |
| Discount Approval (approved) | Pack / prepare items | `inventory.team@example.com` |

---

## Implementation Changes

### Script: `deploy-unified-assignment.ps1`

#### A. Custom Fields
1. Ensure `custom_next_task_assign_to` exists (Link to User, after `custom_assigned_to`)
2. Update `custom_assigned_to` label to "Assign To"
3. Update `custom_next_task_assign_to` label to "Next Task: Assign To"
4. Remove description text from all assignment fields

#### B. Client Script (`Task-Accept Start`)
1. Always hide `custom_team_queue_role` (deprecated)
2. Remove mutual exclusion logic between assigned_to and team_queue_role
3. Show `custom_next_task_assign_to` only for dispatch workflow task kinds
4. Hide `custom_next_task_assign_to` for non-dispatch tasks
5. After accept, show assignment as read-only info

#### C. Server Script (`dispatch_task_accept`)
1. Set `custom_assigned_to = frappe.session.user` when accepting

#### D. Server Script (`Task-after-save-dispatch-flow`)
1. Modify `make_task()` to accept `source_task` parameter
2. If source task has `custom_next_task_assign_to`, use it as the assignee
3. Always set `custom_assigned_to` on the new task to the chosen assignee
4. Pass `source_task=doc.name` in all `make_task()` calls

#### E. Server Script (new assignment sync in before_save)
1. When `custom_assigned_to` changes, sync to `_assign`
2. This ensures task list filtering stays consistent

---

## Deployment

```powershell
# Check current state (read-only)
.\deploy-unified-assignment.ps1 -Mode Check -Target test

# Deploy to test
.\deploy-unified-assignment.ps1 -Mode Deploy -Target test

# After verification, deploy to main (with approval)
.\deploy-unified-assignment.ps1 -Mode Deploy -Target main
```

---

## Testing Checklist (on test site)

- [ ] Open a Pack task → see "Assign To" field (one box)
- [ ] Can select a real user in "Assign To"
- [ ] Can select a team placeholder (e.g. inventory.team@example.com) in "Assign To"
- [ ] `custom_team_queue_role` is hidden
- [ ] "Next Task: Assign To" visible for Pack task (dispatch workflow)
- [ ] "Next Task: Assign To" hidden for Debt Collection (not dispatch)
- [ ] Accept task → `custom_assigned_to` becomes current user
- [ ] After accept, can manually reassign to different user
- [ ] Complete Order Entry with "Next Task: Assign To" = specific user → Pack task assigned to that user
- [ ] Complete Order Entry with "Next Task: Assign To" empty → Pack task assigned to default team
- [ ] Task list "My Tasks" filter shows tasks assigned to current user
- [ ] Task list "Open Tasks" filter shows team-available tasks

---

## Backward Compatibility

- Old tasks with `custom_team_queue_role` set: still visible in task list via `_assign`
- `Task-team-queue-notify` script still works (checks `_assign`)
- No bulk migration of old tasks needed
- New tasks use unified approach; old tasks updated when accepted/reassigned

---

## Risk Assessment

- **Medium risk**: touches server-side task creation routing
- **Mitigated by**: deploy to test first, comprehensive testing
- **Rollback**: revert client/server scripts to previous versions
- **No data loss**: only adding fields, not removing any
