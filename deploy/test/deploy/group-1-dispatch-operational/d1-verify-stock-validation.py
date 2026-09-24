# ==============================================================
# D1 verification - Stock Entry validation restored. Run against TEST.
#
# The assertion that matters is PRESERVATION, not "non-zero". A wrong-but-
# positive valuation would pass a non-zero check, and the defect being fixed is
# precisely that transfers arrived valued at zero because ignore_validate
# skipped set_basic_rate.
#
# Run as e2e.inventory and e2e.order.creating, NEVER as Administrator --
# privileged users are exempt from the access-control gates.
#
# Everything is rolled back; no records survive the run.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-1-dispatch-operational\d1-verify-stock-validation.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body, users passed as parameters.
# IPython treats a blank line as end-of-block when code is piped in.
# ==============================================================
import frappe
def d1_verify(INV_USER, ORDER_USER, RETURNS_USER):
    results = []
    MAIN = "Main - Inmed"
    TRANSIT = "Delivery In-Transit - Inmed"
    RETURNS = "Returns - Inmed"
    try:
        frappe.set_user("Administrator")
        company = frappe.db.get_single_value("Global Defaults", "default_company") or "InMED"
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        # Pick an item that is healthy in Main: positive stock, real valuation,
        # and a selling price (order entry now refuses unpriced items).
        item = None
        rate = 0
        vrate = 0
        for b in frappe.get_all("Bin", filters={"warehouse": MAIN, "actual_qty": [">", 5]}, fields=["item_code", "actual_qty", "valuation_rate"], order_by="actual_qty desc", limit_page_length=60):
            if not b.valuation_rate or float(b.valuation_rate) <= 0:
                continue
            p = frappe.db.get_value("Item Price", {"item_code": b.item_code, "price_list": "Standard Selling", "price_list_rate": [">", 0]}, "price_list_rate")
            if p:
                item = b.item_code
                rate = float(p)
                vrate = float(b.valuation_rate)
                break
        if not item:
            results.append(("FIXTURE healthy priced item in Main", "FAIL", "none found - cannot verify"))
            raise Exception("no usable item")
        uom = frappe.db.get_value("Item", item, "stock_uom") or "Nos"
        wh = frappe.db.get_value("Warehouse", {"name": ["not in", [MAIN, TRANSIT, RETURNS, "Lost & Damaged - Inmed"]], "is_group": 0, "company": company}, "name")
        results.append(("FIXTURE item / valuation / client wh", "PASS", "{0} @ {1} -> {2}".format(item, vrate, wh)))
        # ---- 1. code shape: the bypasses are gone from the deployed script ----
        body = frappe.db.get_value("Server Script", "Task-after-save-dispatch-flow", "script") or ""
        codeonly = "\n".join([ln.split("#")[0] for ln in body.split("\n")])
        leftover = [f for f in ["ignore_validate", "ignore_stock_validation", "allow_zero_valuation_rate"] if f in codeonly]
        results.append(("DEPLOYED create_se has no bypasses", "PASS" if not leftover else "FAIL", ", ".join(leftover) or "none"))
        gbody = frappe.db.get_value("Server Script", "Task-before-save-dispatch-gates", "script") or ""
        uncond = "if not doc.order_client_location_warehouse:" in gbody
        results.append(("DEPLOYED warehouse gate unconditional", "PASS" if uncond else "FAIL", "found" if uncond else "still gated on return_expected"))
        # ---- 2. Order Entry refuses a blank client warehouse (no-return path) ----
        c2 = frappe.new_doc("Dispatch Case")
        c2.status = "Draft"
        c2.customer = cust
        c2.return_expected = 0
        c2.flags.ignore_permissions = True
        c2.flags.ignore_mandatory = True
        r2 = c2.append("case_items", {})
        r2.item_code = item
        r2.item_name = item
        r2.dispatched_qty = 1
        r2.unit_price = rate
        c2.insert()
        oe = frappe.get_doc({"doctype": "Task", "subject": "D1VERIFY order entry", "task_kind": "Order entry", "task_access_policy": "Order entry", "customer": cust, "dispatch_case": c2.name, "status": "Working", "custom_assigned_to": ORDER_USER, "custom_accepted_by": ORDER_USER, "order_return_expected": 0, "order_client_location_warehouse": ""})
        oe.flags.ignore_permissions = True
        oe.insert()
        frappe.set_user(ORDER_USER)
        try:
            oe.reload()
            oe.status = "Completed"
            oe.save()
            results.append(("GATE blank client warehouse refused (no-return)", "FAIL", "completion was allowed"))
        except Exception as e:
            msg = str(e)
            ok = "Client Location Warehouse is required" in msg
            results.append(("GATE blank client warehouse refused (no-return)", "PASS" if ok else "FAIL", msg[:110]))
        frappe.set_user("Administrator")
        # ---- 3. Pack completion: transfer preserves valuation ----
        case = frappe.new_doc("Dispatch Case")
        case.status = "Confirmed"
        case.customer = cust
        case.client_location_warehouse = wh
        case.return_expected = 0
        case.flags.ignore_permissions = True
        case.flags.ignore_mandatory = True
        rr = case.append("case_items", {})
        rr.item_code = item
        rr.item_name = item
        rr.dispatched_qty = 2
        rr.unit_price = rate
        rr.custom_scanned_qty = 2
        case.insert()
        case.flags.ignore_permissions = True
        case.submit()
        pack = frappe.get_doc({"doctype": "Task", "subject": "D1VERIFY pack", "task_kind": "Pack / prepare items", "task_access_policy": "Pack / prepare items", "customer": cust, "dispatch_case": case.name, "status": "Working", "custom_assigned_to": INV_USER, "custom_accepted_by": INV_USER})
        pack.flags.ignore_permissions = True
        pack.insert()
        # db_insert() writes the row and skips the File controller entirely.
        # insert() makes the controller stat the file on disk, and these File
        # records point at paths that no longer exist on this instance. The gate
        # reads file_url out of the database and never opens the file, so a raw
        # row is a faithful fixture. Rolled back with everything else.
        photo = frappe.get_doc({"doctype": "File", "file_name": "d1verify.png", "file_url": "/files/d1verify.png", "attached_to_doctype": "Task", "attached_to_name": pack.name, "is_private": 0})
        photo.name = "d1v-" + frappe.generate_hash("", 8)
        photo.db_insert()
        main_before = float(frappe.db.get_value("Bin", {"item_code": item, "warehouse": MAIN}, "valuation_rate") or 0)
        frappe.set_user(INV_USER)
        pack_err = ""
        try:
            pack.reload()
            pack.status = "Completed"
            pack.save()
        except Exception as e:
            pack_err = str(e)[:150]
        frappe.set_user("Administrator")
        se_name = frappe.db.get_value("Dispatch Case", case.name, "dispatch_stock_entry")
        if not se_name:
            results.append(("PACK created a Stock Entry", "FAIL", pack_err or "no dispatch_stock_entry set"))
        else:
            results.append(("PACK created a Stock Entry", "PASS", se_name))
            sles = frappe.get_all("Stock Ledger Entry", filters={"voucher_no": se_name, "is_cancelled": 0}, fields=["warehouse", "actual_qty", "valuation_rate", "stock_value_difference"], limit_page_length=0)
            results.append(("PACK entry produced ledger entries", "PASS" if sles else "FAIL", "{0} SLE".format(len(sles))))
            out = [s for s in sles if float(s.actual_qty) < 0]
            inn = [s for s in sles if float(s.actual_qty) > 0]
            if out and inn:
                ov = float(out[0].valuation_rate or 0)
                iv = float(inn[0].valuation_rate or 0)
                # THE core assertion: the transfer must carry value across, not
                # arrive at zero. ignore_validate used to skip set_basic_rate.
                same = abs(ov - iv) < 0.01
                results.append(("PACK valuation PRESERVED across transfer", "PASS" if same else "FAIL", "out {0} -> in {1}".format(ov, iv)))
                results.append(("PACK incoming value is not zero", "PASS" if iv > 0 else "FAIL", "in rate {0}".format(iv)))
            else:
                results.append(("PACK valuation PRESERVED across transfer", "FAIL", "expected one in and one out SLE, got {0}".format(len(sles))))
        # ---- 4. insufficient stock is refused, not silently posted ----
        big = frappe.new_doc("Dispatch Case")
        big.status = "Confirmed"
        big.customer = cust
        big.client_location_warehouse = wh
        big.return_expected = 0
        big.flags.ignore_permissions = True
        big.flags.ignore_mandatory = True
        rb = big.append("case_items", {})
        rb.item_code = item
        rb.item_name = item
        rb.dispatched_qty = 999999
        rb.unit_price = rate
        rb.custom_scanned_qty = 999999
        big.insert()
        big.flags.ignore_permissions = True
        big.submit()
        bpack = frappe.get_doc({"doctype": "Task", "subject": "D1VERIFY overdraw", "task_kind": "Pack / prepare items", "task_access_policy": "Pack / prepare items", "customer": cust, "dispatch_case": big.name, "status": "Working", "custom_assigned_to": INV_USER, "custom_accepted_by": INV_USER})
        bpack.flags.ignore_permissions = True
        bpack.insert()
        bphoto = frappe.get_doc({"doctype": "File", "file_name": "d1verify2.png", "file_url": "/files/d1verify2.png", "attached_to_doctype": "Task", "attached_to_name": bpack.name, "is_private": 0})
        bphoto.name = "d1v-" + frappe.generate_hash("", 8)
        bphoto.db_insert()
        frappe.set_user(INV_USER)
        refused = False
        errtext = ""
        try:
            bpack.reload()
            bpack.status = "Completed"
            bpack.save()
        except Exception as e:
            refused = True
            errtext = str(e)[:110]
        frappe.set_user("Administrator")
        bse = frappe.db.get_value("Dispatch Case", big.name, "dispatch_stock_entry")
        # Removing ignore_stock_validation restores ERPNext's own check -- it
        # does not overrule Stock Settings. With allow_negative_stock = 1,
        # ERPNext has no objection to raise, so an overdraw still posts. That is
        # a separate global lever with a far wider blast radius than D1, and
        # turning it off would immediately fail on the 13 bins already negative.
        # Reported, not asserted, so D1 is not blamed for a setting it does not
        # control.
        allowneg = frappe.db.get_single_value("Stock Settings", "allow_negative_stock")
        if refused and not bse:
            results.append(("STOCK overdraw refused", "PASS", errtext))
        elif allowneg:
            results.append(("STOCK overdraw (allow_negative_stock=1)", "NOTE", "posted as expected for this setting - see D1 known limit"))
        elif bse:
            bsles = frappe.get_all("Stock Ledger Entry", filters={"voucher_no": bse, "is_cancelled": 0}, limit_page_length=0)
            results.append(("STOCK overdraw refused", "FAIL", "SE {0} created with {1} SLE".format(bse, len(bsles))))
        else:
            results.append(("STOCK overdraw refused", "PASS", "no stock entry created"))
        # ---- 5. restock does not drag Main's moving average down ----
        seed = frappe.get_doc({"doctype": "Stock Entry", "stock_entry_type": "Material Receipt", "purpose": "Material Receipt", "company": company, "items": [{"item_code": item, "qty": 4, "transfer_qty": 4, "uom": uom, "stock_uom": uom, "conversion_factor": 1, "t_warehouse": RETURNS, "basic_rate": main_before, "cost_center": "Main - Inmed", "expense_account": "Stock Adjustment - Inmed"}]})
        seed.flags.ignore_permissions = True
        seed.insert()
        seed.submit()
        rate_before_restock = float(frappe.db.get_value("Bin", {"item_code": item, "warehouse": MAIN}, "valuation_rate") or 0)
        rcase = frappe.new_doc("Dispatch Case")
        rcase.status = "Confirmed"
        rcase.customer = cust
        rcase.client_location_warehouse = wh
        rcase.return_expected = 1
        rcase.flags.ignore_permissions = True
        rcase.flags.ignore_mandatory = True
        r5 = rcase.append("case_items", {})
        r5.item_code = item
        r5.item_name = item
        r5.dispatched_qty = 4
        r5.returned_qty = 4
        r5.unit_price = rate
        rcase.insert()
        rcase.flags.ignore_permissions = True
        rcase.submit()
        frappe.db.set_value("Dispatch Case", rcase.name, "status", "Invoice Pending")
        # Returns restocking is gated to Ops - Returns, so it must be driven by
        # the returns user. Using the inventory user here failed the task-kind
        # role check -- correct behaviour, wrong fixture.
        rt = frappe.get_doc({"doctype": "Task", "subject": "D1VERIFY restock", "task_kind": "Returns restocking", "task_access_policy": "Returns restocking", "customer": cust, "dispatch_case": rcase.name, "status": "Working", "custom_assigned_to": RETURNS_USER, "custom_accepted_by": RETURNS_USER})
        rt.flags.ignore_permissions = True
        rt.insert()
        # Returns restocking requires a photo before it can be completed (added
        # by Group 1 D6, after this harness was written -- so this step failed
        # on the D6 gate, not on anything D1 tests). Same db_insert() trick as
        # the photos above: it skips the File controller, which would otherwise
        # stat a file that does not exist on disk.
        rphoto = frappe.get_doc({"doctype": "File", "file_name": "d1restock.png", "file_url": "/files/d1restock.png", "attached_to_doctype": "Task", "attached_to_name": rt.name, "is_private": 0})
        rphoto.name = "d1v-" + frappe.generate_hash("", 8)
        rphoto.db_insert()
        frappe.set_user(RETURNS_USER)
        rerr = ""
        try:
            rt.reload()
            rt.status = "Completed"
            rt.save()
        except Exception as e:
            rerr = str(e)[:140]
        frappe.set_user("Administrator")
        rse = frappe.db.get_value("Dispatch Case", rcase.name, "restock_stock_entry")
        rate_after_restock = float(frappe.db.get_value("Bin", {"item_code": item, "warehouse": MAIN}, "valuation_rate") or 0)
        if not rse:
            results.append(("RESTOCK created a Stock Entry", "FAIL", rerr or "no restock_stock_entry"))
        else:
            results.append(("RESTOCK created a Stock Entry", "PASS", rse))
            moved = abs(rate_after_restock - rate_before_restock)
            # THE acceptance test. Zero-valued restock used to pull the moving
            # average down on every returns cycle, compounding indefinitely.
            results.append(("RESTOCK leaves Main valuation unchanged", "PASS" if moved < 0.01 else "FAIL", "{0} -> {1}".format(rate_before_restock, rate_after_restock)))
        # ---- 6. no silent no-ops among anything this run created ----
        made = frappe.get_all("Stock Entry", filters={"docstatus": 1, "creation": [">", frappe.utils.add_to_date(None, minutes=-10)]}, fields=["name"], limit_page_length=0)
        empties = []
        for s in made:
            n = frappe.db.count("Stock Ledger Entry", {"voucher_no": s.name, "is_cancelled": 0})
            if n == 0:
                empties.append(s.name)
        results.append(("NO silent no-op Stock Entries this run", "PASS" if not empties else "FAIL", ", ".join(empties[:5]) or "all posted"))
    except Exception as e:
        results.append(("RUN", "FAIL", str(e)[:170]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("D1VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("D1VERIFY | {0:<46} | {1:<4} | {2}".format(name, verdict, detail))
    print("D1VERIFY_RESULTS_END")
d1_verify("e2e.inventory@test.erpnext.am", "e2e.order.creating@test.erpnext.am", "e2e.returns@test.erpnext.am")
