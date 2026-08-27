# Name: dispatch_case_packing_scan
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

case_name = frappe.form_dict.get("case_name")
barcode = (frappe.form_dict.get("barcode") or "").strip()
qty = float(frappe.form_dict.get("qty") or 1)
MAIN_WH = "Main - Inmed"

if not case_name:
    frappe.throw("Dispatch Case is required.")
if not barcode:
    frappe.throw("Barcode is required.")
if qty <= 0:
    frappe.throw("Scan quantity must be greater than zero.")

case = frappe.get_doc("Dispatch Case", case_name)

item_code = None
batch_no = None
expiry_date = None
item_code_override = frappe.form_dict.get("item_code_override")
raw = barcode.replace("]C1", "").replace("]d2", "")

if item_code_override and frappe.db.exists("Item", item_code_override):
    item_code = item_code_override

if not item_code and frappe.db.exists("Item", barcode):
    item_code = barcode

if not item_code:
    ib = frappe.db.get_value("Item Barcode", {"barcode": barcode}, "parent")
    if ib:
        item_code = ib

if "17" in raw and "10" in raw:
    try:
        p17 = raw.index("17")
        exp6 = raw[p17 + 2:p17 + 8]
        if len(exp6) == 6 and exp6.isdigit():
            yy = int(exp6[0:2])
            mm = int(exp6[2:4])
            dd = int(exp6[4:6])
            yyyy = 2000 + yy
            expiry_date = f"{yyyy:04d}-{mm:02d}-{dd:02d}"
        p10 = raw.index("10")
        lot = raw[p10 + 2:]
        for marker in ["17", "11", "21"]:
            cut = lot.find(marker)
            if cut > 0:
                lot = lot[:cut]
        batch_no = lot.strip("() ")[:80]
    except Exception:
        pass

if batch_no and not item_code:
    b_item = frappe.db.get_value("Batch", batch_no, "item")
    if b_item:
        item_code = b_item

if not item_code:
    frappe.throw("Could not identify Item from barcode. Scan the product REF/item barcode first, or use a barcode linked to an Item.")

matching_rows = []
for row in (case.case_items or []):
    required = float(row.dispatched_qty or 0)
    scanned = float(row.get("custom_scanned_qty") or 0)
    if row.item_code == item_code and scanned < required:
        matching_rows.append(row)

if not matching_rows:
    frappe.throw("This item is not required for this Dispatch Case, or it is already fully scanned: " + item_code)

row = matching_rows[0]
required = float(row.dispatched_qty or 0)
scanned = float(row.get("custom_scanned_qty") or 0) + qty
remaining = required - scanned

warning = ""
if batch_no:
    row.batch_no = batch_no
    batch_expiry = frappe.db.get_value("Batch", batch_no, "expiry_date")
    if batch_expiry and not expiry_date:
        expiry_date = str(batch_expiry)

if expiry_date:
    try:
        earlier_batches = frappe.get_all(
            "Batch",
            filters={"item": item_code, "disabled": 0, "expiry_date": ["<", expiry_date]},
            fields=["name", "expiry_date"],
            order_by="expiry_date asc",
            limit_page_length=10,
        )
        available_earlier = []
        for b in earlier_batches:
            available_qty = 0
            try:
                res = frappe.db.sql(
                    """
                    select coalesce(sum(actual_qty), 0)
                    from `tabStock Ledger Entry`
                    where item_code=%s and warehouse=%s and batch_no=%s and is_cancelled=0
                    """,
                    (item_code, MAIN_WH, b.name),
                )
                available_qty = float(res[0][0] or 0) if res else 0
            except Exception:
                available_qty = 0
            if available_qty > 0:
                available_earlier.append(f"{b.name} exp {b.expiry_date} qty {available_qty}")
        if available_earlier:
            warning = "FEFO warning only: earlier-expiring stock exists in Main - Inmed. Consider using first: " + "; ".join(available_earlier[:3])
    except Exception as e:
        warning = "FEFO check could not be completed: " + str(e)

row.custom_scanned_qty = scanned
row.custom_remaining_qty = remaining if remaining > 0 else 0
row.custom_last_scanned_barcode = barcode
row.custom_last_scan_at = now_datetime()
row.custom_last_scanned_by = frappe.session.user
row.custom_fefo_warning = warning
if scanned < required:
    row.custom_packing_status = "Partial"
elif scanned == required:
    row.custom_packing_status = "Complete"
else:
    row.custom_packing_status = "Over Scanned"

all_complete = True
for r in (case.case_items or []):
    req = float(r.dispatched_qty or 0)
    scn = float(r.get("custom_scanned_qty") or 0)
    r.custom_remaining_qty = max(req - scn, 0)
    if scn < req:
        all_complete = False

case.custom_packing_scan_barcode = ""
case.custom_packing_scan_qty = 1
case.custom_packing_scan_result = f"Scanned {qty} x {item_code}. Row scanned {scanned}/{required}."
case.custom_packing_last_warning = warning
case.flags.ignore_permissions = True
case.flags.ignore_validate_update_after_submit = True
case.save()

frappe.response["message"] = {
    "ok": True,
    "item_code": item_code,
    "batch_no": batch_no,
    "expiry_date": expiry_date,
    "row_scanned_qty": scanned,
    "row_required_qty": required,
    "all_complete": all_complete,
    "warning": warning,
}