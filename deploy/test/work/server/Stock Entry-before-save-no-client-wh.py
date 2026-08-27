# Name: Stock Entry-before-save-no-client-wh
# Type: DocType Event
# DocType: Stock Entry
# Event: Before Save
# Disabled: 1
# ---

CLIENTS_ROOT = "Clients - Inmed"

if doc.get("sales_order"):
    root = frappe.get_doc("Warehouse", CLIENTS_ROOT)
    root_lft = int(root.lft)
    root_rgt = int(root.rgt)

    for row in (doc.items or []):
        wh = row.t_warehouse or doc.get("to_warehouse")
        if wh:
            is_client_wh = frappe.db.exists(
                "Warehouse",
                {"name": wh, "lft": [">=", root_lft], "rgt": ["<=", root_rgt]},
            )

            if is_client_wh:
                frappe.throw("Standard sales must not move stock into client location warehouses (Clients - Inmed).")