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
    "Return Call": ["Ops - Returns", "Ops - Order Accepting"],
    "Debt Closure Approval": ["Ops - Directors"],
}
allowed = TASK_KIND_ALLOWED_ROLES.get(task.task_kind) or []
user_roles = frappe.get_all("Has Role", filters={"parent": frappe.session.user}, pluck="role")
has_allowed_role = False
for r in allowed:
    if r in user_roles:
        has_allowed_role = True

if allowed and not has_allowed_role and frappe.session.user != "Administrator" and "System Manager" not in user_roles:
    frappe.throw("You are not allowed to accept this task kind. Required role: " + ", ".join(allowed))

# Assignment check removed - any user with correct role can re-accept
if task.custom_team_queue_role and frappe.session.user != "Administrator" and "System Manager" not in user_roles:
    if task.custom_team_queue_role not in user_roles:
        frappe.throw("This task is assigned to team '" + task.custom_team_queue_role + "'. You need that role to accept.")

try:
    assigned = frappe.parse_json(task.get("_assign") or "[]") or []
except Exception:
    assigned = []

team_placeholders = ["inventory.team@example.com", "delivery.team@example.com", "returns.team@example.com", "accounting.team@example.com", "finance.team@example.com", "order.creation.team@example.com", "order.team@example.com"]
real_assigned = [u for u in assigned if u not in team_placeholders]
# Re-acceptance allowed - no blocking here

# FIXED: Update _assign via db and create ToDo manually (assign_to module not available in RestrictedPython)
# Cancel existing open ToDos first
open_todos = frappe.get_all("ToDo", filters={"reference_type": "Task", "reference_name": task.name, "status": "Open"}, pluck="name")
for td in open_todos or []:
    frappe.db.set_value("ToDo", td, "status", "Cancelled")

# Update _assign in database first, then reload and save
frappe.db.set_value("Task", task.name, "_assign", json.dumps([frappe.session.user]), update_modified=False)
frappe.db.commit()

# Reload task to get the updated _assign value
task.reload()
task.status = "Working"
task.custom_accepted_by = frappe.session.user
task.custom_accepted_at = frappe.utils.now_datetime()
task.custom_assigned_to = frappe.session.user
task.custom_team_queue_role = ""
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

frappe.response["message"] = {"ok": True, "task": task.name, "assigned_to": frappe.session.user, "status": task.status}