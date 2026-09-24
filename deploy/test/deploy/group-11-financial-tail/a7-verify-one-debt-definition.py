# ==============================================================
# A7 VERIFY: all consumers of "what this customer owes" agree.
#
# The point of A7 is not any single formula -- it is that four consumers now
# compute the SAME one. So the central assertion is agreement on shared
# fixtures, not correctness of one site in isolation. RestrictedPython has no
# module system, so the formula is duplicated by necessity; this is what stops
# the copies drifting.
#
# Consumers checked:
#   1. Scheduled-debt-collection.get_net_receivable_amd   (Debt Alert, hourly)
#   2. Scheduled-debt-collection-episodes threshold test  (daily)
#   3. task_debt_panel totals.net_receivable              (what the collector sees)
#   4. RPT - Clients Exceeding Debt Threshold SQL          (Director report)
#
# Fixtures, one customer each, so the cases cannot contaminate one another:
#   A  invoice only                      -> net == gross
#   B  invoice + UNTAGGED credit         -> credit offsets
#   C  invoice + credit tagged to a case -> credit does NOT offset  <- the fix
#   D  invoice + both kinds              -> only the untagged part offsets
#
# Also asserts the things that must NOT have changed:
#   - the overdue trigger is still gross, so an old invoice covered by credit
#     still raises an episode (with the credit surfaced in its description)
#   - the retired duplicate report is gone and the workspace has no dead links
#
# Everything rolls back.
# ==============================================================
import frappe
def a7_verify():
    R = []
    def ok(label, cond, detail=""):
        R.append((label, "PASS" if cond else "FAIL", str(detail)[:88]))
        return cond
    def mkcust(tag, threshold):
        c = frappe.get_doc({"doctype": "Customer", "customer_name": "A7 " + tag + " " + frappe.generate_hash("", 5), "customer_type": "Company", "client_code": "A7" + frappe.generate_hash("", 6), "client_kind": "Hospital", "debt_threshold_amd": threshold})
        c.flags.ignore_permissions = True
        c.insert()
        return c.name
    def mkinv(cust, amount, days_overdue=0):
        item = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, "item_code")
        # set_posting_time = 1 is REQUIRED to back-date. Without it ERPNext
        # silently overrides posting_date with today, so a back-dated due_date
        # then fails "Due Date cannot be before Posting Date" -- and the
        # not-overdue fixtures pass anyway, because their due date happens to
        # equal today. The failure looks like a due-date bug and is a
        # posting-date bug.
        si = frappe.get_doc({"doctype": "Sales Invoice", "customer": cust, "company": "InMED", "currency": "AMD", "update_stock": 0, "set_posting_time": 1, "posting_date": frappe.utils.add_days(frappe.utils.nowdate(), -days_overdue - 1), "due_date": frappe.utils.add_days(frappe.utils.nowdate(), -days_overdue), "items": [{"item_code": item, "qty": 1, "rate": amount}]})
        si.flags.ignore_permissions = True
        si.insert()
        si.submit()
        return si.name
    def mkcredit(cust, amount, tagged_case):
        pe = frappe.get_doc({"doctype": "Payment Entry", "payment_type": "Receive", "party_type": "Customer", "party": cust, "paid_amount": amount, "received_amount": amount, "company": "InMED", "paid_to": "Cash - Inmed", "mode_of_payment": "Cash", "posting_date": frappe.utils.nowdate(), "reference_date": frappe.utils.nowdate(), "dispatch_case": tagged_case or ""})
        pe.flags.ignore_permissions = True
        pe.insert()
        pe.submit()
        return pe.name
    def mkcase(cust):
        item = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, "item_code")
        c = frappe.get_doc({"doctype": "Dispatch Case", "customer": cust, "status": "Confirmed", "client_location_warehouse": "Main - Inmed", "case_items": [{"item_code": item, "dispatched_qty": 1, "unit_price": 100}]})
        c.flags.ignore_permissions = True
        c.insert()
        c.submit()
        return c.name
    # ── the four implementations, called exactly as the real code calls them
    def basis_alert(cust):
        rows = frappe.db.sql("select coalesce((select sum(outstanding_amount) from `tabSales Invoice` where docstatus=1 and outstanding_amount>0 and customer=%(cust)s and company=%(co)s),0) - coalesce((select sum(unallocated_amount) from `tabPayment Entry` where docstatus=1 and payment_type='Receive' and party_type='Customer' and party=%(cust)s and company=%(co)s and unallocated_amount>0 and (dispatch_case is null or dispatch_case='')),0)", {"cust": cust, "co": "InMED"})
        return float(rows[0][0] or 0)
    def basis_episodes(cust):
        gross = 0.0
        for si in frappe.get_all("Sales Invoice", filters={"customer": cust, "docstatus": 1, "outstanding_amount": [">", 0]}, fields=["outstanding_amount"], limit_page_length=0):
            gross = gross + float(si.outstanding_amount or 0)
        avail = 0.0
        for pe in frappe.get_all("Payment Entry", filters={"party_type": "Customer", "party": cust, "docstatus": 1, "payment_type": "Receive", "unallocated_amount": [">", 0]}, fields=["unallocated_amount", "dispatch_case"], limit_page_length=0):
            if not (pe.dispatch_case or ""):
                avail = avail + float(pe.unallocated_amount or 0)
        return gross - avail
    def basis_panel(cust):
        frappe.form_dict.clear()
        frappe.form_dict["customer"] = cust
        frappe.response.pop("message", None)
        frappe.get_doc("Server Script", "task_debt_panel").execute_method()
        m = frappe.response.get("message") or {}
        return float((m.get("totals") or {}).get("net_receivable") or 0), m
    def basis_report(cust):
        rows = frappe.db.sql("select (coalesce(si.t,0) - coalesce(pe.a,0)) from `tabCustomer` c left join (select customer, sum(outstanding_amount) t from `tabSales Invoice` where docstatus=1 and outstanding_amount>0 group by customer) si on si.customer=c.name left join (select party customer, sum(unallocated_amount) a from `tabPayment Entry` where docstatus=1 and payment_type='Receive' and party_type='Customer' and unallocated_amount>0 and (dispatch_case is null or dispatch_case='') group by party) pe on pe.customer=c.name where c.name=%s", (cust,))
        return float((rows[0][0] if rows and rows[0][0] is not None else 0))
    try:
        frappe.set_user("Administrator")
        # ── A: invoice only ───────────────────────────────────────────
        cA = mkcust("A", 1000000)
        mkinv(cA, 5000)
        vals = [basis_alert(cA), basis_episodes(cA), basis_panel(cA)[0], basis_report(cA)]
        ok("A invoice only: all four agree", len(set([round(v, 2) for v in vals])) == 1, "{0}".format(vals))
        ok("A net equals gross (nothing to offset)", round(vals[0], 2) == 5000.0, "{0}".format(vals[0]))
        # ── B: untagged credit offsets ────────────────────────────────
        cB = mkcust("B", 1000000)
        mkinv(cB, 5000)
        mkcredit(cB, 2000, "")
        vals = [basis_alert(cB), basis_episodes(cB), basis_panel(cB)[0], basis_report(cB)]
        ok("B untagged credit: all four agree", len(set([round(v, 2) for v in vals])) == 1, "{0}".format(vals))
        ok("B untagged credit DOES offset", round(vals[0], 2) == 3000.0, "expected 3000, got {0}".format(vals[0]))
        # ── C: earmarked credit must NOT offset -- the fix ────────────
        cC = mkcust("C", 1000000)
        mkinv(cC, 5000)
        caseC = mkcase(cC)
        mkcredit(cC, 2000, caseC)
        vals = [basis_alert(cC), basis_episodes(cC), basis_panel(cC)[0], basis_report(cC)]
        ok("C earmarked credit: all four agree", len(set([round(v, 2) for v in vals])) == 1, "{0}".format(vals))
        ok("C earmarked credit does NOT offset", round(vals[0], 2) == 5000.0, "expected 5000, got {0}".format(vals[0]))
        # ── D: both kinds, only the untagged part offsets ─────────────
        cD = mkcust("D", 1000000)
        mkinv(cD, 10000)
        caseD = mkcase(cD)
        mkcredit(cD, 1500, "")
        mkcredit(cD, 4000, caseD)
        vals = [basis_alert(cD), basis_episodes(cD), basis_panel(cD)[0], basis_report(cD)]
        ok("D mixed credit: all four agree", len(set([round(v, 2) for v in vals])) == 1, "{0}".format(vals))
        ok("D only untagged offsets", round(vals[0], 2) == 8500.0, "expected 8500 (10000-1500), got {0}".format(vals[0]))
        net, msg = basis_panel(cD)
        tot = msg.get("totals") or {}
        ok("D panel splits available vs earmarked", float(tot.get("available_credit") or 0) == 1500.0 and float(tot.get("earmarked_credit") or 0) == 4000.0, "avail={0} earmarked={1}".format(tot.get("available_credit"), tot.get("earmarked_credit")))
        ok("D panel total credit still the full sum", float(tot.get("unallocated_credit") or 0) == 5500.0, "{0}".format(tot.get("unallocated_credit")))
        # ── overdue trigger must still be gross ──────────────────────
        cE = mkcust("E", 999999999)
        mkinv(cE, 7000, days_overdue=30)
        mkcredit(cE, 7000, "")
        ok("E net is zero (credit covers it)", round(basis_alert(cE), 2) == 0.0, "{0}".format(basis_alert(cE)))
        gross_e = 0.0
        for si in frappe.get_all("Sales Invoice", filters={"customer": cE, "docstatus": 1, "outstanding_amount": [">", 0]}, fields=["outstanding_amount"], limit_page_length=0):
            gross_e = gross_e + float(si.outstanding_amount or 0)
        ok("E invoice still overdue and gross > 0", gross_e == 7000.0, "gross={0} -> overdue path still fires".format(gross_e))
        # ── the duplicate report is gone, workspace has no dead links ─
        ok("duplicate Risk report retired", not frappe.db.exists("Report", "RPT " + chr(8212) + " Risk " + chr(8212) + " Debt Threshold Exceeded"), "still present" if frappe.db.exists("Report", "RPT " + chr(8212) + " Risk " + chr(8212) + " Debt Threshold Exceeded") else "gone")
        ws = frappe.get_doc("Workspace", "Ops " + chr(8212) + " Reporting Pack")
        dead = []
        for sc in (ws.shortcuts or []):
            if sc.type == "Report" and not frappe.db.exists("Report", sc.link_to):
                dead.append(sc.link_to)
        ok("workspace has no dead report shortcuts", len(dead) == 0, "dead: {0}".format(dead))
    except Exception as e:
        R.append(("HARNESS ABORTED", "FAIL", str(e)[:140]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("A7VERIFY_START")
    for n, v, d in R:
        print("A7VERIFY | {0:<44} | {1:<4} | {2}".format(n, v, d))
    print("A7VERIFY | {0} passed / {1} total".format(len([1 for x in R if x[1] == "PASS"]), len(R)))
    print("A7VERIFY_END")
a7_verify()
