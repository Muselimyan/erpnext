# `custom_next_task_assign_to` — Deep Analysis

> **Scope**: Every server script, client script, schema definition, and property setter that reads, writes, shows, or hides the `custom_next_task_assign_to` field on the Task DocType.
>
> **Method**: Line-by-line reading of every deployed script file under `deploy/test/work/`, cross-referenced against schema metadata (`deploy/test/schema/*.json`).
>
> **Confidence scale**:
> - **0.95–1.00**: Directly confirmed from extracted deployed source and/or schema metadata.
> - **0.80–0.94**: Strongly supported by code and cross-file evidence; runtime confirmation useful.
> - **0.60–0.79**: Plausible interpretation requiring targeted validation.

---

## 1. Field Definition (from schema)

Source: `deploy/test/schema/custom-fields.json`, entry `Task-custom_next_task_assign_to` (lines 6727–6768)

| Property | Value |
|---|---|
| **Fieldname** | `custom_next_task_assign_to` |
| **Label** | "Next Task: Assign To" |
| **Type** | Link → User |
| **Position** | After `custom_assigned_to` (idx 6 in field order) |
| **Hidden** | 0 (not hidden by default) |
| **Read-only** | 0 |
| **Required** | 0 |
| **Default** | (none) |
| **depends_on** | `eval:["Order entry","Pack / prepare items","Delivery","Return Call","Other: Entry","Other: Processing","Returns processing / verification"].includes(doc.task_kind)` |
| **Created** | 2026-07-22 |
| **Last modified** | 2026-08-27 |

**Property setters**: No property setter overrides `depends_on`, `hidden`, or any other property of this field. The only reference is in the `field_order` setter which positions it 6th.

**Confidence: 1.00**

---

## 2. Purpose

The field allows the current task's assignee to nominate a specific user for the **next task** in the chain, overriding the default team-placeholder assignment (e.g., `delivery.team@example.com`). Without a value, the next task defaults to the team placeholder.

---

## 3. Server-Side Consumers

There are **exactly three** server-side code paths that read this field.

### Consumer A — Dispatch Flow `make_task()` (the main consumer)

**File**: `server/Task-after-save-dispatch-flow.py`, lines 88–120

```python
def make_task(kind, subject, assignee, desc="", link_field=None,
              dispatch_case_name=None, customer=None, source_task=None):
    dc_name = dispatch_case_name or doc.dispatch_case
    cust = customer or frappe.db.get_value("Dispatch Case", dc_name, "customer")
    existing = frappe.db.exists("Task", {
        "dispatch_case": dc_name, "task_kind": kind,
        "status": ["not in", ["Completed", "Cancelled"]]
    })
    if existing:
        return existing
    t = frappe.get_doc({
        "doctype": "Task", "subject": subject, "task_kind": kind,
        "task_access_policy": kind,
        "dispatch_case": dc_name, "customer": cust, "description": desc,
    })
    # Check if source task specified next-task assignment
    if source_task:
        next_user = frappe.db.get_value("Task", source_task,
                                        "custom_next_task_assign_to")
        if next_user:
            assignee = next_user          # ← override the team placeholder
    t.custom_assigned_to = assignee
    t.flags.ignore_permissions = True
    t.insert()
    ...
```

**How it works**: When creating a new task in the dispatch chain, if `source_task` is provided, it reads `custom_next_task_assign_to` from the source task. If a value exists, it overrides the default `assignee` (a team placeholder).

**All callers pass `source_task=doc.name`:**

