import frappe
frappe.init(site="161.97.83.156", sites_path="/home/frappe/frappe-bench/sites")
frappe.connect()

h050 = frappe.db.get_value("Warehouse", {"warehouse_name": ("like", "H050%")}, "warehouse_name")
print("Current H050 warehouse_name:", repr(h050))
print()
if h050:
    after_em = h050.split("\u2014", 1)[-1].strip()
    print("Short name chars:")
    for ch in after_em:
        print(f"  {ch!r}  U+{ord(ch):04X}")

frappe.destroy()
