# Name: Purchase Order-before-submit-director-approval
# Type: DocType Event
# DocType: Purchase Order
# Event: Before Submit
# Disabled: 0
# ---

if doc.director_approval_status != "Approved":
    frappe.throw(
        "Director approval is required before submitting the Purchase Order. "
        "Create a Purchase Approval task, get it completed as Approved, then submit."
    )