| Line | Trigger | Next task created | source_task |
|---|---|---|---|
| 221 | Order entry completed | Pack / prepare items | Order entry task |
| 229 | Pack completed | Delivery | Pack task |
| 192 | Delivery → Delivered (no return) | Invoice preparation | Delivery task |
| 195 | Delivery → Delivered (return expected) | Return Call | Delivery task |
| 238 | Return Call completed | Pickup Returns | Return Call task |
| 209 | Pickup Returns → Returned to WH | Returns processing | Pickup Returns task |
| 251 | Returns Inspection completed | Invoice preparation | Returns processing task |
| 257 | Returns Inspection completed | Returns restocking | Returns processing task |
| 286 | Discount Approval → Approved | Pack / prepare items | Discount Approval task |
| 289 | Discount Approval → Rejected | Order entry | Discount Approval task |

**Important**: The value is **read but never cleared** from the source task. After consumption, the field still shows its value on the completed task. **Confidence: 1.00**

### Consumer B — Account Details Processing

**File**: `server/Task-after-save-account-details-processing.py`, lines 17–21

```python
assignee = doc.get("custom_next_task_assign_to")
if assignee and (not doc.get("custom_assigned_to")
                 or assignee == doc.get("custom_assigned_to")):
    assignee = None
if not assignee:
    assignee = "accounting.team@example.com"
```

**Behavior**: If `custom_next_task_assign_to` is the **same user** as `custom_assigned_to`, the value is **discarded** and the team placeholder is used instead. The intention is: "don't assign the processing task to the same person who did the entry — send it to the team queue."

Specifically:
- `next = "user_b"`, `current = "user_a"` → assignee = `"user_b"` (different user, used)
- `next = "user_a"`, `current = "user_a"` → assignee = None → `"accounting.team@example.com"` (same user, discarded)
- `next = "user_a"`, `current = ""` → assignee = None → `"accounting.team@example.com"` (no current, discarded)

After determining the assignee, the script properly creates `_assign` JSON and a ToDo for the new task (lines 49–58).

**Confidence: 0.95**

### Consumer C — Other Processing

**File**: `server/Task-after-save-other-processing.py`, lines 21–24

```python
if doc.get("custom_next_task_assign_to"):
    new_task.custom_assigned_to = doc.custom_next_task_assign_to
elif doc.get("custom_assigned_to"):
    new_task.custom_assigned_to = doc.custom_assigned_to
```

**Behavior**: Simpler than Account Details — if set, use it unconditionally; no "same user" clearing. Falls back to the **current assignee** (not team placeholder).

**Critical difference from Consumer B**: This script does **NOT** create `_assign` or a ToDo after insert (lines 25–29 only set team queue fields and insert the task). The assigned user will not receive any notification and the task won't appear in their Frappe inbox.

**Confidence: 1.00**

---

## 4. Client-Side Visibility — Layer-by-Layer Analysis

The field's visibility is controlled by **5 overlapping layers** that all fire on every form refresh. Because ERPNext client scripts don't have guaranteed execution order and use competing `setTimeout` delays, the net visibility depends on which layer runs last.

### Layer 1 — Schema `depends_on` (field definition)

The field definition's `depends_on` expression renders the field for 7 task kinds:

1. Order entry
2. Pack / prepare items
3. Delivery
4. Return Call
5. Other: Entry
6. Other: Processing
7. Returns processing / verification

For all other task kinds, the field is natively hidden.

### Layer 2 — `Task-Accept Start.js` (lines 182–190) — THE DOMINANT LAYER

```javascript
const dispatchKinds = [
    "Order entry", "Pack / prepare items", "Delivery", "Return Call",
    "Pickup Returns", "Returns processing / verification",
    "Returns restocking", "Invoice preparation / create invoice",
    "Discount Approval"
];
if (dispatchKinds.includes(frm.doc.task_kind)
    || frm.doc.task_kind === "Account Details: Entry") {
    frm.set_df_property("custom_next_task_assign_to", "hidden", 0);
} else {
    frm.set_df_property("custom_next_task_assign_to", "hidden", 1);
}
```

This runs **immediately** on every `refresh` event and shows the field for **10 task kinds** — a superset of the schema's 7. It explicitly hides the field for everything not in its list (line 187).

