# Name: Item-before-save-reorder-change-reason
# Type: DocType Event
# DocType: Item
# Event: Before Save
# Disabled: 1
# ---

before = doc.get_doc_before_save()
if before:
    def snap(rows):
        return [(r.warehouse, r.warehouse_reorder_level or 0, r.warehouse_reorder_qty or 0) for r in (rows or [])]
    if snap(before.reorder_levels) != snap(doc.reorder_levels):
        if not (doc.reorder_change_reason or "").strip():
            frappe.throw("Doc 08: Reorder Change Reason required.")