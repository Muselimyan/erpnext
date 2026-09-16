# ==============================================================
# W9 verification - run against TEST via bench console.
#
# Proves the submitted-document gate now covers what "Before Save" never could,
# that the flow's own bookkeeping still passes it, that a financial change
# produces version history naming the user, and that the operational flow on a
# submitted case still works for the roles that do the work.
#
# Everything is rolled back; no records survive the run.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-11-financial-tail\w9-verify-submit-contract.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body, params not globals.
# ==============================================================
import frappe
def w9_verify(INVENTORY_USER, ACCOUNTING_USER):
    results = []
    try:
        frappe.set_user("Administrator")
        company = frappe.db.get_single_value("Global Defaults", "default_company") or "InMED"
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        priced = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, ["item_code", "price_list_rate"], as_dict=True)
        rate = float(priced.price_list_rate)
        case = frappe.new_doc("Dispatch Case")
        case.status = "Confirmed"
        case.customer = cust
        case.flags.ignore_permissions = True
        case.flags.ignore_mandatory = True
        r = case.append("case_items", {})
        r.item_code = priced.item_code
        r.item_name = priced.item_code
        r.dispatched_qty = 1
        r.used_qty = 1
        r.unit_price = rate
        case.insert()
        case.flags.ignore_permissions = True
        case.submit()
        # ---- 1. the gap is closed: non-holder blocked on a SUBMITTED case -
        frappe.set_user(INVENTORY_USER)
        try:
            c = frappe.get_doc("Dispatch Case", case.name)
            c.notes = "W9VERIFY intruder on a submitted case"
            c.flags.ignore_permissions = True
            c.save()
            results.append(("GATE non-holder on SUBMITTED case", "FAIL", "still allowed"))
        except Exception as e:
            results.append(("GATE non-holder on SUBMITTED case", "PASS", "blocked: " + str(e)[:95]))
        # ---- 2. a task holder CAN still work a submitted case -------------
        # This is the whole reason the Director-only restriction was not carried
        # over: packing, delivery and returns all mutate a submitted case.
        frappe.set_user("Administrator")
        packtask = frappe.get_doc({"doctype": "Task", "subject": "W9VERIFY pack", "task_kind": "Pack / prepare items", "task_access_policy": "Pack / prepare items", "customer": cust, "dispatch_case": case.name, "status": "Working", "custom_assigned_to": INVENTORY_USER, "custom_accepted_by": INVENTORY_USER})
        packtask.flags.ignore_permissions = True
        packtask.insert()
        frappe.set_user(INVENTORY_USER)
        try:
            c = frappe.get_doc("Dispatch Case", case.name)
            for row in c.case_items:
                row.custom_scanned_qty = 1
            c.flags.ignore_permissions = True
            c.flags.ignore_validate_update_after_submit = True
            c.save()
            results.append(("GATE task holder works submitted case", "PASS", "scanned qty saved"))
        except Exception as e:
            results.append(("GATE task holder works submitted case", "FAIL", str(e)[:120]))
        # ---- 3. system bookkeeping passes on a submitted case -------------
        frappe.set_user(ACCOUNTING_USER)
        try:
            c = frappe.get_doc("Dispatch Case", case.name)
            c.status = "Invoice Pending"
            c.flags.ignore_permissions = True
            c.save()
            results.append(("GATE system-only write on submitted", "PASS", "status change allowed"))
        except Exception as e:
            results.append(("GATE system-only write on submitted", "FAIL", str(e)[:120]))
        # ---- 4. a financial change leaves version history -----------------
        frappe.set_user("Administrator")
        si = frappe.get_doc({"doctype": "Sales Invoice", "customer": cust, "company": company, "currency": "AMD", "update_stock": 0, "dispatch_case": case.name, "items": [{"item_code": priced.item_code, "qty": 1, "rate": rate}]})
        si.flags.ignore_permissions = True
        si.insert()
        si.submit()
        invtask = frappe.get_doc({"doctype": "Task", "subject": "W9VERIFY invoice", "task_kind": "Invoice preparation / create invoice", "task_access_policy": "Invoice preparation / create invoice", "customer": cust, "dispatch_case": case.name, "status": "Working", "custom_assigned_to": ACCOUNTING_USER, "custom_accepted_by": ACCOUNTING_USER})
        invtask.flags.ignore_permissions = True
        invtask.insert()
        versions_before = frappe.db.count("Version", {"ref_doctype": "Dispatch Case", "docname": case.name})
        frappe.set_user(ACCOUNTING_USER)
        try:
            t = frappe.get_doc("Task", invtask.name)
            t.status = "Completed"
            t.flags.ignore_permissions = True
            t.save()
            frappe.set_user("Administrator")
            versions_after = frappe.db.count("Version", {"ref_doctype": "Dispatch Case", "docname": case.name})
            amt = frappe.db.get_value("Dispatch Case", case.name, ["total_invoice_amount", "outstanding_amount"], as_dict=True)
            if versions_after > versions_before:
                results.append(("AUDIT financial change leaves a Version", "PASS", str(versions_before) + " -> " + str(versions_after) + " rows"))
            else:
                results.append(("AUDIT financial change leaves a Version", "FAIL", "still " + str(versions_after) + " version rows"))
            if float(amt.total_invoice_amount or 0) > 0:
                results.append(("AUDIT financial fields written", "PASS", "total=" + str(amt.total_invoice_amount) + " outstanding=" + str(amt.outstanding_amount)))
            else:
                results.append(("AUDIT financial fields written", "FAIL", "total_invoice_amount=" + str(amt.total_invoice_amount)))
        except Exception as e:
            results.append(("AUDIT financial change leaves a Version", "FAIL", str(e)[:120]))
            results.append(("AUDIT financial fields written", "FAIL", "not reached"))
        # ---- 5. Invoiced is gone from the status options -------------------
        frappe.set_user("Administrator")
        opts = frappe.get_meta("Dispatch Case").get_field("status").options or ""
        if "Invoiced" not in [o.strip() for o in opts.split("\n")]:
            results.append(("SCHEMA Invoiced status removed", "PASS", "not in options"))
        else:
            results.append(("SCHEMA Invoiced status removed", "FAIL", "still present"))
        # ---- 6. the mojibake in the task subject is gone -------------------
        body = frappe.db.get_value("Server Script", "Dispatch-Case-after-save", "script") or ""
        if "\u00e2\u0080\u0094" in body:
            results.append(("TEXT discount task subject mojibake", "FAIL", "still corrupted"))
        elif "\u2014" in body:
            results.append(("TEXT discount task subject mojibake", "PASS", "clean em-dash"))
        else:
            results.append(("TEXT discount task subject mojibake", "WARN", "no em-dash found at all"))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("W9VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("W9VERIFY | {0:<40} | {1:<4} | {2}".format(name, verdict, detail))
    print("W9VERIFY_RESULTS_END")
w9_verify("e2e.inventory@test.erpnext.am", "e2e.accounting@test.erpnext.am")
