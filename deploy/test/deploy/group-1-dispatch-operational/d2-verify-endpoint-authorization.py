# ==============================================================
# D2 verification - endpoint authorization and row identity. Run against TEST.
#
# The point of this file is the NEGATIVE cases: a user holding the wrong task on
# the right case must be refused. Those are invisible to the existing e2e API
# suite, which runs entirely as Administrator -- privileged users are exempt from
# the access-control gates, and three defects in this area survived because of
# exactly that blind spot (Group 11 A5).
#
# Fixture shape: one submitted case carrying THREE open tasks at once, held by
# three different users. That is not contrived -- returns inspection fans out to
# Write-off Approval, Invoice preparation and Returns restocking simultaneously,
# which is why "do you hold any task on this case" was never sufficient.
#
# Everything is rolled back; no records survive the run.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-1-dispatch-operational\d2-verify-endpoint-authorization.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body, users passed as parameters.
# ==============================================================
import frappe
import json
def d2_verify(INV_USER, RETURNS_USER, ACCT_USER, ORDER_USER):
    results = []
    def call(script, args, as_user):
        frappe.set_user(as_user)
        frappe.form_dict.clear()
        for k in args:
            frappe.form_dict[k] = args[k]
        frappe.response.pop("message", None)
        frappe.get_doc("Server Script", script).execute_method()
        return frappe.response.get("message") or {}
    def expect_refused(label, script, args, as_user, needle):
        try:
            call(script, args, as_user)
            results.append((label, "FAIL", "call was ALLOWED"))
        except Exception as e:
            msg = str(e)
            ok = needle.lower() in msg.lower()
            results.append((label, "PASS" if ok else "FAIL", msg[:104]))
        frappe.set_user("Administrator")
    def expect_ok(label, script, args, as_user):
        try:
            m = call(script, args, as_user)
            results.append((label, "PASS" if m.get("ok") else "FAIL", json.dumps(m)[:96]))
        except Exception as e:
            results.append((label, "FAIL", str(e)[:104]))
        frappe.set_user("Administrator")
    try:
        frappe.set_user("Administrator")
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        priced = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, ["item_code", "price_list_rate"], as_dict=True)
        item = priced.item_code
        rate = float(priced.price_list_rate)
        wh = frappe.db.get_value("Warehouse", {"is_group": 0, "name": ["not like", "%In-Transit%"]}, "name")
        # ---- fixture: submitted case, two rows, three concurrent open tasks ----
        case = frappe.new_doc("Dispatch Case")
        case.status = "Confirmed"
        case.customer = cust
        case.client_location_warehouse = wh
        case.return_expected = 1
        case.flags.ignore_permissions = True
        case.flags.ignore_mandatory = True
        for q in [4, 6]:
            r = case.append("case_items", {})
            r.item_code = item
            r.item_name = item
            r.dispatched_qty = q
            r.unit_price = rate
        case.insert()
        case.flags.ignore_permissions = True
        case.submit()
        rows = frappe.get_all("Dispatch Case Item", filters={"parent": case.name}, fields=["name", "dispatched_qty"], order_by="idx asc")
        row0 = rows[0].name
        row1 = rows[1].name
        def mktask(kind, user):
            t = frappe.get_doc({"doctype": "Task", "subject": "D2VERIFY " + kind, "task_kind": kind, "task_access_policy": kind, "customer": cust, "dispatch_case": case.name, "status": "Working", "custom_assigned_to": user, "custom_accepted_by": user})
            t.flags.ignore_permissions = True
            t.insert()
            return t.name
        t_pack = mktask("Pack / prepare items", INV_USER)
        t_insp = mktask("Returns processing / verification", RETURNS_USER)
        t_inv = mktask("Invoice preparation / create invoice", ACCT_USER)
        results.append(("FIXTURE case with 3 concurrent open tasks", "PASS", "{0} rows={1}".format(case.name, len(rows))))
        # ---- 1. packing: only the Pack holder ----
        expect_ok("PACK holder may mark packed", "task_mark_item_packed", {"case_name": case.name, "row_name": row0, "packed": 1}, INV_USER)
        expect_refused("PACK refused to Invoice holder", "task_mark_item_packed", {"case_name": case.name, "row_name": row0, "packed": 1}, ACCT_USER, "Pack / prepare items task")
        expect_refused("PACK refused to Returns holder", "task_mark_item_packed", {"case_name": case.name, "row_name": row0, "packed": 1}, RETURNS_USER, "Pack / prepare items task")
        # ---- 2. scanning: only the Pack holder ----
        expect_refused("SCAN refused to Invoice holder", "dispatch_case_packing_scan", {"case_name": case.name, "barcode": item, "qty": 1}, ACCT_USER, "Pack / prepare items task")
        # ---- 3. return quantities: only the Returns holder ----
        expect_ok("RETURNS holder may set quantities", "task_update_return_item_quantities", {"case_name": case.name, "row_name": row0, "returned_qty": 4, "lost_damaged_qty": 0}, RETURNS_USER)
        expect_refused("RETURNS refused to Pack holder", "task_update_return_item_quantities", {"case_name": case.name, "row_name": row0, "returned_qty": 1, "lost_damaged_qty": 0}, INV_USER, "Returns processing")
        # ---- 4. the old index contract is refused, not silently served ----
        expect_refused("item_idx refused with an explanation", "task_mark_item_packed", {"case_name": case.name, "item_idx": 0, "packed": 1}, INV_USER, "row_name, not item_idx")
        expect_refused("packed_indices refused with an explanation", "task_mark_items_packed_batch", {"case_name": case.name, "packed_indices": "[0]", "mode": "packing"}, INV_USER, "row_names, not packed_indices")
        # ---- 5. row identity: a foreign row name is rejected ----
        other = frappe.db.get_value("Dispatch Case Item", {"parent": ["!=", case.name]}, "name")
        if other:
            expect_refused("foreign row_name rejected", "task_mark_item_packed", {"case_name": case.name, "row_name": other, "packed": 1}, INV_USER, "is not on Dispatch Case")
        # ---- 6. batch: mode must be backed by a task the caller holds ----
        expect_refused("batch 'returns' mode refused to Pack holder", "task_mark_items_packed_batch", {"case_name": case.name, "row_names": json.dumps([row0]), "mode": "returns"}, INV_USER, "requires an accepted Returns processing")
        expect_ok("batch 'packing' mode allowed to Pack holder", "task_mark_items_packed_batch", {"case_name": case.name, "row_names": json.dumps([row0, row1]), "mode": "packing"}, INV_USER)
        expect_refused("batch rejects an unknown mode", "task_mark_items_packed_batch", {"case_name": case.name, "row_names": json.dumps([row0]), "mode": "whatever"}, INV_USER, "must be 'packing' or 'returns'")
        # ---- 7. batch addresses the RIGHT rows ----
        frappe.set_user("Administrator")
        s0 = float(frappe.db.get_value("Dispatch Case Item", row0, "custom_scanned_qty") or 0)
        s1 = float(frappe.db.get_value("Dispatch Case Item", row1, "custom_scanned_qty") or 0)
        both = (s0 == 4 and s1 == 6)
        results.append(("batch marked each row its own qty", "PASS" if both else "FAIL", "row0={0} (want 4) row1={1} (want 6)".format(s0, s1)))
        # ---- 8. product removal now refuses a submitted case ----
        oe = mktask("Order entry", ORDER_USER)
        expect_refused("remove product refused on submitted case", "task_remove_dispatch_product", {"case_name": case.name, "row_name": row0}, ORDER_USER, "already submitted")
        # ---- 9. and still works on a Draft case ----
        d = frappe.new_doc("Dispatch Case")
        d.status = "Draft"
        d.customer = cust
        d.client_location_warehouse = wh
        d.flags.ignore_permissions = True
        d.flags.ignore_mandatory = True
        dr = d.append("case_items", {})
        dr.item_code = item
        dr.item_name = item
        dr.dispatched_qty = 1
        dr.unit_price = rate
        d.insert()
        drow = frappe.get_all("Dispatch Case Item", filters={"parent": d.name}, fields=["name"])[0].name
        doe = frappe.get_doc({"doctype": "Task", "subject": "D2VERIFY draft oe", "task_kind": "Order entry", "task_access_policy": "Order entry", "customer": cust, "dispatch_case": d.name, "status": "Working", "custom_assigned_to": ORDER_USER, "custom_accepted_by": ORDER_USER})
        doe.flags.ignore_permissions = True
        doe.insert()
        expect_ok("remove product allowed on Draft case", "task_remove_dispatch_product", {"case_name": d.name, "row_name": drow}, ORDER_USER)
    except Exception as e:
        results.append(("RUN", "FAIL", str(e)[:170]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("D2VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("D2VERIFY | {0:<46} | {1:<4} | {2}".format(name, verdict, detail))
    print("D2VERIFY_RESULTS_END")
d2_verify("e2e.inventory@test.erpnext.am", "e2e.returns@test.erpnext.am", "e2e.accounting@test.erpnext.am", "e2e.order.creating@test.erpnext.am")
