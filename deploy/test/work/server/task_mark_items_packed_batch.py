# Name: task_mark_items_packed_batch
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

case_name = frappe.form_dict.get('case_name')
packed_json = frappe.form_dict.get('packed_indices') or '[]'
packed_indices = json.loads(packed_json)
task_kind = frappe.form_dict.get('task_kind') or ''

if not case_name:
        frappe.throw('Dispatch Case is required.')

case = frappe.get_doc('Dispatch Case', case_name)
is_returns = (task_kind == 'Returns processing / verification')

for idx, row in enumerate(case.case_items):
        required_qty = float(row.dispatched_qty or 0)
        if is_returns:
                if idx in packed_indices:
                        row.returned_qty = required_qty
                else:
                        row.returned_qty = 0
                row.used_qty = float(row.dispatched_qty or 0) - float(row.returned_qty or 0) - float(row.lost_damaged_qty or 0)
        else:
                if idx in packed_indices:
                        row.custom_scanned_qty = required_qty
                        row.custom_remaining_qty = 0
                        row.custom_packing_status = 'Complete'
                else:
                        row.custom_scanned_qty = 0
                        row.custom_remaining_qty = required_qty
                        row.custom_packing_status = 'Pending'

case.flags.ignore_permissions = True
case.save()

frappe.response['message'] = {'ok': True, 'total': len(case.case_items), 'packed': len(packed_indices)}