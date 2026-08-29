# Name: Task-before-save-policy
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

def task_has_image(task_name):
    """Check if a Task has at least one attached image File record."""
    exts = (".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif")
    files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": task_name}, fields=["file_url"])
    images = [f.file_url for f in files if (f.file_url or "").lower().split("?")[0].endswith(exts)]
    print(f"[Photo] task_has_image({task_name}): total_files={len(files)}, images={len(images)}, urls={images[:5]}")
    return len(images) > 0

before = doc.get_doc_before_save()
before_status = before.status if before else None
is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")
DIRECTOR_ROLE = "Ops - Directors"

# Read role and team mappings from Task Access Policy (single source of truth)
allowed_roles = []
default_team = ""
policy = None
if doc.task_kind:
    try:
        policy = frappe.get_doc("Task Access Policy", doc.task_kind)
        allowed_roles = [r.role for r in (policy.allowed_roles or [])]
        default_team = policy.default_team_user or ""
    except Exception:
        pass

print(f"[Policy] {frappe.utils.now()} task={doc.name} kind={doc.task_kind} policy_found={'yes' if policy else 'no'} roles={len(allowed_roles)} default_team={default_team}")

def current_user_roles():
    return set(frappe.get_all("Has Role", filters={"parent": frappe.session.user}, pluck="role"))
def has_any_role(user_roles, allowed_roles):
    return any(r in user_roles for r in (allowed_roles or []))
def is_admin_override(user_roles):
    return bool("System Manager" in user_roles or "Ops - Directors" in user_roles or frappe.session.user == "Administrator")
def get_assigned_users(task_doc):
    try:
        return json.loads(task_doc.get("_assign") or "[]") or []
    except Exception:
        return []
def user_has_allowed_role(user, allowed_roles):
    user_roles = set(frappe.get_all("Has Role", filters={"parent": user}, pluck="role"))
    return any(r in user_roles for r in (allowed_roles or []))

# Default team user assignment: if task_kind is set and custom_assigned_to is empty, assign to default team user
if doc.task_kind and not doc.custom_assigned_to:
    if default_team:
        doc.custom_assigned_to = default_team
        print(f"[Policy] {frappe.utils.now()} task={doc.name} default_assign: team={default_team}")

# Always sync _assign from custom_assigned_to (single source of truth)
if doc.custom_assigned_to:
    doc.set("_assign", json.dumps([doc.custom_assigned_to]))
    print(f"[Policy] {frappe.utils.now()} task={doc.name} assign_sync: user={doc.custom_assigned_to}")
else:
    doc.set("_assign", "[]")

if doc.task_kind and not doc.task_access_policy:
    doc.task_access_policy = doc.task_kind
if doc.task_access_policy and not frappe.db.exists("Task Access Policy", doc.task_access_policy):
    frappe.throw("Task Access Policy '" + doc.task_access_policy + "' does not exist.")
user_roles = current_user_roles()
if before and doc.task_kind and not is_admin_override(user_roles):
    if not has_any_role(user_roles, allowed_roles):
        print(f"[Policy] {frappe.utils.now()} task={doc.name} role_check: user={frappe.session.user} allowed={allowed_roles} result=BLOCKED")
        frappe.throw("You are not allowed to edit Task Kind '" + doc.task_kind + "'.")
if is_becoming_completed and doc.task_kind and not is_admin_override(user_roles):
    if not has_any_role(user_roles, allowed_roles):
        print(f"[Policy] {frappe.utils.now()} task={doc.name} completing: user={frappe.session.user} allowed={allowed_roles} result=BLOCKED")
        frappe.throw("Only " + ", ".join(allowed_roles) + " can complete Task Kind '" + doc.task_kind + "'.")
# Old-flow mandatory attachments (only for tasks NOT linked to a Dispatch Case)
if not doc.dispatch_case:
    if is_becoming_completed and doc.task_kind == "Delivery":
        has_img = task_has_image(doc.name)
        print(f"[Photo] {frappe.utils.now()} task={doc.name} policy Delivery gate (no DC): has_image={has_img}, result={'PASS' if has_img else 'BLOCKED'}")
        if not has_img:
            frappe.throw("At least one photo is required to complete a Delivery task.")
    if is_becoming_completed and doc.task_kind == "Return drop-off at warehouse":
        has_img = task_has_image(doc.name)
        print(f"[Photo] {frappe.utils.now()} task={doc.name} policy Return drop-off gate (no DC): has_image={has_img}, result={'PASS' if has_img else 'BLOCKED'}")
        if not has_img:
            frappe.throw("At least one photo is required to complete a Return drop-off at warehouse task.")
assigned_users = get_assigned_users(doc)
is_becoming_working = (doc.status == "Working" and before_status != "Working")
# TEMPORARILY DISABLED FOR LAUNCH - assignment validation causes issues with accept workflow
# Will re-enable after launch when workflow is stable
# if doc.task_kind and doc.status not in ("Cancelled", "Open", "Working") and not is_becoming_working:
#     if len(assigned_users) != 1:
#         frappe.throw("Each operational task must be assigned to exactly 1 user. Current count: " + str(len(assigned_users)) + ".")
# if doc.task_kind and len(assigned_users) == 1 and allowed_roles:
#     owner = assigned_users[0]
#     if not user_has_allowed_role(owner, allowed_roles):
#         frappe.throw("Task Kind '" + doc.task_kind + "' must be assigned to a user in: " + ", ".join(allowed_roles) + ".")
# if is_becoming_completed:
#     if len(assigned_users) != 1:
#         frappe.throw("Assign exactly 1 owner before completing this task.")
if is_becoming_completed and not doc.completed_at:
    doc.completed_at = frappe.utils.now_datetime()