**Mismatches with schema:**
- Client ADDS: `Pickup Returns`, `Returns restocking`, `Invoice preparation / create invoice`, `Discount Approval`, `Account Details: Entry`
- Client REMOVES: `Other: Entry`, `Other: Processing` (not in `dispatchKinds`, so hidden by the `else` branch)

**This is the dominant layer because it runs immediately and uses explicit `hidden` property sets that override the schema's `depends_on`.**

### Layer 3 — `Task-Other UI Cleanup.js` (line 42) — Delayed Recovery for Other: Entry

```javascript
if (frm.fields_dict.custom_next_task_assign_to) {
    frm.set_df_property("custom_next_task_assign_to", "label",
                        "Next Task: Assign To");
    frm.toggle_display("custom_next_task_assign_to",
                        String(frm.doc.subject || "") !== "Other: Processing");
}
```

This runs at **delayed intervals** (200ms, 800ms, 1600ms, 3000ms after refresh).

- For `Other: Entry`: shows the field (subject is not "Other: Processing")
- For `Other: Processing`: hides the field

Because Layer 2 runs immediately and hides the field for Other tasks, but Layer 3 runs later and re-shows it for Other: Entry, the net result is:
1. **0ms**: Field hidden (Layer 2)
2. **200ms**: Field shown (Layer 3 fires)

The field flickers for ~200ms. On slow devices this may be visible.

### Layer 4 — `Task-Inspect Returns Next Assign Visible.js` (lines 17–25) — Redundant

```javascript
function task_inspect_returns_next_assign_visible(frm) {
    if (frm.doc.task_kind !== 'Returns processing / verification') return;
    frm.set_df_property('custom_next_task_assign_to', 'label',
                        'Next Task: Assign To');
    frm.set_df_property('custom_next_task_assign_to', 'hidden', 0);
    frm.toggle_display('custom_next_task_assign_to', true);
    if (frm.fields_dict.custom_next_task_assign_to.$wrapper) {
        frm.fields_dict.custom_next_task_assign_to.$wrapper.show();
    }
}
```

Forcefully shows for `Returns processing / verification` only. Runs at 0ms, 300ms, 1000ms. **Redundant** — Layer 2 already includes this task kind in `dispatchKinds`. This script adds `.$wrapper.show()` as an extra-forceful DOM-level show.

### Layer 5 — `Task-Delivery UI Fix.js` (lines 19–21) — Redundant

```javascript
if (frm.fields_dict.custom_next_task_assign_to) {
    frm.set_df_property("custom_next_task_assign_to", "hidden", 0);
    frm.toggle_display("custom_next_task_assign_to", true);
}
```

Forcefully shows for `Delivery` only. Runs at 0ms, 300ms, 900ms. **Redundant** — Layer 2 already includes Delivery in `dispatchKinds`.

### Layer 6 — `account_details_entry_keep_next_assign_empty()` (lines 363–371 of Task-Accept Start.js) — Value Auto-Clear

```javascript
function account_details_entry_keep_next_assign_empty(frm) {
    if (String(frm.doc.task_kind || "").trim() !== "Account Details: Entry")
        return;
    var nextAssign = String(frm.doc.custom_next_task_assign_to || "").trim();
    var currentAssign = String(frm.doc.custom_assigned_to || "").trim();
    if (nextAssign && (!currentAssign || nextAssign === currentAssign)) {
        frm.set_value("custom_next_task_assign_to", "");
    }
}
```

For `Account Details: Entry` only: auto-clears the value if it equals `custom_assigned_to`. Runs on **every refresh**. This is the client-side mirror of Consumer B's server-side logic.

---

## 5. Net Visibility Matrix

All 18+ task kinds analyzed. "Consumed?" means the server actually reads the value when the task is completed.

