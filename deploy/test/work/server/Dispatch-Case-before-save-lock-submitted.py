# Name: Dispatch-Case-before-save-lock-submitted
# Type: DocType Event
# DocType: Dispatch Case
# Event: Before Save
# Disabled: 0
# ---

# Only Directors/Admins can edit ALREADY submitted Dispatch Cases
# Allow initial creation and first submit for everyone
before = doc.get_doc_before_save()
before_docstatus = before.docstatus if before else 0
if before_docstatus == 1:
	user_roles = [r[0] for r in frappe.db.sql('SELECT role FROM `tabHas Role` WHERE parent=%s', (frappe.session.user,))]
	privileged = ['Ops - Directors', 'System Manager', 'Administrator']
	is_privileged = False
	for role in privileged:
		if role in user_roles:
			is_privileged = True
			break
	if not is_privileged and not doc.flags.ignore_permissions:
		frappe.throw('Only Directors or Administrators can edit a submitted Dispatch Case.')