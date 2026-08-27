# Name: task_lookup_product_barcode
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

def run_script():
    barcode = (frappe.form_dict.get("barcode") or "").strip()
    if not barcode:
        frappe.throw("Barcode is required.")
    item_code = None
    if frappe.db.exists("Item", barcode):
        item_code = barcode
    if not item_code:
        item_code = frappe.db.get_value("Item Barcode", {"barcode": barcode}, "parent")
    frappe.response["message"] = {"ok": True, "barcode": barcode, "item_code": item_code}
run_script()