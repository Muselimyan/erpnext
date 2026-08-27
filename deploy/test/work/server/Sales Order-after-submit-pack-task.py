# Name: Sales Order-after-submit-pack-task
# Type: DocType Event
# DocType: Sales Order
# Event: After Submit
# Disabled: 0
# ---

def run_script(doc):
    INVENTORY_ROLE = "Ops - Inventory"

    def assign_single_owner(task_name, user):
        frappe.db.set_value("Task", task_name, "_assign", frappe.as_json([user]), update_modified=False)
        other_todos = frappe.get_all(
            "ToDo",
            filters={
                "reference_type": "Task",
                "reference_name": task_name,
                "allocated_to": ["!=", user],
                "status": "Open",
            },
            pluck="name",
        )
        for td in (other_todos or []):
            frappe.db.set_value("ToDo", td, "status", "Cancelled")
        if not frappe.db.exists(
            "ToDo",
            {"reference_type": "Task", "reference_name": task_name, "allocated_to": user, "status": "Open"},
        ):
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = user
            todo.reference_type = "Task"
            todo.reference_name = task_name
            todo.description = frappe.db.get_value("Task", task_name, "subject") or task_name
            todo.assigned_by = frappe.session.user
            todo.insert(ignore_permissions=True)

    approval_status = doc.discount_approval_status or "Not Required"
    if approval_status not in ("Not Required", "Approved"):
        return

    existing = frappe.get_all(
        "Task",
        filters={
            "task_kind": "Pack / prepare items",
            "sales_order": doc.name,
            "status": ["!=", "Cancelled"],
        },
        pluck="name",
    )
    if existing:
        return

    task = frappe.new_doc("Task")
    task.subject = "Pack - " + doc.name
    task.status = "Open"
    task.task_kind = "Pack / prepare items"
    task.task_access_policy = "Pack / prepare items"
    task.sales_order = doc.name
    task.customer = doc.customer or ""
    task.insert(ignore_permissions=True)

    inventory_users = frappe.get_all("Has Role", filters={"role": INVENTORY_ROLE}, pluck="parent")
    inventory_users = sorted(list(set(inventory_users or [])))
    inventory_users = [
        u for u in inventory_users
        if u not in ("Administrator", "Guest") and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
    ]
    if inventory_users:
        assign_single_owner(task.name, inventory_users[0])

run_script(doc)