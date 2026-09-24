# ==============================================================
# D9 verification - negative stock is now refused. Run against TEST.
#
# The D1 verify recorded the overdraw as a NOTE rather than a PASS, because
# allow_negative_stock = 1 meant ERPNext had no objection to raise. With the
# setting off, the same scenario must now be REFUSED -- that flips the note into
# a real assertion and closes the loop D1 left open.
#
# Also confirms the normal path still works, because a gate that only ever says
# no is not a fix.
#
# Everything is rolled back.
# ==============================================================
import frappe
def d9_verify(INV_USER):
    results = []
    MAIN = "Main - Inmed"
    try:
        frappe.set_user("Administrator")
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        allowneg = frappe.db.get_single_value("Stock Settings", "allow_negative_stock")
        results.append(("SETTING allow_negative_stock is off", "PASS" if not allowneg else "FAIL", "value={0}".format(allowneg)))
        item = None
        onhand = 0
        for b in frappe.get_all("Bin", filters={"warehouse": MAIN, "actual_qty": [">", 5]}, fields=["item_code", "actual_qty", "valuation_rate"], order_by="actual_qty desc", limit_page_length=60):
            if not b.valuation_rate or float(b.valuation_rate) <= 0:
                continue
            if frappe.db.get_value("Item Price", {"item_code": b.item_code, "price_list": "Standard Selling", "price_list_rate": [">", 0]}, "price_list_rate"):
                item = b.item_code
                onhand = float(b.actual_qty)
                break
        rate = float(frappe.db.get_value("Item Price", {"item_code": item, "price_list": "Standard Selling", "price_list_rate": [">", 0]}, "price_list_rate"))
        wh = frappe.db.get_value("Warehouse", {"is_group": 0, "name": ["not like", "%In-Transit%"]}, "name")
        results.append(("FIXTURE item and on-hand", "PASS", "{0} has {1} in Main".format(item, onhand)))
        def run_pack(qty, label):
            c = frappe.new_doc("Dispatch Case")
            c.status = "Confirmed"
            c.customer = cust
            c.client_location_warehouse = wh
            c.return_expected = 0
            c.flags.ignore_permissions = True
            c.flags.ignore_mandatory = True
            r = c.append("case_items", {})
            r.item_code = item
            r.item_name = item
            r.dispatched_qty = qty
            r.unit_price = rate
            r.custom_scanned_qty = qty
            c.insert()
            c.flags.ignore_permissions = True
            c.submit()
            t = frappe.get_doc({"doctype": "Task", "subject": "D9 " + label, "task_kind": "Pack / prepare items", "task_access_policy": "Pack / prepare items", "customer": cust, "dispatch_case": c.name, "status": "Working", "custom_assigned_to": INV_USER, "custom_accepted_by": INV_USER})
            t.flags.ignore_permissions = True
            t.insert()
            p = frappe.get_doc({"doctype": "File", "file_name": "d9.png", "file_url": "/files/d9.png", "attached_to_doctype": "Task", "attached_to_name": t.name, "is_private": 0})
            p.name = "d9-" + frappe.generate_hash("", 8)
            p.db_insert()
            frappe.set_user(INV_USER)
            err = ""
            try:
                t.reload()
                t.status = "Completed"
                t.save()
            except Exception as e:
                err = str(e)
            frappe.set_user("Administrator")
            return frappe.db.get_value("Dispatch Case", c.name, "dispatch_stock_entry"), err
        # ORDER MATTERS. The normal case runs FIRST.
        #
        # Run the other way round, the refused overdraw still writes its ledger
        # rows inside the open transaction before validation throws, leaving the
        # bin deeply negative -- so the subsequent normal pack fails too, and the
        # test reports a product defect that is purely its own doing. That is
        # what the first version of this file did.
        # ---- 1. a normal quantity still works ----
        se_ok, err_ok = run_pack(2, "normal")
        if se_ok:
            sles = frappe.get_all("Stock Ledger Entry", filters={"voucher_no": se_ok, "is_cancelled": 0}, fields=["actual_qty", "valuation_rate"], limit_page_length=0)
            inn = [s for s in sles if float(s.actual_qty) > 0]
            v = float(inn[0].valuation_rate) if inn else 0
            results.append(("NORMAL pack still succeeds", "PASS", "{0}, {1} SLE, in-rate {2}".format(se_ok, len(sles), v)))
            results.append(("NORMAL pack still carries valuation", "PASS" if v > 0 else "FAIL", "rate {0}".format(v)))
        else:
            results.append(("NORMAL pack still succeeds", "FAIL", err_ok[:104] or "no stock entry"))
        # ---- 2. the overdraw D1 could only NOTE must now be refused ----
        se_big, err_big = run_pack(999999, "overdraw")
        if se_big:
            n = frappe.db.count("Stock Ledger Entry", {"voucher_no": se_big, "is_cancelled": 0})
            results.append(("OVERDRAW is refused", "FAIL", "SE {0} created with {1} SLE".format(se_big, n)))
        else:
            results.append(("OVERDRAW is refused", "PASS", (err_big or "no stock entry created")[:100]))
    except Exception as e:
        results.append(("RUN", "FAIL", str(e)[:170]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("D9VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("D9VERIFY | {0:<38} | {1:<4} | {2}".format(name, verdict, detail))
    print("D9VERIFY_RESULTS_END")
d9_verify("e2e.inventory@test.erpnext.am")
