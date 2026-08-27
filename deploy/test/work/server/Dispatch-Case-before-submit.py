# Name: Dispatch-Case-before-submit
# Type: DocType Event
# DocType: Dispatch Case
# Event: Before Submit
# Disabled: 0
# ---

if not doc.case_items:
	frappe.throw('Add at least one item before submitting.')
if doc.status not in ('Draft', 'Confirmed'):
	frappe.throw('Cannot submit a Dispatch Case in status: ' + doc.status)
if doc.status == 'Draft':
	doc.status = 'Confirmed'
# Do NOT create Pack task here - it will be created when Order Entry task is completed