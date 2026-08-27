# Name: doc15_norm_reorder_daily_notifications
# Type: Scheduler Event
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

from frappe.utils import nowdate

recipients = []
for role in ["Ops - Purchasing", "Ops - Directors"]:
    for user in frappe.get_all("Has Role", filters={"role": role, "parenttype": "User"}, pluck="parent"):
        if frappe.db.get_value("User", user, "enabled") and user not in recipients:
            recipients.append(user)

if recipients:
    below_reorder = frappe.db.sql("""
        select distinct b.item_code
        from `tabBin` b
        join `tabItem` i on i.name = b.item_code
        left join `tabItem Reorder` ir on ir.parent = i.name and ir.warehouse = b.warehouse
        where i.disabled = 0
          and coalesce(ir.warehouse_reorder_level, 0) > 0
          and b.actual_qty <= ir.warehouse_reorder_level
        limit 100
    """, as_dict=True)

    if below_reorder:
        subject = "Daily norm/reorder alert: {0} item(s) need review".format(len(below_reorder))
        item_lines = "\n".join(["- " + row.item_code for row in below_reorder[:50]])
        description = subject + "\n\n" + item_lines + "\n\nOpen report: RPT â€” Purchasing â€” Norm and Reorder"
        for user in recipients:
            existing = frappe.get_all(
                "ToDo",
                filters={"allocated_to": user, "description": ["like", "Daily norm/reorder alert%"], "status": "Open", "date": nowdate()},
                limit=1
            )
            if not existing:
                frappe.get_doc({
                    "doctype": "ToDo",
                    "allocated_to": user,
                    "description": description,
                    "priority": "Medium",
                    "status": "Open",
                    "date": nowdate()
                }).insert(ignore_permissions=True)
        frappe.db.commit()