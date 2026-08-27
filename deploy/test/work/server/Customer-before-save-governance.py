# Name: Customer-before-save-governance
# Type: DocType Event
# DocType: 
# Event: Before Save
# Disabled: 0
# ---

before = doc.get_doc_before_save()

user_roles = set(frappe.get_roles(frappe.session.user))
is_privileged = (
    "Ops - Accounting" in user_roles or
    "Ops - Directors" in user_roles or
    "System Manager" in user_roles
)

if before and before.client_code != doc.client_code and not is_privileged:
    frappe.throw("Only Accounting/Directors can change Client Code")

if before and before.is_provisional and not doc.is_provisional and not is_privileged:
    frappe.throw("Only Accounting/Directors can mark a client as non-provisional")