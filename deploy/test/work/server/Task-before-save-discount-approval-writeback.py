# Name: Task-before-save-discount-approval-writeback
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

def run_script(doc):
    before = doc.get_doc_before_save()
    before_status = before.status if before else None

    is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

    if not is_becoming_completed:
        return

    if doc.task_kind != "Discount Approval":
        return

    if not doc.sales_order:
        frappe.throw("Discount Approval task must be linked to a Sales Order.")

    if doc.approval_outcome not in ("Approved", "Rejected"):
        frappe.throw("Approval Outcome must be set to Approved or Rejected before completing the task.")

    frappe.db.set_value(
        "Sales Order",
        doc.sales_order,
        {
            "discount_approval_status": doc.approval_outcome,
            "discount_approval_note": doc.approval_note or "",
            "discount_approval_task": doc.name,
        },
    )

    if doc.approval_outcome != "Approved":
        return

    so_docstatus = frappe.db.get_value("Sales Order", doc.sales_order, "docstatus")
    if int(so_docstatus or 0) != 1:
        return

    existing_pack = frappe.get_all(
        "Task",
        filters={
            "task_kind": "Pack / prepare items",
            "sales_order": doc.sales_order,
            "status": ["!=", "Cancelled"],
        },
        pluck="name",
    )
    if existing_pack:
        return

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

    so_customer = frappe.db.get_value("Sales Order", doc.sales_order, "customer")
    pack_task = frappe.new_doc("Task")
    pack_task.subject = "Pack - " + doc.sales_order
    pack_task.status = "Open"
    pack_task.task_kind = "Pack / prepare items"
    pack_task.task_access_policy = "Pack / prepare items"
    pack_task.sales_order = doc.sales_order
    pack_task.customer = so_customer or ""
    pack_task.insert(ignore_permissions=True)

    inventory_users = frappe.get_all("Has Role", filters={"role": INVENTORY_ROLE}, pluck="parent")
    inventory_users = sorted(list(set(inventory_users or [])))
    inventory_users = [
        u for u in inventory_users
        if u not in ("Administrator", "Guest") and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
    ]
    if inventory_users:
        assign_single_owner(pack_task.name, inventory_users[0])

run_script(doc)