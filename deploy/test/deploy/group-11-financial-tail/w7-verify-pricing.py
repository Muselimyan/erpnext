# ==============================================================
# W7 verification - run against TEST via bench console.
#
# Proves the selling price is resolved on the server in the right precedence,
# that a client-supplied price is ignored, that an unpriced item is refused,
# and that the tender remaining-quantity check fires at ORDER ENTRY rather
# than at invoice submission.
#
# Everything is rolled back; no records survive the run.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-11-financial-tail\w7-verify-pricing.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body, params not globals --
# IPython treats a blank line as end-of-block when code is piped in.
# ==============================================================
import frappe
def w7_verify(ORDER_USER):
    results = []
    try:
        frappe.set_user("Administrator")
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        # An item that HAS a Standard Selling price, and one that does not.
        priced = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, ["item_code", "price_list_rate"], as_dict=True)
        listed = frappe.get_all("Item Price", filters={"price_list": "Standard Selling"}, fields=["item_code"], limit_page_length=0)
        listed_codes = {}
        for l in listed:
            listed_codes[l.item_code] = True
        unpriced_item = None
        for i in frappe.get_all("Item", filters={"disabled": 0, "is_stock_item": 1}, fields=["name"], limit_page_length=0):
            if i.name not in listed_codes:
                unpriced_item = i.name
                break
        # ---- fixture: an accepted Order entry task with a draft case -------
        oe = frappe.get_doc({"doctype": "Task", "subject": "W7VERIFY order entry", "task_kind": "Order entry", "task_access_policy": "Order entry", "customer": cust, "status": "Working", "custom_assigned_to": ORDER_USER, "custom_accepted_by": ORDER_USER})
        oe.flags.ignore_permissions = True
        oe.insert()
        case = frappe.new_doc("Dispatch Case")
        case.status = "Draft"
        case.customer = cust
        case.order_entry_task = oe.name
        case.flags.ignore_permissions = True
        case.flags.ignore_mandatory = True
        case.insert()
        frappe.db.set_value("Task", oe.name, "dispatch_case", case.name)
        addscript = frappe.get_doc("Server Script", "task_add_dispatch_product")
        # ---- 1. price comes from the list, and a client price is ignored ---
        frappe.set_user(ORDER_USER)
        frappe.form_dict.clear()
        frappe.form_dict["task_name"] = oe.name
        frappe.form_dict["item_code"] = priced.item_code
        frappe.form_dict["qty"] = 1
        frappe.form_dict["unit_price"] = 999999
        try:
            frappe.response.pop("message", None)
            addscript.execute_method()
            frappe.set_user("Administrator")
            c = frappe.get_doc("Dispatch Case", case.name)
            got = 0
            for r in c.case_items:
                if r.item_code == priced.item_code:
                    got = float(r.unit_price or 0)
            if abs(got - float(priced.price_list_rate)) < 0.01:
                results.append(("PRICE resolved from Standard Selling", "PASS", str(got)))
                results.append(("PRICE client-supplied value ignored", "PASS", "sent 999999, stored " + str(got)))
            else:
                results.append(("PRICE resolved from Standard Selling", "FAIL", "expected " + str(priced.price_list_rate) + " got " + str(got)))
                results.append(("PRICE client-supplied value ignored", "FAIL", "stored " + str(got)))
        except Exception as e:
            results.append(("PRICE resolved from Standard Selling", "FAIL", str(e)[:130]))
            results.append(("PRICE client-supplied value ignored", "FAIL", "not reached"))
        # ---- 2. an item with no price is refused --------------------------
        if unpriced_item:
            frappe.set_user(ORDER_USER)
            frappe.form_dict.clear()
            frappe.form_dict["task_name"] = oe.name
            frappe.form_dict["item_code"] = unpriced_item
            frappe.form_dict["qty"] = 1
            try:
                frappe.response.pop("message", None)
                addscript.execute_method()
                results.append(("PRICE unpriced item refused", "FAIL", "was allowed for " + unpriced_item))
            except Exception as e:
                results.append(("PRICE unpriced item refused", "PASS", "blocked: " + str(e)[:90]))
        else:
            results.append(("PRICE unpriced item refused", "SKIP", "every item has a price"))
        # ---- 3. tender price wins, and refuses a discount -----------------
        frappe.set_user("Administrator")
        # Pick an item from an ACTIVE tender. Selecting an arbitrary
        # Tender Agreement Item picks up rows from Closed/Expired tenders, which
        # the resolver correctly ignores, making the test skip itself.
        tender_item = None
        hosp = None
        tstatus = None
        for at in (frappe.get_all("Tender Agreement", filters={"status": "Active"}, fields=["name", "hospital"], limit_page_length=0) or []):
            for ti in frappe.get_doc("Tender Agreement", at.name).items or []:
                if (ti.tender_price or 0) > 0 and tender_item is None:
                    tender_item = frappe._dict({"parent": at.name, "item_code": ti.item_code, "tender_price": ti.tender_price})
                    hosp = at.hospital
                    tstatus = "Active"
        if tender_item:
            if hosp and tstatus == "Active":
                oe2 = frappe.get_doc({"doctype": "Task", "subject": "W7VERIFY tender order", "task_kind": "Order entry", "task_access_policy": "Order entry", "customer": hosp, "status": "Working", "custom_assigned_to": ORDER_USER, "custom_accepted_by": ORDER_USER})
                oe2.flags.ignore_permissions = True
                oe2.insert()
                case2 = frappe.new_doc("Dispatch Case")
                case2.status = "Draft"
                case2.customer = hosp
                case2.order_entry_task = oe2.name
                case2.flags.ignore_permissions = True
                case2.flags.ignore_mandatory = True
                case2.insert()
                frappe.db.set_value("Task", oe2.name, "dispatch_case", case2.name)
                frappe.set_user(ORDER_USER)
                frappe.form_dict.clear()
                frappe.form_dict["task_name"] = oe2.name
                frappe.form_dict["item_code"] = tender_item.item_code
                frappe.form_dict["qty"] = 1
                try:
                    frappe.response.pop("message", None)
                    addscript.execute_method()
                    frappe.set_user("Administrator")
                    c2 = frappe.get_doc("Dispatch Case", case2.name)
                    got2 = 0
                    for r in c2.case_items:
                        if r.item_code == tender_item.item_code:
                            got2 = float(r.unit_price or 0)
                    if abs(got2 - float(tender_item.tender_price)) < 0.01:
                        results.append(("PRICE tender price wins", "PASS", str(got2) + " from " + tender_item.parent))
                    else:
                        results.append(("PRICE tender price wins", "FAIL", "expected " + str(tender_item.tender_price) + " got " + str(got2)))
                except Exception as e:
                    results.append(("PRICE tender price wins", "FAIL", str(e)[:130]))
                # discount on a tender item must be refused
                frappe.set_user(ORDER_USER)
                frappe.form_dict.clear()
                frappe.form_dict["task_name"] = oe2.name
                frappe.form_dict["item_code"] = tender_item.item_code
                frappe.form_dict["qty"] = 1
                frappe.form_dict["discount_pct"] = 10
                try:
                    frappe.response.pop("message", None)
                    addscript.execute_method()
                    results.append(("PRICE tender discount refused", "FAIL", "was allowed"))
                except Exception as e:
                    results.append(("PRICE tender discount refused", "PASS", "blocked: " + str(e)[:90]))
                # ---- 4. tender over-quantity blocked at ORDER ENTRY -------
                frappe.set_user("Administrator")
                for r in frappe.get_doc("Dispatch Case", case2.name).case_items:
                    frappe.db.set_value("Dispatch Case Item", r.name, "dispatched_qty", 100000)
                frappe.set_user(ORDER_USER)
                try:
                    t2 = frappe.get_doc("Task", oe2.name)
                    t2.status = "Completed"
                    t2.flags.ignore_permissions = True
                    t2.save()
                    results.append(("TENDER over-qty blocked at order entry", "FAIL", "order completed"))
                except Exception as e:
                    results.append(("TENDER over-qty blocked at order entry", "PASS", "blocked: " + str(e)[:90]))
            else:
                results.append(("PRICE tender price wins", "SKIP", "no active tender"))
        else:
            results.append(("PRICE tender price wins", "SKIP", "no tender items"))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("W7VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("W7VERIFY | {0:<38} | {1:<4} | {2}".format(name, verdict, detail))
    print("W7VERIFY_RESULTS_END")
w7_verify("e2e.order.creating@test.erpnext.am")