| Task Kind | Schema | Layer 2 (Accept Start) | Other Layers | **Net Visible?** | **Consumed?** | **Verdict** |
|---|---|---|---|---|---|---|
| Order entry | Show | Show | — | **YES** | Yes → Pack | **OK** |
| Pack / prepare items | Show | Show | — | **YES** | Yes → Delivery | **OK** |
| Delivery | Show | Show | L5 re-shows | **YES** | Yes → Invoice or Return Call | **OK** |
| Return Call | Show | Show | — | **YES** | Yes → Pickup Returns | **OK** |
| Pickup Returns | **Hide** | Show | — | **YES** | Yes → Returns Inspection | **OK** (client overrides schema) |
| Returns processing | Show | Show | L4 re-shows | **YES** | Yes → Invoice + Restock | **OK** |
| Discount Approval | **Hide** | Show | — | **YES** | Yes → Pack or Order entry | **OK** (client overrides schema) |
| Account Details: Entry | **Hide** | Show (line 190) | L6 auto-clears same-user | **YES** | Yes (Consumer B) | **OK** (with same-user clearing) |
| Other: Entry | Show | **Hide** | L3 re-shows (200ms) | **YES** (fragile) | Yes (Consumer C) | **FRAGILE** — timing race |
| **Returns restocking** | **Hide** | **Show** | — | **YES** | **NO** — no next task | **BUG: shown but useless** |
| **Invoice preparation** | **Hide** | **Show** | — | **YES** | **NO** — uses `create_or_update_debt_task` | **BUG: shown but useless** |
| Account Details: Processing | Hide | Hide | — | NO | N/A | OK |
| Other: Processing | Show | Hide | L3 hides | NO | N/A | OK |
| Debt Collection | Hide | Hide | — | NO | N/A | OK |
| Debt Closure Approval | Hide | Hide | — | NO | N/A | OK |
| Purchase Approval | Hide | Hide | — | NO | N/A | OK |
| Write-off Approval | Hide | Hide | — | NO | N/A | OK |
| Payment Received | Hide | Hide | — | NO | N/A | OK |

---

## 6. Editability

From `Task-Lock Unaccepted.js`:

- When `can_edit = true` (accepted user or admin): **ALL fields** are set to `read_only = 0` (lines 28–31), including `custom_next_task_assign_to`. The field is editable.
- When `can_edit = false` (not accepted): **ALL fields** are set to `read_only = 1` (lines 55–58). The field is locked.
- Completed tasks: Form is entirely locked by `Task-Lock Completed.js`.

`custom_next_task_assign_to` is **NOT** in the explicit `editable_fields` list (lines 34–40) — but this doesn't matter because the first loop (lines 28–31) already unlocks all fields. If the code were later refactored to only unlock the explicit list, this field would become locked. **Maintenance risk.**

**Confidence: 0.95**

---

## 7. Return Call: Dual Assignment Mechanism

Return Call tasks present a unique case because the dispatch flow has **two** fields that can influence Pickup Returns driver assignment:

1. **`return_pickup_driver`** — a dedicated Link → User field with `depends_on` showing it only for Pickup Returns and Return drop-off tasks. **Hidden on Return Call tasks.**
2. **`custom_next_task_assign_to`** — the generic next-task field. **Visible on Return Call tasks.**

The server code (line 235–238):
```python
driver = doc.return_pickup_driver or DELIVERY_TEAM
...
tid = make_task("Pickup Returns", ..., driver, ..., source_task=doc.name)
```

Inside `make_task`, `custom_next_task_assign_to` is checked and overrides `driver` if set.

**Result**: Since `return_pickup_driver` is hidden on Return Call forms, it will always be blank. The `driver` variable defaults to `DELIVERY_TEAM`. Then `make_task` checks `custom_next_task_assign_to` and overrides if set.

**Net behavior**: `custom_next_task_assign_to` is the effective driver assignment mechanism for Return Call → Pickup Returns. The `return_pickup_driver` read on line 235 is dead code in practice for this path.

