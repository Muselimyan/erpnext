# Name: task_list_filtered
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

my_tasks = int(frappe.form_dict.get("my_tasks") or 0)
open_tasks = int(frappe.form_dict.get("open_tasks") or 0)
completed = int(frappe.form_dict.get("completed") or 0)

user = frappe.session.user
role_rows = frappe.get_all("Has Role", filters={"parenttype": "User", "parent": user}, fields=["role"], limit_page_length=0)
user_roles = set([r.role for r in role_rows])
is_admin = user == "Administrator" or "System Manager" in user_roles

print(f"[List] {frappe.utils.now()} user={user} my_tasks={my_tasks} open_tasks={open_tasks} completed={completed} is_admin={is_admin}")

# Read role and team mappings from Task Access Policy (single source of truth)
policies = frappe.get_all("Task Access Policy",
    fields=["name", "default_team_user"],
    limit_page_length=0)
all_role_rows = frappe.get_all("Task Access Policy Role",
    fields=["parent", "role"],
    limit_page_length=0)

# Build role map from child table
role_map = {}
for row in all_role_rows:
    if row.parent not in role_map:
        role_map[row.parent] = []
    role_map[row.parent].append(row.role)

allowed_kinds = []
team_placeholders = []
seen_tp = set()
for p in policies:
    roles = role_map.get(p.name) or []
    if is_admin or any(r in user_roles for r in roles):
        allowed_kinds.append(p.name)
    elif not roles:
        # Permissive fallback: kinds with no roles are accessible (matches save/accept behavior)
        allowed_kinds.append(p.name)
    if p.default_team_user and p.default_team_user not in seen_tp:
        team_placeholders.append(p.default_team_user)
        seen_tp.add(p.default_team_user)

print(f"[List] {frappe.utils.now()} policies={len(policies)} role_rows={len(all_role_rows)} allowed_kinds={len(allowed_kinds)} team_placeholders={len(team_placeholders)}")

if not allowed_kinds and not is_admin:
    frappe.response["message"] = []
    raise SystemExit

conditions = []
kind_list = ", ".join(["'" + k.replace("'", "''") + "'" for k in allowed_kinds])
none_selected = (not my_tasks and not open_tasks and not completed)

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

    placeholder_conditions = " OR ".join(["_assign LIKE '%" + tp + "%'" for tp in team_placeholders])
    safe_user = user.replace("'", "''")
    team_available_sql = "(_assign IS NULL OR _assign = '' OR _assign = '[]' OR _assign LIKE '%" + safe_user + "%' OR (" + placeholder_conditions + "))"

    if is_admin:
        role_match_sql = "1=1"
    else:
        role_match_sql = "(task_kind IN (" + kind_list + ") OR task_kind IS NULL OR task_kind = '')"

    if has_my:
        my_sql = "(_assign LIKE '%" + safe_user + "%')"
        or_clauses.append(my_sql)

    if has_open or has_completed:
        team_role_sql = "(" + role_match_sql + " AND " + team_available_sql + ")"
        or_clauses.append(team_role_sql)

    assignment_sql = "(" + " OR ".join(or_clauses) + ")" if or_clauses else "1=1"
    conditions.append(status_sql)
    conditions.append(assignment_sql)

where_clause = " AND ".join(conditions) if conditions else "1=1"
sql = "SELECT name FROM `tabTask` WHERE " + where_clause + " ORDER BY modified DESC LIMIT 500"
results = frappe.db.sql(sql, as_dict=True)

print(f"[List] {frappe.utils.now()} result_count={len(results)}")

frappe.response["message"] = [r["name"] for r in results]
