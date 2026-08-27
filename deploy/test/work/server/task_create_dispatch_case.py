# Name: task_create_dispatch_case
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

def run_script():
    task_name = frappe.form_dict.get('task_name')
    if not task_name:
        frappe.throw('Task is required.')
    task = frappe.get_doc('Task', task_name)
    if task.get('dispatch_case'):
        frappe.response['message'] = {'ok': True, 'dispatch_case': task.dispatch_case, 'created': False}
        return
    case = frappe.new_doc('Dispatch Case')
    if task.get('customer'):
        case.customer = task.customer
    case.status = 'Draft'
    case.order_entry_task = task_name
    if task.get('description'):
        case.notes = 'Created from Task ' + task.name + '\n\n' + task.description
    else:
        case.notes = 'Created from Task ' + task.name
    case.flags.ignore_permissions = True
    case.flags.ignore_mandatory = True
    case.insert()
    frappe.db.set_value('Task', task_name, 'dispatch_case', case.name)
    frappe.response['message'] = {'ok': True, 'dispatch_case': case.name, 'created': True}
run_script()