**Confidence: 0.88**

---

## 8. Findings

### BUG-NTA-1: Field shown for Returns restocking but value is never consumed

- **Severity**: Medium
- **Confidence**: 0.97
- **Evidence**: `Task-Accept Start.js` line 183 includes `"Returns restocking"` in `dispatchKinds`, making the field visible. But `Task-after-save-dispatch-flow.py` lines 259–264 show that Restock task completion only creates a Stock Entry — no next task is created, and `custom_next_task_assign_to` is never read.
- **Impact**: Users can fill in a value that has zero effect. Misleading UI.
- **Fix**: Remove `"Returns restocking"` from `dispatchKinds` on line 183 of `Task-Accept Start.js`.

### BUG-NTA-2: Field shown for Invoice preparation but value is never consumed

- **Severity**: Medium
- **Confidence**: 0.97
- **Evidence**: `Task-Accept Start.js` line 183 includes `"Invoice preparation / create invoice"` in `dispatchKinds`. But `Task-after-save-dispatch-flow.py` lines 267–278 show that Invoice preparation completion uses `create_or_update_debt_task()` which has its own hardcoded assignment (`FINANCE_TEAM`). It does NOT read `custom_next_task_assign_to` from the invoice task.
- **Impact**: Same as BUG-NTA-1 — value has no effect.
- **Fix**: Either (a) remove `"Invoice preparation / create invoice"` from `dispatchKinds`, or (b) modify `create_or_update_debt_task()` to accept a `source_task` parameter and read `custom_next_task_assign_to`.

### BUG-NTA-3: Schema `depends_on` is stale — does not match actual visibility

- **Severity**: Low (cosmetic, since client scripts are dominant)
- **Confidence**: 0.95
- **Evidence**: Schema `depends_on` includes 7 task kinds. Client scripts show it for 10 task kinds. Five kinds are client-only overrides (`Pickup Returns`, `Returns restocking`, `Invoice preparation`, `Discount Approval`, `Account Details: Entry`). Two kinds are in schema but hidden by client (`Other: Entry` partially, `Other: Processing` fully).
- **Impact**: If client scripts are ever disabled or delayed, the field appears/disappears based on the wrong criteria. Developers reading the schema get a misleading picture.
- **Fix**: Update the schema `depends_on` to match the task kinds where the field is shown AND consumed:
  ```
  eval:["Order entry","Pack / prepare items","Delivery","Return Call",
        "Pickup Returns","Returns processing / verification",
        "Discount Approval","Account Details: Entry","Other: Entry"]
       .includes(doc.task_kind)
  ```

### BUG-NTA-4: Other: Entry visibility depends on script timing race

- **Severity**: Low-Medium
- **Confidence**: 0.88
- **Evidence**: `Task-Accept Start.js` runs immediately on refresh and hides the field for Other tasks (not in `dispatchKinds`). Then `Task-Other UI Cleanup.js` runs at delayed intervals (200ms, 800ms, 1600ms, 3000ms) and re-shows it for Other: Entry. The field flickers: hidden → shown (~200ms window).
- **Impact**: On slow devices the field may visibly flicker. If client scripts load in unexpected order, the behavior could reverse.
- **Fix**: Add `"Other: Entry"` to `dispatchKinds` in `Task-Accept Start.js` line 183, so both scripts agree on showing it. Remove the redundant toggle from `Task-Other UI Cleanup.js` line 42.

### BUG-NTA-5: Other: Processing tasks created without `_assign` or ToDo

