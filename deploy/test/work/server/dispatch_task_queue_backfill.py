# Name: dispatch_task_queue_backfill
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

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
team_placeholders = ["inventory.team@example.com", "delivery.team@example.com", "returns.team@example.com", "accounting.team@example.com", "finance.team@example.com", "order.creation.team@example.com", "order.team@example.com", "directors.team@example.com"]
limit = int(frappe.form_dict.get("limit") or 200)
updated = 0
scanned = 0
tasks = frappe.get_all(
    "Task",
    filters={"dispatch_case": ["is", "set"], "status": ["not in", ["Completed", "Cancelled", "Template"]]},
    fields=["name", "task_kind", "status", "_assign", "custom_is_team_queue_task", "custom_team_queue_role", "custom_team_queue_status"],
    limit_page_length=limit,
)
for t in tasks:
    scanned += 1
    role = TASK_KIND_TEAM_ROLE.get(t.task_kind)
    if not role:
        continue
    try:
        assigned = frappe.parse_json(t.get("_assign") or "[]") or []
    except Exception:
        assigned = []
    real_assigned = [u for u in assigned if u not in team_placeholders]
    queue_status = "Accepted" if real_assigned else "Open For Team"
    values = {
        "custom_is_team_queue_task": 1,
        "custom_team_queue_role": role,
        "custom_team_queue_status": queue_status,
    }
    if real_assigned:
        values["custom_accepted_by"] = real_assigned[0]
    frappe.db.set_value("Task", t.name, values, update_modified=False)
    updated += 1
frappe.response["message"] = {"ok": True, "scanned": scanned, "updated": updated}