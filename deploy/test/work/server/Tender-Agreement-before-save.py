# Name: Tender-Agreement-before-save
# Type: DocType Event
# DocType: Tender Agreement
# Event: Before Save
# Disabled: 0
# ---

for row in doc.items:
    row.remaining_quantity = (row.won_quantity or 0) - (row.supplied_quantity or 0)
from frappe.utils import nowdate, getdate
today = getdate(nowdate())
valid_from = getdate(doc.valid_from) if doc.valid_from else None
valid_to = getdate(doc.valid_to) if doc.valid_to else None
if doc.status == "Draft":
    pass
elif valid_from and valid_to:
    if today < valid_from:
        doc.status = "Draft"
    elif today >= valid_from and today <= valid_to:
        doc.status = "Active"
    elif today > valid_to:
        doc.status = "Expired"