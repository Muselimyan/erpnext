# Name: dispatch_task_accept
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

task_name = frappe.form_dict.get("task_name")
if not task_name:
    frappe.throw("Task is required.")

task = frappe.get_doc("Task", task_name)
if task.status not in ("Open", "Working"):
    frappe.throw("Only Open or Working tasks can be accepted.")

print(f"[Accept] {frappe.utils.now()} task={task_name} user={frappe.session.user} kind={task.task_kind} status={task.status}")

# Read allowed roles from Task Access Policy (single source of truth)
allowed = []
if task.task_kind:
    try:
        policy = frappe.get_doc("Task Access Policy", task.task_kind)
        allowed = [r.role for r in (policy.allowed_roles or [])]
    except Exception:
        pass

user_roles = frappe.get_all("Has Role", filters={"parent": frappe.session.user}, pluck="role")
has_allowed_role = False
for r in allowed:
    if r in user_roles:
        has_allowed_role = True

print(f"[Accept] {frappe.utils.now()} task={task_name} roles_required={allowed} user_has_role={has_allowed_role}")

if allowed and not has_allowed_role and frappe.session.user != "Administrator" and "System Manager" not in user_roles:
    print(f"[Accept] {frappe.utils.now()} task={task_name} REJECTED: user={frappe.session.user}")
    frappe.throw("You are not allowed to accept this task kind. Required role: " + ", ".join(allowed))

# Cancel existing open ToDos
open_todos = frappe.get_all("ToDo", filters={"reference_type": "Task", "reference_name": task.name, "status": "Open"}, pluck="name")
for td in open_todos or []:
    frappe.db.set_value("ToDo", td, "status", "Cancelled")

# Update _assign in database, then reload and save
frappe.db.set_value("Task", task.name, "_assign", json.dumps([frappe.session.user]), update_modified=False)

# Reload task to get the updated _assign value
task.reload()
task.status = "Working"
task.custom_accepted_by = frappe.session.user
task.custom_accepted_at = frappe.utils.now_datetime()
task.custom_assigned_to = frappe.session.user
task.flags.ignore_permissions = True
task.save()

# Create new ToDo for current user
todo = frappe.new_doc("ToDo")
todo.status = "Open"
todo.allocated_to = frappe.session.user
todo.reference_type = "Task"
todo.reference_name = task.name
todo.description = task.subject or task.name
todo.assigned_by = frappe.session.user
todo.flags.ignore_permissions = True
todo.insert()

print(f"[Accept] {frappe.utils.now()} task={task_name} ACCEPTED: user={frappe.session.user} cancelled_todos={len(open_todos or [])}")

frappe.response["message"] = {"ok": True, "task": task.name, "assigned_to": frappe.session.user, "status": task.status}
