# RETIRED AND DELETED FROM THE SERVER (W10).
#
# This Server Script no longer exists on test. The `Distribute Payment` task
# kind it belonged to has been retired: zero tasks were ever created with it,
# the script was disabled from the start, and nothing created it. Group 3's
# audit recorded it as "intentionally out of active flow, do not enable unless
# the business flow changes" (B-02) -- that change never came.
#
# The file is kept only as a record of what the flow would have done. Do not
# redeploy it; `deploy/test/deploy/group-11-financial-tail/w10-retire-distribute-payment.ps1`
# removes the Select option, the Task Access Policy record and the script itself.
#
# Payment allocation now happens in two places instead: task_record_payment
# logic inside Task-before-save-payment-recording (allocating a collection
# payment across live invoices, oldest first) and task_commit_invoice
# (consuming unallocated advances, case-tagged credit first).
#
# ORIGINAL HEADER BELOW
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