- **Severity**: **High**
- **Confidence**: 0.95
- **Evidence**: `Task-after-save-other-processing.py` sets `custom_assigned_to` from `custom_next_task_assign_to` (line 22) but does NOT call `frappe.db.set_value("Task", new_task.name, "_assign", ...)` or create a ToDo. Compare with `Task-after-save-account-details-processing.py` lines 49–58 which properly does both.
- **Impact**: The assigned user never gets a ToDo notification and the task won't appear in their Frappe assignment inbox. The task exists but is invisible to the assignee unless they manually search or check the team queue.
- **Fix**: Add `_assign` and ToDo creation after `new_task.insert()`, mirroring the Account Details processing script:
  ```python
  assignee = new_task.custom_assigned_to or doc.custom_assigned_to
  frappe.db.set_value("Task", new_task.name, "_assign",
                      json.dumps([assignee]))
  todo = frappe.new_doc("ToDo")
  todo.status = "Open"
  todo.allocated_to = assignee
  todo.reference_type = "Task"
  todo.reference_name = new_task.name
  todo.description = new_task.subject or new_task.name
  todo.assigned_by = frappe.session.user
  todo.flags.ignore_permissions = True
  todo.insert()
  ```

### ISSUE-NTA-6: `account_details_entry_keep_next_assign_empty` auto-clears value on every refresh

- **Severity**: Low-Medium
- **Confidence**: 0.92
- **Evidence**: `Task-Accept Start.js` lines 363–371. If `custom_next_task_assign_to == custom_assigned_to`, the client clears the field on every refresh. The server also discards the same-user value (Consumer B, line 18).
- **Impact**: If a user intentionally sets "Next Task: Assign To" to themselves (wanting to do the processing step too), the value gets cleared on the next refresh. They cannot override this behavior.
- **Improvement**: Either (a) remove the client-side clearing and let the server handle it silently, showing the user a note like "Same as current assignee — will default to team", or (b) keep the behavior but add a transient toast explaining why it was cleared.

### ISSUE-NTA-7: Return Call has two conflicting driver assignment mechanisms

- **Severity**: Low
- **Confidence**: 0.88
- **Evidence**: Dispatch flow reads `return_pickup_driver` from Return Call task (line 235) and uses it as the initial Pickup Returns assignee. Then `make_task` reads `custom_next_task_assign_to` (line 100) and overrides if set. The `return_pickup_driver` field is HIDDEN on Return Call tasks (its `depends_on` only shows it for Pickup Returns / Return drop-off).
- **Net behavior**: `custom_next_task_assign_to` controls the Pickup Returns driver assignment on Return Call tasks, which is correct. But the code path is unnecessarily confusing — `return_pickup_driver` is read but always blank for Return Call tasks.
- **Improvement**: Either (a) show `return_pickup_driver` on Return Call tasks and use it as the primary assignment mechanism (clearer intent — "which driver should pick up?"), or (b) remove the `return_pickup_driver` read on line 235 and rely solely on `custom_next_task_assign_to` via `make_task`.

### ISSUE-NTA-8: Value is never cleared after consumption

- **Severity**: Low (cosmetic)
- **Confidence**: 0.90
- **Evidence**: `make_task()` reads the value via `frappe.db.get_value()` on line 100 but never clears it on the source task. Same for Consumers B and C.
- **Impact**: After completing a task, the completed (locked) task still displays the "Next Task: Assign To" value. This is cosmetically confusing — it suggests the assignment is still "pending" when it has already been consumed. However, since the task is locked (Completed), no functional harm occurs.
- **Fix**: After creating the next task, clear the field:
  ```python
  frappe.db.set_value("Task", source_task,
                      "custom_next_task_assign_to", "",
                      update_modified=False)
  ```

### ISSUE-NTA-9: Three redundant visibility scripts

- **Severity**: Low (code quality / maintenance)
- **Confidence**: 0.95
- **Evidence**: `Task-Inspect Returns Next Assign Visible.js` (26 lines), `Task-Delivery UI Fix.js` (lines 19–21), and the Account Details explicit show (line 190 of `Task-Accept Start.js`) all forcefully show the field for task kinds already in the `dispatchKinds` list. These are belt-and-suspenders additions that add complexity without adding functionality.
- **Improvement**: Remove the redundant visibility overrides and consolidate all visibility logic into the `dispatchKinds` check in `Task-Accept Start.js`.

