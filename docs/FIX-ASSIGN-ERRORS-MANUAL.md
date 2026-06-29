# Fix _assign Field Restriction Errors - Manual Instructions

## Problem
ERPNext 16.x blocks direct assignment to `_assign` field in server scripts, causing this error:
```
Line X: "_assign" is an invalid attribute name because it starts with "_".
```

## Solution
Update 4 server scripts to use `frappe.share.add()` instead of direct `_assign` assignment.

---

## Script 1: dispatch_task_accept

**How to fix:**
1. Go to ERPNext → Search for "Server Script"
2. Open **dispatch_task_accept**
3. Replace the entire script content with the code below
4. Click **Save**

**New code:**
```python
task_name = frappe.form_dict.get("task_name")
if not task_name:
    frappe.throw("Task is required.")

task = frappe.get_doc("Task", task_name)
if task.status not in ("Open", "Working"):
    frappe.throw("Only Open or Working tasks can be accepted.")

TASK_KIND_ALLOWED_ROLES = {
    "Order entry": ["Ops - Order Accepting", "Ops - Order Creating"],
    "Pack / prepare items": ["Ops - Inventory"],
    "Dispatch picking / hand-off": ["Ops - Delivery"],
    "Delivery": ["Delivery Driver", "Ops - Delivery"],
    "Pickup Returns": ["Delivery Driver", "Ops - Delivery", "Ops - Returns"],
    "Return drop-off at warehouse": ["Delivery Driver", "Ops - Delivery"],
    "Returns processing / verification": ["Ops - Returns", "Ops - Inventory"],
    "Returns restocking": ["Ops - Returns"],
    "Invoice preparation / create invoice": ["Ops - Accounting"],
    "Debt Collection": ["Ops - Finance", "Ops - Directors"],
    "Discount Approval": ["Ops - Directors"],
    "Purchase Approval": ["Ops - Directors"],
    "Write-off Approval": ["Ops - Directors"],
}
allowed = TASK_KIND_ALLOWED_ROLES.get(task.task_kind) or []
roles = frappe.get_roles(frappe.session.user) or []
if allowed and not any(r in roles for r in allowed) and frappe.session.user != "Administrator" and "System Manager" not in roles:
    frappe.throw("You are not allowed to accept this task kind. Required role: " + ", ".join(allowed))

try:
    assigned = frappe.parse_json(task.get("_assign") or "[]") or []
except Exception:
    assigned = []

team_placeholders = ["inventory.team@example.com", "delivery.team@example.com", "returns.team@example.com", "accounting.team@example.com", "finance.team@example.com", "order.creation.team@example.com", "order.team@example.com"]
real_assigned = [u for u in assigned if u not in team_placeholders]
if real_assigned and frappe.session.user not in real_assigned:
    frappe.throw("Task is already accepted by: " + ", ".join(real_assigned))

# FIXED: Use frappe.share.add instead of direct _assign
task.status = "Working"
task.flags.ignore_permissions = True
task.save()

# Clear existing assignments
for user in assigned:
    try:
        frappe.share.remove("Task", task.name, user)
    except Exception:
        pass

# Add current user
frappe.share.add("Task", task.name, frappe.session.user, write=1, share=0, notify=0)

# Cancel open ToDos
open_todos = frappe.get_all("ToDo", filters={"reference_type": "Task", "reference_name": task.name, "status": "Open"}, pluck="name")
for td in open_todos or []:
    frappe.db.set_value("ToDo", td, "status", "Cancelled")

# Create new ToDo
todo = frappe.new_doc("ToDo")
todo.status = "Open"
todo.allocated_to = frappe.session.user
todo.reference_type = "Task"
todo.reference_name = task.name
todo.description = f"Task accepted: {task.subject}"
todo.flags.ignore_permissions = True
todo.insert()

frappe.response["message"] = {"status": "success", "task": task.name, "assigned_to": frappe.session.user}
```

---

## Script 2: Dispatch-Case-after-save

**How to fix:**
1. Go to ERPNext → Search for "Server Script"
2. Open **Dispatch-Case-after-save**
3. Find the line that says: `"_assign": json.dumps(["directors.team@example.com"]),`
4. **Delete that entire line**
5. After the line `t.insert()`, add these two lines:
```python
        frappe.db.set_value("Dispatch Case", doc.name, "discount_approval_task", t.name)
        # FIXED: Use frappe.share.add instead of _assign
        frappe.share.add("Task", t.name, "directors.team@example.com", write=1, share=0, notify=1)
```
6. Click **Save**

**What the fixed section should look like:**
```python
        t = frappe.get_doc({
            "doctype": "Task",
            "subject": f"Discount Approval: {doc.name} — {doc.customer}",
            "task_kind": "Discount Approval",
            "task_access_policy": "Discount Approval",
            "dispatch_case": doc.name,
            "customer": doc.customer,
            "description": f"Review and approve or reject discounts.\n\n{disc_lines}",
        })
        t.flags.ignore_permissions = True
        t.insert()
        frappe.db.set_value("Dispatch Case", doc.name, "discount_approval_task", t.name)
        # FIXED: Use frappe.share.add instead of _assign
        frappe.share.add("Task", t.name, "directors.team@example.com", write=1, share=0, notify=1)
```

