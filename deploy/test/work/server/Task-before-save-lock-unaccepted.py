# Name: Task-before-save-lock-unaccepted
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

# Lock: all tasks require acceptance before editing
# Also validate assignment: must be assigned to a user OR a team
# When assignment changes, reset acceptance so new assignee must accept
before = doc.get_doc_before_save()
if before and not doc.flags.ignore_permissions:
    old_user = before.custom_assigned_to or ""
    old_team = before.custom_team_queue_role or ""
    new_user = doc.custom_assigned_to or ""
    new_team = doc.custom_team_queue_role or ""
    if (old_user != new_user) or (old_team != new_team):
        doc.custom_accepted_by = ""
        doc.custom_accepted_at = None
        doc.status = "Open"

if not doc.flags.ignore_permissions and frappe.session.user != "Administrator":
    user_roles = [r[0] for r in frappe.db.sql('SELECT role FROM `tabHas Role` WHERE parent=%s', (frappe.session.user,))]
    if 'System Manager' not in user_roles:
        # Assignment validation (mandatory)
        if not doc.custom_assigned_to and not doc.custom_team_queue_role:
            frappe.throw('Task must be assigned to either a User or a Team (Role).')
        if doc.custom_assigned_to and doc.custom_team_queue_role:
            frappe.throw('Task can only be assigned to a User OR a Team, not both.')
        # Lock: must accept before editing (skip for new docs being created)
        if not doc.is_new():
            accepted_by = doc.custom_accepted_by or frappe.db.get_value('Task', doc.name, 'custom_accepted_by')
            if not accepted_by:
                frappe.throw('You must accept this task before you can edit it. Click Accept / Start Task first.')
            if accepted_by != frappe.session.user:
                frappe.throw('Only the user who accepted this task (' + accepted_by + ') can edit it.')