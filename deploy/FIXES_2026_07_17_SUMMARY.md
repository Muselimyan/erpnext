# ERPNext UI Fixes - July 17, 2026

## Overview

Five separate deployment scripts prepared to fix reported UI/workflow issues.  
All scripts support `-Mode Check` (read-only) and `-Mode Deploy` (apply changes).  
All scripts support `-Target test` (default) and `-Target main`.

**Deployment workflow:**
1. Deploy to **test** first
2. Verify each fix works
3. Deploy to **main** only after test verification

---

## Script 1: Complete Task Save-First

**File:** `fix-complete-task-save-first.ps1`  
**Risk:** Low  
**Changes:** Task-Accept Start client script

### Problem
When user clicks "Complete Task", if they haven't manually saved first, some field changes can be lost or validation doesn't run properly.

### Solution
Complete Task button now **always**:
1. Saves current field changes
2. If save succeeds, sets `status = Completed`
3. Saves again (triggers server validation/workflow)
4. Reloads form

If validation fails at any step, task stays open with error message.

### Testing
1. Open any task
2. Make a field change (don't save manually)
3. Click "Complete Task"
4. Verify: field change is saved AND task completes
5. Try completing a task that fails validation (e.g. missing required field)
6. Verify: validation error shows, task stays open

---

## Script 2: Task Subject Desktop Layout

**File:** `fix-task-subject-desktop-layout.ps1`  
**Risk:** Low  
**Changes:** Task-Header Long Subject Fix client script

### Problem
On desktop, long task subject text can push action buttons off-screen or make header very tall.

### Solution
- Clamps subject to **2 lines maximum** on desktop
- Keeps action buttons **fixed on the right**, always visible
- Shows **full subject as tooltip** on hover
- Prevents layout overflow

### Testing
1. Open a task with a very long subject (50+ chars)
2. Verify: subject shows only 2 lines with ellipsis
3. Hover over subject
4. Verify: tooltip shows full subject
5. Verify: action buttons stay visible on the right
6. Resize browser window
7. Verify: buttons never disappear

---

## Script 3: Mobile Task List Assignee

**File:** `add-task-list-mobile-assignee.ps1`  
**Risk:** Low  
**Changes:** Global-Mobile Back Button List client script

### Problem
On mobile Task list, user cannot see who the task is assigned to without opening each task.

### Solution
Adds assignee badge below task subject on mobile:
- **👤 Person name** (blue badge) - if assigned to specific user
- **👥 Team/Role name** (orange badge) - if assigned to team/role
- **⚪ Unassigned** (gray badge) - if no assignment

### Testing
1. Open Task list on mobile (or narrow browser to <768px)
2. Verify: each task row shows assignee badge
3. Check tasks assigned to:
   - Specific user → shows user email/name in blue
   - Team/role → shows role name in orange
   - Unassigned → shows "Unassigned" in gray
4. Verify: badge doesn't break layout
5. Open desktop Task list
6. Verify: no assignee badge on desktop (desktop already has columns)

---

## Script 4: Dispatch Case Item Selection Stability

**File:** `fix-dispatch-case-item-select.ps1`  
**Risk:** Low-Medium  
**Changes:** Dispatch Case-Products Button client script

### Problem
In Dispatch Case "Add Items by Category" dialog, first click on an item checkbox sometimes doesn't work - page seems to refresh/glitch.

### Solution
- Adds **300ms debounce** to item group onchange
- Prevents rapid HTML refreshes during selection
- Avoids dialog rerender while user is clicking

### Testing
1. Open any Dispatch Case
2. Click "Actions" → "Add Items by Category"
3. Select an Item Group
4. Wait for items to load
5. **Immediately** click first checkbox
6. Verify: checkbox selects on first click (no glitch)
7. Try selecting multiple items quickly
8. Verify: all clicks register properly
9. Change Item Group while items are loading
10. Verify: only final group loads (debounce works)

---

## Script 5: Unified Task Assignment with Next-Task Routing

**File:** `add-task-assignment-unified.ps1`  
**Risk:** **HIGH** - touches task routing/workflow  
**Changes:** 
- Custom Fields (2 new fields)
- Task-Accept Start client script
- Task-after-save-dispatch-flow server script

### Problem
1. Current assignment UI shows separate technical fields (`custom_assigned_to`, `custom_team_queue_role`)
2. No way to choose assignment for the next autocreated task in dispatch workflow

### Solution
**New Custom Fields:**
- `custom_next_task_assign_to` (Link to User)
- `custom_next_task_assign_role` (Link to Role)

**Client Script Changes:**
- Shows next-task assignment fields only for dispatch workflow tasks
- Clears opposite field when one is selected (user OR role, not both)

**Server Script Changes:**
- `make_task()` function now accepts `source_task` parameter
- Checks source task for `custom_next_task_assign_to` / `custom_next_task_assign_role`
- Uses specified assignment if present, otherwise uses default team
- All `make_task()` calls updated to pass `source_task=doc.name`

### Testing - CRITICAL
This is the most complex change. Test thoroughly:

1. **Current task assignment still works:**
   - Assign task to user → verify `_assign` updates
   - Assign task to role → verify team assignment works
   - Accept task → verify assignment changes to current user

2. **Next task assignment - user:**
   - Open Order Entry task
   - Set "Assign Next Task To (User)" = specific user
   - Complete Order Entry task
   - Verify: Pack task is created and assigned to that user

3. **Next task assignment - role:**
   - Open Pack task
   - Set "Assign Next Task To (Team/Role)" = specific role
   - Complete Pack task
   - Verify: Delivery task is created and assigned to that role

4. **Next task assignment - empty (default):**
   - Open Delivery task
   - Leave next-task fields empty
   - Complete Delivery task
   - Verify: next task uses default team (existing behavior)

5. **Field clearing:**
   - Set "Assign Next Task To (User)" = user1
   - Then set "Assign Next Task To (Team/Role)" = role1
   - Verify: user field clears automatically
   - Vice versa

6. **Non-dispatch tasks:**
   - Open a task that is NOT dispatch workflow
   - Verify: next-task fields are hidden

7. **Full dispatch workflow:**
   - Create Order Entry → Pack → Delivery → Invoice
   - At each step, assign next task to different user/role
   - Verify: each autocreated task has correct assignment

**If ANY test fails, DO NOT deploy to main.**

---

## Deployment Order (Recommended)

### On Test Site

1. **fix-complete-task-save-first.ps1**
   - Lowest risk, immediate value
   - Test: complete a task with unsaved changes

2. **fix-task-subject-desktop-layout.ps1**
   - Visual-only, low risk
   - Test: open task with long subject

3. **add-task-list-mobile-assignee.ps1**
   - UI-only, low risk
   - Test: view Task list on mobile

4. **fix-dispatch-case-item-select.ps1**
   - Behavior fix, medium risk
   - Test: add items to Dispatch Case

5. **add-task-assignment-unified.ps1**
   - **HIGHEST RISK** - do last
   - Test: full dispatch workflow with assignment routing

### After Test Verification

Run same scripts with `-Target main` in same order, **only after** each is verified working on test.

---

## Running Scripts

### Check mode (read-only):
```powershell
.\fix-complete-task-save-first.ps1 -Mode Check -Target test
```

### Deploy to test:
```powershell
.\fix-complete-task-save-first.ps1 -Mode Deploy -Target test
```

### Deploy to main (after test verification):
```powershell
.\fix-complete-task-save-first.ps1 -Mode Deploy -Target main
```

---

## Rollback Plan

If any script causes issues:

1. **Client Scripts:** Can be disabled via ERPNext UI:
   - Search for "Client Script"
   - Find the script name
   - Uncheck "Enabled"
   - Save

2. **Server Scripts:** Can be disabled via ERPNext UI:
   - Search for "Server Script"
   - Find the script name
   - Check "Disabled"
   - Save

3. **Custom Fields:** Can be hidden via ERPNext UI:
   - Search for "Custom Field"
   - Find field name
   - Check "Hidden"
   - Save

4. **Full rollback:** Re-run old version of script from git history

---

## Notes

- All scripts are idempotent (safe to run multiple times)
- All scripts check current state before making changes
- Main/test scripts are identical in content (SHA verified)
- PowerShell lint warning about "Upsert-ErpDoc" verb is cosmetic, safe to ignore
- Scripts use same API credentials from `export.ps1`

---

## Status

- [x] Scripts prepared locally
- [ ] Reviewed with user
- [ ] Deployed to test
- [ ] Verified on test
- [ ] Deployed to main
- [ ] Verified on main
