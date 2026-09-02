# Name: task_list_filtered
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

# Returns visibility metadata for the Task list toggle filter system.
# The client injects these as filters into Frappe's standard reportview.get
# pipeline, which handles pagination, sorting, and rendering natively.
#
# Response: { allowed_kinds, team_placeholders, is_admin, user }

user = frappe.session.user
role_rows = frappe.get_all("Has Role",
    filters={"parenttype": "User", "parent": user},
    fields=["role"], limit_page_length=0)
user_roles = set([r.role for r in role_rows])
is_admin = user == "Administrator" or "System Manager" in user_roles

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
        # Permissive fallback: kinds with no roles defined are accessible
        # (matches save/accept behavior in Task-before-save-policy)
        allowed_kinds.append(p.name)
    if p.default_team_user and p.default_team_user not in seen_tp:
        team_placeholders.append(p.default_team_user)
        seen_tp.add(p.default_team_user)

print(f"[List] {frappe.utils.now()} user={user} is_admin={is_admin} allowed_kinds={len(allowed_kinds)} team_placeholders={len(team_placeholders)}")

frappe.response["message"] = {
    "allowed_kinds": allowed_kinds,
    "team_placeholders": team_placeholders,
    "is_admin": is_admin,
    "user": user
}
