# Name: perm_disable_batch_expiry_dbset
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

codes_text = frappe.form_dict.get("codes") or ""
codes = []
for part in codes_text.split(","):
    code = part.strip()
    if code:
        codes.append(code)

updated = []
missing = []
for code in codes:
    exists = frappe.db.exists("Item", code)
    if exists:
        frappe.db.set_value("Item", code, "has_batch_no", 0, update_modified=False)
        frappe.db.set_value("Item", code, "has_expiry_date", 0, update_modified=False)
        updated.append(code)
    else:
        missing.append(code)

frappe.response["message"] = {"updated": updated, "missing": missing, "count": len(updated)}