# Name: Dispatch-Case-after-save
# Type: DocType Event
# DocType: Dispatch Case
# Event: After Save
# Disabled: 0
# ---

if doc.status == "Awaiting Approval" and not doc.discount_approval_task:
    existing = frappe.db.exists("Task", {"dispatch_case": doc.name, "task_kind": "Discount Approval", "status": ["not in", ["Completed", "Cancelled"]]})
    if not existing:
        disc_lines = "\n".join(
            f"- {r.item_code} x{r.dispatched_qty}: {r.unit_price} AMD ({r.discount_pct}% off)"
            for r in doc.case_items if float(r.discount_pct or 0) > 0
        )
        t = frappe.get_doc({
            "doctype": "Task",
            "subject": f"Discount Approval: {doc.name} â€” {doc.customer}",
            "task_kind": "Discount Approval",
            "task_access_policy": "Discount Approval",
            "dispatch_case": doc.name,
            "customer": doc.customer,
            "description": f"Review and approve or reject discounts.\n\n{disc_lines}",
        })
        t.flags.ignore_permissions = True
        t.insert()
        frappe.db.set_value("Dispatch Case", doc.name, "discount_approval_task", t.name)
        # FIXED: Update _assign via db (assign_to module not available in RestrictedPython)
        frappe.db.set_value("Task", t.name, "_assign", json.dumps(["directors.team@example.com"]))
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = "directors.team@example.com"
        todo.reference_type = "Task"
        todo.reference_name = t.name
        todo.description = t.subject
        todo.assigned_by = frappe.session.user
        todo.flags.ignore_permissions = True
        todo.insert()