# Name: Payment Entry-after-submit-debt-closure-check
# Type: DocType Event
# DocType: Payment Entry
# Event: After Submit
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# When a customer's account reaches zero, close their cases and raise one Debt
# Closure Approval.
#
# WHY THE TRIGGER MOVED HERE
# --------------------------
# Debt Closure Approval used to be raised when a Debt Collection TASK was
# completed. That conflated two unrelated facts: that a person finished a piece
# of chasing work, and that the customer's account was settled. A collector
# could close an attempt with money still owed -- two episodes on test were
# closed carrying real outstanding balances -- and an approval was raised
# anyway, asserting a closure that had not happened.
#
# Settlement is a ledger event, so the ledger raises it. Completing a chase
# attempt now means only what it says.
#
# THIS ALSO FIXES THE UNREACHABLE TERMINAL STATE (Group 11 G2)
# ------------------------------------------------------------
# `Closed` was previously reachable only at Invoice Preparation completion, when
# grand_total minus a stored prepaid figure came out at or below zero -- i.e.
# only for a case fully prepaid BEFORE its invoice task completed. For the
# normal pay-after-invoice flow, the case landed in `Payment Pending` and no
# code path ever moved it again. Zero of 270 cases on test had ever been
# Closed. Payment now closes them.
#
# PROFIT IS COMPUTED HERE, NOT ON APPROVAL
# ----------------------------------------
# The old script recomputed profit every time an approval was completed, by
# summing EVERY submitted invoice for the customer. Two approvals for one
# customer therefore counted the same invoices twice (G10). Profit is now
# computed once, at creation, over exactly the cases this closure covers -- and
# a case transitions to Closed only once, which makes that set naturally
# idempotent. Approval then means approving a figure, not regenerating it.
#
# The BASIS of that figure is still Item Price / Standard Buying, which Doc 17
# supersedes with the landed-cost valuation rate. Replacing it is out of scope
# here; this only removes the double counting.
#
# Log tag: [Settled]
# ═══════════════════════════════════════════════════════════════════════

DEBT_CLOSURE_APPROVAL_KIND = "Debt Closure Approval"

if doc.payment_type != "Receive":
    pass
elif doc.party_type != "Customer" or not doc.party:
    pass