---

## Script 3: Dispatch-Case-before-submit

**How to fix:**
1. Go to ERPNext → Search for "Server Script"
2. Open **Dispatch-Case-before-submit**
3. Find the line that says: `"_assign": json.dumps(["inventory.team@example.com"]),`
4. **Delete that entire line**
5. After the line `doc.pack_task = t.name`, add these two lines:
```python
    # FIXED: Use frappe.share.add instead of _assign
    frappe.share.add("Task", t.name, "inventory.team@example.com", write=1, share=0, notify=1)
```
6. Click **Save**

**What the fixed section should look like:**
```python
    t = frappe.get_doc({
        "doctype": "Task",
        "subject": f"Pack: {doc.name} — {doc.customer}",
        "task_kind": "Pack / prepare items",
        "task_access_policy": "Pack / prepare items",
        "dispatch_case": doc.name,
        "customer": doc.customer,
        "description": f"Pack for delivery to: {doc.customer}\nDest: {doc.client_location_warehouse}\n\n{items_txt}",
    })
    t.flags.ignore_permissions = True
    t.insert()
    doc.pack_task = t.name
    # FIXED: Use frappe.share.add instead of _assign
    frappe.share.add("Task", t.name, "inventory.team@example.com", write=1, share=0, notify=1)
```

---

## Script 4: Task-after-save-dispatch-flow

**How to fix:**
1. Go to ERPNext → Search for "Server Script"
2. Open **Task-after-save-dispatch-flow**
3. Find the `make_task` function (around line 20-30)
4. Find the line that says: `"_assign": json.dumps([assignee]),`
5. **Delete that entire line**
6. After the `t.insert()` line in the `make_task` function, add:
```python
        # FIXED: Use frappe.share.add instead of _assign
        frappe.share.add("Task", t.name, assignee, write=1, share=0, notify=1)
```
7. Scroll down and find the `update_debt_collection` function
8. Find the line that says: `"_assign": json.dumps([FINANCE_TEAM]),`
9. **Delete that entire line**
10. After the `t.insert()` line in that function, add:
```python
            # FIXED: Use frappe.share.add instead of _assign
            frappe.share.add("Task", t.name, FINANCE_TEAM, write=1, share=0, notify=1)
```
11. Click **Save**

**What the fixed `make_task` function should look like:**
```python
    def make_task(kind, subject, assignee, desc="", link_field=None):
        existing = frappe.db.exists("Task", {"dispatch_case": doc.dispatch_case, "task_kind": kind, "status": ["not in", ["Completed", "Cancelled"]]})
        if existing:
            return existing
        t = frappe.get_doc({
            "doctype": "Task", "subject": subject, "task_kind": kind, "task_access_policy": kind,
            "dispatch_case": doc.dispatch_case, "customer": case.customer, "description": desc,
        })
        t.flags.ignore_permissions = True
        t.insert()
        if link_field:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, link_field, t.name)
        # FIXED: Use frappe.share.add instead of _assign
        frappe.share.add("Task", t.name, assignee, write=1, share=0, notify=1)
        return t.name
```

**What the fixed `update_debt_collection` section should look like:**
```python
            t = frappe.get_doc({
                "doctype": "Task", "subject": f"Debt Collection: {customer}",
                "task_kind": "Debt Collection", "task_access_policy": "Debt Collection",
                "customer": customer, "total_outstanding": total_out,
                "open_invoices": inv_row,
            })
            t.flags.ignore_permissions = True
            t.insert()
            # FIXED: Use frappe.share.add instead of _assign
            frappe.share.add("Task", t.name, FINANCE_TEAM, write=1, share=0, notify=1)
```

---

## Testing After Fix

Once all 4 scripts are updated:

1. **Test the Accept / Start Task button:**
   - Log in as `inventory.team@example.com`
   - Open a Pack task
   - Click "Accept / Start Task"
   - Should work without errors

2. **Test discount approval task creation:**
   - Create a Dispatch Case with discounted items
   - Save it
   - A discount approval task should be created and assigned to directors

3. **Test pack task creation:**
   - Submit a Dispatch Case
   - A pack task should be created and assigned to inventory team

4. **Test workflow task creation:**
   - Complete a Pack task
   - A Delivery task should be created
   - Complete Returns Inspection
   - Invoice and Debt Collection tasks should be created

All workflows should now work without `_assign` errors!

---

## Why This Fix Works

**Old way (blocked in ERPNext 16.x):**
```python
task._assign = json.dumps(["user@example.com"])
```

**New way (works in ERPNext 16.x):**
```python
frappe.share.add("Task", task.name, "user@example.com", write=1, share=0, notify=1)
```

The `frappe.share.add()` method is the official API for assigning documents to users. It:
- Updates the `_assign` field internally (allowed because it's the official API)
- Creates ToDo notifications
- Handles permissions correctly
- Is future-proof for ERPNext updates
