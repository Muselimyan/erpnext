# Name: Dispatch Case-packing-problem-alerts
# Type: DocType Event
# DocType: Dispatch Case
# Event: After Save
# Disabled: 0
# ---

# Only check for packing problems if a pack task exists (packing has started)
if doc.get("pack_task"):
    problem_rows = []
    for row in doc.get("case_items") or []:
        required = float(row.get("dispatched_qty") or 0)
        scanned = float(row.get("custom_scanned_qty") or 0)
        status = row.get("custom_packing_status")
        reason = row.get("custom_problem_reason") or row.get("custom_scan_note") or ""
        if status == "Problem" or (scanned < required and status in ("Partial", "Pending")):
            problem_rows.append({"item_code": row.get("item_code"), "required": required, "scanned": scanned, "reason": reason, "row_name": row.name})
    if not problem_rows:
        if doc.get("custom_packing_problem_status") and doc.get("custom_packing_problem_status") != "No Problem":
            frappe.db.set_value("Dispatch Case", doc.name, {"custom_packing_problem_status": "No Problem", "custom_packing_problem_summary": ""}, update_modified=False)
    else:
        summary_parts = []
        for p in problem_rows[:5]:
            missing = p["required"] - p["scanned"]
            if missing < 0:
                missing = 0
            part = str(p["item_code"] or "Unknown Item") + " missing " + str(missing)
            if p["reason"]:
                part += " (" + str(p["reason"]) + ")"
            summary_parts.append(part)
        summary = "; ".join(summary_parts)
        updates = {"custom_packing_problem_status": "Problem Open", "custom_packing_problem_summary": summary}
        frappe.db.set_value("Dispatch Case", doc.name, updates, update_modified=False)
        if not doc.get("custom_problem_alert_sent"):
            manager_roles = ["Ops - Inventory Manager", "Ops - Directors", "System Manager"]
            users = []
            for role in manager_roles:
                role_users = frappe.get_all("Has Role", filters={"role": role, "parenttype": "User"}, pluck="parent")
                for user in role_users or []:
                    if user not in users and frappe.db.get_value("User", user, "enabled"):
                        users.append(user)
            created = 0
            for user in users:
                exists = frappe.db.exists("ToDo", {"reference_type": "Dispatch Case", "reference_name": doc.name, "allocated_to": user, "status": "Open", "description": ["like", "Packing problem:%"]})
                if exists:
                    continue
                todo = frappe.new_doc("ToDo")
                todo.status = "Open"
                todo.allocated_to = user
                todo.reference_type = "Dispatch Case"
                todo.reference_name = doc.name
                todo.description = "Packing problem: " + summary
                todo.assigned_by = frappe.session.user
                todo.insert(ignore_permissions=True)
                created += 1
            if created:
                frappe.db.set_value("Dispatch Case", doc.name, "custom_problem_alert_sent", 1, update_modified=False)
                for row in doc.get("case_items") or []:
                    if row.get("custom_packing_status") == "Problem":
                        frappe.db.set_value("Dispatch Case Item", row.name, "custom_problem_alert_sent", 1, update_modified=False)