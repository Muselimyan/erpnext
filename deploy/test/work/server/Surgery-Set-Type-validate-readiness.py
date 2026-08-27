# Name: Surgery-Set-Type-validate-readiness
# Type: DocType Event
# DocType: Collection Set
# Event: Before Save
# Disabled: 0
# ---

MAIN_WH = "Main - Inmed"

missing_lines = []
critical_lines = []

for row in (doc.items or []):
    item_code = row.item
    required_qty = float(row.default_qty or 0)
    if item_code and required_qty > 0:
        bin_row = frappe.db.get_value(
            "Bin",
            {"item_code": item_code, "warehouse": MAIN_WH},
            ["projected_qty"],
            as_dict=True,
        )

        projected = float((bin_row or {}).get("projected_qty") or 0)
        shortage = required_qty - projected

        if shortage > 0:
            line = (
                str(item_code) + ": need " + str(required_qty)
                + ", projected " + str(projected)
                + ", short " + str(shortage)
            )
            missing_lines.append(line)
            if int(row.is_critical or 0) == 1:
                critical_lines.append(line)

if critical_lines:
    doc.readiness_status = "Critical Short"
    doc.readiness_note = "Critical shortages:\n" + "\n".join(critical_lines)
    frappe.msgprint(doc.readiness_note, title="Collection Set readiness warning")
elif missing_lines:
    doc.readiness_status = "Short"
    doc.readiness_note = "Shortages:\n" + "\n".join(missing_lines)
    frappe.msgprint(doc.readiness_note, title="Collection Set readiness warning")
else:
    doc.readiness_status = "Ready"
    doc.readiness_note = ""