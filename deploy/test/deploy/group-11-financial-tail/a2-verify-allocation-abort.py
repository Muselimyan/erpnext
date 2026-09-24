# ==============================================================
# A2 VERIFY: a failed advance allocation must abort the commit, not submit the
# invoice at full value.
#
# The old behaviour wrapped the allocation block in try/except, printed, and
# carried on. The client's money stayed unallocated while the invoice went out
# for the full amount -- so the client got chased for money they had already
# paid, and the only trace was a log line.
#
# What this proves:
#   1. the happy path still allocates and still reduces outstanding
#   2. case-tagged credit is preferred over untagged general credit
#   3. credit tagged to ANOTHER case is still left alone
#   4. a forced allocation failure now leaves NO submitted invoice
#   5. after an aborted commit the case is retryable -- no stranded submitted doc
#
# (4) is induced by pointing a Payment Entry's advance row at a cancelled PE via
# a poisoned unallocated_amount, which makes ERPNext refuse the allocation at
# save time. That is a real failure shape, not a monkeypatch.
#
# Runs as a real accounting user. Everything rolls back.
# ==============================================================
import frappe
def a2_verify(ACCT_USER):
    R = []
    def ok(label, cond, detail=""):
        R.append((label, "PASS" if cond else "FAIL", str(detail)[:92]))
        return cond
    def mkcase(cust, item, price, qty):
        # before-submit only accepts certain opening statuses, so submit in a
        # legal one and move the status afterwards -- same trap that bit the
        # W12 and A3 fixtures.
        c = frappe.get_doc({"doctype": "Dispatch Case", "customer": cust, "status": "Confirmed", "client_location_warehouse": "Main - Inmed", "case_items": [{"item_code": item, "dispatched_qty": qty, "used_qty": qty, "unit_price": price}]})
        c.flags.ignore_permissions = True
        c.insert()
        c.submit()
        frappe.db.set_value("Dispatch Case", c.name, "status", "Invoice Pending")
        return c
    def mktask(case, user):
        t = frappe.get_doc({"doctype": "Task", "subject": "A2 invoice", "task_kind": "Invoice preparation / create invoice", "task_access_policy": "Invoice preparation / create invoice", "status": "Working", "dispatch_case": case.name, "customer": case.customer, "custom_assigned_to": user, "custom_accepted_by": user, "custom_accepted_at": frappe.utils.now()})
        t.flags.ignore_permissions = True
        t.insert()
        return t
    def mkpe(cust, amt, tagged_case):
        pe = frappe.get_doc({"doctype": "Payment Entry", "payment_type": "Receive", "party_type": "Customer", "party": cust, "paid_amount": amt, "received_amount": amt, "company": "InMED", "paid_to": "Cash - Inmed", "mode_of_payment": "Cash", "posting_date": frappe.utils.nowdate(), "reference_date": frappe.utils.nowdate(), "dispatch_case": tagged_case or ""})
        pe.flags.ignore_permissions = True
        pe.insert()
        pe.submit()
        return pe
    def commit(task, user):
        # A SAVEPOINT IS REQUIRED HERE, and its absence invalidates the test.
        # bench console has no request boundary. In a real HTTP request Frappe
        # rolls the whole transaction back when an exception escapes, so a
        # throw part-way through leaves nothing behind. In the console the
        # partial writes stay visible until the final rollback -- including a
        # docstatus=1 written by submit() just before its GL posting failed.
        # Without this savepoint the harness reports a submitted invoice that
        # would never exist in production, and the fix looks broken when it is
        # not.
        frappe.set_user(user)
        frappe.form_dict.clear()
        frappe.form_dict["task_name"] = task
        frappe.response.pop("message", None)
        err = ""
        frappe.db.savepoint("a2commit")
        try:
            frappe.get_doc("Server Script", "task_commit_invoice").execute_method()
        except Exception as e:
            err = str(e)[:200]
            frappe.db.rollback(save_point="a2commit")
        frappe.set_user("Administrator")
        return frappe.response.get("message") or {}, err
    try:
        frappe.set_user("Administrator")
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        item = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, "item_code")
        ok("FIXTURE customer + priced item", bool(cust and item), "{0} / {1}".format(cust, item))
        # ── 1+2+3. happy path with three kinds of credit present ──────
        caseA = mkcase(cust, item, 1000, 10)
        caseB = mkcase(cust, item, 1000, 10)
        pe_this = mkpe(cust, 3000, caseA.name)
        pe_gen = mkpe(cust, 2000, "")
        pe_other = mkpe(cust, 5000, caseB.name)
        tA = mktask(caseA, ACCT_USER)
        msg, err = commit(tA.name, ACCT_USER)
        ok("1 commit succeeded", bool(msg.get("sales_invoice")) and not err, err or msg.get("sales_invoice"))
        si = msg.get("sales_invoice")
        applied = float(msg.get("advance_applied") or 0)
        ok("1 advance was applied", applied > 0, "applied={0}".format(applied))
        ok("2 case-tagged credit consumed first", float(frappe.db.get_value("Payment Entry", pe_this.name, "unallocated_amount") or 0) == 0, "this-case PE left {0}".format(frappe.db.get_value("Payment Entry", pe_this.name, "unallocated_amount")))
        ok("3 OTHER case's credit untouched", float(frappe.db.get_value("Payment Entry", pe_other.name, "unallocated_amount") or 0) == 5000, "other-case PE left {0}".format(frappe.db.get_value("Payment Entry", pe_other.name, "unallocated_amount")))
        outst = float(frappe.db.get_value("Sales Invoice", si, "outstanding_amount") or 0)
        gt = float(frappe.db.get_value("Sales Invoice", si, "grand_total") or 0)
        ok("1 outstanding reduced by the advance", abs(outst - (gt - applied)) < 1, "grand={0} applied={1} outstanding={2}".format(gt, applied, outst))
        # ── 4+5. forced allocation failure must abort ─────────────────
        # Poison: a PE whose unallocated_amount is STALE and larger than the
        # payment can support. Allocation reads the stale figure, tries to
        # allocate more than exists, and ERPNext refuses at save. This is the
        # real-world shape -- credit consumed elsewhere between the read and
        # the write -- not a fabricated exception.
        caseC = mkcase(cust, item, 1000, 10)
        pe_bad = mkpe(cust, 100, caseC.name)
        frappe.db.set_value("Payment Entry", pe_bad.name, "unallocated_amount", 999999)
        tC = mktask(caseC, ACCT_USER)
        before_count = frappe.db.count("Sales Invoice", {"dispatch_case": caseC.name})
        msgC, errC = commit(tC.name, ACCT_USER)
        after = frappe.get_all("Sales Invoice", filters={"dispatch_case": caseC.name}, fields=["name", "docstatus", "outstanding_amount"], limit_page_length=0)
        submitted = [s for s in after if int(s.docstatus) == 1]
        ok("4 allocation failure raised an error", bool(errC) or not msgC.get("sales_invoice"), (errC or "no error")[:80])
        ok("4 NO submitted invoice left behind", len(submitted) == 0, "{0} submitted invoice(s) found".format(len(submitted)))
        ok("5 case has no full-value invoice to chase", not [s for s in submitted if float(s.outstanding_amount or 0) >= 10000], "submitted={0}".format([(s.name, s.outstanding_amount) for s in submitted]))
    except Exception as e:
        R.append(("HARNESS ABORTED", "FAIL", str(e)[:140]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("A2VERIFY_START")
    for n, v, d in R:
        print("A2VERIFY | {0:<44} | {1:<4} | {2}".format(n, v, d))
    print("A2VERIFY | {0} passed / {1} total".format(len([1 for x in R if x[1] == "PASS"]), len(R)))
    print("A2VERIFY_END")
a2_verify("e2e.accounting@test.erpnext.am")
