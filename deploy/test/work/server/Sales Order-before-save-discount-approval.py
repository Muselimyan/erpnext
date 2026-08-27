# Name: Sales Order-before-save-discount-approval
# Type: DocType Event
# DocType: Sales Order
# Event: Before Save
# Disabled: 0
# ---

DIRECTOR_ROLE = "Ops - Directors"

def is_manual_rate_override(row):
    price_list_rate = float(row.get("price_list_rate") or 0)
    discount_pct = float(row.get("discount_percentage") or 0)
    rate = float(row.get("rate") or 0)

    # If there is no price list rate, do NOT treat entered rate as manual override.
    # Otherwise every item with price_list_rate = 0 and normal entered rate would require approval.
    if price_list_rate <= 0:
        return False

    expected = price_list_rate * (1 - (discount_pct / 100.0))
    return abs(rate - expected) > 0.01


def assign_single_owner(task_name, user):
    # Use frappe.as_json instead of json.dumps because json may not be available in Server Script safe_exec.
    frappe.db.set_value(
        "Task",
        task_name,
        "_assign",
        frappe.as_json([user]),
        update_modified=False
    )

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


def user_has_role(role):
    return bool(
        frappe.db.exists(
            "Has Role",
            {
                "parent": frappe.session.user,
                "role": role,
            }
        )
    )


def has_discount(doc, is_manual_rate_override=is_manual_rate_override):
    if float(doc.get("additional_discount_percentage") or 0) != 0:
        frappe.throw(
            "Do not use header-level additional discount. "
            "Use per-line Discount Percentage so approvals and reporting stay consistent."
        )

    for row in (doc.items or []):
        if float(row.get("discount_percentage") or 0) > 0:
            return True

        if is_manual_rate_override(row):
            return True

    return False


def has_manual_pricing(doc, is_manual_rate_override=is_manual_rate_override):
    for row in (doc.items or []):
        if is_manual_rate_override(row):
            return True

    return False


def discount_signature(doc):
    sig = {
        "additional_discount_percentage": float(doc.get("additional_discount_percentage") or 0),
        "items": [],
    }

    for row in (doc.items or []):
        sig["items"].append({
            "item_code": row.get("item_code"),
            "discount_percentage": float(row.get("discount_percentage") or 0),
            "rate": float(row.get("rate") or 0),
            "price_list_rate": float(row.get("price_list_rate") or 0),
        })

    return sig


before = doc.get_doc_before_save()
discount_present = has_discount(doc)

if not discount_present:
    doc.discount_approval_status = "Not Required"
    doc.discount_approval_task = None
    doc.discount_approval_note = None

    open_tasks = frappe.get_all(
        "Task",
        filters={
            "task_kind": "Discount Approval",
            "sales_order": doc.name,
            "status": ["!=", "Completed"],
        },
        pluck="name",
    )

    for tname in (open_tasks or []):
        desc = frappe.db.get_value("Task", tname, "description") or ""
        note = "Cancelled automatically: discount removed from Sales Order."

        if note not in desc:
            desc = (desc + "\n" if desc else "") + note
            frappe.db.set_value("Task", tname, "description", desc)

        frappe.db.set_value("Task", tname, "status", "Cancelled")

        todos = frappe.get_all(
            "ToDo",
            filters={
                "reference_type": "Task",
                "reference_name": tname,
                "status": "Open",
            },
            pluck="name",
        )

        for td in (todos or []):
            frappe.db.set_value("ToDo", td, "status", "Cancelled")

else:
    sig_preserved = False

    if before and before.get("discount_approval_status") in ("Approved", "Rejected"):
        before_sig = discount_signature(before)
        after_sig = discount_signature(doc)

        if before_sig == after_sig:
            doc.discount_approval_status = before.discount_approval_status
            doc.discount_approval_task = before.discount_approval_task
            doc.discount_approval_note = before.discount_approval_note
            sig_preserved = True

    if not sig_preserved:
        doc.discount_approval_status = "Pending"
        doc.discount_approval_task = None
        doc.discount_approval_note = None

        if has_manual_pricing(doc):
            if not (
                user_has_role("Ops - Accounting")
                or user_has_role("Ops - Directors")
            ):
                frappe.throw(
                    "Manual rate changes are allowed only for Accounting/Directors (Doc 09 policy)."
                )

            if not (doc.manual_pricing_reason or "").strip():
                frappe.throw(
                    "Manual Pricing Reason is required when any line rate is manually overridden."
                )

        existing = frappe.get_all(
            "Task",
            filters={
                "task_kind": "Discount Approval",
                "sales_order": doc.name,
                "status": ["!=", "Completed"],
            },
            pluck="name",
        )

        if existing:
            doc.discount_approval_task = existing[0]

        else:
            subject = "Discount Approval - SO " + doc.name

            task = frappe.new_doc("Task")
            task.subject = subject
            task.status = "Open"
            task.task_kind = "Discount Approval"
            task.task_access_policy = "Discount Approval"
            task.sales_order = doc.name
            task.customer = doc.customer

            task.insert(ignore_permissions=True)

            director_users = frappe.get_all(
                "Has Role",
                filters={
                    "role": DIRECTOR_ROLE,
                },
                pluck="parent",
            )

            director_users = sorted(list(set(director_users or [])))

            director_users = [
                u
                for u in director_users
                if u not in ("Administrator", "Guest")
                and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
            ]

            if not director_users:
                frappe.throw(
                    "No director users found. Create at least one User with role '"
                    + DIRECTOR_ROLE
                    + "'."
                )

            assign_single_owner(task.name, director_users[0])
            doc.discount_approval_task = task.name