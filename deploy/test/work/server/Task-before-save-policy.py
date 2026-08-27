# Name: Task-before-save-policy
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

before = doc.get_doc_before_save()
before_status = before.status if before else None
is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")
DIRECTOR_ROLE = "Ops - Directors"
TASK_KIND_ALLOWED_ROLES = {
    "Order entry": ["Ops - Order Accepting", "Ops - Order Creating"],
    "Pack / prepare items": ["Ops - Inventory"],
    "Dispatch picking / hand-off": ["Ops - Delivery"],
    "Delivery": ["Delivery Driver", "Ops - Delivery"],
    "Return to warehouse (aborted delivery / cancelled order)": ["Delivery Driver", "Ops - Delivery"],
    "Return Call": ["Ops - Order Accepting", "Ops - Order Creating", "Ops - Delivery", "Ops - Returns", "Ops - Inventory"],
    "Pickup Returns": ["Delivery Driver", "Ops - Delivery", "Ops - Returns"],
    "Return drop-off at warehouse": ["Delivery Driver", "Ops - Delivery"],
    "Returns processing / verification": ["Ops - Returns", "Ops - Inventory"],
    "Returns restocking": ["Ops - Returns"],
    "Invoice preparation / create invoice": ["Ops - Accounting"],
    "Debt Collection": ["Ops - Finance", "Ops - Directors"],
    "Distribute Payment": ["Ops - Finance", "Ops - Directors"],
    "Payment Received": ["Ops - Finance", "Ops - Directors"],
    "Discount Approval": ["Ops - Directors"],
    "Purchase Approval": ["Ops - Directors"],
    "Write-off Approval": ["Ops - Directors"],
    "Account Details: Entry": ["Ops - Accounting", "Ops - Finance", "Ops - Directors"],
    "Account Details: Processing": ["Ops - Accounting", "Ops - Finance", "Ops - Directors"],
    "Other": ["Ops - Order Accepting", "Ops - Order Creating", "Ops - Inventory", "Ops - Returns", "Ops - Delivery", "Ops - Accounting", "Ops - Directors", "Ops - Finance", "Delivery Driver"],
}
def current_user_roles():
    return set(frappe.get_all("Has Role", filters={"parent": frappe.session.user}, pluck="role"))
def has_any_role(user_roles, allowed_roles):
    return any(r in user_roles for r in (allowed_roles or []))
def is_admin_override(user_roles):
    return bool("System Manager" in user_roles or "Ops - Directors" in user_roles or frappe.session.user == "Administrator")
def get_assigned_users(task_doc):
    try:
        return json.loads(task_doc.get("_assign") or "[]") or []
    except Exception:
        return []
def user_has_allowed_role(user, allowed_roles):
    user_roles = set(frappe.get_all("Has Role", filters={"parent": user}, pluck="role"))
    return any(r in user_roles for r in (allowed_roles or []))
if doc.task_kind and not doc.task_access_policy:
    doc.task_access_policy = doc.task_kind
if doc.task_access_policy and not frappe.db.exists("Task Access Policy", doc.task_access_policy):
    frappe.throw("Task Access Policy '" + doc.task_access_policy + "' does not exist.")
user_roles = current_user_roles()
allowed_roles = TASK_KIND_ALLOWED_ROLES.get(doc.task_kind) or []
if before and doc.task_kind and not is_admin_override(user_roles):
    if not has_any_role(user_roles, allowed_roles):
        frappe.throw("You are not allowed to edit Task Kind '" + doc.task_kind + "'.")
if is_becoming_completed and doc.task_kind and not is_admin_override(user_roles):
    if not has_any_role(user_roles, allowed_roles):
        frappe.throw("Only " + ", ".join(allowed_roles) + " can complete Task Kind '" + doc.task_kind + "'.")
# Old-flow mandatory attachments (only for tasks NOT linked to a Dispatch Case)
if not doc.dispatch_case:
    if is_becoming_completed and doc.task_kind == "Delivery":
        has_pickup = doc.warehouse_pickup_photo or frappe.db.exists("File", {"attached_to_doctype": "Task", "attached_to_name": doc.name, "attached_to_field": "warehouse_pickup_photo"})
        if not has_pickup:
            frappe.throw("Warehouse Pickup Photo is required to complete a Delivery task.")
    if is_becoming_completed and doc.task_kind == "Return drop-off at warehouse":
        has_dropoff = doc.warehouse_dropoff_photo or frappe.db.exists("File", {"attached_to_doctype": "Task", "attached_to_name": doc.name, "attached_to_field": "warehouse_dropoff_photo"})
        if not has_dropoff:
            frappe.throw("Warehouse Drop-off Photo is required to complete a Return drop-off at warehouse task.")
assigned_users = get_assigned_users(doc)
is_becoming_working = (doc.status == "Working" and before_status != "Working")
# TEMPORARILY DISABLED FOR LAUNCH - assignment validation causes issues with accept workflow
# Will re-enable after launch when workflow is stable
# if doc.task_kind and doc.status not in ("Cancelled", "Open", "Working") and not is_becoming_working:
#     if len(assigned_users) != 1:
#         frappe.throw("Each operational task must be assigned to exactly 1 user. Current count: " + str(len(assigned_users)) + ".")
# if doc.task_kind and len(assigned_users) == 1 and allowed_roles:
#     owner = assigned_users[0]
#     if not user_has_allowed_role(owner, allowed_roles):
#         frappe.throw("Task Kind '" + doc.task_kind + "' must be assigned to a user in: " + ", ".join(allowed_roles) + ".")
# if is_becoming_completed:
#     if len(assigned_users) != 1:
#         frappe.throw("Assign exactly 1 owner before completing this task.")
if is_becoming_completed and not doc.completed_at:
    doc.completed_at = frappe.utils.now_datetime()