### ISSUE-NTA-10: Inconsistent same-user behavior between Account Details and Other flows

- **Severity**: Low
- **Confidence**: 0.92
- **Evidence**: Account Details Processing (lines 17–19) discards `custom_next_task_assign_to` if it equals `custom_assigned_to`. Other Processing (lines 21–24) does NOT — it always uses the value if set, even if it's the same user.
- **Impact**: Users learn two different behaviors depending on task kind. Setting "Next Task: Assign To" to yourself works for Other tasks but is silently ignored for Account Details tasks.
- **Improvement**: Choose one behavior and apply consistently across both flows.

---

## 9. Summary Table

| ID | Type | Severity | Confidence | Description |
|---|---|---|---|---|
| BUG-NTA-1 | Bug | Medium | 0.97 | Field shown for Returns restocking but value never consumed |
| BUG-NTA-2 | Bug | Medium | 0.97 | Field shown for Invoice preparation but value never consumed |
| BUG-NTA-3 | Bug | Low | 0.95 | Schema `depends_on` stale — doesn't match client visibility |
| BUG-NTA-4 | Bug | Low-Med | 0.88 | Other: Entry visibility depends on script timing race |
| BUG-NTA-5 | Bug | **High** | 0.95 | Other: Processing tasks missing `_assign` and ToDo |
| NTA-6 | UX Issue | Low-Med | 0.92 | Auto-clear same-user value on every refresh (Account Details) |
| NTA-7 | Design | Low | 0.88 | Two conflicting driver assignment fields on Return Call |
| NTA-8 | Cosmetic | Low | 0.90 | Value never cleared after consumption |
| NTA-9 | Code Quality | Low | 0.95 | Three redundant visibility scripts |
| NTA-10 | Inconsistency | Low | 0.92 | Different same-user behavior: Account Details vs Other |

---

## 10. Recommended Fixes (priority order)

### Priority 1 — Fix BUG-NTA-5 (High)

Add `_assign` and ToDo creation to `Task-after-save-other-processing.py` after `new_task.insert()`, mirroring the Account Details processing pattern. Without this, the assignee set via `custom_next_task_assign_to` never sees the task.

### Priority 2 — Fix BUG-NTA-1 + BUG-NTA-2 (Medium)

Remove `"Returns restocking"` and `"Invoice preparation / create invoice"` from the `dispatchKinds` array in `Task-Accept Start.js` line 183. These task kinds don't create a next task on completion, so showing the field is misleading.

Alternatively, if the business wants these to be functional: modify the completion handlers to read and use the field.

### Priority 3 — Fix BUG-NTA-4 (Low-Medium)

Add `"Other: Entry"` to `dispatchKinds` in `Task-Accept Start.js` line 183 to eliminate the timing race. Remove the redundant toggle from `Task-Other UI Cleanup.js` line 42.

### Priority 4 — Fix BUG-NTA-3 (Low)

Update the schema `depends_on` expression to match the correct set of task kinds where the field is shown and consumed:

```
eval:["Order entry","Pack / prepare items","Delivery","Return Call",
      "Pickup Returns","Returns processing / verification",
      "Discount Approval","Account Details: Entry","Other: Entry"]
     .includes(doc.task_kind)
```

### Priority 5 — Consider NTA-8

Add value-clearing after consumption in `make_task()` and in both processing scripts:

```python
frappe.db.set_value("Task", source_task, "custom_next_task_assign_to", "",
                    update_modified=False)
```

### Priority 6 — Clean up redundant scripts (NTA-9)

Remove redundant visibility overrides from `Task-Inspect Returns Next Assign Visible.js` and `Task-Delivery UI Fix.js` (or at minimum the `custom_next_task_assign_to` lines in them) and consolidate into the single `dispatchKinds` check.
