# Name: Stock Entry-before-submit-dispatch-gate
# Type: DocType Event
# DocType: Stock Entry
# Event: Before Submit
# Disabled: 1
# ---

IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif")

def is_image_url(url):
    return (url or "").lower().split("?")[0].endswith(IMAGE_EXTENSIONS)

def task_has_image(task_name):
    """Check if a Task has at least one attached image File record."""
    files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": task_name}, fields=["file_url"])
    images = [f.file_url for f in files if is_image_url(f.file_url)]
    print(f"[Photo] task_has_image({task_name}): total_files={len(files)}, images={len(images)}, urls={images[:5]}")
    return len(images) > 0

if doc.stock_entry_type == "Material Transfer":
    MAIN_WH = "Main - Inmed"
    DELIVERY_IN_TRANSIT_WH = "Delivery In-Transit - Inmed"

    to_wh = doc.get("to_warehouse")
    from_wh = doc.get("from_warehouse")
    row_targets = [(r.get("s_warehouse"), r.get("t_warehouse")) for r in (doc.get("items") or [])]

    is_dispatch_staging = (
        (from_wh == MAIN_WH and to_wh == DELIVERY_IN_TRANSIT_WH)
        or any((s == MAIN_WH and t == DELIVERY_IN_TRANSIT_WH) for (s, t) in row_targets)
    )

    if is_dispatch_staging:
        if not doc.sales_order:
            frappe.throw("Dispatch staging Stock Entry must be linked to a Sales Order.")

        so = frappe.get_doc("Sales Order", doc.sales_order)

        if so.discount_approval_status in ("Pending", "Rejected"):
            frappe.throw(
                "Discount approval is required before dispatch staging. "
                "Complete the Discount Approval task (Approved) or remove the discount."
            )

        tasks = frappe.get_all(
            "Task",
            filters={
                "task_kind": "Delivery",
                "sales_order": so.name,
                "status": ["!=", "Cancelled"],
            },
            fields=["name"],
        )

        if not tasks:
            frappe.throw("Dispatch staging requires an existing Delivery Task linked to this Sales Order.")

        if not any(task_has_image(t.name) for t in tasks):
            frappe.throw("At least one photo must be attached to the Delivery Task before dispatch staging.")

        if so.is_prepaid:
            if not so.prepayment_payment_entry:
                frappe.throw("Prepaid order requires Prepayment Payment Entry before dispatch staging.")

            pe = frappe.get_doc("Payment Entry", so.prepayment_payment_entry)
            if pe.docstatus != 1:
                frappe.throw("Prepayment Payment Entry must be submitted before dispatch staging.")

            required = float(so.prepayment_required_amount_amd or 0)
            if required > 0:
                paid = float(pe.paid_amount or 0)
                if paid < required:
                    frappe.throw("Prepayment amount is below required amount for this order.")