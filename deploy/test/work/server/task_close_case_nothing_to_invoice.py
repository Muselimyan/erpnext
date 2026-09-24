# Name: task_close_case_nothing_to_invoice
# Type: API
# DocType: 
# Event: 
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# Closes a Dispatch Case that has nothing to bill, and completes its Invoice
# Preparation task.
#
# WHY THIS EXISTS
# ---------------
# "The client returned everything unused" is a routine outcome -- a cancelled
# surgery, a kit sent back intact. In that case no item has a used quantity, so
# there is no invoice to raise.
#
# Before this, the flow created the Invoice Preparation task regardless and its
# gate demanded a submitted invoice, so the task became impossible to finish:
# no user, including an Administrator, could clear it, and the case sat open
# forever. (Group 11 G1.)
#
# Closing needs a deliberate human act with a recorded reason, not a silent
# branch in the orchestrator -- which is also why it is not folded into
# task_commit_invoice.
#
# Log tag: [NoInvoice]
# ═══════════════════════════════════════════════════════════════════════

task_name = frappe.form_dict.get("task_name")
reason = (frappe.form_dict.get("reason") or "").strip()

if not task_name:
    frappe.throw("Task is required.")
if not reason:
    frappe.throw("Give a reason for closing this case without an invoice.")

task = frappe.get_doc("Task", task_name)

if (task.get("custom_accepted_by") or "") != frappe.session.user:
    frappe.throw("You must accept this task before closing the case.")
if (task.get("task_kind") or "") != "Invoice preparation / create invoice":
    frappe.throw("Only an Invoice preparation task can close a case as nothing-to-invoice.")
if not task.get("dispatch_case"):
    frappe.throw("This task has no Dispatch Case.")

case = frappe.get_doc("Dispatch Case", task.dispatch_case)

# Refuse if there IS something to bill -- this path must not become a way to
# skip invoicing a real sale.
# "Billable" MUST mean the same thing here as it does in task_commit_invoice.
#
# This tested raw unit_price while commit tested the effective rate, and the two
# disagreed in both directions. A row at unit_price 0 with used_qty > 0 was not
# "billable" here, so the case closed with no invoice -- goods consumed by the
# client, nothing billed, no record of a loss. A row at unit_price 1000 with a
# 100% discount WAS "billable" here so close refused, while commit priced it at
# zero and refused too, leaving a task that could not be finished by either
# route.
#
# Both now use the effective rate. Zero-priced rows can no longer be created or
# submitted (see Dispatch-Case-before-submit), so this is the last line of
# defence rather than the first, but the two definitions must not drift apart
# again. KEEP IN SYNC WITH task_commit_invoice.py.
billable = []
for r in (case.case_items or []):
    r_rate = float(r.unit_price or 0) * (1 - float(r.discount_pct or 0) / 100)
    if float(r.used_qty or 0) > 0 and r_rate > 0:
        billable.append(r.item_code or "Unknown")
if billable:
    frappe.throw("This case has billable items (" + ", ".join(billable)
                 + "), so it cannot be closed as nothing-to-invoice. Create the invoice instead.")

existing = frappe.get_all(
    "Sales Invoice",
    filters={"dispatch_case": case.name, "docstatus": ["!=", 2]},
    fields=["name"],
    limit_page_length=0,
)
if existing:
    frappe.throw("Dispatch Case " + case.name + " already has invoice " + existing[0].name + ".")

note_line = "Closed without an invoice by " + frappe.session.user + " on " + str(frappe.utils.now()) + ": " + reason
existing_notes = case.notes or ""
if existing_notes:
    new_notes = existing_notes + "\n\n" + note_line
else:
    new_notes = note_line

frappe.db.set_value("Dispatch Case", case.name, {"status": "Closed", "notes": new_notes})

task.status = "Completed"
task.description = (task.description or "") + "\n\n" + note_line
task.flags.ignore_permissions = True
task.save()

print(f"[NoInvoice] {frappe.utils.now()} case={case.name} closed by {frappe.session.user} reason={reason[:80]}")

frappe.response["message"] = {"ok": True, "dispatch_case": case.name, "status": "Closed"}
