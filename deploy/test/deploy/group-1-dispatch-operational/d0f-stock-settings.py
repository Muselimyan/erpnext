# ==============================================================
# D0f - why did an overdrawing Stock Entry still submit? READ ONLY.
#
# D1 removed frappe.flags.ignore_stock_validation from create_se, yet a Pack of
# 999,999 units against a bin holding 52 still posted. Removing the bypass only
# restores ERPNext's own check -- if Stock Settings permits negative stock
# globally, ERPNext has no objection to raise.
# ==============================================================
import frappe
def d0f():
    lines = []
    def emit(k, v, note=""):
        lines.append("D0F | {0:<42} | {1:<10} | {2}".format(k, str(v), note))
    ss = frappe.get_single("Stock Settings")
    for f in ["allow_negative_stock", "over_delivery_receipt_allowance", "role_allowed_to_over_deliver_receive", "stock_frozen_upto", "stock_auth_role"]:
        try:
            emit(f, ss.get(f), "")
        except Exception:
            emit(f, "(not a field)", "")
    emit("--", "--", "")
    neg = frappe.db.count("Bin", {"actual_qty": ["<", 0]})
    emit("bins currently negative (all warehouses)", neg, "")
    negmain = frappe.db.count("Bin", {"actual_qty": ["<", 0], "warehouse": "Main - Inmed"})
    emit("bins negative in Main - Inmed", negmain, "")
    print("D0F_RESULTS_START")
    for ln in lines:
        print(ln)
    print("D0F_RESULTS_END")
    frappe.db.rollback()
d0f()
