# ==============================================================
# D11 PROBE (read-only): what a cancel flow would actually have to deal with.
#
# Not a data-cleanup exercise -- test data is disposable. This measures the
# SHAPE of the problem so the design covers every attachment a case can have,
# rather than only the ones that came to mind.
#
#   1. Cases by status, so the cancellable band can be sized.
#   2. Stock sitting in each transit warehouse, and which statuses hold it.
#   3. Open tasks on cases in the cancellable band -- these are what a cancel
#      has to close, and the count says whether bulk cancellation needs to be
#      efficient or merely correct.
#   4. ADVANCE CREDIT TAGGED TO A CASE. This is the one the existing design doc
#      misses. A Payment Received task can raise an advance tagged to a case at
#      any point, including while it is still Draft. A7 established that tagged
#      credit does NOT offset other debt, and task_commit_invoice will not spend
#      it on another case -- so cancelling a case with tagged credit strands the
#      client's money in a dead case. Nothing would ever release it.
#   5. Invoices on cases in the cancellable band -- should be none, since an
#      invoice is only possible from Delivered onwards. If any exist the
#      assumption is wrong and the design needs the credit-note path after all.
#   6. Sales Invoices whose case is missing/mismatched, for the same reason.
#
# Read-only.
# ==============================================================
import frappe
def d11_probe():
    OUT = []
    CANCELLABLE = ["Draft", "Awaiting Approval", "Confirmed", "Packed", "In Transit"]
    TRANSIT = ["Delivery In-Transit - Inmed", "Return Pickup In-Transit - Inmed", "Returns - Inmed", "Lost & Damaged - Inmed"]
    def line(k, v):
        OUT.append("D11PROBE | {0:<48} | {1}".format(k, v))
    # ── 1. cases by status ────────────────────────────────────────────
    rows = frappe.db.sql("select status, count(*) from `tabDispatch Case` group by status order by count(*) desc")
    line("--- cases by status ---", "")
    total = 0
    for st, n in (rows or []):
        total = total + int(n)
        mark = "  <-- cancellable" if st in CANCELLABLE else ""
        line("  {0}".format(st), "{0}{1}".format(n, mark))
    line("total cases", total)
    inband = frappe.db.count("Dispatch Case", {"status": ["in", CANCELLABLE]})
    line("IN the cancellable band", inband)
    # ── 2. stock in transit warehouses ────────────────────────────────
    line("--- stock held in non-Main warehouses ---", "")
    for wh in TRANSIT:
        agg = frappe.db.sql("select count(distinct item_code), coalesce(sum(actual_qty),0) from `tabBin` where warehouse=%s and actual_qty > 0", (wh,))
        c = int(agg[0][0] or 0) if agg else 0
        q = float(agg[0][1] or 0) if agg else 0
        line("  {0}".format(wh), "{0} item(s), {1} units".format(c, q))
    # ── 3. open tasks on cancellable cases ────────────────────────────
    cases = frappe.get_all("Dispatch Case", filters={"status": ["in", CANCELLABLE]}, fields=["name"], limit_page_length=0)
    names = [c.name for c in cases]
    if names:
        opentasks = frappe.get_all("Task", filters={"dispatch_case": ["in", names], "status": ["not in", ["Completed", "Cancelled"]]}, fields=["name", "task_kind"], limit_page_length=0)
        line("open tasks on cancellable cases", len(opentasks))
        bykind = {}
        for t in opentasks:
            k = t.task_kind or "(none)"
            bykind[k] = (bykind.get(k) or 0) + 1
        for k in sorted(bykind, key=lambda x: -bykind[x])[:8]:
            line("  {0}".format(k[:44]), bykind[k])
        worst = 0
        for n in names:
            c = len([1 for t in opentasks if t.get("dispatch_case") == n])
            if c > worst:
                worst = c
        line("most open tasks on a single case", worst)
    else:
        line("open tasks on cancellable cases", "no cases in band")
    # ── 4. THE HOLE: advance credit tagged to a case ──────────────────
    line("--- advance credit tagged to a case ---", "")
    tagged = frappe.get_all("Payment Entry", filters={"docstatus": 1, "payment_type": "Receive", "party_type": "Customer", "unallocated_amount": [">", 0], "dispatch_case": ["!=", ""]}, fields=["name", "party", "unallocated_amount", "dispatch_case"], limit_page_length=0)
    line("submitted PEs with UNALLOCATED credit tagged to a case", len(tagged))
    amt = 0.0
    onband = 0
    onband_amt = 0.0
    for pe in tagged:
        u = float(pe.unallocated_amount or 0)
        amt = amt + u
        st = frappe.db.get_value("Dispatch Case", pe.dispatch_case, "status")
        if st in CANCELLABLE:
            onband = onband + 1
            onband_amt = onband_amt + u
    line("  total tagged unallocated credit", "{0:.0f}".format(amt))
    line("  ...on a case in the cancellable band", "{0} PE(s), {1:.0f}".format(onband, onband_amt))
    line("VERDICT stranding risk is", "REAL - cancel must release tagged credit" if tagged else "no data today, but reachable by design")
    # ── 5. invoices in the cancellable band (expected: none) ──────────
    line("--- invoices vs the cancellable band ---", "")
    if names:
        inv = frappe.get_all("Sales Invoice", filters={"dispatch_case": ["in", names], "docstatus": ["!=", 2]}, fields=["name", "docstatus", "dispatch_case"], limit_page_length=0)
        sub = [i for i in inv if int(i.docstatus) == 1]
        dra = [i for i in inv if int(i.docstatus) == 0]
        line("invoices on cancellable cases", "{0} submitted, {1} draft".format(len(sub), len(dra)))
        line("VERDICT can an invoice exist pre-Delivered?", "NO - assumption holds" if not sub else "YES - {0} found, design must handle it".format(len(sub)))
        for i in sub[:5]:
            line("  submitted invoice on in-band case", "{0} on {1}".format(i.name, i.dispatch_case))
    # ── 6. orphan / stale invoice pointers ───────────────────────────
    ptr = frappe.db.sql("select count(*) from `tabDispatch Case` dc where dc.sales_invoice is not null and dc.sales_invoice <> '' and not exists (select 1 from `tabSales Invoice` si where si.name = dc.sales_invoice and si.docstatus = 1)")
    line("cases whose sales_invoice pointer is stale/cancelled", int(ptr[0][0] or 0) if ptr else 0)
    print("D11PROBE_START")
    for o in OUT:
        print(o)
    print("D11PROBE_END")
d11_probe()
