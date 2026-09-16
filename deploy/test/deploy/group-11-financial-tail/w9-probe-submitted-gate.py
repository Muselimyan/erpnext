# ==============================================================
# W9 probe - does the Dispatch Case access-control gate cover SUBMITTED cases?
#
# Frappe's run_before_save_methods only runs `before_save` when _action ==
# "save". A submitted document saves with _action == "update_after_submit",
# which runs `before_update_after_submit` instead -- so a Server Script
# registered on "Before Save" never fires for it.
#
# Both the new gate and the old lock-submitted script it replaced are
# registered on "Before Save", so this probe determines whether the
# "only Directors may edit a submitted case" rule has ever been enforced.
#
# Rolled back; no records survive.
# ==============================================================
import frappe
def w9_probe(INVENTORY_USER):
    results = []
    try:
        frappe.set_user("Administrator")
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        priced = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, ["item_code", "price_list_rate"], as_dict=True)
        case = frappe.new_doc("Dispatch Case")
        case.status = "Confirmed"
        case.customer = cust
        case.flags.ignore_permissions = True
        case.flags.ignore_mandatory = True
        r = case.append("case_items", {})
        r.item_code = priced.item_code
        r.item_name = priced.item_code
        r.dispatched_qty = 1
        r.unit_price = priced.price_list_rate
        case.insert()
        case.flags.ignore_permissions = True
        case.submit()
        results.append(("fixture: submitted case", "INFO", case.name + " docstatus=" + str(case.docstatus)))
        # A user holding NO task on this case edits a non-system field.
        frappe.set_user(INVENTORY_USER)
        try:
            c = frappe.get_doc("Dispatch Case", case.name)
            c.notes = "W9PROBE intruder edit on a SUBMITTED case"
            c.flags.ignore_permissions = True
            c.save()
            results.append(("non-holder edits a SUBMITTED case", "GAP", "ALLOWED - the gate does not cover submitted docs"))
        except Exception as e:
            results.append(("non-holder edits a SUBMITTED case", "OK", "blocked: " + str(e)[:110]))
        # Same edit on a DRAFT case, for contrast.
        frappe.set_user("Administrator")
        draft = frappe.new_doc("Dispatch Case")
        draft.status = "Draft"
        draft.customer = cust
        draft.flags.ignore_permissions = True
        draft.flags.ignore_mandatory = True
        draft.insert()
        frappe.set_user(INVENTORY_USER)
        try:
            d = frappe.get_doc("Dispatch Case", draft.name)
            d.notes = "W9PROBE intruder edit on a DRAFT case"
            d.flags.ignore_permissions = True
            d.save()
            results.append(("non-holder edits a DRAFT case", "GAP", "ALLOWED"))
        except Exception as e:
            results.append(("non-holder edits a DRAFT case", "OK", "blocked: " + str(e)[:110]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("W9PROBE_RESULTS_START")
    for name, verdict, detail in results:
        print("W9PROBE | {0:<36} | {1:<4} | {2}".format(name, verdict, detail))
    print("W9PROBE_RESULTS_END")
w9_probe("e2e.inventory@test.erpnext.am")
