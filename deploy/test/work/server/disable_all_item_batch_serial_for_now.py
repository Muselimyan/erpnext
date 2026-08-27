# Name: disable_all_item_batch_serial_for_now
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

items = frappe.get_all("Item", fields=["name", "has_batch_no", "has_serial_no", "has_expiry_date"], limit_page_length=0)
changed = 0
for item in items:
    updates = {}
    if item.get("has_batch_no"):
        updates["has_batch_no"] = 0
    if item.get("has_serial_no"):
        updates["has_serial_no"] = 0
    if item.get("has_expiry_date"):
        updates["has_expiry_date"] = 0
    if updates:
        for fieldname, value in updates.items():
            frappe.db.set_value("Item", item.name, fieldname, value, update_modified=False)
        changed += 1
frappe.db.commit()
frappe.response["message"] = {"ok": True, "checked": len(items), "changed": changed}