# Name: Task-dispatch-queue-integration
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 1
# ---

def run_script():
    if not doc.get("dispatch_case"):
        return
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
    role = TASK_KIND_TEAM_ROLE.get(doc.get("task_kind"))
    if not role:
        return
    if doc.status in ("Completed", "Cancelled", "Template"):
        frappe.db.set_value("Task", doc.name, "custom_team_queue_status", "Closed", update_modified=False)
        return
    team_placeholders = ["inventory.team@example.com", "delivery.team@example.com", "returns.team@example.com", "accounting.team@example.com", "finance.team@example.com", "order.creation.team@example.com", "order.team@example.com", "directors.team@example.com"]
    try:
        assigned = frappe.parse_json(doc.get("_assign") or "[]") or []
    except Exception:
        assigned = []
    real_assigned = [u for u in assigned if u not in team_placeholders]
    values = {
        "custom_is_team_queue_task": 1,
        "custom_team_queue_role": role,
        "custom_team_queue_status": "Accepted" if real_assigned else "Open For Team",
    }
    if real_assigned:
        values["custom_accepted_by"] = real_assigned[0]
    frappe.db.set_value("Task", doc.name, values, update_modified=False)
run_script()