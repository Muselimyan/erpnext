# Name: Task-before-save-lock-unaccepted
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

# Lock: all tasks require acceptance before editing
# When assignment changes, reset acceptance so new assignee must accept
before = doc.get_doc_before_save()
if before and not doc.flags.ignore_permissions:
    old_user = before.custom_assigned_to or ""
    new_user = doc.custom_assigned_to or ""
    if old_user != new_user:
        print(f"[Lock] {frappe.utils.now()} task={doc.name} assignment_changed: {old_user} -> {new_user} resetting acceptance")
        doc.custom_accepted_by = ""
        doc.custom_accepted_at = None
        doc.status = "Open"

if not doc.flags.ignore_permissions and frappe.session.user != "Administrator":
    user_roles = [r[0] for r in frappe.db.sql('SELECT role FROM `tabHas Role` WHERE parent=%s', (frappe.session.user,))]
    if 'System Manager' not in user_roles:
        # Assignment validation: task must have custom_assigned_to set
        if not doc.custom_assigned_to:
            frappe.throw('Task must be assigned to a User or Team.')
        # Lock: must accept before editing (skip for new docs being created)
        if not doc.is_new():
            accepted_by = doc.custom_accepted_by or frappe.db.get_value('Task', doc.name, 'custom_accepted_by')
            if not accepted_by:
                print(f"[Lock] {frappe.utils.now()} task={doc.name} LOCKED: user={frappe.session.user} reason=not_accepted")
                frappe.throw('You must accept this task before you can edit it. Click Accept / Start Task first.')
            if accepted_by != frappe.session.user:
                print(f"[Lock] {frappe.utils.now()} task={doc.name} LOCKED: user={frappe.session.user} accepted_by={accepted_by} reason=wrong_user")
                frappe.throw('Only the user who accepted this task (' + accepted_by + ') can edit it.')
            print(f"[Lock] {frappe.utils.now()} task={doc.name} lock_check: user={frappe.session.user} accepted_by={accepted_by} result=PASS")
