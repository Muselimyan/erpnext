# Name: Surgery-Case-before-save
# Type: DocType Event
# DocType: Surgery Case
# Event: Before Save
# Disabled: 0
# ---

def run_script(doc):
    MAIN_WH           = "Main - Inmed"
    DELIVERY_WH       = "Delivery In-Transit - Inmed"
    RETURN_TRANSIT_WH = "Return Pickup In-Transit - Inmed"
    RETURNS_WH        = "Returns - Inmed"

    def split_serials(s):
        if not s: return []
        return [x.strip() for x in str(s).split("\n") if x.strip()]

    def get_bin_qty(item_code, warehouse):
        return float(frappe.db.get_value("Bin", {"item_code": item_code, "warehouse": warehouse}, "actual_qty") or 0)

    def make_transfer(items, s_wh, t_wh, posting_dt=None):
        se = frappe.new_doc("Stock Entry")
        se.stock_entry_type = "Material Transfer"
        if posting_dt:
            se.set_posting_time = 1
            if hasattr(posting_dt, "date"):
                se.posting_date = posting_dt.date()
                se.posting_time = posting_dt.time()
            else:
                parts = str(posting_dt).split(" ")
                se.posting_date = parts[0]
                if len(parts) > 1: se.posting_time = parts[1].split(".")[0]
        for it in items:
            row = {"item_code": it["item_code"], "qty": it["qty"], "s_warehouse": s_wh, "t_warehouse": t_wh}
            if it.get("batch_no"):  row["batch_no"]  = it["batch_no"]
            if it.get("serial_no"): row["serial_no"] = it["serial_no"]
            se.append("items", row)
        if hasattr(se, "surgery_case"): se.surgery_case = doc.name
        if hasattr(se, "dispatch_group_id") and doc.dispatch_group_id:
            se.dispatch_group_id = doc.dispatch_group_id
        se.insert(ignore_permissions=True)
        return se

    def make_task(subject, task_kind, assign_user):
        t = frappe.new_doc("Task")
        t.subject = subject
        t.task_kind = task_kind
        t.task_access_policy = task_kind
        if hasattr(t, "surgery_case"): t.surgery_case = doc.name
        if hasattr(t, "customer"):     t.customer = doc.client
        if doc.dispatch_group_id:      t.dispatch_group_id = doc.dispatch_group_id
        if assign_user: t._assign = json.dumps([assign_user])
        t.insert(ignore_permissions=True)
        return t.name

    before       = doc.get_doc_before_save()
    before_state = (before.workflow_state if before else None) or "Draft"
    after_state  = doc.workflow_state or "Draft"
    state_changed = (before_state != after_state)

    # Auto-load template items on new case
    if after_state == "Draft" and doc.surgery_set_type and not (doc.case_items or []):
        st = frappe.get_doc("Surgery Set Type", doc.surgery_set_type)
        for r in (st.items or []):
            if r.item and float(r.default_qty or 0) > 0:
                doc.append("case_items", {"item": r.item, "dispatched_qty": float(r.default_qty),
                                          "returned_qty": 0, "lost_damaged_qty": 0, "used_qty": 0})

    # Draft: non-blocking stock shortage warning
    if after_state == "Draft":
        warnings = []
        for row in (doc.case_items or []):
            planned = float(row.dispatched_qty or 0)
            if planned > 0:
                avail = get_bin_qty(row.item, MAIN_WH)
                if avail < planned:
                    warnings.append(row.item + ": planned=" + str(planned) + " avail=" + str(avail))
        doc.shortage_note = ("Draft stock warning:\n" + "\n".join(warnings)) if warnings else ""
        if warnings: frappe.msgprint(doc.shortage_note, title="Stock warning (Draft)")

    if after_state != "Draft" and not doc.client_location_warehouse:
        frappe.throw("Client Location Warehouse is required.")

    CLIENT_WH = doc.client_location_warehouse or ""

    dispatch_items = [{"item_code": r.item, "qty": float(r.dispatched_qty or 0)}
                      for r in (doc.case_items or []) if float(r.dispatched_qty or 0) > 0]
    returned_items = [{"item_code": r.item, "qty": float(r.returned_qty or 0)}
                      for r in (doc.case_items or []) if float(r.returned_qty or 0) > 0]

    # Create delivery task when delivery_person first set (idempotent)
    if (doc.delivery_person and not doc.delivery_task
            and after_state not in ("Draft", "Preparing", "Dispatch Picking")):
        doc.delivery_task = make_task(
            "Deliver - " + doc.name, "Delivery", doc.delivery_person)

    # Create return tasks when person set in Return Pickup Scheduled (idempotent)
    if doc.return_pickup_delivery_person and after_state == "Return Pickup Scheduled":
        if not doc.return_pickup_task:
            doc.return_pickup_task = make_task(
                "Pickup Returns - " + doc.name, "Pickup Returns", doc.return_pickup_delivery_person)
        if not doc.return_dropoff_task:
            doc.return_dropoff_task = make_task(
                "Return drop-off - " + doc.name, "Return drop-off at warehouse",
                doc.return_pickup_delivery_person)

    if not state_changed: return

    # Preparing -> Dispatch Picking: stock gate + draft dispatch SE
    if before_state == "Preparing" and after_state == "Dispatch Picking":
        shortages = []
        for it in dispatch_items:
            avail = get_bin_qty(it["item_code"], MAIN_WH)
            if avail < it["qty"]:
                shortages.append(it["item_code"] + ": need " + str(it["qty"]) + " have " + str(avail))
        if shortages:
            frappe.throw("Insufficient stock in " + MAIN_WH + ":\n" + "\n".join(shortages))
        if not doc.dispatch_stock_entry:
            doc.dispatch_stock_entry = make_transfer(dispatch_items, MAIN_WH, DELIVERY_WH, now_datetime()).name

    # Dispatch Picking -> Dispatched: dispatch SE must be submitted
    if before_state == "Dispatch Picking" and after_state == "Dispatched":
        if not doc.dispatch_stock_entry:
            frappe.throw("Dispatch Stock Entry is missing.")
        if frappe.db.get_value("Stock Entry", doc.dispatch_stock_entry, "docstatus") != 1:
            frappe.throw("Dispatch Stock Entry must be submitted before marking as Dispatched.")

    # Dispatched -> Delivered: delivery task gate + auto-submit delivery SE
    if before_state == "Dispatched" and after_state == "Delivered":
        if not doc.delivery_task:
            frappe.throw("Delivery Task is required. Set Delivery Person and save first.")
        if frappe.db.get_value("Task", doc.delivery_task, "status") != "Completed":
            frappe.throw("Delivery Task must be Completed (with Warehouse Pickup Photo) before marking Delivered.")
        if not doc.delivery_stock_entry:
            d_se = frappe.get_doc("Stock Entry", doc.dispatch_stock_entry)
            items_to_deliver = [{"item_code": it.item_code, "qty": float(it.qty or 0),
                                  "batch_no": getattr(it, "batch_no", None),
                                  "serial_no": getattr(it, "serial_no", None)} for it in d_se.items]
            se = make_transfer(items_to_deliver, DELIVERY_WH, CLIENT_WH, now_datetime())
            se.submit()
            doc.delivery_stock_entry = se.name

    # Return Pickup Scheduled -> Return Pickup In Transit: pickup task gate
    if before_state == "Return Pickup Scheduled" and after_state == "Return Pickup In Transit":
        if not doc.return_pickup_task:
            frappe.throw("Pickup Returns Task is required.")
        if frappe.db.get_value("Task", doc.return_pickup_task, "status") != "Completed":
            frappe.throw("Pickup Returns Task must be Completed before moving to In Transit.")

    # Return Pickup In Transit -> Returns Verification: dropoff task gate + draft return SEs
    if before_state == "Return Pickup In Transit" and after_state == "Returns Verification":
        if not doc.return_dropoff_task:
            frappe.throw("Return drop-off at warehouse Task is required.")
        if frappe.db.get_value("Task", doc.return_dropoff_task, "status") != "Completed":
            frappe.throw("Return drop-off Task must be Completed (with Warehouse Drop-off Photo) first.")
        pickup_dt = (frappe.db.get_value("Task", doc.return_pickup_task, "completed_at")
                     if doc.return_pickup_task else None) or now_datetime()
        if returned_items:
            if not doc.return_pickup_stock_entry:
                doc.return_pickup_stock_entry = make_transfer(
                    returned_items, CLIENT_WH, RETURN_TRANSIT_WH, pickup_dt).name
            if not doc.return_receive_stock_entry:
                doc.return_receive_stock_entry = make_transfer(
                    returned_items, RETURN_TRANSIT_WH, RETURNS_WH, now_datetime()).name

    # Returns Verification -> Returns Received: return SEs must be submitted
    if before_state == "Returns Verification" and after_state == "Returns Received":
        for fn in ("return_pickup_stock_entry", "return_receive_stock_entry"):
            se_name = getattr(doc, fn, None)
            if se_name and frappe.db.get_value("Stock Entry", se_name, "docstatus") != 1:
                frappe.throw("Return Stock Entry " + str(se_name) + " must be submitted before proceeding.")

    # Returns Received -> Usage Derived: compute used_qty + auto-submit Consumption SE
    if before_state == "Returns Received" and after_state == "Usage Derived":
        for row in (doc.case_items or []):
            row.used_qty = (float(row.dispatched_qty or 0) - float(row.returned_qty or 0)
                            - float(row.lost_damaged_qty or 0))
            if row.used_qty < 0:
                frappe.throw("Used Qty negative for " + row.item + ". Check dispatched/returned/lost.")
        if not doc.consumption_stock_entry:
            if not doc.delivery_stock_entry or not doc.return_pickup_stock_entry:
                frappe.throw("Delivery and Return Pickup SEs required before consumption posting.")
            d_se = frappe.get_doc("Stock Entry", doc.delivery_stock_entry)
            r_se = frappe.get_doc("Stock Entry", doc.return_pickup_stock_entry)
            d_by_key = {}; d_serials = {}
            for it in d_se.items:
                key = (it.item_code, getattr(it, "batch_no", None))
                d_by_key[key] = d_by_key.get(key, 0) + float(it.qty or 0)
                sers = split_serials(getattr(it, "serial_no", None))
                if sers: d_serials.setdefault(it.item_code, set()).update(sers)
            r_by_key = {}; r_serials = {}
            for it in r_se.items:
                key = (it.item_code, getattr(it, "batch_no", None))
                r_by_key[key] = r_by_key.get(key, 0) + float(it.qty or 0)
                sers = split_serials(getattr(it, "serial_no", None))
                if sers: r_serials.setdefault(it.item_code, set()).update(sers)
            cons = frappe.new_doc("Stock Entry")
            cons.stock_entry_type = "Material Issue"
            _now = now_datetime()
            cons.set_posting_time = 1
            if hasattr(_now, "date"):
                cons.posting_date = _now.date()
                cons.posting_time = _now.time()
            exc_set = set(r.serial_no for r in (doc.get("tool_serial_exceptions") or [])
                          if getattr(r, "serial_no", None))
            for row in (doc.case_items or []):
                issue_qty = float(row.dispatched_qty or 0) - float(row.returned_qty or 0)
                if issue_qty <= 0: continue
                missing_s = sorted(d_serials.get(row.item, set()) - r_serials.get(row.item, set()))
                if missing_s:
                    not_recorded = [s for s in missing_s if s not in exc_set]
                    if not_recorded:
                        frappe.throw("Missing serials must be in Tool Serial Exceptions before deriving usage:\n"
                                     + "\n".join(not_recorded))
                    cons.append("items", {"item_code": row.item, "qty": len(missing_s),
                                          "s_warehouse": CLIENT_WH, "serial_no": "\n".join(missing_s)})
                    continue
                batch_keys = [k for k in d_by_key if k[0] == row.item and k[1]]
                if batch_keys:
                    rem = issue_qty
                    for key in batch_keys:
                        used_by_batch = d_by_key[key] - r_by_key.get(key, 0)
                        if used_by_batch <= 0: continue
                        take = min(rem, used_by_batch)
                        cons.append("items", {"item_code": row.item, "qty": take,
                                               "s_warehouse": CLIENT_WH, "batch_no": key[1]})
                        rem -= take
                        if rem <= 0: break
                    if rem > 0:
                        frappe.throw("Cannot allocate used qty by batch for item " + row.item)
                else:
                    cons.append("items", {"item_code": row.item, "qty": issue_qty, "s_warehouse": CLIENT_WH})
            if hasattr(cons, "surgery_case"): cons.surgery_case = doc.name
            if hasattr(cons, "dispatch_group_id") and doc.dispatch_group_id:
                cons.dispatch_group_id = doc.dispatch_group_id
            cons.insert(ignore_permissions=True)
            cons.submit()
            doc.consumption_stock_entry = cons.name

    # Usage Derived -> Invoiced: create draft Sales Invoice for used qty
    if before_state == "Usage Derived" and after_state == "Invoiced":
        if not doc.sales_invoice:
            inv = frappe.new_doc("Sales Invoice")
            inv.customer = doc.client
            inv.update_stock = 0
            if hasattr(inv, "surgery_case"):    inv.surgery_case    = doc.name
            if hasattr(inv, "hospital"):        inv.hospital        = doc.hospital
            if hasattr(inv, "hospital_branch"): inv.hospital_branch = doc.hospital_branch
            if hasattr(inv, "doctor_name"):     inv.doctor_name     = doc.doctor_name
            for row in (doc.case_items or []):
                if float(row.used_qty or 0) > 0:
                    inv.append("items", {"item_code": row.item, "qty": row.used_qty})
            inv.insert(ignore_permissions=True)
            doc.sales_invoice = inv.name

    # Invoiced -> Closed: serial accountability gate
    if before_state == "Invoiced" and after_state == "Closed":
        if doc.delivery_stock_entry and doc.return_pickup_stock_entry:
            d_se2 = frappe.get_doc("Stock Entry", doc.delivery_stock_entry)
            r_se2 = frappe.get_doc("Stock Entry", doc.return_pickup_stock_entry)
            exc_set2 = set(r.serial_no for r in (doc.get("tool_serial_exceptions") or [])
                           if getattr(r, "serial_no", None))
            d_sers2 = {}
            for it in d_se2.items:
                sers = split_serials(getattr(it, "serial_no", None))
                if sers: d_sers2.setdefault(it.item_code, set()).update(sers)
            r_sers2 = {}
            for it in r_se2.items:
                sers = split_serials(getattr(it, "serial_no", None))
                if sers: r_sers2.setdefault(it.item_code, set()).update(sers)
            missing_all = [item_code + ": " + s
                           for item_code, sers in d_sers2.items()
                           for s in sorted(sers - r_sers2.get(item_code, set()))
                           if s not in exc_set2]
            if missing_all:
                frappe.throw("Cannot close: serial-tracked tools missing and not in Tool Serial Exceptions:\n"
                             + "\n".join(missing_all))

run_script(doc)