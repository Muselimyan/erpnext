# Name: Payment Entry-after-submit-distribute-payment
# Type: DocType Event
# DocType: Payment Entry
# Event: After Submit
# Disabled: 1
# ---

DIRECTOR_ROLE = "Ops - Directors"

def assign_single_owner(task_name, user):
    frappe.db.set_value("Task", task_name, "_assign", json.dumps([user]), update_modified=False)

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
        {
            "reference_type": "Task",
            "reference_name": task_name,
            "allocated_to": user,
            "status": "Open",
        },
    ):
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = user
        todo.reference_type = "Task"
        todo.reference_name = task_name
        todo.description = frappe.db.get_value("Task", task_name, "subject") or task_name
        todo.assigned_by = frappe.session.user
        todo.insert(ignore_permissions=True)

if doc.party_type == "Customer" and doc.payment_type == "Receive":
    director_users = frappe.get_all(
        "Has Role",
        filters={"role": DIRECTOR_ROLE},
        pluck="parent",
    )
    director_users = sorted(list(set(director_users or [])))

    director_users = [
        u
        for u in director_users
        if u not in ("Administrator", "Guest") and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
    ]

    if director_users:
        assigned_director = director_users[0]

        existing = frappe.get_all(
            "Task",
            filters={
                "task_kind": "Distribute Payment",
                "payment_entry": doc.name,
                "status": ["!=", "Completed"],
            },
            pluck="name",
        )

        if not existing:
            task = frappe.new_doc("Task")
            task.subject = f"Distribute Payment â€” PE {doc.name}"
            task.status = "Open"
            task.task_kind = "Distribute Payment"
            task.task_access_policy = "Distribute Payment"
            task.payment_entry = doc.name
            task.customer = doc.party

            task.insert(ignore_permissions=True)

            assign_single_owner(task.name, assigned_director)