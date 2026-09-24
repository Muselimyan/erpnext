# ==============================================================
# D4 + D5 + D6 verification. Run against TEST.
#
# Includes a regression check that matters more than the cleanup itself: the
# Returns restocking photo gate is a NEW refusal on a task the flow creates
# automatically, so it has to refuse without a photo AND pass with one. A gate
# that only refuses would strand every returns case.
#
# Everything is rolled back.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-1-dispatch-operational\d4-d6-verify-cleanup.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
# ==============================================================
import frappe
def d46_verify(RETURNS_USER):
    results = []
    RETURNS_WH = "Returns - Inmed"
    try:
        frappe.set_user("Administrator")
        company = frappe.db.get_single_value("Global Defaults", "default_company") or "InMED"
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        # ---- D4: task_kind options and default ----
        tk = frappe.get_doc("Custom Field", "Task-task_kind")
        opts = [o for o in (tk.options or "").split("\n") if o]
        gone = [k for k in ["Order accepting", "Dispatch picking / hand-off"] if k in opts]
        results.append(("D4 retired kinds removed from options", "PASS" if not gone else "FAIL", "still present: " + ", ".join(gone) if gone else "{0} options remain".format(len(opts))))
        results.append(("D4 default is now Order entry", "PASS" if tk.default == "Order entry" else "FAIL", "default='{0}'".format(tk.default)))
        held = [k for k in ["Return drop-off at warehouse", "Return to warehouse (aborted delivery / cancelled order)"] if k in opts]
        results.append(("D4 held-back kinds still present", "PASS" if len(held) == 2 else "FAIL", "{0} of 2".format(len(held))))
        # ---- D5: profit field and both allow-list entries gone ----
        has_profit = frappe.db.exists("Custom Field", "Dispatch Case-profit")
        results.append(("D5 Dispatch Case.profit deleted", "PASS" if not has_profit else "FAIL", "still exists" if has_profit else "gone"))
        leftover = []
        for s in ["Dispatch-Case-before-save-access-control", "Dispatch-Case-before-save-submitted-access-control"]:
            body = frappe.db.get_value("Server Script", s, "script") or ""
            code = "\n".join([ln.split("#")[0] for ln in body.split("\n")])
            if '"profit"' in code:
                leftover.append(s)
        results.append(("D5 profit removed from both SYSTEM_FIELDS", "PASS" if not leftover else "FAIL", ", ".join(leftover) or "both clean"))
        # ---- D6: surgery_set_type property setter gone ----
        ps = frappe.db.exists("Property Setter", "Dispatch Case-surgery_set_type-allow_on_submit")
        results.append(("D6 surgery_set_type setter deleted", "PASS" if not ps else "FAIL", "still exists" if ps else "gone"))
        # ---- D6: tab_is_admin gone from the deployed client script ----
        ab = frappe.db.get_value("Client Script", "Task-Action Buttons", "script") or ""
        abcode = "\n".join([ln.split("//")[0] for ln in ab.split("\n")])
        results.append(("D6 tab_is_admin removed", "PASS" if "function tab_is_admin" not in abcode else "FAIL", "gone" if "function tab_is_admin" not in abcode else "still defined"))
        results.append(("D6 tab_can_complete still present", "PASS" if "tab_can_complete" in abcode else "FAIL", ""))
        # ---- D6: stale debt-closure comment corrected ----
        g = frappe.db.get_value("Server Script", "Task-before-save-dispatch-gates", "script") or ""
        stale = "retains its own equivalent check" in g
        results.append(("D6 stale debt-closure comment corrected", "PASS" if not stale else "FAIL", "corrected" if not stale else "still claims a disabled script checks"))
        # ---- D6: user_has_allowed_role NOT deleted (D3 needs it) ----
        pol = frappe.db.get_value("Server Script", "Task-before-save-policy", "script") or ""
        results.append(("D6 user_has_allowed_role preserved for D3", "PASS" if "def user_has_allowed_role" in pol else "FAIL", "present" if "def user_has_allowed_role" in pol else "DELETED - D3 will fail at runtime"))
        # ---- D6: the restock photo gate, both directions ----
        priced = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, ["item_code", "price_list_rate"], as_dict=True)
        item = priced.item_code
        rate = float(priced.price_list_rate)
        uom = frappe.db.get_value("Item", item, "stock_uom") or "Nos"
        wh = frappe.db.get_value("Warehouse", {"is_group": 0, "name": ["not like", "%In-Transit%"]}, "name")
        seed = frappe.get_doc({"doctype": "Stock Entry", "stock_entry_type": "Material Receipt", "purpose": "Material Receipt", "company": company, "items": [{"item_code": item, "qty": 3, "transfer_qty": 3, "uom": uom, "stock_uom": uom, "conversion_factor": 1, "t_warehouse": RETURNS_WH, "basic_rate": 100, "cost_center": "Main - Inmed", "expense_account": "Stock Adjustment - Inmed"}]})
        seed.flags.ignore_permissions = True
        seed.insert()
        seed.submit()
        def mkcase():
            c = frappe.new_doc("Dispatch Case")
            c.status = "Confirmed"
            c.customer = cust
            c.client_location_warehouse = wh
            c.return_expected = 1
            c.flags.ignore_permissions = True
            c.flags.ignore_mandatory = True
            r = c.append("case_items", {})
            r.item_code = item
            r.item_name = item
            r.dispatched_qty = 3
            r.returned_qty = 3
            r.unit_price = rate
            c.insert()
            c.flags.ignore_permissions = True
            c.submit()
            frappe.db.set_value("Dispatch Case", c.name, "status", "Invoice Pending")
            return c
        def mkrestock(case):
            t = frappe.get_doc({"doctype": "Task", "subject": "D46 restock", "task_kind": "Returns restocking", "task_access_policy": "Returns restocking", "customer": cust, "dispatch_case": case.name, "status": "Working", "custom_assigned_to": RETURNS_USER, "custom_accepted_by": RETURNS_USER})
            t.flags.ignore_permissions = True
            t.insert()
            return t
        # without a photo -> refused
        c1 = mkcase()
        t1 = mkrestock(c1)
        frappe.set_user(RETURNS_USER)
        try:
            t1.reload()
            t1.status = "Completed"
            t1.save()
            results.append(("D6 restock refused without a photo", "FAIL", "completion was allowed"))
        except Exception as e:
            msg = str(e)
            ok = "photo is required before completing Returns restocking" in msg
            results.append(("D6 restock refused without a photo", "PASS" if ok else "FAIL", msg[:100]))
        frappe.set_user("Administrator")
        # with a photo -> allowed, and the stock actually moves
        c2 = mkcase()
        t2 = mkrestock(c2)
        ph = frappe.get_doc({"doctype": "File", "file_name": "d46.png", "file_url": "/files/d46.png", "attached_to_doctype": "Task", "attached_to_name": t2.name, "is_private": 0})
        ph.name = "d46-" + frappe.generate_hash("", 8)
        ph.db_insert()
        frappe.set_user(RETURNS_USER)
        err = ""
        try:
            t2.reload()
            t2.status = "Completed"
            t2.save()
        except Exception as e:
            err = str(e)[:110]
        frappe.set_user("Administrator")
        se = frappe.db.get_value("Dispatch Case", c2.name, "restock_stock_entry")
        results.append(("D6 restock ALLOWED with a photo", "PASS" if se else "FAIL", se or err or "no stock entry"))
    except Exception as e:
        results.append(("RUN", "FAIL", str(e)[:170]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("D46VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("D46VERIFY | {0:<44} | {1:<4} | {2}".format(name, verdict, detail))
    print("D46VERIFY_RESULTS_END")
d46_verify("e2e.returns@test.erpnext.am")
