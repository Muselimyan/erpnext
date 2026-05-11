import frappe
frappe.init(site="161.97.83.156", sites_path="/home/frappe/frappe-bench/sites")
frappe.connect()

h050 = frappe.db.get_all("Warehouse", filters={"warehouse_name": ("like", "H050%")}, fields=["name","warehouse_name"])
for r in h050:
    print("H050:", repr(r.name))

children = frappe.db.get_all("Warehouse", filters={"parent_warehouse": ("like", "H050%")}, fields=["name","warehouse_name","parent_warehouse"])
for r in children:
    print("CHILD:", repr(r.name))

frappe.destroy()
