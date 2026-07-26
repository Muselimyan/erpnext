# Unified Task Assignment - Testing Guide

## What Was Prepared

**Script:** `add-unified-task-assignment.ps1`

This script adds "Assign Next Task To" functionality to the dispatch workflow.

## Changes Made

### 1. New Custom Fields (2 fields)

- `custom_next_task_assign_to` (Link to User)
  - Label: "Assign Next Task To: Person"
  - Visible only on dispatch workflow tasks

- `custom_next_task_assign_role` (Link to Role)
  - Label: "Assign Next Task To: Team/Role"
  - Visible only on dispatch workflow tasks

### 2. Client Script Updates

- Shows next-task fields only for dispatch tasks:
  - Order entry
  - Pack / prepare items
  - Delivery
  - Return Call
  - Pickup Returns
  - Returns processing / verification
  - Returns restocking

- Clears opposite field when one is selected
  - If you select a person, team/role clears
  - If you select a team/role, person clears

### 3. Server Script Updates (CRITICAL)

**Modified function:** `make_task()`

**Old signature:**
```python
def make_task(kind, subject, assignee, desc="", link_field=None, dispatch_case_name=None, customer=None):
```

**New signature:**
```python
def make_task(kind, subject, assignee, desc="", link_field=None, dispatch_case_name=None, customer=None, source_task=None):
```

**New logic:**
- Checks source task for `custom_next_task_assign_to` or `custom_next_task_assign_role`
- If found, uses that assignment instead of default team
- If empty, uses default team (existing behavior)

**All `make_task()` calls updated:**
- Now pass `source_task=doc.name`
- This allows next task to check current task's preferences

## Critical Testing Required

### Test 1: Next Task Assignment - Person

1. Create new Dispatch Case
2. Complete Order Entry task
3. **Before completing**, set "Assign Next Task To: Person" = specific user
4. Complete Order Entry
5. **Verify:** Pack task is created and assigned to that specific user
6. Check `_assign` field and `ToDo` record

### Test 2: Next Task Assignment - Team/Role

1. Open Pack task
2. **Before completing**, set "Assign Next Task To: Team/Role" = specific role
3. Complete Pack task
4. **Verify:** Delivery task is created and assigned to that team/role
5. Check assignment shows correctly

### Test 3: Next Task Assignment - Empty (Default)

1. Open Delivery task
2. Leave next-task fields **empty**
3. Complete Delivery task
4. **Verify:** Next task uses default team (existing behavior)
5. Should work exactly as before

### Test 4: Field Clearing

1. Open any dispatch task
2. Set "Assign Next Task To: Person" = user1
3. Then set "Assign Next Task To: Team/Role" = role1
4. **Verify:** Person field clears automatically
5. Vice versa

### Test 5: Non-Dispatch Tasks

1. Open a task that is NOT dispatch workflow
   - Example: Discount Approval, Purchase Approval, etc.
2. **Verify:** Next-task fields are hidden
3. Should not see "Assign Next Task To" fields at all

### Test 6: Full Dispatch Workflow

**Critical end-to-end test:**

1. Create Dispatch Case
2. Order Entry → assign next to user_A → complete
3. **Verify:** Pack task assigned to user_A
4. Pack task → assign next to role_B → complete
5. **Verify:** Delivery task assigned to role_B
6. Delivery task → leave empty → complete
7. **Verify:** Invoice task uses default accounting team
8. Continue through full workflow
9. **Verify:** No errors, all tasks created correctly

### Test 7: Current Task Assignment Still Works

1. Create new task
2. Use existing "Assign To: Person" field
3. **Verify:** Task assigns correctly
4. Accept task
5. **Verify:** Assignment changes to current user
6. **Verify:** `_assign` and `ToDo` update correctly

## What Could Go Wrong

### High Risk Areas

1. **Server script syntax error**
   - Regex replacement might create invalid Python
   - Test by creating/completing any dispatch task
   - Check ERPNext error log

2. **make_task() signature mismatch**
   - If any call doesn't pass source_task, might fail
   - Test all dispatch workflow transitions

3. **Assignment not applied**
   - Next task created but uses default team anyway
   - Check server script logic for next_user/next_role

4. **Duplicate source_task parameter**
   - Regex might add source_task twice
   - Check server script for `source_task=doc.name, source_task=doc.name`

5. **Role assignment format**
   - Team email placeholders vs role names
   - Verify role assignment actually works

## Rollback Plan

If anything breaks:

### Quick Disable

1. **Hide next-task fields:**
   ```powershell
   # Set fields to hidden=1 via API
   ```

2. **Revert server script:**
   - Search for "Server Script"
   - Find "Task-after-save-dispatch-flow"
   - Copy old version from git/backup
   - Paste and save

3. **Revert client script:**
   - Search for "Client Script"
   - Find "Task-Accept Start"
   - Remove next-task UI section

### Full Rollback

Re-run old version of server script from before this change.

## Deployment Order

### On Test Site

```powershell
# Check current state
.\add-unified-task-assignment.ps1 -Mode Check -Target test

# Deploy
.\add-unified-task-assignment.ps1 -Mode Deploy -Target test

# Verify
.\add-unified-task-assignment.ps1 -Mode Check -Target test
```

### Testing Checklist

- [ ] Test 1: Next task to person
- [ ] Test 2: Next task to team/role
- [ ] Test 3: Next task empty (default)
- [ ] Test 4: Field clearing
- [ ] Test 5: Non-dispatch tasks hide fields
- [ ] Test 6: Full dispatch workflow end-to-end
- [ ] Test 7: Current assignment still works
- [ ] No errors in ERPNext error log
- [ ] No errors in browser console

### On Main Site (Only After Test Verification)

```powershell
.\add-unified-task-assignment.ps1 -Mode Deploy -Target main
```

**DO NOT deploy to main until ALL tests pass on test.**

## Notes

- This is the highest-risk change in the whole UI fix batch
- It modifies server-side task creation logic
- All dispatch workflow transitions depend on `make_task()`
- One error could break task autocreation for all workers
- Test thoroughly before main deployment

## Current Two-Box Assignment

The current "Assign To: Person" and "Assign To: Team/Role" fields remain:

- They still work for current task assignment
- They are NOT unified into one box yet
- That would require more complex UI changes
- Current solution: keep two boxes, add next-task routing

## Future: True Unified One-Box Assignment

Not implemented yet. Would require:

- Custom dialog or smart field
- Detect if selected value is user or role
- Auto-populate correct backend field
- More complex but cleaner UX

Current solution is pragmatic: improve what exists, add next-task routing.
