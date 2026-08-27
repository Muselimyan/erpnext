# Name: Task-team-queue-notify
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 1
# ---

def run_script():
    TASK_KIND_TEAM_ROLE = {
        "Order entry": "Ops - Order Accepting",
        "Pack / prepare items": "Ops - Inventory",
        "Dispatch picking / hand-off": "Ops - Delivery",
        "Delivery": "Delivery Driver",
        "Pickup Returns": "Delivery Driver",
        "Return drop-off at warehouse": "Delivery Driver",
        "Returns processing / verification": "Ops - Returns",
        "Returns restocking": "Ops - Returns",
        "Invoice preparation / create invoice": "Ops - Accounting",
        "Debt Collection": "Ops - Finance",
        "Discount Approval": "Ops - Directors",
        "Purchase Approval": "Ops - Directors",
        "Write-off Approval": "Ops - Directors",
    }
    team_role = doc.get("custom_team_queue_role") or TASK_KIND_TEAM_ROLE.get(doc.get("task_kind"))
    if not team_role:
        return
    if doc.status in ("Completed", "Cancelled", "Template"):
        if doc.get("custom_team_queue_status") != "Closed":
            frappe.db.set_value("Task", doc.name, "custom_team_queue_status", "Closed", update_modified=False)
        return
    assigned = []
    try:
        assigned = frappe.parse_json(doc.get("_assign") or "[]") or []
    except Exception:
        assigned = []
    team_placeholders = ["inventory.team@example.com", "delivery.team@example.com", "returns.team@example.com", "accounting.team@example.com", "finance.team@example.com", "order.creation.team@example.com", "order.team@example.com"]
    real_assigned = [u for u in assigned if u not in team_placeholders]
    updates = {}
    if not doc.get("custom_is_team_queue_task"):
        updates["custom_is_team_queue_task"] = 1
    if not doc.get("custom_team_queue_role"):
        updates["custom_team_queue_role"] = team_role
    if real_assigned:
        updates["custom_team_queue_status"] = "Accepted"
        updates["custom_accepted_by"] = real_assigned[0]
    else:
        updates["custom_team_queue_status"] = "Open For Team"
    if updates:
        frappe.db.set_value("Task", doc.name, updates, update_modified=False)
    if real_assigned or doc.get("custom_team_notified"):
        return
    users = frappe.get_all("Has Role", filters={"role": team_role, "parenttype": "User"}, pluck="parent")
    created = 0
    for user in users or []:
        enabled = frappe.db.get_value("User", user, "enabled")
        if not enabled:
            continue
        exists = frappe.db.exists("ToDo", {"reference_type": "Task", "reference_name": doc.name, "allocated_to": user, "status": "Open"})
        if exists:
            continue
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = user
        todo.reference_type = "Task"
        todo.reference_name = doc.name
        todo.description = "Team task available: " + (doc.subject or doc.name)
        todo.assigned_by = frappe.session.user
        todo.insert(ignore_permissions=True)
        created += 1
    if created:
        frappe.db.set_value("Task", doc.name, "custom_team_notified", 1, update_modified=False)
run_script()