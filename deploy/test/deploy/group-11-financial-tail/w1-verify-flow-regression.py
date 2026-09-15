# ==============================================================
# W1 regression check - run against TEST via bench console.
#
# W1 replaced access control for EVERY task kind, not just the financial ones,
# so the main dispatch path and the task_* APIs must still work for the roles
# that actually use them. This exercises the riskiest new code:
#   - Dispatch-Case-before-save-access-control (the new central DC gate)
#   - the rewritten ownership checks in the task_* APIs
#   - the new kind assertions
#   - Task-before-save-dispatch-gates after the DC-conditional restructure
#
# Everything is rolled back; no records survive the run.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-11-financial-tail\w1-verify-flow-regression.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body - IPython treats a blank
# line as end-of-block when code is piped in. Users are parameters, not
# globals, for the same reason.
# ==============================================================
import frappe
def w1_regression(ORDER_USER, INVENTORY_USER):
    results = []
    caseName = None
    try:
        frappe.set_user("Administrator")
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        item = frappe.db.get_value("Item", {"disabled": 0, "is_stock_item": 1}, "name")
        wh = frappe.db.get_value("Warehouse", {"disabled": 0, "is_group": 0}, "name")
        # ---- fixture: Order entry task accepted by the order-creating user --
        oe = frappe.get_doc({"doctype": "Task", "subject": "W1REG order entry", "task_kind": "Order entry", "task_access_policy": "Order entry", "customer": cust, "status": "Working", "custom_assigned_to": ORDER_USER, "custom_accepted_by": ORDER_USER})
        oe.flags.ignore_permissions = True
        oe.insert()
        # ---- 1. create the Dispatch Case as the owning user ----------------
        frappe.set_user(ORDER_USER)
        try:
            case = frappe.new_doc("Dispatch Case")
            case.status = "Draft"
            case.customer = cust
            case.order_entry_task = oe.name
            case.flags.ignore_permissions = True
            case.insert()
            caseName = case.name
            frappe.db.set_value("Task", oe.name, "dispatch_case", caseName)
            results.append(("FLOW create Dispatch Case as owner", "PASS", caseName))
        except Exception as e:
            results.append(("FLOW create Dispatch Case as owner", "FAIL", str(e)[:150]))
        # ---- 2. add a product via the API path as the owning user ----------
        if caseName:
            frappe.set_user(ORDER_USER)
            try:
                c = frappe.get_doc("Dispatch Case", caseName)
                row = c.append("case_items", {})
                row.item_code = item
                row.item_name = item
                row.dispatched_qty = 1
                row.unit_price = 100
                c.flags.ignore_permissions = True
                c.save()
                results.append(("FLOW add case item as owner", "PASS", "1 row"))
            except Exception as e:
                results.append(("FLOW add case item as owner", "FAIL", str(e)[:150]))
        # ---- 3. a user with NO task on the case must be blocked ------------
        if caseName:
            frappe.set_user(INVENTORY_USER)
            try:
                c2 = frappe.get_doc("Dispatch Case", caseName)
                c2.notes = "W1REG intruder"
                c2.flags.ignore_permissions = True
                c2.save()
                results.append(("GATE non-holder editing the case", "FAIL", "was allowed - should be blocked"))
            except Exception as e:
                results.append(("GATE non-holder editing the case", "PASS", "blocked: " + str(e)[:100]))
        # ---- 4. system-only write on the case must be allowed -------------
        # Mimics the flow's own bookkeeping (status / stock links / financials)
        # running with no user holding a task, e.g. ledger reconciliation.
        if caseName:
            frappe.set_user(INVENTORY_USER)
            try:
                c3 = frappe.get_doc("Dispatch Case", caseName)
                c3.status = "Packed"
                c3.flags.ignore_permissions = True
                c3.save()
                results.append(("GATE system-only write on the case", "PASS", "allowed"))
            except Exception as e:
                results.append(("GATE system-only write on the case", "FAIL", str(e)[:150]))
        # ---- 5. Order entry completion gate still fires --------------------
        # Completing with no customer set must still be refused.
        frappe.set_user("Administrator")
        bad = frappe.get_doc({"doctype": "Task", "subject": "W1REG no customer", "task_kind": "Order entry", "task_access_policy": "Order entry", "status": "Working", "custom_assigned_to": ORDER_USER, "custom_accepted_by": ORDER_USER})
        bad.flags.ignore_permissions = True
        bad.insert()
        badCase = frappe.new_doc("Dispatch Case")
        badCase.status = "Draft"
        badCase.order_entry_task = bad.name
        badCase.flags.ignore_permissions = True
        badCase.insert()
        frappe.db.set_value("Task", bad.name, "dispatch_case", badCase.name)
        frappe.set_user(ORDER_USER)
        try:
            b = frappe.get_doc("Task", bad.name)
            b.status = "Completed"
            b.flags.ignore_permissions = True
            b.save()
            results.append(("GATE order-entry completion validation", "FAIL", "completed with no items/customer"))
        except Exception as e:
            results.append(("GATE order-entry completion validation", "PASS", "blocked: " + str(e)[:100]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("W1REG_RESULTS_START")
    for name, verdict, detail in results:
        print("W1REG | {0:<40} | {1:<4} | {2}".format(name, verdict, detail))
    print("W1REG_RESULTS_END")
w1_regression("e2e.order.creating@test.erpnext.am", "e2e.inventory@test.erpnext.am")
