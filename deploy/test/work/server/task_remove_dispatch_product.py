# Name: task_remove_dispatch_product
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

def run_script():
    case_name = frappe.form_dict.get("case_name")
    row_name = frappe.form_dict.get("row_name")
    if not case_name or not row_name:
        frappe.throw("case_name and row_name are required.")
    tfe_tasks = frappe.get_all("Task", filters={"dispatch_case": case_name, "status": ["not in", ["Completed", "Cancelled"]]}, fields=["custom_accepted_by"], limit_page_length=1)
    if not tfe_tasks or (tfe_tasks[0].custom_accepted_by or "") != frappe.session.user:
        frappe.throw("You must accept the task before making changes.")
    case = frappe.get_doc("Dispatch Case", case_name)
    original_count = len(case.case_items)
    case.case_items = [r for r in case.case_items if r.name != row_name]
    if len(case.case_items) == original_count:
        frappe.throw("Row not found in Dispatch Case.")
    case.flags.ignore_permissions = True
    case.save()
    frappe.response["message"] = {"ok": True, "remaining": len(case.case_items)}
run_script()
