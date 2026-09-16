# ==============================================================
# W6 verification - run against TEST via bench console.
#
# Proves the invoice is built, valued and submitted in one action with VAT,
# payment terms and clinical metadata; that it is idempotent; that a case with
# nothing to bill can be closed instead of leaving an unfinishable task; and
# that the completion gate survives Cancel + Amend.
#
# Everything is rolled back; no records survive the run.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-11-financial-tail\w6-verify-invoice-commit.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body, params not globals --
# IPython treats a blank line as end-of-block when code is piped in.
# ==============================================================
import frappe
def w6_verify(ACCOUNTING_USER, ORDER_USER):
    results = []
    try:
        frappe.set_user("Administrator")
        # Prefer a customer that actually has clinical metadata, so the
        # hospital / doctor_name check validates rather than warning.
        cust = frappe.db.get_value("Customer", {"disabled": 0, "doctor_name": ["!=", ""]}, "name")
        if not cust:
            cust = frappe.db.get_value("Customer", {"disabled": 0, "client_kind": "Hospital"}, "name")
        if not cust:
            cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        priced = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, ["item_code", "price_list_rate"], as_dict=True)
        # ---- fixture: a case with a used quantity, ready to invoice --------
        case = frappe.new_doc("Dispatch Case")
        case.status = "Invoice Pending"
        case.customer = cust
        case.flags.ignore_permissions = True
        case.flags.ignore_mandatory = True
        row = case.append("case_items", {})
        row.item_code = priced.item_code
        row.item_name = priced.item_code
        row.dispatched_qty = 2
        row.used_qty = 2
        row.unit_price = priced.price_list_rate
        case.insert()
        inv_task = frappe.get_doc({"doctype": "Task", "subject": "W6VERIFY invoice prep", "task_kind": "Invoice preparation / create invoice", "task_access_policy": "Invoice preparation / create invoice", "customer": cust, "dispatch_case": case.name, "status": "Working", "custom_assigned_to": ACCOUNTING_USER, "custom_accepted_by": ACCOUNTING_USER})
        inv_task.flags.ignore_permissions = True
        inv_task.insert()
        commit = frappe.get_doc("Server Script", "task_commit_invoice")
        # ---- 1. commit creates a SUBMITTED invoice with VAT and terms ------
        frappe.set_user(ACCOUNTING_USER)
        frappe.form_dict.clear()
        frappe.form_dict["task_name"] = inv_task.name
        invname = None
        try:
            frappe.response.pop("message", None)
            commit.execute_method()
            msg = frappe.response.get("message") or {}
            invname = msg.get("sales_invoice")
            frappe.set_user("Administrator")
            si = frappe.get_doc("Sales Invoice", invname)
            expected_net = float(priced.price_list_rate) * 2
            if si.docstatus == 1:
                results.append(("INV created and submitted", "PASS", invname + " docstatus=1"))
            else:
                results.append(("INV created and submitted", "FAIL", "docstatus=" + str(si.docstatus)))
            if abs(float(si.net_total or 0) - expected_net) < 0.01:
                results.append(("INV net total correct", "PASS", str(si.net_total)))
            else:
                results.append(("INV net total correct", "FAIL", "expected " + str(expected_net) + " got " + str(si.net_total)))
            if float(si.total_taxes_and_charges or 0) > 0:
                results.append(("INV VAT applied", "PASS", str(si.total_taxes_and_charges) + " (" + str(si.taxes_and_charges) + ")"))
            else:
                results.append(("INV VAT applied", "FAIL", "tax=0 template=" + str(si.taxes_and_charges)))
            if si.due_date and str(si.due_date) != str(si.posting_date):
                results.append(("INV due date beyond posting date", "PASS", str(si.posting_date) + " -> " + str(si.due_date)))
            else:
                results.append(("INV due date beyond posting date", "FAIL", "due=" + str(si.due_date) + " posting=" + str(si.posting_date)))
            if si.get("dispatch_case") == case.name:
                results.append(("INV dispatch_case link set", "PASS", case.name))
            else:
                results.append(("INV dispatch_case link set", "FAIL", str(si.get("dispatch_case"))))
            if si.get("hospital") or si.get("doctor_name"):
                results.append(("INV clinical metadata set", "PASS", "hospital=" + str(si.get("hospital")) + " doctor=" + str(si.get("doctor_name"))))
            else:
                results.append(("INV clinical metadata set", "WARN", "customer has neither hospital nor doctor_name"))
        except Exception as e:
            results.append(("INV created and submitted", "FAIL", str(e)[:150]))
        # ---- 2. committing twice is refused -------------------------------
        if invname:
            frappe.set_user(ACCOUNTING_USER)
            frappe.form_dict.clear()
            frappe.form_dict["task_name"] = inv_task.name
            try:
                frappe.response.pop("message", None)
                commit.execute_method()
                results.append(("INV second commit refused", "FAIL", "created a duplicate"))
            except Exception as e:
                results.append(("INV second commit refused", "PASS", "blocked: " + str(e)[:90]))
        # ---- 3. the completion gate finds it via SI.dispatch_case ---------
        frappe.set_user(ACCOUNTING_USER)
        try:
            t = frappe.get_doc("Task", inv_task.name)
            t.status = "Completed"
            t.flags.ignore_permissions = True
            t.save()
            results.append(("GATE invoice task completes", "PASS", "allowed"))
        except Exception as e:
            results.append(("GATE invoice task completes", "FAIL", str(e)[:150]))
        # ---- 4. Cancel + Amend keeps the case findable --------------------
        if invname:
            frappe.set_user("Administrator")
            try:
                si = frappe.get_doc("Sales Invoice", invname)
                si.flags.ignore_permissions = True
                si.cancel()
                amended = frappe.copy_doc(si)
                amended.amended_from = si.name
                amended.docstatus = 0
                amended.flags.ignore_permissions = True
                amended.insert()
                amended.submit()
                found = frappe.get_all("Sales Invoice", filters={"dispatch_case": case.name, "docstatus": 1}, fields=["name"], limit_page_length=0)
                if found and found[0].name == amended.name:
                    results.append(("AMEND case still resolves to new invoice", "PASS", si.name + " -> " + amended.name))
                else:
                    results.append(("AMEND case still resolves to new invoice", "FAIL", "found " + str(found)))
            except Exception as e:
                results.append(("AMEND case still resolves to new invoice", "FAIL", str(e)[:150]))
        # ---- 5. nothing-to-invoice closes the case ------------------------
        frappe.set_user("Administrator")
        case2 = frappe.new_doc("Dispatch Case")
        case2.status = "Invoice Pending"
        case2.customer = cust
        case2.flags.ignore_permissions = True
        case2.flags.ignore_mandatory = True
        r2 = case2.append("case_items", {})
        r2.item_code = priced.item_code
        r2.item_name = priced.item_code
        r2.dispatched_qty = 2
        r2.returned_qty = 2
        r2.used_qty = 0
        r2.unit_price = priced.price_list_rate
        case2.insert()
        t2 = frappe.get_doc({"doctype": "Task", "subject": "W6VERIFY nothing to invoice", "task_kind": "Invoice preparation / create invoice", "task_access_policy": "Invoice preparation / create invoice", "customer": cust, "dispatch_case": case2.name, "status": "Working", "custom_assigned_to": ACCOUNTING_USER, "custom_accepted_by": ACCOUNTING_USER})
        t2.flags.ignore_permissions = True
        t2.insert()
        # committing must refuse, because there is nothing billable
        frappe.set_user(ACCOUNTING_USER)
        frappe.form_dict.clear()
        frappe.form_dict["task_name"] = t2.name
        try:
            frappe.response.pop("message", None)
            commit.execute_method()
            results.append(("NTI commit refused when nothing used", "FAIL", "created an invoice"))
        except Exception as e:
            results.append(("NTI commit refused when nothing used", "PASS", "blocked: " + str(e)[:80]))
        closer = frappe.get_doc("Server Script", "task_close_case_nothing_to_invoice")
        frappe.set_user(ACCOUNTING_USER)
        frappe.form_dict.clear()
        frappe.form_dict["task_name"] = t2.name
        frappe.form_dict["reason"] = "W6VERIFY: client returned everything unused"
        try:
            frappe.response.pop("message", None)
            closer.execute_method()
            frappe.set_user("Administrator")
            st = frappe.db.get_value("Dispatch Case", case2.name, "status")
            tst = frappe.db.get_value("Task", t2.name, "status")
            if st == "Closed" and tst == "Completed":
                results.append(("NTI closes case and completes task", "PASS", "case=Closed task=Completed"))
            else:
                results.append(("NTI closes case and completes task", "FAIL", "case=" + str(st) + " task=" + str(tst)))
        except Exception as e:
            results.append(("NTI closes case and completes task", "FAIL", str(e)[:150]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("W6VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("W6VERIFY | {0:<40} | {1:<4} | {2}".format(name, verdict, detail))
    print("W6VERIFY_RESULTS_END")
w6_verify("e2e.accounting@test.erpnext.am", "e2e.order.creating@test.erpnext.am")
