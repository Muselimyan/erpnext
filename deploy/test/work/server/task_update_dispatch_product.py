# Name: task_update_dispatch_product
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

def run_script():
    case_name = frappe.form_dict.get("case_name")
    row_name = frappe.form_dict.get("row_name")
    dispatched_qty = frappe.form_dict.get("dispatched_qty")
    unit_price = frappe.form_dict.get("unit_price")
    discount_pct = frappe.form_dict.get("discount_pct")
    batch_no = frappe.form_dict.get("batch_no")
    if not case_name or not row_name:
        frappe.throw("case_name and row_name are required.")
    case = frappe.get_doc("Dispatch Case", case_name)
    found = False
    for row in case.case_items:
        if row.name == row_name:
            if dispatched_qty is not None:
                row.dispatched_qty = float(dispatched_qty)
                row.custom_remaining_qty = max(float(dispatched_qty) - float(row.custom_scanned_qty or 0), 0)
            if unit_price is not None:
                row.unit_price = float(unit_price)
            if discount_pct is not None:
                row.discount_pct = float(discount_pct)
            if batch_no is not None:
                row.batch_no = batch_no or None
            found = True
            break
    if not found:
        frappe.throw("Row not found in Dispatch Case.")
    case.flags.ignore_permissions = True
    case.save()
    frappe.response["message"] = {"ok": True}
run_script()
