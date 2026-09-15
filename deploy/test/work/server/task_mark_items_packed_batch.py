# Name: task_mark_items_packed_batch
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

case_name = frappe.form_dict.get('case_name')
packed_json = frappe.form_dict.get('packed_indices') or '[]'
packed_indices = json.loads(packed_json)

if not case_name:
        frappe.throw('Dispatch Case is required.')

# Deterministic ownership check. This previously used limit_page_length=1 with
# no order_by, so when a case had more than one open task WHICH task was
# checked depended on whatever row order MariaDB returned. Filtering by the
# caller makes it deterministic.
mytasks = frappe.get_all(
        'Task',
        filters={'dispatch_case': case_name, 'custom_accepted_by': frappe.session.user,
                 'status': ['not in', ['Completed', 'Cancelled']]},
        fields=['name', 'task_kind'],
        limit_page_length=0,
)
if not mytasks:
        frappe.throw('You must accept a task for this Dispatch Case before making changes.')
acting_kind = mytasks[0].task_kind or ''

case = frappe.get_doc('Dispatch Case', case_name)

# The acting kind is derived from the caller's own accepted task, NOT from a
# client-supplied `task_kind` parameter as it was before. Trusting the client
# meant a user holding only a Pack task could pass
# task_kind='Returns processing / verification' and overwrite returned_qty and
# used_qty on the case.
is_returns = (acting_kind == 'Returns processing / verification')

for idx, row in enumerate(case.case_items):
        required_qty = float(row.dispatched_qty or 0)
        if is_returns:
                if idx in packed_indices:
                        row.returned_qty = required_qty
                else:
                        row.returned_qty = 0
                row.used_qty = float(row.dispatched_qty or 0) - float(row.returned_qty or 0) - float(row.lost_damaged_qty or 0)
        else:
                row.custom_scanned_qty = required_qty if idx in packed_indices else 0

case.flags.ignore_permissions = True
case.flags.ignore_validate_update_after_submit = True
case.save()

frappe.response['message'] = {'ok': True, 'total': len(case.case_items), 'packed': len(packed_indices)}