else:
    customer = doc.party

    # Settled means no unpaid submitted invoice remains. Unallocated credit is
    # not debt, so it deliberately does not hold closure open.
    still_unpaid = frappe.get_all(
        "Sales Invoice",
        filters={"customer": customer, "docstatus": 1, "outstanding_amount": [">", 0]},
        fields=["name"],
        limit_page_length=1,
    )

    if still_unpaid:
        print(f"[Settled] {frappe.utils.now()} pe={doc.name} customer={customer} still has unpaid invoices, nothing to close")
    else:
        # ── Close the cases this settlement covers ─────────────────────
        # Only cases that are actually waiting on money, and only where every
        # invoice raised for them is settled.
        open_cases = frappe.get_all(
            "Dispatch Case",
            filters={"customer": customer, "status": ["in", ["Payment Pending", "Invoice Pending"]]},
            fields=["name", "status"],
            limit_page_length=0,
        )

        closed_cases = []
        for c in (open_cases or []):
            case_invoices = frappe.get_all(
                "Sales Invoice",
                filters={"dispatch_case": c.name, "docstatus": 1},
                fields=["name", "outstanding_amount"],
                limit_page_length=0,
            )
            if not case_invoices:
                continue
            case_settled = True
            for ci in case_invoices:
                if float(ci.outstanding_amount or 0) > 0:
                    case_settled = False
            if case_settled:
                frappe.db.set_value("Dispatch Case", c.name, "status", "Closed")
                closed_cases.append(c.name)

        print(f"[Settled] {frappe.utils.now()} pe={doc.name} customer={customer} closed_cases={closed_cases}")

        # ── One open approval per customer ─────────────────────────────
        existing_approval = frappe.get_all(
            "Task",
            filters={"task_kind": DEBT_CLOSURE_APPROVAL_KIND, "customer": customer,
                     "status": ["not in", ["Completed", "Cancelled"]]},
            fields=["name"],
            limit_page_length=1,
        )

        # A SETTLEMENT ALWAYS GETS DIRECTOR REVIEW, even when it closed no case.
        #
        # This used to raise the approval only when the payment itself moved at
        # least one case to Closed. Two ordinary situations produced no approval
        # and no notification -- only a log line nobody reads:
        #   - the account settles but every case was already Closed
        #   - a case sits in a status outside Payment Pending / Invoice Pending
        #     (Delivered, say), so it is not a closure candidate at all
        # In both the customer's balance reached zero with no Director ever
        # seeing it, and the approval is where profit is recorded, so nothing
        # recorded the profit either.
        #
        # The dedupe above still applies: one open approval per customer.
        if existing_approval:
            print(f"[Settled] {frappe.utils.now()} approval {existing_approval[0].name} already open for {customer}")
        else:
            # ── Profit over exactly the cases closed here ──────────────
            total_profit = 0
            missing_prices = []
            covered_invoices = []
            for case_name in closed_cases:
                for ci in (frappe.get_all("Sales Invoice",
                                          filters={"dispatch_case": case_name, "docstatus": 1},
                                          fields=["name"], limit_page_length=0) or []):
                    covered_invoices.append(ci.name)
                    inv = frappe.get_doc("Sales Invoice", ci.name)
                    for item in inv.items:
                        selling = float(item.rate or 0) * float(item.qty or 0)
                        buying_rate = frappe.db.get_value("Item Price", {"item_code": item.item_code, "price_list": "Standard Buying"}, "price_list_rate") or 0
                        if not buying_rate:
                            missing_prices.append(item.item_code)
                        total_profit += selling - (float(buying_rate) * float(item.qty or 0))

            payments = frappe.get_all(
                "Payment Entry",
                filters={"party_type": "Customer", "party": customer, "docstatus": 1, "payment_type": "Receive"},
                fields=["name", "posting_date", "paid_amount", "mode_of_payment", "reference_no"],
                order_by="posting_date asc",
                limit_page_length=0,
            )

            desc = ["Customer " + str(customer) + " has settled their account.", ""]
            if closed_cases:
                desc.append("Cases closed by this settlement: " + ", ".join(closed_cases))
                desc.append("Invoices covered: " + (", ".join(covered_invoices) if covered_invoices else "none"))
                desc.append("Profit on the covered cases: " + str(total_profit) + " AMD")
            else:
                # Do NOT print "Profit: 0" here. A zero reads as a computed
                # figure, and the truth is that there was nothing to compute it
                # over. Say so.
                desc.append("This payment closed NO Dispatch Case.")
                desc.append("")
                desc.append("The account balance is now zero, but either every case was")
                desc.append("already Closed, or the remaining cases are in a status that is not")
                desc.append("a closure candidate (only Payment Pending and Invoice Pending are).")
                desc.append("")
                desc.append("No profit figure is computed, because no case was closed by this")
                desc.append("settlement. Check the customer's open cases before approving.")
            if missing_prices:
                unique_missing = []
                for mp in missing_prices:
                    if mp not in unique_missing:
                        unique_missing.append(mp)
                desc.append("")
                desc.append("WARNING: no Standard Buying price for " + ", ".join(sorted(unique_missing)) + ", so the profit figure is incomplete.")
            desc.append("")
            desc.append("Payments received (from submitted Payment Entries):")
            for p in (payments or []):
                desc.append("  " + str(p.posting_date) + " | " + str(p.paid_amount) + " AMD | "
                            + str(p.mode_of_payment or "") + " | Ref: " + str(p.reference_no or "") + " | " + p.name)

            approval_policy = frappe.get_doc("Task Access Policy", DEBT_CLOSURE_APPROVAL_KIND)
            approval_assignee = approval_policy.default_team_user or ""

            t = frappe.get_doc({
                "doctype": "Task",
                "subject": "Debt Closure Approval: " + str(customer),
                "task_kind": DEBT_CLOSURE_APPROVAL_KIND,
                "task_access_policy": DEBT_CLOSURE_APPROVAL_KIND,
                "customer": customer,
                # Both guarded: closed_cases is empty whenever the settlement
                # closed nothing, and indexing it unguarded was an IndexError
                # waiting for that branch to become reachable.
                "dispatch_case": closed_cases[0] if closed_cases else "",
                "sales_invoice": covered_invoices[0] if covered_invoices else "",
                "payment_entry": doc.name,
                # Not set when nothing was closed. Be aware this reads back as
                # 0 either way -- it is a Currency field, so Frappe stores 0 for
                # None and the stored number cannot express "not computed". The
                # DESCRIPTION is what distinguishes the two cases, which is why
                # it states it in words rather than leaving the reader to
                # interpret a zero.
                "custom_case_profit": total_profit if closed_cases else None,
                "description": "\n".join(desc),
            })
            if approval_assignee:
                t.custom_assigned_to = approval_assignee
            t.flags.ignore_permissions = True
            t.insert()

            if approval_assignee:
                frappe.db.set_value("Task", t.name, "_assign", json.dumps([approval_assignee]), update_modified=False)
                if not frappe.db.exists("ToDo", {"reference_type": "Task", "reference_name": t.name, "allocated_to": approval_assignee, "status": "Open"}):
                    todo = frappe.new_doc("ToDo")
                    todo.status = "Open"
                    todo.allocated_to = approval_assignee
                    todo.reference_type = "Task"
                    todo.reference_name = t.name
                    todo.description = t.subject
                    todo.assigned_by = frappe.session.user
                    todo.insert(ignore_permissions=True)

            print(f"[Settled] {frappe.utils.now()} raised approval {t.name} for {customer} cases={closed_cases} profit={total_profit}")
