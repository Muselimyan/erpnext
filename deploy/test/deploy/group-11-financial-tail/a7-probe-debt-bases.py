# ==============================================================
# A7 PROBE (read-only): establish the two facts the single-definition change
# depends on, and measure how far apart the five current bases actually are.
#
#   1. How many Companies exist? One of the two GL-based consumers filters by
#      company and the other does not. With a single company that divergence is
#      theoretical; with two it is live.
#
#   2. When an invoice consumes an advance through its `advances` table, does
#      ERPNext also write a Payment Entry Reference row? RPT - Receivables -
#      Unallocated Advances recomputes unallocated as
#      paid_amount - SUM(Payment Entry Reference.allocated_amount) instead of
#      reading PE.unallocated_amount. If the reference row is NOT written, that
#      report disagrees with the other four by design.
#
#   3. Per customer, all five bases side by side, so the operational effect of
#      switching definition is visible BEFORE any code changes.
#
# Read-only. No writes.
# ==============================================================
import frappe
def a7_probe():
    OUT = []
    def line(k, v):
        OUT.append("A7PROBE | {0:<46} | {1}".format(k, v))
    # ── 1. companies ──────────────────────────────────────────────────
    comps = frappe.get_all("Company", fields=["name"], limit_page_length=0)
    line("Company records", "{0} -> {1}".format(len(comps), ", ".join([c.name for c in comps])[:60]))
    line("company filter divergence is", "THEORETICAL" if len(comps) < 2 else "LIVE - bases will disagree")
    # ── 2. does an advance allocation write a PE Reference row? ────────
    # Look at real submitted Receive PEs that have been partly/fully consumed
    # (paid_amount > unallocated_amount) and ask whether references exist.
    pes = frappe.get_all("Payment Entry", filters={"docstatus": 1, "payment_type": "Receive", "party_type": "Customer"}, fields=["name", "paid_amount", "unallocated_amount"], limit_page_length=0)
    consumed = [p for p in pes if float(p.paid_amount or 0) - float(p.unallocated_amount or 0) > 0.01]
    line("submitted customer Receive PEs", len(pes))
    line("...partly or fully consumed", len(consumed))
    with_ref = 0
    without_ref = 0
    for p in consumed:
        n = frappe.db.count("Payment Entry Reference", {"parent": p.name, "reference_doctype": "Sales Invoice"})
        if n > 0:
            with_ref = with_ref + 1
        else:
            without_ref = without_ref + 1
    line("consumed PEs WITH a reference row", with_ref)
    line("consumed PEs WITHOUT a reference row", without_ref)
    if consumed:
        verdict = "AGREES with the field" if without_ref == 0 else "DISAGREES on {0} PE(s)".format(without_ref)
    else:
        verdict = "NO DATA - no consumed advances on test"
    line("VERDICT Unallocated Advances report", verdict)
    # ── 3. the five bases, per customer, side by side ──────────────────
    # basis A  gross      = SUM(SI.outstanding)                    <- episodes
    # basis B  net-all    = A - SUM(all unallocated credit)        <- panel, RPT threshold
    # basis C  net-untag  = A - SUM(UNTAGGED unallocated credit)   <- PROPOSED
    # basis D  gl-company = SUM(debit-credit) filtered by company  <- Debt Alert
    # basis E  gl-nocomp  = SUM(debit-credit) unfiltered           <- RPT Risk
    comp = comps[0].name if comps else ""
    custs = frappe.get_all("Customer", filters={"disabled": 0}, fields=["name", "debt_threshold_amd"], limit_page_length=0)
    rows = []
    for c in custs:
        a = 0.0
        for si in frappe.get_all("Sales Invoice", filters={"customer": c.name, "docstatus": 1, "outstanding_amount": [">", 0]}, fields=["outstanding_amount"], limit_page_length=0):
            a = a + float(si.outstanding_amount or 0)
        allcr = 0.0
        untag = 0.0
        for pe in frappe.get_all("Payment Entry", filters={"party": c.name, "party_type": "Customer", "docstatus": 1, "payment_type": "Receive", "unallocated_amount": [">", 0]}, fields=["unallocated_amount", "dispatch_case"], limit_page_length=0):
            u = float(pe.unallocated_amount or 0)
            allcr = allcr + u
            if not (pe.dispatch_case or ""):
                untag = untag + u
        d = frappe.db.sql("select sum(debit-credit) from `tabGL Entry` where is_cancelled=0 and party_type='Customer' and party=%s and company=%s", (c.name, comp))
        e = frappe.db.sql("select sum(debit-credit) from `tabGL Entry` where is_cancelled=0 and party_type='Customer' and party=%s", (c.name,))
        dv = float((d[0][0] if d and d[0][0] is not None else 0))
        ev = float((e[0][0] if e and e[0][0] is not None else 0))
        if a > 0 or allcr > 0 or abs(dv) > 0.01 or abs(ev) > 0.01:
            rows.append((c.name, float(c.debt_threshold_amd or 0), a, a - allcr, a - untag, dv, ev))
    line("customers with any financial position", len(rows))
    # how many customers would CHANGE threshold verdict under the proposal?
    moved = []
    for n, th, a, ball, cuntag, dv, ev in rows:
        if th <= 0:
            continue
        was = ball > th
        now = cuntag > th
        if was != now:
            moved.append((n, th, ball, cuntag, "NOW over" if now else "NOW under"))
    line("customers whose threshold verdict CHANGES", len(moved))
    for n, th, ball, cuntag, what in moved[:8]:
        line("  {0}".format(n[:30]), "thr={0:.0f} net-all={1:.0f} net-untag={2:.0f} {3}".format(th, ball, cuntag, what))
    # disagreements between the two GL consumers
    gl_diff = [r for r in rows if abs(r[5] - r[6]) > 0.01]
    line("customers where GL-with-company != GL-without", len(gl_diff))
    # gross vs net spread
    spread = [r for r in rows if abs(r[2] - r[4]) > 0.01]
    line("customers where gross != net-untagged", len(spread))
    print("A7PROBE_START")
    for o in OUT:
        print(o)
    print("A7PROBE | ---- per-customer sample (first 10 with a position) ----")
    print("A7PROBE | {0:<30} {1:>10} {2:>10} {3:>10} {4:>10} {5:>10} {6:>10}".format("customer", "threshold", "gross", "net-all", "net-untag", "gl-comp", "gl-nocomp"))
    for n, th, a, ball, cuntag, dv, ev in rows[:10]:
        print("A7PROBE | {0:<30} {1:>10.0f} {2:>10.0f} {3:>10.0f} {4:>10.0f} {5:>10.0f} {6:>10.0f}".format(n[:30], th, a, ball, cuntag, dv, ev))
    print("A7PROBE_END")
a7_probe()
