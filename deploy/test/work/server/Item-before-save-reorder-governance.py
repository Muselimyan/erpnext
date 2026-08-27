# Name: Item-before-save-reorder-governance
# Type: DocType Event
# DocType: Item
# Event: Before Save
# Disabled: 0
# ---

before = doc.get_doc_before_save()

if not before:
    pass
else:
    # Standard ERPNext fieldname for Item Reorder child table.
    # If your instance uses a different name, change this value.
    REORDER_FIELDNAME = "reorder_levels"

    def normalize(rows):
        out = []
        for r in (rows or []):
            out.append({
                "warehouse": r.warehouse,
                "reorder_level": float(getattr(r, "warehouse_reorder_level", 0) or 0),
                "reorder_qty": float(getattr(r, "warehouse_reorder_qty", 0) or 0),
            })
        return out

    before_rows = normalize(before.get(REORDER_FIELDNAME) or [])
    after_rows  = normalize(doc.get(REORDER_FIELDNAME) or [])

    if before_rows != after_rows:
        if not (doc.reorder_change_reason or "").strip():
            frappe.throw(
                "Reorder Change Reason is required when changing reorder thresholds "
                "(Doc 08 governance rule)."
            )