# Name: Purchase Invoice-before-submit-no-update-stock
# Type: DocType Event
# DocType: Purchase Invoice
# Event: Before Submit
# Disabled: 0
# ---

if doc.get("update_stock"):
    frappe.throw("Do not use Purchase Invoice to update stock. Use Purchase Receipt for receiving (Doc 07 policy).")