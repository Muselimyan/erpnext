TASK_KIND_ALLOWED_ROLES = {
    "Order entry": ["Ops - Order Accepting", "Ops - Order Creating"],
    "Pack / prepare items": ["Ops - Inventory"],
    "Dispatch picking / hand-off": ["Ops - Delivery"],
    "Delivery": ["Delivery Driver", "Ops - Delivery"],
    "Return to warehouse (aborted delivery / cancelled order)": ["Delivery Driver", "Ops - Delivery"],
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
    "Other": ["Ops - Order Accepting", "Ops - Order Creating", "Ops - Inventory", "Ops - Returns", "Ops - Delivery", "Ops - Accounting", "Ops - Directors", "Ops - Finance", "Delivery Driver"],
    "Return Call": ["Ops - Returns", "Ops - Delivery"],
}

TEAM_PLACEHOLDERS = [
    "inventory.team@example.com",
    "delivery.team@example.com",
    "returns.team@example.com",
    "accounting.team@example.com",
    "finance.team@example.com",
    "order.creation.team@example.com",
    "order.team@example.com",
    "directors.team@example.com",
]

my_tasks = int(frappe.form_dict.get("my_tasks") or 0)
open_tasks = int(frappe.form_dict.get("open_tasks") or 0)
completed = int(frappe.form_dict.get("completed") or 0)

user = frappe.session.user
user_role_list = frappe.get_all("Has Role", filters={"parent": user}, pluck="role")
is_admin = user == "Administrator" or "System Manager" in user_role_list

allowed_kinds = []
for kind, roles in TASK_KIND_ALLOWED_ROLES.items():
    if is_admin or any(r in user_role_list for r in roles):
        allowed_kinds.append(kind)

if not allowed_kinds and not is_admin:
    frappe.response["message"] = []
else:
    kind_list = ", ".join(["'" + k.replace("'", "''") + "'" for k in allowed_kinds])
    none_selected = (not my_tasks and not open_tasks and not completed)

    conditions = []

    if none_selected:
        if is_admin:
            conditions.append("1=1")
        else:
            conditions.append("(task_kind IN (" + kind_list + ") OR task_kind IS NULL OR task_kind = '')")
    else:
        or_clauses = []
        has_open = bool(open_tasks)
        has_completed = bool(completed)
        has_my = bool(my_tasks)

        if has_open and has_completed:
            status_sql = "status != 'Cancelled'"
        elif has_completed and not has_open:
            status_sql = "status = 'Completed'"
        else:
            status_sql = "status NOT IN ('Completed', 'Cancelled')"

        placeholder_conditions = " OR ".join(["_assign LIKE '%" + tp + "%'" for tp in TEAM_PLACEHOLDERS])
        user_escaped = user.replace("'", "''")
        team_available_sql = "(_assign IS NULL OR _assign = '' OR _assign = '[]' OR _assign LIKE '%" + user_escaped + "%' OR (" + placeholder_conditions + "))"

        if is_admin:
            role_match_sql = "1=1"
        else:
            role_match_sql = "(task_kind IN (" + kind_list + ") OR task_kind IS NULL OR task_kind = '')"

        if has_my:
            my_sql = "(_assign LIKE '%" + user_escaped + "%')"
            or_clauses.append(my_sql)

        if has_open or has_completed:
            team_role_sql = "(" + role_match_sql + " AND " + team_available_sql + ")"
            or_clauses.append(team_role_sql)

        if or_clauses:
            assignment_sql = "(" + " OR ".join(or_clauses) + ")"
        else:
            assignment_sql = "1=1"

        conditions.append(status_sql)
        conditions.append(assignment_sql)

    where_clause = " AND ".join(conditions) if conditions else "1=1"
    sql = "SELECT name FROM `tabTask` WHERE " + where_clause + " ORDER BY modified DESC LIMIT 500"
    results = frappe.db.sql(sql, as_dict=True)
    frappe.response["message"] = [r["name"] for r in results]
